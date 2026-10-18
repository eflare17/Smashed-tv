// Procedural 3D models: locomotives, cars, industries, stations, houses, trees.
// Everything faces +Z and sits on y = 0 (rail top for rolling stock).
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const matCache = new Map();
export function mat(color, o = {}) {
  const key = color + '|' + JSON.stringify(o);
  let m = matCache.get(key);
  if (!m) {
    m = new THREE.MeshStandardMaterial({
      color, roughness: o.r ?? 0.7, metalness: o.m ?? 0, flatShading: !!o.flat,
      emissive: o.e ?? 0x000000, emissiveIntensity: o.ei ?? 1,
      transparent: !!o.t, opacity: o.op ?? 1, side: o.ds ? THREE.DoubleSide : THREE.FrontSide,
    });
    matCache.set(key, m);
  }
  return m;
}

function add(parent, geo, material, x = 0, y = 0, z = 0) {
  const m = new THREE.Mesh(geo, material);
  m.position.set(x, y, z);
  m.castShadow = true; m.receiveShadow = true;
  parent.add(m);
  return m;
}
const box = (p, w, h, d, m, x, y, z) => add(p, new THREE.BoxGeometry(w, h, d), m, x, y, z);
// cylinder lying along Z
function cylZ(p, r, len, m, x, y, z, seg = 16, r2 = r) {
  const g = new THREE.CylinderGeometry(r, r2, len, seg); g.rotateX(Math.PI / 2);
  return add(p, g, m, x, y, z);
}
// cylinder standing up
const cylY = (p, rt, rb, h, m, x, y, z, seg = 14) => add(p, new THREE.CylinderGeometry(rt, rb, h, seg), m, x, y + h / 2, z);
// wheel: axle along X
function wheel(p, r, m, x, y, z) {
  const g = new THREE.CylinderGeometry(r, r, 0.14, 18); g.rotateZ(Math.PI / 2);
  const w = add(p, g, m, x, y, z);
  // spokes so the turning shows
  const sp = new THREE.BoxGeometry(0.16, r * 1.7, 0.08);
  const s1 = new THREE.Mesh(sp, mat(0x111111)); s1.position.x = x > 0 ? 0.02 : -0.02; w.add(s1);
  const s2 = s1.clone(); s2.rotation.x = Math.PI / 2; w.add(s2);
  return w;
}

// prism (gable roof): base -0.5..0.5 in X and Z at y=0, ridge along X at y=1
export function prismGeometry() {
  const v = [
    -0.5, 0, -0.5, 0.5, 0, -0.5, 0.5, 1, 0, -0.5, 0, -0.5, 0.5, 1, 0, -0.5, 1, 0,     // back slope
    -0.5, 0, 0.5, -0.5, 1, 0, 0.5, 1, 0, -0.5, 0, 0.5, 0.5, 1, 0, 0.5, 0, 0.5,        // front slope
    -0.5, 0, -0.5, -0.5, 1, 0, -0.5, 0, 0.5,                                            // gable ends
    0.5, 0, -0.5, 0.5, 0, 0.5, 0.5, 1, 0,
  ];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(v, 3));
  g.computeVertexNormals();
  return g;
}
const PRISM = prismGeometry();
function roof(p, w, h, d, m, x, y, z, rotY = 0) {
  const r = add(p, PRISM, m, x, y, z); r.scale.set(w, h, d); r.rotation.y = rotY; return r;
}

// ---------------- rolling stock ----------------
export const RAIL_TOP = 0.52;

export function makeLoco(model) {
  if (model.kind === 'diesel' || model.kind === 'stream') return makeDiesel(model);
  const outer = new THREE.Group(), g = new THREE.Group(); outer.add(g);
  const [lead, drive, trail] = model.wheels;
  const main = mat(model.color, { r: 0.45, m: 0.35 }), dark = mat(0x1b1b1d, { r: 0.6, m: 0.4 });
  const trim = mat(model.trim, { r: 0.3, m: 0.85 }), red = mat(model.wheel ?? 0x7a1c16, { r: 0.5, m: 0.3 });
  const black = mat(0x0c0c0c, { r: 0.8 });
  const bl = 3.4 + drive * 0.18;             // boiler length grows with drivers
  box(g, 1.25, 0.35, bl + 2.4, dark, 0, 0.75, 0.3);
  box(g, 2.0, 0.07, bl + 0.6, dark, 0, 1.08, 0.7);
  cylZ(g, 0.62, bl, main, 0, 1.75, 0.9);
  for (let i = 0; i < 3; i++) {
    const t = new THREE.Mesh(new THREE.TorusGeometry(0.63, 0.035, 6, 24), trim);
    t.position.set(0, 1.75, 0.9 - bl / 2 + (i + 0.5) * bl / 3); g.add(t);
  }
  const front = 0.9 + bl / 2;
  cylZ(g, 0.67, 0.9, black, 0, 1.75, front + 0.45);
  cylZ(g, 0.5, 0.06, dark, 0, 1.75, front + 0.92);
  cylY(g, 0.2, 0.17, 0.95, black, 0, 2.3, front + 0.4);
  const stackTop = cylY(g, 0.36, 0.22, 0.32, black, 0, 3.22, front + 0.4);
  cylY(g, 0.28, 0.36, 0.4, trim, 0, 2.3, 1.0);
  const dome = new THREE.Mesh(new THREE.SphereGeometry(0.28, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), trim);
  dome.position.set(0, 2.7, 1.0); g.add(dome);
  cylY(g, 0.24, 0.3, 0.3, main, 0, 2.3, 0.1);
  // cab
  const cabZ = 0.9 - bl / 2 - 0.75;
  box(g, 1.95, 1.65, 1.5, main, 0, 2.0, cabZ);
  box(g, 1.97, 0.55, 0.5, mat(0x0f1418, { r: 0.2, m: 0.6 }), 0, 2.35, cabZ + 0.25);
  box(g, 2.25, 0.12, 1.95, dark, 0, 2.88, cabZ - 0.05);
  // headlamp (glows)
  box(g, 0.42, 0.42, 0.5, dark, 0, 2.55, front + 0.6);
  const lamp = box(g, 0.3, 0.3, 0.05, mat(0xfff1c4, { e: 0xffe2a0, ei: 2.5 }), 0, 2.55, front + 0.86);
  lamp.castShadow = false;
  // pilot (cowcatcher) and buffer beam
  const pilot = box(g, 1.7, 0.55, 0.75, mat(model.wheel ?? 0x7a1c16, { r: 0.6 }), 0, 0.42, front + 1.15);
  pilot.rotation.x = -0.65;
  box(g, 1.9, 0.3, 0.2, red, 0, 0.82, front + 0.85);
  // cylinders
  for (const sx of [-1, 1]) cylZ(g, 0.27, 0.95, dark, sx * 0.78, 0.92, front + 0.2, 12);
  // wheels
  const wheels = [], rods = [];
  const rd = drive >= 8 ? 0.46 : drive >= 6 ? 0.52 : 0.6;
  const z0 = cabZ + 0.75, z1 = front - 0.55;
  const span = (z1 - z0), gap = span / Math.max(1, drive / 2);
  const drivers = [];
  for (let i = 0; i < drive / 2; i++) drivers.push(z0 + gap * (i + 0.5));
  for (const sx of [-1, 1]) {
    for (const z of drivers) wheels.push({ m: wheel(g, rd, red, sx * 0.62, rd, z), r: rd });
    for (let i = 0; i < lead / 2; i++) wheels.push({ m: wheel(g, 0.3, dark, sx * 0.62, 0.3, front + 0.35 - i * 0.7), r: 0.3 });
    for (let i = 0; i < trail / 2; i++) wheels.push({ m: wheel(g, 0.36, dark, sx * 0.62, 0.36, cabZ - 0.1 - i * 0.75), r: 0.36 });
    if (drivers.length > 1) {
      const rod = box(g, 0.06, 0.1, drivers[drivers.length - 1] - drivers[0] + 0.2, trim, sx * 0.74, rd, (drivers[0] + drivers[drivers.length - 1]) / 2);
      rods.push({ m: rod, y: rd, z: rod.position.z, r: rd * 0.42 });
    }
  }
  const len = front + 1.5 - (cabZ - 0.95);
  const center = (front + 1.5 + cabZ - 0.95) / 2;
  g.position.z = -center;
  g.scale.setScalar(model.size ?? 1);
  stackTop.updateMatrix();
  return {
    group: outer, wheels, rods, len: len * (model.size ?? 1),
    smoke: new THREE.Vector3(0, 3.5, front + 0.4 - center).multiplyScalar(model.size ?? 1), lamp,
  };
}

export function makeTender(model) {
  const outer = new THREE.Group(), g = new THREE.Group(); outer.add(g);
  const main = mat(model.color, { r: 0.45, m: 0.35 }), dark = mat(0x1b1b1d, { r: 0.6, m: 0.4 });
  const trim = mat(model.trim, { r: 0.3, m: 0.85 });
  const L = 3.2 + (model.cars > 8 ? 1 : 0);
  box(g, 1.3, 0.3, L, dark, 0, 0.75, 0);
  box(g, 1.95, 1.3, L - 0.2, main, 0, 1.55, 0);
  box(g, 1.97, 0.1, L - 0.1, trim, 0, 1.95, 0);
  const coal = box(g, 1.7, 0.45, L * 0.62, mat(0x111111, { r: 1, flat: true }), 0, 2.35, 0.3);
  coal.scale.y = 1;
  const wheels = [];
  for (const sx of [-1, 1]) for (const z of [-L / 2 + 0.5, -L / 2 + 1.1, L / 2 - 1.1, L / 2 - 0.5])
    wheels.push({ m: wheel(g, 0.36, dark, sx * 0.62, 0.36, z), r: 0.36 });
  g.scale.setScalar(model.size ?? 1);
  return { group: outer, wheels, rods: [], len: L * (model.size ?? 1) };
}

function makeDiesel(model) {
  const outer = new THREE.Group(), g = new THREE.Group(); outer.add(g);
  const main = mat(model.color, { r: 0.35, m: model.kind === 'stream' ? 0.85 : 0.3 });
  const trim = mat(model.trim, { r: 0.4, m: 0.3 }), dark = mat(0x1b1b1d, { r: 0.6, m: 0.4 });
  const glass = mat(0x0b1015, { r: 0.1, m: 0.8 });
  const L = 7.6;
  box(g, 1.5, 0.4, L, dark, 0, 0.85, 0);
  box(g, 2.05, 1.85, L - 1.6, main, 0, 2.0, -0.8);
  const nose = new THREE.Mesh(new THREE.SphereGeometry(1.03, 20, 14, 0, Math.PI * 2, 0, Math.PI / 2), main);
  nose.rotation.x = Math.PI / 2; nose.scale.set(1, 1.5, 0.92); nose.position.set(0, 2.0, L / 2 - 1.6);
  nose.castShadow = true; g.add(nose);
  const ws = box(g, 1.6, 0.42, 0.6, glass, 0, 2.62, L / 2 - 1.45); ws.rotation.x = -0.5;
  for (const sx of [-1, 1]) {
    box(g, 0.04, 0.22, L - 1.4, trim, sx * 1.04, 1.5, -0.6);
    box(g, 0.04, 0.1, L - 1.6, trim, sx * 1.04, 2.45, -0.9);
  }
  if (model.kind === 'stream') for (let i = 0; i < 4; i++) for (const sx of [-1, 1]) box(g, 0.03, 0.05, L - 2, dark, sx * 1.04, 1.75 + i * 0.12, -1);
  const lamp = box(g, 0.32, 0.32, 0.06, mat(0xfff1c4, { e: 0xffe2a0, ei: 2.5 }), 0, 2.3, L / 2 - 0.15);
  lamp.castShadow = false;
  const wheels = [];
  for (const bz of [-L / 2 + 1.6, L / 2 - 1.8]) {
    box(g, 1.6, 0.5, 2.4, dark, 0, 0.5, bz);
    for (const sx of [-1, 1]) for (const dz of [-0.8, 0, 0.8]) wheels.push({ m: wheel(g, 0.36, dark, sx * 0.62, 0.36, bz + dz), r: 0.36 });
  }
  return { group: outer, wheels, rods: [], len: L, smoke: new THREE.Vector3(0, 3.0, 0.5), lamp, diesel: true };
}

const CAR_COLORS = {
  coach: 0x6b1f22, mail: 0x23412c, box: 0x7b3b22, reefer: 0xe8dfc8, grain: 0xb7a47a, hopper: 0x2b2b2e, flat: 0x5a4030,
};
export function makeCar(cargo) {
  const outer = new THREE.Group(), g = new THREE.Group(); outer.add(g);
  const dark = mat(0x1b1b1d, { r: 0.6, m: 0.4 });
  const kind = cargo.car, L = 5.0;
  const body = mat(CAR_COLORS[kind] ?? 0x666666, { r: 0.6, m: 0.15 });
  box(g, 1.5, 0.25, L, dark, 0, 0.85, 0);
  const wheels = [];
  for (const bz of [-1.75, 1.75]) {
    box(g, 1.3, 0.3, 1.4, dark, 0, 0.45, bz);
    for (const sx of [-1, 1]) for (const dz of [-0.42, 0.42]) wheels.push({ m: wheel(g, 0.32, dark, sx * 0.62, 0.32, bz + dz), r: 0.32 });
  }
  const roofM = mat(0x2a2a2c, { r: 0.7 });
  if (kind === 'coach' || kind === 'mail') {
    box(g, 1.9, 1.5, L, body, 0, 1.75, 0);
    if (kind === 'coach') box(g, 1.92, 0.42, L - 0.6, mat(0x2a2016, { e: 0xffc070, ei: 0.25, r: 0.2 }), 0, 2.05, 0);
    else for (const z of [-1.5, 1.5]) box(g, 1.92, 0.3, 0.5, mat(0x111a14, { r: 0.2 }), 0, 2.1, z);
    box(g, 1.92, 0.08, L - 0.2, mat(0xc9a55a, { m: 0.8, r: 0.3 }), 0, 1.55, 0);
    box(g, 2.05, 0.18, L + 0.1, roofM, 0, 2.58, 0);
    box(g, 1.3, 0.2, L - 0.4, roofM, 0, 2.75, 0);
  } else if (kind === 'box' || kind === 'reefer' || kind === 'grain') {
    box(g, 1.9, 1.85, L, body, 0, 1.92, 0);
    for (const sx of [-1, 1]) box(g, 0.03, 1.4, 1.2, mat(kind === 'reefer' ? 0xb9ae96 : 0x5e2c18), sx * 0.96, 1.85, 0);
    box(g, 1.98, 0.12, L + 0.05, roofM, 0, 2.9, 0);
    if (kind === 'reefer') for (const z of [-2, 2]) box(g, 0.6, 0.15, 0.6, roofM, 0, 3.0, z);
    if (kind === 'grain') for (const z of [-1.5, 0, 1.5]) box(g, 0.7, 0.12, 0.5, roofM, 0, 3.0, z);
  } else if (kind === 'hopper') {
    for (const sx of [-1, 1]) box(g, 0.1, 1.3, L, body, sx * 0.9, 1.65, 0);
    for (const sz of [-1, 1]) box(g, 1.8, 1.3, 0.1, body, 0, 1.65, sz * (L / 2 - 0.05));
    box(g, 1.75, 0.2, L - 0.2, body, 0, 1.1, 0);
    const load = box(g, 1.7, 0.6, L - 0.2, mat(cargo.load, { r: 1, flat: true }), 0, 2.0, 0);
    load.castShadow = false;
    for (const z of [-1.4, 0, 1.4]) {
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.9, 7, 5, 0, Math.PI * 2, 0, Math.PI / 2), mat(cargo.load, { r: 1, flat: true }));
      m.scale.set(0.95, 0.5, 0.85); m.position.set(0, 2.25, z); g.add(m);
    }
  } else if (kind === 'flat') {
    box(g, 1.9, 0.2, L, body, 0, 1.08, 0);
    if (cargo.load === 'logs') {
      const lm = mat(0x7a5432, { r: 0.9 });
      const rows = [[-0.6, 0, 0.6], [-0.3, 0.3], [0]];
      rows.forEach((row, ri) => row.forEach(x => cylZ(g, 0.3, L - 0.3, lm, x, 1.48 + ri * 0.5, 0, 9)));
      for (const sx of [-1, 1]) for (const z of [-2, 0, 2]) box(g, 0.08, 1.4, 0.08, dark, sx * 0.92, 1.85, z);
    } else {
      const sm = mat(0x8a9097, { m: 0.9, r: 0.35 });
      for (let r = 0; r < 2; r++) for (const x of [-0.5, 0, 0.5]) box(g, 0.38, 0.32, L - 0.4, sm, x, 1.36 + r * 0.34, 0);
    }
  }
  return { group: outer, wheels, rods: [], len: L };
}

// ---------------- stations ----------------
export function makeStation() {
  const g = new THREE.Group();
  const plat = mat(0x9b9184, { r: 0.9 }), wall = mat(0xc9b48f, { r: 0.8 }), brick = mat(0x8a4b36, { r: 0.85 });
  const roofM = mat(0x3b3f47, { r: 0.6, flat: true }), wood = mat(0x5a3c27);
  box(g, 3.6, 0.6, 22, plat, 3.1, 0.25, 0);
  box(g, 0.25, 0.62, 22, mat(0xd9d2c0), 1.45, 0.26, 0);
  // depot
  box(g, 4.2, 2.8, 9, wall, 6.6, 1.95, 0);
  box(g, 4.25, 0.5, 9.05, brick, 6.6, 0.8, 0);
  roof(g, 9.8, 1.8, 5.4, roofM, 6.6, 3.35, 0, Math.PI / 2);
  cylY(g, 0.3, 0.3, 1.6, brick, 7.5, 4.1, 2.6, 6);
  for (const z of [-3, -1, 1, 3]) box(g, 0.05, 1.1, 0.75, mat(0x26303a, { e: 0xffc070, ei: 0.25, r: 0.2 }), 4.48, 2.2, z);
  box(g, 0.06, 1.8, 1.0, wood, 4.48, 1.9, 0);
  // canopy
  for (const z of [-6, -2, 2, 6]) cylY(g, 0.08, 0.08, 2.9, mat(0x2b2b2b, { m: 0.7 }), 2.4, 0.55, z, 6);
  box(g, 3.2, 0.12, 14, roofM, 3.0, 3.5, 0).rotation.z = -0.08;
  // lamps and benches
  for (const z of [-9, 9]) {
    cylY(g, 0.06, 0.06, 2.4, mat(0x222222), 1.9, 0.55, z, 6);
    box(g, 0.3, 0.3, 0.3, mat(0xfff0c8, { e: 0xffd890, ei: 1.5 }), 1.9, 3.1, z).castShadow = false;
  }
  for (const z of [-4, 4]) box(g, 0.5, 0.45, 1.6, wood, 4.0, 0.78, z);
  // name board
  box(g, 0.1, 0.6, 3.2, mat(0x1b2733), 4.9, 3.0, -6);
  return g;
}

// ---------------- industries ----------------
export function makeIndustry(type) {
  const g = new THREE.Group(), chimneys = [];
  const brick = mat(0x8a4b36, { r: 0.85 }), dark = mat(0x2b2b2e, { r: 0.7 }), roofM = mat(0x3b3f47, { r: 0.6, flat: true });
  const wood = mat(0x6b4a2e, { r: 0.85 }), stone = mat(0x8d8a84, { r: 0.9 }), steel = mat(0x5a5f66, { m: 0.7, r: 0.4 });
  const pile = (x, z, r, h, color) => { const m = add(g, new THREE.ConeGeometry(r, h, 8), mat(color, { r: 1, flat: true }), x, h / 2, z); m.rotation.y = x; };
  const chimney = (x, z, h, r, m = brick) => { cylY(g, r * 0.8, r, h, m, x, 0, z, 10); chimneys.push(new THREE.Vector3(x, h + 0.3, z)); };
  const headframe = (x, z, m) => {
    for (const [dx, dz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
      const leg = box(g, 0.3, 10, 0.3, m, x + dx * 0.9, 5, z + dz * 0.9);
      leg.rotation.z = -dx * 0.08; leg.rotation.x = dz * 0.08;
    }
    const strut = box(g, 0.3, 11, 0.3, m, x - 2.5, 5, z); strut.rotation.z = -0.45;
    box(g, 2.4, 0.3, 2.4, m, x, 9.8, z);
    const wheelM = new THREE.Mesh(new THREE.TorusGeometry(1.0, 0.13, 6, 18), steel);
    wheelM.position.set(x, 10.6, z); wheelM.castShadow = true; g.add(wheelM);
  };
  if (type === 'coal' || type === 'iron') {
    const pc = type === 'coal' ? 0x161616 : 0x8a4a2e;
    headframe(0, 0, type === 'coal' ? wood : steel);
    box(g, 5, 3.6, 4.2, type === 'coal' ? brick : stone, -5.5, 1.8, -1);
    roof(g, 5.3, 1.6, 4.6, roofM, -5.5, 3.6, -1);
    chimney(-7.5, -2.6, 9, 0.5);
    pile(5, 3.5, 3.2, 2.4, pc); pile(4, -4, 2.4, 1.8, pc); pile(1.5, 5.5, 1.8, 1.3, pc);
    box(g, 3, 3, 3, wood, 5.5, 4, -0.5); box(g, 0.3, 3, 0.3, wood, 4.3, 1.5, -1.7); box(g, 0.3, 3, 0.3, wood, 6.7, 1.5, 0.7);
  } else if (type === 'lumber') {
    box(g, 7, 3.2, 4.4, wood, -2, 1.6, -2);
    roof(g, 7.3, 1.5, 5, roofM, -2, 3.2, -2);
    chimney(-5, -3.5, 6, 0.35, steel);
    const logM = mat(0x8a5e38, { r: 0.9 });
    for (const [px, pz] of [[4, 3], [-3, 4.5]]) {
      [[-0.75, 0, 0.75], [-0.38, 0.38], [0]].forEach((row, ri) => row.forEach(dx => cylZ(g, 0.38, 5, logM, px + dx, 0.38 + ri * 0.66, pz, 9)));
    }
    for (let i = 0; i < 7; i++) cylY(g, 0.35, 0.4, 0.5, logM, 7 + Math.sin(i * 2.1) * 3, 0, -4 + i * 1.3, 7);
  } else if (type === 'farm') {
    const red = mat(0x9a2a22, { r: 0.8 }), white = mat(0xe8e2d4, { r: 0.8 });
    box(g, 5, 3.6, 7, red, 0, 1.8, 0);
    roof(g, 5.4, 2.3, 7.4, roofM, 0, 3.6, 0, Math.PI / 2);
    box(g, 0.05, 2.4, 2, white, 2.52, 1.2, 0);
    cylY(g, 1.3, 1.3, 7.5, mat(0xa9aaa6, { m: 0.5, r: 0.5 }), -4, 0, 2);
    const dome = new THREE.Mesh(new THREE.SphereGeometry(1.3, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), mat(0x7d8a92, { m: 0.6, r: 0.4 }));
    dome.position.set(-4, 7.5, 2); dome.castShadow = true; g.add(dome);
    box(g, 3.2, 2.2, 3.6, white, 1, 1.1, -7);
    roof(g, 3.6, 1.5, 4.0, mat(0x5a2b22, { flat: true }), 1, 2.2, -7);
    for (const [x, z] of [[5, 4], [6, 6], [4.5, 7]]) cylY(g, 0.8, 0.8, 1.1, mat(0xd7b55a, { r: 1 }), x, 0, z, 10);
  } else if (type === 'steel') {
    const shed = mat(0x4a4d52, { r: 0.7 });
    box(g, 11, 6, 6, shed, -1, 3, -3); roof(g, 11.3, 2.2, 6.4, roofM, -1, 6, -3);
    box(g, 6, 4, 5, shed, 3, 2, 4); roof(g, 6.3, 1.6, 5.4, roofM, 3, 4, 4);
    cylY(g, 2.0, 2.4, 10, mat(0x5a3a2a, { r: 0.8 }), -5, 0, 4.5, 16);
    const glow = box(g, 1.4, 1.2, 0.2, mat(0xff8a2a, { e: 0xff6a10, ei: 4 }), -5, 1.0, 6.9);
    glow.castShadow = false;
    for (const x of [-6, -3, 0]) chimney(x, -7, 17, 0.7, mat(0x7a3a2c, { r: 0.85 }));
  } else if (type === 'factory') {
    for (let i = 0; i < 4; i++) {
      box(g, 3, 4, 10, brick, -5 + i * 3, 2, 0);
      const r = roof(g, 10, 1.8, 3, roofM, -5 + i * 3, 4, 0, Math.PI / 2); r.scale.set(10, 1.8, 3);
    }
    chimney(5, -4, 15, 0.7);
    cylY(g, 1.4, 1.4, 2.2, wood, 6, 6, 4, 12); for (const dx of [-0.9, 0.9]) box(g, 0.2, 6, 0.2, wood, 6 + dx, 3, 4);
  } else if (type === 'food') {
    const white = mat(0xdedad0, { r: 0.75 });
    box(g, 8, 4, 6, white, -2, 2, -2); roof(g, 8.3, 1.6, 6.4, mat(0x6e2c24, { flat: true }), -2, 4, -2);
    for (let i = 0; i < 4; i++) cylY(g, 1.1, 1.1, 8, mat(0xb9bcbf, { m: 0.5, r: 0.45 }), 3 + (i % 2) * 2.4, 0, 2 + Math.floor(i / 2) * 2.4);
    chimney(-5, 2.5, 9, 0.45);
  }
  g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  return { group: g, chimneys };
}

export function makeTownHall() {
  const g = new THREE.Group();
  const stone = mat(0xd8cfbc, { r: 0.85 }), roofM = mat(0x3b4a52, { r: 0.5, flat: true });
  box(g, 8, 4.5, 6, stone, 0, 2.25, 0);
  roof(g, 8.4, 2, 6.6, roofM, 0, 4.5, 0);
  box(g, 2.4, 9, 2.4, stone, 0, 4.5, 3.2);
  add(g, new THREE.ConeGeometry(1.9, 4, 4), roofM, 0, 11, 3.2).rotation.y = Math.PI / 4;
  const clock = new THREE.Mesh(new THREE.CircleGeometry(0.7, 20), mat(0xf4ecd8, { e: 0xfff1d0, ei: 0.3 }));
  clock.position.set(0, 7.5, 4.42); g.add(clock);
  return g;
}

// ---------------- instanced geometry ----------------
function colored(geo, color) {
  const c = new THREE.Color(color), n = geo.attributes.position.count, a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; }
  geo.setAttribute('color', new THREE.BufferAttribute(a, 3));
  return geo;
}
export function coniferGeometry() {
  const parts = [];
  const trunk = new THREE.CylinderGeometry(0.18, 0.25, 1.6, 6); trunk.translate(0, 0.8, 0); parts.push(colored(trunk.toNonIndexed(), 0x4a3424));
  const cones = [[1.7, 3.2, 1.2], [1.35, 2.8, 2.7], [0.9, 2.3, 4.1]];
  for (const [r, h, y] of cones) { const c = new THREE.ConeGeometry(r, h, 7); c.translate(0, y + h / 2, 0); parts.push(colored(c.toNonIndexed(), 0x2f5a36)); }
  return mergeGeometries(parts);
}
export function broadleafGeometry() {
  const parts = [];
  const trunk = new THREE.CylinderGeometry(0.2, 0.3, 2.2, 6); trunk.translate(0, 1.1, 0); parts.push(colored(trunk.toNonIndexed(), 0x4f3a28));
  for (const [x, y, z, r] of [[0, 3.4, 0, 1.8], [0.9, 2.9, 0.3, 1.2], [-0.8, 3.0, -0.4, 1.3], [0.2, 4.3, 0.2, 1.2]]) {
    const s = new THREE.IcosahedronGeometry(r, 0); s.translate(x, y, z); parts.push(colored(s.toNonIndexed(), 0x4d7a32));
  }
  return mergeGeometries(parts);
}

export function wallGeometry() {
  const g = new THREE.BoxGeometry(1, 1, 1); g.translate(0, 0.5, 0);
  const uv = g.attributes.uv;
  for (let i = 8; i < 16; i++) uv.setXY(i, 0.02, 0.02);     // top and bottom faces: plain wall, no windows
  return g;
}
export function windowTexture() {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const x = c.getContext('2d');
  x.fillStyle = '#ffffff'; x.fillRect(0, 0, 128, 128);
  x.fillStyle = '#e6e2da'; for (let i = 0; i < 128; i += 8) x.fillRect(0, i, 128, 1);
  for (const [wx, wy] of [[22, 30], [74, 30], [22, 78], [74, 78]]) {
    x.fillStyle = '#3a4048'; x.fillRect(wx - 2, wy - 2, 36, 30);
    x.fillStyle = '#56606c'; x.fillRect(wx, wy, 32, 26);
    x.fillStyle = '#7d8896'; x.fillRect(wx, wy, 32, 6);
    x.fillStyle = '#3a4048'; x.fillRect(wx + 15, wy, 2, 26);
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}
export { PRISM };
