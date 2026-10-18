// Smoke, floating labels, the catchment ring and a few synthesised sounds.
import * as THREE from 'three';
import { CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js';
import { G } from './state.js';
import * as W from './world.js';

// ---------------- smoke ----------------
const MAX = 4000;
let pts, geo, pos, size, alpha, shade, life = new Float32Array(MAX), vel = new Float32Array(MAX * 3), maxLife = new Float32Array(MAX), grow = new Float32Array(MAX);
let head = 0;
export function initSmoke() {
  geo = new THREE.BufferGeometry();
  pos = new Float32Array(MAX * 3); size = new Float32Array(MAX); alpha = new Float32Array(MAX); shade = new Float32Array(MAX);
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('size', new THREE.BufferAttribute(size, 1));
  geo.setAttribute('alpha', new THREE.BufferAttribute(alpha, 1));
  geo.setAttribute('shade', new THREE.BufferAttribute(shade, 1));
  const c = document.createElement('canvas'); c.width = c.height = 64;
  const x = c.getContext('2d'), gr = x.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.45, 'rgba(255,255,255,0.55)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = gr; x.fillRect(0, 0, 64, 64);
  const tex = new THREE.CanvasTexture(c);
  const m = new THREE.ShaderMaterial({
    uniforms: { map: { value: tex }, scale: { value: 600 }, light: { value: new THREE.Color(1, 0.97, 0.92) }, fogColor: { value: new THREE.Color() }, fogDensity: { value: 0 } },
    vertexShader: `attribute float size; attribute float alpha; attribute float shade; varying float vA; varying float vS; varying float vFog; uniform float scale; uniform float fogDensity;
      void main(){ vec4 mv = modelViewMatrix * vec4(position,1.0); gl_PointSize = size * scale / -mv.z; gl_Position = projectionMatrix * mv; vA = alpha; vS = shade;
      float d = -mv.z; vFog = 1.0 - exp(-fogDensity*fogDensity*d*d); }`,
    fragmentShader: `uniform sampler2D map; uniform vec3 light; uniform vec3 fogColor; varying float vA; varying float vS; varying float vFog;
      void main(){ vec4 t = texture2D(map, gl_PointCoord); vec3 col = mix(vec3(0.18), vec3(0.92), vS) * light; col = mix(col, fogColor, vFog); gl_FragColor = vec4(col, t.a * vA); }`,
    transparent: true, depthWrite: false,
  });
  pts = new THREE.Points(geo, m);
  pts.frustumCulled = false;
  pts.renderOrder = 10;
  G.scene.add(pts);
  for (let i = 0; i < MAX; i++) alpha[i] = 0;
}
export function emitSmoke(p, kind = 1, speed = 0) {
  const i = head; head = (head + 1) % MAX;
  pos[i * 3] = p.x + (Math.random() - 0.5) * 0.3; pos[i * 3 + 1] = p.y; pos[i * 3 + 2] = p.z + (Math.random() - 0.5) * 0.3;
  vel[i * 3] = (Math.random() - 0.5) * 0.6 + 0.6; vel[i * 3 + 1] = 2.2 + Math.random() * 1.2 + speed * 0.05; vel[i * 3 + 2] = (Math.random() - 0.5) * 0.6 + 0.3;
  life[i] = 0; maxLife[i] = kind === 2 ? 7 : kind < 1 ? 1.6 : 2.8 + Math.random() * 0.8;
  size[i] = kind === 2 ? 2.4 : kind < 1 ? 0.7 : 0.8; grow[i] = kind === 2 ? 2.2 : kind < 1 ? 0.9 : 1.15;
  shade[i] = kind === 2 ? 0.35 + Math.random() * 0.2 : kind < 1 ? 0.25 : 0.82 + Math.random() * 0.15;
}
export function updateSmoke(dt) {
  if (!geo) return;
  for (let i = 0; i < MAX; i++) {
    if (life[i] >= maxLife[i]) { alpha[i] = 0; continue; }
    life[i] += dt;
    const t = life[i] / maxLife[i];
    pos[i * 3] += vel[i * 3] * dt; pos[i * 3 + 1] += vel[i * 3 + 1] * dt; pos[i * 3 + 2] += vel[i * 3 + 2] * dt;
    vel[i * 3 + 1] *= 1 - dt * 0.5;
    size[i] += grow[i] * dt;
    alpha[i] = Math.min(1, t * 8) * (1 - t) * 0.55;
  }
  geo.attributes.position.needsUpdate = geo.attributes.size.needsUpdate = geo.attributes.alpha.needsUpdate = geo.attributes.shade.needsUpdate = true;
  if (G.scene.fog) { pts.material.uniforms.fogColor.value.copy(G.scene.fog.color); pts.material.uniforms.fogDensity.value = G.scene.fog.density; }
  pts.material.uniforms.scale.value = G.renderer.domElement.height * 0.9;
}
let chimAcc = 0;
export function industrySmoke(dt) {
  chimAcc += dt * 1.6;
  while (chimAcc > 1) {
    chimAcc -= 1;
    for (const ind of G.industries) {
      if (!ind.chimneys.length) continue;
      const busy = ind.def.accepts.length ? (ind.inp > 0.5 ? 1 : 0.35) : ind.stations.length ? 1 : 0.5;
      if (Math.random() > busy) continue;
      emitSmoke(ind.chimneys[Math.floor(Math.random() * ind.chimneys.length)], 2);
    }
  }
}
export function setSmokeLight(color) { if (pts) pts.material.uniforms.light.value.copy(color); }

// ---------------- labels ----------------
export function label(text, cls, x, y, z) {
  const el = document.createElement('div'); el.className = 'lbl ' + cls; el.textContent = text;
  const o = new CSS2DObject(el); o.position.set(x, y, z);
  G.scene.add(o);
  return o;
}
const pops = [];
export function moneyPop(x, y, z, text) {
  const o = label(text, 'pop', x, y + 6, z);
  pops.push({ o, t: 0, y: y + 6 });
}
export function updatePops(dt) {
  for (let i = pops.length - 1; i >= 0; i--) {
    const p = pops[i]; p.t += dt;
    p.o.position.y = p.y + p.t * 4;
    p.o.element.style.opacity = String(Math.max(0, 1 - Math.max(0, p.t - 1.4) / 0.8));
    if (p.t > 2.2) { G.scene.remove(p.o); p.o.element.remove(); pops.splice(i, 1); }
  }
}

// ---------------- catchment ring ----------------
let ring = null;
export function showRing(x, z, r, color = 0xffd27a) {
  const n = 96, arr = new Float32Array((n + 1) * 3);
  for (let i = 0; i <= n; i++) {
    const a = i / n * Math.PI * 2, px = x + Math.cos(a) * r, pz = z + Math.sin(a) * r;
    arr[i * 3] = px; arr[i * 3 + 1] = Math.max(W.heightAt(px, pz), W.WATER) + 0.6; arr[i * 3 + 2] = pz;
  }
  if (!ring) {
    ring = new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.9, depthTest: false }));
    ring.renderOrder = 20; G.scene.add(ring);
  }
  ring.geometry.setAttribute('position', new THREE.BufferAttribute(arr, 3));
  ring.material.color.set(color);
  ring.visible = true;
}
export function hideRing() { if (ring) ring.visible = false; }

// ghost of a station while placing it
let ghost = null;
export function showGhost(makeStation, x, y, z, axis, ok) {
  if (!ghost) {
    ghost = makeStation();
    ghost.traverse(o => { if (o.isMesh) { o.material = o.material.clone(); o.material.transparent = true; o.material.opacity = 0.6; o.castShadow = false; } });
    G.scene.add(ghost);
  }
  ghost.visible = true;
  ghost.position.set(x, y, z); ghost.rotation.y = Math.atan2(axis.x, axis.z);
  ghost.traverse(o => { if (o.isMesh) o.material.emissive?.set(ok ? 0x103010 : 0x501010); });
}
export function hideGhost() { if (ghost) ghost.visible = false; }

// ---------------- sound ----------------
let ac = null;
function ctx() { if (!ac) { try { ac = new AudioContext(); } catch { return null; } } if (ac.state === 'suspended') ac.resume(); return ac; }
export function whistle(vol = 0.08) {
  if (!G.sound) return; const a = ctx(); if (!a) return;
  const t = a.currentTime, g = a.createGain(), f = a.createBiquadFilter();
  f.type = 'bandpass'; f.frequency.value = 900; f.Q.value = 1.2;
  g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.08); g.gain.setValueAtTime(vol, t + 0.55); g.gain.linearRampToValueAtTime(0, t + 0.9);
  for (const fr of [466, 554, 698]) { const o = a.createOscillator(); o.type = 'sawtooth'; o.frequency.value = fr; o.frequency.linearRampToValueAtTime(fr * 0.985, t + 0.9); o.connect(f); o.start(t); o.stop(t + 1); }
  f.connect(g); g.connect(a.destination);
}
export function chime(vol = 0.05) {
  if (!G.sound) return; const a = ctx(); if (!a) return;
  const t = a.currentTime;
  [1318, 1760].forEach((fr, i) => {
    const o = a.createOscillator(), g = a.createGain(); o.type = 'sine'; o.frequency.value = fr;
    g.gain.setValueAtTime(0, t + i * 0.08); g.gain.linearRampToValueAtTime(vol, t + i * 0.08 + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.08 + 0.6);
    o.connect(g); g.connect(a.destination); o.start(t + i * 0.08); o.stop(t + i * 0.08 + 0.7);
  });
}
export function click(vol = 0.04) {
  if (!G.sound) return; const a = ctx(); if (!a) return;
  const t = a.currentTime, o = a.createOscillator(), g = a.createGain();
  o.type = 'square'; o.frequency.setValueAtTime(220, t); o.frequency.exponentialRampToValueAtTime(80, t + 0.12);
  g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
  o.connect(g); g.connect(a.destination); o.start(t); o.stop(t + 0.16);
}
