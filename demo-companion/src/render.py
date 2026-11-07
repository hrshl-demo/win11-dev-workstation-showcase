"""Rendering helpers for the Demo Companion generator: inline markup, blocks, steps, page kinds, the app shell."""
import html
import json
import posixpath
import re
from pathlib import Path

import quick
import registry as REG

ROOT = Path(__file__).resolve().parent.parent
SITE = json.loads((ROOT / "src" / "content" / "site.json").read_text(encoding="utf-8-sig"))
DIAGRAMS = json.loads((ROOT / "src" / "content" / "diagrams.json").read_text(encoding="utf-8-sig"))
LEGEND, REPOS, JOURNEYS, LINKS = SITE["legend"], SITE["repos"], SITE["journeys"], SITE.get("links", {})
JIDX = {j["id"]: i for i, j in enumerate(JOURNEYS)}
JBY = {j["id"]: j for j in JOURNEYS}
PAGES = sorted(SITE["pages"], key=lambda p: (JIDX[p["journey"]], p["order"]))
PBY = {p["id"]: p for p in PAGES}
PH = re.compile(r"\{\{ph:([^}]+)\}\}")
SHELL_VERSION = "1"


def esc(s):
    return html.escape(str(s), quote=True)


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", str(s).lower()).strip("-") or "section"


def page_file(pid):
    return "index.html" if pid == "index" else f"pages/{PBY[pid]['journey']}/{pid}.html"


def root_of(pid):
    return "" if pid == "index" else "../../"


def rel(cur, target, anchor=""):
    cur_dir = posixpath.dirname(page_file(cur)) or "."
    return posixpath.relpath(page_file(target), cur_dir) + (anchor or "")


def png_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")
    except OSError:
        pass
    return None


def new_ctx():
    return {"tokens": {}, "diagrams": [], "shots": [], "text": [], "toc": []}


# ---------------------------------------------------------------- inline markup
CODE_RE = re.compile(r"`([^`]+)`")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
BOLD_RE = re.compile(r"\*\*([^*]+)\*\*")


def inline(text, cur):
    s = str(text)
    stash = []

    def keep(m):
        body = html.escape(m.group(1), quote=False)
        if "/" in body and len(body) >= 12:
            body = body.replace("/", "/<wbr>")
        if "\\" in body:
            body = body.replace("\\", "\\<wbr>")
        stash.append("<code>" + body + "</code>")
        return f"\x00{len(stash) - 1}\x00"

    s = CODE_RE.sub(keep, s)
    s = html.escape(s, quote=False)

    def link(m):
        label, href = m.group(1), m.group(2)
        if href.startswith("page:"):
            pid, _, anc = href[5:].partition("#")
            if pid not in PBY:
                return m.group(0)
            return f'<a class="xref" href="{rel(cur, pid, ("#" + anc) if anc else "")}">{label}</a>'
        if href.startswith("#"):
            return f'<a class="xref" href="{esc(html.unescape(href))}">{label}</a>'
        if href.startswith("asset:"):
            return f'<a class="ext" href="{root_of(cur)}assets/files/{esc(href[6:])}" download>{label}</a>'
        if href.startswith(("http://", "https://")):
            return f'<a class="ext" href="{esc(html.unescape(href))}" target="_blank" rel="noopener noreferrer">{label}</a>'
        return m.group(0)

    s = LINK_RE.sub(link, s)
    s = BOLD_RE.sub(r"<strong>\1</strong>", s)
    return re.sub(r"\x00(\d+)\x00", lambda m: stash[int(m.group(1))], s)


def plain(text):
    """Text without markup, for the search index and plain-text fallbacks."""
    s = re.sub(r"`([^`]+)`", r"\1", str(text))
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    return s.replace("**", "")


# ---------------------------------------------------------------- repo references
SKILLS = {k: v for k, v in SITE.get("skills_catalog", {}).items() if not k.startswith("_")}


def resolve_ref(ref):
    """A reference to Microsoft's skills repository may name a skill: its folder comes from the verified catalog."""
    if ref.get("skill") and not ref.get("path"):
        return {**ref, "path": f"skills/{ref['skill']}/"}
    return ref


def tool_ref(t):
    """Reference for an entry of a prompt's 'tools' list: a Microsoft skill links to its own folder, anything else keeps its label."""
    if t.get("repo") == "skills" and t["name"] in SKILLS:
        return {"repo": "skills", "skill": t["name"]}
    return {"repo": t.get("repo", "content"), "label": t["name"]}


def repo_url(ref):
    ref = resolve_ref(ref)
    r = REPOS[ref["repo"]]
    path = (ref.get("path") or "").strip().replace("\\", "/")
    pin = ref.get("ref")
    if pin == "commit":
        pin = r.get("commit")
    pin = pin or r.get("commit") or r.get("branch", "main")
    if not path:
        return r["url"]
    kind = "tree" if path.endswith("/") else "blob"
    return f"{r['url']}/{kind}/{pin}/{path.rstrip('/') if kind == 'tree' else path}"


def repo_chip(ref, cur, with_why=True):
    ref = resolve_ref(ref)
    r = REPOS[ref["repo"]]
    path = ref.get("path") or ""
    label = ref.get("label")
    shown = f"<code>{esc(path)}</code>" if path else ""
    name = esc(r["label"])
    why = f'<span class="why">{inline(ref["why"], cur)}</span>' if with_why and ref.get("why") else ""
    what = SKILLS.get(ref.get("skill") or "", {}).get("what")
    said = f'<span class="why skill-what">Microsoft: {esc(what)}</span>' if what else ""
    lab = f'<span class="rlabel">{esc(label)}</span>' if label else ""
    note = f'<span class="why">{inline(ref["note"], cur)}</span>' if ref.get("note") else ""
    return (f'<a class="repo-chip" style="--rc:{r["color"]}" href="{esc(repo_url(ref))}" target="_blank" rel="noopener noreferrer">'
            f'<span class="rdot" aria-hidden="true"></span><span class="rname">{name}</span>{lab}{shown}</a>{why}{said}{note}')


def repo_list(refs, cur, title="Repository behind this step"):
    """Only repositories flagged step_box in site.json (Microsoft's skills repository) get a box under a step."""
    shown = [r for r in (refs or []) if REPOS[r["repo"]].get("step_box")]
    if not shown:
        return ""
    items = "".join(f'<li>{repo_chip(r, cur)}</li>' for r in shown)
    return f'<div class="step-repo"><h4>{esc(title)}</h4><ul>{items}</ul></div>'


# ---------------------------------------------------------------- blocks
def code_block(c, cur, ctx, extra=""):
    actor = c.get("actor", "terminal")
    a = LEGEND["actors"].get(actor if actor != "file" else "generated", LEGEND["actors"]["generated"])
    metadata = {p["token"]: p for p in (c.get("placeholders") or [])}
    how = {token: p.get("how", "") for token, p in metadata.items()}
    text = c["text"]
    out, pos = [], 0
    for m in PH.finditer(text):
        out.append(html.escape(text[pos:m.start()], quote=False))
        tok = m.group(1)
        ctx["tokens"].setdefault(tok, metadata[tok])
        out.append(f'<span class="ph" data-token="{esc(tok)}" tabindex="0" title="{esc(how.get(tok, "Replace with your value"))}">&lt;{esc(tok)}&gt;</span>')
        pos = m.end()
    out.append(html.escape(text[pos:], quote=False))
    kind_label = {"terminal": "Copy only · human action", "copilot": "Copy only · choose the named agent", "file": "Documented material"}.get(actor, actor)
    note = f'<p class="code-note">{inline(c["note"], cur)}</p>' if c.get("note") else ""
    ctx["text"].append(c.get("label", ""))
    ctx["text"].append(plain(text))
    if c.get("note"):
        ctx["text"].append(plain(c["note"]))
    return (f'<figure class="code {extra}" data-actor="{esc(actor)}" style="--ac:{a["color"]}">'
            f'<figcaption><span class="actor-glyph" aria-hidden="true">{esc(a["glyph"])}</span>'
            f'<span class="code-label">{esc(c.get("label", ""))}</span>'
            f'<span class="code-kind">{esc(kind_label)} · {esc(c.get("lang", ""))}</span>'
            f'<button class="copy" type="button" data-copy aria-label="Copy: {esc(c.get("label", ""))}"><span class="copy-ico" aria-hidden="true"></span><span class="copy-txt">Copy</span></button></figcaption>'
            f'<pre tabindex="0"><code class="lang-{esc(c.get("lang", ""))}">{"".join(out)}</code></pre>{note}</figure>')


def screenshot(s, cur, ctx):
    cap = inline(s.get("caption", ""), cur)
    if s.get("placeholder"):
        name = s.get("file") or ""
        real = (ROOT / "assets" / "screens" / name) if name else None
        if real is not None and real.is_file():        # the real capture was dropped into assets/screens/: it replaces the placeholder
            ctx.setdefault("screens", []).append(name)
            dim = png_size(real)
            wh = f' width="{dim[0]}" height="{dim[1]}"' if dim else ""
            return (f'<figure class="shot"><div class="shot-img" data-lightbox><img src="{root_of(cur)}assets/screens/{esc(name)}" alt="{esc(s.get("alt", ""))}"{wh} loading="lazy">'
                    f'<span class="shot-tag">Real screenshot</span></div><figcaption>{cap}</figcaption></figure>')
        ctx["shots"].append({"capture": s["capture"], "caption": plain(s.get("caption", "")), "file": name})
        fname = (f'<p class="ph-file">Save the capture as <code>assets/screens/{esc(name)}</code>; the site then shows it here.</p>' if name else "")
        return (f'<figure class="shot placeholder"><div class="ph-box"><span class="ph-badge">Capture placeholder · not evidence</span>'
                f'<p><strong>Capture this:</strong> {esc(s["capture"])}</p>{fname}</div><figcaption>{cap}</figcaption></figure>')
    src = s["file"]
    dim = png_size(ROOT / src)
    wh = f' width="{dim[0]}" height="{dim[1]}"' if dim else ""
    pins = "".join(f'<button type="button" class="pin" style="left:{p["x"]}%;top:{p["y"]}%" data-pin="{p["n"]}" aria-label="Pin {p["n"]}: {esc(p["text"])}">{p["n"]}</button>' for p in s.get("pins", []) or [])
    plist = ""
    if s.get("pins"):
        plist = '<ol class="pin-list">' + "".join(f'<li value="{p["n"]}"><b>{p["n"]}</b> {inline(p["text"], cur)}</li>' for p in s["pins"]) + "</ol>"
    return (f'<figure class="shot"><div class="shot-img" data-lightbox><img src="{root_of(cur)}{esc(src)}" alt="{esc(s.get("alt", ""))}"{wh} loading="lazy">{pins}'
            f'<span class="shot-tag">Real screenshot</span></div><figcaption>{cap}</figcaption>{plist}</figure>')


def callout(c, cur):
    icon = {"info": "i", "tip": "★", "warn": "!", "danger": "✕", "billing": "$", "gap": "?"}.get(c["kind"], "i")
    title = f'<strong class="co-title">{esc(c["title"])}</strong>' if c.get("title") else ""
    return (f'<aside class="callout" data-kind="{esc(c["kind"])}" role="note"><span class="co-ico" aria-hidden="true">{icon}</span>'
            f'<div>{title}<p>{inline(c["text"], cur)}</p></div></aside>')


def fieldnote_html(nid, cur, ctx, short=False):
    """A coordinator field note: one text in fieldnotes.json, one fixed label, wherever it is shown."""
    n = REG.note(nid)
    text = n["short"] if short else n["text"]
    ctx["text"].append(plain(f'{n["title"]} {text}'))
    title = f"Field note {nid}" if short else f'Field note {nid} · {n["title"]}'
    return (f'<aside class="callout fieldnote" data-kind="field" role="note"><span class="co-ico" aria-hidden="true">F</span>'
            f'<div><strong class="co-title">{esc(title)}</strong><p>{inline(text, cur)}</p>'
            f'<p class="fn-label">{esc(REG.FIELDNOTES["label"])}</p></div></aside>')


def open_links(ids, ctx):
    """The 'Open ...' buttons of a step: addresses come from links.json only; each opens in a new tab and carries the arrow."""
    out = []
    for lid in ids or []:
        lk = REG.link(lid)
        verb = REG.LINK_VERB[lk["kind"]]
        out.append(f'<a class="btn url open-{lk["kind"]}" href="{esc(lk["href"])}" target="_blank" rel="noopener noreferrer">{esc(verb)} {esc(lk["label"])} <span aria-hidden="true">↗</span></a>')
        ctx["text"].append(f'{verb} {lk["label"]}')
    return '<div class="open-links">' + "".join(out) + "</div>" if out else ""


def checklist_html(spec, cur, ctx):
    """Tick boxes, one per step of a quick page, each with a link to the quick step and to its details. State is kept in this browser."""
    src = spec["from"]
    items = []
    for s in REG.quick_steps(src):
        no = s["_no"]
        more = s.get("more")
        ids = more if isinstance(more, list) else ([more] if more else [])
        det = ""
        if ids:
            pid, _, anc = ids[0].partition("#")
            det = f' · <a class="xref" href="{rel(cur, pid, ("#" + anc) if anc else "")}">details</a>'
        ctx["text"].append(f'{no}. {plain(s["title"])}')
        items.append(f'<li><label class="chk"><input type="checkbox" data-tick="{esc(src)}:{esc(no)}"><span class="chk-box" aria-hidden="true"></span>'
                     f'<span class="chk-text"><b>{esc(no)}.</b> {inline(s["title"], cur)}</span></label>'
                     f'<span class="chk-links"><a class="xref" href="{rel(cur, src, "#step-" + no)}">quick step</a>{det}</span></li>')
    return (f'<p class="chk-summary" data-tick-summary="{esc(src)}" aria-live="polite"></p>'
            f'<ul class="chk-list" aria-label="{esc(spec.get("title", "Steps"))}">{"".join(items)}</ul>')


def table_html(t, cur):
    head = "".join(f"<th scope=\"col\">{inline(h, cur)}</th>" for h in t["head"])
    rows = "".join("<tr>" + "".join(f"<td>{inline(c, cur)}</td>" for c in r) + "</tr>" for r in t["rows"])
    return f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{rows}</tbody></table></div>'


def block(b, cur, ctx):
    k, v = next(iter(b.items()))
    if k == "p":
        ctx["text"].append(plain(v))
        return f"<p>{inline(v, cur)}</p>"
    if k == "h":
        ctx["text"].append(plain(v))
        return f'<h3 class="sub" id="{slug(v)}">{inline(v, cur)}</h3>'
    if k in ("ul", "ol"):
        ctx["text"].extend(plain(i) for i in v)
        return f"<{k}>" + "".join(f"<li>{inline(i, cur)}</li>" for i in v) + f"</{k}>"
    if k == "callout":
        ctx["text"].append(plain(v["text"]))
        return callout(v, cur)
    if k == "table":
        for r in v["rows"]:
            ctx["text"].extend(plain(c) for c in r)
        return table_html(v, cur)
    if k == "kv":
        ctx["text"].extend(plain(value) for pair in v for value in pair)
        return '<dl class="kv">' + "".join(f"<div><dt>{inline(a, cur)}</dt><dd>{inline(b2, cur)}</dd></div>" for a, b2 in v) + "</dl>"
    if k == "code":
        return code_block(v, cur, ctx)
    if k == "quote":
        return (f'<figure class="real-output"><figcaption><span class="ro-badge">Documented example · not observed</span> {esc(v["label"])}</figcaption>'
                f'<pre tabindex="0"><code>{html.escape(v["text"], quote=False)}</code></pre><p class="ro-src">Source: {esc(v["source"])}</p></figure>')
    if k == "screenshot":
        return screenshot(v, cur, ctx)
    if k == "link":
        note = f'<span class="lc-note">{inline(v["note"], cur)}</span>' if v.get("note") else ""
        if str(v["href"]).startswith("asset:"):
            return (f'<a class="link-card" href="{root_of(cur)}assets/files/{esc(v["href"][6:])}" download><span class="lc-label">{esc(v["label"])}</span>{note}'
                    f'<span class="lc-url">in this folder: assets/files/{esc(v["href"][6:])}</span></a>')
        return (f'<a class="link-card" href="{esc(v["href"])}" target="_blank" rel="noopener noreferrer"><span class="lc-label">{esc(v["label"])}</span>{note}'
                f'<span class="lc-url">{esc(re.sub(r"^https?://", "", v["href"]))}</span></a>')
    if k == "diagram":
        return diagram_figure(v, cur, ctx)
    if k == "more":                                    # only built by render_quick: a small link to the detailed page(s); 'page#step-6' names the step
        ids = v if isinstance(v, list) else [v]
        parts = []
        for ref in ids:
            pid, _, anc = ref.partition("#")
            label = PBY[pid]["title"] + (f" · step {anc[5:]}" if anc.startswith("step-") else "")
            parts.append(f'<a class="xref" href="{rel(cur, pid, ("#" + anc) if anc else "")}">{esc(label)}</a>')
            ctx["text"].append(label)
        return f'<p class="quick-more">Details: {", ".join(parts)}</p>'
    if k == "fieldnote":                               # a coordinator field note, full text, from fieldnotes.json
        return fieldnote_html(v, cur, ctx)
    if k == "fieldnote_short":                         # only built by quick_step: the same note, short
        return fieldnote_html(v, cur, ctx, short=True)
    if k == "checklist":                               # tick boxes generated from the steps of a quick page
        return checklist_html(v, cur, ctx)
    if k == "value":                                   # only built by quick_step: the field for a value, inside the step whose command needs it
        metadata = ctx["tokens"].setdefault(v["token"], v)
        ctx["text"].append(v["token"])
        return f'<div class="values v-inline">{value_row(v["token"], metadata["how"], metadata)}</div>'
    raise ValueError(f"unknown content block: {k}")


def blocks(bs, cur, ctx):
    return "".join(block(b, cur, ctx) for b in (bs or []))


# ---------------------------------------------------------------- badges and small parts
def actor_badge(actor):
    a = LEGEND["actors"][actor]
    return f'<span class="actor-badge" data-actor="{actor}" style="--ac:{a["color"]}"><b aria-hidden="true">{esc(a["glyph"])}</b>{esc(a["label"])}</span>'


def status_badge(status):
    if not status:
        return ""
    s = LEGEND["status"][status]
    return f'<span class="badge status" data-status="{status}" title="{esc(s["desc"])}">{esc(s["label"])}</span>'


def where_html(where):
    parts = [p.strip() for p in str(where).split("›") if p.strip()]
    return '<p class="where" aria-label="Where this happens">' + '<i aria-hidden="true">›</i>'.join(f"<span>{esc(p)}</span>" for p in parts) + "</p>"


def diagram_figure(did, cur, ctx, title=None):
    d = DIAGRAMS.get(did) or ctx.get("extra_diagrams", {}).get(did)
    if not d:
        raise KeyError(f"unknown diagram '{did}'")
    if did not in ctx["diagrams"]:
        ctx["diagrams"].append(did)
    steps = "".join(f'<li><strong>{esc(s["title"])}.</strong> {esc(s["text"])}</li>' for s in d.get("steps", []))
    return (f'<figure class="diagram" data-diagram="{esc(did)}" aria-label="{esc(d["title"])}">'
            f'<figcaption class="dg-title"><span>{esc(title or d["title"])}</span><em>{esc(d.get("caption", ""))}</em></figcaption>'
            f'<div class="dg-stage" role="img" aria-label="{esc(d["title"] + ". " + d.get("caption", ""))}"></div>'
            f'<ol class="dg-steps">{steps}</ol></figure>')


# ---------------------------------------------------------------- steps
def step_html(i, s, cur, ctx):
    a = s["actor"]
    ac = LEGEND["actors"][a]
    label = REG.step_no(i, s)                          # the number shown: the step's own 'no' (6, 6a) or its position on the page
    time = f'<span class="time" title="Expected duration">{esc(s["time"])}</span>' if s.get("time") else ""
    status = status_badge(s["status"]) if s.get("status") else ""
    url = ""
    if s.get("url"):
        url = f'<a class="btn url" href="{esc(s["url"]["href"])}" target="_blank" rel="noopener noreferrer">{esc(s["url"]["label"])} <span aria-hidden="true">↗</span></a>'
    url += open_links(s.get("open"), ctx)
    shot = screenshot(s["shot"], cur, ctx) if s.get("shot") else ""
    expect = f'<div class="expect"><b>You should see</b><p>{inline(s["expect"], cur)}</p></div>' if s.get("expect") else ""
    ctx["text"].append(s["title"])
    return (f'<li class="step" id="step-{esc(label)}" data-actor="{a}" data-step="{i}" data-no="{esc(label)}" style="--ac:{ac["color"]}">'
            f'<div class="step-head"><label class="step-check" title="Mark this step as done"><input type="checkbox" data-step-check aria-label="Step {esc(label)} done"><span class="num">{esc(label)}</span></label>'
            f'{actor_badge(a)}<h3>{inline(s["title"], cur)}</h3>{status}{time}</div>'
            f'{where_html(s["where"])}<div class="step-body">{blocks(s.get("body"), cur, ctx)}{url}{shot}</div>'
            f'{repo_list(s.get("repo"), cur)}{expect}</li>')


# ---------------------------------------------------------------- navigation chrome
def sidebar_html(cur):
    cur_j = PBY[cur]["journey"]
    out = ['<div class="side-search"><button type="button" class="search-open" data-search-open aria-label="Search the guide"><span aria-hidden="true">⌕</span> Search <kbd>/</kbd></button></div>']
    out.append('<div class="side-progress" data-overall><span class="sp-bar"><i></i></span><span class="sp-text">0 of 0 pages done</span><small>Manual progress, not machine verification.</small></div>')
    for j in JOURNEYS:
        pages = [p for p in PAGES if p["journey"] == j["id"]]
        open_ = " open" if j["id"] == cur_j else ""
        lis = []
        for p in pages:
            st = p.get("status_for_nav")
            cur_attr = ' aria-current="page"' if p["id"] == cur else ""
            lis.append(f'<li><a class="nav-link" href="{rel(cur, p["id"])}" data-page="{p["id"]}"{cur_attr}>'
                       f'<span class="st" data-status="{st or "none"}" aria-hidden="true"></span><span class="nl-t">{esc(p.get("short") or p["title"])}</span><span class="tick" aria-hidden="true"></span></a></li>')
        out.append(f'<details class="nav-journey" data-journey="{j["id"]}"{open_} style="--jc:{j["color"]}"><summary><span class="jdot" aria-hidden="true"></span>'
                   f'<span class="jt">{esc(j["title"])}</span><span class="jcount" data-jcount="{j["id"]}">{len(pages)}</span></summary><ul>{"".join(lis)}</ul></details>')
    return "".join(out)


def journey_bar(cur):
    if cur == "index":
        return ""
    reg = PBY[cur]
    j = JBY[reg["journey"]]
    pages = [p for p in PAGES if p["journey"] == j["id"]]
    idx = [p["id"] for p in pages].index(cur) + 1
    dots = "".join(f'<a class="jd" href="{rel(cur, p["id"])}" data-page="{p["id"]}" title="{esc(p["title"])}"{" aria-current=\"page\"" if p["id"] == cur else ""}><span class="sr">{esc(p["title"])}</span></a>' for p in pages)
    return (f'<div class="journey-bar" style="--jc:{j["color"]}"><span class="jb-label"><b>{esc(j["title"])}</b> · page {idx} of {len(pages)}</span>'
            f'<span class="jb-dots" aria-hidden="false">{dots}</span></div>')


def crumbs(cur):
    reg = PBY[cur]
    j = JBY[reg["journey"]]
    if cur == "index":
        return ""
    first = [p for p in PAGES if p["journey"] == j["id"]][0]
    return (f'<nav class="crumbs" aria-label="Breadcrumb"><a href="{rel(cur, "index")}">Home</a><i aria-hidden="true">›</i>'
            f'<a href="{rel(cur, first["id"])}" style="--jc:{j["color"]}">{esc(j["title"])}</a><i aria-hidden="true">›</i><span aria-current="page">{esc(reg.get("short") or reg["title"])}</span></nav>')


def pager(cur):
    ids = [p["id"] for p in PAGES]
    i = ids.index(cur)
    def card(pid, direction):
        if pid is None:
            return '<span class="pg pg-empty"></span>'
        p = PBY[pid]
        j = JBY[p["journey"]]
        arrow = "←" if direction == "prev" else "→"
        label = "Previous" if direction == "prev" else "Next"
        return (f'<a class="pg pg-{direction}" rel="{direction}" href="{rel(cur, pid)}" style="--jc:{j["color"]}"><span class="pg-dir">{arrow} {label}</span>'
                f'<span class="pg-title">{esc(p["title"])}</span><span class="pg-j">{esc(j["short"])}</span></a>')
    return f'<nav class="pager" aria-label="Previous and next page">{card(ids[i - 1] if i > 0 else None, "prev")}{card(ids[i + 1] if i + 1 < len(ids) else None, "next")}</nav>'


def shell(cur, title, main_html, toc, description=""):
    reg = PBY[cur]
    j = JBY[reg["journey"]]
    root = root_of(cur)
    toc_html = ""
    if toc:
        toc_html = '<nav class="toc" aria-label="On this page"><h2>On this page</h2><ol>' + "".join(
            f'<li class="{"sub" if t.get("sub") else ""}"><a href="#{esc(t["id"])}">{esc(t["label"])}</a></li>' for t in toc) + "</ol></nav>"
    return f"""<!doctype html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} · {esc(SITE["short"])}</title>
<meta name="description" content="{esc(description or reg.get("summary", ""))}">
<meta name="color-scheme" content="light dark">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' file: 'unsafe-inline'; style-src 'self' file: 'unsafe-inline'; img-src 'self' file: data:; connect-src 'none'; font-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<link rel="stylesheet" href="{root}assets/css/app.css">
<link rel="stylesheet" href="{root}assets/css/deck.css">
<script>var m=/[?&]theme=(light|dark)/.exec(location.search);if(m)document.documentElement.setAttribute('data-theme',m[1]);try{{var t=m?m[1]:localStorage.getItem('w11dc.theme');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t);if(m)localStorage.setItem('w11dc.theme',m[1]);}}catch(e){{window.DC_STORAGE_ISSUES=['Guide theme storage is unavailable; changes may not survive navigation.'];}}if(!/[?&]deck=off\\b/.test(location.search)&&((window.innerWidth>=600&&window.innerHeight>=520)||/[?&]deck=on\\b/.test(location.search))){{document.documentElement.classList.add('deck-pending');setTimeout(function(){{document.documentElement.classList.remove('deck-pending')}},3500);}}</script>
</head>
<body data-page="{cur}" data-journey="{j["id"]}" data-root="{root}" style="--jc:{j["color"]}">
<a class="skip" href="#main">Skip to content</a>
<header class="topbar">
<button class="icon-btn menu-btn" type="button" data-menu aria-label="Open the navigation" aria-expanded="false"><span></span></button>
<a class="brand" href="{rel(cur, "index")}"><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">{esc(SITE["short"])}</span><span class="brand-sub">{esc(SITE["project"])}</span></a>
<div class="top-actions">
<button class="top-btn" type="button" data-resume title="Continue where you left off" hidden>Resume</button>
<button class="top-btn" type="button" data-search-open title="Search (press /)"><span aria-hidden="true">⌕</span><span class="tb-t">Search</span></button>
<button class="top-btn" type="button" data-help title="Keyboard shortcuts (press ?)"><span aria-hidden="true">⌨</span><span class="tb-t">Keys</span></button>
<div class="seg" role="group" aria-label="Colour theme"><button type="button" data-theme-set="light" aria-pressed="true" title="Light mode (press T to switch)"><span aria-hidden="true">☀</span><span class="tb-t">Light</span></button><button type="button" data-theme-set="dark" aria-pressed="false" title="Dark mode (press T to switch)"><span aria-hidden="true">☾</span><span class="tb-t">Dark</span></button></div>
</div>
</header>
<aside class="storage-warning" data-storage-warning role="status" hidden><strong>Guide storage limitation</strong><ul></ul><button type="button" class="btn ghost" data-dismiss-storage>Dismiss</button></aside>
<div class="app">
<nav class="sidebar" id="sidebar" aria-label="Guide navigation">{sidebar_html(cur)}</nav>
<div class="scrim" data-scrim></div>
<main id="main" tabindex="-1">
<div class="wrap">
{crumbs(cur)}
{journey_bar(cur)}
{main_html}
{pager(cur)}
<footer class="foot"><p>{esc(SITE["title"])} · guide version {esc(SITE["version"])} · written from repository commit {esc(REPOS["poc"]["commit"])} · facts as of {esc(SITE["as_of"])}. Synthetic data only. Anything not verified is marked.</p></footer>
</div>
</main>
{toc_html}
</div>
<script src="{root}data/site.js"></script>
<script src="{root}data/search.js"></script>
<script src="{root}assets/js/app.js"></script>
<script src="{root}assets/js/deck.js"></script>
</body>
</html>
"""


# ---------------------------------------------------------------- page header and assembly
def header_html(cur, d=None, kicker=None):
    reg = PBY[cur]
    j = JBY[reg["journey"]]
    d = d or {}
    title = d.get("title") or reg["title"]
    summary = d.get("summary") or reg.get("summary", "")
    chips = []
    if d.get("status"):
        chips.append(status_badge(d["status"]))
    if d.get("duration"):
        chips.append(f'<span class="badge meta" title="How long this takes"><span aria-hidden="true">⏱</span> {esc(d["duration"])}</span>')
    if d.get("cost"):
        chips.append(f'<span class="badge meta cost" title="What it costs"><span aria-hidden="true">$</span> {esc(d["cost"])}</span>')
    rk = d.get("repos") or []
    for k in rk:
        r = REPOS[k]
        chips.append(f'<a class="badge repo" style="--rc:{r["color"]}" href="{esc(r["url"])}" target="_blank" rel="noopener noreferrer"><span class="rdot"></span>{esc(r["label"])}</a>')
    billing = ""
    if d.get("billable"):
        billing = ('<aside class="billing-banner" role="note"><span aria-hidden="true">$</span><div><strong>This page starts something that bills.</strong> '
                   'Only a separately authorized human can perform these actions. Read the prerequisites and independent approval gates first. This HTML never dispatches or deploys.</div></aside>')
    action = ""
    if d.get("action_notice"):
        action = ('<aside class="billing-banner action-banner" role="note"><span aria-hidden="true">!</span><div><strong>Separate human approval required.</strong> '
                  f'{esc(d["action_notice"])}</div></aside>')
    done = '<button class="done-btn" type="button" data-done aria-pressed="false"><span class="ck" aria-hidden="true"></span><span class="dt">Mark page done</span></button>' if reg["kind"] not in ("home",) else ""
    return (f'<header class="page-head"><p class="kicker" style="--jc:{j["color"]}">{esc(kicker or j["title"])}</p><h1>{esc(title)}</h1>'
            f'<p class="lede">{inline(summary, cur)}</p><div class="chips">{"".join(chips)}{done}</div>'
            '<p class="manual-note">Copy-only instructions. Checkmarks are manual progress, not laptop verification.</p></header>' + action + billing)


def value_row(tok, how, metadata=None):
    """One value field: the same markup in the Your values panel and, on the quick pages, inside the step that needs it (every field of a token stays in step through app.js)."""
    metadata = metadata or {}
    constraints = f' maxlength="{int(metadata.get("max_length", 40))}" pattern="{esc(metadata.get("pattern", "[0-9a-f]{{40}}"))}"'
    return (f'<label class="v-row"><span class="v-name">{esc(tok)}</span><span class="v-how">{esc(how)}</span>'
            f'<input type="text" data-token-input="{esc(tok)}" autocomplete="off" spellcheck="false"{constraints} placeholder="paste the reviewed 40-hex SHA"></label>')


def values_panel(ctx):
    if not ctx["tokens"] or ctx.get("inline_values"):
        return ""
    rows = "".join(value_row(t, p["how"], p) for t, p in ctx["tokens"].items())
    return (f'<aside class="values" id="values" aria-label="Your values"><h2><span aria-hidden="true">✎</span> Your values for this page</h2>'
            f'<p>The commands below contain values only you know. They are highlighted. Type them once here and every command on this page fills in, '
            f'and so do the commands on the other pages of this guide that you open in this browser tab. '
            f'Only the non-sensitive reviewed main SHA is accepted, kept in this tab session only and never sent anywhere. Browser session restore may retain it. Never enter credentials or customer data.</p><div class="v-grid">{rows}</div>'
            '<p data-value-status aria-live="polite"></p><button type="button" class="btn ghost" data-clear-values>Clear tab values</button></aside>')


def section_html(sec):
    letter = f'<span class="sec-letter" aria-hidden="true">{esc(sec["letter"])}</span>' if sec.get("letter") else ""
    cls = ("sec " + sec.get("cls", "")).strip()
    return f'<section class="{cls}" id="{esc(sec["id"])}"><h2>{letter}<span>{esc(sec["title"])}</span></h2>{sec["html"]}</section>'


# ---------------------------------------------------------------- page kinds
def render_activity(cur, d, ctx):
    reg = PBY[cur]
    secs = []
    secs.append({"id": "purpose", "letter": "A", "title": "Purpose and place in the demo", "html": blocks(d["purpose"], cur, ctx)})
    secs.append({"id": "starting-state", "letter": "B", "title": "Starting state", "html": blocks(d["starting_state"], cur, ctx)})
    steps = '<ol class="steps">' + "".join(step_html(i, s, cur, ctx) for i, s in enumerate(d["steps"], 1)) + "</ol>"
    secs.append({"id": "steps", "letter": "C", "title": "Exact actions", "html": steps,
                 "subs": [(f"step-{REG.step_no(i, s)}", f"{REG.step_no(i, s)}. {plain(s['title'])}") for i, s in enumerate(d["steps"], 1)]})
    cp = d.get("copyable") or []
    extra = d.get("_copyable_extra", "")
    if cp or extra:
        secs.append({"id": "copyable", "letter": "D", "title": "Copyable material", "html": extra + "".join(code_block(c, cur, ctx) for c in cp)})
    else:
        secs.append({"id": "copyable", "letter": "D", "title": "Copyable material", "html": '<p class="muted">Every command and message for this page sits inside its step, next to the explanation, with its own Copy button.</p>'})
    secs.append({"id": "expected", "letter": "E", "title": "Expected result", "html": blocks(d["expected"], cur, ctx)})
    v = d["verify"]
    ver = '<h3 class="sub" id="verify-success">How to confirm success</h3>' + blocks(v["success"], cur, ctx)
    fl = []
    for f in v["failures"]:
        rs = {"yes": ("Safe to repeat", "ok"), "no": ("Do not repeat", "no"), "careful": ("Repeat with care", "care")}[f["repeat_safe"]]
        note = f'<p class="f-note">{inline(f["note"], cur)}</p>' if f.get("note") else ""
        fl.append(f'<details class="failure"><summary><span class="f-sym">{inline(f["symptom"], cur)}</span><span class="rs" data-rs="{rs[1]}">{rs[0]}</span></summary>'
                  f'<div class="f-body"><dl><dt>Likely cause</dt><dd>{inline(f["cause"], cur)}</dd><dt>What to do</dt><dd>{inline(f["fix"], cur)}</dd></dl>{note}</div></details>')
    ver += '<h3 class="sub" id="verify-failures">If something goes wrong</h3><div class="failures">' + "".join(fl) + "</div>"
    ver += '<h3 class="sub" id="verify-recovery">Safe recovery</h3>' + blocks(v["recovery"], cur, ctx)
    if v.get("limitations"):
        ver += '<h3 class="sub" id="verify-limits">Limits of this check</h3>' + blocks(v["limitations"], cur, ctx)
    secs.append({"id": "verify", "letter": "F", "title": "Verify and recover", "html": ver})
    say = "".join(f'<li><span class="q" aria-hidden="true">“</span><p>{inline(x, cur)}</p></li>' for x in d["say"])
    secs.append({"id": "say", "letter": "G", "title": "What to say during the demo",
                 "html": f'<div class="say-tools"><button type="button" class="btn ghost" data-teleprompter>Open teleprompter</button><span class="muted">One line at a time, large type. Use the arrow keys.</span></div><ol class="say">{say}</ol>'})
    for x in d["say"]:
        ctx["text"].append(plain(x))
    secs.append(sources_section(d, cur, ctx))
    return secs


def sources_section(d, cur, ctx):
    src = "".join(f'<li>{repo_chip(r, cur, with_why=False)}</li>' for r in d.get("sources", []) or [])
    gaps = d.get("evidence_gaps") or []
    g = ""
    if gaps:
        g = '<h3 class="sub" id="evidence-gaps">Evidence gaps on this page</h3>' + "".join(callout({"kind": "gap", "text": x}, cur) for x in gaps)
        ctx["text"].extend(gaps)
    return {"id": "sources", "title": "Sources and evidence", "cls": "sources",
            "html": f'<p class="muted">{esc(SITE["sources_note"])}</p><ul class="src-list">{src}</ul>{g}'}


def render_reference(cur, d, ctx):
    secs = []
    for s in d["sections"]:
        secs.append({"id": s["id"], "title": s["title"], "html": blocks(s["blocks"], cur, ctx)})
    secs.append(sources_section(d, cur, ctx))
    return secs


def quick_step(s, page_status):
    """A step of the non-detailed flow as an ordinary step: the click path, a short list of what to do, a field for each value its commands need, the blocks to copy, one line to expect."""
    body = []
    codes = quick.step_codes(s)
    if s.get("do"):
        body.append({"ol": s["do"]})
    seen = []
    for c in codes:                                    # a value the commands need is typed in the step itself (no separate Your values slide on a quick page)
        for p in c.get("placeholders") or []:
            if p["token"] not in seen:
                seen.append(p["token"])
                body.append({"value": p})
    for key, kind in (("warn", "warn"), ("bills", "billing"), ("danger", "danger")):   # a warning comes before the command it is about
        if s.get(key):
            body.append({"callout": {"kind": kind, "text": s[key]}})
    for nid in s.get("fn") or []:                      # the field notes of this step, short
        body.append({"fieldnote_short": nid})
    for c in codes:
        body.append({"code": c})
    if s.get("more"):
        body.append({"more": s["more"]})
    out = {"actor": s["actor"], "title": s["title"], "where": s["where"], "body": body}
    for k in ("time", "url", "shot", "no", "open"):
        if s.get(k):
            out[k] = s[k]
    if s.get("see"):
        out["expect"] = s["see"]
    status = (s.get("evidence") or {}).get("status") or s.get("status")
    if status and status != page_status:
        out["status"] = status
    return out


def render_quick(cur, d, ctx):
    """The non-detailed flow: one slide per step and nothing else (no purpose, no failures, no sources)."""
    ctx["inline_values"] = True                        # the value fields sit inside the steps: no Your values panel
    steps = [quick_step(s, d.get("status")) for s in d["steps"]]
    html_ = '<ol class="steps">' + "".join(step_html(i, s, cur, ctx) for i, s in enumerate(steps, 1)) + "</ol>"
    return [{"id": "steps", "letter": "Q", "title": "Quick steps", "html": html_,
             "subs": [(f"step-{REG.step_no(i, s)}", f"{REG.step_no(i, s)}. {plain(s['title'])}") for i, s in enumerate(steps, 1)]}]


def build_page_html(cur, secs, ctx, d=None, kicker=None, top_html="", title=None, description="", no_header=False):
    reg = PBY[cur]
    toc = []
    body = []
    for sec in secs:
        body.append(section_html(sec))
        toc.append({"id": sec["id"], "label": (sec.get("letter") + " · " if sec.get("letter") else "") + sec["title"]})
        for sid, lab in sec.get("subs", []) or []:
            toc.append({"id": sid, "label": lab, "sub": True})
    head = "" if no_header else header_html(cur, d, kicker)
    main = head + top_html + values_panel(ctx) + "".join(body)
    return shell(cur, title or (d or {}).get("title") or reg["title"], main, toc, description or (d or {}).get("summary") or reg.get("summary", ""))
