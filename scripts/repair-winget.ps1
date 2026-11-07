<#
.SYNOPSIS
Guided, confirmed WinGet repair without bypassing organisation policy.
.DESCRIPTION
Checks policy first and returns exit 2 on a policy block. Each repair requires
ShouldProcess consent and is re-tested; stops at the first working configure.
Other failures return 1. Never run this script from an autonomous agent.
.PARAMETER AllUsers
Use the official repair's AllUsers option (requires administrator consent).
.EXAMPLE
.\scripts\repair-winget.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$AllUsers)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Test-WinGetConfigure {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $winget = Get-NativeCommandPath winget
    if (-not $winget) {
        return [pscustomobject]@{ Ready = $false; Output = 'WinGet not resolvable.' }
    }
    try {
        $version = Invoke-NativeCommand $winget @('--version') -TimeoutSeconds 15
        $match = [regex]::Match($version.Output, '\d+\.\d+\.\d+')
        $configure = Invoke-NativeCommand $winget @('configure', '--help') -TimeoutSeconds 30
        $ready = $version.ExitCode -eq 0 -and $match.Success -and
            [version]$match.Value -ge [version]'1.6.3482' -and $configure.ExitCode -eq 0
        return [pscustomobject]@{ Ready = $ready; Output = $version.Output + "`n" + $configure.Output }
    } catch { return [pscustomobject]@{ Ready = $false; Output = $_.Exception.Message } }
}

function Invoke-WinGetRepair {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([int])]
    param([switch]$AllUsers)
    try {
        $policy = @(Get-WinGetPolicy)
        $blocked = @($policy | Where-Object { $_.Status -eq 'FAIL' })
        if ($blocked.Count -gt 0) {
            Write-CheckReport $blocked
            Write-ShowcaseMessage '[FAIL] Contact IT: this script does not change organisation policy.'
            return (Get-CheckExitCode $blocked -PolicyRepair)
        }
        $test = Test-WinGetConfigure
        if ($test.Ready) { Write-ShowcaseMessage '[PASS] WinGet configure already works; no repair needed.'; return 0 }
        $history = $test.Output
        $steps = @('Register', 'Reset', 'Official', 'Enable', 'Redistributable')
        foreach ($step in $steps) {
            Assert-WorkstationPolicy
            if ($step -eq 'Reset') {
                $os = Get-CimInstance Win32_OperatingSystem
                if ([int]$os.BuildNumber -lt 22000 -or $os.ProductType -ne 1) {
                    Write-ShowcaseMessage '[WARN] App Installer reset is offered only on Windows 11.'
                    continue
                }
            }
            if ($step -eq 'Redistributable' -and $history -notmatch '-2146233079|0x80131509') { continue }
            $action = switch ($step) {
                Register { 'Re-register App Installer for the signed-in user' }
                Reset { 'Reset App Installer for the signed-in user' }
                Official { 'Install NuGet and Microsoft.WinGet.Client from PSGallery; run official latest WinGet repair' }
                Enable { 'Enable the WinGet configure command' }
                Redistributable { 'Install the Visual C++ Redistributable for configure error -2146233079' }
            }
            if (-not $PSCmdlet.ShouldProcess('WinGet / App Installer', $action)) { continue }
            try {
                switch ($step) {
                    Register {
                        $null = Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
                    }
                    Reset {
                        $package = Get-AppxPackage Microsoft.DesktopAppInstaller
                        if ($null -eq $package) { throw 'No current-user App Installer package to reset.' }
                        $package | Reset-AppxPackage
                    }
                    Official {
                        if ($AllUsers -and -not (Test-IsAdministrator)) { throw '-AllUsers requires an elevated user session.' }
                        $null = Install-PackageProvider -Name NuGet -Force
                        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery
                        Import-Module Microsoft.WinGet.Client -Force
                        if ($AllUsers) { Repair-WinGetPackageManager -Force -Latest -AllUsers }
                        else { Repair-WinGetPackageManager -Force -Latest }
                    }
                    Enable {
                        $winget = Get-NativeCommandPath winget
                        if (-not $winget) { throw 'WinGet still not resolvable; check App execution aliases.' }
                        $result = Invoke-NativeCommand $winget @('configure', '--enable') -TimeoutSeconds 60
                        Assert-NativeSuccess $result 'Enable WinGet configure'
                    }
                    Redistributable {
                        $winget = Get-NativeCommandPath winget
                        if (-not $winget) { throw 'WinGet is unavailable.' }
                        $architecture = $env:PROCESSOR_ARCHITECTURE
                        if ($env:PROCESSOR_ARCHITEW6432) { $architecture = $env:PROCESSOR_ARCHITEW6432 }
                        $packageId = if ($architecture -eq 'ARM64') { 'Microsoft.VCRedist.2015+.arm64' } else { 'Microsoft.VCRedist.2015+.x64' }
                        $result = Invoke-NativeCommand $winget @('install', '--id', $packageId, '--exact', '--source', 'winget') -TimeoutSeconds 600
                        Assert-NativeSuccess $result 'Install Visual C++ Redistributable'
                    }
                }
                Write-ShowcaseMessage "[PASS] Repair step completed: $action"
            } catch {
                $history += "`n" + $_.Exception.Message
                Write-ShowcaseMessage "[WARN] Repair step failed: $($_.Exception.Message)"
            }
            Assert-WorkstationPolicy
            $test = Test-WinGetConfigure
            $history += "`n" + $test.Output
            if ($test.Ready) { Write-ShowcaseMessage '[PASS] WinGet configure works. Repair stopped.'; return 0 }
            Write-ShowcaseMessage '[WARN] Re-test failed; the next repair requires separate consent.'
        }
        if ($WhatIfPreference) { Write-ShowcaseMessage '[PASS] Repair plan only; no changes made.'; return 0 }
        Write-ShowcaseMessage '[FAIL] WinGet configure is still unavailable. Check App Installer account registration, aliases and logs; contact IT.'
        return 1
    } catch {
        $blocked = @(Get-WinGetPolicy | Where-Object { $_.Status -eq 'FAIL' })
        if ($blocked.Count -gt 0) { Write-CheckReport $blocked; return 2 }
        Write-ShowcaseMessage "[FAIL] Repair: $($_.Exception.Message)"
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-WinGetRepair @PSBoundParameters) }
