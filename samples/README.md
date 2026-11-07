# Banking sample applications

These independent, synthetic applications illustrate a governed developer
workflow. They do not contact banks, move money or use market/customer data.
Each defaults to port **8080** and exposes `GET /health`; run them sequentially,
or use the per-sample `PORT` override to avoid conflicts.

| Sample | Runtime | Checks from its directory |
| --- | --- | --- |
| [EMI API](python-emi-api/README.md) | Python 3.14, FastAPI, uv | `uv run pytest` |
| [IFSC format service](java-ifsc-service/README.md) | Java 25, Spring Boot 4.1.2, official Maven wrapper | `.\mvnw.cmd -B verify` |
| [Synthetic FX conversion](go-fx-rates/README.md) | Go 1.27.3, standard library | `go vet ./...`; `go test ./...` |
| [Legacy payment service](java-legacy-upgrade/README.md) | Java 11, Spring Boot 2.7.18 | `.\mvnw.cmd -B verify` |

The legacy runtime/framework is an explicit modernization-demo exception and
is excluded from normal CI. Do not deploy these samples as banking systems.
See each README for input contracts, test cases, container commands and
verified image/version provenance.

Use only tools already approved and installed by your organisation. The sample
commands are for the developer to run; repository creation does not perform
machine setup. A first `uv` or Maven invocation may restore project dependencies.
Container examples prefer `wslc`, fall back to `docker`, and require an
already-approved runtime. No sample uses Compose or Dev Container features.

Never put credentials or personal data here. Use environment configuration
locally; a future Azure integration should use Azure Key Vault and managed
identity. The baseline has no amortisation schedule or Azure deployment files.
