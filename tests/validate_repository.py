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
    require(len(labels) == len(set(labels)), "duplicate task")
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
    require(set(workflow["on"]) == {"push", "pull_request"}, "CI triggers")
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


def check_azure_preparation() -> None:
    path = ROOT / "azure.yaml"
    if not path.exists():
        return
    schema_url = (
        "https://raw.githubusercontent.com/Azure/azure-dev/main/"
        "schemas/v1.0/azure.yaml.json"
    )
    with urllib.request.urlopen(schema_url, timeout=20) as response:
        schema = json.load(response)
    config = load_yaml(path)
    jsonschema.validate(config, schema)
    require(config["services"]["emi"]["host"] == "containerapp", "Azure host")
    require((ROOT / config["services"]["emi"]["project"]).is_dir(), "Azure project path")
    parameters = json.loads(
        (ROOT / "infra" / "main.parameters.json").read_text(encoding="utf-8")
    )
    bindings = {
        "environmentName": "${AZURE_ENV_NAME}",
        "location": "${AZURE_LOCATION}",
        "containerImage": "${EMI_CONTAINER_IMAGE}",
    }
    require(
        {name: value["value"] for name, value in parameters["parameters"].items()}
        == bindings,
        "Azure parameters must bind real developer-provided environment values",
    )
    source = (ROOT / "infra" / "main.bicep").read_text(encoding="utf-8")
    for name in bindings:
        require(bool(re.search(rf"^param {name} string$", source, re.M)),
                f"missing Azure parameter {name}")
    require("param containerImage string =" not in source, "no seed-image placeholder")
    require("ingressAllowInsecure: false" in source, "HTTPS ingress required")
    require("enableRbacAuthorization: true" in source, "Key Vault RBAC required")
    require("publicNetworkAccess: 'Disabled'" in source, "sealed Key Vault required")
    modules = re.findall(r"'br/public:([^']+)'", source)
    require(len(modules) == 5, "Azure module inventory")
    for module in modules:
        require(bool(re.fullmatch(r"avm/(res|ptn)/[\w/-]+:\d+\.\d+\.\d+", module)),
                f"unpinned AVM module {module}")
    print("PASS Azure preparation schema, bindings and static security invariants")
    print("NOT RUN Bicep compile/deployment: separate developer acceptance checks")


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
            ):
                check()
                print(f"PASS {name}")
            check_azure_preparation()
        return 0
    except (ValueError, KeyError, OSError, jsonschema.ValidationError,
            yaml.YAMLError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
