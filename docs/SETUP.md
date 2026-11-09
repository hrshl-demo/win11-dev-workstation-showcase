# End-to-end VS Code setup

Follow **Phase 0 prerequisites → Phase 1 preflight → Phase 2 automated laptop setup → Phase 3 verification → Phase 4 project restore and checks → Phase 5 run/debug → Phase 6 GitHub CI → Phase 7 existing AKS**. Humans may run the tasks directly or select the narrowly approved local **Workstation setup** agent below. All other agents explain/inspect and never install; no agent changes policy. Missing languages/extensions on a fresh or partially configured device belong to automated setup, not individual manual installation.

For quick steps, detailed activities and one-screen slides, keep the complete [offline demo companion](../demo-companion/README.md) folder and double-click its `index.html`. Instructions and local assets work offline; source links need network/repository access. Checkmarks record only manual progress, not machine verification. Its README lists standard-library-only content/source checks; no viewer build or server is needed.

## Phase 0: prerequisites before repository scripts

Complete this checklist **before running any repository script**, including Preflight:

| Human / IT prerequisite | Acceptance criterion |
| --- | --- |
| Supported Windows 11 | Serviced Windows 11 release, build 22621+; approved device image |
| Elevation and changes | Permission for administrator/UAC, Windows/WSL changes, reboot and package licences; save work |
| Hardware and storage | Approved virtualization/nested virtualization enabled; at least 15 GB free for the readiness gate, plus selected SDK/cache/image budget |
| App Installer / WinGet | Registered for the signed-in developer, executable and configuration capability allowed; not SYSTEM |
| Network / proxy / trust | Approved WinHTTP and WinGet proxy, payload/module/image endpoints and TLS/AuthentiCode validation paths |
| Minimum clone tools | Approved Git and VS Code available **before cloning**; repository access and permission to trust reviewed source |
| Script execution | Effective policy permits reviewed repository scripts/modules; see the inline checks below |
| Extension delivery | Approved marketplace, extension allowlist, target VS Code installation/account/profile and licences; see [extension acceptance](#extension-source-and-profile-acceptance) |

For the narrower Native Python/Java/Go demo, virtualization and WSL/container
permissions apply only to those separately opted-in scopes; Native Preflight
does not query or require them. Other platform, disk, policy and source
approvals remain required.

Python 3.14, Java 25, Go, WSL/wslc and the 12 required extensions are **setup outputs**, not things you must manually install first. See [IT prerequisites](IT-PREREQUISITES.md) for approvals outside this repository's checks.

This VS Code-first route genuinely requires Git/VS Code first. IT can supply an approved image or software distribution for that minimum; Core also inventories them but cannot install them before you have cloned/opened it. Missing minimum clone tools are an IT prerequisite, not an automatic fallback to the broad Microsoft preset. That preset is only the separately reviewed explicit legacy option described below.

### Script execution before Preflight

In **VS Code → Terminal → New Terminal → PowerShell**, these inline read-only commands work even when scripts are blocked:

```powershell
Get-ExecutionPolicy -List
Get-ExecutionPolicy
```

`Undefined` means no setting in that scope, not permission: all scopes Undefined can still produce effective `Restricted` on a Windows client. The effective command is authoritative for that shell. The list does **not** prove other IT controls (application control, endpoint security, WinGet/WSL or extension policy) are clear.

If effective policy is `Restricted` only because of the default/unset policy, and IT explicitly permits this account to run reviewed local repository scripts, the **human**, not a script/agent, may use:

```powershell
# HUMAN ONLY, after IT approval; this persists for this account:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Get-ExecutionPolicy -List
Get-ExecutionPolicy
```

Record the previous CurrentUser value. This is a persistent account-level change until changed again, not a process-only exception; it does not change LocalMachine and cannot override MachinePolicy/UserPolicy. Do not loosen an explicitly imposed policy. Under `AllSigned`, IT must supply trusted signatures for repository scripts **and modules**; Microsoft's wrapper signature does not sign this repository. If Group Policy or other controls block execution, stop for IT's approved execution/signing route. Never use Bypass, Unrestricted, process overrides or embedded-script execution to evade a block.

A reviewed Git clone and a downloaded ZIP can have different provenance/mark-of-the-web behavior. RemoteSigned still rejects unsigned internet-marked files; inspect the specific blocked file and its provenance with IT, rather than recursively unblocking the repository. No automatic unblocking is supplied. [PowerShell policy reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1).

### Clone and open

In VS Code use **Source Control → Clone Repository**, or **Ctrl+Shift+P → Git: Clone**, with:

```text
https://github.com/hrshl-demo/win11-dev-workstation-showcase
```

Select an approved local folder and open the clone. Read the source before granting Workspace Trust. Use **Terminal → New Terminal**, select **PowerShell**, and keep the repository root as the working directory. **Terminal → Run Task** exposes the same developer actions without leaving the editor. Open a second integrated terminal with the **+** button when a server/port-forward occupies the first.

Browser authentication, UAC and reboot remain external OS/service interactions. Setup duration depends on downloads, device and restart; full provisioning is **not the 15-minute coding demo**, and hosted CI does not prove fresh-laptop acceptance.

### Select Workstation setup in VS Code

Open the reviewed clone as the workspace, with approved Copilot access and
Workspace Trust. In Copilot Chat choose a session target running **locally on
this Windows device** (Local, or Copilot running locally), not remote/cloud.
Choose **Workstation setup** in the **Agent** dropdown. It is discovered natively
from `.github\agents\workstation-setup.agent.md`; no plugin, MCP server, cloud
environment or setup Actions job is needed. Send one kickoff:

```text
Start the local setup and demo journey. Use NativeDemo for Python/Java/Go and essential debugger extensions. Inventory first, retain installed versions/settings, and ask for my approval before installations, dependency Restore and local launches. Keep Azure, containers, WSL and optional scopes separate.
```

The agent reads the scripts/catalog/tasks, checks safe workspace/vendor state,
runs **local installed-software inventory before network Preflight**, reports
missing/retained/unknown scope, and invokes only needed independently approved
modules through existing terminal tools. It re-inventories actual versions,
checks enabled intended-profile acceptance with you, explicitly Restores
approved dependencies, then runs no-hidden-restore Test/Lint/Coverage and the
separately approved local startup/health/synthetic requests. You do **not** need
to copy each command or pick Run Task for every module.

Selection or `start` is **not blanket approval**. Review scoped tool commands,
package/licence/download implications and individual native confirmations in
the exposed terminal. Only **you** answer PowerShell/vendor prompts; the agent
must not type Y/A/Yes-to-All or disable tool/native approval. Administrator/UAC,
restart, script signing and private-marketplace compatibility can require a
human pause. If the harness cannot expose an interactive prompt, the operation
is **NOT RUN/blocked**, not silently rerun unconfirmed.

Default scope is **Native VS Code Python/current Java/Go**, not the full
workstation. `verify.ps1 -NativeDemo -Json` positively checks **18 records**:
eight required tools, five language/debugger extension IDs and all five policy
rows. Native Preflight/Verify do not query WSL/wslc or require virtualization,
Azure tools or containers. The shared definition is
`Get-NativeDemoRequirement` in `scripts\_common.psm1`.
Every Native record must PASS with exit **0**, alongside fresh runtime evidence,
known vendor/reboot safety and human/IT acceptance of the actual enabled
profile and existing source/account routing. Malformed/partial/duplicate/
unexpected records, required FAIL/unknown or policy/profile/source uncertainty
stop. No failure-ignore list or WSL output heuristic is used.

Full `verify.ps1 -Json` remains unchanged and strict: 16 tools, 12 extensions,
five policies. Its missing WSL/stub timeout or optional-full-profile extensions
remain **full FAIL/exit 1**, even if Native passes. Keep full and Native results
separate; full readiness is **NOT RUN/not accepted** if no full inventory was
requested. Do not probe/install WSL to make Native ready. The human's narrower
Native approval permits requesting separately approved Dependencies Restore,
not full readiness, F5 or startup acceptance. `RunLocal` is the existing native
action; it does not select a WSL/container runtime.
WSL changes, Ubuntu, licensed
Docker, modernization, PowerShell test-module Restore, image builds and
container launches have separate approvals. Broad legacy bundle/Finish/SkipBase,
repair, upgrades, policy/source/account/profile changes, automatic elevation/
reboot, cleanup/reset, Git publication and cloud execution are outside the
agent. [AGENTS.md](../AGENTS.md#human-invoked-vs-code-exception) documents the
exception; generic coding/build/desktop/cloud/remote/subagents, including
workflow implementers, still cannot execute setup/preview/WhatIf/Restore/apps.
**Workstation onboarding** remains the read-only explanation alternative.
Existing task/help labels such as **human-operated** and **user-run** include
this named human-invoked route with real approvals; they do not authorize
implementation/build agents or remove any script confirmation.

Troubleshooting's generic agent restrictions still cover coding/read-only
troubleshooting roles and all daily checks. The named workflow may only return
to the separately approved stages above; it never repairs, launches to
troubleshoot, or hides acquisition inside a daily check.

After a known stopped/completed task, or after **you** save work and perform an
approved restart/full VS Code reopen, select the same agent and send:

```text
Resume the local setup and demo journey. Use NativeDemo for Python/Java/Go and essential debugger extensions; leave Azure/containers/WSL separate. Recheck installer/reboot safety and fresh installed-software inventory; do not blindly retry. Ask for new approvals for any remaining changes.
```

The agent does not interpret launcher exit 0, a declined target, an installer
log, cancellation or a progress checkmark as acceptance. Uncertain vendor state
or a pending reboot stops the next install. Live VS Code selection, tool use,
native confirmations and successful laptop execution require a human rehearsal;
schema/static/mocked checks and hosted CI do not establish them.

If the agent is missing, use **Chat: Open Customizations → Agents**, confirm its
workspace source and file diagnostics, and verify the reviewed clone contains
the file. Check the selected local harness's actual read/search/execute tool
inventory: unavailable tools can be ignored by a client. Do not add `*`, change
autoapprove settings or assume that `target` switches execution/security; that
frontmatter field only changes editor interpretation. Use the manual task
fallback below if tools or human-accessible prompts are unavailable, or stop for
IT if policy/signing/source approval is blocked.

## Phase 1: preflight and optional inventory

Choose **Terminal → Run Task → Preflight**, or:

```powershell
.\scripts\preflight.ps1
```

**Gate:** no Preflight FAIL and exit 0, plus Phase 0 approvals. WARN is advisory: missing WSL/wslc is expected before its module and does not block unrelated modules. A policy, disk, virtualization, WinGet or endpoint FAIL must be resolved before apply; a PASS does not certify every enterprise control or payload source.

HTTPS results include URI/status/attempts, the actual timeout and safe failure categories. Default timeout remains **5 seconds per attempt**; classified transient timeout/DNS/connect failures get at most three attempts with 250 ms backoff. HTTP denial and certificate failures do not retry. Root 404/405 means reachability only, not artifact access; redirects are not followed. If exhausted, bootstrap stops before setup and reports the failed checks—do not keep retrying full setup blindly or Restore dependencies to unblock the network.

### Explicit slow-network choice

If a permitted endpoint responds too slowly, choose **Terminal → Run Task → Preflight → 30** in the HTTPS timeout picker (choices **5 / 15 / 30**, default **5**). If readiness passes and setup is approved, choose **30** in the named module task or **User-run setup** too; only if opting into the legacy bundle/confirmed Finish setup choose **30** there as well. The selection is passed through the dispatcher and bootstrap to its own child Preflight; a separate successful 30-second Preflight is not cached and does not change a later default-5 setup. Setup preview shows its selected context without network requests; no Test/Run task gets this picker.

Direct equivalent user-operated commands:

```powershell
.\scripts\preflight.ps1 -HttpsTimeoutSeconds 30
# Human or specifically approved Workstation setup workflow; native confirmation:
.\scripts\bootstrap.ps1 -Module Python -Apply -HttpsTimeoutSeconds 30 -Confirm
# Optional legacy finish ONLY after successful base/reboot/resume:
.\scripts\bootstrap.ps1 -LegacyMicrosoftBundle -Apply -SkipBase -HttpsTimeoutSeconds 30 -Confirm
```

`HttpsTimeoutSeconds` accepts **1–30** and affects only HTTPS readiness requests, not installer download/health/configuration timeouts or proxy/TLS policy. Three attempts across six hosts plus backoff allow **93 seconds of HTTPS budget at 5**, **273 at 15**, **543 at 30**; child Preflight additionally has a fixed 120-second platform allowance, giving bounded outer budgets **213 / 393 / 663 seconds**. Actual HTTP/DNS implementation timing may reach that outer timeout; a slow option can take about 11 minutes before a full six-host failure, not wait forever. Denials/certificate errors still stop without retry, and failed checks still gate setup.

A read-only operator observation of the same official README HEAD request returned HTTP 200 in **21.74 seconds** with a 30-second timeout after exhausting default-5 attempts. That demonstrates a usable slower setting for that observation, not that every failure is latency or all artifacts/enterprise sources are permitted. See [diagnostics](TROUBLESHOOTING.md#intermittent-https-preflight-failures).

Optionally choose **Verify** (`.\scripts\verify.ps1`) to inventory existing tools. Before setup, missing/wrong Python, Java, Go, runtime or extensions deliberately produce **exit 1**. This is an expected inventory failure, **not installation failure** and not the Preflight gate. Do not require all Verify checks to pass before installing their outputs.

| Laptop state | Automated route |
| --- | --- |
| Fresh or partial, including a stopped/cancelled Microsoft base | Phase 2 preview then independently chosen installed-first modules; keep installed software/settings and downloaded files |
| Earlier Microsoft bundle confirmed successful, including reboot/resume | Prefer modules for missing targets; **Finish setup** is a separately chosen LEGACY broad add-on only |
| Entire profile already verified | Skip Phase 2; continue with Phase 3 verification then Phase 4 |

## Phase 2: automated laptop setup

**Normal setup is modular, not the Microsoft preset.** Review `.config\setup-packages.json` and `scripts\_setup.psm1`, choose **Setup preview** and one module, then its named install task only after approval. **User-run setup** is an alternative one-module selector, never an all-in-one bundle. No-module `bootstrap.ps1` is a nonmutating Core preview; applying requires `-Apply`:

```powershell
.\scripts\bootstrap.ps1 -Module Python
.\scripts\bootstrap.ps1 -Module Python -Apply -WhatIf
# Human or specifically approved Workstation setup workflow after review/approval:
.\scripts\bootstrap.ps1 -Module Python -Apply -Confirm
```

**Ordering guarantee:** every target's installation is locally checked before any installer/payload download, source/provider activity or installer invocation. Existing compatible software shows its version/location and **SKIP download/install/upgrade**. Existing incompatible or unverified registered software is retained and fails readiness without downloads; inventory access/version errors are **unknown**, not “missing”. All targets in a module are inventoried before its first installer, then each missing target is checked again after approval. Only proven missing targets get individual WinGet/CLI/DISM actions; no broad configuration is applied first. No source/provider restore, automatic upgrade or installer-cache cleanup occurs.

Discovery checks local uninstall registration, Python registration/Store packages, known executable locations and read-only version probes, including compatible SDKs installed off PATH. A stale VS Code terminal with an old Python first on PATH or no `pwsh` does not authorize redownloading a discovered installation. Unregistered portable/custom installations outside these supported locations cannot be guessed: tell IT their actual locations before approving “missing”; do not infer installation from cached payloads or Store/bootstrap aliases. Selection is command-local, never a persistent PATH/JAVA_HOME/profile rewrite.

| Module / exact task | Targets, only if locally missing |
| --- | --- |
| **Install core tools** / Core | Git, VS Code, gh, Copilot CLI, uv, PowerShell 7, Node LTS, Azure CLI, azd, kubectl. No fonts, PowerToys, NVM, Explorer/taskbar/profile or global Copilot tweaks |
| **Install Python SDK** / Python | Python 3.14, separately retryable |
| **Install Java SDK** / Java | Microsoft OpenJDK 25, separately retryable |
| **Install Go SDK** / Go | Go, separately retryable; missing-target install is pinned to the sample's `go.mod` version (1.27.3), not an accidental newer release |
| **Install extensions (approved source)** / Extensions | Full default: missing members of the 12 required set. Explicit `-NativeDemo`: only five language/debugger targets. Both require existing CLI/default-profile source approval |
| **Install WSL components** / WSL | Read-only runtime/features/distro inventory first; only disabled features or absent runtime. Approved Administrator terminal needed for feature inventory/actions |
| **Install Ubuntu (optional)** / Ubuntu | Explicit distro opt-in after WSL/features/restart ready. Existing package/distro skips download; no reset/unregister/default changes or automatic launch |
| **Install Docker Desktop (licensed optional)** / Docker | Separately licensed approved opt-in; existing Docker skips install, no fallback after wslc denial |
| **Install modernization (optional approved source)** / Modernization | Java 11 and only the optional 13th extension; legacy stays excluded from All tests/CI |

Run modules sequentially; each can be retried independently **only after any previous installer is confirmed stopped/completed**. No module claims full workstation verification. Normal setup does not restore project dependencies, launch services/containers, authenticate or deploy. WSL preserves all distributions/data and skips runtime updates when installed; an old WSL lacking `wslc` requires a separate IT-approved upgrade decision. DISM uses `/NoRestart`; a required/pending restart pauses the module before additional downloads. Save work and restart yourself, then preview again. Ubuntu requires installed WSL and enabled features, never a hidden prerequisite install.

VS Code shows per-target streamed installer lines and elapsed progress, followed by actual exit/module results. Per missing target wait is **7200 seconds (2 hours) default**, selectable **3600 / 7200 / 14400**, direct `InstallTimeoutSeconds` range **300–14400**. HTTPS readiness timeout remains separate and is performed after local inventory, only if an approved missing install is needed. Timeout is a failure with unknown vendor/elevated-child state, not permission to retry; only its own launcher may be stopped, never unrelated processes. `.showcase-setup\module-*.jsonl` records non-secret state/elapsed events, not raw installer output; preview/WhatIf writes nothing. Existing downloaded files are retained and are not treated as proof of installation.

### Optional legacy Microsoft bundle

**Legacy Microsoft bundle (optional)** explicitly opts into the signed standard bundle and broad add-on preserved in `legacy-bootstrap.ps1`. **This is NOT the installed-first path**: upstream may download before detecting existing packages and apply Windows/profile/fonts/settings. Review its source separately; no module invokes its internal phase files or modifies the signed Microsoft tree. `.config\configuration.winget` and `.config\java-modernization.winget` are retained **legacy opt-in artifacts**, not normal module installers.

Only this legacy task has the base wait picker **7200 / 14400 default / 28800 seconds (2 / 4 / 8 hours)**. The wait includes large downloads, retries, UAC/manual/final-keypress pauses; it remains bounded and independent from module/HTTPS budgets. Signature, policy, confirmations and reboot/timeout guards are retained. **Finish setup** is legacy-only, unused by the normal module journey, and requires confirmed successful base plus reboot/resume; a stopped partial base is not complete.

For a future new approved setup, after confirming no earlier base is active:

```powershell
.\scripts\bootstrap.ps1 -LegacyMicrosoftBundle -Apply -HttpsTimeoutSeconds 30 -BaseSetupTimeoutSeconds 28800 -Confirm
```

**A launcher timeout is not an installer/UAC failure.** The watchdog stops only its own child launcher; elevated Microsoft setup may still be running. Timeout reports the selected wait and unknown elevated-base state, fails closed, and never starts the add-on/Verify or retries. Initial UAC informational text is not treated as the cause. Keep an existing base running and follow its safe progress/completion evidence in `%ProgramData%\CalmOS\devconfig-log.txt`; do not kill it, start a second setup, update its working clone or use SkipBase to escape the timeout. **Finish setup is safe only after the base and every required reboot/resume are confirmed complete**, using a fresh terminal. If completion/failure is uncertain, stop for human/IT diagnosis rather than rerunning automatically. See [watchdog recovery](TROUBLESHOOTING.md#microsoft-base-launcher-timeout).

Microsoft base prints a final **“Calm OS setup complete”** summary with flagged steps, or separately reports **“stopped early”** on genuine failure. It then closes its transcript/releases its setup lock and waits for a final keypress before exiting. **A live elevated PID can therefore mean installation, completed setup awaiting dismissal, or a failed run awaiting dismissal.** Review the existing window's final summary and flagged steps, respond to its final keypress prompt, and confirm actual successful completion plus reboot/resume before **Finish setup**. Neither PID presence, a released lock nor log activity alone proves readiness; a stopped-early/flagged failure needs diagnosis, not automatic SkipBase.

| Automated layer | What it supplies / changes |
| --- | --- |
| Normal module setup | Individual missing targets only, locally inventoried before downloading; no Microsoft preset or broad configuration |
| Optional Microsoft **standard** base | Broad upstream tools/settings; may redownload existing tools and elevate/restart; separately reviewed [base definition](https://github.com/microsoft/WindowsDeveloperConfig) |
| Extension automation | Normal Extensions module checks `code --list-extensions --show-versions` before installing only missing IDs, never uses `--force` |
| Optional only | 13th Java modernization extension and Java 11 opt-in; Docker Desktop commented out, separately licensed/approved, never default |

The **12 required extension IDs**, checked individually and only missing members installed by Extensions, are:

| Support | Extension ID |
| --- | --- |
| Python | `ms-python.python` |
| Java pack | `vscjava.vscode-java-pack` |
| Go | `golang.go` |
| Azure resources | `ms-azuretools.vscode-azureresourcegroups` |
| Azure Copilot | `ms-azuretools.vscode-azure-github-copilot` |
| Bicep | `ms-azuretools.vscode-bicep` |
| Containers | `ms-azuretools.vscode-containers` |
| Dev Containers | `ms-vscode-remote.remote-containers` |
| WSL | `ms-vscode-remote.remote-wsl` |
| GitHub PRs | `GitHub.vscode-pull-request-github` |
| PowerShell | `ms-vscode.powershell` |
| YAML | `redhat.vscode-yaml` |

`vscjava.migrate-java-to-azure` is the **optional 13th**, only with modernization opt-in. Extension packs can bring bundled dependencies; IT must approve those too. Recommendations do not install extensions by themselves.

Normal modules preserve existing versions/settings; incompatible versions are not automatically replaced. Newly installed vendor packages can require elevation/first-use changes; do not promise exact UAC counts or universal compatibility. Module success is not the later manifest-defined development toolchain acceptance.

Only if you deliberately selected the optional legacy bundle, save work before its possible restart. Wait for `WindowsDevConfigResume` and confirmed successful base completion, then in a new terminal:

```powershell
.\scripts\bootstrap.ps1 -LegacyMicrosoftBundle -Apply -SkipBase -Confirm
```

**Finish setup** explicitly selects that legacy broad add-on. `-SkipBase` without `-LegacyMicrosoftBundle -Apply` is rejected. Do not use it for a cancelled/stopped partial installation. The normal modular path has no “finish base” step.

### Extension source and profile acceptance

Normal Extensions uses the existing CLI/default profile, inventories versions first, skips existing IDs and invokes installation only for missing IDs without `--force`. The named approved-source task passes `ExtensionSourceApproved`, an explicit human/IT attestation, **not** proof or a source override. Neither this flag nor CLI exit 0 proves the active window's profile/source/enabled state. IT must establish compatible delivery before using it. The retained legacy [DSC resource](https://github.com/microsoft/winget-dsc/blob/main/resources/Help/Microsoft.VSCode.Dsc/VSCodeExtension.md) has no target profile or marketplace parameter; this historical limitation is not repaired by bypassing policy.

Before apply, IT must approve the selected CLI installation/user context, all 12 IDs and bundled dependencies, and verify its effective [AllowedExtensions/private marketplace policy](https://code.visualstudio.com/docs/enterprise/extensions). A private-marketplace banner alone is not proof any ID is blocked. Conversely, CLI exit 0 does not prove approved source or enabled state. Do not assume another process inherits the window's authentication/profile. If the active profile is not the current CLI default, arrange IT-approved managed automated delivery, not a new profile or public-source workaround.

If the approved enterprise profile/source cannot be honored by this resource, **stop: setup is not accepted**. IT must provide a compatible managed automated extension-delivery route (approved image/bootstrap distribution or audited configuration), not ask developers to install the missing IDs one by one or switch to the public marketplace. Do not override marketplace/allowlist policy, switch accounts/installs to evade it, or download unapproved VSIX files. This repository does not silently implement such a fallback.

## Phase 3: post-setup verification

After the selected modules/any user restart, open a **fresh terminal**, then choose **Verify**. If VS Code was open during installation, a new terminal or Reload Window can still inherit its old process environment: save work, fully exit VS Code and reopen it from Windows when appropriate. Known-path discovery itself never changes global PATH/settings.

```powershell
.\scripts\verify.ps1
```

Now required FAIL/exit 1 means setup is **not accepted**: diagnose installation/configuration logs, PATH/version selection, reboot/resume and approved extension source/profile. Do not treat an old Python first on PATH as proof Python 3.14 was not installed; compare executable locations with IT, without deleting other runtimes.

Default **full** verification requires **12 extensions**. In the intended VS Code window, also confirm its profile, enabled required extensions, approved source and enterprise sign-in. The [CLI reference](https://code.visualstudio.com/docs/configure/command-line) documents read-only `code --list-extensions --show-versions --profile "Your approved existing profile"`; use the actual existing approved profile, not a newly invented profile. Compare this with Verify's unqualified CLI list. Policy-disabled installed extensions are not accepted.

### Native demo selection

The existing Extensions module can explicitly select only
`ms-python.python`, `ms-python.debugpy`, `redhat.java`,
`vscjava.vscode-java-debug` and `golang.go`, as required by the native
`debugpy`/`java`/`go` launch configurations. Python Debugger bundles debugpy;
Java language support is a debugger dependency. Approved bundled dependencies
use the same marketplace route and human/IT approval. The full twelve-extension
module and optional modernization profile are unchanged.

```powershell
.\scripts\developer.ps1 -Action SetupPreview -SetupModule Extensions -NativeDemo
# Only after scope and existing CLI/source/profile routing are human/IT approved:
.\scripts\developer.ps1 -Action Setup -SetupModule Extensions -NativeDemo -ExtensionSourceApproved -Confirm
.\scripts\preflight.ps1 -NativeDemo -Json
.\scripts\verify.ps1 -NativeDemo -Json
```

Compatible installed IDs/versions are retained; malformed/duplicate/unknown
inventory stops before sources/downloads. Native selection cannot be used with
another module or the legacy bundle. Native PASS checks prerequisites only,
not intended-profile enablement, source approval, helper availability or live F5.
Go Delve/helper acquisition requires a separate approved Restore before
debugging; missing helpers mean **F5 NOT RUN**, never a hidden download.

Java modernization remains optional:

```powershell
.\scripts\bootstrap.ps1 -Module Modernization -Apply -ExtensionSourceApproved -Confirm
.\scripts\verify.ps1 -IncludeJavaModernization
```

This does not select Java 11 for legacy tests. `verify.ps1 -Json` returns readiness results. `-RunConfigTest` is a separately approved **legacy configuration test**, not the normal modular acceptance path; it can restore test providers/modules and is not an agent or daily-test action.

Read configuration in the editor before choosing to apply it. `winget configure show -f .config\configuration.winget` inspects the profile; test/apply and any repairs remain separate, user-approved actions. The upstream full setup/uninstall changes more machine state and is not a shortcut for this quickstart.

### Before / after acceptance

| Evidence | Before setup | After setup |
| --- | --- | --- |
| Phase 0 approvals and script policy | Required before scripts | Still required; no bypass |
| Preflight | No FAIL; WSL/wslc WARN expected if absent | Recheck infrastructure failures; no claimed payload/enterprise certification |
| Verify | Optional inventory exit 1 expected for missing selected outputs | Native: all 18 PASS/exit 0 plus human profile/source acceptance. Full: separately all 33 PASS/exit 0; Native never changes full FAIL |
| Project dependencies | Not supplied by laptop setup | Explicit Phase 4 Restore before daily checks |
| GitHub / AKS | Access/governance decisions separate | CI checked; deployment independently manual, not automatically provisioned |

## Phase 4: project restore and daily checks

### Restore project packages

Tool installation is not project dependency restoration. After setup/verification, explicitly choose the Restore task or run:

```powershell
.\scripts\developer.ps1 -Action Restore -Sample All
```

This **user task can access approved package sources** and materialize locked Python dependencies, the manifest-defined Maven wrapper/plugins/dependencies, and the pinned Pester/PSScriptAnalyzer modules in `.tools\powershell`. Go uses the installed manifest-defined toolchain and standard library; no automatic replacement toolchain is allowed. Repeat only after dependency changes or a documented missing-package result.

Restore is not part of a test/coverage/lint action, not an agent task and not an instruction to install a missing language runtime. Check errors and proxy policies; never work around a denied source. For the optional legacy exercise select `-Sample Legacy` after independently confirming Java 11. `All` never includes legacy.

For an explicitly approved **local container image build**, choose
**Restore project dependencies → ContainerImages** (not the default Dependencies
target), or run:

```powershell
.\scripts\developer.ps1 -Action Restore -RestoreTarget ContainerImages -Sample Python -Runtime Auto -Confirm
```

Choose Python/Java/Go/All/Legacy and an approved runtime explicitly. `All` images
includes only the three modern applications, not PowerShell or Legacy.
This confirmed Restore target is the **only local image-build/acquisition step**;
it can download approved base images and build packages. It is not hidden in
Run, Test, Lint, Coverage or F5.

### Daily test, lint and coverage

Use **Terminal → Run Task** for the named test/lint/coverage actions or run:

```powershell
.\scripts\developer.ps1 -Action Test -Sample All
.\scripts\developer.ps1 -Action Lint -Sample All
.\scripts\developer.ps1 -Action Coverage -Sample All
```

Use `-Sample Python`, `Java`, `Go` or `PowerShell` for focused work. Daily actions require existing runtimes/restored packages and must not download or restore. Missing prerequisites mean **NOT RUN**, not passed. An offline switch alone does not prove that a tool cannot restore cached packages.

| Sample / tooling | Daily checks | Reports relative to sample root (PowerShell: repo root) |
| --- | --- | --- |
| Python: pytest + pytest-cov, Ruff | Unit/API/rounding tests, coverage; Ruff lint | `test-results.xml`, `coverage.xml`, `htmlcov\index.html` |
| Current Java: JUnit 5 + JaCoCo, Checkstyle | Maven verification and coverage; configured Maven Checkstyle rules | `target\surefire-reports\`, `target\site\jacoco\index.html`, `target\site\jacoco\jacoco.xml` |
| Go: built-in test/coverage + vet | `go test ./...`, `go vet ./...`, coverage; formatting check | `test-results.json`, `coverage.out`, `coverage.html` |
| PowerShell: Pester **5.7.1** + PSScriptAnalyzer **1.24.0** | Mock/AST tests and analyzer for scripts; never execute setup/repair | `artifacts\pester.xml` |

Coverage actions generate reports; the table is not a claim that every report is generated by Test alone. JUnit/coverage reports are CI artifacts, not proof of production readiness. Coverage is not a substitute for invalid-input, health, logging and rounding assertions. Inspect task output for the exact checks performed; a compile check is not an unconfigured third-party linter.

In the **Testing** Activity Bar, the Python extension, Java Test Runner (part of the Java pack) and Go extension support test discovery/run/debug after their interpreters/JDK/toolchain are configured. Select the locked Python `.venv` interpreter and the correct Java 25 JDK. Extensions can prompt to download helper tools: do not accept automatically; follow the approved setup/restore route. The PowerShell extension provides language/debug support; use the Pester task for reproducible PowerShell tests. Open generated HTML reports from Explorer; use integrated-terminal output and CI artifacts for XML/JSON evidence.

For **Run and Debug → F5**, select the intended sample configuration. The pinned
Python `.venv`, correct JDK and (for Go debugging) approved Delve must already
exist. F5 does not restore packages or install debugger helpers.

### Task picker names

Use these exact entries in **Terminal → Run Task**:

| Stage | Task labels |
| --- | --- |
| Fresh-device setup | **Preflight**, **Setup preview**, **User-run setup**, **Finish setup**, **Verify** |
| Explicit package restore | **Restore project dependencies**, or **Restore Python/Java/Go/PowerShell** |
| Daily checks | **Test all samples**, **Coverage all samples**, **Lint all samples**; focused **Test/Coverage/Lint Python/Java/Go/PowerShell** |
| Optional legacy | **Test legacy Java (Java 11 opt-in)** |
| User launch | **Run EMI API**, **Run IFSC service**, **Run FX rates**, each with **(local)** or **(container)** |
| GitHub / Azure | **GitHub workflow status**, **Deploy AKS (manual main only)** |
| Kubernetes | **Kubernetes manifest check**, **Kubernetes status**, **Kubernetes logs**, **Kubernetes port-forward** |
| Confirmed recovery | **Reset demo**; preview first and fetch safe `origin/main` yourself, as in the demo runbook |

Grouped names above describe the matching picker entries, not a single task
with slashes. Only setup/restore tasks may acquire approved dependencies;
launch/dispatch remains a separate explicit user action.

Sample READMEs retain direct commands for the named sample directory. Developer actions route to those directories; do not execute a sample's build from the repository root.

## Phase 5: run, debug and containers

The developer launches services directly, or through the separately approved
**Workstation setup** local launch stage. The manual **Terminal → Run Task**
fallback is:

```powershell
.\scripts\developer.ps1 -Action RunLocal -Sample Python
# Or, using the existing image from explicit ContainerImages restoration:
.\scripts\developer.ps1 -Action RunContainer -Sample Python
```

For the first EMI request, choose **Terminal → Run Task → Run EMI API (local)** and confirm the launch after restoring packages. Keep its terminal open, choose **Terminal → New Terminal → PowerShell** (or the **+** button), then paste:

```powershell
Invoke-RestMethod http://localhost:8080/health
$loan = @{ principal = '2500000'; annual_rate_percent = '8.5'; tenure_months = 240 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8080/emi -ContentType 'application/json' -Body $loan
```

Expect health `status: ok` and EMI `"21695.58"` (display `"₹21,695.58"`). Use **Ctrl+C** in the task terminal to stop it. No Docker or Azure setup is required for this local request.

Choose Java/Go similarly; their sample READMEs contain the synthetic requests. For an explicit launcher port:

```powershell
.\scripts\run-sample.ps1 -Name python-emi-api -Mode local -Port 8080
```

The shared launcher accepts **`-Runtime Auto|wslc|docker`**. `Auto` is the default:
`wslc` first, `docker` **only when `wslc` is absent**. An explicit selection
probes **only that approved runtime** and never falls back after failure/denial:

```powershell
# Explicitly approved runtime, not a policy workaround:
.\scripts\run-sample.ps1 -Name python-emi-api -Mode container -Runtime wslc -Port 8080
```

A failing or policy-blocked automatic selection must stop rather than switch.
Docker Desktop remains a **commented optional** configuration choice: IT must
review its licence/subscription terms before anyone enables it. It is not
installed by default. On an approved Docker-standard device, review removal of
the workspace `dev.containers.dockerPath: wslc` override and explicitly choose
`-Runtime docker`; approval is not inferred from a WSL denial.

RunContainer first inspects the existing local image and runs with
**`--pull=never`**; a missing image means **NOT RUN**. It never builds/pulls or
restores packages. Choose the separate confirmed ContainerImages Restore target
beforehand; agents do not build/run merely because a task exists.

## Phase 6: GitHub and CI

Basic clone/fetch/push authentication is **built into VS Code**, not dependent on Copilot. PRs/issues use the official [GitHub Pull Requests and Issues](https://marketplace.visualstudio.com/items?itemName=GitHub.vscode-pull-request-github) extension, ID **`GitHub.vscode-pull-request-github`**, included in automated extension setup.

1. Open the **GitHub** Activity Bar view → **Sign In**. Follow the organisation-approved browser sign-in and return to VS Code. Copilot's **Use AI Features** sign-in/seat is separate from repository write access.
2. Confirm the approved Git commit identity. If absent, configure it yourself in the integrated terminal using your organisation's values; never put tokens/customer identities in source.
3. Select the branch in the Status Bar → **Create new branch**, starting from reviewed `main`.
4. Make a small change, run focused checks, inspect the Source Control diff, stage intended files and **Commit** with a conventional message.
5. Select **Publish Branch** (or push/sync an existing branch). Without repository write access, use an approved fork; sign-in does not grant write permissions.
6. **Ctrl+Shift+P → GitHub Pull Requests: Create Pull Request**. Check the base, preserve the PR template, include observed commands/results/skips and request reviewers.
7. Inspect PR checks/diffs. **GitHub workflow status** uses an already authenticated approved GitHub CLI; missing CLI/auth is reported, not repaired by agents. Merge only with required approvals and passing checks.

The [official VS Code walkthrough](https://code.visualstudio.com/docs/sourcecontrol/github) documents this flow. CI checks modern services/PowerShell/configuration and builds modern containers; legacy is excluded. A push or PR **never deploys** to Azure.

## Phase 7: existing AKS

[GITHUB-AKS.md](GITHUB-AKS.md) describes IT-owned prerequisites and the separate manual deployment. Use the Kubernetes check/status/logs/port-forward tasks only in the documented context. Static checks do not authenticate or provision; live checks require a previously approved user context and network path. Dispatch is explicit, main-only, and requires the current main `source_sha` plus a different environment reviewer.

## Cleanup after work is finished

**Wait until laptop setup/reboot/resume has finished and stop local app, test and Restore tasks. Do not update this working clone or run cleanup while setup is running.** Later, use **Terminal -> Run Task -> Cleanup preview**. **Cleanup generated resources** requires explicit `-Apply` and per-target confirmation. Nothing runs automatically.

```powershell
# HUMAN, later: nonmutating plan
.\scripts\cleanup.ps1
# HUMAN, after reviewing the plan and stopping tasks
.\scripts\cleanup.ps1 -Apply -Confirm
# Optional exact owned containers, never images/volumes/networks
.\scripts\cleanup.ps1 -IncludeContainers
.\scripts\cleanup.ps1 -Apply -IncludeContainers -Confirm
```

Future developer tasks record only newly absent, exact report files they create: Python JUnit/coverage reports, Go JSON/coverage reports, PowerShell NUnit/coverage reports and the current Java JaCoCo data/XML. The ignored `.showcase-owned.json` is bound to this checkout's Git-local hash anchor and random workspace ID. Existing reports are never adopted; files changed or replaced after recording are retained. Repeated checks that overwrite reports may therefore make them ineligible. Missing historical ownership is an expected WARN, not permission to delete by filename. User notes and all unknown files remain, even inside output directories; empty directories remain too.

This conservative version **does not remove `.venv`, `.tools`, `target`/HTML/cache trees or local restored packages**, even if a developer task created them. It does not recursively inventory a directory and assume everything inside belongs to the showcase. Unknown ownership is retained rather than guessed. Do not modify, move or delete the receipt/anchor to authorize cleanup. Corruption, copied checkout metadata, tracked files, nested repositories, reparse/hardlink targets, busy files or an active developer-operation lock fail closed. Stop the task holding a lock normally; never kill shared processes or delete locks to force progress. The receipt/hash mechanism protects against accidental edits, not a privileged user deliberately rewriting both records.

Container cleanup is separately opt-in: only future Run tasks' recorded immutable ID, exact name, workspace labels and original `wslc`/Docker runtime may match. Historical generic showcase labels, another clone's containers and named replacements are not adopted. Runtime denial is a failure, not a Docker fallback. No images, volumes, networks or build cache are pruned.

**Always retained:** GitHub Copilot/GHCP and its settings/accounts, Git/gh/VS Code/extensions, Python/Java/Go/PowerShell/SDKs, WSL distributions/data, Docker Desktop, Azure tools, policies/proxy/registry/PATH, Git configuration/credentials, global/user package caches, all source and uncommitted files, bootstrap/base logs/resume tasks outside this checkout, and all GitHub/AKS/ACR/Azure resources. Cleanup is not an undo of workstation setup. **Reset demo** is a different, explicitly destructive exercise operation that restores sample changes; cleanup never invokes it. Shared-tool uninstallation cannot be promised harmless and is not provided here.

## Troubleshooting and logs

Use only the explicit human/IT-approved Phase 0 policy route; never change policy or run repairs automatically to make a check pass. Use Phase 2 for incomplete laptop setup, Phase 4 for missing project packages, and [Troubleshooting](TROUBLESHOOTING.md) for post-setup failures.

Base log: `%ProgramData%\CalmOS\devconfig-log.txt`. Add-on logs: `%LOCALAPPDATA%\win11-dev-workstation\bootstrap-*.log`. Redact identities, sensitive paths and secrets before sharing. Verification proves only what its observed output reports for that user/device/revision.
