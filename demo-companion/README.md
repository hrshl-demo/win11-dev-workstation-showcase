# Windows 11 workstation demo companion

An offline, multi-page guided companion for this private repository. The 20
pages contain quick steps, detailed A-G activities, recovery, architecture,
copy-only commands, exact runbook prompts and a dated evidence register.

For **execution rather than command copying**, open the reviewed repository in
locally running Windows VS Code, select **Workstation setup** in Chat's Agent
dropdown, and use the companion's source-bound start/resume prompt. The named
agent invokes existing terminal surfaces after inventory and scoped human
approval; you answer native confirmations. Generic coding/build/desktop/cloud
agents do not have that exception. Missing tools/prompts, IT policy, UAC and
restart remain real pauses. This HTML only copies instructions and never runs
the agent or setup. Live VS Code tool/approval acceptance is not yet proven.

## Open the complete folder

Keep this **whole folder** and double-click `index.html`. No server, viewer
build, installation or sign-in is required. A portable ZIP must be extracted
as a complete folder first. Do not download only the entry HTML: its relative
`assets`, `data` and `pages` are required. Private GitHub keeps the static
sources; this is not GitHub Pages or an externally hosted application.

Default desktop slides use the reused generic measured-fit deck engine.
The generic shell, CSS and deck are adapted from the separately verified
Demo Companion reference; registry, instructions and source bindings are
specific to this workstation repository.
Short/phone screens use long pages and a drawer. `?deck=off` requests a long
page; `?deck=on` forces the deck. Light is default; `?theme=dark` is explicit.
Use arrows/Home/End, M (slides), / or Ctrl+K (local search), ? (keys), T (theme),
Escape (close), or normal buttons/links. Browser Print exposes slide content.

Checkmarks, pages-done counters and Resume are **manual progress, not machine
verification**. Storage failures are displayed, with memory-only fallback.
Copy never executes or sends anything. Clipboard denial is displayed.
No credentials/customer data are collected, and no network API, external
script/font, installer, shell, elevation or cloud operation runs from HTML.
Online source links require user clicks and private-repository access.

## Source and evidence scope

Underlying source pin:
`c226e1233c56f10ee9215835f7cb56cf8ee24b84`, facts as of **2026-11-08**.
The evidence register preserves earlier dated main/fallback runs, independently
of this source pin; it is not live polling or acceptance of the new agent.
Laptop setup, extension
profile/source acceptance, Restore, F5, sample/container requests and AKS
deployment are **not proven live by this companion**.

Normal setup is installed-first named modules, not a Microsoft bundle.
Human-approved Restore is separate from no-restore daily checks. Stopped
partial legacy setup is not successful Finish/resume or rollback. Existing
AKS/ACR delivery requires real inputs, current trusted main, independent
approval and same-run image digests; unavailable controls fail closed.

## Maintain without installing or launching anything

Viewing requires no Python/Node. Maintainer regeneration uses only an
**already installed Python 3.12+ standard library and Git**, from this folder
inside the repository. The Python used for this generator is not acceptance
of the sample's required Python 3.14 environment.

```powershell
python -B src\validate_content.py --require-all
python -B src\build.py --strict
python -B src\check_site.py
python -B src\test_companion.py
```

The generator reads current and immutable pinned repository text, then writes
LF HTML/classic-script globals and `src\sources.lock.json`. It never executes
the source-bound commands. All copyable terminal/prompt text is defined once
in `src\content\blocks\commands.json`; task equivalents are derived from
actual task labels/arguments and checked against both sources.

`check_site.py` validates HTML/anchors/assets/code integrity, offline loading,
privacy, stale content and JavaScript syntax with **already installed** Node.
Node absence is **NOT RUN**, not a syntax pass. A complete standalone copy
can run `check_site.py --use-lock` to compare to the delivered source lock;
that mode explicitly does not independently inspect the source repository.
Do not install tools, restore dependencies or start a server to make checks
pass. Visual browser validation is a separate observation, never inferred
from static checks.

An optional `src\sweep.py` audit uses an **already installed Edge** executable
and a fresh session-artifact `--output` directory. It reads local `file://`
assets only, with exact-size disposable test frames and synthetic storage/
clipboard cases. It starts no HTTP server, installs nothing, uses a separate
temporary browser profile and never accesses the OS clipboard. The audit is
not setup, sample, cloud or laptop verification.

See [the schema](src/SCHEMA.md), [facts](src/FACTS.md) and
[first-time path audit](src/FIRST-TIME-PATH.md). Generated files are committed,
so readers never need the generator.
