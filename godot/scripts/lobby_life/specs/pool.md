# Spec: the pool, dive tower (ladder, deck, springboard), diving, swimming, splashes, rubber ducks

Source: `/home/user/Smashed-tv/Smashed.html` (line numbers `Lnnnn` refer to it).
Coordinates: arena pixels, x right, y down the screen (ground plane), z / `dz` = height above the floor.
`ARENA = { w: 860, h: 520, wall: 18 }` (L615). `T.radius = 14` (L259). Everything here exists **only in the lobby**
(`!w.started && T.loungeFloor`), never in a run.

---------------------------------------------------------------------------------------------------
## 1. Constants and tunables

### 1.1 `T` table (L329-L337, slider ranges L520-L524)
| key | value | slider [min,max,step] | meaning |
|---|---|---|---|
| `loungeFloor` | 1 | [0,1,1] | lobby floor art on; whole pool/tower feature is off when 0 |
| `towerX` | 604 | [18,842,1] | x of the middle of the tower's legs |
| `towerY` | 190 | [18,502,1] | y where the tower's feet touch the floor |
| `towerScale` | 1.25 | [0.5,2,0.02] | art scale (art is drawn at half its pixel size times this) |
| `climbSpeed` | 120 | [30,400,5] | px/s up/down the ladder (dz units) |
| `boardWalk` | 120 | [30,400,5] | px/s along the board |
| `diveHop` | 240 | [0,600,10] | initial upward vz when leaving the board |
| `diveFwd` | 130 | [0,400,5] | initial vx when leaving the board |
| `swimSpeed` | 120 | [30,400,5] | target px/s in the water |

### 1.2 Pool rectangle (L767-L769)
```js
// the water, in arena pixels (measured off the floor art)
const POOL = { x0: 624, y0: 90, x1: 815, y1: 239 };
```
Derived rectangles (all from POOL):
| name | rect | used for |
|---|---|---|
| `inWater(x,y)` (L5671) | strict `x0+6 < x < x1-6`, `y0+6 < y < y1-6` → (630..809, 96..233) | "did the fall land in water", potato splashes |
| walkers' solid `water` box (L5776) | x0+6, y0+6, x1-6, y1-6 | non-diving players are pushed out with radius **1** (so you cannot walk in) |
| swim clamp `b` (L5755) | x 638..801, y 100..231 (`x0+14, x1-14, y0+10, y1-8`) | swimmer stays inside |
| water draw rect (L5903) | x 633..806, y 99..230 (`±9`) | animated water redraw clip |
| `duckBounds()` (L5831) | x 640..799, y 108..229 (`x0+16, x1-16, y0+18, y1-10`) | ducks stay inside |

### 1.3 Dive states (L5674)
```js
const DIVE = { CLIMB: 1, BOARD: 2, FALL: 3, SWIM: 4 };   // 0 = not diving
```

### 1.4 `towerGeo()` (L5655-L5670) — everything in arena pixels
```js
function towerGeo() {
  const k = T.towerScale;
  const climbY = T.towerY - 2;                 // just in front of the tower, so he draws over it
  const feet = climbY + T.radius * 0.9;        // where his feet sit on the floor while up there
  return {
    ladderX: T.towerX - 1.5 * k,
    climbY,
    baseY:   T.towerY + T.radius * 0.7 + 1,    // stepping off the bottom rung
    deckH:   feet - (T.towerY - 66 * k),       // top of the ladder
    boardH:  feet - (T.towerY - 72 * k),       // the board sits a touch higher
    boardX0: T.towerX + 15 * k,
    tipX:    T.towerX + 63 * k
  };
}
```
With default T (matches `calls.towerGeo` in godot/data/game_data.json):
`ladderX 602.125, climbY 188, baseY 200.8, deckH 93.1, boardH 100.6, boardX0 622.75, tipX 682.75`.

### 1.5 Tower solid box (L5637-L5640)
```js
function towerBox() { const k = T.towerScale;
  return { x0: T.towerX - 19 * k, x1: T.towerX + 19 * k, y0: T.towerY - 9 * k, y1: T.towerY }; }
```
= x 580.25..627.75, y 178.75..190. Walking players are pushed out of it with radius `T.radius*0.7` = 9.8 (L5782);
cans with radius 6 (L5789). `pushOutOfBox(o,r,b)` (L5642-L5654): clamp point to box, if distance < r push the
circle centre out to distance r along the normal; if the centre is inside, leave through the nearest side.

---------------------------------------------------------------------------------------------------
## 2. State variables

### 2.1 On each player (`newPlayer`, L726)
```js
dive: 0, dz: 0, vz: 0, dvt: 0,  // the dive tower: which stage, height off the floor
```
| var | meaning |
|---|---|
| `p.dive` | 0 or a DIVE value |
| `p.dz` | height above the floor (climb height, deck/board height, falling height; 0 while swimming) |
| `p.vz` | vertical speed during FALL |
| `p.dvt` | seconds spent in the current dive state (reset to 0 on each state entry except CLIMB←BOARD) |
| reused: `p.x, p.y, p.vx, p.vy, p.fx, p.fy, p.ix, p.iy, p.moving, p.odo, p.firing` | normal player fields; `odo` drives animation frames |

Networking (host → guest snapshot): `p.dive` (index 45) and `Math.round(p.dz)` (index 46) are sent, L8357;
unpacked L8461-L8462 (`dive: a[45] || 0`, `dz: a[46]` when not on the trampoline). Everything else (ripples,
ducks, splashes, drips) is local decoration on each screen.

### 2.2 World / globals
| name | line | contents |
|---|---|---|
| `w.floaters` | L6034 | `{x,y,text,t,col}` rising text ("SPLASH!"), stepped L8199-L8203 (rise 34 px/s, removed at t>0.9), drawn L12626-L12636 (bold 13px monospace, black shadow +1,+1, alpha 1 until t 0.6 then fades to 0 at 0.9). Sent to guest (L8318/L8426). |
| `w.shake` | L5678 | screen shake amplitude; decays `-90/s` (L8038); random offset `±shake/2` (cap 40) per frame (L11529-L11533) |
| `w.bits` | L6246 | spark particles from `fx()`/`burst()` |
| `w.events` | L6243 | `[kind,x,y]` FX events to replay on the guest |
| `RIPPLES` | L5796 | `{x,y,t,life,grow,w}` water rings |
| `SPLASHES` | L6080 | white-water splash objects |
| `DUCKS`, `DUCK_CLOCK`, `DUCK_IMG` | L5823, L5830 | the ducks |
| `POOL_FX = { last, dive:{}, emit:{} }` | L5896 | water-draw clock; last dive state per player id; ripple-trail timer per id |
| `DRIP = { was:{}, wet:{}, drops:[], runs:[], bits:[], spots:[], last }`, `DRIP_TIME = 3` | L6142-L6143 | dripping after climbing out |
| `NPC_GOTH.thrown` / `.dive` / `.wait` / `.rip` | L10326-L10368 | Gothica in the pool |
| `SHROOM.dive`, `.lastDive`, `.lastEye`, `.camX`, `.boardU`, `.springY/V`, `.bob`, `.walkPh`, `.moveK`, `.stepD`, `.look` | L3547, L4343-L4403 | first-person-only dive presentation |

---------------------------------------------------------------------------------------------------
## 3. Getting on the ladder (player step, L7289-L7299)

Runs every sim tick for every live player, after sitting/gym/bed handling and the slot machine, before
normal movement:
```js
const lounge = !w.started && T.loungeFloor && !secretActive(w);
if (p.dive && (!lounge || p.launch > 0)) { p.dive = 0; p.dz = 0; p.vz = 0; }      // thrown/launched: off the tower
if (!p.dive && lounge && p.roll <= 0 && p.launch <= 0 && inp.my < -0.5 && Math.abs(inp.mx) < 0.7) {
  const tg = towerGeo();
  if (Math.abs(p.x - tg.ladderX) < 14 && p.y > T.towerY && p.y < T.towerY + 30) {
    p.dive = DIVE.CLIMB; p.dz = 0; p.dvt = 0; p.vx = 0; p.vy = 0;
    p.x = tg.ladderX; p.y = tg.climbY;
  }
}
if (p.dive) { stepDive(w, p, inp, dt); continue; }    // dive owns the player this tick (no shooting, no normal move)
```
So: **no E/use press** – you stand at the ladder foot (|x−602.1| < 14, 190 < y < 220) and push **up**
(W / Up arrow / stick up / touch stick up, `my < -0.5`, not too diagonal `|mx| < 0.7`), not mid-roll or launched.
You snap to x = ladderX, y = climbY (188) — y is NOT changed while up the tower; height is `dz`.
`secretActive(w)` (L13797) = slot-machine secret sequence running blocks it.

You **cannot walk into the pool**: non-diving players are pushed out of the water box (L5781). The only way in is
off the board (or Gothica being thrown).

Things that disable themselves while `p.dive` is set: team ring and shadow (drawJared), gym (`gymNear` L935, plate is
racked if you climb carrying one L1007), rope (L9995), wardrobe (L1949), trampoline (L2077/L2106), mirror (L2172),
BBQ (L2049), mushroom (L3550), picking Gothica up (`canCarry` L9872), can kicking (L8172), lobby solid push-out
(L5780). Starting the run (L13579-L13583) resets: SWIM or FALL → `p.y = POOL.y1 + T.radius` (253); CLIMB/BOARD →
`p.y = baseY`; then `dive=dz=vz=vx=vy=0`.

---------------------------------------------------------------------------------------------------
## 4. `stepDive(w, p, inp, dt)` – the state machine (L5683-L5771)

Common prologue: `p.firing = 0; p.dvt += dt;`. Input: `inp.mx`, `inp.my` in −1..1 (up = negative my), `inp.roll` bool.

### 4.1 CLIMB (L5690-L5702)
```js
const climb = -inp.my * T.climbSpeed * dt;   // up the screen is up the ladder
p.dz = Math.max(0, p.dz + climb);
p.odo += Math.abs(climb);
p.vx = 0; p.vy = 0;
p.fx = 0; p.fy = -1; p.ix = 0; p.iy = -1; p.moving = climb ? 1 : 0;   // facing away from camera (back sprite)
if (p.dz <= 0 && inp.my > 0.3) {             // back off the bottom rung
  p.dive = 0; p.y = tg.baseY; p.fy = 1;
} else if (p.dz >= tg.deckH) {
  p.dz = tg.deckH; p.dive = DIVE.BOARD; p.dvt = 0;
}
```
- Up/W climbs, Down/S descends, proportional to stick. Horizontal ignored. Full climb = 93.1/120 ≈ 0.78 s.
- At the bottom (dz 0) holding down (> 0.3) steps off: y = baseY (200.8), facing down; x stays ladderX.
- Reaching deckH → BOARD.

### 4.2 BOARD (L5704-L5726)
```js
const dir = Math.abs(inp.mx) > 0.05 ? Math.sign(inp.mx) : 0, pace = Math.min(1, Math.abs(inp.mx) * 2);
p.x = Math.max(tg.ladderX, Math.min(tg.tipX, p.x + dir * pace * T.boardWalk * dt));
p.odo += Math.abs(dir) * pace * T.boardWalk * dt;
p.vx = 0; p.vy = 0;
p.moving = dir ? 1 : 0; p.ix = dir; p.iy = 0;
if (dir) { p.fx = dir; p.fy = 0; }
const along = Math.max(0, Math.min(1, (p.x - tg.ladderX) / Math.max(1, tg.boardX0 - tg.ladderX)));
p.dz = tg.deckH + (tg.boardH - tg.deckH) * along;           // deck 93.1 → board 100.6 over x 602.1..622.75
if (p.x <= tg.ladderX + 2 && inp.my > 0.5 && !dir) {        // back down
  p.dive = DIVE.CLIMB; p.fx = 0; p.fy = -1;  return;         // (dvt not reset; dz stays at deckH)
}
// roll button from anywhere up here, or just walk off the end
if (p.dvt > 0.15 && (inp.roll || (p.x >= tg.tipX && dir > 0))) {
  p.dive = DIVE.FALL; p.dvt = 0;
  p.vx = T.diveFwd; p.vy = 40; p.vz = T.diveHop;             // always out to the RIGHT, +40 px/s down-screen
  p.fx = 1; p.fy = 0;
  if (SND.ctx) sTone(0.14, 260, 720, 0.16, 'triangle');      // boing
}
```
- Left/right (A/D, stick x) walk along x between ladderX (602.125) and tipX (682.75). |mx| ≥ 0.5 = full 120 px/s,
  smaller pushes walk proportionally slower (dead zone 0.05). Up/down ignored except "down at the ladder end".
- Exits: (a) at the ladder end (x ≤ 604.125) holding down (> 0.5) with no horizontal → CLIMB (then down the ladder);
  (b) after 0.15 s on the board, **roll button** (Shift / P2 Ctrl / pad B, RB, LT / second-finger tap) anywhere on
  the board/deck, or pushing right while at the tip → FALL. Note roll is forced false while carrying Gothica
  (L7172), so with her you must walk off the end (or press E to throw her, §8).
- The deck part (x < boardX0) is also "the board" logically.

### 4.3 FALL (L5728-L5744)
```js
p.vz -= 1200 * dt;
p.dz += p.vz * dt;
p.x += p.vx * dt; p.y += p.vy * dt;
p.odo += 240 * dt;                           // drives the tumble animation
if (p.dz <= 0) {
  p.dz = 0; p.vz = 0;
  if (inWater(p.x, p.y)) {
    p.dive = DIVE.SWIM; p.dvt = 0; p.vx *= 0.2; p.vy = 0;
    splash(w, p.x, p.y);
  } else {                                   // missed the pool entirely
    p.dive = 0; p.vx = 0; p.vy = 0;
    fx(w, FX.WALL, p.x, p.y);
  }
}
```
Gravity 1200 px/s² (hard-coded). No input. With defaults: off the tip (dz 100.6) airtime ≈ 0.656 s, lands at
(≈768, ≈214); rolling off at the ladder end (dz 93.1) ≈ 0.642 s → (≈686, ≈214). Both in water with default tuning.
Collision with walls/solids is not applied during the dive.

### 4.4 SWIM (L5746-L5771)
```js
const ease = Math.min(1, 4 * dt);
p.vx += (inp.mx * T.swimSpeed - p.vx) * ease;
p.vy += (inp.my * T.swimSpeed - p.vy) * ease;
p.x += p.vx * dt; p.y += p.vy * dt;
p.odo += Math.hypot(p.vx, p.vy) * dt;
const ml = Math.hypot(inp.mx, inp.my);
p.moving = ml > 0.1 ? 1 : 0;
if (p.moving) { p.ix = inp.mx; p.iy = inp.my; p.fx = inp.mx / ml; p.fy = inp.my / ml; }
const b = { x0: POOL.x0 + 14, x1: POOL.x1 - 14, y0: POOL.y0 + 10, y1: POOL.y1 - 8 };
let ox = 0, oy = 0;
if (p.x < b.x0) { p.x = b.x0; p.vx = 0; if (inp.mx < -0.5) ox = -1; }
if (p.x > b.x1) { p.x = b.x1; p.vx = 0; if (inp.mx > 0.5) ox = 1; }
if (p.y < b.y0) { p.y = b.y0; p.vy = 0; if (inp.my < -0.5) oy = -1; }
if (p.y > b.y1) { p.y = b.y1; p.vy = 0; if (inp.my > 0.5) oy = 1; }
if ((ox || oy) && p.dvt > 0.5) {             // haul yourself out onto the tiles
  const out = T.radius * 0.7;                // 9.8
  if (ox < 0) p.x = POOL.x0 + 6 - out;       // 620.2
  if (ox > 0) p.x = POOL.x1 - 6 + out;       // 818.8
  if (oy < 0) p.y = POOL.y0 + 6 - out;       // 86.2
  if (oy > 0) p.y = POOL.y1 - 6 + out;       // 242.8
  p.dive = 0; p.vx = 0; p.vy = 0;
  fx(w, FX.WALL, p.x, p.y);
}
```
- 8-way swim with exponential velocity smoothing (rate 4/s) toward `input * 120`.
- **Getting out**: swim into any edge of the clamp box while pushing outward (> 0.5) after 0.5 s in the water →
  teleported just outside the water on that side, normal walking resumes, small grey spark burst. No E needed.
- Shooting is impossible in every dive state (stepDive `continue`s past the shooting code). Weapon switching
  still happens (it is before L7289).

### 4.5 Transition summary
| from | to | condition |
|---|---|---|
| 0 | CLIMB | lobby, not rolling/launched, `my < -0.5`, `|mx| < 0.7`, `|x-ladderX|<14`, `towerY<y<towerY+30` |
| CLIMB | 0 | `dz<=0 && my>0.3` → y = baseY |
| CLIMB | BOARD | `dz >= deckH` |
| BOARD | CLIMB | `x<=ladderX+2 && my>0.5 && !dir` |
| BOARD | FALL | `dvt>0.15 && (roll || (x>=tipX && dir>0))` |
| FALL | SWIM | `dz<=0 && inWater` → splash |
| FALL | 0 | `dz<=0 && !inWater` → FX.WALL |
| SWIM | 0 | pushing out of an edge, `dvt>0.5` |
| any | 0 | `!lounge` (run starts / secret) or `p.launch>0` → `dive=dz=vz=0` (no position fix; run start has its own fix L13579) |

---------------------------------------------------------------------------------------------------
## 5. Controls per state

Input sources (built every frame): P1 `localInput0` L8985: W/A/S/D, touch move stick (`moveStick`, dead zone 0.12),
pad 0 left stick (dead zone 0.2); roll = Shift, or a second-finger tap on the move side (`consumeRollTap` L8610), or
pad buttons 1 (B, unless sitting/holding B), 5 (RB), 6 (LT) (L9020-L9022). P2 local `localInput1` L9039: arrows,
roll = Control, pad 1 buttons 1/5/6. Guest player: same as P1 on their machine, sent over the net.
"E" (use) = key `e` (L8655) / pad A (button 0 → padTap('e'), L8976) / touch carry button. `actKey()` (L8882) prints
'A' if the pad was used last, else 'E'.

| state | move | roll | E |
|---|---|---|---|
| walking near ladder | up climbs on | normal roll (blocks climbing that tick) | whatever else is near |
| CLIMB | up/down = climb/descend; x ignored | ignored | nothing (`lobbyLabel` returns null) – if carrying Gothica E does nothing (she "stays put") |
| BOARD | left/right walk; down at ladder end = back to ladder | dive (after 0.15 s) | only if carrying Gothica: throw her in |
| FALL | ignored | ignored | nothing |
| SWIM | 8-way swim; push into an edge to climb out | ignored | nothing |

### 5.1 Prompts / labels (exact strings)
- Top-down, over the local player's head (L12268-L12286), only when `towerOn` (`!w.started && T.loungeFloor && !cal.on`):
  ```js
  const atLadder = !p.dive && Math.abs(p.x - tg.ladderX) < 14 && p.y > T.towerY && p.y < T.towerY + 30;
  const tip = atLadder ? '↑ climb' : (p.dive === DIVE.BOARD ? (NPC_GOTH.carrier === p.id ? actKey() + ': throw her in!' : 'walk off or roll to dive!') : '');
  ```
  i.e. `'↑ climb'`, `'walk off or roll to dive!'`, `'E: throw her in!'` / `'A: throw her in!'`. Nothing while
  climbing, falling, swimming. Drawn for **every** player (not only the local one), inside a `translate(0, p.dive===SWIM ? 36 : -dz)`;
  `ty = max(12 + dz, round(p.y - r*spriteScale*1.25) - 4)` (spriteScale 4.6 → 80.5 px above feet), font
  `bold 11px ui-sans-serif, system-ui, sans-serif`, centred, shadow `rgba(0,0,0,0.6)` at +1,+1, text `#8fd3ff`.
- Use-button label (`lobbyLabel` L10088-L10091): carrying Gothica on BOARD → `'THROW!'`; carrying on any other dive
  state → none; any dive state otherwise → none (`if (p.dive) return null;`). Touch button (`carryButton` L10109-L10115):
  circle at (ARENA.w−62, ARENA.h−18−118) = (798, 384), r 34, fill `rgba(20,12,28,0.72)`, stroke `#f7a8ff` 2px,
  label `bold 12px` `#f7a8ff`.
- First-person (sober or tripping) HUD tips (L4892-L4899), white bold 14px, centred, y = 40 on the board else ARENA.h−97:
  `'face the ladder and hold W to climb'` (at the ladder foot), `'W: up   S: down'` (CLIMB — three spaces),
  `'walk off the end, or Shift to dive'` (BOARD). Hidden while the FP drop/splash plays.

### 5.2 First-person differences (`shroomInput`, L3705-L3717)
When the first-person view (mushroom trip `SHROOM.on`, or its "sober" plain FP mode) is on and the player is on the tower,
input is rewritten (`up = -inp.my` from W/S, `SHROOM_CLIMB = 0.16`, `SHROOM_BOARD_PACE = 0.085`, L3544-L3545):
```js
if (SHROOM.dive || (me && me.dive === DIVE.FALL)) return done({ mx: 0, my: 0, roll: false });   // mid-dive: along for the ride
if (me && me.dive === DIVE.CLIMB)                                 // W up the ladder, S down, and slowly
  return done({ mx: 0, my: (me.dz || 0) <= 0 && up < 0 ? 1 : -up * SHROOM_CLIMB, ay: -100 });
if (me && me.dive === DIVE.BOARD) {                               // W out along the board, S back to the ladder
  const back = up < 0 && me.x <= towerGeo().ladderX + 2;
  return done({ mx: back ? 0 : up * SHROOM_BOARD_PACE, my: back ? 1 : 0 });
}
```
(`done` sets ax=100, ay=0, shoot=false, keeps `roll`). So in FP: climb ≈ 19.2 px/s (≈4.85 s), board W = forward
at pace 0.17 (≈20.4 px/s, ≈4 s to the tip), S walks back and at the ladder end goes down; Shift still dives from the
board. Getting on the ladder in FP: the normal WASD is rotated by view angle, so you must *face* the ladder (≈ north)
and press W so that the resulting world `my < -0.5`. While swimming in FP, movement is the normal view-relative WASD.
View angle is locked while on the tower (L4287): CLIMB → −π/2 (facing up the screen = the ladder), BOARD → 0 (facing
+x, out over the pool), during the FP drop → 0; it eases toward the lock at rate 6/s.

---------------------------------------------------------------------------------------------------
## 6. Drawing (top-down)

### 6.1 Layer order in the lobby frame (`render`, L11536-L12401)
1. Background, yard. 2. **Lounge floor art** `LOUNGE_IMG` drawn at (18,18) size 824×484 (L11544) – the pool basin
   and tiles are *in this floor art*. 3. `drawPoolWater(w)` (L11546). 4. `drawDucks(w)` (L11547).
5. … grid lines (transparent in lobby), other floor things … 6. particles `w.bits` (3×3 squares, L11803-L11807), then
   `drawSplashes()` and `drawDrips(w)` (wet spots) (L11809). 7. Players + props sorted by y (L12218-L12399):
   the tower is a depth prop at `y = T.towerY - 4` (186): it is drawn just before the first character with
   `p.y >= 186`. A climbing/board player has y = climbY = 188, so he is drawn **in front of** the tower. A player standing
   behind (y < 186) is drawn under it. If nobody is in front it's drawn after everyone (L12399-L12400).
8. `drawDripDrops()` (after characters, L12401). 9. Floaters (L12626).

### 6.2 Tower art — `drawTower()` (L5968-L5977)
Art: `TOWER_IMG` (base64 PNG at L766) = **`godot/assets/TOWER_IMG_src.png`** (manifest key `TOWER_IMG.src`),
172×194 px; also extracted as `godot/scripts/lobby_life/art/pool/dive_tower.png` (byte-identical). The image is the
whole tower: a grey steel frame on four legs, a ladder up the front-left, a tiled deck with handrails on top and the
blue springboard sticking out to the right (board top-right).
```js
const k = T.towerScale;
const dw = TOWER_IMG.naturalWidth / 2 * k, dh = TOWER_IMG.naturalHeight / 2 * k;   // 107.5 × 121.25
// legs centre sits 19px in from the left edge at this size
ctx.imageSmoothingEnabled = false;
ctx.drawImage(TOWER_IMG, Math.round(T.towerX - 19 * k), Math.round(T.towerY - dh), Math.round(dw), Math.round(dh));
```
→ drawn at (580, 69), size 108×121 (nearest-neighbour). Bottom edge = towerY (190).

### 6.3 The water — `drawPoolWater(w)` (L5897-L5966)
Own clock `POOL_FX.last` (real time, dt capped 0.1). Floor-art scale `sx = LOUNGE_IMG.naturalWidth/(860-36)`,
`sy = naturalHeight/(520-36)` – the webp is 824×484 so both are 1.
- Clip to `rect(633, 99, 173, 131)`. Redraw the floor art in horizontal **2 px bands**, each band shifted sideways:
  ```js
  const band = 2, pad = 4;
  for (let y = wy0; y < wy1; y += band) {
    const off = Math.sin(y * 0.16 + now * 2.1) * 1.4 + Math.sin(y * 0.05 - now * 1.3) * 0.8;
    ctx.drawImage(LOUNGE_IMG, (wx0 - pad - 18) * sx, (y - 18) * sy, (wx1 - wx0 + pad * 2) * sx, band * sy,
                  wx0 - pad + off, y, wx1 - wx0 + pad * 2, band);
  }
  ```
  (smoothing off; `now` = seconds). In Godot this is a horizontal-wobble shader on the pool region of the floor texture:
  `uv.x -= (sin(y*0.16 + t*2.1)*1.4 + sin(y*0.05 - t*1.3)*0.8)` with y quantised to 2 px rows.
- Sheen: linear gradient from (633,99) to (806,230), `s = (now*0.08) % 1`; stops: 0→transparent, s−0.12→transparent,
  s→`rgba(255,255,255,0.07)`, s+0.12→transparent, 1→transparent (clamped to 0..1). Filled over the rect.
- Ring emitters (per player in `w.players`; NOT Gothica here – her rings are pushed by her own code):
  - entering SWIM (state changed since last frame): 3 rings `{t: -i*0.18, life 1.3, grow 70, w 2.5}`, emit timer 0.4.
  - while swimming: timer −= dt; at ≤0 push `{life: moving?0.9:1.6, grow: moving?34:26, w 1.5}` and reset timer to
    `moving ? 0.22 : 0.9` (moving = speed > 20).
  - ambient: with probability `dt*0.9` per frame, if < 40 rings, a ring at a random point inset 10 px:
    `{life 1.8, grow 18, w 1}`.
- Ring draw (still clipped): age k = t/life; skip t<0 (delayed); `rx = 5 + grow*k`, ellipse radii (rx, rx*0.45),
  stroke `#e6f7ff`, alpha `0.55*(1-k)`, lineWidth `w`. Removed at t ≥ life.
  Rings are pushed from many places (ducks, splashes, drops, Gothica) into the same `RIPPLES` list.

### 6.4 The player while diving — `drawJared` (L10475-L10725)
- `swim = p.dive === SWIM`; `elev = swim ? 0 : p.dz` (sprite raised by dz; L10479, L10693 `dy -= elev`).
- No team ring when `p.dive` (L10482). Shadow: drawn on the floor at p.y unless swimming, scaled `sf = 1 - min(0.45, lift/22)`
  (lift = dz), so on the tower it's a small shadow at the tower foot (y 188+11.9).
- CLIMB / BOARD: ordinary run/idle pose from `poseFor` using facing (CLIMB: fx 0, fy −1 → `back` sprite, animated by odo;
  BOARD: side sprites, flipped when facing left). Frames advance with `odo` (`floor(odo/26)%2` for a/b, run cycles by runStride 13).
- FALL: tumble (L10523-L10527): `pose = { img: 'roll' + (floor(odo/26)%4 + 1), flip: false }` → roll1..roll4 frames of the
  character sheet (odo += 240/s → frame change every 0.108 s), with roll scale/anchoring rules (`rolling` branch L10684-L10687).
- SWIM (L10695-L10704, L10713-L10724):
  ```js
  wob = Math.sin(performance.now() / 260 + (typeof p.id === 'number' ? p.id : 3) * 2);
  dy += h * 0.48 + wob * 1.5;                       // sunk to the shoulders, bobbing
  ctx.save(); ctx.beginPath(); ctx.rect(p.x - dw * 1.5, dy - 20, dw * 3, p.y - (dy - 20)); ctx.clip();   // cut at the waterline y = p.y
  ... draw sprite ...
  ctx.restore();
  const rw = dw * 0.42 + (p.moving ? 3 : 0);
  ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(225,246,255,0.8)';
  ctx.beginPath(); ctx.ellipse(p.x, p.y, rw + wob, 5, 0, 0, Math.PI * 2); ctx.stroke();
  ctx.strokeStyle = P_COLOURS[p.id]; ctx.globalAlpha = 0.6;          // team colour ring ('#e0473f' P1, '#4f9fe8' P2)
  ctx.beginPath(); ctx.ellipse(p.x, p.y + 1, rw + 6 - wob, 8, 0, 0, Math.PI * 2); ctx.stroke();
  ```
  (h = sprite height ≈ T.radius*spriteScale*charScale*…; the sprite's feet would be at p.y+0.9r, it is pushed down by
  0.48h so only head and shoulders show above the clip line p.y.) Pose while swimming = normal run/idle pose from facing.
- Things over his head (tips, HP pips, etc.) are translated by `-dz`, or **+36** when swimming (L12270).

### 6.5 Rubber ducks (L5797-L5895)
**Art is not an image file**: 18×15 pixel-art strings in the code (`DUCK_ROWS` L5802-L5818) coloured by palette
(`DUCK_LOOKS` L5819-L5822), rendered once per look into a canvas (`duckImg`, L5824-L5829). Side view facing right; the
bottom 4 rows sit under the water. Pre-rendered PNGs: `godot/scripts/lobby_life/art/pool/duck_yellow.png`,
`duck_black.png` (18×15 each). Pattern + palettes (for regeneration):
```
.......KKKK.......      yellow: K #3a2408  Y #ffd21f  y #e8a400  W #fff7b0  O #ff8a1e  o #d8621a  E #1c1410
......KYYYYK......      black : K #0e0a14  Y #2c2438  y #1a1422  W #6b5a86  O #8a2a52  o #5e1a38  E #e8e0f0
.....KYWWYYYK.....      ('.' transparent; K outline, Y body, y body shade, W highlight, O beak, o beak shade, E eye)
.....KYWYYEYYKKK..
.....KYYYYEYKOOOK.
.....KYYYYYYKoooK.
..KK..KYYYYYKKKK..
.KYYK.KYYYYYYK....
.KYYYKKYYYYYYYKK..
KYYYYYYYYYYYYYYYK.
KYWWYYYYYYYYYYYyK.
KYYWYYYYYYYYYYyyK.
.KyYYYYYYYYYYyyK..
..KKyyyyyyyyyKK...
....KKKKKKKKKK....
```
**Count & start positions** (`initDucks`, L5832-L5838; done lazily on first draw, never reset):
```js
[['yellow', 0.25, 0.3], ['yellow', 0.72, 0.62], ['black', 0.45, 0.78]].forEach(([look, fx, fy], i) =>
  DUCKS.push({ look, x: b.x0 + (b.x1 - b.x0) * fx, y: b.y0 + (b.y1 - b.y0) * fy, vx: 0, vy: 0,
               head: Math.random() * Math.PI * 2, flip: i === 1, ph: Math.random() * 6.28, wob: 0 }));
```
with b = duckBounds (640..799, 108..229) → yellow (679.75, 144.3), yellow (754.48, 183.02) facing left, black (711.55, 202.38).

**Behaviour** (`stepDucks(w, dt)` L5847-L5878, called from `drawDucks` with its own real-time clock, dt ≤ 0.1; purely
local decoration on each machine, not networked):
```js
for each duck d:
  d.head += (Math.random() - 0.5) * dt * 1.6;                 // slow wandering heading
  d.vx += Math.cos(d.head) * 4 * dt; d.vy += Math.sin(d.head) * 4 * dt;
  const damp = Math.max(0, 1 - dt * 0.9); d.vx *= damp; d.vy *= damp;
  for each swimmer s (players with dive===SWIM, plus NPC_GOTH if thrown==='swim'):
    dx = d.x - s.x, dy = d.y - s.y, r = hypot || 0.01
    if (r < 20) { d.vx += dx/r*90*dt + s.vx*0.8*dt; d.vy += dy/r*90*dt + s.vy*0.8*dt; d.wob = max(d.wob, 0.6); }
pairwise (i<j): if r < 17: push each apart by (17-r)/2 along the normal; rel = (vc - va)·n;
   if rel < 0: va += n*rel; vc -= n*rel (velocities exchanged along normal); wob = max(wob, 0.4) on both
for each duck:
  d.x += d.vx*dt; d.y += d.vy*dt;
  bounce off duckBounds: clamp; reflect that velocity component ×0.6; head = PI - head (x walls) or -head (y walls)
  if (d.vx > 1.5) d.flip = false; else if (d.vx < -1.5) d.flip = true;     // face travel direction
  d.ph += dt * 2.2; d.wob = max(0, d.wob - dt * 1.2);
  if (hypot(vx,vy) > 18 && Math.random() < dt * 6) RIPPLES.push({ x: d.x, y: d.y + 1, t: 0, life: 0.9, grow: 22, w: 1.2 });
```
**Knocked by splashes** (`duckSplash(x,y,power)` L5840-L5846), called from `fx()` for FX.SPLASH (power 0.6) and FX.DIVE
(power 1.6) — host only (the guest's `playEvents` L11125 does not call it):
```js
r = dist; if (r > 70) skip;  m = 60 * (1 - r/70) * power;  a = r > 1 ? atan2(dy,dx) : random angle;
d.vx += cos(a)*m; d.vy += sin(a)*m; d.wob = 1;
```
**No quacking / no sound** (no "quack" anywhere). Ducks are not hittable and not solid to players.

**Drawing** (`drawDucks` L5879-L5895), sorted by y, in the floor layer (under every character):
```js
const im = duckImg(d.look), wl = im.height - 4 /* 11 */, bob = Math.sin(d.ph) * 0.7, tilt = Math.sin(d.ph * 3) * 0.3 * d.wob;
ctx.fillStyle = 'rgba(10,40,70,0.28)'; ellipse(d.x, d.y + 1, 10, 3) fill;                 // shadow in the water
ctx.translate(round(d.x), round(d.y + bob)); ctx.rotate(tilt); if (d.flip) ctx.scale(-1, 1);
ctx.drawImage(im, -im.width / 2, -wl, im.width, im.height);                                 // 1 art px = 1 arena px
ctx.fillStyle = 'rgba(40,140,210,0.55)'; ctx.fillRect(-im.width / 2, 0, im.width, im.height - wl);   // water over bottom 4 rows
// (restore) then a waterline ring:
ctx.strokeStyle = 'rgba(225,246,255,0.75)'; ctx.lineWidth = 1; ellipse(d.x, d.y + bob + 0.5, 11, 2.6) stroke;
```
So the duck's origin (d.x, d.y) is its waterline; it bobs ±0.7 px at 2.2 rad/s, and rocks up to ±0.3 rad (×wob, at
6.6 rad/s) after being bumped. In first-person view the ducks are billboard sprites (L4126, foot = height−4).

### 6.6 Splash visuals
`splash(w, x, y)` (L5676-L5681) – a player (or Gothica) landing in water:
```js
fx(w, FX.DIVE, x, y);
w.shake = Math.max(w.shake || 0, 8);
w.floaters.push({ x, y: y - 50, text: 'SPLASH!', t: 0, col: '#8fd3ff' });
if (SND.ctx) { sNoise(0.55, 1500, 0.7, 0.45, 'lowpass', 250); sTone(0.2, 170, 60, 0.2, 'sine'); }
```
`fx(w, kind, x, y)` (L6238-L6244): sparks `burst(w,x,y,n,colour,speed)` from `FX_LOOK[kind]` (L6073-L6075):
FX.SPLASH (8) = `[10, '#e6f7ff', 200]`, FX.DIVE (9) = `[16, '#ffffff', 260]`, FX.WALL (2) = `[3, '#5a6274', 120]`.
Each spark: random angle, speed `speed*(0.3+rnd*0.7)`, life `0.25+rnd*0.35`, max 0.6; moved with drag `0.9^(dt*60)`
(L8288-L8295); drawn as 3×3 squares, alpha life/max. Then `SPLASH → duckSplash(.,.,0.6); waterSplash(x,y,0.45)`,
`DIVE → duckSplash(.,.,1.6); waterSplash(x,y,1)`. Event also queued for the guest (who runs waterSplash + sparks).

`waterSplash(x, y, size)` (L6081-L6096) – a white-water splash object:
```js
ring = round(38*size + 8) crown drops: a = i/ring*2π + rnd*0.2, out = (40 + rnd*60)*size;
   {x: cos a*8*size, y: sin a*4*size, z: 2, vx: cos a*out, vy: sin a*out*0.5, vz: (120 + rnd*120)*sqrt(size), r: 1.5 + rnd*2.5*size}
plume = round(28*size) drops: a random, out = rnd*20*size;
   {x:0, y:0, z:4, vx: cos a*out, vy: sin a*out*0.5, vz: (150 + rnd*180)*size, r: 2 + rnd*3*size}
SPLASHES.push({x, y, size, t: 0, drops});
3 rings: RIPPLES.push({x, y, t: -i*0.15, life 1.4, grow 40 + 45*size, w 1.2 + 1.5*size})
```
`drawSplashes()` (L6097-L6137), own real-time clock, gravity G = 700:
- Foam while `fk = min(1, t/1.4) < 1`: `fr = (16 + 36*sqrt(fk))*size + 6`; white ellipse (fr, fr*0.45) alpha `0.85*(1-fk)`;
  7 lumps `#bfe9ff` at angle `k*0.9 + t*0.7`, offset (cos*0.8fr, sin*0.8fr*0.45), radii (0.28fr, 0.13fr).
- Drops with z>0: `x+=vx dt; y+=vy dt; vz-=700dt; z+=vz dt; vx*=0.99`; on landing (z≤0) 30% chance of a ring
  `{life 0.6, grow 10, w 1}`. Shadow: 1 px tall rect `#0a3a60` alpha 0.18 at (x+d.x−r/2, y+d.y), width ceil(r).
  Then two passes at alpha 0.95: pass 0 rim `#7cc8f0` size ceil(r)+2, pass 1 `#ffffff` (r>3) or `#eefaff`, size ceil(r);
  at (x+d.x−s/2, y+d.y−z−s/2), height +2 when falling (vz<0).
- Removed when no drops alive and foam done.

Other splash sources: a lobbed potato landing in water (L8056) and a potato from the rope "potato rain" settling in water
(L10039) → `fx(w, FX.SPLASH, …)` (small splash, no sound from fx itself).

### 6.7 Dripping after getting out (L6139-L6235)
Per player (and Gothica in the lobby): when `DRIP.was[k]` (was SWIM last frame) and now `!swim && !e.dive` → wet for
`DRIP_TIME = 3` s and 5 wet spots on the tiles (`r 3..6`, life 4). While wet (f = wet/3): drops spawn with prob
`dt*22*f + dt*2` at one of `DRIP_POINTS` (fractions of sprite height h = radius*spriteScale ≈ 64.4) and hang 0.25-0.6 s
then fall at 420 px/s² to `e.y + 1..4`, leaving a spot (life 1.8, max 70 spots) and 2 tiny bits; trickles spawn with
prob `dt*9*f`. Colours: drop `#2f79ad` with `#bfe9ff`/`#e8f8ff` glint, trickle `#cfefff`/`#ffffff`, spots `#3a78a8`
alpha 0.35 fading. Spots drawn with the floor effects (L11809), drops/trickles over characters (L12401).
(Full code L6142-L6235 – short and self-contained; port verbatim.)

---------------------------------------------------------------------------------------------------
## 7. Sounds (all synthesised with WebAudio; `sTone(dur, f0, f1, gain, wave)` = oscillator with exponential pitch
glide f0→f1 and exponential gain decay to ~0 over dur (L11228); `sNoise(dur, freq, q, gain, type, sweepTo)` = looped
white noise through a biquad filter (type, freq, Q) with optional exponential cutoff sweep to `sweepTo`, gain decaying
over dur (L11213))

| event | code | line |
|---|---|---|
| leaving the board (boing) | `sTone(0.14, 260, 720, 0.16, 'triangle')` | L5723 |
| splash into pool | `sNoise(0.55, 1500, 0.7, 0.45, 'lowpass', 250)` + `sTone(0.2, 170, 60, 0.2, 'sine')` | L5680 |
| missed the pool / climbing out | none (only FX.WALL sparks) | L5740, L5769 |
| Gothica thrown (boing) | `sTone(0.14, 260, 720, 0.16, 'triangle')` | L10331 |
| FP board footstep creak (every 30 FP units) | `sNoise(0.06, 350, 1.2, 0.18, 'lowpass', 120)` + `sTone(0.16, 190-bu*50, 140-bu*40, 0.045, 'sawtooth')` | L4363 |
| FP drop whoosh | `sNoise(2.6, 250, 2, 0.35, 'bandpass', 2600)` + `sTone(0.2, 300, 700, 0.1, 'triangle')` | L4385 |
| FP splash | `sNoise(1.3,1600,0.7,0.65,'lowpass',160)`, `sNoise(0.5,4000,1,0.3,'highpass',1500)`, `sTone(0.35,150,45,0.35,'sine')`, then arpeggio semitones [0,4,7,11,14,19] over 392 Hz, each `sTone(1.1, f, f*1.01, 0.07, 'triangle')` at 120+80·i ms | L4943-L4946 |
| FP miss (thump) | `sNoise(0.3, 300, 1, 0.5, 'lowpass', 60)` + `sTone(0.25, 120, 40, 0.3, 'square')` | L4934 |

Note the boing/splash sounds live in host-side sim code, so in the HTML a network guest hears none of them (only sees
the splash via the FX event). Ducks make no sound.

---------------------------------------------------------------------------------------------------
## 8. Gothica and the pool (details belong to the Gothica spec; references here)
- Carrying her: she follows the carrier including `dz` ("up the ladder with him", L10256). E on the ladder does nothing.
- On the BOARD, E throws her: `throwGoth(w, (p.fx < 0 ? -1 : 1) * T.diveFwd * 1.25, 40, T.diveHop * 0.9)` (L10156-L10160)
  i.e. vx ±162.5, vy 40, vz 216. Label 'THROW!' / tip 'E: throw her in!'.
- Walking off the end while carrying her (FALL): `throwGoth(w, p.vx * 1.15, p.vy, p.vz * 1.05)` (L10258).
- `throwGoth` (L10326-L10332): `thrown='air'`, floater `'WHEEE!'` `#f7a8ff` at y−dz−40, boing sound.
- `stepThrownGoth` (L10333-L10368): air: gravity 1200, `spin += 9*dt`; landing `inWater` → `thrown='swim'`, `dive=SWIM`,
  `wait=3.5`, `vx*=0.2`, `vy=0`, `rip=0.4`, `splash(w,…)` + 3 extra rings (life 1.3, grow 70, w 2.5); else
  `thrown='floor'`, wait 1.8, FX.WALL, floater `'OOF'` `#ffd0d0`. Swim: drifts on vx with damping `1-min(1,3dt)`, ring every
  0.9 s (life 1.6, grow 26, w 1.5), clamped to the swim box; after 3.5 s she climbs out at `y = POOL.y1 + 18` (257),
  `wait 1.2`, facing down (drip effect triggers).
- She counts as a swimmer for duck shoving (L5850), is drawn by `drawJared` with the swim clip while `thrown==='swim'`
  (L12240; her rings: `P_COLOURS['npc_goth']` is undefined so the second ring re-uses the previous stroke colour),
  and in first person as a head-and-shoulders cut-out (top 38% of her front_run frame, L4137-L4139).
- Gothica's NPC stroll area `NPC_AREA = {x0:70,x1:590,y0:250,y1:410}` (L9852) keeps her clear of pool and tower.
- Net snapshot of her state includes `thrown` ('swim' index 3) and `dive` (L10232-L10244).

---------------------------------------------------------------------------------------------------
## 9. First-person ("mushroom" / sober FP) dive presentation (your screen only; simulation is unchanged)
Only needed if the FP mode is ported. Constants L3539-L3546: `SHROOM_EYE 62`, `SHROOM_WALL 150`, `SHROOM_TOWER 710`
(eye height at the top), `SHROOM_BOARD 350` (FP board length), `SHROOM_FALL 2.6` s, `SHROOM_SPLASH 1.8` s,
`SHROOM_SWIM_EYE 18`.
- Eye height (L4344-L4346): CLIMB/BOARD `EYE + dz/deckH*(710-62)`; SWIM 18.
- Board (L4352-L4372): `bu = (x-ladderX)/(tipX-ladderX)`; camera x = `ladderX + bu*(POOL.x0+40-ladderX)`; springboard sag
  `12*ease((bu-0.7)/0.3)`, footstep every 30 units adds spring impulse `26*bu²`, spring `v += (-140y - 7v)dt`, y clamped
  −6..10; head bob `|sin(walkPh)|*3.2`. Pitch looks down more along the board (L4374).
- The drop (L4382-L4401): starts when last state was BOARD and now isn't BOARD/CLIMB; 2.6 s fall with eye
  `h0 + (18-h0)*f²`, two forward somersaults (pitch round 4π, screen rotated 180° in the "back" half), then
  `shroomSplash` (rainbow flash, 7 colour rings, 160 spray drops, 45 bubbles while "under", surface flash at 1.2-1.5 s),
  ends after a further 1.8 s. Input frozen throughout. Missing the pool → white flash thump.
- Ladder overlay: rainbow rungs every 0.2·VH sliding with eye height, rails at 24%/74% width (L4675-L4688). Board
  drawn as 3D planks (L4709-L4754). The tower cut-out prop is hidden while you're on it (L4327). Up high the floor is
  drawn ×(1..3) scaled around (POOL.x0+20, pool mid-y) (L4408), the pool glows with rainbow rings (L4454-L4461).
- FP trip clock pauses while on the tower (L4274-L4277).

---------------------------------------------------------------------------------------------------
## 10. Art files
| file | what | px size | source |
|---|---|---|---|
| `godot/assets/TOWER_IMG_src.png` | dive tower (frame, ladder, deck, blue springboard) | 172×194, drawn at ×0.625 (108×121) | base64 `TOWER_IMG` L766, in manifest |
| `godot/scripts/lobby_life/art/pool/dive_tower.png` | same bytes as above (extracted copy) | 172×194 | L766 |
| `godot/assets/LOUNGE_IMG_src.webp` | lobby floor art incl. pool basin & tiles; the water animation re-samples its pool region | 824×484 (1:1 with arena interior at (18,18)) | base64 `LOUNGE_IMG` L764, in manifest |
| `godot/scripts/lobby_life/art/pool/duck_yellow.png` | yellow rubber duck, faces right, 1 px = 1 arena px | 18×15 | rendered from `DUCK_ROWS`/`DUCK_LOOKS.yellow` L5802-L5822 (not base64) |
| `godot/scripts/lobby_life/art/pool/duck_black.png` | black (goth) rubber duck | 18×15 | `DUCK_LOOKS.black` |
| character `roll1..roll4`, run/back sprites | tumble and swim/climb poses | per character | character sheets (other spec) |

No other embedded images are used by the pool/tower/dive/duck features (water, ripples, splashes, drips, shadows are all
procedural). Extraction script: `<your scratchpad>/pool_art.py`.
