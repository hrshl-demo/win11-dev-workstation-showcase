"""Bind copyable material to this workstation repository, without executing it."""
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "src" / "content"
LOCK = ROOT / "src" / "sources.lock.json"
SITE = json.loads((CONTENT / "site.json").read_text(encoding="utf-8"))
PIN = SITE["repos"]["poc"]["commit"]
PH = re.compile(r"\{\{ph:([^}]+)\}\}")


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def relative_path(text):
    parts = text.replace("\\", "/").split("/")
    if not text or any(p in ("", ".", "..") or ":" in p for p in parts):
        raise ValueError(f"unsafe repository-relative path: {text!r}")
    return Path(*parts)


@lru_cache(maxsize=1)
def repo_root():
    explicit = os.environ.get("WORKSTATION_REPO_CHECKOUT")
    candidates = [Path(explicit)] if explicit else [ROOT.parent]
    for candidate in candidates:
        if (candidate / ".vscode" / "tasks.json").is_file() and (candidate / "AGENTS.md").is_file():
            return candidate.resolve()
    return None


@lru_cache(maxsize=None)
def source_text(path, pinned=False):
    repository = repo_root()
    if repository is None:
        raise RuntimeError("NOT RUN: source checkout absent; use the repository or WORKSTATION_REPO_CHECKOUT")
    relative = relative_path(path)
    if not pinned:
        return (repository / relative).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("NOT RUN: installed Git is needed for immutable source comparison")
    result = subprocess.run(
        [git, "--no-pager", "-C", str(repository), "show", f"{PIN}:{relative.as_posix()}"],
        capture_output=True, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"NOT RUN: pinned source {PIN}:{path} is unavailable locally; no fetch is performed")
    return result.stdout.decode("utf-8-sig").replace("\r\n", "\n")


def _task_text(binding, source):
    tasks = json.loads(source)
    matches = [task for task in tasks["tasks"] if task["label"] == binding["label"]]
    if len(matches) != 1:
        raise ValueError(f"task label must resolve exactly once: {binding['label']}")
    task = matches[0]
    if task.get("command") != "powershell.exe":
        raise ValueError(f"not a PowerShell dispatcher task: {binding['label']}")
    arguments = task["args"]
    if arguments[:2] != ["-NoProfile", "-File"]:
        raise ValueError(f"unexpected task invocation: {binding['label']}")
    inputs = {item["id"]: item for item in tasks["inputs"]}
    supplied = binding.get("inputs", {})
    used = set()

    def replace_input(match):
        identifier = match.group(1)
        used.add(identifier)
        definition = inputs[identifier]
        value = str(supplied.get(identifier, definition.get("default", "")))
        if definition["type"] == "pickString" and value not in definition["options"]:
            raise ValueError(f"invalid picker value for {identifier}: {value!r}")
        if definition["type"] != "pickString" and not PH.fullmatch(value):
            raise ValueError(f"freeform input {identifier} must be an explicit declared placeholder")
        return value

    resolved = []
    for argument in arguments[2:]:
        value = argument.replace("${workspaceFolder}", ".")
        value = re.sub(r"\$\{input:([^}]+)\}", replace_input, value)
        if "$" in value and not PH.search(value):
            raise ValueError(f"unresolved task interpolation: {value!r}")
        resolved.append("'" + value.replace("'", "''") + "'" if " " in value else value)
    if set(supplied) - used:
        raise ValueError(f"unused input overrides: {sorted(set(supplied) - used)}")
    return "\n".join([" ".join(resolved)])


def _bind(definition):
    binding = definition["bound"]
    current = source_text(binding["path"])
    pinned = source_text(binding["path"], pinned=True)
    kind = binding["kind"]
    if kind == "task":
        text = _task_text(binding, current)
        if text != _task_text(binding, pinned):
            raise ValueError(f"task changed from documented source pin: {binding['label']}")
    elif kind == "lines":
        text = binding["text"]
        for line in text.splitlines():
            if line.strip() and (line.strip() not in current or line.strip() not in pinned):
                raise ValueError(f"copyable line not found verbatim in current and pinned {binding['path']}: {line!r}")
    elif kind == "fence":
        def extract(source):
            fences = re.findall(r"```[^\n]*\n(.*?)\n```", source, re.S)
            found = [body for body in fences if body.startswith(binding["starts"])]
            if len(found) != 1:
                raise ValueError(f"source fence must resolve exactly once: {binding['starts']!r}")
            return found[0]
        text = extract(current)
        if text != extract(pinned):
            raise ValueError(f"source fence changed from documented pin: {binding['starts']!r}")
    else:
        raise ValueError(f"unknown binding kind: {kind}")
    references = [{"path": binding["path"]}]
    for switch in binding.get("switches", []):
        name = switch["name"]
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", name):
            raise ValueError("invalid switch name")
        pattern = r"\[switch\]\s*\$" + re.escape(name) + r"\b"
        if not all(re.search(pattern, source_text(switch["path"], pinned=pin), re.I) for pin in (False, True)):
            raise ValueError(f"switch is not declared in current and pinned source: {name}")
        text += " -" + name
        references.append({"path": switch["path"]})
    return {**copy.deepcopy(definition), "text": text, "source": references}


@lru_cache(maxsize=1)
def file_blocks():
    result = {}
    for file in sorted((CONTENT / "blocks").glob("*.json")):
        for definition in json.loads(file.read_text(encoding="utf-8"))["blocks"]:
            identifier = definition["id"]
            if identifier in result:
                raise ValueError(f"duplicate block id: {identifier}")
            result[identifier] = _bind(definition)
    return result


def source_blocks():
    return file_blocks()


def prompts():
    return [b for key, b in file_blocks().items() if key.startswith("prompt-")], []


def resolve_page(value):
    if isinstance(value, dict):
        if set(value) == {"ref"}:
            return copy.deepcopy(file_blocks()[value["ref"]])
        return {key: resolve_page(item) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve_page(item) for item in value]
    return value


def write_lock():
    blocks = file_blocks()
    paths = sorted({ref["path"] for block in blocks.values() for ref in block["source"]})
    data = {
        "repository": SITE["repos"]["poc"]["url"],
        "underlying_source_commit": PIN,
        "as_of": SITE["as_of"],
        "comparison": "Copyable text matches current checkout and immutable pin; no commands executed.",
        "blocks": {key: {"sha256": sha(block["text"]), "text": block["text"],
                         "source": block["source"], "actor": block["actor"]}
                   for key, block in blocks.items()},
        "pinned_source_files": {path: sha(source_text(path, pinned=True)) for path in paths},
    }
    LOCK.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    return data
