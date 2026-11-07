<#
.SYNOPSIS
Run a synthetic banking sample locally or in an approved container runtime.
.DESCRIPTION
Local mode runs in the foreground (Ctrl+C stops it), using uv, mvnw.cmd or Go.
Port controls the local listener or the container's published host port.
Container mode prefers wslc and falls back to Docker only when wslc is absent,
never after a policy or runtime denial. Existing same-name containers are not
replaced. A successful /health response is required before printing the URL.
.PARAMETER Name
python-emi-api, java-ifsc-service or go-fx-rates.
.PARAMETER Mode
local (default) or container.
.PARAMETER Port
Local listener / published host port; defaults to 8080.
.PARAMETER HealthTimeoutSeconds
Maximum health wait, defaults to 90 seconds.
.EXAMPLE
.\scripts\run-sample.ps1 -Name python-emi-api -Mode container -Port 8081
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][ValidateSet('python-emi-api', 'java-ifsc-service', 'go-fx-rates')][string]$Name,
    [ValidateSet('local', 'container')][string]$Mode = 'local',
    [ValidateRange(1, 65535)][int]$Port = 8080,
    [ValidateRange(1, 600)][int]$HealthTimeoutSeconds = 90
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Get-LocalSampleCommand {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Directory, [int]$Port)
    switch ($Name) {
        'python-emi-api' {
            $path = Get-NativeCommandPath uv
            $arguments = @('run', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', [string]$Port)
        }
        'java-ifsc-service' {
            $path = Join-Path $Directory 'mvnw.cmd'
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Windows Maven wrapper mvnw.cmd is missing.' }
            $arguments = @('-B', 'spring-boot:run', "-Dspring-boot.run.arguments=--server.port=$Port")
        }
        'go-fx-rates' {
            $path = Get-NativeCommandPath go
            $arguments = @('run', '.')
        }
        default { throw "Unknown sample: $Name" }
    }
    if (-not $path) { throw "Required local tooling for $Name is not on PATH." }
    [pscustomobject]@{ Path = $path; Arguments = $arguments }
}

function Invoke-LocalSampleProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([int])]
    param([Parameter(Mandatory)][object]$Command, [string]$Directory,
        [string]$Name, [int]$Port)
    if (-not $PSCmdlet.ShouldProcess($Name, "Run local server on port $Port")) { return 0 }
    $originalPort = [Environment]::GetEnvironmentVariable('PORT', 'Process')
    Push-Location -LiteralPath $Directory
    try {
        if ($Name -eq 'go-fx-rates') { $env:PORT = [string]$Port }
        Write-ShowcaseMessage "[PASS] Starting $Name at http://127.0.0.1:$Port (foreground; Ctrl+C to stop)."
        $ErrorActionPreference = 'Continue'
        # PowerShell 7 must not turn native stderr into terminating errors.
        $PSNativeCommandUseErrorActionPreference = $false
        & $Command.Path @($Command.Arguments) | Out-Host
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw "Local sample exited with code $code." }
        return 0
    } finally {
        [Environment]::SetEnvironmentVariable('PORT', $originalPort, 'Process')
        Pop-Location
    }
}

function Invoke-Sample {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$Name, [string]$Mode = 'local',
        [int]$Port = 8080, [int]$HealthTimeoutSeconds = 90)
    $runtime = $null
    $started = $false
    $containerName = "win11-demo-$Name"
    try {
        $directory = Join-Path (Get-ShowcaseRoot) "samples\$Name"
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Sample directory missing: $directory" }
        Assert-SafeDirectory $directory
        if ($Mode -eq 'local') {
            $command = Get-LocalSampleCommand -Name $Name -Directory $directory -Port $Port
            return (Invoke-LocalSampleProcess -Command $command -Directory $directory -Name $Name -Port $Port -WhatIf:$WhatIfPreference)
        }
        $runtime = Get-ContainerRuntime
        Write-ShowcaseMessage "[PASS] Container runtime: $($runtime.Name) ($($runtime.Path))."
        if (-not $PSCmdlet.ShouldProcess($containerName, "Build $Name and run container, publishing localhost port $Port")) { return 0 }
        $existing = Invoke-NativeCommand $runtime.Path @('ps', '-a', '--filter', "name=$containerName", '--format', '{{.Names}}')
        Assert-NativeSuccess $existing "List $($runtime.Name) containers (no runtime fallback on denial)"
        if (@($existing.StdOut -split '[\r\n]+' | Where-Object { $_.Trim() -eq $containerName }).Count -gt 0) {
            throw "Container $containerName already exists. Use demo-reset.ps1 after reviewing its confirmation."
        }
        $image = "win11-demo/${Name}:latest"
        $build = Invoke-NativeCommand $runtime.Path @('build', '-t', $image, $directory) -TimeoutSeconds 1800
        if ($build.Output) { Write-ShowcaseMessage $build.Output }
        Assert-NativeSuccess $build 'Build sample image'
        $run = Invoke-NativeCommand $runtime.Path @('run', '-d', '-p', "127.0.0.1:${Port}:8080",
            '--name', $containerName, '--label', 'io.win11-dev-workstation.showcase=true', $image) -TimeoutSeconds 120
        Assert-NativeSuccess $run 'Start sample container'
        $started = $true
        $health = Wait-SampleHealth -Port $Port -TimeoutSeconds $HealthTimeoutSeconds
        Write-ShowcaseMessage "[PASS] Health ready: $health"
        Write-ShowcaseMessage "[PASS] Sample URL: http://127.0.0.1:$Port"
        return 0
    } catch {
        Write-ShowcaseMessage "[FAIL] Sample: $($_.Exception.Message)"
        if ($started -and $null -ne $runtime -and $PSCmdlet.ShouldProcess($containerName, 'Stop and remove the container created by this failed run')) {
            try {
                $stop = Invoke-NativeCommand $runtime.Path @('stop', $containerName)
                Assert-NativeSuccess $stop 'Stop failed demo container'
                $remove = Invoke-NativeCommand $runtime.Path @('rm', $containerName)
                Assert-NativeSuccess $remove 'Remove failed demo container'
            } catch { Write-ShowcaseMessage "[WARN] Failed-run cleanup: $($_.Exception.Message)" }
        }
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Sample @PSBoundParameters) }
