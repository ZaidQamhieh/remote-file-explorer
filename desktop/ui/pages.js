/* RFE Tonal - shell, pages, dialogs, palette, keyboard, main loop. */
(function () {
  'use strict';
  const A = window.A, E = A.E, U = A.U, S = A.S, $ = A.$, $$ = A.$$, esc = A.esc, ic = A.ic, fic = A.fic, st = A.state, Pane = A.Pane;
  const KEY = 'rfe-tonal-settings-v1';
  try { Object.assign(S, JSON.parse(localStorage.getItem(KEY) || '{}')); } catch (e) { /* storage unavailable */ }
  const save = () => { if (/[?&]thumb=1/.test(location.search)) return; try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) { /* ignore */ } };
  const applyTheme = () => {
    const dark = S.theme === 'dark' || (S.theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light'; document.documentElement.dataset.density = S.density === 'compact' ? 'compact' : 'comfortable';
    if (typeof syncThemeBtn === 'function') syncThemeBtn();
  };

  function syncThemeBtn() {
    const b = $('#btnTheme'); if (!b) return; const dark = document.documentElement.dataset.theme === 'dark';
    b.innerHTML = ic(dark ? 'moon' : 'sun'); b.title = 'Theme: ' + (S.theme === 'system' ? 'system (' + (dark ? 'dark' : 'light') + ')' : S.theme);
  }
  function setTheme(v) { S.theme = v; save(); applyTheme(); syncThemeBtn(); if (st.view === 'settings') pageSettings(); }
  function themeMenu(btn) {
    const r = btn.getBoundingClientRect(); const mk = (v, icn, l) => ({ icon: S.theme === v ? 'check' : icn, label: l, onClick: () => setTheme(v) });
    A.menu(r.right - 200, r.bottom + 6, [{ head: 'Theme' }, mk('light', 'sun', 'Light'), mk('dark', 'moon', 'Dark'), mk('system', 'monitor', 'Match system')]);
  }
  A.setTheme = setTheme; A.save = save;
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { if (S.theme === 'system') { applyTheme(); syncThemeBtn(); } });

  /* ---------- panes ---------- */
  A.mainPane = new Pane('main', null, { onNav: () => { renderDetail(); renderChip(); }, onSelect: () => renderDetail(), onSpin: () => { const b = $('#btnRefresh'); if (b) { b.classList.add('spin'); setTimeout(() => b.classList.remove('spin'), 700); } } });
  A.localPane = new Pane('local', 'local', { compact: true, rh: 40, onSelect: () => renderLocalFooter(), onNav: () => renderLocalFooter() });
  A.activePane = A.mainPane;
  A.setActive = (p) => { A.activePane = p; };
  A.mainHost = () => A.mainPane.host;
  A.setMainHost = (h) => { A.mainPane.setHost(h); renderChip(); renderDetail(); renderRail(); };
  A.showDetails = () => { st.sideTab = 'details'; renderSide(); };

  /* ---------- routing / layout ---------- */
  A.go = (v) => {
    if (st.view === v && v !== 'files') { renderStage(); return; }
    st.view = v; closePop(); renderAll(); if (v === 'tools' && A.toolOpened) A.toolOpened();
  };
  function layout() {
    const m = $('#main'); m.classList.toggle('nosid', st.view !== 'files'); m.classList.toggle('nosheet', st.view === 'transfers');
    m.style.setProperty('--sheet', st.sheetOpen ? '252px' : '66px'); $('#side').style.display = st.view === 'files' ? '' : 'none';
  }
  function renderAll() { layout(); renderRail(); renderChip(); renderStage(); renderSide(); renderSheet(true); }
  A.renderAll = renderAll;
  A.renderRail = () => renderRail(); /* A control that redraws the page keeps the keyboard focus: the same switch or segment button gets it back. */
  A.pageSettings = () => {
    const a = document.activeElement; const inSeg = a && a.closest && a.closest('[data-set]');
    const sel = a && a.dataset && $('#stage').contains(a) ? (a.dataset.sw ? '[data-sw="' + a.dataset.sw + '"]' : a.dataset.sx ? '[data-sx="' + a.dataset.sx + '"]' : inSeg && a.dataset.v !== undefined ? '[data-set="' + inSeg.dataset.set + '"] [data-v="' + a.dataset.v + '"]' : '') : '';
    pageSettings();
    if (sel) { const n = $(sel, $('#stage')); if (n) n.focus(); }
  }; A.renderDetail = () => renderDetail();

  /* ---------- rail ---------- */
  function counts() {
    const T = E.tasks; const g = { active: 0, attn: 0, queued: 0, done: 0 }; for (const t of T) g[A.groupOf(t)]++; return g;
  }
  function renderRail() {
    const c = counts(); const bad = E.servers.some((s) => s.state === 'lost' || s.state === 'offline' || s.state === 'trust' || s.state === 'refused');
    const D = (v, i, l, extra) => '<button class="dest' + (st.view === v ? ' on' : '') + '" data-go="' + v + '" aria-label="' + l + '"><div class="pill">' + ic(i) + (extra || '') + '</div>' + l + '</button>';
    $('#rail').innerHTML = '<div class="rmenu" title="RFE">' + ic('list') + '</div><button class="fab" data-new="1" title="New connection" aria-label="New connection">' + ic('plug') + '</button>' +
      D('files', 'folder', 'Files') + D('servers', 'server', 'Servers', bad ? '<i class="dt"></i>' : '') + D('devices', 'phone', 'Devices', A.X && A.X.inbox && A.X.inbox.length ? '<i class="bg">' + A.X.inbox.length + '</i>' : '') +
      D('transfers', 'swap', 'Transfers', c.attn ? '<i class="bg">' + c.attn + '</i>' : c.active + c.queued ? '<i class="bg pri">' + (c.active + c.queued) + '</i>' : '') +
      D('search', 'search', 'Search') + D('tools', 'layers', 'Tools') + D('history', 'history', 'History') + '<div class="sp"></div>' + D('settings', 'gear', 'Settings');
  }
  $('#rail').addEventListener('click', (e) => { const b = e.target.closest('[data-go]'); if (b) A.go(b.dataset.go); else if (e.target.closest('[data-new]')) A.serverDialog(); });

  /* ---------- top bar ---------- */
  function buildTop() {
    $('#top').innerHTML = '<label class="sbar">' + ic('search') + '<input id="q" placeholder="Search files on this server" aria-label="Search" autocomplete="off"><kbd>/</kbd></label><button class="srv" id="chip" aria-haspopup="menu"></button><span class="sp"></span><button class="ib" id="btnRefresh" title="Refresh (F5)" aria-label="Refresh">' + ic('refresh') + '</button><button class="ib" id="btnQR" title="Pair a phone (QR)" aria-label="Pair a phone">' + ic('qr') + '</button><button class="ib" id="btnTheme" title="Theme" aria-label="Theme">' + ic('sun') + '</button><button class="ib" id="btnPal" title="Command palette (Ctrl+K)" aria-label="Command palette">' + ic('command') + '</button><button class="ib" id="btnBell" title="Notifications" aria-label="Notifications">' + ic('bell') + '<i class="bd" id="bd" hidden></i></button><button class="av" id="btnAv" aria-label="Account">Z</button>';
    const q = $('#q'); let tm;
    q.addEventListener('input', () => { clearTimeout(tm); tm = setTimeout(() => runQuery(q.value), 280); });
    q.addEventListener('keydown', (e) => { if (e.key === 'Enter') { clearTimeout(tm); runQuery(q.value); } if (e.key === 'Escape') { q.value = ''; q.blur(); runQuery(''); } });
    $('#chip').addEventListener('click', (e) => serverMenu(e.currentTarget));
    $('#btnRefresh').addEventListener('click', () => (st.view === 'files' ? A.mainPane.refresh(true) : A.go('files')));
    $('#btnPal').addEventListener('click', () => palette());
    $('#btnQR').addEventListener('click', () => A.pairDialog && A.pairDialog());
    $('#btnTheme').addEventListener('click', (e) => themeMenu(e.currentTarget));
    syncThemeBtn();
    $('#btnBell').addEventListener('click', (e) => bellMenu(e.currentTarget));
    $('#btnAv').addEventListener('click', (e) => { const r = e.currentTarget.getBoundingClientRect(); A.menu(r.right - 224, r.bottom + 6, [{ head: (() => { const sv = E.server(A.mainPane.host); return sv && sv.signedIn && sv.user ? sv.user + '@' + sv.name : 'Not signed in'; })() }, { icon: 'phone', label: 'Pair a phone', onClick: () => A.pairDialog && A.pairDialog() }, { icon: 'user', label: 'Accounts…', onClick: () => A.accountsDialog && A.accountsDialog() }, { icon: 'gear', label: 'Settings', onClick: () => A.go('settings') }, { icon: 'keyboard', label: 'Keyboard shortcuts', onClick: shortcutsDialog }]); });
  }
  function runQuery(v) {
    st.q = v.trim(); if (st.q && A.recordQuery) A.recordQuery(st.q);
    if (!st.q) { if (st.view === 'search') { A.searchRun = null; renderStage(); } return; }
    if (st.view !== 'search') { st.view = 'search'; layout(); renderRail(); renderSide(); renderSheet(true); }
    startSearch();
  }
  A.runQuery = (v) => { const q = $('#q'); if (q) q.value = v; runQuery(v); };
  function renderChip() {
    const h = A.mainPane.host; const s = E.server(h) || { name: 'No server', state: 'disconnected', latency: 0, via: '' }; const chip = $('#chip'); if (!chip) return;
    const state = h === 'local' ? 'online' : s.state; const lat = h === 'local' ? 'this computer' : state === 'online' ? s.latency + ' ms · ' + s.via : state === 'lost' ? 'connection lost' : state === 'offline' ? 'offline' : state === 'connecting' ? 'connecting…' : state === 'trust' ? 'verify key' : state === 'refused' ? 'key changed' : 'not connected';
    chip.innerHTML = '<i class="dot ' + state + '"></i>' + esc(A.hostName(h)) + '<small>' + esc(lat) + '</small>' + ic('chevron-down');
    const q = $('#q'); if (q) q.placeholder = 'Search in ' + (h === 'local' ? 'this computer' : s.name);
  }
  function serverMenu(btn) {
    const r = btn.getBoundingClientRect();
    const dotc = (s) => (s === 'online' ? 'var(--ok-dot)' : s === 'lost' || s === 'offline' || s === 'refused' ? 'var(--err)' : s === 'disconnected' ? 'var(--outline)' : 'var(--amber-dot)');
    const items = [{ head: 'Browse on' }, { dot: 'var(--primary)', label: 'This computer', sub: 'local', onClick: () => A.setMainHost('local') }, '-'].concat(E.servers.map((s) => ({ dot: dotc(s.state), label: s.name, sub: s.state === 'online' ? s.latency + ' ms' : s.state, onClick: () => { if (st.view !== 'files') A.go('files'); A.setMainHost(s.id); if (s.state === 'disconnected') E.connect(s.id); } })), '-', { icon: 'server', label: 'Manage servers…', onClick: () => A.go('servers') }, { icon: 'plus', label: 'New connection…', onClick: () => A.serverDialog() });
    A.menu(r.left, r.bottom + 6, items.concat(A.favItems ? A.favItems() : []));
  }
  let popOpen = null;
  function closePop() { A.closeMenus(); popOpen = null; }
  function bellMenu(btn) {
    const r = btn.getBoundingClientRect(); const ns = E.notes.slice(0, 12);
    const html = ns.length ? ns.map((n) => '<div class="ni ' + n.kind + (n.read ? '' : ' unread') + '">' + ic(n.kind === 'error' ? 'alert-circle' : n.kind === 'ok' ? 'check-circle' : 'info') + '<div><span>' + esc(n.text) + '</span><small>' + A.ago(n.at) + '</small></div></div>').join('') : '<div class="ni">No notifications</div>';
    const m = A.menu(r.right - 380, r.bottom + 6, [], { cls: 'notif' }); m.innerHTML = '<div class="mh">Notifications</div>' + html + '<hr><div class="mi" data-clear="1">' + ic('check') + '<span>Mark all as read</span></div>';
    m.addEventListener('click', (e) => { if (e.target.closest('[data-clear]')) { E.notes.forEach((n) => (n.read = true)); updateBell(); A.closeMenus(); } });
    setTimeout(() => { E.notes.forEach((n) => (n.read = true)); updateBell(); }, 1500);
  }
  function updateBell() { const n = E.notes.filter((x) => !x.read).length; const b = $('#bd'); if (b) { b.hidden = !n; b.textContent = n; } }

  /* ---------- stage ---------- */
  function renderStage() {
    const s = $('#stage');
    if (st.view === 'files') { s.className = 'stage'; s.innerHTML = '<div id="paneMain" style="display:flex;flex-direction:column;flex:1;min-height:0"></div>'; A.mainPane.mount($('#paneMain')); return; }
    s.className = 'stage page'; s.scrollTop = 0;
    ({ servers: pageServers, transfers: pageTransfers, search: pageSearch, history: pageHistory, settings: pageSettings, devices: () => A.pageDevices(), tools: () => A.pageTools() })[st.view](); if (A.afterPage) A.afterPage(st.view);
  }
  /* ---------- side (details + local) ---------- */
  function renderSide() {
    const side = $('#side'); if (st.view !== 'files') return;
    side.innerHTML = '<div class="stabs2" role="tablist"><button role="tab" data-tab="details" class="' + (st.sideTab === 'details' ? 'on' : '') + '">Details</button><button role="tab" data-tab="local" class="' + (st.sideTab === 'local' ? 'on' : '') + '">Local files</button></div><div class="sbody"><div class="detail" id="detail"' + (st.sideTab === 'details' ? '' : ' hidden') + '></div><div id="localWrap" style="display:' + (st.sideTab === 'local' ? 'flex' : 'none') + ';flex-direction:column;flex:1;min-height:0"><div id="paneLocal" style="display:flex;flex-direction:column;flex:1;min-height:0"></div><div class="da" id="localFoot" style="border-top:1px solid var(--outline-var);padding-top:12px"></div></div></div>';
    A.localPane.mount($('#paneLocal')); renderDetail(); renderLocalFooter();
  }
  $('#side').addEventListener('click', (e) => {
    const t = e.target.closest('[data-tab]'); if (t) { st.sideTab = t.dataset.tab; renderSide(); return; }
    const a = e.target.closest('[data-do]'); if (!a) return; const p = A.mainPane; const sel = p.selected();
    switch (a.dataset.do) {
      case 'download': p.transfer(); break; case 'rename': p.startRename(sel[0]); break; case 'delete': p.del(); break;
      case 'preview': p.preview(sel[0]); break; case 'newfolder': p.startNew(); break;
      case 'upload': st.sideTab = 'local'; renderSide(); break;
      case 'uploadsel': A.localPane.transfer(); break;
      case 'settings': A.go('settings'); break;
    }
  });
  function renderLocalFooter() {
    const f = $('#localFoot'); if (!f) return; const sel = A.localPane.selected(); const m = A.mainPane; const ok = m.host !== 'local' && E.connected(m.host);
    f.innerHTML = sel.length ? '<button class="btn f" data-do="uploadsel"' + (ok ? '' : ' disabled') + '>' + ic('upload') + 'Upload ' + sel.length + ' to ' + esc(A.hostName(m.host)) + '</button><span style="color:var(--on-var);font-size:12.5px;align-self:center">' + (ok ? 'into ' + esc(m.path) : 'connect a server first') + '</span>' : '<div style="color:var(--on-var);font-size:13px;display:flex;gap:8px;align-items:center">' + ic('info') + 'Select files here, then upload. Or drag them onto the file list.</div>';
  }
  function renderDetail() {
    const d = $('#detail'); if (!d) return; const p = A.mainPane;
    if (!p.online()) { d.innerHTML = '<div class="dd" style="padding-top:24px;color:var(--on-var)">' + ic('plug', { size: 40 }) + '<h3 style="margin-top:10px;color:var(--on-surface)">' + esc(A.hostName(p.host)) + '</h3><p>Not connected. Details appear here once you connect.</p></div>'; return; }
    const sel = p.selected(); const dir = E.fs.get(p.host, p.path);
    const remote = p.host !== 'local'; const kv = (rows) => '<dl class="kv">' + rows.map((r) => '<dt>' + r[0] + '</dt><dd class="' + (r[2] || '') + '">' + r[1] + '</dd>').join('') + '</dl>';
    if (sel.length === 0 && !dir) {
      d.innerHTML = '<div class="dprev">' + ic('folder', { size: 56 }) + '</div><div class="dd"><h3>' + esc(A.hostName(p.host)) + '</h3><div class="sub">Details appear here once the folder is open.</div></div>';
      return;
    }
    if (sel.length === 0) {
      d.innerHTML = A.previewHTML(p.host, p.path, dir) + '<div class="dd"><h3>' + esc(U.baseOf(p.path) || A.hostName(p.host)) + '</h3><div class="sub">' + E.fs.itemCount(dir).toLocaleString() + ' items · folder</div>' + kv([['Modified', U.fmtDate(dir.mod)], ['Permissions', esc(dir.perm) + ' ' + esc(dir.own), 'mono'], ['Location', esc(p.path), 'mono'], ['Server', esc(A.hostName(p.host)) + (remote ? ' · ' + E.server(p.host).latency + ' ms' : '')]]) + '</div><div class="hint">' + ic('info') + '<span>Select a file to preview it. Drag files here from the Local files tab to ' + (remote ? 'upload' : 'copy') + '.</span></div><div class="da"><button class="btn t" data-do="newfolder">' + ic('folder-plus') + 'New folder</button>' + (remote ? '<button class="btn" data-do="upload">' + ic('upload') + 'Upload files</button>' : '') + '</div>';
      return;
    }
    if (sel.length === 1) {
      const n = sel[0]; const k = U.kindOf(n); const full = U.join(p.path, n.n); const t = n.t === 'dir' ? E.fs.total(n) : null;
      d.innerHTML = A.previewHTML(p.host, p.path, n) + '<div class="dd"><h3>' + esc(n.n) + '</h3><div class="sub">' + U.KINDS[k] + (n.t === 'dir' ? (n.cc == null && !n.kids ? '' : ' · ' + E.fs.itemCount(n).toLocaleString() + ' items') : ' · ' + U.fmtBytes(n.b)) + '</div>' + (!E.fs.canRead(n) ? '<div class="hint" style="margin:0 0 10px;background:var(--warn-c);color:var(--on-warn-c)">' + ic('lock') + '<span>Owned by <b>' + esc(n.own) + '</b>, mode ' + U.permOctal(n.perm) + '. You can’t read this file; downloads will fail.</span></div>' : '') + kv([['Modified', U.fmtDate(n.mod)], ['Permissions', esc(n.perm) + ' ' + esc(n.own), 'mono'], ['Location', esc(full), 'mono']].concat(t ? [['Contents', t.files.toLocaleString() + ' files, ' + t.dirs + ' folders · ' + U.fmtBytes(t.bytes)]] : []).concat(remote ? [['Download to', esc(S.downloadDir) + ' <a data-do="settings">Change</a>']] : [])) + '</div><div class="da"><button class="btn f" data-do="download">' + ic(remote ? 'download' : 'upload') + (remote ? 'Download' : 'Upload') + '</button>' + (n.t === 'file' ? '<button class="btn" data-do="preview">' + ic('eye') + 'Preview</button>' : '') + '<button class="btn" data-do="rename">' + ic('edit') + 'Rename</button><button class="btn e" data-do="delete" aria-label="Delete">' + ic('trash') + '</button></div>';
      return;
    }
    const tot = sel.reduce((a, n) => a + E.fs.total(n).bytes, 0);
    d.innerHTML = '<div class="dprev">' + ic('copy', { size: 56 }) + '</div><div class="dd"><h3>' + sel.length + ' items selected</h3><div class="sub">' + U.fmtBytes(tot) + ' total</div><ul class="names" style="list-style:none;margin:0;padding:0">' + sel.slice(0, 8).map((n) => '<li style="display:flex;gap:8px;padding:3px 0;align-items:center">' + fic(n) + '<span class="trunc">' + esc(n.n) + '</span></li>').join('') + (sel.length > 8 ? '<li style="color:var(--on-var)">and ' + (sel.length - 8) + ' more</li>' : '') + '</ul></div><div class="da"><button class="btn f" data-do="download">' + ic(remote ? 'download' : 'upload') + (remote ? 'Download' : 'Upload') + '</button><button class="btn e" data-do="delete">' + ic('trash') + 'Delete</button></div>';
  }

  /* ---------- sheet ---------- */
  let sheetSig = '';
  A.renderSheet = renderSheet;
  function renderSheet(force) {
    const sh = $('#sheet'); if (st.view === 'transfers') return;
    const c = counts(); const sig = E.tasks.map((t) => t.id + t.state + (t.msg || '') + (t.conflict ? 'c' : '')).join('|') + '/' + st.sheetTab + st.sheetOpen + st.view + (E.tasks.length ? '' : 'e');
    if (!force && sig === sheetSig) { A.patchCards(sh); updateTotals(); return; }
    sheetSig = sig; layout();
    const tab = (k, l, n, red) => '<button class="stab' + (st.sheetTab === k ? ' on' : '') + '" data-stab="' + k + '" role="tab">' + l + ' <b' + (red && n ? ' class="r"' : '') + '>' + n + '</b></button>';
    const list = E.tasks.filter((t) => A.groupOf(t) === st.sheetTab).sort((a, b) => a.queuedAt - b.queuedAt);
    const anyRun = E.tasks.some((t) => t.state === 'running' || t.state === 'queued'), anyPaused = E.tasks.some((t) => t.state === 'paused');
    sh.classList.toggle('min', !st.sheetOpen); $('#main').classList.toggle('noconn', !(A.mainPane.host !== 'local' && E.connected(A.mainPane.host)));
    sh.innerHTML = '<button class="efab" data-efab="1">' + ic('upload') + 'Upload</button><div class="hdl" data-hdl="1" title="' + (st.sheetOpen ? 'Collapse' : 'Expand') + '" role="button" aria-label="Toggle transfers"></div><div class="stabs" role="tablist">' + tab('active', 'Active', c.active) + tab('attn', 'Needs attention', c.attn, true) + tab('queued', 'Queued', c.queued) + tab('done', 'Done', c.done) + '<span class="sp"></span><div class="tot"><span id="tot"></span>' + (anyRun || !anyPaused ? '<button class="btn sm" data-sa="pauseall"' + (anyRun ? '' : ' disabled') + '>' + ic('pause') + 'Pause all</button>' : '<button class="btn sm" data-sa="resumeall">' + ic('play') + 'Resume all</button>') + (c.done ? '<button class="btn sm tx" data-sa="clear">Clear done</button>' : '') + '</div></div><div class="cards">' + (list.length ? list.map(A.card).join('') : '<div class="none">' + ic(st.sheetTab === 'attn' ? 'check-circle' : 'swap', { size: 22 }) + (st.sheetTab === 'active' ? 'No transfers running. Drag files onto the list, or press Upload.' : st.sheetTab === 'attn' ? 'Nothing needs your attention.' : st.sheetTab === 'queued' ? 'Nothing is waiting in the queue.' : 'Completed transfers show up here.') + '</div>') + '</div>';
    A.patchCards(sh); updateTotals();
  }
  function updateTotals() { const t = $('#tot'); if (!t) return; const sp = E.totalSpeed(); const n = E.tasks.filter((x) => x.state === 'running').length; t.textContent = n ? U.fmtSpeed(sp) + ' total · ' + n + ' running' : 'Idle'; }
  $('#sheet').addEventListener('click', (e) => {
    const sa = e.target.closest('[data-sa]'); if (sa) { ({ pauseall: E.pauseAll, resumeall: E.resumeAll, clear: E.clearDone })[sa.dataset.sa](); return; }
    const tb = e.target.closest('[data-stab]'); if (tb) { st.sheetTab = tb.dataset.stab; st.sheetOpen = true; renderSheet(true); return; }
    if (e.target.closest('[data-hdl]')) { st.sheetOpen = !st.sheetOpen; renderSheet(true); return; }
    if (e.target.closest('[data-efab]')) { uploadFab(); return; }
    A.cardClick(e);
  });
  function uploadFab() {
    const m = A.mainPane;
    if (m.host === 'local' || !E.connected(m.host)) { A.snack('Open a connected server first to upload into it.', { error: true, action: 'Servers', onAction: () => A.go('servers') }); return; }
    if (st.view !== 'files') A.go('files');
    const sel = A.localPane.selected();
    if (sel.length) { A.localPane.transfer(); return; }
    A.chooseAndUpload();
  }

  /* ---------- servers page ---------- */
  function spark(h) {
    const v = h.slice(-30); const w = 200, hh = 36; const nums = v.filter((x) => x != null); if (nums.length < 2) return '<svg viewBox="0 0 200 36"><line x1="0" y1="18" x2="200" y2="18" stroke="var(--outline-var)" stroke-dasharray="4 4"/></svg>';
    const mx = Math.max.apply(null, nums) + 2, mn = Math.min.apply(null, nums) - 2; let d = '', pen = false;
    v.forEach((x, i) => { if (x == null) { pen = false; return; } const X = (i / (v.length - 1)) * w, Y = hh - 3 - ((x - mn) / (mx - mn || 1)) * (hh - 8); d += (pen ? 'L' : 'M') + X.toFixed(1) + ' ' + Y.toFixed(1); pen = true; });
    return '<svg viewBox="0 0 200 36" preserveAspectRatio="none"><path d="' + d + '" fill="none" stroke="var(--primary)" stroke-width="1.8" stroke-linejoin="round"/></svg>';
  }
  const STL = { login: 'Sign in', online: 'Connected', lost: 'Connection lost', offline: 'Offline', connecting: 'Connecting', trust: 'Verify key', refused: 'Key changed', disconnected: 'Not connected' };
  function serverCard(s) {
    const icn = /^(Windows|macOS|Darwin)/i.test(s.os) ? 'laptop' : /raspberry|arm/i.test(s.os) ? 'cpu' : 'server'; const hasDisk = s.disk[1] > 0; const used = hasDisk ? s.disk[0] / s.disk[1] : 0; const big = s.disk[1] >= 1000; const dsk = (v) => (big ? (v / 1000).toFixed(1) : v.toFixed(v < 10 ? 1 : 0));
    let note = '', act = '';
    const B = (a, l, k, i) => '<button class="btn sm ' + k + '" data-sa="' + a + '" data-id="' + s.id + '">' + (i ? ic(i) : '') + l + '</button>';
    if (s.state === 'online') act = B('open', 'Open', 'f', 'folder-open') + B('disconnect', 'Disconnect', '');
    else if (s.state === 'lost') { note = '<div class="note w">' + ic('wifi-off') + '<span>Lost ' + Math.round((E.now() - s.lostAt) / 1000) + ' s ago. ' + (S.autoReconnect ? 'Retrying in ' + Math.max(0, Math.ceil(s.retryIn)) + ' s. Transfers are paused.' : 'Auto-reconnect is off.') + '</span></div>'; act = B('retry', 'Retry now', 'f', 'refresh') + B('edit', 'Edit', ''); }
    else if (s.state === 'offline') { note = '<div class="note e">' + ic('alert-circle') + '<span>' + esc(s.error || 'Host did not answer on ' + s.host + ':' + s.port) + '. Last seen ' + (s.lastSeen ? A.ago(s.lastSeen) : 'never') + '.</span></div>'; act = B('retry', 'Try again', 'f', 'refresh') + B('edit', 'Edit', ''); }
    else if (s.state === 'connecting') { note = '<div class="note w">' + ic('spinner') + '<span>Contacting ' + esc(s.host) + '…</span></div>'; act = B('cancel', 'Cancel', ''); }
    else if (s.state === 'login') { note = '<div class="note w">' + ic('user') + '<span>' + esc(s.msg || 'Signed out on this host. Sign in to continue.') + '</span></div>'; act = B('signin', 'Sign in', 'f', 'user') + B('cancel', 'Cancel', ''); }
    else if (s.state === 'trust') { note = '<div class="note w">' + ic('shield') + '<span>Unknown host key. Compare <span class="mono">' + esc(s.fp.slice(0, 23)) + '…</span> with the one on the server before you trust it.</span></div>'; act = B('trust', 'Trust and connect', 'f', 'shield-check') + B('cancel', 'Cancel', ''); }
    else if (s.state === 'refused') { note = '<div class="note e">' + ic('shield') + '<span>The certificate changed. Connection refused to protect your files.</span></div>'; act = B('reverify', 'Review…', 'f', 'shield-check') + B('diag', 'Diagnose', ''); }
    else act = B('connect', 'Connect', 'f', 'plug') + B('edit', 'Edit', '');
    return '<div class="sc' + (A.mainPane.host === s.id ? ' sel' : '') + '" data-sid="' + s.id + '"><div class="h"><div class="gl">' + ic(icn) + '</div><div><b>' + esc(s.name) + '</b><small>' + esc(s.host) + ':' + s.port + '</small></div><span class="sp"></span><span class="chipst ' + s.state + '"><i></i>' + STL[s.state] + '</span></div>' +
      '<div class="meta"><div><small>Route</small>' + esc(s.via) + '</div><div><small>System</small>' + esc(s.os) + '</div><div><small>Agent</small>' + esc(s.agent || '—') + '</div></div>' +
      '<div class="lat">' + spark(s.hist) + '<b>' + (s.state === 'online' ? s.latency + '<small> ms</small>' : '—') + '</b></div>' +
      '<div><div class="bar' + (used > 0.8 ? ' hi' : '') + '"><i style="width:' + (used * 100).toFixed(0) + '%"></i></div><div class="row2"><span>Storage</span><span>' + (hasDisk ? dsk(s.disk[0]) + (big ? ' TB' : ' GB') + ' of ' + dsk(s.disk[1]) + (big ? ' TB' : ' GB') : '—') + '</span></div></div>' + note +
      '<div class="ac">' + act + '<button class="ib sm" data-sa="more" data-id="' + s.id + '" aria-label="More">' + ic('more-v') + '</button></div></div>';
  }
  A.serverCard = serverCard;
  function pageServers() {
    const on = E.servers.filter((s) => s.state === 'online').length;
    $('#stage').innerHTML = '<h2 class="pt">Servers</h2><p class="ps">' + E.servers.length + ' saved · ' + on + ' connected · browsing <b>' + esc(A.hostName(A.mainPane.host)) + '</b>' + (E.servers.length ? '' : '. No host is saved yet.') + '</p><div class="grid3" id="sgrid">' + E.servers.map(serverCard).join('') + '<div class="sc add" data-sa="add" role="button" tabindex="0">' + ic('plus') + '<b>Add a server</b><span style="color:var(--on-var)">Host, key and fingerprint</span></div></div>';
  }
  $('#stage').addEventListener('click', (e) => {
    const sa = e.target.closest('[data-sa]'); if (!sa || st.view !== 'servers') return; const id = sa.dataset.id; const s = id && E.server(id);
    switch (sa.dataset.sa) {
      case 'open': A.setMainHost(id); A.go('files'); break;
      case 'connect': A.setMainHost(id); E.connect(id); A.go('files'); break;
      case 'disconnect': E.disconnect(id); break; case 'retry': E.retryNow(id); break; case 'cancel': E.cancelConnect(id); break;
      case 'reverify': A.reverifyDialog(id); break; case 'diag': A.diagnose(id); break;
      case 'trust': E.trust(id); A.signInDialog(E.server(id)); break; case 'signin': A.signInDialog(s); break; case 'edit': A.serverDialog(s); break; case 'add': A.serverDialog(); break;
      case 'more': { const r = sa.getBoundingClientRect(); A.menu(r.left, r.bottom, [{ icon: 'folder-open', label: 'Browse files', disabled: s.state !== 'online', onClick: () => { A.setMainHost(id); A.go('files'); } }, { icon: 'edit', label: 'Edit connection', onClick: () => A.serverDialog(s) }].concat(A.serverMenuExtra ? A.serverMenuExtra(s) : [], ['-', { icon: 'trash', label: 'Forget server', danger: true, onClick: () => forgetDialog(s) }])); break; }
    }
  });
  function forgetDialog(s) {
    const n = E.tasks.filter((t) => t.host === s.id && A.groupOf(t) !== 'done').length;
    A.dialog({ icon: 'trash', cls: 'danger', title: 'Forget ' + s.name + '?', body: 'This removes the saved connection and its pinned key.' + (n ? ' <b>' + n + ' unfinished transfer' + (n === 1 ? '' : 's') + ' will be cancelled.</b>' : ''), actions: [{ label: 'Cancel' }, { label: 'Forget', kind: 'ed', cb: async () => { if (A.mainPane.host === s.id) A.mainPane.setHost('local'); try { await E.forget(s.id); A.snack('Forgot ' + s.name); } catch (e) { A.snack(e.message, { error: true }); } renderAll(); } }] });
  }
  A.serverDialog = (s) => {
    const edit = !!s; const v = s || { name: '', host: '', port: 7443 };
    const d = A.dialog({
      icon: 'plug', title: edit ? 'Edit ' + s.name : 'New connection', width: 520, enter: 'ok',
      body: (edit || !A.connTabs ? '' : A.connTabs('manual')) + '<div class="fld"><label>Name</label><input id="sn" value="' + esc(v.name) + '" placeholder="e.g. render-farm" spellcheck="false"><span class="err" id="sne"></span></div><div class="fld two"><div class="fld" style="margin:0"><label>Host or address</label><input id="sh" value="' + esc(v.host) + '"' + (edit ? ' disabled' : '') + ' placeholder="100.64.0.12 or host.example.com" spellcheck="false"><span class="err" id="she"></span></div><div class="fld" style="margin:0"><label>Port</label><input id="sp" value="' + v.port + '"' + (edit ? ' disabled' : '') + ' inputmode="numeric"></div></div><div style="color:var(--on-var);font-size:12.5px">' + (edit ? 'The address belongs to the trusted key. To use another address, add a new connection.' : "Type the new host's address. Your current login stays saved. " + 'The app reads the server’s certificate fingerprint first and sends no password until you confirm it.') + '</div>',
      actions: [{ label: 'Cancel' }, { id: 'ok', label: edit ? 'Save' : 'Connect', kind: 'f', icon: edit ? 'check' : 'plug', cb: (ctl) => {
        const g = (i) => $(i, ctl.el); const host = g('#sh').value.trim(), port = parseInt(g('#sp').value, 10) || 7443; const name = g('#sn').value.trim() || host; let bad = false;
        g('#sne').textContent = ''; g('#she').textContent = '';
        if (E.servers.some((x) => x.name.toLowerCase() === name.toLowerCase() && (!edit || x.id !== s.id))) { g('#sne').textContent = 'A server with this name already exists'; bad = true; }
        if (!host || /\s/.test(host)) { g('#she').textContent = 'Enter a host or IP address'; bad = true; }
        if (bad) return false;
        if (edit) { E.updateServer(s.id, { name }).then(() => { A.snack('Saved ' + name); renderAll(); }).catch((e) => A.snack(e.message, { error: true })); }
        else A.addAndOpen({ name, host, port });
      } }]
    });
    return d;
  };

  /* ---------- transfers page ---------- */
  function pageTransfers() {
    const c = counts(); const T = E.tasks; const sec = (k, title, hint) => { const l = T.filter((t) => A.groupOf(t) === k).sort((a, b) => a.queuedAt - b.queuedAt); return l.length ? '<div class="sec">' + title + ' <b>' + l.length + '</b></div><div class="grid3 cwide">' + l.map(A.card).join('') + '</div>' : ''; };
    const moved = E.history.filter((h) => h.ok).length; const sessionBytes = T.filter((t) => t.state === 'done').reduce((a, t) => a + t.bytes, 0) + T.filter((t) => t.state === 'running').reduce((a, t) => a + t.done, 0);
    $('#stage').innerHTML = '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap"><div style="flex:1"><h2 class="pt">Transfers</h2><p class="ps" style="margin:0 0 14px">Everything moving between this computer and your servers.</p></div><button class="btn" data-pa="pauseall">' + ic('pause') + 'Pause all</button><button class="btn" data-pa="resumeall">' + ic('play') + 'Resume all</button><button class="btn" data-pa="retryfailed">' + ic('retry') + 'Retry failed</button><button class="btn tx" data-pa="clear">Clear completed</button></div>' +
      '<div class="sum"><div><b id="sumSpeed">' + U.fmtSpeed(E.totalSpeed()) + '</b><small>current speed</small></div><div><b>' + c.active + '</b><small>active</small></div><div><b>' + c.queued + '</b><small>queued</small></div><div><b style="color:' + (c.attn ? 'var(--err)' : 'inherit') + '">' + c.attn + '</b><small>need attention</small></div><div><b>' + c.done + '</b><small>completed</small></div><div><b>' + U.fmtBytes(sessionBytes) + '</b><small>moved this session</small></div></div>' +
      (T.length ? sec('attn', 'Needs attention') + sec('active', 'Active') + sec('queued', 'Queued') + sec('done', 'Completed') : '<div class="es" style="min-height:300px"><div class="box"><div class="ico">' + ic('swap') + '</div><h3>No transfers yet</h3><p>Drag files between Local files and a server, or use Upload and Download. ' + moved + ' earlier transfer' + (moved === 1 ? '' : 's') + ' in History.</p><div class="row"><button class="btn f" data-pa="files">' + ic('folder') + 'Go to files</button></div></div></div>');
    A.patchCards($('#stage'));
  }
  $('#stage').addEventListener('click', (e) => {
    if (st.view !== 'transfers') return; const pa = e.target.closest('[data-pa]');
    if (pa) { ({ pauseall: E.pauseAll, resumeall: E.resumeAll, retryfailed: E.retryFailed, clear: E.clearDone, files: () => A.go('files') })[pa.dataset.pa](); return; }
    A.cardClick(e);
  });

  /* ---------- search ---------- */
  function startSearch() {
    const sr = (A.searchRun = { q: st.q, scope: st.scope || 'server', filter: st.sfilter || 'all', results: [], scanned: 0, done: false, tok: Math.random() });
    const hosts = sr.scope === 'server' ? [A.mainPane.host] : sr.scope === 'all' ? E.servers.filter((s) => s.state === 'online').map((s) => s.id) : ['local'];
    sr.hosts = hosts.filter((h) => E.connected(h)); sr.skipped = hosts.filter((h) => !E.connected(h));
    sr.job = E.makeSearch(sr.hosts, sr.q, { filter: sr.filter, max: 400 });
    if (A.sync) { while (!sr.job.step(1e6)); sr.results = sr.job.results; sr.scanned = sr.job.scanned; sr.done = true; renderStage(); return; }
    renderStage();
    const step = () => { if (A.searchRun !== sr) return; const done = sr.job.step(7000); sr.results = sr.job.results; sr.scanned = sr.job.scanned; sr.done = done; updateSearch(); if (!done) setTimeout(step, 16); };
    setTimeout(step, 30);
  }
  function pageSearch() {
    const sr = A.searchRun;
    if (!sr) { $('#stage').innerHTML = '<h2 class="pt">Search</h2><p class="ps">Type in the search bar above. Searches run live over the whole folder tree, including very large folders.</p><div class="es" style="min-height:320px"><div class="box"><div class="ico">' + ic('search') + '</div><h3>Search a server</h3><p>Try <span class="mono">keystore</span>, <span class="mono">release</span> or <span class="mono">frame_0042</span>. Press <span class="kbd">/</span> to focus the search bar.</p>' + (A.searchExtra ? A.searchExtra() : '') + '</div></div>'; return; }
    const chip = (k, l, cur, key) => '<button class="chip' + (cur === k ? ' on' : '') + '" data-sf="' + key + ':' + k + '">' + (cur === k ? ic('check') : '') + l + '</button>';
    $('#stage').innerHTML = '<h2 class="pt">Results for “' + esc(sr.q) + '”' + (A.searchSave ? A.searchSave(sr) : '') + '</h2><div class="chips" style="padding:8px 0 0">' + chip('server', 'This server', sr.scope, 'scope') + chip('all', 'All connected servers', sr.scope, 'scope') + chip('local', 'This computer', sr.scope, 'scope') + '<span style="width:12px"></span>' + [['all', 'Everything'], ['folders', 'Folders'], ['packages', 'Packages'], ['media', 'Media'], ['archives', 'Archives'], ['big', 'Over 100 MB']].map((f) => chip(f[0], f[1], sr.filter, 'filter')).join('') + '</div><div class="prog" id="sprog"></div><div id="sres"></div>';
    updateSearch();
  }
  function updateSearch() {
    const sr = A.searchRun; if (!sr || st.view !== 'search') return; const pg = $('#sprog'), rs = $('#sres'); if (!pg) return;
    const where = sr.hosts.map(A.hostName).join(', ');
    pg.innerHTML = sr.skipped.length && !sr.hosts.length ? ic('wifi-off') + '<span>' + esc(sr.skipped.map(A.hostName).join(', ')) + ' is not connected, so it can’t be searched.</span>' : (sr.done ? ic('check-circle') + '<span><b>' + sr.results.length + (sr.results.length >= 400 ? '+' : '') + '</b> result' + (sr.results.length === 1 ? '' : 's') + ' · scanned ' + sr.scanned.toLocaleString() + ' items on ' + esc(where) + '</span>' : '<div class="lin ind"><i></i></div><span>Searching ' + esc(where) + '… <b>' + sr.scanned.toLocaleString() + '</b> items scanned · <b>' + sr.results.length + '</b> found</span>') + (sr.skipped.length && sr.hosts.length ? '<span>· skipped ' + esc(sr.skipped.map(A.hostName).join(', ')) + ' (not connected)</span>' : '');
    if (!sr.results.length) { rs.innerHTML = sr.done ? '<div class="es" style="min-height:240px"><div class="box"><div class="ico">' + ic('search') + '</div><h3>No matches</h3><p>Nothing named like “' + esc(sr.q) + '” in ' + esc(where || 'the selected scope') + '.</p></div></div>' : ''; return; }
    rs.innerHTML = sr.results.slice(0, 200).map((r, i) => '<div class="res" data-ri="' + i + '"><div class="lead">' + fic(r.node) + '</div><div style="min-width:0"><b>' + A.hl(r.node.n, sr.q) + (!E.fs.canRead(r.node) ? '<span style="font-size:11.5px;color:var(--warn);background:var(--warn-c);border-radius:8px;padding:0 7px;margin-left:8px">' + esc(r.node.own) + ' only</span>' : '') + '</b><small>' + esc(r.dir) + '</small></div><div class="sv"><i></i>' + esc(A.hostName(r.host)) + '</div><div style="color:var(--on-var);font-size:13px">' + U.fmtDate(r.node.mod) + '</div><div style="text-align:right;color:var(--on-var);font-size:13px">' + A.itemSize(r.node) + '</div></div>').join('') + (sr.results.length > 200 ? '<div style="padding:12px;color:var(--on-var)">Showing the first 200 results. Narrow the search to see more.</div>' : '');
  }
  $('#stage').addEventListener('click', (e) => {
    if (st.view !== 'search') return; const sf = e.target.closest('[data-sf]');
    if (sf) { const [k, v] = sf.dataset.sf.split(':'); if (k === 'scope') st.scope = v; else st.sfilter = v; startSearch(); return; }
    const r = e.target.closest('[data-ri]'); if (r) { const x = A.searchRun.results[+r.dataset.ri]; openResult(x); }
  });
  function openResult(x) {
    if (x.host === 'local') { A.go('files'); st.sideTab = 'local'; renderSide(); A.localPane.go(x.node.t === 'dir' ? x.path : x.dir); if (x.node.t !== 'dir') { A.localPane.sel = new Set([x.node.n]); A.localPane.render(); } return; }
    A.mainPane.setHost(x.host); A.go('files'); A.mainPane.go(x.node.t === 'dir' ? x.path : x.dir);
    if (x.node.t !== 'dir') { A.mainPane.sel = new Set([x.node.n]); const i = A.mainPane.items.findIndex((n) => n.n === x.node.n); A.mainPane.anchor = i; A.mainPane.render(); const rows = $('[data-rows]', A.mainPane.el); if (rows && i >= 0) { rows.scrollTop = Math.max(0, i * A.mainPane.rh - 120); A.mainPane.renderRows(); } renderDetail(); }
  }

  /* ---------- history ---------- */
  function pageHistory() {
    const F = [['all', 'All'], ['transfer', 'Transfers'], ['conn', 'Connections'], ['audit', 'Security'], ['err', 'Errors']]; const f = st.histFilter;
    const rows = E.history.filter((h) => f === 'all' || (f === 'err' ? h.error : f === 'transfer' ? h.kind === 'transfer' || h.kind === 'queue' : h.kind === f));
    $('#stage').innerHTML = '<div style="display:flex;align-items:center;gap:10px"><div style="flex:1"><h2 class="pt">History</h2><p class="ps" style="margin:0 0 6px">Transfers and connection events from this session.</p></div><button class="btn tx" data-hc="1">Clear history</button></div><div class="chips" style="padding:6px 0 10px">' + F.map((x) => '<button class="chip' + (f === x[0] ? ' on' : '') + '" data-hf="' + x[0] + '">' + (f === x[0] ? ic('check') : '') + x[1] + '</button>').join('') + '</div>' +
      (rows.length ? rows.slice(0, 200).map((h) => '<div class="hrow ' + (h.error ? 'err' : h.ok ? 'ok' : '') + '"><div class="gi">' + ic(h.error ? 'alert-circle' : h.kind === 'audit' ? 'shield-check' : h.kind === 'conn' ? 'plug' : h.kind === 'queue' ? 'clock' : h.dir === 'up' ? 'upload' : h.dir === 'down' ? 'download' : 'check-circle') + '</div><div>' + esc(h.text) + (h.host ? '<br><small>' + esc(A.hostName(h.host)) + '</small>' : '') + '</div><time>' + U.fmtTime(h.at) + '</time></div>').join('') : '<div class="es" style="min-height:280px"><div class="box"><div class="ico">' + ic('history') + '</div><h3>Nothing here yet</h3><p>' + (f === 'audit' ? (A.X.auditDenied && A.X.auditDenied.size ? 'This login cannot read the audit log or the agent log.' : 'The audit log is empty.') : E.history.length ? 'No loaded event matches these filters.' : 'Finished and failed transfers, connections and drops are listed here.') + '</p></div></div>');
  }
  $('#stage').addEventListener('click', (e) => {
    if (st.view !== 'history') return; const hf = e.target.closest('[data-hf]'); if (hf) { st.histFilter = hf.dataset.hf; pageHistory(); } else if (e.target.closest('[data-hc]')) { E.history.length = 0; E.emit('history'); }
  });

  /* ---------- settings ---------- */
  function pageSettings() {
    const seg = (key, opts) => '<div class="seg" data-set="' + key + '">' + opts.map((o) => '<button data-v="' + o[0] + '" class="' + (String(S[key]) === String(o[0]) ? 'on' : '') + '">' + o[1] + '</button>').join('') + '</div>';
    const sw = (key) => '<button class="sw' + (S[key] ? ' on' : '') + '" data-sw="' + key + '" role="switch" aria-checked="' + !!S[key] + '" aria-label="' + key + '"></button>';
    const row = (t, s, c) => '<div class="sr"><div class="l"><b>' + t + '</b>' + (s ? '<small>' + s + '</small>' : '') + '</div>' + c + '</div>';
    $('#stage').innerHTML = '<h2 class="pt">Settings</h2><p class="ps">Changes apply immediately and are kept on this computer.</p><div class="setg">' +
      '<div class="sg"><h4>Transfers</h4>' + row('Parallel transfers', 'How many files move at once', seg('parallel', [[1, '1'], [2, '2'], [3, '3'], [4, '4']])) + row('Speed limit', 'Shared across running transfers', seg('limit', [[0, 'None'], [10, '10 MB/s'], [25, '25'], [50, '50']])) + row('When a name already exists', 'Applies to new transfers', seg('onConflict', [['ask', 'Ask'], ['replace', 'Replace'], ['keep', 'Keep both'], ['skip', 'Skip']])) + row('Verify checksums', 'Compare SHA-256 after each download', sw('verify')) + row('Download folder', 'Downloads are saved here.<br><span class="mono">' + esc(A.downloadDir()) + '</span>', '<span style="display:flex;gap:8px"><button class="btn" data-sx="dlfolder">' + ic('folder-open') + 'Change…</button><button class="btn tx" data-sx="dlreset">Reset</button></span>') + '</div>' +
      '<div class="sg"><h4>Connection</h4>' + row('Reconnect automatically', 'Retries every 8 seconds and resumes transfers when the server is back', sw('autoReconnect')) + row('Notify when a transfer finishes', '', sw('notifyDone')) + row('Notify about errors', 'Failed transfers and lost connections', sw('notifyErrors')) + '</div>' +
      '<div class="sg"><h4>Appearance</h4>' + row('Theme', '', seg('theme', [['light', 'Light'], ['dark', 'Dark'], ['system', 'System']])) + row('Row density', 'Compact fits more rows', seg('density', [['comfortable', 'Comfortable'], ['compact', 'Compact']])) + '</div>' +
      (A.settingsExtra ? A.settingsExtra({ row, seg, sw }) : '') +
      '<div class="sg"><h4>Help</h4><div class="sr"><div class="l"><b>Keyboard shortcuts</b><small>Press <span class="kbd">Ctrl</span> <span class="kbd">K</span> for everything</small></div><button class="btn" data-sx="keys">' + ic('keyboard') + 'Show</button></div></div></div>';
  }
  $('#stage').addEventListener('click', (e) => {
    if (st.view !== 'settings') return;
    const sg = e.target.closest('[data-set] button'); if (sg) { const k = sg.closest('[data-set]').dataset.set; let v = sg.dataset.v; if (!isNaN(+v) && v !== '') v = +v; S[k] = v; save(); applyTheme(); if (k === 'parallel' || k === 'limit' || k === 'onConflict') E.pushPrefs(); A.pageSettings(); if (k === 'density') { A.mainPane.render(); A.localPane.render(); } return; }
    const sw = e.target.closest('[data-sw]'); if (sw) { S[sw.dataset.sw] = !S[sw.dataset.sw]; save(); if (sw.dataset.sw === 'verify') E.pushPrefs(); A.pageSettings(); if (A.onSwitch) A.onSwitch(sw.dataset.sw); return; }
    const sx = e.target.closest('[data-sx]'); if (sx) { const a = sx.dataset.sx; if (A.settingsAction && A.settingsAction(a)) return; if (a === 'keys') shortcutsDialog(); }
  });
  function shortcutsDialog() {
    const k = [['Ctrl K', 'Command palette'], ['/', 'Focus search'], ['Enter', 'Open folder or preview file'], ['Backspace', 'Up one folder'], ['Alt ← →', 'Back / forward'], ['F2', 'Rename'], ['Del', 'Delete'], ['Ctrl A', 'Select all'], ['Ctrl D', 'Download selection'], ['Ctrl U', 'Upload from Local files'], ['Ctrl ⇧ N', 'New folder'], ['F5', 'Refresh'], ['Ctrl L', 'Edit path'], ['Esc', 'Clear selection / close']];
    A.dialog({ icon: 'keyboard', title: 'Keyboard shortcuts', width: 520, body: '<div style="display:grid;grid-template-columns:auto 1fr;gap:8px 20px">' + k.map((r) => '<span class="kbd">' + r[0] + '</span><span>' + r[1] + '</span>').join('') + '</div>', actions: [{ label: 'Close', kind: 'f' }] });
  }

  /* ---------- command palette ---------- */
  function palette() {
    const m = A.mainPane; const cur = m.host; const cmds = [];
    const C = (icon, label, run, kbd, sub) => cmds.push({ icon, label, run, kbd, sub });
    C('folder', 'Go to Files', () => A.go('files')); C('server', 'Go to Servers', () => A.go('servers')); C('swap', 'Go to Transfers', () => A.go('transfers')); C('search', 'Go to Search', () => A.go('search')); C('history', 'Go to History', () => A.go('history')); C('gear', 'Open Settings', () => A.go('settings'));
    for (const s of E.servers) C('server', 'Switch to ' + s.name, () => { A.go('files'); A.setMainHost(s.id); if (s.state === 'disconnected') E.connect(s.id); }, '', s.state === 'online' ? s.latency + ' ms' : s.state);
    C('monitor', 'Browse this computer', () => { A.go('files'); A.setMainHost('local'); });
    C('folder-plus', 'New folder here', () => { A.go('files'); m.startNew(); }, 'Ctrl+⇧+N'); C('refresh', 'Refresh folder', () => m.refresh(true), 'F5');
    C('download', 'Download selection', () => m.transfer(), 'Ctrl+D'); C('upload', 'Upload from Local files', uploadFab, 'Ctrl+U');
    C('plug', 'New connection…', () => A.serverDialog()); 
    C('pause', 'Pause all transfers', () => E.pauseAll()); C('play', 'Resume all transfers', () => E.resumeAll()); C('retry', 'Retry failed transfers', () => E.retryFailed()); C('check', 'Clear completed transfers', () => E.clearDone());
    (A.paletteExtra || []).forEach((f) => f(C));
    C('palette', 'Toggle dark theme', () => { S.theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; save(); applyTheme(); if (st.view === 'settings') pageSettings(); }); C('keyboard', 'Keyboard shortcuts', shortcutsDialog);
    let hi = 0, shown = cmds.slice();
    const d = A.dialog({ title: '', width: 600, noFocus: false, body: '', actions: [] });
    const sc = d.el.parentNode; sc.innerHTML = '<div class="pal" role="dialog" aria-label="Command palette"><div class="in">' + ic('search') + '<input id="pq" placeholder="Type a command or server name" spellcheck="false" aria-label="Command"></div><div class="lst" id="pl"></div></div>';
    sc.style.placeItems = 'start center';
    const draw = () => { $('#pl', sc).innerHTML = shown.length ? shown.map((c, i) => '<div class="it' + (i === hi ? ' hi' : '') + '" data-i="' + i + '">' + ic(c.icon) + '<span>' + esc(c.label) + '</span>' + (c.kbd ? '<kbd>' + esc(c.kbd) + '</kbd>' : c.sub ? '<small>' + esc(c.sub) + '</small>' : '') + '</div>').join('') : '<div class="none">No matching command</div>'; const h = $('.hi', sc); if (h) h.scrollIntoView({ block: 'nearest' }); };
    const run = (c) => { sc.remove(); document.removeEventListener('keydown', key, true); c.run(); };
    const key = (e) => { if (e.key === 'Escape') { e.stopPropagation(); sc.remove(); document.removeEventListener('keydown', key, true); } else if (e.key === 'ArrowDown') { e.preventDefault(); hi = Math.min(shown.length - 1, hi + 1); draw(); } else if (e.key === 'ArrowUp') { e.preventDefault(); hi = Math.max(0, hi - 1); draw(); } else if (e.key === 'Enter') { e.preventDefault(); if (shown[hi]) run(shown[hi]); } };
    document.addEventListener('keydown', key, true);
    sc.addEventListener('mousedown', (e) => { if (e.target === sc) { sc.remove(); document.removeEventListener('keydown', key, true); } });
    $('#pl', sc).addEventListener('click', (e) => { const it = e.target.closest('[data-i]'); if (it) run(shown[+it.dataset.i]); });
    $('#pq', sc).addEventListener('input', (e) => { const w = e.target.value.toLowerCase().split(/\s+/).filter(Boolean); shown = cmds.filter((c) => w.every((x) => (c.label + ' ' + (c.sub || '')).toLowerCase().includes(x))); hi = 0; draw(); });
    draw(); $('#pq', sc).focus();
  }
  A.palette = palette;

  /* ---------- keyboard ---------- */
  document.addEventListener('keydown', (e) => {
    const t = e.target; const typing = t.matches && t.matches('input,textarea,select');
    if (document.querySelector('.scrim')) return;
    const mod = e.ctrlKey || e.metaKey;
    if (mod && e.key.toLowerCase() === 'k') { e.preventDefault(); palette(); return; }
    if (e.key === '/' && !typing) { e.preventDefault(); $('#q').focus(); return; }
    if (typing) return;
    const p = st.view === 'files' ? A.activePane : null; if (e.key === 'F5') { e.preventDefault(); if (p) p.refresh(true); return; }
    if (!p) return; const sel = p.selected(); const one = sel.length === 1 ? sel[0] : null;
    if (mod && e.key.toLowerCase() === 'a') { e.preventDefault(); p.selectAll(); }
    else if (e.key === 'Delete') { if (sel.length) { e.preventDefault(); p.del(); } }
    else if (e.key === 'F2') { if (one) { e.preventDefault(); p.startRename(one); } }
    else if (e.key === 'Enter') { if (one) { e.preventDefault(); p.open(one); } }
    else if (e.key === 'Backspace' || (e.altKey && e.key === 'ArrowUp')) { e.preventDefault(); p.up(); }
    else if (e.altKey && e.key === 'ArrowLeft') { e.preventDefault(); p.back(); } else if (e.altKey && e.key === 'ArrowRight') { e.preventDefault(); p.forward(); }
    else if (mod && e.key.toLowerCase() === 'd') { e.preventDefault(); if (p.host !== 'local') p.transfer(); }
    else if (mod && e.key.toLowerCase() === 'u') { e.preventDefault(); uploadFab(); }
    else if (mod && e.shiftKey && e.key.toLowerCase() === 'n') { e.preventDefault(); p.startNew(); }
    else if (mod && e.key.toLowerCase() === 'l') { e.preventDefault(); p.editPath = true; p.render(); }
    else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault(); const n = p.items.length; if (!n) return; let i = p.anchor; i = e.key === 'ArrowDown' ? Math.min(n - 1, i + 1) : Math.max(0, i < 0 ? 0 : i - 1);
      p.selectIdx(i, e); const rows = $('[data-rows]', p.el); if (rows && p.mode === 'list') { const rh = p.rh; if (i * rh < rows.scrollTop) rows.scrollTop = i * rh; else if ((i + 1) * rh > rows.scrollTop + rows.clientHeight) rows.scrollTop = (i + 1) * rh - rows.clientHeight; }
    }
    else if (e.key === 'Escape') { if (p.sel.size) { p.sel.clear(); p.selChanged(); } }
  });

  /* ---------- engine events -> UI ---------- */
  let pend = new Set(), raf = 0, lastSlow = 0;
  A.flush = () => { if (raf) { cancelAnimationFrame(raf); raf = 0; } const p = pend; pend = new Set(); p.forEach(flush); };
  const sched = (k) => { pend.add(k); if (!raf) raf = requestAnimationFrame(() => { raf = 0; const p = pend; pend = new Set(); p.forEach(flush); }); };
  function flush(k) {
    if (k === 'transfers') { renderSheet(); renderRail(); if (st.view === 'transfers') pageTransfers(); }
    else if (k === 'servers') { renderChip(); renderRail(); for (const p of [A.mainPane, A.localPane]) if (p.host !== 'local' && p.el && p.el.isConnected) { p.refreshItems(); p.render(); } if (st.view === 'servers') pageServers(); renderDetail(); renderLocalFooter(); }
    else if (k === 'fs') { for (const p of [A.mainPane, A.localPane]) if (p.el && p.el.isConnected && !p.renaming && !p.creating && !p.editPath) { p.refreshItems(); p.renderRows(); p.renderFoot(); } renderDetail(); }
    else if (k === 'history') { if (st.view === 'history') pageHistory(); }
    else if (k === 'bell') updateBell();
  }
  E.on((type, data) => {
    if (type === 'tick') {
      renderSheet(); if (st.view === 'transfers') { A.patchCards($('#stage')); const s = $('#sumSpeed'); if (s) s.textContent = U.fmtSpeed(E.totalSpeed()); }
      const nowMs = performance.now(); if (nowMs - lastSlow > 900) { lastSlow = nowMs; if (st.view === 'servers') pageServers(); const h = A.mainPane.host; if (st.view === 'files' && h !== 'local' && !E.connected(h) && A.mainPane.el && A.mainPane.el.isConnected) A.mainPane.render(); renderChip(); }
    } else if (type === 'notify') { sched('bell'); if (data.kind === 'error') A.snack(data.text, /denied|owned by/i.test(data.text) ? { error: true, action: 'Transfers', onAction: () => A.go('transfers') } : { error: true, action: 'Servers', onAction: () => A.go('servers') }); }
    else sched(type === 'latency' ? 'servers' : type);
  });
  addEventListener('beforeunload', save);


  /* ---------- boot ---------- */
  applyTheme(); matchMedia('(prefers-color-scheme: dark)').addEventListener && matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyTheme);
  const q = new URLSearchParams(location.search);
  buildTop(); renderAll(); updateBell();
  /* later scripts (features, fx*) extend A: start once they have all run */
  const boot = () => E.init().then(() => {
    const first = E.servers.find((x) => x.signedIn) || E.servers[0];
    A.mainPane.setHost(q.get('host') || (first ? first.id : 'local'));
    renderAll();
    if (!E.servers.length) A.go('servers');
    if (A.maybeOnboard) A.maybeOnboard();
    if (q.get('view')) A.go(q.get('view'));
  }).catch((e) => A.snack('Could not start: ' + (e && e.message || e), { error: true }));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
  if (q.get('thumb')) document.documentElement.classList.add('nofx');
  A.paused = false;
  setInterval(() => { if (!A.paused) E.tick(250); }, 250);
  A.ready = true;
})();
