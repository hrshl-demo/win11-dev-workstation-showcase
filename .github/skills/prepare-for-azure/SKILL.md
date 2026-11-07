---
name: prepare-for-azure
description: Prepare and review application manifests for an existing AKS cluster and ACR, without authentication, provisioning or deployment.
---
# Prepare for existing AKS

1. Read `docs\GITHUB-AKS.md`, `docs\ARCHITECTURE.md`, the chosen sample README/Dockerfile and the committed Kubernetes templates. Use already available official Azure documentation tools for reference only; do not query an account or authenticate.
2. Prepare application-only Deployment and ClusterIP Service manifests for the existing, IT-created restricted namespace. Preserve non-root containers, resource limits and health probes. No namespace, RBAC, registry, cluster, ingress, public LoadBalancer or infrastructure creation.
3. Require application image/namespace inputs; never invent values, use `latest`, supply placeholder images or pretend an image is published. Deployment consumes immutable digests from the same main-only workflow run. Report unset inputs.
4. Review separate OIDC build/deploy identities, exact federated subject matching, registry permissions, kubelet pull identity, namespace RBAC and private-API runner connectivity. IT owns configuration and role grants. Actual secrets, if ever needed, belong in Key Vault accessed through managed/workload identity, not source.
5. Validate only offline/static files with already installed tooling/dependencies. Do not fetch packages or tools. Distinguish static checks, missing prerequisites and unobserved live acceptance.
6. Never run Azure login, Actions dispatch, image build/push, `kubectl apply`, `az aks get-credentials`, azd deployment, ARM/Terraform provisioning or any service/container launch. Approval to edit files is not approval to execute them.
7. If blocked, inspect the reviewed existing-AKS files on revised `main`/`demo-complete` and provide a preparation-only handoff. Do not fall back to old Container Apps infrastructure or the historical unsafe tag.

Done: reviewable application files and a missing-input/validation summary, with no authentication, provisioning, package restoration or deployment.
