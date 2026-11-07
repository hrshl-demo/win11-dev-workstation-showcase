<#
.SYNOPSIS
Classify synthetic Microsoft launcher outcomes without running any installer.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\_common.psm1') -Force
}

Describe 'Bounded Microsoft base-only wait and recovery' {
    BeforeEach { Mock Test-BaseResumePending -ModuleName _common { $false } }
    It 'reports actual budget and unknown elevated state rather than initial UAC text' -TestCases @(
        @{ Budget = 7200 }, @{ Budget = 14400 }, @{ Budget = 28800 }) {
        param($Budget)
        $result = [pscustomobject]@{ TimedOut = $true; ExitCode = 124
            Output = 'Setup needs Administrator rights (a UAC prompt will appear)...' }
        { Get-BaseSetupOutcome $result -BaseSetupTimeoutSeconds $Budget } |
            Should -Throw "*exceeded $Budget seconds*Elevated Microsoft base state is unknown*final keypress*No add-on or Verify started*"
        Should -Invoke Test-BaseResumePending -ModuleName _common -Times 0 -Exactly
    }
    It 'retains the four-hour default and rejects budgets outside two to eight hours' {
        $result = [pscustomobject]@{ TimedOut = $true; ExitCode = 124; Output = '' }
        { Get-BaseSetupOutcome $result } | Should -Throw '*exceeded 14400 seconds*'
        { Get-BaseSetupOutcome $result -BaseSetupTimeoutSeconds 7199 } | Should -Throw
        { Get-BaseSetupOutcome $result -BaseSetupTimeoutSeconds 28801 } | Should -Throw
    }
    It 'preserves successful completion' {
        Get-BaseSetupOutcome ([pscustomobject]@{ TimedOut = $false; ExitCode = 0; Output = '' }) |
            Should -Be 'Complete'
        Should -Invoke Test-BaseResumePending -ModuleName _common -Times 1 -Exactly
    }
    It 'preserves genuine failure, including real exit 124 without timeout' -TestCases @(
        @{ Code = 1 }, @{ Code = 5 }, @{ Code = 124 }) {
        param($Code)
        { Get-BaseSetupOutcome ([pscustomobject]@{ TimedOut = $false; ExitCode = $Code; Output = 'synthetic failure' }) } |
            Should -Throw "*Microsoft base setup failed (exit $Code)*"
        Should -Invoke Test-BaseResumePending -ModuleName _common -Times 0 -Exactly
    }
    It 'preserves explicit reboot exits' -TestCases @(@{ Code = 3010 }, @{ Code = 1641 }) {
        param($Code)
        Get-BaseSetupOutcome ([pscustomobject]@{ TimedOut = $false; ExitCode = $Code; Output = '' }) |
            Should -Be 'ResumePending'
        Should -Invoke Test-BaseResumePending -ModuleName _common -Times 0 -Exactly
    }
    It 'preserves successful launcher pending base resume' {
        Mock Test-BaseResumePending -ModuleName _common { $true }
        Get-BaseSetupOutcome ([pscustomobject]@{ TimedOut = $false; ExitCode = 0; Output = '' }) |
            Should -Be 'ResumePending'
    }
    It 'leaves native default budgets and launcher-only termination intact' {
        $root = Split-Path -Parent $PSScriptRoot
        $text = Get-Content (Join-Path $root 'scripts\_common.psm1') -Raw
        $text | Should -Match '\[ValidateRange\(1, 28800\)\]\[int\]\$TimeoutSeconds = 60'
        $text | Should -Match '\$process.Kill\(\)'
        $text | Should -Not -Match '\$process.Kill\(\$true\)|taskkill|Stop-Process -Name'
    }
}
