# Source facts and trust boundaries

Underlying installer/application source:
`73cd348c198da748c77d8a22c4d8314abdc66d36`. Facts as of **2026-11-08**.
The source-command lock contains the exact command/prompt text and immutable
source hashes. Companion discovery links are focused documentation additions;
no installer, sample, CI, deployment or cleanup logic is changed.

- Setup is one installed-first named module. Every target is inventoried
  before payload/source/provider activity; compatible installed versions are
  retained, unknown/incompatible inventory stops without downloads.
- Normal bootstrap previews Core without mutation. Agents never execute even
  module preview/WhatIf. SDKs, approved extensions, WSL and optional Ubuntu are
  independently confirmed. Docker/licensing and modernization are opt-in.
- The legacy Microsoft bundle is not normal setup or partial-run recovery.
  A stopped partial base is not completed Finish/SkipBase/reboot/resume.
- Save work and fully exit/reopen VS Code from Windows when environment
  refresh is needed. A new terminal or Reload Window is not guaranteed.
- Required acceptance is 12 extensions in the intended approved profile,
  with the thirteenth modernization recommendation optional. CLI IDs alone
  do not prove profile, enabled state or marketplace policy acceptance.
- Explicit human Restore is separate from daily Test/Lint/Coverage and F5.
  Missing prerequisites mean NOT RUN. All excludes legacy Java.
- Money uses exact arithmetic, explicit half-up rounding, fixed two-decimal
  JSON strings and Indian INR grouping. Go review defects are non-serving
  training text. Historical `demo-baseline` is never runnable/deployable.
- Existing-AKS delivery is optional and manual from trusted current main,
  with required real inputs, modern CI, distinct identities, same-run digests
  and independent live-verifiable environment protection. Fail closed.
- Cleanup retains source, shared tools, accounts, environments, module/cache
  trees, WSL/distro data and cloud resources. Only exact newly owned unchanged
  generated outputs can qualify after review and confirmation.

These are repository facts, not a recorded successful laptop setup. The
dated evidence register scopes the successful underlying main/fallback jobs;
all live operator acceptance still requires a human observation.

## User-clicked link registry

Reviewed against source addresses on **2026-11-08**, not an HTTP/live sign-in
rehearsal. No online link is opened automatically.

| ID | Scope |
| --- | --- |
| `repo` | Authorized private workstation repository |
| `actions` | Its CI/manual workflow run list |
| `wsl-docs` | Official Microsoft WSL documentation |
| `aks-docs` | Official Microsoft AKS documentation |
| `execution-policy` | Official PowerShell execution-policy documentation |
