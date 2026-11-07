# Architecture

## Layers and ownership

| Layer | Purpose | Owner / boundary |
| --- | --- | --- |
| Windows 11 | Device, virtualization, user context and package infrastructure | IT selects image, policies and servicing |
| Microsoft Windows Developer Config | Signed, resumable standard workstation base | Upstream Microsoft project; separate trust and release lifecycle |
| `.config\configuration.winget` | Required tool/extension add-on, OS assertion, WSL container readiness resource | Repository-reviewed declarative state; schema 0.2 |
| `.config\java-modernization.winget` | Legacy JDK and modernization extension | Opt-in only with `-IncludeJavaModernization` |
| `scripts\` | Preflight, orchestration, verification, guided repair, sample launch, guarded reset | Explicit commands, exit status and confirmation |
| `.vscode\` | Recommendations, tasks, launch settings and container-path preference | Editor convenience, not enterprise policy |
| `.github\` and `AGENTS.md` | Instructions, custom agent, skills, CI and review guidance | Harness discovery and task permission still apply |
| `samples\` | Synthetic-data Python, Java and Go services plus legacy exercise | Manifest-defined runtimes, tested behaviour and sample-scoped recovery |
| Governance | Intune, Defender, Entra identity, GitHub Copilot policy | IT/security managed; not installed or configured by the add-on |

The required configuration has **12 required extensions**; `.vscode\extensions.json` recommends **13**, including optional modernization. Verification must distinguish recommendations from requirements. Current language/runtime pins belong in manifests/configurations.

## Setup execution and restart

1. `preflight.ps1` reports readiness without installing or changing policy.
2. `bootstrap.ps1` verifies the Microsoft standard wrapper's Authenticode signature before expression execution.
3. The upstream base can elevate and restart; its `WindowsDevConfigResume` task resumes **only the base**.
4. A human runs `bootstrap.ps1 -SkipBase` after the base finishes to apply the add-on and verify. `-IncludeJavaModernization` also applies the optional configuration.
5. `verify.ps1` checks tools/extensions; `-RunConfigTest` invokes WinGet test logic, and `-Json` emits structured output.

The base log and add-on log are separate; see [Setup](SETUP.md). Bootstrap does not sign in to GitHub/Azure, run sample services, start containers or deploy infrastructure.

## Financial and service boundaries

The main services expose `/health` and listen on their sample-defined port, with launcher `-Port` controlling the requested host/local port. `run-sample.ps1 -Name python-emi-api|java-ifsc-service|go-fx-rates -Mode local|container -Port` selects one service; container mode prefers `wslc` then an installed `docker` and reports the choice. A successful health probe is readiness, not full functional validation.

Monetary input/calculation uses decimal or exact arithmetic, explicit half-up rounding and **fixed two-decimal strings in JSON**. INR presentation uses lakh grouping. Baseline EMI totals multiply the rounded EMI by tenure. The schedule exercise preserves EMI, applies a one-time principal prepayment after the chosen installment, shortens tenure and settles the final installment exactly; it is not a change to the existing EMI contract.

## Prepared Azure fallback

On `demo-complete`, repository-root `azure.yaml` targets `samples\python-emi-api` as an azd Container Apps service. Root `infra\main.bicep` declares subscription-scoped infrastructure using published AVM modules pinned in that file; `infra\main.parameters.json` maps these required azd environment values:

| azd value | Bicep parameter | Required input |
| --- | --- | --- |
| `AZURE_ENV_NAME` | `environmentName` | Approved environment name |
| `AZURE_LOCATION` | `location` | IT-approved Azure region |
| `EMI_CONTAINER_IMAGE` | `containerImage` | Actual, already-published EMI application image, preferably digest-qualified; no placeholder/default |

**Seed the image first, under a separately approved provisioning plan.** The template declares a new registry and application together, but does not seed/import/publish an image. A new registry is empty; an existing image elsewhere does not automatically appear there. Resolve registry provisioning and image-seeding order, the AVM `imageName` format and managed-identity pull access before the first app deployment. Preparation performs none of those operations.

The intended hosting design is external HTTPS ingress to port 8080, zero to one replica, a user-assigned managed identity and AVM-managed `AcrPull`. Key Vault uses RBAC, purge protection and disabled public network access; the identity is assigned **Key Vault Secrets User**. The application needs no secrets, and the vault is intentionally empty and sealed: no private endpoint/network path is provisioned here. IT must approve private connectivity before any future secret use; role assignment alone does not establish working secret retrieval.

Declared outputs cover resource group, registry endpoint/name, Container Apps environment ID, Log Analytics workspace ID, vault name/URI, identity client ID and `API_URL`. These are template declarations, not observed deployed values.

Validation performed for this fallback is limited to static JSON/YAML/reference checks. No Bicep compiler was available: compilation, deployment and live launch tests are **NOT RUN**. A separately authorised user with their own compiler can later run from the repository root:

```powershell
bicep build .\infra\main.bicep
```

This may restore AVM modules. Agents must not install missing tooling, restore modules or run that compilation under the current no-download boundary. Static checks do not prove compilation, deployment, image availability or effective access.

## Pull request → CI → tagged release → adoption

1. Submit a small pull request with tests, configuration rationale, security implications and actual validation evidence.
2. CI covers the main Python/Java/Go samples, PowerShell lint/mock checks and configuration validation. The intentionally legacy Java exercise is excluded from the normal matrix; record separate validation when its JDK is available.
3. Review passing checks and limitations before creating a tagged release. Do not claim a release/tag or green CI until observed.
4. Developers review release changes and rerun bootstrap, choosing `-SkipBase` for add-on-only reconciliation. Re-verify and record results under the target user's policies.

Desired-state configuration and upstream setup are **designed for re-running**, not immutable snapshots: packages may update and a resource can fail or be blocked. Successful verification is required after reconciliation. Repair is conditional, confirmed intervention; it is not unconditional idempotent setup.

**Do not extend the idempotency claim to launches or resets.** Sample launch starts a process/container and can conflict with ports/names; reset discards sample changes after confirmation. Neither is part of bootstrap.

## Demo assets and recovery

Release/demo preparation supplies an immutable `demo-baseline` tag and a `demo-complete` branch holding the schedule, preparation-only Azure files and Go review exercise. Confirm refs and contents before presenting; bootstrap does not create them. Root `azure.yaml` and `infra\` are deliberate fallback assets outside the sample-reset scope: `demo-reset.ps1` neither restores nor removes them and can refuse reset while unrelated root changes are present. Recovery protects unrelated work and stops/removes only known demo containers. Use the [demo recovery procedure](DEMO-SCRIPT.md#recovery-without-losing-unrelated-work), never repository-wide destructive cleanup or changes to the baseline tag.

For upstream behaviour and signed/source separation, consult [Windows Developer Config](https://github.com/microsoft/WindowsDeveloperConfig). For governance constraints, consult [IT prerequisites](IT-PREREQUISITES.md).
