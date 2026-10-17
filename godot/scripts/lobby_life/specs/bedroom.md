# Bedroom features spec: mirror, hair styles, shirt print, wardrobe, bed

Source: `/home/user/Smashed-tv/Smashed.html` (line numbers `@NNNN`). World units: x across, y down (ground plane), z/dz height.
The canvas's virtual screen is ARENA 860x520 (`ARENA.wall` = 18). Lobby height `LOBBY_H` = 880. The bedroom floor sits under the lounge.
`T.radius` = 14, `T.spriteScale` = 4.6, `T.altScale` = 1.242, `T.altWide` = 1. `NEW_ART` = {juicy, tyson2, goth, inky} (@619).
A NEW_ART character is drawn h = 14 * 4.6 * 1.242 ≈ **80 units tall**, so its 160 px run art is drawn at **0.5 units per pixel**.
Feet: `dy = p.y + r*0.9 - h`, `dx = p.x - dw/2` (drawJared @10673-10691).

Extracted art lives in `/home/user/Smashed-tv/godot/scripts/lobby_life/art/bedroom/` (made by the scratchpad script
`<your scratchpad>/extract_bedroom.py`). See §7.

---------------------------------------------------------------------------------------------------
## 0. Layout constants (@1971-1976, @1947, @2161)

| name | value | notes |
|---|---|---|
| `BEDROOM` | x0 18, y0 520, x1 458, y1 862 | the floor rect (440 x 342). `bedroom.png` is drawn stretched into it (it is exactly 440x342, so 1 px = 1 unit) |
| `BED_DOOR` | x 110, w 64 | the gap in the lounge's bottom wall (y 502..520) |
| `BED` | x0 314, x1 446, y0 520, y1 676 | headboard against the top wall |
| `NIGHTSTAND` | x0 282, x1 308, y0 520, y1 556 | |
| `WARD` | x 180, y 620 (feet), s 1, open false, k 0, t 0 | |
| `MIRROR` | x 246, y 616 (feet), w 60, h 92 | |

Solid boxes (players pushed out with radius `T.radius*0.5` = 7, @5783; also used for Gothica's paths and spud plants):
- `wardBox()` @1948: x 148..212, y 604..620
- `bedBoxes()` @2156: bed {x 314..446, y 520..664} (`BED.y1 - 12`), NIGHTSTAND, `mirrorBox()` {x 216..276, y 606..616}
All in `lobbySolidBoxes()` @3431 (only when `T.loungeFloor`).

Placeholder floor if the art is missing: `drawBedroomPlaceholder()` @2409 (planks, rug at 96,650 200x150, nightstand + lamp, bed). Not needed if
`bedroom_floor.png` is used. `drawLowerLobby` @2289 draws: dark fill, `BED_ART` stretched to BEDROOM, **drawSleepers(w)**, then the
left/right/bottom walls (`#2b3040`, 18 thick) and the door frame/mat.

Depth sort (top-down, @12225-12232): props in the lobby are inserted into the y-sorted character list at
`WARD.y - 6` = 614 (drawWardrobe) and `MIRROR.y - 6` = 610 (drawMirror): drawn just before the first character whose y >= that.

---------------------------------------------------------------------------------------------------
## 1. The E / action button and its labels

`lobbyLabel(w, p)` @10088 picks the single label shown on the round E button (`carryButton()` @10109: screen x 798, y 384, r 34,
fill `rgba(20,12,28,0.72)`, stroke `#f7a8ff` 2px, text bold 12px `#f7a8ff`). Priority order (first match wins):
1. Gothica carry / tramp / bbq / gym labels…
2. `p.sit` → BONG/HIT
3. **`p.bed` → `'GET UP'`**
4. rope `'PULL'`
5. **`wardNear(p)` → `WARD.open ? 'CLOSE' : 'OPEN'`**
6. arcade `'PLAY'`
7. **`mirrorNear(p)` → `mirrorLook ? 'BACK' : 'LOOK'`**
8. shroom `'EAT'`, chair `'SIT'`, tramp `'CLIMB ON'`
9. **`bedNear(w,p)` → `'LIE DOWN'`**
10. `'PICK UP'` (Gothica)
Null when `!p.alive || w.started || w.over || cal.on`.

In first person (sober) the same label is shown under the crosshair as `actKey() + ': ' + label.toLowerCase()` (e.g. `E: look`,
`A: lie down` when a pad was used last; `actKey()` @8882), bold 15px `#f7a8ff` with a 1px black shadow, at screen (430, 292) (`ARENA.h/2 + 32`).

What E actually does: key `e` (not repeat, lobby) @8655 (host) / @8656 (guest):
`if (!shroomTryEat() && !arcadeTryOpen() && !mirrorTryLook()) toggleCarry(world)` (host) or `SITREQ.id++` (guest → host runs
`lobbyAction(w, p)` for player 1 when its `inp.sq` counter changes, @7179-7181). The same chain runs for a tap on the E button (@8743)
and pad A (button 0 → `padTap('e')`, @8976). So the **mirror is handled locally on each screen before** `lobbyAction`; wardrobe and bed go
through `lobbyAction` @10140 (host-authoritative):
```js
if (!carrying && wardNear(p)) { toggleWard(); return; }       // @10151
...
if (p.bed) { getUp(p); return; }                               // @10153
if (!carrying) { const bs = bedNear(w, p); if (bs) { lieDown(p, bs); return; } }
```

---------------------------------------------------------------------------------------------------
## 2. The full-length MIRROR

### 2.1 State (@2161-2171) — all local to each screen, never networked
```js
const MIRROR = { x: 246, y: ARENA.h + 96 /*616*/, w: 60, h: 92 };
const MIRROR_ZOOM = 4.4;
let mirrorLook = false, mirrorK = 0, mirrorAt = null;   // mirrorAt: {x,y} where you stood when you looked
let mirrorTurn = -Math.PI / 2;                          // the way the reflection faces, radians, screen-local
let mirrorGoal = null;                                  // target angle while an arrow button turns you
```

### 2.2 Proximity
```js
function mirrorNear(p) { return !!p && p.alive && !p.dive && !p.sit && !p.lift && !p.leg && !p.bed && T.loungeFloor
  && Math.abs(p.x - MIRROR.x) < 24 && p.y > MIRROR.y && p.y < MIRROR.y + 40; }   // x 222..270, y 616..656
```

### 2.3 State machine
- **Enter** `mirrorTryLook()` @2173: needs view world `v` (host: `world`, guest: `net.view`) with `!v.started && !v.over && !cal.on`.
  If already looking → `mirrorLook = false`, return true (E toggles out). Else if `mirrorNear(localMe())`:
  `mirrorLook = true; mirrorAt = {x: me.x, y: me.y}; mirrorTurn = -PI/2; mirrorGoal = null`.
- **Each frame** `mirrorStep(w, me, dt)` @2182 (called from `camFollow`, dt capped 0.1):
  - while looking: `turn = (D||→ ? 1:0) - (A||← ? 1:0)`; touch move stick `|dx| > 0.25` → `turn = dx`; pad 0 `|axes[0]| > 0.3` → `turn = axes[0]`.
    `if (turn) { mirrorTurn += turn * 3.2 * dt; mirrorGoal = null; }` else if `mirrorGoal !== null` move toward it at **6 rad/s**, snapping when within a step.
  - auto exit: `w.started || w.over || !mirrorNear(me) || hypot(me - mirrorAt) > 3` → `mirrorLook = false`.
  - `mirrorK = clamp(mirrorK + (mirrorLook ? dt : -dt) * 3, 0, 1)` → **fade in/out over 1/3 s**.
- `mirrorSpin(d)` @2209 (arrow buttons): `mirrorGoal = (mirrorGoal ?? mirrorTurn) + d * PI/4` (an eighth of a turn per tap, taps accumulate).
- `mirrorMe(p)` @2197: `mirrorK > 0 && !p.npc && p.id === (guest ? 1 : 0)` — the local player, while fading.

### 2.4 Movement lock & exits (input, @9029-9032)
While `mirrorLook`: `if (inp.my > 0.6) mirrorLook = false; else { inp.mx = inp.my = 0; inp.shoot = inp.roll = false; }`
So: S / ↓ / stick down steps away; A/D/←/→ only turn; W does nothing. E (toggle), the E button (label `BACK`), pad **B** (button 1,
@8971: `if (mirrorLook) { if (hit(1)) { PAD.holdB = true; mirrorLook = false; } return; }` — all other pad buttons ignored while looking,
so a pad has no hair control; the left stick turns and stick-down leaves). Starting a game also exits.

### 2.5 Camera (camFollow @8521-8534)
`want = MIRROR_ZOOM (4.4)` while `mirrorLook`; `CAM.z += (want - CAM.z) * min(1, dt*5)` (rate 5 while looking/seated, else 10); snaps when
< 0.003. Target `tx = MIRROR.x (246)`, `ty = MIRROR.y - 38 (578)`; `CAM.x/y += (t - CAM) * min(1, dt*8)`. The view is clamped inside the world.
On leaving, the zoom eases back to the player's normal zoom.

### 2.6 First person
`fpBusy()` @3587 is true while `mirrorLook` (also `SHED.open`, `me.bed`, …): first person steps aside to top-down for the duration and
re-locks the mouse when done. In FP the mirror is a static billboard: `shroomCapture` @4055 draws `drawMirror(quiet)` with **no players**
(empty glass) into an offscreen and uses its bounding box as a sprite (x centre, y = bottom - 4). Same for the wardrobe (re-captured when
`WARD.open` changes, sig @4323).

### 2.7 Drawing `drawMirror(w)` @2247 (world coords, under the camera)
```
x0 = 216, top = 524; glass g = {x0: 220, x1: 268, y0: 529, y1: 609}  (48 x 80)
shadow: ellipse(246, 615, rx 34, ry 4) rgba(0,0,0,0.25)
frame:  rect(216, 524, 60, 89) #6b4526; highlight rect(217, 525, 58, 2) #8a5a34
feet:   rect(219, 612, 4, 4) and rect(265, 612, 4, 4) #4a2e1c
glass:  vertical linear gradient y 529→609, #9fb4c4 → #6d8193; then clip to the glass rect
```
**Reflection technique** (no render-to-texture; characters are simply re-drawn, scaled, inside the clip):
```js
const seen = w.players.filter(p => p.alive && !p.dive && !p.sit && !p.lift && !p.leg && !p.bed
  && p.y > m.y && p.y < m.y + 170 && Math.abs(p.x - m.x) < 70).sort((a, b) => b.y - a.y);   // farthest first
seen.sort((a, b) => mirrorMe(a) - mirrorMe(b));                                              // you last (on top)
for (const p of seen) {
  const d = p.y - m.y;
  let s = 0.72 - 0.3 * Math.min(1, d / 170), rx = m.x + (p.x - m.x) * 0.35, ry = g.y1 + 2;   // 0.72 at the glass .. 0.42 at 170 away
  if (mirrorMe(p)) {                                   // grow to fill the glass, feet on its bottom edge
    const k = mirrorK * mirrorK * (3 - 2 * mirrorK);   // smoothstep
    const sF = (g.y1 - g.y0) / (T.radius * T.spriteScale * charScale * (NEW_ART ? T.altScale : 1));   // 80/80 = 1.0 for Juicy
    const ryF = g.y1 - 1 - T.radius * 0.9 * sF;        // 595.4
    s += (sF - s) * k; rx += (m.x - rx) * k; ry += (ryF - ry) * k;
  }
  let r = { ...p, x: rx, y: ry, fy: -p.fy, iy: -(p.iy||0), ady: -(p.ady||0), mdy: -(p.mdy||0), rdy: -(p.rdy||0) };  // y-facing flipped
  if (mirrorMe(p) && mirrorLook) {
    const fx = Math.cos(mirrorTurn), fy = Math.sin(mirrorTurn);
    r = { ...r, id: 'mirror' + p.id, npc: true, moving: 0, firing: 0, fx, fy: -fy, ix: fx, iy: -fy };
  }
  ctx.globalAlpha = 0.9; translate(rx, ry); scale(s, s); translate(-rx, -ry); drawJared(w, r);
}
// sheen: polygon (g.x0, g.y0+30) (g.x0+14, g.y0) (g.x0+22, g.y0) (g.x0, g.y0+44), rgba(255,255,255,0.18)
```
Notes for the port:
- The reflection is the character drawn normally (same frame-picking `poseFor` / 8-way `sectorOf`), with its **y facing negated**, so someone
  facing the mirror (north, back view) shows their front, and left/right are kept (no horizontal flip). The scale is about the point (rx, ry),
  i.e. the sprite's foot-reference point is placed at the bottom of the glass.
- `npc: true` hides the team ring under the reflection; non-local reflections keep their ring (they are drawn with the real p.id).
- `mirrorTurn = -PI/2` → fx 0, fy -1 → reflection fy = +1 → **front view**. Turning right increases the angle. The reflection uses the
  sector key `'mirror'+id` (its own 8-way hysteresis: hold within 22.5°+10°). `moving: 0` → standing frame (run cycle frame chosen by `p.odo`).
- Hair styles and shirt prints show automatically because they are baked into the character's frames (§3, §4).
- The real you fades: in the main character pass @12261 `if (mirrorMe(p)) { if (mirrorK < 1) draw with alpha 1 - mirrorK; continue; }`.
- Everyone's screen draws everyone's reflection (so you see your friend in it); only the zoom/turn/fade is local.

### 2.8 Mirror HUD (screen space, after the camera is restored; @2198-2246, drawn by `drawMirrorHint` @12454 and `drawHairButton` @12455)
Shown only when `mirrorLook && mirrorK >= 0.8`.
- **Turn arrows** `mirrorArrows()`: two circles at (430 ∓ 168, 210) = (262, 210) d=-1 and (598, 210) d=+1, r 26. Fill `rgba(40,24,16,0.85)`,
  stroke `#f6d17a` 2px; arrowhead triangle `(x + d*11, y), (x - d*7, y - 12), (x - d*7, y + 12)` fill `#f6d17a`. Hit radius r + 8 → `mirrorSpin(d)`.
- **Hair arrows** `hairArrows()`: (312, 409) d=-1 and (548, 409) d=+1, r 18, same colours, triangle `(x + d*7, y), (x - d*5, y ± 8)`.
  Hit radius r + 8 → `setLocalBeard(LOCAL_BEARD + d)`. (Pointer handler order @8731-8732: hair arrows, then turn arrows.)
- **Hint** (alpha `min(1, (mirrorK - 0.8) * 5)`), centred at x 430:
  - `'HAIR  ' + (LOCAL_BEARD + 1) + ' of ' + BEARDS.length` — bold 10px `rgba(246,209,122,0.85)` at y 392 (no shadow)
  - style label (e.g. `THE CLASSIC`) — bold 18px `#f6d17a` at y 415, shadow `rgba(0,0,0,0.65)` at (+1, y 416)
  - tip — bold 13px white at y 438, shadow at (+1, 439):
    - touch (`touchSeen || 'ontouchstart' in window`): `big arrows (or drag) to turn round  ·  small arrows: hair  ·  BACK to step away`
    - else: `A / D or the big arrows: turn round  ·  F or the small arrows: hair  ·  S or E: step away`
- Keyboard **F** (not repeat) while looking: `setLocalBeard(LOCAL_BEARD + (shift ? -1 : 1))` @8629.

---------------------------------------------------------------------------------------------------
## 3. HAIR STYLES (Juicy Jared only)

### 3.1 Data (@1418-1450)
```js
const BEARDS = [
  { key: 'classic', label: 'THE CLASSIC' },              // 0 = his own art, untouched (no HAIR_ART entry)
  { key: 'braids',  label: 'BRAIDS' },
  { key: 'mullet',  label: 'MULLET' },
  { key: 'slick',   label: 'SLICKED BACK' },
  { key: 'tyson',   label: 'TYSON', face: true },        // haircut + beard, keeps his face & sunglasses
  { key: 'mohawk',  label: 'MOHAWK', face: true },
  { key: 'mohawk_blue',   label: 'MOHAWK  BLUE',   face: true },   // (two spaces in the label)
  { key: 'mohawk_purple', label: 'MOHAWK  PURPLE', face: true },
  { key: 'mohawk_green',  label: 'MOHAWK  GREEN',  face: true },
];
HAIR_ART[style][view] = [ax, ay, dataURI]   // view ∈ front, diag, side, back, bdiag; ax, ay: top-left of the art in RUN FRAME 0 pixels
const HAIR_HEAD = { front: [48.5, 9, 53, 19], diag: [53.5, 9, 53, 19], side: [60.5, 9, 51, 19.5], back: [47, 9, 46, 17], bdiag: [51, 9, 47, 18] };
                  // his head in <view>_run[0]: centre x, top y, bottom y, half width (pixels)
const HAIR_FIT = { "juicy.front_run.0": [1.0, 0.0, 0.0], ... }   // 131 entries: frame "<charId>.<key>.<index>" → [s, ox, oy]
```
All of these (+ anchors, sizes) are dumped to `art/bedroom/hair_data.json`. HAIR_FIT covers juicy, juicy_shotgun, juicy_launcher,
juicy_spud frames (run cycles, a/b, back, reload, pickup, throw). Meaning: the head in that frame = `(ox, oy) + s * (head in run frame 0)`,
in that frame's own pixels.

### 3.2 State, persistence, network
- `LOCAL_BEARD` (your index), `GUEST_BEARD` (host's copy of the guest's). Loaded from **localStorage `smashed-hair`** (int, clamped) @1449.
- `p.beard` on each player: set at creation `id 0 ? LOCAL_BEARD : id 1 ? GUEST_BEARD : 0` (@727); sent in the snapshot (array index 50, @8357/@8462).
- `setLocalBeard(i)` @1645: wraps modulo 9, saves `smashed-hair`, guest sends `{t:'beard', b}` (also sent on connect @10820), host sets
  `world.players[0].beard`. Host on `{t:'beard'}` sets `GUEST_BEARD` and `world.players[1].beard` (@10841). Sound: "snip" =
  `sNoise(0.08 s, 3200 Hz, Q 2, gain 0.12, bandpass, sweep → 1800)` + `sTone(0.05 s, 900→1300 Hz, 0.06, square)`.
- `CH_STYLE[ch]` = style currently baked into character `ch`'s frames. `ensureLooks(w)` @1637 (every frame): for each distinct `p.ch`
  (first player on a character wins if two share one), `want = clamp(p.beard|0)`; if it differs from `CH_STYLE[p.ch]`, set it and
  `applyShirtArt(p.ch)` (re-bakes every frame of that character with hair + any shirt print).

### 3.3 Which frames get hair
`hairView(key)` @1451 (key = the frame's IMG key):
- `'carry'` → `side`; non-string keys (gym/sit arrays: SIT_ART, SIT_IDLE, GYM_ART.press, LEG_ART.press, LEG_LAYER.jared) → none; `roll*` → none
- prefix `bdiag|diag|front|side|back` → that view (e.g. `front_run`, `diag_a`, `back`, `bdiag_b`)
- ends in `side` (`reload_side`, `throw_side`) → `side`; ends in `front`, or `reload`, `pickup` → `front`; else (e.g. `victory`) none.

`hairFit(im, key, ch)` @1484 — only if `ch.startsWith('juicy')`:
1. If `HAIR_FIT[im.__fit]` exists (`__fit = charId.key.index`, @9456): `[s, ox, oy]`; if `|s - 1| < 0.05` then `s = 1` and ox, oy rounded.
2. Else if the frame is a stored IMG frame (has `__fit`) or the view is back/bdiag → **no hair** (head too changed).
3. Else (frames built at draw time: the carry frames) → find the sunglasses with `hairAnchor` in this frame and in `<view>_run[0]`
   (`hairRef`), `s = 1, ox = A.x - ref.x, oy = A.y - ref.y, carry: key === 'carry', faceX: A.x`.

`hairAnchor(d, w, h)` @1461: first pixel in scan order within the top 60% that is "blue" (`a > 200 && b > 150 && r < 110 && b > g + 10`), then an
8-connected flood (neighbourhood ±2) over blue pixels → bbox `{x: minX, y: minY, w}`; null if < 4 pixels.

### 3.4 `hairPaint(g, W, H, S, F, style)` @1505 — the algorithm
Inputs: canvas `g` holding the frame at S× size (S = 1 for plain frames; 2 or 3 for printed frames, see §4), fit F `{view, s, ox, oy}`.
```
art   = HAIR_ART[key]; av = (F.view == 'bdiag' && !art.bdiag) ? 'back' : F.view; fb = av != F.view   (all styles have bdiag now, so fb is false)
L     = hair image for av, at = art[av]   ([ax, ay])
hairBox(F) (frame px): [hx - hw - 7 (+3 if bdiag), 0] .. [hx + hw + 7 (+3 if bdiag), oy + (HEAD.bottom + 18) * s]  each mapped as  ox + v*s
X0..X1, 0..y1 = that box * S        (the only region read/written)
if fb: ox += 3*s
dx = (ox + ax*s)*S, dy = (oy + ay*s)*S, dw = L.w*s*S, dh = L.h*s*S       ← where the new hair image goes
md = alpha of L drawn at (dx, dy, dw, dh) into an RW x y1 scratch (smoothing only if s < 0.8)
```
Pixel tests: `hairLike(o)`: `a > 200 && max(rgb) < 125 && r >= b - 4 && g < r + 25` (dark & warm); `skin(o)`: `a > 100 && r > 120 && r > g + 25`.
`ref` = `hairRef(view)` if the style has `face: true` and view is not back/bdiag, else null. `faceTop = ref ? (oy + (ref.y - 1)*s)*S : ∞`
(nothing at or below the top of the sunglasses is erased for face styles).

**Erase old hair** (when !fb): with `[hx, t0, t1, hw] = HAIR_HEAD[view]`, `hy = (t0+t1)/2`, for each pixel in
y ∈ [(oy + (t0-3)s)S, min(y1, (oy + (t1+1)s)S, faceTop)), x ∈ [(ox + (hx-hw-5)s)S, (ox + (hx+hw+5)s)S):
```
ry = ((y+.5)/S - oy)/s - hy;  rx = ((x+.5)/S - ox)/s - hx
grow = ry < 0 ? 2.5 : 1;  u = rx/(hw+grow);  v = ry/((t1-t0)/2 + grow)
skip pixels flagged as Gothica (carry only, below)
if (u²+v² <= 1 && (hairLike || (ry < 0 && a < 200) || (max(rgb) < 125 && g < r + 10)))   → alpha = 0, unless (ref && skin)
else if (!ref && v < (back/bdiag ? 0.85 : 0.3) && md.alpha == 0 && (skin || (a > 0 && max(rgb) < 125 && g < r + 10))
         && (rx/(hw+5))² + v² <= 1)                                                         → alpha = 0   (old head bits the new hair won't cover)
```
(if fb: instead clear only hairLike pixels under the new hair's alpha.)
Then draw L at (dx, dy, dw, dh), source-over, alpha 1, no filter, smoothing only when s < 0.8.
Finally, if `her` (carry) or `ref` (face style): restore from the pre-erase copy every pixel that is Gothica, and (face styles) every
**sunglasses** pixel (`a > 200 && b > 140 && b > r + 40`) so his own glasses are always on top of the new art.

Carry special case (`F.carry`, @1537-1550): Gothica's head is in front of his. Starting at `(faceX + 4, gl.y*s + oy - 3)` (up to 6 px up), flood
fill (4-connected) "his" pixels (`a >= 200` and orange skin `r > 110 && g < .75r && b < .62r`, or dark warm `max < 125 && r > b + 6 && r >= g`,
or blue `b > r + 40`); per row, his leftmost x; rows above his top copy the top row, rows below the last copy the last; every opaque pixel left
of that per row is "her" — kept out of the erase and copied back over the new hair.

`hairFrame(im, style, key, ch)` @1577 caches per image per style (WeakMap); style 0 or art not loaded → original image; no fit → original.
Result is a same-size canvas.

### 3.5 Godot port recipe
Precompute per (frame, style) at load or on change: for every Juicy frame with a HAIR_FIT entry (or the carry frames), run the erase +
stamp above on the frame's Image, using `hair_data.json`. Equivalent simpler approach if you trust the data: for each frame, erase the ellipse
region per rules, then blit `hair/<style>_<view>.png` at `(ox + ax*s, oy + ay*s)` scaled by s (nearest unless s < 0.8), then re-stamp
sunglasses for face styles. Characters other than juicy* never get hair (so the hair only changes Juicy Jared; selecting a style while
playing another character just changes the saved index).

### 3.6 Hair art files (all 1 px = 1 sprite px; drawn at the frame's scale, i.e. 0.5 world units/px in game)
In the repo's manifest: `HAIR_ART@1418` → `godot/assets/misc/line1418_N.png`; the other styles have their own folders.

| manifest file | style / view | at (ax, ay) | size |
|---|---|---|---|
| misc/line1418_0.png | braids front | 30, 11 | 37x42 |
| misc/line1418_1.png | braids diag | 36, 11 | 35x43 |
| misc/line1418_2.png | braids side | 46, 10 | 33x41 |
| misc/line1418_3.png | braids **back** | 30, 9 | 31x35 |
| misc/line1418_4.png | braids **bdiag** | 34, 9 | 35x42 |
| misc/line1418_5.png | mullet front | 30, 10 | 38x51 |
| misc/line1418_6.png | mullet diag | 37, 10 | 35x51 |
| misc/line1418_7.png | mullet side | 45, 10 | 36x51 |
| misc/line1418_8.png | mullet bdiag | 33, 10 | 36x43 |
| misc/line1418_9.png | mullet back | 31, 9 | 34x49 |
| misc/line1418_10.png | slick front | 30, 9 | 38x51 |
| misc/line1418_11.png | slick diag | 37, 10 | 35x50 |
| misc/line1418_12.png | slick side | 45, 9 | 34x45 |
| misc/line1418_13.png | slick bdiag | 33, 10 | 36x37 |
| misc/line1418_14.png | slick back | 30, 9 | 35x36 |
| HAIR_ART_tyson/{front,diag,side,bdiag,back}_2.png | tyson | 27,11 / 29,14 / 37,9 / 27,8 / 26,8 | 43x50 / 50x49 / 47x45 / 47x38 / 42x38 |
| HAIR_ART_mohawk*/{view}_2.png (mohawk, _blue, _purple, _green) | mohawk | 20,0 / 25,0 / 32,0 / 24,0 / 21,0 | 57x41 / 57x55 / 57x53 / 54x49 / 52x48 |

(Note the braids order is front, diag, side, back, bdiag; mullet/slick are front, diag, side, bdiag, back.) The same images, with clear names,
are in `art/bedroom/hair/<style>_<view>.png`.

---------------------------------------------------------------------------------------------------
## 4. SHIRT PICTURE printed on the singlet (SHIRT / SHED)

### 4.1 State (@1160-1167, @1765)
```js
const SHIRT = { art: null, artBack: null, place: null, placeBack: null, smooth: true, boxes: new Map(), originals: null, key: 'smashed-shirt-art' };
// place/placeBack: {x, y, w, h} in 0..1 of the shirt box (may exceed 0..1); smooth: LOOK: PHOTO (true) / LOOK: PIXEL (false)
const REMOTE_PRINT = { ch: null, art: null, artBack: null, place: null, placeBack: null, smooth: true };   // the friend's
let PRINT = SHIRT;                          // the one being printed right now
const SHED = { open: false, place: null, drag: null, pose: null, side: 'front' };   // the editor
```
`printFor(ch)`: your own character → SHIRT; the friend's character (`REMOTE_PRINT.ch`) → REMOTE_PRINT; else none. `backKey(k)` = key matches
`/^b(ack|diag)/` (uses back picture & placeBack). `shirtSide(k)` = key matches `/^(side|diag)/` or `'carry'` (strap handling).

### 4.2 localStorage (all under `smashed-shirt-art`)
| key | value |
|---|---|
| `smashed-shirt-art` | front picture, data URL (webp q0.92, png fallback), trimmed & ≤ 512 px on the long side |
| `smashed-shirt-art-back` | back picture, same |
| `smashed-shirt-art-place` | JSON `{x,y,w,h}` (saved on DONE) |
| `smashed-shirt-art-place-back` | JSON (saved on DONE if set) |
| `smashed-shirt-art-look` | `'photo'` or `'pixel'` (default photo; anything but `'pixel'` = photo) |
`clearShirtArt()` removes '', '-back', '-place', '-place-back' (not '-look'), nulls art/artBack/place/placeBack, closes the editor.

### 4.3 Getting a picture: the ART button (wardrobe open) and file picker
`artButton()` @1911: only on the host (`net.role !== 'client'`), lobby (`!started && !over && !cal.on && T.loungeFloor`), player 0 alive,
`WARD.open && wardNear(p)`. Screen pos **(718, 384) r 34** (80 left of the E button). Drawn @1917: circle fill `rgba(14,40,26,0.8)` stroke
`#6fd3a0` 2px; `ART` bold 13px `#6fd3a0` at y-6; sub-label 9px at y+9: `'tap: change'` if SHIRT.art else `'on shirt'`. If SHIRT.art, a small
× badge at (x + 0.72r, y - 0.72r) r 9 (fill `rgba(20,12,28,0.9)`, stroke `#e0473f`, `×` bold 12px `#e0473f`).
Pointer @8735-8737: tap within 12 of the badge → `clearShirtArt()`; within r + 6 of the button → `SHIRT.art ? openShirtEditor() : pickShirtArt()`.
No keyboard/pad binding. Not drawn in first person.

`pickShirtArt()` @1757: creates `<input type=file accept="image/*">` and clicks it. `loadShirtArt(file)` @1729: read as data URL → draw →
**trim** edges whose pixels are `a < 30` or all of r,g,b > 244 (white); scale by `k = min(1, 512 / max(tw, th))`; encode webp 0.92 (png fallback);
then: if the editor is open on the back side it becomes `SHIRT.artBack`, else `SHIRT.art`; if the editor was closed open it on the front;
`SHED.place = shirtFitPlace(back ? 'fill' : 'fit')`; `shedSaveSide()`; `applyShirtArt()`; save the data URL to localStorage.
(Godot: use a FileDialog / platform file picker; on web, JavaScriptBridge.)

### 4.4 Finding the shirt in a frame: `shirtLogoBox(im)` @1207 (cached per image)
Returns `{box: [x, y, w, h], mask: canvas (whole shirt incl. filled holes), shade: canvas (just the green)}` or null.
1. `isShirt(o)`: `a > 200` and one of: `(g > 1.2r && g > 1.2b && g > 80)`, `(r < 60 && g >= 70 && b <= 1.2g)`, `(r < 30 && g >= 45 && g > 2r && b <= 1.4g)`.
2. Pale lettering joins: a non-green opaque pixel with `max-min <= 75` and luminance `0.3r+0.59g+0.11b >= 105`, not "glass"
   (`b > g + 8 && r >= 170 && b >= 225`), counts if green is found within 9 px both left & right, or both above & below.
3. If ≥ 60 green px: 4-connected components of the marked pixels, sorted by size; keep parts with `≥ max(30, 0.12 * biggest)` pixels that
   are not mostly bluish (`b > g` in > 50%). Union → `best` (box = union bbox). Requires ≥ 60 px.
4. Fill holes: flood "outside" from each part's bbox border through non-shirt pixels (within that bbox). Inside the union box: non-shirt,
   non-outside pixels that are skin (`r > 110 && r > 1.15g && r > 1.3b`) or glass → outside. Remaining holes grouped by light/dark
   (`light = lum >= 105 || b > r + 40`), 4-connected; a hole becomes outside if bordered by more skin than half the shirt contacts
   (`bySkin > byShirt*0.5`) or it is dark and > 40 px.
5. mask = shirt pixels + (in box and not outside) → white opaque; shade = green pixels only.

`patchShade(im, L)` @1316: for pixels under `L.shade` (or mask), `v = clamp(round(255 * lum / avgLum), 60, 255)` grey, opaque; else transparent.
Used as a multiply layer so the fabric folds darken the print.

`shirtStrap(L, w, h)` @1350: from mask row widths, `top` = first row with pixels; extend down while the row width keeps growing (non-decreasing);
if that band is 3..14 rows → `{y0: top, y1}` (the strap over the shoulder), else null.

### 4.5 Printing a frame: `shirtSkin(im, isBack, mirror, hi, sideish)` @1371
```
L = shirtLogoBox(im); [bx, by, bw, bh] = L.box
a = (isBack && PRINT.artBack) || PRINT.art;  if (mirror) a = horizontally flipped copy   // a flipped frame still reads correctly
pl = isBack ? (PRINT.placeBack || fillPlace(a, bw, bh)) : PRINT.place  || {x:0,y:0,w:1,h:1}
S  = PRINT.smooth ? (hi ? 3 : 2) : 1          // hi: SIT_ART, SIT_IDLE, GYM_ART.press, LEG_ART.press, LEG_LAYER.jared (camera zooms on them)
patch (w*S x h*S), smoothing = PRINT.smooth (high quality):
  draw a at ((bx + plx*bw)*S, (by + pl.y*bh)*S, max(1, pl.w*bw)*S, max(1, pl.h*bh)*S), plx = mirror ? 1 - pl.x - pl.w : pl.x
  destination-in: L.mask scaled ×S (nearest)          // only on the shirt
  destination-in: im scaled ×S (nearest)              // never in transparent gaps
  if (sideish && strap): source-atop fill rows strap.y0..strap.y1 (×S, full width) with shirtTone(a) = average colour of a (8x8 downsample)
out (w*S x h*S): im scaled ×S nearest; then patch on top;
  then multiply patchShade(im, L) with alpha = isBack ? (smooth ? 0.3 : 0.5) : 0.75;
  in PHOTO mode the shade layer is smoothed and blurred by 0.7*S px.
out.__ss = S
```
`fillPlace(a, bw, bh)` = cover the box, centred. Output is S× larger than the sprite but drawn at the same on-screen size (dw x h), so in
PHOTO mode the picture has 2–3× the sprite's resolution.

`shirtPrinted(im, isBack, hi, sideish)` @1687 makes both the normal and mirrored versions (`c.__mir`); drawJared uses `__mir` when the pose is
flipped (@10710) so the picture is never mirrored on screen.

### 4.6 Applying it to every frame: `applyShirtArt(only?)` @1652
Collects every character on screen (`world.players`, `net.view.players`), plus any in CH_STYLE (default `juicy`). First run captures
originals: Jared's gym/sit art arrays (SIT_ART, SIT_IDLE, GYM_ART.press, LEG_ART.press, LEG_LAYER.jared, as 'juicy') and every IMG set whose
id equals the character or starts with `ch + '_'` (e.g. juicy_shotgun, juicy_spud). Then for each `[holder, key, orig, ch]`:
`style = CH_STYLE[ch]`, `pr = printFor(ch)`; no print → `hairFrame(im, style, key, ch)`; print → `printedWithHair(...)` (print cached per frame by
a key of picture ids/places/smooth/back/hi/sideish; on a hair change only the head region is restored from a saved copy (`keepHead`, filled
in a background loop ≤ 6 ms per tick) and `hairPaint` reapplied at S). The holder's frame is **replaced in place**, so all drawing code
(reflection, bed, FP) automatically uses printed/haired frames. Retries every 400 ms while images still load.
Frames built at draw time (carry frames, jab-run stitches) are printed in `shirtWorn` @1705 (LRU of 40, current facing only).
Prints apply to whichever character you are, but only find a shirt on art with Jared's green singlet (otherwise `shirtLogoBox` → null, no print).

Network (@1186-1200, every 1000 ms when connected): if your (char, picture ids, places, smooth) signature changed, send
`{t:'shirt', ch: myChar, a: printData(SHIRT.art), b: printData(SHIRT.artBack), p, pb, s}` (`printData`: ≤ 256 px, webp 0.85 / png).
Receiver `onPrintData` @1177 validates data URLs (webp/png/jpeg, < 600000 chars) and place objects, stores in REMOTE_PRINT, `applyShirtArt()`.
Disconnect clears REMOTE_PRINT.

### 4.7 The shirt editor (SHED) — `shirtEditorGeo()` @1801, `drawShirtEditor()` @1829 (screen space, drawn over the HUD)
Opens via `openShirtEditor()` (needs art; side = front; `shedLoadSide()`: copy SHIRT.place / placeBack, or default `fit` (front) / `fill` (back)).
Geometry (ARENA 860x520): panel `pw 430, ph 330` at `(215, 95)`; full-screen dim `rgba(8,10,14,0.78)`; panel fill `rgba(20,12,28,0.96)`,
stroke `#f7a8ff` 2px, radius 10.
- Title (bold 14px `#f7a8ff`) at (231, 117): `FRONT OF HIS SHIRT` / `BACK OF HIS SHIRT`.
- Footer (11px `#8b93a4`) at (231, 407): `drag to move · drag a corner to stretch · it only goes on the shirt`.
- View square `{x 231, y 135, w 250, h 250}`, fill `#11141b`. Pose image = Juicy's (`IMG.juicy || IMG.jared`) `front_run[0]` (or `back_run[0]`
  on the back side), its unprinted original. Source square around the shirt box: `pad = round(max(bw,bh) * 0.28)`, `s = max(bw,bh) + 2*pad`,
  centred on the box; drawn nearest-neighbour into the view; `k = 250 / s`; on-screen box = view + (box - src) * k.
- Preview: picture at `shirtArtRect` drawn into an S×(S=2 photo / 1 pixel) canvas of the source square, `destination-in` the mask, blown up
  over the view. Then dashed outline of the picture rect `rgba(246,209,122,0.55)` [3,3], dashed shirt box `rgba(111,211,160,0.35)` [4,3].
- Corner handles: 16x16 `#1c1a22` with 12x12 `#f6d17a` inside, at each corner of the picture rect.
- Buttons (w 128, h 26, x = 215 + 430 - 128 - 16 = 501, radius 6, stroke `#f7a8ff` 1.5, text bold 12px white):
  | y | action | label |
  |---|---|---|
  | 139 | file | `PICK PICTURE` |
  | 171 | fit | `FIT` |
  | 203 | fill | `FILL` |
  | 235 | turn | `TURN AROUND` (front) / `SHOW FRONT` (back) |
  | 267 | smooth | `LOOK: PHOTO` / `LOOK: PIXEL` |
  | 349 | done | `DONE` (fill `#1f5a36`) |
  | 383 | cancel | `CANCEL` (fill `#5a1f28`) |
  other buttons fill `#3a2150`.
- `shirtFitPlace(mode)` @1773 (ar = picture w/h, br = box w/h): fit → contain (`ar > br ? w 1, h br/ar : h 1, w ar/br`), fill → cover;
  centred `x = (1-w)/2, y = (1-h)/2`.
- Pointer (`shirtEditorDown` @1874; editor swallows all taps while open): buttons as above (turn = save current side, flip side, load
  side; smooth = toggle, save `-look`, re-print; done = save side, write `-place`/`-place-back`, re-print, close; cancel = close (in-memory
  SHIRT.place may already have been updated by loadShirtArt)). Else a corner within 16 px → drag mode nw/ne/sw/se; inside the rect → move
  (offset kept); else nothing. `shirtEditorMove` @1895: move sets x,y from the pointer; corners resize with min size `0.08` (box fraction),
  opposite corner fixed. Pointer up → `drag = null`. No clamping to the box. No keyboard/pad controls; the game keeps running underneath
  (walking away hides the ART button but not the editor).

---------------------------------------------------------------------------------------------------
## 5. THE WARDROBE (WARD)

```js
const WARD_ART = ['wardrobe-0.png', 'wardrobe-1.png', 'wardrobe-2.png'].map(artImg);   // embedded base64 (ART_B64 @1037)
const WARD = { x: 180, y: ARENA.h + 100 /*620*/, s: 1, open: false, k: 0, t: 0 };
function wardNear(p) { return !!p && p.alive && !p.dive && !p.sit && T.loungeFloor && Math.abs(p.x - WARD.x) < 40 && p.y > WARD.y - 2 && p.y < WARD.y + 38; }
//   x 140..220, y 618..658
function toggleWard() { WARD.open = !WARD.open; /* creak + clunk */ }
```
- **One shared state**: `WARD.open` lives on the host (toggled by either player's E through `lobbyAction`) and is sent to the guest in the
  snapshot as `wd: 0|1` (@8306, applied @8405). E label `OPEN` / `CLOSE`.
- **Animation** `drawWardrobe()` @1954 (each screen, real time): `dt = min(0.1, now - WARD.t)`; `WARD.k = clamp(k ± dt*5, 0, 1)` (0.2 s);
  frame = `k <= 0 ? 0 : k < 1 ? 1 : 2` (shut / one door / both doors). Drawn at **half the art's pixel size** × s: 176x193 px → **88 x 96.5**
  units, `drawImage(im, round(180 - 44), round(620 - 96.5), 88, 97)` nearest-neighbour, bottom-centred on (180, 620). Shadow first:
  ellipse (180, 619) rx 34 ry 6 `rgba(0,0,0,0.25)`.
- **What's inside**: purely painted art (frame 2 shows hanging: a green singlet, a brown leather jacket, a blue Hawaiian shirt, a red box on
  the shelf, a drawer). There is **no clothes/character changing** in the wardrobe. The only interaction behind its doors is the **ART**
  button (§4.3) — the shirt-picture feature — for the host only. (Characters are picked elsewhere: `CHAR_IDS` = juicy, tyson2, goth,
  jared, tyson, inky; the guest sends `{t:'char'}`; not part of the bedroom.)
- Sound on toggle: `sTone(0.35 s, open ? 180→320 : 240→150 Hz, gain 0.08, sawtooth)` (creak) + `sNoise(0.12 s, 900 Hz, Q 2, 0.12, bandpass)` (clunk).
  Plays on the screen that performed the toggle (host) only.
- First person: billboard prop captured from `drawWardrobe()`; re-captured when `WARD.open` changes (so it shows the final frame, not the swing).

---------------------------------------------------------------------------------------------------
## 6. THE BED

```js
function bedSpot(side) { return { x: (BED.x0 + BED.x1) / 2 + (side === 1 ? -30 : 30), y: BED.y0 + 70 }; }   // side 1: (350, 590), side 2: (410, 590)
function bedNear(w, p) {
  if (!p || !p.alive || p.dive || p.sit || p.lift || p.leg || p.bed || w.started || !lobbyTall(w)) return 0;
  if (p.x < BED.x0 - 24 || p.x > BED.x1 + 24 || p.y < BED.y0 || p.y > BED.y1 + 34) return 0;   // x 290..470, y 520..710
  const taken = s => w.players.some(q => q !== p && q.bed === s);
  const want = p.x < (BED.x0 + BED.x1) / 2 ? 1 : 2;              // the half you're nearer (centre x 380)
  return !taken(want) ? want : !taken(3 - want) ? 3 - want : 0;  // else the other side, else none
}
function lieDown(p, side) { const s = bedSpot(side); p.bed = side; p.x = s.x; p.y = s.y; p.vx = p.vy = 0; p.fx = 0; p.fy = 1; }
function getUp(p) { p.x = bedSpot(p.bed).x; p.y = BED.y1 + T.radius + 2; /* 692 */ p.bed = 0; p.vx = p.vy = 0; p.fx = 0; p.fy = 1; }
```
- `p.bed`: 0 none, 1 left, 2 right. Host-authoritative, in the snapshot (index 49). **Both players can lie down at once** (one per side).
- Enter: E / tap / pad A with label `LIE DOWN` (not while carrying Gothica). Exit: E (`GET UP`), or in the host's step @7200: any move
  input with `hypot(mx, my) > 0.3` or the roll button → `getUp`; otherwise input is zeroed and the player is pinned to `bedSpot`.
  If a run starts, `p.bed = 0`.
- **Nothing else happens**: no time skip, no healing, no save; it's cosmetic. (Other features exclude `p.bed` players: mirror, tramp, bbq,
  shroom, FP cast.) In first person, `fpBusy()` is true while you're in bed → top-down view; in FP other players in bed aren't drawn.
- The main character pass skips players with `p.bed` (@12260); they're drawn by `drawSleepers(w)` @2459, called from `drawLowerLobby`
  right after the floor art (so under walls and every standing character):
```js
im = (IMG[p.ch] || IMG.jared).front_run[0] (or front_a / front)       // the baked frame (hair + print included)
h  = T.radius * T.spriteScale * charScale * (NEW_ART ? T.altScale : 1)  // ≈ 80
dw = h * im.w / im.h * (NEW_ART ? T.altWide : 1)
s = bedSpot(p.bed), top = BED.y0 + 16 /*536*/
clip rect(BED.x0, BED.y0, BED.x1 - BED.x0, 50)    // y 520..570: only head & shoulders show above the fold
drawImage(im, round(s.x - dw/2), round(top), round(dw), round(h))   nearest
fillRect(s.x - dw/2 + 2, 570, dw - 4, 8)  #dfe6f0     // turned-down sheet over his chest
fillRect(s.x - dw/2 + 2, 578, dw - 4, 8)  #2f4f7a     // blanket edge
// z z z: three 'z' (bold 12px), for i in 0..2: f = (t*0.5 + i/3) % 1 (t = seconds); colour rgba(220,235,255, 1 - f);
//        at (s.x + 14 + f*16, top - f*26)   → each z drifts up-right 16x26 units over 2 s, fading
```
- No sound for lying down/getting up.

---------------------------------------------------------------------------------------------------
## 7. Extracted / mapped art

Directory: `/home/user/Smashed-tv/godot/scripts/lobby_life/art/bedroom/`

| file | what | px | draw scale |
|---|---|---|---|
| `wardrobe_0_shut.png` | ART_B64 `wardrobe-0.png`, doors shut (WARD.k == 0) | 176x193 | 0.5 units/px → 88x96.5, bottom-centre at (180, 620) |
| `wardrobe_1_one_door.png` | `wardrobe-1.png`, one door open (0 < k < 1) | 176x193 | same |
| `wardrobe_2_both_open.png` | `wardrobe-2.png`, both doors open, clothes visible (k == 1) | 176x193 | same |
| `bedroom_floor.png` | ART_B64 `bedroom.png`: the bedroom floor with bed, pillows, nightstand, rug, slippers, dumbbell, books | 440x342 | 1 unit/px at (18, 520) (= BEDROOM rect) |
| `hair/<style>_<view>.png` | 40 hair images: braids, mullet, slick, tyson, mohawk, mohawk_blue, mohawk_purple, mohawk_green × front/diag/side/back/bdiag | see §3.6 | sprite pixels (1:1 on the 160 px Juicy frames → 0.5 units/px), times the frame's HAIR_FIT `s` |
| `hair_data.json` | BEARDS, HAIR_ART anchors+sizes+files, HAIR_HEAD, HAIR_FIT (131) | — | — |

Same originals in the repo: `art/bedroom.png`, `art/wardrobe-*.png` (the files ART_B64 was built from); hair in
`godot/assets/misc/line1418_0..14.png`, `godot/assets/HAIR_ART_{tyson,mohawk,mohawk_blue,mohawk_purple,mohawk_green}/{view}_2.png`.
The mirror, sheet/blanket strip, z's, buttons and editor are drawn procedurally (colours above). No `gymImg(...)` art is used by these features.
Character frames: `godot/assets/CHARS/juicy/sprites/*.png` (run frames 160 px tall: front_run 98 wide, diag 115, side 135, bdiag 118, back 95).

---------------------------------------------------------------------------------------------------
## 8. Sounds (WebAudio synth; `sTone(dur, f0, f1, gain, wave)` = oscillator with exponential freq ramp f0→f1 and gain ramp → 0.0008;
`sNoise(dur, freq, Q, gain, type, sweepTo)` = looped white noise through a biquad filter, optional freq sweep, same gain envelope)
- Wardrobe open: sawtooth 180→320 Hz 0.35 s g0.08 + bandpass noise 900 Hz Q2 0.12 s g0.12. Close: sawtooth 240→150 Hz + same noise.
- Hair change ("snip"): bandpass noise 3200→1800 Hz Q2 0.08 s g0.12 + square 900→1300 Hz 0.05 s g0.06.
- Mirror, bed, shirt editor: silent.

---------------------------------------------------------------------------------------------------
## 9. Controls summary

| context | keyboard | mouse/touch | gamepad |
|---|---|---|---|
| near mirror | E: LOOK | tap E button | A |
| looking | A/D or ←/→ turn (3.2 rad/s); F next hair, Shift+F previous; E or S/↓ step away; moving > 3 units exits | big arrows ±45° turn (6 rad/s), small arrows hair ∓/±; move stick x turns, stick down exits; E button (`BACK`) exits | left stick x turns, stick down exits; B exits; nothing else |
| wardrobe | E: OPEN/CLOSE | E button; ART button (host, open, near): pick picture / open editor; × clears | A |
| shirt editor | — | buttons, drag picture, drag corners | — |
| bed | E: LIE DOWN / GET UP; any move key or Shift (roll) gets up | E button / move stick | A; stick / B / RB / LT (roll) gets up |
