# Spec: the mushroom and its trip, the slot machine, the vending machine, the barbecue and esky, and cash

Source: `/home/user/Smashed-tv/Smashed.html` (build b331). `Lnnnn` means a line in that file. Coordinates: x runs across, y runs down the screen (the ground plane), z is height. The arena is 860x520 with an 18-unit wall (`ARENA`, L656). The lobby is 880 tall (`LOBBY_H`); the backyard extends the world to 2003x1998 (`YARD`).
All tuning numbers come from `T` (L280-590), which is also dumped to `godot/data/game_data.json["T"]`. Values below are the defaults.

Several lines in the HTML are very long (base64). Read them with `cut -c1-300`.

---------------------------------------------------------------------------------------------------

## 0. Cash (the player's money)

| what | where | detail |
|---|---|---|
| variable | `p.coins` (integer per player), L721 `coins: 0` in `newPlayer` | It is the only wallet. Slot and vending machine spend it. |
| lobby start | `fillLobby` L745: `p.coins = Math.max(p.coins, T.lobbyCash, T.testCash)`; `addPlayer` L6069 does the same for a joining player 2 | `lobbyCash`=40, `testCash`=2500 ("TESTING… Set 0 before release") |
| run start | `startGame` L13567: `p.coins = T.testCash` | Lobby winnings do not carry over. Also resets `speed`, `magnet`, `food` and coins on the floor (L13560-13597). |
| earning | `payKill` L6486: `n = round(ETYPE.coins * T.coinMult)` (grunt 1, swarmer 1, brute 5, batter 3, L668-672) is added straight to the killer's `coins`, plus a floater `'$'+n` in the player's colour | If nobody owns the kill, the money is split among the living players (L6505-6510, floater colour `#7fd89a`). |
| loose notes | `w.coins[]` objects `{x,y,vx,vy,life,arm,rot,spin,phase,owner?,pull?}`; pickup loop L8243-8285 | Notes fly while `arm>0` and cannot be picked up then. Drag is `0.02^dt`. Pickup happens within `coinGrab` 34 (+1 coin, `SFX.cash()`). Notes are pulled in within `coinMagnet` 95, or within `max(95, magnetRange 460)` while the player has a magnet. Pull strength is `coinPull(900) * boost * (1 - d/reach) * dt`, where boost is 2.4 with a magnet and 1 without. While a note is being pulled its life is kept at least 1.5 s (magnet) or 0.6 s. A note blinks when its `life<2`: it is skipped every other 1/8 s. |
| HUD | L12466-12480 | Each player gets a line `'$' + p.coins` in `bold 17px ui-monospace`, colour `P_COLOURS[id]` (`#e0473f` P1, `#4f9fe8` P2), at x=`ARENA.wall+8`=26, y=`ARENA.wall+46+i*22` (64, 86). The launcher's rocket count `'☢ '+rockets` (or ammo) sits at x=88. The HUD is hidden in the slot's secret room. |
| cash sound | `SFX.cash` L11341 | `sTone(0.07, ~1180Hz±8%, 0, 0.11, triangle)` + `sTone(0.09, ~1760Hz±8%, 0, 0.07, sine)` |
| floaters | `w.floaters` `{x,y,text,t,col}`; update L8199-8203 (rise 34 u/s, removed at t>0.9); draw L12626-12637 | `bold 13px ui-monospace`, centred, with a 1px black 60% shadow. Alpha is 1 until t=0.6, then fades linearly to 0 at 0.9. Capped at 30. |
| banner | `banner={text,until}` L6876, draw L12666-12674 | `bold 34px sans`, centred at (430, `ARENA.wall+72`=90), stroke `rgba(20,22,28,.9)` width 5, fill `#f6d17a`. |

Sound helpers (all synthesised): `sTone(dur,f0,f1,gain,wave)` L11228 is an oscillator with an exponential frequency glide f0 to f1 and an exponential gain decay to 0.0008. `sNoise(dur,freq,q,gain,filterType,sweepTo)` L11213 is looped white noise through a biquad, with the frequency swept exponentially to `sweepTo` and the gain decayed exponentially.

Generic E/action controls: keyboard **E** (L8655 host, L8656 guest), gamepad button 0 (**A**; L8973/8976 `padTap('e')`), touch: the round "carry button". `actKey()` L8882 returns `'A'` if the gamepad was used last, otherwise `'E'`. The carry button (L10111-10137) is a circle at (ARENA.w-62, ARENA.h-18-70-48) = (798, 384), r=34, fill `rgba(20,12,28,.72)`, stroke `#f7a8ff` 2px, with the label in `bold 12px` `#f7a8ff`. It is drawn every frame whenever `lobbyLabel` returns a label (L12443), on desktop too. The label text comes from `lobbyLabel(w,p)` L10089. Its priority order is: Gothica carry > trampoline > **bbqLabel** > gym > sit/bong > bed > rope > wardrobe > arcade > mirror > **'EAT' (mushroom)** > chair > trampoline > bed > pick up.

---------------------------------------------------------------------------------------------------

## 1. The mushroom (SHROOM) and the trip

### 1.1 Constants (L3539-3547)
```js
const SHROOM_SPOT = { x: 52, y: 424 };            // bottom-left of the lounge
const SHROOM_TIME = 30, SHROOM_IN = 2.2, SHROOM_OUT = 2.5, SHROOM_REGROW = 20;
const SHROOM_RW = 288, SHROOM_RH = 174;            // 3D view's internal resolution
const SHROOM_EYE = 62, SHROOM_WALL = 150;          // eye height, wall height (world units; he is 64 tall)
const SHROOM_TOWER = 710;                          // eye height at top of dive tower (20 m)
const SHROOM_CLIMB = 0.16;                         // ladder speed multiplier (~5 s climb)
const SHROOM_BOARD = 350, SHROOM_BOARD_PACE = 0.085; // 10 m board, ~4 s walk
const SHROOM_FALL = 2.6, SHROOM_SPLASH = 1.8, SHROOM_SWIM_EYE = 18;
const SHROOM = { on:false, t:0, clock:0, dive:null, lastDive:0, lastEye:0, ang:0, turn:0, gone:0, last:0,
                 beat:-1, props:null, floor:null, cv:null, chars:new Map(), music:null };
```
Other `SHROOM` fields set later: `sober`, `keepGone`, `lookY` (-0.6..0.6), `look`, `edgeArmed`, `busy`, `hue`, `calm`, `camX`, `boardU`, `walkPh`, `moveK`, `stepD`, `springV`, `springY`, `bob`, `propSig`, `view`, `zbuf`/`occN`/`occT`/`occTop`, `clouds`, `x` (extras cache), `dummy`, `glow`, `legCv`.

**The mushroom is purely local per screen.** It is never networked. Each player (host and guest) has their own mushroom and their own trip, and the other player keeps seeing the normal top-down lobby. It exists only in the lobby with the lounge floor on (`T.loungeFloor`=1).

### 1.2 Presence, respawn and state machine
- The clock is `shroomNow() = performance.now()/1000` (real seconds, not sim time).
- `shroomHere()` L3549 returns `!SHROOM.on && now >= SHROOM.gone`. `gone` starts at 0, so the mushroom is there from the start.
- `shroomNear(p)` L3550: p is alive and not diving, sitting, lifting, on the leg press or in bed, `T.loungeFloor` is on, and `hypot(p - SHROOM_SPOT) < 26`.
- The label is **'EAT'** (lobbyLabel L10102, when `shroomNear && shroomHere`). The bottom-right button shows `EAT`.
- **E (keyboard, pad A, carry-button tap)**: `shroomTryEat()` L3551 is called first in the E handler, before every other lobby action (L8655/8656/8743).
  - If a trip is on (not sober), it returns true and swallows E. **While tripping, E does nothing else.**
  - If the run has started, the game is over, calibration is on, or the mushroom is not here or not near, it returns false.
  - Otherwise it starts the trip: `on=true, t=0, clock=0, gone=Infinity`, `ang = atan2(me.fy, me.fx)` (or -π/2 when facing is 0), clears the character cache and calls `shroomMusic(true)`.
- **States:** `OFF(present)` → E → `TRIP(t: 0→30)` → `endShroom()` → `OFF(absent, gone=now+20)` → after 20 s real time → `OFF(present)`.
- `endShroom()` L3563: sets `on=false`, clears props, floor and dive, clears touch fingers. Then:
  - Trip: `gone = now + SHROOM_REGROW (20 s)` and `shroomMusic(false)`.
  - Sober (plain first person): `gone = keepGone` (the mushroom is left as it was), `lookY=0`, releases the pointer lock and updates the button label.
- **The trip ends when** (in `drawShroom` L4271/4279):
  - `trip >= SHROOM_TIME (30)`, or
  - immediately, if `w.started || w.over || cal.on || !me || !T.loungeFloor` (starting a run ends it).
- **Two clocks** (L4272-4278):
  - `clock` always advances by dt and drives colours, the beat, music and wobble.
  - `SHROOM.t` ("trip") advances by dt unless you are **on the tower** (`me.dive` is CLIMB, BOARD or FALL, or the trip-only dive animation `SHROOM.dive` is running) **and** `t >= 30-2.5-0.2 = 27.3`. In other words, the trip clock never runs out while you are up the tower or falling; it holds just before the come-down.
  - dt is `min(0.1, real dt)`.
- Fade: `ease(f)=f²(3-2f)`.
  - `fade = t<2.2 ? ease(t/2.2) : t>27.5 ? ease((30-t)/2.5) : 1`.
  - `amp = sober ? 0 : 0.4 + 0.6*fade` ("how hard it's hitting").

### 1.3 Sober vs trip (plain first person, "V")
`toggleFirstPerson()` L3574 is bound to **V** (L8628), the HTML button `#fpBtn` (L135, label `'First person (V)'` / `'Top-down view (V)'`, L3591), and a touch "eye" button (`fpButton()` = zoom button + 40 down, r=16, L3592; drawn L3621-3630).
- It uses the same renderer with `sober=true`: `t` is pinned at `SHROOM_IN+1`, `amp=0`, `hue=0` and `calm=1`. There are no colours, wobble, music, trip clock or rainbow timer bar. It stays on until toggled off.
- V does nothing mid-trip ("the mushroom's in charge"). Eating the mushroom while sober is impossible: `shroomTryEat` returns false when `SHROOM.on && sober`, so E falls through to normal actions.
- Sober only:
  - Pointer lock: a click captures the mouse (`fpLock`), and Esc releases it. While unlocked, the text `'click to look around with the mouse'` is shown (bold 13px, `#f6d17a`, at the centre, y-18).
  - Mouse-edge turning (edge 12% of the width, `2.4*edge` rad/s).
  - Look up/down with `lookY` (mouse Y `*0.0035`, arrow up/down at 1.6/s, right stick Y; clamped to ±0.6). This is added to the pitch.
  - Blue sky (`rgb(120-70sv,170-70sv,235-40sv)`), grey ceiling (96,92,88 × shade), daylight and haze outside (mix toward (204,218,232) by `min(.5, dist/3200)`), proper textures (`fpMaterial`), roofs.
  - The E hint under the crosshair: `actKey()+': '+label.toLowerCase()` (bold 15px, `#f7a8ff`, at y+32) plus the carry button.
  - Hotbar, controls help, the eye button and **`shroomWords`** (floaters and Gothica's speech bubble placed in 3D). In the trip these are **not** drawn: the whole block L4905-4928 is inside `if (sober)`.
  - `fpBusy()` L3587 (arcade, Mega Drive, shirt editor, mirror, sitting, bed, bench, leg press): first person steps aside to the top-down view until you are done.

### 1.4 Controls during the trip (`shroomInput` L3706, called from the input build L9033)
- For the first `SHROOM_IN*0.5 = 1.1 s` the normal top-down controls apply.
- After that, inputs are remapped relative to the view angle `a = SHROOM.ang`:
  - Movement: `fwd = -inp.my`, `side = inp.mx`, giving `mx = fwd*cos a + side*(-sin a)` and `my = fwd*sin a + side*cos a`. So W/S walk, A/D strafe, and the gamepad left stick or touch stick does the same.
  - Aim is always straight ahead: `ax,ay = (cos a, sin a) * reach`, where `reach = clamp(lobDefault(220)*(1 - lookY*1.4), 60, lobFar(400))` (look up to throw further).
  - Shoot: mouse button, gamepad button 7 (RT) or the touch FIRE button. Touch aiming via aimStick disables the mouse shot.
- **Turning:**
  - Mouse `movementX * 0.0045` rad/px. This works without pointer lock while tripping (L3672).
  - Arrow keys ±2.4 rad/s, unless local player 2 is using them (two local players and no network).
  - Touch aimStick `dx*2.8` rad/s.
  - Gamepad right stick `x*|x|*3.2` rad/s (deadzone 0.18).
  - Touch: a finger on the right half drags, with `turn += dx*0.0075` and `lookY += dy*0.004` (L8753, L8789).
- Touch UI (`fpTouchShown`): the FIRE button at (ARENA.w-155, ARENA.h-115) = (705, 405), r=40 (L3595, drawn L3600-3618) with a crosshair icon and the label 'FIRE'; the trampoline JUMP button; the left move stick. For the first 6 s of `clock`, hints `'thumb here to walk'` (x=215) and `'drag here to look'` (x=645) are drawn at y=156 in `#f6d17a`, bold 14px, fading over 1.5 s.
- Dive tower in first person (trip or sober):
  - On the ladder (CLIMB), W climbs at 0.16× speed and S goes down.
  - On the BOARD, W walks out at 0.085× pace, and S at the ladder end climbs back.
  - While falling, all input is zeroed.
  - The view angle is locked: -π/2 on the ladder, 0 on the board and fall, eased at `min(1, dt*6)`.
  - Tips (bold 14px white with a shadow, at y=ARENA.h-97, or y=40 on the board): `'face the ladder and hold W to climb'`, `'W: up   S: down'`, `'walk off the end, or Shift to dive'`.

### 1.5 What the trip looks like (`drawShroom` L4267-4929)
A full-screen **first-person raycast of the lobby (and yard)**, rendered at **288×174** internal pixels and scaled up with nearest-neighbour. It is drawn over the already-rendered top-down frame (calls at L12815 host and L12763 guest, before `drawTrip()`).

**Camera:**
- FOV 66° horizontal, `proj = 144/tan(33°)`.
- Eye height 62 (on the trampoline `62+dz`; swimming 18; on the tower it interpolates from 62 up to 710 by `dz/deckH`).
- Pitch only slides the horizon: `hor = RH/2 - proj*tan(pitch)`. Above the wall height while on the tower or falling (`tp`), every pixel is cast properly instead.
- Position = the player's x,y.

**Layers, back to front:**
1. **Floor (rows below the horizon)**
   - The source is the floor picture `fpFloor()` L3978: the yard art plus the lounge art plus the bedroom art, 1 px = 1 world unit.
   - It is sampled at warped coords: `ux = wx + sin(wy*.045 + t*2.1)*warp`, `uy = wy + cos(wx*.04 + t*1.7)*warp`, with `warp = 7*amp*(1-.7calm)`.
   - The sample is blended with the rainbow LUT (`SHROOM_LUT`, 256-step hue wheel, L3728) by `mix = (0.3+0.2 sin(1.3t))*amp*(1-.8calm)`, LUT index `((ux+uy)*.9 + dist*.6 + t*120) & 255`, times `shade = min(1, (260+eye*1.2)/(dist+60))`.
   - Outside the picture: a dark swirl, `LUT[((sin(ux*.02+t)+sin(uy*.025-1.2t)+2)*55 + t*60) & 255] * 0.22`.
   - Inside the pool rect (`POOL` 624,90–815,239, inset 8): rainbow ripples, `ring = sin(hypot(ux-pcx, uy-pcy)*.12 - 5t)*.5+.5`, mixed toward water blue as `calm` rises.
2. **Ceiling (rows above the horizon, indoors)**: a slow plasma, `sin(wx*.025+t) + sin(wy*.03-1.3t) + sin((wx+wy)*.018+.7t)` mapped into the LUT, at brightness `shade*(0.55+0.25amp)`. Outdoors it is the sky: rainbow bands `LUT[(sv*260 + x*.35 + sin(x*.05+t)*18 - t*90)&255]`. Near the roofline (eye > 100) the ceiling crossfades to sky.
3. **Walls**, column by column (`fpCast`)
   - Every wall in the trip is the same melting rainbow:
     - `li = (u*.9 + v*180 + t*180)&255`.
     - Dark bands: ×0.45 when `frac(u*.08 + v*7 - 2.5t) < .28`.
     - `shade = min(1, 220/(d+40)) * (side ? .85 : 1) * (0.8 + 0.4*pulse)`.
   - Column melt (vertical wobble): `sin(x*.07 + 2.3t)*5*amp + sin(x*.023 - 1.1t)*4*amp` on the top edge, and half of it on the bottom edge.
4. **Billboard sprites ("Doom-style cut-outs")**, sorted far to near and clipped per column by occluders:
   - Furniture captured once (`shroomCapture` L4034): the tower, gym bench, plate rack, leg press, table, rope, arcade cabinets, slot machine (`SLOT_IMG.idle_a` at h=92*slotScale), vending machine (only in a run, so never here), wardrobe and mirror. They are re-captured when the wardrobe, bar or plates change.
   - Other players and Gothica: re-rendered off-screen every 100 ms at 150×180, turned to face you (`shroomCharacter` L4145).
   - Dummies (procedural 30×50 canvas), bullets (16×16 glow, shown only beyond 70 units), cans, potato plants, thrown potatoes, rockets, blasts, ducks, thrown Gothica (`shroomExtras` L4096), and the **barbecue flames (glow sprites) and smoke puffs** (`fpPuff`).
   - Aim ring for the launcher or lob.
5. **Gun flash** (when blasters are not shown), the ladder rails (rainbow `hsl` rungs) on CLIMB, and **rainbow clouds** when high (18 clouds, z 420-940, drifting +14 u/s).
6. **Psychedelia** (L4843-4852):
   - **Trails**: the `acc` buffer is not cleared. Each frame the new view is drawn over it at alpha `0.35 + 0.35*(1 - 0.6amp)` (0.3 while somersaulting).
   - **Double vision**: two extra copies offset ±`8*amp` internal px horizontally, composite `lighter`, alpha `0.12*amp*(1-.6calm)`.
   - **Hue rotation**: `hue += dt*45*(1-.85calm)` degrees (360 wraps). The `acc` layer is drawn through `filter: hue-rotate(hue) saturate(1.3+0.5amp-0.3calm)`. Water and grass get a counter-rotated colour (`hueFix`) so they read blue and green when calm.
   - `calm` eases (rate 3/s) toward 1 on the ladder or board (not falling), otherwise toward 0. Up the tower the colours calm down.
7. **Fade in/out (spiral)** while `fade<1`:
   - The pre-trip top-down frame (`under`, grabbed while t<2.3 or t>27.4) is drawn rotated `fade*1.4` rad, scaled `1+1.5*fade`, alpha `1-fade`.
   - The trip view is drawn rotated `(1-fade)*-1.2` rad and scaled `0.4+0.6*fade` about the screen centre, at alpha `fade`.
   - So the lobby spirals away while the 3D view spirals in, and the reverse on the come-down.
8. **Overlays**, not hue-shifted:
   - The board and feet when on the board (`drawBoard`/`drawFeet`; boots from `BOOT_PIX`).
   - **The blasters in your hands** (`drawFpGuns` L4234) when the weapon is the blaster and you are not diving. The left gun is `FP_BLASTER` art tinted to your character's skin; the right gun is its mirror. Each is drawn at height `CH*0.44`, x at 0.335 W (left gun's right edge) and 0.665 W (right gun's left edge). They bob with the walk, recoil alternately and draw a muzzle flash; tracers fly to the crosshair in 110 ms.
   - **A snag in hand** if `me.food` (see §4).
   - Crosshair: white 80%, 1.5 px, arms from 2 to 7 px around the centre.
   - **Trip timer**: a 3 px rainbow gradient bar along the top, width `ARENA.w*(1-t/30)`, with stops `hsl(i*60 + t*120, 100%, 60%)`.
- **Beat:** `bpm` const = 0.21 s per beat. `pulse = (1 - (t%0.21)/0.21)^3` (0 when sober) brightens the walls.

**Dive from the tower during the trip** (screen-only embellishment, L4383-4400, `shroomSplash` L4931, `drawShroomSplash` L4948):
- Leaving BOARD state starts `SHROOM.dive` (2.6 s). The eye drops `h0 → 18` with `f²`. Position lerps to the actual pool position. Two forward somersaults: the pitch rotates through 4π, and in the "over the top" half the view is drawn flipped 180°.
- Sound at start: `sNoise(2.6, 250, 2, .35, bandpass, →2600)` + `sTone(.2, 300→700, .1, triangle)`.
- At 2.6 s: splash. If you are in water (`me.dive===SWIM` or `inWater`):
  - Visuals: a white-to-rainbow radial flash for 0.35 s; 7 rainbow elliptical rings expanding (`r = 20 + rt*520`, ry = 0.45r); 160 rainbow spray drops (gravity 900); an underwater hue wash plus 45 rising rainbow bubbles from st 0.1 to 1.3; the screen ripple distortion (horizontal band offsets `sin(y/VH*18 + 9t)*2% W`); a white flash at the surface at st 1.2-1.5.
  - Sound: `sNoise(1.3,1600,.7,.65,lowpass→160)`, `sNoise(.5,4000,1,.3,highpass→1500)`, `sTone(.35,150→45,.35,sine)`, and an arpeggio of 1.1 s triangles at `392·2^(n/12)` for n ∈ [0,4,7,11,14,19], starting at 120 ms and spaced 80 ms apart.
  - If you are not in water: a 0.4 s white flash, plus `sNoise(.3,300,1,.5,lowpass→60)` and `sTone(.25,120→40,.3,square)`.
- Ends at 2.6+1.8 = 4.4 s.
- Board footsteps every 30 units: `sNoise(.06,350,1.2,.18,lowpass→120)` + `sTone(.16, 190-50bu → 140-40bu, .045, sawtooth)`, with a board spring and sag.

### 1.6 Words
- The trip itself shows no words besides the tower tips, touch hints and the button labels above.
- `shroomWords` (floaters such as `+$`/`YUM!` and Gothica's speech bubble placed at their 3D positions, hidden behind walls) only runs in sober first person (L4925).
- The carry button is not drawn in the trip view. The trip covers the whole screen, and the top-down HUD drawn underneath is cleared (`ctx.clearRect`).

### 1.7 Music (`shroomMusic` L3649) and beat
- **On:**
  - The output gain ramps exponentially 0.0001 → 0.9 over 2 s into `SND.master`.
  - The drone goes through a lowpass at 900 Hz, Q 6, with its cutoff modulated by an LFO at 0.3 Hz, depth ±600 Hz.
  - Oscillators `[98 saw .09], [98.9 saw .09], [147 triangle .08], [196.4 sine .06]`, each with vibrato at 0.4-0.9 Hz (random), depth 1.2% of its frequency.
  - Plus a whoosh up, `sNoise(1.8, 200, 4, .3, bandpass, →3200)`.
- **Off:** an exponential fade to 0.0001 over 2 s, oscillators stopped at +2.1 s, and a whoosh down `sNoise(1.6, 3000, 3, .25, bandpass, →200)`.
- **Arpeggio** (from `drawShroom` L4305-4309): every 0.21 s beat, when not sober, sound is on and fade>0.2.
  - Note `n = [0,3,5,7,10,12,15,17][(beat*3 + (beat>>3)) % 8]`.
  - `sTone(0.3, 196·2^(n/12), ×1.004, 0.045*fade, beat%4 ? 'triangle' : 'square')`.
- Sober mode has no music.

### 1.8 The pickup on the floor (`drawShroomPickup` L3632, called in lobby props L11911)
- Drawn only when `!w.started && !cal.on && T.loungeFloor && shroomHere()`.
- At x=52, y=424, `bob = round(sin(now*2.2))` px. Drawn in world units:
  - **Glow**: a radial gradient centred (x, y-6), r 2→22, colour `hsla((now*90)%360, 100%, 70%, 0.35+0.15 sin(3 now))` fading to transparent. It fills the rect (x-22, y-28, 44, 44).
  - **Shadow**: an ellipse at (x, y+1), radii 8×3, `rgba(0,0,0,.3)`.
  - **Stem**: `#e9dcc0` rect (x-3, y-8+bob, 6, 9), with its left 2 px shaded `#c8b894`.
  - **Cap** in `#b3202a`: (x-9, y-12+bob, 18, 5), (x-7, y-15+bob, 14, 3), (x-4, y-17+bob, 8, 2).
  - **Highlight**: `#e0414a` (x-6, y-15, 8, 2).
  - **Underside line**: `#7c141c` (x-9, y-8, 18, 1).
  - **Spots**: `#fff6ea` at (x-5, y-13, 2×2), (x+2, y-15, 2×2), (x+5, y-11, 2×2), (x-8, y-10, 2×1).
- Pre-rendered without glow or bob: `art/machines/shroom_pickup.png` (18×19, anchor pixel (9,17) = SHROOM_SPOT, scale 1).

### 1.9 Not to be confused with
`TRIP` / `drawTrip()` (L4991+, "THE TRIP", the mantis) is the *bong* trip (two hits within 30 s while seated). It is a separate feature.

---------------------------------------------------------------------------------------------------

## 2. The slot machine

### 2.1 Tunables (T)
| key | value | meaning |
|---|---|---|
| `spinCost` | 5 | dollars per pull |
| `spinTime` | 1.6 | seconds the reels turn (player rooted) |
| `spinCool` | 8 | seconds before the next pull |
| `slotScale` | 1.35 | cabinet drawn height = 92*1.35 = **124.2** |
| `slotDrop` | 38 | y = `ARENA.wall + 54 + slotDrop` = **110** |
| `reelScale` | 1.9 | reel window blow-up |
| `slotRadius` | 46 | use distance |
| `loungeSlotX` | 90 | x in the lobby (with the lounge floor) |
| `magnetTime` 14, `magnetRange` 460, `magnetBonus` 1 | | cash magnet |
| `speedTime` 10, `speedMul` 1.55 | | speed boost |
| `overheal` 6, `playerHp` 5 | | health prize cap = 11 |

**Position** (`calls.slot` = {x:90, y:110}): L8194-8195 recomputes it every step. `y = 18+54+38 = 110`. `x = 90` in the lobby (`!w.started && T.loungeFloor`), otherwise `ARENA.w*0.5 = 430` in a run. It is not solid. The two arcade cabinets stand beside it on the lounge's top wall (L2489-2503, `cabY()` = slot y + 6).

### 2.2 State
- `w.slot` (L6048): `{ x, y, flash:0, sym:0, cool:0, busy:-1, broken:false, prize:null, decoy:[0,0] }`. The host owns it. It is networked as `sl:[x, y, flash*100, cool*10, prizeIndex, decoy0, decoy1]` (L8332).
- Player fields: `p.spin` (seconds left, >0 while spinning), `p.speed` (seconds), `p.magnet` (seconds), `p.coins`.

### 2.3 Use: no E. Stand still to play (`stepPlayers` L7275-7287)
```js
if (!w.over && !w.slot.broken && w.slot.cool <= 0 && w.slot.busy < 0
    && inp.mx === 0 && inp.my === 0 && p.coins >= T.spinCost
    && Math.hypot(p.x - w.slot.x, p.y - w.slot.y) < T.slotRadius) {
  p.coins -= T.spinCost; p.spin = T.spinTime; w.slot.busy = p.id;
  w.slot.prize = pickPrize(w);                                    // decided up front
  w.slot.decoy = [floor(rnd*6), floor(rnd*6)];
}
```
- **While spinning** (L7229-7239): `p.spin -= dt`. Velocity decays by `0.001^dt`. Input, shooting, rolling and weapon switching are all ignored (`continue`).
- **When `p.spin` reaches 0:** `w.slot.cool = spinCool (8)`, `busy = -1`, then `award(w, p, prize)`.
- `slot.cool` counts down in the world step (L8240). `slot.flash` decays by 1/s (L8197).
- If the spinner dies or leaves mid-spin, `busy` is released (L7681, L7831).
- **States:** `READY` → (stand still in radius, ≥$5) → `SPINNING 1.6s` → award, `flash=1` → `COOLDOWN 8s` → `READY`. Also `BROKEN`:
  - At run start (L13595) the machine is `broken=true` with `sign='stand'`.
  - The janitor comes after wave `janitorWave` (1), in the breather, and fixes it (L7860-7990). This sets `broken=false`, `flash=0.9` and the banner `'MACHINE IS LIVE'`.
  - In the lobby the machine works (`newWorld` sets broken false). The run-only janitor and the secret room (`beginSlotSecret`, L13805) are out of scope.

### 2.4 Prizes and odds (`PRIZES` L624-633; `pickPrize` L6271 is a weighted pick with total weight 18)
| key | label (banner) | weight | odds | reel symbol | effect (`award` L6278) |
|---|---|---|---|---|---|
| blasters | `REAL GUNS!` | 3 | 16.7% | 1 shotgun | `giveWeapon(p,'blaster')` (permanent). If you already have blasters, `ammo = min(spudMaxAmmo 200, ammo + spudPellets*2 = 20)` instead. |
| shotgun | `SHOTGUN!` | 3 | 16.7% | 1 shotgun | `giveWeapon(p,'shotgun')`, which lasts `shotgunTime` = 12 s (run only; the timer only ticks when `w.started`) |
| health | `+2 HEALTH` | 3 | 16.7% | 0 heart | `hp = min(playerHp + overheal = 11, hp + 2)`. Extra hearts show as gold pips. |
| speed | `SPEED BOOST` | 2 | 11.1% | 3 bolt | `p.speed = 10`. The max speed is ×1.55 while `p.speed>0` (L7511). Drawn as a green ellipse under the player: `rgba(111,211,160,.5)`, 2 px, at (x, y+radius*0.85), radii radius*1.3 × radius*0.6 (L12414-12418). |
| clear | `SCREEN CLEAR` | 1 | 5.6% | 4 star | A nuke falls at the arena centre (`w.nuke = {x:430, y:260, t:0, phase:'fall'}`) with the falling whistle `startWhistle(T.nukeFall=1.9)` |
| cash | `JACKPOT!` | 2 | 11.1% | 2 coin | 18 notes burst from the machine at angles `i/18*2π + rnd*0.3`, speed 420-760, `life = coinLife+4 = 10`, `arm = 0.85` (can't be grabbed while flying), random rot and spin |
| magnet | `CASH MAGNET!` | 2 | 11.1% | 2 coin | `p.magnet = 14`. The pickup reach becomes 460 and the pull ×2.4. Each kill drops `magnetBonus` (1) extra loose note owned by the killer (L6490-6500). A ring of radius `460*0.5*pulse` (pulse = 0.88+0.12 sin(1.7t)) is drawn round the player in `rgba(246,209,122,.28)`, 2 px (L12404-12412). |
| bust | `BUST!` | 2 | 11.1% | 5 skull | A **brute** enemy (type 2) spawns 90 units from you in a random direction: `{t:2, hp:eMaxHp(2), spawn:0.6, ...}` |

- Note that `speed` and `magnet` only count down when `w.started`, so in the lobby they last until the run starts. Run start sets both to 0.
- Every award sets `banner = {text: label, until: now+1600 ms}` and `w.slot.flash = 1.0`.
- `giveWeapon` (L6878) also sets the banner to the weapon name + '!' for non-spud weapons, so a new blaster shows `'BLASTERS!'` (name `'blasters'`) and the shotgun `'SHOTGUN!'`. That call comes after `award` sets its banner, so the weapon name is what you see. If you already have blasters, REAL GUNS only gives ammo and keeps the `'REAL GUNS!'` banner.
- No weapon other than blasters and shotgun comes from the slot.

### 2.5 Drawing (L12052-12153)
**Cabinet sprite:**
- Key: `'win'` if `flash>0.001`, else `'spin'` if anyone is spinning, else alternate `idle_a`/`idle_b` at 3 Hz (`floor(w.t*3)%2 ? idle_b : idle_a`).
- Size: `h = 92*slotScale = 124.2`, `dw = h*89/128 ≈ 86.4`.
- Top-left: `(round(x - dw/2), round(y + 6 - h))`. The feet are at y+6.
- Nearest-neighbour filtering.
- Shadow: an ellipse at (x, y+4), radii `dw*0.4 × 7`, `rgba(0,0,0,.35)`.
- Alpha 0.55 while cooling down (not spinning, no flash), or 0.38 when broken.

**Live reels**, shown while someone spins or while flash>0:
- `rw = dw*0.16*1.9`, `rh = h*0.115*1.9`, `cy = sy + h*0.503`.
- Columns: `mid = dw*0.525`, `cols = [mid + (dw*.40 - mid)*1.9, mid, mid + (dw*.65 - mid)*1.9]`, offset from sx.
- The backing panel is `rgba(12,13,18,.92)` with padding `padX = rw*.22`, `padY = rh*.3`, and a 2 px stroke: `#f6d17a` while flashing, else `#4b5468`.
- Each reel window is filled `#f2efe6` and clipped.
- `frac = 1 - spin/spinTime`. Reel i stops at `[0.45, 0.70, 1.0][i]`.
- While turning: symbols scroll upward at 420 px/s (`off = (w.t*420)%rh`). The symbol is `(k + i*2 + floor(w.t*9)) % 6` for k = -1..2, at size `rh*0.8`, covered by 55% `#f2efe6` haze.
- When stopped:
  - Reel 2 (and every reel while flashing) shows `prize.sym`.
  - Reels 0 and 1 show `decoy[i]` (which may equal the prize symbol by chance).
- **Symbols** (`drawSym` L11862, unit u = size/10, centred):
  - 0 heart: `#e0473f`, two circles r 2.4u at (±2u, -u) plus a triangle down to +4.4u.
  - 1 shotgun: barrel `#4a5260` (-4.5u, -1.2u, 8u×2.2u), stock `#8a5a33` (+2.5u, -1.6u, 2.5u×3.2u).
  - 2 coin: circle r 3.6u `#d9a520`, inner r 2.4u `#f6d17a`.
  - 3 bolt: `#6fd3a0` polygon.
  - 4 star: `#f6d17a`, 5-point, r 4u / 1.7u.
  - 5 skull: `#cfd4de` circle r 3.4u plus a jaw (4u×2.2u), eyes `#14161c`.

**Cooldown bar:** when `cool>0`, a 56×5 bar at (x-28, y+12). Background `rgba(20,22,28,.75)`, fill `#5a6274` of width `56*(1 - cool/8)`.

**Spin ring on the player** (L12347-12354): a `#f6d17a` 3 px arc of radius `T.radius + 14` from -90° sweeping `frac*360°`.

**Prompt** under the machine for the nearest alive player within 46 who is not spinning (bold 13px sans, centred at (x, y+28)):
- `'OUT OF ORDER'` (`#8b93a4`) if broken.
- `'recharging — ' + cool.toFixed(1) + 's'` (`#8b93a4`).
- `'need $5'` (`#8b93a4`) if coins < spinCost.
- else `'$5 PLAY — stand still'` (`#f6d17a`).
- The dash in these strings is an em dash (U+2014).

**Art** (`SLOT_SPRITES`, data URIs at L9447; manifest key `SLOT_SPRITES`): `godot/assets/SLOT_SPRITES/{idle_a,idle_b,spin,win}.png`, each **89×128**, drawn at 124.2/128 = **0.970×**. Copies are in `godot/scripts/lobby_life/art/machines/slot_{idle_a,idle_b,spin,win}.png`. The cabinet is neon purple and teal, with a "SMASHED" marquee, three reel windows (cherries, 7 and bar) and a lever on the right.

**First person:** the cabinet appears as a static cut-out of `idle_a` (`shroomCapture` L4048).

### 2.6 Sounds
The machine has no sound of its own (no spin or win jingle). The prizes have their own sounds: the nuke whistle for clear, `SFX.cash` per note picked up, and the weapon-switch tone. The only machine audio is the janitor or secret-room sequence (out of scope).

---------------------------------------------------------------------------------------------------

## 3. The vending machine (nuke launcher)

### 3.1 Tunables
| key | value | meaning |
|---|---|---|
| `vendShow` | 1 | on |
| `vendX` | 0.82 | run: x = 860*0.82 = **705.2** |
| `loungeVendX` | 235 | lobby x (unused: see `vendHere`) |
| `vendDrop` | 82 | y = 18+54+82 = **154** |
| `vendHeight` | 150 | drawn height |
| `vendPrice` | 2500 | price |
| `vendRadius` | 56 | read and buy distance |
| `vendHold` | 0.8 | seconds standing still to buy |
| `launcherRounds` | 3 | rockets you get |

```js
function vendHere(w) { return T.vendShow && !!(w && w.started); }       // L753: RUN ONLY (b215)
function vendPos(w) { const lobby = w && !w.started;
  return { x: lobby ? T.loungeVendX : ARENA.w * T.vendX, y: ARENA.wall + 54 + T.vendDrop }; }
```
`calls.vendPos` = {235, 154} is the lobby value. **The machine is not present in the lobby at all**: it is neither drawn nor buyable. It appears only in runs, at (705.2, 154). It is not solid.

### 3.2 State
- `w.vendSold` (L6042): true once bought during the current run wave, and "restocks when the next one starts". The lobby never sells out. Networked.
- `p.buy`: hold-timer seconds. `p.rockets`, `p.prevWeapon`, `p.dump`.

### 3.3 Hold to buy, with no E: stand still (L7251-7272)
```js
const canBuy = vendHere(w) && !w.over && !w.vendSold && !secretActive(w)
  && p.weapon !== 'launcher' && p.coins >= T.vendPrice
  && inp.mx === 0 && inp.my === 0 && !inp.shoot
  && Math.hypot(p.x - vp.x, p.y - vp.y) < T.vendRadius;
if (canBuy) { p.buy += dt; if (p.buy >= T.vendHold) {
    p.buy = 0; p.coins -= T.vendPrice; if (w.started) w.vendSold = true;
    p.prevWeapon = p.weapon; giveWeapon(p, 'launcher'); p.cooldown = 0.35;
    w.floaters.push({ x: vp.x, y: vp.y - 40, text: '-$' + T.vendPrice, t: 0, col: '#e0473f' });
    sTone(0.08, 500, 900, 0.2, 'square'); sTone(0.25, 90, 60, 0.3, 'square'); } }
else p.buy = 0;     // moving, shooting, or leaving resets the hold
```
- `giveWeapon('launcher')` sets `rockets = 3` and the banner `'NUKE LAUNCHER!'` (the weapon name uppercased + '!', 1.4 s).
- When the rockets run out (`p.dump`): after a beat the weapon reverts to the blaster (if owned) or the spud, with the banner `'EMPTY!'` and `sTone(.05, 700→300, .15, square)` (L7243-7250).
- **States:** `IDLE` → (conditions met) `HOLDING buy: 0→0.8 s` → `BOUGHT` (`vendSold=true`, sprite `sold`). Any break of the conditions resets `buy=0`.

### 3.4 Drawing (L12013-12050)
**Sprite:**
- Key: `w.vendSold ? 'sold' : (floor(w.t*2.5)%2 ? 'idle_b' : 'idle_a')`, so it blinks at 2.5 Hz.
- `h = 150`, `dw = 150*176/300 = 88`. Top-left `(round(x - dw/2), round(y + 6 - h))`. Nearest-neighbour.
- Shadow: an ellipse at (x, y+4), radii `dw*.45 × 7`, `rgba(0,0,0,.35)`.

**Text** for the first alive player within 56, not shown when the game is over (centred at x):
- Line 1 (bold 13px, y+28): `'NUKE LAUNCHER — $2500'` in `#f6d17a`, or `'SOLD OUT — back next wave'` in `#e0473f`.
- Line 2 (12px, y+44), only if not sold:
  - `'you’ve already got one'` (`#8b93a4`) if holding the launcher.
  - `'you’re $' + short + ' short'` (`#8b93a4`).
  - else `'stand still to buy'` (`#9be29b`).
  - The apostrophes are U+2019.
- Buy progress bar while `buy>0`: 70×6 at (x-35, y+50), background `rgba(20,22,28,.8)`, fill `#9be29b` of width `70*buy/0.8`.

**Art** (`VEND_SPRITES` L9435; manifest key `VEND_SPRITES`): `godot/assets/VEND_SPRITES/{idle_a,idle_b,sold}.png`, each **176×300**, drawn at **0.5×** (150/300). Copies are in `godot/scripts/lobby_life/art/machines/vend_{idle_a,idle_b,sold}.png`. The cabinet is military green with hazard stripes and a radiation sign, a launcher behind glass, a red LED price "$2500", a "3 ROUNDS INCL" plate, a coin slot and a red button.

**First person:** a cut-out of `idle_a` at height 150 (only if `vendHere`, so in practice never, since first person is lobby-only).

**Sound:** only the purchase chirp and thump above.

---------------------------------------------------------------------------------------------------

## 4. The barbecue and esky (backyard deck)

Lobby only, and only when `lobbyTall(w)` is true: `!w.started && T.loungeFloor && !cal.on && !secretActive(w)` (L1979). The yard art (`YARD_IMG`, manifest `YARD_IMG@1985` → `godot/assets/misc/line1985_0.webp`, laid at offset (-45,-50), 1 px = 1 unit) already shows the barbecue body and table. The code draws the live hotplate, knobs, smoke and esky over it.

### 4.1 Geometry (L2008-2009, L2041-2047)
```js
YARD_SOLIDS: { x0:488, y0:566, x1:618, y1:634, h:36, m:'bbq' },   // the barbecue body (solid, 36 tall in FP)
             { x0:488, y0:690, x1:520, y1:712, h:22, m:'esky' },  // the esky (solid, 22 tall)
const BBQ = { x0:522, y0:634, x1:626, y1:692,              // where you stand to use it (in front)
  top: { x0:523, y0:524, x1:583, y1:554 },                  // hotplate as drawn top-down (60x30)
  fp:  { x0:520, y0:576, x1:586, y1:622 },                  // hotplate footprint in first person
  rate: [0, 0.055, 0.1, 0.17] };                            // cook rate per second at heat 0..3
const ESKY = { x: 504, y: 701 };
bbqNear(p)  = p inside BBQ rect (strict);   eskyNear(p) = hypot(p - ESKY) < 42
```

### 4.2 State (host-owned, networked)
- `w.bbq = { heat: 0, s: [-1,-1,-1,-1] }` (L6045).
  - `heat`: 0 off, 1 low, 2 medium, 3 high.
  - `s[i]`: the doneness of the snag in hotplate place i (-1 = empty; 0 raw → 1 cooked → 2 max).
  - Snapshot (L8367): `bq: [heat, ...s.map(c => c<0 ? -1 : round(c*100))]`.
- `p.food` (snapshot L8363): 0 none, 1 raw snag, 2 cooked, 3 burnt. It is cleared at run start (L13564).

### 4.3 Labels (`bbqLabel` L2048), checked before every other lobby label
Returns null unless the bbq exists, the player is alive, not in a run, `lobbyTall`, and not on the trampoline, in the air, seated, in bed or diving. Otherwise:
```
if bbqNear(p):
   food==1           -> 'COOK'       (only if an empty place exists; else null and fall through)
   food==0           -> 'TAKE SNAG'  if any s>=1, else ['LIGHT','TURN UP','TURN UP','TURN OFF'][heat]
   (food 2/3 at the bbq: falls through)
if eskyNear(p):  food==0 -> 'GRAB SNAG';  food==1 -> 'PUT BACK'
if food>=2:      food==2 -> 'EAT', food==3 -> 'EAT IT?'     (anywhere)
```
- Label shown: the carry-button text (as above, UPPERCASE). In sober first person it is also shown as `'E: take snag'` etc. (lowercase) under the crosshair.
- Control: **E** / pad **A** / tap the carry button.
- The guest's E is sent as a request (`SITREQ`) and the host runs `lobbyAction(w, p)`, which calls `bbqAction` first (L10147).

### 4.4 Actions (`bbqAction` L2058)
| label | effect |
|---|---|
| `LIGHT` / `TURN UP` / `TURN OFF` | `heat = (heat+1) % 4`, cycling off → low → medium → high → off |
| `COOK` | the first empty place `s[indexOf(-1)] = 0`; `food = 0` |
| `TAKE SNAG` | picks the cooked snag (s≥1) with the **highest** s (the one nearest burning); `food = s ≥ 1.6 ? 3 (burnt) : 2 (cooked)`; that place becomes -1. Raw snags (s<1) can't be taken back off. |
| `GRAB SNAG` | `food = 1` (the esky is infinite) |
| `PUT BACK` | `food = 0` |
| `EAT` / `EAT IT?` | `food = 0`; floater at (p.x, p.y-70): `'YUM!'` `#7fd89a` (cooked) or `'BLEH!'` `#9aa0a8` (burnt). If cooked and `hp < playerHp (5)`, `hp += 1`. Burnt does nothing else. |

### 4.5 Cooking (`bbqStep` L2073, called from `lobbySolids` L5775 every lobby step)
- When `heat>0`, each occupied place gets `s = min(2, s + rate[heat]*dt)`. There is **no flipping**. Cooking pauses when the heat is off.
- Timings from raw:

| heat | rate/s | to cooked (s=1) | to "burnt when taken" (s=1.6) | to max (s=2) |
|---|---|---|---|---|
| 1 low | 0.055 | 18.2 s | 29.1 s | 36.4 s |
| 2 med | 0.10 | 10 s | 16 s | 20 s |
| 3 high | 0.17 | 5.9 s | 9.4 s | 11.8 s |

- Visual stages by s:
  - 0 raw pink, lerping to cooked brown at 1.
  - From 1 to 1.6, lerping to burnt black.
  - Grill marks appear when s > 0.45.
  - The shine dims at s ≥ 1.4.
  - Smoke turns black when any s > 1.5.

### 4.6 Drawing
`snagColour(c)` L2357:
```js
k = min(1,c); b = clamp((c-1)/0.6, 0, 1);
r = 232+(150-232)k; g = 150+(84-150)k; bl = 150+(44-150)k;   // raw (232,150,150) -> cooked (150,84,44)
return [r+(36-r)b, g+(28-g)b, bl+(24-bl)b];                  // -> burnt (36,28,24)
```

`drawSnag(x,y,c,w,h)` L2362:
- A rounded rect (radius h/2) in snagColour.
- Shine: a 1 px line at (x+h/2, y+1, w-h, 1), `rgba(255,255,255, c<1.4 ? .35 : .1)`.
- If c > 0.45: three 1 px grill marks at x + i*w/4, colour `rgba(30,14,6,.55)`.

`drawBbq(w)` L2369, drawn on the floor layer after the yard (`drawLowerLobby`, L11565), so players walk over it. With `T0 = BBQ.top` (60×30 at 523,524):
- Lid propped open: `#9ea3aa` (x0-1, y0-9, 62, 9), plus a highlight `#c9ced4` (x0+1, y0-8, 58, 3).
- Plate: `#26272b` fill of the full rect.
- When heat > 0, burner glow every 4 px of x from x0+2: a 3 px wide column, full height-2, colour `rgba(255, 110+60f, 30, f)` with `f = (0.35 + 0.2*heat)*(0.7 + 0.3 sin(13 now + 1.7x))`.
- Grill bars: `#7d8189` 1 px horizontal lines every 4 px from y0+2. Outline `#111` 1 px.
- Snags: place i at (x0+6 + (i%2)*28, y0+6 + (i>>1)*12), size 20×6. So two columns by two rows.
- Knobs: dots at x ∈ [530, 543, 552, 562, 574], y=580, 3×3 `#ff5a2a`. The lit count is `[0,1,3,5][heat]` (low lights 1, medium 3, high 5).
- Smoke puffs: circles at (x0 + u*60, y0 + v*30 - z), radius r, grey `c` at alpha `a*min(1,life)`.
- Esky at (504,701):
  - Shadow `rgba(0,0,0,.25)` (ex-15, ey+9, 32, 4).
  - Body `#2f6fbf` (ex-16, ey-8, 32, 18).
  - Lid `#e6eaee` (ex-17, ey-16, 34, 9).
  - Handle `#9aa3ad` (ex-6, ey-13, 12, 3).
  - Outline `#13213a` strokeRect (ex-16.5, ey-16.5, 33, 27).

`drawHeldSnag(p)` L2398 (drawn after the character, L12267): `drawSnag(p.x + (p.fx<0 ? -18 : 4), p.y - 20 - dz, [0,0,1,1.8][food], 14, 5)`. A raw snag shows as c=0, cooked as c=1 and burnt as c=1.8.

**Smoke and sound** (`bbqFx` L2341, run from `drawBbq` and from first person). It keeps `BBQ_FX = {puffs, last, heat, siz}` per screen and works from the host's state, so the guest hears it too. Volume `near = max(0, 1 - dist(me, (553,600))/700)`.
- **Heat change:** a knob click `sTone(.03, 1800→1200, .05*near, square)`. When lighting from off, add a whoomp `sNoise(.5, 400, 1.5, .25*near, bandpass, →1400)`.
- **Heat > 0 and any snag on:**
  - Sizzle every 0.05-0.17 s: `sNoise(.06-.12, 3500-6500 Hz, Q2, (.012+.01*heat)*near, highpass)`.
  - Puffs spawn with probability `dt*(2 + 3*heat + (burnt ? 8 : 0))`: `{u: .15-.85, v: .2-.8, z:0, r:3, a: burnt ? .5 : .28, c: burnt ? 60 : 210, life:1.6}`.
- **Heat > 0 with an empty grill:** shimmer puffs at rate `dt*0.8`: `{u: .2-.8, v: .5, r:2, a:.12, c:200, life:1.2}`.
- **Puff update:** `z += 26 dt`, `r += 5 dt`, `life -= dt`, u jitters by ±0.01.

**First person** (trip or sober):
- The bbq solid (36 high) and the esky (22 high) are walls/blocks.
- The hotplate top is coloured per pixel by `bbqPlateRGB(u,v,B,now)` L3854:
  - Snag i occupies u ∈ [su, su+.33] and v ∈ [sv, sv+.22], with `su = .1 + (i%2)*.47` and `sv = .18 + (i>>1)*.42`. Its colour is snagColour, darkened to ×0.5 on stripes where `fpRep((u-su)*40, 3.3) < .5` if s > .45.
  - Grill bars (96,99,106) where `fpRep(v*34, 3) < 1.2`.
  - Lit gaps: `f = (.25 + .17*heat)*(.7 + .3 sin(13 now + 60u))`, colour `(34+210f, 30+100f², 28)`.
  - Unlit gaps: (38,39,43).
- The esky top is (228,232,236).
- Flames are `2+heat` additive glow sprites of size `(5 + 2.5*heat)*flicker` above the plate. Puffs are radial-gradient billboards (`fpPuff`, 24×24, pale or dark at 4 alpha levels).
- **Held snag in first person** (L4877-4884), when not on the board and not diving:
  - A rounded rect at the screen centre-bottom: translate (0.5 CW, 0.7 CH), rotate -0.18 rad, size `0.17 CW × 0.065 CH`.
  - Colour `snagColour([0,0,1,1.8][food])`, plus a shine bar at 30% white.
  - If cooked or burnt, 4 dark marks.

There is **no image art** for the barbecue, esky or snags. Everything is procedural apart from the yard picture.

---------------------------------------------------------------------------------------------------

## 5. Art files

Extracted by `<your scratchpad>/extract_machines.py`, which reads the HTML and does not write to it. Output folder: `godot/scripts/lobby_life/art/machines/`. All images are pixel art, so use nearest-neighbour filtering.

| file | what | px | draw scale | also in manifest |
|---|---|---|---|---|
| `slot_idle_a.png`, `slot_idle_b.png` | slot cabinet idle frames (alternate at 3 Hz) | 89×128 | h=124.2, so ×0.970; feet at y+6 | `godot/assets/SLOT_SPRITES/idle_a.png`, `idle_b.png` |
| `slot_spin.png` | cabinet while anyone spins | 89×128 | ×0.970 | `godot/assets/SLOT_SPRITES/spin.png` |
| `slot_win.png` | cabinet while `flash>0` (1 s after a win) | 89×128 | ×0.970 | `godot/assets/SLOT_SPRITES/win.png` |
| `vend_idle_a.png`, `vend_idle_b.png` | vending machine idle (alternate at 2.5 Hz) | 176×300 | ×0.5 (h=150); feet at y+6 | `godot/assets/VEND_SPRITES/idle_a.png`, `idle_b.png` |
| `vend_sold.png` | vending machine sold out | 176×300 | ×0.5 | `godot/assets/VEND_SPRITES/sold.png` |
| `fp_blaster_left.png` | first-person left hand and blaster (the right one is a horizontal mirror; skin pixels are recoloured to the character's skin, `fpGunFor` L4209). Muzzle at (171, 15) in source px (`FP_BLASTER.mx/my`). | 172×177 | height = 0.44 × screen height | `godot/assets/FP_BLASTER_img_src.png` |
| `fp_boot_pix.png` | his boot from above (first-person feet on the diving board); rendered from the `BOOT_PIX` code table L4169 (not base64) | 18×22 | see `drawFeet` | none (procedural) |
| `shroom_pickup.png` | the mushroom on the floor, without glow; rendered from `drawShroomPickup` rects | 18×19 | 1 px = 1 unit; anchor (9,17) at SHROOM_SPOT | none (procedural) |

- The yard background that the barbecue sits on is `godot/assets/misc/line1985_0.webp` (manifest `YARD_IMG@1985`, 2003×1998 units, drawn at (-45,-50)).
- The lounge floor used by the trip's floor is `godot/assets/LOUNGE_IMG_src.webp`.
- No other base64 images are used by these four features. The `gymImg('…')` calls near L3489-3523 are the bong, vape and torch, which belong to the bong trip.
