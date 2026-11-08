<#
.SYNOPSIS
Installed-first modules tested with synthetic inventory, TestDrive and mocks.
.DESCRIPTION
No actual installer, source/provider restoration, WSL change or preset runs.
One harmless native child prints a fixture line to exercise live output capture.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
BeforeAll {
    $script:Repository = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:Repository 'scripts\_setup.psm1') -Force
}

Describe 'Installed-first module effects' {
    BeforeEach {
        $global:SetupFixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $global:SetupFixtureRoot
        $global:SetupFixtureState = 'Installed'
        $global:SetupFixtureCompatible = $true
        $global:SetupFixtureRebootCode = 0
        Mock Get-ShowcaseRoot -ModuleName _setup { $global:SetupFixtureRoot }
        Mock Get-LocalInstallation -ModuleName _setup { @() }
        Mock Get-SetupPackage -ModuleName _setup {
            [pscustomobject]@{ Id = 'Synthetic.Tool'; Command = 'synthetic'; Args = @('--version'); Required = '.+'; Product = '^Synthetic'; Paths = @() }
        }
        Mock Get-SetupInventory -ModuleName _setup {
            [pscustomobject]@{ Id = $Package.Id; State = $global:SetupFixtureState
                Compatible = $global:SetupFixtureCompatible; Version = '3.14.10'; Path = 'C:\existing\tool.exe' }
        }
        Mock Invoke-SetupNative -ModuleName _setup { [pscustomobject]@{ ExitCode = 0; ElapsedSeconds = 1 } }
        Mock Invoke-SetupReadiness -ModuleName _setup {}
        Mock Assert-WorkstationPolicy -ModuleName _setup {}
        Mock Get-NativeCommandPath -ModuleName _setup { 'synthetic-winget.exe' }
        Mock Write-ShowcaseMessage -ModuleName _setup {}
    }
    AfterEach {
        Remove-Variable SetupFixtureRoot, SetupFixtureState, SetupFixtureCompatible, SetupFixtureRebootCode -Scope Global
    }
    It 'installed target skips all download/installer/preflight activity before sources' {
        Invoke-SetupModule -Module Python -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
        Test-Path (Join-Path $global:SetupFixtureRoot '.showcase-setup') | Should -BeFalse
    }
    It 'installed but incompatible is retained with failure and zero downloads/upgrades' {
        $global:SetupFixtureCompatible = $false
        Invoke-SetupModule -Module Python -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
    }
    It 'inventory failure is unknown, not missing, and stops before sources' {
        Mock Get-LocalInstallation -ModuleName _setup { throw 'Registry inventory denied' }
        Invoke-SetupModule -Module Core -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
    }
    It 'unknown relevant registration blocks apply with no preflight or download' {
        Mock Get-SetupInventory -ModuleName _setup {
            & (Get-Module _setup) {
                Get-SetupExecutable ([pscustomobject]@{ Id = 'Synthetic.Tool'; Command = 'synthetic'
                    Args = @('--version'); Required = '.+'; Paths = @() }) @(
                    [pscustomobject]@{ Location = "C:\bad`"location" })
            }
        }
        Mock Get-NativeCommandPath -ModuleName _setup { $null }
        Invoke-SetupModule -Module Core -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Assert-WorkstationPolicy -ModuleName _setup -Times 0 -Exactly
        Test-Path (Join-Path $global:SetupFixtureRoot '.showcase-setup') | Should -BeFalse
    }
    It 'default preview and WhatIf have zero installer and file effects even when missing' {
        $global:SetupFixtureState = 'Missing'
        Invoke-SetupModule | Should -Be 0
        Invoke-SetupModule -Module Python -Apply -WhatIf | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Test-Path (Join-Path $global:SetupFixtureRoot '.showcase-setup') | Should -BeFalse
    }
    It 'mixed installed/missing invokes only the missing target after inventory and recheck' {
        Mock Get-SetupPackage -ModuleName _setup {
            @([pscustomobject]@{ Id = 'Synthetic.Existing' }, [pscustomobject]@{ Id = 'Synthetic.Missing' })
        }
        Mock Get-SetupInventory -ModuleName _setup {
            [pscustomobject]@{ Id = $Package.Id; State = $(if ($Package.Id -eq 'Synthetic.Existing') { 'Installed' } else { 'Missing' })
                Compatible = $true; Version = '1.0'; Path = '' }
        }
        Invoke-SetupModule -Module Core -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'Synthetic.Missing' -and $Arguments -notcontains 'Synthetic.Existing' -and
            $Arguments -contains 'install' -and $Arguments -notcontains 'upgrade'
        }
        Should -Invoke Get-SetupInventory -ModuleName _setup -Times 3 -Exactly
    }
    It 'recheck retains a tool installed during the approval pause' {
        $global:SetupFixtureState = 'Missing'
        Mock Invoke-SetupReadiness -ModuleName _setup { $global:SetupFixtureState = 'Installed' }
        Invoke-SetupModule -Module Python -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
    }
    It 'single-module retry never invokes another SDK or the Microsoft bundle' {
        $global:SetupFixtureState = 'Missing'
        Invoke-SetupModule -Module Go -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Get-SetupPackage -ModuleName _setup -Times 2 -Exactly -ParameterFilter { $Module -eq 'Go' }
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly
    }
    It 'new missing Go is pinned to the reviewed manifest version, never latest by accident' {
        $global:SetupFixtureState = 'Missing'
        Mock Get-SetupPackage -ModuleName _setup {
            [pscustomobject]@{ Id = 'GoLang.Go'; Version = '1.27.3' }
        }
        Invoke-SetupModule -Module Go -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains '--version' -and $Arguments -contains '1.27.3'
        }
    }
    It 'stops on genuine failure or uncertain timeout without retrying or claiming Verify' -TestCases @(
        @{ Timeout = $false }, @{ Timeout = $true }) {
        param($Timeout)
        $global:SetupFixtureState = 'Missing'
        if ($Timeout) {
            Mock Invoke-SetupNative -ModuleName _setup { throw 'Wait timed out; vendor state unknown' }
        } else {
            Mock Invoke-SetupNative -ModuleName _setup { [pscustomobject]@{ ExitCode = 5; ElapsedSeconds = 1 } }
        }
        Invoke-SetupModule -Module Python -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly
        $logs = @(Get-ChildItem (Join-Path $global:SetupFixtureRoot '.showcase-setup') -File)
        $states = @(Get-Content $logs[0].FullName | ForEach-Object { ($_ | ConvertFrom-Json).State })
        $states | Should -Contain 'StoppedUnverified'
        $states | Should -Not -Contain 'ModuleReturned'
    }
    It 'records bounded per-module event states without raw installer output' {
        $global:SetupFixtureState = 'Missing'
        Invoke-SetupModule -Module Python -Apply -InstallTimeoutSeconds 14400 -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 14400 }
        $log = Get-ChildItem (Join-Path $global:SetupFixtureRoot '.showcase-setup') -File
        $records = @(Get-Content $log.FullName | ForEach-Object { $_ | ConvertFrom-Json })
        $records[0].State | Should -Be 'Started'
        $records[-1].State | Should -Be 'ModuleReturned'
        $records[-1].PSObject.Properties.Name | Should -Not -Contain 'Output'
        $records[-1].ElapsedSeconds | Should -BeGreaterOrEqual 0
    }
    It 'pauses on a vendor reboot outcome before the next missing target' -TestCases @(
        @{ Code = 3010 }, @{ Code = 1641 }) {
        param($Code)
        $global:SetupFixtureRebootCode = $Code
        $global:SetupFixtureState = 'Missing'
        Mock Get-SetupPackage -ModuleName _setup {
            @([pscustomobject]@{ Id = 'Synthetic.First' }, [pscustomobject]@{ Id = 'Synthetic.Next' })
        }
        Mock Invoke-SetupNative -ModuleName _setup { [pscustomobject]@{ ExitCode = $global:SetupFixtureRebootCode; ElapsedSeconds = 1 } }
        Invoke-SetupModule -Module Core -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'Synthetic.First' -and $Arguments -notcontains 'Synthetic.Next'
        }
        $log = Get-ChildItem (Join-Path $global:SetupFixtureRoot '.showcase-setup') -File
        $states = @(Get-Content $log.FullName | ForEach-Object { ($_ | ConvertFrom-Json).State })
        $states[-1] | Should -Be 'RestartRequired'
        $states | Should -Not -Contain 'ModuleReturned'
    }
    It 'missing extensions require source approval before preflight or download' {
        Mock Get-SetupExtension -ModuleName _setup {
            [pscustomobject]@{ Id = 'ms-python.python'; State = 'Missing'; Compatible = $true; Path = 'synthetic-code.cmd'; Version = '' }
        }
        Invoke-SetupModule -Module Extensions -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
    }
    It 'all installed extensions skip source approval, preflight and every installer' {
        Mock Get-SetupExtension -ModuleName _setup {
            [pscustomobject]@{ Id = 'ms-python.python'; State = 'Installed'; Compatible = $true; Path = 'synthetic-code.cmd'; Version = '1.0' }
        }
        Invoke-SetupModule -Module Extensions -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
    }
    It 'rejects an out-of-range target budget before inventory or effects' {
        { Invoke-SetupModule -InstallTimeoutSeconds 14401 -Apply -Confirm:$false } | Should -Throw
        Should -Invoke Get-LocalInstallation -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
    }
}

Describe 'Local installed-target discovery, including stale PATH' {
    BeforeEach {
        $global:SetupFixturePackage = [pscustomobject]@{ Id = 'Python.Python.3.14'; Command = 'python'
            Args = @('--version'); Product = '^Python'; Required = '\b3\.14\.'; Paths = @('C:\already-installed\python.exe') }
        Mock Get-NativeCommandPath -ModuleName _setup { 'C:\stale-path\python.exe' }
        Mock Test-Path -ModuleName _setup { $false }
        Mock Test-Path -ModuleName _setup { $true } -ParameterFilter {
            $LiteralPath -in @('C:\stale-path\python.exe', 'C:\already-installed\python.exe')
        }
        Mock Get-Item -ModuleName _setup { [pscustomobject]@{ Attributes = [IO.FileAttributes]::Normal } }
        Mock Invoke-NativeCommand -ModuleName _setup {
            [pscustomobject]@{ ExitCode = 0; TimedOut = $false; Output = $(if ($FilePath -eq 'C:\stale-path\python.exe') { 'Python 3.12.10' } else { 'Python 3.14.10' }) }
        }
    }
    AfterEach { Remove-Variable SetupFixturePackage -Scope Global }
    It 'finds compatible installed Python off PATH without upgrading the old default' {
        $result = Get-SetupInventory $global:SetupFixturePackage @()
        $result.State | Should -Be 'Installed'
        $result.Compatible | Should -BeTrue
        $result.Path | Should -Be 'C:\already-installed\python.exe'
        $result.Version | Should -Be 'Python 3.14.10'
    }
    It 'registry-only installation is retained, not mistaken for missing' {
        Mock Get-SetupExecutable -ModuleName _setup { $null }
        $result = Get-SetupInventory $global:SetupFixturePackage @(
            [pscustomobject]@{ Name = 'Python 3.14.10'; Version = '3.14.10'; Location = 'D:\managed' })
        $result.State | Should -Be 'Installed'
        $result.Compatible | Should -BeFalse
    }
    It 'normalizes a quoted registration directory containing spaces before probing' {
        $global:SetupFixturePackage.Paths = @()
        Mock Get-NativeCommandPath -ModuleName _setup { $null }
        Mock Test-Path -ModuleName _setup { $true } -ParameterFilter { $LiteralPath -eq 'C:\Program Files\Synthetic Python\python.exe' }
        $result = Get-SetupInventory $global:SetupFixturePackage @(
            [pscustomobject]@{ Name = 'Python 3.14.10'; Location = '  "C:\Program Files\Synthetic Python"  '; Version = '3.14.10' })
        $result.State | Should -Be 'Installed'
        $result.Path | Should -Be 'C:\Program Files\Synthetic Python\python.exe'
        $result.Compatible | Should -BeTrue
    }
    It 'retains a proven compatible candidate despite malformed matching registration' {
        $result = Get-SetupInventory $global:SetupFixturePackage @(
            [pscustomobject]@{ Name = 'Python 3.14.10'; Location = 'C:\bad"location'; Version = '3.14.10' })
        $result.Path | Should -Be 'C:\already-installed\python.exe'
        $result.Compatible | Should -BeTrue
    }
    It 'reports malformed relevant registration as package-specific unknown, not missing' -TestCases @(
        @{ Value = 'C:\bad"location' }, @{ Value = "C:\bad`nlocation" },
        @{ Value = 'C:\bad|location' }, @{ Value = 'relative\location' },
        @{ Value = '%SHOWCASE_UNSET_PATH_FIXTURE%\tool' }, @{ Value = 'C:relative' }) {
        param($Value)
        $global:SetupFixturePackage.Paths = @()
        Mock Get-NativeCommandPath -ModuleName _setup { $null }
        { Get-SetupInventory $global:SetupFixturePackage @(
            [pscustomobject]@{ Name = 'Python 3.14.10'; Location = $Value; Version = '3.14.10' }) } |
            Should -Throw '*Inventory unknown for Python.Python.3.14*no downloads*'
        Should -Invoke Invoke-NativeCommand -ModuleName _setup -Times 0 -Exactly
    }
    It 'validates known and link target paths instead of executing registration strings' {
        $global:SetupFixturePackage.Paths = @('C:\bad"known.exe')
        Mock Get-NativeCommandPath -ModuleName _setup { $null }
        { Get-SetupExecutable $global:SetupFixturePackage @() } | Should -Throw '*known location*'
        $global:SetupFixturePackage.Paths = @('C:\already-installed\python.exe')
        Mock Get-Item -ModuleName _setup {
            [pscustomobject]@{ Attributes = [IO.FileAttributes]::ReparsePoint; Target = 'C:\bad"target.exe' }
        }
        { Get-SetupExecutable $global:SetupFixturePackage @() } | Should -Throw '*executable link*'
        Should -Invoke Invoke-NativeCommand -ModuleName _setup -Times 0 -Exactly
    }
    It 'reports invalid Python ExecutablePath without invoking it as a command' {
        $global:SetupFixturePackage.Paths = @()
        Mock Get-NativeCommandPath -ModuleName _setup { $null }
        Mock Test-Path -ModuleName _setup { $true } -ParameterFilter { $LiteralPath -like 'HKCU:\SOFTWARE\Python\PythonCore*' }
        Mock Get-ChildItem -ModuleName _setup {
            [pscustomobject]@{ PSPath = 'HKCU:\SOFTWARE\Python\PythonCore\3.14' }
        }
        Mock Get-ItemProperty -ModuleName _setup { [pscustomobject]@{ ExecutablePath = 'C:\python.exe --install' + '"' } }
        { Get-SetupExecutable $global:SetupFixturePackage @() } | Should -Throw '*Python registration executable*'
        Should -Invoke Invoke-NativeCommand -ModuleName _setup -Times 0 -Exactly
    }
    It 'retains a registered Store Python with a four-component package version' {
        $global:SetupFixturePackage.Product = (@(Get-SetupPackage Python)[0]).Product
        Mock Get-SetupExecutable -ModuleName _setup { $null }
        $result = Get-SetupInventory $global:SetupFixturePackage @(
            [pscustomobject]@{ Name = 'Python 3.14.1000.0'; Version = '3.14.1000.0'; Location = 'C:\registered-store' })
        $result.State | Should -Be 'Installed'
        $result.Compatible | Should -BeFalse
    }

    Describe 'Real path normalization and inactive NVM discovery' {
        It 'uses real .NET normalization with quotes, spaces and process environment expansion' {
            & (Get-Module _setup) {
                $result = ConvertTo-SetupPath '  "%ProgramFiles%\Synthetic Tool\..\Synthetic Tool"  '
                $result.Reason | Should -BeNullOrEmpty
                $result.Path | Should -Be ([IO.Path]::Combine($env:ProgramFiles, 'Synthetic Tool'))
                [IO.Path]::IsPathRooted($result.Path) | Should -BeTrue
            }
        }
        It 'rejects control, illegal, unexpanded, relative and network path syntax consistently' -TestCases @(
            @{ Value = 'C:\bad{NUL}path' }, @{ Value = "C:\bad`tpath" }, @{ Value = 'C:\bad<path' },
            @{ Value = 'C:\bad>path' }, @{ Value = 'C:\bad?path' }, @{ Value = 'C:\bad*path' },
            @{ Value = 'C:\bad:path' }, @{ Value = 'C:\bad"path' }, @{ Value = 'relative' },
            @{ Value = '\\untrusted\share\tool.exe' }, @{ Value = '%SHOWCASE_UNSET_PATH_FIXTURE%\tool' }) {
            param($Value)
            & (Get-Module _setup) {
                param($InputPath)
                $result = ConvertTo-SetupPath $InputPath
                $result.Path | Should -BeNullOrEmpty
                $result.Reason | Should -Not -BeNullOrEmpty
                $result.OptionalAbsent | Should -BeFalse
            } ($Value.Replace('{NUL}', [string][char]0))
        }
        It 'finds an inactive NVM runtime when node is absent from PATH' {
            $previous = $env:NVM_HOME
            $env:NVM_HOME = 'C:\Synthetic NVM'
            Mock Get-NativeCommandPath -ModuleName _setup { $null }
            Mock Test-Path -ModuleName _setup { $false }
            Mock Test-Path -ModuleName _setup { $true } -ParameterFilter {
                $LiteralPath -in @('C:\Synthetic NVM', 'C:\Synthetic NVM\v24.0.0\node.exe')
            }
            Mock Get-ChildItem -ModuleName _setup {
                [pscustomobject]@{ Name = 'v24.0.0'; FullName = 'C:\Synthetic NVM\v24.0.0' }
            }
            Mock Get-Item -ModuleName _setup { [pscustomobject]@{ Attributes = [IO.FileAttributes]::Normal } }
            Mock Invoke-NativeCommand -ModuleName _setup { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; Output = 'v24.0.0' } }
            Mock Get-LocalInstallation -ModuleName _setup { @() }
            Mock Get-SetupPackage -ModuleName _setup {
                [pscustomobject]@{ Id = 'OpenJS.NodeJS.LTS'; Command = 'node'
                    Args = @('--version'); Required = '^v24\.'; Product = '^Node'; Paths = @() }
            }
            Mock Invoke-SetupNative -ModuleName _setup {}
            Mock Invoke-SetupReadiness -ModuleName _setup {}
            try {
                $result = Get-SetupInventory ([pscustomobject]@{ Id = 'OpenJS.NodeJS.LTS'; Command = 'node'
                    Args = @('--version'); Required = '^v24\.'; Product = '^Node'; Paths = @() }) @()
                $result.State | Should -Be 'Installed'
                $result.Compatible | Should -BeTrue
                $result.Path | Should -Be 'C:\Synthetic NVM\v24.0.0\node.exe'
                Invoke-SetupModule -Module Core -Apply -Confirm:$false | Should -Be 0
                Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
                Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
            } finally { $env:NVM_HOME = $previous }
        }
    }
    It 'finds already-installed PowerShell 7 despite a stale PATH miss' {
        $global:SetupFixturePackage.Command = 'pwsh'
        $global:SetupFixturePackage.Paths = @('C:\existing\PowerShell\7\pwsh.exe')
        $global:SetupFixturePackage.Required = '^7\.'
        Mock Get-NativeCommandPath -ModuleName _setup { $null }
        Mock Test-Path -ModuleName _setup { $true } -ParameterFilter { $LiteralPath -eq 'C:\existing\PowerShell\7\pwsh.exe' }
        Mock Invoke-NativeCommand -ModuleName _setup { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; Output = '7.5.4' } }
        $result = Get-SetupInventory $global:SetupFixturePackage @()
        $result.State | Should -Be 'Installed'
        $result.Compatible | Should -BeTrue
        $result.Path | Should -Be 'C:\existing\PowerShell\7\pwsh.exe'
    }
    It 'a version probe failure is unknown and cannot become missing' {
        Mock Invoke-NativeCommand -ModuleName _setup { [pscustomobject]@{ ExitCode = 5; TimedOut = $false; Output = '' } }
        { Get-SetupInventory $global:SetupFixturePackage @() } | Should -Throw '*unknown*'
    }
    It 'does not treat Windows Store aliases or cached payloads as installations' {
        $global:SetupFixturePackage.Paths = @()
        Mock Get-NativeCommandPath -ModuleName _setup { 'C:\Users\synthetic\AppData\Local\Microsoft\WindowsApps\python.exe' }
        Mock Test-Path -ModuleName _setup { $false }
        Mock Test-Path -ModuleName _setup { $true } -ParameterFilter { $LiteralPath -match '\\WindowsApps\\python.exe$' }
        Get-SetupExecutable $global:SetupFixturePackage @() | Should -BeNullOrEmpty
        Should -Invoke Invoke-NativeCommand -ModuleName _setup -Times 0 -Exactly
    }
}

Describe 'WSL and distro preservation' {
    BeforeEach {
        $global:SetupFixtureWsl = [pscustomobject]@{ Installed = $true; Version = '2.9.3'
            Path = 'synthetic-wsl.exe'; UbuntuInstalled = $true; Distributions = @('Ubuntu', 'my-work')
            Features = @(@{ Name = 'Microsoft-Windows-Subsystem-Linux'; State = 'Enabled' }, @{ Name = 'VirtualMachinePlatform'; State = 'Enabled' }) }
        Mock Get-SetupWslState -ModuleName _setup { $global:SetupFixtureWsl }
        Mock Invoke-SetupNative -ModuleName _setup { throw 'Existing WSL/distro must not update or install.' }
        Mock Invoke-SetupReadiness -ModuleName _setup {}
        Mock Write-ShowcaseMessage -ModuleName _setup {}
    }
    AfterEach { Remove-Variable SetupFixtureWsl -Scope Global }
    It 'existing runtime and Ubuntu skip downloads, update and distro actions' {
        Invoke-SetupModule -Module WSL -Apply -Confirm:$false | Should -Be 0
        Invoke-SetupModule -Module Ubuntu -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
    }
    It 'pending restart and unknown feature state do not install anything' {
        $global:SetupFixtureWsl.Features[0].State = 'EnablePending'
        Invoke-SetupModule -Module WSL -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        Mock Get-SetupWslState -ModuleName _setup { throw 'Feature inventory denied' }
        Invoke-SetupModule -Module WSL -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
    }
    It 'an absent Ubuntu does not download before WSL/features are ready' {
        $global:SetupFixtureWsl.UbuntuInstalled = $false
        $global:SetupFixtureWsl.Installed = $false
        Invoke-SetupModule -Module Ubuntu -Apply -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
    }
}

Describe 'Live progress and entrypoint boundaries' {
    It 'derives Go install and compatibility versions from the sample manifest' {
        $package = @(Get-SetupPackage Go)[0]
        $manifest = Get-Content (Join-Path $script:Repository 'samples\go-fx-rates\go.mod') -Raw
        $manifest | Should -Match ('(?m)^go ' + [regex]::Escape($package.Version) + '\s*$')
        ('go version go' + $package.Version + ' windows/amd64') | Should -Match $package.Required
    }
    It 'streams before completion, drains final stdout/stderr and retains the genuine exit' {
        $global:SetupFixtureOutput = @()
        $global:SetupFixtureClock = [Diagnostics.Stopwatch]::StartNew()
        $global:SetupFixtureTimes = @()
        Mock Write-ShowcaseMessage -ModuleName _setup {
            $global:SetupFixtureOutput += $Message
            $global:SetupFixtureTimes += $global:SetupFixtureClock.ElapsedMilliseconds
        }
        try {
            $result = Invoke-SetupNative (Get-Process -Id $PID).Path @('-NoProfile', '-Command',
                "'fixture progress'; Start-Sleep -Milliseconds 1000; [Console]::Error.WriteLine('fixture stderr'); 'fixture final'; exit 7") 'synthetic-fixture' 300
            $result.ExitCode | Should -Be 7
            ($global:SetupFixtureOutput -join "`n") | Should -Match 'fixture progress'
            ($global:SetupFixtureOutput -join "`n") | Should -Match 'fixture stderr'
            ($global:SetupFixtureOutput -join "`n") | Should -Match 'fixture final'
            $global:SetupFixtureOutput.Count | Should -Be 3
            ($global:SetupFixtureTimes[-1] - $global:SetupFixtureTimes[0]) | Should -BeGreaterThan 500
        } finally { Remove-Variable SetupFixtureOutput, SetupFixtureClock, SetupFixtureTimes -Scope Global }
    }
    It 'default bootstrap is a preview and legacy bundle requires explicit opt-in and Apply' {
        $text = Get-Content (Join-Path $script:Repository 'scripts\bootstrap.ps1') -Raw
        $text | Should -Match "\[string\]\`$Module = 'Core'"
        $text | Should -Match 'if \(\$LegacyMicrosoftBundle\)'
        $text | Should -Match 'if \(-not \$Apply\)'
        $text | Should -Match 'Invoke-SetupModule -Module \$Module -Apply:\$Apply'
        $text | Should -Not -Match 'aka.ms|winget.*configure|Read-MicrosoftSignedScript'
        $legacy = Get-Content (Join-Path $script:Repository 'scripts\legacy-bootstrap.ps1') -Raw
        $legacy | Should -Match 'Read-MicrosoftSignedScript'
        $legacy | Should -Match 'Get-BaseSetupOutcome'
    }
    It 'has no provider restore, MSI repair inventory, upgrade, prune or preset shortcuts' {
        $text = Get-Content (Join-Path $script:Repository 'scripts\_setup.psm1') -Raw
        $text | Should -Not -Match 'Win32_Product|Save-Module|Install-Module|Install-PackageProvider|--force|--web-download|--unregister|--update|Start-Process'
        $text | Should -Match 'ReadLineAsync'
        $text | Should -Match 'Write-Progress'
        $text | Should -Match '\$process.Kill\(\)'
        $text | Should -Not -Match '\$process.Kill\(\$true\)|Stop-Process|Restart-Computer'
    }
}
