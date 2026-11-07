<#
.SYNOPSIS
Installed-first, separately confirmed workstation modules with bounded progress.
.DESCRIPTION
Only local registry, known executable locations and read-only version commands
determine installation. Unknown/incompatible inventory never triggers download.
No provider restore, preset, source/policy change or automatic upgrade is used.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1')

function Get-SetupPackage {
    [CmdletBinding()]
    param([string]$Module)
    $catalog = Get-Content (Join-Path (Get-ShowcaseRoot) '.config\setup-packages.json') -Raw | ConvertFrom-Json
    $property = $catalog.PSObject.Properties[$Module]
    if ($null -eq $property) { return @() }
    if ($Module -eq 'Go') {
        $manifest = Get-Content (Join-Path (Get-ShowcaseRoot) 'samples\go-fx-rates\go.mod') -Raw
        if ($manifest -notmatch '(?m)^go ([0-9]+\.[0-9]+\.[0-9]+)\s*$') { throw 'Go manifest version is unknown; no installer can run.' }
        $version = $Matches[1]
        $property.Value[0] | Add-Member -NotePropertyName Version -NotePropertyValue $version
        $property.Value[0] | Add-Member -NotePropertyName Required -NotePropertyValue ('^go version go' + [regex]::Escape($version) + '\s')
    }
    return @($property.Value)
}

function Get-LocalInstallation {
    [CmdletBinding()]
    param()
    $records = @()
    foreach ($path in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (Test-Path -LiteralPath $path) {
            foreach ($key in Get-ChildItem -LiteralPath $path -ErrorAction Stop) {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if ($item.PSObject.Properties['DisplayName']) {
                    $records += [pscustomobject]@{ Name = [string]$item.DisplayName
                        Version = $(if ($item.PSObject.Properties['DisplayVersion']) { [string]$item.DisplayVersion } else { '' })
                        Location = $(if ($item.PSObject.Properties['InstallLocation']) { [string]$item.InstallLocation } else { '' }) }
                }
            }
        }
    }
    foreach ($package in Get-AppxPackage -Name 'PythonSoftwareFoundation.Python*' -ErrorAction Stop) {
        $records += [pscustomobject]@{ Name = 'Python ' + ([string]$package.Version)
            Version = [string]$package.Version; Location = [string]$package.InstallLocation }
    }
    return $records
}

function Get-SetupExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param([object]$Package, [object[]]$Installations)
    $candidates = @()
    $onPath = Get-NativeCommandPath $Package.Command
    if ($onPath) { $candidates += $onPath }
    foreach ($path in @($Package.Paths)) {
        $expanded = [Environment]::ExpandEnvironmentVariables($path)
        if ($expanded -notmatch '%[^%]+%') { $candidates += $expanded }
    }
    $exe = if ($Package.Command -eq 'java11') { 'java.exe' } else { $Package.Command + '.exe' }
    foreach ($item in $Installations) {
        if ($item.Location -and [IO.Path]::IsPathRooted($item.Location)) {
            $candidates += @((Join-Path $item.Location $exe), (Join-Path $item.Location "bin\$exe"))
        }
    }
    if ($Package.Command -in @('java', 'java11')) {
        foreach ($parent in @((Join-Path $env:ProgramFiles 'Microsoft'), (Join-Path $env:ProgramFiles 'Java'),
            (Join-Path $env:ProgramFiles 'Eclipse Adoptium'))) {
            if (Test-Path -LiteralPath $parent -PathType Container) {
                foreach ($directory in Get-ChildItem -LiteralPath $parent -Directory -ErrorAction Stop) {
                    $candidates += Join-Path $directory.FullName 'bin\java.exe'
                }
            }
        }
    }
    if ($Package.Command -eq 'python') {
        foreach ($root in @('HKCU:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\Python\PythonCore',
            'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
            if (Test-Path -LiteralPath $root) {
                foreach ($version in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
                    $key = Join-Path $version.PSPath 'InstallPath'
                    if (Test-Path -LiteralPath $key) {
                        $values = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
                        if ($values.PSObject.Properties['ExecutablePath']) { $candidates += [string]$values.ExecutablePath }
                    }
                }
                if ($Package.Command -eq 'node') {
                    foreach ($parent in @([Environment]::ExpandEnvironmentVariables('%NVM_HOME%'),
                        [Environment]::ExpandEnvironmentVariables('%APPDATA%\nvm'))) {
                        if ($parent -notmatch '%[^%]+%' -and (Test-Path -LiteralPath $parent -PathType Container)) {
                            foreach ($directory in Get-ChildItem -LiteralPath $parent -Directory -ErrorAction Stop |
                                Where-Object Name -Match '^v[0-9]+\.[0-9]+\.[0-9]+$') {
                                $candidates += Join-Path $directory.FullName 'node.exe'
                            }
                        }
                    }
                }
            }
        }
    }
    $firstInstalled = $null
    foreach ($path in $candidates | Select-Object -Unique) {
        # App Execution Aliases are launch/install stubs, not proof of a runtime.
        if ($path -match '\\Microsoft\\WindowsApps\\') { continue }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                # WinGet Links are permitted only when a real local target exists.
                $item = Get-Item -LiteralPath $path -Force
                if (-not $item.PSObject.Properties['Target'] -or -not $item.Target -or
                    -not (Test-Path -LiteralPath ([string]@($item.Target)[0]) -PathType Leaf)) {
                    throw 'Executable is an unresolved link; inventory unknown.'
                }
            }
            $probe = Invoke-NativeCommand $path @($Package.Args) -TimeoutSeconds 30
            if ($probe.TimedOut -or $probe.ExitCode -ne 0 -or -not $probe.Output.Trim()) {
                throw 'Existing executable version probe failed; inventory unknown, not missing.'
            }
            if ($probe.Output -match $Package.Required) { return $path }
            if (-not $firstInstalled -and $Package.Command -ne 'java11') { $firstInstalled = $path }
        }
    }
    return $firstInstalled
}

function Get-SetupInventory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([object]$Package, [object[]]$Installations)
    $registered = @($Installations | Where-Object { $_.Name -match $Package.Product })
    $path = Get-SetupExecutable $Package $registered
    if ($path) {
        $version = Invoke-NativeCommand $path @($Package.Args) -TimeoutSeconds 30
        if ($version.TimedOut -or $version.ExitCode -ne 0 -or -not $version.Output.Trim()) {
            throw "Inventory unknown for $($Package.Id): version command failed; no installer will run."
        }
        return [pscustomobject]@{ Id = $Package.Id; State = 'Installed'; Path = $path
            Version = (($version.Output -replace "`0", '').Trim() -split '[\r\n]+')[0]
            Compatible = [bool]($version.Output -match $Package.Required) }
    }
    if ($registered.Count -gt 0) {
        return [pscustomobject]@{ Id = $Package.Id; State = 'Installed'; Path = $registered[0].Location
            Version = ($registered.Version -join ', '); Compatible = $false }
    }
    return [pscustomobject]@{ Id = $Package.Id; State = 'Missing'; Path = ''; Version = ''; Compatible = $false }
}

function Get-SetupExtension {
    [CmdletBinding()]
    param([switch]$Modernization)
    $code = Get-NativeCommandPath code
    if (-not $code) {
        $package = @(Get-SetupPackage Core | Where-Object Command -eq code)[0]
        $code = Get-SetupExecutable $package @(Get-LocalInstallation | Where-Object { $_.Name -match $package.Product })
    }
    if (-not $code) { throw 'VS Code CLI is missing. Run Core first and open a fresh terminal; extensions were not downloaded.' }
    $result = Invoke-NativeCommand $code @('--list-extensions', '--show-versions') -TimeoutSeconds 60
    Assert-NativeSuccess $result 'Local VS Code extension inventory (current CLI/default profile)'
    $installed = @{}
    foreach ($line in $result.StdOut -split '[\r\n]+') {
        if (-not $line.Trim()) { continue }
        if ($line -notmatch '^([a-z0-9][a-z0-9.-]+\.[a-z0-9][a-z0-9.-]+)@(.+)$') {
            throw 'Unrecognised extension inventory; no extension installer will run.'
        }
        $installed[$Matches[1].ToLowerInvariant()] = $Matches[2]
    }
    $required = @(Get-RequiredExtension (Join-Path (Get-ShowcaseRoot) '.vscode\extensions.json'))
    if ($Modernization) { $required = @('vscjava.migrate-java-to-azure') }
    foreach ($id in $required) {
        [pscustomobject]@{ Id = $id; State = $(if ($installed.ContainsKey($id.ToLowerInvariant())) { 'Installed' } else { 'Missing' })
            Version = $installed[$id.ToLowerInvariant()]; Path = $code; Compatible = $true }
    }
}

function Get-SetupWslState {
    [CmdletBinding()]
    param()
    $features = @()
    foreach ($name in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
        if ([string]$feature.State -notin @('Enabled', 'Disabled', 'EnablePending', 'DisablePending')) {
            throw 'WSL feature inventory unknown; no installation/update.'
        }
        $features += [pscustomobject]@{ Name = $name; State = [string]$feature.State }
    }
    $packages = @(Get-AppxPackage -Name MicrosoftCorporationII.WindowsSubsystemForLinux -ErrorAction Stop)
    $distroPackages = @(Get-AppxPackage -Name '*Ubuntu*' -ErrorAction Stop)
    $distributions = @()
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (Test-Path -LiteralPath $key) {
        foreach ($child in Get-ChildItem -LiteralPath $key -ErrorAction Stop) {
            $entry = Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction Stop
            if (-not $entry.PSObject.Properties['DistributionName']) { throw 'Unknown WSL distro registry state; retained.' }
            $distributions += [string]$entry.DistributionName
        }
    }
    $wsl = Get-NativeCommandPath wsl
    $version = ''
    if ($packages.Count -gt 0) { $version = [string]$packages[0].Version }
    # MSI installs may not appear in the current account's AppX inventory.
    $registered = @(Get-LocalInstallation | Where-Object { $_.Name -match '(?i)Windows Subsystem for Linux' })
    if ($registered.Count -gt 0) { $version = [string]$registered[0].Version }
    if (-not $version -and ($distributions.Count -gt 0 -or
        (@($features | Where-Object { $_.Name -eq 'Microsoft-Windows-Subsystem-Linux' -and $_.State -eq 'Enabled' }).Count -gt 0 -and $wsl))) {
        $version = 'Existing distro/inbox runtime; version unverified'
    }
    [pscustomobject]@{ Features = $features; Installed = [bool]$version; Version = $version; Path = $wsl
        Distributions = $distributions; UbuntuInstalled = [bool]($distroPackages.Count -gt 0 -or @($distributions | Where-Object { $_ -match '^Ubuntu(?:-|$)' }).Count -gt 0) }
}

function Invoke-SetupNative {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string]$Path, [string[]]$Arguments, [string]$Target,
        [ValidateRange(300, 14400)][int]$TimeoutSeconds = 7200)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    $argumentsText = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    if ([IO.Path]::GetExtension($Path) -in @('.cmd', '.bat')) {
        if ($Path -match '["%!\r\n]' -or $argumentsText -match '[%!\r\n&|<>^]') { throw 'Unsafe installer command arguments.' }
        $start.FileName = $env:ComSpec
        $start.Arguments = '/d /s /c ""' + $Path + '" ' + $argumentsText + '"'
    } else { $start.FileName = $Path; $start.Arguments = $argumentsText }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Installer launcher could not start.' }
        $stdout = $process.StandardOutput.ReadLineAsync()
        $stderr = $process.StandardError.ReadLineAsync()
        $stdoutDone = $false
        $stderrDone = $false
        while (-not $process.HasExited -or -not $stdoutDone -or -not $stderrDone) {
            foreach ($stream in @('stdout', 'stderr')) {
                $task = if ($stream -eq 'stdout') { $stdout } else { $stderr }
                $done = if ($stream -eq 'stdout') { $stdoutDone } else { $stderrDone }
                if (-not $done -and $task.IsCompleted) {
                    $line = $task.GetAwaiter().GetResult()
                    if ($null -eq $line) {
                        if ($stream -eq 'stdout') { $stdoutDone = $true }
                        else { $stderrDone = $true }
                    } else {
                        Write-ShowcaseMessage "[INFO] ${Target}: $line"
                        if ($stream -eq 'stdout') { $stdout = $process.StandardOutput.ReadLineAsync() }
                        else { $stderr = $process.StandardError.ReadLineAsync() }
                    }
                }
            }
            Write-Progress -Activity "Installing missing $Target" -Status "Elapsed $([int]$clock.Elapsed.TotalSeconds)s / ${TimeoutSeconds}s; existing tools are never upgraded"
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                if (-not $process.HasExited) { $process.Kill() }
                throw "Wait timed out after ${TimeoutSeconds}s for $Target. Only this launcher was stopped; vendor/elevated installer state is unknown. Do not retry until its completion/failure is confirmed."
            }
            Start-Sleep -Milliseconds 100
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; ElapsedSeconds = [int]$clock.Elapsed.TotalSeconds }
    } finally {
        Write-Progress -Activity "Installing missing $Target" -Completed
        $process.Dispose()
    }
}

function Write-SetupEvent {
    [CmdletBinding()]
    param([string]$LogPath, [string]$Module, [string]$State, [string]$Target = '', [int]$ElapsedSeconds = 0)
    if ($LogPath) {
        $record = [ordered]@{ Time = (Get-Date).ToUniversalTime().ToString('o'); Module = $Module
            State = $State; Target = $Target; ElapsedSeconds = $ElapsedSeconds }
        [IO.File]::AppendAllText($LogPath, ((ConvertTo-Json $record -Compress) + [Environment]::NewLine))
    }
}

function Invoke-SetupReadiness {
    [CmdletBinding()]
    param([int]$HttpsTimeoutSeconds)
    $shell = (Get-Process -Id $PID).Path
    $result = Invoke-NativeCommand $shell @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'preflight.ps1'),
        '-Json', '-HttpsTimeoutSeconds', [string]$HttpsTimeoutSeconds) -TimeoutSeconds (Get-PreflightTimeout $HttpsTimeoutSeconds)
    Assert-NativeSuccess $result 'Module preflight; no installers started'
    $checks = @($result.StdOut | ConvertFrom-Json)
    if ((Get-CheckExitCode $checks) -ne 0) { throw 'Module preflight failed; no installers started.' }
}

function Invoke-SetupModule {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([int])]
    param([ValidateSet('Core', 'Python', 'Java', 'Go', 'Extensions', 'WSL', 'Ubuntu', 'Docker', 'Modernization')]
        [string]$Module = 'Core', [switch]$Apply, [switch]$ExtensionSourceApproved,
        [ValidateRange(1, 30)][int]$HttpsTimeoutSeconds = 5,
        [ValidateRange(300, 14400)][int]$InstallTimeoutSeconds = 7200)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $logPath = ''
    $mutex = $null
    $mutexHeld = $false
    try {
        Write-ShowcaseMessage "[INFO] Module $Module inventory first; $(if ($Apply) { 'apply requested' } else { 'read-only preview' })."
        # Complete the module's local inventory before any source/payload activity.
        $inventory = @()
        $wsl = $null
        if ($Module -in @('WSL', 'Ubuntu')) { $wsl = Get-SetupWslState }
        elseif ($Module -eq 'Extensions') { $inventory = @(Get-SetupExtension) }
        else {
            $installed = @(Get-LocalInstallation)
            foreach ($package in Get-SetupPackage $Module) { $inventory += Get-SetupInventory $package $installed }
            if ($Module -eq 'Modernization') { $inventory += @(Get-SetupExtension -Modernization) }
        }
        foreach ($item in $inventory | Where-Object State -eq Installed) {
            Write-ShowcaseMessage "[PASS] SKIP download/install/upgrade: $($item.Id); version $($item.Version); location $($item.Path)."
        }
        if (@($inventory | Where-Object { $_.State -eq 'Installed' -and -not $_.Compatible }).Count -gt 0) {
            throw 'Installed version/location is incompatible or cannot prove sample readiness. Retained without downloads/upgrades; obtain a separate IT-approved version decision.'
        }
        $missing = @($inventory | Where-Object State -eq Missing)
        if ($null -ne $wsl) {
            Write-ShowcaseMessage "[INFO] WSL installed=$($wsl.Installed); version=$($wsl.Version); distributions=$($wsl.Distributions -join ', '); features=$($wsl.Features | ConvertTo-Json -Compress)."
            if ($Module -eq 'Ubuntu') {
                if ($wsl.UbuntuInstalled) {
                    Write-ShowcaseMessage '[PASS] SKIP Ubuntu download/install; existing package/distro retained. Complete any first-use user prompt yourself.'
                    return 0
                }
                if (-not $wsl.Installed -or -not $wsl.Path -or @($wsl.Features | Where-Object State -ne Enabled).Count -gt 0) {
                    throw 'Ubuntu requires installed WSL and enabled features after any user restart. No download started.'
                }
                $missing = @([pscustomobject]@{ Id = 'Ubuntu'; State = 'Missing'; Path = $wsl.Path })
            } else {
                if ($wsl.Installed) { Write-ShowcaseMessage '[PASS] SKIP WSL runtime download/update; existing runtime and all distro data retained.' }
                if (@($wsl.Features | Where-Object State -in @('EnablePending', 'DisablePending')).Count -gt 0) {
                    throw 'WSL feature restart pending. Save work and choose a restart yourself; no install/update started.'
                }
                $missing = @($wsl.Features | Where-Object State -eq Disabled | ForEach-Object {
                    [pscustomobject]@{ Id = $_.Name; State = 'Missing'; Path = 'WindowsFeature' }
                })
                if (-not $wsl.Installed) { $missing += [pscustomobject]@{ Id = 'Microsoft.WSL'; State = 'Missing'; Path = '' } }
            }
        }
        foreach ($item in $missing) { Write-ShowcaseMessage "[WARN] Missing target: $($item.Id); only this target is eligible." }
        if (-not $Apply -or $WhatIfPreference -or $missing.Count -eq 0) {
            Write-ShowcaseMessage "[PASS] Module $Module inventory/preview complete in $([int]$clock.Elapsed.TotalSeconds)s. This is NOT full workstation verification."
            return 0
        }
        if (($Module -eq 'Extensions' -or
            @($missing | Where-Object Id -eq 'vscjava.migrate-java-to-azure').Count -gt 0) -and -not $ExtensionSourceApproved) {
            throw 'Missing extensions require explicit ExtensionSourceApproved after IT validates existing CLI/default-profile marketplace routing. No public-source override.'
        }
        Assert-WorkstationPolicy
        Invoke-SetupReadiness $HttpsTimeoutSeconds
        # Only human apply creates a local, non-secret event journal; no provider
        # restore, profile changes, or pre-existing download ownership is involved.
        $mutex = New-Object Threading.Mutex($false, 'Local\Win11ShowcaseModularSetup')
        if (-not $mutex.WaitOne(0)) { throw 'Another modular setup is active. Wait; no concurrent installer or automatic retry.' }
        $mutexHeld = $true
        $logDirectory = Join-Path (Get-ShowcaseRoot) '.showcase-setup'
        Assert-SafeDirectory $logDirectory
        if (-not (Test-Path -LiteralPath $logDirectory)) { $null = New-Item -ItemType Directory -Path $logDirectory }
        $logPath = Join-Path $logDirectory ("module-{0}-{1}.jsonl" -f $Module, [guid]::NewGuid().ToString('N'))
        Write-SetupEvent $logPath $Module 'Started'
        Write-ShowcaseMessage "[INFO] Module event log: $logPath (states only, no installer output/credentials)."
        $restart = $false
        foreach ($item in $missing) {
            if (-not $PSCmdlet.ShouldProcess($item.Id, "Install locally proven missing target only; $Module module; no upgrades; Docker requires licence approval")) {
                Write-ShowcaseMessage "[WARN] Target declined; still missing/unverified: $($item.Id)."
                Write-SetupEvent $logPath $Module 'Declined' $item.Id ([int]$clock.Elapsed.TotalSeconds)
                continue
            }
            Write-SetupEvent $logPath $Module 'CheckingAgain' $item.Id ([int]$clock.Elapsed.TotalSeconds)
            # Reinventory before each installer: a concurrent/manual installation is not adopted as missing.
            if ($item.Path -eq 'WindowsFeature') {
                $current = Get-SetupWslState
                if (($current.Features | Where-Object Name -eq $item.Id).State -ne 'Disabled') {
                    Write-ShowcaseMessage "[WARN] Feature state changed; retained: $($item.Id)"; continue
                }
                $dism = Get-NativeCommandPath dism
                if (-not $dism) { throw 'DISM prerequisite unavailable; no feature change.' }
                $result = Invoke-SetupNative $dism @('/Online', '/Enable-Feature', "/FeatureName:$($item.Id)",
                    '/All', '/NoRestart') $item.Id $InstallTimeoutSeconds
                if ($result.ExitCode -notin @(0, 3010)) { throw "Feature operation failed: exit $($result.ExitCode); no automatic retry." }
                Write-ShowcaseMessage "[PASS] Feature operation returned without automatic restart: $($item.Id)."
                Write-SetupEvent $logPath $Module 'FeatureReturned' $item.Id ([int]$clock.Elapsed.TotalSeconds)
                if ($result.ExitCode -eq 3010) {
                    Write-ShowcaseMessage '[WARN] Restart required. Module paused; restart yourself before retrying WSL. No runtime/distro download follows a pending feature restart.'
                    Write-SetupEvent $logPath $Module 'RestartRequired' $item.Id ([int]$clock.Elapsed.TotalSeconds)
                    return 0
                }
                continue
            }
            if ($Module -eq 'Ubuntu') {
                if ((Get-SetupWslState).UbuntuInstalled) { Write-ShowcaseMessage '[PASS] SKIP Ubuntu now present.'; continue }
                $result = Invoke-SetupNative $item.Path @('--install', '--distribution', 'Ubuntu', '--no-launch') 'Ubuntu' $InstallTimeoutSeconds
            } elseif ($Module -eq 'Extensions' -or $item.Id -eq 'vscjava.migrate-java-to-azure') {
                $current = @(Get-SetupExtension -Modernization:($Module -eq 'Modernization') | Where-Object Id -eq $item.Id)[0]
                if ($current.State -eq 'Installed') { Write-ShowcaseMessage "[PASS] SKIP extension now present: $($item.Id)"; continue }
                $result = Invoke-SetupNative $current.Path @('--install-extension', $item.Id) $item.Id $InstallTimeoutSeconds
            } else {
                if ($item.Id -eq 'Microsoft.WSL') {
                    if ((Get-SetupWslState).Installed) { Write-ShowcaseMessage '[PASS] SKIP WSL now present.'; continue }
                } else {
                    $package = @(Get-SetupPackage $Module | Where-Object Id -eq $item.Id)[0]
                    $current = Get-SetupInventory $package @(Get-LocalInstallation)
                    if ($current.State -eq 'Installed') { Write-ShowcaseMessage "[WARN] SKIP now installed: $($item.Id); re-run read-only inventory for compatibility."; continue }
                }
                $winget = Get-NativeCommandPath winget
                if (-not $winget) { throw 'WinGet prerequisite unavailable; no provider/source restore or installer download.' }
                $installArguments = @('install', '--id', $item.Id, '--exact', '--source', 'winget',
                    '--silent', '--disable-interactivity', '--accept-package-agreements')
                if ($Module -eq 'Go' -and $package.PSObject.Properties['Version']) { $installArguments += @('--version', [string]$package.Version) }
                $result = Invoke-SetupNative $winget $installArguments $item.Id $InstallTimeoutSeconds
            }
            if ($result.ExitCode -in @(3010, 1641)) { $restart = $true }
            elseif ($result.ExitCode -ne 0) { throw "Target $($item.Id) installer exit $($result.ExitCode). Stop and diagnose; no automatic retry." }
            Write-ShowcaseMessage "[PASS] Installer returned for $($item.Id); exit $($result.ExitCode); elapsed $($result.ElapsedSeconds)s. Fresh-terminal inventory/Verify still required."
            Write-SetupEvent $logPath $Module 'InstallerReturned' $item.Id ([int]$clock.Elapsed.TotalSeconds)
        }
        if ($restart) { Write-ShowcaseMessage '[WARN] Restart required: save work and restart yourself before subsequent modules. No automatic reboot.' }
        Write-ShowcaseMessage "[PASS] Module $Module completed in $([int]$clock.Elapsed.TotalSeconds)s; not full workstation verification. Run inventory/Verify in a fresh terminal."
        Write-SetupEvent $logPath $Module 'ModuleReturned' '' ([int]$clock.Elapsed.TotalSeconds)
        return 0
    } catch {
        Write-ShowcaseMessage "[FAIL] Module $Module stopped after $([int]$clock.Elapsed.TotalSeconds)s: $($_.Exception.Message)"
        Write-SetupEvent $logPath $Module 'StoppedUnverified' '' ([int]$clock.Elapsed.TotalSeconds)
        return 1
    } finally {
        if ($mutexHeld) { $mutex.ReleaseMutex() }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}

Export-ModuleMember -Function Get-SetupPackage, Get-LocalInstallation, Get-SetupExecutable,
    Get-SetupInventory, Get-SetupExtension, Get-SetupWslState, Invoke-SetupNative,
    Invoke-SetupReadiness, Invoke-SetupModule, Write-SetupEvent
