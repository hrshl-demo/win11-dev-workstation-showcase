---
name: prepare-for-azure
description: Prepare Azure Container Apps infrastructure with managed identity and Key Vault using Azure skills, without deploying.
---
# Prepare for Azure

1. Read the application Dockerfile and architecture, and select GitHub Copilot for Azure's azure-prepare skill in the developer's VS Code session.
2. Plan azd preparation for the Python API with Container Apps, a user-assigned managed identity and an RBAC-enabled Key Vault. Use environment parameters for region and the application's built image; never fabricate an account, subscription, credentials or a secret.
3. Generate azure.yaml and Bicep plus parameter bindings. Keep secrets out of source and environment examples; use Key Vault and managed identity for actual secret retrieval.
4. Compile/validate the files locally if the developer has approved tooling. Describe all resources, roles, HTTPS ingress, cost implications and what still needs user values.
5. Do NOT run azd up, azd deploy, az deployment, terraform apply or Azure login. Do not create resources, push images or claim deployment.
6. If network/tooling is unavailable, inspect the committed demo-complete preparation and explain it without deploying.

Done: meaningful infrastructure and azd bindings exist, the application remains testable locally, and the developer has an explicit preparation-only handoff.
