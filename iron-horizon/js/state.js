// Shared game state. Every module reads and writes this one object.
export const START_YEAR = 1835;
export const DAY_SEC = 0.25;            // real seconds per game day at 1x
export const GOAL = { worth: 5_000_000, year: 1880 };

export const G = {
  scene: null, camera: null, renderer: null, controls: null,
  seed: 1, rnd: Math.random, noise: null,
  started: false, day: 0, speed: 1,
  cash: 600_000, loan: 0, assetValue: 0,
  nodes: new Map(), edges: new Map(), stations: new Map(), trains: new Map(),
  cities: [], industries: [],
  nextId: 1,
  ledger: { cur: blankLedger(), last: null },
  tool: 'inspect', selection: null, routeEdit: null, follow: null,
  quality: 'high', labels: true, sound: true, tod: 'day',
  goalWon: false,
};

export function blankLedger() { return { revenue: 0, ops: 0, maint: 0, interest: 0, build: 0 }; }
export const newId = () => G.nextId++;
export const year = () => START_YEAR + Math.floor(G.day / 365);
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const dateStr = () => `${MONTHS[Math.floor((G.day % 365) / 30.42) % 12]} ${year()}`;

export function spend(amount, cat = 'build') {
  G.cash -= amount;
  G.ledger.cur[cat] += amount;
  if (cat === 'build') G.assetValue += amount * 0.6;
}
export function earn(amount) { G.cash += amount; G.ledger.cur.revenue += amount; }

export function money(v) {
  const s = v < 0 ? '-' : '', a = Math.abs(v);
  if (a >= 1e6) return `${s}$${(a / 1e6).toFixed(a >= 1e7 ? 1 : 2)}M`;
  if (a >= 1e3) return `${s}$${(a / 1e3).toFixed(a >= 1e5 ? 0 : 1)}k`;
  return `${s}$${Math.round(a)}`;
}

export function netWorth() {
  let trains = 0;
  for (const t of G.trains.values()) trains += t.model.cost * Math.max(0.3, 1 - t.age * 0.04);
  return G.cash - G.loan + G.assetValue + trains;
}
