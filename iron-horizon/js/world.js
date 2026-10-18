// The land: heightmap, terrain mesh, water, forests, cities and industries.
import * as THREE from 'three';
import { G, newId } from './state.js';
import { makeNoise, mulberry32, smoothstep, lerp, clamp } from './noise.js';
import * as M from './models.js';

export const WORLD = 640, SEG = 320, CELL = WORLD / SEG, HALF = WORLD / 2, WATER = 0, VN = SEG + 1;
export const H = new Float32Array(VN * VN);
const lockH = new Uint8Array(VN * VN);
let terrainGeo, terrainMesh, colors;
export const vi = (c, r) => r * VN + c;

export function heightAt(x, z) {
  let fx = (x + HALF) / CELL, fz = (z + HALF) / CELL;
  fx = clamp(fx, 0, SEG - 1e-4); fz = clamp(fz, 0, SEG - 1e-4);
  const c = Math.floor(fx), r = Math.floor(fz), tx = fx - c, tz = fz - r;
  const ha = H[r * VN + c], hb = H[(r + 1) * VN + c], hc = H[(r + 1) * VN + c + 1], hd = H[r * VN + c + 1];
  if (tx + tz <= 1) return ha + (hd - ha) * tx + (hb - ha) * tz;
  return hc + (hb - hc) * (1 - tx) + (hd - hc) * (1 - tz);
}
export function slopeAt(x, z) {
  const dx = heightAt(x + 1.5, z) - heightAt(x - 1.5, z), dz = heightAt(x, z + 1.5) - heightAt(x, z - 1.5);
  return Math.hypot(dx, dz) / 3;
}
function roughness(x, z, r) {
  let lo = Infinity, hi = -Infinity;
  for (let a = 0; a < 12; a++) for (const rr of [r * 0.5, r]) {
    const h = heightAt(x + Math.cos(a * 0.5236) * rr, z + Math.sin(a * 0.5236) * rr);
    lo = Math.min(lo, h); hi = Math.max(hi, h);
  }
  return { lo, hi, d: hi - lo };
}
export const inMap = (x, z, m = 0) => Math.abs(x) < HALF - m && Math.abs(z) < HALF - m;

// ---------------- heightmap ----------------
function genHeights(nz) {
  for (let r = 0; r < VN; r++) for (let c = 0; c < VN; c++) {
    const x = -HALF + c * CELL, z = -HALF + r * CELL;
    let e = nz.fbm(x / 340 + 11, z / 340 - 7, 5) * 16 + 6;
    const mask = smoothstep(0.05, 0.5, nz.fbm(x / 420 - 3, z / 420 + 9, 3));
    let rid = 1 - Math.abs(nz.fbm(x / 150, z / 150, 4)); rid = rid * rid * rid;
    e += rid * mask * 62 + mask * 6;
    e += nz.fbm(x / 45, z / 45, 3) * (1.2 + mask * 3);
    // gentle valleys: squash the lowlands so there's room to build
    if (e > 1 && e < 14) e = 1 + (e - 1) * 0.7;
    // a coast along the west edge
    const coast = smoothstep(-130, -300, x + nz.n2(z / 160, 3.3) * 60);
    e = lerp(e, -14, coast);
    // the whole map is a land mass in the sea: every border dips under the water
    const edge = Math.max(Math.abs(x), Math.abs(z)) + nz.n2(x / 90 + 5, z / 90) * 14;
    e = lerp(e, -12, smoothstep(HALF - 70, HALF - 8, edge));
    H[r * VN + c] = e;
  }
}

function flatten(x, z, r, target, soft = 6) {
  const c0 = Math.max(0, Math.floor((x - r - soft + HALF) / CELL)), c1 = Math.min(SEG, Math.ceil((x + r + soft + HALF) / CELL));
  const r0 = Math.max(0, Math.floor((z - r - soft + HALF) / CELL)), r1 = Math.min(SEG, Math.ceil((z + r + soft + HALF) / CELL));
  for (let rr = r0; rr <= r1; rr++) for (let cc = c0; cc <= c1; cc++) {
    const px = -HALF + cc * CELL, pz = -HALF + rr * CELL, d = Math.hypot(px - x, pz - z);
    const w = 1 - smoothstep(r, r + soft, d);
    if (w > 0) { const i = rr * VN + cc; H[i] = lerp(H[i], target, w); }
  }
}

// ---------------- terrain colours ----------------
const C = (hex) => new THREE.Color(hex);
const PAL = {
  sand: C(0xcdb98a), mud: C(0x6f6447), grassA: C(0x5d8a3a), grassB: C(0x7c9a45), dry: C(0x9a9a5a),
  rock: C(0x7d7468), rockD: C(0x5c564f), snow: C(0xf2f4f6), dirt: C(0x8b7353), road: C(0x9c8a6c),
};
const tmp = new THREE.Color();
function baseColor(i, nz) {
  const c = i % VN, r = Math.floor(i / VN), x = -HALF + c * CELL, z = -HALF + r * CELL, h = H[i];
  const s = slopeAt(x, z), n = nz.n2(x / 18, z / 18) * 0.5 + 0.5, n2 = nz.n2(x / 70 + 9, z / 70) * 0.5 + 0.5;
  if (h < WATER - 0.5) return tmp.copy(PAL.mud).lerp(PAL.sand, clamp((h + 6) / 6, 0, 1));
  if (h < WATER + 1.0) return tmp.copy(PAL.sand);
  tmp.copy(PAL.grassA).lerp(PAL.grassB, n * 0.8).lerp(PAL.dry, n2 * 0.35 + smoothstep(14, 40, h) * 0.4);
  if (h < WATER + 1.8) tmp.lerp(PAL.sand, 1 - (h - WATER - 1.0) / 0.8);
  const rock = smoothstep(0.55, 0.95, s) + smoothstep(38, 52, h) * 0.6;
  if (rock > 0) tmp.lerp(n > 0.5 ? PAL.rock : PAL.rockD, clamp(rock, 0, 1));
  const snow = smoothstep(56, 64, h + n * 4) * (1 - smoothstep(0.7, 1.1, s));
  if (snow > 0) tmp.lerp(PAL.snow, snow);
  return tmp;
}
function paint(i, col, w) {
  if (w <= 0) return;
  const a = colors.array;
  a[i * 3] = lerp(a[i * 3], col.r, w); a[i * 3 + 1] = lerp(a[i * 3 + 1], col.g, w); a[i * 3 + 2] = lerp(a[i * 3 + 2], col.b, w);
}
function paintDisc(x, z, r, col, w0 = 1) {
  const c0 = Math.max(0, Math.floor((x - r + HALF) / CELL)), c1 = Math.min(SEG, Math.ceil((x + r + HALF) / CELL));
  const r0 = Math.max(0, Math.floor((z - r + HALF) / CELL)), r1 = Math.min(SEG, Math.ceil((z + r + HALF) / CELL));
  for (let rr = r0; rr <= r1; rr++) for (let cc = c0; cc <= c1; cc++) {
    const d = Math.hypot(-HALF + cc * CELL - x, -HALF + rr * CELL - z);
    if (d < r) paint(rr * VN + cc, col, w0 * (1 - smoothstep(r * 0.55, r, d)));
  }
}

function detailTexture(rnd) {
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const x = c.getContext('2d'), img = x.createImageData(256, 256);
  for (let i = 0; i < 256 * 256; i++) {
    const v = 205 + rnd() * 50;
    img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = v; img.data[i * 4 + 3] = 255;
  }
  x.putImageData(img, 0, 0);
  x.globalAlpha = 0.25;
  for (let k = 0; k < 900; k++) { x.fillStyle = rnd() < 0.5 ? '#fff' : '#999'; x.fillRect(rnd() * 256, rnd() * 256, 1 + rnd() * 3, 1 + rnd() * 3); }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(90, 90); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}

function buildTerrain(nz, rnd) {
  terrainGeo = new THREE.PlaneGeometry(WORLD, WORLD, SEG, SEG);
  terrainGeo.rotateX(-Math.PI / 2);
  const pos = terrainGeo.attributes.position;
  for (let i = 0; i < VN * VN; i++) pos.setY(i, H[i]);
  const arr = new Float32Array(VN * VN * 3);
  colors = new THREE.BufferAttribute(arr, 3);
  for (let i = 0; i < VN * VN; i++) { const c = baseColor(i, nz); arr[i * 3] = c.r; arr[i * 3 + 1] = c.g; arr[i * 3 + 2] = c.b; }
  terrainGeo.setAttribute('color', colors);
  terrainGeo.computeVertexNormals();
  terrainMesh = new THREE.Mesh(terrainGeo, new THREE.MeshStandardMaterial({ vertexColors: true, map: detailTexture(rnd), roughness: 0.95, metalness: 0 }));
  terrainMesh.receiveShadow = true; terrainMesh.castShadow = true;
  G.scene.add(terrainMesh);
  // a skirt so the map edge doesn't look like paper
  const skirt = new THREE.Mesh(new THREE.PlaneGeometry(WORLD * 8, WORLD * 8), new THREE.MeshStandardMaterial({ color: 0x4a5a4a, roughness: 1 }));
  skirt.rotation.x = -Math.PI / 2; skirt.position.y = -12.5; G.scene.add(skirt);
}
function refreshTerrain(colorsToo = true) {
  const pos = terrainGeo.attributes.position;
  for (let i = 0; i < VN * VN; i++) pos.array[i * 3 + 1] = H[i];
  pos.needsUpdate = true;
  terrainGeo.computeVertexNormals();
  if (colorsToo) colors.needsUpdate = true;
}

// Cut and fill the ground so it meets a track (or station) bed. pts: [{x,y,z}]
export function carve(pts, opts = {}) {
  const best = new Map();
  for (let k = 0; k < pts.length; k++) {
    const p = pts[k], ground = heightAt(p.x, p.z);
    if (ground < WATER + 0.3) continue;
    const target = p.y - (opts.drop ?? 0.3), diff = target - ground;
    if (diff > 5) continue;                                   // bridge: leave the valley alone
    const inner = opts.inner ?? 2.6, R = inner + 1.5 + Math.min(Math.abs(diff) * 1.7, 11);
    const c0 = Math.max(0, Math.floor((p.x - R + HALF) / CELL)), c1 = Math.min(SEG, Math.ceil((p.x + R + HALF) / CELL));
    const r0 = Math.max(0, Math.floor((p.z - R + HALF) / CELL)), r1 = Math.min(SEG, Math.ceil((p.z + R + HALF) / CELL));
    for (let rr = r0; rr <= r1; rr++) for (let cc = c0; cc <= c1; cc++) {
      const d = Math.hypot(-HALF + cc * CELL - p.x, -HALF + rr * CELL - p.z);
      if (d > R) continue;
      const w = d < inner ? 1 : 1 - smoothstep(inner, R, d);
      const i = rr * VN + cc, b = best.get(i);
      if (!b || w > b[0]) best.set(i, [w, target]);
    }
  }
  for (const [i, [w, t]] of best) {
    if (H[i] < WATER + 0.2) continue;
    if (lockH[i] && w < 0.99) continue;
    const before = H[i];
    H[i] = lerp(H[i], t, w);
    if (w > 0.8) lockH[i] = 1;
    const delta = Math.abs(H[i] - before);
    if (delta > 0.25) paint(i, PAL.dirt, Math.min(0.75, delta * 0.35) * w);
    else if (opts.bed && w > 0.9) paint(i, PAL.dirt, 0.35);
  }
  refreshTerrain();
}

// ---------------- water ----------------
// a tiling normal map made from a sum of periodic waves
function waterNormals() {
  const N = 256, hgt = new Float32Array(N * N), rnd = mulberry32(99);
  const waves = [];
  for (let k = 0; k < 28; k++) waves.push({ fx: Math.round((rnd() - 0.5) * 18), fy: Math.round((rnd() - 0.5) * 18), ph: rnd() * 6.28, a: 1 / (1 + k * 0.25) });
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    let h = 0;
    for (const w of waves) h += w.a * Math.sin((w.fx * x + w.fy * y) / N * Math.PI * 2 + w.ph);
    hgt[y * N + x] = h;
  }
  const c = document.createElement('canvas'); c.width = c.height = N;
  const ctx2 = c.getContext('2d'), img = ctx2.createImageData(N, N);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const dx = hgt[y * N + ((x + 1) % N)] - hgt[y * N + ((x + N - 1) % N)];
    const dy = hgt[((y + 1) % N) * N + x] - hgt[((y + N - 1) % N) * N + x];
    const nx = -dx * 0.35, ny = -dy * 0.35, nz = 1, l = Math.hypot(nx, ny, nz), i = (y * N + x) * 4;
    img.data[i] = (nx / l * 0.5 + 0.5) * 255; img.data[i + 1] = (ny / l * 0.5 + 0.5) * 255; img.data[i + 2] = (nz / l * 0.5 + 0.5) * 255; img.data[i + 3] = 255;
  }
  ctx2.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}
// Water over the map is tinted by depth (turquoise shallows, deep blue sea) and
// reflects the sky; a ring of open sea runs out to the horizon around it.
const SHALLOW = new THREE.Color(0x46c2b4), MID = new THREE.Color(0x1c7f95), DEEP = new THREE.Color(0x0b3d5e);
export function buildWater() {
  const normals = waterNormals();
  normals.repeat.set(60, 60);
  const material = new THREE.MeshStandardMaterial({
    vertexColors: true, transparent: true, roughness: 0.06, metalness: 0.0, normalMap: normals,
    normalScale: new THREE.Vector2(0.35, 0.35), envMapIntensity: 1.1, depthWrite: false,
  });
  G.waterMats = [material];
  const S2 = 160, geo = new THREE.PlaneGeometry(WORLD, WORLD, S2, S2);
  geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position, col = new Float32Array(pos.count * 4), c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const depth = WATER - heightAt(pos.getX(i), pos.getZ(i));
    c.copy(SHALLOW).lerp(MID, smoothstep(0, 4, depth)).lerp(DEEP, smoothstep(4, 12, depth));
    col[i * 4] = c.r; col[i * 4 + 1] = c.g; col[i * 4 + 2] = c.b;
    col[i * 4 + 3] = depth < -1 ? 0 : 0.45 + smoothstep(-0.5, 6, depth) * 0.5;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 4));
  const inner = new THREE.Mesh(geo, material);
  inner.position.y = WATER; inner.renderOrder = 1;
  // the open sea: a big square with the map cut out of it
  const shape = new THREE.Shape([new THREE.Vector2(-WORLD * 5, -WORLD * 5), new THREE.Vector2(WORLD * 5, -WORLD * 5), new THREE.Vector2(WORLD * 5, WORLD * 5), new THREE.Vector2(-WORLD * 5, WORLD * 5)]);
  shape.holes.push(new THREE.Path([new THREE.Vector2(-HALF, -HALF), new THREE.Vector2(-HALF, HALF), new THREE.Vector2(HALF, HALF), new THREE.Vector2(HALF, -HALF)]));
  const sg = new THREE.ShapeGeometry(shape); sg.rotateX(-Math.PI / 2);
  const sc = new Float32Array(sg.attributes.position.count * 4);
  for (let i = 0; i < sg.attributes.position.count; i++) { sc[i * 4] = DEEP.r; sc[i * 4 + 1] = DEEP.g; sc[i * 4 + 2] = DEEP.b; sc[i * 4 + 3] = 0.95; }
  sg.setAttribute('color', new THREE.BufferAttribute(sc, 4));
  const outer = new THREE.Mesh(sg, material);
  outer.position.y = WATER;
  const w = new THREE.Group(); w.add(inner, outer);
  w.receiveShadow = true; inner.receiveShadow = true;
  G.scene.add(w); G.water = w;
}
export function tickWater(t) {
  const m = G.waterMats?.[0]; if (!m) return;
  m.normalMap.offset.set(t * 0.004, t * 0.0025);
}

// ---------------- trees ----------------
const trees = { meshes: [], grid: new Map(), list: [] };
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
function forestAt(nz, x, z) { return nz.fbm(x / 110 + 40, z / 110 - 20, 4) + 0.18 * nz.n2(x / 22, z / 22); }
function buildTrees(nz, rnd, avoid) {
  const cand = [];
  for (let z = -HALF + 4; z < HALF - 4; z += 3.4) for (let x = -HALF + 4; x < HALF - 4; x += 3.4) {
    const px = x + (rnd() - 0.5) * 3, pz = z + (rnd() - 0.5) * 3, h = heightAt(px, pz);
    if (h < WATER + 1.4 || h > 54) continue;
    const s = slopeAt(px, pz); if (s > 1.1) continue;
    const f = forestAt(nz, px, pz);
    const p = f > 0.12 ? 0.85 : f > 0.0 ? 0.25 : 0.025;
    if (rnd() > p) continue;
    if (avoid(px, pz)) continue;
    const conifer = h > 20 ? rnd() < 0.9 : rnd() < 0.35;
    cand.push({ x: px, z: pz, y: h, conifer, s: 0.75 + rnd() * 0.7, rot: rnd() * 6.28, tint: rnd() });
  }
  const geos = [M.coniferGeometry(), M.broadleafGeometry()];
  const material = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85, flatShading: true });
  const counts = [cand.filter(t => t.conifer).length, cand.filter(t => !t.conifer).length];
  const meshes = geos.map((g, k) => { const m = new THREE.InstancedMesh(g, material, Math.max(1, counts[k])); m.castShadow = true; m.receiveShadow = true; G.scene.add(m); return m; });
  const idx = [0, 0], mtx = new THREE.Matrix4(), q = new THREE.Quaternion(), col = new THREE.Color();
  for (const t of cand) {
    const k = t.conifer ? 0 : 1;
    q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), t.rot);
    mtx.compose(new THREE.Vector3(t.x, t.y - 0.2, t.z), q, new THREE.Vector3(t.s, t.s * (0.9 + t.tint * 0.3), t.s));
    meshes[k].setMatrixAt(idx[k], mtx);
    col.setHSL(k ? 0.22 + t.tint * 0.1 : 0.3 + t.tint * 0.06, 0.25 + t.tint * 0.2, 0.7 + t.tint * 0.4);
    meshes[k].setColorAt(idx[k], col);
    t.k = k; t.i = idx[k]++;
    const key = `${Math.floor(t.x / 10)},${Math.floor(t.z / 10)}`;
    if (!trees.grid.has(key)) trees.grid.set(key, []);
    trees.grid.get(key).push(t);
  }
  trees.meshes = meshes; trees.list = cand;
}
export function removeTrees(x, z, r) {
  let hit = false;
  for (let gx = Math.floor((x - r) / 10); gx <= Math.floor((x + r) / 10); gx++)
    for (let gz = Math.floor((z - r) / 10); gz <= Math.floor((z + r) / 10); gz++) {
      const cell = trees.grid.get(`${gx},${gz}`); if (!cell) continue;
      for (const t of cell) if (!t.gone && Math.hypot(t.x - x, t.z - z) < r) { t.gone = true; trees.meshes[t.k].setMatrixAt(t.i, ZERO); hit = true; }
    }
  if (hit) trees.meshes.forEach(m => { m.instanceMatrix.needsUpdate = true; });
}

// ---------------- cities ----------------
const CITY_NAMES = ['Ashford', 'Brennan Falls', 'Carver City', 'Dunmore', 'Elmstead', 'Fairhaven', 'Glenrock', 'Harlow',
  'Ironbridge', 'Juniper', 'Kingsley', 'Lowell Bay', 'Millbrook', 'Northgate', 'Oakridge', 'Pinecrest'];
const WALLS = [0xe9e1cf, 0xd9c9a8, 0xb5674c, 0x9c4a36, 0xcfc5b4, 0xa9b4bb, 0xe3d3b0, 0x8f5a44];
const ROOFS = [0x3b3f47, 0x5a2e25, 0x4b3a2f, 0x2f4a3f, 0x6b3a2a];
const bld = { walls: null, roofs: null, n: 0, grow: [] };
const MAX_BLD = 4000;

function setupBuildings() {
  const tex = M.windowTexture(); tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  const wallMat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.85 });
  // repeat the window pattern by each building's size instead of stretching it
  wallMat.onBeforeCompile = (sh) => {
    sh.vertexShader = sh.vertexShader.replace('#include <uv_vertex>', `#include <uv_vertex>
      #ifdef USE_INSTANCING
        vec3 isc = vec3(length(instanceMatrix[0].xyz), length(instanceMatrix[1].xyz), length(instanceMatrix[2].xyz));
        float iw = abs(normal.x) > 0.5 ? isc.z : isc.x;
        vMapUv *= vec2(max(1.0, floor(iw / 3.2 + 0.5)), max(1.0, floor(isc.y / 4.6 + 0.5)));
      #endif`);
  };
  bld.walls = new THREE.InstancedMesh(M.wallGeometry(), wallMat, MAX_BLD);
  bld.roofs = new THREE.InstancedMesh(M.PRISM, new THREE.MeshStandardMaterial({ roughness: 0.7, flatShading: true }), MAX_BLD);
  for (const m of [bld.walls, bld.roofs]) { m.count = 0; m.castShadow = m.receiveShadow = true; m.frustumCulled = false; G.scene.add(m); }
}

function makeCity(name, x, z, pop, rnd, nz) {
  const ang = rnd() * Math.PI, u = { x: Math.cos(ang), z: Math.sin(ang) }, v = { x: -u.z, z: u.x };
  const lots = [];
  const SP = 5.2;
  for (let i = -12; i <= 12; i++) for (let j = -12; j <= 12; j++) {
    if (i % 3 === 0 || j % 3 === 0) continue;               // streets
    const px = x + (i * u.x + j * v.x) * SP, pz = z + (i * u.z + j * v.z) * SP;
    const d = Math.hypot(px - x, pz - z) * (1 + nz.n2(px / 30, pz / 30) * 0.25);
    if (d > 70 || !inMap(px, pz, 10)) continue;
    const h = heightAt(px, pz);
    if (h < WATER + 0.8 || slopeAt(px, pz) > 0.45) continue;
    if (d < 10) continue;                                    // the square
    lots.push({ x: px, z: pz, d, rot: -ang, alive: false, gone: false });
  }
  lots.sort((a, b) => a.d - b.d);
  const city = { id: newId(), kind: 'city', name, x, z, ang, u, v, pop, growth: 0, lots, built: 0, delivered: {}, painted: 0 };
  const hall = M.makeTownHall();
  hall.position.set(x, heightAt(x, z) - 0.2, z); hall.rotation.y = -ang;
  hall.userData.pick = city;
  hall.traverse(o => { if (o.isMesh) { o.castShadow = o.receiveShadow = true; o.userData.pick = city; } });
  G.scene.add(hall); city.hall = hall;
  return city;
}

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _c = new THREE.Color(), UP = new THREE.Vector3(0, 1, 0);
function placeBuilding(city, lot, rank, animate) {
  const big = city.pop > 2500 && lot.d < 22 + city.pop / 400;
  const w = big ? 4.2 : 3 + ((rank * 7) % 5) * 0.2, d = big ? 4.2 : 3.2 + ((rank * 3) % 4) * 0.25;
  const hgt = big ? 5 + ((rank * 13) % 7) * (city.pop / 2500) : 2.4 + ((rank * 5) % 3) * 0.5;
  let y = Infinity;
  for (const [a, b] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) y = Math.min(y, heightAt(lot.x + a * w / 2, lot.z + b * d / 2));
  y -= 0.4;
  lot.i = bld.n++; lot.alive = true;
  lot.m = { w, d, h: hgt + 0.4, y, big };
  lot.wall = WALLS[(rank * 5 + Math.floor(lot.x)) % WALLS.length]; lot.roof = ROOFS[(rank * 3) % ROOFS.length];
  bld.walls.setColorAt(lot.i, _c.set(lot.wall));
  bld.roofs.setColorAt(lot.i, _c.set(lot.roof));
  setLotMatrix(lot, animate ? 0.01 : 1);
  if (animate) bld.grow.push({ lot, t: 0 });
  bld.walls.count = bld.roofs.count = bld.n;
  bld.walls.instanceColor.needsUpdate = bld.roofs.instanceColor.needsUpdate = true;
  removeTrees(lot.x, lot.z, 4);
}
function setLotMatrix(lot, k) {
  const { w, d, h, y, big } = lot.m;
  _q.setFromAxisAngle(UP, lot.rot);
  _m.compose(new THREE.Vector3(lot.x, y, lot.z), _q, new THREE.Vector3(w, h * k, d));
  bld.walls.setMatrixAt(lot.i, _m);
  if (big) _m.compose(new THREE.Vector3(lot.x, y + h * k, lot.z), _q, new THREE.Vector3(w * 0.9, 0.35 * k, d * 0.9));
  else _m.compose(new THREE.Vector3(lot.x, y + h * k, lot.z), _q, new THREE.Vector3(w * 1.12, 1.5 * k, d * 1.15));
  bld.roofs.setMatrixAt(lot.i, _m);
  bld.walls.instanceMatrix.needsUpdate = bld.roofs.instanceMatrix.needsUpdate = true;
}
export function demolishNear(x, z, r) {
  let n = 0;
  for (const city of G.cities) {
    if (Math.hypot(city.x - x, city.z - z) > 80) continue;
    for (const lot of city.lots) {
      if (lot.gone || Math.hypot(lot.x - x, lot.z - z) > r) continue;
      lot.gone = true;
      if (lot.alive) { lot.alive = false; bld.walls.setMatrixAt(lot.i, ZERO); bld.roofs.setMatrixAt(lot.i, ZERO); n++; city.pop = Math.max(200, city.pop - 25); }
    }
  }
  if (n) bld.walls.instanceMatrix.needsUpdate = bld.roofs.instanceMatrix.needsUpdate = true;
  return n;
}
export function countBuildingsNear(x, z, r) {
  let n = 0;
  for (const city of G.cities) {
    if (Math.hypot(city.x - x, city.z - z) > 80 + r) continue;
    for (const lot of city.lots) if (lot.alive && Math.hypot(lot.x - x, lot.z - z) < r) n++;
  }
  return n;
}
export function growCity(city, animate = true) {
  const target = Math.floor(city.pop / 38);
  let rank = city.built;
  for (const lot of city.lots) {
    if (city.built >= target || bld.n >= MAX_BLD) break;
    if (lot.alive || lot.gone) continue;
    if (G.blocked && G.blocked(lot.x, lot.z, 3.2)) { lot.gone = true; continue; }
    placeBuilding(city, lot, rank++, animate);
    city.built++;
  }
  paintRoads(city);
}
function paintRoads(city) {
  let far = 0;
  for (const lot of city.lots) if (lot.alive) far = Math.max(far, Math.hypot(lot.x - city.x, lot.z - city.z));
  far += 6;
  if (far <= city.painted + 2) return;
  city.painted = far;
  const SP = 5.2;
  paintDisc(city.x, city.z, 9, PAL.road, 0.8);
  for (let k = -12; k <= 12; k += 3) for (const [a, b] of [[city.u, city.v], [city.v, city.u]]) {
    for (let s = -70; s <= 70; s += 1.5) {
      const px = city.x + a.x * k * SP + b.x * s, pz = city.z + a.z * k * SP + b.z * s;
      if (Math.hypot(px - city.x, pz - city.z) > far) continue;
      const i = vi(clamp(Math.round((px + HALF) / CELL), 0, SEG), clamp(Math.round((pz + HALF) / CELL), 0, SEG));
      if (H[i] > WATER + 0.5) paint(i, PAL.road, 0.4);
    }
  }
  colors.needsUpdate = true;
}
export function tickBuildings(dt) {
  for (let k = bld.grow.length - 1; k >= 0; k--) {
    const g = bld.grow[k]; g.t += dt * 1.5;
    if (!g.lot.alive) { bld.grow.splice(k, 1); continue; }
    const e = Math.min(1, g.t), k2 = 1 - Math.pow(1 - e, 3);
    setLotMatrix(g.lot, Math.max(0.01, k2));
    if (e >= 1) bld.grow.splice(k, 1);
  }
}

// ---------------- industries ----------------
export const IND_TYPES = {
  coal: { name: 'Coal Mine', produces: 'coal', rate: 1.0, accepts: [] },
  iron: { name: 'Iron Mine', produces: 'ore', rate: 0.9, accepts: [] },
  lumber: { name: 'Lumber Camp', produces: 'lumber', rate: 1.0, accepts: [] },
  farm: { name: 'Farm', produces: 'grain', rate: 1.1, accepts: [] },
  steel: { name: 'Steel Mill', produces: 'steel', accepts: ['coal', 'ore'], base: 0.12 },
  factory: { name: 'Factory', produces: 'goods', accepts: ['steel', 'lumber'], base: 0.12 },
  food: { name: 'Food Plant', produces: 'food', accepts: ['grain'], base: 0.12 },
};
function nearestCity(x, z) {
  let best = null, bd = Infinity;
  for (const c of G.cities) { const d = Math.hypot(c.x - x, c.z - z); if (d < bd) { bd = d; best = c; } }
  return { city: best, d: bd };
}
export { nearestCity };

function siteOK(type, x, z, nz) {
  if (!inMap(x, z, 40)) return false;
  const h = heightAt(x, z); if (h < WATER + 2) return false;
  const ro = roughness(x, z, 11);
  if (ro.lo < WATER + 1.2) return false;
  const nc = nearestCity(x, z);
  for (const o of G.industries) if (Math.hypot(o.x - x, o.z - z) < 42) return false;
  const proc = type === 'steel' || type === 'factory' || type === 'food';
  if (nc.d < (proc ? 48 : 70)) return false;
  if (proc) return nc.d < 110 && ro.d < 7;
  if (type === 'coal' || type === 'iron') return h > 10 && h < 45 && ro.d < 14;
  if (type === 'lumber') return forestAt(nz, x, z) > 0.1 && h < 35 && ro.d < 9;
  if (type === 'farm') return h < 14 && ro.d < 3.5 && forestAt(nz, x, z) < 0.15;
  return true;
}

function placeIndustry(type, x, z, rnd) {
  const ro = roughness(x, z, 9);
  const y = clamp(heightAt(x, z), ro.lo + 0.5, ro.hi);
  flatten(x, z, type === 'farm' ? 9 : 10, y, 7);
  const ind = {
    id: newId(), kind: 'industry', type, def: IND_TYPES[type], x, z, y, rot: rnd() * Math.PI * 2,
    inp: 0, mult: 0.8 + rnd() * 0.5, produced: 0, producedLast: 0, stations: [], radius: 11,
  };
  ind.name = `${nearestCity(x, z).city.name} ${ind.def.name}`;
  G.industries.push(ind);
  return ind;
}
function dressIndustry(ind, rnd) {
  const { group, chimneys } = M.makeIndustry(ind.type);
  group.position.set(ind.x, ind.y - 0.15, ind.z); group.rotation.y = ind.rot;
  group.traverse(o => { o.userData.pick = ind; });
  G.scene.add(group);
  group.updateMatrixWorld(true);
  ind.group = group;
  ind.chimneys = chimneys.map(c => group.localToWorld(c.clone()));
  paintDisc(ind.x, ind.z, 12, PAL.dirt, 0.6);
  if (ind.type === 'farm') paintFields(ind, rnd);
}
function paintFields(ind, rnd) {
  const crops = [C(0xc9b45a), C(0x8fa84a), C(0x6b8e3a), C(0xb08a4a), C(0xd8c27a)];
  for (let f = 0; f < 5; f++) {
    const a = ind.rot + f * 1.25 + rnd() * 0.4, dist = 22 + rnd() * 8;
    const cx = ind.x + Math.cos(a) * dist, cz = ind.z + Math.sin(a) * dist;
    const fu = { x: Math.cos(ind.rot), z: Math.sin(ind.rot) }, fv = { x: -fu.z, z: fu.x };
    const col = crops[Math.floor(rnd() * crops.length)], col2 = col.clone().multiplyScalar(0.82);
    for (let s = -10; s <= 10; s += 1) for (let t = -7; t <= 7; t += 1) {
      const px = cx + fu.x * s + fv.x * t, pz = cz + fu.z * s + fv.z * t;
      if (!inMap(px, pz, 2) || heightAt(px, pz) < WATER + 1.2 || slopeAt(px, pz) > 0.3) continue;
      const i = vi(clamp(Math.round((px + HALF) / CELL), 0, SEG), clamp(Math.round((pz + HALF) / CELL), 0, SEG));
      paint(i, (Math.floor(s / 2) & 1) ? col : col2, 0.85);
    }
    (ind.fields ??= []).push({ x: cx, z: cz });
  }
}

// ---------------- generate everything ----------------
export function generate(seed) {
  G.seed = seed;
  const nz = makeNoise(seed), rnd = mulberry32(seed * 7 + 3);
  G.noise = nz; G.rnd = rnd;
  genHeights(nz);

  // cities
  const names = CITY_NAMES.slice().sort(() => rnd() - 0.5);
  for (let tries = 0; tries < 6000 && G.cities.length < 8; tries++) {
    const x = (rnd() - 0.5) * (WORLD - 120), z = (rnd() - 0.5) * (WORLD - 120);
    const h = heightAt(x, z);
    if (h < WATER + 1.5 || h > 16) continue;
    if (roughness(x, z, 26).d > (tries < 3000 ? 4 : 7)) continue;
    if (G.cities.some(c => Math.hypot(c.x - x, c.z - z) < 120)) continue;
    G.cities.push({ x, z, name: names[G.cities.length], pop: 0 });
  }
  for (const c of G.cities) flatten(c.x, c.z, 34, Math.max(WATER + 2.6, heightAt(c.x, c.z) * 0.6 + roughness(c.x, c.z, 30).lo * 0.4), 18);

  // industries
  const plan = [['coal', 4], ['iron', 3], ['lumber', 4], ['farm', 6], ['steel', 2], ['factory', 3], ['food', 2]];
  for (const [type, n] of plan) {
    let placed = 0;
    for (let tries = 0; tries < 4000 && placed < n; tries++) {
      const x = (rnd() - 0.5) * WORLD, z = (rnd() - 0.5) * WORLD;
      if (!siteOK(type, x, z, nz)) continue;
      placeIndustry(type, x, z, rnd); placed++;
    }
  }

  buildTerrain(nz, rnd);
  setupBuildings();
  const proto = G.cities.splice(0);
  for (const p of proto) {
    const big = proto.indexOf(p) < 2;
    G.cities.push(makeCity(p.name, p.x, p.z, Math.round(big ? 2600 + rnd() * 1200 : 700 + rnd() * 1300), rnd, nz));
  }
  for (const ind of G.industries) dressIndustry(ind, rnd);
  buildTrees(nz, rnd, (x, z) => {
    for (const c of G.cities) if (Math.hypot(c.x - x, c.z - z) < 30 + c.pop / 120) return true;
    for (const i of G.industries) {
      if (Math.hypot(i.x - x, i.z - z) < 21) return true;
      if (i.fields) for (const f of i.fields) if (Math.hypot(f.x - x, f.z - z) < 12) return true;
    }
    return false;
  });
  for (const c of G.cities) growCity(c, false);
  colors.needsUpdate = true;
}
