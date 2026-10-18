// The Blocks card of sprite-maker.html: carve a block (voxel) character from the sheets already made
// (sprite-blocks.js), look at it in 3D (plain WebGL: drag to spin, walk and attack on the rig), paint it block by
// block (touch-friendly), optionally ask Gemini for clean front/side/back views to carve from, and put it in the
// game JSON's "voxel" field. Uses the page's own S, SHEETS, gemini(), el(), $(), save keys and pictures helpers.
(function () {
  'use strict';
  const SB = window.SpriteBlocks;
  const B = {
    model: null,          // { parts: {name: Map}, bones, meta }
    views: null,          // Gemini's clean views: { raw, frames: [front, side, back] }
    useViews: true,
    anim: 'walk', spin: true, yaw: 0.5, pitch: 0.18, dist: 0, t: 0,
    part: 'head', tool: 'add', axis: 'front', layer: 0, zoom: 0, colour: 0xd08060, mirror: true, edit3d: false,
    undo: [], redo: [], status: '',
  };
  window.BlocksUI = B;
  const NAMES = { head: 'Head', torso: 'Body', pelvis: 'Hips', arm_r: 'Right upper arm', forearm_r: 'Right forearm', hand_r: 'Right hand',
    arm_l: 'Left upper arm', forearm_l: 'Left forearm', hand_l: 'Left hand', thigh_r: 'Right thigh', shin_r: 'Right shin', foot_r: 'Right foot',
    thigh_l: 'Left thigh', shin_l: 'Left shin', foot_l: 'Left foot' };
  const hex = c => '#' + c.toString(16).padStart(6, '0');

  // ---------------------------------------------------------------- the card
  const css = `
  .bk-wrap { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 12px; margin-top: 10px; }
  .bk-view { position: relative; }
  .bk-view canvas { width: 100%; aspect-ratio: 1 / 1.15; display: block; border-radius: 8px; touch-action: none;
    background: radial-gradient(circle at 50% 40%, #3a3f52, #1a1c24); }
  .bk-seg { display: inline-flex; border: 1px solid var(--line); border-radius: 7px; overflow: hidden; }
  .bk-seg button { border: 0; border-radius: 0; padding: 9px 12px; min-height: 40px; }
  .bk-seg button.on { background: #5b2a63; }
  .bk-tools { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 8px 0; }
  .bk-tools button, .bk-tools select { min-height: 40px; }
  .bk-pal { display: flex; flex-wrap: wrap; gap: 4px; margin: 6px 0; }
  .bk-pal button { width: 30px; height: 30px; padding: 0; border-radius: 5px; border: 2px solid transparent; }
  .bk-pal button.on { border-color: #fff; }
  .bk-grid { overflow: auto; max-height: 62vh; border-radius: 8px; border: 1px solid var(--line);
    background: repeating-conic-gradient(#2a2d38 0 25%, #22242e 0 50%) 0 0 / 16px 16px; }
  .bk-grid canvas { display: block; image-rendering: pixelated; touch-action: none; }
  .bk-grid.pan canvas { touch-action: auto; }
  .bk-views { display: flex; gap: 6px; align-items: flex-end; flex-wrap: wrap; }
  .bk-views canvas { image-rendering: pixelated; background: repeating-conic-gradient(#2a2d38 0 25%, #22242e 0 50%) 0 0 / 12px 12px; border-radius: 4px; }
  .bk-cur { width: 40px; height: 40px; border-radius: 6px; border: 1px solid var(--line); padding: 0; }
  #bkColour { width: 44px; height: 40px; padding: 2px; }
  @media (max-width: 760px) { .bk-wrap { grid-template-columns: 1fr; } }`;
  document.head.append(el('style', null, css));

  const card = el('div', { class: 'card', id: 'blocks' });
  $('sheets').after(card);
  card.innerHTML = `
    <div class="sheet-head"><h2>Blocks (3D for the Godot game)</h2><span class="pill" id="bkPill">not made yet</span></div>
    <p class="hint" style="margin:6px 0 0">Carves a block character from the sheets above (standing front, side, back and the diagonals),
      coloured from their pixels, with the same parts and joints as Jared's, one block per sprite pixel. Paint it below, then
      <b>Download for the game</b> puts the blocks in the same file.</p>
    <div class="controls">
      <button class="primary" id="bkMake">Make blocks</button>
      <span class="hint" id="bkState"></span>
    </div>
    <details id="bkAsk" style="margin-top:8px">
      <summary>Cleaner views from Gemini (optional)</summary>
      <p class="hint">Sends the design and the standing turnaround and asks for straight front, side and back views with the arms and legs apart,
        which carve better. Then press Make blocks again.</p>
      <div class="controls">
        <button id="bkGem">Ask Gemini</button>
        <button id="bkCopy">Copy prompt</button>
        <button id="bkOwn">Use my own picture</button><input type="file" id="bkOwnFile" accept="image/*" hidden>
        <label style="margin:0"><input type="checkbox" id="bkUse" checked> Carve from these views</label>
        <button id="bkClearViews">Clear</button>
      </div>
      <div class="bk-views" id="bkViews"></div>
      <div class="err" id="bkErr"></div>
    </details>
    <div class="bk-wrap">
      <div class="bk-view">
        <canvas id="bkGl" aria-label="3D preview: drag to spin"></canvas>
        <div class="bk-tools">
          <span class="bk-seg" id="bkAnim"><button data-a="stand">Stand</button><button data-a="walk">Walk</button><button data-a="attack">Attack</button></span>
          <label style="margin:0"><input type="checkbox" id="bkSpin" checked> Spin</label>
          <label style="margin:0"><input type="checkbox" id="bk3d"> Tap to paint</label>
        </div>
        <p class="hint" style="margin:0">Drag to turn it, pinch or scroll to zoom. "Tap to paint" stands it still and uses the tool on the block you tap.</p>
      </div>
      <div>
        <div class="bk-tools">
          <select id="bkPart" aria-label="part"></select>
          <span class="bk-seg" id="bkAxis"><button data-v="front">Front</button><button data-v="side">Side</button><button data-v="top">Top</button></span>
        </div>
        <div class="bk-tools">
          <span class="bk-seg" id="bkTool"><button data-t="add">Add</button><button data-t="paint">Paint</button><button data-t="remove">Remove</button><button data-t="pick">Pick</button><button data-t="pan">Pan</button></span>
        </div>
        <div class="bk-tools">
          <label style="margin:0;flex:1 1 160px">Layer <span id="bkLayerN"></span><input type="range" id="bkLayer" min="0" max="1" value="0" style="width:100%"></label>
          <button id="bkZoomOut" aria-label="zoom out">−</button><button id="bkZoomIn" aria-label="zoom in">+</button>
        </div>
        <div class="bk-grid" id="bkGridWrap"><canvas id="bkGrid"></canvas></div>
        <p class="hint" style="margin:4px 0 0">Add puts blocks on this layer (the bright ones); Paint, Remove and Pick work on the block you see there.
          Step the layer in to get at blocks inside.</p>
        <div class="bk-tools">
          <span class="bk-cur" id="bkCur"></span><input type="color" id="bkColour" aria-label="any colour">
          <label style="margin:0"><input type="checkbox" id="bkMirror" checked> Mirror left/right</label>
          <button id="bkUndo">Undo</button><button id="bkRedo">Redo</button>
        </div>
        <div class="bk-pal" id="bkPal"></div>
      </div>
    </div>`;

  // ---------------------------------------------------------------- frames to carve from
  function frameOf(sheetId, i) { const s = S.sheets[sheetId]; return s && s.frames && s.frames[i] || null; }
  function carveViews() {
    const st = id => frameOf('standing', id);
    const run = (id, i) => frameOf(id, i || 0);
    const v = {
      front: st(0) || run('front_run'), diag: st(1) || run('diag_run'), side: st(2) || run('side_run'),
      bdiag: st(3) || run('bdiag_run'), back: st(4) || run('back_run'),
    };
    if (B.views && B.views.frames && B.useViews) {
      const [f, s, b] = B.views.frames;
      if (f) v.front = f; if (s) v.side = s; if (b) v.back = b;
    }
    return v;
  }

  // ---------------------------------------------------------------- make / keep
  function setState(t) { $('bkState').textContent = t; }
  function pill() {
    const p = $('bkPill');
    if (!B.model) { p.className = 'pill'; p.textContent = 'not made yet'; return; }
    let n = 0; for (const m of Object.values(B.model.parts)) n += m.size;
    p.className = 'pill ok'; p.textContent = n.toLocaleString() + ' blocks';
  }
  async function make() {
    const v = carveViews();
    if (!v.front) { setState('Make the "Standing still" sheet first (or open a character .json).'); return; }
    setState('carving...');
    await new Promise(r => setTimeout(r, 20));
    try {
      B.model = SB.carve(v);
      B.undo = []; B.redo = [];
      rebuildAll(); fitLayer(); palette(); drawGrid(); pill(); keep();
      const m = B.model.meta;
      setState('Done: ' + m.height + ' blocks tall' + (m.mirrored.length ? ' (' + m.mirrored.filter(p => /^(thigh|arm)/.test(p)).map(p => NAMES[p].toLowerCase().replace(/ (upper )?(arm|thigh)$/, ' ' + (p.startsWith('arm') ? 'arm' : 'leg'))).join(', ') + ' copied from the other side)' : '') + '.');
    } catch (e) { setState(String(e.message || e)); }
  }
  const dbKey = () => 'blocks:' + charKey();
  function serial() {
    if (!B.model) return null;
    const parts = {};
    for (const [p, m] of Object.entries(B.model.parts)) { const a = new Int32Array(m.size * 2); let i = 0; for (const [k, c] of m) { a[i++] = k; a[i++] = c; } parts[p] = a; }
    return { parts, bones: B.model.bones, meta: B.model.meta };
  }
  let keepT = 0;
  function keep() {
    clearTimeout(keepT);
    keepT = setTimeout(() => DB.set(dbKey(), { model: serial(), views: B.views ? { raw: B.views.raw } : null, useViews: B.useViews }), 400);
  }
  function unserial(o) {
    const parts = {};
    for (const p of SB.PARTS) { const m = new Map(), a = o.parts[p] || []; for (let i = 0; i < a.length; i += 2) m.set(a[i], a[i + 1]); parts[p] = m; }
    return { parts, bones: o.bones, meta: o.meta };
  }
  B.load = async function () {
    const v = await DB.get(dbKey());
    B.model = v && v.model ? unserial(v.model) : null;
    B.views = v && v.views && v.views.raw ? { raw: v.views.raw, frames: null } : null;
    B.useViews = !v || v.useViews !== false;
    $('bkUse').checked = B.useViews;
    B.undo = []; B.redo = [];
    if (B.views) await cutViews();
    showViews();
    rebuildAll(); fitLayer(); palette(); drawGrid(); pill(); setState('');
  };
  // from a game JSON's "voxel" field (opening a downloaded character)
  B.fromGame = function (vx) {
    if (!vx || !vx.rig || !vx.files) return;
    const files = {};
    for (const [n, b] of Object.entries(vx.files)) files[n] = Uint8Array.from(atob(b), ch => ch.charCodeAt(0));
    B.model = SB.fromGame(vx.rig, files);
    B.model.meta.height = B.model.meta.height || 0; B.model.meta.mirrored = [];
    B.undo = []; B.redo = [];
    rebuildAll(); fitLayer(); palette(); drawGrid(); pill(); keep();
  };
  // the game JSON's "voxel" field: rig.json and the .vox files (base64), as godot/assets/voxel/<id>/ wants them
  B.exportField = function (id) {
    if (!B.model) return null;
    const g = SB.gameFiles(B.model, id);
    const files = {};
    for (const [n, bytes] of Object.entries(g.files)) { let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000)); files[n] = btoa(s); }
    return { format: 'smashed-blocks-1', rig: g.rig, files };
  };

  // ---------------------------------------------------------------- Gemini's clean views
  function viewsPrompt() {
    const name = $('charName').value.trim() || 'the character';
    const desc = $('charDesc').value.trim();
    return [
      'Make a pixel art character turnaround for building a 3D block model.',
      'IMAGE 1 is the character design for ' + name + '. Copy ' + name + ' exactly: face, hair, outfit, colours and build.' + (desc ? ' ' + desc : ''),
      S.sheets.standing && S.sheets.standing.raw ? 'IMAGE 2 is ' + name + ' already drawn in the game\'s pixel art style, standing, turning through five directions. Match its style, size and colours exactly.' : '',
      'Exactly three full-body figures in one row, left to right, evenly spaced, with a clear gap of plain green between them: 1 FRONT VIEW facing the camera; 2 SIDE PROFILE facing RIGHT (we see only the right side: one eye, the nose pointing right); 3 BACK VIEW from straight behind (no face).',
      'All three the same height and size, feet on the same line, standing straight and still, like an orthographic model sheet with no perspective, the camera level with the chest. Arms hanging straight down, held a little away from the body so there is a gap of background between each arm and the body in the front and back views. Legs straight and slightly apart, with a gap between them. Hands empty. Every figure shows the whole body from the top of the head to the soles.',
      'Plain solid bright green background (#00FF00) only: no floor, no shadow, no text, no labels, no borders. Crisp pixel art with hard edges, no blur.',
    ].filter(Boolean).join('\n\n');
  }
  async function askGemini() {
    $('bkErr').textContent = '';
    if (!S.design) { $('bkErr').textContent = 'Add the design picture first.'; return; }
    if (!apiKey()) { $('setup').open = true; $('apiKey').focus(); $('bkErr').textContent = 'No Gemini key: use Copy prompt and the Gemini app, then Use my own picture.'; return; }
    $('bkGem').disabled = true; $('bkGem').textContent = 'drawing... (about a minute)';
    try {
      const imgs = [await shrinkForSend(S.design)];
      if (S.sheets.standing && S.sheets.standing.raw) imgs.push(await shrinkForSend(S.sheets.standing.raw));
      const res = await gemini({ model: $('imgModel').value.trim(), text: viewsPrompt(), images: imgs, image: true, aspect: '16:9' });
      if (!res.img) throw new Error('Gemini sent back no picture' + (res.why ? ' (' + res.why + ')' : '') + (res.text ? ':\n' + res.text.slice(0, 400) : '.'));
      B.views = { raw: res.img, frames: null };
      await cutViews(); showViews(); keep();
    } catch (e) { $('bkErr').textContent = String(e.message || e); }
    finally { $('bkGem').disabled = false; $('bkGem').textContent = 'Ask Gemini'; }
  }
  async function cutViews() {
    const im = await loadImg(B.views.raw);
    const c = document.createElement('canvas'); c.width = im.naturalWidth; c.height = im.naturalHeight;
    const g = c.getContext('2d'); g.drawImage(im, 0, 0);
    const r = SpriteCut.cutSheet(g.getImageData(0, 0, c.width, c.height), { frames: 3, sizeBy: 'median', ground: 'each', size: 1, mirror: false });
    B.views.frames = r.frames;
    B.views.note = r.frames.length !== 3 ? 'got ' + r.frames.length + ' of 3 views' : (r.note || '');
  }
  function showViews() {
    const box = $('bkViews'); box.replaceChildren();
    if (!B.views) return;
    box.append(el('img', { class: 'thumb', src: B.views.raw, alt: 'Gemini\'s views', onclick: () => zoom(B.views.raw) }));
    for (const f of B.views.frames || []) { const c = frameToCanvas(f); c.style.height = '160px'; box.append(c); }
    if (B.views.note) box.append(el('span', { class: 'note' }, B.views.note));
  }

  // ---------------------------------------------------------------- WebGL preview
  const gl = $('bkGl').getContext('webgl', { antialias: true, preserveDrawingBuffer: true });
  const M = {
    id() { const m = new Float32Array(16); m[0] = m[5] = m[10] = m[15] = 1; return m; },
    mul(a, b) { const o = new Float32Array(16); for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k]; o[c * 4 + r] = s; } return o; },
    tr(x, y, z) { const m = M.id(); m[12] = x; m[13] = y; m[14] = z; return m; },
    rx(a) { const m = M.id(), c = Math.cos(a), s = Math.sin(a); m[5] = c; m[6] = s; m[9] = -s; m[10] = c; return m; },
    ry(a) { const m = M.id(), c = Math.cos(a), s = Math.sin(a); m[0] = c; m[2] = -s; m[8] = s; m[10] = c; return m; },
    rz(a) { const m = M.id(), c = Math.cos(a), s = Math.sin(a); m[0] = c; m[1] = s; m[4] = -s; m[5] = c; return m; },
    euler(e) { return e ? M.mul(M.ry(e[1]), M.mul(M.rx(e[0]), M.rz(e[2]))) : M.id(); },     // Godot's YXZ
    persp(fy, asp, n, f) { const m = new Float32Array(16), t = 1 / Math.tan(fy / 2); m[0] = t / asp; m[5] = t; m[10] = (f + n) / (n - f); m[11] = -1; m[14] = 2 * f * n / (n - f); return m; },
    inv(m) {
      const a = m, o = new Float32Array(16);
      const b00 = a[0] * a[5] - a[1] * a[4], b01 = a[0] * a[6] - a[2] * a[4], b02 = a[0] * a[7] - a[3] * a[4], b03 = a[1] * a[6] - a[2] * a[5];
      const b04 = a[1] * a[7] - a[3] * a[5], b05 = a[2] * a[7] - a[3] * a[6], b06 = a[8] * a[13] - a[9] * a[12], b07 = a[8] * a[14] - a[10] * a[12];
      const b08 = a[8] * a[15] - a[11] * a[12], b09 = a[9] * a[14] - a[10] * a[13], b10 = a[9] * a[15] - a[11] * a[13], b11 = a[10] * a[15] - a[11] * a[14];
      const d = 1 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06);
      o[0] = (a[5] * b11 - a[6] * b10 + a[7] * b09) * d; o[1] = (a[2] * b10 - a[1] * b11 - a[3] * b09) * d;
      o[2] = (a[13] * b05 - a[14] * b04 + a[15] * b03) * d; o[3] = (a[10] * b04 - a[9] * b05 - a[11] * b03) * d;
      o[4] = (a[6] * b08 - a[4] * b11 - a[7] * b07) * d; o[5] = (a[0] * b11 - a[2] * b08 + a[3] * b07) * d;
      o[6] = (a[14] * b02 - a[12] * b05 - a[15] * b01) * d; o[7] = (a[8] * b05 - a[10] * b02 + a[11] * b01) * d;
      o[8] = (a[4] * b10 - a[5] * b08 + a[7] * b06) * d; o[9] = (a[1] * b08 - a[0] * b10 - a[3] * b06) * d;
      o[10] = (a[12] * b04 - a[13] * b02 + a[15] * b00) * d; o[11] = (a[9] * b02 - a[8] * b04 - a[11] * b00) * d;
      o[12] = (a[5] * b07 - a[4] * b09 - a[6] * b06) * d; o[13] = (a[0] * b09 - a[1] * b07 + a[2] * b06) * d;
      o[14] = (a[13] * b01 - a[12] * b03 - a[14] * b00) * d; o[15] = (a[8] * b03 - a[9] * b01 + a[10] * b00) * d;
      return o;
    },
    apply(m, v) { const o = [0, 0, 0, 0]; for (let r = 0; r < 4; r++) o[r] = m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * v[3]; return o; },
  };
  let prog = null, loc = {};
  const meshes = {};       // part -> { buf, ibuf, n, idx32 }
  let u32 = false;
  if (gl) {
    u32 = !!gl.getExtension('OES_element_index_uint');
    const sh = (t, src) => { const s = gl.createShader(t); gl.shaderSource(s, src); gl.compileShader(s); return s; };
    prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER, `
      attribute vec3 aP; attribute vec3 aN; attribute vec3 aC;
      uniform mat4 uVP; uniform mat4 uM; varying vec3 vC; varying vec3 vN;
      void main() { vC = aC; vN = mat3(uM) * aN; gl_Position = uVP * uM * vec4(aP, 1.0); }`));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, `
      precision mediump float; varying vec3 vC; varying vec3 vN; uniform vec3 uL; uniform float uDim;
      void main() { vec3 n = normalize(vN); float d = max(dot(n, uL), 0.0);
        float l = 0.62 + 0.38 * d + 0.06 * n.y; gl_FragColor = vec4(vC * l * uDim, 1.0); }`));
    gl.linkProgram(prog);
    for (const a of ['aP', 'aN', 'aC']) loc[a] = gl.getAttribLocation(prog, a);
    for (const u of ['uVP', 'uM', 'uL', 'uDim']) loc[u] = gl.getUniformLocation(prog, u);
  }
  function rebuildPart(p) {
    if (!gl) return;
    const old = meshes[p];
    if (old) { gl.deleteBuffer(old.buf); gl.deleteBuffer(old.ibuf); delete meshes[p]; }
    const v = B.model && B.model.parts[p];
    if (!v || !v.size) return;
    const m = SB.mesh(v);
    const nv = m.pos.length / 3;
    const data = new Float32Array(nv * 9);
    for (let i = 0; i < nv; i++) for (let j = 0; j < 3; j++) { data[i * 9 + j] = m.pos[i * 3 + j]; data[i * 9 + 3 + j] = m.nrm[i * 3 + j]; data[i * 9 + 6 + j] = m.col[i * 3 + j]; }
    const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    const big = nv > 65535;
    const ibuf = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibuf);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, big && u32 ? new Uint32Array(m.idx) : new Uint16Array(m.idx), gl.STATIC_DRAW);
    meshes[p] = { buf, ibuf, n: m.idx.length, big: big && u32, tris: m.idx.length / 3 };
  }
  let occ = new Map();          // every block: key -> part (for tap picking)
  function rebuildAll() {
    for (const p of SB.PARTS) rebuildPart(p);
    occ = new Map();
    if (B.model) for (const [p, m] of Object.entries(B.model.parts)) for (const k of m.keys()) occ.set(k, p);
    fillPartSelect();
  }
  // the bones' world matrices for a pose (voxels)
  function skins(ps) {
    const W = {}, out = {}, piv = {};
    for (const b of B.model.bones) piv[b.name] = b.pivot;
    for (const b of B.model.bones) {
      const p = piv[b.name], par = b.parent;
      let local;
      if (!par) local = M.mul(M.tr(ps.pos[0] + p[0], ps.pos[1] + p[1], ps.pos[2] + p[2]), M.euler(ps.rot[b.name]));
      else { const q = piv[par]; local = M.mul(M.tr(p[0] - q[0], p[1] - q[1], p[2] - q[2]), M.euler(ps.rot[b.name])); }
      W[b.name] = par ? M.mul(W[par], local) : local;
      out[b.name] = M.mul(W[b.name], M.tr(-p[0], -p[1], -p[2]));
    }
    return out;
  }
  function camera() {
    const c = $('bkGl');
    const H = (B.model && B.model.meta.height) || 150;
    const dist = (B.dist || 1.8) * H;
    const proj = M.persp(0.62, c.width / c.height, 1, dist * 4);
    const view = M.mul(M.tr(0, 0, -dist), M.mul(M.rx(B.pitch), M.ry(-B.yaw)));
    const vp = M.mul(proj, M.mul(view, M.tr(0, -H * 0.52, 0)));
    return { vp, H };
  }
  let lastT = 0;
  function frameLoop(now) {
    requestAnimationFrame(frameLoop);
    const dt = Math.min(0.1, (now - (lastT || now)) / 1000); lastT = now;
    const c = $('bkGl');
    if (!gl || !c.offsetWidth) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.round(c.clientWidth * dpr), h = Math.round(c.clientHeight * dpr);
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    if (!B.frozen) {
      B.t += dt;
      if (B.spin && !B.edit3d && !drag) B.yaw += dt * 0.6;
    }
    draw();
  }
  function draw() {
    const c = $('bkGl');
    gl.viewport(0, 0, c.width, c.height);
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    if (!B.model) return;
    gl.enable(gl.DEPTH_TEST); gl.enable(gl.CULL_FACE);
    gl.useProgram(prog);
    const { vp } = camera();
    gl.uniformMatrix4fv(loc.uVP, false, vp);
    const L = [-0.45, 0.75, 0.5], l = Math.hypot(...L);
    gl.uniform3f(loc.uL, L[0] / l, L[1] / l, L[2] / l);
    const st = B.edit3d ? { t: 0 } : B.anim === 'walk' ? { t: B.t, moving: true, speed: 120, odo: B.t * 120 }
      : B.anim === 'attack' ? { t: B.t, weapon: 'fists', act: 'punch', act_f: (B.t * 1.6) % 1.4 } : { t: B.t };
    const ps = B.edit3d ? { rot: {}, pos: [0, 0, 0] } : SB.pose(st);
    const sk = skins(ps);
    for (const p of SB.PARTS) {
      const m = meshes[p]; if (!m) continue;
      gl.uniformMatrix4fv(loc.uM, false, sk[SB.BONE_OF(p)]);
      gl.uniform1f(loc.uDim, B.edit3d && p !== B.part && SB.MIRROR(B.part) !== p ? 0.55 : 1);
      gl.bindBuffer(gl.ARRAY_BUFFER, m.buf);
      gl.enableVertexAttribArray(loc.aP); gl.vertexAttribPointer(loc.aP, 3, gl.FLOAT, false, 36, 0);
      gl.enableVertexAttribArray(loc.aN); gl.vertexAttribPointer(loc.aN, 3, gl.FLOAT, false, 36, 12);
      gl.enableVertexAttribArray(loc.aC); gl.vertexAttribPointer(loc.aC, 3, gl.FLOAT, false, 36, 24);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.ibuf);
      gl.drawElements(gl.TRIANGLES, m.n, m.big ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT, 0);
    }
  }
  // for tests: a still frame at a given angle and moment
  B.shot = function (yaw, pitch, anim, t) { B.yaw = yaw; B.pitch = pitch == null ? B.pitch : pitch; if (anim) setAnim(anim); if (t != null) B.t = t; B.frozen = true; draw(); };

  // drag to spin, pinch / wheel to zoom, tap to paint
  let drag = null; const ptrs = new Map();
  const glc = $('bkGl');
  glc.addEventListener('pointerdown', e => {
    glc.setPointerCapture(e.pointerId);
    ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (ptrs.size === 1) drag = { x: e.clientX, y: e.clientY, x0: e.clientX, y0: e.clientY, moved: false };
    else drag = { pinch: pinchDist(), dist: B.dist || 1.8, moved: true };
  });
  glc.addEventListener('pointermove', e => {
    if (!ptrs.has(e.pointerId)) return;
    ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (!drag) return;
    if (drag.pinch) { B.dist = Math.max(0.8, Math.min(5, drag.dist * drag.pinch / Math.max(1, pinchDist()))); return; }
    if (Math.abs(e.clientX - drag.x0) + Math.abs(e.clientY - drag.y0) > 6) drag.moved = true;
    if (!drag.moved) return;
    B.yaw -= (e.clientX - drag.x) * 0.012;
    B.pitch = Math.max(-0.6, Math.min(1.3, B.pitch + (e.clientY - drag.y) * 0.01));
    drag.x = e.clientX; drag.y = e.clientY;
  });
  const up = e => {
    ptrs.delete(e.pointerId);
    if (drag && !drag.moved && !drag.pinch && B.edit3d && e.type === 'pointerup') tap3d(e);
    if (!ptrs.size) drag = null;
  };
  glc.addEventListener('pointerup', up); glc.addEventListener('pointercancel', up);
  glc.addEventListener('wheel', e => { e.preventDefault(); B.dist = Math.max(0.8, Math.min(5, (B.dist || 1.8) * (e.deltaY > 0 ? 1.1 : 0.9))); }, { passive: false });
  function pinchDist() { const p = [...ptrs.values()]; return p.length < 2 ? 1 : Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]); }

  // a ray from the tap through the still model, block by block (Amanatides and Woo)
  function tap3d(e) {
    if (!B.model) return;
    const r = glc.getBoundingClientRect();
    const nx = (e.clientX - r.left) / r.width * 2 - 1, ny = 1 - (e.clientY - r.top) / r.height * 2;
    const inv = M.inv(camera().vp);
    const a = M.apply(inv, [nx, ny, -1, 1]), b = M.apply(inv, [nx, ny, 1, 1]);
    const o = [a[0] / a[3], a[1] / a[3], a[2] / a[3]], f = [b[0] / b[3], b[1] / b[3], b[2] / b[3]];
    const d = [f[0] - o[0], f[1] - o[1], f[2] - o[2]], len = Math.hypot(...d);
    for (let i = 0; i < 3; i++) d[i] /= len;
    const cell = o.map(Math.floor), step = d.map(Math.sign), tMax = [], tD = [];
    for (let i = 0; i < 3; i++) { tD[i] = d[i] ? Math.abs(1 / d[i]) : 1e9; tMax[i] = d[i] ? ((d[i] > 0 ? cell[i] + 1 - o[i] : o[i] - cell[i]) * tD[i]) : 1e9; }
    let prev = null;
    for (let n = 0; n < 4000; n++) {
      const k = SB.key(cell[0], cell[1], cell[2]);
      if (Math.abs(cell[0]) < 500 && cell[1] > -500 && cell[1] < 500 && Math.abs(cell[2]) < 500 && occ.has(k)) {
        const part = occ.get(k);
        if (B.tool === 'add') { if (prev) { begin(); edit(part, prev, B.colour); end(); } }
        else if (B.tool === 'pick') pickColour(B.model.parts[part].get(k));
        else { begin(); edit(part, cell.slice(), B.tool === 'remove' ? undefined : B.colour); end(); }
        if (B.part !== part) { B.part = part; $('bkPart').value = part; fitLayer(); }
        drawGrid();
        return;
      }
      prev = cell.slice();
      const i = tMax[0] < tMax[1] ? (tMax[0] < tMax[2] ? 0 : 2) : (tMax[1] < tMax[2] ? 1 : 2);
      cell[i] += step[i]; tMax[i] += tD[i];
    }
  }

  // ---------------------------------------------------------------- editing (with mirror and undo)
  let stroke = null;
  function begin() { stroke = []; }
  function end() { if (stroke && stroke.length) { B.undo.push(stroke); if (B.undo.length > 200) B.undo.shift(); B.redo = []; } stroke = null; flush(); }
  const dirty = new Set();
  function setVox(part, k, c) {
    const m = B.model.parts[part];
    const before = m.get(k);
    if (before === c) return;
    if (c === undefined) { m.delete(k); occ.delete(k); } else { m.set(k, c); occ.set(k, part); }
    if (stroke) stroke.push([part, k, before, c]);
    dirty.add(part);
  }
  function edit(part, p, c) {
    const k = SB.key(p[0], p[1], p[2]);
    const owner = occ.get(k);
    if (owner) part = owner;                       // a block already there belongs to its own part
    if (B.tool === 'paint' && !owner) return;
    if (B.tool === 'add' && owner) return;
    setVox(part, k, c);
    if (B.mirror) {
      const mk = SB.key(-p[0] - 1, p[1], p[2]), mp = SB.MIRROR(part), mo = occ.get(mk);
      if (B.tool === 'paint' && !mo) return;
      if (B.tool === 'add' && mo) return;
      if (mk !== k) setVox(mo || mp, mk, c);
    }
  }
  function flush() { for (const p of dirty) rebuildPart(p); dirty.clear(); pill(); keep(); }
  function undoRedo(from, to, undo) {
    const s = from.pop(); if (!s) return;
    const list = undo ? s.slice().reverse() : s;
    for (const [p, k, before, after] of list) {
      const v = undo ? before : after, m = B.model.parts[p];
      if (v === undefined) { m.delete(k); occ.delete(k); } else { m.set(k, v); occ.set(k, p); }
      dirty.add(p);
    }
    to.push(s); flush(); drawGrid();
  }

  // ---------------------------------------------------------------- the block painter (one layer of a part)
  // Front: x across, y up, layer = z (front to back). Side: z across (forward to the right), y up, layer = x.
  // Top: x across, z down the screen (forward at the bottom), layer = y.
  function bbox(part) {
    const m = B.model && B.model.parts[part];
    let b = null;
    if (m) for (const k of m.keys()) {
      const x = SB.kx(k), y = SB.ky(k), z = SB.kz(k);
      if (!b) b = [x, y, z, x, y, z];
      else { b[0] = Math.min(b[0], x); b[1] = Math.min(b[1], y); b[2] = Math.min(b[2], z); b[3] = Math.max(b[3], x); b[4] = Math.max(b[4], y); b[5] = Math.max(b[5], z); }
    }
    if (!b) { const piv = B.model ? (B.model.bones.find(q => q.name === SB.BONE_OF(part)) || { pivot: [0, 80, 0] }).pivot : [0, 80, 0]; b = [piv[0] - 5, piv[1] - 5, piv[2] - 5, piv[0] + 5, piv[1] + 5, piv[2] + 5].map(Math.round); }
    const pad = 3;
    return [b[0] - pad, b[1] - pad, b[2] - pad, b[3] + pad, b[4] + pad, b[5] + pad];
  }
  // grid cell (u, v) on screen and the layer -> model point
  function axes() {
    const b = bbox(B.part);
    if (B.axis === 'front') return { b, nu: b[3] - b[0] + 1, nv: b[4] - b[1] + 1, l0: b[2], l1: b[5], pt: (u, v, l) => [b[0] + u, b[4] - v, l] };
    if (B.axis === 'side') return { b, nu: b[5] - b[2] + 1, nv: b[4] - b[1] + 1, l0: b[0], l1: b[3], pt: (u, v, l) => [l, b[4] - v, b[2] + u] };
    return { b, nu: b[3] - b[0] + 1, nv: b[5] - b[2] + 1, l0: b[1], l1: b[4], pt: (u, v, l) => [b[0] + u, l, b[2] + v] };
  }
  function fitLayer() {
    if (!B.model) return;
    const a = axes();
    const L = $('bkLayer');
    L.min = a.l0; L.max = a.l1;
    // start on the layer nearest the viewer that has the part's blocks: the painter shows the outside from there
    const m = B.model.parts[B.part];
    let best = null;
    for (const k of m.keys()) {
      const l = B.axis === 'front' ? SB.kz(k) : B.axis === 'side' ? SB.kx(k) : SB.ky(k);
      if (best === null || (B.axis === 'side' ? l < best : l > best)) best = l;
    }
    if (best === null) best = Math.round((a.l0 + a.l1) / 2);
    B.layer = best; L.value = best;
    const wrap = $('bkGridWrap');
    B.zoom = Math.max(4, Math.min(28, Math.floor((wrap.clientWidth || 320) / a.nu)));
  }
  function drawGrid() {
    const c = $('bkGrid');
    if (!B.model) { c.width = c.height = 1; return; }
    const a = axes(), z = B.zoom;
    $('bkLayerN').textContent = B.layer + ' (' + (B.axis === 'front' ? 'front to back' : B.axis === 'side' ? 'right to left' : 'bottom to top') + ')';
    c.width = a.nu * z; c.height = a.nv * z;
    const g = c.getContext('2d');
    g.clearRect(0, 0, c.width, c.height);
    const m = B.model.parts[B.part];
    for (let v = 0; v < a.nv; v++) for (let u = 0; u < a.nu; u++) {
      const p = a.pt(u, v, B.layer);
      const k = SB.key(p[0], p[1], p[2]);
      const own = m.get(k);
      if (own !== undefined) { g.fillStyle = hex(own); g.fillRect(u * z, v * z, z, z); continue; }
      const other = occ.get(k);
      if (other) { g.fillStyle = 'rgba(255,255,255,0.10)'; g.fillRect(u * z, v * z, z, z); continue; }
      // the part's block seen further in (what Paint, Remove and Pick work on), fainter the deeper it is
      const q = seen(a, u, v);
      if (q) { g.globalAlpha = Math.max(0.3, 0.8 - q.d * 0.06); g.fillStyle = hex(q.c); g.fillRect(u * z, v * z, z, z); g.globalAlpha = 1; }
    }
    if (z >= 8) {
      g.strokeStyle = 'rgba(255,255,255,0.08)'; g.lineWidth = 1; g.beginPath();
      for (let u = 0; u <= a.nu; u++) { g.moveTo(u * z + 0.5, 0); g.lineTo(u * z + 0.5, c.height); }
      for (let v = 0; v <= a.nv; v++) { g.moveTo(0, v * z + 0.5); g.lineTo(c.width, v * z + 0.5); }
      g.stroke();
    }
    // the mirror line (x = 0) on the front and top views
    if (B.axis !== 'side') { const u0 = -a.b[0]; g.strokeStyle = 'rgba(247,168,255,0.35)'; g.beginPath(); g.moveTo(u0 * z + 0.5, 0); g.lineTo(u0 * z + 0.5, c.height); g.stroke(); }
  }
  // the first of the part's blocks at or behind the layer, looking from the viewer's side
  function seen(a, u, v) {
    const m = B.model.parts[B.part];
    for (let d = 0; d <= 64; d++) {
      const l = B.layer + (B.axis === 'side' ? d : -d);
      if (l < a.l0 || l > a.l1) break;
      const p = a.pt(u, v, l), c = m.get(SB.key(p[0], p[1], p[2]));
      if (c !== undefined) return { p, c, d };
    }
    return null;
  }
  const gridC = $('bkGrid');
  let gdown = false;
  function gridAt(e) {
    const r = gridC.getBoundingClientRect(), a = axes();
    const u = Math.floor((e.clientX - r.left) / r.width * a.nu), v = Math.floor((e.clientY - r.top) / r.height * a.nv);
    if (u < 0 || v < 0 || u >= a.nu || v >= a.nv) return null;
    if (B.tool === 'add') return a.pt(u, v, B.layer);
    const q = seen(a, u, v);
    return q ? q.p : null;
  }
  function gridUse(e) {
    const p = gridAt(e); if (!p || !B.model) return;
    if (B.tool === 'pick') { const c = occ.has(SB.key(...p)) ? B.model.parts[occ.get(SB.key(...p))].get(SB.key(...p)) : undefined; if (c !== undefined) pickColour(c); return; }
    edit(B.part, p, B.tool === 'remove' ? undefined : B.colour);
    for (const q of dirty) rebuildPart(q); dirty.clear();
    drawGrid();
  }
  gridC.addEventListener('pointerdown', e => { if (B.tool === 'pan' || !B.model) return; e.preventDefault(); gridC.setPointerCapture(e.pointerId); gdown = true; begin(); gridUse(e); });
  gridC.addEventListener('pointermove', e => { if (gdown) gridUse(e); });
  const gup = () => { if (gdown) { gdown = false; end(); drawGrid(); } };
  gridC.addEventListener('pointerup', gup); gridC.addEventListener('pointercancel', gup);

  // ---------------------------------------------------------------- colours
  function pickColour(c) { B.colour = c; $('bkColour').value = hex(c); palette(); if (B.tool === 'pick') setTool('paint'); }
  let designCols = [];
  async function designPalette() {
    designCols = [];
    if (!S.design) return;
    try {
      const im = await loadImg(S.design), c = document.createElement('canvas'); c.width = c.height = 64;
      const g = c.getContext('2d'); g.drawImage(im, 0, 0, 64, 64);
      const d = g.getImageData(0, 0, 64, 64).data, n = {};
      for (let i = 0; i < d.length; i += 4) {
        if (d[i + 3] < 200) continue;
        const r = d[i], gg = d[i + 1], b = d[i + 2];
        if (gg > r + 50 && gg > b + 50 && gg > 150) continue;        // the green screen
        const k = ((r >> 4) << 8) | ((gg >> 4) << 4) | (b >> 4); n[k] = (n[k] || 0) + 1;
      }
      designCols = Object.entries(n).sort((a, b) => b[1] - a[1]).slice(0, 10).map(([k]) => { k = +k; return SB.pack(((k >> 8) & 15) * 17, ((k >> 4) & 15) * 17, (k & 15) * 17); });
    } catch (_) {}
  }
  function palette() {
    const box = $('bkPal'); box.replaceChildren();
    $('bkCur').style.background = hex(B.colour);
    const n = new Map();
    if (B.model) for (const m of Object.values(B.model.parts)) for (const c of m.values()) n.set(c, (n.get(c) || 0) + 1);
    // the model's colours, most used first, near-duplicates merged
    const cols = [];
    for (const [c] of [...n.entries()].sort((a, b) => b[1] - a[1])) {
      const [r, g, b] = SB.rgbOf(c);
      if (cols.some(q => { const [r2, g2, b2] = SB.rgbOf(q); return Math.abs(r - r2) + Math.abs(g - g2) + Math.abs(b - b2) < 30; })) continue;
      cols.push(c); if (cols.length >= 34) break;
    }
    for (const c of cols.concat(designCols)) {
      box.append(el('button', { class: c === B.colour ? 'on' : '', style: 'background:' + hex(c), title: hex(c), 'aria-label': 'colour ' + hex(c), onclick: () => { B.colour = c; $('bkColour').value = hex(c); palette(); if (B.tool === 'pick' || B.tool === 'remove' || B.tool === 'pan') setTool('paint'); } }));
    }
  }

  // ---------------------------------------------------------------- wiring
  function fillPartSelect() {
    const s = $('bkPart');
    if (s.options.length !== SB.PARTS.length) s.replaceChildren(...SB.PARTS.map(p => el('option', { value: p }, NAMES[p])));
    s.value = B.part;
  }
  function seg(id, attr, val) { for (const b of $(id).querySelectorAll('button')) b.classList.toggle('on', b.dataset[attr] === val); }
  function setAnim(a) { B.anim = a; seg('bkAnim', 'a', a); }
  function setTool(t) { B.tool = t; seg('bkTool', 't', t); $('bkGridWrap').classList.toggle('pan', t === 'pan'); }
  function setAxis(v) { B.axis = v; seg('bkAxis', 'v', v); fitLayer(); drawGrid(); }
  $('bkAnim').onclick = e => { if (e.target.dataset.a) setAnim(e.target.dataset.a); };
  $('bkTool').onclick = e => { if (e.target.dataset.t) setTool(e.target.dataset.t); };
  $('bkAxis').onclick = e => { if (e.target.dataset.v) setAxis(e.target.dataset.v); };
  $('bkPart').onchange = () => { B.part = $('bkPart').value; fitLayer(); drawGrid(); };
  $('bkLayer').oninput = () => { B.layer = +$('bkLayer').value; drawGrid(); };
  $('bkZoomIn').onclick = () => { B.zoom = Math.min(48, B.zoom + 2); drawGrid(); };
  $('bkZoomOut').onclick = () => { B.zoom = Math.max(3, B.zoom - 2); drawGrid(); };
  $('bkUndo').onclick = () => undoRedo(B.undo, B.redo, true);
  $('bkRedo').onclick = () => undoRedo(B.redo, B.undo, false);
  $('bkMirror').onchange = () => { B.mirror = $('bkMirror').checked; };
  $('bkSpin').onchange = () => { B.spin = $('bkSpin').checked; };
  $('bk3d').onchange = () => { B.edit3d = $('bk3d').checked; };
  $('bkColour').oninput = () => { B.colour = parseInt($('bkColour').value.slice(1), 16); palette(); if (B.tool === 'pick' || B.tool === 'remove' || B.tool === 'pan') setTool('paint'); };
  $('bkMake').onclick = make;
  $('bkGem').onclick = askGemini;
  $('bkCopy').onclick = async e => { await navigator.clipboard.writeText(viewsPrompt()).catch(() => {}); e.target.textContent = 'Copied'; setTimeout(() => e.target.textContent = 'Copy prompt', 1500); };
  $('bkOwn').onclick = () => $('bkOwnFile').click();
  $('bkOwnFile').onchange = async () => { const f = $('bkOwnFile').files[0]; if (!f) return; B.views = { raw: await fileToDataURL(f), frames: null }; await cutViews(); showViews(); keep(); };
  $('bkUse').onchange = () => { B.useViews = $('bkUse').checked; keep(); };
  $('bkClearViews').onclick = () => { B.views = null; showViews(); keep(); };
  document.addEventListener('keydown', e => {
    if (!(e.ctrlKey || e.metaKey) || e.key.toLowerCase() !== 'z' || /INPUT|TEXTAREA/.test(document.activeElement.tagName)) return;
    e.preventDefault(); if (e.shiftKey) $('bkRedo').click(); else $('bkUndo').click();
  });
  setAnim('walk'); setTool('add'); setAxis('front'); fillPartSelect();
  $('bkColour').value = hex(B.colour);
  if (!gl) $('bkGl').replaceWith(el('div', { class: 'err' }, 'This browser has no WebGL, so no 3D preview (the painter still works).'));
  else requestAnimationFrame(frameLoop);
  B.designPalette = () => designPalette().then(palette);
  if (DB.db) { B.load(); B.designPalette(); }
  B.make = make;
  B.setTool = setTool; B.setAxis = setAxis; B.setAnim = setAnim; B.drawGrid = drawGrid; B.fitLayer = fitLayer;
  B.selectPart = p => { B.part = p; $('bkPart').value = p; fitLayer(); drawGrid(); };
  B.meshes = meshes;
})();
