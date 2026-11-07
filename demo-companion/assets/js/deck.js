/* Demo Companion · deck.js · turns each page into a deck of single-screen slides, so nothing has to be scrolled.
   The page is plain HTML first. This script only regroups its blocks into slides (one per step, one per section, long sections split by
   what fits the screen) and adds Back/Next, a slide list and the keyboard. Without it, or with ?deck=off, the page reads as one long page.
   Classic script, no dependencies, works from file://. */
(function () {
  'use strict';
  var doc = document, root = doc.documentElement, body = doc.body, wrap = doc.querySelector('main .wrap');
  function ready(ok) { root.classList.remove('deck-pending'); root.classList.toggle('deck-ready', !!ok); }
  function narrowScreen() { return Math.min(innerWidth, screen.width || innerWidth) < 600 || innerHeight < 520; }
  var forced = /[?&]deck=on\b/.test(location.search);
  if (!wrap || /[?&]deck=off\b/.test(location.search) || !(window.Element && Element.prototype.closest && Element.prototype.matches)) { ready(false); return; }

  var $ = function (s, c) { return (c || doc).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || doc).querySelectorAll(s)); };
  var kids = function (e) { return Array.prototype.slice.call(e.children); };
  var mk = function (tag, cls, html) { var e = doc.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  var esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); };
  var textOf = function (e) { return ((e && e.textContent) || '').replace(/\s+/g, ' ').trim(); };

  var backup = wrap.innerHTML;
  var G = [], S = [], active = 0, splits = [], aliases = {}, paneW = 0, paneH = 0, lastW = 0, lastH = 0;
  var holder, topEl, stripEl, stageEl, navEl, menuEl, barEl, countEl, labelEl, prevBtn, nextBtn, menuBtn, doneBtn;
  var prevA = $('.pager a[rel="prev"]', wrap), nextA = $('.pager a[rel="next"]', wrap);
  var crumbs = $('.crumbs', wrap), jbar = $('.journey-bar', wrap);

  /* ---------------------------------------------------------------- plan: which blocks belong together */
  function secInfo(sec) {
    var h2 = $(':scope > h2', sec), letter = '', title = '';
    if (h2) {
      var l = $('.sec-letter', h2); letter = l ? textOf(l) : '';
      var t = $$('span', h2).filter(function (x) { return !x.classList.contains('sec-letter'); })[0]; title = textOf(t || h2);
    }
    return { h2: h2, letter: letter, title: title };
  }
  function sectionGroups(sec) {
    var si = secInfo(sec), steps = $(':scope > ol.steps', sec), rest = kids(sec).filter(function (c) { return c !== si.h2; });
    if (!steps) return [{ id: sec.id, kind: $('.explorer', sec) ? 'app' : 'section', letter: si.letter, title: si.title, h2: si.h2, raw: rest }];
    var lis = kids(steps), total = lis.length;
    return lis.map(function (li, i) {
      var body = $('.step-body', li), repo = $(':scope > .step-repo', li), expect = $(':scope > .expect', li), cb = $('[data-step-check]', li);
      return { id: li.id, kind: 'step', letter: si.letter, secTitle: si.title, n: li.getAttribute('data-no') || String(+li.getAttribute('data-step') || (i + 1)), ord: i + 1, total: total, title: textOf($('h3', li)),
        head: $('.step-head', li), where: $('.where', li), raw: kids(body).concat(repo ? [repo] : [], expect ? [expect] : []),
        ac: li.style.getPropertyValue('--ac'), actor: li.getAttribute('data-actor'), done: li.classList.contains('done') || !!(cb && cb.checked) };
    });
  }
  function isMedia(x) { return x.t === 'media' || x.t === 'diagram'; }
  function kindOf(e) {
    if (e.matches('figure.diagram')) return 'diagram';
    if (e.matches('figure.shot:not(.placeholder), figure.real-output')) return 'media';
    if (e.matches('figure.code')) { var p = $('pre', e); return p && p.textContent.split('\n').length > 5 ? 'media' : 'text'; }
    return 'text';
  }
  var PLAIN = 'p, ul, ol, h2, h3.sub, aside.callout, .expect, .step-repo, .say-tools';
  function wrapItems(arr) {
    var out = [];
    arr.forEach(function (e) {
      if (e.matches('.legend')) { kids(e).forEach(function (c) { out.push({ el: c, t: kindOf(c), plain: c.matches(PLAIN) }); }); return; }
      out.push({ el: e, t: kindOf(e), plain: e.matches(PLAIN) });
    });
    return out;
  }
  function plan() {
    $$('dl.glance > div', wrap).forEach(function (r) { if ($('ul', r)) r.classList.add('wide'); });
    $$('.explorer[data-explorer="relationships"]', wrap).forEach(function (ex) {   /* the chord chart and the list are two views of one explorer: show one at a time */
      var tb = $('.ex-toolbar', ex); if (!tb || $('.ex-view', tb)) return;
      var seg = mk('span', 'seg ex-view', '<button type="button" data-view="chord" aria-pressed="true">Chord</button><button type="button" data-view="list" aria-pressed="false">List</button>');
      seg.setAttribute('role', 'group'); seg.setAttribute('aria-label', 'View');
      tb.insertBefore(seg, $('.ex-count', tb));
      ex.setAttribute('data-view', 'chord');
      if (ex.__setLayout) ex.__setLayout('columns');
      seg.addEventListener('click', function (e) {
        var b = e.target.closest('button'); if (!b) return;
        ex.setAttribute('data-view', b.getAttribute('data-view'));
        $$('button', seg).forEach(function (x) { x.setAttribute('aria-pressed', x === b ? 'true' : 'false'); });
      });
    });
    var cover = { id: 'cover', kind: 'cover', title: textOf($('h1', wrap)) || 'Overview', raw: [] };
    G = [cover];
    var list = kids(wrap).filter(function (e) { return !e.matches('.crumbs, .journey-bar, .pager, .foot, .deck-holder, .deck-top, .deck-stage, .deck-nav'); });
    list.forEach(function (e) {
      if (e.matches('.page-head, .hero, .billing-banner')) { cover.raw.push(e); return; }
      if (e.matches('aside.values')) { G.push({ id: 'values', kind: 'values', title: 'Your values', raw: [e] }); return; }
      if (e.matches('section.sec')) { sectionGroups(e).forEach(function (g) { G.push(g); }); return; }
      G.push({ id: 'x' + G.length, kind: 'other', title: textOf(e).slice(0, 40) || 'More', raw: [e] });
    });
    var nxt = G[1];                                   /* the purpose section sits under the cover when it directly follows it */
    if (nxt && nxt.id === 'purpose' && nxt.kind === 'section' && nxt.h2) {
      cover.raw.push(nxt.h2); nxt.raw.forEach(function (x) { cover.raw.push(x); }); aliases.purpose = nxt.h2; cover.merged = true; G.splice(1, 1);
    }
    G.forEach(function (g) {
      g.its = wrapItems(g.raw);
      [g.head, g.where, g.h2].forEach(function (e) { if (e && !g.its.some(function (x) { return x.el === e; })) holder.appendChild(e); });
      g.its.forEach(function (x) { holder.appendChild(x.el); });
    });
    kids(wrap).forEach(function (e) { if (e.matches('section.sec, aside.values, .page-head, .hero, .billing-banner')) e.remove(); });
  }

  /* ---------------------------------------------------------------- slides */
  function cont(e) {                                  /* a plain copy of a heading for the second and later slides of a group */
    var c = e.cloneNode(true);
    $$('[id]', c).forEach(function (n) { n.removeAttribute('id'); });
    $$('input', c).forEach(function (n) { n.remove(); });
    $$('.slide-part', c).forEach(function (n) { n.remove(); });
    c.classList.add('cont');
    return c;
  }
  function partSpan(host) {                           /* the counter is filled in once the group is packed; its room is kept meanwhile, so a title wraps the same way while it is measured */
    var s = $('.slide-part', host); if (!s) { s = mk('span', 'slide-part'); host.appendChild(s); } s.textContent = '00 of 00'; return s;
  }
  function headFor(g, part) {
    var h;
    if (g.kind === 'step') {
      h = mk('div', 'slide-head');
      h.appendChild(mk('div', 'slide-label', '<span>' + esc(g.letter + ' · ' + g.secTitle) + ' · step ' + g.n + (String(g.n) === String(g.ord) ? ' of ' + g.total : '') + '</span><span class="slide-part">00 of 00</span>'));
      h.appendChild(part === 0 ? g.head : cont(g.head));
      if (g.where) h.appendChild(part === 0 ? g.where : cont(g.where));
      return h;
    }
    if ((g.kind === 'section' || g.kind === 'app') && g.h2) {
      h = mk('div', 'slide-head');
      var h2 = part === 0 ? g.h2 : cont(g.h2); partSpan(h2); h.appendChild(h2);
      return h;
    }
    return null;
  }
  function newSlide(g, part, app) {
    var el = mk('section', 'slide'); el.setAttribute('role', 'group'); el.setAttribute('aria-roledescription', 'slide'); el.setAttribute('data-g', g.id);
    if (g.kind === 'step') { el.classList.add('step'); el.setAttribute('data-actor', g.actor || ''); if (g.ac) el.style.setProperty('--ac', g.ac); if (g.done) el.classList.add('done'); }
    if (app) el.classList.add('tool');
    if (g.kind === 'cover') el.classList.add('cover');
    var head = headFor(g, part);
    if (head) el.appendChild(head);
    var bodyEl = mk('div', 'slide-body one'), a = mk('div', 'col a'), b = mk('div', 'col b');
    bodyEl.appendChild(a); bodyEl.appendChild(b); el.appendChild(bodyEl);
    stageEl.appendChild(el);
    el.style.setProperty('--bh', bodyEl.clientHeight + 'px');          /* the height left for the content, for pictures and code */
    return { g: g, part: part, el: el, body: bodyEl, a: a, b: b, items: [], head: head, closed: false, oversize: false };
  }
  function layoutFull(s) {
    var diagram = s.items.some(function (x) { return x.t === 'diagram'; });
    var two = !diagram && paneW >= 720 && paneW >= paneH && s.items.some(isMedia) && s.items.some(function (x) { return !isMedia(x); });   /* side by side on a landscape stage only; a portrait one stacks */
    s.body.className = 'slide-body ' + (two ? 'two' : 'one') + (s.cols2 && !diagram && !two ? ' cols2' : '');
    s.a.textContent = ''; s.b.textContent = '';
    s.items.forEach(function (x) { (two && isMedia(x) ? s.b : s.a).appendChild(x.el); });
    s.el.classList.toggle('has-diagram', diagram);
  }
  function fits(s) {
    if (s.a.scrollHeight > s.a.clientHeight + 1) return false;
    if (s.body.classList.contains('two') && s.b.scrollHeight > s.b.clientHeight + 1) return false;
    if (s.a.scrollWidth > s.a.clientWidth + 1) return false;
    return true;
  }
  function fitsLayout(s) {                            /* one column first; plain text on a wide stage may flow into two columns */
    s.cols2 = false; layoutFull(s);
    if (fits(s)) return true;
    if (paneW >= 900 && s.items.length && s.items.every(function (x) { return x.plain; })) {
      s.cols2 = true; layoutFull(s);
      if (fits(s)) return true;
      s.cols2 = false; layoutFull(s);
    }
    return false;
  }

  function shrinkPictures(s) {                        /* a picture a little too tall for its slide is made smaller by what the slide is short of */
    if (!$('.shot-img img', s.el)) return false;
    for (var k = 0; k < 4 && !fits(s); k++) {
      var over = Math.max(s.a.scrollHeight - s.a.clientHeight, s.body.classList.contains('two') ? s.b.scrollHeight - s.b.clientHeight : 0);
      if (over <= 0) break;
      s.el.style.setProperty('--shrink', ((parseFloat(s.el.style.getPropertyValue('--shrink')) || 0) + over + 2) + 'px');
    }
    return fits(s);
  }

  function squeeze(s) {                               /* a block that cannot be cut and is a little too tall for a short window: the slide's text is set a size smaller */
    s.el.classList.add('squeeze');
    if (fitsLayout(s)) return true;
    s.el.classList.remove('squeeze'); fitsLayout(s);
    return false;
  }

  /* what can be cut into parts when it is taller than a slide: table rows, list items, grid cards */
  function splitInfo(e) {
    if (e.matches('.table-wrap')) {
      var tb = $('tbody', e), tbl = $('table', e); if (!tb || !tbl) return null;
      return { kids: kids(tb), host: tb, empty: function () {
        var w = e.cloneNode(false); w.removeAttribute('id'); var t = tbl.cloneNode(false), th = $('thead', e);
        if (th) t.appendChild(th.cloneNode(true));
        var b = tb.cloneNode(false); t.appendChild(b); w.appendChild(t); w._into = b; return w; } };
    }
    if (e.matches('ul, ol, dl.kv, dl.glance, dl.stats, .failures, .jcards, .repo-cards, .cards-grid')) {
      return { kids: kids(e), host: e, empty: function (from) {
        var w = e.cloneNode(false); w.removeAttribute('id');
        if (e.tagName === 'OL') w.start = (parseInt(e.getAttribute('start'), 10) || 1) + from;
        w._into = w; return w; } };
    }
    return null;
  }
  function chunks(its) {                              /* a sub-heading travels with everything up to the next one */
    var out = [], cur = null;
    its.forEach(function (x) {
      if (x.el.matches('h2, h3.sub')) { cur = [x]; out.push(cur); }
      else if (cur) cur.push(x);
      else out.push([x]);
    });
    return out;
  }

  function pack(g) {
    var made = [], cur = null, at = -1, intro = [], tool = g.its;
    function open(app) { cur = newSlide(g, made.length, app); made.push(cur); return cur; }
    if (g.kind === 'app') {                           /* an explorer gets its own slide, the text before it (how to read it) goes on a slide of its own first */
      g.its.forEach(function (x, i) { if (at < 0 && (x.el.matches('.explorer') || $('.explorer', x.el))) at = i; });
      if (at > 0) { intro = g.its.slice(0, at); tool = g.its.slice(at); }
    }
    open(g.kind === 'app' && !intro.length);
    if (g.kind === 'app') {
      if (intro.length) { chunks(intro).forEach(place); open(true); }
      tool.forEach(function (x) { cur.items.push(x); });
      layoutFull(cur);
      var ex = $('.explorer', cur.el), exKind = ex ? ex.getAttribute('data-explorer') : '';
      cur.el.classList.toggle('fit', exKind === 'relationships');
      if (exKind === 'relationships') cur.el.style.setProperty('--bh', cur.body.clientHeight + 'px');   /* the head is hidden on this slide */
      if (!$('.ex-split', cur.el) && exKind !== 'relationships') cur.el.classList.add('scroll');
      return made;
    }
    function splitInto(x, info) {
      splits.push({ host: info.host, kids: info.kids.slice(), orig: x.el });
      var start = 0, part = null;
      function begin(from) { start = from; part = info.empty(from); cur.items.push({ el: part, t: x.t, plain: x.plain }); layoutFull(cur); }
      begin(0);
      for (var i = 0; i < info.kids.length; i++) {
        part._into.appendChild(info.kids[i]);
        if (fitsLayout(cur)) continue;
        if (i > start) { var prev = cur; open(); begin(i); part._into.appendChild(info.kids[i]); fitsLayout(prev); }   /* prev lost its last item: lay it out again */
        if (!fitsLayout(cur) && !squeeze(cur)) cur.oversize = true;
      }
    }
    function placeLarge(u) {                          /* does not fit even an empty slide: split what can be split, otherwise let the slide scroll */
      if (u.length > 2) { place(u.slice(0, 2)); for (var i = 2; i < u.length; i++) place([u[i]]); return; }
      var x = u[u.length - 1], info = splitInfo(x.el);
      u.slice(0, -1).forEach(function (h) { cur.items.push(h); });
      if (info && info.kids.length > 1) { splitInto(x, info); return; }
      cur.items.push(x);
      if (!fitsLayout(cur) && !shrinkPictures(cur) && !squeeze(cur)) cur.oversize = true;
    }
    function place(u) {
      if (cur.closed) open();
      var solo = u.some(function (x) { return x.t === 'diagram'; });
      if (solo && cur.items.length) open();
      var n0 = cur.items.length;
      u.forEach(function (x) { cur.items.push(x); });
      if (solo) { layoutFull(cur); cur.closed = true; return; }
      if (fitsLayout(cur)) return;
      cur.items.length = n0; fitsLayout(cur);
      if (n0 > 0) { open(); place(u); return; }
      placeLarge(u);
    }
    chunks(g.its).forEach(place);
    return made;
  }
  function packAll() {
    S = []; splits = [];
    G.forEach(function (g) { pack(g).forEach(function (s) { S.push(s); }); });
    var count = {};
    S.forEach(function (s) { count[s.g.id] = (count[s.g.id] || 0) + 1; });
    S.forEach(function (s, i) {
      var g = s.g, n = count[g.id];
      s.el.classList.toggle('oversize', !!s.oversize);
      s.el.classList.toggle('done', !!s.g.done);
      s.title = g.kind === 'step' ? g.letter + ' · step ' + g.n + ': ' + g.title : g.kind === 'cover' ? (s.part && g.merged ? 'A · Purpose and place in the demo' : g.title) : (g.letter ? g.letter + ' · ' : '') + g.title;
      var sp = $('.slide-part', s.el);
      if (n > 1) { if (sp) sp.textContent = (s.part + 1) + ' of ' + n; s.title += ' (' + (s.part + 1) + '/' + n + ')'; }
      else if (sp) sp.textContent = '';
      s.el.setAttribute('aria-label', (i + 1) + ' of ' + S.length + ': ' + s.title);
    });
  }
  function clearSlides() {                            /* put every block back in the holder so the slides can be built again */
    splits.forEach(function (sp) { sp.kids.forEach(function (k) { sp.host.appendChild(k); }); holder.appendChild(sp.orig); });
    splits = [];
    G.forEach(function (g) {
      [g.head, g.where, g.h2].forEach(function (e) { if (e) { $$('.slide-part', e).forEach(function (n) { n.remove(); }); holder.appendChild(e); } });
      g.its.forEach(function (x) { holder.appendChild(x.el); });
    });
    S.forEach(function (s) { s.el.remove(); });
    S = [];
  }
  function measure() {
    paneW = stageEl.clientWidth; paneH = stageEl.clientHeight; lastW = paneW; lastH = paneH;
    stageEl.style.setProperty('--sh', paneH + 'px');
    stageEl.classList.toggle('narrow', paneW < 760);
  }
  function redrawDiagrams() {                         /* the picture is drawn for the width its slide really has */
    $$('figure.diagram', stageEl).forEach(function (f) { if (f._dcDraw) f._dcDraw(); });
  }

  /* ---------------------------------------------------------------- navigation */
  function hashFor(i) { var s = S[i]; return s.g.id + (s.part ? '~' + (s.part + 1) : ''); }
  function slideFromHash(h) {
    if (!h) return -1;
    h = h.replace(/^#/, ''); try { h = decodeURIComponent(h); } catch (e) { /* keep as is */ }
    var m = /^slide=(first|last|\d+)$/.exec(h);
    if (m) return m[1] === 'first' ? 0 : m[1] === 'last' ? S.length - 1 : Math.min(S.length - 1, Math.max(0, +m[1] - 1));
    var id = h, part = 0, pm = /^(.*)~(\d+)$/.exec(h), k;
    if (pm) { id = pm[1]; part = +pm[2] - 1; }
    for (k = 0; k < S.length; k++) if (S[k].g.id === id && S[k].part === part) return k;
    for (k = 0; k < S.length; k++) if (S[k].g.id === id) return k;
    var t = doc.getElementById(id) || aliases[id];
    var sl = t && t.closest && t.closest('.slide');
    if (sl) for (k = 0; k < S.length; k++) if (S[k].el === sl) return k;
    return -1;
  }
  function pageTitle(a) { var t = a && $('.pg-title', a); return t ? textOf(t) : ''; }
  function firstIndex(id) { for (var k = 0; k < S.length; k++) if (S[k].g.id === id) return k; return -1; }
  function updateNav() {
    var n = S.length, i = active, ag = S[i].g;
    if (barEl) { var bar = $('i', barEl); if (bar) bar.style.width = (n > 1 ? Math.round(100 * i / (n - 1)) : 100) + '%'; }
    countEl.textContent = (i + 1) + ' / ' + n; labelEl.textContent = S[i].title;
    prevBtn.disabled = i === 0 && !prevA;
    prevBtn.innerHTML = i === 0 ? '<span>← Previous page</span>' + (prevA ? '<span class="sub">' + esc(pageTitle(prevA)) + '</span>' : '') : '<span>← Back</span>';
    nextBtn.disabled = i === n - 1 && !nextA;
    nextBtn.innerHTML = i === n - 1 ? '<span>Next page →</span>' + (nextA ? '<span class="sub">' + esc(pageTitle(nextA)) + '</span>' : '') : '<span>Next →</span>';
    $$('.deck-mi', menuEl).forEach(function (b, k) { b.classList.toggle('on', k === i); });
    $$('.deck-tab, .deck-pill', stripEl).forEach(function (b) {
      var id = b.getAttribute('data-g'), on = b.classList.contains('deck-pill') ? id === ag.id : (b.hasAttribute('data-steps') ? ag.kind === 'step' : id === ag.id);
      b.classList.toggle('on', on); if (on) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current');
    });
  }
  function go(i, quiet) {
    if (i < 0) { if (prevA) location.href = prevA.getAttribute('href') + '#slide=last'; return; }
    if (i >= S.length) { if (nextA) location.href = nextA.getAttribute('href'); return; }
    active = i;
    S.forEach(function (s, k) {
      var on = k === i;
      s.el.classList.toggle('is-active', on); s.el.classList.toggle('is-before', k < i);
      if (on) { s.el.removeAttribute('inert'); s.el.removeAttribute('aria-hidden'); s.seen = true; $$('.col', s.el).forEach(function (c) { c.scrollTop = 0; }); }
      else { s.el.setAttribute('inert', ''); s.el.setAttribute('aria-hidden', 'true'); }
    });
    updateNav();
    if (!quiet) { try { history.replaceState(null, '', i === 0 ? location.pathname + location.search : '#' + encodeURIComponent(hashFor(i))); } catch (e) { /* file:// may refuse */ } }
  }
  function step(d) { go(active + d); }
  function toggleMenu(open) { var o = open == null ? menuEl.hidden : open; menuEl.hidden = !o; menuBtn.setAttribute('aria-expanded', o ? 'true' : 'false'); if (o) { var on = $('.deck-mi.on', menuEl); if (on) on.scrollIntoView({ block: 'nearest' }); } }

  var SHORT = { 'purpose': 'Purpose', 'starting-state': 'Before you start', 'copyable': 'Copy-paste', 'expected': 'Expected result', 'verify': 'Verify and recover', 'say': 'What to say', 'sources': 'Sources' };
  function buildStrip() {                             /* one tab per section, and numbered pills for the steps: the "sub-section sliders" */
    stripEl.textContent = '';
    var stepsHost = null, n = 0, lettered = G.some(function (g) { return g.letter; });
    G.forEach(function (g) {
      if (firstIndex(g.id) < 0) return;
      if (g.kind === 'step') {
        if (!stepsHost) {
          var st = mk('button', 'deck-tab', '<b>' + esc(g.letter || String(n + 1)) + '</b><span>Steps</span>'); st.type = 'button';
          st.setAttribute('data-g', g.id); st.setAttribute('data-steps', '1'); st.title = g.secTitle + ': step by step'; stripEl.appendChild(st);
          stepsHost = mk('span', 'deck-pills'); stripEl.appendChild(stepsHost); n++;
        }
        var p = mk('button', 'deck-pill' + (g.done ? ' done' : ''), String(g.n)); p.type = 'button'; p.setAttribute('data-g', g.id); p.title = 'Step ' + g.n + ': ' + g.title;
        if (g.ac) p.style.setProperty('--ac', g.ac);
        stepsHost.appendChild(p); return;
      }
      n++;
      var label = g.kind === 'cover' ? 'Overview' : g.kind === 'values' ? 'Your values' : (SHORT[g.id] || g.title);
      var badge = g.letter || (g.kind === 'cover' ? (g.merged ? 'A' : '⌂') : g.kind === 'values' ? '✎' : g.id === 'sources' ? '§' : (lettered ? '◇' : String(n)));
      if (g.kind === 'cover' && !lettered) badge = '1';
      var t = mk('button', 'deck-tab', '<b>' + esc(badge) + '</b><span>' + esc(label) + '</span>'); t.type = 'button';
      t.setAttribute('data-g', g.id); t.title = g.kind === 'cover' ? g.title : (g.letter ? g.letter + ' · ' : '') + g.title; stripEl.appendChild(t);
    });
    fitStrip();
  }
  function fitStrip() {                               /* when labels would be cut off, inactive tabs show only their badge */
    stripEl.classList.remove('compact');
    var cut = stripEl.scrollWidth > stripEl.clientWidth + 1 || $$('.deck-tab span', stripEl).some(function (sp) { return sp.scrollWidth > sp.clientWidth + 1; });
    if (cut) stripEl.classList.add('compact');
  }

  function buildNav() {
    navEl.textContent = '';
    prevBtn = mk('button', 'deck-btn'); prevBtn.type = 'button';
    nextBtn = mk('button', 'deck-btn primary'); nextBtn.type = 'button';
    var mid = mk('div', 'deck-mid');
    countEl = mk('span', 'deck-count'); countEl.setAttribute('aria-live', 'polite');
    barEl = mk('div', 'deck-bar', '<i></i>'); barEl.setAttribute('aria-hidden', 'true');
    labelEl = mk('span', 'deck-label');
    mid.appendChild(countEl); mid.appendChild(barEl); mid.appendChild(labelEl);
    menuBtn = mk('button', 'deck-menu-btn', '<span aria-hidden="true">☰</span> Slides'); menuBtn.type = 'button'; menuBtn.setAttribute('aria-expanded', 'false'); menuBtn.title = 'List of slides on this page (M)';
    menuEl = mk('div', 'deck-menu'); menuEl.hidden = true;
    menuEl.appendChild(mk('div', 'deck-menu-h', 'Slides on this page'));
    S.forEach(function (s, k) { var b = mk('button', 'deck-mi', '<b>' + (k + 1) + '</b><span>' + esc(s.title) + '</span>'); b.type = 'button'; b.setAttribute('data-i', k); menuEl.appendChild(b); });
    navEl.appendChild(prevBtn); navEl.appendChild(mid); navEl.appendChild(menuBtn);
    if ($('[data-done]', wrap) || $('[data-done]', holder)) {
      doneBtn = mk('button', 'done-btn', '<span class="ck" aria-hidden="true"></span><span class="dt">Mark page done</span>'); doneBtn.type = 'button'; doneBtn.setAttribute('data-done', ''); doneBtn.setAttribute('aria-pressed', 'false');
      var first = $('[data-done]', stageEl) || $('[data-done]', holder);
      if (first) { doneBtn.setAttribute('aria-pressed', first.getAttribute('aria-pressed') || 'false'); $('.dt', doneBtn).textContent = textOf($('.dt', first)) || 'Mark page done'; }
      navEl.appendChild(doneBtn);
    }
    navEl.appendChild(nextBtn); navEl.appendChild(menuEl);
    buildStrip();
  }

  /* ---------------------------------------------------------------- checks for the test run */
  function audit() {
    var over = [], oversize = [], blank = [];
    S.forEach(function (s, i) {
      var label = (i + 1) + ':' + s.title;
      if (s.oversize) oversize.push(label + ' [h ' + s.a.scrollHeight + '/' + s.a.clientHeight + ' w ' + s.a.scrollWidth + '/' + s.a.clientWidth + ' b ' + s.b.scrollHeight + '/' + s.b.clientHeight + ' ' + s.items.map(function (x) { return x.t[0]; }).join('') + ']'); else if (!s.el.classList.contains('tool') && !fits(s)) over.push(label + ' [h ' + s.a.scrollHeight + '/' + s.a.clientHeight + ' w ' + s.a.scrollWidth + '/' + s.a.clientWidth + (s.cols2 ? ' cols2' : '') + ' ' + s.items.map(function (x) { return x.t[0] + (x.plain ? 'p' : ''); }).join('') + ' bh ' + s.el.style.getPropertyValue('--bh') + ' head ' + (s.head ? s.head.offsetHeight : 0) + ' items ' + s.items.map(function (x) { return x.el.offsetHeight; }).join(',') + ']');
      if (!s.items.length) blank.push(label);
    });
    var doc2 = doc.scrollingElement || root;
    var tall = S.filter(function (s) { return s.el.getBoundingClientRect().height > stageEl.clientHeight + 2; }).map(function (s) { return s.title + ' ' + Math.round(s.el.getBoundingClientRect().height); });   /* a slide taller than its stage is clipped */
    var info = { slides: S.length, over: over, oversize: oversize, blank: blank, tall: tall, pageScroll: doc2.scrollHeight > innerHeight + 1 || doc2.scrollWidth > innerWidth + 1, vw: innerWidth, vh: innerHeight, sw: paneW, sh: paneH,
      titles: S.map(function (s) { return s.title + ' [' + s.items.map(function (x) { return x.t[0]; }).join('') + (s.cols2 ? ' 2col' : '') + ']'; }) };
    root.setAttribute('data-deck', JSON.stringify(info));
    return info;
  }

  /* ---------------------------------------------------------------- build, rebuild, wire up */
  function repaginate() {
    var cur = S[active], g = cur && cur.g, part = cur ? cur.part : 0, cnt = S.filter(function (s) { return s.g === g; }).length;
    clearSlides(); measure(); packAll(); redrawDiagrams(); buildNav();
    var cands = []; S.forEach(function (s, i) { if (s.g === g) cands.push(i); });
    var k = cands.length ? cands[Math.min(cands.length - 1, Math.round(part / Math.max(1, cnt - 1) * (cands.length - 1)))] : 0;
    go(k, true); audit();
  }
  var rt = null;
  function onResize() {
    if (!stageEl || !stageEl.clientWidth) return;
    if (Math.abs(stageEl.clientWidth - lastW) < 8 && Math.abs(stageEl.clientHeight - lastH) < 8) return;
    clearTimeout(rt); rt = setTimeout(repaginate, 180);
  }
  var wired = false;
  function wireOnce() {
    if (wired) return; wired = true;
    navEl.addEventListener('click', function (e) {
      var b = e.target.closest('.deck-btn');
      if (b && b === prevBtn) step(-1);
      else if (b && b === nextBtn) step(1);
      else if (e.target.closest('.deck-menu-btn')) toggleMenu();
      else { var mi = e.target.closest('.deck-mi'); if (mi) { toggleMenu(false); go(+mi.getAttribute('data-i')); } }
    });
    stripEl.addEventListener('click', function (e) {
      var t = e.target.closest('.deck-tab, .deck-pill'); if (!t) return;
      var i = firstIndex(t.getAttribute('data-g')); if (i >= 0) go(i);
    });
    window.addEventListener('resize', onResize);
    if (window.ResizeObserver) new ResizeObserver(onResize).observe(stageEl);
    window.addEventListener('hashchange', function () { if (!root.classList.contains('deck')) return; var i = slideFromHash(location.hash); if (i >= 0 && i !== active) go(i, true); });
    stageEl.addEventListener('scroll', function () { stageEl.scrollTop = 0; stageEl.scrollLeft = 0; });
    doc.addEventListener('click', function (e) {                    /* a link to a section or step of this page goes to its slide */
      if (!root.classList.contains('deck')) return;
      var a = e.target.closest && e.target.closest('a[href^="#"]'); if (!a || a.classList.contains('skip')) return;
      var href = a.getAttribute('href'); if (href === '#' || href === '#main') return;
      var i = slideFromHash(href); if (i >= 0) { e.preventDefault(); go(i); }
    });
    doc.addEventListener('click', function (e) {                    /* a highlighted value in a command opens the "Your values" slide */
      if (!root.classList.contains('deck')) return;
      var ph = e.target.closest && e.target.closest('.ph'); if (!ph) return;
      var vi = -1; S.forEach(function (s, k) { if (vi < 0 && s.g.kind === 'values') vi = k; }); if (vi < 0) return;
      e.stopPropagation(); e.preventDefault(); go(vi);
      var inp = $('[data-token-input="' + String(ph.getAttribute('data-token')).replace(/"/g, '\\"') + '"]'); if (inp) { try { inp.focus({ preventScroll: true }); } catch (x) { inp.focus(); } }
    }, true);
    doc.addEventListener('click', function (e) { if (menuEl && !menuEl.hidden && !e.target.closest('.deck-menu, .deck-menu-btn')) toggleMenu(false); });
    doc.addEventListener('change', function (e) {                   /* ticking a step marks all its slides and its pill */
      var cb = e.target; if (!cb.matches || !cb.matches('[data-step-check]')) return;
      var sl = cb.closest('.slide'); if (!sl) return;
      var gid = sl.getAttribute('data-g');
      S.forEach(function (s) { if (s.g.id === gid) { s.g.done = cb.checked; s.el.classList.toggle('done', cb.checked); } });
      $$('.deck-pill', stripEl).forEach(function (p) { if (p.getAttribute('data-g') === gid) p.classList.toggle('done', cb.checked); });
    });
    doc.addEventListener('keydown', function (e) {
      if (!root.classList.contains('deck')) return;
      if (e.defaultPrevented || e.ctrlKey || e.altKey || e.metaKey) return;
      var t = e.target, tag = (t.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea' || tag === 'select' || t.isContentEditable || $('.dlg, .tele, .lightbox')) return;
      if (e.key === 'Home') { e.preventDefault(); go(0); }
      else if (e.key === 'End') { e.preventDefault(); go(S.length - 1); }
      else if (e.key === 'm' || e.key === 'M') { toggleMenu(); }
      else if (e.key === 'Escape') { toggleMenu(false); }
    });
    var sx = 0, sy = 0, st = 0, tracking = false;                    /* swipe on a touch screen */
    stageEl.addEventListener('pointerdown', function (e) { if (e.pointerType !== 'touch' || e.target.closest('pre, .table-wrap, .dg-stage, input, textarea, select')) return; tracking = true; sx = e.clientX; sy = e.clientY; st = Date.now(); });
    stageEl.addEventListener('pointerup', function (e) { if (!tracking) return; tracking = false; var dx = e.clientX - sx, dy = e.clientY - sy; if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.6 && Date.now() - st < 700) step(dx < 0 ? 1 : -1); });
    stageEl.addEventListener('pointercancel', function () { tracking = false; });
    window.addEventListener('load', function () { setTimeout(function () { var a = audit(); if (a.over.length && !stageEl._retried) { stageEl._retried = true; repaginate(); } }, 350); });
  }

  function init() {
    holder = mk('div', 'deck-holder'); holder.hidden = true;
    topEl = mk('div', 'deck-top');
    var row = mk('div', 'deck-row'); if (crumbs) row.appendChild(crumbs); if (jbar) row.appendChild(jbar);
    stripEl = mk('div', 'deck-strip'); stripEl.setAttribute('role', 'group'); stripEl.setAttribute('aria-label', 'Sections and steps of this page');
    topEl.appendChild(row); topEl.appendChild(stripEl);
    stageEl = mk('div', 'deck-stage'); stageEl.setAttribute('role', 'region'); stageEl.setAttribute('aria-label', 'Slides');
    navEl = mk('nav', 'deck-nav'); navEl.setAttribute('aria-label', 'Slide navigation');
    wrap.insertBefore(holder, wrap.firstChild); wrap.insertBefore(navEl, wrap.firstChild); wrap.insertBefore(stageEl, wrap.firstChild); wrap.insertBefore(topEl, wrap.firstChild);
    navEl.appendChild(mk('button', 'deck-btn', '&nbsp;'));        /* gives the bar its final height before the slides are measured */
    plan();
    root.classList.add('deck');
    measure(); packAll(); redrawDiagrams(); buildNav(); wireOnce();
    var start = slideFromHash(location.hash);
    go(start >= 0 ? start : 0, true);
    window.DC_DECK = { step: step, go: go, count: function () { return S.length; }, index: function () { return active; }, audit: audit, repaginate: repaginate };
    audit();
  }

  var fragment = null, deckObject = null, broken = false;
  function mode() {
    if (broken) return;
    if (narrowScreen() && !forced) {
      if (root.classList.contains('deck')) {
        clearTimeout(rt); fragment = doc.createDocumentFragment();
        kids(wrap).forEach(function (node) { fragment.appendChild(node); });
        wrap.innerHTML = backup; root.classList.remove('deck'); root.removeAttribute('data-deck');
        deckObject = window.DC_DECK; delete window.DC_DECK;
        if (window.DC) window.DC.restore();
      }
      ready(false); return;
    }
    if (root.classList.contains('deck')) return;
    try {
      if (fragment) {
        wrap.innerHTML = ''; wrap.appendChild(fragment); fragment = null;
        root.classList.add('deck'); window.DC_DECK = deckObject;
        if (window.DC) window.DC.restore();
        G.forEach(function (g) { var cb = g.head && $('[data-step-check]', g.head); if (cb) g.done = cb.checked; });
        repaginate();
        var fromHash = slideFromHash(location.hash); if (fromHash >= 0) go(fromHash, true);
      } else {
        backup = wrap.innerHTML; init();
      }
      ready(true);
    } catch (err) {
      broken = true; clearTimeout(rt); wrap.innerHTML = backup;
      root.classList.remove('deck'); root.removeAttribute('data-deck'); delete window.DC_DECK;
      root.setAttribute('data-js-errors', (root.getAttribute('data-js-errors') || '') + 'deck: ' + String(err && err.message || err) + ' @' + String(err && err.stack || '').split('\n')[1] + '; ');
      if (window.DC) { window.DC.restore(); window.DC.toast('Slide layout failed; restored the long page. Reload with ?deck=off if needed.', 'warn'); }
      ready(false);
    }
  }
  window.addEventListener('resize', mode);
  mode();
})();
