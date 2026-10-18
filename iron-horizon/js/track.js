// Track network: a graph of nodes joined by smooth curved edges, plus routing.
import * as THREE from 'three';
import { G, newId, spend } from './state.js';
import * as W from './world.js';
import { mat } from './models.js';
import { clamp, smoothstep } from './noise.js';

export const TRACK_COST = 420, BRIDGE_COST = 1500, MIN_RADIUS = 11, MAX_GRADE = 0.10, RULING_GRADE = 0.045;
const STEP = 1.0;

// ---------------- graph ----------------
export function createNode(x, y, z, axis = null) {
  const n = { id: newId(), x, y, z, axis, edges: new Set(), station: null };
  G.nodes.set(n.id, n);
  return n;
}
const norm = (x, z) => { const l = Math.hypot(x, z) || 1; return { x: x / l, z: z / l }; };
export function leaveDir(e, n) {
  const p = e.pts, k = Math.min(3, p.length - 1);
  if (e.a === n.id) return norm(p[k].x - p[0].x, p[k].z - p[0].z);
  const L = p.length - 1;
  return norm(p[L - k].x - p[L].x, p[L - k].z - p[L].z);
}

// ---------------- snapping ----------------
export function nearestNode(x, z, r) {
  let best = null, bd = r;
  for (const n of G.nodes.values()) { const d = Math.hypot(n.x - x, n.z - z); if (d < bd) { bd = d; best = n; } }
  return best;
}
export function nearestEdgePoint(x, z, r) {
  let best = null, bd = r;
  for (const e of G.edges.values()) {
    const p = e.pts;
    for (let i = 0; i < p.length; i++) {
      const d = Math.hypot(p[i].x - x, p[i].z - z);
      if (d < bd) { bd = d; best = { edge: e, idx: i, d }; }
    }
  }
  return best;
}
export function snapRef(x, z, { stations = true, toward = null } = {}) {
  if (stations) for (const st of G.stations.values()) {
    if (Math.hypot(st.node.x - x, st.node.z - z) >= 7) continue;
    // clicking a station means its nearest open track end, if it has one
    let n = st.node, bd = Infinity;
    for (const e of st.node.edges) {
      const o = G.nodes.get(e.a === st.node.id ? e.b : e.a);
      const d = toward ? Math.hypot(o.x - toward.x, o.z - toward.z) : Math.hypot(o.x - x, o.z - z);
      if (o.edges.size === 1 && d < bd) { bd = d; n = o; }
    }
    return { kind: 'node', node: n, x: n.x, z: n.z, y: n.y };
  }
  const n = nearestNode(x, z, 4.5);
  if (n) return { kind: 'node', node: n, x: n.x, z: n.z, y: n.y };
  const ep = nearestEdgePoint(x, z, 3.5);
  if (ep && ep.idx > 4 && ep.idx < ep.edge.pts.length - 5) {
    const p = ep.edge.pts[ep.idx];
    return { kind: 'edge', edge: ep.edge, idx: ep.idx, x: p.x, z: p.z, y: p.y };
  }
  const g = W.heightAt(x, z);
  return { kind: 'free', x, z, y: Math.max(g, W.WATER + 1.8), ground: g };
}
// The direction a new edge must have at a ref, as a direction of travel from a to b.
// At the end of a track the new piece has to carry straight on out of it.
function refTangent(ref, chord, isEnd) {
  let ax = null;
  if (ref.kind === 'node' && ref.node.edges.size === 1) {
    const ld = leaveDir([...ref.node.edges][0], ref.node);
    return isEnd ? ld : { x: -ld.x, z: -ld.z };
  }
  if (ref.kind === 'node' && ref.node.axis) ax = ref.node.axis;
  if (ref.kind === 'edge') {
    const p = ref.edge.pts, i = ref.idx;
    ax = norm(p[i + 2].x - p[i - 2].x, p[i + 2].z - p[i - 2].z);
  }
  if (!ax) return null;
  const s = ax.x * chord.x + ax.z * chord.z >= 0 ? 1 : -1;
  return { x: ax.x * s, z: ax.z * s };
}

// ---------------- planning a new edge ----------------
function resample(raw, step) {
  const cum = [0];
  for (let i = 1; i < raw.length; i++) cum.push(cum[i - 1] + Math.hypot(raw[i].x - raw[i - 1].x, raw[i].z - raw[i - 1].z));
  const total = cum[cum.length - 1], n = Math.max(2, Math.round(total / step)), out = [];
  let j = 0;
  for (let k = 0; k <= n; k++) {
    const s = total * k / n;
    while (j < raw.length - 2 && cum[j + 1] < s) j++;
    const t = (s - cum[j]) / Math.max(1e-6, cum[j + 1] - cum[j]);
    out.push({ x: raw[j].x + (raw[j + 1].x - raw[j].x) * t, z: raw[j].z + (raw[j + 1].z - raw[j].z) * t, y: 0 });
  }
  return { pts: out, len: total };
}

export function planEdge(a, b) {
  const L = Math.hypot(b.x - a.x, b.z - a.z);
  if (L < 5) return { valid: false, reason: 'Too short', pts: [] };
  if (a.kind === 'node' && b.kind === 'node' && a.node === b.node) return { valid: false, reason: 'Same point', pts: [] };
  const chord = { x: (b.x - a.x) / L, z: (b.z - a.z) / L };
  let t0 = refTangent(a, chord, false), t1 = refTangent(b, chord, true);
  const reflect = (t) => { const d = t.x * chord.x + t.z * chord.z; return { x: 2 * d * chord.x - t.x, z: 2 * d * chord.z - t.z }; };
  if (!t0 && !t1) t0 = t1 = chord;
  else if (!t0) t0 = reflect(t1);
  else if (!t1) t1 = reflect(t0);
  const theta = Math.min(Math.acos(clamp(t0.x * t1.x + t0.z * t1.z, -1, 1)), 2.9);
  const m = theta < 0.05 ? L : 2 * L * Math.tan(theta / 4) / Math.sin(theta / 2);
  const raw = [], N = Math.max(16, Math.ceil(L * 2));
  for (let k = 0; k <= N; k++) {
    const t = k / N, t2 = t * t, t3 = t2 * t;
    const h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t, h01 = -2 * t3 + 3 * t2, h11 = t3 - t2;
    raw.push({ x: h00 * a.x + h10 * m * t0.x + h01 * b.x + h11 * m * t1.x, z: h00 * a.z + h10 * m * t0.z + h01 * b.z + h11 * m * t1.z });
  }
  const { pts, len } = resample(raw, STEP);
  const n = pts.length;
  const plan = { pts, len, valid: true, reason: '', a, b };

  // tightest curve
  let minR = Infinity;
  for (let i = 2; i < n - 2; i++) {
    const d1 = norm(pts[i].x - pts[i - 2].x, pts[i].z - pts[i - 2].z), d2 = norm(pts[i + 2].x - pts[i].x, pts[i + 2].z - pts[i].z);
    const ang = Math.acos(clamp(d1.x * d2.x + d1.z * d2.z, -1, 1));
    if (ang > 1e-4) minR = Math.min(minR, (2 * len / (n - 1)) / ang);
  }
  plan.minR = minR;

  // height profile: follow the ground, smoothed, pinned to both ends
  const ter = new Float32Array(n), y = new Float32Array(n);
  for (let i = 0; i < n; i++) { ter[i] = W.heightAt(pts[i].x, pts[i].z); y[i] = Math.max(ter[i], W.WATER + 1.8); }
  const tmp = new Float32Array(n), R = clamp(Math.round(n / 8), 4, 14);
  for (let pass = 0; pass < 3; pass++) {
    for (let i = 0; i < n; i++) {
      let s = 0, c = 0;
      for (let k = -R; k <= R; k++) { s += y[clamp(i + k, 0, n - 1)]; c++; }
      tmp[i] = s / c;
    }
    y.set(tmp);
  }
  const ya = a.y ?? y[0], yb = b.y ?? y[n - 1], d0 = ya - y[0], d1 = yb - y[n - 1];
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    y[i] += d0 + (d1 - d0) * t;
    if (ter[i] < W.WATER + 0.5) y[i] = Math.max(y[i], W.WATER + 1.6);
  }
  // limit the grade like a surveyor would: cut through rises, fill dips, ends stay put
  const gs = Math.max(RULING_GRADE * len / (n - 1), Math.abs(yb - ya) / (n - 1) * 1.08);
  y[0] = ya; y[n - 1] = yb;
  for (let i = 1; i < n - 1; i++) y[i] = clamp(y[i], y[i - 1] - gs, y[i - 1] + gs);
  for (let i = n - 2; i > 0; i--) y[i] = clamp(y[i], y[i + 1] - gs, y[i + 1] + gs);
  // round off the vertical curves
  for (let pass = 0; pass < 2; pass++) {
    for (let i = 1; i < n - 1; i++) { let s = 0, c = 0; for (let k = -3; k <= 3; k++) { s += y[clamp(i + k, 0, n - 1)]; c++; } tmp[i] = s / c; }
    for (let i = 1; i < n - 1; i++) y[i] = tmp[i];
  }
  let earth = 0;
  for (let i = 0; i < n; i++) {
    if (ter[i] < W.WATER + 0.5) y[i] = Math.max(y[i], W.WATER + 1.6);
    pts[i].y = y[i];
    earth += Math.min(6, Math.abs(y[i] - ter[i]));
  }
  let maxG = 0, sumG = 0, bridge = 0;
  for (let i = 0; i < n; i++) {
    const g = Math.abs(y[Math.min(n - 1, i + 3)] - y[Math.max(0, i - 3)]) / (Math.min(n - 1, i + 3) - Math.max(0, i - 3)) / (len / (n - 1));
    maxG = Math.max(maxG, g); sumG += g;
    if (y[i] - ter[i] > 4 || ter[i] < W.WATER + 0.3) bridge += len / (n - 1);
  }
  plan.maxGrade = maxG; plan.bridge = bridge;

  // obstacles
  let demolish = 0;
  for (let i = 0; i < n && plan.valid; i += 2) {
    const p = pts[i];
    if (!W.inMap(p.x, p.z, 4)) { plan.valid = false; plan.reason = 'Off the map'; }
    for (const ind of G.industries) if (Math.hypot(ind.x - p.x, ind.z - p.z) < 10) { plan.valid = false; plan.reason = `Blocked by ${ind.name}`; }
    for (const st of G.stations.values()) {
      if ((a.node && a.node.station === st) || (b.node && b.node.station === st)) continue;
      if (Math.hypot(st.node.x - p.x, st.node.z - p.z) < 5) { plan.valid = false; plan.reason = `Runs into ${st.name}`; }
    }
    for (const c of G.cities) if (Math.hypot(c.x - p.x, c.z - p.z) < 9) { plan.valid = false; plan.reason = `Blocked by ${c.name} town hall`; }
  }
  if (plan.valid) for (let i = 0; i < n; i += 3) demolish += W.countBuildingsNear(pts[i].x, pts[i].z, 3.5);
  plan.demolish = demolish;
  if (plan.valid && minR < MIN_RADIUS) { plan.valid = false; plan.reason = 'Curve too sharp'; }
  if (plan.valid && maxG > MAX_GRADE) { plan.valid = false; plan.reason = `Too steep (${(maxG * 100).toFixed(1)}%)`; }
  plan.cost = Math.round(len * TRACK_COST * (1 + (sumG / n) * 8) + bridge * BRIDGE_COST + earth * 60 + demolish * 1500);
  return plan;
}

// ---------------- building ----------------
function resolveRef(ref, yHint) {
  if (ref.kind === 'node' && G.nodes.has(ref.node.id)) return ref.node;
  if (ref.kind === 'edge' || ref.kind === 'node') {
    const n = nearestNode(ref.x, ref.z, 0.6); if (n) return n;
    const ep = nearestEdgePoint(ref.x, ref.z, 0.8);
    if (ep && ep.idx > 1 && ep.idx < ep.edge.pts.length - 2) return splitEdge(ep.edge, ep.idx);
  }
  return createNode(ref.x, yHint, ref.z, null);
}

export function buildEdge(plan) {
  const pts = plan.pts, n = pts.length;
  const A = resolveRef(plan.a, pts[0].y), B = resolveRef(plan.b, pts[n - 1].y);
  if (A === B) return null;
  pts[0] = { x: A.x, y: A.y, z: A.z }; pts[n - 1] = { x: B.x, y: B.y, z: B.z };
  if (!A.axis) A.axis = norm(pts[2].x - pts[0].x, pts[2].z - pts[0].z);
  if (!B.axis) B.axis = norm(pts[n - 1].x - pts[n - 3].x, pts[n - 1].z - pts[n - 3].z);
  spend(plan.cost);
  return addEdge(A, B, pts, plan.cost, true);
}

export function addEdge(A, B, pts, cost, terraform) {
  const e = { id: newId(), kind: 'edge', a: A.id, b: B.id, pts, cost, len: 0 };
  for (let i = 1; i < pts.length; i++) e.len += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z);
  G.edges.set(e.id, e); A.edges.add(e); B.edges.add(e);
  if (terraform) {
    W.carve(pts, { bed: true });
    for (let i = 0; i < pts.length; i += 2) {
      const g = W.heightAt(pts[i].x, pts[i].z);
      W.removeTrees(pts[i].x, pts[i].z, 3.5 + Math.min(6, Math.abs(pts[i].y - g)));
      W.demolishNear(pts[i].x, pts[i].z, 3.5);
    }
  }
  buildEdgeMesh(e);
  return e;
}

export function splitEdge(e, idx) {
  const p = e.pts, P = p[idx];
  const n = createNode(P.x, P.y, P.z, norm(p[idx + 1].x - p[idx - 1].x, p[idx + 1].z - p[idx - 1].z));
  const A = G.nodes.get(e.a), B = G.nodes.get(e.b);
  removeEdgeRaw(e);
  addEdge(A, n, p.slice(0, idx + 1), e.cost * idx / p.length, false);
  addEdge(n, B, p.slice(idx), e.cost * (1 - idx / p.length), false);
  return n;
}

function removeEdgeRaw(e) {
  G.edges.delete(e.id);
  G.nodes.get(e.a)?.edges.delete(e); G.nodes.get(e.b)?.edges.delete(e);
  if (e.group) { G.scene.remove(e.group); e.group.traverse(o => { if (o.geometry) o.geometry.dispose(); }); }
}
export function removeEdge(e) {
  removeEdgeRaw(e);
  for (const id of [e.a, e.b]) {
    const n = G.nodes.get(id);
    if (n && n.edges.size === 0 && !n.station) G.nodes.delete(id);
  }
  G.cash += e.cost * 0.4;
  G.assetValue = Math.max(0, G.assetValue - e.cost * 0.6);
}

// ---------------- meshes ----------------
let ballastMat, railMat, sleeperMat, pierMat, previewMats;
function gravelTexture() {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const x = c.getContext('2d');
  x.fillStyle = '#857a6c'; x.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 2600; i++) {
    const v = 90 + Math.random() * 110 | 0;
    x.fillStyle = `rgb(${v},${v * 0.95 | 0},${v * 0.88 | 0})`;
    x.fillRect(Math.random() * 128, Math.random() * 128, 1 + Math.random() * 2.5, 1 + Math.random() * 2.5);
  }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}
function ensureMats() {
  if (ballastMat) return;
  ballastMat = new THREE.MeshStandardMaterial({ map: gravelTexture(), roughness: 1 });
  railMat = new THREE.MeshStandardMaterial({ color: 0xb8bcc2, metalness: 0.9, roughness: 0.32 });
  sleeperMat = new THREE.MeshStandardMaterial({ color: 0x4a3626, roughness: 0.9 });
  pierMat = mat(0x8d877d, { r: 0.95 });
  previewMats = { ok: new THREE.MeshBasicMaterial({ color: 0x7cf29a, transparent: true, opacity: 0.55, depthWrite: false }), bad: new THREE.MeshBasicMaterial({ color: 0xff5a4a, transparent: true, opacity: 0.55, depthWrite: false }) };
}

function frames(pts) {
  const n = pts.length, out = [];
  for (let i = 0; i < n; i++) {
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(n - 1, i + 1)];
    const t = norm(b.x - a.x, b.z - a.z);
    out.push({ t, s: { x: -t.z, z: t.x } });
  }
  return out;
}
// a strip with a fixed cross-section swept along pts. profile: [[side offset, height offset], ...]
function sweep(pts, fr, profile, vScale = 0.5) {
  const n = pts.length, k = profile.length, pos = [], uv = [], idx = [];
  let cum = 0;
  for (let i = 0; i < n; i++) {
    if (i) cum += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z);
    for (let j = 0; j < k; j++) {
      const [o, h] = profile[j];
      pos.push(pts[i].x + fr[i].s.x * o, pts[i].y + h, pts[i].z + fr[i].s.z * o);
      uv.push(j / (k - 1), cum * vScale);
    }
  }
  for (let i = 0; i < n - 1; i++) for (let j = 0; j < k - 1; j++) {
    const a = i * k + j, b = (i + 1) * k + j;
    idx.push(a, b, b + 1, a, b + 1, a + 1);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx); g.computeVertexNormals();
  return g;
}

export function trackMeshes(pts, opts = {}) {
  ensureMats();
  const g = new THREE.Group(), fr = frames(pts);
  const ballast = new THREE.Mesh(sweep(pts, fr, [[2.2, -0.45], [1.35, 0.25], [-1.35, 0.25], [-2.2, -0.45]], 0.25), ballastMat);
  ballast.receiveShadow = true; g.add(ballast);
  for (const side of [-0.62, 0.62]) {
    const r = new THREE.Mesh(sweep(pts, fr, [[side + 0.07, 0.38], [side + 0.05, 0.52], [side - 0.05, 0.52], [side - 0.07, 0.38]]), railMat);
    r.castShadow = true; g.add(r);
  }
  // sleepers
  let total = 0; const cum = [0];
  for (let i = 1; i < pts.length; i++) { total += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z); cum.push(total); }
  const count = Math.max(1, Math.floor(total / 0.9));
  const sl = new THREE.InstancedMesh(new THREE.BoxGeometry(2.35, 0.14, 0.38), sleeperMat, count);
  const o = new THREE.Object3D();
  let j = 0;
  for (let k = 0; k < count; k++) {
    const s = (k + 0.5) * total / count;
    while (j < pts.length - 2 && cum[j + 1] < s) j++;
    const t = (s - cum[j]) / Math.max(1e-6, cum[j + 1] - cum[j]), a = pts[j], b = pts[j + 1];
    o.position.set(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t + 0.32, a.z + (b.z - a.z) * t);
    o.lookAt(o.position.x + (b.x - a.x), o.position.y + (b.y - a.y), o.position.z + (b.z - a.z));
    o.updateMatrix(); sl.setMatrixAt(k, o.matrix);
  }
  sl.receiveShadow = true; sl.castShadow = true; g.add(sl);
  // bridge piers where the line flies over a valley or water
  if (!opts.noPiers) {
    let last = -99;
    for (let i = 0; i < pts.length; i++) {
      const p = pts[i], ground = W.heightAt(p.x, p.z);
      if ((p.y - ground > 3 || ground < W.WATER + 0.3) && cum[i] - last > 7) {
        last = cum[i];
        const bottom = ground - 1, h = p.y - 0.45 - bottom;
        if (h <= 0.5) continue;
        const pier = new THREE.Mesh(new THREE.BoxGeometry(3.4, h, 1.1), pierMat);
        pier.position.set(p.x, bottom + h / 2, p.z); pier.rotation.y = Math.atan2(fr[i].t.x, fr[i].t.z);
        pier.castShadow = pier.receiveShadow = true; g.add(pier);
      }
    }
    // side girders over bridged stretches
    let run = [];
    const flush = () => {
      if (run.length > 3) for (const side of [-1.9, 1.9]) {
        const m = new THREE.Mesh(sweep(run.map(i => pts[i]), run.map(i => fr[i]), [[side - 0.12, -0.9], [side - 0.12, 0.35], [side + 0.12, 0.35], [side + 0.12, -0.9]]), mat(0x3d3a36, { m: 0.6, r: 0.5 }));
        m.castShadow = true; g.add(m);
      }
      run = [];
    };
    for (let i = 0; i < pts.length; i++) {
      const ground = W.heightAt(pts[i].x, pts[i].z);
      if (pts[i].y - ground > 2.5 || ground < W.WATER + 0.3) run.push(i); else flush();
    }
    flush();
  }
  return g;
}
function buildEdgeMesh(e) {
  e.group = trackMeshes(e.pts);
  e.group.traverse(o => { o.userData.pick = e; });
  G.scene.add(e.group);
}

let preview = null;
export function showPreview(plan) {
  ensureMats();
  clearPreview();
  if (!plan || plan.pts.length < 2) return;
  const fr = frames(plan.pts);
  preview = new THREE.Mesh(sweep(plan.pts, fr, [[1.6, 0.7], [-1.6, 0.7]]), plan.valid ? previewMats.ok : previewMats.bad);
  preview.renderOrder = 5;
  G.scene.add(preview);
}
export function clearPreview() { if (preview) { G.scene.remove(preview); preview.geometry.dispose(); preview = null; } }

// highlight an edge (bulldoze hover)
let hl = null;
export function highlightEdge(e) {
  ensureMats();
  if (hl && hl.edge === e) return;
  if (hl) { G.scene.remove(hl.mesh); hl.mesh.geometry.dispose(); hl = null; }
  if (!e) return;
  const m = new THREE.Mesh(sweep(e.pts, frames(e.pts), [[1.8, 0.75], [-1.8, 0.75]]), previewMats.bad);
  G.scene.add(m); hl = { edge: e, mesh: m };
}

// ---------------- routing ----------------
// Dijkstra over (edge, direction) states. Trains can't take a switch backwards except at stations.
export function findPath(fromId, toId) {
  if (fromId === toId) return null;
  const S = G.nodes.get(fromId); if (!S) return null;
  const dist = new Map(), prev = new Map(), heap = [];
  const push = (k, d) => { heap.push([d, k]); let i = heap.length - 1; while (i > 0) { const p = (i - 1) >> 1; if (heap[p][0] <= heap[i][0]) break; [heap[p], heap[i]] = [heap[i], heap[p]]; i = p; } };
  const pop = () => { const top = heap[0], last = heap.pop(); if (heap.length) { heap[0] = last; let i = 0; for (;;) { const l = 2 * i + 1, r = l + 1; let m = i; if (l < heap.length && heap[l][0] < heap[m][0]) m = l; if (r < heap.length && heap[r][0] < heap[m][0]) m = r; if (m === i) break; [heap[m], heap[i]] = [heap[i], heap[m]]; i = m; } } return top; };
  const key = (e, fw) => e.id * 2 + (fw ? 1 : 0);
  const states = new Map();
  for (const e of S.edges) { const fw = e.a === fromId, k = key(e, fw); states.set(k, [e, fw]); dist.set(k, e.len); push(k, e.len); }
  while (heap.length) {
    const [d, k] = pop();
    if (d > dist.get(k)) continue;
    const [e, fw] = states.get(k), mId = fw ? e.b : e.a;
    if (mId === toId) {
      const list = []; let c = k;
      while (c !== undefined) { list.push(states.get(c)); c = prev.get(c); }
      return list.reverse();
    }
    const m = G.nodes.get(mId), arrive = leaveDir(e, m), isSt = !!m.station;
    for (const f of m.edges) {
      let extra = 0;
      if (f === e) { if (!isSt) continue; extra = 40; }
      else if (!isSt) { const ld = leaveDir(f, m); if (ld.x * arrive.x + ld.z * arrive.z > -0.3) continue; }
      else { const ld = leaveDir(f, m); if (ld.x * arrive.x + ld.z * arrive.z > -0.3) extra = 40; }
      const fw2 = f.a === mId, k2 = key(f, fw2), nd = d + f.len + extra;
      if (nd < (dist.get(k2) ?? Infinity)) { dist.set(k2, nd); prev.set(k2, k); states.set(k2, [f, fw2]); push(k2, nd); }
    }
  }
  return null;
}
export function pathPoints(list) {
  const out = [];
  for (const [e, fw] of list) {
    const p = fw ? e.pts : e.pts.slice().reverse();
    for (let i = out.length ? 1 : 0; i < p.length; i++) out.push(p[i]);
  }
  return out;
}
export function totalTrackLength() { let s = 0; for (const e of G.edges.values()) s += e.len; return s; }

// a straight piece of track between two points (station stubs)
export function straightPts(a, b) {
  const L = Math.hypot(b.x - a.x, b.z - a.z), n = Math.max(2, Math.round(L / STEP)), pts = [];
  for (let k = 0; k <= n; k++) { const t = k / n; pts.push({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t }); }
  return pts;
}
export function isBlocked(x, z, r) {
  for (const e of G.edges.values()) {
    const p = e.pts;
    for (let i = 0; i < p.length; i += 2) if (Math.abs(p[i].x - x) < r + 2 && Math.abs(p[i].z - z) < r + 2 && Math.hypot(p[i].x - x, p[i].z - z) < r + 1.5) return true;
  }
  for (const st of G.stations.values()) if (Math.hypot(st.bx - x, st.bz - z) < 10 + r) return true;
  return false;
}
