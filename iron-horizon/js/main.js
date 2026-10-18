// Iron Horizon: renderer, camera, input, tools, panels, save/load and the main loop.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { Sky } from 'three/addons/objects/Sky.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { SMAAPass } from 'three/addons/postprocessing/SMAAPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { CSS2DRenderer } from 'three/addons/renderers/CSS2DRenderer.js';
import { G, DAY_SEC, GOAL, START_YEAR, year, dateStr, money, netWorth, blankLedger, spend } from './state.js';
import * as W from './world.js';
import * as T from './track.js';
import * as S from './sim.js';
import * as FX from './fx.js';
import { makeStation } from './models.js';

const $ = (s) => document.querySelector(s);
window.IH = G;   // handy in the console
window.IHrender = () => { controls.update(); renderFrame(); labelRenderer.render(scene, camera); };
const SAVE_KEY = 'ironHorizonSave1';
try { const q = JSON.parse(localStorage.getItem('ironHorizonPrefs') || '{}'); Object.assign(G, { quality: q.quality ?? G.quality, labels: q.labels ?? true, sound: q.sound ?? true, tod: q.tod ?? 'day' }); } catch { }
const savePrefs = () => { try { localStorage.setItem('ironHorizonPrefs', JSON.stringify({ quality: G.quality, labels: G.labels, sound: G.sound, tod: G.tod })); } catch { } };

// ---------------- renderer & scene ----------------
const renderer = new THREE.WebGLRenderer({ antialias: G.quality === 'low', powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, G.quality === 'high' ? 2 : 1.25));
renderer.setSize(innerWidth, innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.62;
renderer.shadowMap.enabled = G.quality !== 'low';
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
$('#app').appendChild(renderer.domElement);
const labelRenderer = new CSS2DRenderer({ element: $('#labels') });
labelRenderer.setSize(innerWidth, innerHeight);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.5, 5000);
G.scene = scene; G.camera = camera; G.renderer = renderer;
scene.fog = new THREE.FogExp2(0xbfd3e3, 0.0011);

const sun = new THREE.DirectionalLight(0xfff2dd, 3.2);
sun.castShadow = true;
sun.shadow.mapSize.setScalar(G.quality === 'high' ? 4096 : 2048);
sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.6;
scene.add(sun, sun.target);
const hemi = new THREE.HemisphereLight(0xcfe2ff, 0x5a5040, 0.35);
scene.add(hemi);

const sky = new Sky(); sky.scale.setScalar(4000); scene.add(sky);
const sunDir = new THREE.Vector3();
const pmrem = new THREE.PMREMGenerator(renderer);
let envRT = null;
const TOD = {
  morning: { elev: 11, az: 115, color: 0xffd2a0, int: 3.0, fog: 0xd6cbbd, turb: 5, ray: 2.6, exp: 0.58 },
  day: { elev: 40, az: 150, color: 0xfff0d8, int: 3.6, fog: 0xb4cce0, turb: 2.4, ray: 2.0, exp: 0.56 },
  evening: { elev: 6, az: 245, color: 0xffa060, int: 2.8, fog: 0xd8ab88, turb: 8, ray: 3.2, exp: 0.62 },
};
function applyTimeOfDay() {
  const t = TOD[G.tod] ?? TOD.day;
  const phi = THREE.MathUtils.degToRad(90 - t.elev), theta = THREE.MathUtils.degToRad(t.az);
  sunDir.setFromSphericalCoords(1, phi, theta);
  const u = sky.material.uniforms;
  u.sunPosition.value.copy(sunDir); u.turbidity.value = t.turb; u.rayleigh.value = t.ray; u.mieCoefficient.value = 0.003; u.mieDirectionalG.value = 0.86;
  sun.color.set(t.color); sun.intensity = t.int;
  scene.fog.color.set(t.fog);
  renderer.toneMappingExposure = t.exp;
  hemi.color.set(t.fog);
  FX.setSmokeLight(new THREE.Color(t.color).lerp(new THREE.Color(0xffffff), 0.5));
  // image-based light from the sky
  const skyScene = new THREE.Scene(); const s2 = new Sky(); s2.scale.setScalar(1000); s2.material.uniforms = sky.material.uniforms; skyScene.add(s2);
  if (envRT) envRT.dispose();
  envRT = pmrem.fromScene(skyScene, 0, 0.1, 2000);
  scene.environment = envRT.texture;
}

// post-processing: bloom, then a touch of colour grading and a vignette after tone mapping
const GRADE = {
  uniforms: { tDiffuse: { value: null } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; varying vec2 vUv;
    void main(){ vec4 c = texture2D(tDiffuse, vUv); float l = dot(c.rgb, vec3(0.299,0.587,0.114));
      c.rgb = mix(vec3(l), c.rgb, 1.15); c.rgb = (c.rgb - 0.5) * 1.07 + 0.5;
      c.rgb *= vec3(1.02, 1.0, 0.97);
      vec2 d = vUv - 0.5; c.rgb *= 1.0 - dot(d, d) * 0.6; gl_FragColor = c; }`,
};
let composer = null;
function setupComposer() {
  composer = null;
  if (G.quality === 'low') return;
  composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.22, 0.5, 0.9));
  composer.addPass(new OutputPass());
  composer.addPass(new ShaderPass(GRADE));
  composer.addPass(new SMAAPass(innerWidth * renderer.getPixelRatio(), innerHeight * renderer.getPixelRatio()));
}
// sky light fills shadows in too much on matte surfaces; keep it for metal
const tamed = new WeakSet();
function tameEnv() {
  scene.traverse(o => {
    const m = o.material; if (!m || Array.isArray(m) || tamed.has(m) || G.waterMats?.includes(m)) return;
    tamed.add(m);
    if (m.isMeshStandardMaterial) m.envMapIntensity = m.metalness > 0.5 ? 0.9 : 0.45;
  });
}
setInterval(tameEnv, 1000);

// ---------------- camera controls ----------------
const controls = new OrbitControls(camera, renderer.domElement);
G.controls = controls;
controls.enableDamping = true; controls.dampingFactor = 0.08;
controls.screenSpacePanning = false;
controls.minDistance = 22; controls.maxDistance = 560;
controls.minPolarAngle = 0.15; controls.maxPolarAngle = 1.36;
controls.zoomSpeed = 1.2;
controls.mouseButtons = { LEFT: THREE.MOUSE.PAN, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.ROTATE };
controls.touches = { ONE: THREE.TOUCH.PAN, TWO: THREE.TOUCH.DOLLY_ROTATE };
controls.addEventListener('start', () => { if (G.follow && controls._panning) G.follow = null; });
camera.position.set(0, 330, 360); controls.target.set(0, 0, 0);

const keys = new Set();
function cameraKeys(dt) {
  const dist = camera.position.distanceTo(controls.target), sp = dist * 1.1 * dt;
  const fwd = new THREE.Vector3().subVectors(controls.target, camera.position).setY(0).normalize(), right = new THREE.Vector3(-fwd.z, 0, fwd.x);
  const mv = new THREE.Vector3();
  if (keys.has('w') || keys.has('arrowup')) mv.add(fwd);
  if (keys.has('s') || keys.has('arrowdown')) mv.sub(fwd);
  if (keys.has('d') || keys.has('arrowright')) mv.add(right);
  if (keys.has('a') || keys.has('arrowleft')) mv.sub(right);
  if (mv.lengthSq()) { mv.normalize().multiplyScalar(sp); controls.target.add(mv); camera.position.add(mv); G.follow = null; }
  const rot = (keys.has('q') ? 1 : 0) - (keys.has('e') ? 1 : 0);
  if (rot) {
    const off = camera.position.clone().sub(controls.target).applyAxisAngle(new THREE.Vector3(0, 1, 0), rot * dt * 1.4);
    camera.position.copy(controls.target).add(off);
  }
}
function clampTarget() {
  const t = controls.target, lim = W.HALF - 10;
  const cx = THREE.MathUtils.clamp(t.x, -lim, lim), cz = THREE.MathUtils.clamp(t.z, -lim, lim);
  const ground = Math.max(W.heightAt(cx, cz), W.WATER);
  const dy = (ground - t.y) * 0.1;
  const d = new THREE.Vector3(cx - t.x, dy, cz - t.z);
  t.add(d); camera.position.add(d);
  const minY = Math.max(W.heightAt(camera.position.x, camera.position.z), W.WATER) + 4;
  if (camera.position.y < minY) camera.position.y = minY;
}

// ---------------- picking ----------------
const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
function setRay(e) { ndc.set(e.clientX / innerWidth * 2 - 1, -(e.clientY / innerHeight) * 2 + 1); ray.setFromCamera(ndc, camera); }
function pickGround(e) {
  setRay(e);
  const o = ray.ray.origin, d = ray.ray.direction;
  let t = 0;
  if (o.y > 90) { if (d.y >= 0) return null; t = (90 - o.y) / d.y; }
  let prev = t;
  for (let i = 0; i < 1500; i++) {
    const x = o.x + d.x * t, y = o.y + d.y * t, z = o.z + d.z * t;
    if (Math.abs(x) > W.HALF + 40 || Math.abs(z) > W.HALF + 40) { if (i > 50) return null; }
    if (y <= Math.max(W.heightAt(x, z), W.WATER)) {
      let lo = prev, hi = t;
      for (let k = 0; k < 10; k++) { const m = (lo + hi) / 2; const yy = o.y + d.y * m; if (yy <= Math.max(W.heightAt(o.x + d.x * m, o.z + d.z * m), W.WATER)) hi = m; else lo = m; }
      return new THREE.Vector3(o.x + d.x * hi, o.y + d.y * hi, o.z + d.z * hi);
    }
    prev = t; t += Math.max(0.8, t * 0.004);
  }
  return null;
}
function pickObject(e) {
  setRay(e);
  const objs = [];
  for (const tr of G.trains.values()) for (const u of tr.units) objs.push(u.group);
  for (const st of G.stations.values()) objs.push(st.group);
  for (const i of G.industries) objs.push(i.group);
  for (const c of G.cities) objs.push(c.hall);
  const hits = ray.intersectObjects(objs, true);
  const groundP = pickGround(e);
  const gd = groundP ? groundP.distanceTo(ray.ray.origin) : Infinity;
  for (const h of hits) if (h.object.userData.pick && h.distance < gd + 2) return h.object.userData.pick;
  if (groundP) {
    // a click near a town picks the town
    for (const c of G.cities) if (Math.hypot(c.x - groundP.x, c.z - groundP.z) < 20 + c.built * 0.15) return c;
  }
  return null;
}

// ---------------- UI helpers ----------------
function toast(msg, cls = '') {
  const el = document.createElement('div'); el.className = 'toast ' + cls; el.innerHTML = msg;
  $('#toasts').appendChild(el);
  setTimeout(() => { el.style.transition = 'opacity .4s'; el.style.opacity = '0'; setTimeout(() => el.remove(), 400); }, 3200);
}
function tip(e, html) { const t = $('#tip'); t.innerHTML = html; t.classList.remove('hidden'); t.style.left = Math.min(innerWidth - 290, e.clientX + 18) + 'px'; t.style.top = (e.clientY + 18) + 'px'; }
const hideTip = () => $('#tip').classList.add('hidden');
const HINTS = {
  inspect: '<b>Click</b> anything to inspect · <b>Left-drag</b> pan · <b>Right-drag</b> rotate · <b>Wheel</b> zoom · <b>WASD / QE</b> move',
  track: '<b>Drag</b> from a station, a track end or open ground to lay track · new track curves smoothly out of existing rails',
  station: '<b>Click</b> to build a station (on open ground or on a track) · <b>R</b> rotates · the gold ring is what it serves',
  trains: 'Buy a locomotive, then <b>click stations</b> in the order the train should visit them',
  bulldoze: '<b>Click</b> a piece of track or a station to remove it (40% refund)',
  route: '<b>Click stations</b> to add stops · the train loops through them in order · <b>Enter</b> confirms, <b>Esc</b> cancels',
};
const cargoChip = (c, extra = '') => `<span class="chip"><i style="background:${S.CARGO[c].color}"></i>${S.CARGO[c].name}${extra}</span>`;

function setTool(t) {
  if (G.routeEdit && t !== 'route') G.routeEdit = null;
  G.tool = t;
  document.querySelectorAll('#tools button').forEach(b => b.classList.toggle('on', b.dataset.tool === t || (t === 'route' && b.dataset.tool === 'trains')));
  controls.mouseButtons.LEFT = t === 'inspect' || t === 'trains' || t === 'finance' || t === 'settings' ? THREE.MOUSE.PAN : -1;
  $('#hint').innerHTML = HINTS[t] ?? HINTS.inspect;
  drag = null; T.clearPreview(); T.highlightEdge(null); FX.hideRing(); FX.hideGhost(); hideTip();
  if (t === 'trains') showTrains();
  else if (t === 'finance') showFinance();
  else if (t === 'settings') showSettings();
  else if (t === 'route') showRoute();
  else if (t === 'track' || t === 'station' || t === 'bulldoze') closePanel();
}
function openPanel(html, sel = null) { G.selection = sel; $('#panelBody').innerHTML = html; $('#panel').classList.remove('hidden'); }
function closePanel() { G.selection = null; $('#panel').classList.add('hidden'); FX.hideRing(); if (G.tool === 'route') setTool('inspect'); }
$('#panel .close').onclick = () => { closePanel(); if (['trains', 'finance', 'settings'].includes(G.tool)) setTool('inspect'); };

// ---------------- panels ----------------
function showStation(st) {
  FX.showRing(st.x, st.z, S.STATION_R);
  const sup = [...st.supplies], acc = [...st.accepts];
  const stock = Object.keys(S.CARGO).filter(c => (st.stock[c] ?? 0) >= 0.5)
    .map(c => `<div class="stock"><span>${S.CARGO[c].name}</span><div class="bar"><i style="width:${Math.min(100, st.stock[c] / 1.8)}%;background:${S.CARGO[c].color}"></i></div><span>${Math.floor(st.stock[c])}</span></div>`).join('');
  const serving = [...G.trains.values()].filter(t => t.route.includes(st.id));
  openPanel(`<h2>${st.name}</h2><div class="sub">Station${st.coverCity ? ` · serves ${st.coverCity.name}` : ''}</div>
    <h3>Supplies</h3><div class="chips">${sup.length ? sup.map(c => cargoChip(c)).join('') : '<span class="note">Nothing here to pick up. Move closer to a town or industry.</span>'}</div>
    <h3>Waiting cargo</h3>${stock || '<div class="note">None waiting yet.</div>'}
    <h3>Accepts (price)</h3><div class="chips">${acc.length ? acc.map(c => cargoChip(c, ` <small>${Math.round((st.demand[c] ?? 1) * 100)}%</small>`)).join('') : '<span class="note">Nothing.</span>'}</div>
    ${st.coverInd.length ? `<h3>Industries in range</h3>${st.coverInd.map(i => `<div class="row"><span>${i.def.name}</span><span>${S.CARGO[i.def.produces].name}</span></div>`).join('')}` : ''}
    <h3>Trains</h3>${serving.length ? serving.map(t => `<div class="row"><span>${t.name}</span><span>${S.trainStatus(t)}</span></div>`).join('') : '<div class="note">No trains stop here. Use the Trains tool to add one.</div>'}`, { kind: 'station', obj: st });
}
function showIndustry(ind) {
  FX.showRing(ind.x, ind.z, 12, 0x9fd3ff);
  const d = ind.def;
  openPanel(`<h2>${ind.name}</h2><div class="sub">${d.name}</div>
    <h3>Produces</h3><div class="chips">${cargoChip(d.produces)}</div>
    ${d.accepts.length ? `<h3>Needs</h3><div class="chips">${d.accepts.map(c => cargoChip(c)).join('')}</div><div class="note">Delivering what it needs makes it produce far more.</div>` : ''}
    <h3>Output</h3>
    <div class="row"><span>This year</span><span>${Math.round(ind.produced)} units</span></div>
    <div class="row"><span>Last year</span><span>${Math.round(ind.producedLast)} units</span></div>
    ${d.accepts.length ? `<div class="row"><span>Stockpiled inputs</span><span>${Math.round(ind.inp)}</span></div>` : ''}
    <h3>Served by</h3>${ind.stations.length ? ind.stations.map(s => `<div class="row"><span>${s.name}</span><span></span></div>`).join('') : '<div class="note">No station in range — nothing gets shipped. Build a station within its reach.</div>'}`, { kind: 'industry', obj: ind });
}
function showCity(c) {
  FX.showRing(c.x, c.z, 20 + c.built * 0.2, 0xffffff);
  const acc = ['pass', 'mail', 'goods', 'food'].concat(c.pop >= 1500 ? ['coal'] : [], c.pop >= 3000 ? ['lumber', 'steel'] : []);
  const sts = [...G.stations.values()].filter(s => s.coverCity === c);
  openPanel(`<h2>${c.name}</h2><div class="sub">Town · population ${c.pop.toLocaleString()}</div>
    <h3>Ships out</h3><div class="chips">${cargoChip('pass')}${cargoChip('mail')}</div>
    <h3>Wants</h3><div class="chips">${acc.map(a => cargoChip(a)).join('')}</div>
    <div class="note">Deliveries of goods, food and passengers make the town grow; bigger towns want more kinds of freight.</div>
    <h3>Stations</h3>${sts.length ? sts.map(s => `<div class="row"><span>${s.name}</span><span>${s.coverN} buildings</span></div>`).join('') : '<div class="note">Not served yet.</div>'}`, { kind: 'city', obj: c });
}
function showTrain(tr) {
  FX.hideRing();
  const cars = tr.cars.length ? tr.cars.map(c => `<div class="row"><span>${S.CARGO[c.cargo].name}</span><span>${c.units} from ${G.stations.get(c.from)?.name ?? '?'}</span></div>`).join('') : '<div class="note">Running empty.</div>';
  openPanel(`<h2>${tr.name}</h2><div class="sub">${tr.model.name} ${tr.model.type} · ${S.trainStatus(tr)}</div>
    <div class="row"><span>Speed</span><span>${Math.round(tr.v * 3)} mph</span></div>
    <div class="row"><span>Cars</span><span>${tr.cars.length} / ${tr.model.cars}</span></div>
    <h3>Route</h3>${tr.route.map((id, i) => `<div class="row"><span>${i + 1}. ${G.stations.get(id)?.name ?? '(removed)'}</span><span>${i === tr.next && tr.state === 'run' ? '→ next' : ''}</span></div>`).join('')}
    <h3>Cargo</h3>${cars}
    <h3>Profit</h3>
    <div class="row"><span>This year</span><span>${money(tr.profitYear)}</span></div>
    <div class="row"><span>Last year</span><span>${money(tr.profitLast)}</span></div>
    <div class="row"><span>All time</span><span>${money(tr.lifetime)}</span></div>
    <div class="row"><span>Running cost</span><span>${money(tr.model.op)}/yr</span></div>
    <div class="btns"><button class="btn" id="bFollow">${G.follow === tr ? 'Stop following' : 'Follow with camera'}</button><button class="btn ghost" id="bRoute">Edit route</button><button class="btn danger" id="bSell">Sell</button></div>`, { kind: 'train', obj: tr });
  $('#bFollow').onclick = () => { G.follow = G.follow === tr ? null : tr; if (G.follow) followSnap(); showTrain(tr); };
  $('#bRoute').onclick = () => { G.routeEdit = { train: tr, model: tr.model, stops: tr.route.slice() }; setTool('route'); };
  $('#bSell').onclick = () => { S.sellTrain(tr); toast(`Sold ${tr.name}`); closePanel(); };
}
function showTrains() {
  const list = [...G.trains.values()];
  const locos = S.LOCOS.filter(m => m.year <= year() + 12);
  openPanel(`<h2>Trains</h2><div class="sub">${list.length} running</div>
    ${list.map(t => `<div class="train" data-t="${t.id}"><b>${t.name}</b><small>${S.trainStatus(t)} · ${money(t.profitYear)} this year</small></div>`).join('') || '<div class="note">No trains yet. Build two stations, join them with track, then buy a locomotive below.</div>'}
    <h3>Buy a locomotive</h3>
    ${locos.map(m => { const ok = m.year <= year(), afford = G.cash >= m.cost; return `<button class="loco ${ok && afford ? '' : 'off'}" data-m="${m.id}" ${ok && afford ? '' : 'disabled'}>
      <b>${m.name} <small style="display:inline;color:var(--dim)">${m.type}</small></b><span class="price">${ok ? money(m.cost) : m.year}</span>
      <small>${Math.round(m.speed * 3)} mph · ${m.cars} cars · ${money(m.op)}/yr to run${ok ? '' : ` · available ${m.year}`}</small></button>`; }).join('')}`, { kind: 'trains' });
  document.querySelectorAll('.train[data-t]').forEach(el => el.onclick = () => showTrain(G.trains.get(+el.dataset.t)));
  document.querySelectorAll('.loco[data-m]').forEach(el => el.onclick = () => {
    const m = S.LOCOS.find(x => x.id === el.dataset.m);
    if (G.stations.size < 2) { toast('Build at least two stations first', 'bad'); return; }
    G.routeEdit = { train: null, model: m, stops: [] }; setTool('route');
  });
}
function showRoute() {
  const r = G.routeEdit; if (!r) return;
  const bad = r.stops.length >= 2 ? S.routeProblems(r.stops) : [];
  openPanel(`<h2>${r.train ? 'Edit route' : 'New train'}</h2><div class="sub">${r.model.name} ${r.model.type} · click stations on the map</div>
    ${r.stops.map((id, i) => `<div class="stop"><span class="n">${i + 1}</span>${G.stations.get(id)?.name ?? '?'}<button class="x" data-i="${i}">×</button></div>
      ${r.stops.length >= 2 ? `<div class="leg ${bad.includes(i) ? 'bad' : 'ok'}">${bad.includes(i) ? '✗ no track to' : '✓ track to'} ${G.stations.get(r.stops[(i + 1) % r.stops.length])?.name ?? ''}</div>` : ''}`).join('') || '<div class="note">Click the first station.</div>'}
    <div class="btns"><button class="btn" id="bOk" ${r.stops.length >= 2 && !bad.length ? '' : 'disabled'}>${r.train ? 'Save route' : `Buy for ${money(r.model.cost)}`}</button><button class="btn ghost" id="bCancel">Cancel</button></div>
    ${bad.length ? '<div class="note">Every stop needs track to the next one, and the last back to the first. Trains can only reverse at stations.</div>' : ''}`, { kind: 'route' });
  document.querySelectorAll('.stop .x').forEach(b => b.onclick = () => { r.stops.splice(+b.dataset.i, 1); showRoute(); });
  $('#bOk').onclick = confirmRoute;
  $('#bCancel').onclick = () => { const t = r.train; G.routeEdit = null; setTool(t ? 'inspect' : 'trains'); if (t) showTrain(t); };
}
function confirmRoute() {
  const r = G.routeEdit; if (!r || r.stops.length < 2 || S.routeProblems(r.stops).length) return;
  if (r.train) {
    r.train.route = r.stops.slice(); r.train.cur = 0; r.train.next = 1 % r.stops.length;
    if (r.train.state === 'noroute') r.train.timer = 0;
    toast(`${r.train.name} has a new route`, 'good');
    const t = r.train; G.routeEdit = null; setTool('inspect'); showTrain(t);
  } else {
    if (G.cash < r.model.cost) { toast('Not enough cash', 'bad'); return; }
    const tr = S.buyTrain(r.model, r.stops);
    FX.whistle(0.07);
    toast(`${tr.name} is in service`, 'good');
    G.routeEdit = null; setTool('inspect'); showTrain(tr);
  }
}
function showFinance() {
  const L = G.ledger, row = (k, l) => `<div class="row"><span>${l}</span><span>${money(L.cur[k])}${L.last ? ` <small style="color:var(--dim)">/ ${money(L.last[k])}</small>` : ''}</span></div>`;
  const profit = (x) => x.revenue - x.ops - x.maint - x.interest;
  openPanel(`<h2>Finances</h2><div class="sub">${dateStr()} · this year${L.last ? ' / last year' : ''}</div>
    <div class="row"><span>Cash</span><span>${money(G.cash)}</span></div>
    <div class="row"><span>Loan (6%)</span><span>${money(G.loan)}</span></div>
    <div class="row"><span>Net worth</span><span>${money(netWorth())}</span></div>
    <h3>Income statement</h3>
    ${row('revenue', 'Freight & fares')}${row('ops', 'Train running')}${row('maint', 'Track upkeep')}${row('interest', 'Interest')}
    <div class="row"><span>Operating profit</span><span class="${profit(L.cur) >= 0 ? 'pos' : 'neg'}">${money(profit(L.cur))}</span></div>
    ${row('build', 'Construction')}
    <h3>Bank</h3>
    <div class="btns"><button class="btn" id="bBorrow" ${G.loan >= 1_500_000 ? 'disabled' : ''}>Borrow $250k</button><button class="btn ghost" id="bRepay" ${G.loan <= 0 || G.cash < 250_000 ? 'disabled' : ''}>Repay $250k</button></div>
    <div class="note">You can borrow up to $1.5M. Interest is charged daily.</div>
    <h3>Goal</h3><div class="note">Reach a net worth of <b>${money(GOAL.worth)}</b> before ${GOAL.year}.${G.goalWon ? ' <b style="color:var(--good)">Achieved!</b>' : ''}</div>`, { kind: 'finance' });
  $('#bBorrow').onclick = () => { G.loan += 250000; G.cash += 250000; showFinance(); };
  $('#bRepay').onclick = () => { G.loan -= 250000; G.cash -= 250000; showFinance(); };
}
function showSettings() {
  const seg = (name, opts, cur) => `<div class="seg" data-set="${name}">${opts.map(([v, l]) => `<button data-v="${v}" class="${cur === v ? 'on' : ''}">${l}</button>`).join('')}</div>`;
  openPanel(`<h2>Settings</h2><div class="sub">Map seed ${G.seed}</div>
    <h3>Graphics</h3>${seg('quality', [['low', 'Low'], ['medium', 'Medium'], ['high', 'High']], G.quality)}
    <div class="note">Changing quality reloads the page (your game is saved first).</div>
    <h3>Time of day</h3>${seg('tod', [['morning', 'Morning'], ['day', 'Midday'], ['evening', 'Evening']], G.tod)}
    <h3>Labels</h3>${seg('labels', [['1', 'On'], ['0', 'Off']], G.labels ? '1' : '0')}
    <h3>Sound</h3>${seg('sound', [['1', 'On'], ['0', 'Off']], G.sound ? '1' : '0')}
    <h3>Game</h3><div class="btns"><button class="btn" id="bSave">Save</button><button class="btn ghost" id="bLoad">Load</button><button class="btn danger" id="bNew">New map</button></div>
    <div class="note">The game also saves itself every new year.</div>`, { kind: 'settings' });
  document.querySelectorAll('.seg').forEach(s => s.querySelectorAll('button').forEach(b => b.onclick = () => {
    const k = s.dataset.set, v = b.dataset.v;
    if (k === 'quality') { G.quality = v; savePrefs(); if (G.started) saveGame(true); location.search = G.started ? '?load=1' : ''; return; }
    if (k === 'tod') { G.tod = v; applyTimeOfDay(); }
    if (k === 'labels') { G.labels = v === '1'; document.body.classList.toggle('nolabels', !G.labels); }
    if (k === 'sound') G.sound = v === '1';
    savePrefs(); showSettings();
  }));
  $('#bSave').onclick = () => saveGame();
  $('#bLoad').onclick = () => { if (localStorage.getItem(SAVE_KEY)) location.search = '?load=1'; else toast('No saved game', 'bad'); };
  $('#bNew').onclick = () => { if (confirm('Start a new map? Unsaved progress is lost.')) location.search = '?new=1'; };
}
function refreshPanel() {
  const s = G.selection; if (!s || $('#panel').classList.contains('hidden')) return;
  if (s.kind === 'station') showStation(s.obj);
  else if (s.kind === 'train') { if (G.trains.has(s.obj.id)) showTrain(s.obj); else closePanel(); }
  else if (s.kind === 'industry') showIndustry(s.obj);
  else if (s.kind === 'city') showCity(s.obj);
  else if (s.kind === 'trains') showTrains();
}

// ---------------- pointer input ----------------
let drag = null, down = null, stationAxisAngle = 0;
const el = renderer.domElement;
el.addEventListener('contextmenu', e => e.preventDefault());
el.addEventListener('pointerdown', e => {
  down = { x: e.clientX, y: e.clientY, b: e.button };
  if (e.button !== 0 || !G.started) return;
  if (G.tool === 'track') {
    const p = pickGround(e); if (!p) return;
    drag = { sx: p.x, sz: p.z, a: T.snapRef(p.x, p.z), plan: null };
  }
});
el.addEventListener('pointermove', e => {
  if (!G.started) return;
  if (G.tool === 'track') {
    const p = pickGround(e);
    if (!p) return;
    if (drag) {
      drag.a = T.snapRef(drag.sx, drag.sz, { toward: p });
      const b = T.snapRef(p.x, p.z, { toward: drag.a });
      drag.b = b; drag.plan = T.planEdge(drag.a, b);
      T.showPreview(drag.plan);
      const pl = drag.plan;
      if (!pl.pts.length) { tip(e, `<span class="bad">${pl.reason}</span>`); return; }
      const afford = G.cash >= pl.cost;
      tip(e, `<b>${money(pl.cost)}</b> · ${Math.round(pl.len)} m · grade ${(pl.maxGrade * 100).toFixed(1)}%${pl.bridge > 1 ? ` · bridge ${Math.round(pl.bridge)} m` : ''}${pl.demolish ? ` · demolishes ${pl.demolish}` : ''}
        <br>${pl.valid ? (afford ? '<span class="ok">Release to build</span>' : '<span class="bad">Not enough cash</span>') : `<span class="bad">${pl.reason}</span>`}`);
    } else {
      const r = T.snapRef(p.x, p.z);
      tip(e, r.kind === 'free' ? 'Drag to lay track' : r.kind === 'edge' ? 'Branch off this track' : r.node.station ? `From ${r.node.station.name}` : 'Continue this track');
    }
  } else if (G.tool === 'station') {
    const p = pickGround(e); if (!p) return;
    const axis = { x: Math.sin(stationAxisAngle), z: Math.cos(stationAxisAngle) };
    const site = S.stationSite(p.x, p.z, axis);
    FX.showGhost(makeStation, site.x, site.y ?? p.y, site.z, site.axis, site.ok);
    FX.showRing(site.x, site.z, S.STATION_R, site.ok ? 0xffd27a : 0xff6a5a);
    if (site.ok) {
      const c = S.coverageAt(site.x, site.z);
      tip(e, `<b>${money(site.cost)}</b>${site.ref.kind === 'edge' ? ' · on existing track' : ''}<br>Supplies: ${[...c.supplies].map(k => S.CARGO[k].name).join(', ') || 'nothing'}<br>Accepts: ${[...c.accepts].map(k => S.CARGO[k].name).join(', ') || 'nothing'}`);
    } else tip(e, `<span class="bad">${site.reason}</span>`);
  } else if (G.tool === 'bulldoze') {
    const p = pickGround(e); if (!p) return;
    const st = [...G.stations.values()].find(s => Math.hypot(s.x - p.x, s.z - p.z) < 9);
    if (st) { T.highlightEdge(null); FX.showRing(st.x, st.z, 10, 0xff6a5a); tip(e, `Remove <b>${st.name}</b>`); return; }
    FX.hideRing();
    const ep = T.nearestEdgePoint(p.x, p.z, 4);
    T.highlightEdge(ep?.edge ?? null);
    if (ep) tip(e, `Remove track · refund ${money(ep.edge.cost * 0.4)}`); else hideTip();
  } else if (G.tool === 'route') {
    const p = pickGround(e);
    const st = p && [...G.stations.values()].find(s => Math.hypot(s.x - p.x, s.z - p.z) < 14);
    if (st) { FX.showRing(st.x, st.z, 10, 0xffd27a); tip(e, `Add <b>${st.name}</b>`); } else { FX.hideRing(); hideTip(); }
  }
});
el.addEventListener('pointerup', e => {
  if (!G.started || !down) return;
  const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6;
  const btn = down.b; down = null;
  if (btn !== 0) return;
  if (G.tool === 'track') {
    if (drag?.plan && moved) {
      const pl = drag.plan;
      if (!pl.valid) toast(pl.reason, 'bad');
      else if (G.cash < pl.cost) toast(`Need ${money(pl.cost)} — borrow from the bank in Finances`, 'bad');
      else { T.buildEdge(pl); FX.click(); S.refreshCoverage(); }
    }
    drag = null; T.clearPreview(); hideTip();
    return;
  }
  if (moved) return;
  if (G.tool === 'station') {
    const p = pickGround(e); if (!p) return;
    const site = S.stationSite(p.x, p.z, { x: Math.sin(stationAxisAngle), z: Math.cos(stationAxisAngle) });
    if (!site.ok) { toast(site.reason, 'bad'); return; }
    if (G.cash < site.cost) { toast('Not enough cash', 'bad'); return; }
    const st = S.buildStation(site);
    addStationLabel(st);
    FX.click(); FX.hideGhost();
    toast(`Built ${st.name}`, 'good');
  } else if (G.tool === 'bulldoze') {
    const p = pickGround(e); if (!p) return;
    const st = [...G.stations.values()].find(s => Math.hypot(s.x - p.x, s.z - p.z) < 9);
    if (st) { const err = S.removeStation(st); if (err) toast(err, 'bad'); else { scene.remove(st.label); st.label.element.remove(); FX.hideRing(); FX.click(); } return; }
    const ep = T.nearestEdgePoint(p.x, p.z, 4);
    if (ep) {
      if (ep.edge.a === ep.edge.b) return;
      const n1 = G.nodes.get(ep.edge.a), n2 = G.nodes.get(ep.edge.b);
      // don't strand a station's own stub without warning: just remove
      T.removeEdge(ep.edge); T.highlightEdge(null); FX.click();
      void n1; void n2;
    }
  } else if (G.tool === 'route') {
    const p = pickGround(e);
    const st = p && [...G.stations.values()].find(s => Math.hypot(s.x - p.x, s.z - p.z) < 14);
    if (st && G.routeEdit) {
      const r = G.routeEdit;
      if (r.stops[r.stops.length - 1] !== st.id) r.stops.push(st.id);
      FX.click(); showRoute();
    }
  } else {
    const o = pickObject(e);
    if (!o) { closePanel(); return; }
    if (o.kind === 'station') showStation(o);
    else if (o.kind === 'industry') showIndustry(o);
    else if (o.kind === 'city') showCity(o);
    else if (o.kind === 'train') showTrain(o);
  }
});
addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT') return;
  const k = e.key.toLowerCase();
  keys.add(k);
  if (!G.started) return;
  if (k === ' ') { e.preventDefault(); setSpeed(G.speed === 0 ? (G.lastSpeed || 1) : 0); }
  if (k === '1') setTool('inspect'); if (k === '2') setTool('track'); if (k === '3') setTool('station'); if (k === '4') setTool('trains'); if (k === '5') setTool('bulldoze');
  if (k === 'r' && G.tool === 'station') { stationAxisAngle += Math.PI / 8; }
  if (k === 'escape') { if (G.tool === 'route') { G.routeEdit = null; setTool('trains'); } else if (drag) { drag = null; T.clearPreview(); hideTip(); } else { setTool('inspect'); closePanel(); } }
  if (k === 'enter' && G.tool === 'route') confirmRoute();
});
addEventListener('keyup', e => keys.delete(e.key.toLowerCase()));
addEventListener('blur', () => keys.clear());
document.querySelectorAll('#tools button').forEach(b => b.onclick = () => setTool(b.dataset.tool));
document.querySelectorAll('.speeds button').forEach(b => b.onclick = () => setSpeed(+b.dataset.speed));
function setSpeed(s) { if (s > 0) G.lastSpeed = s; G.speed = s; document.querySelectorAll('.speeds button').forEach(b => b.classList.toggle('on', +b.dataset.speed === s)); }

// ---------------- labels in the world ----------------
function addCityLabel(c) {
  c.label = FX.label('', 'city', c.x, W.heightAt(c.x, c.z) + 18, c.z);
  updateCityLabel(c);
}
function updateCityLabel(c) { c.label.element.innerHTML = `${c.name}<small>${c.pop.toLocaleString()}</small>`; }
function addStationLabel(st) { st.label = FX.label(st.name, 'station', st.x, st.y + 7, st.z); }

// ---------------- camera follow ----------------
function followSnap() {
  const tr = G.follow; if (!tr) return;
  const p = tr.units[0].group.position;
  const off = camera.position.clone().sub(controls.target);
  if (off.length() > 120) off.setLength(60);
  controls.target.copy(p); camera.position.copy(p).add(off);
}
function followTick(dt) {
  const tr = G.follow; if (!tr || !G.trains.has(tr.id)) { G.follow = null; return; }
  const p = tr.units[0].group.position;
  const d = p.clone().sub(controls.target).multiplyScalar(Math.min(1, dt * 6));
  controls.target.add(d); camera.position.add(d);
}

// ---------------- save / load ----------------
function saveGame(quiet = false) {
  const r2 = (v) => Math.round(v * 100) / 100;
  const data = {
    v: 1, seed: G.seed, cash: G.cash, loan: G.loan, day: G.day, nextId: G.nextId, assetValue: G.assetValue, ledger: G.ledger, goalWon: G.goalWon,
    nodes: [...G.nodes.values()].map(n => [n.id, r2(n.x), r2(n.y), r2(n.z), n.axis ? r2(n.axis.x * 1000) / 1000 : null, n.axis ? r2(n.axis.z * 1000) / 1000 : null]),
    edges: [...G.edges.values()].map(e => [e.id, e.a, e.b, Math.round(e.cost), e.pts.flatMap(p => [r2(p.x), r2(p.y), r2(p.z)])]),
    stations: [...G.stations.values()].map(s => ({ id: s.id, node: s.node.id, name: s.name, stock: s.stock, demand: s.demand, free: s.free })),
    trains: [...G.trains.values()].map(t => ({ id: t.id, name: t.name, model: t.model.id, route: t.route, cur: t.cur, next: t.next, cars: t.cars, profitYear: t.profitYear, profitLast: t.profitLast, lifetime: t.lifetime, age: t.age })),
    cities: G.cities.map(c => [c.pop, c.growth]),
    industries: G.industries.map(i => [i.inp, i.produced, i.producedLast]),
  };
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(data)); if (!quiet) toast('Game saved', 'good'); }
  catch { toast('Could not save (storage full or blocked)', 'bad'); }
}
function loadSave() { try { return JSON.parse(localStorage.getItem(SAVE_KEY)); } catch { return null; } }
function applySave(d) {
  Object.assign(G, { cash: d.cash, loan: d.loan, day: d.day, assetValue: d.assetValue, ledger: d.ledger, goalWon: d.goalWon, nextId: d.nextId });
  for (const [id, x, y, z, ax, az] of d.nodes) {
    const n = { id, x, y, z, axis: ax == null ? null : { x: ax, z: az }, edges: new Set(), station: null };
    G.nodes.set(id, n);
  }
  // replay construction in the order it happened so the land is carved the same way
  const ops = [...d.edges.map(e => ({ id: e[0], e })), ...d.stations.map(s => ({ id: s.id, s }))].sort((a, b) => a.id - b.id);
  for (const op of ops) {
    if (op.e) {
      const [id, a, b, cost, flat] = op.e, pts = [];
      for (let i = 0; i < flat.length; i += 3) pts.push({ x: flat[i], y: flat[i + 1], z: flat[i + 2] });
      const e = T.addEdge(G.nodes.get(a), G.nodes.get(b), pts, cost, true);
      G.edges.delete(e.id); e.id = id; G.edges.set(id, e);
    } else {
      const s = op.s, n = G.nodes.get(s.node);
      if (s.free) { const pad = []; for (let k = -13; k <= 13; k++) pad.push({ x: n.x + n.axis.x * k, y: n.y, z: n.z + n.axis.z * k }); W.carve(pad, { inner: 3, bed: true }); }
      const st = S.buildStation({ axis: n.axis, ref: { kind: s.free ? 'free' : 'node' } }, s);
      addStationLabel(st);
    }
  }
  d.cities.forEach(([pop, growth], i) => { const c = G.cities[i]; if (!c) return; c.pop = pop; c.growth = growth; W.growCity(c, false); });
  d.industries.forEach(([inp, p, pl], i) => { const ind = G.industries[i]; if (ind) { ind.inp = inp; ind.produced = p; ind.producedLast = pl; } });
  S.refreshCoverage();
  for (const t of d.trains) {
    const model = S.LOCOS.find(m => m.id === t.model); if (!model) continue;
    const tr = { ...t, model, kind: 'train', path: null, d: 0, v: 0, state: 'load', timer: 0.5 + Math.random(), smokeAcc: 0 };
    S.spawnTrain(tr);
  }
  G.nextId = d.nextId;
}

// ---------------- HUD ----------------
let hudAcc = 0;
function updateHud(dt) {
  hudAcc += dt; if (hudAcc < 0.25) return; hudAcc = 0;
  $('#cash').textContent = money(G.cash); $('#cash').className = G.cash < 0 ? 'neg' : '';
  const nw = netWorth();
  $('#worth').textContent = money(nw);
  $('#date').textContent = dateStr();
  $('#goalText').textContent = G.goalWon ? 'Goal reached!' : `Goal: ${money(GOAL.worth)} by ${GOAL.year}`;
  $('#goalBar').style.width = Math.max(0, Math.min(100, nw / GOAL.worth * 100)) + '%';
  if (!G.goalWon && nw >= GOAL.worth && year() < GOAL.year) { G.goalWon = true; toast(`<b>You did it!</b> A ${money(GOAL.worth)} railroad empire before ${GOAL.year}. Keep building!`, 'good'); FX.whistle(0.1); }
  for (const c of G.cities) updateCityLabel(c);
}
let panelAcc = 0;

// ---------------- events from the simulation ----------------
G.onRevenue = (st, total, tr) => {
  FX.moneyPop(st.x, st.y, st.z, `+${money(total)}`);
  if (camera.position.distanceTo(st.group.position) < 220) FX.chime(0.03);
};
G.onDepart = (tr) => { if (G.follow === tr || (G.selection?.obj === tr)) FX.whistle(0.05); };
G.blocked = (x, z, r) => T.isBlocked(x, z, r);

// ---------------- boot ----------------
function resize() {
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight); labelRenderer.setSize(innerWidth, innerHeight);
  if (composer) { composer.setSize(innerWidth, innerHeight); }
}
addEventListener('resize', resize);

const params = new URLSearchParams(location.search);
const save = loadSave();
const loading = params.has('load') && save;
const seed = loading ? save.seed : (params.get('seed') ? +params.get('seed') : Math.floor(Math.random() * 1e6));

setTimeout(boot, 30);
function boot() {
  W.generate(seed);
  W.buildWater();
  applyTimeOfDay();
  setupComposer();
  FX.initSmoke();
  for (const c of G.cities) addCityLabel(c);
  document.body.classList.toggle('nolabels', !G.labels);
  // frame the biggest town
  const c0 = G.cities[0];
  if (c0) { controls.target.set(c0.x, W.heightAt(c0.x, c0.z), c0.z); camera.position.set(c0.x + 140, 170, c0.z + 160); }
  $('#loading').classList.add('hidden');
  if (loading) { applySave(save); start(); }
  else {
    $('#title').classList.remove('hidden');
    $('#continueGame').classList.toggle('hidden', !save);
    if (params.has('new')) { $('#title').classList.add('hidden'); start(); }
  }
  requestAnimationFrame(loop);
}
$('#newGame').onclick = () => { $('#title').classList.add('hidden'); start(); };
$('#continueGame').onclick = () => { location.search = '?load=1'; };
function start() {
  G.started = true;
  $('#hud').classList.remove('hidden');
  $('#title').classList.add('hidden');
  setSpeed(1); setTool('inspect');
  if (!loading) {
    history.replaceState(null, '', location.pathname);
    toast(`Welcome to the ${year()} frontier. You have ${money(G.cash)} to start a railroad.`);
    setTimeout(() => toast('Tip: put a station in each of two big towns, join them with track, and buy a train.'), 3500);
  } else history.replaceState(null, '', location.pathname);
}

// ---------------- main loop ----------------
const clock = new THREE.Clock();
let titleSpin = 0, lastYear = null;
function loop() {
  requestAnimationFrame(loop);
  const dt = Math.min(0.05, clock.getDelta());
  const gdt = G.started ? dt * G.speed : 0;
  if (G.started) {
    if (lastYear === null) lastYear = year();
    G.day += gdt / DAY_SEC;
    if (gdt > 0) S.econTick(gdt / DAY_SEC);
    if (year() !== lastYear) {
      lastYear = year();
      const L = G.ledger; L.last = L.cur; L.cur = blankLedger();
      S.yearTick();
      const op = L.last.revenue - L.last.ops - L.last.maint - L.last.interest;
      toast(`<b>${lastYear}</b> · last year's operating profit ${money(op)}`, op >= 0 ? 'good' : 'bad');
      const avail = S.LOCOS.find(m => m.year === lastYear);
      if (avail) toast(`New locomotive available: <b>${avail.name} ${avail.type}</b>`, 'good');
      saveGame(true);
    }
    S.updateTrains(gdt, FX.emitSmoke);
    cameraKeys(dt);
    if (G.follow) followTick(dt);
    updateHud(dt);
    panelAcc += dt; if (panelAcc > 0.5) { panelAcc = 0; if (G.tool === 'inspect' || G.tool === 'trains') refreshPanel(); }
  } else {
    // slow orbit behind the title
    titleSpin += dt * 0.04;
    const t = controls.target, off = camera.position.clone().sub(t).applyAxisAngle(new THREE.Vector3(0, 1, 0), dt * 0.04);
    camera.position.copy(t).add(off);
  }
  if (gdt > 0) FX.industrySmoke(gdt);
  FX.updateSmoke(gdt || 0);
  FX.updatePops(dt);
  W.tickBuildings(dt);
  W.tickWater(clock.elapsedTime);
  controls.update();
  clampTarget();
  // keep the shadow camera around what we're looking at
  const dist = camera.position.distanceTo(controls.target);
  const ext = THREE.MathUtils.clamp(dist * 0.9, 70, 320);
  const sc = sun.shadow.camera;
  if (Math.abs(sc.right - ext) > 1) { sc.left = -ext; sc.right = ext; sc.top = ext; sc.bottom = -ext; sc.near = 1; sc.far = 1400; sc.updateProjectionMatrix(); }
  const texel = (ext * 2) / sun.shadow.mapSize.x;
  const tx = Math.round(controls.target.x / texel) * texel, tz = Math.round(controls.target.z / texel) * texel;
  sun.target.position.set(tx, controls.target.y, tz);
  sun.position.copy(sun.target.position).addScaledVector(sunDir, 600);
  renderFrame();
}
function renderFrame() {
  if (composer) composer.render(); else renderer.render(scene, camera);
  labelRenderer.render(scene, camera);
}
void START_YEAR; void spend;
