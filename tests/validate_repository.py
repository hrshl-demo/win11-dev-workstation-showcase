"""Read-only structural checks; no workstation setup or sample launches."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

import json5
import jsonschema
import yaml

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_URL = "https://aka.ms/configuration-dsc-schema/0.2"
EXTENSIONS = {
    "ms-python.python",
    "vscjava.vscode-java-pack",
    "golang.go",
    "ms-azuretools.vscode-azureresourcegroups",
    "ms-azuretools.vscode-azure-github-copilot",
    "ms-azuretools.vscode-bicep",
    "ms-azuretools.vscode-containers",
    "ms-vscode-remote.remote-containers",
    "ms-vscode-remote.remote-wsl",
    "github.vscode-pull-request-github",
    "ms-vscode.powershell",
    "redhat.vscode-yaml",
}
MODERNIZER = "vscjava.migrate-java-to-azure"
SAMPLES = (
    "python-emi-api",
    "java-ifsc-service",
    "go-fx-rates",
    "java-legacy-upgrade",
)
REQUIRED = (
    "README.md", "LICENSE", "SECURITY.md", "AGENTS.md", ".gitignore",
    ".gitattributes", ".editorconfig", "samples/README.md",
    "scripts/_common.psm1", "scripts/preflight.ps1", "scripts/bootstrap.ps1",
    "scripts/verify.ps1", "scripts/repair-winget.ps1", "scripts/run-sample.ps1",
    "scripts/demo-reset.ps1", "tests/Common.Tests.ps1", "tests/Scripts.Tests.ps1",
    ".github/copilot-instructions.md", ".github/pull_request_template.md",
    ".github/workflows/ci.yml", ".github/agents/onboarding.agent.md",
    "docs/SETUP.md", "docs/DEMO-SCRIPT.md", "docs/TROUBLESHOOTING.md",
    "docs/IT-PREREQUISITES.md", "docs/WINDOWS-VS-MAC.md", "docs/ARCHITECTURE.md",
    "samples/python-emi-api/pyproject.toml", "samples/python-emi-api/uv.lock",
    "samples/python-emi-api/.python-version",
    "scripts/developer.ps1", "tests/Developer.Tests.ps1", ".vscode/project-tools.json",
    ".github/workflows/deploy-aks.yml", "docs/GITHUB-AKS.md", "k8s/workloads.json",
    "scripts/check_deployment.py", "scripts/render_kubernetes.py", "scripts/smoke_aks.py",
    "tests/check_kubernetes.py", "tests/test_deployment.py",
    "scripts/cleanup.ps1", "scripts/_ownership.psm1", "tests/Ownership.Tests.ps1",
    "tests/BaseSetup.Tests.ps1",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def load_yaml(path: Path) -> dict:
    result = yaml.safe_load(path.read_text(encoding="utf-8-sig"))
    require(isinstance(result, dict), f"{path}: expected a mapping")
    return result


def frontmatter(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8-sig")
    match = re.fullmatch(r"---\r?\n(.*?)\r?\n---\r?\n(.+)", text, re.S)
    require(match is not None, f"{path}: missing YAML frontmatter or body")
    assert match
    data = yaml.safe_load(match.group(1))
    require(isinstance(data, dict), f"{path}: invalid frontmatter")
    return data, match.group(2)


def check_configs(schema: dict) -> None:
    validator = jsonschema.Draft202012Validator(schema)
    installed: dict[str, set[str]] = {}
    for name in ("configuration", "java-modernization"):
        path = ROOT / ".config" / f"{name}.winget"
        require(
            path.read_text(encoding="utf-8-sig").splitlines()[0]
            == f"# yaml-language-server: $schema={SCHEMA_URL}",
            f"{path}: incorrect schema header",
        )
        data = load_yaml(path)
        validator.validate(data)
        properties = data["properties"]
        require(properties["configurationVersion"] == "0.2.0", "schema version")
        resources = properties["resources"]
        all_units = resources + properties.get("assertions", [])
        ids = [unit["id"] for unit in all_units]
        require(len(ids) == len(set(ids)), f"{path}: duplicate resource id")
        for unit in all_units:
            require(
                set(unit.get("dependsOn", [])).issubset(ids),
                f"{path}: unresolved dependsOn",
            )
            require(unit["id"] not in unit.get("dependsOn", []), "self dependency")
        extensions = [
            unit for unit in resources
            if unit["resource"] == "Microsoft.VSCode.Dsc/VSCodeExtension"
        ]
        installed[name] = {
            unit["settings"]["Name"].lower() for unit in extensions
        }
        for unit in extensions:
            require(unit["settings"]["Exist"] is True, "extension must exist")
            require(unit["directives"]["allowPrerelease"] is True, "DSC prerelease")
        if name == "configuration":
            require(len(extensions) == 12, "default profile must have 12 extensions")
            for unit in extensions:
                require("vscode" in unit["dependsOn"], "extension needs VS Code")
            packages = {
                unit["settings"]["id"]
                for unit in resources
                if unit["resource"] == "Microsoft.WinGet.DSC/WinGetPackage"
            }
            require(packages == {
                "Microsoft.VisualStudioCode", "Git.Git", "GitHub.cli",
                "GitHub.Copilot", "Python.Python.3.14", "Microsoft.AzureCLI",
                "Microsoft.OpenJDK.25", "GoLang.Go", "Microsoft.Azd",
                "Kubernetes.kubectl",
            }, "default package inventory differs from approved scope")
            assertion = properties["assertions"][0]
            require(assertion["settings"]["MinVersion"] == "10.0.22621", "OS floor")
    require(installed["configuration"] == EXTENSIONS, "default extension inventory")
    require(installed["java-modernization"] == {MODERNIZER}, "optional modernizer")


def check_workspace() -> None:
    documents = {}
    for name in ("extensions", "settings", "tasks", "launch"):
        path = ROOT / ".vscode" / f"{name}.json"
        documents[name] = json5.loads(path.read_text(encoding="utf-8-sig"))
    recommendations = documents["extensions"]["recommendations"]
    require(len(recommendations) == 13, "expected thirteen recommendations")
    require(
        {item.lower() for item in recommendations} == EXTENSIONS | {MODERNIZER},
        "recommendations differ from installation profiles",
    )
    tasks = documents["tasks"]["tasks"]
    labels = [task["label"] for task in tasks]
    require("Cleanup preview" in labels and "Cleanup generated resources" in labels,
            "missing explicit cleanup lifecycle tasks")
    cleanup = {task["label"]: task for task in tasks if task["label"].startswith("Cleanup")}
    require("-Apply" not in cleanup["Cleanup preview"]["args"], "cleanup preview must be nonmutating")
    require({"-Apply", "-Confirm"}.issubset(cleanup["Cleanup generated resources"]["args"]),
            "cleanup apply requires explicit confirmation")
    require(len(labels) == len(set(labels)), "duplicate task")
    base_picker = [item for item in documents["tasks"]["inputs"] if item["id"] == "baseSetupTimeoutSeconds"]
    require(len(base_picker) == 1 and base_picker[0]["default"] == "14400"
            and base_picker[0]["options"] == ["7200", "14400", "28800"], "bounded base-only wait picker")
    for task in tasks:
        require(("${input:baseSetupTimeoutSeconds}" in task["args"])
                == (task["label"] in {"Setup preview", "User-run setup"}), "base wait picker scope")
    for task in tasks:
        require(set(task.get("dependsOn", [])).issubset(labels), "unresolved task")
    require({"Preflight", "Verify", "Test all samples", "Run EMI API (local)",
             "Run EMI API (container)", "Reset demo"}.issubset(labels), "missing task")
    require(
        {item["type"] for item in documents["launch"]["configurations"]}
        == {"debugpy", "java", "go"}, "debugger inventory",
    )
    path = ROOT / "samples" / "python-emi-api" / ".devcontainer" / "devcontainer.json"
    container = json5.loads(path.read_text(encoding="utf-8-sig"))
    require("features" not in container and "dockerComposeFile" not in container,
            "devcontainer must not use features or Compose")
    require(container.get("image", "").startswith("mcr.microsoft.com/devcontainers/"),
            "official devcontainer image required")


def check_customizations() -> None:
    for language in ("python", "java", "go", "powershell"):
        path = ROOT / ".github" / "instructions" / f"{language}.instructions.md"
        metadata, _ = frontmatter(path)
        extension = {"python": "py", "java": "java", "go": "go", "powershell": "ps1"}[language]
        require(metadata.get("applyTo") == f"**/*.{extension}", f"{path}: scope")
    for name in ("extend-emi-api", "containerise-and-run", "prepare-for-azure",
                 "bank-standards-review"):
        metadata, body = frontmatter(ROOT / ".github" / "skills" / name / "SKILL.md")
        require(metadata.get("name") == name, f"{name}: skill name")
        require(bool(metadata.get("description")), f"{name}: description")
        require("Done:" in body, f"{name}: definition of done")
    metadata, body = frontmatter(ROOT / ".github" / "agents" / "onboarding.agent.md")
    require(metadata.get("tools") == ["read", "search", "execute"], "onboarding tools")
    require("ONLY commands" in body and "Never run bootstrap" in body, "agent boundary")


def check_workflow() -> None:
    # BaseLoader preserves the YAML 1.2 'on' key instead of YAML 1.1 booleans.
    workflow = yaml.load(
        (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8"),
        Loader=yaml.BaseLoader,
    )
    require(set(workflow["on"]) == {"push", "pull_request", "workflow_dispatch", "workflow_call"}, "CI triggers")
    require(workflow["permissions"] == {"contents": "read"}, "CI least privilege")
    for name, job in workflow["jobs"].items():
        for step in job["steps"]:
            if "uses" in step:
                require(bool(re.fullmatch(r"[\w.-]+/[\w.-]+@[0-9a-f]{40}",
                                          step["uses"])), f"{name}: unpinned action")
            require("java-legacy-upgrade" not in step.get("run", ""),
                    "legacy excluded from CI")
    require({"python", "java", "go", "powershell", "config"}.issubset(workflow["jobs"]),
            "CI workload inventory")
    require(set(workflow["jobs"]["containers"]["needs"]) == {"python", "java", "go", "powershell", "config"},
            "every test/lint gate must precede modern container builds")
    deployment = yaml.load(
        (ROOT / ".github" / "workflows" / "deploy-aks.yml").read_text(),
        Loader=yaml.BaseLoader,
    )
    require(set(deployment["on"]) == {"workflow_dispatch"}, "AKS must be manual-only")
    require(deployment["permissions"] == {"contents": "read"}, "AKS root permissions")
    jobs = deployment["jobs"]
    require(jobs["tests"]["uses"] == "./.github/workflows/ci.yml", "same-source complete test gate")
    require(jobs["deploy"]["environment"]["name"] == "aks-demo", "independent approval environment")
    require(set(jobs["build"]["needs"]) == {"governance", "tests"}, "tested, protected builds")
    require(set(jobs["deploy"]["needs"]) == {"governance", "tests", "build"}, "digest promotion gates")
    for name, job in jobs.items():
        permissions = job.get("permissions", {"contents": "read"})
        require(permissions == ({"contents": "read", "id-token": "write"}
                                if name in {"build", "deploy"} else {"contents": "read"}),
                f"{name}: OIDC only on Azure jobs")
        for step in job.get("steps", []):
            if "uses" in step:
                require(bool(re.fullmatch(r"[\w.-]+/[\w.-]+@[0-9a-f]{40}", step["uses"])),
                        f"{name}: unpinned deployment action")
            require("--admin" not in step.get("run", ""), "never AKS admin credentials")
    require(jobs["build"]["outputs"].keys() >= {"registry", "emi", "ifsc", "fx"},
            "same-run immutable image outputs")
    require("check_deployment.py" in str(jobs["governance"]), "live gate must fail closed")
    from check_kubernetes import check
    check()


def check_onboarding_journey() -> None:
    setup = (ROOT / "docs" / "SETUP.md").read_text(encoding="utf-8-sig")
    readme = (ROOT / "README.md").read_text(encoding="utf-8-sig")
    phases = re.findall(r"^## Phase (\d):", setup, re.M)
    require(phases == [str(index) for index in range(8)],
            "SETUP must order Phase 0 prerequisites through Phase 7 AKS")
    before_preflight = setup.split("## Phase 1:", 1)[0]
    for command in ("Get-ExecutionPolicy -List", "\nGet-ExecutionPolicy\n",
                    "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned"):
        require(command in before_preflight, f"missing prerequisite policy guidance: {command}")
    require("before running any repository script" in before_preflight.lower(),
            "prerequisites must precede script execution")
    for boundary in ("persistent account-level", "MachinePolicy/UserPolicy",
                     "AllSigned", "mark-of-the-web", "before cloning"):
        require(boundary in before_preflight, f"missing Phase 0 boundary: {boundary}")
    inventory = setup.split("## Phase 1:", 1)[1].split("## Phase 2:", 1)[0]
    require("exit 1" in inventory and re.search(r"\bexpected inventory failure\b", inventory)
            and "missing WSL/wslc" in inventory and "WARN" in inventory,
            "pre-install Verify failure and WSL WARN must be distinguished from preflight gate")
    for extension in EXTENSIONS | {MODERNIZER}:
        require(f"`{extension}`" in setup.lower(),
                f"setup extension inventory missing {extension}")
    require("12 required extension IDs" in setup and "optional 13th" in setup,
            "required versus optional extension profile must be explicit")
    for boundary in ("no target profile or marketplace parameter", "stop: setup is not accepted",
                     "managed automated", "not proof any ID is blocked"):
        require(boundary in setup, f"missing enterprise extension acceptance: {boundary}")
    tasks = json.loads((ROOT / ".vscode" / "tasks.json").read_text(encoding="utf-8-sig"))
    labels = {task["label"] for task in tasks["tasks"]}
    timeout_inputs = [item for item in tasks["inputs"] if item["id"] == "httpsTimeoutSeconds"]
    require(len(timeout_inputs) == 1 and timeout_inputs[0]["default"] == "5"
            and timeout_inputs[0]["options"] == ["5", "15", "30"],
            "HTTPS timeout picker must default to 5 with explicit 15/30 choices")
    for task in tasks["tasks"]:
        relevant = task["label"] in {"Preflight", "Setup preview", "User-run setup", "Finish setup"}
        require(("${input:httpsTimeoutSeconds}" in task["args"]) == relevant,
                f"HTTPS timeout picker scope: {task['label']}")
        if relevant:
            position = task["args"].index("-HttpsTimeoutSeconds")
            require(task["args"][position + 1] == "${input:httpsTimeoutSeconds}",
                    "timeout task input must reach the named dispatcher parameter")
    required_labels = (
        "Preflight", "Setup preview", "User-run setup", "Finish setup", "Verify",
        "Restore project dependencies", "Test all samples", "Lint all samples",
        "Coverage all samples", "Run EMI API (local)", "GitHub workflow status",
        "Deploy AKS (manual main only)",
    )
    for label in required_labels:
        require(label in labels and f"**{label}**" in readme,
                f"README journey/task contract missing {label}")
    anchors = {
        re.sub(r"[^\w -]", "", heading.lower()).replace(" ", "-")
        for heading in re.findall(r"^#{1,6} (.+)$", setup, re.M)
    }
    for anchor in re.findall(r"docs/SETUP\.md#([^)]+)", readme):
        require(anchor in anchors, f"README references missing SETUP heading: {anchor}")


def check_files_and_links() -> None:
    for name in REQUIRED:
        path = ROOT / name
        require(path.is_file() and path.stat().st_size > 0, f"missing/empty {name}")
    for sample in SAMPLES:
        for name in ("README.md", "Dockerfile", ".dockerignore"):
            path = ROOT / "samples" / sample / name
            require(path.is_file() and path.stat().st_size > 0, f"missing {path}")
        dockerfile = (ROOT / "samples" / sample / "Dockerfile").read_text()
        require(bool(re.search(r"^USER (?!root\b|0\b).+", dockerfile, re.M)),
                f"{sample}: explicit non-root USER required")
        require("HEALTHCHECK" in dockerfile, f"{sample}: healthcheck required")
        for image in re.findall(r"^FROM\s+(\S+)", dockerfile, re.M):
            require("@sha256:" in image, f"{sample}: base image not digest pinned")
    python = ROOT / "samples" / "python-emi-api"
    for name in ("__init__", "main", "models", "emi", "money", "logging_config"):
        path = python / "app" / f"{name}.py"
        require(path.is_file() and path.stat().st_size > 0, f"missing/empty {path}")
    for name in ("api", "emi", "money", "logging"):
        require((python / "tests" / f"test_{name}.py").is_file(), f"missing Python {name} tests")
    for sample, package, main_classes, test_classes in (
        ("java-ifsc-service", "ifsc",
         ("IfscApplication", "IfscController", "IfscService", "IfscResult"),
         ("IfscServiceTest", "IfscControllerTest")),
        ("java-legacy-upgrade", "legacy",
         ("LegacyApplication", "PaymentController", "PaymentService"),
         ("PaymentServiceTest", "PaymentControllerTest")),
    ):
        base = ROOT / "samples" / sample
        for name in ("pom.xml", "mvnw", "mvnw.cmd", ".mvn/wrapper/maven-wrapper.properties",
                     "src/main/resources/application.properties"):
            require((base / name).is_file(), f"missing {sample}/{name}")
        for kind, classes in (("main", main_classes), ("test", test_classes)):
            for name in classes:
                path = base / "src" / kind / "java" / "showcase" / package / f"{name}.java"
                require(path.is_file() and path.stat().st_size > 0, f"missing/empty {path}")
    for name in ("go.mod", "main.go", "main_test.go", "money.go", "money_test.go"):
        require((ROOT / "samples" / "go-fx-rates" / name).is_file(), f"missing Go {name}")
    go = (ROOT / "samples" / "go-fx-rates" / "main.go").read_text()
    require('slog.Info("conversion request", "query"' not in go
            and "safeError(w, http.StatusBadRequest, err.Error())" not in go,
            "historical Go demo gaps must never enter live/container deployment code")
    require((ROOT / "tests" / "fixtures" / "go-review-example.txt").is_file(),
            "non-serving review exercise fixture required")
    markdown = [ROOT / name for name in ("README.md", "SECURITY.md", "AGENTS.md")]
    markdown += list((ROOT / "docs").glob("*.md"))
    markdown += list((ROOT / ".github").rglob("*.md"))
    markdown += list((ROOT / "samples").glob("*/README.md"))
    for path in markdown:
        text = path.read_text(encoding="utf-8-sig")
        for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
            target = target.split("#", 1)[0]
            if not target or "://" in target or target.startswith("mailto:"):
                continue
            require((path.parent / target).exists(), f"{path}: broken link {target}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema-file", type=Path, help="Previously downloaded official schema")
    parser.add_argument("--configs-only", action="store_true", help="First implementation gate")
    arguments = parser.parse_args()
    try:
        if arguments.schema_file:
            schema = json.loads(arguments.schema_file.read_text(encoding="utf-8"))
        else:
            with urllib.request.urlopen(SCHEMA_URL, timeout=20) as response:
                schema = json.load(response)
        check_configs(schema)
        print("PASS WinGet schema and approved profiles")
        if not arguments.configs_only:
            for name, check in (
                ("workspace and devcontainer", check_workspace),
                ("Copilot frontmatter and locations", check_customizations),
                ("pinned least-privilege CI", check_workflow),
                ("required files, images and local Markdown links", check_files_and_links),
                ("Phase 0–7 onboarding and automated extension acceptance", check_onboarding_journey),
            ):
                check()
                print(f"PASS {name}")
        return 0
    except (ValueError, KeyError, OSError, jsonschema.ValidationError,
            yaml.YAMLError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
