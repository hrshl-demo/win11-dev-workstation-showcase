# Bank engineering standards

- Use synthetic examples only. Never commit secrets or personal/customer data.
- Read configuration from environment variables locally; use Azure Key Vault and managed identity in Azure.
- Mask PAN, Aadhaar, mobile and account numbers before logging; do not log raw requests or query strings.
- Use Decimal, BigDecimal or exact integer/rational decimal arithmetic for money, never binary floating point. Choose explicit rounding; serialize money as fixed two-decimal strings and display INR with Indian lakh grouping.
- Validate all inputs at the edge with practical limits. Return safe client errors, not internal exceptions.
- Ship tests with every behavior change, including invalid inputs, health and rounding boundaries.
- Keep pull requests small; use conventional commits. Pin application dependencies and CI actions. Prefer Microsoft and established open-source libraries.
- The legacy Java sample is an explicit Java 11 / Spring Boot 2.7 instruction exception, retained for user-led modernization; do not upgrade it by hand. Apply Java 25 / Spring Boot 4 standards to the current IFSC sample.
- Revised main has no Go serving-code exceptions. Review the non-serving `tests\fixtures\go-review-example.txt` without applying its defects to live code. The historical `demo-baseline` tag is unsafe and must not be launched or deployed; retain legacy Java only for its explicitly requested modernization exercise.
- Agents never run workstation setup, repair, elevation, WSL updates or deployment. Read-only preflight and verification are allowed. Application/container launches are user-operated in this showcase.
- Separate setup once, explicit human package Restore, daily no-restore tests/lint/coverage, GitHub review and manual existing-AKS deployment. Report missing prerequisites as NOT RUN; never install to make a check pass.
- Local image builds require explicit confirmed RestoreTarget ContainerImages. RunContainer inspects an existing image and uses --pull=never; never hide package/image restoration in Run, F5 or daily checks.
- AKS preparation is files-only for an existing cluster/ACR, with required image inputs and no placeholder defaults. Never provision, authenticate, publish images or dispatch Actions. Deployment must use trusted main, current source SHA, independent environment approval and same-run image digests; unavailable/unverifiable approval gates fail closed.
