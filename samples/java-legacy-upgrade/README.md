# Legacy synthetic payment service

Kept old on purpose for the GitHub Copilot modernization demo. Do not upgrade by hand.

**Explicit legacy exception:** this sample deliberately uses Java **11** and
Spring Boot **2.7.18**, not the modern Java/Spring Boot standard. It is excluded
from the normal CI sample matrix. The old framework is a modernization exercise,
not a production recommendation; do not deploy it as a real banking service.

The single business endpoint simulates an INR payment with synthetic account
aliases and IFSC codes. No money moves, no bank is contacted, no customer data
is stored and no request payload is logged.

## Test and run

From this directory, with a Java **11** JDK on `JAVA_HOME`:

```powershell
.\mvnw.cmd -B verify
.\mvnw.cmd -B spring-boot:run
```

Linux/macOS equivalents: `./mvnw -B verify` and
`./mvnw -B spring-boot:run`. Maven 3.9.16 is supplied by the official wrapper;
its first invocation needs Maven Central network access. `verify` runs
**29 test invocations across two JUnit 5 test files** and creates `target/app.jar`.

Default port: **8080**. Override only in your current terminal:

```powershell
$env:PORT = '8081'
java -jar .\target\app.jar
# After stopping with Ctrl+C:
Remove-Item Env:PORT
```

In another terminal (replace 8080 with 8081 if overridden):

```powershell
Invoke-RestMethod http://localhost:8080/health
$payment = @{ sourceAccount = 'SYN-ACCOUNT-001'; beneficiaryIfsc = 'ABCD0123456'; amount = 250000.00 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8080/payments -ContentType 'application/json' -Body $payment
```

`GET /health` returns `{"status":"ok"}`. `POST /payments` accepts:

```json
{"sourceAccount":"SYN-ACCOUNT-001","beneficiaryIfsc":"ABCD0123456","amount":250000.00}
```

The HTTP 200 result includes a generated `SYN-` reference, `status: "SIMULATED"`,
`currency: "INR"`, `amount: 250000.00`, `fee: 50.00`,
`totalDebit: 250050.00`, and `amountInr`, `feeInr`, `totalDebitInr` using Indian
digit grouping (for example `₹2,50,050.00`). Synthetic fees are **0.1%**, capped
at **₹50.00** and rounded using `BigDecimal` and `HALF_UP`. Amounts must be
between ₹0.01 and ₹1,00,00,000.00 with at most two fractional digits.
Source aliases must match `SYN-ACCOUNT-` followed by exactly three digits.
Beneficiary IFSC syntax must match `^[A-Z]{4}0[A-Z0-9]{6}$` (uppercase only).
Malformed JSON, missing fields and invalid inputs return HTTP 400 with
`{"reason":"Invalid synthetic payment request."}`. No internal exception or
validation detail is disclosed. Repeated calls simulate separate requests;
this is not an idempotent payment processing system.

## Container

Only run these commands with an already-approved runtime, from this directory:

```powershell
$runtime = if (Get-Command wslc -ErrorAction SilentlyContinue) { 'wslc' } elseif (Get-Command docker -ErrorAction SilentlyContinue) { 'docker' } else { throw 'No approved container runtime is available.' }
Write-Host "Runtime: $runtime"
& $runtime build -t showcase-legacy .
& $runtime run -d --name showcase-legacy -p 8080:8080 showcase-legacy
Invoke-RestMethod http://localhost:8080/health
$payment = @{ sourceAccount = 'SYN-ACCOUNT-001'; beneficiaryIfsc = 'ABCD0123456'; amount = 1005.00 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8080/payments -ContentType 'application/json' -Body $payment
& $runtime stop showcase-legacy
& $runtime rm showcase-legacy
```

Wait for startup before calling `/health`. For a container port override use
`-e PORT=8081 -p 8081:8081`. Do not run both samples on host port 8080
simultaneously. The multi-stage Dockerfile runs the tests on Java 11 and the
final JRE runs as non-root UID/GID 10001. Images are digest-pinned.
Its health check runs `java -jar app.jar --healthcheck`, a two-second Java
standard-library HTTP probe that does not start another server.

## Verified provenance

Verified on **7 November 2026**, from official primary endpoints:

- [Spring Boot 2.7.18 parent](https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-starter-parent/2.7.18/spring-boot-starter-parent-2.7.18.pom):
  intentionally retained legacy framework.
- [Maven 3.9.16 ZIP](https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.zip):
  matched its published `.sha512`; derived distribution SHA-256 is
  `5af3b743dd8b876b5c45da33b676251e5f1687712644abb4ee519ca56e1d89ce`.
- [Official Maven Wrapper 3.3.4 bin ZIP](https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper-distribution/3.3.4/maven-wrapper-distribution-3.3.4-bin.zip):
  launchers and JAR restored unmodified; ZIP and
  [official wrapper JAR](https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar)
  matched their published `.sha1` over authenticated HTTPS. Central has no
  `.sha256` for these artifacts; the SHA-256 of the verified JAR is
  `4e2fbf6554bc8a4702cdfdd3bef464f423393d784ddbb037216320ce55d5e4e1`,
  pinned in `.mvn/wrapper/maven-wrapper.properties` alongside the Maven checksum.
- [Official Eclipse Temurin images](https://hub.docker.com/_/eclipse-temurin):
  `11-jdk` manifest at
  `https://registry-1.docker.io/v2/library/eclipse-temurin/manifests/11-jdk`
  returned `sha256:810d03ef723872693a38e5c1367cc88a0bee58edcf06a2ab868ccc048888db73`;
  `11-jre` at
  `https://registry-1.docker.io/v2/library/eclipse-temurin/manifests/11-jre`
  returned `sha256:5dd0f12260b837ce636299e4fc0a10c7c70ed879d1f162470da6badd6f8f733d`.

## Validation on the build workstation

`.\mvnw.cmd -B verify` passed on portable Temurin **11.0.32.1+1**: **29 tests,
zero failures, zero errors, zero skipped**; the executable JAR was packaged.
`JAVA_HOME`, `MAVEN_USER_HOME` and `MAVEN_OPTS` were scoped to the validating
process. The Java 11 JDK was restored into the sibling IFSC sample's ignored
`.scratch/` directory and Maven downloads were scoped to this sample's ignored
`.maven-user-home/`. No machine setup or global installation was changed.
After the user prohibited further installations, `.\mvnw.cmd -o -B -q verify`
recompiled the health-probe changes and passed the same 29 tests using the
existing portable JDK/cache only; `-o` disables Maven network restoration.

The JDK came from the [official Adoptium API](https://api.adoptium.net/v3/assets/latest/11/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse)
and its linked official release archive; SHA-256 was verified as
`d5008f02174c1ad21c10407cbf104815cb390ec4c263d53946e8d0507d7a77f9`.
Container and live-server commands were **NOT RUN**: services/containers were
not permitted and neither `wslc` nor `docker` was available. MockMvc verified
`/health`, the payment contract and safe validation errors in-process. The
official Linux shell wrapper was not executed on this Windows host; its
executable mode is preserved.

No credentials belong in this sample. For later Azure integration use
environment configuration, Azure Key Vault and managed identity.
