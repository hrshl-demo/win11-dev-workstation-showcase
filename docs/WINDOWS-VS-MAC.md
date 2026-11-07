# Windows 11 and macOS for development

Choose devices by workload, supported hardware, operational controls and developer needs—not by a universal platform ranking.

## Parity

Both platforms support VS Code, GitHub Copilot and Azure CLI. Microsoft Intune manages both, and Defender for Endpoint supports both through platform-specific onboarding and capabilities. Those products do not imply identical policy surfaces or detection coverage.

VS Code supports [enterprise policies on Windows and macOS](https://code.visualstudio.com/docs/enterprise/policies). GitHub account/licensing and organisation policy remain separate from local editor settings.

## Where Windows 11 can be a stronger fit

| Requirement | Windows option | Qualification |
| --- | --- | --- |
| Repeatable workstation preparation | [Microsoft-signed Windows Developer Config](https://github.com/microsoft/WindowsDeveloperConfig), plus reviewed WinGet configuration | Community add-on; enterprise approval, elevation and restart may be required |
| Linux development beside Windows applications | WSL2 uses a real Linux kernel; Windows business applications stay on the same device | Kernel, filesystem, networking and hardware differences still require production testing; “same as production” is not guaranteed |
| Familiar shell ergonomics | [WSL Comfort](https://github.com/microsoft/WindowsDeveloperConfig) offers optional `pbcopy`, `pbpaste`, `open`, shell tools and Homebrew | Separate optional configuration, not part of this repository's required base/add-on |
| Governed Linux containers | WSL containers with Intune access/privilege/registry controls and a supported Defender plug-in | See [support boundaries](IT-PREREQUISITES.md); CLI minimum and Defender minimum differ, and ARM64 Defender plug-in coverage is excluded |
| Hardware choice | Approved AMD, Intel, NVIDIA and Qualcomm device options; NVIDIA CUDA-capable devices can suit local AI | Validate architecture-specific packages, drivers, GPU/framework compatibility and security coverage; not every device supports every workload |
| Remote developer access | Windows 365 offers ready-to-code developer configurations and centrally managed Cloud PCs | Pilot images, licensing, nested virtualization and regional availability. This exact repository configuration is not claimed as a built-in public preview |
| One device for mixed work | Windows development tools and Windows-only business applications | Avoids a separate Windows environment where those applications are required |

macOS remains a strong choice for native Apple-platform development and teams with established Mac fleet operations. Containers, cloud tooling and familiar Unix workflows are available there too; this showcase does not demonstrate macOS configuration or benchmark either platform.

## Verified, not assumed

- [WSL container GA announcement](https://blogs.windows.com/windowsdeveloper/2026/09/29/wsl-containers-now-generally-available/): 29 September 2026.
- [WSL container CLI](https://learn.microsoft.com/en-us/windows/wsl/wsl-container): WSL 2.9.3+; no claim that every API projection is GA.
- [Intune WSL policies](https://learn.microsoft.com/en-us/windows/wsl/intune) and [Defender WSL plug-in](https://learn.microsoft.com/en-us/defender-endpoint/mde-plugin-wsl): configurable governance and conditional visibility, not automatic complete protection.
- [Windows 365 developer overview](https://blogs.windows.com/windowsdeveloper/2026/09/14/build-anywhere-stay-in-flow-with-windows-365/): developer configuration described; no unsupported “same configuration in public preview” promise.

Sources reviewed 7 November 2026. No performance, cost or productivity advantage is asserted without measurement.
