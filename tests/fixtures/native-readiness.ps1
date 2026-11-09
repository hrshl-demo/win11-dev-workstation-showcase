<#
.SYNOPSIS
Exercise actual Native verification/selection using source definitions and synthetic operations only.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $RepositoryRoot
$allowed = @{
    'scripts\_common.psm1' = @('Get-CheckResult', 'Write-CheckReport', 'Get-CheckExitCode',
        'Get-RequiredExtension', 'Get-NativeDemoRequirement')
    'scripts\verify.ps1' = @('Get-VerificationCheck', 'Assert-NativeDemoCheck', 'Invoke-Verification')
    'scripts\preflight.ps1' = @('Get-PreflightCheck', 'Invoke-Preflight')
    'scripts\_setup.psm1' = @('Get-SetupExtension', 'Invoke-SetupModule')
    'scripts\developer.ps1' = @('Invoke-Developer')
}
$script:ToolNames = @()
foreach ($file in $allowed.Keys) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    foreach ($definition in $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $false)) {
        if ($definition.Name -eq 'Get-VerificationCheck') {
            $script:ToolNames = @([regex]::Matches($definition.Extent.Text, "Name = '([a-z]+)'") |
                ForEach-Object { $_.Groups[1].Value })
        }
        if ($allowed[$file] -contains $definition.Name) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
}
$requirements = Get-NativeDemoRequirement
$script:MissingJava = $false
$script:IncompatibleJava = $false
$script:UnknownInventory = $false
$script:PolicyBlocked = $false
$script:MissingExtension = ''
$script:BadExtensions = ''
$script:CommandLookups = @()
$script:NativeCalls = @()
$script:CimCalls = @()
$script:InstallerCalls = 0
$script:ReadinessCalls = 0
$script:BootstrapArguments = @()
$script:Messages = @()
$script:Launch = $null
function Get-LocalInstallation {
    if ($script:UnknownInventory) { throw 'Synthetic unknown inventory.' }
    @()
}
function Get-SetupPackage { param($Module) @() }
function Get-SetupExecutable { throw 'Unexpected setup discovery in this fixture.' }
function Get-WinGetPolicy {
    foreach ($name in $requirements.Policies) {
        $status = if ($script:PolicyBlocked -and $name -eq $requirements.Policies[0]) { 'FAIL' } else { 'PASS' }
        Get-CheckResult $name $status 'Fixture only.' -Found 'Not configured'
    }
}
function Get-ShowcaseRoot { $root }
function Get-NativeCommandPath {
    param($Name)
    $script:CommandLookups += $Name
    if ($Name -eq 'wslc' -or ($script:MissingJava -and $Name -eq 'java')) { return $null }
    "fixture:$Name"
}
function Assert-NativeSuccess {
    param($Result, $Context)
    if ($Result.ExitCode -ne 0) { throw "Synthetic failure: $Context" }
}
function Invoke-NativeCommand {
    param($FilePath, $ArgumentList, $TimeoutSeconds)
    if ($FilePath -notlike 'fixture:*' -or $TimeoutSeconds -notin @(10, 15, 30, 60) -or
        ($ArgumentList -contains 'configure' -and $ArgumentList -notcontains '--help')) {
        throw 'Unexpected external/provider command in synthetic verification.'
    }
    $script:NativeCalls += $FilePath
    $exitCode = 0
    $text = if ($ArgumentList -contains '--list-extensions') {
        $ids = @(@(Get-RequiredExtension (Join-Path $root '.vscode\extensions.json')) +
            @($requirements.Extensions) | Select-Object -Unique)
        $ids = @($ids | Where-Object { $_ -ne $script:MissingExtension })
        if ($ArgumentList -contains '--show-versions') {
            switch ($script:BadExtensions) {
                'malformed' { 'not-an-extension' }
                'duplicate' { 'ms-python.python@1.2.3'; 'ms-python.python@1.2.3' }
                'unknown-version' { 'ms-python.python@unknown' }
                default { $ids | ForEach-Object { "$_@1.2.3" } }
            }
        } else {
            # Eight missing full-profile extensions reproduce the live scope,
            # without making any of those unrelated IDs a Native prerequisite.
            @($ids | Where-Object { $requirements.Extensions -contains $_ -or
                $_ -in @('vscjava.vscode-java-pack', 'ms-vscode.powershell') }) -join "`n"
        }
    } else {
        switch ($FilePath) {
            'fixture:winget' { 'v1.29.380' }
            'fixture:python' { 'Python 3.14.10' }
            'fixture:java' {
                if ($script:IncompatibleJava) { 'openjdk version "11.0.1"' }
                else { 'openjdk version "25.0.5"' }
            }
            'fixture:go' { 'go version go1.27.3 windows/amd64' }
            'fixture:node' { 'v26.0.0' }
            'fixture:pwsh' { '7.6.9' }
            'fixture:wsl' { $exitCode = 124; 'The Windows Subsystem for Linux is not installed.' }
            default { 'Synthetic installed tool' }
        }
    }
    $text = @($text) -join "`n"
    [pscustomobject]@{ ExitCode = $exitCode; Output = $text; StdOut = $text; StdErr = ''; TimedOut = ($exitCode -eq 124) }
}
function Get-CimInstance {
    param($ClassName, $Filter)
    $script:CimCalls += $ClassName
    switch ($ClassName) {
        'Win32_OperatingSystem' { [pscustomobject]@{ BuildNumber = '22621'; ProductType = 1; Caption = 'Synthetic Windows 11' } }
        'Win32_LogicalDisk' { [pscustomobject]@{ FreeSpace = 20GB } }
        default { throw 'Native must not query virtualization.' }
    }
}
function Get-AppxPackage { param($Name) [pscustomobject]@{ Version = '1.11.11451' } }
function Test-IsAdministrator { $false }
function Get-HttpsProbe {
    param($Uri, $TimeoutSeconds)
    [pscustomobject]@{ Uri = $Uri; Reachable = $true; StatusCode = 200; Attempts = 1
        ErrorType = ''; Reason = 'Synthetic HTTPS only'; TimeoutSeconds = $TimeoutSeconds }
}
function Get-ExecutionPolicy { param([switch]$List) [pscustomobject]@{ Scope = 'Process'; ExecutionPolicy = 'Synthetic' } }
function Write-ShowcaseMessage { param($Message) $script:Messages += $Message }
function Write-SetupEvent { param($Path, $Module, $State, $Target, $ElapsedSeconds) }
function Assert-WorkstationPolicy { if ($script:PolicyBlocked) { throw 'Synthetic policy denial.' } }
function Invoke-SetupReadiness { param($HttpsTimeoutSeconds, [switch]$NativeDemo) $script:ReadinessCalls++; throw 'Synthetic readiness stop; no installer/file operation.' }
function Invoke-SetupNative { $script:InstallerCalls++; throw 'No installer is allowed in this fixture.' }
function New-Item { throw 'No output/journal mutation is allowed in this fixture.' }
function Get-Process { param($Id) [pscustomobject]@{ Path = 'Invoke-FixtureBootstrap' } }
function Invoke-FixtureBootstrap { $script:BootstrapArguments = @($args); $global:LASTEXITCODE = 0 }
function Join-Path {
    param([AllowEmptyString()][string]$Path, [string]$ChildPath)
    # Extracted ScriptBlocks have no file origin; bind only the reviewed child path.
    if (-not $Path) {
        if ($ChildPath -ne 'bootstrap.ps1') { throw 'Unexpected originless source path in fixture.' }
        $Path = "$root\scripts"
    }
    Microsoft.PowerShell.Management\Join-Path $Path $ChildPath
}

$full = @(Invoke-Verification -Json)
$parsed = $full[0] | ConvertFrom-Json
$fullChecks = @($parsed)
if ($full.Count -ne 2 -or [int]$full[-1] -ne 1 -or $fullChecks.Count -ne 33 -or
    @($fullChecks | Where-Object Status -eq FAIL).Count -ne 10 -or
    ($fullChecks | Where-Object Name -eq wsl).Found -ne 'The Windows Subsystem for Linux is not installed.') {
    throw 'Full default verification must retain all 33 records and live-shaped WSL stub/optional extension failures.'
}
Write-Output 'SYNTHETIC PASS: full Verify remains 33 rows, exit 1, 10 FAIL including WSL stub exit 124'

$script:CommandLookups = @()
$script:NativeCalls = @()
$native = @(Invoke-Verification -NativeDemo -Json)
$parsed = $native[0] | ConvertFrom-Json
$nativeChecks = @($parsed)
if ($native.Count -ne 2 -or [int]$native[-1] -ne 0 -or $nativeChecks.Count -ne 18 -or
    @($nativeChecks | Where-Object Status -ne PASS).Count -ne 0) { throw 'Positive Native selection did not pass every required row.' }
if (@($script:CommandLookups | Where-Object { $requirements.Tools -notcontains $_ }).Count -gt 0) {
    throw 'Native verification queried an optional WSL/Azure/container/full-profile tool.'
}
Write-Output 'SYNTHETIC PASS: Native 18/18 PASS and exit 0 independently; no WSL/Azure/container probe'

function Test-FixtureNativeEligibility {
    param([string]$Json, [int]$ExitCode, [bool]$InventoryAccepted, [bool]$ProfileAccepted, [bool]$SafetyKnown)
    if ($ExitCode -ne 0 -or -not $InventoryAccepted -or -not $ProfileAccepted -or -not $SafetyKnown) { return $false }
    if (-not $Json.Trim().StartsWith('[')) { return $false }
    try {
        $parsed = $Json | ConvertFrom-Json -ErrorAction Stop
        $checks = @($parsed)
        Assert-NativeDemoCheck $checks
    } catch { return $false }
    return @($checks | Where-Object Status -ne PASS).Count -eq 0
}
if (-not (Test-FixtureNativeEligibility $native[0] 0 $true $true $true)) { throw 'Complete positive Native report was rejected.' }
foreach ($scenario in @('missing-native-java', 'incompatible-native-java', 'unknown-inventory',
    'missing-debugpy', 'policy-denial', 'malformed-extension-inventory', 'duplicate-extension-inventory', 'unknown-extension-version')) {
    $script:MissingJava = $scenario -eq 'missing-native-java'
    $script:IncompatibleJava = $scenario -eq 'incompatible-native-java'
    $script:UnknownInventory = $scenario -eq 'unknown-inventory'
    $script:MissingExtension = if ($scenario -eq 'missing-debugpy') { 'ms-python.debugpy' } else { '' }
    $script:PolicyBlocked = $scenario -eq 'policy-denial'
    $script:BadExtensions = switch ($scenario) {
        'malformed-extension-inventory' { 'malformed' }
        'duplicate-extension-inventory' { 'duplicate' }
        'unknown-extension-version' { 'unknown-version' }
        default { '' }
    }
    $result = @(Invoke-Verification -NativeDemo -Json)
    if ([int]$result[-1] -ne 1 -or (Test-FixtureNativeEligibility $result[0] ([int]$result[-1]) $true $true $true)) {
        throw "Native required failure became accepted: $scenario"
    }
    Write-Output "SYNTHETIC PASS: rejects $scenario; Native exit 1, no success-shaped fallback"
}
$script:MissingJava = $false
$script:IncompatibleJava = $false
$script:UnknownInventory = $false
$script:MissingExtension = ''
$script:PolicyBlocked = $false
$script:BadExtensions = ''
foreach ($case in @(
    @{ Name = 'malformed JSON'; Json = '[not-json' },
    @{ Name = 'empty array'; Json = '[]' },
    @{ Name = 'not an array'; Json = '{}' },
    @{ Name = 'missing Native row'; Json = (@($nativeChecks | Where-Object Name -ne java) | ConvertTo-Json) },
    @{ Name = 'duplicate row'; Json = ((@($nativeChecks) + @($nativeChecks[0])) | ConvertTo-Json) }
)) {
    if (Test-FixtureNativeEligibility $case.Json 0 $true $true $true) { throw "Invalid Native JSON became accepted: $($case.Name)" }
    Write-Output "SYNTHETIC PASS: rejects $($case.Name)"
}
foreach ($mutation in @('unexpected-identity', 'unknown-status', 'missing-field', 'duplicate-identity', 'required-failure')) {
    $records = $native[0] | ConvertFrom-Json
    switch ($mutation) {
        'unexpected-identity' { $records[0].Name = 'unexpected' }
        'unknown-status' { $records[0].Status = 'UNKNOWN' }
        'missing-field' { $records[0].PSObject.Properties.Remove('Name') }
        'duplicate-identity' { $records[-1] = $records[0] }
        'required-failure' { $records[0].Status = 'FAIL' }
    }
    if (Test-FixtureNativeEligibility (ConvertTo-Json -InputObject @($records) -Depth 5) 0 $true $true $true) {
        throw "Malformed/failed Native record became accepted: $mutation"
    }
}
foreach ($condition in @('inventory', 'profile', 'safety', 'exit')) {
    if (Test-FixtureNativeEligibility $native[0] $(if ($condition -eq 'exit') { 1 } else { 0 }) `
        ($condition -ne 'inventory') ($condition -ne 'profile') ($condition -ne 'safety')) { throw "Unaccepted $condition became Native eligibility." }
}
Write-Output 'SYNTHETIC PASS: positive inventory/profile/safety and exact exit 0 are required'

$script:CommandLookups = @()
$preflight = @(Invoke-Preflight -NativeDemo -Json)
if ([int]$preflight[-1] -ne 0 -or $script:CommandLookups -contains 'wsl' -or
    $script:CommandLookups -contains 'wslc' -or $script:CimCalls -contains 'Win32_Processor') {
    throw 'Native Preflight incorrectly queried/required WSL or virtualization.'
}
Write-Output 'SYNTHETIC PASS: Native Preflight omits WSL/wslc/virtualization; policy/network checks retained'

$extensionInventory = @(Get-SetupExtension -NativeDemo)
if (($extensionInventory.Id -join ',') -cne ($requirements.Extensions -join ',') -or
    @($extensionInventory | Where-Object State -ne Installed).Count -gt 0) { throw 'Native extension selection is not authoritative.' }
if ((Invoke-Developer -Action SetupPreview -SetupModule Extensions -NativeDemo) -ne 0 -or $script:ReadinessCalls -ne 0) {
    throw 'Installed Native extension preview invoked provider/source readiness.'
}
$script:MissingExtension = 'ms-python.debugpy'
if ((Invoke-SetupModule -Module Extensions -NativeDemo -Apply -Confirm:$false) -ne 1 -or $script:ReadinessCalls -ne 0) {
    throw 'Missing Native extension bypassed source attestation.'
}
if ((Invoke-SetupModule -Module Extensions -NativeDemo -Apply -ExtensionSourceApproved -Confirm:$false) -ne 1 -or
    $script:ReadinessCalls -ne 1 -or $script:InstallerCalls -ne 0) { throw 'Synthetic readiness stop did not preserve mutation boundaries.' }
$script:MissingExtension = ''
$script:BadExtensions = 'malformed'
if ((Invoke-SetupModule -Module Extensions -NativeDemo -Apply -ExtensionSourceApproved -Confirm:$false) -ne 1 -or
    $script:ReadinessCalls -ne 1) { throw 'Unknown inventory reached source readiness.' }
$script:BadExtensions = ''
$setupCode = Invoke-Developer -Action Setup -SetupModule Extensions -NativeDemo -ExtensionSourceApproved -Confirm:$false
if ($setupCode -ne 0 -or
    $script:BootstrapArguments -notcontains '-NativeDemo' -or $script:BootstrapArguments -notcontains '-Confirm' -or
    $script:BootstrapArguments -notcontains 'Extensions' -or
    $script:BootstrapArguments -notcontains (Join-Path "$root\scripts" 'bootstrap.ps1')) {
    throw "Native setup binding failed: exit $setupCode; arguments $($script:BootstrapArguments -join ','); messages $($script:Messages -join '; ')"
}
foreach ($invalid in @('Core', 'Java', 'WSL', 'Modernization')) {
    if ((Invoke-Developer -Action SetupPreview -SetupModule $invalid -NativeDemo) -ne 1) { throw 'Native selection escaped Extensions scope.' }
}
Write-Output 'SYNTHETIC PASS: five-ID Extensions inventory/dispatcher binding; installed retained, unknown/source/readiness stops before installers'

function Start-DeveloperSample {
    param($Sample, [switch]$Container, $Runtime, $Port, [switch]$WhatIf)
    $script:Launch = [pscustomobject]@{ Sample = $Sample; Container = [bool]$Container; Runtime = $Runtime; Port = $Port }
}
foreach ($sample in @('Python', 'Java', 'Go')) {
    $port = switch ($sample) { 'Python' { 8080 }; 'Java' { 8081 }; 'Go' { 8082 } }
    $code = Invoke-Developer -Action RunLocal -Sample $sample -Port $port
    if ($code -ne 0 -or $script:Launch.Container -or $script:Launch.Runtime -ne 'auto' -or
        $script:Launch.Sample -ne $sample -or $script:Launch.Port -ne $port) { throw 'Native launch bound to the wrong action/runtime/sample.' }
    Write-Output "SYNTHETIC PASS: RunLocal $sample/$port binds Container=false; no app or WSL launched"
}
Write-Output "Fixture PASS under PowerShell $($PSVersionTable.PSVersion); no installed-software, policy, provider or application query ran."
