# Repository agent rules

## Boundaries

- Read the applicable `.github` instructions and sample README before editing. Keep changes task-scoped, customer-neutral and based on synthetic data.
- **Never execute setup or repair:** Microsoft setup/uninstall one-liners, `bootstrap.ps1`, `repair-winget.ps1`, package installation/configuration apply, WSL installation/update, policy changes, elevation or restart. This prohibition includes invoking setup/repair with `-WhatIf`; inspect source and mocks instead.
- Read-only `preflight.ps1` and `verify.ps1` are allowed. `verify.ps1 -RunConfigTest` requires an explicit request because it invokes WinGet configuration tests.
- Verification switches are `-IncludeJavaModernization`, `-RunConfigTest` and `-Json`. The default extension profile requires 12; modernization requires the optional 13th. `-RunConfigTest` tests the required configuration and also the modernization configuration when both switches are selected. `-Json` emits the results array; no switch installs tools or selects Java 11 for legacy tests.
- Do not start apps or containers, authenticate to Azure, deploy, publish, reset samples, create tags/branches or commit unless the task explicitly authorises that action. Approval to edit files is not approval to execute generated infrastructure.
- Azure preparation must keep the application image as a required environment-backed parameter, without a placeholder or unrelated demo-service default. Report unset inputs; do not build/publish an image or launch Azure merely to complete preparation.
- Do not work around IT policy or install missing tools. Do not download or restore dependencies, toolchains, modules or portable tools, including implicit downloads by test/build commands or configuration tests. A project-local location such as `.tools\` does not make installation or restoration permissible. Use only already available tools and dependencies; mark an absent prerequisite and its affected command **NOT RUN**.
- Do not override execution policy in a child shell or the current process without explicit prior approval. Leaving machine/user policy unchanged is not authorization for a process-only override. If policy prevents execution, report the check **NOT RUN** and use permitted static inspection instead.

## Build and test

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

The **exact two Go baseline exceptions listed in step 5 of [the demo script](docs/DEMO-SCRIPT.md)** apply only to the documented baseline code in `samples\go-fx-rates`. Preserve them during unrelated work; fix them with regression tests when that review exercise or an explicit remediation is requested. Do not introduce, duplicate or extend those exceptions to other code, inputs or environments. All other standards continue to apply. These are scoped, documented demo exceptions, not general unsafe permission.
