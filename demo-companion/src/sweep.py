"""Optional existing-Edge offline layout/interaction audit; no HTTP server or installs.

The source HTML and its exact local assets are loaded in same-origin srcdoc
frames solely to measure exact desktop/tall/short/phone viewport dimensions.
The only HTML adaptation is absolute local asset/navigation URLs and synthetic
test setup. Direct file:// entry rendering is also checked separately.
"""
import argparse
import html
import json
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

from check_site import Page
from render import PAGES, ROOT, page_file

SIZES = ((1366, 900), (1440, 1100), (900, 480), (390, 844))
PROBE = r"""
function inspect(frame, variant) {
  var w = frame.contentWindow, d = frame.contentDocument, r = d.documentElement;
  var deck = w.DC_DECK, info = deck ? deck.audit() : null, failures = [], checks = [];
  if (!w.DC) failures.push('app did not initialize');
  if (!!deck !== (frame.width >= 600 && frame.height >= 520)) failures.push('wrong default deck threshold');
  if (r.getAttribute('data-js-errors')) failures.push(r.getAttribute('data-js-errors'));
  if (info && (info.over.length || info.blank.length || info.tall.length || info.pageScroll)) failures.push('deck layout: ' + JSON.stringify(info));
  if (d.scrollingElement.scrollWidth > w.innerWidth + 2) {
    var offenders = [].slice.call(d.body.querySelectorAll('*')).filter(function(item){return item.getBoundingClientRect().right > w.innerWidth + 2;}).slice(0, 12).map(function(item){
      var box = item.getBoundingClientRect();
      return item.tagName + '.' + item.className + ' right=' + Math.round(box.right) + ' width=' + Math.round(box.width);
    });
    failures.push('horizontal page overflow: ' + r.getAttribute('data-overflow') + ' ' + JSON.stringify(offenders));
    failures.push('unclipped intrinsic overflow: ' + JSON.stringify([].slice.call(d.body.querySelectorAll('*')).filter(function(item){
      return item.clientWidth > 0 && item.scrollWidth > item.clientWidth + 2 && w.getComputedStyle(item).overflowX === 'visible';
    }).slice(0, 16).map(function(item){return item.tagName + '.' + item.className + ' ' + item.scrollWidth + '/' + item.clientWidth;})));
  }
  if (variant === 'denied' && d.querySelector('[data-storage-warning]').hidden) failures.push('storage denial not surfaced');
  if (variant === 'corrupt' && d.querySelector('[data-storage-warning]').hidden) failures.push('corrupt progress not surfaced');
  var boxes = [].slice.call(d.querySelectorAll('[data-step-check]'));
  if (w.DC && boxes.length) {
    boxes.forEach(function (box) { box.checked = true; box.dispatchEvent(new w.Event('change', {bubbles:true})); });
    var id = d.body.getAttribute('data-page');
    if (!w.DC.progress.pages[id].done) failures.push('manual all-ticked page not done');
    boxes[0].checked = false; boxes[0].dispatchEvent(new w.Event('change', {bubbles:true}));
    if (w.DC.progress.pages[id].done) failures.push('unchecking a step left false completed state');
    checks.push('manual tick/all-done/uncheck');
  }
  if (deck) {
    var count = deck.count();
    deck.go(count - 1); if (deck.index() !== count - 1) failures.push('last-slide navigation failed');
    deck.go(0);
    var steps = d.querySelectorAll('.deck-pill');
    if (steps.length) { steps[0].click(); if (!d.querySelector('.slide.is-active').getAttribute('data-g').startsWith('step-')) failures.push('step tab navigation failed'); }
    w.location.hash = '#slide=last';
    w.dispatchEvent(new w.HashChangeEvent('hashchange'));
    if (deck.index() !== count - 1) failures.push('slide deep link failed');
    deck.go(0); checks.push('deck tabs/edge/deep-link');
  }
  if (w.DC) {
    var search = d.querySelector('[data-search-open]');
    search.click();
    var input = d.querySelector('.dlg input');
    input.value = 'Preflight'; input.dispatchEvent(new w.Event('input', {bubbles:true}));
    if (!d.querySelector('.sr-item')) failures.push('local search did not find source content');
    d.dispatchEvent(new w.KeyboardEvent('keydown', {key:'Escape', bubbles:true}));
    if (d.querySelector('.dlg')) failures.push('Escape did not close search');
    d.querySelector('[data-theme-set="dark"]').click();
    if (r.getAttribute('data-theme') !== 'dark') failures.push('theme switch failed');
    d.querySelector('[data-theme-set="light"]').click();
    checks.push('search/Escape/theme');
    var field = d.querySelector('[data-token-input]');
    if (field) {
      field.value = 'f'.repeat(40); field.dispatchEvent(new w.Event('input', {bubbles:true}));
      var code = d.querySelector('.ph').closest('code');
      if (w.DC.codeText(code).text !== code.textContent) failures.push('filled copy differs from visible code');
      field.value = 'invalid-sha'; field.dispatchEvent(new w.Event('input', {bubbles:true}));
      var copied = w.DC.codeText(code);
      if (copied.text !== code.textContent || copied.missing.length !== 1 || copied.text.indexOf('<reviewed-main-sha>') < 0) failures.push('unresolved copy differs or lacks warning state');
      d.querySelector('[data-clear-values]').click();
      if (field.value) failures.push('tab values not cleared');
      checks.push('valid/invalid SHA; exact visible copy; tab clear');
    }
  }
  var details = [].slice.call(d.querySelectorAll('main details')), wasOpen = details.map(function(item){return item.open;});
  w.dispatchEvent(new w.Event('beforeprint'));
  if (details.some(function(item){return !item.open;})) failures.push('print disclosure did not open');
  w.dispatchEvent(new w.Event('afterprint'));
  if (details.some(function(item,index){return item.open !== wasOpen[index];})) failures.push('print disclosure state not restored');
  checks.push('before/after print disclosures');
  if (deck) {
    var originalHeight = frame.height;
    frame.height = 480; void frame.offsetHeight; w.dispatchEvent(new w.Event('resize'));
    if (w.DC_DECK || r.classList.contains('deck')) failures.push('short resize did not enter long-page mode');
    frame.height = originalHeight; void frame.offsetHeight; w.dispatchEvent(new w.Event('resize'));
    if (!w.DC_DECK || !r.classList.contains('deck')) failures.push('tall resize did not restore deck');
    checks.push('resize below/above 520px');
  }
  var row = {page:frame.getAttribute('data-page'), size:frame.width+'x'+frame.height, variant:variant,
             slides:info ? info.slides : 0, scrollSlides:info ? info.oversize.length : 0, checks:checks, failures:failures};
  if (!w.DC) return Promise.resolve(row);
  Object.defineProperty(w.navigator, 'clipboard', {configurable:true, value:null});
  var captured = null;
  d.execCommand = function () { captured = d.querySelector('textarea').value; return true; };
  return w.DC.copy('Synthetic clipboard fixture').then(function(ok) {
    if (!ok || captured !== 'Synthetic clipboard fixture') failures.push('file fallback copy failed');
    d.execCommand = function () { return false; };
    return w.DC.copy('Synthetic clipboard denial fixture');
  }).then(function(ok) {
    if (ok) failures.push('clipboard denial treated as success');
    checks.push('mocked clipboard fallback/denial; no OS clipboard access');
    return row;
  });
}
setTimeout(function () {
  var pending = [].slice.call(document.querySelectorAll('iframe')).map(function(frame) {
    try { return inspect(frame, frame.getAttribute('data-variant')); }
    catch (error) { return Promise.resolve({page:frame.getAttribute('data-page'), failures:[String(error)]}); }
  });
  Promise.all(pending).then(function(rows) {
    setTimeout(function() {
      [].slice.call(document.querySelectorAll('iframe')).forEach(function(frame,index) {
        var w = frame.contentWindow, r = frame.contentDocument.documentElement;
        if (r.getAttribute('data-js-errors')) rows[index].failures.push(r.getAttribute('data-js-errors'));
        if (frame.contentDocument.scrollingElement.scrollWidth > w.innerWidth + 2) rows[index].failures.push('post-interaction horizontal page overflow');
        if (w.DC_DECK) {
          var audit = w.DC_DECK.audit();
          if (audit.over.length || audit.blank.length || audit.tall.length || audit.pageScroll) rows[index].failures.push('post-resize layout: ' + JSON.stringify(audit));
        }
      });
      document.getElementById('results').textContent = JSON.stringify(rows);
    }, 500);
  });
}, 4200);
"""


def local_html(file, variant="normal"):
    text = file.read_text(encoding="utf-8")

    def absolute(match):
        key, url = match.groups()
        parts = urlsplit(html.unescape(url))
        if parts.scheme or not parts.path:
            return match.group(0)
        path = (file.parent / Path(*unquote(parts.path).split("/"))).resolve()
        target = path.as_uri()
        if parts.query:
            target += "?" + parts.query
        if parts.fragment:
            target += "#" + parts.fragment
        return key + '="' + html.escape(target, quote=True) + '"'

    text = re.sub(r'\b(src|href)="([^"]+)"', absolute, text)
    if variant == "denied":
        setup = "['localStorage','sessionStorage'].forEach(function(k){Object.defineProperty(window,k,{get:function(){throw new Error('synthetic storage denial');}});});"
    elif variant == "corrupt":
        setup = ("var syntheticStore={'w11dc.progress.v1':'{\"pages\":null,\"last\":null}'};"
                 "Object.defineProperty(window,'localStorage',{value:{"
                 "getItem:function(k){return syntheticStore[k] || null;},"
                 "setItem:function(k,v){syntheticStore[k]=v;},"
                 "removeItem:function(k){delete syntheticStore[k];}}});")
    else:
        setup = ""
    if setup:
        text = text.replace("<script>", "<script>" + setup + "</script><script>", 1)
    return text


def run_edge(edge, output, url, name, screenshot=False):
    command = [str(edge), "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
               "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-extensions",
               "--disable-renderer-backgrounding", "--force-device-scale-factor=1",
               f"--user-data-dir={output / 'browser-profile'}", "--window-size=1500,1200",
               "--virtual-time-budget=7000"]
    command += [f"--screenshot={output / (name + '.png')}" if screenshot else "--dump-dom", url]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = process.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        print(f"NOT RUN: browser PID {process.pid} timed out; stop the owning PowerShell tool session/process tree.")
        sys.stdout.flush()
        process.wait()
        raise RuntimeError("offline browser audit timed out")
    if process.returncode:
        raise RuntimeError(f"existing Edge audit failed with exit {process.returncode}: {stderr.decode('utf-8', errors='replace')[:300]}")
    decoded = stdout.decode("utf-8", errors="replace")
    if not screenshot:
        (output / (name + ".html")).write_text(decoded, encoding="utf-8", newline="\n")
    return decoded


def results(document):
    class Result(HTMLParser):
        def __init__(self):
            super().__init__()
            self.capture, self.text = False, ""

        def handle_starttag(self, tag, attrs):
            if dict(attrs).get("id") == "results":
                self.capture = True

        def handle_endtag(self, tag):
            if tag == "pre":
                self.capture = False

        def handle_data(self, text):
            if self.capture:
                self.text += text
    parser = Result()
    parser.feed(document)
    if not parser.text or parser.text == "pending":
        raise RuntimeError("NOT RUN: browser did not return viewport diagnostics")
    return json.loads(parser.text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--edge", required=True, type=Path, help="already installed Edge executable")
    parser.add_argument("--output", required=True, type=Path, help="fresh dedicated session-artifact directory")
    arguments = parser.parse_args()
    if not arguments.edge.is_file():
        sys.exit("NOT RUN: existing Edge executable absent; no browser install attempted")
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for width, height in SIZES:
        frames = []
        for page in PAGES:
            file = ROOT / Path(*page_file(page["id"]).split("/"))
            content = local_html(file)
            frames.append(f'<iframe width="{width}" height="{height}" data-page="{page["id"]}" data-variant="normal" srcdoc="{html.escape(content, quote=True)}"></iframe>')
        if width == 1366:
            file = ROOT / "pages" / "quick" / "quick-setup.html"
            for variant in ("denied", "corrupt"):
                frames.append(f'<iframe width="{width}" height="{height}" data-page="quick-setup" data-variant="{variant}" srcdoc="{html.escape(local_html(file, variant), quote=True)}"></iframe>')
        wrapper = ("<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' "
                   "content=\"default-src 'none'; script-src file: 'unsafe-inline'; style-src file: 'unsafe-inline'; frame-src about: file:; img-src file: data:; connect-src 'none'\">"
                   "<style>body{margin:0}iframe{display:block;border:0}</style></head><body>" +
                   "".join(frames) + "<pre id='results'>pending</pre><script>" + PROBE + "</script></body></html>")
        wrapper_file = output / f"viewport-{width}x{height}.html"
        wrapper_file.write_text(wrapper, encoding="utf-8", newline="\n")
        document = run_edge(arguments.edge, output, wrapper_file.as_uri(), f"result-{width}x{height}")
        batch = results(document)
        rows.extend(batch)
        failed = [row for row in batch if row["failures"]]
        print(f"Existing-Edge offline viewport {width}x{height}: {len(batch)} pages/variants, {len(failed)} failures")
    direct = run_edge(arguments.edge, output, (ROOT / "index.html").as_uri(), "entry-file")
    page = Page()
    page.feed(direct)
    if 'class="deck deck-ready' not in direct and "data-deck=" not in direct:
        rows.append({"page": "index file://", "failures": ["direct entry deck did not initialize"]})
    dark = run_edge(arguments.edge, output, (ROOT / "index.html").as_uri() + "?deck=off&theme=dark", "entry-long-dark")
    if 'data-theme="dark"' not in dark or "data-deck=" in dark:
        rows.append({"page": "index ?deck=off&theme=dark", "failures": ["direct long/dark query behavior failed"]})
    run_edge(arguments.edge, output, (ROOT / "index.html").as_uri(), "welcome", screenshot=True)
    (output / "sweep-results.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8", newline="\n")
    failures = [row for row in rows if row["failures"]]
    for failure in failures:
        print(json.dumps(failure))
    print(f"Offline viewport/interaction audit: {len(rows)} cases, {len(failures)} failures; artifact directory {output}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
