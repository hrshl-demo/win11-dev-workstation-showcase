<#
.SYNOPSIS
Verify the installed tools and VS Code workspace extension profile.
.DESCRIPTION
Read-only. The default profile requires 12 extensions; the optional Java
modernization profile requires all 13 recommendations. Missing required tools
or wrong required versions return exit 1. Authentication is not inspected.
Before setup this exit 1 is expected inventory, not an installation failure
or the bootstrap preflight gate. After setup required FAIL means not accepted.
Extension listing uses the CLI without a profile argument; confirm approved
source/profile and enabled extensions in the intended window separately.
.PARAMETER RunConfigTest
Also run the read-only WinGet configuration test, including modernization when selected.
.PARAMETER IncludeJavaModernization
Require the modernization extension and test its add-on configuration.
.PARAMETER Json
Emit one JSON array without native output or formatting.
.EXAMPLE
.\scripts\verify.ps1 -RunConfigTest -IncludeJavaModernization
#>
[CmdletBinding()]
param([switch]$RunConfigTest, [switch]$IncludeJavaModernization, [switch]$Json)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1') -Force

function Get-VerificationCheck {
    [CmdletBinding()]
    [OutputType([pscustomobject], [object[]])]
    param([switch]$RunConfigTest, [switch]$IncludeJavaModernization)
    $definitions = @(
        @{ Name = 'winget'; Args = @('--version'); Expected = '>= 1.6.2631'; Pattern = '\d+\.\d+\.\d+'; Minimum = '1.6.2631' },
        @{ Name = 'git'; Args = @('--version'); Expected = 'Installed' },
        @{ Name = 'gh'; Args = @('--version'); Expected = 'Installed' },
        @{ Name = 'copilot'; Args = @('--version'); Expected = 'Installed' },
        @{ Name = 'code'; Args = @('--version'); Expected = 'Installed' },
        @{ Name = 'python'; Args = @('--version'); Expected = '3.14.x'; Pattern = '\b3\.14\.\d+' },
        @{ Name = 'uv'; Args = @('--version'); Expected = 'Installed' },
        @{ Name = 'java'; Args = @('-version'); Expected = '25.x'; Pattern = 'version\s+"25(?:[."]|$)' },
        @{ Name = 'go'; Args = @('version'); Expected = 'Installed stable Go' },
        @{ Name = 'az'; Args = @('version'); Expected = 'Installed' },
        @{ Name = 'azd'; Args = @('version'); Expected = 'Installed' },
        @{ Name = 'kubectl'; Args = @('version', '--client'); Expected = 'Installed' },
        @{ Name = 'node'; Args = @('--version'); Expected = 'Installed LTS' },
        @{ Name = 'wsl'; Args = @('--version'); Expected = '>= 2.9.3'; Pattern = '\d+\.\d+\.\d+'; Minimum = '2.9.3' },
        @{ Name = 'wslc'; Args = @(); Expected = 'Present on PATH'; PresenceOnly = $true }
    )
    $policies = @(Get-WinGetPolicy)
    $policies
    $blocked = @($policies | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0
    foreach ($definition in $definitions) {
        $name = $definition.Name
        if ($name -eq 'winget' -and $blocked) {
            Get-CheckResult $name FAIL 'Blocked by organisation policy, contact IT.' -Expected $definition.Expected -Found 'Blocked'
            continue
        }
        $path = Get-NativeCommandPath $name
        if (-not $path) {
            Get-CheckResult $name FAIL 'Missing from PATH. Run the approved bootstrap, then open a new terminal.' -Expected $definition.Expected -Found 'Missing'
            continue
        }
        if ($definition.ContainsKey('PresenceOnly')) {
            Get-CheckResult $name PASS 'Runtime found; permission and container health are checked when running a sample.' -Expected $definition.Expected -Found $path
            continue
        }
        try {
            $result = Invoke-NativeCommand $path $definition.Args -TimeoutSeconds 30
            $text = ($result.Output -replace "`0", '').Trim()
            $valid = $result.ExitCode -eq 0 -and $text.Length -gt 0
            if ($definition.ContainsKey('Pattern')) {
                $match = [regex]::Match($text, $definition.Pattern)
                $valid = $valid -and $match.Success
                if ($valid -and $definition.ContainsKey('Minimum')) {
                    $valid = [version]$match.Value -ge [version]$definition.Minimum
                }
            }
            $found = ($text -split '[\r\n]+')[0]
            $status = if ($valid) { 'PASS' } else { 'FAIL' }
            Get-CheckResult $name $status "Expected $($definition.Expected); command exit $($result.ExitCode). Update via the approved configuration if needed." -Expected $definition.Expected -Found $found
        } catch {
            Get-CheckResult $name FAIL $_.Exception.Message -Expected $definition.Expected -Found 'Could not run'
        }
    }
    $root = Get-ShowcaseRoot
    try {
        $extensions = @(Get-RequiredExtension (Join-Path $root '.vscode\extensions.json') -IncludeJavaModernization:$IncludeJavaModernization)
        $code = Get-NativeCommandPath code
        $installed = @()
        if ($code) {
            $list = Invoke-NativeCommand $code @('--list-extensions') -TimeoutSeconds 30
            Assert-NativeSuccess $list 'List VS Code extensions'
            $installed = @($list.StdOut -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        foreach ($extension in $extensions) {
            $present = $installed -icontains $extension
            $status = if ($present) { 'PASS' } else { 'FAIL' }
            $found = if ($present) { 'Installed' } else { 'Missing' }
            Get-CheckResult $extension $status 'Required configuration automates extension installation. See SETUP Phase 2/3 for approved source, CLI account/profile and enabled-state acceptance; do not bypass enterprise policy.' -Expected 'Installed' -Found $found
        }
    } catch { Get-CheckResult 'Extension profile' FAIL $_.Exception.Message }
    if ($RunConfigTest) {
        if ($blocked) {
            Get-CheckResult 'Configuration test' FAIL 'Blocked by organisation policy, contact IT.'
        } else {
            $winget = Get-NativeCommandPath winget
            if (-not $winget) {
                Get-CheckResult 'Configuration test' FAIL 'WinGet is missing.'
            } else {
                $files = @('configuration.winget')
                if ($IncludeJavaModernization) { $files += 'java-modernization.winget' }
                foreach ($file in $files) {
                    try {
                        $path = Join-Path $root ".config\$file"
                        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Configuration not found: $path" }
                        $result = Invoke-NativeCommand $winget @('configure', 'test', '-f', $path) -TimeoutSeconds 300
                        $status = if ($result.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
                        Get-CheckResult $file $status "Read-only configuration test exit $($result.ExitCode): $($result.Output -replace '[\r\n]+', ' ')"
                    } catch { Get-CheckResult $file FAIL $_.Exception.Message }
                }
            }
        }
    }
}

function Invoke-Verification {
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$RunConfigTest, [switch]$IncludeJavaModernization, [switch]$Json)
    try { $checks = @(Get-VerificationCheck -RunConfigTest:$RunConfigTest -IncludeJavaModernization:$IncludeJavaModernization) }
    catch { $checks = @(Get-CheckResult 'Verification' FAIL $_.Exception.Message) }
    Write-CheckReport $checks -Json:$Json -Table
    return (Get-CheckExitCode $checks)
}

if ($MyInvocation.InvocationName -ne '.') {
    $result = @(Invoke-Verification @PSBoundParameters)
    for ($index = 0; $index -lt $result.Count - 1; $index++) { Write-Output $result[$index] }
    exit ([int]$result[-1])
}
