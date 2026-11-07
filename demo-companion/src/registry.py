"""Project registries shared by rendering and validation."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "src" / "content"
SITE = json.loads((CONTENT / "site.json").read_text(encoding="utf-8"))
LINKS = json.loads((CONTENT / "links.json").read_text(encoding="utf-8"))
FIELDNOTES = json.loads((CONTENT / "fieldnotes.json").read_text(encoding="utf-8"))
LINK_KINDS = ("repo", "learn", "open")
LINK_VERB = {"repo": "Open", "learn": "Read", "open": "Open"}
REGISTER_PAGES = tuple(p["id"] for p in SITE["pages"] if p["kind"] == "quick")


def link(identifier):
    return LINKS["links"][identifier]


def note(identifier):
    return FIELDNOTES["notes"][identifier]


def step_no(index, step):
    return str(step.get("no") or index)


def quick_steps(identifier):
    data = json.loads((CONTENT / "pages" / f"{identifier}.json").read_text(encoding="utf-8"))
    return [{**s, "_no": step_no(i, s)} for i, s in enumerate(data["steps"], 1)]


def url_allowed(url):
    if any(url == item["href"] for item in LINKS["links"].values()):
        return True
    base = SITE["repos"]["poc"]["url"]
    return url == base or url.startswith(base + "/")
