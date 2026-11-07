# 15-minute VS Code demo

Setup and package restoration happen **before** the presentation. Full provisioning is not this 15-minute coding demo; a separate provisioning presentation needs its own download/reboot/enterprise-acceptance window, not recorded CI as fresh-laptop proof. Use synthetic data and a disposable reviewed checkout of safe revised `main`. All work uses VS Code menus, tasks and integrated terminals. Do not approve agent requests to install, authenticate, launch, dispatch, provision or bypass policy.

## Pre-demo checklist

- Follow [Setup Phase 0–7](SETUP.md): prerequisites before scripts, Preflight, automated full setup for fresh/partial incomplete-base devices, Finish setup only after base completion/resume, post-setup Verify then explicit **user** Restore. Confirm runtimes, test packages, 12 required extensions enabled in the intended approved profile/source and GitHub/Copilot access.
- Rehearse daily Test/Lint/Coverage tasks and inspect reports. Before the presentation, explicitly build approved local images through confirmed Restore ContainerImages. RunContainer requires those existing images and uses `--pull=never`, with no build/pull/restoration. Missing prerequisites mean NOT RUN; do not restore packages/images or repair the machine during the demo.
- Confirm instructions, onboarding agent and skills in the Agent Customizations editor. Tool access does not grant permission.
- Inspect current `main` and the retained `demo-complete` schedule fallback. The original `demo-baseline` tag is historical unsafe code: **do not launch it, restore running samples from it or deploy it**.
- Confirm port 8080 and the already approved runtime. `-Runtime Auto` chooses `wslc` first and Docker only if WSL CLI is absent; explicit `-Runtime wslc|docker` probes only that approved choice without fallback. Never select another runtime to bypass a policy denial.
- Inspect GitHub CI and [existing-AKS prerequisites](GITHUB-AKS.md). The live demo prepares/reviews files; deployment is a separate dispatch and independent approval, not a surprise end-of-demo action.
- Optional modernization requires Java 11 and its extension arranged in advance. Core checks exclude legacy; `verify.ps1 -IncludeJavaModernization` checks the extension but does not select Java 11.
- Keep recorded output clearly labelled with its revision/runtime/date. Never present recorded checks as live results.

## 1. Readiness and developer workflow — 00:00–02:00

**Say:** “Prerequisites come before scripts. Fresh or partially configured devices use approved automated setup; missing tools in pre-install inventory are expected. Fully verified devices skip installation. Package restore is separate; daily checks never install.”

In **Terminal → New Terminal → PowerShell**, repository root:

```powershell
.\scripts\verify.ps1
.\scripts\developer.ps1 -Action Test -Sample All
```

Show **Terminal → Run Task**, the Testing Activity Bar, Source Control and the GitHub Pull Requests view.

Paste to **Workstation onboarding**:

```text
Read docs\SETUP.md and docs\IT-PREREQUISITES.md. Explain prerequisites, installed-first module preview and independent Core/SDK/Extensions/WSL installs chosen by the human. Existing tools skip download/upgrade; incompatible/unknown inventory fails without download, including stale PATH discovery. Missing pre-setup outputs can cause expected optional Verify exit 1. Normal setup never invokes Microsoft bundle or global tweaks; a stopped partial base is not completed. Legacy bundle/SkipBase is optional only after confirmed successful base/resume. Explain automated missing extensions and approved source/profile acceptance. Separate human Restore, no-restore tests, GitHub CI and AKS approval. You may run only preflight.ps1 and verify.ps1 without RunConfigTest. Do not run module setup, repair, policy/auth/launch/deployment actions.
```

**Expected:** Accurate readiness/test output, with optional modernization distinguished. **Fallback:** Label recorded output and explain current failures; no laptop repair.

## 2. Extend EMI with focused tests — 02:00–06:00

**Say:** “Financial invariants stay explicit: preserve rounded EMI, shorten tenure, settle the last payment exactly.”

Focus `samples\python-emi-api`, use Agent mode:

```text
Use the extend-emi-api skill and repository instructions to add POST /emi/schedule only in samples\python-emi-api. Use Decimal and ROUND_HALF_UP; fixed two-decimal monetary strings and Indian INR grouping. Preserve existing rounded EMI and POST /emi total_payment. Accept optional paired prepayment_amount/prepayment_month. Each month round interest, apply regular installment, then one-time prepayment to remaining principal after that month's payment. Shorten tenure without lowering EMI. Reject invalid/unpaired inputs and prepayment above remaining principal. Final installment is exactly remaining principal plus rounded interest; never create a negative balance. Add no-prepayment, valid/invalid prepayment, shortened-tenure, settlement and rounding tests. Run only no-download/no-restore checks with the existing pinned environment. If unavailable, report NOT RUN; do not install, launch or change another sample.
```

Review the diff; the developer runs the focused Test/Coverage tasks:

```powershell
.\scripts\developer.ps1 -Action Test -Sample Python
.\scripts\developer.ps1 -Action Coverage -Sample Python
```

Synthetic existing EMI example: principal `"2500000.00"`, annual rate `"8.5"`, tenure `240`; EMI `"21695.58"`.

**Expected:** Focused behavior/tests and truthful check results. **Fallback:** Open inspected `demo-complete` schedule files and recorded evidence; do not accept an unfinished diff to meet the clock.

## 3. Operator container launch — 06:00–08:00

**Say:** “The operator, not the agent, starts the approved runtime and verifies a real synthetic request.”

Ask the agent to **review only** the sample Dockerfile, non-root execution, health check and runtime selection. Do not ask it to run containerisation or setup.

The **human** uses the container task or integrated terminal with the image
already prepared in the explicit Restore ContainerImages stage:

```powershell
.\scripts\developer.ps1 -Action RunContainer -Sample Python
```

In a second VS Code integrated terminal:

```powershell
Invoke-RestMethod -Uri 'http://localhost:8080/health'
Invoke-RestMethod -Method Post -Uri 'http://localhost:8080/emi' -ContentType 'application/json' -Body '{"principal":"2500000.00","annual_rate_percent":"8.5","tenure_months":240}'
```

Open the service using VS Code's browser UI. Expected monetary strings: `"21695.58"`, `"5206939.20"`, `"2706939.20"`; INR displays `₹21,695.58`, `₹52,06,939.20`, `₹27,06,939.20`.

**Fallback:** If `wslc` is absent, use only the already approved Docker alternative. If present but failing, stop and show recorded evidence; do not switch to circumvent WSL policy. Neither runtime available means no launch. Docker Desktop is optional and licence-reviewed, never installed live.

## 4. Existing AKS preparation, not provisioning — 08:00–10:30

**Say:** “We reuse existing AKS and ACR. Tests gate image build; independent approval gates namespace deployment. A PR never deploys.”

Paste:

```text
Use prepare-for-azure to review application-only Kubernetes manifests and docs\GITHUB-AKS.md for existing AKS/ACR. Require real namespace/image inputs; do not invent values, placeholders or latest tags. Keep non-root Deployments, health probes, limits and ClusterIP Services. Explain main-only workflow_dispatch with required current source_sha, modern-service test gates, separate OIDC build/deploy identities, same-run image digests and independent aks-demo approval. Explain precreated namespace, kubelet pulls, ABAC/non-ABAC permissions and private API runner connectivity. Verify official documentation only; validate static files using existing dependencies. Do not authenticate, fetch tools, provision, create namespace/RBAC/registry/ingress, build/push images, get kubeconfig, dispatch Actions or deploy. Report missing inputs and distinguish static from unobserved live checks.
```

Show `.github\workflows\deploy-aks.yml`, Kubernetes templates and `docs\GITHUB-AKS.md`. Explain required reviewers, prevent self-review, no admin bypass and main-only environment rule. Private repository reviewer protection needs a compatible plan and live verification; unavailable/unverifiable controls **fail closed**.

The developer can use the Kubernetes static-check task. Do **not** dispatch a deployment as part of this preparation segment.

**Fallback:** Inspect existing-AKS files on reviewed `main`/`demo-complete`. No old Container Apps `azure.yaml`/infra and no historical unsafe baseline. Missing Azure values remain missing; do not provision to finish preparation.

## 5. Review an isolated unsafe fixture — 10:30–13:00

**Say:** “Serving Go code is safe. We teach review using non-executable text, not defects in an image that could reach AKS.”

The fixture `tests\fixtures\go-review-example.txt` contains the historical examples of **raw query-string logging** and **internal error-message disclosure**. It is not Go source, a live handler or deployment input.

Paste:

```text
Read .github\copilot-instructions.md and .github\instructions\go.instructions.md. Review tests\fixtures\go-review-example.txt as non-serving training text. Identify the two actionable findings with fixture line references and impact, and describe safe logging/stable client-error alternatives and regression assertions. Do not apply either defect to live samples, modify the fixture into executable code, launch services or install tools. Contrast with the safe samples\go-fx-rates regression tests; do not claim checks ran unless observed.
```

The developer runs:

```powershell
.\scripts\developer.ps1 -Action Lint -Sample Go
.\scripts\developer.ps1 -Action Test -Sample Go
.\scripts\developer.ps1 -Action Coverage -Sample Go
```

**Expected:** Two concrete fixture findings, no serving-code exceptions and accurate observed checks. **Fallback:** Show safe regression tests plus recorded output; never restore old defects to make the exercise work.

## 6. GitHub PR and optional modernization — 13:00–15:00

In VS Code select **Source Control**, inspect/stage intended files, commit with a conventional message, **Publish Branch**, then **GitHub Pull Requests: Create Pull Request**. Preserve the PR template; record exact observed commands/results/skips. Show CI checks/artifacts. Main merge and deployment approvals remain separate decisions.

If rehearsed beforehand, use GitHub Copilot modernization to **assess** the intentional Java 11 / Boot 2.7 sample, preserving synthetic contracts and recording the migration plan/checks. A two-minute assessment is not a promise of a completed migration. Do not upgrade by hand, add legacy to main CI, install a JDK or deploy it.

## Recovery without losing unrelated work

1. Stop agent edits and inspect **Source Control** or `git status --short` in the integrated terminal. Preserve unrelated staged, unstaged, untracked and unsaved editor work. Do not blindly stash/delete it.
2. Prefer a separately prepared, reviewed clean checkout of safe revised `main`, or inspected `demo-complete` for the schedule fallback. Use **File → Open Folder** to change checkout; do not switch a dirty/shared checkout.
3. Confirm the fallback's actual contents/ref before tests or user launches. It retains the schedule and the same manual/main-only AKS pipeline, not old Container Apps preparation. Deployment from a fallback branch is forbidden.
4. For a user-approved sample reset, first **Ctrl+Shift+P → Git: Fetch** from the
   approved remote. Inspect `origin/main` and ensure sample subtrees contain no
   unrelated work. Preview `.\scripts\demo-reset.ps1 -WhatIf` in the integrated
   terminal, then select **Terminal → Run Task → Reset demo** (confirmed) or run
   `.\scripts\demo-reset.ps1` only after reviewing and
   explicitly confirming its sample/container scope. It restores only samples
   from fetched safe `origin/main`, freezes/rechecks the commit during
   confirmation and rejects old unsafe Go code. It does not fetch for you.
   Preserve unrelated untracked files; never approve deletion merely because
   they sit under samples. The original `demo-baseline` remains historical and
   unchanged, not a reset source or deployment ref.
5. Stop only the specific operator-owned sample process/container using its
   known terminal/process ID/name. The reset helper handles only its known
   labelled demo containers, not unrelated containers. No repository-wide
   `reset --hard`, `clean`, container prune or mass stop/remove. Any targeted
   restore is a separate explicit user action after confirming no unrelated
   work in that subtree.

Recovery never runs setup, repair, package restore, uninstall, authentication or deployment.
