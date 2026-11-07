# Troubleshooting

Start with `.\scripts\preflight.ps1` and `winget --info` from the signed-in developer's terminal. Record exact output and redact paths, identities and secrets before sharing. State-changing fixes below are **human-operated, IT-approved actions**; agents must not execute them.

## WinGet

| Symptom | Likely cause | Check / approved next step |
| --- | --- | --- |
| `winget` not recognised | App Installer missing or not yet registered for this user | `Get-AppxPackage Microsoft.DesktopAppInstaller`; after first sign-in, request registration with `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe` |
| Installed but command missing | Execution alias disabled or WindowsApps absent from PATH | Check Settings → Apps → Advanced app settings → App execution aliases; test `& "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"`. Reopen the terminal after an approved fix |
| Works for administrator, not developer | Per-user App Installer registration differs | Check from the developer account; do not switch permanently to an administrator account |
| Package appears broken | Damaged registration/package | Human-approved Windows 11 reset: `Get-AppxPackage Microsoft.DesktopAppInstaller \| Reset-AppxPackage`; or guided `.\scripts\repair-winget.ps1 -WhatIf`, then `.\scripts\repair-winget.ps1` with confirmation |
| No output / unexpectedly exits | Old or damaged client | Update App Installer through Microsoft Store or [official releases](https://github.com/microsoft/winget-cli/releases); inspect logs and then, if approved, `winget source update` |
| `configure` unrecognised | Old client or configuration disabled | Check `winget --version` and policy; this repository requires at least 1.6.2631 and warns below 1.6.3482. Human-approved `winget configure --enable`; update App Installer if needed |
| `configure validate` reports “not available publicly” for public units | Catalogue public-availability detection or source/proxy visibility | Verify the public PowerShell Gallery sources and approved proxy path with IT. A catalogue warning can produce exit 1; do not claim native validation passed, bypass policy or automatically run repair |
| Configuration internal error `-2146233079` | Missing Visual C++ runtime, per upstream guidance | IT may install `Microsoft.VCRedist.2015+.x64` or `Microsoft.VCRedist.2015+.arm64` for the actual architecture; guided repair prompts before doing so |
| Operation disabled by Group Policy | Organisation policy | `winget --info`; inspect `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller`. Contact IT; never change or bypass policy |
| Source blocked or missing | Source allow policy / network controls | IT reviews `EnableAllowedSources`, `EnableDefaultSource` and approved source definitions; do not add an unapproved source |
| Delivery Optimization errors `0x801901a0` / `0x80d03002` | Downloader/network path | With IT approval, merge `"network": {"downloader": "wininet"}` into existing `winget settings`; do not replace other settings or assume this fixes every network error |
| `0x80072efd` | Network, proxy or TLS connectivity | Check approved WinHTTP and WinGet proxy configuration, endpoint reachability and TLS 1.2; never disable TLS/certificate verification |
| Scheduled deployment fails as SYSTEM | WinGet CLI is per-user packaged software | Do not run WinGet CLI as SYSTEM. IT must design an appropriate supported management deployment, not impersonate a developer |
| Double-clicking `.winget` fails | App Installer file association/version | It is plain YAML: inspect in VS Code/Notepad, then use the documented PowerShell `winget configure show/test` commands |

Historical version/error associations in supplied instructions are not a substitute for current diagnostics. There is no blanket App Installer `1.11.11451` requirement in the current official installation guide; check the installed client and configuration capability instead.

Observed locally with WinGet `1.29.380`: both profiles passed `configure show` and official schema validation, but `configure validate` exited 1 with public-availability warnings for `Microsoft.Windows.Developer`, `Microsoft.WinGet.DSC`, `PSDscResources` and `Microsoft.VSCode.Dsc`. An absolute isolated `--module-path` under `.tools` reproduced the result without repair or configuration apply. Upstream [ConfigurationFlow.cpp](https://raw.githubusercontent.com/microsoft/winget-cli/master/src/AppInstallerCLICore/Workflows/ConfigurationFlow.cpp) treats `!catalogDetails.IsPublic` as a warning that sets `foundIssue`; schema success and readable configuration therefore do not establish native validation success. Target-environment configuration acceptance remains unobserved.

## Official repair sequence

After policy approval, the [Microsoft troubleshooting guide](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting) documents:

```powershell
Install-PackageProvider -Name NuGet -Force
Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery
Repair-WinGetPackageManager -Force -Latest
```

`-AllUsers` is an explicitly elevated, wider-scope option, not the default remedy. The repository's guided repair checks policy first, asks before mutations, retests, and stops at success. If blocked by organisation policy, contact IT.

## Workstation and demo

| Symptom | Action |
| --- | --- |
| Repository script blocked before bootstrap/preflight runs, or module import denied | An effective Restricted policy blocks repository scripts; AllSigned requires trusted signatures for scripts and modules. Bootstrap may be blocked before its body or preflight runs, and module imports may also be denied. Obtain an IT-approved script-execution context first. The upstream Microsoft signature does not authorize this repository's scripts. No automatic policy override is permitted. |
| Base restarted; add-on missing | Wait for `WindowsDevConfigResume` and the base summary, then run `.\scripts\bootstrap.ps1 -SkipBase` in a fresh terminal |
| Signature invalid / wrong publisher | Stop. Do not run the downloaded wrapper; review network inspection, trust chain and upstream source with IT |
| Tools missing immediately after install | Open a new terminal; compare PATH and `.\scripts\verify.ps1`. Do not claim success until verification passes |
| `wslc` unavailable | Check `wsl --version`; CLI requires WSL 2.9.3+. IT/human may approve `wsl --update`; agents must not run it |
| Container image pull denied | Check WSL container/registry policies and approved registry availability. Never bypass the allowlist |
| Dev Containers expects `wslc` on a Docker-standard device | Remove the workspace `dev.containers.dockerPath` override with approval; use the approved runtime |
| Modernization extension missing | Expected unless opted in; use `-IncludeJavaModernization` only for the optional exercise |
| Port conflict / demo drift | Use only approved sample launch parameters; follow [sample-scoped recovery](DEMO-SCRIPT.md#recovery-without-losing-unrelated-work), not mass process/container cleanup |

## Logs and primary references

- Base: `%ProgramData%\CalmOS\devconfig-log.txt`; task: `WindowsDevConfigResume`.
- Add-on: `%LOCALAPPDATA%\win11-dev-workstation\bootstrap-*.log` (generated timestamp and unique suffix).
- WinGet: `winget --info`; default `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir`.
- [WinGet installation and registration](https://learn.microsoft.com/en-us/windows/package-manager/winget/), [settings](https://learn.microsoft.com/en-us/windows/package-manager/winget/settings), [upstream troubleshooting](https://github.com/microsoft/WindowsDeveloperConfig), [DesktopAppInstaller policy](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-desktopappinstaller).
