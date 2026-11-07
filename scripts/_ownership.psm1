<#
.SYNOPSIS
Conservative checkout-local receipts for newly created, exact generated files.
.DESCRIPTION
Receipts are bound to the Git worktree and checked against an independent hash
anchor. Existing files, environments, module trees and shared caches are never
adopted. This is accidental-edit protection, not a security boundary against a
user who can deliberately rewrite both the receipt and its Git-local anchor.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '_common.psm1')
$script:ActiveOwnership = $null

function Get-OwnedOutputPath {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    @('artifacts\pester.xml', 'artifacts\powershell-coverage.xml',
        'samples\python-emi-api\test-results.xml', 'samples\python-emi-api\coverage.xml',
        'samples\python-emi-api\.coverage', 'samples\go-fx-rates\test-results.json',
        'samples\go-fx-rates\coverage.out', 'samples\go-fx-rates\coverage.html',
        'samples\java-ifsc-service\target\jacoco.exec',
        'samples\java-ifsc-service\target\site\jacoco\jacoco.xml')
}

function Assert-OwnedPath {
    [CmdletBinding()]
    param([string]$Root, [string]$RelativePath, [switch]$Metadata)
    $allowed = if ($Metadata) { @('.showcase-owned.json') } else { @(Get-OwnedOutputPath) }
    if ($RelativePath -cnotin $allowed) { throw 'Path is not an exact allowed checkout output.' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $RelativePath))
    if (-not $path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Output escaped the checkout.'
    }
    Assert-SafeDirectory $rootPath
    $current = $path
    while ($current -and $current -ne $rootPath) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse output refused.' }
            if ($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $current '.git'))) {
                throw 'Nested repository output refused.'
            }
        }
        $current = Split-Path -Parent $current
    }
    $git = Get-NativeCommandPath git
    if (-not $git) { throw 'Git is required to prove tracked-file exclusion.' }
    $tracked = Invoke-NativeCommand $git @('--literal-pathspecs', 'ls-files', '--error-unmatch', '--', $RelativePath.Replace('\', '/')) -WorkingDirectory $Root
    if ($tracked.TimedOut -or $tracked.ExitCode -notin @(0, 1)) { throw 'Cannot verify tracked-file exclusion.' }
    if ($tracked.ExitCode -eq 0) { throw 'Tracked output refused; source and staged files are retained.' }
    return $path
}

function Get-OwnershipLocation {
    [CmdletBinding()]
    param()
    $root = [IO.Path]::GetFullPath((Get-ShowcaseRoot)).TrimEnd('\')
    Assert-SafeDirectory $root
    $git = Get-NativeCommandPath git
    if (-not $git) { throw 'Git is required for checkout ownership.' }
    $result = Invoke-NativeCommand $git @('rev-parse', '--absolute-git-dir') -WorkingDirectory $root
    Assert-NativeSuccess $result 'Resolve checkout Git metadata'
    $gitDirectory = $result.StdOut.Trim()
    Assert-SafeDirectory $gitDirectory
    [pscustomobject]@{ Root = $root; Ledger = (Join-Path $root '.showcase-owned.json')
        Anchor = (Join-Path $gitDirectory 'showcase-ownership.json')
        Lock = (Join-Path $gitDirectory 'showcase-operation.lock') }
}

function Save-OwnershipReceipt {
    [CmdletBinding()]
    param([object]$Context)
    if ($Context.Receipt.Root -cne $Context.Location.Root) { throw 'Wrong checkout receipt cannot be saved.' }
    if ((Test-Path -LiteralPath $Context.Location.Ledger) -or (Test-Path -LiteralPath $Context.Location.Anchor)) {
        $existing = Get-OwnershipReceipt $Context.Location
        if ($existing.Workspace -cne $Context.Receipt.Workspace) { throw 'Workspace ownership changed; save refused.' }
    }
    $null = Assert-OwnedPath $Context.Location.Root '.showcase-owned.json' -Metadata
    foreach ($path in @($Context.Location.Ledger, $Context.Location.Anchor)) {
        if (Test-Path -LiteralPath $path) {
            $handle = Open-OwnedOutput $path
            $handle.Dispose()
        }
    }
    $text = ConvertTo-Json -InputObject $Context.Receipt -Depth 5
    [IO.File]::WriteAllText($Context.Location.Ledger, $text)
    $anchor = [ordered]@{ Root = $Context.Location.Root; Workspace = $Context.Receipt.Workspace
        Hash = (Get-FileHash -LiteralPath $Context.Location.Ledger -Algorithm SHA256).Hash }
    [IO.File]::WriteAllText($Context.Location.Anchor, (ConvertTo-Json $anchor))
}

function Get-OwnershipReceipt {
    [CmdletBinding()]
    param([object]$Location)
    $null = Assert-OwnedPath $Location.Root '.showcase-owned.json' -Metadata
    $ledgerExists = Test-Path -LiteralPath $Location.Ledger
    $anchorExists = Test-Path -LiteralPath $Location.Anchor
    if (-not $ledgerExists -and -not $anchorExists) { return $null }
    if (-not $ledgerExists -or -not $anchorExists) { throw 'Incomplete ownership metadata; no adoption or cleanup permitted.' }
    Assert-SafeDirectory (Split-Path -Parent $Location.Anchor)
    foreach ($path in @($Location.Anchor, $Location.Ledger, $Location.Lock)) {
        if (Test-Path -LiteralPath $path) {
            if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Replaced ownership metadata refused.'
            }
            if ($path -ne $Location.Lock) {
                $handle = Open-OwnedOutput $path
                $handle.Dispose()
            }
        }
    }
    $anchor = Get-Content -LiteralPath $Location.Anchor -Raw | ConvertFrom-Json
    $receipt = Get-Content -LiteralPath $Location.Ledger -Raw | ConvertFrom-Json
    if ($anchor.Root -cne $Location.Root -or $receipt.Root -cne $Location.Root -or
        $receipt.Version -ne 1 -or $receipt.Workspace -notmatch '^[a-f0-9]{32}$' -or
        $anchor.Workspace -cne $receipt.Workspace -or
        $anchor.Hash -cne (Get-FileHash -LiteralPath $Location.Ledger -Algorithm SHA256).Hash) {
        throw 'Ownership metadata changed or belongs to a different checkout; retained.'
    }
    foreach ($file in @($receipt.Files)) {
        $null = Assert-OwnedPath $Location.Root $file.Path
        if ($file.Hash -notmatch '^[A-F0-9]{64}$' -or $file.Identity -notmatch '^[0-9]+:[0-9]+:[0-9]+$') {
            throw 'Invalid output fingerprint/identity.'
        }
    }
    foreach ($container in @($receipt.Containers)) {
        if ($container.Id -notmatch '^[a-f0-9]{64}$' -or $container.Runtime -cnotin @('docker', 'wslc') -or
            $container.Name -cnotin @('win11-demo-python-emi-api', 'win11-demo-java-ifsc-service',
                'win11-demo-go-fx-rates', 'win11-demo-java-legacy-upgrade')) {
            throw 'Invalid container receipt.'
        }
    }
    return $receipt
}

function Enter-ShowcaseOperation {
    [CmdletBinding()]
    param([switch]$ReadOnly, [string[]]$OutputPaths = @())
    $location = Get-OwnershipLocation
    $receipt = Get-OwnershipReceipt $location
    if ($ReadOnly -and -not (Test-Path -LiteralPath $location.Lock)) {
        if ($null -ne $receipt) { throw 'Ownership lock missing; retained.' }
        return [pscustomobject]@{ Location = $location; Receipt = $null; Handle = $null; Before = @{} }
    }
    if (Test-Path -LiteralPath $location.Lock) {
        if ((Get-Item -LiteralPath $location.Lock -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Operation lock replaced; retained.'
        }
        $lockCheck = Open-OwnedOutput $location.Lock
        $lockCheck.Dispose()
    }
    $mode = if ($ReadOnly) { [IO.FileMode]::Open } else { [IO.FileMode]::OpenOrCreate }
    $access = if ($ReadOnly) { [IO.FileAccess]::Read } else { [IO.FileAccess]::ReadWrite }
    $handle = [IO.File]::Open($location.Lock, $mode, $access, [IO.FileShare]::None)
    try {
        $receipt = Get-OwnershipReceipt $location
        if ($null -eq $receipt -and -not $ReadOnly) {
            $receipt = [pscustomobject]@{ Version = 1; Root = $location.Root
                Workspace = [guid]::NewGuid().ToString('N'); Files = @(); Containers = @() }
        }
        $context = [pscustomobject]@{ Location = $location; Receipt = $receipt; Handle = $handle; Before = @{} }
        if (-not $ReadOnly) {
            foreach ($relative in $OutputPaths) {
                $path = Assert-OwnedPath $location.Root $relative
                $context.Before[$relative] = Test-Path -LiteralPath $path
            }
            Save-OwnershipReceipt $context
            $script:ActiveOwnership = $context
        }
        return $context
    } catch { $handle.Dispose(); throw }
}

function Exit-ShowcaseOperation {
    [CmdletBinding()]
    param([object]$Context, [switch]$Record)
    try {
        if ($Record) {
            # Only files absent before this controlled operation are eligible.
            # Existing receipts are not refreshed after an overwrite or user edit.
            foreach ($relative in @($Context.Before.Keys)) {
                $path = Assert-OwnedPath $Context.Location.Root $relative
                if (-not $Context.Before[$relative] -and (Test-Path -LiteralPath $path -PathType Leaf) -and
                    @($Context.Receipt.Files | Where-Object Path -ceq $relative).Count -eq 0) {
                    $handle = Open-OwnedOutput $path
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try {
                        $hash = [BitConverter]::ToString($sha.ComputeHash($handle)).Replace('-', '')
                        $Context.Receipt.Files += [pscustomobject]@{ Path = $relative; Hash = $hash
                            Identity = [Showcase.OwnedFile]::Identity($handle) }
                    } finally { $sha.Dispose(); $handle.Dispose() }
                }
            }
            Save-OwnershipReceipt $Context
        }
    } finally {
        $script:ActiveOwnership = $null
        if ($null -ne $Context.Handle) { $Context.Handle.Dispose() }
    }
}

function Get-ShowcaseWorkspace {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($null -eq $script:ActiveOwnership) { throw 'Container launch requires an active checkout operation.' }
    return $script:ActiveOwnership.Receipt.Workspace
}

function Register-ShowcaseContainer {
    [CmdletBinding()]
    param([string]$Id, [string]$Name, [string]$Runtime)
    $null = Get-ShowcaseWorkspace
    if ($Id -notmatch '^[a-f0-9]{64}$' -or $Runtime -cnotin @('docker', 'wslc') -or
        $Name -cnotin @('win11-demo-python-emi-api', 'win11-demo-java-ifsc-service',
            'win11-demo-go-fx-rates', 'win11-demo-java-legacy-upgrade')) {
        throw 'Container did not return an immutable expected identity; not adopted.'
    }
    $script:ActiveOwnership.Receipt.Containers += [pscustomobject]@{ Id = $Id; Name = $Name; Runtime = $Runtime }
    Save-OwnershipReceipt $script:ActiveOwnership
}

function Unregister-ShowcaseContainer {
    [CmdletBinding()]
    param([ValidatePattern('^[a-f0-9]{64}$')][string]$Id)
    $null = Get-ShowcaseWorkspace
    $script:ActiveOwnership.Receipt.Containers = @($script:ActiveOwnership.Receipt.Containers | Where-Object Id -cne $Id)
    Save-OwnershipReceipt $script:ActiveOwnership
}

function Test-OwnedContainer {
    [CmdletBinding()]
    [OutputType([bool])]
    param([object]$Container, [string]$Workspace, [object]$Runtime)
    $result = Invoke-NativeCommand $Runtime.Path @('inspect', $Container.Id) -TimeoutSeconds 30
    Assert-NativeSuccess $result 'Inspect exact recorded container; no runtime fallback'
    $items = @($result.StdOut | ConvertFrom-Json)
    if ($items.Count -ne 1) { throw 'Unexpected container inspection response.' }
    $item = $items[0]
    return ($item.Id -ceq $Container.Id -and $item.Name -ceq ('/' + $Container.Name) -and
        $item.Config.Labels.PSObject.Properties['io.win11-dev-workstation.workspace'] -and
        $item.Config.Labels.'io.win11-dev-workstation.workspace' -ceq $Workspace -and
        $item.Config.Labels.PSObject.Properties['io.win11-dev-workstation.showcase'] -and
        $item.Config.Labels.'io.win11-dev-workstation.showcase' -ceq 'true')
}

function Open-OwnedOutput {
    [CmdletBinding()]
    param([string]$Path)
    if (-not ('Showcase.OwnedFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Showcase {
    public static class OwnedFile {
        [StructLayout(LayoutKind.Sequential)]
        struct Info {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern SafeFileHandle CreateFile(string path, uint access, uint share,
            IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool SetFileInformationByHandle(SafeFileHandle handle, int kind,
            ref byte delete, uint length);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,
            System.Text.StringBuilder path, uint length, uint flags);
        public static FileStream Open(string path) {
            var handle = CreateFile(path, 0x80010000, 0, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
            if (handle.IsInvalid) { handle.Dispose(); throw new Win32Exception(Marshal.GetLastWin32Error()); }
            Info info;
            if (!GetFileInformationByHandle(handle, out info) || info.Links != 1 ||
                (info.Attributes & (0x400 | 0x10)) != 0) {
                handle.Dispose(); throw new IOException("Hardlink, reparse or non-file output refused.");
            }
            return new FileStream(handle, FileAccess.Read);
        }
        public static void Delete(FileStream stream, string expectedPath) {
            var path = new System.Text.StringBuilder(32768);
            uint length = GetFinalPathNameByHandle(stream.SafeFileHandle, path, 32768, 0);
            if (length == 0 || length >= 32768) throw new IOException("Cannot verify locked output path.");
            string finalPath = path.ToString();
            if (finalPath.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
                finalPath = @"\\" + finalPath.Substring(8);
            else if (finalPath.StartsWith(@"\\?\", StringComparison.Ordinal))
                finalPath = finalPath.Substring(4);
            if (!String.Equals(finalPath, System.IO.Path.GetFullPath(expectedPath), StringComparison.OrdinalIgnoreCase))
                throw new IOException("Locked output moved; deletion refused.");
            byte delete = 1;
            if (!SetFileInformationByHandle(stream.SafeFileHandle, 4, ref delete, 1))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        public static string Identity(FileStream stream) {
            Info info;
            if (!GetFileInformationByHandle(stream.SafeFileHandle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return info.Volume + ":" + info.IndexHigh + ":" + info.IndexLow;
        }
    }
}
'@
    }
    return [Showcase.OwnedFile]::Open($Path)
}

function Remove-OwnedOutput {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([IO.FileStream]$Handle, [string]$Path)
    if ($PSCmdlet.ShouldProcess($Path, 'Delete the exact locked output file')) {
        [Showcase.OwnedFile]::Delete($Handle, $Path)
    }
}

Export-ModuleMember -Function Get-OwnedOutputPath, Assert-OwnedPath, Get-OwnershipLocation,
    Save-OwnershipReceipt, Get-OwnershipReceipt, Enter-ShowcaseOperation, Exit-ShowcaseOperation,
    Get-ShowcaseWorkspace, Register-ShowcaseContainer, Unregister-ShowcaseContainer,
    Test-OwnedContainer, Open-OwnedOutput, Remove-OwnedOutput
