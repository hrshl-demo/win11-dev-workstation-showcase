# Synthetic sample applications

These independent applications do not contact banks, move money or use
customer/market data. Each exposes `/health` and defaults to port 8080; run
sequentially or choose explicit ports.

Open the **repository root in VS Code**. Follow [Setup](../docs/SETUP.md) for the
fresh-approved versus already-configured routes, then choose the explicit
**Restore project dependencies** user task. Daily Test/Lint/Coverage tasks do
not install or restore missing prerequisites.

For orchestration instead of command copying, the human may select
**Workstation setup** in local VS Code Chat and approve its separate setup,
dependency Restore and local launch stages; see [selection and resume](../docs/SETUP.md#select-workstation-setup-in-vs-code).
This exception does not let coding/build/desktop/cloud agents acquire tools or
launch samples. The manual tasks and all no-restore daily guards are unchanged.

| Sample | Runtime | Focused developer tasks |
| --- | --- | --- |
| [EMI API](python-emi-api/README.md) | Python 3.14, FastAPI, uv | Test/Lint/Coverage Python: pytest, pytest-cov, Ruff |
| [IFSC format service](java-ifsc-service/README.md) | Java 25, Spring Boot 4.1.2, Maven wrapper | Test/Lint/Coverage Java: JUnit 5, JaCoCo, Checkstyle |
| [Synthetic FX conversion](go-fx-rates/README.md) | Go 1.27.3, standard library | Test/Lint/Coverage Go: built-in tests/coverage, vet |
| [Legacy payment service](java-legacy-upgrade/README.md) | Java 11, Spring Boot 2.7.18 | Test legacy Java (Java 11 opt-in); excluded from All/modern CI/deployment |

Use **Terminal → Run Task**, Testing, Run and Debug or integrated PowerShell.
F5 requires the approved interpreter/JDK/debugger and packages already present.
Reports and direct sample-directory commands are in the individual READMEs.
Historical provenance/test evidence is revision-specific, not current CI or
cloud acceptance.

Only the developer launches applications/containers, directly or through the
separately approved named local workflow. The shared launcher uses
`-Runtime Auto|wslc|docker`: Auto is WSL-first, Docker only when `wslc` is absent;
explicit selection probes only the approved runtime and never falls back on
denial. Docker Desktop remains a commented optional licensing choice. No sample
needs Compose or automatic Dev Container post-create installs.

Container image builds are a separately confirmed **Restore → ContainerImages**
target. RunContainer inspects existing local images and uses `--pull=never`;
missing images mean NOT RUN, never an implicit build/pull. Modern `All` image
restoration excludes PowerShell and the optional legacy image.

The revised Go service is safe; review defects only in non-serving
`tests\fixtures\go-review-example.txt`. The historical `demo-baseline` tag is
not runnable/deployable. Revised main is the safe baseline; `demo-complete`
retains the inspected EMI schedule fallback and shared existing-AKS delivery.

[Existing AKS + ACR](../docs/GITHUB-AKS.md) uses application-only manifests,
manual current-main-SHA dispatch, successful modern-service gates, same-run
immutable image digests and independent approval. No resource provisioning,
legacy deployment, public ingress or customer credentials. Use environment
configuration; any future real secrets require a reviewed Key Vault/identity design.
