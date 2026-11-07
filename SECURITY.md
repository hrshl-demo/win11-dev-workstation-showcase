# Security policy

## Scope

This community showcase is for synthetic-data development demonstrations. No production support or security certification is implied. Use an IT-approved device, accounts, networks and container registries. The documented demo exceptions are narrowly scoped exercises, not permission to weaken other code or enterprise controls.

## Safe use

- Never put credentials, real account numbers, PAN, Aadhaar, mobile numbers or personal data in source, prompts, tests, screenshots or logs.
- Use environment variables for local configuration. In Azure, design for managed identity and [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview); do not embed credentials in generated files.
- Review downloaded code. Bootstrap must reject an invalid signature or a signer that is not Microsoft Corporation. HTTPS alone is not publisher verification. Never bypass execution policy or organisation policy.
- Setup, repair, uninstall and reset can change the device or destroy data. Review their help and dry-run output; a human owns execution and confirmation.
- Containers and cloud resources are not launched by default. Inspect images, generated infrastructure and permissions before approving any execution.

## Reporting

Report vulnerabilities privately through the repository's **Security → Report a vulnerability** option if enabled. If unavailable, contact repository maintainers privately through their published GitHub contact channels; do not disclose exploitation details in a public issue. Provide the affected revision, impact and a minimal synthetic-data reproduction. Remove tokens and identifying data from attachments.

For issues in upstream products, use their publisher's security reporting process rather than this repository. If a credential is exposed, revoke it immediately through its issuer before cleaning up files or history.
