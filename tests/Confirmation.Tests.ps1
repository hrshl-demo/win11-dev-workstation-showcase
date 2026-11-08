<#
.SYNOPSIS
Cold-process confirmation regressions using synthetic package modules only.
.DESCRIPTION
No actual Appx query/initialization, installer or workstation entrypoint runs.
Every generated file and simulated installer marker belongs to TestDrive.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Repository = Split-Path -Parent $PSScriptRoot
    function Invoke-ColdConfirmationFixture {
        param([string]$Mode, [string]$Answer = 'N', [switch]$WhatIf, [switch]$FailImport)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root
        $synthetic = Join-Path $root 'SyntheticPackages.psm1'
        $moduleText = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Alias -Name Get-SyntheticPackage -Value Get-SyntheticPackageRecord
Set-Alias -Name Add-SyntheticPackage -Value Get-SyntheticPackageRecord
Set-Alias -Name Remove-SyntheticPackage -Value Get-SyntheticPackageRecord
Set-Alias -Name Reset-SyntheticPackage -Value Get-SyntheticPackageRecord
function Get-SyntheticPackageRecord { [pscustomobject]@{ Version = '7.6.9.0'; InstallLocation = 'C:\synthetic\package' } }
Export-ModuleMember -Function Get-SyntheticPackageRecord -Alias *
'@
        if ($FailImport) { $moduleText += "`nthrow 'Synthetic initialization failed'`n" }
        Set-Content -LiteralPath $synthetic -Value $moduleText
        $child = Join-Path $root 'cold.ps1'
        $text = @'
param($Repository, $FixtureRoot, $Mode, $UseWhatIf)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'Low'
$beforeConfirm = $ConfirmPreference
$beforeWhatIf = $WhatIfPreference
$global:ConfirmationFixtureRoot = $FixtureRoot
$global:ConfirmationFixtureMode = $Mode
Import-Module (Join-Path $Repository 'scripts\_setup.psm1')
$module = Get-Module _setup
& $module {
    function script:Test-Path {
        [CmdletBinding()]
        param($LiteralPath, $PathType)
        if ($LiteralPath -like 'HK*:*') { return $false }
        Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
    }
    function script:Get-AppxPackage {
        [CmdletBinding()]
        param($Name)
        Import-Module (Join-Path $global:ConfirmationFixtureRoot 'SyntheticPackages.psm1') -ErrorAction Stop
        Get-SyntheticPackageRecord
    }
    function script:Get-ShowcaseRoot { $global:ConfirmationFixtureRoot }
    function script:Get-SetupPackage {
        [pscustomobject]@{ Id = 'Synthetic.Java'; Command = 'synthetic'; Paths = @(); Product = '^Synthetic'; Args = @('--version'); Required = '.+' }
    }
    function script:Get-SetupInventory {
        param($Package, $Installations)
        if ($global:ConfirmationFixtureMode -eq 'Unknown') { throw 'Synthetic inventory unknown; no downloads' }
        [pscustomobject]@{ Id = $Package.Id; State = $(if ($global:ConfirmationFixtureMode -eq 'Installed') { 'Installed' } else { 'Missing' })
            Compatible = $true; Version = '25.0.1'; Path = '' }
    }
    function script:Assert-WorkstationPolicy {}
    function script:Invoke-SetupReadiness {}
    function script:Get-NativeCommandPath { 'synthetic-installer.exe' }
    function script:Get-WindowsOptionalFeature {
        [CmdletBinding()]
        param([switch]$Online, $FeatureName)
        [pscustomobject]@{ State = 'Enabled' }
    }
    function script:Invoke-SetupNative {
        [IO.File]::WriteAllText((Join-Path $global:ConfirmationFixtureRoot 'simulated-installer.txt'), 'approved fixture only')
        [pscustomobject]@{ ExitCode = 0; ElapsedSeconds = 0 }
    }
}
$selectedModule = if ($Mode -eq 'WslInstalled') { 'WSL' } else { 'Java' }
$result = Invoke-SetupModule -Module $selectedModule -Apply -Confirm -WhatIf:($UseWhatIf -eq 'True')
if ($ConfirmPreference -ne $beforeConfirm -or $WhatIfPreference -ne $beforeWhatIf) { throw 'Caller preferences changed' }
$restored = & $module { $ConfirmPreference -eq 'Low' }
if (-not $restored) { throw 'Module preference scope leaked' }
$logDirectory = Join-Path $FixtureRoot '.showcase-setup'
[ordered]@{ Result = $result; Confirm = [string]$ConfirmPreference; WhatIf = $WhatIfPreference
    Installer = Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $FixtureRoot 'simulated-installer.txt')
    Journal = Microsoft.PowerShell.Management\Test-Path -LiteralPath $logDirectory } | ConvertTo-Json -Compress
'@
        Set-Content -LiteralPath $child -Value $text
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = (Get-Process -Id $PID).Path
        $start.Arguments = '-NoProfile -File "' + $child + '" "' + $script:Repository + '" "' + $root + '" ' + $Mode + ' ' + [string][bool]$WhatIf
        $start.UseShellExecute = $false
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $start
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.WriteLine($Answer)
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(30000)) {
                $process.Kill()
                throw 'Cold synthetic confirmation process timed out.'
            }
            $output = $stdout.GetAwaiter().GetResult()
            $errorText = $stderr.GetAwaiter().GetResult()
            $process.ExitCode | Should -Be 0 -Because $errorText
            $output | Should -Not -Match 'Set Alias|Create Directory|New-Item'
            $json = @($output -split '[\r\n]+' | Where-Object { $_ -match '^\{"Result":' })[-1] | ConvertFrom-Json
            [pscustomobject]@{ Output = $output; Error = $errorText; Data = $json }
        } finally { $process.Dispose() }
    }
}

Describe 'Fresh process trusted inventory confirmation scoping' {
    It 'cold installed inventory defines aliases without prompts and preserves caller preferences' {
        $result = Invoke-ColdConfirmationFixture -Mode Installed
        $result.Data.Result | Should -Be 0
        $result.Data.Confirm | Should -Be 'Low'
        $result.Data.Installer | Should -BeFalse
        $result.Data.Journal | Should -BeFalse
        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -Not -Match 'Install locally proven'
    }
    It 'declining the actual target writes no journal or installer marker' {
        $result = Invoke-ColdConfirmationFixture -Mode Missing -Answer N
        $result.Data.Result | Should -Be 0
        $result.Data.Installer | Should -BeFalse
        $result.Data.Journal | Should -BeFalse
        $result.Output | Should -Match 'Target declined'
    }
    It 'cold WSL inventory also avoids inherited alias confirmations without feature actions' {
        $result = Invoke-ColdConfirmationFixture -Mode WslInstalled
        $result.Data.Result | Should -Be 0
        $result.Data.Installer | Should -BeFalse
        $result.Data.Journal | Should -BeFalse
        $result.Data.Confirm | Should -Be 'Low'
        $result.Error | Should -BeNullOrEmpty
    }
    It 'approving the real target permits only scoped fixture housekeeping and simulated installer' {
        $result = Invoke-ColdConfirmationFixture -Mode Missing -Answer Y
        $result.Data.Result | Should -Be 0
        $result.Data.Installer | Should -BeTrue
        $result.Data.Journal | Should -BeTrue
        $result.Data.Confirm | Should -Be 'Low'
        $result.Error | Should -BeNullOrEmpty
    }
    It 'WhatIf preserves inventory with no journal or installer and no internal prompts' {
        $result = Invoke-ColdConfirmationFixture -Mode Missing -WhatIf
        $result.Data.Result | Should -Be 0
        $result.Data.Installer | Should -BeFalse
        $result.Data.Journal | Should -BeFalse
        $result.Data.WhatIf | Should -BeFalse
    }
    It 'unexpected cold initialization and inventory errors stay explicit and restore preferences' -TestCases @(
        @{ Mode = 'Missing'; FailImport = $true }, @{ Mode = 'Unknown'; FailImport = $false }) {
        param($Mode, $FailImport)
        $result = Invoke-ColdConfirmationFixture -Mode $Mode -FailImport:$FailImport
        $result.Data.Result | Should -Be 1
        $result.Data.Installer | Should -BeFalse
        $result.Data.Journal | Should -BeFalse
        $result.Data.Confirm | Should -Be 'Low'
        $result.Output | Should -Match '\[FAIL\]'
    }
}
