<#
.SYNOPSIS
Shared read-only checks, native command isolation, and safety helpers.
.DESCRIPTION
Used by the showcase scripts on Windows PowerShell 5.1 and PowerShell 7.
Organisation policy is reported, never modified or bypassed.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ShowcaseRoot {
    <#
    .SYNOPSIS
    Resolve the repository root relative to this shared module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    Split-Path -Parent $PSScriptRoot
}

function Write-ShowcaseMessage {
    <#
    .SYNOPSIS
    Write an interactive status message to the information stream, not JSON.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Information -MessageData $Message -InformationAction Continue
}

function Get-CheckResult {
    <#
    .SYNOPSIS
    Create an in-memory readiness result without changing workstation state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$Expected = '',
        [string]$Found = ''
    )
    [pscustomobject][ordered]@{
        Name = $Name; Expected = $Expected; Found = $Found
        Status = $Status; Message = $Message
    }
}

function Write-CheckReport {
    <#
    .SYNOPSIS
    Print checks as clean JSON, a table, or interactive status messages.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Checks,
        [switch]$Json, [switch]$Quiet, [switch]$Table)
    if ($Json) {
        ConvertTo-Json -InputObject @($Checks) -Depth 5
    } elseif ($Table) {
        $Checks | Select-Object @{Name = 'Tool'; Expression = { $_.Name }},
            Expected, Found, Status | Format-Table -AutoSize | Out-Host
        $Checks | Where-Object { $_.Status -ne 'PASS' } |
            ForEach-Object { Write-Information -MessageData "[$($_.Status)] $($_.Name): $($_.Message)" -InformationAction Continue }
    } else {
        foreach ($check in $Checks) {
            if (-not $Quiet -or $check.Status -eq 'FAIL') {
                Write-Information -MessageData "[$($check.Status)] $($check.Name): $($check.Message)" -InformationAction Continue
            }
        }
    }
}

function Get-CheckExitCode {
    <#
    .SYNOPSIS
    Return zero for success, one for failures, or two for blocked repairs.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([AllowEmptyCollection()][object[]]$Checks = @(), [switch]$PolicyRepair)
    if (@($Checks | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0) {
        if ($PolicyRepair) { return 2 }
        return 1
    }
    return 0
}

function Get-WinGetPolicy {
    <#
    .SYNOPSIS
    Report effective AppInstaller registry policy values without changing them.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller'
    $values = $null
    if (Test-Path -LiteralPath $path) {
        $values = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    }
    foreach ($name in @('EnableAppInstaller',
        'EnableWindowsPackageManagerCommandLineInterfaces',
        'EnableWindowsPackageManagerConfiguration', 'EnableAllowedSources', 'EnableDefaultSource')) {
        $property = if ($null -ne $values) { $values.PSObject.Properties[$name] } else { $null }
        if ($null -eq $property) {
            Get-CheckResult -Name $name -Status PASS -Message 'Not configured (no explicit policy block).' -Found 'Not configured'
        } elseif ([string]$property.Value -eq '0') {
            Get-CheckResult -Name $name -Status FAIL -Found '0' -Message 'Blocked by organisation policy, contact IT. Contact IT: this script does not change organisation policy.'
        } else {
            Get-CheckResult -Name $name -Status PASS -Found ([string]$property.Value) -Message "Policy value: $($property.Value)."
        }
    }
}

function Assert-WinGetPolicy {
    <#
    .SYNOPSIS
    Stop on explicit organisation policy blocks without bypassing them.
    #>
    [CmdletBinding()]
    param()
    $blocked = @(Get-WinGetPolicy | Where-Object { $_.Status -eq 'FAIL' })
    if ($blocked.Count -gt 0) {
        throw (($blocked | ForEach-Object { "$($_.Name): $($_.Message)" }) -join ' ')
    }

}

function Assert-WorkstationPolicy {
    <#
    .SYNOPSIS
    Policy guard exported for the workstation WinGet configuration.
    #>
    [CmdletBinding()]
    param()
    Assert-WinGetPolicy
}

function Get-NativeCommandPath {
    <#
    .SYNOPSIS
    Resolve an application on PATH, excluding aliases and functions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) { return $command.Source }
    return $null
}

function ConvertTo-NativeArgument {
    <#
    .SYNOPSIS
    Quote one Windows native command argument.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting, including trailing backslashes.
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
    Capture native stdout, stderr, exit status and timeout as one result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(), [string]$WorkingDirectory = '',
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
        [AllowEmptyString()][string]$InputText)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputText')
    $arguments = ($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($FilePath) -in @('.cmd', '.bat')) {
        if ($FilePath -match '["%!\r\n]' -or $arguments -match '[%!\r\n&|<>^]') {
            throw 'Unsafe batch command arguments.'
        }
        $start.FileName = $env:ComSpec
        $start.Arguments = '/d /s /c ""' + $FilePath + '" ' + $arguments + '"'
    } else {
        $start.FileName = $FilePath
        $start.Arguments = $arguments
    }
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $FilePath." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($start.RedirectStandardInput) {
            $process.StandardInput.Write($InputText)
            $process.StandardInput.Close()
        }
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill()
            $process.WaitForExit()
        }
        $outText = $stdout.GetAwaiter().GetResult()
        $errText = $stderr.GetAwaiter().GetResult()
        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        [pscustomobject]@{
            ExitCode = $exitCode; StdOut = $outText; StdErr = $errText
            Output = ($outText + "`n" + $errText).Trim(); TimedOut = $timedOut
        }
    } finally {
        $process.Dispose()
    }
}

function Assert-NativeSuccess {
    <#
    .SYNOPSIS
    Throw when a native command returned a nonzero exit code.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Result, [Parameter(Mandatory)][string]$Action)
    if ($Result.ExitCode -ne 0) { throw "$Action failed (exit $($Result.ExitCode)): $($Result.Output)" }
}

function Get-ContainerRuntime {
    <#
    .SYNOPSIS
    Prefer wslc; use Docker only if wslc is absent.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    foreach ($name in @('wslc', 'docker')) {
        $path = Get-NativeCommandPath $name
        if ($path) {
            # Availability is not permission: never fall back after a denied wslc command.
            return [pscustomobject]@{ Name = $name; Path = $path }
        }
    }
    throw 'No container runtime found. Use approved WSL containers, or Docker only where already licensed.'
}

function Test-HttpsEndpoint {
    <#
    .SYNOPSIS
    Probe HTTPS with TLS 1.2 and a bounded timeout.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][uri]$Uri, [ValidateRange(1, 60)][int]$TimeoutSeconds = 5)
    if ($Uri.Scheme -ne 'https') { throw 'Readiness probes must use HTTPS.' }
    $originalTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $originalTls -bor [Net.SecurityProtocolType]::Tls12
        $response = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    } catch {
        # A server denying HEAD still proves the HTTPS connection reached that server.
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) { return $true }
        return $false
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalTls
    }
}

function Wait-SampleHealth {
    <#
    .SYNOPSIS
    Wait for an HTTP 200 health response on the loopback port.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 90)
    $uri = "http://127.0.0.1:$Port/health"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $remaining = [Math]::Max(1, [Math]::Ceiling($TimeoutSeconds - $watch.Elapsed.TotalSeconds))
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec ([Math]::Min(2, $remaining)) -ErrorAction Stop
            if ($response.StatusCode -eq 200) { return $uri }
        } catch {
            Write-Verbose "Health not ready: $($_.Exception.Message)"
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Health check timed out after $TimeoutSeconds seconds: $uri"
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
    Report current elevation without requesting it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } finally { $identity.Dispose() }
}

function Test-BaseResumePending {
    <#
    .SYNOPSIS
    Detect Microsoft setup resume tasks or pending reboot markers.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $task = Get-ScheduledTask -TaskName WindowsDevConfigResume -ErrorAction SilentlyContinue
    if ($null -ne $task -and $task.State -ne 'Disabled') { return $true }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path -LiteralPath $key) { return $true }
    }
    return $false
}

function Assert-SafeDirectory {
    <#
    .SYNOPSIS
    Refuse file or reparse-point directories and ancestors.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Unsafe directory (not a regular directory or is a reparse point): $cursor"
            }
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Get-RequiredExtension {
    <#
    .SYNOPSIS
    Read the 12 default or 13 modernization extension requirements.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path, [switch]$IncludeJavaModernization)
    $extensionProfile = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $extensions = @($extensionProfile.recommendations)
    if ($extensions.Count -ne 13 -or @($extensions | Select-Object -Unique).Count -ne 13 -or
        $extensions -notcontains 'vscjava.migrate-java-to-azure') {
        throw 'Expected 13 unique recommendations in the workspace extension profile.'
    }

    foreach ($extension in $extensions) {
        if ($extension -eq 'vscjava.migrate-java-to-azure' -and -not $IncludeJavaModernization) { continue }
        $extension
    }
}

function Assert-SafeSampleTree {
    <#
    .SYNOPSIS
    Check sample descendants without traversing reparse points.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    Assert-SafeDirectory $Path
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $directories = New-Object 'Collections.Generic.Stack[string]'
    $directories.Push($Path)
    while ($directories.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $directories.Pop() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point present under samples; refusing destructive reset: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $directories.Push($item.FullName) }
        }
    }
}

function Read-MicrosoftSignedScript {
    <#
    .SYNOPSIS
    Read locked setup text only after its valid Microsoft signature is checked.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Downloaded setup must be a regular file.'
    }
    # Lock out writes/deletion while both the signature and executable text
    # are read. The execution payload never rereads an unlocked pathname.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw 'Microsoft setup signature is not Valid with a Microsoft Corporation signer. Refusing to execute.'
        }
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

Export-ModuleMember -Function Get-ShowcaseRoot, Get-CheckResult, Write-CheckReport, Write-ShowcaseMessage,
    Get-CheckExitCode, Get-WinGetPolicy, Assert-WinGetPolicy, Assert-WorkstationPolicy, Get-NativeCommandPath,
    ConvertTo-NativeArgument, Invoke-NativeCommand, Assert-NativeSuccess,
    Get-ContainerRuntime, Test-HttpsEndpoint, Wait-SampleHealth, Test-IsAdministrator,
    Test-BaseResumePending, Assert-SafeDirectory, Get-RequiredExtension,
    Read-MicrosoftSignedScript, Assert-SafeSampleTree
