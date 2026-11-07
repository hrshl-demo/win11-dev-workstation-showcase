# Synthetic FX conversion

Go **1.27.3**, standard library only. Fixed rates to INR are **USD 88.00**,
**EUR 102.00** and **GBP 117.00**: synthetic demonstration values,
**not market data**. This service does not call banks or external rate providers.

## Test and run

From this directory, with your already-approved Go installation:

```powershell
go vet ./...
go test ./...
go run .
```

The default port is **8080**. Override it in this process:

```powershell
$env:PORT = '8081'
go run .
# After stopping with Ctrl+C:
Remove-Item Env:PORT
```

In another terminal (change the port when overridden):

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

## Container

Use an already-approved runtime, preferring `wslc`:

```powershell
$runtime = if (Get-Command wslc -ErrorAction SilentlyContinue) { 'wslc' } elseif (Get-Command docker -ErrorAction SilentlyContinue) { 'docker' } else { throw 'No approved container runtime is available.' }
Write-Host "Runtime: $runtime"
& $runtime build -t showcase-fx .
& $runtime run -d --name showcase-fx -p 8080:8080 showcase-fx
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod 'http://localhost:8080/convert?from=USD&to=INR&amount=100'
& $runtime stop showcase-fx
& $runtime rm showcase-fx
```

Wait for startup before calling `/health`. Use `-e PORT=8081 -p 8081:8081`
for a container port override. The build stage runs vet/tests and builds with
CGO disabled. The final distroless image runs as non-root UID/GID **65532**.
Its executable health check calls `/health` with a two-second HTTP timeout.
There are no external modules, so **no `go.sum` is needed**.

## Verification and provenance

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
Container builds/runs and live-server checks were also **NOT RUN**: execution
was prohibited and no approved container runtime was available. Registry
verification establishes image existence/digests, not a successful build.

For a future Azure integration, use environment configuration, Azure Key Vault
and managed identity; do not add credentials to this sample.
