"""Validate workstation content and immutable source bindings; never run its commands."""
import argparse
import json
import re
import sys
from pathlib import Path

import forbidden
import registry as REG
import sources as S

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "src" / "content"
BLOCK_KEYS = {"p", "h", "ul", "ol", "table", "kv", "callout", "code", "fieldnote", "checklist", "quote", "screenshot"}
PAGE_KINDS = {"home", "quick", "activity", "reference", "prompts", "evidence"}
CALLOUTS = {"info", "tip", "warn", "danger", "billing", "gap"}
NO = re.compile(r"^[1-9][0-9]?[a-z]?$")
INLINE_LINK = re.compile(r"\]\(page:([a-z0-9-]+)(?:#([a-z0-9-]+))?\)")


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def walk(value):
    yield value
    if isinstance(value, dict):
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)


def validate(require_all=True):
    errors = []
    def error(where, message):
        errors.append(f"{where}: {message}")

    loaded = {}
    for file in sorted(CONTENT.rglob("*.json")):
        try:
            loaded[file.relative_to(CONTENT).as_posix()] = read_json(file)
        except (OSError, ValueError, UnicodeError) as exc:
            error(str(file.relative_to(ROOT)), str(exc))
    if errors:
        return errors
    site = loaded["site.json"]
    actors = set(site["legend"]["actors"])
    statuses = set(site["legend"]["status"])
    pages = {page["id"]: page for page in site["pages"]}
    if len(pages) != len(site["pages"]):
        error("site", "duplicate page id")
    journeys = {journey["id"] for journey in site["journeys"]}
    for identifier, page in pages.items():
        if not re.fullmatch(r"[a-z0-9-]+", identifier) or page["journey"] not in journeys or page["kind"] not in PAGE_KINDS:
            error(identifier, "invalid registry id/journey/kind")
    try:
        named = S.file_blocks()
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
        error("source bindings", str(exc))
        return errors
    for identifier, block in named.items():
        if not re.fullmatch(r"[a-z0-9-]+", identifier):
            error(identifier, "invalid block id")
        for field in ("label", "text", "actor", "lang"):
            if not block.get(field):
                error(identifier, f"missing {field}")
        if block.get("actor") not in {"terminal", "copilot", "file"}:
            error(identifier, "invalid code actor")
        used = set(S.PH.findall(block["text"]))
        declared = {placeholder["token"] for placeholder in block.get("placeholders", [])}
        if used != declared:
            error(identifier, "used and declared placeholders differ")
        for placeholder in block.get("placeholders", []):
            if (placeholder.get("token") != "reviewed-main-sha" or not placeholder.get("how")
                    or placeholder.get("pattern") != "^[0-9a-f]{40}$" or placeholder.get("max_length") != 40):
                error(identifier, "only the declared non-sensitive 40-hex reviewed main SHA is accepted")
        if block["lang"] == "powershell" and re.search(r"&&|\|\||^\s*(?:PS>|PS [A-Z]:)", block["text"], re.M):
            error(identifier, "unsupported PowerShell syntax or copied prompt")
        for label in forbidden.scan(block["text"]):
            error(identifier, label)
    data = {}
    for identifier, page in pages.items():
        if page["kind"] not in {"quick", "activity", "reference"}:
            continue
        value = loaded.get(f"pages/{identifier}.json")
        if value is None:
            if require_all:
                error(identifier, "registered content missing")
            continue
        data[identifier] = value
        if value.get("id") != identifier or value.get("status") not in statuses:
            error(identifier, "page id/status missing or invalid")
        if not value.get("summary"):
            error(identifier, "summary missing")
        if page["kind"] != "quick":
            if not isinstance(value.get("evidence_gaps"), list) or not value.get("sources"):
                error(identifier, "sources and explicit evidence gaps required")
            for reference in value.get("sources", []):
                try:
                    path = S.relative_path(reference["path"])
                    if reference.get("repo") != "poc" or not (S.repo_root() / path).exists():
                        error(identifier, f"unknown source {reference}")
                except (ValueError, KeyError, TypeError) as exc:
                    error(identifier, str(exc))
        steps = value.get("steps", [])
        if page["kind"] in {"activity", "quick"} and not steps:
            error(identifier, "steps missing")
        labels = set()
        for index, step in enumerate(steps, 1):
            label = REG.step_no(index, step)
            if not NO.fullmatch(label) or label in labels:
                error(identifier, f"invalid/duplicate step number {label}")
            labels.add(label)
            if step.get("actor") not in actors or not step.get("title") or not step.get("where"):
                error(identifier, f"step {label}: actor/title/where required")
            if page["kind"] == "quick":
                lines = step.get("do", [])
                words = sum(len(str(text).split()) for text in lines)
                words += sum(len(str(step.get(key, "")).split()) for key in ("warn", "bills", "danger", "see"))
                if len(lines) > 6 or words > 90 or not (lines or step.get("code") or step.get("codes")):
                    error(identifier, f"quick step {label} exceeds 6 lines/90 words or has no action")
                target, separator, anchor = str(step.get("more", "")).partition("#")
                detailed = loaded.get(f"pages/{target}.json", {})
                targets = {f"step-{REG.step_no(i, item)}" for i, item in enumerate(detailed.get("steps", []), 1)}
                if target not in pages or not separator or anchor not in targets:
                    error(identifier, f"quick step {label}: detailed target/step does not exist")
        if page["kind"] == "activity":
            for field in ("purpose", "starting_state", "expected", "copyable"):
                if field not in value or field != "copyable" and not value[field]:
                    error(identifier, f"A-G activity needs {field}")
            verify = value.get("verify", {})
            for field in ("success", "failures", "recovery"):
                if not verify.get(field):
                    error(identifier, f"verify.{field} missing")
            for failure in verify.get("failures", []):
                if any(not failure.get(key) for key in ("symptom", "cause", "fix")) or failure.get("repeat_safe") not in {"yes", "no", "careful"}:
                    error(identifier, "failure needs symptom/cause/fix/repeat safety")
            if not 3 <= len(value.get("say", [])) <= 8:
                error(identifier, "G needs 3-8 spoken lines")
        if page["kind"] == "reference":
            sections = value.get("sections", [])
            if len(sections) < 2 or any(not section.get("id") or not section.get("title") or not section.get("blocks") for section in sections):
                error(identifier, "reference needs two or more complete sections")
        for node in walk(value):
            if isinstance(node, dict) and set(node) == {"ref"} and node["ref"] not in named:
                error(identifier, f"unknown code ref {node['ref']}")
            if isinstance(node, dict) and "code" in node and set(node["code"]) != {"ref"}:
                error(identifier, "code must use one named source-bound ref, not an inline duplicate")
            if isinstance(node, dict) and "codes" in node:
                if any(set(code) != {"ref"} for code in node["codes"]):
                    error(identifier, "codes must contain named refs")
            if isinstance(node, dict) and "table" in node:
                table = node["table"]
                if any(len(row) != len(table["head"]) for row in table["rows"]):
                    error(identifier, "table row/head shape differs")
            if isinstance(node, str):
                for label in forbidden.scan(node):
                    error(identifier, label)
                for match in INLINE_LINK.finditer(node):
                    if match.group(1) not in pages:
                        error(identifier, f"unknown internal page {match.group(1)}")
        block_lists = []
        if page["kind"] == "activity":
            block_lists.extend(value[field] for field in ("purpose", "starting_state", "expected"))
            block_lists.extend(step.get("body", []) for step in steps)
            block_lists.extend(value["verify"].get(field, []) for field in ("success", "recovery", "limitations"))
        elif page["kind"] == "reference":
            block_lists.extend(section["blocks"] for section in value["sections"])
        for items in block_lists:
            for item in items:
                if not isinstance(item, dict) or len(item) != 1 or next(iter(item)) not in BLOCK_KEYS:
                    error(identifier, f"unknown/invalid typed block: {item}")
    extra = {file.stem for file in (CONTENT / "pages").glob("*.json")} - set(data)
    if extra:
        error("pages", f"unregistered content files: {sorted(extra)}")
    for identifier, item in loaded["links.json"]["links"].items():
        if item.get("kind") not in REG.LINK_KINDS or not item.get("href", "").startswith("https://"):
            error(identifier, "online links must be declared HTTPS user-clicked references")
    evidence = loaded["evidence.json"]
    expected_jobs = {"python", "java", "go", "config", "powershell (powershell)", "powershell (pwsh)",
                     "containers (python-emi-api)", "containers (java-ifsc-service)", "containers (go-fx-rates)"}
    for run in evidence["runs"]:
        if (not re.fullmatch(r"[0-9a-f]{40}", run["sha"]) or not run.get("observed_at")
                or {job["name"] for job in run["jobs"]} != expected_jobs
                or len(run["jobs"]) != 9 or run["status"] != "completed"
                or run["conclusion"] != "success"
                or any(job["status"] != "completed" or job["conclusion"] != "success" for job in run["jobs"])):
            error("evidence", "dated run/job observation shape is inconsistent")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-all", action="store_true")
    arguments = parser.parse_args()
    errors = validate(require_all=arguments.require_all)
    for error in errors:
        print("ERROR " + error)
    print(f"Content/source gate: {len(REG.SITE['pages'])} registered pages; {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
