<#
.SYNOPSIS
Safe mocked contracts for the user-run developer dispatcher and VS Code tasks.
.DESCRIPTION
The guarded dispatcher is dot-sourced to allow real Pester code coverage.
Dot-sourcing imports definitions only, not an action. No setup, restore, server,
container, deployment or toolchain entry point is executed.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Repository = Split-Path -Parent $PSScriptRoot
    $script:DeveloperPath = Join-Path $script:Repository 'scripts\developer.ps1'
    $tokens = $null
    $errors = $null
    $script:DeveloperAst = [Management.Automation.Language.Parser]::ParseFile(
        $script:DeveloperPath, [ref]$tokens, [ref]$errors)
    $script:ParseErrors = @($errors)
    . $script:DeveloperPath -Action Test -Sample All
    $script:Tasks = Get-Content (Join-Path $script:Repository '.vscode\tasks.json') -Raw | ConvertFrom-Json
    $script:Launch = Get-Content (Join-Path $script:Repository '.vscode\launch.json') -Raw | ConvertFrom-Json
}

Describe 'Developer script and VS Code contracts' {
    It 'offers HTTPS timeout choices only for readiness/setup tasks with a five-second default' {
        $timeoutInput = $script:Tasks.inputs | Where-Object id -eq httpsTimeoutSeconds
        $timeoutInput.default | Should -Be '5'
        @($timeoutInput.options) | Should -Be @('5', '15', '30')
        foreach ($task in $script:Tasks.tasks) {
            $hasChoice = $task.args -contains '${input:httpsTimeoutSeconds}'
            $hasChoice | Should -Be ($task.label -in @('Preflight', 'Setup preview', 'User-run setup', 'Finish setup'))
            if ($hasChoice) { $task.args | Should -Contain '-HttpsTimeoutSeconds' }
        }
    }
    It 'parses in Windows PowerShell with approved function verbs' {
        $script:ParseErrors.Count | Should -Be 0
        $approved = (Get-Verb).Verb
        foreach ($definition in $script:DeveloperAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
        }, $false)) {
            $approved | Should -Contain ($definition.Name -split '-')[0]
        }
        $script:DeveloperAst.Extent.Text | Should -Match 'Set-StrictMode -Version Latest'
        $script:DeveloperAst.Extent.Text | Should -Not -Match 'Invoke-Expression|ExecutionPolicy\s+(Bypass|Unrestricted)|Install-PackageProvider|Install-Module'
        $script:DeveloperAst.Extent.Text | Should -Not -Match '\$home\s*='
    }

    It 'excludes legacy from All' {
        @(Get-DeveloperSample All).Count | Should -Be 4
        @(Get-DeveloperSample All) | Should -Not -Contain 'Legacy'
        @(Get-DeveloperSample Legacy) | Should -Contain 'Legacy'
    }

    It 'uses process arguments without automatic tasks or F5 restore' {
        foreach ($task in $script:Tasks.tasks) {
            $task.type | Should -Be 'process'
            $task.command | Should -Be 'powershell.exe'
            $task.args | Should -Not -Contain '-ExecutionPolicy'
            $task.PSObject.Properties.Name | Should -Not -Contain 'runOptions'
        }
        foreach ($launch in $script:Launch.configurations) {
            $launch.PSObject.Properties.Name | Should -Not -Contain 'preLaunchTask'
        }
        ($script:Launch.configurations | Where-Object type -eq debugpy).python |
            Should -Match '\.venv\\Scripts\\python.exe$'
    }

    It 'requires confirmation on all user-run mutation tasks' {
        foreach ($task in $script:Tasks.tasks | Where-Object {
            $_.args -contains 'Restore' -or $_.args -contains 'Setup' -or
            $_.args -contains 'FinishSetup' -or $_.args -contains 'RunLocal' -or
            $_.args -contains 'RunContainer' -or $_.args -contains 'DeployDispatch' -or
            $_.args -contains 'KubernetesPortForward'
        }) { $task.args | Should -Contain '-Confirm' }
        $reset = $script:Tasks.tasks | Where-Object label -eq 'Reset demo'
        $reset.args | Should -Contain '-Confirm'
        $reset.args | Should -Contain '${workspaceFolder}\scripts\demo-reset.ps1'
    }

    It 'builds images only through explicit Restore, never during Run' {
        $launch = $script:DeveloperAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Start-DeveloperSample'
        }, $false)
        $launch.Extent.Text | Should -Not -Match "@\('build'"
        $launch.Extent.Text | Should -Match "--pull=never"
        $launch.Extent.Text | Should -Match "'image', 'inspect'"
    }

    It 'preserves four container Dockerfile tasks without making legacy default' {
        @($script:Tasks.tasks | Where-Object { $_.args -contains 'RunContainer' }).Count | Should -Be 4
        ($script:Tasks.tasks | Where-Object label -eq 'Test all samples').args | Should -Contain 'All'
    }
}

Describe 'Developer safe execution and failure paths' {
    BeforeEach {
        Mock Write-ShowcaseMessage {}
        Mock Invoke-NativeCommand { throw 'Unexpected native execution in safe test.' }
        Mock Get-NativeCommandPath { throw 'Unexpected tool lookup in safe test.' }
        Mock Get-DeveloperDirectory { $script:Repository }
        Mock New-Item { throw 'Unexpected filesystem mutation in safe test.' }
    }
    It 'propagates slow-network timeout and bounded budget to read-only child preflight' {
        Mock Invoke-DeveloperNative { [pscustomobject]@{ ExitCode = 0 } }
        Invoke-Developer -Action Preflight -HttpsTimeoutSeconds 30 | Should -Be 0
        Should -Invoke Invoke-DeveloperNative -Times 1 -Exactly -ParameterFilter {
            $TimeoutSeconds -eq 663 -and $Arguments[-2] -eq '-HttpsTimeoutSeconds' -and $Arguments[-1] -eq '30'
        }
    }
    It 'propagates the timeout through setup and finish using a harmless in-memory child fixture' -TestCases @(
        @{ SelectedAction = 'Setup' }, @{ SelectedAction = 'FinishSetup' }
    ) {
        param($SelectedAction)
        function Invoke-SetupFixture {
            $script:CapturedSetupArguments = @($args)
            $global:LASTEXITCODE = 0
        }
        Mock Get-Process { [pscustomobject]@{ Path = 'Invoke-SetupFixture' } }
        Invoke-Developer -Action $SelectedAction -HttpsTimeoutSeconds 30 -Confirm:$false | Should -Be 0
        $script:CapturedSetupArguments | Should -Contain '-HttpsTimeoutSeconds'
        $script:CapturedSetupArguments | Should -Contain '30'
        ($script:CapturedSetupArguments -contains '-SkipBase') | Should -Be ($SelectedAction -eq 'FinishSetup')
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }
    It 'rejects out-of-range HTTPS timeout without dispatching any native task' {
        { Invoke-Developer -Action Preflight -HttpsTimeoutSeconds 31 } | Should -Throw
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'reports native readiness failure once without a dependency Restore hint' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 1; TimedOut = $false; Output = '[FAIL] HTTPS: Timeout; attempts: 3/3' }
        }
        { Invoke-DeveloperNative -Path 'synthetic' -Arguments @('Preflight') } | Should -Throw '*Developer task failed*'
        Should -Invoke Write-ShowcaseMessage -Times 1 -Exactly -ParameterFilter { $Message -match 'HTTPS: Timeout' }
        $script:DeveloperAst.Extent.Text | Should -Not -Match 'Developer task \(missing cached dependencies'
    }

    It 'shows source/config only without invoking bootstrap, even with WhatIf' {
        Mock Get-Content { 'synthetic source preview' }
        Invoke-Developer -Action SetupPreview -WhatIf | Should -Be 0
        Should -Invoke Get-Content -Times 3 -Exactly
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'makes WhatIf a no-op for restoration and checks' {
        Invoke-Developer -Action Restore -Sample All -WhatIf | Should -Be 0
        Invoke-Developer -Action Restore -RestoreTarget ContainerImages -Sample All -WhatIf | Should -Be 0
        Invoke-Developer -Action Coverage -Sample All -WhatIf | Should -Be 0
        Should -Invoke Get-NativeCommandPath -Times 0 -Exactly
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
    }

    It 'refuses unsafe source SHA before any CLI invocation' {
        Invoke-Developer -Action DeployDispatch -SourceSha 'main & calc.exe' -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'refuses stale main instead of dispatching' {
        Mock Get-DeveloperTool { 'synthetic-gh.exe' }
        Mock Invoke-DeveloperNative {
            [pscustomobject]@{ StdOut = ('b' * 40); Output = ''; ExitCode = 0 }
        }
        Invoke-Developer -Action DeployDispatch -SourceSha ('a' * 40) -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-DeveloperNative -Times 1 -Exactly
    }

    It 'uses only main and a validated source_sha CLI field' {
        Mock Get-DeveloperTool { 'synthetic-gh.exe' }
        Mock Invoke-DeveloperNative {
            [pscustomobject]@{ StdOut = ('a' * 40); Output = ''; ExitCode = 0 }
        }
        Invoke-Developer -Action DeployDispatch -SourceSha ('a' * 40) -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-DeveloperNative -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'deploy-aks.yml' -and $Arguments -contains 'main' -and
            $Arguments -contains ('source_sha=' + ('a' * 40)) -and $Arguments -notcontains 'feature'
        }
    }

    It 'rejects unsafe namespace rather than interpolating a shell command' {
        { Invoke-DeveloperCluster -Action KubernetesLogs -Sample Python -Namespace 'demo;calc' -Port 8080 } |
            Should -Throw
        Should -Invoke Get-NativeCommandPath -Times 0 -Exactly
    }

    It 'keeps fixed deployment names and bounded logs' {
        Mock Get-DeveloperTool { 'synthetic-kubectl.exe' }
        Mock Invoke-DeveloperNative {}
        Invoke-DeveloperCluster -Action KubernetesLogs -Sample Java -Namespace 'approved-demo' -Port 8080
        Should -Invoke Invoke-DeveloperNative -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'deployment/ifsc' -and $Arguments -contains '--tail=100'
        }
    }

    It 'fails clearly instead of restoring an absent Python environment' {
        Mock Test-Path { $false }
        { Get-DeveloperPython $script:Repository } | Should -Throw '*NOT RUN*'
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'refuses a missing container image without building or pulling it' {
        Mock Assert-WorkstationPolicy {}
        Mock Get-ContainerRuntime { [pscustomobject]@{ Name = 'docker'; Path = 'synthetic-docker.exe' } }
        Mock Invoke-NativeCommand { [pscustomobject]@{ ExitCode = 1; StdOut = ''; Output = '' } }
        Mock Invoke-DeveloperNative { throw 'Run must not execute for a missing image.' }
        { Start-DeveloperSample -Sample Python -Container -Runtime docker -Port 8080 -Confirm:$false } |
            Should -Throw '*Restore -RestoreTarget ContainerImages*'
        Should -Invoke Invoke-DeveloperNative -Times 0 -Exactly
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter {
            $ArgumentList -contains 'image' -and $ArgumentList -contains 'inspect'
        }
    }

    It 'runs an existing image with pull disabled' {
        Mock Assert-WorkstationPolicy {}
        Mock Get-ContainerRuntime { [pscustomobject]@{ Name = 'docker'; Path = 'synthetic-docker.exe' } }
        Mock Invoke-NativeCommand { [pscustomobject]@{ ExitCode = 0; StdOut = ''; Output = '' } }
        Mock Invoke-DeveloperNative { [pscustomobject]@{ StdOut = ('b' * 64) } }
        Mock Get-ShowcaseWorkspace { 'a' * 32 }
        Mock Register-ShowcaseContainer {}
        Mock Wait-SampleHealth {}
        Start-DeveloperSample -Sample Python -Container -Runtime docker -Port 8080 -Confirm:$false
        Should -Invoke Invoke-DeveloperNative -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'run' -and $Arguments -contains '--pull=never' -and
            $Arguments -notcontains 'build' -and $Arguments -notcontains 'pull' -and
            $Arguments -contains ('io.win11-dev-workstation.workspace=' + ('a' * 32))
        }
        Should -Invoke Register-ShowcaseContainer -Times 1 -Exactly -ParameterFilter { $Id -ceq ('b' * 64) }
    }

    It 'does not substitute a global PowerShell module when project pins are absent' {
        Mock Test-Path { $false }
        { Import-DeveloperModule Pester } | Should -Throw '*project-local Pester 5.7.1*'
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'never installs NuGet while restoring modules' {
        Mock Get-PackageProvider { @() }
        { Invoke-DeveloperRestore PowerShell -Confirm:$false } | Should -Throw '*No provider install*'
        Should -Invoke New-Item -Times 0 -Exactly
    }

    It 'requires JAVA_HOME before launching the wrapper' {
        $original = $env:JAVA_HOME
        try {
            [Environment]::SetEnvironmentVariable('JAVA_HOME', $null, 'Process')
            { Get-DeveloperMaven $script:Repository Java } | Should -Throw '*JAVA_HOME*'
        } finally { [Environment]::SetEnvironmentVariable('JAVA_HOME', $original, 'Process') }
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'requires the pinned existing Go toolchain' {
        Mock Get-DeveloperTool { 'synthetic-go.exe' }
        Mock Invoke-DeveloperNative {
            [pscustomobject]@{ StdOut = 'go version go1.26.0 windows/amd64'; Output = ''; ExitCode = 0 }
        }
        { Get-DeveloperGo $script:Repository } | Should -Throw '*Go 1.27.3*'
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'rejects a missing Maven ZIP before the wrapper can restore it' {
        $original = $env:JAVA_HOME
        try {
            $env:JAVA_HOME = $script:Repository
            Mock Test-Path { $LiteralPath -notlike '*.zip' }
            Mock Assert-SafeDirectory {}
            Mock Invoke-DeveloperNative {
                [pscustomobject]@{ StdOut = ''; Output = 'openjdk version "25.0.1"'; ExitCode = 0 }
            }
            { Get-DeveloperMaven $script:Repository Java } | Should -Throw '*ZIP/unpacked wrapper cache*'
        } finally { [Environment]::SetEnvironmentVariable('JAVA_HOME', $original, 'Process') }
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'checks every All member even when one check fails' {
        Mock Invoke-DeveloperCheck { throw 'synthetic missing prerequisite' }
        Invoke-Developer -Action Test -Sample All -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-DeveloperCheck -Times 4 -Exactly
    }

    It 'excludes PowerShell and legacy from All container image restores' {
        Mock Restore-DeveloperImage {}
        Invoke-Developer -Action Restore -RestoreTarget ContainerImages -Sample All -Confirm:$false | Should -Be 0
        Should -Invoke Restore-DeveloperImage -Times 3 -Exactly
        Should -Invoke Restore-DeveloperImage -Times 0 -Exactly -ParameterFilter {
            $Sample -in @('PowerShell', 'Legacy')
        }
    }

    It 'restores process environment after successful or failed checks' {
        $before = @{}
        foreach ($key in @('UV_OFFLINE', 'UV_NO_SYNC', 'UV_PYTHON_DOWNLOADS', 'GOTOOLCHAIN', 'GOPROXY', 'GOSUMDB', 'PORT')) {
            $before[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        }
        Mock Invoke-DeveloperCheck {
            $env:UV_OFFLINE | Should -Be '1'
            $env:UV_NO_SYNC | Should -Be '1'
            $env:UV_PYTHON_DOWNLOADS | Should -Be 'never'
            $env:GOTOOLCHAIN | Should -Be 'local'
            $env:GOPROXY | Should -Be 'off'
            throw 'synthetic failure'
        }
        Invoke-Developer -Action Test -Sample Go -Confirm:$false | Should -Be 1
        foreach ($key in $before.Keys) {
            [Environment]::GetEnvironmentVariable($key, 'Process') | Should -Be $before[$key]
        }
    }
}
