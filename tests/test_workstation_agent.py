"""Static local-agent contracts; never execute setup, Restore or sample recipes.

Existing Pester fixtures exercise the reused dispatcher's actual mutation gates.
Neither these checks nor those fixtures prove live VS Code/model adherence.
"""

from __future__ import annotations

import ast
import json
import re
import shlex
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENT = ROOT / ".github" / "agents" / "workstation-setup.agent.md"
DEFAULT_MODULES = {"Core", "Python", "Java", "Go", "Extensions"}
DEFAULT_SAMPLES = {"Python", "Java", "Go"}
FLAGS = {"Confirm", "Json", "ExtensionSourceApproved"}


def agent_text() -> str:
    return AGENT.read_text(encoding="utf-8")


def recipes() -> list[list[str]]:
    return [
        [token[1:-1] if token[:1] == token[-1:] and token[:1] in "'\"" else token
         for token in shlex.split(line, posix=False)]
        for fence in re.findall(r"```powershell\n(.*?)\n```", agent_text(), re.S)
        for line in fence.splitlines()
        if line.strip()
    ]


def parameters(tokens: list[str]) -> dict[str, str | bool]:
    result: dict[str, str | bool] = {}
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if not re.fullmatch(r"-[A-Za-z]+", token):
            raise ValueError(f"Unexpected recipe token: {token}")
        name = token[1:]
        if name in result:
            raise ValueError(f"Duplicate recipe parameter: {name}")
        if name in FLAGS:
            result[name] = True
            index += 1
        else:
            if index + 1 >= len(tokens):
                raise ValueError(f"Missing recipe argument: {name}")
            result[name] = tokens[index + 1]
            index += 2
    return result


def dispatcher_recipes() -> list[dict[str, str | bool]]:
    return [
        parameters(tokens[4:]) for tokens in recipes()
        if tokens[:4] == [
            "powershell.exe", "-NoProfile", "-File", r".\scripts\developer.ps1"
        ]
    ]


def task_parameters(label: str) -> dict[str, str | bool]:
    tasks = json.loads((ROOT / ".vscode" / "tasks.json").read_text(encoding="utf-8"))
    defaults = {item["id"]: item.get("default", "") for item in tasks["inputs"]}
    task = next(item for item in tasks["tasks"] if item["label"] == label)
    tokens = [
        re.sub(r"\$\{input:([^}]+)\}", lambda match: defaults[match[1]], token)
        for token in task["args"][3:]
    ]
    return parameters(tokens)


class WorkstationAgentTests(unittest.TestCase):
    def test_native_frontmatter_has_only_shared_least_privilege_fields(self) -> None:
        header, _ = agent_text()[4:].split("\n---\n", 1)
        pairs = [line.split(":", 1) for line in header.splitlines()]
        self.assertEqual(len(pairs), len({key for key, _ in pairs}))
        values = {key: value.strip() for key, value in pairs}
        self.assertEqual(set(values), {
            "name", "description", "tools", "user-invocable", "disable-model-invocation"
        })
        self.assertEqual(values["name"], "Workstation setup")
        self.assertTrue(values["description"])
        self.assertEqual(ast.literal_eval(values["tools"]), ["read", "search", "execute"])
        self.assertEqual(values["user-invocable"], "true")
        self.assertEqual(values["disable-model-invocation"], "true")

    def test_all_terminal_recipes_use_existing_allowlisted_surfaces(self) -> None:
        for tokens in recipes():
            with self.subTest(tokens=tokens):
                if tokens[0] == "Invoke-RestMethod":
                    continue
                self.assertEqual(tokens[:3], ["powershell.exe", "-NoProfile", "-File"])
                self.assertIn(tokens[3], {
                    r".\scripts\developer.ps1", r".\scripts\preflight.ps1",
                    r".\scripts\verify.ps1"
                })
                script = ROOT / "scripts" / tokens[3].split("\\")[-1]
                declaration = script.read_text(encoding="utf-8-sig").split("Set-StrictMode", 1)[0]
                for name in parameters(tokens[4:]):
                    if name == "Confirm":
                        self.assertIn("SupportsShouldProcess = $true", declaration)
                    else:
                        self.assertRegex(declaration, rf"\${name}\b")

    def test_local_inventory_covers_default_modules_before_preflight(self) -> None:
        native = [tokens for tokens in recipes() if tokens[0] == "powershell.exe"]
        preview = native[:5]
        self.assertEqual(
            {parameters(tokens[4:])["SetupModule"] for tokens in preview},
            DEFAULT_MODULES,
        )
        self.assertTrue(all(
            parameters(tokens[4:])["Action"] == "SetupPreview" for tokens in preview
        ))
        self.assertEqual(native[5][3], r".\scripts\preflight.ps1")
        self.assertEqual(parameters(native[5][4:])["HttpsTimeoutSeconds"], "5")

    def test_preview_recipe_matches_actual_task_defaults(self) -> None:
        expected = task_parameters("Setup preview")
        for recipe in dispatcher_recipes():
            if recipe["Action"] != "SetupPreview":
                continue
            self.assertEqual(recipe["Action"], expected["Action"])
            self.assertNotIn("Confirm", recipe)
            self.assertNotIn("Apply", recipe)

    def test_native_readiness_and_verify_recipe_are_bound_to_existing_source(self) -> None:
        verify = [tokens for tokens in recipes() if tokens[3:4] == [r".\scripts\verify.ps1"]]
        self.assertEqual(verify, [[
            "powershell.exe", "-NoProfile", "-File", r".\scripts\verify.ps1", "-Json"
        ]])
        text = agent_text()
        native_line = re.search(r"Native Verify tool rows: (.*)", text)
        other_line = re.search(r"Other full-profile tool rows: (.*)", text)
        self.assertIsNotNone(native_line)
        self.assertIsNotNone(other_line)
        assert native_line is not None and other_line is not None
        native = set(re.findall(r"`([a-z]+)`", native_line[1]))
        other = set(re.findall(r"`([a-z]+)`", other_line[1]))
        self.assertEqual(native, {"winget", "git", "code", "python", "uv", "pwsh", "java", "go"})
        self.assertEqual(other, {"gh", "copilot", "az", "azd", "kubectl", "node", "wsl", "wslc"})
        failures = re.search(r"Failure identities eligible for narrower Native: (.*)", text)
        self.assertIsNotNone(failures)
        assert failures is not None
        self.assertEqual(set(re.findall(r"`([a-z]+)`", failures[1])), {"wsl", "wslc"})
        source = (ROOT / "scripts" / "verify.ps1").read_text(encoding="utf-8-sig")
        definitions = source.split("$definitions = @(", 1)[1].split("$local =", 1)[0]
        self.assertEqual(set(re.findall(r"Name = '([a-z]+)'", definitions)), native | other)
        self.assertIn("Get-CheckResult $name FAIL", source)
        self.assertIn("-Found 'Missing/unusable'", source)
        self.assertIn("return (Get-CheckExitCode $checks)", source)
        self.assertTrue((ROOT / "tests" / "fixtures" / "native-readiness.ps1").is_file())
        self.assertNotRegex(source.split("Set-StrictMode", 1)[0], r"\$(?:Native|Mode)\b")
        normalized = " ".join(text.split())
        for boundary in (
            "full-workstation verification FAIL", "explicit narrower Native continuation",
            "Empty/incomplete arrays", "block Native continuation", "Declining that continuation stops",
            "Container = false", "Core includes tools beyond Native prerequisites",
            "every other default Verify row positively PASS", "exact Name identities",
            "no duplicate or unexpected rows",
            "directly wrapping that pipeline nests arrays on 5.1",
        ):
            self.assertIn(boundary, normalized)
        developer = (ROOT / "scripts" / "developer.ps1").read_text(encoding="utf-8-sig")
        self.assertIn(
            "Start-DeveloperSample $Sample -Container:($Action -eq 'RunContainer')", developer
        )
        preflight = (ROOT / "scripts" / "preflight.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("Get-CheckResult 'WSL' WARN 'Not installed.", preflight)
        self.assertIn("$status = if ($wslc) { 'PASS' } else { 'WARN' }", preflight)

    def test_every_changing_recipe_retains_native_confirmation(self) -> None:
        for recipe in dispatcher_recipes():
            with self.subTest(recipe=recipe):
                self.assertIn(recipe["Action"], {
                    "SetupPreview", "Setup", "Restore", "Test", "Lint", "Coverage", "RunLocal"
                })
                self.assertEqual(
                    recipe.get("Confirm", False),
                    recipe["Action"] in {"Setup", "Restore", "RunLocal"},
                )

    def test_setup_template_matches_each_named_catalog_task(self) -> None:
        template = next(
            recipe for recipe in dispatcher_recipes()
            if recipe.get("Action") == "Setup" and recipe.get("SetupModule") == "Python"
        )
        labels = {
            "Core": "Install core tools", "Python": "Install Python SDK",
            "Java": "Install Java SDK", "Go": "Install Go SDK",
        }
        for module, label in labels.items():
            with self.subTest(module=module):
                self.assertEqual({**template, "SetupModule": module}, task_parameters(label))

    def test_extension_template_keeps_real_source_attestation(self) -> None:
        recipe = next(
            recipe for recipe in dispatcher_recipes()
            if recipe.get("Action") == "Setup" and recipe.get("SetupModule") == "Extensions"
        )
        self.assertEqual(recipe, task_parameters("Install extensions (approved source)"))
        self.assertIn("attestation, not a source bypass", agent_text())
        self.assertIn("Unsupported private routing", agent_text())

    def test_restore_template_is_explicit_dependencies_not_images_or_all(self) -> None:
        template = next(
            recipe for recipe in dispatcher_recipes() if recipe.get("Action") == "Restore"
        )
        self.assertEqual(template["RestoreTarget"], "Dependencies")
        for sample in DEFAULT_SAMPLES:
            with self.subTest(sample=sample):
                expected = task_parameters(f"Restore {sample}")
                self.assertEqual(
                    {**template, "Sample": sample},
                    {**expected, "RestoreTarget": "Dependencies"},
                )

    def test_daily_templates_match_no_restore_sample_tasks(self) -> None:
        for template in dispatcher_recipes():
            if template["Action"] not in {"Test", "Lint", "Coverage"}:
                continue
            for sample in DEFAULT_SAMPLES:
                with self.subTest(action=template["Action"], sample=sample):
                    self.assertEqual(
                        {**template, "Sample": sample},
                        task_parameters(f"{template['Action']} {sample}"),
                    )
        text = agent_text()
        self.assertIn("new scoped\nhuman decision", text)
        self.assertIn("even from cache", text)
        dispatcher = (ROOT / "scripts" / "developer.ps1").read_text(encoding="utf-8-sig")
        for guard in (
            "$env:UV_NO_SYNC = '1'", "$env:UV_OFFLINE = '1'",
            "$env:UV_PYTHON_DOWNLOADS = 'never'", "$env:GOTOOLCHAIN = 'local'",
            "$env:GOPROXY = 'off'", "$env:GOSUMDB = 'off'",
        ):
            self.assertIn(guard, dispatcher)

    def test_launch_templates_match_existing_tasks_and_distinct_ports(self) -> None:
        labels = {
            "Python": "Run EMI API (local)", "Java": "Run IFSC service (local)",
            "Go": "Run FX rates (local)",
        }
        launches = [recipe for recipe in dispatcher_recipes() if recipe["Action"] == "RunLocal"]
        self.assertEqual({recipe["Sample"] for recipe in launches}, DEFAULT_SAMPLES)
        self.assertEqual({recipe["Port"] for recipe in launches}, {"8080", "8081", "8082"})
        for recipe in launches:
            expected = task_parameters(labels[str(recipe["Sample"])])
            self.assertEqual(recipe, {"Port": "8080", **expected})

    def test_health_and_requests_are_bounded_loopback_synthetic_only(self) -> None:
        requests = [parameters(tokens[1:]) for tokens in recipes() if tokens[0] == "Invoke-RestMethod"]
        self.assertEqual(len(requests), 6)
        for request in requests:
            self.assertRegex(str(request["Uri"]), r"^http://127\.0\.0\.1:808[012]/")
            self.assertEqual(request["TimeoutSec"], "10")
            self.assertEqual(request["ErrorAction"], "Stop")
        post = next(request for request in requests if request.get("Method") == "Post")
        self.assertEqual(json.loads(str(post["Body"])), {
            "principal": "2500000.00", "annual_rate_percent": "8.5", "tenure_months": 240
        })

    def test_no_recipe_bypasses_or_adds_cloud_destructive_scope(self) -> None:
        commands = "\n".join(" ".join(tokens) for tokens in recipes())
        self.assertNotRegex(commands, (
            r"(?i)Confirm:\$false|ConfirmPreference|ExecutionPolicy|Invoke-Expression|"
            r"RunAs|setx|Start-Process|Restart-Computer|Reset-|Remove-|Uninstall-|"
            r"LegacySetup|FinishSetup|SkipBase|RunConfigTest|DeployDispatch|"
            r"az login|kubectl|git (push|commit|reset|clean|checkout)|--force"
        ))

    def test_stop_resume_and_approval_contracts_cover_unverified_outcomes(self) -> None:
        text = " ".join(agent_text().split())
        for boundary in (
            "before Preflight's", "unknown state stops", "A declined target remains",
            "exit 3010/1641", "stop before the next install",
            "never blindly retry", "pending reboot", "or call it full setup",
            "If a prompt cannot be answered", "not you", "Y/A/Yes-to-All",
            "not installation, Restore or launch consent",
        ):
            with self.subTest(boundary=boundary):
                self.assertTrue(boundary in text, boundary)

    def test_instruction_surfaces_keep_the_exception_named_and_narrow(self) -> None:
        for path in (
            ROOT / "AGENTS.md", ROOT / ".github" / "copilot-instructions.md",
            ROOT / ".github" / "instructions" / "powershell.instructions.md",
        ):
            with self.subTest(path=path):
                text = path.read_text(encoding="utf-8")
                self.assertIn("Workstation setup", text)
                self.assertIn("exception", text)
                self.assertRegex(text, r"(?i)desktop")
                self.assertRegex(text, r"(?i)cloud")
                self.assertRegex(text, r"(?i)subagent")
        setup = (ROOT / "docs" / "SETUP.md").read_text(encoding="utf-8")
        self.assertIn("Troubleshooting's generic agent restrictions", setup)
        self.assertIn("separately approved stages", setup)
        onboarding = (ROOT / ".github" / "agents" / "onboarding.agent.md").read_text(encoding="utf-8")
        self.assertIn("This agent remains read-only", onboarding)
        self.assertIn("ONLY commands", onboarding)
        self.assertIn("Never run bootstrap", onboarding)

    def test_default_optional_scopes_and_historical_baseline_stay_separate(self) -> None:
        text = agent_text()
        for boundary in (
            "WSL is a **separately approved**", "Ubuntu, licensed Docker Desktop",
            "optional 13th", "image builds and container launches",
            "--pull=never", "broad legacy Microsoft bundle", "outside this agent",
            "historical unsafe `demo-baseline`", "Do not create source files",
            "Never authenticate", "Do not invoke other agents",
        ):
            with self.subTest(boundary=boundary):
                self.assertTrue(boundary.lower() in text.lower(), boundary)


if __name__ == "__main__":
    unittest.main(verbosity=2)
