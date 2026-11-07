# Bank engineering standards

- Use synthetic examples only. Never commit secrets or personal/customer data.
- Read configuration from environment variables locally; use Azure Key Vault and managed identity in Azure.
- Mask PAN, Aadhaar, mobile and account numbers before logging; do not log raw requests or query strings.
- Use Decimal, BigDecimal or exact integer/rational decimal arithmetic for money, never binary floating point. Choose explicit rounding; serialize money as fixed two-decimal strings and display INR with Indian lakh grouping.
- Validate all inputs at the edge with practical limits. Return safe client errors, not internal exceptions.
- Ship tests with every behavior change, including invalid inputs, health and rounding boundaries.
- Keep pull requests small; use conventional commits. Pin application dependencies and CI actions. Prefer Microsoft and established open-source libraries.
- The legacy Java sample is an explicit Java 11 / Spring Boot 2.7 instruction exception, retained for user-led modernization; do not upgrade it by hand. Apply Java 25 / Spring Boot 4 standards to the current IFSC sample.
- Preserve explicitly documented baseline demo exceptions until the presenter requests the relevant review workflow; they are not permission for additional standards violations.
- Agents never run workstation setup, repair, elevation, WSL updates or deployment. Read-only preflight and verification are allowed. Application/container launches are user-operated in this showcase.
