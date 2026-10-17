# Spec: lounge table + 2 chairs, sitting, bong/vape, bong trip, blackjack with Gothica

Source: `/home/user/Smashed-tv/Smashed.html` (build b331). Line numbers are HTML lines.
Coordinates: world px, x right, y down the screen (ground plane), z height. ARENA = 860x520, wall 18.
All "lobby only": everything here is disabled once the run has started (`w.started`) and requires `T.loungeFloor` (=1).

Constants (from `T`, also in `godot/data/game_data.json`):
`T.tableX = 165`, `T.tableY = 300`, `T.radius = 14`, `T.spriteScale = 4.6`, `T.npcSpeed = 38`, `T.npcGoth = 1`.

---------------------------------------------------------------------------------------------------
## 1. Geometry: table, chairs, solid box

```js
// 3432
function tableBox() { return { x0: T.tableX - 52, x1: T.tableX + 52, y0: T.tableY - 16, y1: T.tableY + 16 }; }
// 3434  chair 1 = left of table (sits facing right), chair 2 = right (faces left)
function chairPos(i) { return { x: T.tableX + (i === 1 ? -44 : 44), y: T.tableY + 2 }; }
```
- tableBox = (113..217, 284..316): one solid lump covering table+both chairs, part of `lobbySolidBoxes()` (3431). Players are pushed out of it; Gothica (when not carried/thrown) is pushed out with radius 8 (5786); her pathfinding avoids it inflated by NPC_PAD=12 (10172).
- Chair 1 seat point = (121, 302); chair 2 = (209, 302).
- `bongRest()` (5533) = (tableX-9, tableY-19) = (156, 281): centre of the bong sprite when on the table.

### chairNear(w,p) (3435-3443) – the "SIT" prompt
Returns 1/2 or 0. Requires: `p.alive`, not `p.dive`, `!w.started`, `T.loungeFloor`, p is not carrying Gothica (`NPC_GOTH.carrier !== p.id`). Checks chair 1 then 2; skip a chair if another player has `q.sit === i`; hit if `|p.x-c.x| < 44 && |p.y-c.y| < 44`.

---------------------------------------------------------------------------------------------------
## 2. Drawing the table (drawTable, 3444-3486)

Skipped if `w.started || !T.loungeFloor || cal.on`. Drawn in the floor/prop layer (11910) BEFORE all characters, so characters always draw over it (no depth sort). x=165,y=300. All rects in world px:
1. Shadow: ellipse centre (x, y+18), radii 56x10, `rgba(0,0,0,0.22)`.
2. Chairs (skipped for a chair whose occupant uses the sit art / sit legs — `sitArtIn(chair)` (5200): Jared's art brings its own stool). `chair(cx, flip)`, chair1 cx=x-44 flip=false, chair2 cx=x+44 flip=true:
   - seat `#5a3a1e` rect (cx-12, y-4, 24x14); inner `#7a5230` (cx-11, y-3, 22x10)
   - front legs `#3e2712` (cx-12, y+10, 3x9) and (cx+9, y+10, 3x9)
   - back post `#5a3a1e` at bx = cx+9 (flip) or cx-12, rect (bx, y-24, 3x22)
   - 3 slats `#7a5230`: (flip ? cx-12 : cx-9, y-22+s*6, 21x3), s=0..2
   - second post `#5a3a1e` (flip ? cx+9 : cx-12, y-24, 3x22)
3. Pedestal `#3e2712` rect (x-4, y-2, 8x20) + foot ellipse (x, y+18) 14x5.
4. Rim ellipse `#4a2e15` (x, y-4) 30x13; top `#8a5a2b` (x, y-6) 28x11; sheen `#a06a35` (x-4, y-8) 16x5.
5. Grain `#3e2712` 1px lines: (x-20,y-6,40), (x-14,y-10,28), (x-16,y-2,32).
6. Bong, if `!bongHeld()`: `drawGymImg(VAPE_ART.bong, x-9, y-19, false)` then `drawBongVape(x-9, y-19, 1)` (see 4.1).
   `bongHeld()` (5532) = any player in the HOST's `world` has `vape.held` or `usesSitArt(p)`.
7. Mug: `#e8e2d2` (x+8, y-15, 7x8); handle `#c9c1ad` (x+15, y-13, 2x4); coffee `#4a2e15` (x+9, y-14, 5x2).
8. `drawTableCards(w)` (5359): blackjack cards on the table top (section 7.6).

`drawGymImg(im,cx,cy,flip)` (823): draws image CENTRED at (cx,cy) at half its pixel size (naturalW/2 x naturalH/2), nearest-neighbour, flip = scale(-1,1).

In first-person (shroom 3D view) the table is also rendered as a camera-facing billboard prop (`drawTable(quiet)` in the props list, 4047).

---------------------------------------------------------------------------------------------------
## 3. Sitting down / standing up

### Player state fields
| field | values | meaning |
|---|---|---|
| `p.sit` | 0, 1, 2 | which chair (0 = not seated) |
| `p.bong` | 0/1 | has picked the bong up (chose BONG) |
| `p.vape` | null or `{t, last, held?, bub?}` | a hit in progress; `t` = seconds since start |
| `p.hitRow` | 0 | reset on stand; otherwise unused (row counting is global `BONG_HITS`) |
| `p.fx, p.fy` | facing | set to (±1, 0) on sitting |

### Sitting (E)
`lobbyAction(w,p)` (10140-10165) handles E. Order of priority before reaching the table: Gothica anim / trampoline / BBQ / trampoline-on / gym / rope / wardrobe. Then:
```js
if (p.sit) { if (!p.bong) p.bong = 1; else if (!p.vape) p.vape = { t: 0 }; return; }   // 10152
...
{ const ch = chairNear(w, p); if (ch && !carrying) { p.sit = ch; const c = chairPos(ch); p.x = c.x; p.y = c.y; p.vx = 0; p.vy = 0; p.fx = ch === 1 ? 1 : -1; p.fy = 0; return; } }  // 10155
```
(also `sitDown(p,ch)` 5473 does the same.)
So E while seated: 1st press = take the bong (`p.bong=1`), every later press (when no hit running) = start a hit (`p.vape={t:0}`). E is ignored during a hit.

### Seated each tick (7186-7190, in the player step)
```js
if (p.sit && !w.started) {
  if (Math.hypot(inp.mx, inp.my) > 0.3 || inp.roll) { p.sit = 0; p.vape = null; }        // stand up
  else { inp = {...inp, mx:0, my:0, shoot:false, roll:false}; pin p to chairPos(p.sit); vx=vy=0; }
} else if (p.sit) p.sit = 0;                                                               // run started
if (!p.sit) { p.bong = 0; p.hitRow = 0; }                                                  // bong goes back on table
```
Standing up = any movement input > 0.3 (keys/stick/touch stick) or the roll input. Standing cancels a running hit with no bongHit. No shooting while seated. Player appears at the chair point when standing (normal collision pushes him out of tableBox).

### E-button prompt label (lobbyLabel 10096/10103)
- Near free chair: `'SIT'`
- Seated, no bong: `'BONG'`; seated with bong, no hit: `'HIT'`; during a hit: no button (null).
The prompt is the round "E button" (`carryButton`, 10111): centre (ARENA.w-62, ARENA.h-wall-70-48) = (798, 384), r 34, fill `rgba(20,12,28,0.72)`, stroke `#f7a8ff` 2px, label bold 12px `#f7a8ff` centred. Tap/click on it = E.

### Camera while seated (8509, 8524-8530)
`SIT_ZOOM = 1.8`; target centre (tableX, tableY-12) = (165, 288); zoom lerps at rate `dt*5` (normal 10), position lerps `dt*8`.

### First person
`fpBusy()` (3587) is true while `me.sit`: first-person (the shroom 3D view) "steps aside" and the normal top-down view + controls are used while seated. Pressing a move key (WASD/arrows) while seated in FP mode stands you up and re-locks the pointer into FP (3699). Nothing seated-specific is drawn in FP.

---------------------------------------------------------------------------------------------------
## 4. Drawing a seated player

Dispatch in drawPlayer (10490-10517):
1. `usesSitArt(p)` (5179): `p.sit && p.bong && p.ch === 'juicy'` and SIT_ART loaded -> `drawSitArt(p)` (Jared holding bong, SIT_T timings).
2. `usesSitLegs(p) && sitIdleReady()` (5225): `p.sit && !p.bong && p.ch==='juicy'` -> `drawSitIdle(p)` (hands on knees).
3. Otherwise (other characters): generic seated pose + `vapeFrame` (VAPE_T timings). See 4.4.
The player's team ring (ellipse) is still drawn first (10481-10487).

### 4.1 Art: VAPE_ART / bong in the stem
`VAPE_ART` (3488-3492, + `.torch2` at 5622). `drawBongVape(cx, cy, dir)` (3505-3517): the Verdavape (vape.png) sits in the bong's bowl, along the stem:
```js
const BONG_GEO = { lip: [-1.9, -13], bowl: [5, 0], stem: [0.55, -0.83], tube: [-4.4, 0, -12, 3], water: [0, 8, 5] };  // 3502
sd = (stem.x*dir, stem.y); bowl = (cx + dir*5, cy); vl = 12;
vape centre = bowl + sd*(vl/2 - 2);  rotate(atan2(sd.x, -sd.y)); if dir<0 scale(-1,1)
k = vl / (vape.naturalHeight/2)  // = 0.6 ; drawn size (28/2*k) x (40/2*k) = 8.4 x 12 world px, centred
returns tip = bowl + sd*(vl - 3)
```
`TORCH_NOZ = [3.2, -6]` (3503): torch nozzle offset from torch2's centre.

### 4.2 drawSitArt(p) — Jared with the bong (5136-5178), SIT_T
```js
const SIT_T = { heat: 0.25, click: 2.1, pull: 2.4, blow: 3.8, done: 5.9, end: 6.2 };       // 5096
const SIT_GEO = { stool: 10.5, mouth: [21, -46.5], tip: [29.2, -34.5], flame: [33.3, -39], floor: 18 };  // 3526
```
- `dir = p.sit === 2 ? -1 : 1`. If `p.vape`, `v.t += dt` (dt clamped 0..0.1, wall clock).
- Frame: `f = !v ? 0 : t<0.25 ? 0 : t<2.4 ? 1 : t<3.8 ? 2 : t<5.9 ? 3 : 0`.
  SIT_ART frames: 0 hold bong+torch ready, 1 lips on it/torch going, 2 pulling (tip red), 3 blowing out.
- Placement: image drawn at HALF its pixel size (90x118 px -> 45x59 world), left = `p.x - 10.5`, bottom = `p.y + 18` (top = bottom-59). For dir<0 the whole thing is mirrored about x = p.x (`translate(p.x*2,0); scale(-1,1)`), nearest-neighbour.
  (If the shirt-print feature is active the frame is a canvas `__ss` times bigger; drawn size is still natural/(2*ss). `__mir` = pre-mirrored print. Port: just use the PNG.)
- Art-space point -> world: `W(ox,oy) = (p.x + dir*(ox - 10.5), bottom + oy)`.
- Heat: `!v ? 0 : t<0.25 ? 0 : t<2.4 ? min(1,(t-0.25)/1.6) : max(0, 1-(t-2.4)/2.4)`.
- Stem vape overlay `drawStemVape(left, bottom-h, SIT_STEM[f], heat)` (inside the mirrored transform):
  `SIT_STEM = [[29.25,24],[29.75,23.5],[29.5,24.5],[28,23.5]]` (world px from art top-left, per frame).
  Pixel sprite STEM_PIX (5110-5123), each char = 0.5x0.5 world px, '.' transparent:
  ```
  ...KKKKKK.
  ...KHHHHK.
  ...KLSSDK.
  ...KLSSDK.
  ...KLSSDK.
  KWWPKLSSDK
  KwwPKLSSDK
  ...KEEEEK.
  ...KWWWwK.
  ...KWWWwK.
  ...KWWwwK.
  ...KKKKKK.
  ```
  Colours: K `#1c1a22`, L `#e6e8ec`, S `#b4b8c0`, D `#7a7e88`, E `#5a5e68`, W `#9a5a32`, w `#6e3c1e`, P `#c9ccd2`;
  H (cap) = heat<=0 `#d7d9de`, <0.35 `#e8a07a`, <0.7 `#ff6a2a`, else `#ff3a1e`.
  Origin `x0 = round((ax+tip.x)*2 - 6)/2`, `y0 = round((ay+tip.y)*2 - 1.5)/2`; pixel (r,c) at `(x0 + (c - floor(r/4))/2, y0 + r/2)` (lean: one px left every STEM_LEAN=4 rows). If heat>0.35: glow rect `#ff8a2a` alpha 0.3*heat at (x0+1, y0-0.5, 3x2).
- Frame 1 (torch): flame dot at W(33.3,-39): circle r 2.2 `#9fe8ff`, alpha `0.35 + 0.3*sin(now*47)*sin(now*13)`. Torch hiss sound every 1/6 s.
- Click at t crossing 2.1 (two square ticks, 70ms apart).
- Frame 2 (pull): with prob dt*8 per frame push a wisp at W(29.2,-34.5) (x, y-1): `{vx: dir*3, vy:-12, r:1, grow:4, life:0.9, a:0.45}`; bubble tone every 1/9 s.
- Blow: t in [3.8, 5.2), prob dt*30 per frame: puff at mouth W(21,-46.5) + (dir*2, 0): `vx = dir*(30+rnd*30)*(0.4+s)` with `s = 1-(t-3.8)/1.4`, `vy = -8 - rnd*12`, `r = 1.5+rnd*1.5`, `grow = 9+rnd*8`, `life = 2+rnd`, `a = 0.7`.
- At t crossing blow+1.6 = 5.4: 35% chance floater `'*cough*'` colour `#e8e2d2` at (mouth.x, mouth.y-18).
- At t >= 6.2: `p.vape = null; bongHit(p)`.

### 4.3 drawSitIdle(p) — Jared seated, empty-handed (5189-5199)
Same placement/mirroring as 4.2 using SIT_IDLE. Frame: `(now % 9) > 7.6 ? 3 : 0` (frame 3 = head turned toward camera for 1.4 s every 9 s). Frames 1 and 2 exist but are unused.
Also `drawSitLegs` (5227, from SIT_ART[0] rows >=64 with bong/hand painted out) is used only in the generic path below when sit idle art isn't loaded; port can ignore it.

### 4.4 Generic seated pose (other characters) (10492-10516) + vapeFrame (5534-5620)
- Image: character's `side_run` (first frame) or `side_a`. `h = T.radius*T.spriteScale*charScale` (=64.4*scale), `dw = h*aspect`. `keep = 0.58`, `seatY = p.y + 6`. Mirrored about p.x for chair 2.
- Far leg `drawSeatedLegs(im, p.x, seatY, true)`, then the sprite's top 58% height and left 56% width (`VAPE_GEO.cut`, crops the gun barrel) drawn at (p.x-dw/2, seatY-h*0.58) size (dw*0.56, h*0.58), then near leg.
- `drawSeatedLegs` (5503-5530): procedural polygons (thigh/knee/shin/boot) with colours sampled from the sprite (`legColours` 5479: shorts from 58-72% height, skin from 28-52%, boot from 88-100%), outline `#1c1a22`. Leg origin: hip x = x-6, thigh top ty = seatY-11 (+1 near, -1 far, far leg offset +3 x, darker). Knee x = x+14. Exact polygon point lists at 5512-5515.
- `vapeFrame(p, {top, dw, h})`, timings `VAPE_T = { lift: 0.5, torch: 0.55, click: 2.35, pull: 2.6, down: 3.9, blow: 4.2, end: 7 }` (3498), `VAPE_GEO = { mouthX: -0.01, mouthY: 0.262, cut: 0.56, tilt: 0.45 }` (5621):
  - mouth = (p.x + dir*dw*-0.01, top + h*0.262). ease = smoothstep.
  - bong lifted from bongRest to `held = (mouth.x + dir*2 - dir*lip.x, mouth.y - lip.y)`: `up = t<3.9 ? ease(t/0.5) : 1 - ease((t-3.9)/0.45)`; arc: `cy -= sin(up*PI)*6`. `v.held = up > 0` (hides the table's bong).
  - Bong rotated by `ang = -dir*0.45*up` round its lip point.
  - Tube milk: `fill = t<2.6 ? 0 : t<3.9 ? ease((t-2.6)/0.9) : max(0, 1-(t-3.9)/0.5)`, rect `#eef0f4` alpha 0.55 over tube x [-4.4..0], y from cy+3 up by 15*fill.
  - Tip glow: `heat = t<0.55 ? 0 : t<2.6 ? min(1,(t-0.85)/1.4) : max(0,1-(t-2.6)/1.2)`; circle r1.9 colour <0.4 `#e89090`, <0.8 `#e0402a`, else `#ff5a2a`, alpha min(1,heat*1.5); halo r4.5 `#ff7a2a` alpha 0.3*heat.
  - Torch (torch2.png, drawn half size, flipped `scale(-dir,1)`) for t in (0.55, 2.6): `rise = ease((t-0.55)/0.25)*ease((2.6-t)/0.25)`, nozzle at tip + (dir*7, 5 + (1-rise)*8), alpha rise. When rise>0.9: flame = 3 triangles from nozzle to `nozzle + (tip-nozzle)*(0.9+0.12*sin(now*55))`, half-widths/colours/alpha: (2, `#1e5bff`, 0.8), (1.3, `#39c8ff`, 0.9), (0.5, `#e8fbff`, 1).
  - Pull (2.6..3.9): bubbles in water (prob dt*30, 1x1 white, rise 22 px/s, live 0.3 s) at `(rnd-0.5)*10, y 8` relative to bong centre; wisps like 4.2.
  - Blow (4.2..5.5, prob dt*26): puffs like 4.2 but at mouth+(dir*3,0), `s=1-(t-4.2)/1.3`, grow 8+rnd*7, a 0.65. Cough 35% at t=5.7. End at t>=7 -> `p.vape=null; bongHit(p)`.

### 4.5 Smoke (drawSmoke, 5622-5637), global `VAPOUR[]`
Drawn after characters (12401). Per particle per frame (dt clamped 0.1):
```js
s.t += dt; if (s.t >= s.life) remove;
s.x += s.vx*dt; s.y += s.vy*dt; s.vx *= 1 - dt*1.4; s.vy -= 4*dt;
k = s.t/s.life; r = s.r + s.grow*sqrt(k);
alpha = s.a*(1-k)*(1-k*0.3); circle (s.x,s.y,r) '#e9e6ee';
then alpha*0.6, circle (s.x - r*0.25, s.y - r*0.3, r*0.55) '#ffffff'
```

### 4.6 Sit-art geometry summary (HTML units)
Sprite 90x118 px -> 45x59 world. Bottom-left of art = (p.x-10.5, p.y+18) facing right. Chair 1: art spans x 110.5..155.5, y 261..320. Chair 2 mirrored: x 174.5..219.5.

---------------------------------------------------------------------------------------------------
## 5. Bong hits and the trip

### bongHit (5009-5018)
```js
const BONG_HITS = { row: 0, at: 0 };
function bongHit(p) {
  if (!p || p.id !== (net.role === 'client' ? 1 : 0)) return;     // only YOUR OWN hit counts, on your own screen
  const now = performance.now() / 1000;
  if (now - BONG_HITS.at < 3) return;                               // de-dup (same hit seen twice)
  BONG_HITS.row = (p.sit && BONG_HITS.at && now - BONG_HITS.at < 30) ? BONG_HITS.row + 1 : 1;
  BONG_HITS.at = now;
  if (BONG_HITS.row >= 2 && !TRIP) { BONG_HITS.row = 0; startTrip(); }
}
```
=> 2 completed hits, the second finishing within 30 s of the first (and >=3 s), triggers a trip on that player's screen only. Guest: counted when its own snapshot vape field (idx 54) goes from >= (6.2-0.6)*100 to 0 (10858).

### Trip timeline `TRIP_T = { dark: 1.5, show: 3, full: 4.5, fade: 11, gone: 11.5, back: 12.2, end: 13.8 }` (5005)
`TRIP = { t, last, beat, nodes, seq?, seg?, rise?, sting? }`. Drawn last, over everything incl. HUD, in SCREEN space (860x520 scaled to canvas) (12764, 12816). Gameplay continues underneath (input is not blocked). (`full` and `gone` unused.)
- Black overlay alpha: `t<1.5 ? ease(t/1.5) : t<12.2 ? 1 : 1 - ease((t-12.2)/1.6)`; ease = smoothstep. Fill `#000` full screen.
- 3 < t < 11: the MANTIS (robed praying-mantis figure, 4 frames, animated at 5 fps: `MANTIS[floor(t*5)%4]`):
  - Visibility sequence generated once per trip: from s=3 while s<11: on = 0.45+rnd*0.7 s, off = 0.12+rnd*0.4 s, segment `[s, s+on, side]` with side = (rnd-0.5)*2 in [-1,1].
  - Alpha a = 0 between segments; first segment fades in over 0.8 s (`ease((t-seg0)/0.8)`), others 1. Random blink: each frame with prob dt*4, a *= 0.2.
  - Progress `pr = ((t-3)/8)^1.6`; scale `k = 0.22 * (2.6/0.22)^pr` (0.22 -> 2.6 of the 169x240 image, i.e. 37x53 px -> 439x624 px).
  - `cx = 430 + side*60*(1-pr)`; `feet = 270 + 390*pr^2 + sin(t*1.7)*6*k`.
  - Shadow: ellipse (cx, feet+22k), radii 46k x 9k, `#1a1a22`, alpha a*0.5.
  - Image drawn at (round(cx - w*0.45), round(feet - h)), size w = 169k, h = 240k, alpha a, nearest-neighbour.
  - Crackle noise each time a new segment (not the first) starts.
- Film grain while black > 0.2: 90 random white 1.5x1.5 squares/frame, alpha 0.05*black.
- Ends: at t>=11 music fades (stopTripMusic); at t>=13.8 TRIP=null. Total 13.8 s.

### Trip sound (5019-5046, 5076-5088)
- Music (startTrip): master fader exp-ramp 0.0001->1 over 2.5 s. Lowpass 650 Hz Q8 with LFO 0.18 Hz depth ±420 Hz on cutoff. Oscillators into it: saw 110 Hz g.16, saw 116.5 g.15, saw 155.6 g.1, triangle 55 g.2. High whine: sines 1244.5 and 1318.5 Hz gliding to x0.94 over 12 s, 5.3 Hz vibrato ±9 Hz, gain 0.06, into output and a 0.37 s feedback (0.5) delay.
- stopTripMusic: fader exp-ramp to 0.0001 over 1.6 s, stop at +1.7 s.
- At t>2.4: rising whoosh (bandpass noise 2 s, 250->2600 Hz, Q5, g.35).
- Heartbeat every 1.15 s from t=3 to 11: thump (sine 130->60 Hz 0.16 s + lowpass noise 500 Hz 0.07 s), second weaker thump 170 ms later (0.7 then 0.5).
- At t>11: shriek (saw 1400->90 Hz 0.9 s g.3 + bandpass noise 3000->300 Hz 0.5 s).

Other hit sounds: torch hiss = bandpass noise 0.18 s 2600 Hz Q.6 g.05, every 1/6 s while flame on; click = square 2400->2200 Hz 0.02 s g.12 then 2600->2400 g.1 after 70 ms; bubbling = sine 0.05 s (180..300)->120 Hz g.06 every 1/9 s while pulling.
Helpers: `sTone(dur,f0,f1,gain,wave)` exp freq ramp + exp decay to 0.0008; `sNoise(dur,freq,q,gain,type,sweepTo)` looped white noise through biquad, exp decay (11213-11239).

---------------------------------------------------------------------------------------------------
## 6. The sit menu and CARDS button (HUD, screen space 860x520, drawn after the world, 12441-12449)

### sitMenu (5434-5442) – shown when local player is seated, alive, `!me.bong`, no `w.bj`, lobby, not over, not calibrating
- Host: panel pw 360, ph 84, px = 860-18-360-48 = 434, py = 18+34 = 52. Buttons (h 30):
  - `'BONG (E)'` x px+16, y py+40, w 150, colour `#3a2150` -> host: lobbyAction (= E: p.bong=1); guest: SITREQ.
  - `'CALL GOTHICA (B)'` x px+pw-186, w 170, colour `#1f5a36` -> doBJ('call').
- Guest: pw 240 (px 554), only `'CALL GOTHICA (B)'` at x px+35. (Comment says the guest has no bong; but E on the guest still sets p.bong via the host's lobbyAction.)
- Draw (5443-5458): panel roundRect r10 `rgba(20,12,28,0.9)`, stroke `#f7a8ff` 2px; title `"Take a seat. What'll it be?"` bold 14px white centred at (px+pw/2, py+20); buttons roundRect r7 fill col, stroke `#f7a8ff` 1.5, label bold 13px white centred.

### cardsButton (5427-5432) – seated, no `w.bj` (so visible after taking the bong)
Circle at (860-62-80, 520-18-70-48) = (718, 384), r 34. Fill `rgba(14,40,26,0.8)`, stroke `#6fd3a0` 2px; `'CARDS'` bold 12px `#6fd3a0` at y-5, `'(B)'` 10px at y+9. Click within r+6 -> doBJ('call').

---------------------------------------------------------------------------------------------------
## 7. Blackjack (5234-5424)

Rules (comment 5234): Gothica deals; dealer draws to 16, stands on 17 (soft 17 counts as 17); every seated player plays vs her; bet `BJ_BET = 10` coins; blackjack pays 3:2. Host-authoritative; state `w.bj` rides the snapshot.

### 7.1 State `w.bj`
```js
{ ph: 'idle'|'play'|'dealer'|'done', deck: [card...], d: [dealer cards], seats: { 1?: seat, 2?: seat },
  turn: 0|1|2, t: seconds timer (dealer phase), shown: bool (hole card revealed), say: string, sayN: int }
seat = { pid, c: [cards], st: 'play'|'stand'|'bust'|'bj'|'left', bet: 10, res: ''|'WIN'|'LOSE'|'PUSH'|'BUST'|'BLACKJACK'|'LEFT' }
```
Card = int 0..51: rank `c % 13` (0=A ... 9=10, 10=J, 11=Q, 12=K), suit `floor(c/13)` -> `['♠','♥','♦','♣']`; red if 13<=c<39. -1 = face down.
`bjValue` (5240): A=11 (reduced to 1 while >21), 2-9 face, 10/J/Q/K=10; -1 skipped.
`bjDraw` (5246): when deck empty, rebuild 104 cards (2 decks, i%52) and Fisher-Yates shuffle; pop from end.
`bjSay(b,text)`: sets say, increments sayN (Gothica speaks when sayN changes).

### 7.2 Actions `bjAction(w, p, a)` (5254-5290), a in `call | stop | deal | hit | stand`
Ignored unless lobby, p alive and seated.
- `call`, or `deal` with no bj: if bj exists -> nothing. If Gothica is carried or thrown -> floater `"Gothica's busy!"` (`#f7a8ff`). Else `w.bj = {ph:'idle', deck:[], d:[], seats:{}, turn:0, t:0, shown:false, say:'', sayN:0}` and she says (50/50) `"Cards? Sure, I'll deal."` or `'Ooh, blackjack? Coming!'`.
- `stop` ("DONE"): only in ph idle/done -> `w.bj = null` (she leaves).
- `deal`: ignored in play/dealer. Busy check as above. New bj keeping the old deck and sayN. For each alive seated player: if `coins < 10` floater `'need 10 coins'` (`#e0473f`) and skip; else `coins -= 10`, seat created. No seats -> bj = null. Deal 2 rounds: each seat one card, then dealer one (dealer card index 1 = hole card). Seats with 21 -> st 'bj'. `ph='play'`, `turn = first seat (1 then 2) with st 'play'`. Say `'Cards, boys.'` (2 seats) or `'Cards up, big guy.'`. If no one to play: ph 'dealer', t=0.9.
- `hit` / `stand`: only when ph 'play', `turn === p.sit`, seat st 'play'. Hit: draw; >21 -> 'bust'; ==21 -> 'stand' (auto). Stand -> 'stand'. If not 'play' any more -> `bjAdvance` (next seat with 'play', else ph 'dealer', t=0.7).

### 7.3 stepBJ(w, dt) (5291-5323), host each tick
- run started -> bj=null.
- For each seat whose player is no longer seated in that chair: in play/dealer, if st play/stand/bj -> st 'left', res 'LEFT' (bet lost), advance if it was their turn; in idle/done -> seat deleted.
- If not dealer phase and nobody seated -> bj = null.
- Dealer phase: `t -= dt`, wait until <= 0. Then: if !shown -> shown = true, t = 0.8 (flip hole card). Else if any seat st 'stand' and dealer < 17 -> draw, t = 0.8. Else settle:
  - dv = dealer value, dbj = 21 with 2 cards. Per seat: left -> LEFT; bust -> BUST; bj -> dealer bj ? PUSH (pay 10) : BLACKJACK (pay round(10*2.5)=25); else dealer bj -> LOSE; dv>21 or v>dv -> WIN (pay 20); v==dv -> PUSH (pay 10); else LOSE.
  - `coins += pay`; floater over player at (x, y-70): `res + (net>0 ? ' +'+net : net<0 ? ' '+net : '')`, e.g. `WIN +10`, `BLACKJACK +15`, `LOSE -10`, `BUST -10`, `LEFT -10`, `PUSH`; colour net>0 `#6fd3a0`, <0 `#e0473f`, 0 `#f6d17a`.
  - She says: any player BJ -> `'Blackjack?! Lucky.'`; else dv>21 -> `'Ugh, I bust.'`; else dbj -> `'Blackjack. House wins~'`; else won && !lost -> `'Fine, you win.'`; lost && !won -> `'House wins~'`; else `'Some you win...'`.
  - ph 'done', turn 0.
Note: dealer only draws if at least one seat is 'stand' (all bust/bj -> she just reveals).

### 7.4 Network
`bjPack` (5325): `[phIndex, dealer cards with index1 = -1 while !shown, turn, [[seat, pid, cards, stIndex, res]...], say, sayN]` (no deck). `bjView` = what the players see (hole card hidden). Guest sends `BJREQ.id++ / BJREQ.a` (input fields bq, ba; host runs bjAction for p when bq changes, 7182). Guest E = SITREQ.id++ -> host lobbyAction(p) (7181).

### 7.5 Gothica (NPC_GOTH) while blackjack is on (lobbyGoth 10263-10276)
- When `w.bj` exists: `n.dealing = true`; target spot `(tableX, tableY-30)` = (165, 270), i.e. standing BEHIND the table (far side, top of screen), centred. She walks there along her obstacle-avoiding path at `T.npcSpeed * 2.4` = 91.2 px/s (hurries). When within 4 px: stops, faces the players/camera (`fx=0, fy=1`, front-facing idle sprite), and stays (standing, not seated) until bj is cleared.
- When bj becomes null: dealing=false, wait 1.5 s, then she wanders again.
- Speech: when `bj.sayN !== n.bjSayN` and say non-empty -> `n.bubble = { text: say, t: 0, dur: 2.6 }`. Bubble (drawSpeech 1134): white `#fffdf6` roundRect r6, ink `#1c1a22` 2px, bold 11px text, padding 14, height 20, top at n.y-92, centred on her (clamped inside walls), tail pointing to her; alpha fades in over 0.12 s and out over the last 0.4 s. (FP view: 4081 draws it at height 92, bold 14px.)
- "Summoned" only by `call` (menu button, CARDS button, B/X); no other summon logic. If someone is carrying/threw her: "Gothica's busy!".

### 7.6 Cards drawing
`drawCard(x, y, c, W, H)` (5338-5357): shadow roundRect (x+1, y+2) `rgba(0,0,0,0.35)` radius W/7.
- Back (c<0): `#5a2a6e` roundRect r W/7, inner outline `#f7a8ff` lw max(1,W/14) at inset W*0.14 (size W*0.72 x H-W*0.28, r W/10).
- Face: `#fbf8f0` roundRect, stroke `#1c1a22` 1px. If W>=14: rank bold round(W*0.42)px at (x+W/2, y+H*0.3), suit round(W*0.5)px at (x+W/2, y+H*0.7), colour red `#d8283a` or `#1c1a22`. If W<14: just a 2x2 dot of that colour at the centre.
On the table (`drawTableCards`, 5359, world space, uses bjView): dealer cards at (x-8+i*4, y-16) 6x8; seat 1 at (x-24+i*3, y-6), seat 2 at (x+8+i*3, y-6), 6x8 (x,y = tableX,tableY).

### 7.7 Panel `bjPanel` / `drawBJPanel` (5367-5425) — shown when local player seated and `w.bj` exists
- pw 330, rows = 1 + number of seats, ph = 64 + max(1,rows)*46; px = 860-18-330-48 = 464; py = 52.
- Background roundRect r10 `rgba(14,40,26,0.9)`, stroke `#f7a8ff` 2px. `'BLACKJACK'` bold 13px `#f7a8ff` at (px+12, py+14) left; `'coins ' + me.coins` bold 12px `#f6d17a` right at (px+pw-12, py+14).
- ph idle: centred 12px `#dfe6ea`: `'Gothica deals. Beat her to 21 without going over.'` at py+44, `'Dealer stands on 17 · blackjack pays 3:2'` at py+62.
- Otherwise rows from y = py+28, step 46: label bold 11px at (px+12, y+9) (`#ffffff` if lit else `#bfc8d0`); total bold 15px at (px+12, y+27) (`#ff6a6a` if >21 else white); cards 26x36 at (px+72+i*30, y); note bold 12px right-aligned at (px+pw-12, y+18), green `#6fd3a0` if /WIN|BLACKJACK/, red `#ff6a6a` if /LOSE|BUST|LEFT/, else `#f6d17a`.
  - Row 'GOTHICA': total = shown ? full value : value of visible cards; note `'drawing...'` in dealer phase; lit in dealer phase.
  - Seat rows (1 then 2): label `'YOU'` or `'P' + (pid+1)`; note = res, else 'BUST' / 'BLACKJACK!' / (play & their turn: `'your go'` or `'their go'`) / `'stands'`; lit when it's their turn.
  - Not dealt in and not done: `'sitting this hand out'` 11px `#bfc8d0` centred at y+6.
- Buttons (h 24, at y = py+ph-30), roundRect r6, stroke `#f7a8ff` 1.5, bold 12px white label; fill `#2f7d4a` for HIT on your turn else `#3a2150`:
  - Your turn: `'HIT (H)'` (px+20, w130), `'STAND (T)'` (px+pw-150, w130).
  - ph done/idle: `'DEAL (B) · 10 coins'` or `'DEAL AGAIN (B) · 10 coins'` (px+16, w pw-128=202), `'DONE'` (px+pw-104, w88) -> stop.
- Card flick sound when the visible card count (incl. +1 when hole shown) increases: triangle 1500->700 Hz 0.04 s g.06.

---------------------------------------------------------------------------------------------------
## 8. Controls summary

| input | context | effect |
|---|---|---|
| E / pad A / tap E-button | near free chair | sit |
| E / A | seated, no bong | take bong (`p.bong=1`) |
| E / A | seated with bong, no hit | start hit |
| move keys/stick > 0.3, or roll (Shift, pad RB/LT, 2nd finger) | seated | stand up (cancels hit; seat in hand = LEFT) |
| B (key) / pad X | seated | `deal` (= call Gothica if not called; deal/deal again in idle/done) |
| H / pad Y | seated, your turn | hit |
| T / pad B | seated, your turn | stand (pad B does NOT roll while seated) |
| click/tap panel buttons | | HIT / STAND / DEAL / DONE |
| click CARDS circle / CALL GOTHICA | | call |
| click BONG (E) | sit menu | take bong |
Keyboard B/H/T only when `localSitting()` (8652), ignore repeats. While seated the pad maps ONLY A/X/Y/B (8972-8975). DONE has no key.
Help text strings: `'At the card table', 'B deal,  H hit,  T stand'` (keys), `'X deal,  Y hit,  B stand'` (pad) (8894/8902); page hint 237; lobby footer `'shoot the dummies, have a sit at the table  ·  ...'` (12551).

Floaters (world, 12626 + 8199): bold 13px monospace with 1px black shadow, rise 34 px/s, alive 0.9 s, alpha 1 until 0.6 s then fades.

---------------------------------------------------------------------------------------------------
## 9. Extracted art (`/home/user/Smashed-tv/godot/scripts/lobby_life/art/table/`)

Extractor: `<your scratchpad>/extract_table_art.py`. All are `gymImg('<base64 png>')` (783). All are "2x pixel" art: drawn at 0.5 scale in world px unless noted. None of these are in `godot/assets/manifest.json`.

| file | HTML line | what | px | drawn |
|---|---|---|---|---|
| bong.png | 3489 VAPE_ART.bong | glass beaker bong | 30x52 | 0.5 (15x26), centred at bongRest (156,281) |
| vape.png | 3490 VAPE_ART.vape | Verdavape (steel T-handle) in the stem | 28x40 | scaled to 12 px tall (x0.3: 8.4x12), rotated along stem |
| torch_unused.png | 3491 VAPE_ART.torch | red butane torch — not referenced anywhere | 23x40 | unused |
| torch2.png | 5622 VAPE_ART.torch2 | small green torch (generic-character hit) | 15x30 | 0.5 (7.5x15), flipped to face the tip |
| sit_bong_0_hold.png .. sit_bong_3_blow.png | 3520-3523 SIT_ART[0..3] | Jared on stool with bong: hold / torch / pull / blow | 90x118 each | 0.5 (45x59), bottom-left (p.x-10.5, p.y+18), mirror for chair 2 |
| sit_idle_0_relaxed, _1_breathe, _2_relaxed, _3_look .png | 5183-5186 SIT_IDLE[0..3] | Jared seated, hands on knees (1,2 unused) | 90x118 each | same as SIT_ART |
| trip_mantis_0..3.png | 4997-5000 MANTIS[0..3] | robed mantis, claws working (5 fps) | 169x240 each | screen space, scale 0.22 -> 2.6 |

Gothica's dealing sprites are her normal character art: `godot/assets/CHARS/goth/sprites/*` (front idle while dealing). Jared/juicy standing sprites for other paths are under `godot/assets/CHARS/`.
