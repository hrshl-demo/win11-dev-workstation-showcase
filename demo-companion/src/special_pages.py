"""Home, source-bound prompt library and dated evidence register."""
import json
from pathlib import Path

import registry as REG
import sources as S
from render import (JOURNEYS, LEGEND, PAGES, PBY, ROOT, SITE, blocks, build_page_html,
                    code_block, esc, new_ctx, rel, status_badge, table_html)


def home_page(cur, page_info):
    context = new_ctx()
    data = S.resolve_page(json.loads((ROOT / "src" / "content" / "home.json").read_text(encoding="utf-8")))
    hero = (f'<header class="hero"><p class="eyebrow">Offline demo companion · Windows 11</p>'
            f'<h1>{esc(SITE["title"])}</h1><p class="lede">{esc(SITE["summary"])}</p>'
            f'<div class="cta"><a class="btn primary" href="{rel(cur, "quick-setup")}">Start the setup journey →</a>'
            f'<a class="btn quick" href="{rel(cur, "quick-develop")}">Already verified? Develop →</a>'
            '<button type="button" class="btn ghost" data-resume-big hidden>Resume</button>'
            '<button type="button" class="done-btn" data-done aria-pressed="false"><span class="ck" aria-hidden="true"></span><span class="dt">Mark page done</span></button></div></header>')
    cards = []
    for index, journey in enumerate(JOURNEYS, 1):
        pages = [p for p in PAGES if p["journey"] == journey["id"]]
        cards.append(f'<a class="jcard" href="{rel(cur, pages[0]["id"])}" style="--jc:{journey["color"]}">'
                     f'<span class="jnum" aria-hidden="true">{index:02}</span><h3>{esc(journey["title"])}</h3>'
                     f'<p>{esc(journey["summary"])}</p><span class="jmeta">{len(pages)} pages · manual progress</span>'
                     '<span class="jgo">Open journey <i aria-hidden="true">→</i></span></a>')
    legend = "".join(f'<li>{status_badge(key)}<span>{esc(item["desc"])}</span></li>'
                     for key, item in LEGEND["status"].items())
    sections = [
        {"id": "boundaries", "title": "What this companion does and never does", "html": blocks(data["boundaries"], cur, context)},
        {"id": "journeys", "title": "Choose your journey", "html": '<div class="jcards">' + "".join(cards) + "</div>"},
        {"id": "controls", "title": "Read, navigate, copy and print", "html": blocks(data["controls"], cur, context)},
        {"id": "trust", "title": "Evidence labels are scoped, not promises", "html": '<div class="legend"><ul>' + legend + "</ul></div>"},
    ]
    return build_page_html(cur, sections, context, top_html=hero, no_header=True), context


def prompts_page(cur):
    context = new_ctx()
    sections = [{"id": "boundaries", "title": "Select the named role; human approval stays separate",
                 "html": blocks([{"callout": {"kind": "warn", "text": "Exact source-bound setup/runbook prompts; Copy never sends a chat. Only human-selected Workstation setup in local Windows VS Code may drive approved setup/Restore/launch stages with native confirmations retained. Ordinary coding/build/desktop/cloud agents cannot. No agent gains repair, policy bypass, automatic elevation/restart, Git publication, cleanup or cloud execution."}}], cur, context)}]
    for block in S.prompts()[0]:
        sections.append({"id": block["id"], "title": block["label"], "html": code_block(block, cur, context)})
    return build_page_html(cur, sections, context, {"status": "documented", "repos": ["poc"], "duration": "Read and review; no timing promise", "cost": "Existing approved Copilot access"}), context


def evidence_page(cur, page_info):
    context = new_ctx()
    data = json.loads((ROOT / "src" / "content" / "evidence.json").read_text(encoding="utf-8"))
    rows = []
    for run in data["runs"]:
        jobs = ", ".join(f'{job["name"]}: {job["conclusion"]}' for job in run["jobs"])
        rows.append([run["branch"], f'`{run["sha"]}`', f'[Run {run["id"]}]({run["url"]})',
                     f'{run["status"]} / {run["conclusion"]}; {len(run["jobs"])} of {len(run["jobs"])} jobs successful',
                     jobs, run["observed_at"]])
    sections = [
        {"id": "scope", "title": "Dated repository evidence only",
         "html": blocks([{"p": data["scope"]}, {"callout": {"kind": "gap", "text": "Laptop setup, approved profile/source acceptance, Restore, F5, real sample/container requests and AKS deployment have NOT been proven live by this companion. A green hosted job or manual tick cannot establish any of them."}}], cur, context)},
        {"id": "repository-runs", "title": "Proven live: underlying source CI at the stated revisions",
         "html": table_html({"head": ["Branch", "Exact SHA", "Evidence", "Run result", "All job conclusions", "Observed"], "rows": rows}, cur)},
        {"id": "historical-ref", "title": "Historical ref is retained, not runnable",
         "html": blocks([{"p": f'Historical `demo-baseline` remains `{data["historical_baseline"]}`. Do not launch, reset runnable samples to, or deploy that unsafe historical source. Inspect reviewed `main`; `demo-complete` is a separate schedule fallback, never a deployment ref.'}], cur, context)},
    ]
    for identifier in REG.REGISTER_PAGES:
        manual = []
        for step in REG.quick_steps(identifier):
            no = step["_no"]
            detail = step["more"]
            manual.append([f'[Step {no}: {step["title"]}](page:{identifier}#step-{no})',
                           "Documented / not rehearsed on the laptop",
                           f'[Detailed instructions](page:{detail})',
                           "Human observation required; no automatic verification"])
        sections.append({"id": "manual-" + identifier, "title": PBY[identifier]["title"] + ": manual evidence gaps",
                         "html": table_html({"head": ["Step", "Trust label", "Source path", "Acceptance"], "rows": manual}, cur)})
    context["text"].append(" ".join(str(item) for item in data["runs"]))
    return build_page_html(cur, sections, context, {"status": "documented", "repos": ["poc"], "duration": "Dated observations, not live polling", "cost": "No automatic network access"}), context
