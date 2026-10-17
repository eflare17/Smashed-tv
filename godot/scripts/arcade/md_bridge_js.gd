class_name MdBridgeJs
extends RefCounted
## The browser half of the Mega Drive cabinet (web build only), put into the page once with JavaScriptBridge.
## It is the HTML game's own MEGA DRIVE code (Smashed.html, "MEGA DRIVE": mdDb, mdPut, mdUnzip, mdAddFiles,
## mdPlay, mdSnap, mdStartStream, mdApplyPad, mdJoin / mdHookCalls, mdSendPad, mdLayoutPad), reshaped as
## window.SmashedMD for Godot to call, with the menu moved into Godot (ArcadeMd). The same IndexedDB library
## ("smashed-megadrive": games and roms) and the same console choice (localStorage "smashed-console"), so on the
## same site the HTML game and this one share the library.
##
## A game runs in EmulatorJS in an iframe over the whole game, with a bar on top (its name, Set picture,
## Library, Close). The emulator's files come from ../emu/data/ (the site serves the repo's emu/ folder next to
## godot-play/), or a few other places, or EmulatorJS's own site as a last resort, like mdBasePath.
##
## Events go back to Godot as JSON through the listener Godot sets (setListener): {ev: "list", games, pick},
## {ev: "note", text}, {ev: "playing", id, name}, {ev: "started"}, {ev: "pic", id}, {ev: "library"},
## {ev: "close"}, {ev: "pad", bits} (player 2's buttons, to send to the host), {ev: "watching"}, {ev: "watch_end"}.

const JS := r"""
(function () {
if (window.SmashedMD) return;
const MD_SYS = {
  md:   { core: 'segaMD', label: 'Mega Drive',     tag: 'MD',   ext: ['md', 'bin', 'gen', 'smd', '68k', 'sgd'] },
  snes: { core: 'snes',   label: 'Super Nintendo', tag: 'SNES', ext: ['sfc', 'smc', 'fig', 'swc'] },
  sms:  { core: 'segaMD', label: 'Master System',  tag: 'SMS',  ext: ['sms'], extra: true },
  gg:   { core: 'segaMD', label: 'Game Gear',      tag: 'GG',   ext: ['gg'],  extra: true }
};
const MD_EXT = [].concat(...Object.values(MD_SYS).map(o => o.ext));
const MD_CDN = 'https://cdn.emulatorjs.org/stable/data/';
const MD_PADS = {
  md:   { btn: [4, 5, 6, 7, 1, 0, 8, 3, 10, 9, 11, 2],
          keys: { j: 4, k: 5, l: 6, u: 8, i: 9, o: 10, m: 11 }, keyHelp: 'J K L = A B C, U I O = X Y Z, Enter = Start',
          gp: { 2: 4, 0: 5, 1: 6, 4: 8, 3: 9, 5: 10, 8: 11 },
          touch: [[4, 'A', 0, 0], [5, 'B', 1, 0], [6, 'C', 2, 0], [8, 'X', 0, 1], [9, 'Y', 1, 1], [10, 'Z', 2, 1], [11, 'MODE', -1, 0]] },
  snes: { btn: [4, 5, 6, 7, 8, 0, 1, 3, 9, 10, 11, 2],
          keys: { l: 4, k: 5, j: 6, i: 8, u: 9, o: 10, m: 11 }, keyHelp: 'J K L = Y B A, I = X, U O = L R, M = Select, Enter = Start',
          gp: { 1: 4, 0: 5, 2: 6, 3: 8, 4: 9, 5: 10, 8: 11 },
          touch: [[6, 'Y', 0, 0], [5, 'B', 1, 0], [4, 'A', 2, 0], [9, 'L', 0, 1], [8, 'X', 1, 1], [10, 'R', 2, 1], [11, 'SELECT', -1, 0]] }
};
const MD_DIR_KEYS = { arrowup: 0, w: 0, arrowdown: 1, s: 1, arrowleft: 2, a: 2, arrowright: 3, d: 3, enter: 7 };
const MD = { games: [], frame: null, emu: null, playing: null, url: null, base: null, db: null, listener: null,
             box: null, mode: null, remotePad: 0, pad: 0, padSent: -1, padAt: 0, watchCall: null, watchSys: 'md', wantJoin: false,
             call: null, copy: null, pick: 'all', addedSys: null };
try { const k = localStorage.getItem('smashed-console'); if (k === 'all' || MD_SYS[k]) MD.pick = k; } catch (_) {}
function padOf(sys) { return MD_PADS[sys] || MD_PADS.md; }
function emit(o) { try { if (MD.listener) MD.listener(JSON.stringify(o)); } catch (e) { console.log('SmashedMD emit', e); } }
function note(text) { emit({ ev: 'note', text: text || '' }); if (MD.box) MD.box.note.textContent = text || ''; }
function sysOf(file) { const ext = String(file).split('.').pop().toLowerCase(); return Object.keys(MD_SYS).find(k => MD_SYS[k].ext.includes(ext)) || 'md'; }
function gameSys(g) { const k = sysOf(g.file); return MD_SYS[k] ? k : 'md'; }
function niceName(file) {
  const dot = file.lastIndexOf('.');
  const base = dot > 0 ? file.slice(0, dot) : file;
  return base.split('_').join(' ').replace(/ +/g, ' ').trim() || file;
}

// ---- the library: names in one store, the files themselves in another
function db() {
  if (!MD.db) MD.db = new Promise((res, rej) => {
    const r = indexedDB.open('smashed-megadrive', 1);
    r.onupgradeneeded = () => { r.result.createObjectStore('games', { keyPath: 'id', autoIncrement: true }); r.result.createObjectStore('roms'); };
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  return MD.db;
}
async function req(stores, mode, fn) {
  const d = await db();
  return new Promise((res, rej) => {
    const tx = d.transaction(stores, mode); let out;
    const r = fn(...[].concat(stores).map(s => tx.objectStore(s)));
    if (r && 'onsuccess' in r) r.onsuccess = () => { out = r.result; };
    tx.oncomplete = () => res(out); tx.onerror = () => rej(tx.error); tx.onabort = () => rej(tx.error);
  });
}
function sendList() {
  emit({ ev: 'list', pick: MD.pick, games: MD.games.map(g => ({ id: g.id, file: g.file, name: g.name, sys: gameSys(g), size: g.size, pic: g.pic || '' })) });
}
async function loadList() {
  try { MD.games = (await req('games', 'readonly', s => s.getAll())) || []; }
  catch (e) { MD.games = []; note("This browser won't let the game keep files (private browsing?)."); }
  MD.games.sort((a, b) => a.name.localeCompare(b.name));
  sendList();
}
async function put(file, data) {
  if (MD.games.some(g => g.file === file && g.size === data.byteLength)) return false;
  const meta = { file, name: niceName(file), sys: sysOf(file), size: data.byteLength, added: Date.now() };
  if (MD.addedSys) MD.addedSys.add(gameSys(meta));
  const d = await db();
  await new Promise((res, rej) => {
    const tx = d.transaction(['games', 'roms'], 'readwrite');
    const r = tx.objectStore('games').add(meta);
    r.onsuccess = () => { meta.id = r.result; tx.objectStore('roms').put(data, r.result); };
    tx.oncomplete = res; tx.onerror = () => rej(tx.error); tx.onabort = () => rej(tx.error);
  });
  MD.games.push(meta);
  return true;
}
async function del(id) {
  await req(['games', 'roms'], 'readwrite', (g, r) => { g.delete(id); r.delete(id); });
  MD.games = MD.games.filter(g => g.id !== id); sendList();
}
async function unzip(buf) {
  const dv = new DataView(buf), u8 = new Uint8Array(buf);
  let end = -1;
  for (let i = buf.byteLength - 22; i >= Math.max(0, buf.byteLength - 65557); i--) if (dv.getUint32(i, true) === 0x06054b50) { end = i; break; }
  if (end < 0) return null;
  const n = dv.getUint16(end + 10, true); let p = dv.getUint32(end + 16, true);
  const out = [];
  for (let k = 0; k < n; k++) {
    if (p + 46 > buf.byteLength || dv.getUint32(p, true) !== 0x02014b50) return null;
    const method = dv.getUint16(p + 10, true), csize = dv.getUint32(p + 20, true);
    const nl = dv.getUint16(p + 28, true), el = dv.getUint16(p + 30, true), cl = dv.getUint16(p + 32, true), off = dv.getUint32(p + 42, true);
    const name = new TextDecoder().decode(u8.subarray(p + 46, p + 46 + nl));
    p += 46 + nl + el + cl;
    const base = name.split('/').pop(), ext = base.split('.').pop().toLowerCase();
    if (!base || base.startsWith('.') || !MD_EXT.includes(ext)) continue;
    const at = off + 30 + dv.getUint16(off + 26, true) + dv.getUint16(off + 28, true);
    const raw = u8.subarray(at, at + csize);
    let bytes;
    if (method === 0) bytes = raw.slice();
    else if (method === 8 && typeof DecompressionStream === 'function')
      bytes = new Uint8Array(await new Response(new Blob([raw]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer());
    else return null;
    out.push({ name: base, data: bytes.buffer });
  }
  return out;
}
async function addFiles(list) {
  const files = [...(list || [])];
  if (!files.length) return;
  try { if (navigator.storage && navigator.storage.persist) navigator.storage.persist(); } catch (_) {}
  let added = 0, had = 0, skipped = 0;
  MD.addedSys = new Set();
  note('Adding ' + files.length + ' file' + (files.length > 1 ? 's' : '') + '…');
  for (const f of files) {
    const ext = f.name.split('.').pop().toLowerCase();
    try {
      if (ext === 'zip') {
        const buf = await f.arrayBuffer(), inside = await unzip(buf);
        if (inside === null) { (await put(f.name, buf)) ? added++ : had++; }
        else if (!inside.length) skipped++;
        else for (const g of inside) (await put(g.name, g.data)) ? added++ : had++;
      } else if (ext === '7z' || MD_EXT.includes(ext)) { (await put(f.name, await f.arrayBuffer())) ? added++ : had++; }
      else skipped++;
    } catch (e) { skipped++; }
  }
  MD.games.sort((a, b) => a.name.localeCompare(b.name));
  const got = [...MD.addedSys]; MD.addedSys = null;
  if (got.length && MD.pick !== 'all' && !got.every(k => k === MD.pick)) setPick(got.length === 1 ? got[0] : 'all');
  sendList();
  note([added ? 'Added ' + added + ' game' + (added > 1 ? 's' : '') + '.' : '', had ? had + ' already in your library.' : '',
        skipped ? skipped + ' file' + (skipped > 1 ? 's' : '') + ' skipped (not a Mega Drive or Super Nintendo game).' : ''].filter(Boolean).join(' ') || 'Nothing added.');
}
function setPick(k) { MD.pick = k; try { localStorage.setItem('smashed-console', k); } catch (_) {} }
// the file picker: a hidden input, clicked (the click Godot passes on is still the user's, for a few seconds)
function pick(folder) {
  const inp = document.createElement('input');
  inp.type = 'file'; inp.multiple = true; inp.style.display = 'none';
  if (folder) inp.webkitdirectory = true;
  inp.addEventListener('change', () => { addFiles(inp.files).finally(() => inp.remove()); });
  document.body.appendChild(inp);
  inp.click();
}
function canFolder() { return ('webkitdirectory' in document.createElement('input')) && !/iPhone|iPad|Android/i.test(navigator.userAgent); }

// ---- the box over the game: a bar (name, Set picture, Library, Close), a note, and the screen
function button(text, fn) {
  const b = document.createElement('button'); b.textContent = text;
  b.style.cssText = 'padding:6px 12px;font:13px ui-sans-serif,system-ui,sans-serif;background:#232833;color:#fff;border:1px solid #333a49;border-radius:6px;cursor:pointer';
  b.addEventListener('click', e => { e.preventDefault(); fn(); });
  return b;
}
function makeBox() {
  if (MD.box) return MD.box;
  const box = document.createElement('div');
  box.id = 'smashedMd';
  box.style.cssText = 'position:fixed;inset:0;z-index:1000;display:none;flex-direction:column;background:rgba(10,10,14,0.97);color:#cfd4de;font:14px ui-sans-serif,system-ui,sans-serif';
  const top = document.createElement('div');
  top.style.cssText = 'display:flex;align-items:center;gap:8px;padding:8px 10px;background:#15171e;border-bottom:1px solid #2a2f3b;flex:none';
  const title = document.createElement('span');
  title.style.cssText = 'flex:1;font-weight:700;letter-spacing:1px;color:#e0473f;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
  const snapB = button('📷 Set picture', async () => { note((await snap(true)) ? 'Picture saved.' : "Couldn't take a picture yet: wait for the game to start."); });
  const backB = button('Library', () => { stopGame(); stopWatching(true); hide(); emit({ ev: 'library' }); });
  const exitB = button('Close', () => { close(); });
  top.append(title, snapB, backB, exitB);
  const n = document.createElement('div');
  n.style.cssText = 'padding:0 10px;color:#8b93a4;font-size:12px';
  const screen = document.createElement('div');
  screen.style.cssText = 'flex:1;position:relative;background:#000';
  const wait = document.createElement('div');
  wait.style.cssText = 'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#8b93a4;pointer-events:none';
  const pad = document.createElement('div');
  pad.style.cssText = 'position:absolute;left:0;right:0;bottom:0;height:46%;pointer-events:none;display:none';
  screen.append(wait, pad);
  screen.addEventListener('click', () => { const v = screen.querySelector('video'); if (v && v.paused) v.play().then(() => { wait.textContent = ''; }).catch(() => {}); });
  box.append(top, n, screen);
  document.body.appendChild(box);
  MD.box = { el: box, title, snapB, backB, exitB, note: n, screen, wait, pad };
  layoutPad('md');
  return MD.box;
}
function show(mode, titleText) {
  const b = makeBox();
  MD.mode = mode;
  b.el.style.display = 'flex';
  b.title.textContent = titleText;
  b.snapB.style.display = mode === 'play' ? '' : 'none';
  b.backB.style.display = mode === 'play' ? '' : 'none';
  b.pad.style.display = mode === 'watch' && (('ontouchstart' in window) || navigator.maxTouchPoints > 0) ? 'block' : 'none';
}
function hide() {
  if (MD.box) MD.box.el.style.display = 'none';
  MD.mode = null;
  const c = document.querySelector('canvas'); if (c) { try { c.focus(); } catch (_) {} }
}
function close() { stopGame(); stopWatching(true); hide(); emit({ ev: 'close' }); }

async function basePath() {
  if (MD.base) return MD.base;
  for (const p of ['../emu/data/', 'emu/data/', '../../emu/data/', '../../../emu/data/']) {
    try { const r = await fetch(p + 'loader.js', { method: 'HEAD', cache: 'no-store' }); if (r.ok) return (MD.base = { path: new URL(p, location.href).href, local: true }); } catch (_) {}
  }
  return (MD.base = { path: MD_CDN, local: false });
}
async function play(id) {
  const meta = MD.games.find(g => g.id === id);
  if (!meta) return;
  if (MD.watchCall || MD.wantJoin) stopWatching(true);
  note('Loading…');
  let data;
  try { data = await req('roms', 'readonly', s => s.get(id)); } catch (_) {}
  if (!data) { note("Couldn't read that game. Try removing it and adding it again."); return; }
  const base = await basePath();
  stopGame();
  MD.playing = meta; MD.url = URL.createObjectURL(new Blob([data]));
  const cfg = { core: MD_SYS[gameSys(meta)].core, path: base.path, url: MD.url, name: meta.file };
  const lt = String.fromCharCode(60);
  const doc = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    + '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#game{width:100%;height:100%}</style></head><body><div id="game"></div><script>'
    + 'var C=' + JSON.stringify(cfg).split(lt).join('\\u003c') + ';'
    + 'window.EJS_player="#game";window.EJS_core=C.core;window.EJS_pathtodata=C.path;window.EJS_gameUrl=C.url;window.EJS_gameName=C.name;'
    + 'window.EJS_disableAutoLang=false;window.EJS_color="#e0473f";window.EJS_backgroundColor="#000";window.EJS_threads=false;'
    + 'window.EJS_onGameStart=function(){parent.postMessage({md:"started"},"*")};'
    + 'document.addEventListener("keydown",function(e){if(e.key==="Escape")parent.postMessage({md:"esc"},"*")},true);'
    + lt + '/script>' + lt + 'script src="' + base.path + 'loader.js">' + lt + '/script></body></html>';
  const b = makeBox();
  const f = document.createElement('iframe');
  f.setAttribute('allow', 'autoplay; gamepad; fullscreen');
  f.setAttribute('allowfullscreen', '');
  f.title = meta.name;
  f.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;border:0;background:#000';
  f.srcdoc = doc;
  b.screen.insertBefore(f, b.wait);
  MD.frame = f;
  b.wait.textContent = '';
  show('play', meta.name);
  note(base.local ? '' : 'Loading the emulator from EmulatorJS…');
  emit({ ev: 'playing', id: meta.id, name: meta.name, sys: gameSys(meta) });
  setTimeout(() => { try { f.focus(); } catch (_) {} }, 50);
}
function stopGame() {
  if (MD.playing) emit({ ev: 'stopped' });
  endStream();
  if (MD.frame) { try { MD.frame.remove(); } catch (_) {} }
  if (MD.url) URL.revokeObjectURL(MD.url);
  MD.frame = null; MD.emu = null; MD.url = null; MD.playing = null;
}
function started() {
  if (!MD.frame) return;
  try { MD.emu = MD.frame.contentWindow.EJS_emulator; } catch (_) { MD.emu = null; }
  emit({ ev: 'started' });
  const meta = MD.playing;
  if (meta && !meta.pic) for (const s of [9, 15, 23, 34]) setTimeout(() => { if (MD.playing === meta && !meta.pic) snap(false); }, s * 1000);
}
async function snap(force) {
  const emu = MD.emu, meta = MD.playing;
  if (!emu || !meta || !emu.gameManager || !emu.gameManager.screenshot) return false;
  let png = null; try { png = await Promise.race([emu.gameManager.screenshot(), new Promise(r => setTimeout(r, 3000))]); } catch (_) {}
  if (!png || !(png.byteLength || png.length) || MD.playing !== meta) return false;
  let bm; try { bm = await createImageBitmap(new Blob([png], { type: 'image/png' })); } catch (_) { return false; }
  const c = document.createElement('canvas'); c.width = 160; c.height = 112;
  const g = c.getContext('2d'); g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high'; g.drawImage(bm, 0, 0, c.width, c.height);
  if (!force) {
    const d = g.getImageData(0, 0, c.width, c.height).data; let sum = 0, n = 0;
    for (let i = 0; i < d.length; i += 16) { sum += d[i] + d[i + 1] + d[i + 2]; n++; }
    if (sum / n < 70) return false;
  }
  meta.pic = c.toDataURL('image/jpeg', 0.82);
  try { await req('games', 'readwrite', s => s.put(meta)); } catch (_) {}
  emit({ ev: 'pic', id: meta.id, pic: meta.pic });
  sendList();
  return true;
}
addEventListener('message', e => {
  if (!MD.frame || e.source !== MD.frame.contentWindow || !e.data) return;
  if (e.data.md === 'started') started();
  if (e.data.md === 'esc') close();
});
addEventListener('keydown', e => { if (MD.mode && e.key === 'Escape') { close(); e.preventDefault(); } }, true);

// ---- player 2 (the friend joining, milestone 4's connection carries the messages; the picture goes as a call)
// What the host tells the friend: {t:'md', on:1, name, who, sys, pic} (Godot builds it from offer()).
function offer() { const m = MD.playing; return m && MD.emu ? { name: m.name.slice(0, 60), sys: gameSys(m), pic: m.pic || '' } : null; }
// Host: the friend said mdjoin: send them the emulator's screen and sound as a PeerJS call (peer: your PeerJS
// Peer, remoteId: theirs). Returns true if the call went out.
function streamTo(peer, remoteId) {
  const emu = MD.emu;
  if (!emu || !emu.canvas || !peer || MD.call) return false;
  let stream;
  try { stream = emu.collectScreenRecordingMediaTracks(emu.canvas, 60); } catch (_) { stream = null; }
  if (!stream || !stream.getVideoTracks().length) { try { stream = emu.canvas.captureStream(60); } catch (_) { return false; } }
  const call = peer.call(remoteId, stream);
  if (!call) { stream.getTracks().forEach(t => t.stop()); return false; }
  MD.call = call; MD.copy = { stop: () => stream.getTracks().forEach(t => t.stop()) };
  call.on('close', () => { if (MD.call === call) endStream(); });
  call.on('error', () => { if (MD.call === call) endStream(); });
  note('Player 2 has joined.');
  return true;
}
function endStream() {
  const call = MD.call; MD.call = null;
  if (MD.copy) { MD.copy.stop(); MD.copy = null; }
  try { if (call) call.close(); } catch (_) {}
  applyPad(0);
}
// Host: the friend's buttons (bits: up down left right A B C start X Y Z mode), pressed as player 2.
function applyPad(bits) {
  const emu = MD.emu, was = MD.remotePad; MD.remotePad = bits;
  if (!emu || !emu.gameManager) return;
  const btn = padOf(MD.playing && gameSys(MD.playing)).btn;
  for (let i = 0; i < btn.length; i++) {
    const a = (was >> i) & 1, b = (bits >> i) & 1;
    if (a !== b) { try { emu.gameManager.simulateInput(1, btn[i], b); } catch (_) {} }
  }
}
// Friend: join the host's game (Godot sends mdjoin); answerCall(call) takes the host's PeerJS call.
function join(name, sys) {
  stopGame();
  MD.wantJoin = true; MD.pad = 0; MD.padSent = -1; MD.watchSys = MD_SYS[sys] ? sys : 'md';
  const b = makeBox();
  b.wait.textContent = 'Waiting for the picture…';
  show('watch', (name || 'MEGA DRIVE') + ' (player 2)');
  layoutPad(MD.watchSys);
  note('You are player 2.  Keys: arrows or WASD, ' + padOf(MD.watchSys).keyHelp + '.');
  try { document.activeElement && document.activeElement.blur && document.activeElement.blur(); } catch (_) {}
}
function answerCall(call) {
  if (!MD.wantJoin) { try { call.close(); } catch (_) {} return false; }
  if (MD.watchCall) { try { MD.watchCall.close(); } catch (_) {} }
  MD.watchCall = call;
  call.answer();
  call.on('stream', s => watch(s));
  call.on('close', () => { if (MD.watchCall === call) stopWatching(false); });
  return true;
}
function watch(stream) {
  const b = makeBox();
  let v = b.screen.querySelector('video');
  if (!v) {
    v = document.createElement('video'); v.playsInline = true; v.autoplay = true;
    v.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;object-fit:contain;background:#000';
    b.screen.insertBefore(v, b.wait);
  }
  v.srcObject = stream;
  b.wait.textContent = '';
  v.play().catch(() => { b.wait.textContent = 'Tap to start the picture'; v.muted = false; });
  emit({ ev: 'watching' });
}
function stopWatching(tell) {
  const was = MD.wantJoin || MD.watchCall;
  MD.wantJoin = false;
  if (MD.watchCall) { const c = MD.watchCall; MD.watchCall = null; try { c.close(); } catch (_) {} }
  if (MD.box) { const v = MD.box.screen.querySelector('video'); if (v) { v.srcObject = null; v.remove(); } for (const bt of MD.box.pad.querySelectorAll('button')) bt.style.background = ''; }
  MD.pad = 0;
  if (was) emit({ ev: 'watch_end', tell: !!tell });
  if (was && MD.mode === 'watch') hide();
}
function sendPad() {
  if (MD.mode !== 'watch') return;
  let bits = MD.pad;
  const gp = navigator.getGamepads ? [...navigator.getGamepads()].find(g => g) : null;
  if (gp) {
    const on = i => gp.buttons[i] && gp.buttons[i].pressed;
    const ax = gp.axes[0] || 0, ay = gp.axes[1] || 0;
    if (on(12) || ay < -0.5) bits |= 1; if (on(13) || ay > 0.5) bits |= 2; if (on(14) || ax < -0.5) bits |= 4; if (on(15) || ax > 0.5) bits |= 8;
    if (on(9)) bits |= 128;
    const map = padOf(MD.watchSys).gp;
    for (const i in map) if (on(+i)) bits |= 1 << map[i];
  }
  if (bits !== MD.padSent || performance.now() - MD.padAt > 250) {
    MD.padSent = bits; MD.padAt = performance.now();
    emit({ ev: 'pad', bits });
  }
}
setInterval(sendPad, 16);
function padKey(e, down) {
  if (MD.mode !== 'watch') return;
  const k = e.key.toLowerCase();
  const b = k in MD_DIR_KEYS ? MD_DIR_KEYS[k] : padOf(MD.watchSys).keys[k];
  if (b === undefined) return;
  if (down) MD.pad |= 1 << b; else MD.pad &= ~(1 << b);
  e.preventDefault(); e.stopPropagation();
}
addEventListener('keydown', e => padKey(e, true), true);
addEventListener('keyup', e => padKey(e, false), true);
function padButton(b) {
  const bit = 1 << (+b.dataset.b);
  const on = e => { MD.pad |= bit; b.style.background = 'rgba(224,71,63,0.55)'; try { b.setPointerCapture(e.pointerId); } catch (_) {} e.preventDefault(); };
  const off = e => { MD.pad &= ~bit; b.style.background = ''; e.preventDefault(); };
  b.addEventListener('pointerdown', on); b.addEventListener('pointerup', off); b.addEventListener('pointercancel', off);
  b.addEventListener('contextmenu', e => e.preventDefault());
}
function layoutPad(sys) {
  const pad = MD.box && MD.box.pad; if (!pad) return;
  pad.textContent = '';
  const base = 'position:absolute;pointer-events:auto;padding:0;touch-action:none;user-select:none;-webkit-user-select:none;'
    + 'background:rgba(20,22,30,0.55);color:#fff;border:2px solid rgba(255,255,255,0.35);font:700 14px ui-sans-serif,system-ui,sans-serif;';
  const add = (bit, label, css) => { const b = document.createElement('button'); b.dataset.b = bit; b.textContent = label; b.style.cssText = base + css; pad.appendChild(b); padButton(b); };
  add(0, '▲', 'left:62px;bottom:118px;width:48px;height:48px;border-radius:10px');
  add(1, '▼', 'left:62px;bottom:14px;width:48px;height:48px;border-radius:10px');
  add(2, '◀', 'left:10px;bottom:66px;width:48px;height:48px;border-radius:10px');
  add(3, '▶', 'left:114px;bottom:66px;width:48px;height:48px;border-radius:10px');
  add(7, 'START', 'left:50%;margin-left:4px;bottom:14px;width:64px;height:30px;border-radius:15px;font-size:12px');
  for (const [bit, label, col, row] of padOf(sys).touch) {
    if (col < 0) add(bit, label, 'left:50%;margin-left:-68px;bottom:14px;width:64px;height:30px;border-radius:15px;font-size:12px');
    else add(bit, label, 'right:' + (136 - col * 62) + 'px;bottom:' + (40 + col * 16 + row * 66) + 'px;width:54px;height:54px;border-radius:50%');
  }
}

// ---- later: a Google Drive games folder (decided with the owner: "Connect Google Drive" in this menu, signing
// in with Google, listing the games in a folder shared with your friend). Needs the owner's OAuth client ID.
// driveConnect(clientId) is the hook: it should sign in (Google Identity Services), list the folder's ROMs and
// emit {ev:'drive_list', games:[{driveId, name, size}]}; drivePlay(driveId) downloads one and plays it.
function driveConnect(clientId) {
  if (!clientId) { note('Google Drive needs the OAuth client ID from the owner first.'); return false; }
  note('Google Drive is not built yet.');
  return false;
}

window.SmashedMD = {
  setListener(cb) { MD.listener = cb; },
  list: loadList, pick, canFolder, del: id => del(+id), play: id => play(+id), stop: () => { stopGame(); hide(); },
  close, setPick: k => { setPick(k); sendList(); }, snap, isPlaying: () => !!MD.playing, mode: () => MD.mode || '',
  offer: () => JSON.stringify(offer()), streamTo, endStream, applyPad: b => applyPad((b | 0) & 4095),
  join, answerCall, watch, stopWatching, driveConnect, sys: MD_SYS
};
})();
"""
