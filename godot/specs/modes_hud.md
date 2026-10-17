# Spec: game modes and the HUD

Source: `Smashed.html` (build b331). Read from the code; line numbers are the HTML file's (`L1234`). Tuning is
written `T.name (value)`, where `T` is the tuning table (`data/game_data.json` → `T`, HTML `L255`). Positions are HTML
units: `x` across, `y` down the screen (north to south on the ground), `z` up. The arena/lounge is `ARENA = {w: 860,
h: 520, wall: 18}`. Screen-space HUD positions are in the HTML canvas's own 860 × 520 coordinates (the canvas is drawn
at 860 × 520 logical pixels and CSS-scaled to fit the page, `resize` `L8562`), so every HUD number below scales with the
screen. The simulation runs in fixed steps of `1/120` s (`advanceSimulation` `L12705`).

What this spec covers:
1. The mode picker (`MODES`, Classic, Protect Gothica) and how a run starts with a mode.
2. Protect Gothica: `PROT`, `newGoth`, `stepGoth`, `protTarget`, `protHurt`, carrying her in a run, her health bar,
   her speech, the best wave.
3. The in-run HUD: hp pips, money, ammo, the wave / left / killed line, the weapon bar layout, banners, floating
   numbers, the help overlay, the on-screen buttons.
4. The game-over screen and restarting.
5. The victory dance between waves (victory frames).
6. The secret preview and the bonus room inside the slot machine (`slotSecret`, `enterMachine`), at a summary level.
7. Phone controls in a run: the twin sticks, roll taps, firing, tap-to-throw/tap-to-fire, the E button.
8. Sounds, the network snapshot fields, history notes, edge cases.
9. **In Godot**: how to build it on the milestone 1 contracts.

Other specs own neighbouring systems and are referred to rather than repeated: `enemies_waves.md` (the wave director,
enemies, the janitor, player health and death, the run's start and restart, the wave banner), `weapons.md` (weapons,
the weapon bar in full detail, banners set by weapons, first-person shooting). Where this spec repeats something of
theirs it's because the HUD draws it; the numbers agree.

---

## 1. Game modes

### 1.1 Data (`L12853-12872`)

```js
const MODES = [{ id: 'classic', name: 'Classic' }, { id: 'protect', name: 'Protect Gothica' }];   // L12856 (also game_data.json "MODES")
let gameMode = 'classic';                                                                          // L12857
// L12858: on load, gameMode = localStorage 'smashed-mode' if it is one of the MODES ids
```

State:

| where | name | start | meaning |
|---|---|---|---|
| page | `gameMode` | `'classic'`, or the saved `smashed-mode` | this browser's pick for the next run (the host's is the one played) |
| world | `mode` | absent (undefined) in a new world | which mode the current run is; set by `startGame` (`L13555`) |
| world | `goth` | absent / `null` | Gothica's run state in Protect mode (§2), `null` in Classic |
| world | `gothDown` | absent / `false` | she went down (the run ended because of her); only used for the snapshot `gd` |

### 1.2 The picker UI (DOM, not the canvas)

Two copies of the same control, both kept in sync:
- In the top button row (`L130`): `◀` (`#modePrev`), the name (`#modeName`, class `modeName`), `▶` (`#modeNext`), then
  `Start` (`#startBtn`, class `primary`), `Restart`, `Full screen`, `Zoom`, `First person (V)`, `Sound`, and the
  network buttons.
- In the full-screen bar (`#fsBar`, `L218`, shown only while the stage is full screen, top right at (12 px from the
  right, 10 px from the top), `opacity 0.9`, 1 on hover): `◀` `#fsModePrev`, `#fsModeName`, `▶` `#fsModeNext`,
  `Start` (`#fsStart`), `Restart` (`#fsRestart`), the debug buttons, `Exit`.

Styles (`L28-30`): `.modeArrow` padding 9 px left and right; `.modeName` inline-block, `min-width 118px` (104 px in
the full-screen bar, 13 px font there), centred, colour `#f6d17a`, `font: 600 14px` sans-serif. Buttons: background
`#232733`, border `1px #333947`, radius 3, padding `6px 12px`; `primary`: `#e0473f` fill and border, white, weight
600, `opacity 0.35` when disabled.

Behaviour:
- `stepMode(d)` (`L12860`): does nothing for the network guest, during a run (`world.started`) or while calibrating
  guns (`cal.on`). Otherwise moves `gameMode` one step through `MODES` (wrapping both ways), saves it in
  `localStorage 'smashed-mode'`, calls `updateModeUI()`.
- The arrows call `stepMode(-1)` / `stepMode(+1)` and blur themselves (`L13616-13617`) so the next key goes to the
  game.
- `shownMode()` (`L12859`): the guest shows the host's mode (`net.view.mode`, from the snapshot field `md`, else
  `'classic'`); the host shows `world.mode` during a run, else its own `gameMode`.
- `updateModeUI()` (`L12867`): writes the shown mode's `name` into both name spans, and disables all four arrows when
  `net.role === 'client' || world.started || cal.on` (the guest sees the host's pick, greyed out). It runs at load and
  every 200 ms (`setInterval`, `L13618`).
- The Start buttons are disabled (every 200 ms, `L13608-13614`) when `world.started || net.role === 'client' ||
  cal.on`.

### 1.3 Starting a run with a mode

`startGame()` (`L13549`; full list of what it resets in `enemies_waves.md` §3.1). The mode-specific part, first thing
after the guards (secret room active, already started, network guest, calibrating):

```js
world.started = true;
world.mode = gameMode;                                          // b294: which mode this run is
world.goth = gameMode === 'protect' ? newGoth(world) : null;
world.gothDown = false;
world.breather = T.intermission;                                 // 2.2 s to wave 1
```

Start triggers: Enter (`L8651`, not a repeat, only if not started), the Start buttons, the pad's Menu button (button 9,
`L8982`: `'enter'` when not started, `'r'` when over), and (only with the title poster showing, which is off:
`showPoster = false`, `L6056`) a tap near the bottom message.

There is no difference between the modes in waves, enemies, weapons, money or the janitor. Classic: the run ends when
every player is down. Protect: players come back after `PROT.respawn` s, and the run ends when Gothica goes down.

---

## 2. Protect Gothica (`L12874-13068`)

The idea, from the comment at `L12875`: she's in the arena for the run, with a health bar. Calm, she wanders, and heads
for a ripe potato when she's hurt (eating one heals her). An enemy close by sends her running away from it, without a
thought for what's ahead. Jared can carry her (E): she can't be hurt up there, but he's slow, can't shoot or roll, and
after a few seconds she wriggles down. Enemies go for whichever is closer, her or a player. You come back after a few
seconds if you go down; if she goes down, that's the run.

### 2.1 PROT (`L12882`, also `game_data.json` "PROT")

| key | value | meaning |
|---|---|---|
| `hp` | 10 | her health (a player has `T.playerHp` 5) |
| `walk` | 38 | strolling speed, units/s (as in the lobby; `T.npcSpeed` is also 38) |
| `run` | 110 | panicking speed: quicker than a grunt (40 × wave speed), slower than a swarmer |
| `panicR` | 130 | an enemy this close and she bolts |
| `hurtFor` | 0.9 | can't be hurt again for this long after a hit (she blinks) |
| `heal` | 2 | health per potato eaten |
| `eatR` | 280 | how far she'll go for a ripe potato |
| `carryFor` | 4 | seconds in his arms before she wriggles down |
| `carryCool` | 1.5 | after wriggling down: how long before anyone can pick her up again |
| `carrySlow` | 0.7 | the carrier's top speed multiplier |
| `respawn` | 4 | seconds a downed player waits before coming back |
| `margin` | 70 | she wanders this far in from the walls |

Other numbers she uses: `T.carryRange` 46 (pick-up distance), `T.contactDmg` 1, `T.contactPush` 320, `T.shrapDmg` 1,
`T.spudGrow` 9 (a plant is ripe at `t ≥ 9`), `T.playerHp` 5, `T.radius` 14, `T.spriteScale` 4.6, `T.enemyRadius` 15,
`ETYPE` (`dmg`: grunt 1, swarmer 1, brute 2, batter 2; `r`: 1, 0.6, 1.6, 1; `mass`: 1, 0.45, 2.8, 1.1; batter is
`melee`). `T.batReach` 46.

Who can carry her: `CARRIERS = new Set(['juicy', 'jared'])` (`L9858`): Juicy Jared and the old-art Jared. Tyson,
Gothica and Inky can't.

`PROT_SAY` (`L12896`), picked with `Math.random()`:
- `panic`: "Help!", "Eek!", "Get away!", "Nooo!"
- `hurt`: "Ow!", "Ouch!", "Hey!"
- `eat`: "Mmm", "Yum!"
- `free`: "Put me down!", "I can walk!"
- and when she goes down: "Ugh..." (3 s).

`protSay(g, list, dur)` (`L12897`): `g.bubble = { text: random from list, t: 0, dur: dur || 1.6 }`.

### 2.2 Her state: `newGoth(w)` (`L12900`)

`protTop(w)` (`L12899`) = `max(ARENA.wall + 14, slot.y + 40)`: she keeps below the machines along the top wall (behind
them she'd be out of sight). In a run the slot machine is at `y = 110`, so `protTop = 150`.

```
m = ARENA.wall + PROT.margin = 88
x = clamp(NPC_GOTH.x || 430, m, 860 - m)                 // 88..772: she starts where lobby Gothica was standing
y = clamp(NPC_GOTH.y || 260, protTop + 30, 520 - m)      // 180..432
```

| field | start | meaning |
|---|---|---|
| `id` | `'npc_goth'` | |
| `npc`, `prot` | true, true | an NPC, and the Protect one (the renderer checks `prot`) |
| `ch` | `'goth'` | her art |
| `weapon` | `'blaster'` | only so `drawJared`'s weapon lookups work; she never shoots |
| `alive` | true | always true, even when down (`hp ≤ 0` is "down") |
| `x`, `y` | above | position |
| `odo` | 0 | distance walked (drives her run cycle) |
| `moving` | false | |
| `ix`, `iy` | 0, 1 | last move direction |
| `fx`, `fy` | 0, 1 | facing (0, 1 = facing the camera / south) |
| `vx`, `vy` | 0, 0 | knock-back velocity only (her walking isn't velocity based) |
| `tx`, `ty` | x, y | wander target |
| `wait` | 1.5 | seconds before she picks a new wander target |
| `hp`, `max` | 10, 10 | |
| `hurt` | 0 | invulnerability left after a hit |
| `carrier` | −1 | the player id carrying her, or −1 |
| `carryT` | 0 | seconds she's been carried this time |
| `carryCd` | 0 | seconds before she can be picked up again |
| `face` | false | which way she faces in his arms (true = left) |
| `panic` | 0 | seconds of running left |
| `runX`, `runY` | (absent) | the direction she's running in |
| `sayCd` | 0 | seconds before she can say another panic/hurt line |
| `bubble` | null | `{ text, t, dur }` |

Players get one extra field in Protect mode: `p.downT` (seconds down; created on first use).

### 2.3 Who enemies chase: `protTarget(w, e, target, best)` (`L12951`)

Every enemy step (`L7553-7559`): `target` = the nearest living player and `best` its distance. Then, if `w.goth`:

```
if !g or g.hp <= 0 or g.carrier >= 0: keep (target, best)
d = |g - e|
return d < best ? (g, d) : (target, best)
```

So enemies chase her when she's nearer than every living player, and ignore her while she's carried or down. With
every player down they all go for her. The batter's wind-up and swing (`L7566` onwards) use this target too.

### 2.4 Being hurt: `protHurt(w, g, dmg, nx, ny)` (`L12938`)

Returns true if the hit landed.

```
if g.hurt > 0 or g.hp <= 0 or g.carrier >= 0: return false      // invulnerable, already down, or in his arms
g.hp = max(0, g.hp - dmg); g.hurt = PROT.hurtFor (0.9)
g.vx += nx * T.contactPush * 0.8; g.vy += ny * T.contactPush * 0.8   // a 256 u/s shove
fx(w, FX.HURT, g.x, g.y)                                            // red bits + the hurt sound
if g.hp <= 0:
    g.alive = true; g.moving = false; g.bubble = { text: 'Ugh...', t: 0, dur: 3 }
    fx(w, FX.DOWN, g.x, g.y)                                         // big red burst + the down sound
    w.over = true; w.gothDown = true                                 // the run is over
elif g.sayCd <= 0: protSay(g, PROT_SAY.hurt, 1.1); g.sayCd = 1.2
return true
```

What hurts her (three places):
1. **Touch** (in `stepGoth`, §2.6 last step): any non-melee enemy (grunt, swarmer, brute) not still spawning, within
   `eRad(e) + 12` (grunt 27, swarmer 21, brute 36): `protHurt(T.contactDmg × ETYPE.dmg)` = 1 (grunt, swarmer) or 2
   (brute), pushed away from the enemy; if it landed, the enemy is pushed back too: `e.v −= dir × contactPush × 0.6 /
   mass` (192 / mass).
2. **The batter's swing** (`L7600-7602`, at the moment the swing hits, same moment it tests players): if she's within
   `T.batReach + 12 = 58` of him and in front (`(d · swingDir)/|d| ≥ 0.25`): `protHurt(T.contactDmg × ETYPE.dmg (batter 2) = 2, swingDir)`.
   The batter never hurts her by touch (b294 comment: "the batter has to swing").
3. **Brute shrapnel** (`L7816-7819`, checked before the players): a shard within 16 of her: `protHurt(T.shrapDmg (1),
   shard direction)`; the shard is used up only if the hit landed (during her 0.9 s she's see-through to it).

Bullets, potatoes, rockets and blasts never hurt her (`weapons.md` §9.1).

### 2.5 Carrying her in a run

`protCanCarry(w, p)` (`L12915`):
```
g and w.started and not w.over and g.hp > 0 and g.carrier < 0 and g.carryCd <= 0
and p and p.alive and not p.dive and CARRIERS.has(p.ch) and |p - g| < T.carryRange (46)
```

`protectCarry(w, p)` (`L12928`), what E does in a Protect run (for either player):
```
if !g or !p or w.over: return
if g.carrier == p.id: protSetDown(w, g, 0.3); return            // put her down
if protCanCarry(w, p):
    g.carrier = p.id; g.carryT = 0; g.face = p.fx < 0; g.moving = false; g.bubble = null
    JIG.npc_goth.v += 30                                         // her bounce gets a kick (the jiggle spring)
```

`protSetDown(w, g, cool)` (`L12920`):
```
p = the carrier
g.carrier = -1; g.carryT = 0; g.carryCd = cool || 0.3
if p: g.x = p.x + (g.face ? 20 : -20); g.y = p.y + 4
clamp g.x to [32, 828], g.y to [protTop (150), 488]
g.moving = false; g.wait = 0.4; g.fx = 0; g.fy = 1             // stands facing the camera, then wanders on
```
(Note: `face` true means facing left, so she's put down on his right: behind him if he's walking left. Kept as is.)

While she's carried:
- The carrier can't shoot or roll: `stepBase` (`L7172`) replaces his input's `shoot` and `roll` with false whenever
  `gothHeldBy(w, p)` (`L12909`: in a run, `w.goth.carrier === p.id`).
- His top speed is `T.maxSpeed × PROT.carrySlow` = 182 (`L7511`; × `T.speedMul` 1.55 too if he has the speed boost:
  282). Acceleration and friction are unchanged.
- She can't be hurt and enemies ignore her (§2.3, §2.4), so they all go for the players: carrying is a shield for her,
  not for him.
- `stepGoth` (§2.6) holds her at his position and sets her down after `PROT.carryFor` (4 s) with
  `PROT.carryCool` (1.5 s) and a `free` line (1.4 s); or straight away (cool 0.5) if he dies or dives.
- She isn't drawn herself; he's drawn with the carry frames (`drawJared` `L10646-10660`: the `CARRY_FRAMES` pictures,
  manifest `CARRY_FRAMES@9741` (3 frames: stand, walk-body, squat), the walk built from his run stride
  `floor(odo / T.runStride) % 7`, flipped by `gothFace(w)` = `g.face`, scaled `T.carryScale (1) × height / 160`,
  anchored at `CARRY_ANCHOR = 72/160` across; her jiggle runs on his footsteps). In a run there's no scoop or
  set-down animation (`NPC_GOTH.anim` is the lobby's). The carry pictures are the lobby-Gothica spec's; this system
  only switches them on.

How E reaches `protectCarry`:
- Host keyboard: `E` (`L8653`): `if (k === 'e' && !e.repeat && world.started && world.goth && net.role !== 'client')
  protectCarry(world, world.players[0])`. In a Classic run E does nothing.
- The on-screen round button (`carryButton` `L10109`, tap or click within `r + 8`): in a run with Gothica, label
  `'PUT DOWN'` if you carry her, `'PICK UP'` if `protCanCarry`, else no button; tapping it calls `toggleCarry(world)` →
  `lobbyAction(w, players[0])` (`L10140`), whose first line is `if (w.started && w.goth) { protectCarry(w, p);
  return; }`.
- Gamepad A (button 0) = the E key (`padTap('e')`, `L8975`).
- The network guest: `E` or the button increments `SITREQ.id` (`L8654`); the counter rides in every input as `sq`; the
  host's step (`L7175-7178`), for player 1 in a Protect run, calls `protectCarry(w, p)` once each time `sq` changes
  (`p.lastSq` remembers the last seen; the first value seen is only recorded).

### 2.6 Each step: `stepGoth(w, dt)` (`L12957`)

Called once per sim step from `stepBase` (`L8040`), after the nuke, rockets, the shake decay and the plants, and
before the potato rain, the gym and blackjack. The whole order of a step is in `enemies_waves.md` §3.5; the parts that
touch Protect mode, in order: players (carry blocks shoot/roll; the guest's `sq`; the ×0.7 speed cap) → wave director
→ enemies (targets via `protTarget`; the batter's swing can hit her) → contact damage to players → shrapnel (her first)
→ ... → `stepGoth`.

```
g = w.goth
if !g or !w.started or w.over or secretActive(w): return
g.hurt   = max(0, g.hurt - dt)
g.carryCd = max(0, g.carryCd - dt)
g.sayCd  = max(0, g.sayCd - dt)
if g.bubble and (g.bubble.t += dt) > g.bubble.dur: g.bubble = null

# 1. players who went down come back after a while, next to her
for p in players:
    if p.alive: p.downT = 0; continue
    p.downT += dt; if p.downT < PROT.respawn (4): continue
    p.alive = true; p.downT = 0; p.hp = T.playerHp (5, no overheal); p.grace = 1.5; p.iframe = 0
    p.x = g.x + (p.id ? 40 : -40); p.y = g.y + 10; p.vx = p.vy = 0; p.roll = 0; p.rollCd = 0
    clamp p to [32, 828] x [32, 488]                        (wall + T.radius)

# 2. in someone's arms: safe, until she's had enough
if g.carrier >= 0:
    p = the carrier
    if !p or !p.alive or p.dive: protSetDown(w, g, 0.5); return
    g.x = p.x; g.y = p.y; g.moving = false; g.vx = g.vy = 0
    if p.moving and |p.ix| > 0.2: g.face = p.ix < 0
    if (g.carryT += dt) >= PROT.carryFor (4): protSetDown(w, g, PROT.carryCool (1.5)); protSay(g, free, 1.4)
    return

# 3. read the knock-back speed now (a hit later this step only slides her next step)
kick = |(g.vx, g.vy)|
mx = my = spd = 0

# 4. anything close? run directly away from everything that's close (and only that)
ax = ay = 0; near = inf
for e in enemies, skipping e.spawn > 0:
    d = |g - e| (or 1); near = min(near, d)
    if d < PROT.panicR (130): ax += (g.x-e.x)/d * (1/d); ay += (g.y-e.y)/d * (1/d)   # nearer ones count more
if near < 130:
    if g.panic <= 0 and g.sayCd <= 0: protSay(g, panic, 1.2); g.sayCd = 2.5
    g.panic = 0.8                                             # and keeps running a moment after
    g.runX = ax; g.runY = ay

if g.panic > 0:
    g.panic -= dt
    (rx, ry) = (g.runX, g.runY)
    # the walls turn her: she slides along them rather than into them
    if g.x < 48 and rx < 0: rx = 0;   if g.x > 812 and rx > 0: rx = 0          (48 = wall + 30)
    if g.y < protTop + 16 (166) and ry < 0: ry = 0;   if g.y > 472 and ry > 0: ry = 0
    if |(rx, ry)| > 1e-6: (mx, my) = normalised; spd = PROT.run (110)
    g.wait = 0.6                                              # then she gets her breath back
    g.tx = g.x; g.ty = g.y
else:
    # hurt, and a ripe potato in reach? go and eat it
    food = null; fd = PROT.eatR (280)
    if g.hp < g.max: for pl in w.plants with pl.t >= T.spudGrow (9): nearest within fd
    if food:
        g.wait = 0; g.tx = food.x; g.ty = food.y
        if fd < 14:
            remove the plant
            g.hp = min(g.max, g.hp + PROT.heal (2))
            protSay(g, eat, 1.2)
            w.floaters.push({ x: g.x, y: g.y - 46, text: '+2', t: 0, col: '#7dff9a' })
            fx(w, FX.WALL, food.x, food.y)                    # a little grey puff (no sound)
            g.wait = 0.8; g.tx = g.x; g.ty = g.y
    elif g.wait > 0:
        g.wait -= dt
        if g.wait <= 0:                                        # a new spot to stroll to
            m = 88; top = max(88, protTop + 20) = 170
            g.tx = m + random() * (860 - 2m)                   # 88..772
            g.ty = top + random() * (520 - m - top)            # 170..432
    elif |target - g| < 4:
        g.wait = 1.2 + random() * 2.2; g.fx = 0; g.fy = 1     # arrived: stand facing the camera 1.2..3.4 s
    if g.wait <= 0:
        d = |target - g|
        if d > 2: (mx, my) = unit toward target; spd = food ? PROT.walk * 1.8 (68.4) : PROT.walk (38)

# 5. move
if spd > 0: g.ix, g.iy, g.fx, g.fy = mx, my; g.x += mx*spd*dt; g.y += my*spd*dt; g.odo += spd*dt; g.moving = true
else: g.moving = false
# knocked back by a hit: slide to a stop
if kick > 1: g.x += g.vx*dt; g.y += g.vy*dt; f = 0.002^dt; g.vx *= f; g.vy *= f     # keeps 0.2% a second
else: g.vx = g.vy = 0
clamp g.x to [32, 828], g.y to [protTop (150), 488]

# 6. contact: anything that isn't a batter hurts her on touch (the batter has to swing)
for e in enemies, skipping e.spawn > 0 and melee types:
    d = |g - e|; if d > eRad(e) + 12: continue
    if protHurt(w, g, T.contactDmg * ETYPE.dmg, (g-e)/d): e.v -= (g-e)/d * contactPush * 0.6 / mass
```

Notes:
- Her wander targets and lines use `Math.random()` (not the world's `rnd`): only the host runs this, so it doesn't
  matter.
- She ignores solids and props (there are none in a run) and other characters; only the walls and `protTop` stop her.
- Her walk doesn't use acceleration: she's at full speed or stopped.
- She isn't stepped while the slot machine's bonus room is on (§6): she stays frozen where she was, still drawn.

### 2.7 How she's drawn (top-down, `renderBase` `L12221-12252`)

She joins the depth sort with the players (`npc = w.goth` unless carried or calibrating; sorted by `y`):
- **Down** (`hp ≤ 0`): `drawThrownGoth(... thrown: 'floor', dz: 0)` (`L10370`): `IMG.goth.front_run[0]` (manifest
  `CHARS.goth.sprites.front_run[0]`), height `T.radius × T.spriteScale × scale × T.altScale` = 14 × 4.6 × 1 × 1.242 =
  **80** units, width by the picture's aspect × `T.altWide` (1); rotated 90° (lying on her side), centred at
  `(x, y + 0.9r − dw/2)`; a contact shadow ellipse at `(x, y + 0.85r)`, radii `0.95r × 0.4r`, black at 0.35.
- **Blinking** after a hit: while `hurt > 0`, she's not drawn on frames where `floor(hurt × 20) % 2 == 0` (10 Hz,
  like the players' i-frames).
- Otherwise `drawJared(w, g)`: the ordinary character drawing (run cycle by `odo` every `T.runStride` 13 units, the
  stand pair, five directions plus flips, her jiggle × `T.npcJiggle` 2.2), exactly as for a player of `ch = 'goth'`.
  No hp pips over her head and no ring (the `continue` at `L12252`).
- **Her health bar** (`drawGothBar` `L13057`), only while `hp > 0`, in world space (it zooms with the camera):
  ```
  w = 40, h = 5, x = round(g.x - 20), y = round(g.y - T.radius*T.spriteScale*1.25 + 14)   // g.y - 66.5
  back:  rgba(0,0,0,0.65), (x-1, y-1, 42, 7)
  fill:  f = clamp(hp / max, 0, 1); colour f > 0.5 ? '#f7a8ff' (her pink) : f > 0.25 ? '#f6d17a' : '#e0473f'
         (x, y, round(40 f), 5)
  ```
- **"E: pick up"** over her while the local player could pick her up (`protCanCarry(w, localPlayer())`):
  `actKey() + ': pick up'` (`actKey` `L8882`: 'A' if a pad was used more recently than the keyboard or a pointer,
  else 'E'), bold 11 px sans-serif, centred at `(x, y − 80.5 + 4)`, white with a 1 px down-right shadow
  `rgba(0,0,0,0.6)`.
- **Her speech bubble** (drawn last, over everything, `drawSpeech(g, 0)` `L1134`): bold 11 px sans; box
  `text width + 14` × 20 at `(x − pw/2, y − 92)`, kept inside the walls (`[wall + 2, w − wall − pw − 2]`), fill
  `#fffdf6`, 2 px stroke `#1c1a22`, corner radius 6; a tail (triangle `tx−5 … tx+1, +7 … tx+5`) pointing down at her;
  text `#1c1a22` centred. Alpha `min(1, (dur − t)/0.4, t/0.12)`: fades in over 0.12 s and out over the last 0.4 s.
- The **"+2"** when she eats is a floater (bold 13 px monospace, centred, `#7dff9a`, a 1 px black 0.6 shadow, rising
  34 u/s, alpha 1 until 0.6 s then fading to 0 at 0.9 s, removed at 0.9 s: `L8201`, `L12619`).
- Hurt/down bursts: `FX_LOOK[HURT] = 10 bits '#e0473f' speed 220`, `[DOWN] = 24 bits '#e0473f' 300`, `[WALL] = 3 bits
  '#5a6274' 120` (3 × 3 squares, life 0.25-0.6 s).

### 2.8 The best wave (`L13064-13068`)

```js
let protBest = +localStorage.getItem('smashed-protect-best') || 0;
function protNoteBest(wave) { if (wave > protBest) { protBest = wave; localStorage.setItem('smashed-protect-best', String(wave)); } }
```
Called from the game-over drawing every frame while `w.over && w.goth` (§4) with `w.wave` (the wave in progress when
she went down). Per browser; the guest records its own best from what it sees (its renderer runs the same code on
`net.view`). There's no best for Classic.

---

## 3. The in-run HUD

Everything here is drawn by `renderBase` (`L11527`) after the world (`ctx.restore()` at `L12440`, "camera off: the
HUD stays put"), **inside the screen-shake transform** (`L11529-11533`: a random offset of up to
`±min(40, w.shake)/2` in x and y every frame), so the HUD shakes with the picture. In this order:

1. touch sticks (§7), 2. the E/carry button, 3. the trampoline JUMP button, cards button, shirt-art button, sit menu,
   shirt editor, blackjack panel (lobby things), 4. **the weapon bar**, 5. the zoom button, the first-person (eye)
   button (lobby only), the arcade, mirror and hair UI (lobby), 6. the controls help, 7. **the top-left line**,
   8. **the wallets and ammo**, 9. calibration crosshairs (tuning), 10. the room code (host waiting for a guest),
   11. the title poster (off), 12. **the wave banner** (breather), 13. world-space again: rockets, blasts, the nuke,
   **floaters** (cash numbers etc.), 14. the launcher touch hint, 15. **the big banner**, 16. **the game-over
   overlay**.

### 3.1 The top-left line (`L12458-12463`)

12 px monospace `#6d7486`, left-aligned at `(ARENA.wall + 8, ARENA.wall + 20)` = **(26, 38)**:
- in a run: `'wave ' + w.wave + '   ' + w.enemies.length + ' left   ' + totalKills + ' killed'` (three spaces
  between the parts). `left` counts enemies on the floor (including ones still materialising), not the ones still
  queued to spawn. `totalKills` = the sum of every player's `kills`.
- in the lobby: nothing.
- with `?debug` in the address: `BUILD + '   wave …   … left   … killed   ' + hudRight`, also in the lobby, where
  `hudRight` is the snapshot size (`snapBytes + ' B/tick'`) on the host, plus `'   ' + ping + ' ms'` with a guest; the
  ping on the guest.
- nothing at all while inside the slot machine's room.

### 3.2 Money and ammo (`L12465-12479`)

Bold 17 px monospace, one line per player (`i` = index in `players`), at y = `ARENA.wall + 46 + 22 i` = **64, 86**:
- `'$' + coins` at x = 26, in the player's colour `P_COLOURS[p.id]` (`L616`: player 0 `#e0473f` red, player 1
  `#4f9fe8` blue).
- at x = **88**: holding the launcher: `'☢ ' + rockets` in `#f6d17a`, `#e0473f` when 0. Else if the weapon uses ammo
  (spud gun, potato throw): `'● ' + ammo` in `#d8b878`, or `'○ 0'` in `#e0473f`. Blasters, shotgun, fists: nothing.
- Shown in the lobby and in a run alike; hidden in the slot machine's room. (`T.testCash` is 2500 in b331, so
  everyone starts with $2500; "Set 0 before release".)

### 3.3 Health pips (over each player's head, world space, `L12386-12396`)

Drawn after the player's sprite, lifted by `dz` (and `+36` for a swimmer), for every living player (and they blink
with the player while `iframe > 0`):
```
shown = max(T.playerHp, ceil(p.hp))                         // 5, or more with overheal (up to 5 + T.overheal 6)
chScale = CHARS[p.ch].scale * (NEW_ART.has(p.ch) ? T.altScale (1.242) : 1)
pipY = round(p.y + r*0.9 - r*T.spriteScale*T.hpHeight*chScale)     // r = 14: new art y - 71.4; old art y - 55.0
pip i (0..shown-1): 4 x 4 at x = round(p.x - shown*3 + i*6), y = pipY
   colour: i < hp ? (i >= T.playerHp ? '#f6d17a' (overheal, gold) : P_COLOURS[p.id]) : 'rgba(255,255,255,0.15)'
```
The 34 × 4 bars for the throw charge and the shotgun time (`weapons.md` §11.6) sit at `round(p.y + 0.9r −
r·spriteScale·hpHeight) − 8` = y − 63 with **no** `chScale`: 8 above the pips for the old art (pips y − 55), but
8.4 *below* them for the new art (pips y − 71.4), where the comment's "just above the hp pips" doesn't hold. In Godot
put them 8 above the pips for every character (the intent). (README fix: this line said "8 units higher" for all.)
Gothica has no pips: she has her bar (§2.7).

### 3.4 The weapon bar (`hotbarGeo` `L9925`, `drawHotbar` `L9942`; details in `weapons.md` §12)

Six square slots, `s = 54`, gap 8, centred at the bottom: `x0 = 430 − 182 = 248`, `y = 520 − 18 − 54 − 8 = 440`; slot
`i` at `x0 + 62 i`. Each is laid out at 40 × 40 and scaled by 54/40: background `rgba(14,16,22,0.78)`; border 1 px
`#3a4050` (not owned) / `#8b93a4` (owned) / 2 px `#f6d17a` (in hand) / `#e0473f` for 350 ms after picking one you don't
have; the key number top-left (9 px monospace `#6b7385` at (4, 7)); the icon at (20, 15) in 34 × 20; the count at
(20, 30). Order from `localStorage 'smashed-hotbar'` (default fists, spud, lob, blaster, shotgun, launcher). Tap = pick
(moved < 8), drag onto another slot = swap and save. Keys 1-6, the pad's LB/Y/d-pad cycle (`padCycleWeapon` `L8940`:
the next/previous slot you own). Hidden while calibrating, **when the game is over**, and in the slot machine's room.
Shown in the lobby too.

### 3.5 Banners

**The wave banner** (`L12557-12577`), while `breather > 0 && started && !over`:
- bold 26 px sans `#cfd4de`, centred at (430, 250): `'WAVE ' + (w.wave + 1)`.
- 14 px `#8b93a4` at (430, 276): `waveSize(next) + ' incoming'` + (if any) `' — '` + the new types joined with
  `' and '`: `swarmers` (next ≥ `T.swarmWave`), `batters` (only if `T.baseEnemy ≠ 3` and next ≥ `T.batWave`), `brutes`
  (next ≥ `T.bruteWave`). (The numbers are `enemies_waves.md`'s.)
- **Protect mode, before wave 1 only** (`w.goth && w.wave === 0`): 14 px `#f7a8ff` at (430, 298):
  `'keep Gothica alive  ·  potatoes heal her'` + (`'  ·  E picks her up'` if the local player's character is a
  carrier). Note it always says "E", not the pad's "A".

**The big banner** (`L12666-12676`), drawn after everything but the game-over overlay ("so nothing, including the
lobby poster, can cover it"): `banner = { text, until }` (a page global, `L6876`, `until` in `performance.now()` ms).
While `until > now`: bold 34 px sans, centred at **(430, 90)** (`ARENA.wall + 72`), a 5 px stroke
`rgba(20,22,28,0.9)` under a `#f6d17a` fill. No fade, no animation; a new banner simply replaces the old.

Who sets it:
| text | for | where |
|---|---|---|
| prize label: `REAL GUNS!`, `SHOTGUN!`, `+2 HEALTH`, `SPEED BOOST`, `SCREEN CLEAR`, `JACKPOT!`, `CASH MAGNET!`, `BUST!` | 1600 ms | `award` `L6279` (then `giveWeapon` may replace it) |
| `BLASTERS!`, `SHOTGUN!`, `NUKE LAUNCHER!`, `FISTS!`, `POTATO!` (weapon name + "!", not for the spud gun) | 1400 ms | `giveWeapon` `L6884` |
| `EMPTY!` (the launcher's last rocket gone) | 1000 ms | `L7248` |
| `MACHINE IS LIVE` (the janitor fixed the slot machine) | 1600 ms | `L7987` |
| `GARY KEEPS THE CHANGE` (back from the bonus room) | 1800 ms | `L13920` |
`beginSlotSecret` clears it (`banner.until = 0`).

Banners are set by the simulation but live in a page global, so **only the host sees them**; the guest never gets
them (not in the snapshot). Fix in Godot: make a banner an event (§8).

**The launcher touch hint** (`L12639-12663`, `weapons.md` §11.6): on a touch device, the first 4 s after picking up a
full launcher: `TAP WHERE YOU WANT IT TO LAND`, bold 22 px at (430, 124), gold with a dark 5 px stroke, fading in over
0.25 s and out over the last 0.5 s.

### 3.6 Floating numbers (world space, `L12617-12629`)

`w.floaters` items `{ x, y, text, t, col }`: rise 34 u/s, gone at `t > 0.9` (`L8201`); bold 13 px monospace,
centred, a `rgba(0,0,0,0.6)` copy 1 px down-right, then the text in `col || '#7fd89a'`; alpha 1 until 0.6 s, then
`1 − (t − 0.6)/0.3`. In a run: cash from kills (coins spec), Gothica's "+2".

### 3.7 Buttons on the canvas (screen space, all scale with the canvas)

| button | where (centre, radius) | shown | look |
|---|---|---|---|
| E / carry (`carryButton` `L10109`) | (798, 384), r 34 | whenever there's a label (§2.5; in the lobby the lobby's E labels) | fill `rgba(20,12,28,0.72)`, 2 px `#f7a8ff` ring, bold 12 px `#f7a8ff` label, centred |
| zoom (`zoomButton` `L8542`) | (818, 82), r 16 | always (not calibrating) | fill `rgba(14,16,22,0.72)`, ring `#f6d17a` when zoomed else `#8b93a4`, a magnifier with `+` (or `−` on the last step) |
| first person (eye, `fpButton`) | (818, 122), r 16 | **lobby only** (`fpCan` needs `!started`) | as the zoom button, an eye |
| FIRE (first person, phone) | (705, 405), r 40 | lobby first person on touch | §7.3 |
| JUMP (trampoline, phone) | (798, 304), r 30 | lobby only | |

Zoom in a run: the 2× step becomes 1.5× (`zoomWanted` `L8520`); inside the bonus room the zoom is forced to 1×.

### 3.8 The controls help (`drawControlsHelp` `L8906`)

- Lobby only, when the full list is off: a quiet reminder bottom-left, 11 px sans, `rgba(255,255,255,0.75)` with a
  black 0.5 shadow, at (26, 492): `Tab: controls` (keyboard) or `D-pad ▼: controls` (pad).
- The list (any time, run included): Tab or the pad's d-pad down toggles it; it also opens by itself for 7 s the
  first time a pad is used, fading over the last 600 ms. A 470 wide panel, `54 + rows × 22` tall, centred
  (top ≥ 8), fill `rgba(12,14,20,0.9)`, 2 px `rgba(247,168,255,0.6)` border, radius 10; title bold 15 px `#f7a8ff`
  (`CONTROLLER` / `KEYBOARD AND MOUSE`) at y + 20; rows from y + 46 every 22: key right-aligned at x + 170 bold 13 px
  `#ffd36b`, what it does left-aligned at x + 186, 13 px `#e6e8ee`. The rows are `HELP_PAD` / `HELP_KEYS`
  (`L8889-8905`), e.g. "Menu — Start the run (restart when it's over)", "R — Restart", "Enter — Start the run".

### 3.9 Gamepad feedback (`L8963-8965`)

When the local player's hp drops: `dual-rumble` 140 ms, strong 0.6, weak 0.35; if that took the last heart, 420 ms,
strong 1, weak 0.35.

---

## 4. Game over (`L12677-12695`, the sim part in `enemies_waves.md` §3.3)

`w.over` is set by: Classic, the last living player dying (`L7597`, `L7683`, `L7833`, each guarded by `!w.goth`);
Protect, Gothica's hp reaching 0 (`protHurt`). In Protect mode players dying never ends the run.

Then:
- The simulation stops completely: `frame` only calls `advanceSimulation` while `!world.over` (`L12798`), and the
  step itself is skipped too (`L12710`). Nothing moves, bits freeze in the air, timers stop, the shake never decays
  (a shake at the moment of death keeps jittering the whole picture: fix in Godot by decaying it anyway).
- The weapon bar hides; the E button hides in Protect (its label needs `!w.over`).
- The overlay, drawn last, in screen space (inside the shake):
  ```
  fill the whole canvas rgba(20,22,28,0.78)
  centred, (430, 238): bold 40 px sans '#e0473f':   Protect ? "GOTHICA'S DOWN" : "DOWN"
  (430, 268): 16 px sans '#cfd4de':
      Protect ? 'you kept her safe to wave ' + w.wave + ' — best: wave ' + max(protBest, w.wave)
              : 'made it to wave ' + w.wave + ' — ' + totalKills + ' killed'
  (430, 294): 13 px sans '#8b93a4': 'press R, or tap here to restart'
  ```
  In Protect mode `protNoteBest(w.wave)` runs first (so the best shown already includes this run).
- Under the overlay the last frame stays: Gothica lying on the floor with "Ugh..." over her (her bubble timer is
  frozen, so it never fades), the dead players simply not drawn.

Restarting (`restartGame` `L13541`): R (any time), the `Restart` / full-screen `Restart` buttons, the pad's Menu
button while over, or a tap/click within `|x − 430| < 220, |y − 260| < 60` while over (`L8707-8713`; host only; the
guest's R says "The host can restart the online game."). It builds a fresh lobby (`newWorld`), keeping a second player
if there was one, and `world.mode` is gone (the picker shows `gameMode` again). It never goes straight into a new run.

---

## 5. The victory dance (between waves)

### 5.1 When (`drawJared` `L10583-10600`)

Off by default: `T.celebrate (0)` "1 = flex between waves, 0 = keep running". With `T.celebrate = 1`, a player (or
Gothica, who's drawn the same way) dances when **all** of:
- `w.started && w.breather > 0 && !w.over && !cal.on` (the breather after a wave, including the 2.2 s before wave 1);
- none of the poses checked before it apply: falling off the tower, a punch, charging/throwing a potato, picking one
  up, reloading the spud gun, being blown away, rolling (those take precedence; the carry pose overrides it after);
- the character has victory art: `(IMG[skin] || IMG[p.ch] || IMG.jared).victory` (the weapon sheet first, e.g.
  `tyson_shotgun`).
It's only a picture: he can still run about, shoot and so on; the dance replaces the run cycle.

### 5.2 Which frame

```
elapsed = max(0, T.intermission (2.2) - w.breather)        // 0 at the start of the breather
n = number of victory frames in IMG[p.ch]  (the base character's sheet, 1 if it's not a list)
n >= 8:  play = [0,1,2,3,4,5,4,5,7,6,4,5,4,5,7,6]; f = play[min(15, floor(elapsed * 7))]
         ("relaxed, relaxed, fists, up, flex, grin, crossed, kiss")
n == 4:  f = elapsed < 0.15 ? 0 : elapsed < 0.3 ? 1 : 2 + floor(elapsed * 4) % 2     // then 2,3 alternating every 0.25 s
n >= 5 and p.ch != 'goth':  f = min(n - 1, floor(elapsed * 8))   // "a Sprite Maker victory: play it through once
                                                                    //  (fists up, hop, land) and hold the last pose"
otherwise (Gothica, whose 7 are copies of her run): f = 0, held
pose = { img: 'victory', flip: false, frame: f }   // drawn from the weapon skin's sheet if it has one
```
Size: the usual `T.radius × T.spriteScale × CHARS scale × pose scale × (T.altScale for new art)`, times
**`T.flexScale` (1.25)** ("the flex art is drawn slimmer than the run art"). Never flipped.

Note the breather can be longer than `T.intermission` (the janitor's visit, a debug 5.2 s), so `elapsed` sits at 0 for
the extra time; and it restarts at every breather.

The 8-frame rule is also used for a **punch** (`L10528`): a character with ≥ 8 victory frames shows frame 2 ("fists")
while `p.punch > 0`, flipped if `fx < 0`. No current character has 8 (so fists use the normal poses).

### 5.3 The victory frames in the manifest

| sheet (`CHARS.<id>.sprites.victory`) | frames | plays |
|---|---|---|
| `tyson` (old-art Tyson) | 4 (`assets/CHARS/tyson/sprites/victory_0..3.png`) | the 4-frame rule |
| `tyson_shotgun` | 4 | used when old Tyson holds the shotgun (counted from `tyson`'s 4) |
| `goth` | 7 | frame 0 held |
| `inky` | 7 | 0..6 at 8 fps, then holds 6 |
| `juicy`, `tyson2` (and their weapon sheets), `jared` | none | no dance: normal run/stand |

(`tyson` also has `victory_old`, unused.) The milestone 1 `CharFrames.victory_frame(id, elapsed)` already implements
5.2's rules (with `base_char(id) != "goth"`).

---

## 6. The secret preview and the bonus room (summary)

"Gary's second repair: host-owned cinematic, timed bonus room, exact run restore" (`L13791-14113`).

### 6.1 How you get in

- **The hidden route**: after the janitor has fixed the slot machine (`slot.broken = false`, "MACHINE IS LIVE"), shoot
  him once while he's walking out (`jn.phase === 'exit'`, first shot, `!w.slotSecret?.used`) (`L7718`): he goes down,
  gets up, trudges back (`secretReturn = true`) and swings at the machine; on his first swing `beginSlotSecret(w)`
  (`L7959`). Once per world (`slotSecret.used` lives on the world and `startGame` doesn't clear it; R makes a new
  world, so it comes back after a restart).
- **The secret preview**: a `<details>` "Secret preview" (`L178`) with a button "Preview Gary's second repair (2
  players)", shown only with the tweaks on ("Show tweaks", `localStorage 'smashed-tweaks'`, `applyTweaks` `L608`).
  Host only. It makes a fresh two-player run (`newWorld`, `addPlayer`, `startGame`), sets wave 1, a live machine, Gary
  swinging at it, the players 120 to each side and 150 below it, and calls `beginSlotSecret` at once (`L14099-14112`).
  "Restart returns to the lobby."

### 6.2 Phases (`step` `L13860`, `render` `L14050`)

`w.slotSecret = { used, phase, t, room, saved, origins, hazards, earned, nextDrop, nextCash, survived, joinPending }`.
`secretActive(w)` = it exists and `phase !== 'done'`. While active: the wave director, the janitor, potato growth,
Gothica, Start, the character picker, the test keys (`c j g n m p`) are all off; first person is off.

| phase | length | what happens |
|---|---|---|
| `intro` | 6.1 s | `beginSlotSecret` deep-copies the whole world into `saved` (janitor done, machine live), records each player's position in `origins`, zeroes velocities, clears the banner. The sim doesn't step (only `t`). Drawn: the arena with nobody in it, then `drawSuction`: three Gary heads in the cabinet window (t > 0.35), a cyan suction cone (alpha ramping from 0.5 s to 1.5 s), green notes spiralling in (1 to 4.6 s), the players (their `front_run[0]`, 80 tall, pivot at the boots) standing until 1.5 s, dragged feet first to the hatch 1.5-4.15 s (flailing arms, skid marks), shrinking into it 4.15-4.43 s; Gary (`JANITOR_SPRITES` `swing_hit` → `angry` → `pocket`) beside it; "..." at 3.6 s, "POP!" at 4.15 s, a note tucked away at 4.8 s, fade to black from 5.6 s. |
| `landing` | 0.85 s | `enterMachine` (`L13819`): clears every world list (enemies, bullets, coins, plants, rockets, blasts...), no nuke or waves, each player alive with full hp, blasters, at (375 / 485, 350) facing north. Players tumble in from (430, 505) along an arc 45 high; "YOU ARE THE PRIZE" over a fading dark wash; controls locked. |
| `bonus` | 20 s | the normal step runs (move, shoot, roll, collect), players held inside `BONUS_BOUNDS` (90..770 × 135..467). A coin every 0.23 s at a random spot. Skull stamps: one every `max(0.48, 1.05 − 0.025 t)` s near a random living player (±110, ±90), a 1.25 s warning ring (shoot the skull 35 above it, 3 hp, within 29, to break it: +3 coins), then it stamps (within 40: −1 hp, iframe 1). HUD: "HOUSE MONEY  Ns" top, "BANKED $n" and "COLLECT CASH / SHOOT SKULLS / DODGE STAMPS" bottom. Ends at 20 s (survived) or when everyone's down. |
| `payout` | 1.6 s | `finishMachine`: "THANK YOU FOR YOUR CUSTOM" (survived) or "FAULT DETECTED — EJECTING", a cyan-white flash from 1.05 s. |
| `return` | 1.15 s | `restoreFromMachine` (`L13841`): the saved world comes back exactly (the paused wave, its enemies, Gothica), each player keeps the higher of their saved and room cash, +$10 each if survived, placed 55 either side of the machine, 125 below, `grace 2`; enemies within 120 of a player pushed up 145 and stunned 1.5 s. "PLEASE CHECK THE PAYOUT TRAY", flash fading. |
| `done` | | `banner = 'GARY KEEPS THE CHANGE'` (1800 ms); a guest who tried to join meanwhile is added now (`joinPending`). |

Pictures: `MACHINE_ART.src` (manifest, `assets/MACHINE_ART_src.jpg`) drawn over the whole 860 × 520 as the room's
floor; `COG_ART.src` (`assets/COG_ART_src.png`) as four 200 × 200 cogs centred on the corners, each turning
`0.12 rad/s` (directions +, −, −, +, offsets 0, 0.2, 0.4, 0.6); 12 chasing lamps (9 × 3 at `x = 82 + 62 i`, y 109,
`#d9ffff` when `(floor(7t) + i) % 4 == 0`, else `#235e72`). Text with `secretText` (bold monospace, 4 px `#111620`
stroke). The HUD's top line, wallets and weapon bar hide while `room` is on.

Network: the snapshot carries `ss: secretPacket(w)` = `{ used, phase, t (3 dp), room, clock (w.t), origins, earned,
hazards, survived }`; the guest freezes interpolation (`age = 0`) while it's active.

Sounds: §8.2.

---

## 7. Phone controls in a run (top-down)

All touch handling is on the canvas (`pointerdown` `L8698`, `pointermove` `L8778`, `endPointer` `L8805`) in canvas
coordinates (860 × 520, so everything scales with the screen). Any touch sets `touchSeen = true` (which enables the
touch-only hints and buttons). Full screen (`goFullscreen` `L13626`) asks the phone to lock to landscape.

### 7.1 What a finger landing does, in priority order

1. Game over (host): within `|x − 430| < 220, |y − 260| < 60` → restart.
2. The zoom button (r + 6), the eye button (lobby), the hair/mirror/blackjack/cards/shirt/sit buttons (lobby).
3. The JUMP button (trampoline; lobby).
4. **The E button** (`carryButton`, r + 8): in a Protect run, pick up / put down (§2.5).
5. **The weapon bar**: a slot → start a drag (tap selects, drag swaps).
6. (Lobby first person: the right half looks/fires, §7.3.)
7. **The sticks**: the left half (`x < 430`) is the move stick, the right half the aim stick. If that side's stick is
   already held, or both sticks are held (a third finger anywhere), it's a **roll tap** instead: `rollTap = true`,
   cleared after 200 ms if nobody used it (`setTimeout`), and read once by `consumeRollTap` (`L8610`) when building the
   input (so a tap never rolls twice or gets lost).
8. Otherwise the stick starts where the finger landed (a floating stick): `ox, oy` = that point, `dx = dy = 0`, the
   pointer captured. With the launcher in hand the touch is also remembered in `TAPS` (tap to fire); with the potato
   throw in hand in `LOBTOUCH` (tap or hold to throw).

### 7.2 The sticks (`STICK_MAX = 52`, `L8668`)

Moving a finger: `(dx, dy) = (finger − origin)`, clamped to length 52, then divided by 52 (so −1..1). Lifting it
(or `pointercancel`) releases the stick (`active = false, dx = dy = 0`). Losing window focus clears both.

Drawn (`drawStick` `L11385`) only while active: a 52-radius ring at the origin, 2 px `#4b5468`; a 20-radius knob at
`origin + d × 52`, filled `rgba(224,71,63,0.55)` (move, red) or `rgba(246,209,122,0.55)` (aim, gold).

In `localInput0` (`L8985`):
- **Move**: if the move stick is active and `|d| > 0.12`: `(mx, my) = (dx, dy)` (analogue, so a small push walks
  slowly up to the cap). This overrides WASD; a pad's left stick (dead zone 0.2) overrides it in turn.
- **Aim and fire**: the aim stick **is** the trigger: while it's held, `shoot = true`, `st = true` (stick aim), aim
  `(ax, ay) = (dx, dy)`, zeroed if `|d| < 0.06` (a finger resting at the centre fires the way he faces). Exceptions
  for the potato throw: a finger held still (moved < 12) on the aim side with the throw in hand puts the landing spot
  under the finger (`lt` = that world point via `screenToWorld`, shoot while held, thrown on release); a quick tap
  (< 250 ms, moved < 12) on the move side throws it there at once (`lobTap`, kept 130 ms). For the launcher: a quick
  tap (< 300 ms, moved < 12) anywhere fires a rocket at that spot (`tapShot`, an id that increments and is kept 150 ms
  so a network tick can't miss it).
- **Roll**: `keys.shift || consumeRollTap() || pad B/RB/LT`.
- `tc: touchSeen` rides along (the launcher uses it to tell a phone from a keyboard).

### 7.3 First person on a phone (HTML: lobby only)

From b324 (`L3593-3619`): the left thumb walks with the move stick (as always, drawn even in first person); on the right
half, a drag looks round (`turn += Δx × 0.0075`, `lookY = clamp(lookY + Δy × 0.004, ±0.6)`), and a finger that starts
on **FIRE** (`(705, 405)`, r 40, + 10 grace) fires as long as it's down, even when it slides off to look. FIRE: fill
`rgba(14,16,22,0.5)` (`rgba(224,71,63,0.6)` while held), 2.5 px ring `#e0473f` (`#ffd0c8` held), a crosshair and
"FIRE" (bold 11 px) in `#ffb3a8` (white held). For the first 6 s: "thumb here to walk" at (215, 156) and "drag here to
look" at (645, 156), bold 14 px gold with a shadow, fading over the last 1.5 s. In first person the aim stick also turns
you (`2.8 × dx` rad/s).

### 7.4 Phone-specific notes

- b325: the browser's pointer lock is for the mouse only; a touch releases it (it froze every finger on phones).
- b326: any touch, even on a button, counts as a phone being used.
- The touch zones are the canvas halves, not the screen halves (the canvas is letterboxed).
- There's no on-screen Start button inside the canvas while the poster is off: on a phone you press the page's Start
  button (or the full-screen bar's).

---

## 8. Sounds

### 8.1 The synthesiser (`L11152-11242`)

Everything is made at runtime with Web Audio. `audioInit` (`L11194`) makes the context on the first click, tap or key,
a master gain of **0.5** (0 when muted by the Sound button), and one 1.2 s buffer of white noise.
- `sTone(dur, f0, f1, gain, wave)` (`L11228`): an oscillator of type `wave` (default sine) at `f0`, exponential ramp
  to `max(20, f1)` over `dur` (if `f1`), through a gain starting at `gain` with an exponential ramp to 0.0008 over
  `dur`; stops at `dur + 0.02`.
- `sNoise(dur, freq, q, gain, type, sweepTo)` (`L11213`): the noise buffer (looped) through a biquad filter of `type`
  (default lowpass) at `freq`, Q = `q || 1`, its frequency ramped exponentially to `max(40, sweepTo)` over `dur` (if
  given), gain `gain` → 0.0008 exponentially over `dur`.
- `vary(n, amt = 0.12)` = `n × (1 + (random − 0.5) × amt)`.

### 8.2 What this system plays

From the world's `fx` events (`playEventSounds` `L11371`, on the host from `world.events` every frame and on the guest
from the snapshot's `x`):
- `FX.HURT` (a player or Gothica hit): `SFX.hurt` = `sTone(0.30, 420 → 120, 0.34, sawtooth)` +
  `sNoise(0.16, 1600 → 300, Q 1.4, 0.20, bandpass)`.
- `FX.DOWN` (a player down, or Gothica down = game over): `SFX.down` = `sTone(0.75, 300 → 55, 0.40, sawtooth)` +
  `sNoise(0.5, 700 → 90, Q 1, 0.26, lowpass)`.
- `FX.WALL` (Gothica eating) makes no sound.
- Picking her up, putting her down, her speech, the banners, the HUD, mode picking, game over itself: **no sounds**.

The bonus room (`secretAudio` `L13973`), once per beat change, on whichever screen draws it (host and guest):

| beat | when | sound |
|---|---|---|
| `hammer` | intro t < 0.5 | `sNoise(0.12, 1400 → 250, Q 2, 0.3, bandpass)` + `sTone(0.1, 130 → 60, 0.2, square)` |
| `reels` | intro 0.5-1.5 | `sTone(0.6, 650 → 170, 0.12, triangle)` |
| `suction` | intro 1.5-4.15 | `sNoise(2.6, 180 → 1300, Q 1, 0.15, lowpass)` + `sTone(2.6, 65 → 280, 0.07, sawtooth)` |
| `pop` | intro 4.15-4.6 | `sTone(0.13, 600 → 50, 0.3, sine)` + `sNoise(0.1, 1400 → 120, Q 1, 0.22, lowpass)` |
| `quiet` | intro 4.6+ | nothing |
| `landing` | landing | `sNoise(0.15, 450 → 70, Q 1, 0.2, lowpass)` |
| `bonus`, `return` | | nothing |
| `payout` | payout | `sTone(0.35, 440 → 880, 0.14, triangle)` |

---

## 9. Over the network (for milestone 4)

The host runs everything; the guest draws `worldFromSnapshot(snap, age)` (`L8403`) and sends its input. Fields this
system needs (`snapshot` `L8300`):

| field | contents | guest side |
|---|---|---|
| `md` | `w.started ? (w.mode \|\| 'classic') : gameMode` (string): the run's mode, or the host's pick in the lobby | `view.mode`; the guest's picker shows it, greyed |
| `gt` | Gothica, or null: `[x, y, round(hp×10), max, round(fx×100), round(fy×100), moving 0/1, round(odo), carrier, round(hurt×100), face 0/1, carryCd>0 ? 1 : 0, bubble ? [text, round(t×100), round(dur×100)] : null, round(ix×100), round(iy×100)]` | rebuilt with `hp/10`, `odo + (moving ? PROT.walk × age : 0)`, `hurt − age`, the bubble's `t + age`, `npc/prot/alive = true`, `vx = vy = 0` (`L8416-8420`) |
| `gd` | `w.gothDown` 1/0 | `view.gothDown` |
| `o`, `w`, `br`, `st` | over, wave, `round(breather × 100)`, started | the game-over overlay, the top line, the wave banner, the victory timing |
| `fl` | floaters `[x, y, text, round(t×100), col]` | the "+2" and cash numbers |
| `p[i]` | per player: `[7]` hp, `[8]` alive, `[9]` iframe×100, `[13]` kills, `[14]` character index, `[15]` coins, `[16]` weapon index (`blaster, shotgun, spud, launcher, fists, lob`), `[17]` wTime×10, `[28]` ammo, `[40]` rockets, `[36]` roll×100, ... | pips, wallets, ammo, the bar, the "left/killed" line |
| `e` | enemies (their count is "left") | |
| `ss` | the bonus room packet (§6) | |
| `x` | `fx` events `[kind, x, y]` (≤ 40 a step) | bursts and the hurt/down sounds |

Guest input fields this system uses: `sq` (E counter: pick up / put down in a Protect run), `roll` (includes roll
taps), `shoot`/`ax`/`ay`/`st` (the aim stick), `lt/lx/ly` (finger landing spot), `tap/tx/ty` (launcher tap), `tc`.

Not sent (each machine has its own): `gameMode` and `protBest` (localStorage), the banner (a bug: the guest never sees
banners), the help overlay, the hotbar order, the zoom, the sticks.

Two players, Protect: both can carry her (if both are carriers), the guest through `sq`. Restart is the host's.

---

## 10. History worth keeping (the `bNNN` notes)

- **b294**: game modes added: ◀ ▶ beside Start pick the mode; the host's pick is played, the guest sees it greyed;
  the last pick is remembered. Protect Gothica added: `protTarget` (enemies go for her if nearer), the batter's swing
  hits her if she's in the arc, shrapnel hurts her, the guest picks her up/puts her down through `sq`, she's sent in
  the snapshot (`gt`, `gd`, `md`), the run's Gothica replaces lobby Gothica, the first-breather hint.
- **b224**: the build/network readout and the test buttons only with `?debug`; players get just the wave count.
- **b222**: the dark band and start text only over the title poster, not in the lobby. (The poster is now off.)
- **b223**: the weapon bar bigger and at the bottom.
- **b270**: the zoom button moved down, clear of the full-screen buttons.
- **b293**: a weapon pick or roll tap from a frame too short to run a sim step (above 120 fps) is carried to the next
  (`carryInput` `L12704`); `localPlayer` fixed for the guest (no weapon bar before).
- **b312**: the tweaks (sliders, the secret preview, C and J) hidden until "Show tweaks".
- **b316**: the controls help (Tab / d-pad down), shown by itself the first time a pad is used.
- **b317**: the pad's right stick only aims, RT fires; player 2's roll isn't Enter (Enter starts the run).
- **b324, b325, b326**: phones: first person with a stick, drag-to-look and FIRE; pointer lock only for the mouse;
  any touch means a phone; the JUMP button.
- **b293** (secret): rockets and blasts cleared on entering the machine "or one in the air went off in here".

## 11. Edge cases and quirks (as the HTML has them)

1. Protect, all players down: the run goes on; enemies all chase her; players reappear next to her 4 s after each went
   down (or at the next wave start, in the middle, whichever first). Their respawn ignores enemies standing there
   (they have `grace 1.5`).
2. She can go down during the breather only to shrapnel still flying, or a batter mid-swing; nothing spawns then.
3. "kept her safe to wave N" counts the wave that was running (or the one just cleared, in its breather).
4. `protNoteBest` is called every drawn frame of the game-over screen (harmless; saves only on improvement).
5. The game-over screen freezes her bubble ("Ugh...") and the shake.
6. Carrying: put down on his far side when he faces left (`face` true → `+20`).
7. Over the network her `carryCd` is sent only as 1/0 and her `hurt` is counted down by the packet's age, so the
   guest's "PICK UP" prompt and her blinking match the host's closely enough; nothing else of hers is predicted.
8. The E prompt over her uses `actKey()` (E or A), the first-breather hint always says "E".
9. Classic run: E does nothing (nothing to pick up); the round button has no label so it's hidden.
10. The victory dance is off (`T.celebrate 0`), and no current character has the 8-frame punch art.
11. Banners are host-only (a page global, not in the snapshot).
12. The HUD shakes with the screen.
13. During the bonus room she's frozen where she stood and still drawn in the intro and in the room (she isn't
    removed); she's restored with the rest of the saved world.
14. Gothica as a *player* character in Protect mode: allowed; there are then two Gothicas (the NPC and you). She
    can't carry herself (not a carrier).
15. The mode can't change in a run or while calibrating; `restartGame` drops `world.mode`, so the next run uses
    whatever the picker shows.

---

## 12. In Godot

### 12.1 What it builds on (milestone 1 contracts in `godot/scripts/`)

- `GameData` (autoload): `data["MODES"]`, `data["PROT"]`, `data["T"]`, `data["CARRIERS"]` (exported as `{}` because
  it's a `Set` in the HTML: hard-code `["juicy", "jared"]`), `data["P_COLOURS"]`, `data["ARENA"]`, `data["FX"]`,
  `data["ETYPE"]`; `manifest` (`CHARS.goth`, `CARRY_FRAMES@9741`, `MACHINE_ART.src`, `COG_ART.src`,
  `JANITOR_SPRITES`); `tex(path)`; `world_to_3d` / `from_3d`; `UNIT` 0.025.
- `Player` (CharacterBody3D): `char_id`, `facing`, `moving`, `odo`, `html_pos()`, `place()`, `frozen`, `vel`,
  `roll`, `steer`, `look_ang`/`look_y`, `rig`, `controls_enabled`, `focus`/`focus_label`, `use()`, `read_steer()`
  (Input actions `move_*`), `interacted` signal.
- `CharSprite`: `char_id`, `facing`, `moving`, `odo`, `action` (`""`, `"roll"`, `"tumble"`, `"victory"`), `roll_t`,
  `air`, `modulate`, `update_view(camera)`; `CharFrames.victory_frame(id, elapsed)`, `draw_height(id, key)` (already
  × `T.flexScale` for victory).
- `CameraRig`: `mode` (`TOP_DOWN` / `FIRST_PERSON`), `mode_changed`, `target`, `camera()`, `in_run` (2× → 1.5×),
  `bounds`, `mouse_captured()`, `capture_mouse`.
- `Interactable`: `reach`, `label_for(player)`, `act(player)`, `ground_distance()`; the player picks the nearest with
  a label; the M1 `Hud` shows `"E: " + label` and the round pink E button (bottom right, like `carryButton`).
- `Hud` (M1, `scripts/ui/hud.gd`): build label, view label, E prompt and button, crosshair, character picker. Its
  keys 1-3 pick a character (`number_keys_pick`): **turn that off in a run** (1-6 are weapons).
- Input actions in `project.godot`: `move_up/down/left/right`, `interact`, `roll`, `toggle_view`. The weapons spec
  asks for `fire`, `weapon_1..6`, `weapon_prev/next`. This system needs: `start_run` (Enter, pad Start/Menu),
  `restart` (R; pad Start/Menu while over), `help` (Tab, pad d-pad down), `zoom` (Z, d-pad up, already handled in
  `CameraRig` by key), `ui_left/ui_right/ui_accept` for the picker. Ask the Putting-it-together task to add them.

### 12.2 Files (proposed; milestone 2, owned by the modes/HUD task)

| file | class | job |
|---|---|---|
| `scripts/modes/run_modes.gd` | `RunModes` (static + a small `ConfigFile`) | `MODES` from `GameData`; `pick` (persisted in `user://settings.cfg` `[modes] mode`, like `smashed-mode`); `step(d)` with the 1.2 guards; `best_protect` (`[modes] protect_best`) and `note_best(wave)`; signal-free (the picker polls or `RunModes.changed` via a tiny autoload if the main task prefers one). |
| `scripts/modes/protect_sim.gd` | `ProtectSim` (RefCounted) | Gothica's state (2.2) as fields in HTML units; `make(npc_x, npc_y, slot_y)`; `step(dt, sim)` exactly 2.6; `hurt(dmg, n) -> bool` (2.4); `target_for(e_pos, target, best)` (2.3); `can_carry(p)`, `toggle_carry(p)`, `set_down(cool)` (2.5); `pack()`/`unpack(a, age)` (the `gt` array, 9). Pure data: stepped by `ArenaSim` (enemies spec 12.1) in the HTML order, right after the plants. Uses `randf()` for her wander (host only). |
| `scripts/modes/protect_view.gd` | `ProtectView` (Node3D) | draws `ProtectSim` (12.4). |
| `scripts/modes/goth_carry.gd` | `GothCarry` extends `Interactable` | E on her in a run (12.5). |
| `scripts/ui/wave_hud.gd` | `WaveHud` (CanvasLayer) | the run HUD: §3.1, 3.2, 3.5, 3.6 (screen part), 3.8, §4. The enemies spec names this file too: **one file, one owner**, this spec gives its full contents. |
| `scripts/ui/mode_picker.gd` | `ModePicker` (Control) | ◀ name ▶ and Start, in the lobby (12.6). |
| `scripts/ui/touch_controls.gd` | `TouchControls` (Control, full rect) | the sticks, roll taps, FIRE, the E/roll buttons on phones (12.8). |
| `scripts/modes/bonus_room.gd`, `bonus_room_view.gd` | `BonusRoom` (RefCounted), `BonusRoomView` (Node3D + CanvasLayer) | §6 (later in milestone 2, or milestone 3 with the slot machine). |

No `.tscn` needed beyond what `main.gd` builds in code (milestone 1 builds nodes in code): `ArenaSim` owns a
`ProtectSim` when the mode is protect; `main` adds `ProtectView`, `WaveHud`, `ModePicker`, `TouchControls`.

### 12.3 Contract requests (agree before building; don't edit other tasks' files)

- **Player** (with the weapons and enemies requests): `id` (0/1), `alive`, `hp`, `iframe`, `grace`, `kills`,
  `coins`; `speed_mul: float = 1.0` applied to the top speed cap (carrying: 0.7; the speed boost 1.55; they multiply);
  `can_shoot` / `can_roll` (false while carrying); `revive_at(x, y, hp, grace)`; `down_t` can live in `ProtectSim`
  (a per-player array) instead of on the Player.
- **CharSprite**: an action `"carry"` (the `CARRY_FRAMES` pictures, walk built from the stride, flip by her `face`,
  `T.carryScale`, anchor 72/160; owned with lobby Gothica's carrying, M1 "Trampoline and Gothica" task); `skin_id`
  (weapons); and **`victory_t`** settable from outside (the HTML's `elapsed = intermission − breather`, not "time since
  the action started": they differ when the breather is longer than 2.2 s), plus counting frames on the base
  character's sheet while drawing from the skin's.
- **Lobby Gothica** (the NPC task): read her current position at Start (`newGoth` uses it), hide her during the run,
  put her down if someone's carrying her at Start (`lobbyGoth` → `putGothDown`).
- **CameraRig**: nothing new; `in_run = true` in a run; force top-down during the bonus room (12.9).

### 12.4 Gothica in the run (`ProtectView`)

- A `CharSprite` child (`char_id = "goth"`, `shaded` like the players), positioned at `world_to_3d(g.x, g.y)` each
  frame, `facing = (g.fx, g.fy)`, `moving`, `odo` from the sim; `update_view(camera)` so she turns correctly in both
  views. Her jiggle × `T.npcJiggle` goes with the lobby NPC's implementation.
- Blink: `visible = not (g.hurt > 0 and int(floor(g.hurt * 20)) % 2 == 0)`.
- Down: hide the CharSprite and show a flat `Sprite3D` of `CHARS/goth/sprites/front_run_0.png` lying on the floor
  (rotated so her head points along +x, as the HTML rotates her 90°), 80 units long, nearest filtering, with the
  contact shadow; it's what the game-over screen shows under the overlay.
- Hidden while carried (`g.carrier >= 0`): the carrier's CharSprite shows `"carry"`.
- **Health bar**: two quads (or one `Sprite3D` with a tiny shader) billboarded above her head at about 66.5 units up
  (the HTML's `y − 66.5` on screen is height in 3D), 40 × 5 units with a 1-unit `rgba(0,0,0,0.65)` back; fill colour
  by fraction (> 0.5 `#f7a8ff`, > 0.25 `#f6d17a`, else `#e0473f`), anchored left. `no_depth_test = true` and a high
  `render_priority` so it reads over the floor clutter; scale with the camera like the HTML (it's world space).
- **"E: pick up"**: let `GothCarry` drive the M1 HUD prompt instead (the HUD already shows "E: pick up" and the round
  button); additionally a small `Label3D` over her (bold, white, shadow, `billboard = ENABLED`, `no_depth_test`,
  `fixed_size` false) at 76.5 units up while `can_carry(local player)`, with "A" when the last device was a pad.
- **Bubble**: a `Label3D` (or a 2D `PanelContainer` placed with `camera.unproject_position()` at 92 units up) styled
  as §2.7: cream `#fffdf6` box, 2 px `#1c1a22` border, radius 6, dark text, a tail, fade in 0.12 s / out 0.4 s. The 2D
  panel is closer to the HTML and works in both views (hide it when `camera.is_position_behind()`); the HTML's first
  person version (`shroomWords` `L4080`) draws it 14 px, white 0.95, radius 8, text `#2a1f3e`, at height 92 + dz.
- Floater "+2": the shared floaters view (cash numbers), `#7dff9a`.
- FX bursts: the shared `fx` view.

### 12.5 Carrying (`GothCarry`)

An `Interactable` child of `ProtectView`, placed at her position every frame (at the carrier's when carried):
```gdscript
func label_for(p) -> String:
    if sim.over or not p.alive: return ""
    if g.carrier == p.id: return "PUT DOWN"
    return "PICK UP" if protect.can_carry(p) else ""
func act(p) -> void:
    if is_host: protect.toggle_carry(p) else: net.send_sq()    # milestone 4: the guest's counter
```
`reach = T.carryRange` (46); `can_carry` re-checks the distance in HTML units (`ground_distance`). This keeps E, the
pad's A and the M1 round button working with no special case. In a Classic run there's no `GothCarry`, so nothing
shows. While carried, the Player gets `speed_mul *= 0.7`, `can_shoot = can_roll = false` (from `ProtectSim`, each
step).

### 12.6 The mode picker (`ModePicker`)

In the lobby, on the HUD (not a web-page DOM bar): `◀  Classic  ▶   START` at the top, like the HTML's row; the name
in `#f6d17a` 600-weight, 118 px minimum width; Start in `#e0473f`. Fully usable without a mouse (plan: menus usable
with a pad): it takes focus in the lobby, `ui_left`/`ui_right` (and the d-pad) step the mode, `ui_accept`/Start/Enter
starts. Disabled and greyed (showing the host's mode from `md`) for the network guest, during a run, and while
calibrating. A one-line description under the name helps on first sight (new: "Classic: survive the waves" /
"Protect Gothica: keep her alive; potatoes heal her"). Show "Best: wave N" under it when Protect is picked and
`best > 0` (new; the HTML only shows it at game over).

A clear start prompt in the lobby (new, the HTML has none since the poster went): bottom centre, "Enter / Start to
begin" (with the device's own glyph), hidden in a run.

### 12.7 The HUD (`WaveHud`)

A `CanvasLayer` (layer above the M1 `Hud`), the same in both views. Layout from the HTML's 860 × 520 canvas, placed
with anchors so it fits any screen (the project is 1280 × 720, `canvas_items`, `expand`):
- **Top-left line** (§3.1): anchor top-left, 26 / 38 HTML px → about 2 % / 7 % of the height; 12 px monospace
  `#6d7486` scaled by `viewport_height / 520`.
- **Wallets** (§3.2): under it, bold 17 px monospace, player colours; ammo at +62 px.
- **Wave banner** (§3.5) and the Protect hint, centred.
- **Big banner**: a `Banner` API: `show_banner(text, secs)`; the sim raises it through an event (`banner` signal /
  network event, so the guest sees it too: a deliberate fix); bold 34 px gold with a 5 px dark outline
  (`font_outline_color rgba(20,22,28,0.9)`, `outline_size 10`), at 90/520 of the height.
- **Floaters** in screen space? No: they're world things (Label3D billboards, `fixed_size`, rising 34 u/s); the HUD
  doesn't own them.
- **Weapon bar**: `weapons.md`'s `Hotbar` control; `WaveHud` only hides it when over / in the bonus room.
- **Game over** (§4): a full-rect `ColorRect` `rgba(20,22,28,0.78)` and three centred labels; the restart area is a
  button (440 × 120 HTML px around the centre, plus the `restart` action and the pad's Start); on show: release the
  mouse capture (`CameraRig.capture_mouse` / `Input.mouse_mode = VISIBLE`) and call `RunModes.note_best(wave)` once
  (not every frame). Freeze the sim but let the shake decay (fix).
- **Help overlay** (§3.8): a `PanelContainer` with the rows for the last-used device; Tab / d-pad down.
- **Screen shake**: shake the `Camera3D` (both views) and offset the HUD root by the same random amount for parity;
  in first person use a small rotation (enemies spec 12.8) and leave the HUD still.
- Pad rumble on hurt (§3.9): `Input.start_joy_vibration(device, 0.35, 0.6, 0.14)` / `(…, 0.35, 1.0, 0.42)`.
- Text sizes: multiply the HTML's px by `viewport_height / 520`, with a floor of 12 px on phones.

### 12.8 Phone controls (`TouchControls`)

A full-rect `Control` under the HUD `CanvasLayer` with `mouse_filter = PASS` (so the hotbar and buttons on top get
their taps first), reading `InputEventScreenTouch` / `InputEventScreenDrag` by `index`:
- Left half: the floating move stick; feed it into the Player through the existing actions:
  `Input.action_press("move_right", max(0, dx))`, `move_left` with `max(0, −dx)`, etc. (the Player already reads
  `get_action_strength`), dead zone 0.12, `STICK_MAX = 52 × viewport_height / 520` px.
- Right half: the aim stick: sets the aim vector the weapons spec's `InputFrame` reads (`aim_stick = Vector2(dx, dy)`,
  `st = true`) and holds `fire` (`Input.action_press("fire")`) while down; |d| < 0.06 → fire straight ahead. The
  potato-throw and launcher tap rules of §7.2 (still finger = landing spot, quick tap = throw/fire there) belong here
  too, converting the finger to the ground with the camera's ray (the M1 Player's `_mouse_ground` way).
- Roll: a second finger on a busy half or a third finger anywhere → `Input.action_press("roll")` held ~0.1 s, then
  released (the Player reads `is_action_pressed` each frame; the HTML's 200 ms + consume-once becomes "pressed for a
  few frames, roll starts once" because the Player only rolls when `roll <= 0 and roll_cd <= 0`). Add a visible
  **ROLL** button too (new; tablets especially): above the E button.
- Draw: the 52-unit ring (`#4b5468`, 2 px) and the 20-unit knob (move `rgba(224,71,63,0.55)`, aim
  `rgba(246,209,122,0.55)`) only while held.
- The E button is the M1 `Hud`'s (bottom right, pink); keep it.
- Shown when a touch was the last input (plan: the game notices the last device), hidden for keyboard/mouse and pad.
- Sizes scale with the screen; on tablets (short side > ~700 px) cap the stick at about 18 mm.
- Landscape: set `display/window/handheld/orientation` to landscape (main task's `project.godot`).

### 12.9 First person

The HTML has no first person in a run (`fpCan` needs `!started`); the plan wants everything in both views, so:
- **Allow V in a run.** The run's systems are all 2D on the ground; first person is only a different camera.
- **HUD**: the same `WaveHud`. Add your own pips (you can't see your head): a row of 5 (or more) 10 × 10 px squares in
  your colour under your wallet line (new). Keep the crosshair (M1 `Hud`).
- **Gothica**: her billboard bar and bubble work as they are (12.4). Add, in Protect mode only, a **compact bar in the
  HUD** (top centre, "GOTHICA" in `#f7a8ff` 12 px and a 160 × 8 bar with the same colours), since she's often behind
  you; and a **pink chevron at the screen edge** pointing to her when she's off screen, flashing red for 0.9 s when
  she's hurt (new). These can show in top-down too when she's outside the view (top-down at 1.5× doesn't show the
  whole arena).
- **Carrying in first person**: no hands (you can't shoot); show a small "CARRYING GOTHICA" with a 4 s countdown bar
  bottom centre above the weapon bar (new; top-down shows the carry pose instead). Optionally a bob of her picture at
  the bottom of the screen (`CARRY_FRAMES` is side-on art, so skip it unless new art appears).
- **E prompt**: the M1 `Hud` puts "E: pick up" under the crosshair in first person; `GothCarry` needs her within 46
  units, which in first person is "at your feet": also accept her when she's within 46 and roughly in front
  (`|angle| < 60°`), or widen the reach to ~60 in first person (a small deliberate change).
- **Victory dance**: your own isn't visible; your partner and the top-down view see it. No change.
- **Game over**: release the mouse, show the overlay; the camera stays where it was. With Gothica down, the down pose
  is visible if she's in view.
- **The bonus room**: the cinematic and the room are screen-space top-down art; switch the rig to top-down at
  `beginSlotSecret` and back to the previous mode at `done`.
- **Touch in first person**: as the HTML's §7.3 (left stick walks, right half drags to look with 0.0075 rad/px across
  and 0.004 rad/px up/down, FIRE at the bottom right left of the E button, the hints for 6 s), plus the ROLL button.
  Feed look into `Player.look_ang/look_y` (the M1 rig's fields).

### 12.10 The bonus room in Godot (summary)

`BonusRoom` keeps the phases and timings of §6 and is stepped by `ArenaSim` in place of its normal step while active
(the HTML's `step` wrapper). The deep copy becomes `ArenaSim.save_state() -> Dictionary` / `load_state(d)` (the same
data as the snapshot, plus the RNG seed and the queue), which every sim-side system must support (enemies, weapons,
coins, `ProtectSim`). The room: hide the arena's 3D floor and show `MACHINE_ART` as the floor (an 860 × 520 unshaded
quad, nearest filter), four `COG_ART` sprites turning at the corners, the 12 lamps; players clamped to
`BONUS_BOUNDS`; the skull stamps as small 3D/billboard props with the warning ring on the floor; the cinematic as a
2D overlay (`drawSuction`'s shapes with `draw_*`, the players' `front_run_0` pictures, Gary's `JANITOR_SPRITES`). The
"Secret preview" button lives in the tuning/tweaks panel (debug-only), not in the main UI.

### 12.11 Network (milestone 4)

- `ProtectSim.pack()` returns the `gt` array exactly as §9 (same order, same rounding); `unpack(a, age)` does the
  guest's extrapolation. Send `md` and `gd` alongside. The guest's view reads only the unpacked state.
- Add `bn: [text, ms_left]` (or a `banner` event in `x`) so the guest sees banners (fix).
- The guest's E in a run: a counter `sq` in the input, acted on once per change by the host (keep the "first value
  is only recorded" rule, so a guest joining mid-run doesn't toggle).
- `RunModes.pick` and the best wave stay local.

### 12.12 Checks against the HTML

- Picker: ◀ ▶ cycle Classic ⇄ Protect Gothica, remembered after a reload; greyed in a run; Start disabled in a run.
- Protect, wave 1: Gothica appears where lobby Gothica was (clamped to 88..772 × 180..432); the breather shows
  "WAVE 1 / 6 incoming — …" and the pink hint line.
- She strolls at 38 u/s, pauses 1.2-3.4 s facing you; a batter within 130 sends her running at 110 with a "Help!"
  (at most every 2.5 s) for at least 0.8 s after it's out of range; she never goes above y = 150.
- A grunt touching her: −1, she blinks for 0.9 s and slides; a brute: −2; a batter only when it swings at her.
- Hurt, she walks at 68 u/s to a ripe potato within 280, eats it within 14: "+2" in green, "Mmm"/"Yum!", hp +2.
- Juicy Jared within 46: "E: pick up"; E: she's in his arms, he can't shoot or roll, his top speed 182; after 4 s
  "Put me down!" and she can't be picked up for 1.5 s; E again puts her down at once (0.3 s cooldown).
- A player down: back after 4 s beside her with 5 hearts, untouchable for 1.5 s.
- Her hp to 0: "Ugh...", everything stops, "GOTHICA'S DOWN / you kept her safe to wave N — best: wave B".
- Classic: all players down → "DOWN / made it to wave N — K killed"; R or a tap on the message → the lobby.
- HUD: "wave N   M left   K killed" top left (12 px grey), "$2500 ● 20" in red below (and the second player's in
  blue), the bar at the bottom, banners gold at the top.
- Compare with `godot/reference/wave.png`.

---

## 13. HTML function index

| what | where |
|---|---|
| mode picker DOM (`modePrev/Name/Next`, `fsMode*`), styles | L130, L218, L28-30 |
| `MODES`, `gameMode`, `shownMode`, `stepMode`, `updateModeUI` | L12856, L12857-12858, L12859, L12860, L12867 |
| picker wiring, Start buttons enable | L13608-13619 |
| `startGame` (mode part L13554-13557), `restartGame` | L13549, L13541 |
| `PROT`, `PROT_SAY`, `protSay`, `protTop` | L12882, L12896, L12897, L12899 |
| `newGoth`, `gothHeldBy`, `gothFace`, `protCanCarry`, `protSetDown`, `protectCarry` | L12900, L12909, L12914, L12915, L12920, L12928 |
| `protHurt`, `protTarget`, `stepGoth`, `drawGothBar`, `protBest`, `protNoteBest` | L12938, L12951, L12957, L13057, L13064, L13066 |
| `CARRIERS`, `NPC_GOTH` | L9858, L9853 |
| carrying blocks shoot/roll, the guest's `sq`, the speed cap | L7172, L7175-7178, L7511 |
| enemies' target, the batter hitting her, shrapnel hitting her | L7553-7559, L7600-7602, L7816-7819 |
| game over set (Classic) | L7597, L7683, L7833 |
| E key (host / guest) in a run | L8653, L8654 |
| `carryButton`, `drawCarryButton`, `toggleCarry`, `lobbyAction`, `lobbyLabel` | L10109, L10128, L10138, L10140, L10088 |
| her drawing in the cast, the pick-up hint | L12221-12252 |
| `drawSpeech`, `drawThrownGoth`, `shroomWords` (FP bubble) | L1134, L10370, L4069 |
| victory pose, punch pose, carry pose, `flexScale` | L10583-10600, L10528, L10643-10660, L10663 |
| `renderBase` HUD: sticks/buttons, top line, wallets, wave banner, floaters, touch hint, banner, game over | L12441-12457, L12458-12463, L12465-12479, L12557-12577, L12617-12629, L12639-12663, L12666-12676, L12677-12695 |
| hp pips | L12386-12396 |
| `HOTBAR`, `hotbarGeo`, `hotbarSlotAt`, `selectSlot`, `drawHotbar` | L9881, L9925, L9929, L9936, L9942 |
| `banner`, `giveWeapon`, `award` | L6876, L6878, L6278 |
| `zoomWanted`, `camFollow`, `zoomButton`, `drawZoomButton` | L8520, L8521, L8542, L8543 |
| `HELP`, `HELP_PAD`, `HELP_KEYS`, `drawControlsHelp`, `actKey` | L8888-8905, L8906, L8882 |
| pad polling (Menu, A, rumble) | L8952-8983 |
| touch: `rollTap`, `touchSeen`, `consumeRollTap`, `STICK_MAX`, sticks, `pointerdown/move/up` | L8582, L8585, L8610, L8668-8670, L8698, L8778, L8805 |
| `localInput0`, `localInput1` | L8985, L9038 |
| `drawStick` | L11385 |
| first person on phones: `FP_TOUCH`, `fpFireButton`, `drawFpFireButton`, `fpCan` | L3595, L3596, L3600, L3573 |
| `fx`, `FX_LOOK`, `SFX`, `playEventSounds`, `sTone`, `sNoise`, `audioInit` | L6238, L6073, L11310, L11371, L11228, L11213, L11194 |
| `snapshot`, `worldFromSnapshot` | L8300, L8403 |
| bonus room: `secretActive`, `secretPacket`, `beginSlotSecret`, `enterMachine`, `finishMachine`, `restoreFromMachine`, `step`, `drawMachineFloor`, `drawSuction`, `drawBonusHazards`, `secretAudio`, `render`, the preview | L13797, L13798, L13805, L13819, L13835, L13841, L13860, L13928, L13986, L14034, L13973, L14050, L14099 |
| the hidden route (shooting Gary on his way out; his swing) | L7718, L7959 |
| `DEBUG`, `TWEAKS`, `applyTweaks` | L604, L606-611 |
