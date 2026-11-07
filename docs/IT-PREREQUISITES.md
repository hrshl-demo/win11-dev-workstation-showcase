# IT prerequisites

This repository consumes enterprise controls; it does not deploy Intune policies, onboard Defender, create identities or grant Copilot licences. Approve and pilot those controls independently.

## Device and elevation

| Requirement | IT decision |
| --- | --- |
| Windows 11 build 22621+ | Select a supported servicing release and approved device image |
| Administrator elevation | Approve base machine-wide changes and package licences; expect up to two base UAC prompts, plus add-on elevation where resources require it |
| Hardware virtualization | Enable approved BIOS/UEFI virtualization; for Cloud PCs/VMs, confirm supported nested virtualization and SKU capabilities |
| Storage | About 15 GB free for the base; budget additional SDK, build-cache and image space |
| Signed execution | An effective Restricted policy blocks repository scripts; AllSigned requires trusted signatures for scripts and modules. Bootstrap may be blocked before its body or preflight runs, and module imports may also be denied. Obtain an IT-approved script-execution context first. The upstream Microsoft signature does not authorize this repository's scripts. No automatic policy override is permitted. |
| User context | Register App Installer for the signed-in developer; WinGet CLI is not supported as SYSTEM |

The base changes Windows settings and can restart. Full setup additionally enables Remote Desktop/firewall and other settings: it is not the default and needs separate review.

## Network and package sources

Allow approved HTTPS access to `aka.ms`, `github.com`, `raw.githubusercontent.com`, `codeload.github.com`, `release-assets.githubusercontent.com`, `www.powershellgallery.com` and approved WinGet sources, including `cdn.winget.microsoft.com`. Microsoft base guidance requires proxy configuration for **both WinHTTP and WinGet**.

Preflight probes only a subset of hosts. Successful probes do not prove access to package payload CDNs, the VS Code Marketplace, Copilot endpoints, Maven/Python module indexes, approved image registries or Azure services. IT must review those workload-specific dependencies and certificate/signature validation paths separately. TLS inspection must not defeat Authenticode trust or TLS validation.

Approve registry hosts used by reviewed sample Dockerfiles, including Microsoft Container Registry (`mcr.microsoft.com`) and any required upstream registries, or provide approved mirrored images. A registry allowlist restricts registry access, not individual image provenance or vulnerability status.

## App Installer policies

Use the [DesktopAppInstaller Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-desktopappinstaller). Registry policy values are under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller`; verify effective state with `winget --info`.

| Policy | Required outcome |
| --- | --- |
| `EnableAppInstaller` | Package manager use allowed |
| `EnableWindowsPackageManagerCommandLineInterfaces` | CLI use allowed |
| `EnableWindowsPackageManagerConfiguration` | Configuration use allowed |
| `EnableAllowedSources` | Approved sources can be used; explicitly review configured list |
| `EnableDefaultSource` | Default WinGet source available if required by the reviewed configuration |

A value of `0` on the first three disables the corresponding capability. The current CSP documents the CLI/configuration policies for Windows 11 24H2+ and the App Installer/source policies for 22H2+; match policy delivery to the serviced OS rather than assuming every setting applies to the add-on's minimum build. Do not globally enable all sources to solve a denied configuration. The scripts report policy blocks; only IT can decide changes.

## WSL and Linux containers

[Microsoft announced WSL containers GA on 29 September 2026](https://blogs.windows.com/windowsdeveloper/2026/09/29/wsl-containers-now-generally-available/). The [CLI guide](https://learn.microsoft.com/en-us/windows/wsl/wsl-container) requires **WSL 2.9.3+**; `wslc.exe` has the `container.exe` alias. This does not mean every related API projection is GA: the C++/WinRT projection is documented as preview.

Use the [WSL Intune settings catalogue](https://learn.microsoft.com/en-us/windows/wsl/intune) to review:

- **Allow the Windows Subsystem For Linux**, Store versus inbox WSL and WSL1 restrictions.
- **Allow WSL container**: access for users and Windows applications.
- **Allow privileged WSL containers**: restrict privileged mode and additional capabilities.
- **Allowlist for WSL container registries**: restrict pulls through the WSL container CLI and API.
- Custom-kernel, debug-shell and related configuration restrictions according to security policy.

These are IT-delivered controls, not settings bootstrap enables. Test actual policy application with the chosen WSL version. The repository uses simple Docker-compatible build/run/ps/stop/rm/image-list workflows, without Dev Container features or Compose.

## Defender coverage is conditional

The [Defender for Endpoint WSL plug-in guide](https://learn.microsoft.com/en-us/defender-endpoint/mde-plugin-wsl) describes WSL2 and WSL container event visibility on an onboarded Windows host with Defender for Endpoint Plan 2. **WSL container visibility requires WSL 2.9.12+**, not merely the CLI minimum.

IT must install the supported plug-in and verify its health/version and connectivity. The current guide excludes ARM64 and Windows multi-session, warns about custom kernels, and notes that short-lived instances may not appear immediately. The logical WSL device does not provide every host feature: antimalware, threat/vulnerability management and response commands are not available there. Do not equate “Windows host onboarded” with complete Linux-container coverage.

## Identity, Copilot and VS Code

- Assign organisation-approved Copilot Business/Enterprise seats and enforce GitHub organisation policies, model/tool permissions and data-handling rules. A personal/free sign-in is not the enterprise licence path.
- Deliver supported VS Code/Copilot policies using [VS Code enterprise policy templates](https://code.visualstudio.com/docs/enterprise/policies) through device management. Policy values override user/workspace settings; workspace recommendations are not security enforcement.
- Confirm sign-in, Workspace Trust, MCP consent and agent-skill discovery in the target editor/harness. [Customization compatibility](https://code.visualstudio.com/docs/agent-customization/overview) varies; prompt files require Local sessions.
- [GitHub Copilot for Azure](https://learn.microsoft.com/en-us/azure/developer/github-copilot-azure/introduction) includes Azure MCP and `azure-prepare`, `azure-validate`, `azure-deploy` skills. Presence is not approval to deploy. Azure access follows Entra identity and least-privilege RBAC; use managed identity/Key Vault in reviewed designs.

## GitHub CI and existing AKS approval

The developer workflow stays in VS Code: Source Control/GitHub sign-in, branch/commit/publish/PR and integrated-terminal tasks. IT supplies approved VS Code/Git on a fresh laptop before cloning; an already configured laptop skips bootstrap. Setup and explicit project package Restore are human actions, not agent permissions.

Review pinned test dependencies/modules and allowed package sources: pytest/pytest-cov and Ruff, JUnit 5/JaCoCo and Maven Checkstyle, Go built-in tests/coverage/vet, Pester **5.7.1** and PSScriptAnalyzer **1.24.0**. Daily checks must not download missing packages/toolchains. Optional Docker Desktop remains commented and licence-reviewed; `wslc` failure must not cause policy-bypassing Docker fallback. Shared `-Runtime Auto|wslc|docker` selection probes only an explicitly selected approved runtime; explicit choice is not a workaround for denied policy.

For the [existing-AKS plan](GITHUB-AKS.md), IT owns cluster/ACR/namespace/RBAC/OIDC identities and runner connectivity. Use separate build and deploy identities, user rather than admin kubeconfig, Entra kubelogin, kubelet image pulls, ACR mode-aware roles and restricted namespace rights. Private cluster APIs require an approved network-connected runner with preinstalled tools. No workflow provisions resources or exposes public ingress.

Repository administrators must configure `aks-demo` with required reviewers, prevent self-review, no admin bypass and only the main branch. **Private environment creation is not proof of required-reviewer availability**: GitHub Free/Pro/Team reviewer protection is public-repository-only per the current primary reference. Private deployment requires a compatible plan and verifiably active protection. Workflow checks fail closed if the API cannot prove the controls; do not bypass them. Verify actual immutable/legacy OIDC subject claims before federation.

## Windows 365

The [official developer overview](https://blogs.windows.com/windowsdeveloper/2026/09/14/build-anywhere-stay-in-flow-with-windows-365/) describes ready-to-code developer configurations. This does **not** establish that this repository's exact add-on is a built-in Windows 365 public-preview offering. Pilot supported images, policies, licences and virtualization for the intended Cloud PC; do not promise automatic portability or feature availability.

Primary sources reviewed 7 November 2026. Recheck release status and support restrictions before rollout.
