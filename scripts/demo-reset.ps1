<#
.SYNOPSIS
Reset only the known demo containers and samples subtree to demo-baseline.
.DESCRIPTION
Requires explicit confirmation. Refuses unrelated working-tree changes,
merge conflicts, or reparse points under samples. New untracked sample files
are listed and require a second confirmation before deletion; ignored files
and nested repositories are not cleaned. Never resets the entire repository.
Only labelled containers with exact known demo names are stopped/removed.
.EXAMPLE
.\scripts\demo-reset.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Get-SampleResetState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string]$Git, [string]$Root)
    $baseline = Invoke-NativeCommand $Git @('rev-parse', '--verify', 'refs/tags/demo-baseline^{commit}') -WorkingDirectory $Root
    Assert-NativeSuccess $baseline 'Locate demo-baseline tag (create it only after final validation)'
    $tree = Invoke-NativeCommand $Git @('ls-tree', '-r', '--name-only', 'refs/tags/demo-baseline', '--', 'samples') -WorkingDirectory $Root
    Assert-NativeSuccess $tree 'Read baseline samples'
    if (-not $tree.StdOut.Trim()) { throw 'demo-baseline has no tracked samples; refusing reset.' }
    $status = Invoke-NativeCommand $Git @('status', '--porcelain=v1', '-z', '--untracked-files=all') -WorkingDirectory $Root
    Assert-NativeSuccess $status 'Read working-tree status'
    $records = @($status.StdOut -split "`0" | Where-Object { $_ })
    $untracked = @()
    for ($index = 0; $index -lt $records.Count; $index++) {
        $record = $records[$index]
        if ($record.Length -lt 4) { throw 'Unrecognised git status record; refusing reset.' }
        $state = $record.Substring(0, 2)
        $paths = @($record.Substring(3))
        if ($state -match '[RC]') {
            $index++
            if ($index -ge $records.Count) { throw 'Incomplete rename status; refusing reset.' }
            $paths += $records[$index]
        }
        if ($state -match 'U|AA|DD') { throw 'Merge conflicts present; resolve them before reset.' }
        foreach ($path in $paths) {
            if (-not $path.StartsWith('samples/', [StringComparison]::Ordinal) -or $path -match '(^|/)\.\.(/|$)') {
                throw "Unrelated work is present ($path). Commit or preserve it before resetting the demo."
            }
        }
        if ($state -eq '??') { $untracked += $paths[0] }
    }
    $samples = Join-Path $Root 'samples'
    Assert-SafeSampleTree $samples
    [pscustomobject]@{ Untracked = $untracked }
}

function Invoke-DemoReset {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidShouldContinueWithoutForce', '',
        Justification = 'Destructive sample and new-file deletion confirmations must not be bypassed by Force. WhatIf never prompts.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([int])]
    param()
    try {
        $root = Get-ShowcaseRoot
        $git = Get-NativeCommandPath git
        if (-not $git) { throw 'Git is missing from PATH.' }
        $state = Get-SampleResetState -Git $git -Root $root
        Write-ShowcaseMessage '[WARN] Reset replaces tracked samples (including their staged changes) with demo-baseline; no other tracked paths are touched.'
        if (-not $PSCmdlet.ShouldProcess('Known demo containers and samples subtree', 'Stop/remove owned containers; restore samples to demo-baseline')) { return 0 }
        if (-not $PSCmdlet.ShouldContinue('Discard sample demo changes and stop the owned demo containers?', 'Confirm demo reset')) {
            Write-ShowcaseMessage '[WARN] Reset cancelled.'
            return 0
        }
        if ($state.Untracked.Count -gt 0) {
            Write-ShowcaseMessage ('[WARN] New untracked sample files to delete: ' + ($state.Untracked -join ', '))
            if (-not $PSCmdlet.ShouldContinue('Delete the listed new untracked sample files? They are not recoverable from demo-baseline.', 'Confirm new file deletion')) {
                Write-ShowcaseMessage '[WARN] Reset cancelled; new files preserved.'
                return 0
            }
        }
        $runtime = $null
        if ((Get-NativeCommandPath wslc) -or (Get-NativeCommandPath docker)) { $runtime = Get-ContainerRuntime }
        if ($null -ne $runtime) {
            Write-ShowcaseMessage "[PASS] Container runtime: $($runtime.Name)."
            $listed = Invoke-NativeCommand $runtime.Path @('ps', '-a', '--filter',
                'label=io.win11-dev-workstation.showcase=true', '--format', '{{.Names}}')
            Assert-NativeSuccess $listed 'List owned demo containers (denied wslc does not fall back to Docker)'
            $known = @('win11-demo-python-emi-api', 'win11-demo-java-ifsc-service', 'win11-demo-go-fx-rates')
            foreach ($name in @($listed.StdOut -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $known -contains $_ })) {
                if ($PSCmdlet.ShouldProcess($name, 'Stop and remove labelled demo container')) {
                    $stop = Invoke-NativeCommand $runtime.Path @('stop', $name)
                    Assert-NativeSuccess $stop "Stop $name"
                    $remove = Invoke-NativeCommand $runtime.Path @('rm', $name)
                    Assert-NativeSuccess $remove "Remove $name"
                }
            }
        } else { Write-ShowcaseMessage '[WARN] No container runtime installed; container cleanup not needed.' }
        # Recheck immediately before Git mutations so newly appearing unrelated
        # work or unconfirmed new files cannot be swept into a broad reset.
        $current = Get-SampleResetState -Git $git -Root $root
        $previousPaths = @($state.Untracked) -join "`0"
        $currentPaths = @($current.Untracked) -join "`0"
        if ($previousPaths -cne $currentPaths) {
            throw 'Untracked sample files changed during confirmation; re-run and review the new list.'
        }
        if ($PSCmdlet.ShouldProcess((Join-Path $root 'samples'), 'Restore tracked sample files from demo-baseline')) {
            $restore = Invoke-NativeCommand $git @('restore', '--source=refs/tags/demo-baseline', '--staged', '--worktree', '--', 'samples') -WorkingDirectory $root
            Assert-NativeSuccess $restore 'Restore samples'
        }
        if ($state.Untracked.Count -gt 0 -and $PSCmdlet.ShouldProcess('Confirmed untracked sample files', 'Delete only previously confirmed paths')) {
            # Exact paths, not git clean -fd of the whole tree: a concurrently
            # created file must never be deleted without confirmation.
            foreach ($path in $state.Untracked) {
                $clean = Invoke-NativeCommand $git @('--literal-pathspecs', 'clean', '-f', '--', $path) -WorkingDirectory $root
                Assert-NativeSuccess $clean "Clean confirmed sample path $path"
            }
        }
        Write-ShowcaseMessage '[PASS] Demo reset complete; unrelated and ignored files preserved.'
        return 0
    } catch {
        Write-ShowcaseMessage "[FAIL] Demo reset: $($_.Exception.Message)"
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-DemoReset @PSBoundParameters) }
