---
name: containerise-and-run
description: Guide a developer through building a sample with the approved container runtime and checking health and a real request.
---
# Containerise and run

1. Read the sample README and scripts/run-sample.ps1. Confirm the developer has explicitly elected to launch the demo; agents preparing this repository must not launch it.
2. Have the developer run `.\scripts\run-sample.ps1 -Name python-emi-api -Mode container -Port 8080` (or one of its other supported names).
3. Prefer wslc; Docker is allowed only when wslc is absent and already licensed/approved. Stop on policy or runtime permission errors, never fallback to evade them.
4. Wait for the script's real /health success. In VS Code, use the integrated browser to open the printed URL and /docs for Python.
5. Send the sample's documented synthetic request and compare it to the expected exact money or IFSC output. Do not put real data in requests or logs.
6. Report the chosen runtime and verified response. Follow the documented reset procedure only with the developer's confirmation.

Done: developer-observed health and real response succeed, no secrets or elevated/privileged container options are used. Missing runtimes are a blocker, not a passing check.
