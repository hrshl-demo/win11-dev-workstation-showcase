---
applyTo: "**/*.go"
---
# Go

Use the standard library first, table-driven tests and httptest for HTTP contracts.
Use exact integer/rational decimal arithmetic with input-length and value bounds for money, explicit half-up cent rounding and INR lakh grouping.
Apply server/context timeouts. Validate query parameters and send safe errors. Never log request query strings or sensitive values.
Run `go vet ./...` and `go test ./...` inside `samples\go-fx-rates`, using the installed manifest-defined toolchain with downloads disabled. VS Code tasks separate user restoration from daily checks; report missing tools as NOT RUN.
Revised main has no serving-code baseline exceptions. Review the non-serving text fixture `tests\fixtures\go-review-example.txt` without copying defects into Go code. The historical demo-baseline tag is unsafe and must not be launched or deployed; see the demo runbook.
