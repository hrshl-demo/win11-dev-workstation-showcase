"""Fail closed before OIDC unless trusted source, targets and reviewer gate are valid."""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.request

REPOSITORY = "hrshl-demo/win11-dev-workstation-showcase"
ENVIRONMENT = "aks-demo"


def validate_targets(values: dict[str, str]) -> None:
    for key in ("AZURE_BUILD_CLIENT_ID", "AZURE_DEPLOY_CLIENT_ID",
                "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID"):
        if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
                            values.get(key, "")):
            raise ValueError(f"Set {key} to the human-approved target GUID.")
    if values["AZURE_BUILD_CLIENT_ID"] == values["AZURE_DEPLOY_CLIENT_ID"]:
        raise ValueError("Use separate registry-build and namespace-deploy identities.")
    patterns = {
        "ACR_NAME": r"[a-zA-Z0-9]{5,50}",
        "AKS_RESOURCE_GROUP": r"[a-zA-Z0-9_()-][a-zA-Z0-9_().()-]{0,89}",
        "AKS_CLUSTER_NAME": r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}",
        "AKS_NAMESPACE": r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
    }
    for key, pattern in patterns.items():
        if not re.fullmatch(pattern, values.get(key, "")):
            raise ValueError(f"Set a valid required {key}; no default target is supplied.")
    for key in ("AKS_RUNNER_LABELS_JSON", "ACR_RUNNER_LABELS_JSON"):
        if key == "ACR_RUNNER_LABELS_JSON" and not values.get(key):
            continue
        try:
            labels = json.loads(values.get(key, ""))
        except json.JSONDecodeError as error:
            raise ValueError(f"{key} must be an approved Linux runner-label JSON array.") from error
        if (not isinstance(labels, list) or not labels or len(labels) > 8
                or any(not isinstance(label, str) or not re.fullmatch(r"[\w.-]{1,80}", label)
                       for label in labels)
                or not (any(label.startswith("ubuntu-") for label in labels)
                        or ("self-hosted" in labels and any(label.lower() == "linux" for label in labels)))):
            raise ValueError(f"{key} must select an approved Linux runner.")


def validate_source(values: dict[str, str], current_main: str) -> None:
    sha = values.get("GITHUB_SHA", "")
    if (values.get("GITHUB_REPOSITORY") != REPOSITORY
            or values.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or values.get("GITHUB_REF") != "refs/heads/main"
            or not re.fullmatch(r"[0-9a-f]{40}", sha)
            or values.get("SOURCE_SHA") != sha
            or current_main != sha):
        raise ValueError("Dispatch only this repository's current main with its exact source_sha.")


def validate_gate(environment: dict, policies: dict) -> None:
    reviewers = [rule for rule in environment.get("protection_rules", [])
                 if rule.get("type") == "required_reviewers"]
    if (len(reviewers) != 1 or not reviewers[0].get("reviewers")
            or reviewers[0].get("prevent_self_review") is not True
            or environment.get("can_admins_bypass") is not False):
        raise ValueError("aks-demo requires reviewers, no self-review and no admin bypass. "
                         "Private-repository plan support is mandatory; deployment is blocked.")
    policy = environment.get("deployment_branch_policy") or {}
    if policy.get("custom_branch_policies") is not True:
        raise ValueError("aks-demo must restrict deployments to the selected main branch.")
    branches = policies.get("branch_policies", [])
    if len(branches) != 1 or branches[0].get("name") != "main" or branches[0].get("type") != "branch":
        raise ValueError("aks-demo must allow only branch main, with no tag/wildcard policies.")


def github(path: str) -> dict:
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        raise ValueError("A read-only GitHub token is required to verify live approval protection.")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPOSITORY}/{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise ValueError(f"GitHub governance read failed (HTTP {error.code}); no Azure login allowed.") from error
    except urllib.error.URLError as error:
        raise ValueError("GitHub governance read unavailable; no Azure login allowed.") from error


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        values = dict(os.environ)
        validate_targets(values)
        validate_source(values, github("git/ref/heads/main")["object"]["sha"])
        validate_gate(github(f"environments/{ENVIRONMENT}"),
                      github(f"environments/{ENVIRONMENT}/deployment-branch-policies"))
    except (ValueError, KeyError) as error:
        parser.error(str(error))
    print("PASS trusted source, explicit targets and live independent approval protection")


if __name__ == "__main__":
    main()
