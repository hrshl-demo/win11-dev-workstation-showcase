<#
.SYNOPSIS
Safe Pester 5 tests for common policy, process, signature and runtime helpers.
.DESCRIPTION
No setup, repair, elevation, service or container operations are executed.
Fixture files live only under this tests directory and are removed afterwards.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:Repository = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:Repository 'scripts\_common.psm1') -Force
    $script:FixtureRoot = Join-Path $PSScriptRoot ('.common-fixtures-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:FixtureRoot
    $script:Shell = (Get-Process -Id $PID).Path
    $script:Recommendations = @(
        'ms-python.python', 'vscjava.vscode-java-pack', 'golang.go',
        'ms-azuretools.vscode-azureresourcegroups', 'ms-azuretools.vscode-azure-github-copilot',
        'ms-azuretools.vscode-bicep', 'ms-azuretools.vscode-containers',
        'ms-vscode-remote.remote-containers', 'ms-vscode-remote.remote-wsl',
        'GitHub.vscode-pull-request-github', 'vscjava.migrate-java-to-azure',
        'ms-vscode.powershell', 'redhat.vscode-yaml'
    )
    $script:ExtensionFile = Join-Path $script:FixtureRoot 'extensions.json'
    @{ recommendations = $script:Recommendations } | ConvertTo-Json |
        Set-Content -LiteralPath $script:ExtensionFile -Encoding UTF8
    $script:SignatureFile = Join-Path $script:FixtureRoot 'signed-fixture.ps1'
    Set-Content -LiteralPath $script:SignatureFile -Value "Write-Output 'never executed'" -Encoding UTF8
}

AfterAll {
    if ($script:FixtureRoot -and (Test-Path -LiteralPath $script:FixtureRoot)) {
        Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force
    }
}

Describe 'Policy and exit semantics' {
    BeforeEach {
        Mock Test-Path -ModuleName _common { $false }
        Mock Get-ItemProperty -ModuleName _common { throw 'Registry must not be read when absent.' }
    }
    It 'allows an absent policy registry key' {
        $checks = @(Get-WinGetPolicy)
        $checks.Count | Should -Be 5
        Get-CheckExitCode $checks | Should -Be 0
        { Assert-WorkstationPolicy } | Should -Not -Throw
        Should -Invoke Get-ItemProperty -ModuleName _common -Times 0 -Exactly
    }
    It 'allows absent individual policy values' {
        Mock Test-Path -ModuleName _common { $true }
        Mock Get-ItemProperty -ModuleName _common { [pscustomobject]@{} }
        Get-CheckExitCode @(Get-WinGetPolicy) | Should -Be 0
    }
    It 'blocks explicit zero in <Policy>' -TestCases @(
        @{ Policy = 'EnableAppInstaller' },
        @{ Policy = 'EnableWindowsPackageManagerCommandLineInterfaces' },
        @{ Policy = 'EnableWindowsPackageManagerConfiguration' },
        @{ Policy = 'EnableAllowedSources' },
        @{ Policy = 'EnableDefaultSource' }
    ) {
        param($Policy)
        Mock Test-Path -ModuleName _common { $true }
        Mock Get-ItemProperty -ModuleName _common { [pscustomobject]@{ $Policy = 0 } }
        $checks = @(Get-WinGetPolicy)
        @($checks | Where-Object Status -eq FAIL).Count | Should -Be 1
        { Assert-WorkstationPolicy } | Should -Throw '*organisation policy*'
        Get-CheckExitCode $checks | Should -Be 1
        Get-CheckExitCode $checks -PolicyRepair | Should -Be 2
    }
    It 'allows explicitly enabled policy values' {
        Mock Test-Path -ModuleName _common { $true }
        Mock Get-ItemProperty -ModuleName _common { [pscustomobject]@{ EnableAppInstaller = 1 } }
        Get-CheckExitCode @(Get-WinGetPolicy) | Should -Be 0
    }
    It 'fails closed when configured policy cannot be read' {
        Mock Test-Path -ModuleName _common { $true }
        Mock Get-ItemProperty -ModuleName _common { throw 'Access denied reading policy.' }
        { Assert-WorkstationPolicy } | Should -Throw '*Access denied*'
    }
    It 'does not treat warnings as failures' {
        $checks = @(Get-CheckResult 'Advisory' WARN 'Optional item absent.')
        Get-CheckExitCode $checks | Should -Be 0
    }
    It 'returns zero for an empty result collection' {
        Get-CheckExitCode @() | Should -Be 0
    }
    It 'writes clean JSON without a human status prefix' {
        $json = Write-CheckReport @(Get-CheckResult 'Item' PASS 'Ready.') -Json
        $parsed = @($json | ConvertFrom-Json)
        $parsed.Count | Should -Be 1
        $parsed[0].Status | Should -Be 'PASS'
        $json | Should -Not -Match '\[PASS\]'
    }
}

Describe 'Native argument quoting and isolated execution' {
    It 'quotes an empty argument' { ConvertTo-NativeArgument '' | Should -Be '""' }
    It 'does not quote a simple argument' { ConvertTo-NativeArgument 'version' | Should -Be 'version' }
    It 'quotes arguments with spaces' { ConvertTo-NativeArgument 'a b' | Should -Be '"a b"' }
    It 'escapes embedded quotes' { ConvertTo-NativeArgument 'a"b' | Should -Be '"a\"b"' }
    It 'doubles a trailing slash inside quotes' { ConvertTo-NativeArgument 'C:\a b\' | Should -Be '"C:\a b\\"' }
    It 'captures stdout and stderr with the actual nonzero exit code' {
        $result = @(Invoke-NativeCommand $script:Shell @('-NoProfile', '-Command',
            '[Console]::Out.Write("stdout"); [Console]::Error.Write("stderr"); exit 7'))
        $result.Count | Should -Be 1
        $result[0].StdOut | Should -Be 'stdout'
        $result[0].StdErr | Should -Be 'stderr'
        $result[0].ExitCode | Should -Be 7
        { Assert-NativeSuccess $result[0] 'Fixture process' } | Should -Throw '*exit 7*'
    }
    It 'bounds a slow process without success output contamination' {
        $result = Invoke-NativeCommand $script:Shell @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -TimeoutSeconds 1
        $result.TimedOut | Should -BeTrue
        $result.ExitCode | Should -Be 124
    }
    It 'drains both streams without deadlock' {
        $result = Invoke-NativeCommand $script:Shell @('-NoProfile', '-Command',
            '[Console]::Out.Write("o"*100000); [Console]::Error.Write("e"*100000)')
        $result.ExitCode | Should -Be 0
        $result.StdOut.Length | Should -Be 100000
        $result.StdErr.Length | Should -Be 100000
    }
    It 'delivers stdin without putting payload on the command line' {
        $result = Invoke-NativeCommand $script:Shell @('-NoProfile', '-Command',
            '[Console]::Out.Write([Console]::In.ReadToEnd())') -InputText 'signed payload fixture'
        $result.StdOut | Should -Be 'signed payload fixture'
    }
    It 'rejects batch shell metacharacters before starting a process' {
        { Invoke-NativeCommand 'C:\fixture.cmd' @('a&whoami') } | Should -Throw '*Unsafe batch*'
    }
}

Describe 'Container runtime choice' {
    It 'prefers wslc without even probing Docker' {
        Mock Get-NativeCommandPath -ModuleName _common { 'C:\wslc.exe' } -ParameterFilter { $Name -eq 'wslc' }
        Mock Get-NativeCommandPath -ModuleName _common { throw 'Do not probe Docker.' } -ParameterFilter { $Name -eq 'docker' }
        (Get-ContainerRuntime).Name | Should -Be 'wslc'
        Should -Invoke Get-NativeCommandPath -ModuleName _common -Times 0 -Exactly -ParameterFilter { $Name -eq 'docker' }
    }
    It 'uses Docker only when wslc is absent' {
        Mock Get-NativeCommandPath -ModuleName _common { $null } -ParameterFilter { $Name -eq 'wslc' }
        Mock Get-NativeCommandPath -ModuleName _common { 'C:\docker.exe' } -ParameterFilter { $Name -eq 'docker' }
        (Get-ContainerRuntime).Name | Should -Be 'docker'
    }
    It 'fails when neither approved runtime is available' {
        Mock Get-NativeCommandPath -ModuleName _common { $null }
        { Get-ContainerRuntime } | Should -Throw '*No container runtime*'
    }
    It 'explicit Docker never probes wslc or falls back' {
        Mock Get-NativeCommandPath -ModuleName _common { throw 'Do not probe wslc.' } -ParameterFilter { $Name -eq 'wslc' }
        Mock Get-NativeCommandPath -ModuleName _common { 'C:\docker.exe' } -ParameterFilter { $Name -eq 'docker' }
        (Get-ContainerRuntime -Preferred docker).Name | Should -Be 'docker'
        Should -Invoke Get-NativeCommandPath -ModuleName _common -Times 0 -Exactly -ParameterFilter { $Name -eq 'wslc' }
    }
    It 'explicit missing wslc does not switch to Docker' {
        Mock Get-NativeCommandPath -ModuleName _common { $null } -ParameterFilter { $Name -eq 'wslc' }
        Mock Get-NativeCommandPath -ModuleName _common { throw 'Do not probe Docker.' } -ParameterFilter { $Name -eq 'docker' }
        { Get-ContainerRuntime -Preferred wslc } | Should -Throw '*No container runtime*'
    }
}

Describe 'HTTPS and health waiting' {
    BeforeEach {
        Mock Start-Sleep -ModuleName _common {}
    }
    It 'accepts root 404/405 as reachability only' -TestCases @(@{ Code = 404 }, @{ Code = 405 }) {
        param($Code)
        Mock Invoke-WebRequest -ModuleName _common { [pscustomobject]@{ StatusCode = $Code } }
        $probe = Get-HttpsProbe 'https://release-assets.githubusercontent.com/'
        $probe.Reachable | Should -BeTrue
        $probe.StatusCode | Should -Be $Code
        $probe.Reason | Should -Match 'does not verify artifact'
        $probe.Attempts | Should -Be 1
    }
    It 'reads an exception HTTP response rather than classifying root 404 as transport failure' {
        Mock Invoke-WebRequest -ModuleName _common {
            $failure = [Exception]::new('synthetic HTTP response')
            $failure | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 })
            throw $failure
        }
        $probe = Get-HttpsProbe 'https://release-assets.githubusercontent.com/'
        $probe.Reachable | Should -BeTrue
        $probe.StatusCode | Should -Be 404
        $probe.Attempts | Should -Be 1
    }
    It 'does not accept a missing artifact path or access denial or a redirect' -TestCases @(
        @{ Code = 404; Path = '/artifact' }, @{ Code = 401; Path = '/' },
        @{ Code = 403; Path = '/' }, @{ Code = 407; Path = '/' }, @{ Code = 302; Path = '/' }
    ) {
        param($Code, $Path)
        Mock Invoke-WebRequest -ModuleName _common { [pscustomobject]@{ StatusCode = $Code } }
        $probe = Get-HttpsProbe "https://github.com$Path"
        $probe.Reachable | Should -BeFalse
        $probe.Attempts | Should -Be 1
        Should -Invoke Start-Sleep -ModuleName _common -Times 0 -Exactly
    }
    It 'retries timeout and DNS failures and reports recovery' -TestCases @(
        @{ Failure = [Net.WebExceptionStatus]::Timeout },
        @{ Failure = [Net.WebExceptionStatus]::NameResolutionFailure },
        @{ Failure = [Net.WebExceptionStatus]::ConnectFailure }
    ) {
        param($Failure)
        $script:ProbeCalls = 0
        Mock Invoke-WebRequest -ModuleName _common {
            $script:ProbeCalls++
            if ($script:ProbeCalls -lt 3) { throw [Net.WebException]::new('synthetic transport failure', $Failure) }
            [pscustomobject]@{ StatusCode = 200 }
        }
        $probe = Get-HttpsProbe 'https://github.com/'
        $probe.Reachable | Should -BeTrue
        $probe.Attempts | Should -Be 3
        @($probe.RetryReasons).Count | Should -Be 2
        Should -Invoke Start-Sleep -ModuleName _common -Times 2 -Exactly -ParameterFilter { $Milliseconds -eq 250 }
    }
    It 'exhausts only three transport attempts and restores TLS without leaking exception text' {
        $tls = [Net.ServicePointManager]::SecurityProtocol
        Mock Invoke-WebRequest -ModuleName _common { throw [Net.WebException]::new('secret proxy credential', [Net.WebExceptionStatus]::Timeout) }
        $probe = Get-HttpsProbe 'https://github.com/'
        $probe.Reachable | Should -BeFalse
        $probe.Attempts | Should -Be 3
        $probe.Reason | Should -Be 'Timeout'
        ($probe | ConvertTo-Json) | Should -Not -Match 'secret proxy'
        [Net.ServicePointManager]::SecurityProtocol | Should -Be $tls
        Should -Invoke Invoke-WebRequest -ModuleName _common -Times 3 -Exactly -ParameterFilter { $TimeoutSec -eq 5 -and $MaximumRedirection -eq 0 }
    }
    It 'classifies wrapped socket DNS failures used by newer HTTP clients' {
        Mock Invoke-WebRequest -ModuleName _common {
            $socket = [Net.Sockets.SocketException]::new([int][Net.Sockets.SocketError]::HostNotFound)
            throw [Exception]::new('synthetic HTTP client failure', $socket)
        }
        $probe = Get-HttpsProbe 'https://github.com/'
        $probe.Reachable | Should -BeFalse
        $probe.Attempts | Should -Be 3
        $probe.Reason | Should -Be 'HostNotFound'
    }
    It 'never retries certificate failures and restores TLS' {
        $tls = [Net.ServicePointManager]::SecurityProtocol
        Mock Invoke-WebRequest -ModuleName _common { throw [Net.WebException]::new('synthetic certificate failure', [Net.WebExceptionStatus]::TrustFailure) }
        $probe = Get-HttpsProbe 'https://github.com/'
        $probe.Reachable | Should -BeFalse
        $probe.Attempts | Should -Be 1
        $probe.Reason | Should -Be 'TrustFailure'
        [Net.ServicePointManager]::SecurityProtocol | Should -Be $tls
        Should -Invoke Start-Sleep -ModuleName _common -Times 0 -Exactly
    }
    It 'keeps recovery warnings out of JSON while showing them in plain reports' {
        $check = Get-CheckResult 'HTTPS synthetic' PASS 'Recovered after transient transport retries.'
        $check | Add-Member -NotePropertyName Probe -NotePropertyValue ([pscustomobject]@{ Attempts = 3 })
        $json = @(Write-CheckReport -Checks @($check) -Json 6>&1)
        $json.Count | Should -Be 1
        (($json[0] | ConvertFrom-Json)[0]).Probe.Attempts | Should -Be 3
        $plain = @(Write-CheckReport -Checks @($check) 6>&1)
        $plain.Count | Should -Be 2
        [string]$plain[0] | Should -Match '\[WARN\]'
        [string]$plain[1] | Should -Match '\[PASS\]'
    }
    It 'uses HTTPS HEAD with a five-second timeout and restores TLS state' {
        $tls = [Net.ServicePointManager]::SecurityProtocol
        Mock Invoke-WebRequest -ModuleName _common { [pscustomobject]@{ StatusCode = 200 } }
        Test-HttpsEndpoint 'https://github.com' | Should -BeTrue
        [Net.ServicePointManager]::SecurityProtocol | Should -Be $tls
        Should -Invoke Invoke-WebRequest -ModuleName _common -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Head' -and $TimeoutSec -eq 5 -and $Uri.Scheme -eq 'https'
        }
    }
    It 'rejects plaintext readiness endpoints' {
        { Test-HttpsEndpoint 'http://github.com' } | Should -Throw '*HTTPS*'
    }
    It 'reports a transport failure without an absent Response property error' {
        Mock Invoke-WebRequest -ModuleName _common { throw 'Connection failed.' }
        Test-HttpsEndpoint 'https://github.com' | Should -BeFalse
    }
    It 'waits through initial health failure and uses the selected port' {
        $script:HealthCalls = 0
        Mock Invoke-WebRequest -ModuleName _common {
            $script:HealthCalls++
            if ($script:HealthCalls -eq 1) { throw 'Not ready.' }
            [pscustomobject]@{ StatusCode = 200 }
        }
        Mock Start-Sleep -ModuleName _common {}
        Wait-SampleHealth -Port 8181 -TimeoutSeconds 2 | Should -Be 'http://127.0.0.1:8181/health'
        Should -Invoke Invoke-WebRequest -ModuleName _common -Times 2 -Exactly
    }
    It 'fails when health never becomes successful' {
        Mock Invoke-WebRequest -ModuleName _common { [pscustomobject]@{ StatusCode = 503 } }
        { Wait-SampleHealth -Port 8181 -TimeoutSeconds 1 } | Should -Throw '*timed out*'
    }
}

Describe 'Extension profiles and signed payload reading' {
    It 'requires exactly 12 default extensions' {
        $extensions = @(Get-RequiredExtension $script:ExtensionFile)
        $extensions.Count | Should -Be 12
        $extensions | Should -Not -Contain 'vscjava.migrate-java-to-azure'
    }

    Describe 'Read-only base restart/resume detection' {
        BeforeEach {
            Mock Get-ScheduledTask -ModuleName _common { $null }
            Mock Test-Path -ModuleName _common { $false }
        }
        It 'does not invent a pending restart' {
            Test-BaseResumePending | Should -BeFalse
        }
        It 'recognises the Microsoft resume task' {
            Mock Get-ScheduledTask -ModuleName _common { [pscustomobject]@{ State = 'Ready' } }
            Test-BaseResumePending | Should -BeTrue
        }
        It 'recognises a Windows restart marker' {
            Mock Test-Path -ModuleName _common { $true } -ParameterFilter { $LiteralPath -like '*RebootPending' }
            Test-BaseResumePending | Should -BeTrue
        }
    }
    It 'requires all 13 extensions only for modernization' {
        $extensions = @(Get-RequiredExtension $script:ExtensionFile -IncludeJavaModernization)
        $extensions.Count | Should -Be 13
        $extensions | Should -Contain 'vscjava.migrate-java-to-azure'
    }
    It 'rejects an incomplete recommendation profile' {
        $path = Join-Path $script:FixtureRoot 'incomplete.json'
        Set-Content -LiteralPath $path -Value '{"recommendations":[]}'
        { Get-RequiredExtension $path } | Should -Throw '*13 unique*'
    }
    It 'reads but never executes a valid Microsoft-signed fixture' {
        Mock Get-AuthenticodeSignature -ModuleName _common {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation' } }
        }
        Read-MicrosoftSignedScript $script:SignatureFile | Should -Match 'never executed'
        Should -Invoke Get-AuthenticodeSignature -ModuleName _common -Times 1 -Exactly
    }
    It 'refuses <Case> signed text' -TestCases @(
        @{ Case = 'invalid'; Status = 'NotSigned'; Subject = 'CN=Microsoft Corporation' },
        @{ Case = 'non-Microsoft'; Status = 'Valid'; Subject = 'CN=Other Publisher' },
        @{ Case = 'missing-certificate'; Status = 'Valid'; Subject = $null }
    ) {
        param($Case, $Status, $Subject)
        Mock Get-AuthenticodeSignature -ModuleName _common {
            $certificate = if ($null -ne $Subject) { [pscustomobject]@{ Subject = $Subject } } else { $null }
            [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
        }
        { Read-MicrosoftSignedScript $script:SignatureFile } | Should -Throw '*Refusing to execute*'
    }
    It 'rejects a file as a directory ancestor' {
        { Assert-SafeDirectory (Join-Path $script:SignatureFile 'child') } | Should -Throw '*Unsafe directory*'
    }
    It 'checks regular sample trees without changes' {
        { Assert-SafeSampleTree $script:FixtureRoot } | Should -Not -Throw
    }
}
