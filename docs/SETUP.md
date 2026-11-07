# Setup

Run setup only on an approved development device. These are instructions for a human operator, not permission for an agent to change this machine.

## Prerequisites

- Windows 11, build 22621 or later for this add-on; Windows PowerShell 5.1 or PowerShell 7.
- Approved local administrator elevation, hardware virtualization enabled, and about 15 GB free for the base. Allow additional space for SDKs and images.
- App Installer/WinGet registered for the signed-in developer; WinGet configuration support and IT policy permission.
- Network access and approved proxies described in [IT prerequisites](IT-PREREQUISITES.md).
- An assigned organisation Copilot seat; Azure sign-in is only needed for Azure work.

The [Microsoft base guide](https://github.com/microsoft/WindowsDeveloperConfig/blob/main/src/windows-dev-config/README.md) estimates roughly 30 minutes on a clean machine with a good connection. Add-on downloads and enterprise inspection can take longer; the 15-minute demo assumes setup is already complete.

## Three steps

### 1. Review and start the Microsoft base

Open PowerShell at the cloned repository root:

```powershell
.\scripts\preflight.ps1
.\scripts\bootstrap.ps1 -WhatIf
.\scripts\bootstrap.ps1
```

Preflight is read-only and stops bootstrap on failure. Bootstrap verifies a `Valid` Authenticode signature with a signer subject containing `Microsoft Corporation` before executing the standard Microsoft wrapper. Invalid or unverifiable signatures are fatal; never bypass that check.

The base may show up to two UAC prompts: initial elevation and elevation after the WSL restart. Save all work before starting; Microsoft's guide describes a restart countdown. Sign back in and allow its `WindowsDevConfigResume` task to finish. Open Ubuntu once afterwards to create the Linux user.

### 2. Finish the add-on and verify

**Microsoft's resume task does not resume this repository's add-on.** After the base summary, open a fresh terminal at the repository root:

```powershell
.\scripts\bootstrap.ps1 -SkipBase
.\scripts\verify.ps1
.\scripts\verify.ps1 -RunConfigTest
.\scripts\verify.ps1 -Json
```

If no restart was required, bootstrap can proceed directly to the add-on. Re-running with `-SkipBase` checks/applies the add-on without running the Microsoft base again.

For separate review, test or apply of the declarative configuration:

```powershell
winget configure show -f .config\configuration.winget
winget configure test -f .config\configuration.winget
winget configure -f .config\configuration.winget --accept-configuration-agreements
```

`show` and `test` do not apply the configuration; `test` invokes resource test logic and may need resource modules/network access. Read configuration and licence agreements before applying.

Default verification checks **12 required extensions**. The workspace has **13 recommendations**, but the modernization extension is optional:

```powershell
.\scripts\bootstrap.ps1 -SkipBase -IncludeJavaModernization
.\scripts\verify.ps1 -IncludeJavaModernization -RunConfigTest
```

This opt-in adds the legacy Java toolchain and modernization extension; it is not required for the main samples.

`verify.ps1 -IncludeJavaModernization` checks the optional extension; it does not select or independently prove Java 11 for legacy tests. `-RunConfigTest` tests both configuration files only when combined with that switch. `-Json` emits the results array, not an installation report. Select and confirm the legacy JDK separately before its Maven verification.

### 3. Sign in and start development

Open the folder in VS Code. Hover over the Copilot Status Bar icon → **Use AI Features** and sign in with the organisation-approved GitHub account. Confirm its assigned licence and policies. See the [official sign-in guide](https://code.visualstudio.com/docs/setup/copilot).

When authorised to use Azure, run `az login` and select the approved tenant/subscription through your normal access process. Sign-in creates no application resources. The demo prepares files only; deployment is a separate approval.

Build/test commands are in [AGENTS.md](../AGENTS.md) and each sample README. For a separately approved local launch, the contract is:

```powershell
.\scripts\run-sample.ps1 -Name python-emi-api -Mode local -Port 8080
```

Names are `python-emi-api`, `java-ifsc-service`, `go-fx-rates`; modes are `local` or `container`. Container mode prefers `wslc`, then `docker`, and reports the runtime. Docker Desktop is a licensed optional alternative, not installed by default. A Docker-standard device should remove the workspace `dev.containers.dockerPath: wslc` override.

## Official direct setup alternatives

The upstream standard one-liner is `irm https://aka.ms/devconfig/standard/setup.ps1 | iex`. It initially trusts the HTTPS endpoint. To inspect and verify first, a human can download the wrapper into this repository:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/devconfig/standard/setup.ps1' -OutFile .\devconfig-standard.ps1
$signature = Get-AuthenticodeSignature .\devconfig-standard.ps1
if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
    $signature.SignerCertificate.Subject -notlike '*Microsoft Corporation*') {
    throw 'Microsoft signature verification failed; do not execute.'
}
Get-Content -Raw .\devconfig-standard.ps1 | Invoke-Expression
```

The published wrapper uses expression execution; do not assume invoking it as a normal script file has equivalent behaviour. Delete the downloaded file after use. This alternative runs only the base: follow with `.\scripts\bootstrap.ps1 -SkipBase`.

The **full** experience, `irm https://aka.ms/devconfig/full/setup.ps1 | iex`, additionally changes Developer Mode, sudo, Remote Desktop/firewall, widgets and Edge policies. It is **not** this repository's default; require IT approval and use the same download/signature-review pattern before execution.

## Uninstall

The official `irm https://aka.ms/devconfig/standard/uninstall.ps1 | iex` is **destructive**: it removes base tools, resets settings and deletes Ubuntu data. Back up the distribution and personal work, review the upstream uninstall section, and verify the downloaded wrapper as above before execution. It is not a complete inverse of this add-on; have IT review removal of add-on packages/extensions individually. Demo reset is unrelated to workstation uninstall.

Logs: base `%ProgramData%\CalmOS\devconfig-log.txt`; add-on `%LOCALAPPDATA%\win11-dev-workstation\bootstrap-*.log`. Bootstrap generates a timestamp and unique suffix for each log.
