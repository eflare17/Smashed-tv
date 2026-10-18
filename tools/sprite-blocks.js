// Block (voxel) characters from a character's sprite frames, for sprite-maker.html's Blocks card.
// Makes the same thing the Godot port's builder (godot/assets/voxel/tools/vox_build.py) makes for Jared: one
// MagicaVoxel .vox per part (head, torso, pelvis, arm/forearm/hand _l/_r, thigh/shin/foot _l/_r) and a rig.json
// (the same 15 bones, their pivots, which part hangs on which bone and where each grid sits), one block per sprite
// pixel, so a 160 px sprite makes a model as tall as Jared's. godot/integration/voxel.md has the format.
//
// Works on plain { width, height, data } RGBA frames (like sprite-cut.js), so it runs in the browser and in node.
//
// Model axes (as the Godot port): x across (+x the character's left, the viewer's right when it faces you), y up
// (0 = the soles), z forward (toward the viewer of the front frame). A voxel (x, y, z) fills x..x+1 etc.
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- keys and colours
  const KO = 512;
  const key = (x, y, z) => (x + KO) | ((y + KO) << 10) | ((z + KO) << 20);
  const kx = k => (k & 1023) - KO;
  const ky = k => ((k >> 10) & 1023) - KO;
  const kz = k => ((k >> 20) & 1023) - KO;
  const rgbOf = c => [(c >> 16) & 255, (c >> 8) & 255, c & 255];
  const pack = (r, g, b) => ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
  const shade = (c, k) => { const [r, g, b] = rgbOf(c); const f = v => Math.max(0, Math.min(255, Math.round(v * k))); return pack(f(r), f(g), f(b)); };

  const BONES = ['hips', 'chest', 'head', 'arm_r', 'forearm_r', 'hand_r', 'arm_l', 'forearm_l', 'hand_l',
    'thigh_l', 'shin_l', 'foot_l', 'thigh_r', 'shin_r', 'foot_r'];
  const PARENT = { hips: '', chest: 'hips', head: 'chest', arm_r: 'chest', forearm_r: 'arm_r', hand_r: 'forearm_r',
    arm_l: 'chest', forearm_l: 'arm_l', hand_l: 'forearm_l', thigh_l: 'hips', shin_l: 'thigh_l', foot_l: 'shin_l',
    thigh_r: 'hips', shin_r: 'thigh_r', foot_r: 'shin_r' };
  // the parts, in Jared's rig.json order; each hangs on the bone of the same name (torso on chest, pelvis on hips)
  const PARTS = ['head', 'torso', 'pelvis', 'thigh_l', 'thigh_r', 'shin_l', 'shin_r', 'foot_l', 'foot_r',
    'arm_r', 'arm_l', 'forearm_r', 'forearm_l', 'hand_r', 'hand_l'];
  const BONE_OF = p => p === 'torso' ? 'chest' : p === 'pelvis' ? 'hips' : p;
  const MIRROR = p => p.endsWith('_l') ? p.slice(0, -2) + '_r' : p.endsWith('_r') ? p.slice(0, -2) + '_l' : p;

  // ---------------------------------------------------------------- frames
  function frame(img) {
    if (!img) return null;
    const w = img.width, h = img.height, d = img.data;
    const op = (c, r) => c >= 0 && r >= 0 && c < w && r < h && d[(r * w + c) * 4 + 3] > 128;
    const col = (c, r) => { const i = (r * w + c) * 4; return pack(d[i], d[i + 1], d[i + 2]); };
    let top = -1, foot = 0;
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) if (op(c, r)) { if (top < 0) top = r; foot = r + 1; break; }
    const runsCache = {};
    const runs = r => {
      if (runsCache[r]) return runsCache[r];
      const out = [];
      for (let c = 0, s = -1; c <= w; c++) {
        const on = c < w && op(c, r);
        if (on && s < 0) s = c;
        if (!on && s >= 0) { out.push([s, c - 1]); s = -1; }
      }
      return (runsCache[r] = out);
    };
    const extent = r => { const rs = runs(r); return rs.length ? [rs[0][0], rs[rs.length - 1][1]] : null; };
    return { w, h, op, col, top, foot, runs, extent, img };
  }
  function flipImg(img) {
    const w = img.width, h = img.height, s = img.data, d = new Uint8ClampedArray(s.length);
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
      const a = (r * w + c) * 4, b = (r * w + (w - 1 - c)) * 4;
      d[b] = s[a]; d[b + 1] = s[a + 1]; d[b + 2] = s[a + 2]; d[b + 3] = s[a + 3];
    }
    return { width: w, height: h, data: d };
  }
  // the run on row r holding column c, else the nearest one
  function runAt(f, r, c) {
    let best = null, bd = 1e9;
    for (const rn of f.runs(r)) {
      const dd = c < rn[0] ? rn[0] - c : c > rn[1] ? c - rn[1] : 0;
      if (dd < bd) { bd = dd; best = rn; }
    }
    return best;
  }
  const median = a => { const s = a.slice().sort((p, q) => p - q); return s.length ? s[s.length >> 1] : 0; };
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  // ---------------------------------------------------------------- carving
  // views: { front, side (facing right), back, diag (facing down-right), bdiag (facing up-right) }; front is needed.
  // Returns a model: { parts: {name: Map(key -> 0xRRGGBB)}, bones: [{name, parent, pivot}], meta }.
  function carve(views, opt) {
    opt = opt || {};
    const Fr = frame(views.front);
    if (!Fr || Fr.top < 0) throw new Error('No front picture to carve from.');
    const Sd = frame(views.side);
    const top = Fr.top, foot = Fr.foot, H = foot - top;
    const R = f => Math.round(top + f * H);
    const S = v => Math.max(1, Math.round(v * H / 150));     // Jared's sizes, scaled to this body

    // -- where the body is (front frame)
    const cs = [];
    for (let r = R(0.33); r <= R(0.6); r++) { const e = Fr.extent(r); if (e) cs.push((e[0] + e[1] + 1) / 2); }
    const cx0 = Math.round(median(cs));
    const cen = r => runAt(Fr, r, cx0);
    // the head: its width and middle near the top; the shoulders start where a row gets much wider than the head;
    // the chin hangs a little below that, between the shoulders (as Jared's builder cuts his head)
    const hws = [], hcs = [];
    for (let r = R(0.06); r <= R(0.18); r++) { const e = Fr.extent(r); if (e) { hws.push(e[1] + 1 - e[0]); hcs.push((e[0] + e[1] + 1) / 2); } }
    const headW = median(hws) || H * 0.24, headC = median(hcs) || cx0 + 0.5;
    let rs = R(0.27);
    for (let r = R(0.16); r <= R(0.32); r++) { const e = Fr.extent(r); if (e && e[1] + 1 - e[0] > 1.4 * headW) { rs = r; break; } }
    const headEnd = Math.min(rs + S(12), R(0.33));     // rows above it can be head
    const neck = rs + S(6);                             // the head's pivot
    const inHead = (c, r) => r < rs || (r < headEnd && Math.abs(c + 0.5 - headC) <= 0.42 * headW);
    // the crotch: the first row (below the middle) where the gap between the legs starts and stays
    let crotch = -1;
    for (let r = R(0.5); r < foot - S(16) && crotch < 0; r++) {
      let gap = true;
      for (let k = 0; k < 4 && gap; k++) if (Fr.op(cx0, r + k) || Fr.op(cx0 - 1, r + k)) gap = false;
      if (gap) crotch = r;
    }
    if (crotch < 0) crotch = R(0.66);
    const waist = Math.min(R(0.57), crotch - S(6));
    const skirt = crotch - waist > 0.15 * H;
    const hipRow = skirt ? waist + S(10) : crotch;

    // -- the arms: runs either side of the middle one, below the shoulders
    function findArm(side) {          // side -1: the frame's left (the character's right arm), +1: the frame's right
      const sep = {};
      for (let r = rs + S(8); r < Math.min(crotch + S(4), foot - S(14)); r++) {
        const rns = Fr.runs(r), mid = cen(r);
        if (!mid) continue;
        const i = rns.indexOf(mid);
        const out = side < 0 ? rns.slice(0, i) : rns.slice(i + 1);
        const wide = out.filter(rn => rn[1] - rn[0] >= 1);
        if (wide.length) sep[r] = side < 0 ? [wide[0][0], wide[wide.length - 1][1]] : [wide[0][0], wide[wide.length - 1][1]];
      }
      // the longest stretch of rows with a separate arm (gaps of two rows allowed)
      const rows = Object.keys(sep).map(Number).sort((a, b) => a - b);
      let best = null, cur = null;
      for (const r of rows) {
        if (cur && r - cur[1] <= 3) cur[1] = r; else { cur = [r, r]; }
        if (!best || cur[1] - cur[0] > best[1] - best[0]) best = cur.slice();
      }
      const ext = r => Fr.extent(r) || [cx0, cx0];
      if (best && best[1] - best[0] >= 0.06 * H) {
        const [b0, b1] = best;
        const inner0 = side < 0 ? sep[b0][1] : sep[b0][0];
        return {
          top: rs, bottom: b1, separate: true,
          cols(r) {
            if (r < rs || r > b1) return [];
            if (r >= b0 && sep[r]) return range(sep[r][0], sep[r][1]).filter(c => Fr.op(c, r));
            if (r >= b0) return [];
            const e = ext(r);
            return side < 0 ? range(e[0], Math.min(inner0 + S(1), cx0 - 1)).filter(c => Fr.op(c, r))
              : range(Math.max(inner0 - S(1), cx0 + 1), e[1]).filter(c => Fr.op(c, r));
          },
        };
      }
      // painted over the body (holding something): the outer quarter of the width at the chest
      const e40 = ext(R(0.4)), aw = Math.round(0.22 * (e40[1] - e40[0] + 1));
      const lim = side < 0 ? e40[0] + aw - 1 : e40[1] - aw + 1;
      const bottom = Math.min(R(0.62), crotch);
      return {
        top: rs, bottom,
        cols(r) {
          if (r < rs || r > bottom) return [];
          const e = ext(r);
          return side < 0 ? range(e[0], lim).filter(c => Fr.op(c, r)) : range(lim, e[1]).filter(c => Fr.op(c, r));
        },
      };
    }
    const armR = findArm(-1), armL = findArm(+1);

    // -- which part each front pixel is
    const own = {};                               // part -> {row: [cols]}
    const add = (p, r, c) => { (own[p] = own[p] || {}); (own[p][r] = own[p][r] || []).push(c); };
    const legRows = (r) => { const L = foot - crotch; return r < crotch + Math.round(0.46 * L) ? 'thigh' : r < crotch + Math.round(0.77 * L) ? 'shin' : 'foot'; };
    const armSeg = (a, r) => { const L = a.bottom - a.top; return r < a.top + Math.round(0.57 * L) ? 'arm' : r < a.top + Math.round(0.82 * L) ? 'forearm' : 'hand'; };
    const armSets = [[armR, '_r'], [armL, '_l']].map(([a, s]) => {
      const m = {};
      for (let r = a.top; r <= a.bottom; r++) for (const c of a.cols(r)) m[r * 4096 + c] = armSeg(a, r) + s;
      return m;
    });
    for (let r = top; r < foot; r++) for (let c = 0; c < Fr.w; c++) {
      if (!Fr.op(c, r)) continue;
      const id = r * 4096 + c;
      let p;
      if (inHead(c, r)) p = 'head';
      else if (armSets[0][id]) p = armSets[0][id];
      else if (armSets[1][id]) p = armSets[1][id];
      else if (r < crotch) p = r <= waist ? 'torso' : 'pelvis';
      else p = legRows(r) + (c >= cx0 ? '_l' : '_r');
      add(p, r, c);
    }

    // -- a leg drawn lifted (a running frame) or an arm lost against the body: use the other one, mirrored
    const mirrored = {};
    const lowest = sfx => { let lo = -1; for (const seg of ['thigh', 'shin', 'foot']) for (const r of Object.keys(own[seg + sfx] || {})) lo = Math.max(lo, +r); return lo; };
    const mirrorLimb = (segs, from, to) => {
      for (const seg of segs) {
        delete own[seg + to];
        for (const r of Object.keys(own[seg + from] || {})) for (const c of own[seg + from][r]) add(seg + to, +r, 2 * cx0 - 1 - c);
        mirrored[seg + to] = seg + from;
      }
    };
    const count = sfx => { let n = 0; for (const seg of ['shin', 'foot']) for (const r of Object.keys(own[seg + sfx] || {})) n += own[seg + sfx][r].length; return n; };
    const lowL = lowest('_l'), lowR = lowest('_r'), floor = foot - 1 - 0.06 * H, nL = count('_l'), nR = count('_r');
    if ((lowL < floor && lowR >= floor) || nL < 0.6 * nR) mirrorLimb(['thigh', 'shin', 'foot'], '_r', '_l');
    else if ((lowR < floor && lowL >= floor) || nR < 0.6 * nL) mirrorLimb(['thigh', 'shin', 'foot'], '_l', '_r');
    if (armR.separate && !armL.separate) mirrorLimb(['arm', 'forearm', 'hand'], '_r', '_l');
    else if (armL.separate && !armR.separate) mirrorLimb(['arm', 'forearm', 'hand'], '_l', '_r');

    // -- depth from the side frame (its own run on each row, smoothed)
    let cz0 = 0;
    const sideRun = {};
    if (Sd) {
      const sc = [];
      for (let r = rs; r < crotch; r++) { const e = Sd.extent(r); if (e) sc.push((e[0] + e[1] + 1) / 2); }
      cz0 = Math.round(median(sc));
      const raw = {};
      for (let r = Sd.top; r < Sd.foot; r++) { const rn = runAt(Sd, r, cz0); if (rn) raw[r] = rn; }
      for (let r = Sd.top; r < Sd.foot; r++) {
        const zb = [], zf = [];
        for (let k = -2; k <= 2; k++) if (raw[r + k]) { zb.push(raw[r + k][0] - cz0); zf.push(raw[r + k][1] + 1 - cz0); }
        if (zb.length) sideRun[r] = [median(zb), median(zf)];
      }
    }
    const sideAt = r => sideRun[r - foot + (Sd ? Sd.foot : foot)] || null;    // feet on the same line
    let bodySide = null;
    {
      const hs = [], ms = [];
      for (let r = rs + S(6); r < crotch; r++) { const q = sideAt(r); if (q) { hs.push((q[1] - q[0]) / 2); ms.push((q[0] + q[1]) / 2); } }
      if (hs.length) bodySide = { half: median(hs), mid: median(ms) };
    }
    function depth(part, r, c0, c1) {
      const hw = (c1 + 1 - c0) / 2;
      const s = sideAt(r);
      const base = part.replace(/_[lr]$/, '');
      if (base === 'head') {
        if (!s) return [-hw, hw * 1.1];
        let [zb, zf] = s;
        // the chin, between the shoulders: no deeper than the head just above (the side frame's row there is the body)
        const ref = r >= rs ? sideAt(rs - S(3)) : null;
        if (ref) { zb = Math.max(zb, ref[0] + (ref[1] - ref[0]) * 0.25); zf = Math.min(zf, ref[1]); }
        if (zf - zb < hw * 1.2) { const m = (zb + zf) / 2; zb = m - hw * 0.6; zf = m + hw * 0.6; }
        return [zb, zf];
      }
      if (base === 'torso' || base === 'pelvis') {
        // the body's depth: this row's in the side frame, but no deeper than the body's usual (held things and
        // swinging arms stick out of it), and centred where the body usually is
        let m = 0, half = hw * 0.62;
        if (s && bodySide) {
          half = clamp(Math.min((s[1] - s[0]) / 2, bodySide.half * 1.1), 0.42 * hw, 0.72 * hw);
          m = clamp(bodySide.mid, -0.15 * hw, 0.15 * hw);
        }
        return [m - half, m + half];
      }
      if (base === 'foot') {
        if (s) { const half = Math.min((s[1] - s[0]) / 2, hw * 1.0); const m = clamp((s[0] + s[1]) / 2, -hw * 0.3, hw * 0.6); return [m - half, m + half]; }
        return [-hw * 0.6, hw * 1.2];
      }
      const zc = base === 'thigh' || base === 'shin' ? 0 : -S(2);
      return [zc - hw * 0.95, zc + hw * 0.95];
    }
    const POWER = { head: 2.6, torso: 2.3, pelvis: 2.6, foot: 3.2, thigh: 2.4, shin: 2.4, arm: 2.2, forearm: 2.2, hand: 2.2 };

    // -- the shapes: each row across as the front shows it, rounded front to back (a super-ellipse)
    const src = new Map();             // key -> [c, r, part]
    const parts = {};
    for (const p of PARTS) parts[p] = new Map();
    for (const p of Object.keys(own)) {
      const pw = POWER[p.replace(/_[lr]$/, '')] || 2.4;
      for (const r of Object.keys(own[p]).map(Number)) {
        const cols = own[p][r].sort((a, b) => a - b);
        // pieces of a row (an arm's two edges) are rounded on their own
        const pieces = [];
        for (const c of cols) { const last = pieces[pieces.length - 1]; if (last && c - last[1] <= 1) last[1] = c; else pieces.push([c, c]); }
        for (const [c0, c1] of pieces) {
          const xc = (c0 + c1 + 1) / 2, hw = Math.max(0.5, (c1 + 1 - c0) / 2);
          const [zb, zf] = depth(p, r, c0, c1);
          const zc = (zb + zf) / 2, hd = Math.max(0.5, (zf - zb) / 2);
          const y = foot - 1 - r;
          for (let c = c0; c <= c1; c++) {
            const u = Math.min(1, Math.abs(c + 0.5 - xc) / hw);
            const half = Math.max(0.75, hd * Math.pow(1 - Math.pow(u, pw), 1 / pw));
            for (let z = Math.floor(zc - half); z < Math.ceil(zc + half); z++) {
              if (z + 0.5 < zc - half || z + 0.5 > zc + half) continue;
              const k = key(c - cx0, y, z);
              parts[p].set(k, 0);
              src.set(k, [c, r, p]);
            }
          }
        }
      }
    }

    const occAll = new Set();
    for (const p of PARTS) for (const k of parts[p].keys()) occAll.add(k);
    for (const p of PARTS) dropSpecks(parts[p], src, occAll);
    const model = { parts, bones: [], meta: {} };
    colourise(model, views, { foot, src, Fr });
    // mirrored limbs: the colours of the one they copy
    for (const p of Object.keys(mirrored)) {
      const from = parts[mirrored[p]];
      for (const k of parts[p].keys()) { const c = from.get(key(-kx(k) - 1, ky(k), kz(k))); if (c !== undefined) parts[p].set(k, c); }
    }

    // -- the bones (front-frame pixels: x = column - cx0, y = foot - row)
    const J = (c, r, z) => [c - cx0, foot - r, z || 0];
    const midOf = (p, r) => {
      if (!own[p] || !Object.keys(own[p]).length) {            // an empty part: the one above it in the limb
        const up = { hand: 'forearm', forearm: 'arm', foot: 'shin', shin: 'thigh' }[p.replace(/_[lr]$/, '')];
        if (up) return midOf(up + p.slice(-2), r);
      }
      const rows = own[p] || {}; let rr = r; for (let k = 0; k < 40 && !rows[rr]; k++) rr += k % 2 ? -k : k; const cs2 = rows[rr] || [cx0]; return (Math.min(...cs2) + Math.max(...cs2) + 1) / 2; };
    const armJ = (a, s) => {
      const L = a.bottom - a.top, sh = a.top + Math.round(0.12 * L), el = a.top + Math.round(0.57 * L), wr = a.top + Math.round(0.82 * L);
      return { sh: J(midOf('arm' + s, sh), sh, -S(2)), el: J(midOf('forearm' + s, el), el, -S(2)), wr: J(midOf('hand' + s, wr), wr, -S(2)), wrRow: wr, wrCol: midOf('hand' + s, wr) };
    };
    const legJ = s => {
      const L = foot - crotch, kn = crotch + Math.round(0.46 * L), an = crotch + Math.round(0.77 * L);
      return { hip: J(midOf('thigh' + s, crotch + 1), hipRow, 0), kn: J(midOf('shin' + s, kn), kn, 0), an: J(midOf('foot' + s, an), an, -1) };
    };
    const fl = j => j && [-j[0], j[1], j[2]];
    const flipJ = j => ({ sh: fl(j.sh), el: fl(j.el), wr: fl(j.wr), wrRow: j.wrRow, wrCol: j.wrCol !== undefined ? 2 * cx0 - j.wrCol : undefined, hip: fl(j.hip), kn: fl(j.kn), an: fl(j.an) });
    let ar = armJ(armR, '_r'), al = armJ(armL, '_l'), lr = legJ('_r'), ll = legJ('_l');
    if (mirrored.arm_l) al = flipJ(ar); else if (mirrored.arm_r) ar = flipJ(al);
    if (mirrored.thigh_l) ll = flipJ(lr); else if (mirrored.thigh_r) lr = flipJ(ll);
    const headZ = (() => { const s = sideAt(neck); return s ? clamp(Math.round((s[0] + s[1]) / 2), -S(4), S(4)) : 1; })();
    const piv = {
      hips: J(cx0, waist + S(2)), chest: J(cx0, waist - S(4)), head: J(cx0, neck, headZ),
      arm_r: ar.sh, forearm_r: ar.el, hand_r: ar.wr, arm_l: al.sh, forearm_l: al.el, hand_l: al.wr,
      thigh_l: ll.hip, shin_l: ll.kn, foot_l: ll.an, thigh_r: lr.hip, shin_r: lr.kn, foot_r: lr.an,
    };
    model.bones = BONES.map(n => ({ name: n, parent: PARENT[n], pivot: piv[n].map(v => +(+v).toFixed(1)) }));
    model.meta = {
      cx0, foot, cz0, ref_rows: Fr.h, height: H,
      grip_r: [+(ar.wrCol - cx0).toFixed(1), foot - (ar.wrRow + S(7)), 0],
      rows: { top, shoulders: rs, chin: headEnd, neck, crotch, waist, hipRow, skirt }, mirrored: Object.keys(mirrored),
    };
    return model;
  }
  // bits of a part not joined to its main piece and under a few blocks (stray pixels round the art) go
  function dropSpecks(m, src, occAll) {
    const seen = new Set();
    for (const k0 of m.keys()) {
      if (seen.has(k0)) continue;
      const piece = [k0]; seen.add(k0);
      for (let i = 0; i < piece.length; i++) {
        const k = piece[i], x = kx(k), y = ky(k), z = kz(k);
        for (const q of [key(x + 1, y, z), key(x - 1, y, z), key(x, y + 1, z), key(x, y - 1, z), key(x, y, z + 1), key(x, y, z - 1)]) {
          if (m.has(q) && !seen.has(q)) { seen.add(q); piece.push(q); }
        }
      }
      // (a whole part that small goes too if it floats free of every other part)
      const touches = () => piece.some(k => { const x = kx(k), y = ky(k), z = kz(k); return [key(x + 1, y, z), key(x - 1, y, z), key(x, y + 1, z), key(x, y - 1, z), key(x, y, z + 1), key(x, y, z - 1)].some(q => occAll.has(q) && !m.has(q)); });
      if (piece.length < 24 && (piece.length < m.size * 0.2 || !touches())) for (const k of piece) { m.delete(k); src.delete(k); occAll.delete(k); }
    }
  }
  function range(a, b) { const o = []; for (let i = a; i <= b; i++) o.push(i); return o; }

  // ---------------------------------------------------------------- colours
  // Every surface block takes its colour from the frame that looks at it most squarely and can see it (the front,
  // back, side, or the diagonals; the sides and diagonals are drawn facing right, so the other side uses them
  // flipped). Seen-ness is a depth buffer of the model itself in that view, so a block hidden behind an arm in the
  // side frame isn't painted with the arm.
  function colourise(model, views, ctx) {
    const all = new Map();      // key -> part
    for (const p of Object.keys(model.parts)) for (const k of model.parts[p].keys()) all.set(k, p);
    const surf = [];
    const has = (x, y, z) => all.has(key(x, y, z));
    for (const k of all.keys()) {
      const x = kx(k), y = ky(k), z = kz(k);
      if (!has(x + 1, y, z) || !has(x - 1, y, z) || !has(x, y + 1, z) || !has(x, y - 1, z) || !has(x, y, z + 1) || !has(x, y, z - 1)) surf.push(k);
    }
    // normals: away from the filled blocks nearby
    const nrm = new Map();
    for (const k of surf) {
      const x = kx(k), y = ky(k), z = kz(k);
      let nx = 0, ny = 0, nz = 0;
      for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) for (let dz = -2; dz <= 2; dz++) {
        if (!dx && !dy && !dz) continue;
        if (has(x + dx, y + dy, z + dz)) continue;
        const w = 1 / (dx * dx + dy * dy + dz * dz);
        nx += dx * w; ny += dy * w; nz += dz * w;
      }
      const l = Math.hypot(nx, ny, nz) || 1;
      nrm.set(k, [nx / l, ny / l, nz / l]);
    }
    const s2 = Math.SQRT1_2;
    const V = [];
    const addView = (img, d, flipped) => { if (img) V.push({ f: frame(flipped ? flipImg(img) : img), d }); };
    addView(views.front, [0, 0, 1], false);
    addView(views.back, [0, 0, -1], false);
    addView(views.side, [-1, 0, 0], false);
    addView(views.side, [1, 0, 0], true);
    addView(views.diag, [-s2, 0, s2], false);
    addView(views.diag, [s2, 0, s2], true);
    addView(views.bdiag, [-s2, 0, -s2], false);
    addView(views.bdiag, [s2, 0, -s2], true);
    const H = ctx.foot - ctx.Fr.top;
    for (const v of V) {
      const d = v.d, right = [d[2], 0, -d[0]];
      const zb = new Map();
      const proj = new Map();
      for (const k of surf) {
        const px = kx(k) + 0.5, py = ky(k), pz = kz(k) + 0.5;
        const sx = px * right[0] + pz * right[2], dep = px * d[0] + pz * d[2];
        const col = Math.floor(sx), id = py * 4096 + col + 2048;
        proj.set(k, [sx, dep, py]);
        const was = zb.get(id);
        if (was === undefined || dep > was) zb.set(id, dep);
      }
      // line the picture up with the model, row by row (the head can sit forward of the body in a side frame):
      // the middle of each row's outline in the picture against the model's, smoothed, kept near the whole body's
      const mExt = {};
      for (const id of zb.keys()) {
        const py = Math.floor(id / 4096), c = (id % 4096) - 2048;
        const e = mExt[py] || (mExt[py] = [c, c]); if (c < e[0]) e[0] = c; if (c > e[1]) e[1] = c;
      }
      const raw = {};
      const y0 = Math.round(0.1 * H), y1 = Math.round(0.7 * H);
      for (const py of Object.keys(mExt).map(Number)) {
        const e = v.f.extent(v.f.foot - 1 - py);
        if (e) raw[py] = (e[0] + e[1] + 1) / 2 - (mExt[py][0] + mExt[py][1] + 1) / 2;
      }
      const all = Object.keys(raw).map(Number).filter(py => py >= y0 && py <= y1).map(py => raw[py]);
      const whole = all.length ? median(all) : 0;
      v.offs = {};
      for (const py of Object.keys(mExt).map(Number)) {
        const w = [];
        for (let k = -6; k <= 6; k++) if (raw[py + k] !== undefined) w.push(raw[py + k]);
        v.offs[py] = w.length ? clamp(median(w), whole - 0.12 * H, whole + 0.12 * H) : whole;
      }
      v.off = whole;
      v.zb = zb; v.proj = proj;
    }
    for (const k of surf) {
      const n = nrm.get(k);
      let best = null, bw = 0.2;
      for (const v of V) {
        const w = n[0] * v.d[0] + n[1] * 0.0 + n[2] * v.d[2];
        // top and bottom faces lean on whichever side view they tip toward
        const wt = w + (Math.abs(n[1]) > 0.6 ? 0.05 : 0);
        if (wt <= bw) continue;
        const [sx, dep, py] = v.proj.get(k);
        const col = Math.floor(sx);
        const front = v.zb.get(py * 4096 + col + 2048);
        if (front !== undefined && dep < front - 1.6) continue;          // hidden in this view
        const c = Math.floor(sx + (v.offs[py] !== undefined ? v.offs[py] : v.off)), r = v.f.foot - 1 - py;
        let got = -1;
        if (v.f.op(c, r)) got = v.f.col(c, r);
        else if (v.f.op(c - 1, r)) got = v.f.col(c - 1, r);
        else if (v.f.op(c + 1, r)) got = v.f.col(c + 1, r);
        if (got < 0) continue;
        best = got; bw = wt;
      }
      if (best === null) {
        const s = ctx.src.get(k);
        best = s ? shade(ctx.Fr.col(s[0], s[1]), n[2] < -0.3 ? 0.8 : 0.95) : 0x503c32;
      }
      model.parts[all.get(k)].set(k, best);
    }
    // inside blocks: the part's surface colour, darker (only seen if a block is removed)
    for (const p of Object.keys(model.parts)) {
      const m = model.parts[p], cols = [];
      for (const c of m.values()) if (c) cols.push(c);
      let r = 0, g = 0, b = 0;
      for (const c of cols) { r += (c >> 16) & 255; g += (c >> 8) & 255; b += c & 255; }
      const n = cols.length || 1, fill = pack(r / n * 0.7, g / n * 0.7, b / n * 0.7);
      for (const [k, c] of m) if (!c) m.set(k, fill);
    }
  }

  // ---------------------------------------------------------------- .vox (MagicaVoxel), as vox_build.write_vox
  // vox (vx, vy, vz) = (x - x0, (sy - 1) - (z - z0), y - y0): upright in MagicaVoxel, looking toward -y.
  function quantise(cols, n) {
    // merge colours by dropping low bits until they fit
    for (let bits = 1; bits <= 6; bits++) {
      const m = (0xff << bits) & 0xff, mm = (m << 16) | (m << 8) | m;
      const half = (1 << (bits - 1)) | ((1 << (bits - 1)) << 8) | ((1 << (bits - 1)) << 16);
      const set = new Set(cols.map(c => (c & mm) | half));
      if (set.size <= n) { const remap = new Map(cols.map(c => [c, (c & mm) | half])); return { cols: [...set], remap }; }
    }
    return { cols: cols.slice(0, n), remap: new Map(cols.map(c => [c, cols[0]])) };
  }
  function toVox(vox) {
    if (!vox.size) return null;
    let x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
    for (const k of vox.keys()) {
      const x = kx(k), y = ky(k), z = kz(k);
      x0 = Math.min(x0, x); y0 = Math.min(y0, y); z0 = Math.min(z0, z); x1 = Math.max(x1, x); y1 = Math.max(y1, y); z1 = Math.max(z1, z);
    }
    const sx = x1 - x0 + 1, sy = z1 - z0 + 1, sz = y1 - y0 + 1;
    let cols = [...new Set(vox.values())].sort((a, b) => a - b), remap = null;
    if (cols.length > 255) { const q = quantise(cols, 255); cols = q.cols; remap = q.remap; }
    const index = new Map(cols.map((c, i) => [c, i + 1]));
    const n = vox.size;
    const size = 12 + 12, xyzi = 12 + 4 + n * 4, rgba = 12 + 1024;
    const buf = new ArrayBuffer(8 + 12 + size + xyzi + rgba);
    const dv = new DataView(buf), u8 = new Uint8Array(buf);
    let o = 0;
    const str = s => { for (let i = 0; i < 4; i++) u8[o++] = s.charCodeAt(i); };
    const i32 = v => { dv.setInt32(o, v, true); o += 4; };
    str('VOX '); i32(150);
    str('MAIN'); i32(0); i32(size + xyzi + rgba);
    str('SIZE'); i32(12); i32(0); i32(sx); i32(sy); i32(sz);
    str('XYZI'); i32(4 + n * 4); i32(0); i32(n);
    for (const [k, c0] of vox) {
      const c = remap ? remap.get(c0) : c0;
      u8[o++] = kx(k) - x0; u8[o++] = (sy - 1) - (kz(k) - z0); u8[o++] = ky(k) - y0; u8[o++] = index.get(c);
    }
    str('RGBA'); i32(1024); i32(0);
    for (let i = 0; i < 256; i++) {
      const c = i < cols.length ? cols[i] : 0;
      u8[o++] = (c >> 16) & 255; u8[o++] = (c >> 8) & 255; u8[o++] = c & 255; u8[o++] = 255;
    }
    return { bytes: u8, origin: [x0, y0, z0], size: [sx, sy, sz] };
  }
  // A .vox back to blocks (for checks and for opening a game JSON): origin from rig.json
  function fromVox(bytes, origin) {
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const id = o => String.fromCharCode(bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]);
    if (id(0) !== 'VOX ') throw new Error('not a .vox');
    let o = 8, size = null, pts = null, pal = null;
    while (o + 12 <= bytes.length) {
      const cid = id(o), n = dv.getInt32(o + 4, true), m = dv.getInt32(o + 8, true), b = o + 12;
      if (cid === 'MAIN') { o = b; continue; }
      if (cid === 'SIZE' && !size) size = [dv.getInt32(b, true), dv.getInt32(b + 4, true), dv.getInt32(b + 8, true)];
      if (cid === 'XYZI' && !pts) pts = bytes.subarray(b + 4, b + 4 + dv.getInt32(b, true) * 4);
      if (cid === 'RGBA') { pal = []; for (let i = 0; i < 256; i++) pal.push(pack(bytes[b + i * 4], bytes[b + i * 4 + 1], bytes[b + i * 4 + 2])); }
      o = b + n + m;
    }
    const out = new Map();
    for (let i = 0; i < pts.length; i += 4) {
      const vx = pts[i], vy = pts[i + 1], vz = pts[i + 2], ci = pts[i + 3];
      if (!ci) continue;
      out.set(key(origin[0] + vx, origin[1] + vz, origin[2] + (size[1] - 1 - vy)), pal ? pal[ci - 1] : 0x808080);
    }
    return out;
  }

  // ---------------------------------------------------------------- the game's files
  // rig.json (as Jared's) and the .vox files. ref_sheet goth: the sprite maker draws everyone at Gothica's size, so
  // the game sizes a block the way it sizes her pixels.
  function gameFiles(model, id) {
    const files = {}, partsOut = [];
    for (const p of PARTS) {
      const v = model.parts[p];
      if (!v || !v.size) continue;
      const t = toVox(v);
      files[p + '.vox'] = t.bytes;
      partsOut.push({ name: p, bone: BONE_OF(p), file: p + '.vox', origin: t.origin, size: t.size });
    }
    const m = model.meta;
    const rig = {
      char: id, bones: model.bones, parts: partsOut,
      ref_sheet: 'goth', ref_key: 'front_a', ref_frame: 0, ref_rows: m.ref_rows || 160,
      cx0: m.cx0, foot: m.foot, cz0: m.cz0, grip_r: m.grip_r, styles: [], tool: 'sprite-maker',
    };
    return { rig, files };
  }
  // and back (a game JSON's "voxel" field, base64 files)
  function fromGame(rig, files) {
    const parts = {};
    for (const p of PARTS) parts[p] = new Map();
    for (const pm of rig.parts) if (files[pm.file]) parts[pm.name] = fromVox(files[pm.file], pm.origin);
    return { parts, bones: rig.bones, meta: { cx0: rig.cx0, foot: rig.foot, cz0: rig.cz0, ref_rows: rig.ref_rows, grip_r: rig.grip_r } };
  }

  // ---------------------------------------------------------------- greedy meshing (as VoxMesher)
  // A part's quads in voxel units: { pos, nrm, col (0..1), idx }. Faces between two blocks of the part are left out.
  function mesh(vox) {
    const pos = [], nrm = [], col = [], idx = [];
    if (!vox.size) return { pos, nrm, col, idx };
    let x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
    for (const k of vox.keys()) { const x = kx(k), y = ky(k), z = kz(k); if (x < x0) x0 = x; if (y < y0) y0 = y; if (z < z0) z0 = z; if (x > x1) x1 = x; if (y > y1) y1 = y; if (z > z1) z1 = z; }
    const dims = [x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1];
    const cells = new Int32Array(dims[0] * dims[1] * dims[2]);
    for (const [k, c] of vox) cells[(kx(k) - x0) + dims[0] * ((ky(k) - y0) + dims[1] * (kz(k) - z0))] = c + 1;
    const strides = [1, dims[0], dims[0] * dims[1]], org = [x0, y0, z0];
    for (let axis = 0; axis < 3; axis++) {
      const ua = (axis + 1) % 3, va = (axis + 2) % 3;
      const nA = dims[axis], nU = dims[ua], nV = dims[va];
      const mask = new Int32Array(nU * nV);
      for (const dir of [1, -1]) {
        for (let i = 0; i < nA; i++) {
          let any = false;
          const hasNext = i + dir >= 0 && i + dir < nA;
          for (let v = 0; v < nV; v++) for (let u = 0; u < nU; u++) {
            const id = i * strides[axis] + u * strides[ua] + v * strides[va];
            const c = cells[id];
            const m = c && (!hasNext || !cells[id + dir * strides[axis]]) ? c : 0;
            mask[v * nU + u] = m; if (m) any = true;
          }
          if (!any) continue;
          const plane = i + (dir > 0 ? 1 : 0) + org[axis];
          for (let v = 0; v < nV; v++) for (let u = 0; u < nU;) {
            const c = mask[v * nU + u];
            if (!c) { u++; continue; }
            let w = 1; while (u + w < nU && mask[v * nU + u + w] === c) w++;
            let h = 1;
            grow: while (v + h < nV) { for (let q = 0; q < w; q++) if (mask[(v + h) * nU + u + q] !== c) break grow; h++; }
            for (let hh = 0; hh < h; hh++) for (let q = 0; q < w; q++) mask[(v + hh) * nU + u + q] = 0;
            const base = pos.length / 3;
            const corner = (du, dv) => { const p = [0, 0, 0]; p[axis] = plane; p[ua] = org[ua] + u + du; p[va] = org[va] + v + dv; return p; };
            const quad = [corner(0, 0), corner(w, 0), corner(w, h), corner(0, h)];
            const n = [0, 0, 0]; n[axis] = dir;
            const [r, g, b] = rgbOf(c - 1);
            for (const p of quad) { pos.push(p[0], p[1], p[2]); nrm.push(n[0], n[1], n[2]); col.push(r / 255, g / 255, b / 255); }
            // (u, v, axis) is a right-handed set, so 0-1-2 faces +axis
            if (dir > 0) idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
            else idx.push(base, base + 2, base + 1, base, base + 3, base + 2);
            u += w;
          }
        }
      }
    }
    return { pos, nrm, col, idx };
  }

  // ---------------------------------------------------------------- the moves (VoxelAnim's, for the preview)
  // Each bone's turn as Euler angles (x, y, z) in Godot's YXZ order, the body's lift (voxels).
  const CYCLE = 91;
  function pose(s) {
    const rot = {}, t = s.t || 0;
    const out = { rot, pos: [0, 0, 0] };
    const amp = s.moving ? clamp((s.speed || 120) / 160, 0.45, 1) : 0;
    const ph = (s.odo || 0) / CYCLE * Math.PI * 2;
    const breathe = Math.sin(t * 2.1);
    if (amp <= 0) {
      rot.chest = [0.02 * breathe, 0, 0]; rot.head = [-0.015 * breathe, 0.06 * Math.sin(t * 0.37), 0];
      rot.thigh_l = [0, 0, 0.03]; rot.thigh_r = [0, 0, -0.03]; rot.foot_l = [0, 0, -0.03]; rot.foot_r = [0, 0, 0.03];
      out.pos = [0, 0.4 * breathe - 0.4, 0];
    } else {
      for (const [sd, o] of [['l', 0], ['r', Math.PI]]) {
        const p = ph + o, sw = Math.sin(p);
        const thigh = -sw * 0.62 * amp;
        const knee = (0.15 + 0.95 * Math.max(0, Math.cos(p - 0.35))) * amp;
        const foot = -(thigh + knee) * 0.7 + 0.12 * amp * Math.max(0, -sw);
        rot['thigh_' + sd] = [thigh, 0, 0]; rot['shin_' + sd] = [knee, 0, 0]; rot['foot_' + sd] = [foot, 0, 0];
      }
      rot.hips = [0, 0.10 * Math.sin(ph) * amp, 0];
      rot.chest = [0.10 * amp, -0.18 * Math.sin(ph) * amp, 0];
      rot.head = [-0.08 * amp, 0.08 * Math.sin(ph) * amp, 0];
      out.pos = [0, -3.0 * amp + 3.2 * amp * Math.abs(Math.cos(ph)), 0];
    }
    const swing = Math.sin(ph) * amp;
    let l = [[0.62 * swing, 0, 0.14 + 0.02 * breathe], [-0.35 - 0.45 * amp, 0, 0]];
    let r = [[-0.62 * swing, 0, -0.14 - 0.02 * breathe], [-0.35 - 0.45 * amp, 0, 0]];
    if (s.weapon === 'fists') { r = [[-0.55, 0.25, -0.1], [-2.05, 0, 0]]; l = [[-0.55, -0.25, 0.1], [-2.05, 0, 0]]; }
    if (s.act === 'punch') {
      // a jab with the right: out and back
      const k = Math.sin(clamp(s.act_f || 0, 0, 1) * Math.PI), lerp = (a, b) => a + (b - a) * k;
      r = [[lerp(-0.55, -1.5), lerp(0.25, 0.1), -0.1], [lerp(-2.05, -0.05), 0, 0]];
      rot.chest = [0.05, -0.35 * k, 0];
    }
    rot.arm_r = r[0]; rot.forearm_r = r[1]; rot.arm_l = l[0]; rot.forearm_l = l[1];
    return out;
  }

  const api = { carve, colourise, toVox, fromVox, gameFiles, fromGame, mesh, pose, key, kx, ky, kz, flipImg, frame,
    BONES, PARENT, PARTS, BONE_OF, MIRROR, pack, rgbOf };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.SpriteBlocks = api;
})(typeof self !== 'undefined' ? self : this);
