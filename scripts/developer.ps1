<#
.SYNOPSIS
Explicit, user-run development tasks; tests never install or restore tooling.
.DESCRIPTION
Open the cloned repository in VS Code, create a branch with Source Control,
restore approved dependencies explicitly, then test/lint/cover before committing.
Restore, setup, application/container launches and deployment are human actions.
Restore requires existing runtimes; it never installs Python, Java, Go or NuGet.
PowerShell modules are saved only to .tools with pinned versions and confirmation.
Container images are built only by Restore -RestoreTarget ContainerImages.
RunContainer requires an existing image and never builds or pulls one.
Test reports: Python test-results.xml/coverage.xml/htmlcov; Java
target/surefire-reports/target/site/jacoco; Go test-results.json/coverage.out/
coverage.html; PowerShell artifacts/pester.xml (NUnitXml).
F5 requires the existing sample runtime/environment. Install the approved VS Code
Python Debugger, Java Test Runner and Go Delve tooling yourself; F5 has no restore
task. This dispatcher does not change execution policy or configure credentials.
.PARAMETER Action
Select a read-only check or an explicitly user-operated task.
.PARAMETER Sample
Python, Java, Go, PowerShell or All (modern samples plus PowerShell).
Legacy is opt-in and requires Java 11; it is never included in All.
.PARAMETER Runtime
Approved container runtime: auto prefers wslc; docker/wslc explicitly select one.
There is no fallback after a runtime denial or failure.
.PARAMETER RestoreTarget
Dependencies (default) or ContainerImages. ContainerImages builds the selected
sample image explicitly; All includes modern images only, never legacy.
.PARAMETER Port
Loopback application/container/port-forward port.
.PARAMETER HttpsTimeoutSeconds
HTTPS-only preflight timeout, 1-30 seconds, default 5. Passed through setup/finish.
.PARAMETER SourceSha
Required forty-character lowercase SHA of current remote main for DeployDispatch.
.PARAMETER Namespace
Existing Kubernetes namespace, normally from AKS_NAMESPACE. No namespace is created.
.EXAMPLE
.\scripts\developer.ps1 -Action SetupPreview
.EXAMPLE
.\scripts\developer.ps1 -Action Restore -Sample Python -Confirm
.EXAMPLE
.\scripts\developer.ps1 -Action Coverage -Sample All
.EXAMPLE
.\scripts\developer.ps1 -Action Restore -RestoreTarget ContainerImages -Sample Java -Runtime docker -Confirm
.EXAMPLE
.\scripts\developer.ps1 -Action RunContainer -Sample Java -Runtime docker -Confirm
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Preflight', 'SetupPreview', 'Setup', 'FinishSetup', 'Restore',
        'Test', 'Coverage', 'Lint', 'RunLocal', 'RunContainer', 'WorkflowStatus',
        'DeployDispatch', 'KubernetesCheck', 'KubernetesStatus', 'KubernetesLogs',
        'KubernetesPortForward')]
    [string]$Action,
    [ValidateSet('Python', 'Java', 'Go', 'PowerShell', 'All', 'Legacy')]
    [string]$Sample = 'All',
    [ValidateSet('auto', 'docker', 'wslc')][string]$Runtime = 'auto',
    [ValidateSet('Dependencies', 'ContainerImages')][string]$RestoreTarget = 'Dependencies',
    [ValidateRange(1, 65535)][int]$Port = 8080,
    [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5,
    [ValidatePattern('^([0-9a-f]{40})?$')][string]$SourceSha = '',
    [string]$Namespace = $env:AKS_NAMESPACE
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Get-DeveloperSample {
    [CmdletBinding()]
    param([ValidateSet('Python', 'Java', 'Go', 'PowerShell', 'All', 'Legacy')][string]$Sample)
    if ($Sample -eq 'All') { return @('Python', 'Java', 'Go', 'PowerShell') }
    return @($Sample)
}

function Get-DeveloperDirectory {
    [CmdletBinding()]
    param([string]$Sample)
    $names = @{ Python = 'python-emi-api'; Java = 'java-ifsc-service';
        Go = 'go-fx-rates'; Legacy = 'java-legacy-upgrade' }
    if (-not $names.ContainsKey($Sample)) { throw 'Select an application sample.' }
    $directory = Join-Path (Get-ShowcaseRoot) ("samples\" + $names[$Sample])
    Assert-SafeDirectory $directory
    return $directory
}

function Get-DeveloperTool {
    [CmdletBinding()]
    param([string]$Name)
    $path = Get-NativeCommandPath $Name
    if (-not $path) {
        throw "NOT RUN: $Name is unavailable. Ask IT for the approved runtime/tool; no automatic installation."
    }
    return $path
}

function Invoke-DeveloperNative {
    [CmdletBinding()]
    param([string]$Path, [string[]]$Arguments, [string]$Directory = (Get-ShowcaseRoot),
        [ValidateRange(1, 7200)][int]$TimeoutSeconds = 1800)
    $result = Invoke-NativeCommand -FilePath $Path -ArgumentList $Arguments `
        -WorkingDirectory $Directory -TimeoutSeconds $TimeoutSeconds
    if ($result.Output) { Write-ShowcaseMessage $result.Output }
    if ($result.ExitCode -ne 0 -or $result.TimedOut) {
        throw "Developer task failed (exit $($result.ExitCode), timeout $($result.TimedOut)); see the diagnostics above."
    }
    return $result
}

function Get-DeveloperPython {
    [CmdletBinding()]
    param([string]$Directory, [switch]$Lint, [switch]$Coverage)
    $python = Join-Path $Directory '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw 'NOT RUN: sample .venv is absent. Run Restore Python yourself after IT supplies Python 3.14 and uv.'
    }
    Assert-SafeDirectory (Split-Path -Parent $python)
    $packages = @('fastapi==0.118.0', 'pydantic==2.12.4', 'uvicorn==0.37.0',
        'httpx==0.28.1', 'pytest==8.3.4')
    if ($Lint) { $packages += 'ruff==0.14.3' }
    if ($Coverage) { $packages += @('pytest-cov==7.0.0', 'coverage==7.10.6') }
    $check = @'
import importlib.metadata as m, sys
assert sys.version_info[:2] == (3, 14), "Python 3.14 is required"
for pin in sys.argv[1:]:
    name, version = pin.split("==")
    assert m.version(name) == version, f"Missing/mismatched {pin}; run explicit Restore"
'@
    $null = Invoke-DeveloperNative $python (@('-c', $check) + $packages) $Directory
    return $python
}

function Get-DeveloperGo {
    [CmdletBinding()]
    param([string]$Directory)
    $go = Get-DeveloperTool go
    $version = Invoke-DeveloperNative $go @('version') $Directory
    if ($version.StdOut -notmatch '^go version go1\.27\.3\s') {
        throw 'NOT RUN: the Go sample requires the manifest-defined Go 1.27.3; no toolchain download/substitution.'
    }
    return $go
}

function Get-DeveloperMaven {
    [CmdletBinding()]
    param([string]$Directory, [string]$Sample, [switch]$Restore)
    if (-not $env:JAVA_HOME) { throw 'NOT RUN: select the documented JDK using JAVA_HOME; no runtime substitution.' }
    $java = Join-Path $env:JAVA_HOME 'bin\java.exe'
    if (-not (Test-Path -LiteralPath $java -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\javac.exe') -PathType Leaf)) {
        throw 'NOT RUN: JAVA_HOME must contain the documented full JDK, not just a JRE.'
    }
    $version = Invoke-DeveloperNative $java @('-version') $Directory
    $required = if ($Sample -eq 'Legacy') { '11' } else { '25' }
    if ($version.Output -notmatch ('version "' + $required + '(?:[."+-])')) {
        throw "NOT RUN: $Sample requires Java $required on JAVA_HOME."
    }
    $wrapper = Join-Path $Directory 'mvnw.cmd'
    if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $Directory '.mvn\wrapper\maven-wrapper.jar') -PathType Leaf)) {
        throw 'NOT RUN: checked-in Maven wrapper files are missing.'
    }
    if (-not $Restore) {
        $mavenHome = $env:MAVEN_USER_HOME
        if (-not $mavenHome) { $mavenHome = Join-Path $HOME '.m2' }
        # Wrapper 3.3.4 keys this exact distribution URI using Java URI.hashCode.
        # Both the ZIP and unpacked directory are needed to avoid wrapper restore.
        $cache = Join-Path $mavenHome 'wrapper\dists\apache-maven-3.9.16-bin\4200fbc6'
        Assert-SafeDirectory $cache
        $distribution = Join-Path $cache 'apache-maven-3.9.16'
        $zip = Join-Path $cache 'apache-maven-3.9.16-bin.zip'
        if (-not (Test-Path -LiteralPath (Join-Path $distribution 'bin\mvn.cmd') -PathType Leaf) -or
            -not (Test-Path -LiteralPath $zip -PathType Leaf)) {
            throw 'NOT RUN: Maven 3.9.16 ZIP/unpacked wrapper cache is missing. Run Restore Java yourself.'
        }
        Assert-SafeDirectory (Join-Path $distribution 'bin')
        $directories = @(Get-ChildItem -LiteralPath $cache -Directory)
        $properties = Get-Content -LiteralPath (Join-Path $Directory '.mvn\wrapper\maven-wrapper.properties') -Raw
        $jvmOptions = ''
        $jvmConfiguration = Join-Path $Directory '.mvn\jvm.config'
        if (Test-Path -LiteralPath $jvmConfiguration -PathType Leaf) {
            $jvmOptions = Get-Content -LiteralPath $jvmConfiguration -Raw
        }
        if ($directories.Count -ne 1 -or
            $properties -notmatch '(?m)^distributionUrl=https://repo\.maven\.apache\.org/maven2/org/apache/maven/apache-maven/3\.9\.16/apache-maven-3\.9\.16-bin\.zip\r?$' -or
            $properties -match '(?m)^(?:alwaysDownload|alwaysUnpack|distributionBase|distributionPath|zipBase|zipPath)=' -or
            $env:MVNW_REPOURL -or $env:MAVEN_OPTS -match 'maven\.user\.home|user\.home' -or
            $jvmOptions -match 'maven\.user\.home|user\.home') {
            throw 'NOT RUN: wrapper cache overrides prevent proving a no-restoration execution.'
        }
    }
    return $wrapper
}

function Import-DeveloperModule {
    [CmdletBinding()]
    param([ValidateSet('Pester', 'PSScriptAnalyzer')][string]$Name)
    $version = if ($Name -eq 'Pester') { '5.7.1' } else { '1.24.0' }
    $manifest = Join-Path (Get-ShowcaseRoot) ".tools\powershell\$Name\$version\$Name.psd1"
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "NOT RUN: project-local $Name $version is missing. Run Restore PowerShell yourself."
    }
    Assert-SafeDirectory (Split-Path -Parent $manifest)
    $metadata = Test-ModuleManifest -Path $manifest
    if ($metadata.Version -ne [version]$version) { throw "NOT RUN: $Name version does not match the reviewed pin." }
    Import-Module -Name $manifest -Force -ErrorAction Stop
}

function Invoke-DeveloperRestore {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$Sample)
    if (-not $PSCmdlet.ShouldProcess($Sample, 'Restore dependencies from reviewed registries (user-run only)')) { return }
    if ($Sample -eq 'PowerShell') {
        $null = Get-Command Save-Module -ErrorAction Stop
        # Save-Module must not bootstrap NuGet or change repository trust/policy.
        $providers = @(Get-PackageProvider -ListAvailable -ErrorAction Stop | Where-Object {
            $_.Name -eq 'NuGet' -and $_.Version -ge [version]'2.8.5.201'
        })
        if ($providers.Count -eq 0) {
            throw 'NOT RUN: an existing NuGet provider >=2.8.5.201 is required; IT must arrange it. No provider install is attempted.'
        }
        $repository = Get-PSRepository -Name PSGallery -ErrorAction Stop
        if ($repository.SourceLocation -ne 'https://www.powershellgallery.com/api/v2') {
            throw 'NOT RUN: PSGallery must point to its official HTTPS source; no repository configuration is changed.'
        }
        $tools = Join-Path (Get-ShowcaseRoot) '.tools\powershell'
        Assert-SafeDirectory $tools
        if (-not (Test-Path -LiteralPath $tools)) { $null = New-Item -ItemType Directory -Path $tools }
        Save-Module -Name Pester -RequiredVersion '5.7.1' -Repository PSGallery -Path $tools -ErrorAction Stop
        Save-Module -Name PSScriptAnalyzer -RequiredVersion '1.24.0' -Repository PSGallery -Path $tools -ErrorAction Stop
        return
    }
    $directory = Get-DeveloperDirectory $Sample
    switch ($Sample) {
        'Python' {
            $uv = Get-DeveloperTool uv
            # Check only existing interpreters. uv sync is explicitly allowed here,
            # but downloading a Python runtime is never part of project restore.
            $null = Invoke-DeveloperNative $uv @('python', 'find', '3.14', '--no-python-downloads') $directory
            $null = Invoke-DeveloperNative $uv @('sync', '--locked', '--no-python-downloads') $directory
        }
        'Go' {
            $go = Get-DeveloperGo $directory
            $null = Invoke-DeveloperNative $go @('mod', 'download') $directory
        }
        default {
            $maven = Get-DeveloperMaven $directory $Sample -Restore
            $null = Invoke-DeveloperNative $maven @('-B',
                'org.apache.maven.plugins:maven-dependency-plugin:3.9.0:go-offline') $directory
            # Warm dynamic test-provider/plugin dependencies too. This is explicitly
            # a restore operation, never part of Test/Lint/Coverage.
            $null = Invoke-DeveloperNative $maven @('-B', 'verify') $directory
            if ($Sample -eq 'Java') {
                $null = Invoke-DeveloperNative $maven @('-B', 'checkstyle:check') $directory
            }
        }
    }
}

function Restore-DeveloperImage {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$Sample, [string]$Runtime)
    $directory = Get-DeveloperDirectory $Sample
    if (-not $PSCmdlet.ShouldProcess($Sample, 'Explicitly build/restore the user-run container image and its dependencies')) { return }
    Assert-WorkstationPolicy
    $runtimeInfo = Get-ContainerRuntime -Preferred $Runtime
    $image = 'win11-demo/' + (Split-Path -Leaf $directory) + ':latest'
    $null = Invoke-DeveloperNative $runtimeInfo.Path @('build', '-t', $image, '.') $directory
}

function Invoke-DeveloperCheck {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Action, [string]$Sample)
    if (-not $PSCmdlet.ShouldProcess($Sample, "$Action using only existing dependencies; write local reports")) { return }
    if ($Sample -eq 'PowerShell') {
        if ($Action -eq 'Lint') {
            Import-DeveloperModule PSScriptAnalyzer
            $issues = @(Invoke-ScriptAnalyzer -Path (Join-Path (Get-ShowcaseRoot) 'scripts') -Recurse -Severity Error,Warning)
            $issues | Format-Table -AutoSize | Out-Host
            if ($issues.Count -gt 0) { throw 'PowerShell lint reported findings.' }
        } else {
            Import-DeveloperModule Pester
            $artifacts = Join-Path (Get-ShowcaseRoot) 'artifacts'
            Assert-SafeDirectory $artifacts
            if (-not (Test-Path -LiteralPath $artifacts)) { $null = New-Item -ItemType Directory -Path $artifacts }
            $configuration = New-PesterConfiguration
            $configuration.Run.Path = Join-Path (Get-ShowcaseRoot) 'tests'
            $configuration.Run.PassThru = $true
            $configuration.TestResult.Enabled = $true
            $configuration.TestResult.OutputFormat = 'NUnitXml'
            $configuration.TestResult.OutputPath = Join-Path $artifacts 'pester.xml'
            if ($Action -eq 'Coverage') {
                $configuration.CodeCoverage.Enabled = $true
                $configuration.CodeCoverage.Path = Join-Path $PSScriptRoot 'developer.ps1'
                $configuration.CodeCoverage.OutputPath = Join-Path $artifacts 'powershell-coverage.xml'
                $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
            }
            $result = Invoke-Pester -Configuration $configuration
            if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0) { throw 'PowerShell tests failed or discovered no tests.' }
        }
        return
    }
    $directory = Get-DeveloperDirectory $Sample
    switch ($Sample) {
        'Python' {
            $python = Get-DeveloperPython $directory -Lint:($Action -eq 'Lint') -Coverage:($Action -eq 'Coverage')
            $arguments = if ($Action -eq 'Lint') { @('-m', 'ruff', 'check', 'app', 'tests') } else {
                @('-m', 'pytest', '--junitxml=test-results.xml')
            }
            if ($Action -eq 'Coverage') {
                $arguments += @('--cov=app', '--cov-branch', '--cov-report=term-missing',
                    '--cov-report=xml:coverage.xml', '--cov-report=html:htmlcov')
            }
            $null = Invoke-DeveloperNative $python $arguments $directory
        }
        'Go' {
            $go = Get-DeveloperGo $directory
            if ($Action -eq 'Lint') {
                $null = Invoke-DeveloperNative $go @('vet', './...') $directory
                $gofmt = Get-DeveloperTool gofmt
                $format = Invoke-DeveloperNative $gofmt @('-l', '.') $directory
                if ($format.StdOut.Trim()) { throw 'Go formatting differs; run gofmt yourself and review the diff.' }
            } else {
                $arguments = @('test', '-json', './...')
                if ($Action -eq 'Coverage') { $arguments = @('test', '-json', '-coverprofile=coverage.out', '-covermode=atomic', './...') }
                $result = Invoke-NativeCommand $go $arguments -WorkingDirectory $directory -TimeoutSeconds 1800
                [IO.File]::WriteAllText((Join-Path $directory 'test-results.json'), $result.StdOut)
                if ($result.Output) { Write-ShowcaseMessage $result.Output }
                Assert-NativeSuccess $result 'Go tests'
                if ($Action -eq 'Coverage') {
                    $null = Invoke-DeveloperNative $go @('tool', 'cover', '-html=coverage.out', '-o', 'coverage.html') $directory
                }
            }
        }
        default {
            if ($Sample -eq 'Legacy' -and $Action -ne 'Test') { throw 'Legacy supports opt-in Test only; modernization tooling is user-led.' }
            $maven = Get-DeveloperMaven $directory $Sample
            $goal = if ($Action -eq 'Lint') { 'checkstyle:check' } else { 'verify' }
            $null = Invoke-DeveloperNative $maven @('-o', '-B', $goal) $directory
        }
    }
}

function Start-DeveloperSample {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$Sample, [switch]$Container, [string]$Runtime, [int]$Port)
    $directory = Get-DeveloperDirectory $Sample
    if (-not $PSCmdlet.ShouldProcess($Sample, 'Launch user-operated application/container')) { return }
    Assert-WorkstationPolicy
    if ($Container) {
        $runtimeInfo = Get-ContainerRuntime -Preferred $Runtime
        $name = 'win11-demo-' + (Split-Path -Leaf $directory)
        $image = 'win11-demo/' + (Split-Path -Leaf $directory) + ':latest'
        $inspection = Invoke-NativeCommand $runtimeInfo.Path @('image', 'inspect', $image) `
            -WorkingDirectory $directory -TimeoutSeconds 60
        if ($inspection.ExitCode -ne 0) {
            throw 'NOT RUN: local container image is unavailable. Use Restore -RestoreTarget ContainerImages explicitly; Run never builds or pulls.'
        }
        $null = Invoke-DeveloperNative $runtimeInfo.Path @('run', '--pull=never', '-d', '--name', $name,
            '--label', 'io.win11-dev-workstation.showcase=true', '-p', "127.0.0.1:${Port}:8080", $image) $directory
        $null = Wait-SampleHealth -Port $Port -TimeoutSeconds 90
        Write-ShowcaseMessage "[PASS] http://127.0.0.1:$Port; stop/remove $name yourself using $($runtimeInfo.Name)."
        return
    }
    switch ($Sample) {
        'Python' {
            $path = Get-DeveloperPython $directory
            $arguments = @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', [string]$Port)
        }
        'Go' { $path = Get-DeveloperGo $directory; $arguments = @('run', '.') }
        default {
            $path = Get-DeveloperMaven $directory $Sample
            $arguments = @('-o', '-B', 'spring-boot:run', "-Dspring-boot.run.arguments=--server.port=$Port")
        }
    }
    Push-Location -LiteralPath $directory
    try {
        $env:PORT = [string]$Port
        $PSNativeCommandUseErrorActionPreference = $false
        & $path @arguments | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Local application failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
}

function Invoke-DeveloperCluster {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$Action, [string]$Sample, [string]$Namespace, [int]$Port)
    if ($Namespace.Length -gt 63 -or $Namespace -notmatch '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$') {
        throw 'An existing DNS-label AKS_NAMESPACE is required; no credentials/namespace/context are created.'
    }
    $services = @{ Python = 'emi'; Java = 'ifsc'; Go = 'fx' }
    if (-not $services.ContainsKey($Sample)) { throw 'Select Python, Java or Go for Kubernetes tasks.' }
    $kubectl = Get-DeveloperTool kubectl
    $service = $services[$Sample]
    if ($Action -eq 'KubernetesPortForward') {
        if (-not $PSCmdlet.ShouldProcess($service, 'Port-forward through the current approved Kubernetes context')) { return }
        & $kubectl '--namespace' $Namespace 'port-forward' "service/$service" "${Port}:8080" '--address' '127.0.0.1' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Kubernetes port-forward failed.' }
    } else {
        $arguments = if ($Action -eq 'KubernetesLogs') {
            @('--namespace', $Namespace, 'logs', "deployment/$service", '--tail=100')
        } else {
            @('--namespace', $Namespace, 'get', 'deployment,service,pods', '-l', "app=$service")
        }
        $null = Invoke-DeveloperNative $kubectl $arguments
    }
}

function Invoke-Developer {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([string]$Action, [string]$Sample = 'All', [string]$Runtime = 'auto',
        [ValidateSet('Dependencies', 'ContainerImages')][string]$RestoreTarget = 'Dependencies',
        [int]$Port = 8080, [string]$SourceSha = '', [AllowNull()][string]$Namespace,
        [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5)
    $environment = @{}
    foreach ($key in @('UV_OFFLINE', 'UV_NO_SYNC', 'UV_PYTHON_DOWNLOADS', 'GOTOOLCHAIN',
        'GOPROXY', 'GOSUMDB', 'PORT')) {
        $environment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    }
    try {
        $env:UV_PYTHON_DOWNLOADS = 'never'
        $env:GOTOOLCHAIN = 'local'
        if ($Action -eq 'Restore') {
            $env:UV_OFFLINE = '0'
            $env:UV_NO_SYNC = '0'
        } else {
            $env:UV_OFFLINE = '1'
            $env:UV_NO_SYNC = '1'
            $env:GOPROXY = 'off'
            $env:GOSUMDB = 'off'
        }
        switch ($Action) {
            'Preflight' {
                $shell = (Get-Process -Id $PID).Path
                $null = Invoke-DeveloperNative $shell @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'preflight.ps1'),
                    '-HttpsTimeoutSeconds', [string]$HttpsTimeoutSeconds) -TimeoutSeconds (Get-PreflightTimeout $HttpsTimeoutSeconds)
            }
            'SetupPreview' {
                Write-ShowcaseMessage 'Read-only source/config preview; bootstrap is NOT invoked (not even with WhatIf).'
                Write-ShowcaseMessage "Selected HTTPS timeout: $HttpsTimeoutSeconds seconds/attempt; preflight budget: $(Get-PreflightTimeout $HttpsTimeoutSeconds) seconds."
                foreach ($file in @('.config\configuration.winget', '.config\java-modernization.winget', 'scripts\bootstrap.ps1')) {
                    Write-ShowcaseMessage "----- $file -----"
                    Get-Content -LiteralPath (Join-Path (Get-ShowcaseRoot) $file) | Out-Host
                }
            }
            { $_ -in @('Setup', 'FinishSetup') } {
                if ($PSCmdlet.ShouldProcess('Workstation', 'User-run approved setup; may elevate/restart; confirm in the child terminal')) {
                    $shell = (Get-Process -Id $PID).Path
                    $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'bootstrap.ps1'),
                        '-HttpsTimeoutSeconds', [string]$HttpsTimeoutSeconds, '-Confirm')
                    if ($Action -eq 'FinishSetup') { $arguments += '-SkipBase' }
                    & $shell @arguments | Out-Host
                    if ($LASTEXITCODE -ne 0) { throw 'User-run setup failed.' }
                }
            }
            { $_ -in @('Test', 'Coverage', 'Lint', 'Restore') } {
                $failed = @()
                $selected = @(Get-DeveloperSample $Sample)
                if ($Action -eq 'Restore' -and $RestoreTarget -eq 'ContainerImages' -and $Sample -eq 'All') {
                    $selected = @($selected | Where-Object { $_ -ne 'PowerShell' })
                }
                foreach ($item in $selected) {
                    try {
                        if ($Action -eq 'Restore' -and $RestoreTarget -eq 'ContainerImages') {
                            Restore-DeveloperImage $item -Runtime $Runtime -WhatIf:$WhatIfPreference
                        } elseif ($Action -eq 'Restore') { Invoke-DeveloperRestore $item -WhatIf:$WhatIfPreference }
                        else { Invoke-DeveloperCheck $Action $item -WhatIf:$WhatIfPreference }
                    } catch { $failed += $item; Write-ShowcaseMessage "[FAIL] ${item}: $($_.Exception.Message)" }
                }
                if ($failed.Count -gt 0) { throw "$Action failed/NOT RUN for: $($failed -join ', ')." }
            }
            { $_ -in @('RunLocal', 'RunContainer') } {
                Start-DeveloperSample $Sample -Container:($Action -eq 'RunContainer') -Runtime $Runtime -Port $Port -WhatIf:$WhatIfPreference
            }
            'WorkflowStatus' {
                $null = Invoke-DeveloperNative (Get-DeveloperTool gh) @('run', 'list', '--repo',
                    'hrshl-demo/win11-dev-workstation-showcase', '--limit', '10')
            }
            'DeployDispatch' {
                if ($SourceSha -notmatch '^[0-9a-f]{40}$') { throw 'DeployDispatch requires the current main SourceSha (40 lowercase hex characters).' }
                if (-not $PSCmdlet.ShouldProcess('main', "Dispatch deploy-aks.yml for reviewed SHA $SourceSha (requires GitHub approval)")) { return 0 }
                $gh = Get-DeveloperTool gh
                $main = Invoke-DeveloperNative $gh @('api', 'repos/hrshl-demo/win11-dev-workstation-showcase/commits/main', '--jq', '.sha')
                if ($main.StdOut.Trim() -cne $SourceSha) { throw 'source_sha is not current remote main; dispatch refused.' }
                $null = Invoke-DeveloperNative $gh @('workflow', 'run', 'deploy-aks.yml', '--repo',
                    'hrshl-demo/win11-dev-workstation-showcase', '--ref', 'main', '-f', "source_sha=$SourceSha")
            }
            'KubernetesCheck' {
                $python = Get-DeveloperTool python
                $null = Invoke-DeveloperNative $python @('tests/check_kubernetes.py')
            }
            { $_ -in @('KubernetesStatus', 'KubernetesLogs', 'KubernetesPortForward') } {
                Invoke-DeveloperCluster $Action $Sample $Namespace $Port -WhatIf:$WhatIfPreference
            }
            default { throw 'Unsupported developer action.' }
        }
        Write-ShowcaseMessage "[PASS] $Action completed."
        return 0
    } catch {
        Write-ShowcaseMessage "[FAIL] $($_.Exception.Message)"
        return 1
    } finally {
        foreach ($key in $environment.Keys) { [Environment]::SetEnvironmentVariable($key, $environment[$key], 'Process') }
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Developer @PSBoundParameters) }
