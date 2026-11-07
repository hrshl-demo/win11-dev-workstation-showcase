<#
.SYNOPSIS
Read-only Windows developer workstation readiness checks.
.DESCRIPTION
No elevation or changes are made. FAIL returns exit 1; WARN is advisory.
HTTPS checks use at most three five-second attempts with bounded backoff for
transient transport failures only by default; operators may select 1-30 seconds
per HTTPS attempt. Native output is captured, including
stderr, so -Json emits only one JSON array.
.PARAMETER Json
Emit machine-readable checks instead of human-readable messages.
.PARAMETER Quiet
Suppress PASS and WARN messages (JSON still contains every check).
.PARAMETER HttpsTimeoutSeconds
HTTPS-only per-attempt timeout, default 5; choose 30 for an approved slow network.
.EXAMPLE
.\scripts\preflight.ps1 -Json
#>
[CmdletBinding()]
param([switch]$Json, [switch]$Quiet,
    [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Get-PreflightCheck {
    [CmdletBinding()]
    [OutputType([pscustomobject], [object[]])]
    param([ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5)
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $build = [int]$os.BuildNumber
        $status = if ($build -ge 22621 -and $os.ProductType -eq 1) { 'PASS' } else { 'FAIL' }
        Get-CheckResult 'Windows 11' $status "Build $build. Requires Windows 11 build 22621 or later." -Found ([string]$build)
        Get-CheckResult 'Edition' PASS $os.Caption -Found $os.Caption
    } catch { Get-CheckResult 'Windows 11' FAIL "Cannot read OS information: $($_.Exception.Message)" }
    try {
        $elevated = Test-IsAdministrator
        Get-CheckResult 'Elevation (information)' PASS "Elevated: $elevated. Preflight needs no admin; setup needs local admin and UAC consent."
    } catch { Get-CheckResult 'Elevation (information)' WARN $_.Exception.Message }
    try {
        $processors = @(Get-CimInstance Win32_Processor)
        $system = Get-CimInstance Win32_ComputerSystem
        $available = [bool]$system.HypervisorPresent -or @($processors | Where-Object { $_.VirtualizationFirmwareEnabled }).Count -gt 0
        $status = if ($available) { 'PASS' } else { 'FAIL' }
        Get-CheckResult 'Virtualization' $status "Firmware virtualization or hypervisor present: $available. Enable hardware virtualization in firmware if unavailable."
    } catch { Get-CheckResult 'Virtualization' FAIL "Cannot check virtualization: $($_.Exception.Message)" }
    try {
        $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
        $free = [Math]::Round($drive.FreeSpace / 1GB, 1)
        $status = if ($drive.FreeSpace -ge 15GB) { 'PASS' } else { 'FAIL' }
        Get-CheckResult 'System disk' $status "$free GB free on $env:SystemDrive. Free at least 15 GB."
    } catch { Get-CheckResult 'System disk' FAIL "Cannot check free space: $($_.Exception.Message)" }
    try {
        $installer = Get-AppxPackage Microsoft.DesktopAppInstaller | Select-Object -First 1
        if ($null -eq $installer) {
            Get-CheckResult 'App Installer' FAIL 'Not installed for this user. Install/update App Installer via https://aka.ms/getwinget.'
        } else {
            $status = if ([version]$installer.Version -ge [version]'1.11.11451') { 'PASS' } else { 'WARN' }
            Get-CheckResult 'App Installer' $status "Version $($installer.Version). Update App Installer if older than 1.11.11451." -Found $installer.Version
        }
    } catch { Get-CheckResult 'App Installer' FAIL "Cannot read App Installer: $($_.Exception.Message)" }
    $winget = Get-NativeCommandPath winget
    if ($winget) {
        try {
            $result = Invoke-NativeCommand $winget @('--version') -TimeoutSeconds 15
            $match = [regex]::Match($result.Output, '\d+\.\d+\.\d+(?:\.\d+)?')
            if ($result.ExitCode -ne 0 -or -not $match.Success) { throw 'No usable version returned.' }
            $version = [version]$match.Value
            $status = if ($version -lt [version]'1.6.2631') { 'FAIL' } elseif ($version -lt [version]'1.6.3482') { 'WARN' } else { 'PASS' }
            Get-CheckResult 'WinGet' $status "Version $version. Update App Installer if below 1.6.3482 (configure requires 1.6.2631)." -Found $version.ToString()
        } catch { Get-CheckResult 'WinGet' FAIL "Cannot run winget: $($_.Exception.Message). Check App execution aliases and App Installer registration." }
    } else {
        Get-CheckResult 'WinGet' FAIL 'winget not resolvable. Check App Installer, App execution aliases and the WindowsApps PATH entry.'
    }
    $windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $hasPath = @($env:PATH -split ';' | Where-Object {
        [Environment]::ExpandEnvironmentVariables($_).Trim('"').TrimEnd('\') -ieq $windowsApps.TrimEnd('\')
    }).Count -gt 0
    $status = if ($hasPath) { 'PASS' } else { 'WARN' }
    Get-CheckResult 'WindowsApps PATH' $status "WindowsApps on PATH: $hasPath. Add %LOCALAPPDATA%\Microsoft\WindowsApps to your user PATH if missing."
    $policies = @(Get-WinGetPolicy)
    $policies
    if (@($policies | Where-Object { $_.Status -eq 'FAIL' }).Count -eq 0 -and $winget) {
        try {
            $configure = Invoke-NativeCommand $winget @('configure', '--help') -TimeoutSeconds 30
            $status = if ($configure.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
            Get-CheckResult 'WinGet configure' $status "Exit $($configure.ExitCode). If unrecognised, enable configure after IT approval; see repair-winget.ps1."
        } catch { Get-CheckResult 'WinGet configure' FAIL $_.Exception.Message }
    } else {
        Get-CheckResult 'WinGet configure' FAIL 'Not tested: WinGet is missing or blocked by organisation policy. Contact IT.'
    }
    foreach ($hostName in @('github.com', 'raw.githubusercontent.com', 'codeload.github.com',
        'release-assets.githubusercontent.com', 'www.powershellgallery.com', 'cdn.winget.microsoft.com')) {
        $uri = switch ($hostName) {
            'raw.githubusercontent.com' { 'https://raw.githubusercontent.com/microsoft/WindowsDeveloperConfig/refs/heads/main/README.md' }
            'codeload.github.com' { 'https://codeload.github.com/microsoft/WindowsDeveloperConfig/zip/refs/heads/main' }
            default { "https://$hostName/" }
        }
        $probe = Get-HttpsProbe -Uri $uri -TimeoutSeconds $HttpsTimeoutSeconds
        $status = if ($probe.Reachable) { 'PASS' } else { 'FAIL' }
        $message = "URI: $($probe.Uri); HTTP: $($probe.StatusCode); attempts: $($probe.Attempts)/3; timeout: $HttpsTimeoutSeconds seconds/attempt; type: $($probe.ErrorType); $($probe.Reason)"
        if ($probe.Reachable -and $probe.Attempts -gt 1) { $message = "Recovered after transient transport retries. $message" }
        $check = Get-CheckResult "HTTPS $hostName" $status $message
        $check | Add-Member -NotePropertyName Probe -NotePropertyValue $probe
        $check
    }
    try {
        $netsh = Get-NativeCommandPath netsh
        if (-not $netsh) { throw 'netsh is unavailable.' }
        $proxy = Invoke-NativeCommand $netsh @('winhttp', 'show', 'proxy') -TimeoutSeconds 10
        Assert-NativeSuccess $proxy 'Read WinHTTP proxy'
        Get-CheckResult 'WinHTTP proxy (information)' PASS ($proxy.Output -replace '[\r\n]+', ' ')
    } catch { Get-CheckResult 'WinHTTP proxy (information)' WARN $_.Exception.Message }
    try {
        $policiesText = (Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join '; '
        Get-CheckResult 'Execution policies (information)' PASS "$policiesText. Report only; contact IT for policy changes."
    } catch { Get-CheckResult 'Execution policies (information)' WARN $_.Exception.Message }
    $wsl = Get-NativeCommandPath wsl
    if ($wsl) {
        try {
            $result = Invoke-NativeCommand $wsl @('--version') -TimeoutSeconds 15
            $text = $result.Output -replace "`0", ''
            $match = [regex]::Match($text, '\d+\.\d+\.\d+')
            $status = if ($result.ExitCode -eq 0 -and $match.Success -and [version]$match.Value -ge [version]'2.9.3') { 'PASS' } else { 'WARN' }
            Get-CheckResult 'WSL' $status "Version output: $($text -replace '[\r\n]+', ' '). WSL containers need WSL 2.9.3 or later; the Microsoft base supplies WSL."
        } catch { Get-CheckResult 'WSL' WARN $_.Exception.Message }
    } else { Get-CheckResult 'WSL' WARN 'Not installed. The Microsoft base supplies WSL; one restart may be needed.' }
    $wslc = Get-NativeCommandPath wslc
    $status = if ($wslc) { 'PASS' } else { 'WARN' }
    Get-CheckResult 'WSL containers' $status "wslc present: $([bool]$wslc). WSL 2.9.3 or later is required."
}

function Invoke-Preflight {
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$Json, [switch]$Quiet,
        [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5)
    try { $checks = @(Get-PreflightCheck -HttpsTimeoutSeconds $HttpsTimeoutSeconds) }
    catch { $checks = @(Get-CheckResult 'Preflight' FAIL $_.Exception.Message) }
    Write-CheckReport $checks -Json:$Json -Quiet:$Quiet
    return (Get-CheckExitCode $checks)
}

if ($MyInvocation.InvocationName -ne '.') {
    $result = @(Invoke-Preflight @PSBoundParameters)
    for ($index = 0; $index -lt $result.Count - 1; $index++) { Write-Output $result[$index] }
    exit ([int]$result[-1])
}
