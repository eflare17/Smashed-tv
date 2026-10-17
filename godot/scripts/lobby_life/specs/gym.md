# Gym spec: bench press, plate tree, leg press, bell rope

Source: `/home/user/Smashed-tv/Smashed.html` (line numbers = HTML lines). Coordinates are arena pixels:
x across, y down the floor, z/dz = height. ARENA = { w: 860, h: 520, wall: 18 }.
All gym things work **only in the lobby** (`!w.started`) and with `T.loungeFloor` set (it is 1).

**Holding a plate is `p.plate` in the code. There is no `p.hold`.** It is one of `'S' | 'M' | 'L' | null`.

---------------------------------------------------------------------------------------------------
## 0. Tuning and constants

`T` (lines 357-367, slider ranges 536-541; also in `godot/data/game_data.json` → `T`):

| key | value | meaning |
|---|---|---|
| ropeX | 345 | x of the bell rope |
| ropeY | 152 | y where the knot hangs (bottom of the rope) |
| ropeCount | 10 | potatoes per pull |
| ropeCool | 20 | seconds before the rope works again |
| benchX, benchY | 420, 130 | bench centre x, line its front feet stand on |
| rackX, rackY | 528, 112 | plate tree centre x, its feet |
| legX, legY | 470, 236 | leg press centre x, line its front feet stand on |
| spudGrow | 9 | a plant's time to ripen (rain potatoes start ripe) |
| spudPellets | 10 | ammo per potato picked up |
| spudMaxAmmo | 200 | ammo cap |
| spudPickup | 0.36 | bend-and-grab anim time |
| radius | 14 | player radius |

Note for saved tunings (6801): saved `ropeX, benchX, benchY, rackX, rackY` are ignored unless the save is new enough (`gv === 2`). Godot can just use the defaults.

Constants (lines 797-808, 1044-1051, 1071-1078):
```js
const PLATE_KG = { S: 5, M: 10, L: 20 }, BAR_KG = 20;          // 797
const GYM = { bar: { L: [], R: [] }, pegs: [['S'], ['M'], ['L'], ['S'], ['M'], ['L']], anim: null };  // 798
const BAR_REST = { x: 63.7, y: 24.1 };       // bar centre in the bench's hooks (bench-art 2x px)
const BAR_LEN = 216, BAR_SHOULDER = 55;      // bar-art px
const PRESS_OFF = { x: -1, y: 0 };           // press frames vs bench image (2x px)
const FISTS = [[41.8,19.1,94.7,16.1],[37.8,41.8,95.7,38.8],[41.5,65.3,96.1,60.6],[38.5,41.5,94.1,37.2]]; // per press frame: lx,ly,rx,ry (frame px)
const PEGS = [[22.8,27.6,-1],[22.8,63.6,-1],[22.8,100.8,-1],[64.8,21.6,1],[64.8,60,1],[64.8,96,1]]; // rack px: hole x,y, side
const PEG_ROWS = [[16,37],[53,74],[90,115],[12,31],[50,70],[86,108]];   // rack-art rows each peg's rod spans
const RACK_POST = [35, 52], RACK_BASE = 120;  // rack-art columns of the post; row where the base starts
const LEG = { horn: { L: [], R: [] } };       // L = back horn (behind foot plate), R = front horn
const LEG_KG = 50;                            // sled on its own
const LEG_HORNS = [ {L:[74.5,41],R:[178,58.5]}, {L:[96,29.6],R:[190,46.5]}, {L:[74.5,42],R:[178,60]},
                    {L:[74.5,41],R:[178.5,58.5]}, {L:[74.5,42],R:[178,60]}, {L:[74.5,42],R:[178,60]} ];
   // index 0 = empty machine; index fi+1 = press frame fi. First plate spot per horn, machine-art px
const LEG_DIR = { L: [-1, -0.03], R: [1, 0.06] };   // direction each horn runs
const LEG_STEP = 5;                                 // plate thickness along a horn (art px)
const ROPE = { cool: 0, pull: 0 };   const RAIN = [];   // 9992-9993
```
The game_data.json dumps GYM, LEG, ROPE and `calls.benchBox/rackBox/legBox/barRest` (evaluated):
benchBox {x0:393,x1:449,y0:101,y1:129}, rackBox {509,547,96,111}, legBox {424,516,210,234}, barRest {x:420.85,y:71.05}.

"2x pixels": all gym art is drawn at **half its pixel size** (1 art px = 0.5 arena px). All positions measured "in
art px" are divided by 2 when drawn. Image smoothing is off everywhere (nearest filtering).

---------------------------------------------------------------------------------------------------
## 1. Art

### 1a. Extracted PNGs (embedded base64) → `/home/user/Smashed-tv/godot/scripts/lobby_life/art/gym/`
Script: `<your scratchpad>/extract_gym.py`.
All drawn at **natural size / 2** unless noted.

| file | px | HTML source | what |
|---|---|---|---|
| bench_press_frame0.png | 149x164 | GYM_ART.press[0] (786) | Jared on bench + uprights, arms locked out (top). Same as manifest `godot/assets/misc/line786_0.png` |
| bench_press_frame1.png | 149x164 | press[1] (787) | halfway down. = `assets/misc/line787_0.png` |
| bench_press_frame2.png | 149x164 | press[2] (788) | bar at chest. = `assets/misc/line788_0.png` |
| bench_press_frame3.png | 149x164 | press[3] (789) | halfway, red-faced strain (heavy). = `assets/misc/line789_0.png` |
| bench.png | 124x142 | GYM_ART.bench (791) | empty bench with uprights (no bar) |
| plate_tree_rack.png | 84x158 | GYM_ART.rack (792) | plate tree (post, 6 pegs, base), empty |
| barbell.png | 216x14 | GYM_ART.bar (793) | bare barbell |
| plate_L.png / plate_M.png / plate_S.png | 37x47 / 29x38 / 22x30 | GYM_ART.plate.L/M/S (794) | bar plates seen edge-on (used on bar, tree AND in hand) |
| collar.png | 20x18 | GYM_ART.collar (795) | bar collar |
| legpress_machine.png | 214x164 | ART_B64['legpress.png'] (1037) via LEG_ART.machine | empty leg press (used when nobody's in it) |
| legpress_frame1..5.png | 214x164 | ART_B64['legpress-1..5.png'] = LEG_ART.press[0..4] | whole machine WITH Jared: [0] legs out, [1] halfway, [2] knees in, [3] red-faced strain (after 10 reps), [4] gritted-teeth strain |
| legplate_L/M/S.png | 36x47 / 30x38 / 24x30 | ART_B64['legplate-*.png'] = LEG_ART.plate | plates on the leg-press horns |
| legpress_base.png | 215x167 | ART_B64['legpress-base.png'] = LEG_LAYER.base | machine without sled (layered mode only, see 4f) |
| legpress_sled.png | 140x59 | ART_B64['legpress-sled.png'] = LEG_LAYER.sled | sled (foot plate, sleeves, horns) (layered mode only) |

Not extracted (other features in the same ART_B64 dict): bedroom.png, wardrobe-0..2.png.
`artSrc(name)` (1038) uses the embedded base64, else falls back to `art/<name>`.

### 1b. Art from the manifest
* Potato sprites `SPUD_SPRITES` (9430) → `godot/assets/SPUD_SPRITES_0.png` .. `_4.png` (stages sprout..ready;
  `_4` = a spud lying on the ground, used for falling rain potatoes and ready plants).
* Bench press frames also in the manifest as `godot/assets/misc/line786_0.png .. line789_0.png` (identical bytes).

### 1c. Already-extracted pictures in `godot/scripts/world/props/` (relevant ones)
`bench.png` 216x142 (bench with the bar composite: 216 = bar width), `rack.png` 84x158 (= rack art),
`legpress.png` 200x164 (empty machine cropped to the 200px machine width), `rope.png` 25x302 (a render of the
procedural rope), plus `*_shadow.png`. These are static renders; the dynamic pieces (bar, plates, collars, layers,
frames) need the files from 1a. The rope in the HTML is **procedural**, not an image (section 5).

### 1d. Which characters
The bench and leg-press frames are **Jared/"juicy" art only** (green "JUICY JARED" tank top). There is **no per-character
check and no fallback**: whoever lies on the bench / sits in the leg press (any `p.ch`, incl. tyson, goth...) is drawn
as these Jared frames, and their normal sprite is hidden (12260: `if ((p.lift || p.leg || p.bed) && !w.started) continue;`).
Shirt-print/hair customisation (1659-1660, 1677) is applied to `GYM_ART.press`, `LEG_ART.press`, `LEG_LAYER.jared`
as character `'juicy'`; printed frames are bigger by a factor `im.__ss` and drawn at `naturalWidth / (2*ss)`. Without a
print, ss = 1. A port can ignore the print and use ss = 1.

---------------------------------------------------------------------------------------------------
## 2. Interaction (E) — gymNear / gymAction (934-993)

### 2a. Controls
* Keyboard **E** (8655; guest: 8656 sends `SITREQ` → host runs `lobbyAction(w,p)` 7179-7181).
* Gamepad **A** (button 0) → `padTap('e')` (8976).
* Touch / mouse: the round HUD "carry button" (10109-10136): centre `(ARENA.w-62, ARENA.h-ARENA.wall-70-48)` = (798, 384),
  r = 34, fill `rgba(20,12,28,0.72)`, stroke `#f7a8ff` 2px, label text = the action label (bold 12px, `#f7a8ff`).
  It is drawn whenever a label exists (12443); tap within r+8 does E (8742-8743).
* Prompt key letter: `actKey()` (8882) = `'A'` if the gamepad was used more recently than keyboard/pointer, else `'E'`.
* Getting off: E (label GET UP), OR any stick/move input with magnitude > 0.3, OR the roll input (7192-7199).
* While holding a plate: shoot and roll inputs are suppressed (7206). Cannot pick up Gothica (9872 `!p.plate`).

### 2b. Priority (lobbyAction 10140-10150; label order lobbyLabel 10088-10107)
Gothica-carrying / dive / trampoline / air / barbecue come first; then `gymAction` (gym); then the rope
(`!carrying && ropeNear(p) && ROPE.cool <= 0`), then wardrobe, sitting, bed, chairs...
lobbyLabel: `gymNear(w,p).label` beats `'PULL'` for the rope.

### 2c. gymNear(w, p) — exact (returns {kind, label, side?} or null)
```js
if (!p || !p.alive || w.started || !T.loungeFloor || p.dive || p.sit || NPC_GOTH.carrier === p.id || !gymReady()) return null;
if (p.lift) return { kind: 'getup', label: 'GET UP' };
if (p.leg)  return { kind: 'legoff', label: 'GET UP' };
if (GYM.anim) return null;                    // a load/unload is playing: nothing (except getting up) for anyone
if (legReady()) {
  const n = LEG.horn.L.length + LEG.horn.R.length;
  if (|p.x - (T.legX + 56)| < 20 && p.y > T.legY - 62 && p.y < T.legY + 14) {        // horns' end: x 506±20, y 174..250
    if (p.plate) return n < 6 ? { kind:'legload', label:'LOAD' } : null;
    return n ? { kind:'legunload', label:'UNLOAD' } : null;
  }
  if (!p.plate && |p.x - (T.legX - 16)| < 24 && p.y > T.legY - 4 && p.y < T.legY + 32)  // seat: x 454±24, y 232..268
    return { kind:'leg', label:'LEG PRESS' };
}
if (|p.x - T.rackX| < 40 && p.y > T.rackY - 19 && p.y < T.rackY + 44) {             // tree: x 528±40, y 93..156
  if (p.plate) return GYM.pegs.some(q => q.length < 2) ? { kind:'rack', label:'RACK IT' } : null;
  return GYM.pegs.some(q => q.length) ? { kind:'take', label:'TAKE' } : null;
}
const r = barRest();                                                                 // (420.85, 71.05)
for (s of ['L','R']) { ex = r.x + (s==='L' ? -1 : 1) * 48;                           // ends: x 372.85 / 468.85
  if (|p.x - ex| < 18 && p.y > T.benchY - 45 && p.y < T.benchY + 16) {              // y 85..146
    if (p.plate) return GYM.bar[s].length < 3 ? { kind:'load', side:s, label:'LOAD' } : null;
    return GYM.bar[s].length ? { kind:'unload', side:s, label:'UNLOAD' } : null; } }
if (!p.plate && |p.x - T.benchX| < 22 && p.y > T.benchY - 4 && p.y < T.benchY + 36) // bench front: x 420±22, y 126..166
  return { kind:'lift', label:'BENCH' };
return null;
```
(All `<`/`>` are strict.) Note the "near" zones are tested in this order, so the leg press beats the tree, which beats
the bar ends, which beat the bench front. A matching zone that returns null (e.g. holding a plate at a full bar end)
returns null for the whole function — later zones are not tried (the `return` happens inside the zone `if`).

Label strings: `GET UP`, `LOAD`, `UNLOAD`, `LEG PRESS`, `RACK IT`, `TAKE`, `BENCH`; rope: `PULL`.
First-person crosshair text uses `actKey() + ': ' + label.toLowerCase()` (4917) e.g. "E: rack it", "A: leg press".

### 2d. gymAction(w, p) — what each does (962-993)
`clank()` = `sTone(0.08, 900→700, gain .12, 'square')` + `sNoise(0.05, 2400, Q1.2, gain .1, 'highpass', →900)`.

* **take** (965-969): `size` = biggest size present anywhere on the tree, order `L, M, S`. Peg = among pegs whose
  **top** (last element) is that size, the one with the most plates; else the first peg containing that size (remove
  its last occurrence). `p.plate = size; clank()`.
* **rack** (970): `rackPlate(p.plate); p.plate = null; clank()`.
  ```js
  function rackPlate(size) {   // 818
    const want = { S:[0,3], M:[1,4], L:[2,5] }[size].sort((a,b) => GYM.pegs[a].length - GYM.pegs[b].length);
    const peg = want.find(i => GYM.pegs[i].length < 2) ?? GYM.pegs.findIndex(q => q.length < 2);
    if (peg >= 0) GYM.pegs[peg].push(size); }
  ```
  Max 2 plates per peg. Home pegs: S → 0/3, M → 1/4, L → 2/5 (emptier first; tie → front peg); else any peg with room.
* **load** (971): `GYM.anim = { kind:'load', side, size: p.plate, t:0, dur:0.9, pid:p.id }; p.plate = null;` — plate is
  pushed onto `GYM.bar[side]` when the anim ends. Max 3 plates per side.
* **unload** (972): `size = GYM.bar[side].pop(); GYM.anim = { kind:'unload', side, size, t:0, dur:0.9, pid }`.
  At the end: if that player exists and has no plate, `p.plate = size`, else `rackPlate(size)`.
* **lift** (973-977): if `sideKg('L') !== sideKg('R')` → floater `'LOAD IT EVEN'` col `#ffb070` at (benchX, benchY-70)
  and nothing else. Otherwise `kg = gymKg()` (= 20 + both sides),
  `p.lift = { t:0, reps:0, rep: 1.3 + kg*0.012 }; p.x = T.benchX; p.y = T.benchY + 18; p.vx = p.vy = 0;`
  floater `kg + ' KG'` col `#f6d17a` at (benchX, benchY-70).
* **getup** (978-980): `reps = p.lift.reps; p.lift = null;` if reps>0 floater `reps + (reps===1?' REP':' REPS')` col
  `#8fd3ff` at (benchX, benchY-70). (Getting up by moving the stick: `p.lift = null` only, no floater, position not changed — 7193.)
* **legload** (982): `LEG.horn[legSide(true)].push(p.plate); p.plate = null; clank();` — instant, no animation.
* **legunload** (983): `p.plate = LEG.horn[legSide(false)].pop(); clank();`
  ```js
  function legSide(load) {   // 1057
    const kg = { L: legSideKg('L'), R: legSideKg('R') }, n = s => LEG.horn[s].length;
    if (load) return n('R') >= 3 ? 'L' : n('L') >= 3 ? 'R' : kg.L < kg.R ? 'L' : 'R';
    return !n('L') ? 'R' : !n('R') ? 'L' : kg.L > kg.R ? 'L' : 'R'; }
  ```
  (Leg press allows uneven loading; max 6 total, effectively 3 per horn.)
* **leg** (984-987): `kg = legKg()` (= 50 + both horns); `p.leg = { t:0, reps:0, rep: 1.2 + kg*0.008 };
  p.x = T.legX - 16; p.y = T.legY + 6; p.vx = p.vy = 0;` floater `kg + ' KG'` `#f6d17a` at (legX-10, legY-100).
* **legoff** (988-990): as getup, floater at (legX-10, legY-100). (Stick/roll exit: `p.leg = null; p.y = T.legY + 20;` no floater — 7197.)

### 2e. While on a machine (7192-7199, every input step, lobby only)
Input is zeroed (move, shoot, roll) and the player is pinned: bench `(benchX, benchY+18)`, leg press `(legX-16, legY+6)`.
If `w.started` they are cleared (`p.lift = null` / `p.leg = null`). Run start (13562): held plates go `rackPlate`,
`p.lift = p.leg = null`. stepGym (1007): a player holding a plate who dives (tower) or dies → `rackPlate`, plate null.

### 2f. Timing / reps (stepGym 994-1025, called each sim step, 8042)
```js
const before = Math.floor(p.lift.t / p.lift.rep); p.lift.t += dt;
if (Math.floor(p.lift.t / p.lift.rep) > before) { p.lift.reps++;
  w.floaters.push({ x: T.benchX, y: T.benchY - 64, text: String(p.lift.reps), t: 0, col: '#8fd3ff' });
  sNoise(0.08, 300, 1.2, 0.12, 'lowpass', 200); }        // grunt/thump
```
Leg press same with `p.leg`, floater at (legX-10, legY-96), sound `sNoise(0.08, 260, 1.2, 0.12, 'lowpass', 180)`.
A rep is counted at the end of each full cycle (first at t = rep). Rep length: bench empty bar 1.54 s, +0.012 s/kg;
leg press empty 1.6 s, +0.008 s/kg. The rep duration is fixed when you lie down (kg at that time).

GYM.anim timing: `an.t += dt`; when crossing `0.3*dur` → `sTone(0.05, 700→500, .1, 'square')` (collar off); crossing
`0.62*dur` → `sTone(0.09, 260→180, .2, 'triangle')` + `sNoise(0.06, 1800, 1.2, .14, 'bandpass', →600)` (plate home);
at `t >= dur` apply the result (2d) and `GYM.anim = null`.

### 2g. Floating text (8199-8203, draw 12626-12636)
`{x, y, text, t, col}`; each step `t += dt; y -= 34*dt`; removed at t > 0.9. Alpha 1 until t 0.6, then linear to 0 at 0.9.
Font `bold 13px ui-monospace, monospace`, centred, black 60% shadow at +1,+1, then colour. Max 30 floaters (6512).
First person draws them projected at height 40 + t*30, bold 16px (4075-4079).

All texts: `'NN KG'` (#f6d17a), rep numbers `'1','2',..` (#8fd3ff), `'N REP'/'N REPS'` (#8fd3ff), `'LOAD IT EVEN'` (#ffb070),
`'POTATOES!'` (#d8b878). There is no persistent kg counter on screen; kg is only shown by these floaters.

---------------------------------------------------------------------------------------------------
## 3. Bench press drawing (810-895)

Derived positions (bench art 124x142, defaults):
```js
benchOrigin() = { x: T.benchX - im.naturalWidth/4, y: T.benchY - im.naturalHeight/2 }  // (389, 59): top-left; drawn 62x71
barRest()     = { x: o.x + 63.7/2, y: o.y + 24.1/2 }                                     // (420.85, 71.05)
```
`drawGymImg(im, cx, cy, flip)` (823): draws `im` **centred** at (round(cx), round(cy)) at naturalSize/2, optional
horizontal flip.

**drawBenchStation(w)** (878):
1. Shadow: ellipse centre (benchX, benchY-9), radii 34x9, `rgba(0,0,0,0.22)`.
2. No lifter: bench image at (round(o.x), round(o.y)), size natural/2; then `drawLoadedBar(barRest)`.
3. Lifter (`w.players.find(q => q.lift && q.alive)`): `i = liftFrame(lifter)`; frame image at
   `px = o.x + PRESS_OFF.x/2` (= o.x - 0.5), `py = o.y`, size natural/(2*ss) (74.5x82). The press frames include the
   bench and uprights, so the empty bench is NOT drawn. Then
   `drawLoadedBar(px + (lx+rx)/4, py + (ly+ry)/4 + 0.5)` with `[lx,ly,rx,ry] = FISTS[i]` (bar centred between his
   fists), then the **fist overlay** on top at (round(px), round(py)) natural/2.
   Fist overlay (862-873): a copy of the plain (un-printed) frame keeping only pixels within 8.7 frame-px of either fist
   point AND skin-coloured (`r > 150 && r > g + 25 && g > b`); everything else transparent. Purpose: his hands appear
   gripping over the bar. In Godot: precompute 4 small PNGs or use a shader mask.

```js
function liftFrame(p) {   // 874: top, halfway, chest, halfway (red-faced if heavy), top
  const f = (p.lift.t % p.lift.rep) / p.lift.rep;
  return f < 0.2 ? 0 : f < 0.4 ? 1 : f < 0.6 ? 2 : f < 0.8 ? (gymKg() >= 60 ? 3 : 1) : 0; }
```
Red face = frame 3, only when the CURRENT bar total >= 60 kg (bar 20 + 40 of plates).

**drawLoadedBar(cx, cy)** (830-859), all in arena px:
```
bar image centred at (cx, cy) (108x7 drawn).  half = BAR_LEN/4 = 54
for side s, dir = L:-1, R:+1:
  shoulder = cx + dir*(half - BAR_SHOULDER/2)   = cx ± 26.5
  end      = cx + dir*half                       = cx ± 54
  slot(k)  = shoulder + dir*(2 + 3.35*k)         // plate k (0 = innermost)
  cpos(m)  = shoulder + dir*(2 + 3.35*m + 2)     // collar just outside plate m-1
  plates drawn innermost first at (slot(k), cy), flipped on the R side
  collarX = cpos(n) (n = plates on that side); collar drawn at (collarX, cy), flipped on R
```
Animation on side `an.side`, `f = an.t/an.dur`, `ease(x) = smoothstep clamp 0..1`, `collarOut = end + dir*8`:
* load: plate not drawn while f < 0.3 (the code computes end+dir*5 there but skips drawing); from 0.3 it is drawn at
  x = `end + (slot(n) - end) * ease((f-0.3)/0.35)` (reaches its slot at 0.65 and stays). Collar: f<0.3 `cpos(n) → collarOut` eased by f/0.3; 0.3–0.65 hidden; ≥0.65
  `collarOut → cpos(n+1)` eased by (f-0.65)/0.35.
* unload (plate already popped, n = remaining): plate at slot(n) until 0.3, then slides to `end + dir*11` eased by
  (f-0.3)/0.35, hidden from f ≥ 0.65. Collar: `cpos(n+1) → collarOut` (f<0.3), hidden 0.3–0.65, `collarOut → cpos(n)`.

Draw layer: bench station is inserted into the y-sorted character list with sort key `T.benchY - 14` (=116) (12226): it is
drawn just before the first character with `y >= 116`. The lifter himself is not drawn as a character.

---------------------------------------------------------------------------------------------------
## 4. Plate tree and the held plate

### 4a. Plate tree drawing (896-933)
`rackOrigin() = { x: T.rackX - 84/4, y: T.rackY - 158/2 }` = (507, 33); drawn 42x79.
The rack art is cut into 4 layers once (alpha masks, in rack-art px):
`back`: y < 120 && x > 52; `front`: y < 120 && x < 35; `post`: y < 120 && 35 ≤ x ≤ 52; `base`: y ≥ 120.
```js
plateAt(i, k) = { x: o.x + (PEGS[i][0] + side*4*k)/2, y: o.y + (PEGS[i][1] - side*0.4*k)/2 }   // side = PEGS[i][2]
```
Order: shadow ellipse (rackX, rackY-8) 24x8 alpha .22 → `back` layer → back-peg plates (pegs 3..5, k from last to 0,
**flipped**) → `post` → `front` → front-peg plates (pegs 0..2, k 0..n-1, not flipped) → front peg tips: for each front peg
with n plates, `hole = PEGS[i][0] - 4*(n-1)`, `cut = max(0, hole-1)`, redraw the `front` layer's source rect
`(0, r0, cut, r1-r0)` (r0,r1 = PEG_ROWS[i]) to `(o.x, o.y + r0/2, cut/2, (r1-r0)/2)` (the rod's tip poking out through
the outer plate) → `base`. Sort key `T.rackY - 10` (=102).
Initial pegs: front-left 0:S, 1:M, 2:L; back-right 3:S, 4:M, 5:L (top to bottom). Total 6 plates = 70 kg in the gym.

### 4b. Held plate (1151-1154)
```js
function drawHeldPlate(p) { if (!p.plate) return;
  drawGymImg(GYM_ART.plate[p.plate], p.x + (p.fx < 0 ? -4 : 4), p.y - 16, p.fx < 0); }
```
Bar-plate art (not the legplate art), half size, centred 4 px to the facing side and 16 px above p.y, flipped when facing
left. Drawn right after the character (12265-12266), so always in front of him. Same for any character. Not shown in
first-person cut-outs.

---------------------------------------------------------------------------------------------------
## 5. Leg press (1026-1132)

`legOrigin() = { x: round(T.legX - 50), y: round(T.legY - 82) }` = (420, 154) (art corner; 214x164 art, 200 px of
its width is the machine). `legBox()` = {x0 legX-46, x1 legX+46, y0 legY-26, y1 legY-2}.
```js
function legFrame(p) {   // 1062
  const f = (p.leg.t % p.leg.rep) / p.leg.rep;
  return f < 0.2 ? 0 : f < 0.4 ? 1 : f < 0.6 ? 2 : f < 0.8 ? (p.leg.reps >= 10 ? 3 : 4) : 0; }
```
Frames: 0 legs out, 1 halfway, 2 knees in, then pushing out: 3 red-faced (once reps ≥ 10), else 4 gritted teeth. Unlike
the bench, red face depends on rep count, not kg.

### 5a. drawLegStation(w) (1109-1132) — the path actually used
`lifter = w.players.find(q => q.leg && q.alive)`, `fi = legFrame(lifter)` or -1.
`src` = `LEG_ART.press[fi]` (legpress_frame{fi+1}.png) if a lifter and loaded, else `LEG_ART.machine`.
`H = LEG_HORNS[on ? fi + 1 : 0]`, `at(s,k) = H[s] + LEG_DIR[s]*LEG_STEP*k` (art px).
1. Shadow ellipse (legX, legY-12) radii 50x12, alpha .22.
2. `src` at (o.x, o.y) size natural/(2*ss) (107x82).
3. Back horn: plates L at `o + at('L',k)/2` (not flipped); if any:
   `part(x0, ly-7, at('L',nL-1)[0]-x0, 14)` with `x0 = lx - 20.5` (horn end over the plates) and
   `part(lx+7.5, ly-27, 18, 62)` (foot plate and his boots back in front).
4. Front horn: plates R at `o + at('R',k)/2`, **flipped**; if any: `x = ceil(at('R',nR-1)[0]) + 1;
   part(x, ry-8.5, srcWidth - x, 18)` (horn end out through them).
`part(sx,sy,sw,sh)`: `sx = max(0, floor(sx/2)*2)`; copies src rect (sx,sy,sw,sh) (×ss) to `(o.x+sx/2, o.y+sy/2, sw/2, sh/2)`.
Plates use `legplate_*.png` art. Sort key `T.legY - 14` (=222).

### 5b. Layered mode (1066-1108) — dormant
`legLayered()` needs `LEG_LAYER.jared.length === 5 || LEG_LAYER.test`; `jared` is `[]` and nothing in the file fills
it, so this path **never runs** in the shipped game. If you want it: base at `o + origin(-0.55,-0.6)`; sled at
`o + origin + (rest + travel*t)/2` with rest (37,45.6), travel (13.8,-24.7) art px, t from `legSledAt` (keys
[1,.5,0,.5,.5] interpolated at f = 0.1,0.3,0.5,0.7,0.9); horns on the sled L (18,18) dir (-0.98,-0.2), R (116,36) dir
(1,0.07); foot-plate front piece `plateFront [22,0,24,59]`. Recommend: implement 5a only.

---------------------------------------------------------------------------------------------------
## 6. The bell rope and the potato rain (9988-10086)

```js
function ropeNear(p) { return !!p && p.alive && !p.dive && |p.x - T.ropeX| < 26 && p.y > T.ropeY - 4 && p.y < T.ropeY + 40; }
// x 319..371, y 148..192
function pullRope(w) {
  ROPE.cool = T.ropeCool; ROPE.pull = 0.45;
  for (i = 0; i < T.ropeCount; i++) RAIN.push({ x: 318 + rnd*262, y: 126 + rnd*108, dz: 380 + rnd*160, vz:0, vx:0, vy:0,
      squash:0, delay: 0.35 + i*0.12 + rnd*0.08, bounces:0, rot: rnd*6.28, spin: (rnd-0.5)*10 });
  floater 'POTATOES!' #d8b878 at (ropeX, ropeY - 30);
  sTone(0.5, 1320→1240, .22, 'sine'); sTone(0.7, 880→840, .18, 'triangle');   // the bell
}
```
Conditions to pull (10150): lobby, not carrying Gothica, `ropeNear`, `ROPE.cool <= 0`, and no gym action took E first.
`rnd(w)` is the world's seeded RNG (any uniform 0..1 works). Fall zone: x 318..580, y 126..234 (the gym floor).

**stepRain(w, dt)** (10007, every step): `ROPE.cool, ROPE.pull` count down to 0. For each potato: wait `delay`; then
`squash -= 9*dt` (min 0); `vz -= 1500*dt; dz += vz*dt; x += vx*dt; y += vy*dt; rot += spin*dt`. When dz ≤ 0:
`dz = 0; hit = -vz; keep = [0.45, 0.36, 0.28][min(2, bounces)]; bounces++`;
if `hit > 110 && bounces <= 3`: bounce `vz = hit*keep`, `kick = hit*0.08`, `vx = vx*0.6 + (rnd-0.5)*kick` (same vy),
`spin *= 0.55; squash = 1`; if `hit > 300` dust `burst(w, x, y+4, 3, '#b9a58a', 40)`; track loudest hit.
Else it **settles**: removed from RAIN; clamp x,y into `[wall+12, w-(wall+12)]` / `[wall+12, h-(wall+12)]`; if in the pool
→ splash FX only; else (lobby) push out of every `lobbySolidBoxes()` box with radius 10 (`pushOutOfBox`, 5642), then
`w.plants.push({ x, y, t: T.spudGrow, wob: 0.3 })` — i.e. **a ready potato (spud pickup)** lying on the floor. Rain
potatoes are not capped by `spudMax`.
Thud sound once per step for the loudest bounce, throttled to one per 50 ms:
`sNoise(0.05, 220 + thud*0.2, 1.4, min(0.22, 0.06 + thud/3000), 'lowpass', 300)`.
(Lobbed husks that land short also go into RAIN with `delay:0, dz:0` and bounce like this, 8058.)

**Ready potato = pickup** (stepPlants 6000-6019): a player who is alive, not reloading/picking up/throwing, within
`T.radius + 14` (28) of it, and with `ammo < spudMaxAmmo`, auto-picks it up: `ammo = min(200, ammo + 10)`,
`p.pickup = 0.36` (bend-down anim), plant removed, `fx(FX.WALL)`, sounds `sNoise(0.12, 600, 1.2, .3, 'lowpass', 120)` +
`sTone(0.08, 220→160, .14, 'triangle')`. Plants are host state (synced); RAIN is local decoration only.

**drawRope(w)** (10047, drawn with the floor props 11909, before characters; hidden if `w.started` or calibrating):
```
ready = ROPE.cool <= 0; sway = sin(w.t*1.6)*3
top = ARENA.wall (18); bot = T.ropeY + (ROPE.pull > 0 ? sin(ROPE.pull/0.45*PI)*14 : 0)   // dips 14px when pulled
rope: quadratic curve (ropeX, top) → ctrl (ropeX + sway*0.5, (top+bot)/2) → (ropeX + sway, bot),
      round caps, 4px ready '#b08a52' / cooling '#6e5a3c'
highlight: same curve shifted x-1, 1.5px, ready '#e2bd82' / cooling '#8a7454'
knot: ellipse at (ropeX + sway, bot + 6) radii 6x9, ready '#8a5a2b' / cooling '#5c4530', outline rgba(0,0,0,.35) 1px
prompt (local player, ready, ropeNear, not carrying Gothica): actKey() + ': pull', bold 11px sans, centred at
      (ropeX, bot+26), black 60% shadow at (+1,+1), white text
```
**drawRain()** (10069, after plants 12009, before characters): per potato with delay ≤ 0:
`sf = max(0.3, 1 - dz/300)`; shadow ellipse at (x, y+6) radii 13sf x 5sf, `rgba(0,0,0,0.28*sf)`; sprite `SPUD_IMG[4]`
drawn 30 px wide (height by aspect) **centred** at (x, y - dz), scaled (1 + 0.3*squash, 1 - 0.3*squash), rotated `rot`.
Fallback brown ellipse 11x8 `#7a5230`.
Landed potato (plant stage 4, 11991-12006): shadow ellipse (x, y+6) 13x5 alpha .28; SPUD_IMG[4] 30 px wide, bottom at
y+8, top-left `(x-15, y+8-dh)`; glint circle at (x, y-10) radius 3+2g, `rgba(255,240,180,0.35g)`, g = 0.5+0.5 sin(5t + x).

---------------------------------------------------------------------------------------------------
## 7. Gothica's reactions (NPC; detail in her own spec) — 10277-10295, 9872
```js
const lifter = w.players.find(q => (q.lift || q.leg) && q.alive), set = lifter && (lifter.lift || lifter.leg);
if (lifter && set.reps >= 2) {
  if (!n.watch) { n.watch = true; n.said = false; }
  const leg = !lifter.lift;
  const spot = leg ? { x: T.legX - 80, y: T.legY + 26 } : { x: T.benchX + 58, y: T.benchY + 24 };   // (390,262) / (478,154)
  const at   = leg ? { x: T.legX - 16, y: T.legY - 30 } : { x: T.benchX, y: T.benchY - 10 };       // what she looks at
  walk to spot at T.npcSpeed * 2.4 (10314); when within 4 px: stop, face `at`,
  if (!n.said && set.reps >= 5) { n.said = true; n.bubble = { text: "Wow, you're really strong!", t: 0, dur: 3.5 }; }
} else if (n.watch) { n.watch = false; n.wait = 1.2; }   // he got up: pause, then wander
```
From the 2nd rep she hurries over; at the 5th (once per session on the machine, if she's there) she says
**"Wow, you're really strong!"** (speech bubble, drawSpeech 1134-1150). Also you cannot pick her up while holding a plate
or lifting (9872), and gym E is disabled while you carry her (gymNear checks `NPC_GOTH.carrier === p.id`).

---------------------------------------------------------------------------------------------------
## 8. First person (shroom "FP" view)
* Lying on the bench / sitting in the leg press makes `fpBusy()` true (3587-3590): FP steps aside and the normal
  top-down screen shows until you get up (4280: `SHROOM.busy = true`, pointer lock released). Getting off with E or a
  move key re-grabs the mouse (3699-3700).
* In FP the bench, rack, leg press and rope are static cut-out billboards captured from their top-down drawings
  (`shroomCapture` 4034-4047); recaptured whenever `GYM.bar`, `GYM.pegs` or `LEG.horn` change (4323-4324).
  Ready potatoes are billboards 30 px wide (4103-4105). RAIN isn't drawn in FP. Held plate not drawn in FP.
* The E action label shows under the crosshair: `actKey() + ': ' + label.toLowerCase()`, bold 15px, `#f7a8ff`, at
  (ARENA.w/2, ARENA.h/2 + 32) with shadow, plus the round HUD button (4915-4921).
* Floaters drawn in FP at bold 16px (4075-4079).

---------------------------------------------------------------------------------------------------
## 9. Solids and multiplayer
* `lobbySolidBoxes()` (3431) includes benchBox (814: x benchX-27..+29, y benchY-29..benchY-1), rackBox (815: x ±19,
  y rackY-16..rackY-1), legBox (1054). Players collide with these in the lobby.
* Host-authoritative. Snapshot (8358-8365): per player `lift [t*100, reps, rep*100]`, `leg [...]`, `plate` 1/2/3 = S/M/L;
  world `gy: [bar.L string, bar.R string, pegs strings, horn.L, horn.R, anim [kind, side, size, t*100, dur*100, pid]]`.
  Guest applies at 8406-8408, 8463-8465. ROPE/RAIN are local (only the landed plants sync).

## 10. Sound summary (Web Audio synth; `sTone(dur, f0, f1, gain, wave)` = oscillator with exponential pitch glide
f0→f1 and gain decaying exponentially to ~0 over dur; `sNoise(dur, freq, Q, gain, filterType, sweepTo)` = looped white
noise through a biquad whose cutoff glides freq→sweepTo, same gain decay) — 11213-11239
| event | sound |
|---|---|
| take / rack / leg load / leg unload | square 900→700 Hz 80 ms (.12) + highpass noise 2400→900 50 ms (.1): metallic clank |
| bar anim at 30% (collar off) | square 700→500 50 ms (.1) |
| bar anim at 62% (plate home) | triangle 260→180 90 ms (.2) + bandpass noise 1800→600 60 ms (.14) |
| bench rep | lowpass noise 300→200 80 ms (.12) |
| leg rep | lowpass noise 260→180 80 ms (.12) |
| rope pull (bell) | sine 1320→1240 0.5 s (.22) + triangle 880→840 0.7 s (.18) |
| potato bounce thud | lowpass noise (220+hit*0.2)→300, 50 ms, gain min(.22, .06+hit/3000), ≤1 per 50 ms |
| potato picked up | lowpass noise 600→120 120 ms (.3) + triangle 220→160 80 ms (.14) |
No sound for lying down / getting up / "LOAD IT EVEN".
