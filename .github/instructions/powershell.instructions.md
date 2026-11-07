---
applyTo: "**/*.ps1"
---
# PowerShell

Use approved verbs, comment-based help, CmdletBinding and StrictMode Latest; remain compatible with Windows PowerShell 5.1 and PowerShell 7.
Use SupportsShouldProcess and explicit confirmation for mutation. Respect organization policy; never bypass a zero policy value, runtime denial or elevation requirement.
Share policy, runtime and native exit checks through scripts/_common.psm1. Check native exit codes and produce clear PASS/WARN/FAIL output; JSON output must remain parseable.
Use PSScriptAnalyzer without errors and safe mocked tests. Agents never execute bootstrap or repair scripts, even with WhatIf, and never change machine setup.
