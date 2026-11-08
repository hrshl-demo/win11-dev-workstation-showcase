<#
.SYNOPSIS
Parse local VS Code agent recipes without invoking a workstation action.
.DESCRIPTION
Runs under both hosted PowerShell engines. Reading and AST parsing only;
the existing setup/developer fixtures test their real gates with mocks.
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
    foreach ($match in [regex]::Matches($text, '(?s)```powershell\r?\n(.*?)\r?\n```')) {
        $tokens = $null
        $errors = $null
        $script:RecipeAsts += [Management.Automation.Language.Parser]::ParseInput(
            $match.Groups[1].Value, [ref]$tokens, [ref]$errors)
        $script:RecipeErrors += @($errors)
    }
}

Describe 'Workstation setup agent recipe syntax' {
    It 'parses every recipe under the selected PowerShell engine without execution' {
        $script:RecipeAsts.Count | Should -Be 8
        $script:RecipeErrors.Count | Should -Be 0
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
        $count | Should -Be 22
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
