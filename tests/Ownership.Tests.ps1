<#
.SYNOPSIS
Ownership and cleanup regression tests using only TestDrive and runtime mocks.
.DESCRIPTION
No real checkout cleanup, runtime launch, package restore or workstation action.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Repository = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:Repository 'scripts\_ownership.psm1') -Force
    . (Join-Path $script:Repository 'scripts\cleanup.ps1')
}

Describe 'Conservative checkout ownership' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:FixtureRoot
        $gitDirectory = Join-Path $script:FixtureRoot '.git'
        $null = New-Item -ItemType Directory -Path $gitDirectory
        $script:Location = [pscustomobject]@{ Root = $script:FixtureRoot
            Ledger = (Join-Path $script:FixtureRoot '.showcase-owned.json')
            Anchor = (Join-Path $gitDirectory 'showcase-ownership.json')
            Lock = (Join-Path $gitDirectory 'showcase-operation.lock') }
        $global:ShowcaseFixtureLocation = $script:Location
        Mock Get-OwnershipLocation -ModuleName _ownership { $global:ShowcaseFixtureLocation }
        Mock Get-NativeCommandPath -ModuleName _ownership { 'synthetic-git.exe' }
        Mock Invoke-NativeCommand -ModuleName _ownership {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; Output = ''; TimedOut = $false }
        }
        Mock Write-ShowcaseMessage {}
    }
    AfterEach { Remove-Variable ShowcaseFixtureLocation -Scope Global }

    It 'has no effects without historical ownership metadata' {
        Invoke-ShowcaseCleanup | Should -Be 0
        Test-Path -LiteralPath $script:Location.Ledger | Should -BeFalse
        Test-Path -LiteralPath $script:Location.Anchor | Should -BeFalse
        Test-Path -LiteralPath $script:Location.Lock | Should -BeFalse
    }

    It 'records only a newly absent selected report, not existing outputs or environments' {
        $artifacts = Join-Path $script:FixtureRoot 'artifacts'
        $null = New-Item -ItemType Directory -Path $artifacts
        [IO.File]::WriteAllText((Join-Path $artifacts 'powershell-coverage.xml'), 'pre-existing')
        $context = Enter-ShowcaseOperation -OutputPaths @('artifacts\pester.xml', 'artifacts\powershell-coverage.xml')
        [IO.File]::WriteAllText((Join-Path $artifacts 'pester.xml'), 'generated')
        [IO.File]::WriteAllText((Join-Path $artifacts 'my-notes.txt'), 'user notes')
        Exit-ShowcaseOperation $context -Record
        $receipt = Get-OwnershipReceipt $script:Location
        @($receipt.Files).Count | Should -Be 1
        $receipt.Files[0].Path | Should -Be 'artifacts\pester.xml'
        Invoke-ShowcaseCleanup | Should -Be 0
        Invoke-ShowcaseCleanup -Apply -WhatIf | Should -Be 0
        Test-Path -LiteralPath (Join-Path $artifacts 'pester.xml') | Should -BeTrue
        Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 0
        Test-Path -LiteralPath (Join-Path $artifacts 'pester.xml') | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $artifacts 'powershell-coverage.xml') | Should -Be 'pre-existing'
        Get-Content -LiteralPath (Join-Path $artifacts 'my-notes.txt') | Should -Be 'user notes'
        Test-Path -LiteralPath $artifacts | Should -BeTrue
        $context = Enter-ShowcaseOperation -OutputPaths @('artifacts\pester.xml')
        [IO.File]::WriteAllText((Join-Path $artifacts 'pester.xml'), 'next generated report')
        Exit-ShowcaseOperation $context -Record
        Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 0
        Test-Path -LiteralPath (Join-Path $artifacts 'pester.xml') | Should -BeFalse
    }

    It 'retains changed and replaced reports, including an identical replacement' {
        $artifacts = Join-Path $script:FixtureRoot 'artifacts'
        $null = New-Item -ItemType Directory -Path $artifacts
        $path = Join-Path $artifacts 'pester.xml'
        $context = Enter-ShowcaseOperation -OutputPaths @('artifacts\pester.xml')
        [IO.File]::WriteAllText($path, 'generated')
        Exit-ShowcaseOperation $context -Record
        [IO.File]::WriteAllText($path, 'user changed')
        Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 0
        Get-Content -LiteralPath $path | Should -Be 'user changed'
        Move-Item -LiteralPath $path -Destination (Join-Path $artifacts 'saved-user-copy.xml')
        [IO.File]::WriteAllText($path, 'generated')
        Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 0
        Test-Path -LiteralPath $path | Should -BeTrue
    }

    It 'rejects absolute, traversal, shared tools and unknown paths' -TestCases @(
        @{ Path = '..\outside.xml' }, @{ Path = 'C:\Users\other\.copilot\state' },
        @{ Path = '.copilot\cache' }, @{ Path = '.tools\powershell\Pester.psd1' },
        @{ Path = 'samples\python-emi-api\.venv\pyvenv.cfg' }, @{ Path = 'artifacts\user-notes.xml' },
        @{ Path = 'AppData\Local\cache' }, @{ Path = '.git\config' }) {
        param($Path)
        { Assert-OwnedPath $script:FixtureRoot $Path } | Should -Throw '*exact allowed*'
    }

    It 'rejects tracked outputs rather than discarding staged or source work' {
        Mock Invoke-NativeCommand -ModuleName _ownership {
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; Output = ''; TimedOut = $false }
        }
        { Assert-OwnedPath $script:FixtureRoot 'artifacts\pester.xml' } | Should -Throw '*Tracked output*'
    }

    It 'rejects tampered receipts and receipts copied to another checkout' {
        $context = Enter-ShowcaseOperation
        Exit-ShowcaseOperation $context
        [IO.File]::AppendAllText($script:Location.Ledger, ' ')
        { Get-OwnershipReceipt $script:Location } | Should -Throw '*metadata changed*'
    }
    It 'does not overwrite metadata tampered during an active operation' {
        $context = Enter-ShowcaseOperation
        [IO.File]::AppendAllText($script:Location.Ledger, ' ')
        try { { Save-OwnershipReceipt $context } | Should -Throw '*metadata changed*' }
        finally { Exit-ShowcaseOperation $context }
    }
    It 'records explicit legacy containers without making legacy a default workflow' {
        $context = Enter-ShowcaseOperation
        try { Register-ShowcaseContainer -Id ('b' * 64) -Name 'win11-demo-java-legacy-upgrade' -Runtime docker }
        finally { Exit-ShowcaseOperation $context }
        (Get-OwnershipReceipt $script:Location).Containers[0].Name | Should -Be 'win11-demo-java-legacy-upgrade'
    }

    It 'rejects a relocated receipt even when its anchor hash matches' {
        $context = Enter-ShowcaseOperation
        Exit-ShowcaseOperation $context
        $receipt = Get-Content -LiteralPath $script:Location.Ledger -Raw | ConvertFrom-Json
        $receipt.Root = 'C:\another-checkout'
        [IO.File]::WriteAllText($script:Location.Ledger, (ConvertTo-Json $receipt))
        $anchor = Get-Content -LiteralPath $script:Location.Anchor -Raw | ConvertFrom-Json
        $anchor.Hash = (Get-FileHash -LiteralPath $script:Location.Ledger).Hash
        [IO.File]::WriteAllText($script:Location.Anchor, (ConvertTo-Json $anchor))
        { Get-OwnershipReceipt $script:Location } | Should -Throw '*different checkout*'
    }

    It 'refuses nested repositories and reparse-point output parents' {
        $artifacts = Join-Path $script:FixtureRoot 'artifacts'
        $null = New-Item -ItemType Directory -Path (Join-Path $artifacts '.git')
        { Assert-OwnedPath $script:FixtureRoot 'artifacts\pester.xml' } | Should -Throw '*Nested repository*'
        Mock Get-Item -ModuleName _ownership {
            [pscustomobject]@{ Attributes = [IO.FileAttributes]::ReparsePoint; PSIsContainer = $true }
        } -ParameterFilter { $LiteralPath -eq $artifacts }
        { Assert-OwnedPath $script:FixtureRoot 'artifacts\pester.xml' } | Should -Throw '*Reparse*'
    }

    It 'rejects active operation locks before any cleanup effect' {
        $context = Enter-ShowcaseOperation
        try { Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 1 }
        finally { Exit-ShowcaseOperation $context }
    }

    It 'rejects a locked report before deleting another eligible report' {
        $artifacts = Join-Path $script:FixtureRoot 'artifacts'
        $null = New-Item -ItemType Directory -Path $artifacts
        $context = Enter-ShowcaseOperation -OutputPaths @('artifacts\pester.xml', 'artifacts\powershell-coverage.xml')
        foreach ($name in @('pester.xml', 'powershell-coverage.xml')) {
            [IO.File]::WriteAllText((Join-Path $artifacts $name), 'generated')
        }
        Exit-ShowcaseOperation $context -Record
        $locked = [IO.File]::Open((Join-Path $artifacts 'powershell-coverage.xml'), 'Open', 'Read', 'None')
        try {
            Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 1
            Test-Path -LiteralPath (Join-Path $artifacts 'pester.xml') | Should -BeTrue
        } finally { $locked.Dispose() }
    }

    It 'rejects hardlinked outputs without touching either path' {
        $artifacts = Join-Path $script:FixtureRoot 'artifacts'
        $null = New-Item -ItemType Directory -Path $artifacts
        $path = Join-Path $artifacts 'pester.xml'
        [IO.File]::WriteAllText($path, 'user data')
        $null = New-Item -ItemType HardLink -Path (Join-Path $artifacts 'other.xml') -Target $path
        { Open-OwnedOutput $path } | Should -Throw '*Hardlink*'
        Get-Content -LiteralPath $path | Should -Be 'user data'
    }
    It 'refuses deletion through a locked handle whose final path is not the approved path' {
        $artifacts = Join-Path $script:FixtureRoot 'artifacts'
        $null = New-Item -ItemType Directory -Path $artifacts
        $path = Join-Path $artifacts 'pester.xml'
        [IO.File]::WriteAllText($path, 'generated')
        $handle = Open-OwnedOutput $path
        try {
            { Remove-OwnedOutput $handle (Join-Path $artifacts 'another.xml') -Confirm:$false } |
                Should -Throw '*moved*'
        } finally { $handle.Dispose() }
        Get-Content -LiteralPath $path | Should -Be 'generated'
    }
}

Describe 'Container identity and cleanup contracts' {
    BeforeEach {
        $script:Container = [pscustomobject]@{ Id = ('b' * 64); Name = 'win11-demo-python-emi-api'; Runtime = 'docker' }
        $script:Inspection = [pscustomobject]@{ Id = ('b' * 64); Name = '/win11-demo-python-emi-api'
            Config = @{ Labels = @{ 'io.win11-dev-workstation.workspace' = ('a' * 32)
                'io.win11-dev-workstation.showcase' = 'true' } } }
        $global:ShowcaseFixtureInspection = $script:Inspection
        Mock Invoke-NativeCommand -ModuleName _ownership {
            [pscustomobject]@{ ExitCode = 0; StdOut = (ConvertTo-Json -InputObject @($global:ShowcaseFixtureInspection) -Depth 5)
                Output = ''; TimedOut = $false }
        }
    }
    AfterEach { Remove-Variable ShowcaseFixtureInspection -Scope Global }
    It 'matches only exact ID, name and workspace labels' {
        Test-OwnedContainer $script:Container ('a' * 32) @{ Path = 'synthetic-runtime.exe' } | Should -BeTrue
        $script:Inspection.Id = 'c' * 64
        Test-OwnedContainer $script:Container ('a' * 32) @{ Path = 'synthetic-runtime.exe' } | Should -BeFalse
        $script:Inspection.Id = 'b' * 64
        $script:Inspection.Name = '/another-name'
        Test-OwnedContainer $script:Container ('a' * 32) @{ Path = 'synthetic-runtime.exe' } | Should -BeFalse
        $script:Inspection.Name = '/win11-demo-python-emi-api'
        Test-OwnedContainer $script:Container ('c' * 32) @{ Path = 'synthetic-runtime.exe' } | Should -BeFalse
        $script:Inspection.Config.Labels.Remove('io.win11-dev-workstation.workspace')
        Test-OwnedContainer $script:Container ('a' * 32) @{ Path = 'synthetic-runtime.exe' } | Should -BeFalse
    }
    It 'surfaces runtime denial without fallback' {
        Mock Invoke-NativeCommand -ModuleName _ownership {
            [pscustomobject]@{ ExitCode = 5; StdOut = ''; Output = 'Denied'; TimedOut = $false }
        }
        { Test-OwnedContainer $script:Container ('a' * 32) @{ Path = 'synthetic-runtime.exe' } } | Should -Throw
        Should -Invoke Invoke-NativeCommand -ModuleName _ownership -Times 1 -Exactly
    }
    It 'does not inspect containers unless separately opted in' {
        Mock Enter-ShowcaseOperation {
            [pscustomobject]@{ Receipt = @{ Files = @(); Containers = @($script:Container); Workspace = ('a' * 32) }; Handle = $null }
        }
        Mock Exit-ShowcaseOperation {}
        Mock Save-OwnershipReceipt {}
        Mock Get-ContainerRuntime { throw 'Default cleanup must not select a runtime.' }
        Invoke-ShowcaseCleanup -Apply -Confirm:$false | Should -Be 0
        Should -Invoke Get-ContainerRuntime -Times 0 -Exactly
    }
    It 'retains mismatched containers and stops only exact IDs on explicit apply' {
        Mock Enter-ShowcaseOperation {
            [pscustomobject]@{ Receipt = @{ Files = @(); Containers = @($script:Container); Workspace = ('a' * 32) }; Handle = $null }
        }
        Mock Exit-ShowcaseOperation {}
        Mock Save-OwnershipReceipt {}
        Mock Write-ShowcaseMessage {}
        Mock Get-ContainerRuntime { [pscustomobject]@{ Name = 'docker'; Path = 'synthetic-runtime.exe' } }
        Mock Test-OwnedContainer { $false }
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; Output = ''; TimedOut = $false }
        }
        Invoke-ShowcaseCleanup -Apply -IncludeContainers -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
        Mock Test-OwnedContainer { $true }
        Invoke-ShowcaseCleanup -Apply -IncludeContainers -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-NativeCommand -Times 2 -Exactly -ParameterFilter {
            $ArgumentList.Count -eq 2 -and $ArgumentList[0] -in @('stop', 'rm') -and $ArgumentList[1] -ceq ('b' * 64)
        }
    }
    It 'fails closed on a recorded runtime mismatch without stopping anything' {
        Mock Enter-ShowcaseOperation {
            [pscustomobject]@{ Receipt = @{ Files = @(); Containers = @($script:Container); Workspace = ('a' * 32) }; Handle = $null }
        }
        Mock Exit-ShowcaseOperation {}
        Mock Write-ShowcaseMessage {}
        Mock Get-ContainerRuntime { [pscustomobject]@{ Name = 'wslc'; Path = 'synthetic-runtime.exe' } }
        Mock Invoke-NativeCommand { throw 'Must not stop a mismatched runtime.' }
        Invoke-ShowcaseCleanup -Apply -IncludeContainers -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }
    It 'has no uninstallation, broad deletion, Git reset, cloud or pruning command' {
        $text = Get-Content (Join-Path $script:Repository 'scripts\cleanup.ps1') -Raw
        $text | Should -Not -Match 'Remove-Item|demo-reset\.ps1|git restore|git clean|@\(''prune''|winget uninstall|az delete'
        $text | Should -Match 'SupportsShouldProcess'
        $text | Should -Not -Match '\[switch\]\$Force'
        $tasks = Get-Content (Join-Path $script:Repository '.vscode\tasks.json') -Raw | ConvertFrom-Json
        ($tasks.tasks | Where-Object label -eq 'Cleanup preview').args | Should -Not -Contain '-Apply'
        ($tasks.tasks | Where-Object label -eq 'Cleanup generated resources').args | Should -Contain '-Apply'
        ($tasks.tasks | Where-Object label -eq 'Cleanup generated resources').args | Should -Contain '-Confirm'
    }
}
