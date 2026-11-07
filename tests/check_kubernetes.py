"""Offline standard-library checks for the AKS templates; never contact a cluster."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check() -> None:
    document = json.loads((ROOT / "k8s" / "workloads.json").read_text())
    assert document["kind"] == "List"
    items = document["items"]
    assert len(items) == 6
    for item in items:
        name = item["metadata"]["name"]
        assert name in {"emi", "ifsc", "fx"}
        assert item["metadata"]["namespace"] == "${AKS_NAMESPACE}"
        if item["kind"] == "Service":
            assert item["spec"]["type"] == "ClusterIP"
            assert item["spec"]["selector"] == {"app": name}
            continue
        assert item["kind"] == "Deployment"
        assert item["spec"]["replicas"] == 2
        pod = item["spec"]["template"]["spec"]
        assert pod["automountServiceAccountToken"] is False
        assert pod["securityContext"]["runAsNonRoot"] is True
        assert pod["securityContext"]["seccompProfile"]["type"] == "RuntimeDefault"
        assert not any(pod.get(key) for key in ("hostNetwork", "hostPID", "hostIPC"))
        assert len(pod["containers"]) == 1
        container = pod["containers"][0]
        assert container["image"] == "${" + name.upper() + "_IMAGE}"
        security = container["securityContext"]
        assert security["runAsNonRoot"] is True
        assert security["allowPrivilegeEscalation"] is False
        assert security["readOnlyRootFilesystem"] is True
        assert security["capabilities"]["drop"] == ["ALL"]
        for bound in ("requests", "limits"):
            assert set(container["resources"][bound]) == {"cpu", "memory"}
        for probe in ("startupProbe", "readinessProbe", "livenessProbe"):
            assert container[probe]["httpGet"] == {"path": "/health", "port": "http"}
        if name == "ifsc":
            assert container["volumeMounts"] == [{"name": "java-tmp", "mountPath": "/tmp"}]
            assert pod["volumes"] == [{"name": "java-tmp", "emptyDir": {"sizeLimit": "64Mi"}}]
        else:
            assert not pod.get("volumes")
    assert {(item["kind"], item["metadata"]["name"]) for item in items} == {
        (kind, name) for kind in ("Deployment", "Service") for name in ("emi", "ifsc", "fx")
    }


if __name__ == "__main__":
    try:
        check()
    except (AssertionError, KeyError, ValueError) as error:
        print(f"FAIL AKS template invariants: {error}", file=sys.stderr)
        sys.exit(1)
    print("PASS AKS restricted deployments, private services, probes and bounded resources")
