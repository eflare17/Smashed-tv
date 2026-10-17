# Gothica in the lobby: everything beyond wandering (spec from Smashed.html)

Source: `/home/user/Smashed-tv/Smashed.html` (line numbers are that file's). Units: HTML arena pixels,
x across, y down the screen (ground), z / `dz` = height. `T` = the tuning table (`godot/data/game_data.json` "T").
Out of scope: Protect Gothica (`PROT`, `w.goth`, `protectCarry`, `stepGoth`, 12880+), the blackjack game rules
themselves (cards spec), the gym machines themselves (gym spec).

Already in the Godot port (`godot/scripts/npc/gothica.gd`): NPC_AREA spot picking (`npcPickSpot` 10195),
shortest path round furniture (`npcNextPoint` 10209), wait 1.5-4 s facing (0,1), stuck backstop (6 px / 2 s),
pushOutOfBox. Everything below is NOT yet ported.

Relevant numbers (game_data.json T unless noted):

| name | value | meaning |
|---|---|---|
| `T.npcGoth` | 1 | NPC on/off (0 = no lobby Gothica at all) |
| `T.npcSpeed` | 38 | stroll speed px/s; x2.4 = 91.2 when hurrying to watch / deal |
| `T.npcJiggle` | 2.2 | her jiggle multiplier as an NPC (and when carried) |
| `T.carryRange` | 46 | pick-up distance (carrier centre to her centre, ground plane) |
| `T.carryScale` | 1.0 | size of the carry art relative to run art |
| `T.jiggle` | 1.5 | global jiggle strength |
| `T.runStride` | 13 | px per walk frame |
| `T.radius` | 14 | body radius |
| `T.spriteScale` | 4.6 | sprite height = radius*spriteScale (=64.4) |
| `T.altScale` / `T.altWide` | 1.242 / 1 | new-art (NEW_ART: juicy, tyson2, goth, inky) extra scale / widen |
| `T.diveFwd` / `T.diveHop` | 130 / 240 | dive forward speed / upward hop |
| `T.boardWalk` | 120 | board walk speed |
| `T.tableX,Y` | 165, 300 | card table |
| `T.benchX,Y` | 420, 130 | bench press |
| `T.legX,Y` | 470, 236 | leg press |
| `T.towerX,Y`, `towerScale` | 604, 190, 1.25 | dive tower |
| `NPC_AREA` (9852) | x0 70, x1 590, y0 250, y1 410 | |
| `POOL` (769) | x0 624, y0 90, x1 815, y1 239 | |
| `ARENA` | w 860, h 520, wall 18 | |
| `CARRIERS` (9858) | `new Set(['juicy','jared'])` | (dumped as `{}` in game_data.json because it is a Set) |
| `DIVE` (5675) | CLIMB 1, BOARD 2, FALL 3, SWIM 4 | |

`PROT.carryFor 4`, `PROT.carryCool 1.5`, `PROT.carrySlow 0.7` (12890-12892) are **Protect Gothica only**.
In the lobby there is **no carry time limit, no cooldown after putting her down, and no slow-down** while
carrying (line 7511 applies `PROT.carrySlow` only when `w.goth` exists). Only the 0.34 s pick/drop animation
gates E (see 4.3).

Tower geometry (towerGeo 5657, computed with the values above): ladderX 602.125, climbY 188, baseY 200.8,
deckH 93.1 (height at top of ladder), boardH 100.6 (height on the board), boardX0 622.75, tipX 682.75.

---

## 1. State on the NPC (`NPC_GOTH`, 9853)

```js
const NPC_GOTH = { id: 'npc_goth', npc: true, ch: 'goth', weapon: 'blaster', alive: true,
                   x: 200, y: 360, odo: 0, moving: false, ix: 0, iy: 1, fx: 0, fy: 1,
                   vx: 0, vy: 0, tx: 200, ty: 360, wait: 1, t: 0,
                   carrier: -1, face: false };
```

Fields added at run time:

| field | type | meaning |
|---|---|---|
| `t` | s | last `performance.now()/1000`; dt = clamp(now - t, 0, 0.1). Her update runs from the **draw** pass, in real time (see 1.1) |
| `carrier` | int | player id holding her, -1 = nobody |
| `face` | bool | carry art mirrored (true = carrier faces left). Her head is *behind* him |
| `anim` | `{kind:'pick'|'drop', t, dur:0.34}` or null | scoop / set-down animation |
| `thrown` | null / `'air'` / `'floor'` / `'swim'` | thrown state machine |
| `vz`, `dz` | px/s, px | height while thrown; `dz` also = carrier's dz while carried (up the ladder) |
| `spin` | rad | cartwheel angle in the air (+9 rad/s) |
| `dive` | 0 or `DIVE.SWIM` (4) | set to SWIM while paddling so the generic swim drawing/drips/ducks work |
| `rip` | s | timer to next swim ripple |
| `bubble` | `{text, t, dur}` or null | speech bubble |
| `watch` | bool | watching a lifter |
| `said` | bool | already said the gym line this watch |
| `dealing` | bool | at the card table dealing |
| `bjSayN` | int | last blackjack line number shown (`w.bj.sayN`) |
| `stuckT`, `stuckX`, `stuckY` | | wandering backstop (already ported) |

State on the carrier (a player `p`): nothing new is stored on him. "Carrying" is
`NPC_GOTH.carrier === p.id` (helper `gothHeldBy(w,p)` 12909: `!p.npc && NPC_GOTH.carrier === p.id && !w.started`).
His existing fields used: `x, y, dz, vx, vy, vz, fx, ix, moving, odo, dive, alive, ch, plate, lift, leg, sit, bed, tramp, food`.

### 1.1 Update order: `lobbyGoth(w)` (10247)

Called from the render pass (12221 top-down, 4329 first person), returns the NPC to draw or null.
Order of checks each call (first that applies wins):

1. Guest machine: `gothFromHost(w)` (mirror of host; 2.9).
2. `!T.npcGoth || w.started || cal.on` -> if carried, `putGothDown(w)`; return null (hidden).
3. dt; `bubble.t += dt`, drop bubble when `t > dur` (ticks even while carried).
4. **Carried** (`carrier >= 0`) -> section 4. Returns null (drawn as part of him).
5. **Thrown** -> `stepThrownGoth` (section 5); return n.
6. **Blackjack** (`w.bj` exists) -> section 3.
7. **Watching a lifter** -> section 2.
8. Wander (already ported). Speed `T.npcSpeed * (n.watch || n.dealing ? 2.4 : 1)` (10314); walking uses the
   same npcNextPoint path and stuck backstop toward whatever `tx,ty` was set.

When she *arrives* at a dealing/watch spot (`hypot < 4`), she stops (`moving=false, vx=vy=0`), resets
`stuckT=0, stuckX=undefined`, sets facing, and returns without wandering.

---

## 2. Watching the player lift (gym) — 10277-10295

```js
const lifter = w.players.find(q => (q.lift || q.leg) && q.alive), set = lifter && (lifter.lift || lifter.leg);
if (lifter && set.reps >= 2) {
  if (!n.watch) { n.watch = true; n.said = false; }
  const leg = !lifter.lift;
  const spot = leg ? { x: T.legX - 80, y: T.legY + 26 } : { x: T.benchX + 58, y: T.benchY + 24 };
  const at   = leg ? { x: T.legX - 16, y: T.legY - 30 } : { x: T.benchX, y: T.benchY - 10 };
  n.tx = spot.x; n.ty = spot.y; n.wait = 0;
  if (Math.hypot(n.x - spot.x, n.y - spot.y) < 4) {
    n.moving = false; n.vx = n.vy = 0;
    const dx = at.x - n.x, dy = at.y - n.y, d = Math.hypot(dx, dy) || 1;
    n.fx = dx / d; n.fy = dy / d;                     // watching him
    if (!n.said && set.reps >= 5) { n.said = true; n.bubble = { text: "Wow, you're really strong!", t: 0, dur: 3.5 }; }
    ...return n;
  }
} else if (n.watch) { n.watch = false; n.wait = 1.2; }
```

- Trigger: any alive player on the bench (`p.lift`) or leg press (`p.leg`) with `reps >= 2` (reps counted by
  the gym code, `p.lift.reps++` 1011, `p.leg.reps++` 1020). The first such player in `w.players` order.
- Bench: she goes to (478, 154) and faces (420, 120). Leg press: goes to (390, 262), faces (454, 206).
- Walks there at 91.2 px/s (2.4x), path round furniture, `wait` forced to 0.
- Says **"Wow, you're really strong!"** for 3.5 s, once per watching session, when `reps >= 5` *and* she is
  standing at the spot (if he reaches 5 before she arrives, she says it on arrival).
- When he gets up (no lifter, or reps < 2 which can't happen mid-set): `watch=false`, `wait=1.2` s, then she
  picks a new random spot. `said` is reset when the next watch starts.
- Blackjack (section 3) is checked first and overrides watching.
- Speech bubble side while watching: `drawSpeech(p, p.watch ? (p.x >= T.benchX ? 1 : -1) : 0)` (12402).
  Bench spot x 478 >= 420 -> away = +1 (bubble opens to her right). Leg spot x 390 < 420 -> away = -1
  (opens to her left). Note it compares with benchX even at the leg press.

---

## 3. Dealing cards at the table — 10263-10276 (movement/pose only)

```js
const bj = w.bj;
if (!bj) n.bjSayN = 0;
if (bj && bj.sayN !== n.bjSayN) { if (bj.say) n.bubble = { text: bj.say, t: 0, dur: 2.6 }; n.bjSayN = bj.sayN; }
if (bj) {
  n.dealing = true;
  const spot = { x: T.tableX, y: T.tableY - 30 };          // (165, 270): behind the table, which is x 113..217, y 284..316
  n.tx = spot.x; n.ty = spot.y; n.wait = 0;
  if (Math.hypot(n.x - spot.x, n.y - spot.y) < 4) {
    n.moving = false; n.vx = n.vy = 0; n.fx = 0; n.fy = 1;  // facing the players, over the table
    ...return n;
  }
} else if (n.dealing) { n.dealing = false; n.wait = 1.5; }
```

- `w.bj` exists from the moment a seated player calls her (`bjAction` 'call', or 'deal' with no bj, 5258)
  until 'stop' (`w.bj = null` in idle/done) or nobody is seated / game starts (stepBJ 5288-5296).
- She hurries (91.2 px/s) to (165, 270) and stands facing down (0,1), front pose, idle.
- When the table closes: `dealing=false`, waits 1.5 s, then wanders.
- The cards game does not wait for her to arrive; dealing works wherever she is.
- Every new `bjSay` (sayN increments) becomes her bubble for **2.6 s**. Lines (all from 5250-5321):
  - On being called (random 50/50): **"Cards? Sure, I'll deal."** / **"Ooh, blackjack? Coming!"**
  - On a deal: **"Cards, boys."** (2 seated) / **"Cards up, big guy."** (1 seated)
  - On settling, first that applies: **"Blackjack?! Lucky."** (any player blackjack paid) /
    **"Ugh, I bust."** (dealer > 21) / **"Blackjack. House wins~"** (dealer natural) /
    **"Fine, you win."** (some won, none lost) / **"House wins~"** (some lost, none won) /
    **"Some you win..."** (otherwise).
- Blocked while she's carried or thrown: calling or dealing makes a floater **"Gothica's busy!"** colour
  `#f7a8ff` over the player (bjFloat: at p.x, p.y-70) and nothing else (5259, 5267).
- Edge: `canCarry` does not check `dealing`, so a carrier can pick her up mid-game; while carried the bj
  lines are not shown (lobbyGoth returns before the bj code) and the newest one shows when she's put down.
- Also: while not carried/thrown she is pushed out of the table box with radius 8 every tick
  (`pushOutOfBox(NPC_GOTH, 8, tableBox())`, 5786), already in the port.

---

## 4. Being carried by Jared

### 4.1 Who can carry, and when (`canCarry` 9871)

```js
return T.npcGoth && !w.started && p && p.alive && !p.dive && !p.plate && !p.lift && !p.leg && CARRIERS.has(p.ch) && !NPC_GOTH.thrown
       && Math.hypot(p.x - NPC_GOTH.x, p.y - NPC_GOTH.y) < T.carryRange;     // 46
```

Carriers: `juicy` ("Juicy Jared", the new art) and `jared` ("Jucy Jared (old art)") only. Tyson, Inky and a
player playing Gothica cannot. Either player (host or guest) can carry; only one at a time
(`NPC_GOTH.carrier < 0`). Not while holding a gym plate, on bench/leg press, on the tower or swimming.

### 4.2 The E action (`lobbyAction` 10140) — priority order

E (or tap / pad A) runs, in order (the first that does something wins):

0. Key handler first tries `shroomTryEat()`, `arcadeTryOpen()`, `mirrorTryLook()` (8655). Arcade refuses
   if the host is carrying (`NPC_GOTH.carrier === 0`, 2513). Mirror/shroom don't check carrying.
   While tripping (SHROOM on and not sober) E does nothing else at all, so you can't put her down mid-trip.
1. `if (NPC_GOTH.anim) return;` — ignored during the 0.34 s pick/drop.
2. Trampoline (on it: jump/climb off), barbecue (`bbqAction`), `!carrying && trampNear` climb on, gym
   (`gymNear` returns null while carrying, 935), `!carrying` rope pull, `!carrying` wardrobe, sitting / bong,
   bed get-up, `!carrying` lie down, `!carrying` sit on a chair.
3. **Carrying**:
   ```js
   if (p.dive === DIVE.BOARD) throwGoth(w, (p.fx < 0 ? -1 : 1) * T.diveFwd * 1.25, 40, T.diveHop * 0.9);
   else if (!p.dive) NPC_GOTH.anim = { kind: 'drop', t: 0, dur: 0.34 };   // squat, then she's down
   return;   // on the ladder (CLIMB): nothing, she stays in his arms
   ```
4. **Not carrying, `canCarry`** -> pick up:
   ```js
   NPC_GOTH.carrier = p.id; NPC_GOTH.face = p.fx < 0;
   NPC_GOTH.anim = { kind: 'pick', t: 0, dur: 0.34 };
   const j = JIG.npc_goth; if (j) j.v += 30;          // she bounces as she lands in his arms
   ```

So PICK UP has the lowest priority: next to a chair you sit, next to the bed you lie down, etc.

### 4.3 While carried (lobbyGoth 10251-10260)

```js
const p = carrierOf(w);
if (!p || !p.alive) { putGothDown(w); return n; }
n.x = p.x; n.y = p.y; n.dz = p.dz || 0;                          // up the ladder with him
if (n.anim) { n.anim.t += dt; if (n.anim.t >= n.anim.dur) { const k = n.anim.kind; n.anim = null; if (k === 'drop') { putGothDown(w); return n; } } }
if (p.dive === DIVE.FALL) { throwGoth(w, p.vx * 1.15, p.vy, p.vz * 1.05); return n; }   // walked off the end with her
if (p.moving && Math.abs(p.ix) > 0.2) n.face = p.ix < 0;      // face the way he last walked
return null;
```

Effects on the carrier (stepBase 7172-7173, lobbyClamp):
- `shoot` and `roll` inputs are forced false while carrying (so no rolling, no shooting, no roll-dive off the board).
- During `anim` (pick or drop) his movement input is zeroed: he stands still for 0.34 s.
- Walls: `lobbyClamp(p, T.radius, NPC_GOTH.carrier === p.id)` — with `shut=true` the doorways (bedroom door,
  back door) and the yard are removed from the walkable areas: **he can't leave the lounge with her**
  ("she lives in the lounge", lobbyAreas 2166ish). He stays in the lounge rectangle or the bedroom if already there.
- No speed change, no time limit, no cooldown in the lobby.
- He can climb the dive tower with her (the ladder start, 7290, doesn't check carrying): she rides at
  `n.dz = p.dz`. On the ladder E does nothing. On the board E throws her. Walking off the tip (`x >= tipX`
  and pushing right) puts him in DIVE.FALL and she's thrown with his velocity (5.2). Climbing back down works.
- Other blocks while carrying: chairs (`chairNear` 3436 returns 0), gym (935), bed, trampoline, rope,
  wardrobe, arcade (host only). Blackjack call -> "Gothica's busy!".
- Game start, calibration (`cal.on`), or carrier dies/leaves -> `putGothDown`.

### 4.4 Putting her down (`putGothDown` 9863)

```js
n.carrier = -1;
if (p) { n.x = p.x + (n.face ? 20 : -20); n.y = p.y + 4; }   // set down behind him
n.x = clamp(n.x, NPC_AREA.x0, NPC_AREA.x1); n.y = clamp(n.y, NPC_AREA.y0, NPC_AREA.y1);
n.moving = false; n.wait = 2 + Math.random() * 2; n.fx = 0; n.fy = 1;
```

Placed 20 px behind him (he faces right -> she's at x-20), 4 px lower, then **snapped into NPC_AREA**
(so put down in the bedroom she jumps to the lounge area). Stands facing down 2-4 s, then wanders.
The E put-down only happens at the end of the 0.34 s 'drop' animation.

### 4.5 Labels and buttons

`lobbyLabel(w,p)` (10088) gives the E-action label; when carrying it is checked first:
```js
if (NPC_GOTH.carrier === p.id) return p.dive === DIVE.BOARD ? 'THROW!' : (p.dive ? null : 'PUT DOWN');
...
if (NPC_GOTH.carrier < 0 && canCarry(w, p)) return 'PICK UP';   // last in the list
```

- **Over her head** (top-down, 12250-12254), when `NPC_GOTH.carrier < 0 && canCarry(w, localPlayer())`:
  text `actKey() + ': pick up'` ("E: pick up" or "A: pick up" on a pad, `actKey` 8882 = 'A' if the pad was
  used more recently than keyboard/pointer). Font `bold 11px sans-serif`, centred; shadow `rgba(0,0,0,0.6)`
  at (+1,+1), text `#fff` at (p.x, p.y - T.radius*T.spriteScale*1.25) = 80.5 px above her ground point.
  Note: this shows even if a chair/bed would actually take the E.
- **On the board while carrying** (12274): tip `actKey() + ': throw her in!'`, `bold 11px ui-sans-serif`,
  colour `#8fd3ff`, shadow rgba(0,0,0,0.6) +1,+1, at y = max(12 + dz, round(p.y - r*spriteScale*1.25) - 4),
  drawn in a transform translated by -dz. (Not carrying, the board tip is 'walk off or roll to dive!'.)
- **Round on-screen button** (`carryButton` 10109 / `drawCarryButton` 10128, drawn every frame top-down at
  12443 — not only on touch): centre (ARENA.w-62, ARENA.h-ARENA.wall-70-48) = (798, 384), r 34; fill
  `rgba(20,12,28,0.72)`, stroke `#f7a8ff` width 2; label = lobbyLabel ('PICK UP' / 'PUT DOWN' / 'THROW!' /
  others), `bold 12px ui-sans-serif`, `#f7a8ff`, centred. Tap hit radius r+8 = 42 (8743); a tap runs the same
  as E (shroom/arcade/mirror first, then toggleCarry, or SITREQ for the guest).
- First person (sober, 4915): centre text `actKey() + ': ' + label.toLowerCase()` (e.g. "E: put down"),
  `bold 15px`, `#f7a8ff`, shadow rgba(0,0,0,0.65), at (430, 292), plus the same round button.

Controls: keyboard **E** (keydown, not repeat, 8655); gamepad **button 0 (A)** -> `padTap('e')` (8976;
also 8973 when seated); touch the round button. Guest: E increments `SITREQ.id`, sent as `inp.sq`; the host
calls `lobbyAction(w, guest)` when it changes (7179-7181).

### 4.6 How the carried pose is drawn (in `drawJared` for the carrier, 10636-10692)

Gothica is not drawn separately while carried; the carrier is drawn with a combined "Jared carrying
Gothica" frame. Art: `CARRY_FRAMES` (9741), three 160x185 PNGs, facing right, his head at x=72
(`CARRY_ANCHOR = 72/160`), his feet at row 168 (`CARRY_FLOOR = 168`).

| idx | file (extracted) | manifest path | what |
|---|---|---|---|
| 0 | `godot/scripts/lobby_life/art/gothica/carry_stand.png` | `godot/assets/misc/line9741_0.png` | standing (legs together; only a fallback) |
| 1 | `.../carry_stride.png` | `godot/assets/misc/line9741_1.png` | stride: used from the belt up for every walk/stand frame |
| 2 | `.../carry_squat.png` | `godot/assets/misc/line9741_2.png` | squat (scoop / set-down) |

(Extracted files are byte-identical to the manifest ones; 160x185 each. Script:
`<your scratchpad>/extract_gothica.py`.)

Load-time tweak `matchSkin` (9745): his skin pixels (`r>170 && 80<g<185 && 40<b<150 && r>g+30 && g>b+10`)
are multiplied r*1.04, g*1.2, b*1.18 (clamped 255) to match his run art. Bake this into the PNGs or a shader.

Frame choice (10639-10647):
```js
const walk = p.moving ? carryWalkFrame(Math.floor((p.odo || 0) / T.runStride) % 7) : carryStandFrame();
let cim = walk || CARRY_FRAMES[0], cfK = walk ? 1 : 0;
const an = NPC_GOTH.anim;
if (an && NPC_GOTH.carrier === p.id && CARRY_FRAMES[2]) {
  const squat = an.kind === 'pick' ? an.t < 0.2 : an.t >= 0.12;
  if (squat) { cfK = 2; cim = CARRY_FRAMES[2]; }
}
```
- Pick: squat for t in [0, 0.2), then standing until 0.34. Drop: standing for t < 0.12, squat from 0.12 to
  0.34, then she's put down.
- **Walk frames are composited** (`carryWalkFrame(k)` 9794): a 160x185 canvas = **legs** from
  `IMG.juicy.side_run[k]` (k = 0..6; Juicy's side run, 135x160, facing right; `godot/assets/CHARS/juicy/sprites/side_run_k.png`)
  shifted so his glasses centre lands at x=72 and his shorts' top row lands at y=106 (`WAIST`); then
  **the stride frame (CARRY_FRAMES[1]) on top**: all rows y < 106, plus for rows 106..145 only the dark
  runs (max channel < 80, length >= 5) to the right of the rightmost skin pixel (her boots), skipped if the
  row has no skin. Glasses = pixels in the top 40% with `b>150 && g>90 && r<120 && b>r+60` (mean x);
  shorts top = first row y>85 with >= 6 px of `110<r<200, b>r, b>130, |g-b|<30`. The same legs are used for
  both carriers (Jared old art too).
- **Standing** (`carryStandFrame` 9774) = `carryWalkFrame(K)` where K is the Juicy side_run frame with the
  narrowest opaque span in its bottom 24 rows (documented weakness: looks mid-stride).
- Porting suggestion: pre-build the 7 walk composites offline (or just use carry_stride for all).
- Hair/beard style (`hairFrame`, b276) and the shirt print (`shirtWorn`) are applied on top like his other
  frames (the shirt-print system is a separate spec).

Size and position (10660-10686):
```js
pscale = (CHAR_POSE_SCALE[p.ch]?.carry || 1) * T.carryScale * im.naturalHeight / 160;   // 185/160 = 1.15625
h  = T.radius * T.spriteScale * CHARS[p.ch].scale * pscale * (NEW_ART.has(p.ch) ? T.altScale : 1);
dw = h * (160/185) * (alt ? T.altWide : 1);
dx = p.x - dw * CARRY_ANCHOR;                       // his head on p.x
dy = p.y + r*0.9 - h * (CARRY_FLOOR / 185) - elev;   // his feet on the ground line, raised by dz
flip = NPC_GOTH.face  // mirror about p.x: ctx.translate(p.x*2,0); scale(-1,1)
```
- Juicy (new art): h = 64.4*1.15625*1.242 = **92.48**, dw = **79.98** (draw scale 0.4999 arena px per art px).
  Jared (old art): h = **74.46**, dw = **64.40** (draw scale 0.4025).
- Contact shadow under him as usual (ellipse at y + 0.85r, rx 0.95r*sf, ry 0.4r*sf, alpha 0.35*sf,
  sf = 1 - min(0.45, dz/22)). Team ring as usual (not on the tower).
- Facing: `face` is set at pick-up from `p.fx < 0`, then each frame from his walk input when
  `|p.ix| > 0.2` (`face = p.ix < 0`). Walking straight up/down keeps the last side. The art never turns to
  face up/down.
- Pixel-perfect: `imageSmoothingEnabled = false`.

### 4.7 Her jiggle while carried

```js
const amt = T.jiggle > 0 ? jiggleAmount({ id: 'npc_goth', npc: true, odo: p.odo }) * T.npcJiggle : 0;
im = jiggled(cim, 'carry' + cfK, T.jiggle > 0 ? Math.round(amt * T.jiggle) / T.jiggle : 0);
```
Uses the same spring as her walking (`JIG.npc_goth`), driven by **his** odometer, rounded to whole
pixels. Boxes (absolute rows, 9641-9643):
- `carry0` { x0 48, x1 79, y0 63, y1 88 } (standing; walk composites use `carry1`)
- `carry1` { x0 36, x1 58, y0 67, y1 87, ell {cx 46.5, cy 77, rx 10.5, ry 9.5} } (stride + walk frames)
- `carry2` { x0 49, x1 65, y0 100, y1 114, ell {cx 57, cy 107, rx 8, ry 7} } (squat)
See section 7 for the warp itself.

---

## 5. Thrown into the pool (or onto the floor)

### 5.1 Triggers

1. On the board (`p.dive === DIVE.BOARD`), carrying, press E:
   `throwGoth(w, (p.fx < 0 ? -1 : 1) * T.diveFwd * 1.25, 40, T.diveHop * 0.9)` -> vx = +-162.5, vy = 40, vz = 216.
   Facing left (back toward the ladder) she's thrown left and lands on the floor.
2. Walking off the tip with her (carrier enters DIVE.FALL; carrier's FALL sets vx 130, vy 40, vz 240):
   `throwGoth(w, p.vx * 1.15, p.vy, p.vz * 1.05)` -> about vx 149.5, vy 40, vz 252 (checked in lobbyGoth after
   the step, so vz may already have had one gravity tick). The carrier then dives too.
   (Rolling off the board is impossible while carrying: roll input is blocked.)
Start position = her current x, y, dz (= carrier's, e.g. boardH 100.6 on the board).

### 5.2 `throwGoth` (10326)

```js
n.carrier = -1; n.thrown = 'air'; n.vx = vx; n.vy = vy; n.vz = vz; n.spin = 0;
n.moving = false; n.fx = 0; n.fy = 1; n.dive = 0;
w.floaters.push({ x: n.x, y: n.y - (n.dz || 0) - 40, text: 'WHEEE!', t: 0, col: '#f7a8ff' });
if (SND.ctx) sTone(0.14, 260, 720, 0.16, 'triangle');      // boing: 0.14 s triangle sweep 260->720 Hz, vol 0.16
```

### 5.3 State machine `stepThrownGoth` (10333), dt = her real-time dt (max 0.1)

**'air'**:
```js
n.vz -= 1200 * dt; n.dz += n.vz * dt;
n.x += n.vx * dt; n.y += n.vy * dt; n.spin += 9 * dt;
if (n.dz > 0) return;
n.dz = 0; n.vz = 0;
if (inWater(n.x, n.y)) -> 'swim' else -> 'floor'
```
Gravity 1200 px/s^2, no drag, no wall collision while flying (she can fly through anything).
`inWater`: x in (630, 809), y in (96, 233) (POOL inset 6).
Worked example, E-throw from the tip (682.75, 188, dz 100.6): lands after ~0.63 s at ~(785, 213), in the
water; from the board start (622.75) -> ~(725, 213); from the ladder top facing right -> ~(702, 213).

Splash landing -> **'swim'**:
```js
n.thrown = 'swim'; n.dive = DIVE.SWIM; n.wait = 3.5; n.vx *= 0.2; n.vy = 0; n.odo = 0; n.rip = 0.4;
splash(w, n.x, n.y);   // fx(FX.DIVE), screen shake max(shake, 8), floater 'SPLASH!' #8fd3ff at y-50,
                       // sNoise(0.55, 1500, 0.7, 0.45, 'lowpass', 250) + sTone(0.2, 170, 60, 0.2, 'sine')
for (let i = 0; i < 3; i++) RIPPLES.push({ x: n.x, y: n.y, t: -i * 0.18, life: 1.3, grow: 70, w: 2.5 });
```
Dry landing -> **'floor'**:
```js
n.thrown = 'floor'; n.wait = 1.8; n.vx = 0; n.vy = 0;
fx(w, FX.WALL, n.x, n.y);
w.floaters.push({ x: n.x, y: n.y - 40, text: 'OOF', t: 0, col: '#ffd0d0' });
```

**'swim'** (paddling, 3.5 s):
```js
n.x += n.vx * dt; n.vx *= 1 - Math.min(1, 3 * dt);   // drift sideways, damped
n.wait -= dt; n.odo += 20 * dt;
n.rip -= dt;
if (n.rip <= 0) { RIPPLES.push({ x: n.x, y: n.y, t: 0, life: 1.6, grow: 26, w: 1.5 }); n.rip = 0.9; }
n.x = clamp(n.x, POOL.x0 + 14, POOL.x1 - 14);   // 638..801
n.y = clamp(n.y, POOL.y0 + 10, POOL.y1 - 8);    // 100..231
if (n.wait <= 0) { n.thrown = null; n.dive = 0; n.y = POOL.y1 + 18; n.wait = 1.2; n.fx = 0; n.fy = 1; }
```
She climbs out over the **bottom (near) edge**: y snaps to 257, x unchanged, stands facing down 1.2 s, then
wanders back (her next spot is inside NPC_AREA; x may be > 590 at first, she just walks there).
While swimming she shoves the ducks like a swimming player (`stepDucks` 5850: within 20 px, push
90 px/s^2 outward plus 0.8*her velocity, duck wobble 0.6).
After climbing out she **drips** like a player (`drawDrips` 6155, key 'goth'): wet for `DRIP_TIME` 3 s,
5 wet spots on the tiles, drops and trickles from `DRIP_POINTS` at h = T.radius*T.spriteScale.

**'floor'** (flat out, 1.8 s):
```js
n.wait -= dt;
if (n.wait <= 0) { n.thrown = null; n.wait = 1;
  n.x = clamp(n.x, NPC_AREA.x0, NPC_AREA.x1); n.y = clamp(n.y, NPC_AREA.y0, NPC_AREA.y1); }
```
Gets up (snapped into NPC_AREA), stands 1 s, then wanders.

While `thrown` is set: can't be picked up (`canCarry`), blackjack says "Gothica's busy!", she isn't pushed
out of the table. **She never says anything (no speech bubble) during a throw** — only the floaters
WHEEE! / SPLASH! / OOF.

Floaters (all of them, 8199-8203 and 12626): rise 34 px/s, removed at t > 0.9 s, alpha 1 until 0.6 s then
linear to 0 at 0.9 s; `bold 13px ui-monospace, monospace`, centred, shadow rgba(0,0,0,0.6) +1,+1, colour `col`.

### 5.4 Drawing thrown (`drawThrownGoth` 10370) — 'air' and 'floor'

Art: Gothica's `front_run[0]` (`godot/assets/CHARS/goth/sprites/front_run_0.png`, 60x160).
```js
h  = T.radius * T.spriteScale * CHARS.goth.scale * T.altScale;   // 79.98
dw = h * (60/160) * T.altWide;                                    // 29.99
sf = 1 - Math.min(0.45, dz / 22);
shadow: ellipse(n.x, n.y + r*0.85, r*0.95*sf, r*0.4*sf), fill rgba(0,0,0, 0.35*sf)
flat = thrown === 'floor';
translate(n.x, flat ? n.y + r*0.9 - dw/2 : n.y + r*0.9 - h/2 - dz);
rotate(flat ? PI/2 : n.spin);          // air: cartwheels at 9 rad/s; floor: lies on her side (clockwise 90)
drawImage(im, -dw/2, -h/2, dw, h)      // no smoothing
```
**'swim'** is drawn by the normal character drawer (`drawJared`, since `n.dive = SWIM`): her standing
front pose (fx 0, fy 1, not moving) sunk: `dy += h*0.48 + wob*1.5`, `wob = sin(now_ms/260 + 6)` (Gothica's
id is a string so the id term is 3*2), clipped to `rect(x - 1.5dw, dy - 20, 3dw, y - (dy-20))` (cut at the
waterline = her ground y). Then ripples: ellipse(x, y, dw*0.42 + wob, 5) stroke `rgba(225,246,255,0.8)` lw 2,
and ellipse(x, y+1, rw + 6 - wob, 8) at alpha 0.6 in `P_COLOURS[p.id]` — undefined for 'npc_goth', so canvas
keeps the previous stroke (the white). No shadow while swimming. Pool RIPPLES drawn by the pool: ellipse
rx = 5 + grow*k, ry = 0.45 rx, stroke `#e6f7ff`, lw `w`, alpha 0.55*(1-k), k = t/life (skip while t<0).

---

## 6. Speech bubbles

### 6.1 Every line she says in the lobby

| text | when | dur |
|---|---|---|
| "Wow, you're really strong!" | watching a lift, reps >= 5, at the watch spot, once per watch | 3.5 s |
| "Cards? Sure, I'll deal." / "Ooh, blackjack? Coming!" | called to the table (50/50) | 2.6 s |
| "Cards, boys." / "Cards up, big guy." | a hand is dealt (2 seats / 1 seat) | 2.6 s |
| "Blackjack?! Lucky." / "Ugh, I bust." / "Blackjack. House wins~" / "Fine, you win." / "House wins~" / "Some you win..." | hand settles (rules in 3) | 2.6 s |

Non-bubble text tied to her: floaters "WHEEE!" (#f7a8ff), "SPLASH!" (#8fd3ff), "OOF" (#ffd0d0),
"Gothica's busy!" (#f7a8ff, over the player), labels "E: pick up", "E: throw her in!", button
"PICK UP"/"PUT DOWN"/"THROW!". (Protect-mode lines in `PROT_SAY` are out of scope.)

A new line replaces the current bubble immediately (`n.bubble = {...}`, t = 0). Bubbles keep ticking while
she's carried but aren't drawn (she's not in the draw list).

### 6.2 Top-down bubble (`drawSpeech` 1134), drawn after all characters/props (12402)

```js
const fade = Math.min(1, (b.dur - b.t) / 0.4, b.t / 0.12);      // 0.12 s fade in, 0.4 s fade out
ctx.globalAlpha = Math.max(0, fade);
ctx.font = 'bold 11px ui-sans-serif, system-ui, sans-serif';
const tw = ctx.measureText(b.text).width, pw = tw + 14, ph = 20;
const want = away > 0 ? n.x - 14 : away < 0 ? n.x - pw + 14 : n.x - pw / 2;
const bx = Math.round(Math.min(ARENA.w - ARENA.wall - pw - 2, Math.max(ARENA.wall + 2, want))), by = Math.round(n.y - 92);
fill '#fffdf6', stroke '#1c1a22', lineWidth 2, roundRect(bx, by, pw, ph, 6) fill+stroke
const tx = Math.max(bx + 8, Math.min(bx + pw - 8, n.x));   // tail x, pointing at her
tail fill: (tx-5, by+ph-1) -> (tx+1, by+ph+7) -> (tx+5, by+ph-1), closed
tail stroke: (tx-5, by+ph) -> (tx+1, by+ph+7) -> (tx+5, by+ph)   (two sides only, so the join is open)
text '#1c1a22', centre/middle at (bx + pw/2, by + ph/2 + 1)
```
- Box top 92 px above her ground point (bottom at y-72, tail tip at y-65). Doesn't add dz.
- `away`: +1 box extends to her right (left edge 14 px left of her), -1 extends to her left, 0 centred.
  Only non-zero while watching a lift (2). Clamped inside the walls (18..842).

### 6.3 First-person bubble (`shroomWords` 4080)

Anchored at world (n.x, n.y, z = 92 + dz), projected; hidden if behind a wall (z-buffer test, +2 slack).
Only when `n.carrier < 0`. Same fade formula.
```js
font 'bold 14px ui-sans-serif, system-ui, sans-serif';
tw = measure + 16; x0 = q.x - tw/2; y0 = q.y - 26;
fill 'rgba(255,255,255,0.95)', roundRect(x0, y0, tw, 24, 8)  (no outline)
tail: (q.x-5, y0+24) -> (q.x, y0+31) -> (q.x+5, y0+24) same fill
text '#2a1f3e', textAlign center, baseline alphabetic at (q.x, y0+17)
```
Floaters in first person: `bold 16px ui-monospace`, anchored at (f.x, f.y+40, z = 40 + 30 t).

---

## 7. Jiggle (`npcJiggle`)

Applied whenever the character drawn has `p.ch === 'goth'`, skin 'goth', `T.jiggle > 0`, and the pose key
has a `JIGGLE_BOX` (10633):
```js
const amt = jiggleAmount(p) * (p.npc ? T.npcJiggle : 1);   // NPC: x2.2; a player playing Gothica: x1
if (JIGGLE_BOX[key]) im = jiggled(im, key, amt);
```
NPC spring (`jiggleAmount` 9646, keyed by id 'npc_goth', dt capped 0.05):
```js
const step = Math.floor(odo / (T.runStride * 3.5));   // a footfall every 45.5 px walked
if (s.step !== undefined && step !== s.step) s.v += 20;
s.v += (-300 * s.y - 3.2 * s.v) * dt;  s.y += s.v * dt;   return s.y;
```
(Players use a different spring: target sin(odo/(runStride*7)*4pi) when moving, k 700, c 14.)
Pick-up kicks `v += 30`. The same spring object continues while carried (driven by his odo) and after.

Warp (`jiggled` 9705): `level = clamp(round(amt * T.jiggle * 2)/2, -4, 4)` (half-pixel steps; carried uses
whole pixels). Inside the box rows y0..y1 (relative to the art's first opaque row, or absolute for carry*),
each pixel samples from `sy = round(y - level * bell * taper)`, `bell = sin(pi*(y-y0)/(y1-y0))`,
`taper = cos((x - xm)/xr * pi/2)`; only where both destination and source are in the bust mask
(`bustMask`: dark pixels (max channel < 90), plus pale pixels (r>190,g>150,b>120) with dark within 14 px on
both left and right in the row; for carry1/carry2 only inside the ellipse). Positive level = bust drops.
Walking boxes (relative to head top): front_run {17..42, 43..61}, diag_run {16..41, 44..62},
side_run {30..50, 44..63}. (back/bdiag frames: no jiggle.)
Godot: a shader with the same displacement over a mask texture, or prebaked frames for levels -4..4 step 0.5.

---

## 8. Other things she does / doesn't do

- Bed, mirror, bong/vape/smoke, shroom trip, rope potato rain, thrown potatoes, trampoline, barbecue:
  **no interaction or reaction** from her (no NPC_GOTH references in that code). The mirror reflects only
  players (a reflected Gothica *player* gets `npc:true`, so it jiggles with npcJiggle).
- She has no collision with players (players don't push her; her stuck backstop handles blocking).
- Depth: in the top-down draw she's inserted into the depth-sorted cast by y with the players and props
  (12221-12236); no team ring, no HP bar.
- Ducks: shoved while she swims (5.3). Drips after the pool (5.3).

## 9. Playing as Gothica

Choosing Gothica ("Gothica (test)", `ch 'goth'`) does **not** hide the NPC: both exist at once (nothing in
`lobbyGoth` or `T.npcGoth` checks the players' characters). The player-Gothica can't carry (not in
CARRIERS), jiggles at factor 1, uses the inverted down-diagonal flip (`altDiagFlip !== (ch==='goth')`, 9607),
and holds victory frame 1 (10594).

## 10. First-person (and the trip) differences

- First person/trip view (SHROOM) uses `lobbyGoth(w)` too (4329); if not thrown she's a cut-out drawn by
  `shroomCharacter` (drawJared into a 150x180 box, feet at (75,150), turned to the viewer, re-rendered at most
  every 100 ms, cache key 'npc').
- Thrown, as billboard sprites (`shroomExtras` 4127-4140), art front_run[0], h = 79.98, dw = 29.99:
  air: W dw, H h, foot dz + h (no cartwheel); floor: front_run[0] rotated 90 deg into a canvas, W h, H dw*0.6,
  foot dw*0.6; swim: top 38% of the image, W dw, H h*0.38, foot h*0.38.
- Carried: she's part of the carrier's cut-out. When you yourself carry her in first person nothing extra is
  drawn (no arms/her in view); the E hint is the centre text "E: put down" etc (4.5).
- While tripping (not sober), E does nothing else, so you can't pick up / put down; the carry button and
  centre hint are only drawn when sober.
- Bubble and floaters as in 6.3.

## 11. Multiplayer (host-authoritative)

The host runs her; the snapshot carries `ng: !w.started && T.npcGoth ? gothPack() : null` (8307).
`gothPack` (10229) = `[x, y, fx*100, fy*100, moving, odo, carrier, thrownIdx(null/air/floor/swim),
dz, face, anim? [kind, t*100, dur*100] : 0, bubble? [text, t*100, dur*100] : 0, spin*10, dive, ix*100, iy*100]`
(rounded ints). The guest copies it (`gothFromHost` 10237, text sliced to 80 chars) and draws; returns null
while carried. Guest's E goes up as `inp.sq` (SITREQ counter).

## 12. Asset list

| asset | path | px | draw |
|---|---|---|---|
| Carry stand | `godot/scripts/lobby_life/art/gothica/carry_stand.png` (= `godot/assets/misc/line9741_0.png`) | 160x185 | h 92.48 (Juicy) / 74.46 (Jared), anchored head x 72, feet row 168 |
| Carry stride | `.../carry_stride.png` (= `line9741_1.png`) | 160x185 | same; upper body of all walk/stand frames |
| Carry squat | `.../carry_squat.png` (= `line9741_2.png`) | 160x185 | same; pick/drop |
| Carrier legs | `godot/assets/CHARS/juicy/sprites/side_run_0..6.png` | 135x160 | composited under stride (4.6) |
| Gothica thrown/flat/swim-FP | `godot/assets/CHARS/goth/sprites/front_run_0.png` | 60x160 | 29.99 x 79.98 |
| Gothica walking/standing/swimming | `godot/assets/CHARS/goth/sprites/*` (manifest `CHARS.goth`) | 60-66 x 160 | h 79.98 (new art) |

No other embedded images are used by these features (bubbles, buttons, ripples and shadows are drawn with
canvas primitives).
