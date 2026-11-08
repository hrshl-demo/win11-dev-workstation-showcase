# IFSC format service

Java 25, Spring Boot **4.1.2**, Maven **3.9.16** and JUnit **5.14.4**.
All examples are synthetic. This service checks syntax, not bank/branch existence,
account ownership or payment eligibility. It holds no customer data and does not
call a bank or an external directory.

## Test and run

Open the repository root in **VS Code**. Choose **Terminal → Run Task** or use
the integrated PowerShell terminal:

```powershell
# Explicit human package restore:
.\scripts\developer.ps1 -Action Restore -Sample Java
# Daily checks, with restored wrapper/plugins/dependencies and Java 25:
.\scripts\developer.ps1 -Action Test -Sample Java
.\scripts\developer.ps1 -Action Lint -Sample Java
.\scripts\developer.ps1 -Action Coverage -Sample Java
```

The human may select [Workstation setup](../../docs/SETUP.md#select-workstation-setup-in-vs-code)
to orchestrate these separate approved stages in local VS Code. Other agents
still cannot Restore or launch; daily checks never acquire prerequisites.

JUnit 5/Surefire writes `target\surefire-reports\`; JaCoCo writes
`target\site\jacoco\index.html` and `jacoco.xml`. Maven Checkstyle provides the
configured lint rules. The Java pack's Test Runner supports Testing-view
run/debug with the approved Java 25 JDK. Missing prerequisites mean NOT RUN,
not automatic downloads. See [Setup](../../docs/SETUP.md).

From this directory, with a Java 25 JDK on `JAVA_HOME`:

```powershell
.\mvnw.cmd -o -B verify
# Separate, human-operated launch after explicit restoration:
.\mvnw.cmd -o -B spring-boot:run
```

On Linux/macOS the equivalent commands add the same offline `-o` switch.
The first wrapper invocation needs network access to
Maven Central; choose the explicit Restore task rather than allow daily commands
to download it. Offline verification requires its distribution and every plugin/
dependency already present. No global Maven installation is needed.
The original revision's `verify` ran **18 test
invocations across two JUnit 5 test files**, then creates `target/app.jar`.
The JUnit 5 override is intentional: Boot 4 otherwise manages JUnit 6.
Controller tests use current Spring MockMvc with standalone setup and real
constructor-injected service instances: Boot 4.1's SpringExtension requires
JUnit 6, so using its `@WebMvcTest` with JUnit 5 is not compatible.

The default port is **8080**. To override it for this process:

```powershell
$env:PORT = '8081'
java -jar .\target\app.jar
# After stopping with Ctrl+C:
Remove-Item Env:PORT
```

In another **VS Code integrated PowerShell terminal**:

```powershell
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8080/ifsc/abcd0123456
Invoke-RestMethod http://localhost:8080/ifsc/ABCD1123456
```

Use port 8081 in those URLs when overriding `PORT`.

## Contract

`GET /health` returns `{"status":"ok"}`. `GET /ifsc/{code}` trims surrounding
whitespace and uppercases using `Locale.ROOT`, then matches
`^[A-Z]{4}0[A-Z0-9]{6}$`. Both valid and invalid syntax return HTTP 200 because
the resource is a validation result:

```json
{
  "code": "ABCD0123456",
  "valid": true,
  "bankCode": "ABCD",
  "branchCode": "123456",
  "reason": "Valid IFSC format; bank and branch existence are not verified."
}
```

Invalid syntax has `valid: false`, `bankCode: null`, `branchCode: null`, the
normalized `code`, and a safe explanation in `reason`. `ABCD1123456` fails the
required fifth-character zero; `ABC0123456` fails the length. Missing path
segments are not validation requests and return HTTP 404.

## Container

The multi-stage Dockerfile executes the tests and uses digest-pinned official
Eclipse Temurin Java 25 JDK/JRE images. The final process runs as UID/GID 10001,
not root. No host setup, runtime installation or container execution is
performed by the sample itself.
The Docker health check runs `java -jar app.jar --healthcheck`: a two-second
standard-library HTTP probe of `/health`, not another Spring server.

From the repository root, only the developer restores images/runs, directly or
through the named local workflow after separate approvals, using an already-approved
runtime (automatic `wslc` first, `docker` only if `wslc` is absent; never switch after
a WSL failure/policy denial). Docker Desktop remains optional and licence-reviewed:

The shared repository launcher accepts `-Runtime Auto|wslc|docker` (choose one
value) with `-Name java-ifsc-service -Mode container`; explicit selection probes
only the approved runtime and never falls back. See [Setup](../../docs/SETUP.md).

```powershell
# From the repository root, explicit user-approved image restoration:
.\scripts\developer.ps1 -Action Restore -RestoreTarget ContainerImages -Sample Java -Runtime Auto -Confirm
# Separate launch uses the existing image, with --pull=never:
.\scripts\developer.ps1 -Action RunContainer -Sample Java -Runtime Auto
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8080/ifsc/ABCD0123456
```

Wait for startup before calling `/health`. Use the launcher's `-Port` parameter
and its reported endpoint for an override; run samples sequentially or use
distinct host ports. Run never builds or pulls a missing image.

## Verified provenance

Verified against the official endpoints on **7 November 2026**:

| Component | Primary source and selection |
| --- | --- |
| Spring Boot | [Maven Central metadata](https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-starter-parent/maven-metadata.xml): latest matching stable `4.x.y` is **4.1.2**. Metadata's `latest`/`release` is **4.2.0-RC2**, which is not GA and is deliberately excluded. |
| Java compatibility | [Boot 4.1.2 tagged requirements](https://github.com/spring-projects/spring-boot/blob/v4.1.2/documentation/spring-boot-docs/src/docs/antora/modules/ROOT/pages/system-requirements.adoc) supports Java 17 through 27, including 25; Maven 3.6.3 or later. |
| Maven | [Official 3.9.16 distribution](https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.zip), verified using its [published SHA-512](https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.zip.sha512); the SHA-256 derived from those verified bytes is pinned in wrapper properties. |
| Wrapper | Unmodified `mvnw`, `mvnw.cmd` and JAR from the [official Wrapper 3.3.4 bin distribution](https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper-distribution/3.3.4/maven-wrapper-distribution-3.3.4-bin.zip), authenticated over HTTPS and matched to its published `.sha1`. [Official wrapper JAR](https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar) also matched its published `.sha1`; its computed SHA-256 is pinned as `wrapperSha256Sum`. Central does not publish `.sha256` for these wrapper artifacts. |
| JUnit 5 | [JUnit Jupiter metadata](https://repo.maven.apache.org/maven2/org/junit/jupiter/junit-jupiter/maven-metadata.xml): **5.14.4**, explicitly pinned rather than silently adopting JUnit 6. |
| Microsoft image check | `https://mcr.microsoft.com/v2/openjdk/tags/list` returned **404**; no Microsoft OpenJDK 25 image could be verified, so the specified Temurin fallback is used. |
| Build image | [Official Temurin repository](https://hub.docker.com/_/eclipse-temurin), `25-jdk`; manifest verified at `https://registry-1.docker.io/v2/library/eclipse-temurin/manifests/25-jdk`, digest `sha256:83f4a7fc27df94dcc7b8de04d14cbbba8da14406f921e966969c3b09000aa507`. |
| Runtime image | Same official repository, `25-jre`; manifest verified at `https://registry-1.docker.io/v2/library/eclipse-temurin/manifests/25-jre`, digest `sha256:ecdc0adb37bde1a281c4d245a3cd535004b1fc8322d560f5b09463b248c81df0`. |

The release choices above reflect the actual retrieved environment data, not a
version inferred from a calendar. Wrapper distribution SHA-256:
`5af3b743dd8b876b5c45da33b676251e5f1687712644abb4ee519ca56e1d89ce`.
Wrapper JAR SHA-256:
`4e2fbf6554bc8a4702cdfdd3bef464f423393d784ddbb037216320ce55d5e4e1`.

## Validation on the build workstation

The following is **historical original-revision evidence**, not a claim about
the newly configured lint/coverage pipeline or current CI/AKS. This documentation
revision did not execute sample tests, restore packages, build containers or deploy.

`.\mvnw.cmd -B verify` passed on portable Temurin **25.0.5+8**: **18 tests,
zero failures, zero errors, zero skipped**; the executable JAR was packaged.
`JAVA_HOME`, `MAVEN_USER_HOME` and `MAVEN_OPTS` were set only in the validating
process to keep the JDK, wrapper distribution and Maven repository inside the
sample's ignored `.scratch/` and `.maven-user-home/` directories. No machine
configuration or global installation was changed.
After the user requested no further installations, the health-probe changes
were recompiled and the same 18 tests passed using existing tools only with
`.\mvnw.cmd -o -B -q verify`; `-o` disables Maven network restoration.

The portable JDK came from the [official Adoptium API](https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse)
and its linked official release archive; its SHA-256 was verified as
`636bdc13dc649ddc7d5921c5c7d23cca6e44fd19d662b45cc9c02135a6c96c42`.
Container build/run and live-server smoke commands were **NOT RUN**:
services/containers were outside the permitted execution scope, and neither
`wslc` nor `docker` was available. `/health` and the IFSC contract were verified
in-process with MockMvc instead. Linux `./mvnw` execution was not run on this
Windows host; the official shell launcher is stored with executable mode.

Do not add credentials. [Existing AKS + ACR](../../docs/GITHUB-AKS.md) uses shared
application-only manifests, manual current-main-SHA dispatch, immutable same-run
image digests and independent environment review. No sample provisions resources.
Use Key Vault/managed identity only if a later reviewed design requires secrets.
