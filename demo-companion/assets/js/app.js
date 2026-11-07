/* Demo Companion · app.js · shell behaviour. Classic script, no dependencies, works from file:// */
(function () {
  'use strict';
  var doc = document, root = doc.documentElement;
  root.classList.add('js');
  /* diagnostic only: a script error is recorded on <html data-js-errors> so that a test run can see it */
  window.addEventListener('error', function (e) { root.setAttribute('data-js-errors', (root.getAttribute('data-js-errors') || '') + String(e.message || e) + ' @' + String(e.filename || '').split('/').pop() + ':' + (e.lineno || 0) + '; '); });
  window.addEventListener('unhandledrejection', function (e) { root.setAttribute('data-js-errors', (root.getAttribute('data-js-errors') || '') + 'promise: ' + String(e.reason) + '; '); });
  var body = doc.body, SITE = window.DC_SITE || { pages: [], journeys: [] }, ROOT = body.getAttribute('data-root') || '', PAGE = body.getAttribute('data-page');
  var $ = function (s, c) { return (c || doc).querySelector(s); }, $$ = function (s, c) { return Array.prototype.slice.call((c || doc).querySelectorAll(s)); };
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- storage with an in-memory fallback ---------- */
  var mem = Object.create(null), storageIssues = (window.DC_STORAGE_ISSUES || []).slice();
  function storageIssue(message) {
    if (storageIssues.indexOf(message) < 0) storageIssues.push(message);
    var notice = $('[data-storage-warning]');
    if (notice) {
      var list = $('ul', notice); list.textContent = '';
      storageIssues.forEach(function (issue) { var item = doc.createElement('li'); item.textContent = issue; list.appendChild(item); });
      notice.hidden = false;
    }
  }
  function store(kind) {
    var s;
    function unavailable() { s = null; storageIssue(kind + ' is unavailable. Progress/theme or tab values use memory only and may be lost on navigation.'); }
    try { s = window[kind]; s.setItem('w11dc.storage.test', '1'); s.removeItem('w11dc.storage.test'); } catch (e) { unavailable(); }
    return {
      get: function (k) { try { if (s) mem[kind + k] = s.getItem(k); } catch (e) { unavailable(); } return mem[kind + k] || null; },
      set: function (k, v) { mem[kind + k] = v; try { if (s) s.setItem(k, v); } catch (e) { unavailable(); } }
    };
  }
  var LS = store('localStorage'), SS = store('sessionStorage');
  storageIssues.slice().forEach(storageIssue);
  function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
  function validProgress(value) {
    return object(value) && object(value.pages) && (value.last === null || typeof value.last === 'string') &&
      (value.ticks === undefined || object(value.ticks) && Object.keys(value.ticks).every(function (key) { return value.ticks[key] === true; })) &&
      Object.keys(value.pages).every(function (key) {
        var p = value.pages[key];
        return object(p) && Number.isFinite(p.visited) && p.visited >= 0 && typeof p.done === 'boolean' &&
          object(p.steps) && Object.keys(p.steps).every(function (step) { return /^\d+$/.test(step) && p.steps[step] === true; });
      });
  }
  function load(st, k, d, validate) {
    try { var raw = st.get(k); if (!raw) return d; var value = JSON.parse(raw); if (!validate(value)) throw new Error('Invalid saved guide state'); return value; }
    catch (e) { storageIssue('Saved guide state could not be read. It was not treated as completed; starting fresh manual progress or tab values.'); return d; }
  }
  var progress = load(LS, 'w11dc.progress.v1', { pages: {}, last: null }, validProgress), previousPage = progress.last;
  function save() { LS.set('w11dc.progress.v1', JSON.stringify(progress)); }
  function pg(id) { return progress.pages[id] || (progress.pages[id] = { visited: 0, done: false, steps: {} }); }
  var pageUrl = function (id) { var p = SITE.pages.filter(function (x) { return x.id === id; })[0]; return p ? ROOT + p.url : null; };
  var pageTitle = function (id) { var p = SITE.pages.filter(function (x) { return x.id === id; })[0]; return p ? p.title : id; };

  /* ---------- toast ---------- */
  function toast(msg, kind) {
    var t = doc.createElement('div'); t.className = 'toast' + (kind ? ' ' + kind : ''); t.setAttribute('role', 'status'); t.textContent = msg; body.appendChild(t);
    setTimeout(function () { t.style.opacity = '0'; t.style.transition = 'opacity .3s'; setTimeout(function () { t.remove(); }, 320); }, kind === 'warn' ? 4200 : 1800);
  }

  /* ---------- theme: light by default, dark on request ---------- */
  function setTheme(t, persist) {
    root.setAttribute('data-theme', t); if (persist) LS.set('w11dc.theme', t);
    $$('[data-theme-set]').forEach(function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-theme-set') === t ? 'true' : 'false'); });
  }
  setTheme(root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light', false);
  $$('[data-theme-set]').forEach(function (b) { b.addEventListener('click', function () { setTheme(b.getAttribute('data-theme-set'), true); }); });

  /* ---------- mobile menu ---------- */
  function menu(open) { body.classList.toggle('menu-open', open); var b = $('[data-menu]'); if (b) b.setAttribute('aria-expanded', open ? 'true' : 'false'); }
  var mb = $('[data-menu]'); if (mb) mb.addEventListener('click', function () { menu(!body.classList.contains('menu-open')); });
  var sc = $('[data-scrim]'); if (sc) sc.addEventListener('click', function () { menu(false); });

  /* ---------- progress ---------- */
  pg(PAGE).visited = Date.now();
  progress.last = PAGE;
  save();
  function refreshProgress() {
    var total = 0, done = 0;
    SITE.pages.forEach(function (p) { total++; if ((progress.pages[p.id] || {}).done) done++; });
    $$('.nav-link').forEach(function (a) {
      var st = progress.pages[a.getAttribute('data-page')] || {};
      a.classList.toggle('done', !!st.done); a.classList.toggle('visited', !!st.visited);
    });
    $$('.jd').forEach(function (a) {
      var st = progress.pages[a.getAttribute('data-page')] || {};
      a.classList.toggle('done', !!st.done); a.classList.toggle('visited', !!st.visited && !st.done);
    });
    SITE.journeys.forEach(function (j) {
      var ps = SITE.pages.filter(function (p) { return p.journey === j.id; });
      var d = ps.filter(function (p) { return (progress.pages[p.id] || {}).done; }).length;
      var el = $('[data-jcount="' + j.id + '"]'); if (el) el.textContent = d + '/' + ps.length;
    });
    var ov = $('[data-overall]'); if (ov) { $('.sp-text', ov).textContent = done + ' of ' + total + ' pages done'; $('.sp-bar i', ov).style.width = (total ? Math.round(100 * done / total) : 0) + '%'; }
    var d2 = !!pg(PAGE).done;
    $$('[data-done]').forEach(function (btn) { btn.setAttribute('aria-pressed', d2 ? 'true' : 'false'); var dt = $('.dt', btn); if (dt) dt.textContent = d2 ? 'Page done' : 'Mark page done'; });
  }
  doc.addEventListener('click', function (e) { var b = e.target.closest && e.target.closest('[data-done]'); if (!b) return; var p = pg(PAGE); p.done = !p.done; save(); refreshProgress(); toast('Manual progress updated; no machine verification performed.'); });
  function restoreStepChecks() {
    $$('[data-step-check]').forEach(function (cb) {
      var li = cb.closest('.step'), n = cb.getAttribute('data-progress-step') || (li && li.getAttribute('data-step'));
      cb.setAttribute('data-progress-step', n); cb.checked = !!pg(PAGE).steps[n];
      var container = cb.closest('.slide, .step'); if (container) container.classList.toggle('done', cb.checked);
    });
  }
  restoreStepChecks();
  doc.addEventListener('change', function (e) {
    var cb = e.target; if (!cb.matches || !cb.matches('[data-step-check]')) return;
    var n = cb.getAttribute('data-progress-step'), p = pg(PAGE);
    if (cb.checked) p.steps[n] = true; else delete p.steps[n];
    var container = cb.closest('.slide, .step'); if (container) container.classList.toggle('done', cb.checked);
    var all = $$('[data-step-check]'); p.done = all.length > 0 && all.every(function (c) { return c.checked; });
    if (p.done) toast('All steps manually ticked; not machine verification.');
    save(); refreshProgress();
  });
  progress.ticks = progress.ticks || {};
  function refreshTicks() {
    $$('[data-tick]').forEach(function (cb) { cb.checked = !!progress.ticks[cb.getAttribute('data-tick')]; });
    $$('[data-tick-summary]').forEach(function (el) {
      var g = el.getAttribute('data-tick-summary'), all = $$('[data-tick^="' + g + ':"]'), n = all.filter(function (c) { return c.checked; }).length;
      el.textContent = n + ' of ' + all.length + ' ticked (kept in this browser)';
    });
  }
  doc.addEventListener('change', function (e) {
    var cb = e.target; if (!cb.matches || !cb.matches('[data-tick]')) return;
    var k = cb.getAttribute('data-tick'); if (cb.checked) progress.ticks[k] = true; else delete progress.ticks[k];
    save(); refreshTicks();
  });
  refreshTicks();
  refreshProgress();
  var resumeTarget = previousPage && previousPage !== PAGE ? previousPage : null;
  if (!resumeTarget) { var cands = Object.keys(progress.pages).filter(function (k) { return k !== PAGE && progress.pages[k].visited; }); if (cands.length) resumeTarget = cands.sort(function (a, b) { return progress.pages[b].visited - progress.pages[a].visited; })[0]; }
  $$('[data-resume], [data-resume-big]').forEach(function (b) {
    if (!resumeTarget || !pageUrl(resumeTarget)) return; b.hidden = false; b.title = 'Back to: ' + pageTitle(resumeTarget);
    if (b.hasAttribute('data-resume-big')) b.textContent = 'Resume: ' + pageTitle(resumeTarget);
    b.addEventListener('click', function () { location.href = pageUrl(resumeTarget); });
  });

  /* ---------- placeholders and copy ---------- */
  function validValue(token, value) { var rule = (SITE.tokens || {})[token]; return !!rule && value.length <= rule.max_length && new RegExp(rule.pattern).test(value); }
  var values = load(SS, 'w11dc.values', {}, function (value) { return object(value) && Object.keys(value).every(function (token) { return typeof value[token] === 'string' && validValue(token, value[token]); }); });
  function applyValues() {
    $$('.ph').forEach(function (s) {
      var t = s.getAttribute('data-token'), v = (values[t] || '').trim();
      s.classList.toggle('filled', !!v); s.textContent = v ? v : '<' + t + '>';
    });
    $$('[data-token-input]').forEach(function (i) { var t = i.getAttribute('data-token-input'); if (document.activeElement !== i) i.value = values[t] || ''; });
  }
  doc.addEventListener('input', function (e) {
    var i = e.target; if (!i.matches || !i.matches('[data-token-input]')) return;
    var token = i.getAttribute('data-token-input'), value = i.value.trim(), valid = !value || validValue(token, value);
    i.setCustomValidity(valid ? '' : 'Only the reviewed current 40-hex main SHA is accepted. No credentials or customer data.');
    i.setAttribute('aria-invalid', valid ? 'false' : 'true');
    if (value && valid) values[token] = value; else delete values[token];
    SS.set('w11dc.values', JSON.stringify(values)); applyValues();
    $$('[data-value-status]').forEach(function (s) { s.textContent = valid ? '' : 'Incomplete or invalid SHA: not saved or copied into commands.'; });
  });
  doc.addEventListener('click', function (e) {
    var ph = e.target.closest && e.target.closest('.ph');
    if (ph) {
      var sel = '[data-token-input="' + ph.getAttribute('data-token').replace(/"/g, '\\"') + '"]';
      var inp = $(sel, ph.closest('.slide, li.step') || doc) || $(sel);   /* the field in the same step first (quick pages), else the panel */
      if (inp) { inp.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' }); inp.focus(); }
    }
  });
  applyValues();
  function codeText(code) {
    var out = '', missing = [];
    code.childNodes.forEach(function (n) {
      if (n.nodeType === 3) out += n.textContent;
      else if (n.classList && n.classList.contains('ph')) { var t = n.getAttribute('data-token'); out += n.textContent; if (!values[t] && missing.indexOf(t) < 0) missing.push(t); }
      else out += n.textContent;
    });
    return { text: out, missing: missing };
  }
  function fallbackCopy(text) {
    var previous = doc.activeElement, ta = doc.createElement('textarea'); ta.value = text; ta.setAttribute('readonly', ''); ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0'; body.appendChild(ta); ta.select();
    var ok = false; try { ok = doc.execCommand('copy'); } catch (e) { ok = false; } ta.remove(); if (previous && previous.focus) previous.focus(); return ok;
  }
  function copy(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text).then(function () { return true; }, function () { return fallbackCopy(text); });
    return Promise.resolve(fallbackCopy(text));
  }
  doc.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('[data-copy]'); if (!b) return;
    var fig = b.closest('figure'), code = $('pre code', fig); if (!code) return;
    var r = codeText(code);
    copy(r.text).then(function (ok) {
      if (!ok) { toast('Copy was blocked by the browser. Select the text and press Ctrl+C.', 'warn'); return; }
      b.classList.add('ok'); $('.copy-txt', b).textContent = 'Copied'; setTimeout(function () { b.classList.remove('ok'); $('.copy-txt', b).textContent = 'Copy'; }, 1600);
      if (r.missing.length) toast('Copied, but ' + r.missing.length + ' value' + (r.missing.length > 1 ? 's' : '') + ' still to fill in: ' + r.missing.join(', '), 'warn'); else toast('Copied exactly as shown');
    });
  });
  $$('figure.code.collapsible').forEach(function (f) {
    var pre = $('pre', f), b = doc.createElement('button'); b.type = 'button'; b.className = 'expand'; b.textContent = 'Show the whole text';
    pre.parentNode.insertBefore(b, pre.nextSibling);
    if (pre.scrollHeight <= pre.clientHeight + 4) b.hidden = true;
  });
  doc.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('figure.code .expand'); if (!b) return;
    var o = b.closest('figure.code').classList.toggle('open'); b.textContent = o ? 'Collapse' : 'Show the whole text';
  });

  /* ---------- lightbox and pins ---------- */
  doc.addEventListener('click', function (e) {
    var pin = e.target.closest && e.target.closest('.pin');
    if (pin) { var fig = pin.closest('figure'), li = $('.pin-list li[value="' + pin.getAttribute('data-pin') + '"]', fig); if (li) { li.style.transition = 'background .3s'; li.style.background = 'color-mix(in srgb, var(--bad) 22%, transparent)'; setTimeout(function () { li.style.background = ''; }, 1400); } e.stopPropagation(); return; }
    var box = e.target.closest && e.target.closest('[data-lightbox]');
    if (box) { var img = $('img', box); var lb = doc.createElement('div'); lb.className = 'lightbox'; lb.setAttribute('role', 'dialog'); lb.setAttribute('aria-label', 'Screenshot, click to close'); var i2 = doc.createElement('img'); i2.src = img.src; i2.alt = img.alt; lb.appendChild(i2); lb.addEventListener('click', function () { lb.remove(); }); body.appendChild(lb); }
  });

  /* ---------- reveal and TOC scrollspy ---------- */
  var secs = $$('.sec');
  if ('IntersectionObserver' in window && !reduce) {
    var io = new IntersectionObserver(function (es) { es.forEach(function (en) { if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); } }); }, { rootMargin: '0px 0px -8% 0px', threshold: 0.02 });
    secs.forEach(function (s) { io.observe(s); });
    setTimeout(function () { secs.forEach(function (s) { s.classList.add('in'); }); }, 2500);
  } else secs.forEach(function (s) { s.classList.add('in'); });
  var tocLinks = $$('.toc a');
  if (tocLinks.length && 'IntersectionObserver' in window) {
    var map = {}; tocLinks.forEach(function (a) { map[a.getAttribute('href').slice(1)] = a; });
    var targets = Object.keys(map).map(function (id) { return doc.getElementById(id); }).filter(Boolean);
    var spy = new IntersectionObserver(function (es) {
      es.forEach(function (en) { if (en.isIntersecting) { tocLinks.forEach(function (a) { a.classList.remove('on'); }); var a = map[en.target.id]; if (a) { a.classList.add('on'); a.scrollIntoView({ block: 'nearest' }); } } });
    }, { rootMargin: '-12% 0px -78% 0px' });
    targets.forEach(function (t) { spy.observe(t); });
  }

  /* ---------- dialogs: search and help ---------- */
  var dlg = null, dialogFocus = null;
  function closeDlg() { if (dlg) { dlg.remove(); dlg = null; if (dialogFocus && dialogFocus.focus) dialogFocus.focus(); } }
  function openDlg(inner) { closeDlg(); dialogFocus = doc.activeElement; dlg = doc.createElement('div'); dlg.className = 'dlg'; dlg.setAttribute('role', 'dialog'); dlg.setAttribute('aria-modal', 'true'); dlg.setAttribute('aria-labelledby', 'guide-dialog-title'); dlg.innerHTML = '<div class="dlg-box"><button type="button" class="btn ghost dialog-close">Close (Esc)</button>' + inner + '</div>'; $('h2', dlg).id = 'guide-dialog-title'; $('.dialog-close', dlg).addEventListener('click', closeDlg); dlg.addEventListener('mousedown', function (e) { if (e.target === dlg) closeDlg(); }); body.appendChild(dlg); $('.dialog-close', dlg).focus(); return dlg; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function search(q) {
    var toks = q.toLowerCase().split(/\s+/).filter(Boolean); if (!toks.length) return [];
    var res = [];
    (window.DC_SEARCH || []).forEach(function (p) {
      var t = p.t.toLowerCase(), s = (p.s || '').toLowerCase(), x = (p.x || '').toLowerCase(), score = 0, ok = true;
      toks.forEach(function (k) {
        var inT = t.indexOf(k) >= 0, inS = s.indexOf(k) >= 0, n = 0, i = -1; while ((i = x.indexOf(k, i + 1)) >= 0 && n < 8) n++;
        if (!inT && !inS && !n) ok = false; score += (inT ? 10 : 0) + (inS ? 4 : 0) + n;
      });
      if (ok) res.push({ p: p, score: score });
    });
    return res.sort(function (a, b) { return b.score - a.score; }).slice(0, 12);
  }
  function snippet(p, toks) {
    var x = p.x || '', low = x.toLowerCase(), at = -1; toks.some(function (k) { at = low.indexOf(k); return at >= 0; });
    var seg = at < 0 ? (p.s || x.slice(0, 120)) : x.slice(Math.max(0, at - 50), at + 110);
    var out = esc(seg); toks.forEach(function (k) { out = out.replace(new RegExp('(' + k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig'), '<mark>$1</mark>'); });
    return (at > 50 ? '… ' : '') + out + ' …';
  }
  function openSearch() {
    var d = openDlg('<h2>Search the guide</h2><input type="search" placeholder="Try: Preflight, Python, Restore, WSL, approval…" aria-label="Search" autocomplete="off"><ul aria-label="Search results"></ul>');
    var inp = $('input', d), ul = $('ul', d), sel = 0, items = [];
    function render() {
      var q = inp.value.trim(), toks = q.toLowerCase().split(/\s+/).filter(Boolean); items = search(q);
      ul.innerHTML = items.length ? items.map(function (r, i) { var u = ROOT + (SITE.pages.filter(function (x) { return x.id === r.p.id; })[0] || {}).url; return '<li><a class="sr-item' + (i === sel ? ' on' : '') + '" href="' + esc(u) + '"><b><em>' + esc(r.p.j) + '</em>' + esc(r.p.t) + '</b><small>' + snippet(r.p, toks) + '</small></a></li>'; }).join('') : (q ? '<li class="muted" style="padding:10px 12px">No page matches. Try fewer words.</li>' : '<li class="muted" style="padding:10px 12px">Type to search every page, command and explanation.</li>');
    }
    inp.addEventListener('input', function () { sel = 0; render(); });
    inp.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown') { sel = Math.min(items.length - 1, sel + 1); render(); e.preventDefault(); }
      else if (e.key === 'ArrowUp') { sel = Math.max(0, sel - 1); render(); e.preventDefault(); }
      else if (e.key === 'Enter' && items[sel]) { var a = $$('.sr-item', ul)[sel]; if (a) location.href = a.getAttribute('href'); }
    });
    render(); inp.focus();
  }
  function openHelp() {
    openDlg('<h2>Keyboard shortcuts</h2><dl class="keys"><dt><kbd>/</kbd> or <kbd>Ctrl</kbd>+<kbd>K</kbd></dt><dd>Search the guide</dd><dt><kbd>←</kbd> <kbd>→</kbd></dt><dd>Previous and next slide; at the first or last slide they move to the previous or next page</dd><dt><kbd>Home</kbd> <kbd>End</kbd></dt><dd>First and last slide of the page</dd><dt><kbd>M</kbd></dt><dd>The list of slides on this page</dd><dt><kbd>?</kbd></dt><dd>This list</dd><dt><kbd>T</kbd></dt><dd>Switch between light and dark</dd><dt><kbd>Esc</kbd></dt><dd>Close a window or the teleprompter</dd><dt><kbd>Tab</kbd></dt><dd>Move through links, buttons and Copy buttons; <kbd>Enter</kbd> activates</dd></dl>' +
      '<p class="muted">Progress is manual, not machine verification. Browser storage may be denied; a visible warning then explains memory-only behavior. Only a non-sensitive reviewed SHA is accepted in a tab value field.</p>');
  }
  $$('[data-search-open]').forEach(function (b) { b.addEventListener('click', openSearch); });
  $$('[data-help]').forEach(function (b) { b.addEventListener('click', openHelp); });

  /* ---------- teleprompter ---------- */
  doc.addEventListener('click', function (e) {
    if (!e.target.closest || !e.target.closest('[data-teleprompter]')) return;
    var lines = $$('.say li p').map(function (p) { return p.textContent; }); if (!lines.length) return;
    var i = 0, el = doc.createElement('div'); el.className = 'tele'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', 'Teleprompter');
    el.innerHTML = '<div class="tele-top"><span class="t"></span><span class="n"></span><button class="btn" type="button" data-x style="margin-left:auto">Close (Esc)</button></div><div class="tele-main"><p></p></div><div class="tele-bot"><button class="btn" type="button" data-p>← Back</button><span>Arrow keys or space to move on</span><button class="btn" type="button" data-n>Next →</button></div>';
    body.appendChild(el);
    function show() { $('.t', el).textContent = (doc.querySelector('h1') || {}).textContent || ''; $('.n', el).textContent = (i + 1) + ' / ' + lines.length; var p = $('.tele-main p', el); p.style.animation = 'none'; void p.offsetWidth; p.style.animation = ''; p.textContent = lines[i]; }
    function go(d) { i = Math.max(0, Math.min(lines.length - 1, i + d)); show(); }
    function key(e) { if (e.key === 'Escape') { close(); } else if (e.key === 'ArrowRight' || e.key === ' ' || e.key === 'PageDown') { go(1); e.preventDefault(); } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { go(-1); e.preventDefault(); } e.stopPropagation(); }
    function close() { el.remove(); doc.removeEventListener('keydown', key, true); }
    doc.addEventListener('keydown', key, true);
    $('[data-x]', el).addEventListener('click', close); $('[data-p]', el).addEventListener('click', function () { go(-1); }); $('[data-n]', el).addEventListener('click', function () { go(1); });
    show();
  });

  /* ---------- global keys ---------- */
  doc.addEventListener('keydown', function (e) {
    var tag = (e.target.tagName || '').toLowerCase(), typing = tag === 'input' || tag === 'textarea' || tag === 'select' || e.target.isContentEditable;
    if (e.key === 'Escape') { closeDlg(); menu(false); var lb = $('.lightbox'); if (lb) lb.remove(); return; }
    if (dlg) {
      if (e.key === 'Tab') {
        var focusable = $$('button, input, a[href], [tabindex="0"]', dlg), first = focusable[0], last = focusable[focusable.length - 1];
        if (e.shiftKey && doc.activeElement === first) { last.focus(); e.preventDefault(); }
        else if (!e.shiftKey && doc.activeElement === last) { first.focus(); e.preventDefault(); }
      }
      return;
    }
    if (typing || e.altKey || e.metaKey) { if ((e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openSearch(); } return; }
    if (e.ctrlKey && e.key.toLowerCase() === 'k') { e.preventDefault(); openSearch(); return; }
    if (e.ctrlKey) return;
    if (e.key === '/') { e.preventDefault(); openSearch(); }
    else if (e.key === '?') { openHelp(); }
    else if (e.key === 't' || e.key === 'T') { setTheme(root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark', true); }
    else if (e.key === 'ArrowRight') { if (window.DC_DECK) window.DC_DECK.step(1); else { var n = $('a[rel="next"]'); if (n) location.href = n.href; } }
    else if (e.key === 'ArrowLeft') { if (window.DC_DECK) window.DC_DECK.step(-1); else { var p = $('a[rel="prev"]'); if (p) location.href = p.href; } }
  });

  /* ---------- keep the current sidebar link in view ---------- */
  var cur = $('.nav-link[aria-current="page"]'); if (cur) { var sb = $('#sidebar'); if (sb && cur.getBoundingClientRect().bottom > innerHeight) sb.scrollTop = cur.offsetTop - 120; }
  doc.addEventListener('click', function (e) {
    if (e.target.closest && e.target.closest('[data-clear-values]')) { values = {}; SS.set('w11dc.values', '{}'); applyValues(); $$('[data-token-input]').forEach(function (i) { i.value = ''; i.setCustomValidity(''); i.setAttribute('aria-invalid', 'false'); }); $$('[data-value-status]').forEach(function (s) { s.textContent = 'Tab values cleared.'; }); toast('Only this guide tab’s values were cleared.'); }
    if (e.target.closest && e.target.closest('[data-dismiss-storage]')) { var notice = $('[data-storage-warning]'); if (notice) notice.hidden = true; }
  });
  var printDetails = [];
  window.addEventListener('beforeprint', function () { printDetails = $$('main details'); printDetails.forEach(function (d) { d._wasOpen = d.open; d.open = true; }); });
  window.addEventListener('afterprint', function () { printDetails.forEach(function (d) { d.open = d._wasOpen; }); printDetails = []; });
  window.DC = { toast: toast, copy: copy, codeText: codeText, esc: esc, root: ROOT, progress: progress,
    restore: function () { $$('.sec').forEach(function (s) { s.classList.add('in'); }); restoreStepChecks(); refreshTicks(); refreshProgress(); applyValues(); } };
  /* diagnostic only: records whether the page is wider than the window, so a test run can find layout overflow */
  window.addEventListener('load', function () {
    setTimeout(function () {
      var w = root.scrollWidth, c = root.clientWidth;
      if (w <= c + 2) { root.setAttribute('data-overflow', 'no'); return; }
      var bad = [], els = doc.querySelectorAll('main *');
      for (var i = 0; i < els.length && bad.length < 6; i++) {
        var r = els[i].getBoundingClientRect();
        if (r.right > c + 2 && r.width > 0) {
          var p = els[i].parentElement, clipped = false;
          while (p && p !== doc.body) { var ov = getComputedStyle(p).overflowX; if (ov === 'auto' || ov === 'hidden' || ov === 'scroll') { clipped = true; break; } p = p.parentElement; }
          if (!clipped) bad.push(els[i].tagName.toLowerCase() + (typeof els[i].className === 'string' && els[i].className ? '.' + els[i].className.split(' ')[0] : '') + ' ' + Math.round(r.width) + 'px');
        }
      }
      root.setAttribute('data-overflow', 'yes ' + w + '>' + c + ' [' + bad.join(', ') + ']');
    }, 900);
  });
})();
