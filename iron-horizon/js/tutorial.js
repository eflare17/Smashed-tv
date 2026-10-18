// Built-in tutorial: a card that walks a new player through their first line, step by step.
// Each step finishes by itself when the game sees the player has done it.
import { G } from './state.js';
import * as T from './track.js';
import * as FX from './fx.js';
import * as W from './world.js';

let api = null, card = null, idx = -1, acc = 0, marks = [], camStart = null, pair = null;

const stationTowns = () => new Set([...G.stations.values()].map(s => s.coverCity).filter(Boolean)).size;
function connected() {
  const sts = [...G.stations.values()];
  for (let i = 0; i < sts.length; i++) for (let j = i + 1; j < sts.length; j++)
    if (T.findPath(sts[i].node.id, sts[j].node.id)) return true;
  return false;
}
function camMoved() {
  if (!camStart) return false;
  return G.camera.position.distanceTo(camStart.cam) > 30 || G.controls.target.distanceTo(camStart.target) > 20;
}

const STEPS = [
  {
    title: 'Welcome, railroad boss!',
    text: `You run a railroad company. You'll build track between towns and run trains to earn money.
      <br><br>First, look around:<br>• <b>Left-drag</b> moves the map<br>• <b>Right-drag</b> turns it<br>• <b>Scroll</b> zooms in and out`,
    enter() { camStart = { cam: G.camera.position.clone(), target: G.controls.target.clone() }; },
    done: camMoved, next: true,
  },
  {
    title: 'Meet the towns',
    text: `Towns make <b>passengers</b> and <b>mail</b> for your trains to carry, and they buy goods and food.
      <br><br><b>Click on a town</b> (its houses or town hall) to see what it wants.`,
    tool: 'inspect', marks: true,
    done: () => G.selection?.kind === 'city',
  },
  {
    title: 'Pick the station tool',
    text: 'Click the flashing <b>house button</b> on the left, or press <b>3</b>.',
    highlight: 'station', marks: true,
    done: () => G.tool === 'station',
  },
  {
    title: 'Build your first station',
    text: `Click near the edge of a town marked <b>★ Start here</b>.
      <br><br>The gold ring shows what the station collects from: get lots of houses inside it. Press <b>R</b> to turn the station before you click.`,
    highlight: 'station', marks: true,
    done: () => stationTowns() >= 1,
  },
  {
    title: 'Build a second station',
    text: 'Now build a station in the <b>other</b> marked town, the same way.',
    highlight: 'station', marks: true,
    done: () => stationTowns() >= 2,
  },
  {
    title: 'Pick the track tool',
    text: 'Click the flashing <b>track button</b>, or press <b>2</b>.',
    highlight: 'track',
    done: () => G.tool === 'track',
  },
  {
    title: 'Join the two stations',
    text: `<b>Press, drag</b> from one station to the other, then <b>let go</b>.
      <br><br>Green means it can be built. Red means something's in the way, and the box by the mouse says what.
      <br><br>Blocked? Build it in pieces: drag to open ground, let go, then drag on from the end of the new track.`,
    highlight: 'track',
    done: connected,
  },
  {
    title: 'Buy a train',
    text: `Click the flashing <b>train button</b> (or press <b>4</b>) and choose the <b>Comet</b>.
      <br><br>Then click your <b>two stations</b> on the map and press <b>Buy</b>.`,
    highlight: 'trains',
    done: () => G.trains.size > 0,
  },
  {
    title: 'Make some money',
    text: `Your train picks up passengers and mail and carries them to the other town.
      <br><br>Time is running now. Click <b>▶▶</b> at the top to speed it up, and watch for your first <b style="color:var(--gold2)">+$</b>.`,
    enter() { api.setSpeed(2); },
    done: () => G.ledger.cur.revenue > 0 || (G.ledger.last?.revenue ?? 0) > 0,
  },
  {
    title: "You're in business!",
    text: `Nice work. Ways to grow:
      <ul><li>Add more towns and trains. Long routes pay more.</li>
      <li>Put stations by <b>mines, farms and forests</b>, and carry their cargo to the mill, factory or town that wants it. Click any building to see what it makes and needs.</li>
      <li>Coal + iron ore → <b>steel mill</b> → steel. Steel + lumber → <b>factory</b> → goods that towns love.</li>
      <li>Short of money? Borrow in <b>Finances</b> (the bar-chart button).</li></ul>
      Goal: a net worth of <b>$5 million by 1880</b>.`,
    final: true,
  },
];

export const active = () => idx >= 0;

export function start(hooks) {
  api = hooks;
  if (!card) build();
  pickTowns();
  api.setSpeed(0);
  go(0);
}

export function stop(finished) {
  idx = -1;
  card?.classList.add('hidden');
  clearHighlight(); clearMarks();
  try { localStorage.setItem('ironHorizonTutorialDone', '1'); } catch { }
  if (!finished && G.speed === 0) api?.setSpeed(1);
}
export const seen = () => { try { return localStorage.getItem('ironHorizonTutorialDone') === '1'; } catch { return false; } };

function build() {
  card = document.createElement('div');
  card.id = 'tutorial';
  card.innerHTML = `<div class="tut-top"><span class="tut-step"></span><button class="tut-skip">Skip tutorial</button></div>
    <h4></h4><div class="tut-text"></div><div class="tut-dots"></div>
    <div class="tut-foot"><span class="tut-wait">Do this to move on</span><button class="btn tut-next">Next</button></div>`;
  document.getElementById('hud').appendChild(card);
  card.querySelector('.tut-skip').onclick = () => stop(false);
  card.querySelector('.tut-next').onclick = () => { if (STEPS[idx].final) stop(true); else go(idx + 1); };
}

function go(i) {
  idx = i;
  const s = STEPS[i];
  card.classList.remove('hidden');
  card.querySelector('.tut-step').textContent = `Tutorial · step ${i + 1} of ${STEPS.length}`;
  card.querySelector('h4').innerHTML = s.title;
  card.querySelector('.tut-text').innerHTML = s.text;
  card.querySelector('.tut-dots').innerHTML = STEPS.map((_, k) => `<i class="${k < i ? 'done' : k === i ? 'on' : ''}"></i>`).join('');
  const next = card.querySelector('.tut-next');
  next.textContent = s.final ? 'Finish' : 'Next';
  next.classList.toggle('hidden', !s.final && !s.next);
  card.querySelector('.tut-wait').classList.toggle('hidden', !!(s.final || s.next));
  card.classList.remove('pop'); void card.offsetWidth; card.classList.add('pop');
  clearHighlight();
  if (s.highlight) document.querySelector(`#tools button[data-tool="${s.highlight}"]`)?.classList.add('pulse');
  if (s.tool && G.tool !== s.tool) api.setTool(s.tool);
  if (s.marks) showMarks(); else clearMarks();
  s.enter?.();
  if (i > 0) FX.chime(0.04);
}

export function tick(dt) {
  if (idx < 0) return;
  acc += dt; if (acc < 0.3) return; acc = 0;
  const s = STEPS[idx];
  if (s.done && s.done()) go(idx + 1);
}

function clearHighlight() { document.querySelectorAll('#tools .pulse').forEach(b => b.classList.remove('pulse')); }

// two big towns close enough together for a first line
function pickTowns() {
  const big = G.cities.slice().sort((a, b) => b.pop - a.pop).slice(0, 5);
  let best = null;
  for (let i = 0; i < big.length; i++) for (let j = i + 1; j < big.length; j++) {
    const d = Math.hypot(big[i].x - big[j].x, big[i].z - big[j].z);
    const score = d - (big[i].pop + big[j].pop) / 200;
    if (!best || score < best.score) best = { a: big[i], b: big[j], score };
  }
  pair = best ? [best.a, best.b] : G.cities.slice(0, 2);
}
function showMarks() {
  if (marks.length || !pair) return;
  for (const c of pair) {
    const m = FX.label('★ Start here', 'tut-mark', c.x, W.heightAt(c.x, c.z) + 30, c.z);
    marks.push(m);
  }
}
function clearMarks() {
  for (const m of marks) { G.scene.remove(m); m.element.remove(); }
  marks = [];
}
// where the camera should look to see both starting towns
export function startView() {
  if (!pair) pickTowns();
  return pair ? { x: (pair[0].x + pair[1].x) / 2, z: (pair[0].z + pair[1].z) / 2, span: Math.hypot(pair[0].x - pair[1].x, pair[0].z - pair[1].z) } : null;
}
