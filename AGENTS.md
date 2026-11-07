# Repository agent rules

## Boundaries

- Read the applicable `.github` instructions and sample README before editing. Keep changes task-scoped, customer-neutral and based on synthetic data.
- **Never execute setup or repair:** Microsoft setup/uninstall one-liners, `bootstrap.ps1`, `repair-winget.ps1`, package installation/configuration apply, WSL installation/update, policy changes, elevation or restart. This prohibition includes invoking setup/repair with `-WhatIf`; inspect source and mocks instead.
- Read-only `preflight.ps1` and `verify.ps1` are allowed. `verify.ps1 -RunConfigTest` requires an explicit request because it invokes WinGet configuration tests.
- Verification switches are `-IncludeJavaModernization`, `-RunConfigTest` and `-Json`. The default extension profile requires 12; modernization requires the optional 13th. `-RunConfigTest` tests the required configuration and also the modernization configuration when both switches are selected. `-Json` emits the results array; no switch installs tools or selects Java 11 for legacy tests.
- Do not start apps or containers, authenticate to Azure, deploy, publish, reset samples, create tags/branches or commit unless the task explicitly authorises that action. Approval to edit files is not approval to execute generated infrastructure.
- Azure preparation targets an existing AKS cluster and ACR only. Keep application images as required inputs, with no placeholder or unrelated demo-service default; deployment uses same-run immutable image digests. Report unset inputs. Never authenticate, provision, build/publish images or dispatch deployment merely to complete preparation.
- Do not work around IT policy or install missing tools. Do not download or restore dependencies, toolchains, modules or portable tools, including implicit downloads by test/build commands or configuration tests. A project-local location such as `.tools\` does not make installation or restoration permissible. Use only already available tools and dependencies; mark an absent prerequisite and its affected command **NOT RUN**.
- Do not override execution policy in a child shell or the current process without explicit prior approval. Leaving machine/user policy unchanged is not authorization for a process-only override. If policy prevents execution, report the check **NOT RUN** and use permitted static inspection instead.

## Build and test

VS Code tasks and `scripts\developer.ps1` separate **human-operated Setup/Restore** from daily Test/Lint/Coverage/Run. Agents must never run Setup, SetupPreview, FinishSetup or Restore. Local container builds belong only to explicitly confirmed Restore with `-RestoreTarget ContainerImages`; RunContainer requires an existing image and uses `--pull=never`, never build/pull/restoration. Daily checks require installed runtimes and restored dependencies and must prevent downloads/restoration; record missing prerequisites as **NOT RUN**. `All` excludes legacy Java. See [the VS Code quickstart](docs/SETUP.md) for tooling and report paths.

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

## Narrow baseline exceptions

`samples\java-legacy-upgrade` is intentionally Java 11 + Spring Boot 2.7. General guidance for the current Java service does **not** apply to that baseline: do not upgrade it by hand or include it in the normal CI matrix. Change it only for an explicitly requested modernization exercise.

There are **no Go serving-code exceptions on revised `main`**. The review exercise is non-serving text in `tests\fixtures\go-review-example.txt`; review it without copying defects into a service. The historical `demo-baseline` tag contains deliberately unsafe query logging/internal-error disclosure and must not be launched or deployed. Use revised `main` as the safe baseline and inspect the schedule fallback on `demo-complete`. See [the demo script](docs/DEMO-SCRIPT.md).

## GitHub and deployment boundaries

GitHub sign-in, branch/commit/publish/PR operations and package restore are separate user decisions. Existing AKS deployment is manual `workflow_dispatch` only from trusted `main`, with exact current `source_sha`, successful modern-service tests, immutable ACR digests and independent `aks-demo` approval. The live approval check must fail closed if protections or their availability cannot be verified. Agents may prepare/review files but never dispatch, authenticate, grant RBAC, create a namespace/cluster/registry, request admin credentials or bypass policy. See [the existing-AKS plan](docs/GITHUB-AKS.md).
