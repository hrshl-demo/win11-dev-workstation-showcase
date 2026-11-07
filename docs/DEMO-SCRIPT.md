# 15-minute demo script

Setup is completed **before** the presentation. Use synthetic data, an approved device and a disposable demo checkout. Each prompt below is the exact text to paste; generated work still requires review. Do not approve setup, installation, elevation, Azure authentication or deployment from agent tool requests.

## Pre-demo checklist

- Sign in to the organisation-approved GitHub account and confirm its assigned Copilot Business/Enterprise seat, Agent mode and applicable policies.
- Confirm network/proxy access, toolchains, required extensions and discovery of instructions, the onboarding agent and four skills in the Agent Customizations editor.
- Rehearse test commands, runtime/image availability, port 8080 and the integrated browser. Use an already approved Docker runtime if WSL containers are unavailable.
- Confirm `demo-baseline` and `demo-complete` exist locally and inspect their contents. They are release/demo preparation assets, not created by setup.
- Preserve all unrelated work. In the disposable checkout, inspect `git status --short`, preview `.\scripts\demo-reset.ps1 -WhatIf`, then run `.\scripts\demo-reset.ps1` only after reviewing and explicitly confirming its sample/container scope. Do not disable its guards.
- Prepare Java 11 and the modernization extension only if step 6 is planned. Check `.\scripts\verify.ps1 -IncludeJavaModernization` separately; this adds the optional extension check, not Java 11 selection or installation. Confirm the legacy JDK independently. Optional tooling must not fail the core-demo readiness gate.
- Keep an inspected `demo-complete` checkout and captured test output ready. Label recorded evidence; never present it as a live result.

## 1. Prove readiness — 00:00–01:30

**Say:** “We review the workstation against the declared configuration; installed tools alone are not proof of enterprise compliance.”

**Do:** Run at the repository root:

```powershell
.\scripts\verify.ps1
winget configure test -f .config\configuration.winget
```

Paste into the **Workstation onboarding** agent:

```text
Read docs/SETUP.md and docs/IT-PREREQUISITES.md. Explain the verification output in plain language and distinguish required items from optional Java modernization. You may run only scripts/preflight.ps1 and scripts/verify.ps1 without RunConfigTest. Do not run setup, repair, package installation, configuration apply, WSL updates, elevation, restart, Azure sign-in or any application launch. If a check fails, explain the human-operated next step without executing it.
```

**Expected result:** A readable tool/extension table and configuration test result. Report any WARN/FAIL accurately; the default extension requirement is 12, not all 13 recommendations.

**Fallback:** Show previously captured, labelled readiness output and the configuration file; explain the current failure and continue from the already verified fallback checkout. Do not repair the laptop during the demo.

## 2. Extend the EMI API with tests — 01:30–05:30

**Say:** “The agent follows financial invariants and proves them with tests rather than changing payment behaviour by accident.”

**Do:** Select Agent mode, focus `samples\python-emi-api`, and paste:

```text
Use the extend-emi-api skill and repository instructions to add POST /emi/schedule in samples/python-emi-api only. Accept the existing principal, annual_rate_percent and tenure_months plus an optional one-time prepayment_amount and prepayment_month pair. Use Decimal throughout and ROUND_HALF_UP to two decimals. Return monetary JSON as fixed two-decimal strings and display INR with Indian lakh grouping. Keep the existing rounded EMI unchanged. Each month round interest, apply the regular installment, then apply prepayment to remaining principal after the specified month's installment; prepayment shortens tenure, never recalculates EMI. Reject invalid or unpaired prepayment inputs and amounts above the remaining balance. Set the final installment exactly to remaining principal plus rounded interest, with zero final balance and no negative principal. Preserve POST /emi results and total_payment as rounded EMI times tenure. Add tests for no prepayment, valid prepayment, invalid inputs, shortened tenure, final settlement and rounding; run uv run pytest in the sample and fix failures. Do not install tools, launch services or change other samples.
```

Review the diff and test output. Use a synthetic request with `"principal":"2500000.00"`, `"annual_rate_percent":"8.5"`, `tenure_months: 240`; expected existing EMI is `"21695.58"`.

**Expected result:** Focused implementation and passing observed tests. Schedule monetary values are strings, the recurring EMI remains unchanged, and the last installment clears the exact balance. Prepayment reduces duration, not the EMI.

**Fallback:** Stop generation if it exceeds the slot. Inspect the prepared schedule implementation and labelled test evidence on `demo-complete`; do not accept an unfinished diff merely to keep time.

## 3. Containerise and inspect — 05:30–08:00

**Say:** “The same sample runs as a non-root Linux container, with the selected runtime visible.”

**Do:** Paste:

```text
Use the containerise-and-run skill for python-emi-api. Review its Dockerfile and run only scripts/run-sample.ps1 -Name python-emi-api -Mode container -Port 8080 after operator approval. Prefer wslc and fall back only to an already installed, approved docker runtime; report which is used. Do not install or update a runtime. Check http://localhost:8080/health, then POST /emi with {"principal":"2500000.00","annual_rate_percent":"8.5","tenure_months":240}. Open the service in VS Code's integrated browser. Verify emi "21695.58", total_payment "5206939.20", total_interest "2706939.20" and formatted INR values. Do not launch Azure resources, change enterprise policies or touch unrelated containers.
```

The operator-approved launch command is:

```powershell
.\scripts\run-sample.ps1 -Name python-emi-api -Mode container -Port 8080
Invoke-RestMethod -Uri 'http://localhost:8080/health'
Invoke-RestMethod -Method Post -Uri 'http://localhost:8080/emi' -ContentType 'application/json' -Body '{"principal":"2500000.00","annual_rate_percent":"8.5","tenure_months":240}'
```

**Expected result:** Runtime name, a healthy endpoint and the expected synthetic calculation, including `₹21,695.58`, `₹52,06,939.20`, `₹27,06,939.20`. The launcher waits for health; browser display alone is not verification.

**Fallback:** Use the already rehearsed, approved Docker alternative. If neither runtime works, show the Dockerfile and recorded response, clearly marked as recorded; do not install a runtime or bypass registry policy.

## 4. Prepare Azure files, do not deploy — 08:00–10:00

**Say:** “Cloud preparation is a reviewable change, separate from permission to provision or deploy.”

**Do:** Paste:

```text
Use the prepare-for-azure skill and GitHub Copilot for Azure to prepare an azd-based Azure Container Apps design for python-emi-api. Keep every generated file inside samples/python-emi-api so sample-scoped recovery is safe. Use managed identity and Azure Key Vault references if secrets are needed; add no secret values. Make the application container image a required environment-backed parameter with no placeholder image or unrelated demo-service default. Report an unset image input as an unmet prerequisite; do not invent an image or imply it has been published. Describe the resources, trust boundaries, registry access, least-privilege roles and expected cost drivers. Generate reviewable infrastructure and deployment configuration and perform only offline/static validation supported by already installed tooling. Do not run az login, azd auth login, azd up, azd deploy, az deployment, terraform apply, resource creation or any live Azure launch test. Do not deploy. Summarise generated files and distinguish checks actually run from deployment validation not performed.
```

Review generated files and the plan. Deny tools that would authenticate, mutate Azure or execute deployment. The Azure extension includes Azure MCP and skills, but their presence does not authorise their execution.

**Expected result:** A Container Apps design and reviewable files; no Azure resources created, no live launch tests, and explicit validation limitations.

**Fallback:** Inspect the reviewed Azure preparation files on `demo-complete` and explain the design. The application image is a required environment-backed parameter, not a placeholder demo service. Confirm the prepared parameter mapping and report missing runtime inputs honestly; do not build/publish an image or launch Azure to fill them during recovery. Do not claim static validation proves successful deployment.

## 5. Find and fix the two Go baseline gaps — 10:00–13:00

**Say:** “Our reviewer must identify concrete findings, fix them and prevent regressions.”

**Do:** The two intentional Go baseline exceptions are **logging the full request query string** and **returning an internal error message to the client**. This document is their only disclosure location. They are restricted to synthetic-data demo code and must not be copied into other services.

Paste:

```text
Use the bank-standards-review skill to review samples/go-fx-rates against .github/copilot-instructions.md. Report actionable findings with file and line, then fix the documented baseline exceptions within this sample only. Ensure logs cannot disclose raw request inputs, and client errors are stable and safe without internal details. Retain useful safe diagnostics, input validation, synthetic fixed rates and exact monetary arithmetic with fixed two-decimal JSON strings and INR lakh grouping. Add regression tests for the findings and run go vet ./... and go test ./... from samples/go-fx-rates. Do not launch the app, install tools, edit the legacy Java exercise or change unrelated files.
```

**Expected result:** Two concrete findings, a focused remediation and passing observed regression tests. Currency validation, negative-amount rejection and synthetic-rate behaviour remain intact.

**Fallback:** Inspect the reviewed remediation and regression tests on `demo-complete`. State whether tests were observed live or are recorded evidence.

## 6. Optional Java modernization — 13:00–15:00

**Say:** “The legacy application stays old for this specific migration exercise; modernization is an opt-in workflow.”

**Do:** Only if prerequisites were installed and rehearsed before the demo, open the modernization extension for `samples\java-legacy-upgrade` and paste:

```text
Use GitHub Copilot modernization to assess samples/java-legacy-upgrade, intentionally kept on Java 11 and Spring Boot 2.7. Plan and perform a focused migration to Java 25 and a supported Spring Boot release compatible with that target. Preserve endpoint behaviour, constructor-injected services and synthetic data. Update only this sample's manifests, source, tests and migration documentation. Run its Maven wrapper verification with the selected target JDK and fix migration failures. Do not install a JDK, upgrade the baseline by hand outside this workflow, add the legacy sample to the normal CI matrix, launch the app or deploy to Azure. Summarise changes and the exact checks observed.
```

**Expected result:** A migration assessment and, only if completed and verified within the slot, a working migrated sample. Do not promise a full migration in two minutes; the assessment is the bounded live segment.

**Fallback:** Show the rehearsed migration assessment/results. `demo-complete` is required for steps 2, 4 and 5, not assumed to contain modernization. If the extension is unavailable, omit this optional step and use the time for questions.

## Recovery without losing unrelated work

1. Stop agent edits and inspect `git status --short`. Preserve unrelated staged, unstaged, untracked and unsaved editor work in a separate checkout/backup; do not stash or delete it blindly.
2. Preview `.\scripts\demo-reset.ps1 -WhatIf`. Reset restores **only `samples\`**, including its staged changes, from `demo-baseline` and stops/removes only owned containers with the showcase label and these exact names: `win11-demo-python-emi-api`, `win11-demo-java-ifsc-service`, `win11-demo-go-fx-rates`. Review the confirmation; leave all other containers and files untouched. New untracked sample files require a separate, explicit deletion confirmation; preserve unrelated files and decline deletion rather than treating them as demo output. If unrelated work blocks reset, use the prepared disposable checkout instead of bypassing the guard.
3. For the full prepared fallback, confirm a clean disposable checkout and inspect the ref before switching:

   ```powershell
   git show-ref --verify refs/heads/demo-complete
   git status --short
   git switch demo-complete
   ```

   **Do not switch a dirty/shared checkout.** Use the separately prepared fallback checkout instead. Review fallback content before running any tests or launch.
4. When a targeted restore is preferable, use `git restore --source=demo-complete --worktree -- samples/python-emi-api` or the corresponding `samples/go-fx-rates` path **only after confirming that subtree contains no unrelated changes**. This discards tracked edits in the named subtree; it neither removes new files nor restores the index. Inspect residual/untracked files manually, and never use repository-wide `reset --hard`, `clean`, container prune or mass stop/remove.

No recovery step runs setup, repair, uninstall, Azure authentication or deployment.
