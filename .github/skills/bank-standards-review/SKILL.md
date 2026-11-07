---
name: bank-standards-review
description: Review a banking sample against repository standards, fix requested findings and rerun its tests.
---
# Bank standards review

1. Read .github/copilot-instructions.md and the relevant scoped language instructions.
2. Review the sample and tests for log masking, safe error messages, exact monetary arithmetic, input bounds, dependency pins and tests. Respect the legacy Java exception.
3. Report actionable findings with file and line plus impact. Do not reproduce sensitive input in the report.
4. On the presenter's request, fix the scoped baseline exceptions as part of the review; add tests demonstrating safe logging and client errors while preserving successful behavior.
5. Run the affected sample's documented tests (and go vet for Go); fix failures. Do not launch apps, containers, setup or Azure actions.

Done: findings cite actual code, fixes preserve contracts, tests pass and unobserved acceptance checks are clearly marked.
