# Windows 11 developer workstation showcase

A VS Code-first developer workflow for synthetic Python EMI, Java IFSC and Go FX services: set up once, restore project packages explicitly, test locally, review on GitHub, then optionally deploy to **your existing AKS cluster and ACR**.

> Community showcase, not an official Microsoft product. The workstation base is [Microsoft Windows Developer Config](https://github.com/microsoft/WindowsDeveloperConfig). This is not a production banking system.

## Start in VS Code

Use the organisation-approved VS Code installation. Choose **Source Control → Clone Repository** (or **Ctrl+Shift+P → Git: Clone**), enter:

```text
https://github.com/hrshl-demo/win11-dev-workstation-showcase
```

Open the cloned folder. Review its source before accepting Workspace Trust. All commands below run in **Terminal → New Terminal → PowerShell** at the repository root; no separate terminal is needed. Browser sign-in, UAC and restart prompts are the unavoidable external interactions.

| Your laptop | What to do |
| --- | --- |
| **Fresh, IT-approved laptop** | IT first supplies approved VS Code and Git. Read [Setup once](docs/SETUP.md#setup-once-fresh-approved-laptop), run read-only preflight, review setup, then personally run bootstrap. After any restart, reopen VS Code and finish the add-on. Agents never install or change policy. |
| **Already configured laptop** | Skip bootstrap. Run `.\scripts\verify.ps1`. Resolve missing prerequisites with IT; do not reinstall everything. |

Then follow these separate stages:

1. **Restore project packages** — choose **Terminal → Run Task → Restore project dependencies** and its default **Dependencies** target, or explicitly run `.\scripts\developer.ps1 -Action Restore -Sample All` once, and again after dependency changes. The same task's separately confirmed **ContainerImages** target builds local images only when explicitly selected. Restore can download approved packages/base images; it is not workstation setup or permission for an agent to restore.
2. **Daily test, lint, coverage** — choose **Terminal → Run Task → Test all samples / Lint all samples / Coverage all samples**, or the integrated terminal:

   ```powershell
   .\scripts\developer.ps1 -Action Test -Sample All
   .\scripts\developer.ps1 -Action Lint -Sample All
   .\scripts\developer.ps1 -Action Coverage -Sample All
   ```

   Daily commands do not install missing prerequisites. `All` excludes the intentionally legacy Java exercise. See [tools and reports](docs/SETUP.md#daily-test-lint-and-coverage).
3. **GitHub workflow** — sign in from the GitHub view, create a branch from the Status Bar, stage and commit in Source Control, **Publish Branch**, then **GitHub Pull Requests: Create Pull Request**. Inspect CI checks before merging. See [the walkthrough](docs/SETUP.md#github-workflow).
4. **Run a sample** — choose the local/container task only when you personally want to start it. Run never restores packages or builds/pulls images; container Run requires an existing local image and uses `--pull=never`. Automatic runtime selection uses `wslc` first and `docker` **only if `wslc` is absent**. The shared launcher also accepts an explicitly approved `-Runtime wslc` or `-Runtime docker`, probes only that runtime and never falls back after denial. Do not use selection to bypass policy. Docker Desktop remains a commented, optional licensing choice, not the default.
5. **Existing AKS + ACR** — [review the GitHub/AKS plan](docs/GITHUB-AKS.md). Deployment is a separate, human-dispatched, main-only workflow with independent environment approval. No push or PR deploys, and no cluster/registry provisioning.

## Included integrations

| Area | Included |
| --- | --- |
| Workstation | Signed Microsoft base, required WinGet add-on, read-only readiness and verification |
| VS Code | Python, Java, Go and PowerShell support; testing/debugging, tasks and source control |
| GitHub | Built-in Git authentication; official `GitHub.vscode-pull-request-github` extension for PRs/issues; CI with test/coverage artifacts |
| Unit testing / lint | pytest + pytest-cov and Ruff; JUnit 5 + JaCoCo and Checkstyle; Go built-in tests/coverage + vet; Pester 5.7.1 + PSScriptAnalyzer 1.24.0 |
| Azure | OIDC identities, immutable ACR images and namespace-scoped deployment to an existing AKS cluster; ClusterIP services and user port-forward |
| Copilot customization | Bank standards, onboarding agent, EMI extension, container review, preparation-only AKS and standards review skills |

The required profile has **12 extensions**, with an optional 13th for Java modernization. IDs are recorded in `.vscode\extensions.json`; recommendations are not enterprise policy. Runtime/dependency pins belong in manifests and configurations.

## Documentation

- [VS Code setup, packages, daily work and GitHub](docs/SETUP.md)
- [Existing AKS deployment and approval prerequisites](docs/GITHUB-AKS.md)
- [15-minute demo and safe fallback](docs/DEMO-SCRIPT.md)
- [Architecture and lifecycle](docs/ARCHITECTURE.md)
- [IT prerequisites](docs/IT-PREREQUISITES.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Windows versus macOS](docs/WINDOWS-VS-MAC.md)
- [Samples](samples/) · [Agent boundaries](AGENTS.md) · [Security](SECURITY.md) · [MIT licence](LICENSE)

The historical `demo-baseline` tag includes intentionally unsafe Go demonstration code and is **not deployable**. Revised `main` is the safe baseline; review the prepared `demo-complete` schedule fallback before use. Recorded validation is revision-specific evidence, never a claim that this machine, CI or Azure deployment has passed.
