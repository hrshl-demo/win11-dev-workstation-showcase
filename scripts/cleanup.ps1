<#
.SYNOPSIS
Preview or explicitly remove only fingerprinted outputs owned by this checkout.
.DESCRIPTION
Default is a nonmutating plan. Wait for laptop setup and all local application,
test and restore tasks to finish. Apply requires explicit approval for each
target. Unknown, historical, changed and tracked files are retained. Never
uninstalls tools/extensions/GitHub Copilot, removes source, environments, caches,
images, volumes or cloud resources. Does not invoke demo-reset.
.PARAMETER Apply
Enable per-target confirmed deletion; without this switch no mutation occurs.
.PARAMETER IncludeContainers
Opt in to inspect and remove only recorded immutable IDs with this checkout's
workspace label, exact expected name and recorded runtime.
.EXAMPLE
.\scripts\cleanup.ps1
.EXAMPLE
.\scripts\cleanup.ps1 -Apply -Confirm
.EXAMPLE
.\scripts\cleanup.ps1 -Apply -IncludeContainers -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$Apply, [switch]$IncludeContainers)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1')
Import-Module (Join-Path $PSScriptRoot '_ownership.psm1')

function Invoke-ShowcaseCleanup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([int])]
    param([switch]$Apply, [switch]$IncludeContainers)
    $context = $null
    $handles = @()
    try {
        $context = Enter-ShowcaseOperation -ReadOnly
        Write-ShowcaseMessage '[WARN] Stop local app/test/restore tasks first. Shared tools, GHCP, source, environments, caches and cloud resources are never cleanup targets.'
        if ($null -eq $context.Receipt) {
            Write-ShowcaseMessage '[WARN] No ownership receipt: nothing proven owned. Historical resources are retained.'
            return 0
        }
        $files = @()
        foreach ($file in @($context.Receipt.Files)) {
            $path = Assert-OwnedPath $context.Location.Root $file.Path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            # Exclusive handles preflight all eligible files before any deletion.
            # Holding them also prevents concurrent overwrites during confirmation.
            $handle = Open-OwnedOutput $path
            $handles += $handle
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($handle)).Replace('-', '') }
            finally { $sha.Dispose() }
            if ($hash -cne $file.Hash -or [Showcase.OwnedFile]::Identity($handle) -cne $file.Identity) {
                Write-ShowcaseMessage "[WARN] Changed/replaced output retained: $($file.Path)"
                continue
            }
            $files += [pscustomobject]@{ Path = $path; RelativePath = $file.Path; Handle = $handle; Hash = $hash }
        }
        $containers = @()
        if ($IncludeContainers) {
            foreach ($container in @($context.Receipt.Containers)) {
                $runtime = Get-ContainerRuntime -Preferred $container.Runtime
                if ($runtime.Name -cne $container.Runtime) { throw 'Recorded runtime mismatch; no fallback allowed.' }
                if (-not (Test-OwnedContainer $container $context.Receipt.Workspace $runtime)) {
                    Write-ShowcaseMessage "[WARN] Container identity/label mismatch; retained: $($container.Name)"
                    continue
                }
                $containers += [pscustomobject]@{ Receipt = $container; Runtime = $runtime }
            }
        } else { Write-ShowcaseMessage '[WARN] Containers retained; IncludeContainers is explicit opt-in.' }
        foreach ($file in $files) {
            Write-ShowcaseMessage "[PASS] Proven unchanged output: $($file.RelativePath)"
            if ($Apply -and $PSCmdlet.ShouldProcess($file.RelativePath, 'Delete this exact fingerprinted checkout output')) {
                $null = Assert-OwnedPath $context.Location.Root $file.RelativePath
                Remove-OwnedOutput $file.Handle $file.Path -Confirm:$false
            }
        }
        foreach ($entry in $containers) {
            $container = $entry.Receipt
            if ($Apply -and $PSCmdlet.ShouldProcess($container.Id, "Stop/remove exact owned $($container.Name) container")) {
                if (-not (Test-OwnedContainer $container $context.Receipt.Workspace $entry.Runtime)) {
                    throw 'Container identity changed during confirmation; retained.'
                }
                $result = Invoke-NativeCommand $entry.Runtime.Path @('stop', $container.Id) -TimeoutSeconds 60
                Assert-NativeSuccess $result 'Stop exact owned container'
                $result = Invoke-NativeCommand $entry.Runtime.Path @('rm', $container.Id) -TimeoutSeconds 60
                Assert-NativeSuccess $result 'Remove exact owned container (no images/volumes/prune)'
            }
        }
        Write-ShowcaseMessage '[PASS] Cleanup review complete; only explicitly approved proven targets were eligible.'
        return 0
    } catch {
        Write-ShowcaseMessage "[FAIL] Cleanup stopped: $($_.Exception.Message)"
        return 1
    } finally {
        foreach ($handle in $handles) { $handle.Dispose() }
        if ($null -ne $context) { Exit-ShowcaseOperation $context }
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-ShowcaseCleanup @PSBoundParameters) }
