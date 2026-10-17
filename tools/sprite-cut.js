// Cuts a generated sprite sheet into game frames.
// Works on plain { width, height, data } pixel buffers (RGBA), so the same code runs in the
// browser (sprite-maker.html) and in node for testing.
//
// 1. key out the green background
// 2. find the frames (columns with art in them, split or merged until there are as many as asked)
// 3. scale the whole sheet so the character is as tall as Gothica (148px, head to soles)
// 4. put every frame in a 160px tall cell, feet on the bottom row, head and body centred
(function (root) {
  const FRAME_H = 160;      // every sprite in the game is 160px tall
  const BODY_H = 148;       // Gothica, top of hair to soles, measured from her art
  const MAX_H = 158;        // nothing taller than this, so raised arms don't get cut off

  // The background colour: the median of the border pixels that look green.
  function findBg(img) {
    const { width: w, height: h, data: d } = img;
    const rs = [], gs = [], bs = [];
    const take = (x, y) => {
      const i = (y * w + x) * 4, r = d[i], g = d[i + 1], b = d[i + 2];
      if (g > r + 40 && g > b + 40) { rs.push(r); gs.push(g); bs.push(b); }
    };
    const step = Math.max(1, Math.floor(Math.min(w, h) / 200));
    for (let x = 0; x < w; x += step) { take(x, 0); take(x, 1); take(x, h - 1); take(x, h - 2); }
    for (let y = 0; y < h; y += step) { take(0, y); take(1, y); take(w - 1, y); take(w - 2, y); }
    if (rs.length < 20) return [0, 255, 0];
    const med = a => a.sort((p, q) => p - q)[a.length >> 1];
    return [med(rs), med(gs), med(bs)];
  }

  // Green out, in place. Returns a mask (1 = art).
  function keyGreen(img) {
    const { width: w, height: h, data: d } = img;
    const [br, bg, bb] = findBg(img);
    const mask = new Uint8Array(w * h);
    for (let p = 0, i = 0; p < w * h; p++, i += 4) {
      const r = d[i], g = d[i + 1], b = d[i + 2];
      const dist = Math.sqrt((r - br) ** 2 + (g - bg) ** 2 + (b - bb) ** 2);
      const greenness = g - Math.max(r, b);
      if (dist < 110 || (greenness > 100 && g > 150)) { d[i + 3] = 0; }
      else { d[i + 3] = 255; mask[p] = 1; }
    }
    // the edge pixels next to the green pick up a green tint from the image's own blur: take it out
    // (only on the edge, so green in her hair stays green)
    for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
      const p = y * w + x; if (!mask[p]) continue;
      if (mask[p - 1] && mask[p + 1] && mask[p - w] && mask[p + w]) continue;
      const i = p * 4, m = Math.max(d[i], d[i + 2]);
      if (d[i + 1] > m + 10) d[i + 1] = m + 10;
    }
    return mask;
  }

  // Where the frames are: [{x0, x1}] left to right, exactly n of them (or as close as it can get).
  function findFrames(mask, w, h, n) {
    const col = new Uint32Array(w);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) col[x] += mask[y * w + x];
    const thresh = Math.max(2, Math.round(h * 0.004));
    let runs = [];
    for (let x = 0, s = -1; x <= w; x++) {
      const on = x < w && col[x] > thresh;
      if (on && s < 0) s = x;
      if (!on && s >= 0) { runs.push({ x0: s, x1: x - 1 }); s = -1; }
    }
    // join runs split by a hairline gap, drop specks
    const joinGap = Math.max(2, Math.round(w * 0.006));
    runs = runs.reduce((a, r) => {
      const last = a[a.length - 1];
      if (last && r.x0 - last.x1 <= joinGap) last.x1 = r.x1; else a.push({ ...r });
      return a;
    }, []);
    runs = runs.filter(r => r.x1 - r.x0 + 1 >= w * 0.012);
    if (!runs.length) return [];
    // too many: join the pair with the smallest gap between them
    while (runs.length > n) {
      let best = 0, gap = Infinity;
      for (let i = 0; i < runs.length - 1; i++) {
        const g = runs[i + 1].x0 - runs[i].x1;
        // a sliver beside a full-size frame is almost certainly a stray hand or foot: join it first
        const sliver = Math.min(runs[i].x1 - runs[i].x0, runs[i + 1].x1 - runs[i + 1].x0);
        const score = g + sliver * 0.25;
        if (score < gap) { gap = score; best = i; }
      }
      runs.splice(best, 2, { x0: runs[best].x0, x1: runs[best + 1].x1 });
    }
    // too few: frames are touching. Cut the widest run in two, at the column with the least art
    // in it near the middle (where two frames meet, only a hand or a foot crosses over).
    // typical frame width: the median of the runs found. (Not span / n: when Gemini draws fewer
    // figures than asked, that's too narrow and real bodies get cut in half.)
    const ws = runs.map(r => r.x1 - r.x0 + 1).sort((a, b) => a - b);
    // ...unless most of the frames are stuck together, then the median is itself several frames wide
    const each = runs.length * 2 >= n ? ws[ws.length >> 1] : (runs[runs.length - 1].x1 - runs[0].x0 + 1) / n;
    let guard = 0;
    while (runs.length < n && guard++ < 50) {
      let wi = 0;
      runs.forEach((r, i) => { if (r.x1 - r.x0 > runs[wi].x1 - runs[wi].x0) wi = i; });
      const r = runs[wi], width = r.x1 - r.x0 + 1;
      if (width < each * 1.6) break;                                // nothing that looks like two frames
      // which frame boundary to aim for: the one nearest the middle of this run
      const k = Math.max(1, Math.round(width / each / 2));
      const mid = r.x0 + Math.round(each * k), rad = Math.round(each * 0.35);
      let bx = mid, bv = Infinity;
      for (let x = Math.max(r.x0 + 1, mid - rad); x <= Math.min(r.x1 - 1, mid + rad); x++) {
        const v = col[x] + Math.abs(x - mid) * 0.05 * h / each;     // emptiest, nudged toward the mark
        if (v < bv) { bv = v; bx = x; }
      }
      runs.splice(wi, 1, { x0: r.x0, x1: bx - 1 }, { x0: bx, x1: r.x1 });
    }
    return runs;
  }

  // Within columns x0..x1, keep the character and drop loose bits: a fist or foot of the next
  // frame poking across the line, or specks. Clears what it drops from the mask and the image.
  function cleanFrame(img, mask, w, h, f) {
    const fw = f.x1 - f.x0 + 1;
    const lab = new Int32Array(fw * h);
    const comps = [];
    const stack = [];
    for (let y = 0; y < h; y++) for (let x = 0; x < fw; x++) {
      const p = y * fw + x;
      if (lab[p] || !mask[y * w + f.x0 + x]) continue;
      const id = comps.length + 1, c = { id, area: 0, x0: x, x1: x, y0: y, y1: y };
      lab[p] = id; stack.push(p);
      while (stack.length) {
        const q = stack.pop(), qx = q % fw, qy = (q - qx) / fw;
        c.area++;
        if (qx < c.x0) c.x0 = qx; if (qx > c.x1) c.x1 = qx; if (qy < c.y0) c.y0 = qy; if (qy > c.y1) c.y1 = qy;
        // 8-way, so a one-pixel diagonal join (a thin strap, a finger) keeps parts together
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          const nx = qx + dx, ny = qy + dy;
          if (nx < 0 || ny < 0 || nx >= fw || ny >= h) continue;
          const np = ny * fw + nx;
          if (!lab[np] && mask[ny * w + f.x0 + nx]) { lab[np] = id; stack.push(np); }
        }
      }
      comps.push(c);
    }
    if (!comps.length) return;
    const main = comps.reduce((a, b) => (b.area > a.area ? b : a));
    // keep the body, and any sizeable piece that sits over it (a loose strand of hair, a hand
    // drawn just apart from the arm); drop small pieces out at the sides
    const keep = new Set([main.id]);
    for (const c of comps) {
      if (c === main) continue;
      const cx = (c.x0 + c.x1) / 2;
      const over = cx >= main.x0 && cx <= main.x1;
      if (over && c.area >= main.area * 0.004) keep.add(c.id);
    }
    for (let y = 0; y < h; y++) for (let x = 0; x < fw; x++) {
      const id = lab[y * fw + x];
      if (id && !keep.has(id)) { const p = y * w + f.x0 + x; mask[p] = 0; img.data[p * 4 + 3] = 0; }
    }
  }

  // Box around the art in columns x0..x1, plus where the head and body are (for centring).
  function frameBox(mask, w, h, f) {
    let y0 = h, y1 = -1, x0 = f.x1, x1 = f.x0;
    for (let y = 0; y < h; y++) for (let x = f.x0; x <= f.x1; x++) {
      if (!mask[y * w + x]) continue;
      if (y < y0) y0 = y; if (y > y1) y1 = y;
      if (x < x0) x0 = x; if (x > x1) x1 = x;
    }
    if (y1 < 0) return null;
    // centre of the top 40% (head and chest), which stays put while arms and legs swing
    const yTop = y0 + Math.round((y1 - y0) * 0.4);
    let sx = 0, c = 0;
    for (let y = y0; y <= yTop; y++) for (let x = x0; x <= x1; x++) if (mask[y * w + x]) { sx += x; c++; }
    return { x0, x1, y0, y1, ax: c ? sx / c : (x0 + x1) / 2 };
  }

  // Shrink a box of the sheet by s with a proper average (so the big "pixels" Gemini draws
  // become one pixel each), then make the edges hard again.
  function shrink(img, b, s) {
    const { width: w, data: d } = img;
    const sw = b.x1 - b.x0 + 1, sh = b.y1 - b.y0 + 1;
    const tw = Math.max(1, Math.round(sw * s)), th = Math.max(1, Math.round(sh * s));
    const out = new Uint8ClampedArray(tw * th * 4);
    for (let ty = 0; ty < th; ty++) {
      const ya = b.y0 + Math.floor(ty / s), yb = Math.max(ya + 1, b.y0 + Math.floor((ty + 1) / s));
      for (let tx = 0; tx < tw; tx++) {
        const xa = b.x0 + Math.floor(tx / s), xb = Math.max(xa + 1, b.x0 + Math.floor((tx + 1) / s));
        let r = 0, g = 0, bl = 0, a = 0, n = 0;
        for (let y = ya; y < Math.min(yb, img.height); y++) for (let x = xa; x < Math.min(xb, w); x++) {
          const i = (y * w + x) * 4, al = d[i + 3] / 255;
          r += d[i] * al; g += d[i + 1] * al; bl += d[i + 2] * al; a += al; n++;
        }
        const o = (ty * tw + tx) * 4;
        if (n && a / n >= 0.5) { out[o] = r / a; out[o + 1] = g / a; out[o + 2] = bl / a; out[o + 3] = 255; }
      }
    }
    return { width: tw, height: th, data: out };
  }

  // The whole job. opts:
  //   frames   how many frames the sheet should have
  //   sizeBy   'median' (the usual height of the frames) or 'first' (frame 1 is a standing pose)
  //   ground   'each' (every frame's feet on the bottom row) or 'sheet' (keep hops: one ground line)
  //   dropFirst  throw frame 1 away after using it for size
  //   size     the size slider, 1 = Gothica's size
  //   mirror   flip everything left-right (when Gemini drew it facing the wrong way)
  // Returns { frames: [{width,height,data}], cellW, scale, found, note }
  function cutSheet(src, opts) {
    const o = Object.assign({ frames: 7, sizeBy: 'median', ground: 'each', dropFirst: false, size: 1, mirror: false }, opts);
    const img = { width: src.width, height: src.height, data: new Uint8ClampedArray(src.data) };
    const { width: w, height: h } = img;
    const mask = keyGreen(img);
    const want = o.frames + (o.dropFirst ? 1 : 0);
    const cols = findFrames(mask, w, h, want);
    for (const f of cols) cleanFrame(img, mask, w, h, f);
    let boxes = cols.map(f => frameBox(mask, w, h, f)).filter(Boolean);
    const found = boxes.length;
    const notes = [];
    if (found !== want) notes.push('found ' + found + ' frames, expected ' + want);
    if (!boxes.length) return { frames: [], cellW: 0, scale: 0, found, note: 'no art found' };
    const hs = boxes.map(b => b.y1 - b.y0 + 1);
    const ref = o.sizeBy === 'first' ? hs[0] : hs.slice().sort((a, b) => a - b)[hs.length >> 1];
    let scale = BODY_H / ref * o.size;
    const tallest = Math.max(...hs);
    if (tallest * scale > MAX_H) { scale = MAX_H / tallest; notes.push('shrunk a little so the tallest frame fits'); }
    const groundY = Math.max(...boxes.map(b => b.y1));
    if (o.dropFirst) boxes = boxes.slice(1);
    // shrink each frame, then lay them out in equal cells
    const parts = boxes.map(b => {
      const im = shrink(img, b, scale);
      const ax = (b.ax - b.x0) * scale;                         // anchor within the shrunk frame
      const lift = o.ground === 'sheet' ? Math.round((groundY - b.y1) * scale) : 0;
      return { im, ax, lift };
    });
    let half = 0;
    for (const p of parts) half = Math.max(half, p.ax, p.im.width - p.ax);
    const cellW = Math.ceil(half) * 2 + 4;
    const frames = parts.map(p => {
      const out = new Uint8ClampedArray(cellW * FRAME_H * 4);
      const ox = Math.round(cellW / 2 - p.ax), oy = FRAME_H - p.im.height - p.lift;
      for (let y = 0; y < p.im.height; y++) {
        const ty = oy + y; if (ty < 0 || ty >= FRAME_H) continue;
        for (let x = 0; x < p.im.width; x++) {
          let tx = ox + x; if (tx < 0 || tx >= cellW) continue;
          if (o.mirror) tx = cellW - 1 - tx;
          const si = (y * p.im.width + x) * 4, di = (ty * cellW + tx) * 4;
          if (!p.im.data[si + 3]) continue;
          out[di] = p.im.data[si]; out[di + 1] = p.im.data[si + 1]; out[di + 2] = p.im.data[si + 2]; out[di + 3] = 255;
        }
      }
      return { width: cellW, height: FRAME_H, data: out };
    });
    return { frames, cellW, scale, found, note: notes.join('; ') };
  }

  const api = { cutSheet, keyGreen, findFrames, FRAME_H, BODY_H };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.SpriteCut = api;
})(this);
