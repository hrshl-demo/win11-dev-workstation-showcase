# End-to-end VS Code setup

Follow **Phase 0 prerequisites → Phase 1 preflight → Phase 2 automated laptop setup → Phase 3 verification → Phase 4 project restore and checks → Phase 5 run/debug → Phase 6 GitHub CI → Phase 7 existing AKS**. Humans approve/run setup; agents explain and inspect, never install or change policy. Missing languages/extensions on a fresh or partially configured device belong to automated setup, not individual manual installation.

## Phase 0: prerequisites before repository scripts

Complete this checklist **before running any repository script**, including Preflight:

| Human / IT prerequisite | Acceptance criterion |
| --- | --- |
| Supported Windows 11 | Serviced Windows 11 release, build 22621+; approved device image |
| Elevation and changes | Permission for administrator/UAC, Windows/WSL changes, reboot and package licences; save work |
| Hardware and storage | Approved virtualization/nested virtualization enabled; at least 15 GB free for the base, plus SDK/cache/image budget |
| App Installer / WinGet | Registered for the signed-in developer, executable and configuration capability allowed; not SYSTEM |
| Network / proxy / trust | Approved WinHTTP and WinGet proxy, payload/module/image endpoints and TLS/AuthentiCode validation paths |
| Minimum clone tools | Approved Git and VS Code available **before cloning**; repository access and permission to trust reviewed source |
| Script execution | Effective policy permits reviewed repository scripts/modules; see the inline checks below |
| Extension delivery | Approved marketplace, extension allowlist, target VS Code installation/account/profile and licences; see [extension acceptance](#extension-source-and-profile-acceptance) |

Python 3.14, Java 25, Go, WSL/wslc and the 12 required extensions are **setup outputs**, not things you must manually install first. See [IT prerequisites](IT-PREREQUISITES.md) for approvals outside this repository's checks.

This VS Code-first route genuinely requires Git/VS Code first. IT can supply an approved image or software distribution for that minimum; the later add-on also declares Git/VS Code but cannot install them before you have cloned it. If they are absent, use the [official Microsoft base entrypoint guidance](https://github.com/microsoft/WindowsDeveloperConfig) through IT first, reviewing source/signatures/changes and its resume instructions. That base-only alternative is not this add-on and is not permission to paste an unchecked download-and-execute command.

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

## Phase 1: preflight and optional inventory

Choose **Terminal → Run Task → Preflight**, or:

```powershell
.\scripts\preflight.ps1
```

**Gate:** no Preflight FAIL and exit 0, plus Phase 0 approvals. WARN is advisory: missing WSL/wslc is expected before setup and does not block the Microsoft base. A policy, disk, virtualization, WinGet or endpoint FAIL must be resolved before bootstrap; a PASS does not certify every enterprise control or payload source.

HTTPS results include URI/status/attempts, the actual timeout and safe failure categories. Default timeout remains **5 seconds per attempt**; classified transient timeout/DNS/connect failures get at most three attempts with 250 ms backoff. HTTP denial and certificate failures do not retry. Root 404/405 means reachability only, not artifact access; redirects are not followed. If exhausted, bootstrap stops before setup and reports the failed checks—do not keep retrying full setup blindly or Restore dependencies to unblock the network.

### Explicit slow-network choice

If a permitted endpoint responds too slowly, choose **Terminal → Run Task → Preflight → 30** in the HTTPS timeout picker (choices **5 / 15 / 30**, default **5**). If readiness passes and setup is approved, choose **User-run setup → 30** too; select **30 again** for **Finish setup** after base resume if needed. The selection is passed through the dispatcher and bootstrap to its own child Preflight; a separate successful 30-second Preflight is not cached and does not change a later default-5 setup. Setup preview also shows the chosen context; no Test/Run task gets this picker.

Direct equivalent user-operated commands:

```powershell
.\scripts\preflight.ps1 -HttpsTimeoutSeconds 30
# HUMAN ONLY after readiness/approvals; not executed by an agent:
.\scripts\bootstrap.ps1 -HttpsTimeoutSeconds 30
# Only after the Microsoft base is confirmed complete/resumed:
.\scripts\bootstrap.ps1 -SkipBase -HttpsTimeoutSeconds 30
```

`HttpsTimeoutSeconds` accepts **1–30** and affects only HTTPS readiness requests, not installer download/health/configuration timeouts or proxy/TLS policy. Three attempts across six hosts plus backoff allow **93 seconds of HTTPS budget at 5**, **273 at 15**, **543 at 30**; child Preflight additionally has a fixed 120-second platform allowance, giving bounded outer budgets **213 / 393 / 663 seconds**. Actual HTTP/DNS implementation timing may reach that outer timeout; a slow option can take about 11 minutes before a full six-host failure, not wait forever. Denials/certificate errors still stop without retry, and failed checks still gate setup.

A read-only operator observation of the same official README HEAD request returned HTTP 200 in **21.74 seconds** with a 30-second timeout after exhausting default-5 attempts. That demonstrates a usable slower setting for that observation, not that every failure is latency or all artifacts/enterprise sources are permitted. See [diagnostics](TROUBLESHOOTING.md#intermittent-https-preflight-failures).

Optionally choose **Verify** (`.\scripts\verify.ps1`) to inventory existing tools. Before setup, missing/wrong Python, Java, Go, runtime or extensions deliberately produce **exit 1**. This is an expected inventory failure, **not installation failure** and not the Preflight gate. Do not require all Verify checks to pass before installing their outputs.

| Laptop state | Automated route |
| --- | --- |
| Fresh or partial; Microsoft base absent/incomplete, including WSL missing | Phase 2 full **User-run setup** (standard base + add-on) after Phase 0/1 |
| Microsoft standard base confirmed complete; only add-on packages/extensions missing | Phase 2 **Finish setup** (`-SkipBase`) after Phase 0/1 |
| Entire profile already verified | Skip Phase 2; continue with Phase 3 verification then Phase 4 |

## Phase 2: automated laptop setup

Review `.config\configuration.winget` and the Microsoft standard base. Choose exact task **Setup preview**, then **User-run setup** only after approval, or:

```powershell
.\scripts\bootstrap.ps1 -WhatIf
# Only after reviewing the preview and obtaining IT approval:
.\scripts\bootstrap.ps1
```

Preview describes the plan; it does not install or prove sources will work. Full bootstrap reruns Preflight, validates the downloaded Microsoft wrapper's Authenticode signature before execution, and asks consent before base/configuration changes. Invalid/unverifiable signatures stop setup. Agents never execute preview or setup.

### Microsoft base launcher wait and slow full setup

The **Setup preview** and **User-run setup** tasks also offer a separate base-only wait picker: **7200 = 2 hours**, **14400 = 4 hours (default)**, **28800 = 8 hours** for slow full provisioning. This is independent of the HTTPS picker. Four hours replaces the old one-hour watchdog because large downloads, retries, UAC, package installation and reboot preparation can exceed an hour; eight hours is an explicit bounded slow-network option, not a guarantee setup will finish. **Finish setup** does not run the base and therefore has no base-wait picker. Direct bootstrap/developer calls accept `-BaseSetupTimeoutSeconds` in **7200–28800**, default **14400**; preview shows the value, and full setup passes it to the signed base launcher. HTTPS Preflight, installer-wrapper download (60 seconds), add-on configuration (3600 seconds), health checks and final Verify (600 seconds) retain their own budgets.

For a future new approved setup, after confirming no earlier base is active:

```powershell
.\scripts\bootstrap.ps1 -HttpsTimeoutSeconds 30 -BaseSetupTimeoutSeconds 28800
```

**A launcher timeout is not an installer/UAC failure.** The watchdog stops only its own child launcher; elevated Microsoft setup may still be running. Timeout reports the selected wait and unknown elevated-base state, fails closed, and never starts the add-on/Verify or retries. Initial UAC informational text is not treated as the cause. Keep an existing base running and follow its safe progress/completion evidence in `%ProgramData%\CalmOS\devconfig-log.txt`; do not kill it, start a second setup, update its working clone or use SkipBase to escape the timeout. **Finish setup is safe only after the base and every required reboot/resume are confirmed complete**, using a fresh terminal. If completion/failure is uncertain, stop for human/IT diagnosis rather than rerunning automatically. See [watchdog recovery](TROUBLESHOOTING.md#microsoft-base-launcher-timeout).

| Automated layer | What it supplies / changes |
| --- | --- |
| Microsoft **standard** base | Upstream developer tools/settings, PowerShell, uv, Node and WSL; may elevate/restart. Review the current [base definition](https://github.com/microsoft/WindowsDeveloperConfig); full setup/uninstall is not selected |
| Required add-on | VS Code, Git, GitHub CLI/Copilot CLI, Python 3.14, Microsoft OpenJDK 25, Go, Azure CLI, azd, kubectl; updates WSL if wslc is absent |
| Extension automation | 12 `Microsoft.VSCode.Dsc/VSCodeExtension` resources in `.config\configuration.winget`; no twelve separate install clicks |
| Optional only | 13th Java modernization extension and Java 11 opt-in; Docker Desktop commented out, separately licensed/approved, never default |

The **12 required extension IDs**, installed as a set by the add-on, are:

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

Existing tools are evaluated by their resource tests; setup may install/update packages and Windows settings, not remove everything and start over. Do not promise exact UAC counts, unchanged machine settings, or perfect no-change idempotence. WinGet source/version selection and the later manifest-defined development toolchain checks must both pass.

Save work first. The Microsoft base may elevate and restart. Sign back in and wait for `WindowsDevConfigResume` to finish **the base only**. Reopen this folder in VS Code and a new integrated terminal:

```powershell
.\scripts\bootstrap.ps1 -SkipBase
```

Use task **Finish setup** after that base resume. `-SkipBase` is valid **only when the base is already complete or after its resume**, not a fix for an absent/incomplete base or missing WSL. If no restart occurred, bootstrap can already have completed the add-on; proceed to verification. Complete any first-use Ubuntu prompts through the approved VS Code WSL workflow.

### Extension source and profile acceptance

The [official DSC implementation](https://github.com/microsoft/winget-dsc/blob/main/resources/Microsoft.VSCode.Dsc/Microsoft.VSCode.Dsc.psm1) locates an installed VS Code CLI and invokes extension installation. Its [resource contract](https://github.com/microsoft/winget-dsc/blob/main/resources/Help/Microsoft.VSCode.Dsc/VSCodeExtension.md) exposes no target profile or marketplace parameter; this add-on does not pass `--profile`. The repository verifier likewise lists CLI extensions without `--profile`. These are **not proof of the active window's profile, enabled extensions or enterprise marketplace routing**.

Before apply, IT must approve the selected CLI installation/user context, all 12 IDs and bundled dependencies, and verify its effective [AllowedExtensions/private marketplace policy](https://code.visualstudio.com/docs/enterprise/extensions). A private-marketplace banner alone is not proof any ID is blocked. Conversely, a CLI exit 0 does not prove the extension went through that approved source or is enabled in your window. Do not assume the DSC process inherits the window's authentication/profile. The module uses `--force` for version changes; that is not authorization to bypass enterprise policy.

If the approved enterprise profile/source cannot be honored by this resource, **stop: setup is not accepted**. IT must provide a compatible managed automated extension-delivery route (approved image/bootstrap distribution or audited configuration), not ask developers to install the missing IDs one by one or switch to the public marketplace. Do not override marketplace/allowlist policy, switch accounts/installs to evade it, or download unapproved VSIX files. This repository does not silently implement such a fallback.

## Phase 3: post-setup verification

After base/add-on completion, open a **fresh terminal** (reload VS Code if its inherited PATH is stale), then choose **Verify**:

```powershell
.\scripts\verify.ps1
```

Now required FAIL/exit 1 means setup is **not accepted**: diagnose installation/configuration logs, PATH/version selection, reboot/resume and approved extension source/profile. Do not treat an old Python first on PATH as proof Python 3.14 was not installed; compare executable locations with IT, without deleting other runtimes.

Default verification requires **12 extensions**. In the intended VS Code window, also confirm its profile, enabled required extensions, approved source and enterprise sign-in. The [CLI reference](https://code.visualstudio.com/docs/configure/command-line) documents read-only `code --list-extensions --show-versions --profile "Your approved existing profile"`; use the actual existing approved profile, not a newly invented profile. Compare this with Verify's unqualified CLI list. Policy-disabled installed extensions are not accepted.

Java modernization remains optional:

```powershell
.\scripts\bootstrap.ps1 -SkipBase -IncludeJavaModernization
.\scripts\verify.ps1 -IncludeJavaModernization
```

This does not select Java 11 for legacy tests. `verify.ps1 -Json` returns readiness results. After setup, the human may explicitly approve `.\scripts\verify.ps1 -RunConfigTest` to test the applied configuration; it can require modules/network, so it is not a daily test or agent action. Combine with `-IncludeJavaModernization` only when opted in; inspect actual exit/result rather than assuming success.

Read configuration in the editor before choosing to apply it. `winget configure show -f .config\configuration.winget` inspects the profile; test/apply and any repairs remain separate, user-approved actions. The upstream full setup/uninstall changes more machine state and is not a shortcut for this quickstart.

### Before / after acceptance

| Evidence | Before setup | After setup |
| --- | --- | --- |
| Phase 0 approvals and script policy | Required before scripts | Still required; no bypass |
| Preflight | No FAIL; WSL/wslc WARN expected if absent | Recheck infrastructure failures; no claimed payload/enterprise certification |
| Verify | Optional inventory exit 1 expected for missing setup outputs | Required profile exit 0; CLI/profile/source/enabled checks also accepted |
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

Only the developer launches services, from **Terminal → Run Task** or:

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
