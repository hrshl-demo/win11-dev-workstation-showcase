<#
.SYNOPSIS
Explicitly opt in to the legacy Microsoft standard bundle and add-on.
.DESCRIPTION
Requires an approved Windows 11 workstation, internet, local admin and UAC
consent for the Microsoft setup. The base may restart the PC and resumes
itself; explicitly select bootstrap.ps1 -LegacyMicrosoftBundle -Apply -SkipBase
only after confirmed successful completion/resume to finish this broad add-on.
This broad bundle is NOT the modular installed-first path. Its upstream preset
can download before detecting existing tools and change OS/profile settings.
Downloads to a unique directory under TEMP and executes only after a Valid
Microsoft Corporation Authenticode signature. Logs are stored under
LOCALAPPDATA\win11-dev-workstation. Explicit policy blocks are never bypassed.
.PARAMETER SkipBase
Apply this add-on without running the Microsoft base (also used after reboot).
.PARAMETER IncludeJavaModernization
Also apply the Java 11 and Copilot modernization add-on and verify its extension.
.PARAMETER HttpsTimeoutSeconds
Pass an operator-selected 1-30 second HTTPS timeout to child preflight; default 5.
.PARAMETER BaseSetupTimeoutSeconds
Bound only the Microsoft base launcher wait: 7200-28800 seconds, default 14400
(4 hours). A timeout does not prove elevated setup stopped; never retry blindly.
.EXAMPLE
.\scripts\bootstrap.ps1 -WhatIf
.EXAMPLE
.\scripts\bootstrap.ps1 -LegacyMicrosoftBundle -Apply -SkipBase -IncludeJavaModernization
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$SkipBase, [switch]$IncludeJavaModernization,
    [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5,
    [ValidateRange(7200, 28800)][int]$BaseSetupTimeoutSeconds = 14400)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Invoke-Bootstrap {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([int])]
    param([switch]$SkipBase, [switch]$IncludeJavaModernization,
        [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5,
        [ValidateRange(7200, 28800)][int]$BaseSetupTimeoutSeconds = 14400)
    $transcript = $false
    $downloadDirectory = $null
    $downloadPath = $null
    $downloadOwned = $false
    try {
        $root = Get-ShowcaseRoot
        if ($WhatIfPreference) {
            Write-ShowcaseMessage "[PASS] Plan: child preflight HTTPS timeout $HttpsTimeoutSeconds seconds/attempt; overall budget $(Get-PreflightTimeout $HttpsTimeoutSeconds) seconds."
            Write-ShowcaseMessage "[PASS] Plan: Microsoft base-only launcher budget $BaseSetupTimeoutSeconds seconds ($($BaseSetupTimeoutSeconds / 3600) hours); unused with SkipBase."
            Write-ShowcaseMessage '[PASS] Plan only: run read-only preflight; stop on any FAIL or organisation policy block.'
            if (-not $SkipBase) {
                Write-ShowcaseMessage '[WARN] Plan: download https://aka.ms/devconfig/standard/setup.ps1 to a private TEMP directory; verify Valid Microsoft Corporation Authenticode signature; execute verified text. Base may restart and resumes itself.'
                Write-ShowcaseMessage '[WARN] Only after confirmed successful Microsoft restart/resume: .\scripts\bootstrap.ps1 -LegacyMicrosoftBundle -Apply -SkipBase'
            }
            Write-ShowcaseMessage '[PASS] Plan: log to %LOCALAPPDATA%\win11-dev-workstation; apply .config\configuration.winget; verify.'
            if ($IncludeJavaModernization) { Write-ShowcaseMessage '[PASS] Plan: also apply .config\java-modernization.winget; require the modernization extension.' }
            return 0
        }
        Assert-WorkstationPolicy
        $shell = (Get-Process -Id $PID).Path
        $preflightBudget = Get-PreflightTimeout -HttpsTimeoutSeconds $HttpsTimeoutSeconds
        $preflight = Invoke-NativeCommand $shell @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'preflight.ps1'),
            '-Json', '-HttpsTimeoutSeconds', [string]$HttpsTimeoutSeconds) -TimeoutSeconds $preflightBudget
        if ($preflight.TimedOut) { throw "Preflight exceeded its $preflightBudget-second budget; no setup actions started. Review read-only readiness/network diagnostics." }
        $parsedChecks = $preflight.StdOut | ConvertFrom-Json
        $checks = @($parsedChecks)
        if ($preflight.ExitCode -ne 0 -or (Get-CheckExitCode $checks) -ne 0) {
            $failures = @($checks | Where-Object Status -eq 'FAIL' | ForEach-Object { "$($_.Name): $($_.Message)" })
            throw "Preflight failed before setup; no setup actions started. $($failures -join '; ')"
        }
        if (-not $PSCmdlet.ShouldProcess('Developer workstation', 'Run approved bootstrap and write its log')) {
            Write-ShowcaseMessage '[WARN] Bootstrap cancelled; no configuration applied.'
            return 0
        }
        $logDirectory = Join-Path $env:LOCALAPPDATA 'win11-dev-workstation'
        Assert-SafeDirectory $logDirectory
        if (-not (Test-Path -LiteralPath $logDirectory)) { $null = New-Item -ItemType Directory -Path $logDirectory }
        $logPath = Join-Path $logDirectory ("bootstrap-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
        $null = Start-Transcript -Path $logPath -NoClobber
        $transcript = $true
        Write-ShowcaseMessage "[PASS] Bootstrap log: $logPath"
        if (-not $SkipBase) {
            if (-not $PSCmdlet.ShouldProcess('Microsoft standard developer configuration', 'Download, validate Microsoft signature and run; may restart the PC')) {
                Write-ShowcaseMessage '[WARN] Microsoft base declined. Re-run with -SkipBase only if the base is already installed.'
                return 0
            }
            Assert-WorkstationPolicy
            Assert-SafeDirectory $env:TEMP
            $downloadDirectory = Join-Path $env:TEMP ("win11-dev-workstation-" + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $downloadDirectory
            $downloadOwned = $true
            $downloadPath = Join-Path $downloadDirectory 'setup.ps1'
            $originalTls = [Net.ServicePointManager]::SecurityProtocol
            try {
                [Net.ServicePointManager]::SecurityProtocol = $originalTls -bor [Net.SecurityProtocolType]::Tls12
                $null = Invoke-WebRequest -Uri 'https://aka.ms/devconfig/standard/setup.ps1' -OutFile $downloadPath -UseBasicParsing -TimeoutSec 60
            } finally { [Net.ServicePointManager]::SecurityProtocol = $originalTls }
            $setupText = Read-MicrosoftSignedScript -Path $downloadPath
            Write-ShowcaseMessage '[WARN] Microsoft base may restart/resume. Finish only after confirmed success with -LegacyMicrosoftBundle -Apply -SkipBase.'
            # Run in a child shell so the Microsoft wrapper cannot exit this script
            # and lose its log/cleanup or accidentally proceed to the add-on.
            # Stdin avoids Windows' command-line length limit for signed scripts.
            $expression = '$ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; $setup=[Console]::In.ReadToEnd(); try { & ([scriptblock]::Create($setup)) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($expression))
            Write-ShowcaseMessage "[WARN] Waiting up to $BaseSetupTimeoutSeconds seconds ($($BaseSetupTimeoutSeconds / 3600) hours) for the Microsoft base launcher. Elevated setup may continue if this wait times out; do not start another setup."
            $base = Invoke-NativeCommand $shell @('-NoProfile', '-EncodedCommand', $encoded) -InputText $setupText -TimeoutSeconds $BaseSetupTimeoutSeconds
            $baseOutcome = Get-BaseSetupOutcome -Result $base -BaseSetupTimeoutSeconds $BaseSetupTimeoutSeconds
            if ($base.Output) { Write-ShowcaseMessage $base.Output }
            if ($baseOutcome -eq 'ResumePending') {
                Write-ShowcaseMessage '[WARN] Microsoft base needs restart/resume. After confirmed success, select legacy Finish setup (-LegacyMicrosoftBundle -Apply -SkipBase). Add-on not applied yet.'
                return 0
            }
        }
        $winget = Get-NativeCommandPath winget
        if (-not $winget) { throw 'WinGet is not on PATH. Open a new terminal after the base, then run bootstrap.ps1 -SkipBase.' }
        $files = @('configuration.winget')
        if ($IncludeJavaModernization) { $files += 'java-modernization.winget' }
        foreach ($file in $files) {
            $configuration = Join-Path $root ".config\$file"
            if (-not (Test-Path -LiteralPath $configuration -PathType Leaf)) { throw "Configuration missing: $configuration" }
            Assert-WorkstationPolicy
            if (-not $PSCmdlet.ShouldProcess($configuration, 'Apply WinGet configuration (may require UAC)')) {
                Write-ShowcaseMessage '[WARN] Configuration declined; verification not run.'
                return 0
            }
            $result = Invoke-NativeCommand $winget @('configure', '-f', $configuration, '--accept-configuration-agreements') -TimeoutSeconds 3600
            if ($result.Output) { Write-ShowcaseMessage $result.Output }
            Assert-NativeSuccess $result "Apply $file"
        }
        $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'verify.ps1'))
        if ($IncludeJavaModernization) { $arguments += '-IncludeJavaModernization' }
        $verification = Invoke-NativeCommand $shell $arguments -TimeoutSeconds 600
        if ($verification.Output) { Write-ShowcaseMessage $verification.Output }
        Assert-NativeSuccess $verification 'Final verification'
        Write-ShowcaseMessage '[PASS] Workstation verified. Sign in to GitHub Copilot in VS Code; authentication is a separate user action.'
        return 0
    } catch {
        Write-ShowcaseMessage "[FAIL] Bootstrap: $($_.Exception.Message)"
        return 1
    } finally {
        if ($downloadOwned -and $null -ne $downloadDirectory) {
            try {
                Assert-SafeDirectory $downloadDirectory
                if ($null -ne $downloadPath -and (Test-Path -LiteralPath $downloadPath)) {
                    $file = Get-Item -LiteralPath $downloadPath -Force
                    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Download file became a reparse point; refusing cleanup.' }
                    Remove-Item -LiteralPath $downloadPath -Force -WhatIf:$false
                }
                # Never recurse through TEMP: only our single file and empty GUID directory.
                if (@(Get-ChildItem -LiteralPath $downloadDirectory -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $downloadDirectory -Force -WhatIf:$false
                } else {
                    Write-ShowcaseMessage '[WARN] Owned download directory is no longer empty; preserving unexpected files.'
                }
            } catch { Write-ShowcaseMessage "[WARN] Could not clean owned download directory: $($_.Exception.Message)" }
        }
        if ($transcript) { $null = Stop-Transcript }
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Bootstrap @PSBoundParameters) }
