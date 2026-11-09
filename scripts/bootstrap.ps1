<#
.SYNOPSIS
Preview or apply one installed-first setup module; Microsoft bundle is opt-in.
.DESCRIPTION
Default Core preview is nonmutating. Apply explicitly installs only locally
proven missing targets in the selected module. Existing versions are preserved;
incompatible/unknown inventory fails without downloading. No global OS/profile,
font, PowerToys or NVM preset runs by default. LegacyMicrosoftBundle deliberately
opts into the broad signed Microsoft bundle; its upstream behavior is different.
.PARAMETER Module
Independently retryable Core, Python, Java, Go, Extensions, WSL, Ubuntu,
Docker (licensed opt-in), or Modernization (optional Java 11 and 13th extension).
.PARAMETER Apply
Enable confirmed missing-target installations. Omit for a read-only preview.
.PARAMETER ExtensionSourceApproved
Human confirms IT-approved current CLI/default-profile marketplace routing.
Required before any missing extension install; never changes that routing.
.PARAMETER NativeDemo
Select only the five Native language/debugger targets in the Extensions module.
Full Extensions remains the default; cannot combine with legacy or other modules.
.PARAMETER LegacyMicrosoftBundle
Explicit opt-in to the signed broad Microsoft preset, not installed-first modules.
.PARAMETER SkipBase
Legacy only: finish add-on after confirmed successful base and reboot/resume.
.PARAMETER IncludeJavaModernization
Legacy only: also run the optional broad modernization configuration.
.PARAMETER HttpsTimeoutSeconds
HTTPS Preflight only, 1-30 seconds, default 5.
.PARAMETER InstallTimeoutSeconds
Per missing target wait, 300-14400 seconds, default 7200; no automatic retry.
.PARAMETER BaseSetupTimeoutSeconds
Legacy base-only wait, 7200-28800 seconds, default 14400.
.EXAMPLE
.\scripts\bootstrap.ps1 -Module Python
.EXAMPLE
.\scripts\bootstrap.ps1 -Module Python -Apply -Confirm
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Core', 'Python', 'Java', 'Go', 'Extensions', 'WSL', 'Ubuntu', 'Docker', 'Modernization')]
    [string]$Module = 'Core',
    [switch]$Apply, [switch]$ExtensionSourceApproved, [switch]$NativeDemo,
    [switch]$LegacyMicrosoftBundle, [switch]$SkipBase, [switch]$IncludeJavaModernization,
    [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5,
    [ValidateRange(300, 14400)][int]$InstallTimeoutSeconds = 7200,
    [ValidateRange(7200, 28800)][int]$BaseSetupTimeoutSeconds = 14400
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '_setup.psm1')
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($NativeDemo -and ($LegacyMicrosoftBundle -or $Module -ne 'Extensions')) {
            throw 'NativeDemo requires the Extensions module, never the legacy bundle.'
        }
        if ($LegacyMicrosoftBundle) {
            if (-not $Apply) { throw 'Legacy bundle requires explicit Apply; review legacy-bootstrap.ps1 without executing it for preview.' }
            if ($PSBoundParameters.ContainsKey('Module') -or $ExtensionSourceApproved) { throw 'Do not combine modular options with the legacy bundle.' }
            if ($PSCmdlet.ShouldProcess('Legacy Microsoft bundle', 'Run broad signed preset, which may download existing tools and change OS/profile settings')) {
                $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'legacy-bootstrap.ps1'),
                    '-HttpsTimeoutSeconds', [string]$HttpsTimeoutSeconds,
                    '-BaseSetupTimeoutSeconds', [string]$BaseSetupTimeoutSeconds, '-Confirm')
                if ($SkipBase) { $arguments += '-SkipBase' }
                if ($IncludeJavaModernization) { $arguments += '-IncludeJavaModernization' }
                & (Get-Process -Id $PID).Path @arguments | Out-Host
                exit ($LASTEXITCODE)
            }
            exit 0
        }
        if ($SkipBase -or $IncludeJavaModernization) { throw 'SkipBase/IncludeJavaModernization require explicit LegacyMicrosoftBundle. A stopped partial base is not complete.' }
        exit (Invoke-SetupModule -Module $Module -Apply:$Apply -ExtensionSourceApproved:$ExtensionSourceApproved `
            -NativeDemo:$NativeDemo -HttpsTimeoutSeconds $HttpsTimeoutSeconds -InstallTimeoutSeconds $InstallTimeoutSeconds -WhatIf:$WhatIfPreference -Confirm:$true)
    } catch { Write-ShowcaseMessage "[FAIL] Setup: $($_.Exception.Message)"; exit 1 }
}
