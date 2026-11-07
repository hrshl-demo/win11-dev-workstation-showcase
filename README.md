# Windows 11 developer workstation showcase

A VS Code-first developer workflow for synthetic Python EMI, Java IFSC and Go FX services: set up once, restore project packages explicitly, test locally, review on GitHub, then optionally deploy to **your existing AKS cluster and ACR**.

> Community showcase, not an official Microsoft product. Normal setup uses installed-first modules; the broad [Microsoft Windows Developer Config](https://github.com/microsoft/WindowsDeveloperConfig) bundle is optional legacy opt-in. This is not a production banking system.

## End-to-end journey: Phase 0 through Phase 7

**Start with [Phase 0 prerequisites](docs/SETUP.md#phase-0-prerequisites-before-repository-scripts), before executing any script.** IT/humans supply supported Windows, virtualization/disk, elevation/licensing, App Installer/WinGet, network/proxy, repository access, approved Git/VS Code to clone, script execution and extension-source approvals. Python/Java/Go/WSL and extensions are automated setup outputs, not a manual shopping list.

In the integrated PowerShell terminal, the inline prerequisite checks work even when scripts are blocked:

```powershell
Get-ExecutionPolicy -List
Get-ExecutionPolicy
```

Effective Restricted can occur with all scopes Undefined. The guide documents a **human-only, IT-permitted** CurrentUser RemoteSigned route for default restriction, its persistence and the AllSigned/Group Policy stop conditions. No agent or setup script changes policy; no Bypass or blanket unblocking.

After those prerequisites, choose **Source Control → Clone Repository** (or **Ctrl+Shift+P → Git: Clone**) in approved VS Code:

```text
https://github.com/hrshl-demo/win11-dev-workstation-showcase
```

Open the cloned folder. Review its source before accepting Workspace Trust. All commands below run in **Terminal → New Terminal → PowerShell** at the repository root; no separate terminal is needed. Browser sign-in, UAC and restart prompts are the unavoidable external interactions.

| Phase | Exact task / acceptance |
| --- | --- |
| **0 — Prerequisites** | [Human/IT checklist and inline policy checks](docs/SETUP.md#phase-0-prerequisites-before-repository-scripts); Git/VS Code required before clone |
| **1 — Preflight** | **Preflight**: no FAIL, exit 0. WSL/wslc WARN is expected before setup. Optional **Verify** inventory may deliberately exit 1 for missing setup outputs |
| **2 — Modular laptop setup** | **Setup preview** → one module, then **Install core tools**, **Install Python SDK**, **Install Java SDK**, **Install Go SDK**, **Install extensions (approved source)** and **Install WSL components** as needed. **User-run setup** is a one-module selector, not a bundle |
| **3 — Verify setup** | Fresh terminal and **Verify** after modules/restart; full profile acceptance is separate. **Finish setup** is LEGACY-only after confirmed successful optional bundle/reboot/resume, never for a stopped partial base |
| **4 — Restore and test** | Explicit **Restore project dependencies** → **Dependencies**, then **Test all samples**, **Lint all samples**, **Coverage all samples**. `All` excludes legacy; daily checks do not restore |
| **5 — Run/debug/containers** | **Run EMI API (local)**, first request below; F5 needs existing debugger prerequisites. Container Run needs explicitly prepared images, uses `--pull=never` |
| **6 — GitHub / CI** | Source Control branch/commit/**Publish Branch**, GitHub PR/checks, **GitHub workflow status** |
| **7 — Existing AKS** | [Human/IT variables, OIDC/RBAC/network and independent approval](docs/GITHUB-AKS.md), then separately chosen **Deploy AKS (manual main only)**; no push/PR deployment or provisioning |

**Partial/stopped setup:** keep installed software/settings and downloaded files. Modules locally check installations **before downloading anything for that target**; compatible installed tools show version/location and skip download/reinstall/upgrade. Incompatible or unknown inventory stops without download—never silently replacing the older version. A stale terminal/PATH miss alone does not cause a second download of a discoverable SDK. Fully verified devices skip installs, not verification.

**Live modular progress:** per-target output, elapsed wait and exit results; only missing targets are eligible. Default/no-module bootstrap is a nonmutating Core preview. Normal setup excludes fonts/PowerToys/NVM/Explorer/taskbar/profile/global Copilot tweaks. **Legacy Microsoft bundle (optional)** is explicitly different and can redownload/tweak shared settings; it is not needed to recover a cancelled partial run. WSL and optional **Install Ubuntu (optional)** preserve existing distro data, never reset or automatically reboot.

**Enterprise extension delivery:** automation uses VS Code DSC/CLI, which does not select the active window's profile or expose a marketplace parameter. Before apply, IT must verify approved CLI/account/profile/source compatibility and all required IDs; after apply verify they are enabled in the intended window. A private-marketplace banner alone proves neither a block nor automation compatibility. Unsupported routing is a setup acceptance failure requiring a compatible **managed automated delivery** route, not manual installation of each missing extension or a public-marketplace bypass. See [source/profile acceptance](docs/SETUP.md#extension-source-and-profile-acceptance).

The default runtime remains `wslc`, Docker only if absent; explicit approved selection never bypasses denial. Docker Desktop stays commented, optional and licence-reviewed. Full laptop provisioning is separate from the 15-minute coding demo; CI is not fresh-device acceptance.

## Your first request

After the explicit package restore above, choose **Terminal → Run Task → Run EMI API (local)** and confirm the launch. Keep that task terminal open. Choose **Terminal → New Terminal** (or **+**) for a second integrated PowerShell terminal, then paste:

```powershell
Invoke-RestMethod http://localhost:8080/health
$loan = @{ principal = '2500000'; annual_rate_percent = '8.5'; tenure_months = 240 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8080/emi -ContentType 'application/json' -Body $loan
```

Expect health `status: ok` and EMI `"21695.58"` (display `"₹21,695.58"`). Stop the server with **Ctrl+C** in its task terminal. This local first request needs no Docker or Azure configuration.

## Included integrations

| Area | Included |
| --- | --- |
| Workstation | Independently confirmed installed-first modules, live progress, read-only inventory/Verify; signed broad Microsoft bundle retained as optional legacy |
| VS Code | Python, Java, Go and PowerShell support; testing/debugging, tasks and source control |
| GitHub | Built-in Git authentication; official `GitHub.vscode-pull-request-github` extension for PRs/issues; CI with test/coverage artifacts |
| Unit testing / lint | pytest + pytest-cov and Ruff; JUnit 5 + JaCoCo and Checkstyle; Go built-in tests/coverage + vet; Pester 5.7.1 + PSScriptAnalyzer 1.24.0 |
| Azure | OIDC identities, immutable ACR images and namespace-scoped deployment to an existing AKS cluster; ClusterIP services and user port-forward |
| Copilot customization | Bank standards, onboarding agent, EMI extension, container review, preparation-only AKS and standards review skills |

The required profile has **12 extensions**, with an optional 13th for Java modernization. IDs are recorded in `.vscode\extensions.json`; recommendations are not enterprise policy. Runtime/dependency pins belong in manifests and configurations.

## Documentation

**Cleanup later, not during installation:** [scoped cleanup](docs/SETUP.md#cleanup-after-work-is-finished) previews and removes only newly recorded, unchanged checkout outputs and optionally exact owned containers. It is **not** a laptop uninstaller or demo reset. GitHub Copilot/GHCP, shared tools, extensions, environments, caches, source and cloud resources remain untouched.

- [VS Code setup, packages, daily work and GitHub](docs/SETUP.md)
- [Existing AKS deployment and approval prerequisites](docs/GITHUB-AKS.md)
- [15-minute demo and safe fallback](docs/DEMO-SCRIPT.md)
- [Architecture and lifecycle](docs/ARCHITECTURE.md)
- [IT prerequisites](docs/IT-PREREQUISITES.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Windows versus macOS](docs/WINDOWS-VS-MAC.md)
- [Samples](samples/) · [Agent boundaries](AGENTS.md) · [Security](SECURITY.md) · [MIT licence](LICENSE)

The historical `demo-baseline` tag includes intentionally unsafe Go demonstration code and is **not deployable**. Revised `main` is the safe baseline; review the prepared `demo-complete` schedule fallback before use. Recorded validation is revision-specific evidence, never a claim that this machine, CI or Azure deployment has passed.
