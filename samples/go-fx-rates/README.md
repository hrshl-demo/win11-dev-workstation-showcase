# Synthetic FX conversion

Go **1.27.3**, standard library only. Fixed rates to INR are **USD 88.00**,
**EUR 102.00** and **GBP 117.00**: synthetic demonstration values,
**not market data**. This service does not call banks or external rate providers.

## Test and run

Open the repository root in **VS Code** and choose **Terminal → Run Task** or
run in its integrated PowerShell terminal:

```powershell
.\scripts\developer.ps1 -Action Test -Sample Go
.\scripts\developer.ps1 -Action Lint -Sample Go
.\scripts\developer.ps1 -Action Coverage -Sample Go
```

Go built-in tests/coverage and vet need no external module; require the installed
manifest-defined Go version, with no automatic toolchain download.
Reports: `test-results.json`, `coverage.out`, `coverage.html` in this sample.
Use the Go extension's test/debug support or reproducible tasks. Missing Go
means **NOT RUN**, not install. See [Setup](../../docs/SETUP.md).

From this directory, with your already-approved Go installation:

```powershell
$env:GOTOOLCHAIN = 'local'
$env:GOPROXY = 'off'
go vet ./...
go test ./...
# Separate human-operated launch, not part of daily verification:
go run .
```

The default port is **8080**. Override it in this process:

```powershell
$env:PORT = '8081'
go run .
# After stopping with Ctrl+C:
Remove-Item Env:PORT
```

In another **VS Code integrated PowerShell terminal** (change the port when overridden):

```powershell
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod 'http://localhost:8080/convert?from=USD&to=INR&amount=100'
```

`GET /health` returns `{"status":"ok"}`. Conversion returns HTTP 200:

```json
{
  "from": "USD",
  "to": "INR",
  "converted_amount": "8800.00",
  "inr": "₹8,800.00",
  "rate_source": "synthetic fixed rates; not market data"
}
```

Money is a fixed two-decimal **JSON string**, never a floating-point number.
The calculation parses decimal text into a rational number, multiplies by the
integer synthetic rate, and rounds integer paise **half up**. Indian grouping
is applied only for display.

`from`, `to` and `amount` are required exactly once, with no extra parameters.
Currencies are trimmed/uppercased; only INR is a supported target. Unknown
source currencies, negative/non-decimal amounts and malformed queries return
HTTP 400. Amounts must be **0–100000000**, with at most **eight fractional
digits**, no exponent notation, and at most 40 characters. Queries are capped
at 512 characters. The upper bound keeps converted paise safely inside int64.
Request contexts expire after two seconds; the server also has bounded
header/read/write/idle timeouts. No credentials or customer inputs are needed.
In the `demo-complete` fallback, conversion diagnostics include only the fixed
route `/convert`, never query strings, supplied amounts or currency values.
Unknown source currencies receive the stable public message
`"Unsupported source currency."`, with no internal lookup details.

Revised main uses safe client errors and does not log raw query strings.
The review exercise is isolated non-serving text in
`tests\fixtures\go-review-example.txt` at repository root; never copy its
defects into handlers. The original `demo-baseline` tag is historical unsafe
code, not a runnable/deployable fallback.

## Container

Only the developer builds/runs with an approved runtime: automatic `wslc` first, `docker`
only if `wslc` is absent, never after a failing or policy-blocked WSL operation.
Docker Desktop is a commented optional, licence-reviewed choice:

The shared repository launcher accepts `-Runtime Auto|wslc|docker` (choose one
value) with `-Name go-fx-rates -Mode container`; explicit selection probes only
the approved runtime and never falls back. See [Setup](../../docs/SETUP.md).

```powershell
# From the repository root, explicit user-approved image restoration:
.\scripts\developer.ps1 -Action Restore -RestoreTarget ContainerImages -Sample Go -Runtime Auto -Confirm
# Separate launch uses the existing image, with --pull=never:
.\scripts\developer.ps1 -Action RunContainer -Sample Go -Runtime Auto
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod 'http://localhost:8080/convert?from=USD&to=INR&amount=100'
```

Wait for startup before calling `/health`. Use the launcher's `-Port` parameter
and reported endpoint for an override; Run never builds/pulls a missing image.
The explicit Restore image-build stage runs vet/tests and builds with
CGO disabled. The final distroless image runs as non-root UID/GID **65532**.
Its executable health check calls `/health` with a two-second HTTP timeout.
There are no external modules, so **no `go.sum` is needed**.

## Verification and provenance

This is **historical original-revision evidence**. In particular the original
Go tests were not executed; do not imply they passed or prove current
regressions/coverage/CI. This documentation revision ran no Go checks or deployment.

Primary metadata checked **7 November 2026** without downloading software:

| Component | Official source |
| --- | --- |
| Go 1.27.3 | [go.dev release JSON](https://go.dev/dl/?mode=json) reports `go1.27.3`, `stable: true`; the latest stable release, not a calendar inference. |
| Build image | [Official Go image](https://hub.docker.com/_/golang), manifest `https://registry-1.docker.io/v2/library/golang/manifests/1.27.3`: `sha256:e519d3b0a5b285e5aa53ab9eef02bc6bbb9cb04608389b743a136a9ce75f0d1e`. |
| Runtime image | [Official distroless project](https://github.com/GoogleContainerTools/distroless), manifest `https://gcr.io/v2/distroless/static-debian12/manifests/nonroot`: `sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab`. |

**NOT RUN on the build workstation:** `go vet ./...`, `go test ./...` and
`go build .`, because Go was absent and the user requested no tool/dependency
installation. The two test files cover exact rounding/formatting, currencies,
bounds, HTTP health/conversion/validation, cancellation and port overrides
using in-process `httptest` (no listener or external service).
The fallback adds two regression tests asserting that supplied query values
cannot appear in logs and unknown-currency responses cannot expose internal
diagnostics. These Go tests were **NOT RUN** for the same missing-runtime/user
installation boundary; source changes were statically inspected only.
Container builds/runs and live-server checks were also **NOT RUN**: execution
was prohibited and no approved container runtime was available. Registry
verification establishes image existence/digests, not a successful build.

For [existing AKS + ACR](../../docs/GITHUB-AKS.md), use shared application-only
manifests, current-main-SHA manual dispatch, same-run image digests and independent
approval. No sample provisions resources or uses customer credentials. Key Vault/
managed identity requires separate review if actual secrets become necessary.
