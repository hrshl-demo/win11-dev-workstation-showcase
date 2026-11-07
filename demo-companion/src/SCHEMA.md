# Workstation companion content schema

Python standard-library generator; generated HTML and classic JS are committed.
One page registry in `content\site.json`, reusable code definitions in
`content\blocks\commands.json`, useful source paths only. No remote loads.

| Kind | Content |
| --- | --- |
| `home` | Generated from `home.json`: controls, boundaries, journey cards, scoped trust labels |
| `quick` | Summary/status plus numbered short steps: actor/title/where/do/see/more, optional named code and warning |
| `activity` | A purpose, B starting state, C exact numbered steps, D copyable, E expected result, F success/failures/recovery/limits, G 3-8 presentation lines; sources and gaps |
| `reference` | At least two named sections of typed blocks; sources/gaps |
| `prompts` | Generated exact source-bound runbook prompt library |
| `evidence` | Dated `evidence.json` observations plus every quick step's unproven manual acceptance row |

Inline markup: backtick code, bold and `[label](page:page-id#anchor)` internal
links. Every typed block has exactly one key: `p`, `h`, `ul`, `ol`, `kv`,
`table`, `callout`, `code`, `fieldnote`, `checklist`, `quote` or `screenshot`.
Capture placeholders are explicitly not evidence; no real screenshots ship.
Expected contract examples use paragraphs/tables or labelled documented
examples, never a claim of observed output.

Quick steps have at most six instruction lines and 90 words across
instruction/warning/expected text; detailed step anchors are required.
Failures specify symptom, likely cause, safe action and
`repeat_safe: yes|no|careful`. Timing is unknown/variable unless source budgets
are explicitly identified as timeouts, not completion promises.

Code is **only** `{"ref": "block-id"}` in pages. Each definition specifies
id/label/lang/actor and a `bound` source:

- `task`: actual `.vscode\tasks.json` label, optional approved picker inputs;
  derives the PowerShell dispatcher equivalent without executing it.
- `lines`: exact visible text; every line occurs in current and pinned source.
- `fence`: one exact source fence selected by its unique starting text.

Both current checkout and the immutable underlying source pin must match the
rendered copyable text. No invented command, menu label, endpoint or evidence.
Only non-sensitive explicitly declared placeholders are allowed; this
companion needs no credential/account input.

Pages reference the workstation repository as generic registry key `poc`;
source paths use Windows separators, converted to URL separators only when
rendering GitHub links. Actors/statuses/colours are data-driven. Storage uses
the distinct `w11dc.` namespace, manual progress and explicit memory-fallback
feedback. Missing prerequisites or source comparison are NOT RUN, not green
success-shaped fallbacks.
