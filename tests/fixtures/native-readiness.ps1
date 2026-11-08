<#
.SYNOPSIS
Exercise source-extracted verification and Native action binding with no workstation probes.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $RepositoryRoot
$script:PolicyNames = @()
$script:ToolNames = @()
$allowed = @{
    'scripts\_common.psm1' = @('Get-CheckResult', 'Write-CheckReport', 'Get-CheckExitCode', 'Get-RequiredExtension')
    'scripts\verify.ps1' = @('Get-VerificationCheck', 'Invoke-Verification')
    'scripts\developer.ps1' = @('Invoke-Developer')
}
foreach ($file in $allowed.Keys) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    foreach ($definition in $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $false)) {
        if ($definition.Name -eq 'Get-WinGetPolicy') {
            $loop = @($definition.Body.FindAll({
                param($node)
                $node -is [Management.Automation.Language.ForEachStatementAst] -and
                    $node.Variable.VariablePath.UserPath -eq 'name'
            }, $false))[0]
            $script:PolicyNames = @($loop.Condition.FindAll({
                param($node)
                $node -is [Management.Automation.Language.StringConstantExpressionAst]
            }, $true) | ForEach-Object { $_.Value })
        }
        if ($definition.Name -eq 'Get-VerificationCheck') {
            $script:ToolNames = @([regex]::Matches($definition.Extent.Text, "Name = '([a-z]+)'") |
                ForEach-Object { $_.Groups[1].Value })
        }
        if ($allowed[$file] -contains $definition.Name) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
}
$script:MissingJava = $false
$script:IncompatibleJava = $false
$script:UnknownInventory = $false
$script:NativeCalls = @()
$script:Launch = $null
function Get-LocalInstallation {
    if ($script:UnknownInventory) { throw 'Synthetic unknown inventory.' }
    @()
}
function Get-SetupPackage { param($Module) @() }
function Get-SetupExecutable { throw 'Unexpected setup discovery in this fixture.' }
function Get-WinGetPolicy {
    foreach ($name in $script:PolicyNames) { Get-CheckResult $name PASS 'Fixture only.' }
}
function Get-ShowcaseRoot { $root }
function Get-NativeCommandPath {
    param($Name)
    if ($Name -in @('wsl', 'wslc') -or ($script:MissingJava -and $Name -eq 'java')) { return $null }
    "fixture:$Name"
}
function Assert-NativeSuccess {
    param($Result, $Context)
    if ($Result.ExitCode -ne 0) { throw "Synthetic failure: $Context" }
}
function Invoke-NativeCommand {
    param($FilePath, $ArgumentList, $TimeoutSeconds)
    if ($TimeoutSeconds -ne 30 -or $FilePath -notlike 'fixture:*' -or $ArgumentList -contains 'configure') {
        throw 'Unexpected external/provider command in synthetic verification.'
    }
    $script:NativeCalls += $FilePath
    $text = if ($ArgumentList -contains '--list-extensions') {
        (Get-RequiredExtension (Join-Path $root '.vscode\extensions.json')) -join "`n"
    } else {
        switch ($FilePath) {
            'fixture:winget' { 'v1.29.380' }
            'fixture:python' { 'Python 3.14.10' }
            'fixture:java' {
                if ($script:IncompatibleJava) { 'openjdk version "11.0.1"' }
                else { 'openjdk version "25.0.1"' }
            }
            'fixture:go' { 'go version go1.27.3 windows/amd64' }
            'fixture:node' { 'v26.0.0' }
            'fixture:pwsh' { '7.6.9' }
            default { 'Synthetic installed tool' }
        }
    }
    [pscustomobject]@{ ExitCode = 0; Output = $text; StdOut = $text; StdErr = ''; TimedOut = $false }
}
$agent = Get-Content -LiteralPath (Join-Path $root '.github\agents\workstation-setup.agent.md') -Raw
$failureLine = [regex]::Match($agent, '(?m)^Failure identities eligible for narrower Native: (.*)$')
$script:EligibleFailures = @([regex]::Matches($failureLine.Groups[1].Value, '`([a-z]+)`') |
    ForEach-Object { $_.Groups[1].Value })
$script:RequiredNames = @($script:ToolNames) + @(Get-RequiredExtension (Join-Path $root '.vscode\extensions.json')) + @($script:PolicyNames)
if ($script:RequiredNames.Count -ne 33 -or ($script:EligibleFailures -join ',') -cne 'wsl,wslc') {
    throw 'Source-backed default rows or WSL-only failure contract changed.'
}
function Test-FixtureNativeEligibility {
    param([string]$Json, [int]$ExitCode, [bool]$InventoryAccepted, [bool]$ProfileAccepted, [bool]$SafetyKnown)
    if ($ExitCode -ne 1 -or -not $InventoryAccepted -or -not $ProfileAccepted -or -not $SafetyKnown) { return $false }
    if (-not $Json.Trim().StartsWith('[')) { return $false }
    try { $parsed = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    $checks = @($parsed)
    if ($checks.Count -ne $script:RequiredNames.Count) { return $false }
    $failed = @()
    foreach ($check in $checks) {
        if ($null -eq $check -or @($check.PSObject.Properties).Count -ne 5) { return $false }
        foreach ($field in @('Name', 'Expected', 'Found', 'Status', 'Message')) {
            if (-not $check.PSObject.Properties[$field] -or $check.$field -isnot [string]) { return $false }
        }
        if ($script:RequiredNames -cnotcontains $check.Name) { return $false }
        if ($check.Status -ceq 'FAIL') {
            if ($script:EligibleFailures -cnotcontains $check.Name -or $check.Found -cne 'Missing/unusable') { return $false }
            $failed += $check
        } elseif ($check.Status -cne 'PASS') { return $false }
    }
    if (@($checks.Name | Select-Object -Unique).Count -ne $checks.Count) { return $false }
    return $failed.Count -gt 0
}
$missingWslJson = ''
foreach ($scenario in @('missing-wsl', 'missing-native-java', 'incompatible-native-java', 'unknown-inventory')) {
    $script:MissingJava = $scenario -eq 'missing-native-java'
    $script:IncompatibleJava = $scenario -eq 'incompatible-native-java'
    $script:UnknownInventory = $scenario -eq 'unknown-inventory'
    $result = @(Invoke-Verification -Json)
    if ($result.Count -ne 2 -or [int]$result[-1] -ne 1) { throw 'Verify must preserve JSON and full-profile exit 1.' }
    $parsed = $result[0] | ConvertFrom-Json
    $checks = @($parsed)
    $failed = (@($checks | Where-Object Status -eq FAIL).Name | Sort-Object) -join ','
    $expected = switch ($scenario) {
        'missing-wsl' { 'wsl,wslc' }
        'missing-native-java' { 'java,wsl,wslc' }
        'incompatible-native-java' { 'java,wsl,wslc' }
        'unknown-inventory' { 'Verification' }
    }
    if ($failed -ne $expected) { throw "Unexpected failure classification: $failed" }
    if ($scenario -ne 'unknown-inventory' -and $checks.Count -ne 33) { throw 'Fixture must retain every tool/extension/policy row.' }
    $eligible = Test-FixtureNativeEligibility $result[0] 1 $true $true $true
    if ($eligible -ne ($scenario -eq 'missing-wsl')) { throw 'Required runtime/inventory failure became narrower Native eligibility.' }
    if ($scenario -eq 'missing-wsl') {
        $missingWslJson = $result[0]
        foreach ($name in @('winget', 'git', 'code', 'python', 'uv', 'pwsh', 'java', 'go')) {
            if (($checks | Where-Object Name -eq $name).Status -ne 'PASS') { throw 'Native prerequisite failure was hidden.' }
        }
        foreach ($check in @($checks | Where-Object Status -eq FAIL)) {
            if ($check.Found -ne 'Missing/unusable') { throw 'Missing WSL state was changed.' }
        }
    }
    Write-Output "SYNTHETIC PASS: $scenario retains JSON/exit 1 and explicit FAIL=$failed"
}
$baseline = $missingWslJson | ConvertFrom-Json
foreach ($case in @(
    @{ Name = 'malformed JSON'; Json = '[not-json' },
    @{ Name = 'empty array'; Json = '[]' },
    @{ Name = 'not an array'; Json = '{}' },
    @{ Name = 'missing Native row'; Json = (@($baseline | Where-Object Name -ne java) | ConvertTo-Json) },
    @{ Name = 'duplicate row'; Json = ((@($baseline) + @($baseline[0])) | ConvertTo-Json) }
)) {
    if (Test-FixtureNativeEligibility $case.Json 1 $true $true $true) { throw "Invalid report became eligible: $($case.Name)" }
    Write-Output "SYNTHETIC PASS: rejects $($case.Name); no Native acceptance fabricated"
}
foreach ($condition in @('inventory', 'profile', 'safety', 'exit')) {
    $accepted = Test-FixtureNativeEligibility $missingWslJson $(if ($condition -eq 'exit') { 0 } else { 1 }) `
        ($condition -ne 'inventory') ($condition -ne 'profile') ($condition -ne 'safety')
    if ($accepted) { throw "Unaccepted $condition became narrower Native eligibility." }
}
Write-Output 'SYNTHETIC PASS: positive inventory/profile/safety and exact exit 1 are required even for WSL-only failures'
foreach ($mutation in @('other-full-tool-failure', 'policy-failure', 'unknown-WSL', 'message-only-WSL', 'missing-field', 'duplicate-identity')) {
    $records = $missingWslJson | ConvertFrom-Json
    switch ($mutation) {
        'other-full-tool-failure' { ($records | Where-Object Name -eq az).Status = 'FAIL' }
        'policy-failure' { ($records | Where-Object Name -eq $script:PolicyNames[0]).Status = 'FAIL' }
        'unknown-WSL' { ($records | Where-Object Name -eq wsl).Found = 'Inventory unknown' }
        'message-only-WSL' { ($records | Where-Object Name -eq wsl).Name = 'Unexpected WSL error' }
        'missing-field' { ($records | Where-Object Name -eq java).PSObject.Properties.Remove('Name') }
        'duplicate-identity' { $records[-1] = $records[0] }
    }
    $json = ConvertTo-Json -InputObject @($records) -Depth 5
    if (Test-FixtureNativeEligibility $json 1 $true $true $true) { throw "Unexpected $mutation qualified for Native continuation." }
    Write-Output "SYNTHETIC PASS: rejects $mutation under exact structured WSL-only identities"
}
if ($script:NativeCalls -contains 'fixture:wsl' -or $script:NativeCalls -contains 'fixture:wslc') {
    throw 'Absent WSL must not invoke a runtime.'
}
function Start-DeveloperSample {
    param($Sample, [switch]$Container, $Runtime, $Port, [switch]$WhatIf)
    $script:Launch = [pscustomobject]@{ Sample = $Sample; Container = [bool]$Container; Runtime = $Runtime; Port = $Port }
}
function Write-ShowcaseMessage { param($Message) }
foreach ($sample in @('Python', 'Java', 'Go')) {
    $port = switch ($sample) { 'Python' { 8080 }; 'Java' { 8081 }; 'Go' { 8082 } }
    $code = Invoke-Developer -Action RunLocal -Sample $sample -Port $port
    if ($code -ne 0 -or $script:Launch.Container -or $script:Launch.Runtime -ne 'auto' -or
        $script:Launch.Sample -ne $sample -or $script:Launch.Port -ne $port) {
        throw 'Native recipe bound to the wrong action/runtime/sample.'
    }
    Write-Output "SYNTHETIC PASS: RunLocal $sample/$port binds Container=false; no app or WSL launched"
}
Write-Output "Fixture PASS under PowerShell $($PSVersionTable.PSVersion); no installed-software, policy, provider or application query ran."
