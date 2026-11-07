# VS Code quickstart

Keep five activities separate: **setup once → restore project packages → daily checks → GitHub review → approved existing-AKS deployment**. These are human-operated instructions, not agent permissions.

## Open the repository

IT supplies approved VS Code and Git on a fresh laptop. In VS Code use **Source Control → Clone Repository**, or **Ctrl+Shift+P → Git: Clone**, with:

```text
https://github.com/hrshl-demo/win11-dev-workstation-showcase
```

Select an approved local folder and open the clone. Read the source before granting Workspace Trust. Use **Terminal → New Terminal**, select **PowerShell**, and keep the repository root as the working directory. **Terminal → Run Task** exposes the same developer actions without leaving the editor. Open a second integrated terminal with the **+** button when a server/port-forward occupies the first.

No outside terminal is required. GitHub/Entra browser authentication, Windows UAC and reboot are OS/service interactions, not terminal work.

## Setup once: fresh approved laptop

Before proceeding, IT approves Windows 11 build 22621+, virtualization, App Installer/WinGet, administrator elevation, package licences, script execution and network/proxy access. Budget about 15 GB for the Microsoft base plus SDKs, caches and images. See [IT prerequisites](IT-PREREQUISITES.md).

An effective Restricted policy blocks repository scripts; AllSigned requires trusted signatures for scripts/modules. Obtain an IT-approved execution context. **Do not use `ExecutionPolicy Bypass`, change process policy or disable signature checks.** Microsoft's signature on its wrapper does not sign this repository.

In the VS Code integrated PowerShell terminal:

```powershell
.\scripts\preflight.ps1
.\scripts\bootstrap.ps1 -WhatIf
# Only after reviewing the preview and obtaining IT approval:
.\scripts\bootstrap.ps1
```

Preflight is read-only. Bootstrap validates the standard Microsoft wrapper's Authenticode signature before execution; invalid/unverifiable signatures stop setup. Only the human operator runs preview/setup, never an agent.

Save work first. The Microsoft base may elevate and restart. Sign back in and wait for `WindowsDevConfigResume` to finish **the base only**. Reopen this folder in VS Code and a new integrated terminal:

```powershell
.\scripts\bootstrap.ps1 -SkipBase
.\scripts\verify.ps1
```

If no restart occurred, bootstrap can already have completed the add-on; verification still matters. Complete any first-use Ubuntu prompts through the approved VS Code WSL workflow. Do not rerun base setup to solve a package/test failure.

Default verification requires 12 extensions. Java modernization is optional:

```powershell
.\scripts\bootstrap.ps1 -SkipBase -IncludeJavaModernization
.\scripts\verify.ps1 -IncludeJavaModernization
```

This does not select Java 11 for legacy tests. `verify.ps1 -Json` returns readiness results; `-RunConfigTest` invokes WinGet configuration test logic and may need modules/network. Run that switch only when explicitly approved, not as a daily test or from the onboarding agent.

Read configuration in the editor before choosing to apply it. `winget configure show -f .config\configuration.winget` inspects the profile; test/apply and any repairs remain separate, user-approved actions. The upstream full setup/uninstall changes more machine state and is not a shortcut for this quickstart.

## Already configured laptop

**Skip setup.** Open the clone in VS Code and run:

```powershell
.\scripts\verify.ps1
```

Use **Extensions → Show Recommended Extensions** to review workspace recommendations. Approve installations yourself under IT policy; the required profile and optional modernization recommendation are distinct. A missing runtime/module is a prerequisite to resolve, not permission for an agent to download it.

## Restore project packages

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

## Daily test, lint and coverage

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

## GitHub workflow

Basic clone/fetch/push authentication is **built into VS Code**, not dependent on Copilot. PRs/issues use the official [GitHub Pull Requests and Issues](https://marketplace.visualstudio.com/items?itemName=GitHub.vscode-pull-request-github) extension, ID **`GitHub.vscode-pull-request-github`**, already in the required recommendations.

1. Open the **GitHub** Activity Bar view → **Sign In**. Follow the organisation-approved browser sign-in and return to VS Code. Copilot's **Use AI Features** sign-in/seat is separate from repository write access.
2. Confirm the approved Git commit identity. If it is absent, configure it yourself through the integrated terminal using your organisation's documented values; do not put customer identities or tokens in source.
3. Select the branch in the Status Bar → **Create new branch**, starting from current reviewed `main`.
4. Make a small change. Run focused checks, inspect the Source Control diff, stage only intended files, and **Commit** with a conventional message.
5. Select **Publish Branch** (or push/sync an already published branch). If you have no repository write access, use an approved fork; sign-in does not grant write permissions. Protect unrelated local work.
6. **Ctrl+Shift+P → GitHub Pull Requests: Create Pull Request**. Verify base repo/branch, preserve the supplied PR template, include exact commands and observed results/skips, and request reviewers. The extension can publish the branch when prompted.
7. Inspect PR checks and diffs in the GitHub view. The workflow status task (`developer.ps1 -Action WorkflowStatus`) uses an already authenticated approved GitHub CLI from the integrated terminal; missing CLI/authentication is reported, not repaired by agents. Merge only with repository approvals and passing required checks.

The [official VS Code walkthrough](https://code.visualstudio.com/docs/sourcecontrol/github) documents this flow. GitHub Actions CI checks modern services and PowerShell/configuration changes; legacy is intentionally excluded. A PR or push **never deploys** to Azure.

## Run locally or in a container

Only the developer launches services, from **Terminal → Run Task** or:

```powershell
.\scripts\developer.ps1 -Action RunLocal -Sample Python
# Or, using the existing image from explicit ContainerImages restoration:
.\scripts\developer.ps1 -Action RunContainer -Sample Python
```

Choose Java/Go similarly. Use the sample README for synthetic HTTP requests in a second integrated terminal. For an explicit launcher port:

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

## Existing AKS

[GITHUB-AKS.md](GITHUB-AKS.md) describes IT-owned prerequisites and the separate manual deployment. Use the Kubernetes check/status/logs/port-forward tasks only in the documented context. Static checks do not authenticate or provision; live checks require a previously approved user context and network path. Dispatch is explicit, main-only, and requires the current main `source_sha` plus a different environment reviewer.

## Support and logs

Do not change execution policy, run repairs or reinstall the workstation to get past a failed check. See [Troubleshooting](TROUBLESHOOTING.md); route policy and licensing decisions to IT.

Base log: `%ProgramData%\CalmOS\devconfig-log.txt`. Add-on logs: `%LOCALAPPDATA%\win11-dev-workstation\bootstrap-*.log`. Redact identities, sensitive paths and secrets before sharing. Verification proves only what its observed output reports for that user/device/revision.
