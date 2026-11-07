"""Audit emitted HTML, links, assets, source text, privacy and offline script parsing."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

import forbidden
import registry as REG
import sources as S

ROOT = Path(__file__).resolve().parent.parent


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.duplicates, self.links, self.resources = set(), [], [], []
        self.h1 = 0
        self.current = []
        self.codes, self.inline_scripts = [], []
        self.code_figure = False
        self.capture_code = False
        self.placeholder = False
        self.code_text = ""
        self.script_text = None
        self.page_id = None
        self.csp = ""

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        identifier = attrs.get("id")
        if identifier:
            if identifier in self.ids:
                self.duplicates.append(identifier)
            self.ids.add(identifier)
        if tag == "body":
            self.page_id = attrs.get("data-page")
        if tag == "h1":
            self.h1 += 1
        if tag == "meta" and attrs.get("http-equiv", "").lower() == "content-security-policy":
            self.csp = attrs.get("content", "")
        if tag == "a":
            self.links.append((attrs.get("href", ""), attrs))
            if "nav-link" in attrs.get("class", "").split() and attrs.get("aria-current") == "page":
                self.current.append(attrs.get("data-page"))
        if tag in {"script", "img", "iframe", "source", "video", "audio", "object", "embed"} and attrs.get("src"):
            self.resources.append(attrs["src"])
        if tag == "link" and attrs.get("href"):
            self.resources.append(attrs["href"])
        if tag == "script":
            if attrs.get("type") == "module":
                self.resources.append("FORBIDDEN:module")
            if not attrs.get("src"):
                self.script_text = ""
        if tag == "figure":
            self.code_figure = "code" in attrs.get("class", "").split()
        if tag == "code" and self.code_figure:
            self.capture_code, self.code_text = True, ""
        if tag == "span" and self.capture_code and "ph" in attrs.get("class", "").split():
            self.code_text += "{{ph:" + attrs["data-token"] + "}}"
            self.placeholder = True

    def handle_endtag(self, tag):
        if tag == "span":
            self.placeholder = False
        if tag == "code" and self.capture_code:
            self.codes.append(self.code_text)
            self.capture_code = False
        if tag == "figure":
            self.code_figure = False
        if tag == "script" and self.script_text is not None:
            self.inline_scripts.append(self.script_text)
            self.script_text = None

    def handle_data(self, text):
        if self.capture_code and not self.placeholder:
            self.code_text += text
        if self.script_text is not None:
            self.script_text += text


def parse(file):
    page = Page()
    page.feed(file.read_text(encoding="utf-8"))
    return page


def refs(value):
    if isinstance(value, dict):
        if set(value) == {"ref"}:
            yield value["ref"]
        else:
            for item in value.values():
                yield from refs(item)
    elif isinstance(value, list):
        for item in value:
            yield from refs(item)


def check(use_lock=False):
    errors, not_run = [], []
    lock = json.loads(S.LOCK.read_text(encoding="utf-8"))
    if use_lock:
        not_run.append("NOT RUN: independent repository/pin comparison (--use-lock explicitly selected)")
        blocks = lock["blocks"]
    else:
        try:
            blocks = S.file_blocks()
            for identifier, block in blocks.items():
                if lock["blocks"].get(identifier, {}).get("sha256") != S.sha(block["text"]):
                    errors.append(f"stale source lock: {identifier}")
        except (OSError, ValueError, KeyError, RuntimeError) as exc:
            return [str(exc)], not_run
    metadata = {page["id"]: page for page in REG.SITE["pages"]}
    parsed = {}
    for file in sorted(ROOT.rglob("*.html")):
        page = parse(file)
        parsed[file.resolve()] = page
        if page.page_id not in metadata or page.h1 != 1 or page.current != [page.page_id] or page.duplicates:
            errors.append(f"{file.relative_to(ROOT)}: invalid page registry/H1/current navigation/duplicate anchors {page.duplicates}")
        if "connect-src 'none'" not in page.csp or "form-action 'none'" not in page.csp:
            errors.append(f"{file.relative_to(ROOT)}: offline/action CSP missing")
    if len(parsed) != len(metadata):
        errors.append(f"expected {len(metadata)} emitted pages, found {len(parsed)}")
    scripts = set()
    for file, page in parsed.items():
        identifier = page.page_id
        for resource in page.resources:
            if urlsplit(resource).scheme or resource.startswith("//") or resource.startswith("FORBIDDEN:"):
                errors.append(f"{identifier}: remote/module resource {resource}")
        for href, attrs in page.links:
            parts = urlsplit(href)
            if parts.scheme:
                if parts.scheme != "https" or not REG.url_allowed(href):
                    errors.append(f"{identifier}: undeclared external link {href}")
                if attrs.get("target") != "_blank" or not {"noopener", "noreferrer"} <= set(attrs.get("rel", "").split()):
                    errors.append(f"{identifier}: external link lacks safe user-clicked new-tab attributes")
                continue
            if href.startswith("//"):
                errors.append(f"{identifier}: protocol-relative link")
        for href in page.resources + [href for href, _ in page.links if not urlsplit(href).scheme]:
            parts = urlsplit(href)
            if not parts.path:
                destination = file
            else:
                destination = (file.parent / Path(*unquote(parts.path).split("/"))).resolve()
            if not destination.is_relative_to(ROOT.resolve()) or not destination.is_file():
                errors.append(f"{identifier}: absent/outside local target {href}")
            elif parts.fragment and destination in parsed and parts.fragment not in parsed[destination].ids:
                errors.append(f"{identifier}: missing anchor {href}")
        kind = metadata.get(identifier, {}).get("kind")
        if kind == "prompts":
            expected = [block["text"] for key, block in blocks.items() if key.startswith("prompt-")]
        elif kind == "home":
            expected = []
        else:
            source = ROOT / "src" / "content" / "pages" / f"{identifier}.json"
            expected = [blocks[key]["text"] for key in refs(json.loads(source.read_text(encoding="utf-8")))] if source.is_file() else []
        if Counter(expected) != Counter(page.codes):
            errors.append(f"{identifier}: emitted copyable text differs from its single source-bound definitions")
        scripts.update(page.inline_scripts)
    if set(lock["blocks"]) != set(blocks):
        errors.append("source lock block list differs")
    for identifier, block in lock["blocks"].items():
        if S.sha(block["text"]) != block["sha256"]:
            errors.append(f"source lock text/hash differs: {identifier}")
    for file in sorted(ROOT.rglob("*")):
        if not file.is_file() or "__pycache__" in file.parts:
            continue
        raw = file.read_bytes()
        if b"\r" in raw:
            errors.append(f"{file.relative_to(ROOT)}: expected LF bytes")
        if file.name == "forbidden.py":
            continue
        text = raw.decode("utf-8")
        for finding in forbidden.scan(text):
            errors.append(f"{file.relative_to(ROOT)}: {finding}")
        if file.suffix == ".css" and re.search(r"@import|url\(\s*['\"]?(?:https?:)?//", text):
            errors.append(f"{file.relative_to(ROOT)}: remote CSS/font load")
        if file.suffix == ".js" and re.search(r"\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts)\s*[.(]", text):
            errors.append(f"{file.relative_to(ROOT)}: network API")
    node = shutil.which("node")
    if node:
        for file in sorted(ROOT.rglob("*.js")):
            result = subprocess.run([node, "--check", str(file)], capture_output=True, text=True)
            if result.returncode:
                errors.append(f"{file.relative_to(ROOT)}: JavaScript parse failed: {result.stderr.strip()}")
        for script in scripts:
            result = subprocess.run([node, "--check", "-"], input=script, capture_output=True, text=True)
            if result.returncode:
                errors.append("Inline shell JavaScript parse failed: " + result.stderr.strip())
    else:
        not_run.append("NOT RUN: JavaScript parsing; installed Node absent")
    return errors, not_run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--use-lock", action="store_true")
    arguments = parser.parse_args()
    errors, not_run = check(use_lock=arguments.use_lock)
    for item in errors:
        print("ERROR " + item)
    for item in not_run:
        print(item)
    print(f"HTML/assets/source/offline gate: {len(REG.SITE['pages'])} pages; {len(errors)} errors; {len(not_run)} NOT RUN")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
