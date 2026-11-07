<#
.SYNOPSIS
Safe Pester 5 checks for script contracts and actual read-only/mock functions.
.DESCRIPTION
Bootstrap and repair entrypoints are never invoked, even with WhatIf.
Function definitions are loaded from their ASTs without executing script bodies.
All external application, runtime, network and Git calls are mocked.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Repository = Split-Path -Parent $PSScriptRoot
    $script:ScriptsDirectory = Join-Path $script:Repository 'scripts'
    Import-Module (Join-Path $script:ScriptsDirectory '_common.psm1') -Force
    $script:Ast = @{}
    foreach ($file in Get-ChildItem -LiteralPath $script:ScriptsDirectory -File) {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $script:Ast[$file.Name] = [pscustomobject]@{ Tree = $ast; Errors = @($errors); Text = $ast.Extent.Text }
        if ($file.Name -in @('preflight.ps1', 'verify.ps1', 'run-sample.ps1', 'demo-reset.ps1', 'repair-winget.ps1')) {
            foreach ($definition in $ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst]
            }, $false)) {
                if ($file.Name -eq 'repair-winget.ps1' -and $definition.Name -ne 'Test-WinGetConfigure') { continue }
                . ([scriptblock]::Create($definition.Extent.Text))
            }
        }
    }
    $script:Recommendations = @(
        'ms-python.python', 'vscjava.vscode-java-pack', 'golang.go',
        'ms-azuretools.vscode-azureresourcegroups', 'ms-azuretools.vscode-azure-github-copilot',
        'ms-azuretools.vscode-bicep', 'ms-azuretools.vscode-containers',
        'ms-vscode-remote.remote-containers', 'ms-vscode-remote.remote-wsl',
        'GitHub.vscode-pull-request-github', 'vscjava.migrate-java-to-azure',
        'ms-vscode.powershell', 'redhat.vscode-yaml'
    )
}

Describe 'PowerShell script structural contracts' {
    It '<File> parses with help, binding, StrictMode and failure handling' -TestCases @(
        @{ File = 'preflight.ps1' }, @{ File = 'bootstrap.ps1' },
        @{ File = 'verify.ps1' }, @{ File = 'repair-winget.ps1' },
        @{ File = 'run-sample.ps1' }, @{ File = 'demo-reset.ps1' },
        @{ File = '_common.psm1' }
    ) {
        param($File)
        $script:Ast[$File].Errors.Count | Should -Be 0
        $script:Ast[$File].Text | Should -Match '\.SYNOPSIS'
        $script:Ast[$File].Text | Should -Match '\[CmdletBinding\('
        $script:Ast[$File].Text | Should -Match 'Set-StrictMode -Version Latest'
        $script:Ast[$File].Text | Should -Match "\`$ErrorActionPreference = 'Stop'"
        if ($File -ne '_common.psm1') { $script:Ast[$File].Text | Should -Match 'exit \(' }
    }
    It '<File> exposes ShouldProcess' -TestCases @(
        @{ File = 'bootstrap.ps1' }, @{ File = 'repair-winget.ps1' },
        @{ File = 'run-sample.ps1' }, @{ File = 'demo-reset.ps1' }
    ) {
        param($File)
        $script:Ast[$File].Text | Should -Match 'SupportsShouldProcess = \$true'
        $script:Ast[$File].Text | Should -Match '\$PSCmdlet.ShouldProcess'
    }
    It 'bootstrap validates the signed payload before child execution and configuration' {
        $text = $script:Ast['bootstrap.ps1'].Text
        $text.IndexOf('Read-MicrosoftSignedScript -Path') | Should -BeLessThan $text.IndexOf('$base = Invoke-NativeCommand')
        $text.IndexOf('$base = Invoke-NativeCommand') | Should -BeLessThan $text.IndexOf("'configure', '-f'")
        $text | Should -Not -Match '\bInvoke-Expression\b|\biex\b'
        $text | Should -Match '-InputText \$setupText'
        $text | Should -Match '\$downloadOwned = \$true'
        $text | Should -Match 'if \(\$downloadOwned -and'
        $text | Should -Not -Match 'Remove-Item[^\r\n]*-Recurse'
    }
    It 'bootstrap stops on failed structured preflight before any setup mutation without dumping JSON' {
        $text = $script:Ast['bootstrap.ps1'].Text
        $guard = $text.IndexOf("Preflight failed before setup; no setup actions started.")
        $guard | Should -BeGreaterThan 0
        $guard | Should -BeLessThan $text.IndexOf('Start-Transcript')
        $guard | Should -BeLessThan $text.IndexOf('Invoke-WebRequest')
        $text | Should -Match "Where-Object Status -eq 'FAIL'"
        $text | Should -Match 'Preflight exceeded its \$preflightBudget-second budget'
        $text | Should -Match 'Get-PreflightTimeout -HttpsTimeoutSeconds \$HttpsTimeoutSeconds'
        $text | Should -Match "'-HttpsTimeoutSeconds', \[string\]\`$HttpsTimeoutSeconds"
        $text | Should -Match '\-TimeoutSeconds \$preflightBudget'
        $text | Should -Not -Match "Assert-NativeSuccess\s+\`$preflight"
    }
    It 'bootstrap checks reboot markers only when not skipping the base' {
        $tree = $script:Ast['bootstrap.ps1'].Tree
        $resume = $tree.Find({ param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-BaseResumePending'
        }, $true)
        $parent = $resume.Parent
        $baseGuard = $false
        while ($null -ne $parent) {
            if ($parent -is [Management.Automation.Language.IfStatementAst] -and $parent.Clauses[0].Item1.Extent.Text -eq '-not $SkipBase') { $baseGuard = $true }
            $parent = $parent.Parent
        }
        $baseGuard | Should -BeTrue
    }
    It 'repair checks policy before its first native readiness test and defines blocked exit 2' {
        $text = $script:Ast['repair-winget.ps1'].Text
        $body = $text.Substring($text.IndexOf('function Invoke-WinGetRepair'))
        $body.IndexOf('Get-WinGetPolicy') | Should -BeLessThan $body.IndexOf('Test-WinGetConfigure')
        $body | Should -Match 'Get-CheckExitCode \$blocked -PolicyRepair'
    }
    It 'reset never resets all Git paths or cleans the entire sample tree' {
        $text = $script:Ast['demo-reset.ps1'].Text
        $text | Should -Not -Match "'reset'|'-fd'|'-fdx'"
        $text | Should -Match "'--staged', '--worktree', '--', 'samples'"
        $text | Should -Match "'clean', '-f', '--', \`$path"
        $text | Should -Match 'Confirm new file deletion'
        $text | Should -Match 'label=io.win11-dev-workstation.showcase=true'
    }
    It '<File> standalone entrypoint preserves JSON while exiting with its status' -TestCases @(
        @{ File = 'preflight.ps1'; Function = 'Invoke-Preflight' },
        @{ File = 'verify.ps1'; Function = 'Invoke-Verification' }
    ) {
        param($File, $Function)
        $entrypoint = $script:Ast[$File].Tree.EndBlock.Statements[-1].Extent.Text
        $fixture = '$ProgressPreference=''SilentlyContinue''; & { param([switch]$Json); function ' + $Function +
            ' { param([switch]$Json); Write-Output ''[{"Name":"Fixture","Status":"PASS"}]''; return 0 }; ' +
            $entrypoint + ' } -Json'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fixture))
        $shell = (Get-Process -Id $PID).Path
        $result = Invoke-NativeCommand $shell @('-NoProfile', '-EncodedCommand', $encoded) -TimeoutSeconds 15
        $result.ExitCode | Should -Be 0
        $result.StdErr | Should -Be ''
        $parsed = $result.StdOut | ConvertFrom-Json
        $parsed[0].Status | Should -Be 'PASS'
    }
}

Describe 'Actual preflight readiness functions with safe mocks' {
    BeforeEach {
        Mock Get-CimInstance {
            switch ($ClassName) {
                Win32_OperatingSystem { [pscustomobject]@{ BuildNumber = '22621'; ProductType = 1; Caption = 'Windows 11 Pro' } }
                Win32_Processor { [pscustomobject]@{ VirtualizationFirmwareEnabled = $true } }
                Win32_ComputerSystem { [pscustomobject]@{ HypervisorPresent = $false } }
                Win32_LogicalDisk { [pscustomobject]@{ FreeSpace = 20GB } }
            }
        }
        Mock Test-IsAdministrator { $false }
        Mock Get-AppxPackage { [pscustomobject]@{ Version = '1.11.11451' } }
        Mock Get-NativeCommandPath { "C:\$Name.exe" }
        Mock Get-WinGetPolicy { Get-CheckResult 'EnableAppInstaller' PASS 'Not configured.' }
        Mock Get-HttpsProbe {
            [pscustomobject]@{ Uri = [string]$Uri; Reachable = $true; StatusCode = 200
                Attempts = 1; ErrorType = ''; Reason = 'HTTPS host reachable.'; TimeoutSeconds = $TimeoutSeconds }
        }
        Mock Get-ExecutionPolicy { [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'RemoteSigned' } }
        Mock Invoke-NativeCommand {
            $text = switch ($FilePath) {
                'C:\winget.exe' { if ($ArgumentList[0] -eq '--version') { 'v1.29.380' } else { 'configure help' } }
                'C:\wsl.exe' { 'WSL version: 2.9.3' }
                default { 'Direct access (no proxy server).' }
            }
            [pscustomobject]@{ ExitCode = 0; Output = $text; StdOut = $text; StdErr = ''; TimedOut = $false }
        }
    }
    It 'all required mocked readiness checks pass' {
        Get-CheckExitCode @(Get-PreflightCheck) | Should -Be 0
        Should -Invoke Get-HttpsProbe -Times 6 -Exactly -ParameterFilter { $TimeoutSeconds -eq 5 }
        Should -Invoke Get-HttpsProbe -Times 1 -Exactly -ParameterFilter {
            [string]$Uri -eq 'https://codeload.github.com/microsoft/WindowsDeveloperConfig/zip/refs/heads/main'
        }
        It 'passes an explicit slow-network timeout to all six hosts and clean JSON' {
            $output = @(Invoke-Preflight -Json -HttpsTimeoutSeconds 30)
            $output[-1] | Should -Be 0
            $parsed = $output[0] | ConvertFrom-Json
            @($parsed | Where-Object Name -like 'HTTPS *').Count | Should -Be 6
            foreach ($check in $parsed | Where-Object Name -like 'HTTPS *') {
                $check.Probe.TimeoutSeconds | Should -Be 30
            }
            Should -Invoke Get-HttpsProbe -Times 6 -Exactly -ParameterFilter { $TimeoutSeconds -eq 30 }
        }
        It 'rejects out-of-range HTTPS timeout before any probe' -TestCases @(@{ Timeout = 0 }, @{ Timeout = 31 }) {
            param($Timeout)
            { Invoke-Preflight -HttpsTimeoutSeconds $Timeout } | Should -Throw
            Should -Invoke Get-HttpsProbe -Times 0 -Exactly
        }
        Should -Invoke Get-HttpsProbe -Times 1 -Exactly -ParameterFilter {
            [string]$Uri -eq 'https://raw.githubusercontent.com/microsoft/WindowsDeveloperConfig/refs/heads/main/README.md'
        }
    }
    It 'outputs clean JSON and returns a separate integer status' {
        $output = @(Invoke-Preflight -Json)
        $output.Count | Should -Be 2
        $output[-1] | Should -Be 0
        $parsed = $output[0] | ConvertFrom-Json
        @($parsed).Count | Should -Be 20
        $output[0] | Should -Not -Match 'configure help'
        ($parsed | Where-Object Name -eq 'HTTPS release-assets.githubusercontent.com').Probe.Attempts | Should -Be 1
    }
    It 'fails the documented below-minimum WinGet version' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = 'v1.6.2630'; StdOut = 'v1.6.2630'; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $FilePath -eq 'C:\winget.exe' -and $ArgumentList[0] -eq '--version' }
        (Get-PreflightCheck | Where-Object Name -eq WinGet).Status | Should -Be 'FAIL'
    }
    It 'warns for the historical silent-output version range' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = 'v1.6.2631'; StdOut = 'v1.6.2631'; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $FilePath -eq 'C:\winget.exe' -and $ArgumentList[0] -eq '--version' }
        (Get-PreflightCheck | Where-Object Name -eq WinGet).Status | Should -Be 'WARN'
    }
    It 'reports policy failure without probing configure' {
        Mock Get-WinGetPolicy { Get-CheckResult 'EnableAppInstaller' FAIL 'Blocked by organisation policy, contact IT.' }
        Get-CheckExitCode @(Get-PreflightCheck) | Should -Be 1
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'configure' }
    }
    It 'fails insufficient system disk space' {
        Mock Get-CimInstance { [pscustomobject]@{ FreeSpace = 14GB } } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
        (Get-PreflightCheck | Where-Object Name -eq 'System disk').Status | Should -Be 'FAIL'
    }
    It 'permits a hypervisor without firmware flags' {
        Mock Get-CimInstance { [pscustomobject]@{ HypervisorPresent = $true } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        Mock Get-CimInstance { [pscustomobject]@{ VirtualizationFirmwareEnabled = $false } } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        (Get-PreflightCheck | Where-Object Name -eq Virtualization).Status | Should -Be 'PASS'
    }
}

Describe 'Actual tool and extension verification with safe mocks' {
    BeforeEach {
        Mock Get-ShowcaseRoot { $script:Repository }
        Mock Get-WinGetPolicy { Get-CheckResult 'EnableAppInstaller' PASS 'Not configured.' }
        Mock Get-NativeCommandPath { "C:\$Name.exe" }
        Mock Get-RequiredExtension {
            if ($IncludeJavaModernization) { $script:Recommendations }
            else { $script:Recommendations | Where-Object { $_ -ne 'vscjava.migrate-java-to-azure' } }
        }
        Mock Test-Path { $true }
        Mock Invoke-NativeCommand {
            if ($ArgumentList[0] -eq '--list-extensions') { $text = $script:Recommendations -join "`n" }
            else {
                $text = switch ($FilePath) {
                    'C:\winget.exe' { 'v1.29.380' }
                    'C:\python.exe' { 'Python 3.14.0' }
                    'C:\java.exe' { 'openjdk version "25.0.1"' }
                    'C:\wsl.exe' { 'WSL version: 2.9.3' }
                    default { 'Installed tool 1.0' }
                }
            }
            [pscustomobject]@{ ExitCode = 0; Output = $text; StdOut = $text; StdErr = ''; TimedOut = $false }
        }
    }
    It 'verifies 15 tools and the 12-extension default profile' {
        $checks = @(Get-VerificationCheck)
        $checks.Count | Should -Be 28
        Get-CheckExitCode $checks | Should -Be 0
        $checks.Name | Should -Not -Contain 'vscjava.migrate-java-to-azure'
    }
    It 'checks the 13th extension only when modernization is included' {
        $checks = @(Get-VerificationCheck -IncludeJavaModernization)
        $checks.Count | Should -Be 29
        $checks.Name | Should -Contain 'vscjava.migrate-java-to-azure'
    }
    It 'fails Python outside the prescribed 3.14 line' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = 'Python 3.12.0'; StdOut = 'Python 3.12.0'; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $FilePath -eq 'C:\python.exe' }
        (Get-VerificationCheck | Where-Object Name -eq python).Status | Should -Be 'FAIL'
    }
    It 'recognises the Java version emitted on stderr' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = 'openjdk version "25"'; StdOut = ''; StdErr = 'openjdk version "25"'; TimedOut = $false }
        } -ParameterFilter { $FilePath -eq 'C:\java.exe' }
        (Get-VerificationCheck | Where-Object Name -eq java).Status | Should -Be 'PASS'
    }
    It 'fails an older WSL container prerequisite' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = 'WSL version: 2.9.2'; StdOut = 'WSL version: 2.9.2'; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $FilePath -eq 'C:\wsl.exe' }
        (Get-VerificationCheck | Where-Object Name -eq wsl).Status | Should -Be 'FAIL'
    }
    It 'does not run WinGet under an explicit policy block' {
        Mock Get-WinGetPolicy { Get-CheckResult 'EnableWindowsPackageManagerConfiguration' FAIL 'Blocked by organisation policy.' }
        Get-CheckExitCode @(Get-VerificationCheck -RunConfigTest) | Should -Be 1
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter { $FilePath -eq 'C:\winget.exe' }
    }
    It 'runs both read-only configuration tests only when selected' {
        $null = Get-VerificationCheck -RunConfigTest -IncludeJavaModernization
        Should -Invoke Invoke-NativeCommand -Times 2 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'configure' -and $ArgumentList[1] -eq 'test' }
    }
}

Describe 'Actual sample launch planning and mocked container execution' {
    BeforeEach {
        Mock Test-Path { $true }
        Mock Assert-SafeDirectory {}
        Mock Get-ShowcaseRoot { $script:Repository }
        Mock Get-NativeCommandPath { "C:\$Name.exe" }
        Mock Get-ContainerRuntime { [pscustomobject]@{ Name = 'wslc'; Path = 'C:\wslc.exe' } }
        Mock Write-ShowcaseMessage {}
        Mock Wait-SampleHealth { "http://127.0.0.1:$Port/health" }
        Mock Invoke-NativeCommand { [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = ''; StdErr = ''; TimedOut = $false } }
    }
    It 'respects the Python local port argument' {
        $command = Get-LocalSampleCommand python-emi-api 'C:\sample' 8181
        $command.Arguments[-1] | Should -Be '8181'
        $command.Arguments | Should -Contain 'RunLocal'
        $command.Arguments | Should -Contain 'Python'
    }
    It 'delegates Java to the same offline guarded dispatcher with a port override' {
        $command = Get-LocalSampleCommand java-ifsc-service 'C:\sample' 8182
        $command.Arguments | Should -Contain 'Java'
        $command.Arguments[-1] | Should -Be '8182'
    }
    It 'uses the Go sample tooling without invoking a service' {
        $command = Get-LocalSampleCommand go-fx-rates 'C:\sample' 8183
        $command.Arguments | Should -Contain 'Go'
        $command.Arguments | Should -Contain 'RunLocal'
        $script:Ast['run-sample.ps1'].Text | Should -Match '\$env:PORT = \[string\]\$Port'
        $script:Ast['run-sample.ps1'].Text | Should -Match "SetEnvironmentVariable\('PORT', \`$originalPort"
    }
    It 'sets and restores the Go PORT environment for an in-memory fixture command' {
        function Invoke-PortFixtureProcess {
            $script:CapturedPort = $env:PORT
            $global:LASTEXITCODE = 0
        }
        $original = [Environment]::GetEnvironmentVariable('PORT', 'Process')
        $location = (Get-Location).Path
        $command = [pscustomobject]@{ Path = 'Invoke-PortFixtureProcess'; Arguments = @() }
        Invoke-LocalSampleProcess -Command $command -Directory $script:Repository -Name go-fx-rates -Port 8183 -Confirm:$false | Should -Be 0
        $script:CapturedPort | Should -Be '8183'
        [Environment]::GetEnvironmentVariable('PORT', 'Process') | Should -Be $original
        (Get-Location).Path | Should -Be $location
    }
    It 'restores the Go environment and directory even on fixture failure' {
        function Invoke-PortFailureFixture {
            throw 'Fixture failure (no service was started).'
        }
        $original = [Environment]::GetEnvironmentVariable('PORT', 'Process')
        $location = (Get-Location).Path
        $command = [pscustomobject]@{ Path = 'Invoke-PortFailureFixture'; Arguments = @() }
        { Invoke-LocalSampleProcess -Command $command -Directory $script:Repository -Name go-fx-rates -Port 8183 -Confirm:$false } | Should -Throw '*Fixture failure*'
        [Environment]::GetEnvironmentVariable('PORT', 'Process') | Should -Be $original
        (Get-Location).Path | Should -Be $location
    }
    It 'publishes the selected container port and requires actual health waiting' {
        Invoke-Sample python-emi-api container 8181 5 -Confirm:$false | Should -Be 0
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'run' -and $ArgumentList -contains '127.0.0.1:8181:8080' }
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'run' -and $ArgumentList -contains '--pull=never' }
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -in @('build', 'pull') }
        Should -Invoke Wait-SampleHealth -Times 1 -Exactly -ParameterFilter { $Port -eq 8181 -and $TimeoutSeconds -eq 5 }
    }
    It 'preserves an explicitly selected runtime without assigning its validated parameter' {
        Invoke-Sample python-emi-api container 8181 5 -Runtime docker -Confirm:$false | Should -Be 0
        Should -Invoke Get-ContainerRuntime -Times 1 -Exactly -ParameterFilter { $Preferred -eq 'docker' }
    }
    It 'does not fall back after wslc denies access' {
        Mock Invoke-NativeCommand { [pscustomobject]@{ ExitCode = 5; Output = 'Denied by policy'; StdOut = ''; StdErr = 'Denied'; TimedOut = $false } }
        Invoke-Sample python-emi-api container 8181 5 -Confirm:$false | Should -Be 1
        Should -Invoke Get-ContainerRuntime -Times 1 -Exactly
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'C:\wslc.exe' }
    }
    It 'preserves a preexisting same-name container' {
        Mock Invoke-NativeCommand { [pscustomobject]@{ ExitCode = 0; Output = 'win11-demo-python-emi-api'; StdOut = 'win11-demo-python-emi-api'; StdErr = ''; TimedOut = $false } }
        Invoke-Sample python-emi-api container 8181 5 -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -in @('stop', 'rm', 'run', 'build') }
    }
    It 'cleans up only its newly started container when health fails' {
        Mock Wait-SampleHealth { throw 'Health timed out.' }
        Invoke-Sample python-emi-api container 8181 5 -Confirm:$false | Should -Be 1
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'stop' -and $ArgumentList[1] -eq 'win11-demo-python-emi-api' }
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'rm' -and $ArgumentList[1] -eq 'win11-demo-python-emi-api' }
    }
    It 'WhatIf does not build, start, or probe a health endpoint' {
        Invoke-Sample python-emi-api container 8181 5 -WhatIf | Should -Be 0
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
        Should -Invoke Wait-SampleHealth -Times 0 -Exactly
    }
}

Describe 'Extracted read-only WinGet repair readiness helper' {
    BeforeEach {
        Mock Get-NativeCommandPath { 'C:\winget.exe' }
        Mock Invoke-NativeCommand {
            $text = if ($ArgumentList[0] -eq '--version') { 'v1.29.380' } else { 'configure help' }
            [pscustomobject]@{ ExitCode = 0; Output = $text; StdOut = $text; StdErr = ''; TimedOut = $false }
        }
    }
    It 'recognises a working current WinGet without invoking repair' {
        (Test-WinGetConfigure).Ready | Should -BeTrue
    }
    It 'rejects the older silent-output WinGet version' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = 'v1.6.2631'; StdOut = 'v1.6.2631'; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq '--version' }
        (Test-WinGetConfigure).Ready | Should -BeFalse
    }
    It 'rejects a failed configure even if the version is current' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = -2146233079; Output = 'Internal error -2146233079'; StdOut = ''; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'configure' }
        $test = Test-WinGetConfigure
        $test.Ready | Should -BeFalse
        $test.Output | Should -Match '-2146233079'
    }
}

Describe 'Actual reset status/path confinement with safe Git mocks' {
    BeforeEach {
        Mock Assert-SafeSampleTree {}
        Mock Invoke-NativeCommand {
            $text = if ($ArgumentList[0] -eq 'ls-tree') { 'samples/python-emi-api/app/main.py' } elseif ($ArgumentList[0] -eq 'rev-parse') { 'a' * 40 } else { '' }
            [pscustomobject]@{ ExitCode = 0; Output = $text; StdOut = $text; StdErr = ''; TimedOut = $false }
        }
    }
    It 'accepts clean working trees without deleting anything' {
        $state = Get-SampleResetState 'C:\git.exe' $script:Repository
        $state.Untracked.Count | Should -Be 0
    }
    It 'lists intentional new untracked sample files for later confirmation' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = "?? samples/python-emi-api/new test.py`0"; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'status' }
        (Get-SampleResetState 'C:\git.exe' $script:Repository).Untracked | Should -Contain 'samples/python-emi-api/new test.py'
    }
    It 'rejects unrelated <Record> work' -TestCases @(
        @{ Record = ' M README.md' }, @{ Record = '?? unrelated.txt' },
        @{ Record = 'A  docs/new.md' }, @{ Record = ' M samples-other/file.py' }
    ) {
        param($Record)
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = $Record + "`0"; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'status' }
        { Get-SampleResetState 'C:\git.exe' $script:Repository } | Should -Throw '*Unrelated work*'
    }
    It 'rejects a rename crossing the sample boundary' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = "R  samples/new.py`0docs/original.py`0"; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'status' }
        { Get-SampleResetState 'C:\git.exe' $script:Repository } | Should -Throw '*Unrelated work*'
    }
    It 'accepts renames wholly within samples' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = "R  samples/new.py`0samples/old.py`0"; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'status' }
        { Get-SampleResetState 'C:\git.exe' $script:Repository } | Should -Not -Throw
    }
    It 'refuses merge conflicts' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = "UU samples/app.py`0"; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'status' }
        { Get-SampleResetState 'C:\git.exe' $script:Repository } | Should -Throw '*Merge conflicts*'
    }
    It 'refuses a missing baseline before any mutation' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 128; Output = 'Unknown tag'; StdOut = ''; StdErr = 'Unknown tag'; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'rev-parse' }
        { Get-SampleResetState 'C:\git.exe' $script:Repository } | Should -Throw '*origin/main*'
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly
    }
    It 'refuses the historical unsafe Go baseline' {
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = ''; StdOut = 'slog.Info("conversion request", "query", r.URL.RawQuery)'; StdErr = ''; TimedOut = $false }
        } -ParameterFilter { $ArgumentList[0] -eq 'show' }
        { Get-SampleResetState 'C:\git.exe' $script:Repository } | Should -Throw '*historical Go gaps*'
    }
}
