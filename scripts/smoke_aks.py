"""Workflow-only smoke requests through loopback port-forward; never expose ingress."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def check_service(namespace: str, service: str) -> None:
    with tempfile.TemporaryFile(mode="w+") as output:
        process = subprocess.Popen(
            ["kubectl", "--namespace", namespace, "port-forward", "--address", "127.0.0.1",
             f"service/{service}", ":8080"],
            stdout=output, stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 60
            port = None
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"{service} port-forward failed; check approved runner network/RBAC.")
                output.seek(0)
                match = re.search(r"Forwarding from 127\.0\.0\.1:(\d+) ->", output.read())
                if match:
                    port = int(match.group(1))
                    break
                time.sleep(1)
            if port is None:
                raise RuntimeError(f"{service} port-forward readiness timed out.")
            base = f"http://127.0.0.1:{port}"
            with urllib.request.urlopen(base + "/health", timeout=5) as response:
                if json.load(response).get("status") != "ok":
                    raise RuntimeError(f"{service} health response is invalid.")
            if service == "emi":
                request = urllib.request.Request(
                    base + "/emi",
                    data=json.dumps({"principal": "100000", "annual_rate_percent": "12",
                                     "tenure_months": 12}).encode(),
                    headers={"Content-Type": "application/json"},
                )
                with urllib.request.urlopen(request, timeout=5) as response:
                    if not re.fullmatch(r"\d+\.\d{2}", json.load(response).get("emi", "")):
                        raise RuntimeError("EMI smoke response must have fixed-two-decimal money.")
            elif service == "ifsc":
                with urllib.request.urlopen(base + "/ifsc/DEMO0000001", timeout=5) as response:
                    if json.load(response).get("valid") is not True:
                        raise RuntimeError("IFSC synthetic format smoke check failed.")
            else:
                with urllib.request.urlopen(base + "/convert?from=USD&to=INR&amount=100", timeout=5) as response:
                    if json.load(response).get("converted_amount") != "8800.00":
                        raise RuntimeError("FX exact-money smoke check failed.")
            print(f"PASS {service} loopback health and synthetic request")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def main() -> None:
    namespace = os.environ.get("AKS_NAMESPACE", "")
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", namespace):
        raise SystemExit("Set a valid explicit AKS_NAMESPACE.")
    try:
        for service in ("emi", "ifsc", "fx"):
            check_service(namespace, service)
    except (RuntimeError, OSError, ValueError, urllib.error.URLError) as error:
        raise SystemExit(f"AKS smoke checks failed: {error}") from error


if __name__ == "__main__":
    main()
