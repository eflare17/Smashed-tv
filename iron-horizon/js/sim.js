// Stations, trains and the cargo economy.
import * as THREE from 'three';
import { G, newId, spend, earn, year } from './state.js';
import * as W from './world.js';
import * as T from './track.js';
import * as M from './models.js';
import { clamp } from './noise.js';

export const CARGO = {
  pass: { name: 'Passengers', rate: 210, cap: 32, car: 'coach', color: '#e9cf7a' },
  mail: { name: 'Mail', rate: 400, cap: 14, car: 'mail', color: '#9fd3a8' },
  coal: { name: 'Coal', rate: 170, cap: 20, car: 'hopper', load: 0x161616, color: '#9a9a9a' },
  ore: { name: 'Iron Ore', rate: 180, cap: 20, car: 'hopper', load: 0x8a3b22, color: '#d0785a' },
  lumber: { name: 'Lumber', rate: 200, cap: 20, car: 'flat', load: 'logs', color: '#c49a64' },
  grain: { name: 'Grain', rate: 190, cap: 20, car: 'grain', color: '#e6cf6a' },
  steel: { name: 'Steel', rate: 330, cap: 20, car: 'flat', load: 'beams', color: '#b8c4d0' },
  goods: { name: 'Goods', rate: 430, cap: 20, car: 'box', color: '#e49a6a' },
  food: { name: 'Food', rate: 370, cap: 20, car: 'reefer', color: '#f2e6c8' },
};

const wheels = (s) => s.split('-').map(Number);
export const LOCOS = [
  { id: 'comet', name: 'Comet', type: '2-2-0', year: 1830, speed: 12, cars: 3, cost: 45000, op: 11000, color: 0x2f5d3a, trim: 0xd8b25a, size: 0.88 },
  { id: 'hopper', name: 'Grasshopper', type: '4-2-0', year: 1838, speed: 15, cars: 4, cost: 68000, op: 15000, color: 0x3b4f7a, trim: 0xd8b25a, size: 0.92 },
  { id: 'american', name: 'American', type: '4-4-0', year: 1850, speed: 19, cars: 5, cost: 92000, op: 19000, color: 0x7a1f1f, trim: 0xe0be6a },
  { id: 'mogul', name: 'Mogul', type: '2-6-0', year: 1864, speed: 18, cars: 7, cost: 118000, op: 23000, color: 0x1f2b22, trim: 0xc9a55a },
  { id: 'tenwheel', name: 'Ten-Wheeler', type: '4-6-0', year: 1876, speed: 23, cars: 7, cost: 140000, op: 26000, color: 0x24324a, trim: 0xd0b060 },
  { id: 'consol', name: 'Consolidation', type: '2-8-0', year: 1888, speed: 20, cars: 10, cost: 165000, op: 30000, color: 0x1c1c1e, trim: 0xa8a8a8 },
  { id: 'atlantic', name: 'Atlantic', type: '4-4-2', year: 1898, speed: 29, cars: 6, cost: 175000, op: 30000, color: 0x214a3a, trim: 0xe0c070 },
  { id: 'pacific', name: 'Pacific', type: '4-6-2', year: 1910, speed: 31, cars: 9, cost: 220000, op: 34000, color: 0x2a2a2e, trim: 0xd0d0d0 },
  { id: 'mikado', name: 'Mikado', type: '2-8-2', year: 1920, speed: 26, cars: 12, cost: 250000, op: 38000, color: 0x1a1a1a, trim: 0xb0563a },
  { id: 'hudson', name: 'Hudson', type: '4-6-4', year: 1930, speed: 36, cars: 10, cost: 300000, op: 42000, color: 0x1f2f45, trim: 0xd8d8d8 },
  { id: 'arrow', name: 'Silver Arrow', type: 'streamliner', year: 1936, speed: 42, cars: 8, cost: 360000, op: 40000, color: 0xc8ccd0, trim: 0xb03030, kind: 'stream' },
  { id: 'diesel', name: 'Road Diesel', type: 'diesel', year: 1946, speed: 38, cars: 14, cost: 380000, op: 36000, color: 0x8a2a24, trim: 0xe8c040, kind: 'diesel' },
].map(m => ({ ...m, wheels: m.kind ? [0, 0, 0] : wheels(m.type) }));
export const availableLocos = () => LOCOS.filter(m => m.year <= year());

export const STATION_R = 20, STATION_COST = 30000;

// ---------------- stations ----------------
function stationName(x, z) {
  const { city, d } = W.nearestCity(x, z);
  let base = city.name;
  if (d > 45) {
    let ind = null, bd = 40;
    for (const i of G.industries) { const dd = Math.hypot(i.x - x, i.z - z); if (dd < bd) { bd = dd; ind = i; } }
    const suffix = ind ? { coal: 'Colliery', iron: 'Mines', lumber: 'Timber', farm: 'Farms', steel: 'Steelworks', factory: 'Works', food: 'Mills' }[ind.type] : 'Halt';
    base = `${city.name} ${suffix}`;
  }
  const used = [...G.stations.values()].map(s => s.name);
  if (!used.includes(base)) return base;
  for (const s of ['East', 'West', 'North', 'South', 'Junction', 'Central', 'Road']) if (!used.includes(`${base} ${s}`)) return `${base} ${s}`;
  return `${base} ${G.stations.size}`;
}

// Work out where a station would go if the player clicked at (x,z) with the given free-standing axis.
export function stationSite(x, z, axis) {
  const ref = T.snapRef(x, z, { stations: false });
  let site = { ok: true, reason: '', x: ref.x, z: ref.z, axis, ref };
  if (ref.kind === 'edge') { const p = ref.edge.pts, i = ref.idx; const l = Math.hypot(p[i + 2].x - p[i - 2].x, p[i + 2].z - p[i - 2].z); site.axis = { x: (p[i + 2].x - p[i - 2].x) / l, z: (p[i + 2].z - p[i - 2].z) / l }; site.y = ref.y; }
  else if (ref.kind === 'node') {
    if (ref.node.station) return { ...site, ok: false, reason: 'Already a station' };
    if (ref.node.edges.size > 2) return { ...site, ok: false, reason: 'Not on a junction' };
    site.axis = ref.node.axis ?? axis; site.y = ref.y;
  } else {
    const g = W.heightAt(x, z);
    if (g < W.WATER + 1) return { ...site, ok: false, reason: 'Not on water' };
    if (W.slopeAt(x, z) > 0.5) return { ...site, ok: false, reason: 'Too steep here' };
    site.y = g + 0.15;
    for (const s of [-12, 12]) {
      const px = x + axis.x * s, pz = z + axis.z * s;
      if (!W.inMap(px, pz, 6)) return { ...site, ok: false, reason: 'Too close to the edge' };
      if (W.heightAt(px, pz) < W.WATER + 0.5) return { ...site, ok: false, reason: 'Too close to water' };
    }
  }
  if (!W.inMap(site.x, site.z, 10)) return { ...site, ok: false, reason: 'Too close to the edge' };
  for (const st of G.stations.values()) if (Math.hypot(st.x - site.x, st.z - site.z) < 30) return { ...site, ok: false, reason: `Too close to ${st.name}` };
  for (const i of G.industries) if (Math.hypot(i.x - site.x, i.z - site.z) < 15) return { ...site, ok: false, reason: `On top of ${i.name}` };
  for (const c of G.cities) if (Math.hypot(c.x - site.x, c.z - site.z) < 12) return { ...site, ok: false, reason: `On top of ${c.name} town hall` };
  site.cost = STATION_COST + (ref.kind === 'free' ? 24 * T.TRACK_COST : 0);
  return site;
}

export function buildStation(site, restore = null) {
  let node;
  const ax = site.axis;
  if (restore) node = G.nodes.get(restore.node);
  else if (site.ref.kind === 'edge') node = T.splitEdge(site.ref.edge, site.ref.idx);
  else if (site.ref.kind === 'node') { node = site.ref.node; if (!node.axis) node.axis = ax; }
  else {
    const y = site.y;
    const pad = [];
    for (let s = -13; s <= 13; s += 1) pad.push({ x: site.x + ax.x * s, y, z: site.z + ax.z * s });
    W.carve(pad, { inner: 3, bed: true });
    node = T.createNode(site.x, y, site.z, ax);
    const A = T.createNode(site.x - ax.x * 12, y, site.z - ax.z * 12, ax), B = T.createNode(site.x + ax.x * 12, y, site.z + ax.z * 12, ax);
    T.addEdge(A, node, T.straightPts(A, node), 12 * T.TRACK_COST, false);
    T.addEdge(node, B, T.straightPts(node, B), 12 * T.TRACK_COST, false);
  }
  const axis = node.axis;
  const side = { x: axis.z, z: -axis.x };   // the model's +X
  const st = {
    id: restore?.id ?? newId(), kind: 'station', node, name: restore?.name ?? stationName(node.x, node.z),
    x: node.x, y: node.y, z: node.z, axis, stock: {}, demand: {}, accepts: new Set(), supplies: new Set(),
    coverInd: [], coverCity: null, coverN: 0, free: site.ref?.kind === 'free',
    bx: node.x + side.x * 6, bz: node.z + side.z * 6,
  };
  node.station = st;
  // level the ground under the depot
  const pad = [];
  for (let s = -10; s <= 10; s += 1.5) for (const o of [3.5, 6.5]) pad.push({ x: node.x + side.x * o + axis.x * s, y: node.y, z: node.z + side.z * o + axis.z * s });
  W.carve(pad, { inner: 2.2 });
  // clear the platform, depot and the track through the station
  for (let s = -13; s <= 13; s += 2) for (const o of [-1.5, 2, 5.5, 9]) {
    const px = node.x + side.x * o + axis.x * s, pz = node.z + side.z * o + axis.z * s;
    W.removeTrees(px, pz, 4.5); W.demolishNear(px, pz, 3.6);
  }
  const g = M.makeStation();
  g.position.set(node.x, node.y, node.z);
  g.rotation.y = Math.atan2(axis.x, axis.z);
  g.traverse(o => { o.userData.pick = st; });
  G.scene.add(g); st.group = g;
  G.stations.set(st.id, st);
  if (restore) { st.stock = restore.stock; st.demand = restore.demand; }
  else spend(site.cost);
  refreshCoverage();
  return st;
}

export function removeStation(st) {
  for (const t of G.trains.values()) if (t.route.includes(st.id)) return `${t.name} stops here — change its route first`;
  G.scene.remove(st.group);
  st.node.station = null;
  if (st.node.edges.size === 0) G.nodes.delete(st.node.id);
  G.stations.delete(st.id);
  G.cash += STATION_COST * 0.4;
  refreshCoverage();
  return null;
}

export function coverageAt(x, z) {
  const inds = G.industries.filter(i => Math.hypot(i.x - x, i.z - z) < STATION_R + 6);
  let city = null, n = 0;
  for (const c of G.cities) {
    let k = 0;
    for (const lot of c.lots) if (lot.alive && Math.hypot(lot.x - x, lot.z - z) < STATION_R) k++;
    if (Math.hypot(c.x - x, c.z - z) < STATION_R) k += 4;
    if (k > n) { n = k; city = c; }
  }
  if (n < 3) { city = null; n = 0; }
  const supplies = new Set(), accepts = new Set();
  for (const i of inds) { supplies.add(i.def.produces); i.def.accepts.forEach(a => accepts.add(a)); }
  if (city) {
    supplies.add('pass'); supplies.add('mail');
    ['pass', 'mail', 'goods', 'food'].forEach(a => accepts.add(a));
    if (city.pop >= 1500) accepts.add('coal');
    if (city.pop >= 3000) { accepts.add('lumber'); accepts.add('steel'); }
  }
  return { inds, city, n, supplies, accepts };
}
export function refreshCoverage() {
  for (const i of G.industries) i.stations = [];
  for (const st of G.stations.values()) {
    const c = coverageAt(st.x, st.z);
    st.coverInd = c.inds; st.coverCity = c.city; st.coverN = c.n; st.supplies = c.supplies; st.accepts = c.accepts;
    for (const i of c.inds) i.stations.push(st);
  }
}

const STOCK_CAP = 180;
function addStock(st, c, v) { st.stock[c] = Math.min(STOCK_CAP, (st.stock[c] ?? 0) + v); }

// ---------------- daily economy ----------------
export function econTick(dd) {
  for (const ind of G.industries) {
    let out;
    if (ind.def.accepts.length) { const c = Math.min(ind.inp, 3 * dd); ind.inp -= c; out = c * 0.9 + ind.def.base * dd; }
    else out = ind.def.rate * ind.mult * dd;
    if (ind.stations.length) { for (const st of ind.stations) addStock(st, ind.def.produces, out / ind.stations.length); ind.produced += out; }
  }
  for (const st of G.stations.values()) {
    if (st.coverCity) {
      const k = st.coverN * (0.6 + st.coverCity.pop / 5000);
      addStock(st, 'pass', k * 0.05 * dd); addStock(st, 'mail', k * 0.016 * dd);
    }
    for (const c in st.demand) st.demand[c] = Math.min(1, st.demand[c] + 0.003 * dd);
  }
  for (const t of G.trains.values()) spend(t.model.op / 365 * dd, 'ops');
  spend(T.totalTrackLength() * 22 / 365 * dd, 'maint');
  if (G.loan > 0) spend(G.loan * 0.06 / 365 * dd, 'interest');
}
export function yearTick() {
  for (const c of G.cities) {
    c.pop = Math.round(c.pop * 1.012 + c.growth);
    c.growth = 0;
    W.growCity(c, true);
  }
  for (const i of G.industries) { i.producedLast = i.produced; i.produced = 0; }
  for (const t of G.trains.values()) { t.profitLast = t.profitYear; t.profitYear = 0; t.age++; }
  refreshCoverage();
}

// ---------------- trains ----------------
const ACCEL = 2.2, DECEL = 3.2, GAP = 0.35;

export function buyTrain(model, route) {
  spend(model.cost, 'build');
  G.assetValue -= model.cost * 0.6;     // trains are valued separately in net worth
  const n = [...G.trains.values()].length + 1;
  const tr = {
    id: newId(), kind: 'train', name: `No. ${n} ${model.name}`, model, route: route.slice(), cur: 0, next: 1 % route.length,
    cars: [], path: null, d: 0, v: 0, state: 'load', timer: 0.5, profitYear: 0, profitLast: 0, lifetime: 0, age: 0, smokeAcc: 0,
  };
  spawnTrain(tr);
  arrive(tr, true);
  return tr;
}
export function spawnTrain(tr) {
  const loco = M.makeLoco(tr.model);
  tr.units = [{ ...loco, loco: true }];
  if (!tr.model.kind) tr.units.push(M.makeTender(tr.model));
  tr.fixed = tr.units.length;
  for (const u of tr.units) addUnit(tr, u);
  tr.maxLen = tr.units.reduce((s, u) => s + u.len + GAP, 0) + tr.model.cars * (5 + GAP) + 2;
  G.trains.set(tr.id, tr);
  rebuildCars(tr);
}
function addUnit(tr, u) {
  u.group.traverse(o => { o.userData.pick = tr; });
  G.scene.add(u.group);
}
function rebuildCars(tr) {
  for (const u of tr.units.splice(tr.fixed)) { G.scene.remove(u.group); }
  for (const car of tr.cars) { const u = M.makeCar(CARGO[car.cargo]); addUnit(tr, u); tr.units.push(u); }
}
export function sellTrain(tr) {
  for (const u of tr.units) G.scene.remove(u.group);
  G.trains.delete(tr.id);
  G.cash += tr.model.cost * Math.max(0.3, 1 - tr.age * 0.04) * 0.5;
  if (G.follow === tr) G.follow = null;
}

function cumOf(pts) { const c = [0]; for (let i = 1; i < pts.length; i++) c.push(c[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y, pts[i].z - pts[i - 1].z)); return c; }
function sampleAt(path, s, out) {
  const { pts, cum } = path, n = pts.length;
  if (s <= 0) { const p = pts[0]; return out.set(p.x, p.y, p.z); }
  if (s >= path.len) { const p = pts[n - 1]; return out.set(p.x, p.y, p.z); }
  let lo = 0, hi = n - 1;
  while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (cum[mid] <= s) lo = mid; else hi = mid; }
  const t = (s - cum[lo]) / Math.max(1e-6, cum[hi] - cum[lo]), a = pts[lo], b = pts[hi];
  return out.set(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

function startLeg(tr) {
  const from = G.stations.get(tr.route[tr.cur]), to = G.stations.get(tr.route[tr.next]);
  const res = from && to ? T.findPath(from.node.id, to.node.id) : null;
  if (!res) { tr.state = 'noroute'; tr.timer = 2; return; }
  const leg = T.pathPoints(res);
  const len = tr.units.reduce((s, u) => s + u.len + GAP, 0);
  let pts = leg, d = 0;
  if (tr.path) {
    const op = tr.path.pts, n = op.length;
    const od = { x: op[n - 1].x - op[Math.max(0, n - 4)].x, z: op[n - 1].z - op[Math.max(0, n - 4)].z };
    const nd = { x: leg[Math.min(3, leg.length - 1)].x - leg[0].x, z: leg[Math.min(3, leg.length - 1)].z - leg[0].z };
    if (od.x * nd.x + od.z * nd.z > 0) {
      // through station: keep the track behind us so the cars stay put
      let i = n - 1;
      while (i > 0 && tr.path.len - tr.path.cum[i] < tr.maxLen) i--;
      const tail = op.slice(i, n - 1);
      pts = tail.concat(leg);
    }
  }
  const cum = cumOf(pts);
  tr.path = { pts, cum, len: cum[cum.length - 1] };
  if (pts !== leg) d = tr.path.len - cumOf(leg).at(-1);
  else d = Math.min(len, tr.path.len);
  tr.d = d; tr.v = 0; tr.state = 'run';
  if (G.onDepart) G.onDepart(tr);
}

function arrive(tr, first = false) {
  const st = G.stations.get(tr.route[tr.cur]);
  tr.state = 'load'; tr.timer = 1.5; tr.v = 0;
  if (!st) return;
  if (!first) {
    let total = 0;
    tr.cars = tr.cars.filter(car => {
      if (car.from === st.id || !st.accepts.has(car.cargo)) return true;
      total += deliver(st, car);
      return false;
    });
    if (total > 0) { tr.profitYear += total; tr.lifetime += total; if (G.onRevenue) G.onRevenue(st, total, tr); }
  }
  // load: best-paying cargo that some other stop on the route accepts
  const others = tr.route.filter(id => id !== st.id).map(id => G.stations.get(id)).filter(Boolean);
  let free = tr.model.cars - tr.cars.length;
  while (free > 0) {
    let best = null, bv = 0;
    for (const c in st.stock) {
      if (st.stock[c] < 4) continue;
      for (const o of others) {
        if (!o.accepts.has(c)) continue;
        const v = CARGO[c].rate * (o.demand[c] ?? 1) * Math.min(st.stock[c], CARGO[c].cap);
        if (v > bv) { bv = v; best = c; }
      }
    }
    if (!best) break;
    const units = Math.min(CARGO[best].cap, Math.floor(st.stock[best]));
    st.stock[best] -= units;
    tr.cars.push({ cargo: best, units, from: st.id, fx: st.x, fz: st.z, day: G.day });
    free--;
  }
  rebuildCars(tr);
}

function deliver(st, car) {
  const c = CARGO[car.cargo];
  const dist = Math.hypot(st.x - car.fx, st.z - car.fz);
  const days = Math.max(1, G.day - car.day);
  const speed = dist / days;
  const speedMult = clamp(0.55 + 0.45 * speed / 3.2, 0.55, 1.7);
  const dem = st.demand[car.cargo] ?? 1;
  const pay = Math.round(car.units * c.rate * (dist / 100) * speedMult * dem);
  st.demand[car.cargo] = Math.max(0.3, dem - car.units * 0.004);
  earn(pay);
  // effects on the town / industry at the far end
  const ind = st.coverInd.find(i => i.def.accepts.includes(car.cargo));
  if (ind) ind.inp += car.units;
  else if (st.coverCity) st.coverCity.growth += car.units * ({ pass: 0.25, mail: 0.2, goods: 0.8, food: 0.8 }[car.cargo] ?? 0.4);
  return pay;
}

const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _p = new THREE.Vector3(), _w = new THREE.Vector3();
export function updateTrains(dt, emitSmoke) {
  for (const tr of G.trains.values()) {
    if (dt > 0) {
      if (tr.state === 'load' || tr.state === 'noroute') {
        tr.timer -= dt;
        if (tr.timer <= 0) startLeg(tr);
      } else if (tr.state === 'run') {
        const p = tr.path, rem = p.len - tr.d;
        sampleAt(p, tr.d + 2, _a); sampleAt(p, tr.d - 2, _b);
        const grade = (_a.y - _b.y) / 4;
        const load = tr.cars.length / tr.model.cars;
        let vmax = tr.model.speed * clamp(1 - Math.max(0, grade) * 6 * (0.4 + 0.6 * load), 0.3, 1);
        vmax = Math.min(vmax, Math.sqrt(2 * DECEL * Math.max(0, rem - 0.3)) + 0.4);
        const acc = ACCEL * (1.15 - load * 0.45) * (tr.model.speed / 20 + 0.5);
        tr.v = tr.v < vmax ? Math.min(vmax, tr.v + acc * dt) : Math.max(vmax, tr.v - DECEL * 1.6 * dt);
        tr.d += tr.v * dt;
        if (tr.d >= p.len - 0.05) {
          tr.d = p.len;
          tr.cur = tr.next; tr.next = (tr.next + 1) % tr.route.length;
          arrive(tr);
        }
      }
    }
    if (!tr.path) {
      // waiting at its first station before the first departure: park it on the station
      const st = G.stations.get(tr.route[tr.cur]);
      if (st) placeParked(tr, st);
      continue;
    }
    let s = tr.d;
    for (const u of tr.units) {
      const c = s - u.len / 2;
      sampleAt(tr.path, c + u.len * 0.36, _a); sampleAt(tr.path, c - u.len * 0.36, _b);
      _p.addVectors(_a, _b).multiplyScalar(0.5);
      u.group.position.set(_p.x, _p.y + M.RAIL_TOP, _p.z);
      if (_a.distanceToSquared(_b) > 1e-4) u.group.lookAt(_a.x, _a.y + M.RAIL_TOP, _a.z);
      for (const w of u.wheels) w.m.rotation.x += tr.v * dt / w.r;
      if (u.rods) for (const r of u.rods) { const ang = u.wheels[0].m.rotation.x; r.m.position.y = r.y + Math.sin(ang) * r.r; r.m.position.z = r.z + Math.cos(ang) * r.r; }
      s -= u.len + GAP;
    }
    // smoke
    const loco = tr.units[0];
    if (emitSmoke && loco.smoke) {
      tr.smokeAcc += dt * (loco.diesel ? 1.5 + tr.v * 0.1 : 3 + tr.v * 0.7);
      while (tr.smokeAcc > 1) {
        tr.smokeAcc -= 1;
        _w.copy(loco.smoke); loco.group.localToWorld(_w);
        emitSmoke(_w, loco.diesel ? 0.35 : 1, tr.v);
      }
    }
  }
}
function placeParked(tr, st) {
  let s = 0;
  for (const u of tr.units) {
    const c = s - u.len / 2;
    u.group.position.set(st.x + st.axis.x * c, st.y + M.RAIL_TOP, st.z + st.axis.z * c);
    u.group.lookAt(u.group.position.x + st.axis.x, u.group.position.y, u.group.position.z + st.axis.z);
    s -= u.len + GAP;
  }
}

export function trainStatus(tr) {
  const to = G.stations.get(tr.route[tr.next]), at = G.stations.get(tr.route[tr.cur]);
  if (tr.state === 'noroute') return `No track to ${to?.name ?? '?'}!`;
  if (tr.state === 'load') return `Loading at ${at?.name ?? '?'}`;
  return `Heading to ${to?.name ?? '?'}`;
}
export function routeProblems(route) {
  const bad = [];
  for (let i = 0; i < route.length; i++) {
    const a = G.stations.get(route[i]), b = G.stations.get(route[(i + 1) % route.length]);
    if (!a || !b || !T.findPath(a.node.id, b.node.id)) bad.push(i);
  }
  return bad;
}
