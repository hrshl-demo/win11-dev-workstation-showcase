# Synthetic INR EMI API

FastAPI on **Python 3.14**, with uv-managed, hash-locked dependencies.
Examples are synthetic loan calculations, not lending advice or a banking
integration. No customer data, account details or credentials are required.

## Test and run

From this directory, after you have installed your approved Python/uv tools:

```powershell
uv run pytest
uv run uvicorn app.main:app --host 127.0.0.1 --port 8080
```

uv uses `.python-version` **3.14**. Its first invocation may restore project
dependencies; the repository creation process does not install them.
The module entry point also defaults to 8080 and reads `PORT`:

```powershell
$env:PORT = '8081'
uv run python -m app.main
# After stopping with Ctrl+C:
Remove-Item Env:PORT
```

For uvicorn's CLI, override `--port` rather than `PORT`. In another terminal:

```powershell
Invoke-RestMethod http://localhost:8080/health
$loan = @{ principal = '2500000'; annual_rate_percent = '8.5'; tenure_months = 240 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8080/emi -ContentType 'application/json' -Body $loan
```

Change the URLs to 8081 when using that override. OpenAPI is available at
`/openapi.json` and interactive API documentation at `/docs`.

## Contract and rounding

`GET /health` returns `{"status":"ok"}`. `POST /emi` accepts:

```json
{"principal":"2500000","annual_rate_percent":"8.5","tenure_months":240}
```

Principal and rate may also be JSON numeric literals. The edge parser uses
`json.loads(parse_float=Decimal)` **before FastAPI/Pydantic validation**;
numeric literals never pass through binary floating-point. High-precision
decimal strings and literals produce identical results. Monetary response
fields are always fixed **two-decimal JSON strings**:

```json
{
  "emi": "21695.58",
  "total_payment": "5206939.20",
  "total_interest": "2706939.20",
  "emi_inr": "₹21,695.58",
  "total_payment_inr": "₹52,06,939.20",
  "total_interest_inr": "₹27,06,939.20"
}
```

Input bounds: principal **>0 and ≤₹10,00,00,000**, annual rate **>0 and ≤36%**,
and integer tenure **1–480 months**. Decimal inputs have at most 18 fractional
digits and 64 text characters. Unknown fields, non-finite numbers and boolean
amounts are rejected. JSON bodies are limited to 4096 bytes; duplicate JSON
properties are rejected. Validation errors are HTTP 422 with a safe, stable
message; malformed JSON is 400, oversized bodies 413 and wrong content types
415. Client responses never echo input values or internal exceptions.

All EMI calculations use a **local Decimal precision of 50**. Monthly rate is
annual percentage divided by 1200. EMI is rounded **ROUND_HALF_UP** to two
decimals; total payment is that **rounded EMI × months**, and total interest
is total payment minus principal, rounded HALF_UP. At extremely small rates
or principals, this prescribed rounded-payment convention can produce slightly
negative displayed interest; it is not silently clamped or recalculated from
an unrounded EMI. `format_inr` uses Indian lakh/crore grouping.

Structured JSON logs include timestamp, level, logger and message. A masking
filter removes synthetic PAN, Aadhaar, mobile and 9–18-digit account patterns
from formatted messages; the formatter also masks exception text. Tests use
only fabricated placeholders, not actual identifiers.

## Container and VS Code

Use your already-approved runtime, preferring `wslc`:

```powershell
$runtime = if (Get-Command wslc -ErrorAction SilentlyContinue) { 'wslc' } elseif (Get-Command docker -ErrorAction SilentlyContinue) { 'docker' } else { throw 'No approved container runtime is available.' }
Write-Host "Runtime: $runtime"
& $runtime build -t showcase-emi .
& $runtime run -d --name showcase-emi -p 8080:8080 showcase-emi
Invoke-RestMethod http://localhost:8080/health
& $runtime stop showcase-emi
& $runtime rm showcase-emi
```

Wait for startup before calling `/health`; send the example EMI request above.
Use `-e PORT=8081 -p 8081:8081` for a container port override.
The multi-stage slim-Python Dockerfile restores locked dependencies using uv,
runs tests, removes development dependencies, and runs as non-root UID/GID
**10001**. Its health check uses the image's Python standard library.

Open this **sample directory** in VS Code and select **Dev Containers: Reopen
in Container** to use `.devcontainer/devcontainer.json`. The official MCR Python
image runs the editor as `vscode`; there are **no features, Compose files or
automatic post-create installation commands**. Run `uv run pytest` from the
sample root after arranging an approved uv installation in that environment.

## Verification and provenance

Primary metadata checked **7 November 2026**, without downloading Python
packages or container layers:

| Component | Official source |
| --- | --- |
| Locked packages | [PyPI JSON metadata](https://pypi.org/pypi/pydantic/2.12.4/json), with artifact URLs, sizes and SHA-256 hashes recorded in `uv.lock`; FastAPI 0.118.0, Pydantic 2.12.4, uvicorn 0.37.0, pytest 8.3.4 and HTTPX 0.28.1 are pinned. |
| Python 3.14 support | [Pydantic Core 2.41.5 metadata](https://pypi.org/pypi/pydantic-core/2.41.5/json) supplies CPython 3.14 wheels, including Windows x64/ARM64 and Linux x64/ARM64; the lock also contains macOS wheels and source archives. |
| Python image | [Official Python image](https://hub.docker.com/_/python), manifest `https://registry-1.docker.io/v2/library/python/manifests/3.14-slim`: `sha256:af8a5aa14780025dbfbcfbc81bd8a91ebd87711dd5b0f48ed71090949dd7cb1d`. |
| uv image | [Official uv container documentation](https://docs.astral.sh/uv/guides/integration/docker/), manifest `https://ghcr.io/v2/astral-sh/uv/manifests/0.9.17`: `sha256:5cb6b54d2bc3fe2eb9a8483db958a0b9eebf9edff68adedb369df8e7b98711a2`. |
| Dev Container image | [Official Dev Container images](https://github.com/devcontainers/images/tree/main/src/python), manifest `https://mcr.microsoft.com/v2/devcontainers/python/manifests/3.14`: `sha256:66a39503cd5b53c94a57b9a235c6c9371ccf17bafd9c90369e566f638a05ac89`. |

On the build workstation, **`python -m pytest -q` passed 58 test invocations**
using the **already-installed Python 3.12**, FastAPI 0.118.0, Pydantic **2.11.10**
and existing dependencies. No installation/restoration was performed.
These checks validate application behaviour, **not the pinned Python 3.14
environment**. `uv run pytest`, locked dependency synchronization, Python 3.14
execution, container build/run and live-server commands were **NOT RUN**:
Python 3.14/the pinned environment and an approved container runtime were
unavailable, and the user requested no installations or service/container
launches. In-process FastAPI TestClient checked health, precision, OpenAPI and
validation. Four test files cover EMI examples, INR grouping, API contracts
and PII-safe JSON logging.
`uv export --frozen --offline --no-python-downloads --format requirements-txt
--no-emit-project` also passed without synchronization. All 20 locked packages'
artifact URLs, sizes and hashes and their Python 3.14 dependency graphs were
checked against PyPI JSON metadata for Windows, Linux and macOS; no package
archives were downloaded.

For a future Azure integration, use environment configuration, Azure Key Vault
and managed identity. Do not add secrets or an amortisation schedule to this
baseline.
