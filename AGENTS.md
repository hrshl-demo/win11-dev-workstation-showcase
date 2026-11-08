# Repository agent rules

## Boundaries

- Read the applicable `.github` instructions and sample README before editing. Keep changes task-scoped, customer-neutral and based on synthetic data.
- **Default: never execute setup or repair:** Microsoft setup/uninstall one-liners, `bootstrap.ps1`, `repair-winget.ps1`, package installation/configuration apply, WSL installation/update, policy changes, elevation or restart. This prohibition includes invoking setup/repair with `-WhatIf`; inspect source and mocks instead. Only the [human-invoked VS Code exception](#human-invoked-vs-code-exception) below permits selected local workflow actions, never repair or policy/elevation/restart.
- Read-only `preflight.ps1` and `verify.ps1` are allowed. `verify.ps1 -RunConfigTest` requires an explicit request because it invokes WinGet configuration tests.
- Verification switches are `-IncludeJavaModernization`, `-RunConfigTest` and `-Json`. The default extension profile requires 12; modernization requires the optional 13th. `-RunConfigTest` tests the required configuration and also the modernization configuration when both switches are selected. `-Json` emits the results array; no switch installs tools or selects Java 11 for legacy tests.
- Explain the [Phase 0–7 journey](docs/SETUP.md): normal setup is independently confirmed installed-first Core/SDK/Extensions/WSL modules, not a Microsoft preset. Every target is locally inventoried before any download/source/provider/installer activity; installed versions/settings retained, incompatible/unknown stops without downloads. Stopped partial setup is not completed base or rollback. Except for the named human-invoked workflow below, do not run module preview/apply or installation helpers; use safe fixtures/AST. Signed Microsoft bundle is legacy opt-in only; SkipBase/Finish require confirmed successful legacy base/reboot/resume. ExtensionSourceApproved is human/IT attestation of existing CLI/default-profile routing, never a source bypass. No automatic upgrades, global tweaks, distro reset or restart.
- Do not start apps or containers except through the named human-invoked workflow below. Never authenticate to Azure or deploy as an agent. Git publication, sample reset, tags/branches and commits require explicit task authorization, never inferred from file edits or the local setup exception. Approval to edit files is not approval to execute generated infrastructure.
- Azure preparation targets an existing AKS cluster and ACR only. Keep application images as required inputs, with no placeholder or unrelated demo-service default; deployment uses same-run immutable image digests. Report unset inputs. Never authenticate, provision, build/publish images or dispatch deployment merely to complete preparation.
- Do not work around IT policy. Except for separately approved catalog installations and explicit Restore in the named human-invoked workflow below, do not install missing tools or download/restore dependencies, toolchains, modules or portable tools, including implicit downloads by test/build commands or configuration tests. A project-local location such as `.tools\` does not make installation or restoration permissible. All coding/build/desktop agents use only already available tools and dependencies; mark an absent prerequisite and its affected command **NOT RUN**.
- Do not override execution policy in a child shell or the current process without explicit prior approval. Leaving machine/user policy unchanged is not authorization for a process-only override. If policy prevents execution, report the check **NOT RUN** and use permitted static inspection instead.

## Human-invoked VS Code exception

Only a human selecting **Workstation setup** from `.github\agents\workstation-setup.agent.md` in a **locally running VS Code Windows chat**, on a reviewed checkout, may invoke the existing installed-first SetupPreview/Setup, explicit Dependencies Restore, daily checks and separately approved local startup/request surfaces. The human must approve actual installation/download/launch scopes; `start` or agent selection is not that approval. Keep tool approvals and individual native `-Confirm`/ShouldProcess prompts enabled; the human answers them, never the model. If interactive tool/confirmation access is unavailable, stop with the exact blocker.

Inventory actual installed targets before network/provider/source/payload/installer work, retain compatible versions/settings, and stop unknown/incompatible state without downloads. Apply modules sequentially, re-inventory afterwards and on every resume, and stop for unresolved vendor state or pending reboot before any next install. WSL changes, Ubuntu, licensed Docker, Java modernization, PowerShell test-module Restore, image builds and container launches require distinct scopes and approvals; local-demo acceptance is not full-workstation readiness.

This exception **does not apply** to desktop/coordinator, generic coding/build, cloud, remote, unattended or delegated/subagent roles, including agents implementing/testing this workflow. They still never execute real setup/SetupPreview/WhatIf/Restore or launch apps/containers. **Workstation onboarding** remains read-only. No role gains repair, broad legacy bundle/Finish/SkipBase, autoapprove, policy/source/TLS/account/profile changes, automatic upgrade/elevation/reboot, WSL update/reset/unregister, source modification, cleanup/reset, shared-cache deletion, Git publication or cloud execution from this exception. A discovered required runtime may be selected transparently for one process, never globally substituted. Instructions and the tool list are not a command-level security sandbox; existing organization permissions remain authoritative.

## Build and test

VS Code tasks and `scripts\developer.ps1` separate **human-approved Setup/Restore** from daily Test/Lint/Coverage/Run. Except for the named human-invoked workflow, agents must never run Setup, SetupPreview or Restore; FinishSetup is outside that exception too. Local container builds belong only to explicitly confirmed Restore with `-RestoreTarget ContainerImages`; RunContainer requires an existing image and uses `--pull=never`, never build/pull/restoration. Daily checks require installed runtimes and restored dependencies and must prevent downloads/restoration; record missing prerequisites as **NOT RUN**. `All` excludes legacy Java. See [the VS Code quickstart](docs/SETUP.md) for tooling and report paths.

Run commands inside the named sample directory, not the repository root:

| Sample | Windows PowerShell commands |
| --- | --- |
| `samples\python-emi-api` | `uv run pytest` |
| `samples\java-ifsc-service` | `.\mvnw.cmd -B verify` |
| `samples\go-fx-rates` | `go vet ./...`; `go test ./...` |
| `samples\java-legacy-upgrade` | `.\mvnw.cmd -B verify`, with Java 11 selected |

Use manifest-defined versions and wrappers; never silently substitute a different runtime. CI excludes the legacy sample; validate it separately when Java 11 is available. For PowerShell changes, use the repository's mock/AST tests and PSScriptAnalyzer on `scripts\`, without executing state-changing entry points. Report observed results, failures and skips separately.

The commands above and in setup documentation are user-run instructions, not permission to fetch missing prerequisites during repository creation. Before agent execution, confirm the required runtime and dependencies already exist. Use supported modes that prevent both downloads and dependency restoration; offline mode alone may still restore cached packages. Otherwise mark the check **NOT RUN**, without weakening the check or claiming it passed.

## Engineering standards

- Validate input at the edge; mask sensitive data in structured logs and return safe client errors.
- Money uses `Decimal`/`BigDecimal` or exact integer/rational arithmetic, never binary floating point. Serialize monetary JSON as fixed two-decimal strings with explicit `ROUND_HALF_UP` rounding; use Indian lakh grouping for INR display.
- For the EMI schedule exercise, preserve the existing rounded EMI, apply one-time prepayment to outstanding principal after the specified regular payment, shorten tenure, and make the final installment exactly remaining principal plus rounded interest. Never create a negative balance or recompute a lower EMI.
- Add focused tests, keep dependencies pinned in manifests/lockfiles, and prefer Microsoft and established open-source libraries.
- PowerShell must support Windows PowerShell 5.1 and PowerShell 7, use strict mode and approved verbs, and gate state changes with ShouldProcess and appropriate confirmation.
- Preserve unrelated staged, unstaged and untracked work. Never use repository-wide destructive cleanup as a demo shortcut.
- `cleanup.ps1` is a human-operated, default nonmutating ownership plan, never a workstation uninstaller or demo-reset wrapper. Do not execute it against a real checkout. Validate only isolated fixtures/mocks. It may remove only newly recorded exact unchanged file identities/fingerprints and explicitly opted-in immutable workspace-labelled containers. Shared tools/GHCP/extensions, environments/module trees/caches, source, logs outside the checkout and cloud resources are always retained. Missing/ambiguous ownership is not permission to adopt. Wait for setup and app/test/restore tasks to finish before suggesting a user clone update or cleanup.

## Narrow baseline exceptions

`samples\java-legacy-upgrade` is intentionally Java 11 + Spring Boot 2.7. General guidance for the current Java service does **not** apply to that baseline: do not upgrade it by hand or include it in the normal CI matrix. Change it only for an explicitly requested modernization exercise.

There are **no Go serving-code exceptions on revised `main`**. The review exercise is non-serving text in `tests\fixtures\go-review-example.txt`; review it without copying defects into a service. The historical `demo-baseline` tag contains deliberately unsafe query logging/internal-error disclosure and must not be launched or deployed. Use revised `main` as the safe baseline and inspect the schedule fallback on `demo-complete`. See [the demo script](docs/DEMO-SCRIPT.md).

## GitHub and deployment boundaries

GitHub sign-in, branch/commit/publish/PR operations and package restore are separate user decisions. Existing AKS deployment is manual `workflow_dispatch` only from trusted `main`, with exact current `source_sha`, successful modern-service tests, immutable ACR digests and independent `aks-demo` approval. The live approval check must fail closed if protections or their availability cannot be verified. Agents may prepare/review files but never dispatch, authenticate, grant RBAC, create a namespace/cluster/registry, request admin credentials or bypass policy. See [the existing-AKS plan](docs/GITHUB-AKS.md).
