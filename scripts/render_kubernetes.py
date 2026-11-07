"""Render only digest-pinned images into the existing-namespace AKS template."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGE_KEYS = {"emi": "EMI_IMAGE", "ifsc": "IFSC_IMAGE", "fx": "FX_IMAGE"}


def render(values: dict[str, str]) -> dict:
    namespace = values.get("AKS_NAMESPACE", "")
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", namespace):
        raise ValueError("AKS_NAMESPACE must be a nonempty Kubernetes DNS label.")
    registry = values.get("ACR_LOGIN_SERVER", "")
    if not re.fullmatch(r"[a-z0-9.-]+\.azurecr\.io", registry):
        raise ValueError("ACR_LOGIN_SERVER must be the verified existing ACR login server.")
    document = json.loads((ROOT / "k8s" / "workloads.json").read_text())
    for item in document["items"]:
        item["metadata"]["namespace"] = namespace
        if item["kind"] == "Deployment":
            name = item["metadata"]["name"]
            image = values.get(IMAGE_KEYS[name], "")
            expected = re.escape(f"{registry}/showcase/{name}@sha256:")
            if not re.fullmatch(expected + r"[a-f0-9]{64}", image):
                raise ValueError(f"{IMAGE_KEYS[name]} must pin the same-run ACR image digest.")
            item["spec"]["template"]["spec"]["containers"][0]["image"] = image
    return document


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        document = render(dict(os.environ))
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n")


if __name__ == "__main__":
    main()
