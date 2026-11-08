/* composer.js: CHORUS's one "Send" flow, shared by Sky (index.html), Forge and HOLO.
   Open it from any node/card/need with the node attached. The feeder's POST /route suggests
   kind, who, where, when and why (no side effects); Keath edits; POST /send dispatches.
   Pages configure it once:
     ChorusComposer.config = { canSend: () => bool, mock: bool, mockSend: (body) => text, onSent: (res, body) => {} };
   and open it:  ChorusComposer.open({ node, text, kind, to });
   Keys: Enter sends (Shift+Enter is a new line), Esc closes, Tab cycles the chips and fields. */
(function () {
  'use strict';
  const KINDS = [['ask', 'Ask'], ['order', 'Order'], ['action-order', 'Action'], ['suggest', 'Suggest'], ['status', 'Status'], ['review-request', 'Review'], ['handoff', 'Hand off']];
  const KIND_WORDS = { ask: 'a question', order: 'an order', 'action-order': 'an action order', suggest: 'a suggestion', status: 'a status update', 'review-request': 'a review request', handoff: 'a hand-off' };
  const WHERE_WORDS = { channel: 'channel', local: 'local model (answers here)', github: 'GitHub comment', 'review-queue': 'review queue dev#431', studio: 'Studio mission', chatdev: 'ChatDev queue' };
  const TEMPLATES = [
    ['status', 'Status update', 'Status on {label}: '],
    ['review-request', 'Review request', 'Please review {label} and post evidence.'],
    ['order', 'Fix this', 'Fix {label}: {why} Post the receipt when done.'],
    ['ask', 'Explain this', 'Explain {label} in plain words: what is wrong, and what fixes it?'],
    ['handoff', 'Hand off', 'Handing off {label}. Where it stands: {why} Next step: '],
  ];
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const CSS = `
.cc-back{position:fixed;inset:0;background:rgba(3,6,12,.55);z-index:9000;display:flex;align-items:flex-start;justify-content:center;padding:max(6vh,16px) 16px 16px;overflow:auto}
.cc{--cc-bg:#0d1420;--cc-fg:#e7eef8;--cc-dim:#8fa1b8;--cc-line:rgba(160,190,230,.22);--cc-acc:#7fd4c1;--cc-warn:#f0b24a;--cc-bad:#ff6b6b;
 width:min(640px,100%);background:var(--cc-bg);color:var(--cc-fg);border:1px solid var(--cc-line);border-radius:12px;box-shadow:0 18px 60px rgba(0,0,0,.55);
 font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif;padding:14px 16px 12px}
.cc header{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-bottom:8px}
.cc header>div{flex:1;min-width:0}
.cc button,.cc input,.cc textarea{text-transform:none;letter-spacing:normal}
.cc h2{margin:0;font-size:15px;font-weight:600;letter-spacing:.02em}
.cc .about{color:var(--cc-dim);font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cc textarea{width:100%;box-sizing:border-box;min-height:78px;resize:vertical;background:#070c14;color:var(--cc-fg);border:1px solid var(--cc-line);border-radius:8px;padding:8px 10px;font:inherit}
.cc textarea:focus,.cc input:focus,.cc button:focus-visible{outline:2px solid var(--cc-acc);outline-offset:1px}
.cc .grp{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:8px}
.cc .lab{width:52px;flex:none;color:var(--cc-dim);font-size:11px;text-transform:uppercase;letter-spacing:.08em}
.cc .chip{background:transparent;color:var(--cc-fg);border:1px solid var(--cc-line);border-radius:999px;padding:3px 10px;font:inherit;font-size:12.5px;cursor:pointer}
.cc .chip[aria-pressed=true]{background:rgba(127,212,193,.16);border-color:var(--cc-acc);color:#fff}
.cc .chip small{color:var(--cc-dim);margin-left:4px}
.cc .chip.tpl{border-style:dashed;color:var(--cc-dim)}
.cc input.why,.cc input.whenx{flex:1;min-width:140px;background:#070c14;color:var(--cc-fg);border:1px solid var(--cc-line);border-radius:6px;padding:4px 8px;font:inherit;font-size:12.5px}
.cc .preview{margin-top:10px;padding:8px 10px;border-left:3px solid var(--cc-acc);background:rgba(127,212,193,.06);border-radius:4px}
.cc .preview.prep{border-left-color:var(--cc-warn)}
.cc .foot{display:flex;gap:8px;align-items:center;justify-content:space-between;margin-top:10px}
.cc .note{color:var(--cc-dim);font-size:12px}.cc .note.ok{color:var(--cc-acc)}.cc .note.bad{color:var(--cc-bad)}
.cc .send{background:var(--cc-acc);color:#04120e;border:0;border-radius:8px;padding:6px 16px;font:inherit;font-weight:600;cursor:pointer}
.cc .send:disabled{opacity:.45;cursor:not-allowed}
.cc .x{background:transparent;border:1px solid var(--cc-line);color:var(--cc-dim);border-radius:6px;cursor:pointer;font:inherit;padding:2px 8px}
.cc .out{margin-top:8px;white-space:pre-wrap;font-size:12.5px;background:#070c14;border:1px solid var(--cc-line);border-radius:6px;padding:8px;max-height:220px;overflow:auto}
.cc .out code{font-family:ui-monospace,Consolas,monospace;font-size:12px}
@media (max-width:520px){.cc .lab{width:100%}}`;

  let st = null, back = null, box = null, rerouteTimer = 0;
  const cfg = () => window.ChorusComposer.config || {};

  function ensureDom() {
    if (back) return;
    const style = document.createElement('style'); style.textContent = CSS; document.head.append(style);
    back = document.createElement('div'); back.className = 'cc-back'; back.hidden = true;
    back.innerHTML = '<div class="cc" role="dialog" aria-modal="true" aria-labelledby="cc-title"></div>';
    box = back.firstElementChild;
    back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
    back.addEventListener('keydown', onKey);
    document.body.append(back);
  }

  function onKey(e) {
    e.stopPropagation();                         // the page's own shortcuts (Tab, 1-4, Space...) stay out of the composer
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key === 'Enter' && !e.shiftKey && e.target.tagName === 'TEXTAREA') { e.preventDefault(); send(); return; }
    if (e.key === 'Enter' && e.target.tagName === 'INPUT') { e.preventDefault(); send(); return; }
    if (e.key === 'Tab') {                       // keep focus inside: Tab cycles chips and fields
      const f = [...box.querySelectorAll('textarea,input,button:not([disabled])')];
      if (!f.length) return;
      const i = f.indexOf(document.activeElement);
      e.preventDefault();
      f[(i + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    }
  }

  function guess(node) {                         // only when the feeder is unreachable (snapshot file)
    const n = node || {};
    const kind = n.kind === 'pr' ? 'review-request' : (n.failing || n.down || n.ok === false || n.kind === 'crystal') ? 'order' : 'ask';
    const label = n.name || n.title || n.kind || '';
    return { draft: { kind, text: n.draft || (label ? `About ${label}: ` : ''), station: 'anvil' }, to: 'claude (msi seat)', label: 'MSI Claude',
      where: 'channel', reach: 'live', when: 'now', due: '', why: n.verdict || n.detail || '', confidence: 0, reasons: 'router offline: a simple guess',
      alternatives: [], capability: [], offline: true };
  }

  async function route(extra) {
    const body = { text: st.edited ? st.text : '', node: st.node, kind: st.forcedKind || undefined, to: st.forcedTo || undefined, ...extra };
    let r;
    try {
      const res = await fetch('route', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const j = await res.json(); if (!j.ok) throw new Error(j.error || 'refused'); r = j.message;
    } catch (err) { r = guess(st.node); if (st.forcedKind) r.draft.kind = st.forcedKind; }
    st.route = r;
    if (!st.forcedTo) st.to = r.to;
    st.cands = [{ to: r.to, label: r.label, where: r.where, reach: r.reach, because: r.reasons }, ...(r.alternatives || [])];
    if (st.forcedTo && !st.cands.some((c) => c.to === st.forcedTo)) st.cands.unshift({ to: st.forcedTo, label: st.forcedTo, where: 'channel', reach: 'live' });
    if (!st.forcedKind) st.kind = r.draft.kind;
    if (!st.forcedWhere) st.where = (st.cands.find((c) => c.to === st.to) || {}).where || r.where;
    if (!st.edited) st.text = r.draft.text;
    if (!st.whyEdited) st.why = r.why === 'you asked' ? '' : r.why;
    if (!st.whenPicked) { st.when = r.when; st.due = r.due; }
    st.station = r.draft.station;
    render();
  }

  function whereOptions() {
    const c = st.cands.find((x) => x.to === st.to);
    if (!c) return [st.where];
    // cloud seats: GitHub is where they look; 'channel' posts the line AND mirrors it to GitHub
    if (['gpt-6', 'gpt6', 'codex', 'muse'].includes(st.to)) return (st.node && st.node.url) ? ['github', 'review-queue', 'channel'] : ['review-queue', 'channel'];
    return [c.where];
  }
  function current() { return st.cands.find((c) => c.to === st.to) || { label: st.to, reach: 'live' }; }
  function previewText() {
    const c = current();
    let s = `Send to ${c.label} as ${KIND_WORDS[st.kind] || st.kind}${st.where !== 'channel' ? ' (' + (WHERE_WORDS[st.where] || st.where) + ')' : ''}, ${st.when}`;
    if (st.why) s += `, because ${st.why.replace(/\.$/, '')}`;
    if (c.reach === 'prepared') s += ' (prepared: you send it)';
    return s + '.';
  }

  function chips(group, items, sel) {
    return items.map(([v, l, sub]) => `<button type="button" class="chip" data-g="${group}" data-v="${esc(v)}" aria-pressed="${v === sel}"${sub ? ` title="${esc(sub)}"` : ''}>${esc(l)}${sub && group === 'to' ? `<small>${esc(sub.split(',')[0])}</small>` : ''}</button>`).join('');
  }

  function render() {
    const n = st.node || {}, label = n.name || n.title || (n.repo ? `${n.repo}#${n.number}` : '') || n.kind || '';
    const can = canSend(), r = st.route || {};
    const whenItems = [['now', 'now', ''], ['next hourly cycle', 'next cycle', 'hourly']];
    if (st.when && !whenItems.some(([v]) => v === st.when)) whenItems.push([st.when, st.when, st.due]);
    const whoItems = st.cands.slice(0, 5).map((c) => [c.to, c.label, `${c.reach === 'prepared' ? 'prepared' : c.where}, ${c.because || ''}`]);
    box.innerHTML = `<header><div><h2 id="cc-title">Send</h2><div class="about">${label ? 'about: ' + esc(label) : 'no node attached'}${r.offline ? ' · router offline (snapshot): a simple guess' : r.confidence ? ` · router confidence ${Math.round(r.confidence * 100)}%` : ''}</div></div><button type="button" class="x" data-close aria-label="Close (Esc)">Esc</button></header>
      <textarea data-text maxlength="600" aria-label="Message" placeholder="What should happen? (Enter sends, Shift+Enter is a new line)">${esc(st.text)}</textarea>
      <div class="grp" role="group" aria-label="Templates"><span class="lab">Start</span>${TEMPLATES.map(([k, l], i) => `<button type="button" class="chip tpl" data-tpl="${i}">${esc(l)}</button>`).join('')}</div>
      <div class="grp" role="group" aria-label="Kind"><span class="lab">Kind</span>${chips('kind', KINDS.filter(([k]) => k !== 'action-order' || n.action).map(([k, l]) => [k, l, '']), st.kind)}</div>
      <div class="grp" role="group" aria-label="Who"><span class="lab">Who</span>${chips('to', whoItems, st.to)}</div>
      <div class="grp" role="group" aria-label="Where"><span class="lab">Where</span>${chips('where', whereOptions().map((w) => [w, WHERE_WORDS[w] || w, '']), st.where)}</div>
      <div class="grp" role="group" aria-label="When"><span class="lab">When</span>${chips('when', whenItems, st.when)}<input class="whenx" data-whenx placeholder="or: after #424 / at 14:30" aria-label="When, custom"></div>
      <div class="grp"><span class="lab">Why</span><input class="why" data-why maxlength="240" value="${esc(st.why)}" placeholder="one plain sentence" aria-label="Why"></div>
      <div class="preview ${current().reach === 'prepared' ? 'prep' : ''}" data-preview>${esc(previewText())}</div>
      <div class="foot"><span class="note ${st.noteCls || ''}" data-note>${esc(st.note || (can ? '' : (cfg().mock ? '' : 'Snapshot view: start chorus/mindview_feed.py to send.')))}</span><button type="button" class="send" data-send ${can ? '' : 'disabled'}>${cfg().mock ? 'Send (mock)' : 'Send'}</button></div>
      ${st.out ? `<div class="out" data-out>${st.out}</div>` : ''}`;
    wire();
  }

  function wire() {
    const ta = box.querySelector('[data-text]');
    ta.addEventListener('input', () => { st.text = ta.value; st.edited = true; refreshPreview(); clearTimeout(rerouteTimer); rerouteTimer = setTimeout(() => route().then(focusText), 700); });
    box.querySelector('[data-why]').addEventListener('input', (e) => { st.why = e.target.value; st.whyEdited = true; refreshPreview(); });
    box.querySelector('[data-whenx]').addEventListener('change', (e) => setWhen(e.target.value));
    box.querySelector('[data-close]').addEventListener('click', close);
    box.querySelector('[data-send]').addEventListener('click', send);
    box.querySelectorAll('[data-g]').forEach((b) => b.addEventListener('click', () => pick(b.dataset.g, b.dataset.v)));
    box.querySelectorAll('[data-tpl]').forEach((b) => b.addEventListener('click', () => template(+b.dataset.tpl)));
  }
  function focusText() { const ta = box.querySelector('[data-text]'); if (ta) { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); } }
  function refreshPreview() { const p = box.querySelector('[data-preview]'); if (p) p.textContent = previewText(); }

  function setWhen(v) {
    v = String(v || '').trim(); if (!v) return;
    let m = v.match(/after\s+((?:[\w.-]+)?#\d+)/i), due = '';
    if (m) { v = `after ${m[1]} merges`; due = `after:${m[1]}`; }
    else if ((m = v.match(/(?:at\s+)?(\d{1,2}):(\d{2})/))) {
      const d = new Date(); d.setHours(+m[1], +m[2], 0, 0); if (d <= new Date()) d.setDate(d.getDate() + 1);
      v = `at ${m[1].padStart(2, '0')}:${m[2]}`; due = d.toISOString().replace(/\.\d+Z$/, 'Z');
    } else if (/hour|cycle/i.test(v)) { v = 'next hourly cycle'; due = 'hourly'; }
    else { st.note = 'When: try "after #424", "at 14:30" or "next cycle".'; st.noteCls = 'bad'; render(); return; }
    st.when = v; st.due = due; st.whenPicked = true; st.note = ''; render();
  }

  function pick(g, v) {
    if (g === 'kind') { st.forcedKind = v; st.kind = v; st.forcedTo = null; st.forcedWhere = false; route(); return; }
    if (g === 'to') { st.forcedTo = v; st.to = v; st.forcedWhere = false; route(); return; }
    if (g === 'where') { st.where = v; st.forcedWhere = true; render(); return; }
    if (g === 'when') { st.when = v; st.due = v === 'now' ? '' : v === 'next hourly cycle' ? 'hourly' : (st.route && st.route.due) || ''; st.whenPicked = true; render(); }
  }

  function template(i) {
    const [kind, , tpl] = TEMPLATES[i], n = st.node || {};
    const label = n.name || n.title || (n.repo ? `${n.repo}#${n.number}` : '') || 'this';
    st.text = tpl.replace('{label}', label).replace('{why}', st.why ? st.why.replace(/\.?$/, '.') : '');
    st.edited = true; st.forcedKind = kind; st.forcedTo = null; st.forcedWhere = false;
    route().then(focusText);
  }

  function canSend() { const c = cfg(); return !!(c.mock || (c.canSend ? c.canSend() : false)); }

  async function send() {
    if (st.busy) return;
    const text = String(st.text || '').trim();
    if (!text) { st.note = 'Write the message first.'; st.noteCls = 'bad'; render(); focusText(); return; }
    if (!canSend()) { st.note = 'Snapshot view: start chorus/mindview_feed.py to send.'; st.noteCls = 'bad'; render(); return; }
    const n = st.node || {};
    const body = { kind: st.kind, to: st.to, where: st.where, text, why: st.why, when: st.when, due: st.due, node: st.node || {}, station: st.station };
    if (st.kind === 'action-order') { body.action = n.action; body.target = n.target; }
    st.busy = true; st.note = 'Sending…'; st.noteCls = ''; render();
    try {
      if (cfg().mock) {
        const said = cfg().mockSend ? cfg().mockSend(body) : '';
        st.note = `MOCK: not sent. ${said || previewText()}`; st.noteCls = 'ok';
      } else {
        const r = await fetch('send', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        const j = await r.json(); if (!j.ok) throw new Error(j.error || 'refused');
        const res = j.message;
        st.note = res.delivered ? `Sent: ${res.summary}.` : `Prepared, not sent: ${res.summary}.`; st.noteCls = 'ok';
        if (res.answer) st.out = `<b>${esc(current().label)} answers:</b>\n${esc(res.answer)}`;
        else if (res.prepared && res.prepared.command) st.out = `Paste this to send it:\n<code>${esc(res.prepared.command)}</code>`;
        else if (res.prepared) st.out = `Ready to send:\n<code>${esc(JSON.stringify(res.prepared, null, 1))}</code>`;
        else st.out = '';
        if (cfg().onSent) try { cfg().onSent(res, body); } catch (e) { /* the page's refresh must not undo a real send */ }
      }
    } catch (err) { st.note = 'Not sent: ' + (err.message || 'the feeder is not answering'); st.noteCls = 'bad'; }
    st.busy = false; render();
    const b = box.querySelector('[data-send]'); if (b) b.focus();
  }

  function open(o) {
    ensureDom();
    o = o || {};
    st = { node: o.node || null, text: o.text || '', edited: !!o.text, forcedKind: o.kind || null, forcedTo: o.to && o.to !== 'any' ? o.to : null,
      kind: o.kind || 'ask', to: o.to || 'claude (msi seat)', where: 'channel', when: 'now', due: '', why: '', cands: [], note: '', out: '' };
    back.hidden = false; render(); focusText();
    route().then(focusText);
  }
  function close() { if (back) back.hidden = true; st = null; if (cfg().onClose) cfg().onClose(); }

  window.ChorusComposer = Object.assign(window.ChorusComposer || {}, { open, close, isOpen: () => !!(back && !back.hidden) });
})();
