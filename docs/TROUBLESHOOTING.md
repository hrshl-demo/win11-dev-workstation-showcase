# Troubleshooting

Start with [Phase 0 prerequisites](SETUP.md#phase-0-prerequisites-before-repository-scripts) from **VS Code → Terminal → New Terminal → PowerShell**, as the signed-in developer. Inline `Get-ExecutionPolicy -List` and `Get-ExecutionPolicy` work even before scripts are permitted. Only then run Preflight and `winget --info`. Redact paths, identities and secrets. State-changing fixes are **human-operated, IT-approved**. Only the named [Workstation setup](SETUP.md#select-workstation-setup-in-vs-code) workflow can execute separately approved local setup/Restore/launch stages; repair and policy/source/account/profile changes remain human/IT-only, never agent actions. Partial devices follow automated Phase 2 setup; post-setup package/test failures are not a reason to reinstall everything.

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

### Intermittent HTTPS preflight failures

Preflight keeps all six required hosts. It probes HTTPS HEAD with a **default five-second timeout per attempt**, at most three attempts and 250 ms backoff only for classified transport timeout/DNS/connect failures. Final output and clean `-Json` include URI, HTTP status (when available), actual timeout, attempt count, safe error category and reason. Recovery reports PASS with attempt details; exhausted checks remain FAIL. Bootstrap still stops before setup and summarizes failed checks. Do not blindly retry full setup or Restore dependencies to fix a network check.

For an approved slow network, select **30** in the HTTPS timeout picker for **Preflight**, **User-run setup**, and (when the base is already complete/resumed) **Finish setup**. Keep the same explicit choice for setup: a standalone Preflight at 30 followed by default-5 bootstrap otherwise rechecks at 5. Direct `-HttpsTimeoutSeconds 30` is supported on preflight/bootstrap/developer; no file edits or per-tool installs. Only HTTPS readiness changes. The six-host/three-attempt outer child budget is bounded at **663 seconds** for 30 (543 HTTPS/backoff + 120 platform allowance), **213 seconds** at default 5; HTTP denial, certificate failures and setup gates remain unchanged.

An operator observed the same official raw README HEAD return HTTP 200 after **21.74 seconds** with timeout 30, following three default-5 timeouts. This supports explicit slow-network configuration for that observation, not a claim that all historical failures are latency or that all payloads are accessible. Do not request more blind installer retries or bypass TLS/proxy policy. See [the exact picker/commands](SETUP.md#explicit-slow-network-choice).

A root HTTP **404/405** can establish host reachability, **not artifact download permission**. The raw host uses the official WindowsDeveloperConfig README path, and codeload uses that repository's official archive HEAD endpoint rather than its redirecting service root; no archive content is downloaded by this probe and no fictitious release asset is tested. **401/403/407** are access failures; redirects are not followed (including login/proxy pages), certificate failures are not retried, and HTTP failures are never made green with curl or another proxy. An earlier generic FAIL without transport details does not prove its cause was 404: the old helper already accepted any HTTP response, including 404, but hid no-response failures.

After a failure, use the recorded diagnostics and the read-only **Preflight** task / `.\scripts\preflight.ps1 -Json` in the same approved context; IT can inspect proxy/DNS/TLS/source access. No mandatory curl prerequisite, TLS/certificate disabling, policy/proxy changes or dependency restoration is a remedy supplied by this check. Payload/CDN/enterprise acceptance is still separate from reachability.

| Symptom | Action |
| --- | --- |
| Verify exit 1 before setup; outputs absent | Expected optional inventory; use **Setup preview** → matching independently confirmed module. Existing software is checked before downloading; incompatible/unknown is retained. **Finish setup** is optional LEGACY-only, never recovery for a stopped partial base |
| Repository script blocked before bootstrap/preflight runs, or module import denied | An effective Restricted policy blocks repository scripts; AllSigned requires trusted signatures for scripts and modules. Bootstrap may be blocked before its body or preflight runs, and module imports may also be denied. Obtain an IT-approved script-execution context first. The upstream Microsoft signature does not authorize this repository's scripts. No automatic policy override is permitted. |
| Optional legacy base restarted; add-on missing | Wait for confirmed successful base summary/reboot/resume, then explicitly select legacy Finish setup. Normal modules do not require a Microsoft base |
| Signature invalid / wrong publisher | Stop. Do not run the downloaded wrapper; review network inspection, trust chain and upstream source with IT |
| Tools missing immediately after install | Open a new terminal; compare PATH and `.\scripts\verify.ps1`. Do not claim success until verification passes |
| Default Restricted; all policy scopes Undefined | Read effective policy as well as the list. Only the human with IT permission may follow Phase 0's persistent CurrentUser RemoteSigned route. Undefined does not certify all IT policy is clear; no Bypass/process override |
| Required extensions missing or disabled after setup; private marketplace shown | The banner alone proves no block. Compare the approved CLI installation/account, intended existing profile, enabled extensions and effective source/allowlist policy. DSC/Verify do not select that profile. Stop acceptance if unsupported; IT supplies compatible **automated** managed delivery, not twelve manual installs or a public-marketplace fallback |
| WSL/wslc absent before setup | Preflight WARN expected. Preview WSL module in an approved Administrator terminal. Existing runtime is not silently updated; an incompatible version needs a separate IT-approved decision. Ubuntu is a separate opt-in, never reset |
| `wslc` unavailable after completed setup | Check `wsl --version`, resume/logs and policy; CLI requires WSL 2.9.3+. IT/human may approve the documented configuration update; agents must not run it |
| Container image pull denied | Check WSL container/registry policies and approved registry availability. Never bypass the allowlist |
| Dev Containers expects `wslc` on a Docker-standard device | Remove the workspace `dev.containers.dockerPath` override with approval; use the approved runtime |
| Modernization extension missing | Expected unless opted in; use `-IncludeJavaModernization` only for the optional exercise |
| Port conflict / demo drift | Use only approved sample launch parameters; follow [sample-scoped recovery](DEMO-SCRIPT.md#recovery-without-losing-unrelated-work). User fetches safe `origin/main` first in VS Code; reset previews/confirms only samples and owned containers, never the historical unsafe tag or mass cleanup |

## Daily checks, GitHub and existing AKS

| Symptom | Safe next step |
| --- | --- |
| Test/lint/coverage says a package or runtime is missing | Mark NOT RUN. Missing setup outputs return to Phase 2; project packages use a separate Phase 4 Restore approval. After completed setup, diagnose logs/PATH/policy before reapplying. Daily commands never install/restore; only the named human-invoked workflow can return to a separately approved acquisition stage. |
| RunContainer reports no existing local image | Mark NOT RUN. The developer may separately approve Restore with RestoreTarget ContainerImages and -Confirm; Run itself never builds or pulls and uses --pull=never. |
| Python/Java tests missing from Testing view | Select the locked `.venv` interpreter/correct Java 25 JDK; check extension discovery. Do not accept automatic helper/tool downloads without approval. |
| GitHub sign-in works but Publish Branch fails | Sign-in does not grant repository write access. Review remote/organisation access or use an approved fork in the GitHub Pull Requests flow. |
| Deployment refuses source SHA | Use the reviewed current remote main 40-character SHA. If main moved, request a new run; do not loosen the check or deploy from a PR/fallback tag. |
| Environment reviewer/API protection unavailable | Stop. Check plan and `aks-demo` rules with the administrator. Private environment creation alone does not establish reviewer protection; no manual-dispatch bypass. |
| OIDC subject mismatch | IT verifies this repository's actual immutable/legacy subject format and exact federation. No wildcard trust or client-secret workaround. |
| ACR push/pull denied | IT reviews registry permission mode, repository conditions and kubelet pull identity; ABAC Reader/Writer do not grant catalog listing. No broad Contributor/admin workaround. |
| Private AKS API unreachable | Check approved network-connected runner labels, DNS/TLS/network path with IT. Do not make the API public, disable TLS verification or fetch admin kubeconfig. |
| Namespace absent or rollout fails | Namespace is an IT prerequisite. Stop, inspect safe rollout evidence; do not create namespace/RBAC or disable admission policy. |

See [Setup](SETUP.md) for agent selection, manual tasks and reports, and [GitHub/AKS](GITHUB-AKS.md) for the approval plan. Agents never dispatch; only the named human-invoked workflow may execute its separately approved local launch stage, not launch/retry blindly to troubleshoot.

## Microsoft base launcher timeout

The former one-hour wrapper watchdog could return synthetic exit **124** while elevated Microsoft setup continued. Its initial “Administrator rights / UAC prompt” output does **not** establish UAC denial. Large downloads and retries on a slow network can exceed that wait. Updated bootstrap distinguishes `TimedOut` before ordinary exit handling, reports the actual budget and **unknown, possibly still-running elevated-base state**, and never proceeds to add-on/Verify.

Only **Legacy Microsoft bundle (optional)** has the **7200 / 14400 / 28800 second** base wait picker. Normal modules use a separate per-target default 7200-second bounded wait and never invoke that bundle. HTTPS readiness is independent; termination remains restricted to the owned launcher, never a broad process tree or vendor installer.

**Leave an existing base running.** Do not start another setup, interrupt it, change the working clone or use SkipBase just because the wrapper timed out. Inspect retained base completion/progress evidence and resolve genuine errors with IT; log activity alone is not completion. Only choose **Finish setup** after Microsoft base completion and any required reboot/resume are confirmed, in a fresh terminal. Unknown state requires diagnosis, not an automatic retry. Genuine non-timeout failures and reboot/resume outcomes remain separately reported.

The Microsoft base has a **final keypress pause** after its final “Calm OS setup complete” summary (including flagged steps), or a genuine “stopped early” report, and after transcript closure/lock release. The outer launcher wait includes this and other manual/UAC pauses. A live elevated PID can be awaiting dismissal after success or failure, not necessarily installing. Review the existing final summary/flagged steps and answer its final keypress prompt; confirm successful completion and actual reboot/resume before **Finish setup**. PID presence, log activity or lock release alone is not evidence that setup is incomplete or accepted.

## Stopped partial setup and modular retries

**Repeated “Set Alias” prompts before a Java/module installer:** these are standard Appx module command-name definitions during cold read-only inventory, not Add/Remove/Reset package operations or Java downloads. Installer confirmation previously leaked into that initialization. Inventory now scopes confirmation suppression to its trusted read-only calls and restores the caller preference on success/error; selected-module and missing-target approvals remain. Internal journal creation occurs only after target approval and adds no extra confirmation. Decline/WhatIf starts no installer and writes no module journal. If an older task is still waiting there, the human must first establish its cancellation/outcome before updating or retrying; do not answer repeated prompts as a workaround or start a second installer.

**Registered PowerShell MSIX is installed, not missing.** Current-user `Microsoft.PowerShell` package registration is inventoried alongside MSI/known paths. Discovery probes the actual `pwsh.exe` beneath its validated package installation location, including `Program Files\WindowsApps`; package version metadata alone does not prove runtime readiness. The per-user `Microsoft\WindowsApps` execution alias remains excluded. A denied package query, unreadable/missing executable or incompatible runtime stops acceptance without downloading/reinstalling. Do not change WindowsApps ownership/ACLs, activate an alias, re-register the package or repair PATH/registry to bypass this state. Verify uses the same discovery and requires actual PowerShell 7 while retaining Windows PowerShell 5.1 task support.

**Core preview: illegal characters in an installed location.** Discovery normalizes surrounding quotes/spaces and expands environment variables before using local absolute paths. Malformed, control-character, relative, network or unresolved registered paths produce a package/source-specific **unknown** result, never “missing” or an installer download. An independently proven compatible executable may be selected despite invalid alternate metadata, with a warning; otherwise retain installed software and stop for approved review. The exact offending value in a reported preview failure was not collected: malformed/quoted registration is a reproduced source defect, not a claim about that device. Do not edit registry/PATH or reinstall to bypass unknown inventory. Inactive NVM versions are locally inspected for Node without switching versions or downloading.

A force-closed/cancelled Microsoft run is **stopped partial installation**, not rollback or completed base. Keep installed tools/settings and downloaded files. After confirming previous installers stopped/completed and reviewing the published revision, use matching module **Setup preview** first. Do not rerun the broad bundle or SkipBase as recovery.

Each module inventories actual local installations before any download/provider/source action, including known off-PATH SDK locations. Installed/incompatible targets are retained; unknown registry/version/feature inventory fails without downloads. An old Python or missing pwsh in a stale VS Code terminal does not establish missing software. A new terminal/Reload Window may still inherit VS Code's old environment: after confirmed installs, save work and fully exit/reopen VS Code from Windows when appropriate. Verify reports selected executable locations. Select the reported SDK through documented **process-scope** JAVA_HOME/uv/debugger configuration, never delete old runtimes or overwrite global PATH.

Missing targets alone receive streamed progress and elapsed/exit results. Module success is not full Verify acceptance. A timeout/cancellation can leave a vendor installer active: inspect its own evidence, do not retry until state is confirmed. No automatic retry/rollback/upgrade is implemented. `.showcase-setup\module-*.jsonl` retains non-secret state/elapsed events; unknown or stopped states require diagnosis. WSL feature changes use no-restart and pause when restart is needed; Ubuntu actions require ready WSL, keep all existing distro data and do not launch it automatically.

## Cleanup scope retained

Wait for installation/resume and local application/test/restore tasks to finish before updating the clone or selecting **Cleanup preview**. [Scoped cleanup](SETUP.md#cleanup-after-work-is-finished) leaves GHCP/Copilot and every shared tool, extension, runtime, policy, cache, credential, source file and cloud resource alone. Missing receipts or changed reports are expected retention WARNs: historical files, `.venv`, `.tools`, directories and unknown contents are not retrospectively adopted.

An active operation, locked file, tracked target, altered/cross-checkout receipt, nested repository or link fails closed; stop the owning task normally and inspect the evidence. Never remove locks, edit metadata or bypass permissions to force deletion. Container runtime errors require diagnosis of that recorded runtime; a generic label or matching name does not authorize removal. No global prune/uninstaller is part of this flow.

## Retained logs and primary references

- Base: `%ProgramData%\CalmOS\devconfig-log.txt`; task: `WindowsDevConfigResume`.
- Add-on: `%LOCALAPPDATA%\win11-dev-workstation\bootstrap-*.log` (generated timestamp and unique suffix).
- WinGet: `winget --info`; default `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir`.
- [WinGet installation and registration](https://learn.microsoft.com/en-us/windows/package-manager/winget/), [settings](https://learn.microsoft.com/en-us/windows/package-manager/winget/settings), [upstream troubleshooting](https://github.com/microsoft/WindowsDeveloperConfig), [DesktopAppInstaller policy](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-desktopappinstaller).
