---
applyTo: "**/*.go"
---
# Go

Use the standard library first, table-driven tests and httptest for HTTP contracts.
Use exact integer/rational decimal arithmetic with input-length and value bounds for money, explicit half-up cent rounding and INR lakh grouping.
Apply server/context timeouts. Validate query parameters and send safe errors. Never log request query strings or sensitive values.
Run `go vet ./...` and `go test ./...` inside samples/go-fx-rates.
Respect the scoped baseline demo exceptions described in the demo runbook until the presenter requests their review; do not introduce any others.
