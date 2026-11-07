"""Generate committed offline pages/classic-script data. Viewing never needs this."""
import argparse
import json
import sys

import sources as S
import special_pages as SP
import validate_content
from render import (JBY, JOURNEYS, LEGEND, PAGES, PBY, REPOS, ROOT, SITE,
                    build_page_html, new_ctx, page_file, render_activity, render_quick, render_reference)


def write(url, text):
    file = ROOT / S.relative_path(url)
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(text, encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="compatibility flag; all builds are strict")
    parser.parse_args()
    errors = validate_content.validate(require_all=True)
    if errors:
        sys.exit("Content/source gate failed:\n" + "\n".join(errors))
    data = {}
    for page in PAGES:
        file = ROOT / "src" / "content" / "pages" / f"{page['id']}.json"
        if file.is_file():
            data[page["id"]] = S.resolve_page(json.loads(file.read_text(encoding="utf-8")))
            page["status_for_nav"] = data[page["id"]]["status"]
        elif page["kind"] in {"prompts", "evidence"}:
            page["status_for_nav"] = "documented"
    output, contexts, info = {}, {}, {}
    for page in PAGES:
        identifier, kind = page["id"], page["kind"]
        if kind not in {"activity", "reference", "quick"}:
            continue
        value = data[identifier]
        value.setdefault("repos", ["poc"])
        context = new_ctx()
        sections = {"activity": render_activity, "reference": render_reference, "quick": render_quick}[kind](identifier, value, context)
        output[identifier] = build_page_html(identifier, sections, context, value)
        contexts[identifier] = context
        info[identifier] = {"status": value["status"], "gaps": value.get("evidence_gaps", [])}
    for page in PAGES:
        identifier = page["id"]
        if page["kind"] == "prompts":
            output[identifier], contexts[identifier] = SP.prompts_page(identifier)
            info[identifier] = {"status": "documented"}
    output["index"], contexts["index"] = SP.home_page("index", info)
    info["index"] = {"status": None}
    for page in PAGES:
        if page["kind"] == "evidence":
            identifier = page["id"]
            output[identifier], contexts[identifier] = SP.evidence_page(identifier, info)
            info[identifier] = {"status": "documented"}
    for identifier, html in output.items():
        write(page_file(identifier), html)
    tokens = {}
    for block in S.file_blocks().values():
        for placeholder in block.get("placeholders", []):
            token = placeholder["token"]
            if token in tokens and tokens[token] != placeholder:
                sys.exit(f"Inconsistent shared placeholder: {token}")
            tokens[token] = placeholder
    page_data = [
        {"id": page["id"], "journey": page["journey"], "order": page["order"], "kind": page["kind"],
         "title": page["title"], "short": page.get("short") or page["title"],
         "summary": data.get(page["id"], {}).get("summary", page.get("summary", "")),
         "status": info[page["id"]]["status"], "url": page_file(page["id"]),
         "steps": len(data.get(page["id"], {}).get("steps", []))}
        for page in PAGES
    ]
    site = {"title": SITE["title"], "short": SITE["short"], "version": SITE["version"],
            "asOf": SITE["as_of"], "journeys": JOURNEYS, "pages": page_data,
            "repos": REPOS, "legend": LEGEND, "tokens": tokens}
    search = [{"id": page["id"], "t": page["title"], "j": JBY[page["journey"]]["short"],
               "s": data.get(page["id"], {}).get("summary", ""),
               "x": " ".join(text for text in contexts[page["id"]]["text"] if text)}
              for page in PAGES]
    write("data/site.js", "/* generated: no network requests */\nwindow.DC_SITE = " + json.dumps(site, ensure_ascii=False, separators=(",", ":")) + ";\n")
    write("data/search.js", "/* generated: offline local index */\nwindow.DC_SEARCH = " + json.dumps(search, ensure_ascii=False, separators=(",", ":")) + ";\n")
    S.write_lock()
    print(f"Built {len(output)} offline pages, {len(tokens)} non-sensitive value field, {len(S.file_blocks())} source-bound blocks; LF output")


if __name__ == "__main__":
    main()
