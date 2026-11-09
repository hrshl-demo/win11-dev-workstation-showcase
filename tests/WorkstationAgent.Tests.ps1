<#
.SYNOPSIS
Parse local VS Code agent recipes without invoking a workstation action.
.DESCRIPTION
Runs under both hosted PowerShell engines. Recipes are never invoked.
The child fixture extracts only function definitions and substitutes every
workstation/runtime/provider/application operation with synthetic functions.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $repository = Split-Path -Parent $PSScriptRoot
    $text = Get-Content -LiteralPath (Join-Path $repository '.github\agents\workstation-setup.agent.md') -Raw
    $script:RecipeAsts = @()
    $script:RecipeErrors = @()
    $script:NativeFixture = Join-Path $repository 'tests\fixtures\native-readiness.ps1'
    $script:RepositoryRoot = $repository
    foreach ($match in [regex]::Matches($text, '(?s)```powershell\r?\n(.*?)\r?\n```')) {
        $tokens = $null
        $errors = $null
        $script:RecipeAsts += [Management.Automation.Language.Parser]::ParseInput(
            $match.Groups[1].Value, [ref]$tokens, [ref]$errors)
        $script:RecipeErrors += @($errors)
    }

    Describe 'Native Extensions installed-first acquisition with isolated fixtures' {
        BeforeAll {
            Import-Module (Join-Path $script:RepositoryRoot 'scripts\_setup.psm1') -Force
            $script:NativeIds = @((Get-NativeDemoRequirement).Extensions)
        }
        BeforeEach {
            $global:NativeExtensionRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path (Join-Path $global:NativeExtensionRoot '.vscode') -Confirm:$false
            Copy-Item (Join-Path $script:RepositoryRoot '.vscode\extensions.json') (Join-Path $global:NativeExtensionRoot '.vscode\extensions.json') -Confirm:$false
            $global:NativeInstalledIds = @($script:NativeIds)
            $global:NativeBadInventory = $false
            Mock Get-ShowcaseRoot -ModuleName _setup { $global:NativeExtensionRoot }
            Mock Get-LocalInstallation -ModuleName _setup { throw 'Native extensions must not inventory other packages.' }
            Mock Get-NativeCommandPath -ModuleName _setup { 'synthetic-code.exe' }
            Mock Invoke-NativeCommand -ModuleName _setup {
                $text = if ($global:NativeBadInventory) { 'unknown inventory' }
                else { ($global:NativeInstalledIds | ForEach-Object { "$_@1.2.3" }) -join "`n" }
                [pscustomobject]@{ ExitCode = 0; StdOut = $text; StdErr = ''; Output = $text }
            }
            Mock Invoke-SetupReadiness -ModuleName _setup {}
            Mock Assert-WorkstationPolicy -ModuleName _setup {}
            Mock Write-ShowcaseMessage -ModuleName _setup {}
            Mock Invoke-SetupNative -ModuleName _setup {
                $global:NativeInstalledIds += $Arguments[1]
                [pscustomobject]@{ ExitCode = 0; ElapsedSeconds = 1 }
            }
        }
        AfterEach {
            Remove-Variable NativeExtensionRoot, NativeInstalledIds, NativeBadInventory -Scope Global
        }
        It 'retains all installed Native IDs without provider or installer activity' {
            Invoke-SetupModule -Module Extensions -NativeDemo -Apply -Confirm:$false | Should -Be 0
            Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
            Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
            Should -Invoke Get-LocalInstallation -ModuleName _setup -Times 0 -Exactly
        }
        It 'acquires only missing debugpy after attestation and Native readiness, then rechecks the Native selection' {
            $global:NativeInstalledIds = @($global:NativeInstalledIds | Where-Object { $_ -ne 'ms-python.debugpy' })
            Invoke-SetupModule -Module Extensions -NativeDemo -Apply -ExtensionSourceApproved -Confirm:$false | Should -Be 0
            Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 1 -Exactly -ParameterFilter { $NativeDemo }
            Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 1 -Exactly -ParameterFilter {
                $Arguments.Count -eq 2 -and $Arguments[0] -eq '--install-extension' -and $Arguments[1] -eq 'ms-python.debugpy'
            }
            @(Get-SetupExtension -NativeDemo | Where-Object State -ne Installed).Count | Should -Be 0
            @(Get-SetupExtension).Count | Should -Be 12
        }
        It 'stops missing targets without source approval and unknown inventory before any source activity' {
            $global:NativeInstalledIds = @($global:NativeInstalledIds | Where-Object { $_ -ne 'ms-python.debugpy' })
            Invoke-SetupModule -Module Extensions -NativeDemo -Apply -Confirm:$false | Should -Be 1
            $global:NativeBadInventory = $true
            Invoke-SetupModule -Module Extensions -NativeDemo -Apply -ExtensionSourceApproved -Confirm:$false | Should -Be 1
            Should -Invoke Invoke-SetupReadiness -ModuleName _setup -Times 0 -Exactly
            Should -Invoke Invoke-SetupNative -ModuleName _setup -Times 0 -Exactly
        }
    }
}

Describe 'Workstation setup agent recipe syntax' {
    It 'parses every recipe under the selected PowerShell engine without execution' {
        $script:RecipeAsts.Count | Should -Be 9
        $script:RecipeErrors.Count | Should -Be 0
    }

    Describe 'Source-backed Native continuation with no workstation queries' {
        It 'rejects malformed/incomplete/required-runtime reports and binds Native recipes using only synthetic functions' {
            $engine = (Get-Process -Id $PID).Path
            $output = @(& $engine -NoProfile -File $script:NativeFixture -RepositoryRoot $script:RepositoryRoot)
            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -Match 'rejects malformed JSON'
            ($output -join "`n") | Should -Match 'rejects incompatible-native-java; Native exit 1'
            ($output -join "`n") | Should -Match 'positive inventory/profile/safety and exact exit 0'
            ($output -join "`n") | Should -Match 'Native 18/18 PASS and exit 0 independently'
            ($output -join "`n") | Should -Match 'five-ID Extensions inventory/dispatcher binding'
            ($output -join "`n") | Should -Match 'RunLocal Go/8082 binds Container=false'
        }
    }

    It 'contains only existing dispatcher, readiness and loopback request commands' {
        $count = 0
        foreach ($ast in $script:RecipeAsts) {
            foreach ($command in $ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.CommandAst]
            }, $true)) {
                $name = $command.GetCommandName()
                @('powershell.exe', 'Invoke-RestMethod') | Should -Contain $name
                $command.Redirections.Count | Should -Be 0
                if ($name -eq 'powershell.exe') {
                    $command.CommandElements[1].Extent.Text | Should -Be '-NoProfile'
                    $command.CommandElements[2].Extent.Text | Should -Be '-File'
                    @('.\scripts\developer.ps1', '.\scripts\preflight.ps1', '.\scripts\verify.ps1') |
                        Should -Contain $command.CommandElements[3].Extent.Text
                }
                $count++
            }
        }
        $count | Should -Be 23
    }

    It 'does not pipeline approval answers or batch commands into hidden expressions' {
        foreach ($ast in $script:RecipeAsts) {
            $pipelines = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.PipelineAst]
            }, $true))
            foreach ($pipeline in $pipelines) {
                $pipeline.PipelineElements.Count | Should -Be 1
            }
            @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.LoopStatementAst] -or
                $node -is [Management.Automation.Language.ScriptBlockExpressionAst]
            }, $true)).Count | Should -Be 0
        }
    }
}
