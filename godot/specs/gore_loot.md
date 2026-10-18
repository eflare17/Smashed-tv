# Gore and loot: porting spec

Source: `Smashed.html` (build b331). Everything here was read from the code; line numbers are the HTML file's
(`L1234`). Numbers are given as `T.name (value)`, where `T` is the tuning table (`data/game_data.json` -> `"T"`,
HTML `L255-479`). Positions, speeds and sizes are **HTML units** (1 unit = 0.025 m, `GameData.UNIT`): `x` across
(east), `y` down the screen (south on the ground), `z` / `h` up. Angles are radians in the ground plane, measured like
`atan2(dy, dx)` (0 = east, +pi/2 = south). Times are seconds. The simulation runs in fixed steps of `FIXED_DT = 1/120`
(`advanceSimulation`, `L12705`), only on the host. `rnd(w)` is the world's LCG (`L6060`:
`seed = (seed * 1664525 + 1013904223) mod 2^32`, returns `seed / 2^32`, seed 1 in every new world). `Math.random()` is
used only for things that are purely for show (and is called "rand" below).

**What this spec covers:** hits and kills as effects (`fx`, `FX_LOOK`, the spark "bits"), blood (`BLOOD_SPRITES`: hit
sprays, death sprays, floor splats), gore cutting (`goreLabels`, `goreCut`, `GORE_FX` flecks), corpses and flying
body parts, the hit-stop freeze, screen shake, coins and cash (kill pay, loose notes, the magnet, pickup), the wallet,
the slot machine (`SLOT_SPRITES`, `PRIZES`, the reels, awarding, the OUT OF ORDER sign, and its secret bonus room
"inside the machine"), the vending machine (`VEND_SPRITES`, the nuke launcher it sells, buying, restocking), floaters
(the floating words), the shared big banner, the kill counter and the HUD money.

**What other specs own** (and this one only hooks into): enemies, waves, the janitor's walk and phases
(`specs/enemies_waves.md`: it decides when he pays out and when the secret starts); weapons, bullets, the nuke bomb
itself, rockets, potatoes (`specs/weapons.md`: they decide damage and call the kill sequence); the player's movement,
the cameras and first person (milestone 1 contracts in `godot/scripts/`).

---------------------------------------------------------------------------------------------------------------

## 1. Tuning (T) used by this system

| T name | value | what it does here |
|---|---|---|
| `coinMult` | 1 | scales every enemy's pay (`ETYPE.coins`) |
| `coinLife` | 6 | seconds a loose note lies on the floor (some sources add to it) |
| `coinPop` | 150 | how hard magnet-bonus notes scatter from the body |
| `coinGrab` | 34 | pickup radius |
| `coinMagnet` | 95 | notes drift toward you inside this (no magnet) |
| `coinPull` | 900 | pull strength |
| `magnetBonus` | 1 | extra notes each kill throws out while the killer's magnet runs |
| `magnetTime` | 14 | seconds of CASH MAGNET |
| `magnetRange` | 460 | pull reach while the magnet runs |
| `speedTime` | 10 | seconds of SPEED BOOST |
| `speedMul` | 1.55 | top speed multiplier during it (`L7511`) |
| `corpseFly` | 1.35 | how hard a body is thrown |
| `corpseSpin` | 7 | how much the body tumbles |
| `corpseLife` | 7 | seconds before a body (and each piece) is gone |
| `killShake` | 5 | screen shake per kill |
| `killShakeBig` | 3.2 | x that for a shotgun kill (bullet kills only) |
| `bloodSize` | 42 | hit-spray width (units) at scale 1 |
| `deathSpray` | 5 | sprays fanned out on a kill |
| `deathSize` | 1.42 | death spray size vs a hit spray |
| `bloodReach` | 0.68 | how far forward death sprays land, and the spray image's anchor |
| `shotgunBlood` | 1.5 | big kills' blood multiplier |
| `hitStop` | 0.022 | seconds the world freezes on a kill |
| `hitStopBig` | 2.2 | x that for a big kill |
| `splatAlpha` | 0.62 | floor stain opacity |
| `bloodTime` | 0.34 | seconds the 8-frame spray animation takes |
| `splatLife` | 45 | seconds a floor stain lasts |
| `splatMax` | 140 | floor stains kept (oldest dropped); `<= 0` turns stains off |
| `spinCost` | 5 | dollars a pull |
| `spinTime` | 1.6 | seconds the reels turn (you're rooted) |
| `spinCool` | 8 | seconds before the machine takes another coin |
| `slotScale` | 1.35 | cabinet drawn height = 92 x this = 124.2 |
| `slotDrop` | 38 | cabinet's floor line below the top wall: `y = 18 + 54 + 38 = 110` |
| `reelScale` | 1.9 | reel windows blown up |
| `slotRadius` | 46 | how close you stand to pull |
| `loungeSlotX` | 90 | slot x in the lobby (430 in a run) |
| `vendShow` | 1 | vending machine on (1) / hidden (0) |
| `vendX` | 0.82 | vending x in a run = 860 x 0.82 = 705.2 |
| `vendDrop` | 82 | vending floor line: `y = 18 + 54 + 82 = 154` |
| `vendHeight` | 150 | drawn height |
| `vendPrice` | 2500 | the launcher's price |
| `vendRadius` | 56 | how close you stand to buy (and to see the price) |
| `vendHold` | 0.8 | seconds standing still to buy |
| `loungeVendX` | 235 | vending x in the lobby (unused: the machine isn't in the lobby since b215) |
| `lobbyCash` | 40 | free money in the lobby |
| `testCash` | 2500 | TESTING: cash at the lobby and at the start of every run ("Set 0 before release") |
| `overheal` | 6 | +2 HEALTH can stack hp up to `playerHp + overheal` = 11 |
| `playerHp` | 5 | |
| `janitorPay` | 3 | notes the janitor knocks out of the cabinet |
| `nukeShake` | 26 | shake when the SCREEN CLEAR bomb lands (weapons spec) |
| `blastShake` | 18 | shake per rocket blast (weapons spec) |
| `enemyRadius` | 15 | enemy radius = 15 x `ETYPE.r` |
| `enemyScale` | 3.4 | enemy (and corpse) picture height = radius x 3.4 |
| `enemyStride` | 10 | picks the batter's corpse frame from `odo` |
| `stagger` | 0.13 | `killBurst` stuns neighbours `stagger x 0.6` |
| `knockback`, `enemyHp` | 170, 3 | used in the hit paths (weapons spec) |

The tuning panel's slider ranges are `RANGES` (`L481`); not needed for the port.

---------------------------------------------------------------------------------------------------------------

## 2. Constants

**Arena** (`L615`): `ARENA = { w: 860, h: 520, wall: 18 }`.

**Player colours** (`P_COLOURS`, `L616`, also `game_data.json`): player 0 `#e0473f` (red), player 1 `#4f9fe8` (blue).

**Enemy types** (`ETYPE`, `L667-673`; the fields this system reads):

| t | key | r (x15 = radius) | mass | colour | coins (pay) |
|---|---|---|---|---|---|
| 0 | grunt | 1.00 (15) | 1.0 | `#6fd3a0` | 1 |
| 1 | swarmer | 0.60 (9) | 0.45 | `#e8c34f` | 1 |
| 2 | brute | 1.60 (24) | 2.8 | `#b06bd8` | 5 |
| 3 | batter | 1.00 (15) | 1.1 | `#d94a4a` | 3 |

**Effect kinds** (`FX`, `L6072`) and their spark look (`FX_LOOK`, `L6073-6075`): `[count, colour, speed]`.

| kind | id | count | colour | speed | sound (`playEventSounds`, `L11371`) | used for |
|---|---|---|---|---|---|---|
| HIT | 0 | 4 | `#f6d17a` | 180 | `SFX.hit` | anything hit (bullet, punch, husk, splat centre, dummy, janitor, bonus skull) |
| KILL | 1 | 14 | `#6fd3a0` | 260 | `SFX.kill(false)` | a non-brute dies; a bonus skull shot dead |
| WALL | 2 | 3 | `#5a6274` | 120 | none | bullet hits a wall, a can, a player bounced hard off a wall, janitor's hammer clank, a bonus stamp lands, Gothica's food |
| HURT | 3 | 10 | `#e0473f` | 220 | `SFX.hurt` | a player (or Gothica) hurt |
| DOWN | 4 | 24 | `#e0473f` | 300 | `SFX.down` | a player (or Gothica) down |
| BOOM | 5 | 36 | `#ff9a6a` | 420 | `SFX.kill(true)` | a brute dies (`burstShrapnel`) |
| LAUNCH | 6 | 8 | `#c9c9c9` | 140 | `sfxRocket` | a rocket fired |
| BLAST | 7 | 40 | `#ffb347` | 520 | `sfxBlast` | a rocket blast |
| SPLASH | 8 | 10 | `#e6f7ff` | 200 | none | a potato into the pool (+ duck ripple 0.6, water splash 0.45) |
| DIVE | 9 | 16 | `#ffffff` | 260 | none | someone dives in (+ duck ripple 1.6, water splash 1) |

Note the KILL sparks are green (the grunt's colour), not red: the red is the blood sprites.

**Prizes** (`PRIZES`, `L624-633`; weights total 18; the comment "one in eight is a bust" is out of date, it's 1 in 9):

| index | key | label (banner) | weight | chance | sym |
|---|---|---|---|---|---|
| 0 | `blasters` | REAL GUNS! | 3 | 16.7% | 1 (shotgun icon) |
| 1 | `shotgun` | SHOTGUN! | 3 | 16.7% | 1 (shotgun icon) |
| 2 | `health` | +2 HEALTH | 3 | 16.7% | 0 (heart) |
| 3 | `speed` | SPEED BOOST | 2 | 11.1% | 3 (bolt) |
| 4 | `clear` | SCREEN CLEAR | 1 | 5.6% | 4 (star) |
| 5 | `cash` | JACKPOT! | 2 | 11.1% | 2 (coin) |
| 6 | `magnet` | CASH MAGNET! | 2 | 11.1% | 2 (coin) |
| 7 | `bust` | BUST! | 2 | 11.1% | 5 (skull) |

`SYM_COUNT = 6` (`L634`): 0 heart, 1 shotgun, 2 coin, 3 bolt, 4 star, 5 skull. The index into `PRIZES` goes over the
network, so keep this order.

---------------------------------------------------------------------------------------------------------------

## 3. State

### 3.1 World fields (`buildWorld`, `L6029-6053`)

| field | start | what |
|---|---|---|
| `coins` | `[]` | loose notes on the floor (3.4) |
| `bits` | `[]` | spark particles (3.5) |
| `blood` | `[]` | blood sprays playing (3.6), at most 48 |
| `splats` | `[]` | floor stains (3.7), at most `T.splatMax` |
| `corpses` | `[]` | bodies and flying parts (3.8), at most 90 |
| `floaters` | `[]` | floating words (3.9) |
| `shake` | 0 | screen shake amount, decays 90/s |
| `freeze` | 0 | hit-stop seconds left: the whole step is skipped while > 0 |
| `events` | `[]` | `[kind, round(x), round(y)]` fx records for the guest and for sounds, at most 40 between snapshots |
| `slot` | `{ x: 430, y: 110, flash: 0, sym: 0, cool: 0, busy: -1, broken: false, prize: null, decoy: [0, 0] }` | the slot machine (`sym` is never used) |
| `sign` | `'stand'` | the OUT OF ORDER sign: `'stand'` on the cabinet, `'floor'` (the janitor threw it), `'gone'` (in the bonus room) |
| `vendSold` | false | the launcher's been bought this wave |
| `nuke` | null | the SCREEN CLEAR bomb (weapons spec) |
| `slotSecret` | absent | the bonus room (section 14) |
| `seed` | 1 | the RNG |

Not in the world (render-only, each screen its own): `GORE_FX` (flecks, `L6428`), `goreClock`, `GORE_LABELS` /
`GORE_CUTS` caches, `banner` (`L6876`, `{ text, until }` in `performance.now()` ms), and on the guest `net.bits`.

### 3.2 Player fields (`newPlayer`, `L711-729`)

| field | start | what |
|---|---|---|
| `coins` | 0 (then lobby/run values, section 12) | the wallet, whole dollars |
| `kills` | 0 | the kill counter |
| `spin` | 0 | seconds left pulling the slot machine (rooted while > 0) |
| `speed` | 0 | seconds of SPEED BOOST left |
| `magnet` | 0 | seconds of CASH MAGNET left |
| `buy` | 0 | seconds stood at the vending machine (0..`vendHold`) |
| `hp` | `T.playerHp` (5) | (+2 HEALTH) |
| `blasters`, `ammo`, `weapon`, `wTime`, `rockets`, `prevWeapon` | | weapons spec; prizes and the vending machine set them |

### 3.3 Run resets

- **Every new world** (`newWorld` -> `fillLobby`, `L733-749`; also `restartGame`, `L13541`): each player
  `coins = max(coins, T.lobbyCash, T.testCash)` = 2500. A player who joins in the lobby (`addPlayer`, `L6065`): the same.
- **Start of a run** (`startGame`, `L13549-13607`): each player `coins = T.testCash` (2500; "nothing won in the lobby
  carries into the run"), `rockets = 0, dump = 0, buy = 0, hp = 5, weapon 'spud', blasters 0, wTime 0, speed 0,
  magnet 0`. World: `coins`, `corpses`, `blood`, `splats` emptied; `slot.cool = 0, slot.busy = -1,
  slot.broken = true`, `sign = 'stand'`, janitor reset. `kills` are **not** reset (a fresh world starts them at 0;
  the only lobby kills possible are of a BUST brute from the lobby slot, which would carry into the run's count). `floaters` and `bits` are not cleared.
- **Each wave start** (`startWave`, `L6575`): `vendSold = false` (the vending machine restocks).

### 3.4 A loose note (`w.coins[]`)

`{ x, y, vx, vy, life, arm, rot, spin, phase, owner?, pull? }`: `life` seconds left; `arm` seconds still "in the air"
(can't be picked up or pulled); `rot` its turn; `spin` how fast it turns; `phase` a random offset for its bob and
flutter; `owner` (only magnet-bonus notes): only that player can take it; `pull` 1 while a magnet is dragging it.
Each note is worth $1.

### 3.5 A spark (`w.bits[]`)

`{ x, y, vx, vy, life, max: 0.6, colour }`.

### 3.6 A blood spray (`w.blood[]`)

`{ x, y, a, t, big, scale }`: `a` the direction it sprays; `t` its age (negative = not started yet); `big` 0/1 picks the
`boom` frames instead of `hit`; `scale` size.

### 3.7 A floor stain (`w.splats[]`)

`{ x, y, k, life, a, scale }`: `k` 0..5 which `splat` picture; `life` seconds left (from 45); `a` rotation.

### 3.8 A corpse or body part (`w.corpses[]`)

`{ x, y, t, odo, flip, life, max, rot, vx, vy, spin, part, mask, z?, vz?, landed? }`: `t` the enemy type; `odo` the
enemy's odometer (picks the batter's frame); `flip` mirrored; `part` -1 for the body, 0..4 for a piece; `mask` (body
only) bits of the parts it has lost; `z`, `vz` height and vertical speed (pieces only); `landed` (pieces) has it hit
the floor yet.

### 3.9 A floater (`w.floaters[]`)

`{ x, y, text, t, col }`.

---------------------------------------------------------------------------------------------------------------

## 4. The order things happen in a step (`stepBase`, `L7160-8296`)

Only the parts this system owns or reads, in order:

1. **Hit-stop** (`L7162-7165`): `if (w.freeze > 0) { w.freeze -= dt; return; }`. Nothing else runs that step (no
   timers, no `w.t`, no shake decay, no blood ageing). `hitStop` 0.022 s = 3 steps at 1/120; a big kill 0.0484 s = 6.
2. `w.t += dt`.
3. **Each player** (`L7169`):
   - `speed` and `magnet` tick down **only in a run** (`L7225-7226`).
   - **Pulling the slot** (`L7228-7240`): if `spin > 0` (section 13.3), then `continue` (skips the rest of his step).
   - Weapon dump (weapons spec).
   - **Buying** (`L7253-7273`, section 15.2).
   - **Starting a pull** (`L7275-7287`, section 13.2), then `continue` that step.
   - Moving (speed cap with `speedMul`, `L7511`), shooting (sparks, sprays, kills), a hard wall bounce (shake 14 and a
     WALL fx, `L7340-7344`).
4. Wave director, enemies, contact damage (other specs; fx HURT/DOWN).
5. **Bullets** (`L7688-7806`): hits -> `fx HIT`, `spray`; kills -> the kill sequence (5.4); dummies (5.6).
6. **Shrapnel** (`L7809-7857`): kills other enemies with the kill sequence (owner -1).
7. **Janitor** (`L7859-7998`): his notes (11.5) and pocketing them; `slot.broken = false`, `slot.flash = 0.9`.
8. **Nuke** (`L8000-8036`): kills everything big, owner -1; `shake = T.nukeShake` (set, not max); `freeze >= 0.05`.
9. **Rockets** (`stepRockets`, `L8037`): blasts -> `shake >= 18`, `freeze >= 0.06`, kills big.
10. **Shake decays**: `w.shake = max(0, shake - dt * 90)` (`L8038`).
11. Plants, Gothica, rain, gym, blackjack; **husks** (`L8044-8092`: kills; full-power potato `potatoSplat`); action
    timers (the punch lands here: `punchLand`).
12. Lobby playground (dummies come back up after `dummyRespawn`).
13. **Slot position** (`L8194-8195`): `slot.y = 18 + 54 + T.slotDrop`; unless in the bonus room
    `slot.x = (!started && T.loungeFloor) ? T.loungeSlotX : 430` (so the sliders move it live).
14. Lobby solids.
15. **`slot.flash = max(0, flash - dt)`** (`L8197`).
16. **Floaters** (`L8199-8203`).
17. **Corpses** (`L8205-8230`).
18. **Blood sprays** age (`L8232-8235`); **splats** age (`L8236-8239`).
19. **`slot.cool = max(0, cool - dt)`** (`L8240`).
20. **Coins** (`L8242-8285`).
21. **Sparks** (`L8287-8295`).

`step(w, inputs, dt)` (`L13860`) wraps this: outside the secret it just calls `stepBase`; inside it see section 14.
The step only runs while `!world.over` (`advanceSimulation`, `L12710`): on game over everything stops, including
shake decay (see 22).

---------------------------------------------------------------------------------------------------------------

## 5. Hits and kills

### 5.1 `fx(w, kind, x, y)` (`L6238-6244`)

```
[n, colour, speed] = FX_LOOK[kind]
burst(w, x, y, n, colour, speed)
if kind == SPLASH: duckSplash(x, y, 0.6); waterSplash(x, y, 0.45)      # the pool spec's
if kind == DIVE:   duckSplash(x, y, 1.6); waterSplash(x, y, 1)
if w.events.length < 40: w.events.push([kind, round(x), round(y)])
```

### 5.2 `burst(w, x, y, n, colour, speed)` (`L6246-6253`): the sparks

```
repeat n:
  a  = rnd(w) * 2pi
  sp = speed * (0.3 + rnd(w) * 0.7)
  w.bits.push({ x, y, vx: cos(a)*sp, vy: sin(a)*sp, life: 0.25 + rnd(w)*0.35, max: 0.6, colour })
```
`burst` is also called directly (no event, so the guest doesn't see these): a potato bursting (`potatoSplat`, 16
`#e9c98f` at 280 "the flesh", 10 `#8a5a2b` at 200 "the skin"), a magnet-pulled note picked up (3 `#7fd89a` at 90),
falling rope potatoes hitting the floor hard (3 `#b9a58a` at 40). Note the sparks use the world RNG on the host, so
they shift every later random number (harmless; see 23.9).

### 5.3 `spray(w, x, y, dx, dy, big, scale)` (`L6331-6335`): a hit spray

```
w.blood.push({ x, y, a: atan2(dy, dx), t: 0, big: big ? 1 : 0,
               scale: scale || (0.78 + rnd(w)*0.42) * (big ? T.shotgunBlood*0.8 : 1) })   # 0.78..1.2, big x1.2
if w.blood.length > 48: w.blood.shift()
```
(The `rnd` is only drawn when no `scale` is passed; no caller passes one.) Called by bullets hitting an enemy
(`L7755`) or a lobby dummy (`L7781`), at the bullet's impact point, along the bullet's velocity, `big` when the
bullet's knockback multiplier `kb > 1.5` (the shotgun's 2.2; the spud gun's is 0.8, blasters none). Punches, husks,
potato bursts and rockets don't spray on a hit; they only get the kill's death sprays.

### 5.4 The kill sequence (identical at every call site)

```
if e.t == 2 (brute): burstShrapnel(w, e.x, e.y)      # fx BOOM + the shards (enemies spec)
else:                fx(w, KILL, e.x, e.y)
makeCorpse(w, e, dx, dy, big)                          # 8.1
w.shake = max(w.shake, T.killShake * (big ? T.killShakeBig : 1))     # only the bullet path uses the big factor
killBurst(w, e.x, e.y, dx, dy, big)                    # 5.5: death sprays, shove, hit-stop
splat(w, e.x, e.y)                                     # 6.3: a floor stain
payKill(w, e.x, e.y, e.t, owner)                       # 11.1: the money
remove e from w.enemies
(kills++ only on some paths, see 18.1)
```

| where | line | dir `(dx, dy)` | big | shake | owner | kills++ |
|---|---|---|---|---|---|---|
| bullet | `L7757-7769` | bullet velocity | `kb > 1.5` (shotgun) | `killShake x (big ? 3.2 : 1)` = 5 / 16 | `b.owner` | yes |
| punch (`punchLand`) | `L7026-7034` | facing x 200 | no | 5 | `p.id` | **no** |
| potato burst (`potatoSplat`) | `L6992-7000` | outward from the burst x 200 | no | 5 | thrower (or -1) | **no** |
| thrown / lobbed potato (husk) | `L8076-8084` | husk velocity | no | 5 | `h.owner` (or -1) | **no** |
| rocket (`detonate`) | `L7099-7106` | outward from the blast (or the rocket's travel if dead centre) | **yes** | none extra (blast already 18) | rocket owner | yes |
| nuke | `L8016-8023` | outward from the bomb | **yes** | none extra (26) | -1 (split) | no |
| shrapnel | `L7844-7852` | shard velocity | no | 5 | -1 (split) | no |

Note the rocket and nuke paths skip the `shake = killShake` line (they've already set a bigger shake) and the shrapnel
path never calls `burstShrapnel` (it can't kill brutes).

### 5.5 `killBurst(w, x, y, dx, dy, big)` (`L6447-6474`)

```
base = atan2(dy, dx)
# the corpse shoves whatever it falls into (the dead enemy is still in the list here, at distance 0: skipped)
for e in w.enemies:
  d = |e - (x, y)|;  if d > 46 or d < 0.001: continue
  push = (1 - d/46) * 130 / ETYPE[e.t].mass
  e.v += (e - (x,y))/d * push
  e.stun = max(e.stun, T.stagger * 0.6)                 # 0.078 s
n   = max(1, round(T.deathSpray))                       # 5
mul = big ? T.shotgunBlood : 1                          # 1.5
for i in 0..n-1:
  t   = n == 1 ? 0 : (i/(n-1) - 0.5) * 2                # -1 .. 1 across the fan
  a   = base + t*0.38 + (rnd(w) - 0.5)*0.22             # a +-0.38 rad fan, a little jitter
  far = rnd(w) < 0.3                                    # most blood sits on the body; the odd one is thrown
  d   = (far ? 8 + rnd(w)*10 : 2 + rnd(w)*5) * T.bloodReach     # far 5.4..12.2, near 1.4..4.8 units ahead
  w.blood.push({ x: x + cos(a)*d, y: y + sin(a)*d, a,
                 t: -i * 0.018,                          # staggered, so the fan unfurls (0, 18, 36, 54, 72 ms late)
                 big: 1,                                 # death sprays always use the 'boom' frames
                 scale: T.deathSize * mul * (far ? 0.9 : 0.8 + rnd(w)*0.4) })   # 1.14..1.70 (x1.5 big)
while w.blood.length > 48: w.blood.shift()
w.freeze = max(w.freeze, T.hitStop * (big ? T.hitStopBig : 1))   # 0.022 or 0.0484 s
```
(Random draws in order per spray: `a`, `far`, `d`, then `scale` only when not far.)

Also used on a lobby dummy knocked down by a bullet (`L7784`, at `(d.x, d.y - 14)`, big if shotgun) or a rocket
(`L7119`, big); each also `splat(d.x, d.y + 8)`. Dummies make no corpse and pay no `payKill`.

### 5.6 Lobby dummies (the warm-up targets)

Bullet hit (`L7776-7790`): `hp -= 1`, flash, `fx HIT`, `spray` (as 5.3). Knocked down (`hp <= 0`): `down =
T.dummyRespawn`, `killBurst(d.x, d.y - 14, bullet dir, big)`, `splat(d.x, d.y + 8)`, and **the shooter gets $3**:
`coins += 3` and a floater `'$3'` at `(d.x, d.y - 20)` in the shooter's colour. Punches (`L7037-7041`) and potato
bursts (`L7002-7005`) only `hp -= 1`, flash, wobble and `fx HIT`: they never knock a dummy down, even at 0 hp (it stays
up, and the next bullet drops it). Rockets (`L7116-7121`): any dummy within `blastRadius + 16` goes straight down,
`killBurst` big, `splat`, no money.

---------------------------------------------------------------------------------------------------------------

## 6. Blood

### 6.1 Sprays: step (`L8232-8235`)

`t += dt`; removed once `t > T.bloodTime` (0.34). Death sprays start with negative `t` and wait.

### 6.2 Sprays: drawing (`L12420-12438`), over the top of the bodies and players

```
for s in w.blood:
  if s.t < 0: skip
  set = s.big ? BLOOD.boom : BLOOD.hit                 # 8 frames each
  f   = min(7, floor(s.t / T.bloodTime * 8))           # 42.5 ms a frame
  im  = set[f]
  dw  = T.bloodSize * s.scale * (s.big ? 1.25 : 1)     # drawn width; height keeps the frame's aspect
  dh  = im.h * dw / im.w
  alpha = 1 - (s.t / T.bloodTime)^3
  translate(s.x, s.y); rotate(s.a)
  draw im at (-dw * (0.5 - 0.22*T.bloodReach), -dh/2, dw, dh)     # x from -0.35 dw to +0.65 dw: sprays forward
```
The pictures point to the **right** (+x): rotating by `a` points them along the shot. Every frame is drawn at the same
width whatever its pixel size (frame 0 is a small 33x34 / 42x40 start; the rest are about 110 wide), so the first
frame is a small blob blown up. Sizes: a hit spray 33..50 units wide (40..60 shotgun); a death spray 60..90 units
(90..134 big).

`BLOOD_SPRITES` (manifest, `L9374`): `hit` = `assets/BLOOD_SPRITES/hit_0..7.png` (33x34, 99x85, 110x68, 110x80,
110x63, 110x74, 97x54, 94x60), `boom` = `boom_0..7.png` (42x40, 110x102, 110x90, 110x83, 110x92, 110x107, 104x59,
93x43), `splat` = `splat_0..5.png` (110 wide, 58..66 high: dark red blobs).

### 6.3 Floor stains: `splat(w, x, y)` (`L6476-6482`)

```
if T.splatMax <= 0: return
w.splats.push({ x, y, k: floor(rnd(w)*6), life: T.splatLife, a: rnd(w)*2pi, scale: 0.7 + rnd(w)*0.5 })
while w.splats.length > T.splatMax: w.splats.shift()
```
Step (`L8236-8239`): `life -= dt`, removed at 0. Made by every kill (at the body), every dummy knock-down
(`(d.x, d.y + 8)`), and every flying body part when it first lands (8.2, scaled down to 48%).

### 6.4 Floor stains: drawing (`L11569-11581`), first thing on the floor, under everything

```
im = BLOOD.splat[s.k]
dw = T.bloodSize * 1.5 * s.scale          # 63 x scale = 44..76 units wide; dh by aspect
alpha = min(1, s.life / 3) * T.splatAlpha  # full 0.62 until the last 3 s, then fades
translate(s.x, s.y); rotate(s.a); draw centred
```

---------------------------------------------------------------------------------------------------------------

## 7. Gore cutting (b288)

"A kill can take the head, arms and legs off: each piece is cut out of the enemy's own picture along its outline (not
a rectangle of it), with a red stump where it was cut, and the body keeps what's left, bleeding at the same cuts.
Parts: 0 head, 1 left arm, 2 right arm, 3 left leg, 4 right leg, 5 the torso (never taken). Worked out once per
picture: the head is the top quarter as wide as the face, the legs the bottom third either side of the middle, and the
arms anything out past the chest." (comment at `L6341-6345`). "Left" means the picture's left (screen left).

### 7.1 `goreLabels(im)` (`L6347-6399`): label every pixel of a picture, once (cached per image)

Inputs: the RGBA pixels `d` of a `w x h` picture. A pixel is solid when `alpha > 40`.

```
op(x, y) = d[(y*w + x)*4 + 3] > 40
(x0, x1, y0, y1) = bounding box of solid pixels;  none -> null (cache null)
H = y1 - y0 + 1

run(y):  # the widest solid run on row y between x0 and x1, and its middle
  best = [0, (x0 + x1)/2];  s = -1
  for x in x0 .. x1+1:
    o = x <= x1 and op(x, y)
    if o and s < 0: s = x
    if not o and s >= 0:
      if x - s > best[0]: best = [x - s, (s + x - 1)/2]     # strictly wider: the first widest wins
      s = -1
  return best

yHead = y0 + round(H * 0.23);  yLeg = y0 + round(H * 0.62)
[chest, cx] = run(y0 + round(H * 0.45))
tHalf  = max(2, chest * 0.37)
hHalf  = run(y0 + round(H * 0.12))[0] / 2 + 1
legHalf = chest * 0.44
jit(n) = ((((n*73856093) ^ (n*19349663)) >>> 0) % 3) - 1       # -1, 0 or 1: the cuts are torn, not ruled
         # JS: the products are exact doubles, ^ takes each to int32 (low 32 bits), >>> 0 to uint32.
         # GDScript: ((n*73856093) & 0xFFFFFFFF) ^ ((n*19349663) & 0xFFFFFFFF), then % 3 - 1 (n is always >= 0)

lab = int8[w*h] filled with -1
for y in y0..y1, x in x0..x1 where op(x, y):
  o = (y*w + x)*4
  # the grey line under his feet: the bottom 3 rows, grey (max(r,g,b) - min(r,g,b) < 16), away from the middle
  if y > y1 - 3 and max(r,g,b) - min(r,g,b) < 16 and |x - cx| > chest*0.3: continue      # stays -1
  dx = x - cx;  side = dx < 0 ? 1 : 2;  ax = |dx|
  yH = yHead + jit(x);  yL = yLeg + jit(x + 7)
  tH = tHalf + jit(y) + max(0, yHead + H*0.08 - y) * 0.5          # (the shoulders stay with the body)
  lab = y < yH  ? (ax <= hHalf + jit(y + 3) ? 0 : side)               # head, or an arm up high
      : y >= yL ? (ax > legHalf ? side : (dx + jit(y + 11) < 0 ? 3 : 4))   # legs (or a hand/bat out wide)
      :           (ax <= tH ? 5 : side)                                # torso, or an arm

# thin slivers of hip or thigh that fell outside the line go back to the body (a bat or a hand, clear of it, doesn't)
for y in yHead..y1:
  x = x0
  while x <= x1:
    l = lab[y*w + x]
    if l == 1 or l == 2:
      e = x;  while e + 1 <= x1 and lab[y*w + e + 1] == l: e++
      lft = x > 0 ? lab[y*w + x - 1] : -1
      rgt = e < w - 1 ? lab[y*w + e + 1] : -1
      nb  = (lft >= 0 and lft != l) ? lft : (rgt >= 0 and rgt != l) ? rgt : -1
      if nb >= 0 and e - x + 1 <= 2 and y > y0 + H*0.4: lab[y*w + x .. e] = nb
      x = e
    x++

# each arm and the head is one piece: anything of theirs not joined to their biggest part goes back to the body
for part in [0, 1, 2]:
  comps = 4-connected components (left/right within the row, up/down) of pixels labelled `part`, whole image
  sort comps by size, biggest first
  for every pixel j of every comp but the first:
    lab[j] = (j / w) >= yLeg ? ((j % w) < cx ? 3 : 4) : 5
return { w, h, d, lab }
```

### 7.2 `goreCut(im, key, keep)` (`L6400-6423`): cut out the pixels whose label `keep()` accepts (cached per image and key)

```
L = goreLabels(im); null -> null
bounding box (x0..x1, y0..y1) of pixels with lab >= 0 and keep(lab); none -> null
cut(x, y) = in the picture and lab[x, y] >= 0 and not keep(lab[x, y])     # a neighbour that was cut away
for each kept pixel (x, y):
  if cut(x-1,y) or cut(x+1,y) or cut(x,y-1) or cut(x,y+1):     # the wound edge
      rgb = (196, 26, 44)
  elif cut(x-2,y) or cut(x+2,y) or cut(x,y-2) or cut(x,y+2):   # just in from it, darker
      rgb = src * 0.45 + (120, 10, 24) * 0.55                  # stored as bytes: rounded (and clamped)
  else:
      rgb = src
  alpha = src alpha
return { cv: the cropped picture (cw x ch), x: x0, y: y0, w: cw, h: ch }    # x, y = where the crop sits in the original
```
Pixels next to transparent or unlabelled (-1, the grey foot line) pixels are not wounds: only a neighbour belonging to
a removed part makes a stump.

- `goreBodyImage(im, mask)` (`L6424`): `mask == 0 -> null`; else `goreCut(im, 'b' + mask, l -> !(mask & (1 << l)))`
  (everything but the lost parts; the torso, label 5, is never in a mask).
- `gorePart(im, part)` (`L6425`): `goreCut(im, 'p' + part, l -> l == part)`.

A part with no pixels (a sprite whose head or arm the rules didn't find) returns null and simply isn't drawn; the piece
still flies, lands and stains the floor.

Which pictures: the corpse uses the enemy's **front** picture (`enemyFrame(set, 'front', c.odo) || set.idle`,
`L11588`): grunt, swarmer and brute have one `front.png` (58x80, 58x80, 70x80); the batter has four `front_0..3`
(70..73 x 88), picked by the corpse's `odo`: `floor(odo / (T.enemyStride*4/4)) % 4` = `floor(odo / 10) % 4`
(`cycleIndex`, `L9317`). So there are 7 pictures in all, and per picture at most 5 body masks (`31` for a big kill;
`10, 12, 18, 20` for one arm + one leg) and 5 parts: at most 70 cut-outs ever.

---------------------------------------------------------------------------------------------------------------

## 8. Corpses and flying parts

### 8.1 `makeCorpse(w, e, dx, dy, big)` (`L6429-6445`)

```
d = |(dx, dy)| or 1;  angle = atan2(dy, dx)
sp    = (170 + rnd(w)*130) * T.corpseFly * (big ? 1.7 : 1) / ETYPE[e.t].mass
parts = big ? [0, 1, 2, 3, 4]                                    # a big kill takes everything off
            : [1 + floor(rnd(w)*2), 3 + floor(rnd(w)*2)]          # otherwise one arm and one leg
mask  = OR of (1 << p) for p in parts
common = { x: e.x, y: e.y, t: e.t, odo: e.odo || 0, flip: (e.vx || dx) < 0,
           life: T.corpseLife, max: T.corpseLife, rot: 0 }
# the body
push { ...common, vx: dx/d*sp, vy: dy/d*sp, spin: (rnd(w) - 0.5) * T.corpseSpin, part: -1, mask }
# each piece
for part in parts:
  a     = angle + (rnd(w) - 0.5) * 2.5                           # +-1.25 rad around the shot
  speed = sp * (0.65 + rnd(w)*0.9)
  push { ...common, part, mask: 0, z: 8, vz: 100 + rnd(w)*100,
         vx: cos(a)*speed, vy: sin(a)*speed, spin: (rnd(w) - 0.5)*18, rot: rnd(w)*6, landed: false }
while w.corpses.length > 90: w.corpses.shift()                   # (b288: every piece goes over the network, so kept to 90)
```
Body speeds: grunt 230..405 units/s (x1.7 big), swarmer 510..900, brute 82..145, batter 209..368.

### 8.2 Step (`L8205-8230`)

```
c.x += c.vx*dt;  c.y += c.vy*dt
if (c.z || 0) > 0 or (c.vz || 0) > 0:                  # only pieces fly
  c.vz -= 440*dt;  c.z = max(0, c.z + c.vz*dt)
  if c.z == 0:
    if not c.landed:                                    # first touch: a small stain where it lands
      splat(w, c.x, c.y);  newest splat.scale *= 0.48;  c.landed = true
    c.vz = |c.vz| > 45 ? -c.vz*0.23 : 0                 # bounces, then lies there
    c.vx *= 0.65;  c.vy *= 0.65
drag = 0.035^dt;  c.vx *= drag;  c.vy *= drag
c.rot += c.spin*dt;  c.spin *= 0.1^dt
clamp c.x to [26, 834], c.y to [26, 494]               # ARENA.wall + 8 (the arena, even in the tall lobby)
c.life -= dt;  remove at <= 0
```

### 8.3 Drawing (`L11583-11628`), on the floor beneath everything still moving

Drawn after the splats, before the sign, enemies, players. Per corpse:
```
ty = ETYPE[c.t];  im = enemyFrame(EIMG[ty.key], 'front', c.odo) || idle
f  = clamp(c.life / c.max, 0, 1)
r  = T.enemyRadius * ty.r;  z = c.z || 0;  isPart = 0 <= c.part < 6
alpha = min(1, f * 2.2)                                # holds, then fades over the last 3.18 s
translate(c.x, c.y)
# b288: a pool of blood spreading out from under a body that's lost parts
if body and c.mask:
  pim = BLOOD.splat[(|round(c.odo)| + c.t) % 6]
  age = c.max - c.life
  ps  = r * 2.6 * (0.35 + 0.65 * min(1, age/1.4))      # grows from 35% to full over 1.4 s; full = 39 (grunt) .. 62 (brute)
  ph  = ps * pim.h / pim.w
  with alpha x 0.85 x T.splatAlpha, rotate(c.odo * 0.37): draw pim at (-ps/2, -ph/2 + r*0.2, ps, ph)
# the shadow stays on the floor; a piece's shrinks and fades the higher it's thrown
sk = isPart ? 0.45 : 1;  sa = 0.3 * max(0.25, 1 - z/60)
fill ellipse centre (0, r*0.7*sk), radii (r*0.9*sk, r*0.35*sk), black at alpha sa (times the corpse alpha)
translate(0, -z);  rotate(c.rot)
h = r * T.enemyScale  (grunt 51, swarmer 30.6, brute 81.6, batter 51);  k = h / im.h;  dw = h * im.w / im.h
if c.flip: scale(-1, 1)
nearest-neighbour
if isPart:
  pc = gorePart(im, c.part);  draw pc centred: (-pc.w*k/2, -pc.h*k/2, pc.w*k, pc.h*k)      # turns about its own middle
  flecks (8.4)
else:
  bc = goreBodyImage(im, c.mask)
  if bc: draw bc at (round(-dw/2 + bc.x*k), round(-h*0.55 + bc.y*k), bc.w*k, bc.h*k)
  elif not c.mask: draw im at (round(-dw/2), round(-h*0.55), round(dw), round(h))
fallback (no picture): a circle of radius r in ty.colour (bodies only)
```
So a body pivots about a point 55% of the way down its picture (the picture spans `-0.55h .. +0.45h` around the
corpse point), tumbles with `rot`, and slides where it was thrown. A live enemy is drawn with its feet at `y + 0.8r`;
the corpse's picture bottom lands at `y + 0.45h = y + 1.53r`: it drops a little toward the viewer as it dies.

### 8.4 Flecks (`GORE_FX`, `L6428`, spawned `L11615-11617`, drawn `L11629-11635`): per screen, never sent

Uses the real frame time: `gdt = min(0.05, now - goreClock)` (performance clock), recomputed once per render.

- Spawn: for each flying piece with `z > 1`, while `GORE_FX.length < 260`, with probability `gdt * 30` per frame
  (about 30 a second): `{ x: c.x, y: c.y, z, vx: c.vx*0.3 + (rand-0.5)*50, vy: c.vy*0.3 + (rand-0.5)*50,
  vz: 30 + rand*50, life: 0.5 + rand*0.4 }`.
- Step and draw (after all corpses): `life -= gdt; vz -= 420*gdt; z += vz*gdt; x += vx*gdt; y += vy*gdt`; removed
  when `z <= 0` or `life <= 0`. A square at `(round(x), round(y - z))`, 2 wide, 3 tall while falling (`vz < 0`) else
  2, colour `#c21a2e` while `life > 0.3`, then `#8e1022`. Full opacity. They don't stain the floor.

---------------------------------------------------------------------------------------------------------------

## 9. Sparks (`w.bits`)

Step (host, `L8287-8295`; guest `stepBits`, `L11140`, on its own list at frame rate):
`x += vx*dt; y += vy*dt; v *= 0.9^(dt*60)` ("tuned at 60 Hz; now runs at 120"); `life -= dt`; removed at 0.

Draw (`L11802-11808`, after the enemies, before the husks and bullets): a 3x3 square at
`(round(x) - 1, round(y) - 1)` in `colour`, alpha `max(0, life / max)` (so it starts at 0.42..1 and fades).

The guest makes its own from the events (`playEvents`, `L11125`): the same recipe with `Math.random()`, and the water
splashes for SPLASH (0.45) and DIVE (1) (no duck ripples).

---------------------------------------------------------------------------------------------------------------

## 10. Screen shake and the hit-stop

### 10.1 Who shakes it

`w.shake = max(w.shake, amount)` unless noted:

| amount | from | line |
|---|---|---|
| 5 (16 shotgun) | a kill (bullet, punch, potato, husk, shrapnel paths) | 5.4 |
| 5 | a full-power potato bursts | `L6977` |
| 3 | a punch lands on anything | `L7043` |
| 6 | a rocket fired | `L6932` |
| 18 (`blastShake`) | a rocket blast | `L7083` |
| 26 (`nukeShake`) | the SCREEN CLEAR bomb lands (**set**, not max) | `L8006` |
| 8 | a dive into the pool (`splash`) | `L5678` |
| 14 | a player bounced off a wall at > 120 units/s (launched) | `L7341` |
| 22 | the janitor's whack | `L7920` |
| 6 | a bonus-room stamp lands (**set**) | `L13898` |
| 0 | entering, finishing or leaving the bonus room (reset) | `L13813`, `L13839`, `L13847` |

Decay: `shake = max(0, shake - 90*dt)` once per sim step (`L8038`): a kill's 5 lasts 56 ms, a shotgun kill's 16 lasts
0.18 s, the nuke's 26 lasts 0.29 s.

### 10.2 How it's drawn (`renderBase`, `L11528-11533`, undone at `L12697`)

```
amt = min(40, w.shake)
shx = amt ? (rand - 0.5) * amt : 0;  shy = amt ? (rand - 0.5) * amt : 0      # new random offset every rendered frame
translate(shx, shy)  before the camera transform
```
The offset is in the 860x520 screen space (it doesn't grow with zoom), and it moves **everything**, HUD included
(the HUD is drawn inside the same save/restore). Up to +-amt/2 on each axis. The guest gets `sk = round(shake)` in the
snapshot and draws it the same way.

### 10.3 Hit-stop (`w.freeze`)

Set by `killBurst` (0.022 / 0.0484), rockets (`>= 0.06`), the nuke (`>= 0.05`), the janitor's whack (`>= 0.06`). While
> 0 the whole step is skipped (4.1). Drawing carries on (the sprays sit on their first frame, the shake keeps jittering
at its frozen amount). The guest gets `fz = round(freeze*1000)` and holds still (no extrapolation) while it's > 0
(`L12737`).

---------------------------------------------------------------------------------------------------------------

## 11. Coins and cash

"Cash from a kill goes straight to whoever earned it, with a little number floating up where the body was so the
reward still reads. If nobody owns the kill (a nuke, shrapnel) it's split between everyone standing." (`L6483-6485`).
So kills don't scatter notes any more: loose notes only come from the magnet bonus, the slot's JACKPOT, the janitor,
the bonus room and the debug magnet button. Each note is worth $1.

### 11.1 `payKill(w, x, y, t, ownerId)` (`L6486-6513`)

```
n = round((ETYPE[t].coins || 0) * T.coinMult)          # grunt 1, swarmer 1, brute 5, batter 3
if n <= 0: return
killer = w.players[ownerId]
# a magnet turns kills back into loose notes, on top of the wallet pay
if T.magnetBonus > 0 and killer and killer.alive and killer.magnet > 0:
  repeat T.magnetBonus (1):
    a = rnd*2pi;  sp = T.coinPop * (0.5 + rnd*0.8)       # 75..195
    w.coins.push({ x, y, vx: cos(a)*sp, vy: sin(a)*sp, life: T.coinLife, arm: 0.18, owner: ownerId,
                   rot: rnd*6.28, spin: (rnd - 0.5)*9, phase: rnd*6.28 })
if killer and killer.alive:
  killer.coins += n
  w.floaters.push({ x, y: y - 10, text: '$' + n, t: 0, col: P_COLOURS[killer.id] })
else:                                                   # nobody (owner -1) or the killer is dead
  alive = living players;  if none: return
  each = max(1, round(n / alive.length))                # 1 between two -> 1 each; 5 -> 3 each ($6 from a $5 brute)
  everyone alive: coins += each
  w.floaters.push({ x, y: y - 10, text: '$' + n, t: 0, col: '#7fd89a' })
if w.floaters.length > 30: w.floaters.shift()           # (the only place floaters are capped)
```

### 11.2 `dropCoins(w, x, y, t)` (`L6515-6524`): **never called** (the old scatter-on-kill). Don't port it.

### 11.3 Every source of loose notes

| source | where | count | from | speed | life | arm | other |
|---|---|---|---|---|---|---|---|
| magnet bonus | `payKill` | `magnetBonus` (1) per kill | the body | `coinPop x (0.5..1.3)`, any direction | 6 | 0.18 | `owner` = killer, spin +-4.5 |
| JACKPOT! | `award`, `L6303-6314` | 18 | the slot `(slot.x, slot.y)` | `420 + rnd*340`, angle `i/18 x 2pi + rnd*0.3` (an even ring) | 10 (`coinLife + 4`) | 0.85 | no owner, spin +-8. "thrown hard and wide, and briefly out of reach, so you see the shower and have to go and collect it" |
| janitor | `L7965-7973` | `janitorPay` (3) | `(slot.x, slot.y + 6)` | `(cos a x 150, sin a x 90)`, `a = -pi/2 + (i-1)*0.55` (a fan upward) | 9 (`coinLife + 3`) | 0.5 | spin +-5; he pockets every note within 90 of the slot 0.43 s later (see 23.6) |
| bonus room rain | `L13873-13876` | 1 every 0.23 s | random in `x 105..755, y 160..450` | 0 | 5 | 0.25 | `rot rnd*6, spin 5, phase rnd*6` |
| bonus skull shot | `L13893-13896` | 3 | `(h.x + (i-1)*12, h.y)` | `((i-1)*40, -20)` | 4 | 0.2 | `rot 0, spin 4, phase 0` |
| debug magnet (M key with `?debug`, the Magnet button) | `giveTestMagnet`, `L13641-13658` | 14 | around player 0, distance 140..400, angle `i/14 x 2pi + rand*0.4`, clamped to `[28, 832] x [28, 492]` (10 inside the walls) | 0 | 10 | 0.2 | also gives player 0 the magnet; uses `Math.random` |

### 11.4 Step (`L8242-8285`)

```
for each note c (newest first):
  c.x += c.vx*dt;  c.y += c.vy*dt
  drag = 0.02^dt;  c.v *= drag                                     # scatter, then settle quickly
  moving = |c.v|
  c.rot += c.spin * dt * (0.25 + min(1, moving/120))               # paper: tumbles while flying, drifts once settled
  c.spin *= 0.25^dt
  clamp x to [24, worldW - 24], y to [24, worldH - 24]             # (worldW/H: the arena, or the tall lobby)
  c.life -= dt
  if c.arm > 0: c.arm -= dt; continue                              # still in the air: not yours yet (and can't expire)
  # whoever's magnet reaches furthest gets first claim on the note
  near = null; nd = inf; reach = T.coinMagnet
  for p in living players:
    if c.owner defined and c.owner != p.id: continue               # his kill, his money
    r2 = p.magnet > 0 ? max(T.coinMagnet, T.magnetRange) : T.coinMagnet      # 460 or 95
    d  = |p - c|
    if d - r2 < nd - reach: nd = d; near = p; reach = r2           # the player whose reach edge is closest
  if near:
    if nd < T.coinGrab (34):
      near.coins += 1;  taken
      if c.pull: burst(w, c.x, c.y, 3, '#7fd89a', 90)
      SFX.cash()                                                   # host only (see 20.4)
    elif nd < reach and nd > 0.001:
      boost  = near.magnet > 0 ? 2.4 : 1
      c.pull = near.magnet > 0 ? 1 : 0
      c.v   += (near - c)/nd * T.coinPull * boost * (1 - nd/reach) * dt
      c.life = max(c.life, near.magnet > 0 ? 1.5 : 0.6)            # don't blink out mid-flight
  remove if taken or c.life <= 0
```
`pull` is rewritten every step a player has the note in reach (1 if that player's magnet runs, 0 if not) and kept
when nobody does, so a note a magnet once pulled stays bright and flat until a magnet-less player pulls it (README fix).

### 11.5 Drawing a note (`L12156-12199`): after the slot machine, before shrapnel and players ("drawn low so bodies read over them")

```
if c.life < 2 and floor(c.life * 8) % 2 == 0: skip          # about to vanish: blinks at 4 Hz
inAir = c.arm > 0;  speed = |c.v|
if speed > 110:                                             # a streak behind anything moving fast
  u = c.v / speed;  len = min(46, speed * 0.055)
  for k in 1..4:  f = k/4
    alpha 0.34*(1-f);  colour c.pull ? '#9df0b4' : '#58b37a'
    s2 = 6*(1 - f*0.55);  t = c - u*len*f
    rect (t.x - s2, t.y - s2*0.6, 2*s2, 1.2*s2)
tt   = w.t + c.phase
bob  = sin(tt*4) * 1.2
flat = c.pull ? 1 : 0.35 + 0.65*|cos(tt*5 + c.rot)|         # flutter: turns edge-on and back
shadow: ellipse (c.x, c.y + 5), radii (6, 2), rgba(0,0,0,0.28)
translate(c.x, c.y + bob); rotate(c.rot * 0.25); scale(1, flat)
rect (-8, -5, 16, 10) '#2f7d4f'                             # the note
rect (-7, -4, 14, 8)  (inAir or c.pull) ? '#7fd89a' : '#58b37a'      # brighter in flight
circle r 2.4 at (0,0) '#2f7d4f'                             # the round bit in the middle
rects (-6.5, -3.5, 2, 1) and (4.5, 2.5, 2, 1) rgba(255,255,255,0.55)   # corner ticks
```
A green banknote 16x10 units, no picture file.

### 11.6 Magnet and speed rings (`L12404-12418`), drawn over the players

- Magnet (each living player with `magnet > 0`): a circle round the player, radius
  `T.magnetRange * 0.5 * pulse` = **230** x pulse (half the real reach), `pulse = 0.88 + sin(w.t*1.7)*0.12`
  ("slow, shallow breath"), stroke 2 `rgba(246,209,122,0.28)`.
- Speed (`speed > 0`): an ellipse at `(x, y + 14*0.85)`, radii `(14*1.3, 14*0.6)` = (18.2, 8.4), stroke 2
  `rgba(111,211,160,0.5)`.

---------------------------------------------------------------------------------------------------------------

## 12. The wallet

- Lobby: 2500 (`max(coins, lobbyCash 40, testCash 2500)`); with `testCash = 0` it's 40.
- Run start: `testCash` (2500; 0 for release) for everyone.
- Earned: kills (11.1, paid at once), $3 a dummy knocked down by a bullet (lobby), $1 a note picked up, blackjack
  wins (cards spec: `BJ_BET` 10 a hand).
- Spent: $5 a slot pull, $2500 the launcher, blackjack bets.
- The bonus room: you keep what you collected inside, plus $10 each if you survived (14.5).
- It's never negative (every spend checks first). No upper cap.

---------------------------------------------------------------------------------------------------------------

## 13. The slot machine

### 13.1 Where and what

- Position: `(T.loungeSlotX, 110)` = `(90, 110)` in the lobby (with the lounge floor on), `(430, 110)` in a run; `y` is
  the cabinet's floor line. Recomputed every step (`L8194-8195`). In the bonus room it stays where it was.
- Not solid: players and enemies walk through it (it's not in `lobbySolidBoxes`, `L3431`).
- **In the lobby** it works (`broken` false), with the lobby cash to play. Prizes work there too (see 23).
- **In a run** it starts **broken** (`startGame`), with the OUT OF ORDER sign standing on it, and stays dead until the
  janitor fixes it in the breather after wave `T.janitorWave` (1): his phases are in the enemies spec (9.2); the hooks
  here are `w.sign` ('stand' -> 'floor' when he throws it at 0.18 s of his 'yeet'), `w.slot.broken = false` and
  `w.slot.flash = 0.9` with the banner MACHINE IS LIVE (1600 ms) when he's done (`L7983-7989`), and the three notes.
- Debug (tweaks on, J key, host, in a run, `L8638-8645`): breaks it again and sends the janitor (`breather = 5.2`).

### 13.2 Starting a pull (`L7275-7287`)

All of: `!w.over`, `!slot.broken`, `slot.cool <= 0`, `slot.busy < 0` (nobody else pulling), **no move input**
(`inp.mx == 0 && inp.my == 0`; firing doesn't matter), `p.coins >= T.spinCost` (5), within `T.slotRadius` (46) of
`(slot.x, slot.y)`. The player must be alive (dead players skip their step). Then:
```
p.coins -= T.spinCost
p.spin = T.spinTime                 # 1.6 s
slot.busy = p.id                    # claimed
slot.prize = pickPrize(w)           # decided up front so the reels can land on it
slot.decoy = [floor(rnd*6), floor(rnd*6)]
continue                            # the rest of his step is skipped this tick
```
There's no button: you walk up and stand still. The pull starts the first step you're in range and still.

`pickPrize(w)` (`L6270-6276`): `r = rnd * 18; for p in PRIZES: r -= p.weight; if r <= 0: return p`; fallback
`PRIZES[0]`.

### 13.3 While pulling (`L7228-7240`)

Each step: `spin -= dt`; velocity damped hard (`v *= 0.001^dt`), position integrated (no wall clamp); `continue`
(no moving, shooting, rolling, switching weapons (`L7207`), buying). When `spin <= 0`: `spin = 0`,
`slot.cool = T.spinCool` (8), `slot.busy = -1`, `award(w, p, slot.prize || pickPrize(w))`.

If the puller is killed mid-spin (`L7681`, `L7831`): `slot.busy = -1, spin = 0` and the prize is lost (the $5 too).

### 13.4 `award(w, p, prize)` (`L6278-6327`)

```
banner = { text: prize.label, until: now + 1600 }
w.slot.flash = 1.0                                   # the 'win' picture and the three-of-a-kind reels for 1 s
switch prize.key:
  'blasters': if p.blasters: p.ammo = min(T.spudMaxAmmo (200), p.ammo + T.spudPellets*2 (20))   # have them: a potato's worth
              else giveWeapon(p, 'blaster')          # permanent for the run; banner becomes "BLASTERS!" (1400 ms)
  'shotgun':  giveWeapon(p, 'shotgun')               # 12 s of shotgun; banner "SHOTGUN!"
  'health':   p.hp = min(T.playerHp + T.overheal, p.hp + 2)     # up to 11: "the extra hearts are a buffer"
  'speed':    p.speed = T.speedTime                  # 10 s at x1.55 top speed
  'magnet':   p.magnet = T.magnetTime                # 14 s
  'clear':    w.nuke = { x: 430, y: 260, t: 0, phase: 'fall' } and start the whistle (weapons spec 8.8)
              # "don't kill anything yet - the bomb has to land first"; replaces a nuke already falling
  'cash':     the 18-note JACKPOT shower (11.3)
  'bust':     a brute drops in next to you: "the reason spinning is a decision"
              a = rnd*2pi
              w.enemies.push({ x: p.x + cos(a)*90, y: p.y + sin(a)*90, vx: 0, vy: 0, t: 2, hp: eMaxHp(2) (8),
                               flash: 0, spawn: 0.6, st: 0, stT: 0, sdx: 0, sdy: 1, odo: 0, stun: 0 })
```
`giveWeapon` (`L6878`, weapons spec) sets its own banner after the award's, so REAL GUNS! and SHOTGUN! show as
"BLASTERS!" / "SHOTGUN!" for 1.4 s; REAL GUNS! when you already had them stays.

### 13.5 Drawing the cabinet (`L12052-12154`), on the floor behind everyone

Drawn after the vending machine, before the notes and the players.

```
spinning = any player has spin > 0
key = slot.flash > 0.001 ? 'win' : spinning ? 'spin' : (floor(w.t*3) % 2 ? 'idle_b' : 'idle_a')   # idle blinks every 1/3 s
dim = slot.cool > 0 and not spinning and slot.flash <= 0.001
h  = 92 * T.slotScale = 124.2;  dw = h * 89/128 = 86.4         # SLOT_SPRITES are 89x128
shadow: ellipse (slot.x, slot.y + 4), radii (dw*0.4 = 34.5, 7), rgba(0,0,0,0.35)
alpha = slot.broken ? 0.38 : dim ? 0.55 : 1
sx = round(slot.x - dw/2);  sy = round(slot.y + 6 - h)          # bottom 6 below the floor line
draw SLOT_SPRITES[key] at (sx, sy, round(dw), round(h)), nearest
```
`SLOT_SPRITES` (manifest, `L9446`): `idle_a`, `idle_b` (lights blinking), `spin`, `win`, each 89x128, a purple and
cyan arcade cabinet with "SMASHED" on top and a reel window.

**The reels** (while someone spins, or during the 1 s win flash), drawn into the cabinet's reel window, blown up by
`T.reelScale`:
```
rs = 1.9;  rw = dw*0.16*rs = 26.3;  rh = h*0.115*rs = 27.1
cy = sy + h*0.503                                   # the window's middle line
mid = dw*0.525
cols = [mid + (dw*0.40 - mid)*rs, mid, mid + (dw*0.65 - mid)*rs]      # = 24.8, 45.3, 65.8 from sx: spread from the centre
stops = [0.45, 0.70, 1.0]                           # each reel stops at this fraction of the spin
frac = spinner ? 1 - spinner.spin / max(0.05, T.spinTime) : 1
# a dark surround so the reels sit in a screen
padX = rw*0.22;  padY = rh*0.3
rect (sx + cols[0] - rw/2 - padX, cy - rh/2 - padY, (cols[2]-cols[0]) + rw + 2padX, rh + 2padY)   # 78.8 x 43.4
  fill rgba(12,13,18,0.92), stroke 2 (flash ? '#f6d17a' : '#4b5468')
for reel i in 0..2:  cx = sx + cols[i]
  clip to (cx - rw/2, cy - rh/2, rw, rh); fill '#f2efe6'
  if frac < stops[i]:                               # turning
    off = (w.t * 420) % rh
    for k in -1..2: drawSym(cx, cy - rh/2 + k*rh + off, (k + i*2 + floor(w.t*9)) % 6, rh*0.8)
    then '#f2efe6' at alpha 0.55 over the window (motion haze)
  else:                                             # landed
    sym = (i == 2 or flash) ? prize.sym : decoy[i]
    drawSym(cx, cy, sym, rh*0.8)
```
In effect: reels 1 and 2 land on the decoys at 45% and 70% of the spin, reel 3 never lands during the spin, and the
moment the prize is awarded all three show the prize's symbol (a win is always three of a kind; the decoys only tease).
The symbol strip moves **down** the window (`off` grows) despite the comment "scrolling upward".

`drawSym(cx, cy, s, size)` (`L11863-11906`), `u = size/10`:
- 0 heart: `#e0473f`, circles r 2.4u at `(cx -+ 2u, cy - u)` plus triangle `(cx-4.2u, cy) (cx, cy+4.4u) (cx+4.2u, cy)`.
- 1 shotgun: `#4a5260` rect `(cx-4.5u, cy-1.2u, 8u, 2.2u)`; stock `#8a5a33` rect `(cx+2.5u, cy-1.6u, 2.5u, 3.2u)`.
- 2 coin: `#d9a520` circle r 3.6u, `#f6d17a` circle r 2.4u.
- 3 bolt: `#6fd3a0` polygon `(1.5,-4) (-2.5,0.6) (-0.2,0.6) (-1.5,4) (2.5,-0.6) (0.2,-0.6)` x u.
- 4 star: `#f6d17a` 5-point star, outer 4u, inner 1.7u, first point up.
- 5 skull: `#cfd4de` circle r 3.4u at `(cx, cy-0.6u)` + jaw rect `(cx-2u, cy+1.4u, 4u, 2.2u)`; eyes `#14161c`
  `(cx-2u, cy-1.4u, 1.6u, 1.8u)` and `(cx+0.4u, cy-1.4u, 1.6u, 1.8u)`.

**The OUT OF ORDER sign** (`drawSign`, `L11967-11988`, "drawn, not a sprite; it's about 40px on screen"): standing
(`sign == 'stand'`, drawn with the cabinet, `L12128`) at `(slot.x + 4, slot.y - 44)` rotated -0.06; on the floor
(`'floor'`, drawn early with the corpses, `L11638`) at `(slot.x + 30, slot.y + 26)` rotated 0.5 and squashed to 45%
height. The card: shadow rect `(-23,-14,46,30)` rgba(0,0,0,0.35); card `(-22,-13,44,28)` `#c8a56b`; top strip
`(-22,-13,44,3)` `#a8854f`; tape rgba(255,255,255,0.5) `(-24,-16,10,5)` and `(14,11,10,5)`; "OUT OF" at (0,-2) and
"ORDER" at (0,8), bold 8px sans, `#2b2118`, centred.

**Recharge bar** (`L12130-12138`, "visible from anywhere"): while `cool > 0`: 56 x 5 at `(slot.x - 28, slot.y + 12)`,
back rgba(20,22,28,0.75), fill `#5a6274` to `56 x (1 - cool/spinCool)`.

**Prompt** (`L12140-12153`): the first living player (in list order: player 0 first, whoever is local) within
`slotRadius` and not spinning, and not game over: centred bold 13px sans at `(slot.x, slot.y + 28)`:
`OUT OF ORDER` `#8b93a4` if broken; else `recharging — 4.2s` (one decimal) `#8b93a4`; else `need $5` `#8b93a4` if poor;
else `$5 PLAY — stand still` `#f6d17a`.

**Spin ring on the player** (`L12347-12354`): an arc round the puller, radius `T.radius + 14` = 28, from straight up
clockwise by `frac x 2pi`, stroke 3 `#f6d17a` ("you're rooted while this closes").

In the HTML's first person (lobby only), the slot is a still cut-out of `idle_a` captured once per trip
(`shroomCapture`, `L4048-4050`): no reels, no animation.

### 13.6 Sounds

The slot itself makes no sound (no pull, reel or win sound). The SCREEN CLEAR whistle and boom are the weapons spec's.
A BUST brute arrives silently (its spawn ring shows).

---------------------------------------------------------------------------------------------------------------

## 14. The secret bonus room ("inside the machine")

Gary's second repair: a host-owned cinematic, a 20-second bonus room inside the slot machine, then an exact restore of
the run (`L13791-13923`, drawing `L13924-14097`). Triggered by the janitor (enemies spec 9.3): shoot him once during
his exit after a completed repair, and on his next hammer swing `beginSlotSecret(w)` runs. Once per world
(`slotSecret.used`); a restart (new world) makes it available again. Tweaks panel "preview secret" button
(`L14098-14110`) starts a fresh two-player run and jumps straight into it.

`BONUS_BOUNDS = { left: 90, right: 770, top: 135, bottom: 467 }` (`L13796`).
`secretActive(w) = !!(w.slotSecret && w.slotSecret.phase !== 'done')` (`L13797`).

### 14.1 `beginSlotSecret(w)` (`L13805-13818`)

Refused if already used or game over. `saved = deep copy of w` (JSON), with in the copy: janitor `phase 'done'`,
`secretReturn false`; `slot.broken false, busy -1`; `events []`, `freeze 0`. Then
`w.slotSecret = { used: true, phase: 'intro', t: 0, room: false, saved, origins: [{id, x, y} per player],
hazards: [], earned: 0 }`; `freeze 0, shake 0, over false`; players `v 0, spin 0, muzzle 0, iframe 0`;
`slot.flash 0, busy -1, broken false`; the banner is cleared.

### 14.2 Phases (`step`, `L13860-13923`)

| phase | how long | the sim | then |
|---|---|---|---|
| `intro` | 6.1 s | only `s.t` and `w.t` advance (nothing moves) | `enterMachine` |
| `landing` | 0.85 s | only clocks (controls locked) | `phase 'bonus'`, `t 0` |
| `bonus` | 20 s, or until everyone's down | `stepBase` runs (moving, shooting, notes), plus the room rules (14.3) | `finishMachine(survived)` |
| `payout` | 1.6 s | only clocks | `restoreFromMachine` |
| `return` | 1.15 s | only clocks | `slotSecret = { used: true, phase: 'done', t: 0, room: false }`; a guest who tried to join meanwhile is added; banner GARY KEEPS THE CHANGE (1800 ms) |

`enterMachine(w)` (`L13819-13834`): `phase 'landing', t 0, room true, hazards [], nextDrop 0.5, nextCash 0`; empties
`enemies, bullets, ebullets, coins, bits, blood, splats, corpses, floaters, plants, husks, rockets, blasts` ("b293:
rockets and blasts too, or one in the air went off in here"); `nuke null, breather 0, pending 0, queue [], over false`;
janitor 'done', `sign 'gone'`, `slot.broken true, cool 0, busy -1`. Each player: `alive, hp = 5, iframe 0, grace 1`, at
`(430 -+ 55, 350)` (player 0 left), every motion/action timer 0, `weapon 'blaster', wTime 0, blasters 1, speed 0,
magnet 0`, facing north. Coins are **not** touched (you keep your wallet in the room).

### 14.3 The room rules (each step of 'bonus', after `stepBase`)

```
s.t += dt
clamp every player to BONUS_BOUNDS
s.nextCash -= dt; s.nextDrop -= dt
if s.nextCash <= 0: s.nextCash += 0.23; a note (11.3 "bonus room rain")
if s.nextDrop <= 0:
  s.nextDrop = max(0.48, 1.05 - s.t*0.025)            # stamps come faster: 1.05 s apart at first, 0.55 at the end
  target = a random living player (rnd)               # none: aim at (430, 330)
  s.hazards.push({ x: clamp(target.x + (rnd-0.5)*220, 95, 765), y: clamp(target.y + (rnd-0.5)*180, 165, 440),
                   t: 0, hp: 3, hit: false })
for h in hazards:
  h.t += dt
  if h.t < 1.25:                                      # "shoot the marked skull mechanism before it stamps down"
    every bullet within 29 of (h.x, h.y - 35): removed, h.hp -= (b.dmg || 1), fx HIT at (h.x, h.y - 35)
  if h.hp <= 0 and not h.hit: h.hit = true; h.t = 1.65; fx KILL at h; 3 notes (11.3)
  if h.t >= 1.25 and not h.hit:                       # it stamps
    h.hit = true; w.shake = 6; fx WALL at h
    every living player within 40 with iframe <= 0 and grace <= 0: hp -= 1, iframe = 1, fx HURT; at 0: down, fx DOWN
hazards: drop those with t >= 1.85
s.earned = sum over players of max(0, coins - their saved coins)
all down -> finishMachine(false);  s.t >= 20 -> finishMachine(true)
```
`finishMachine(w, survived)` (`L13835-13840`): recompute `earned`, `survived`, `phase 'payout', t 0`, `over false,
freeze 0, shake 0`. While in the room the wave director, the janitor and potato growth are paused (other specs).

### 14.4 `restoreFromMachine(w)` (`L13841-13859`)

```
rewards = each player's coins now
Object.assign(w, saved)                                # the run comes back exactly as it was
w.slotSecret = { ...s, phase: 'return', t: 0, room: false }
over false, freeze 0, shake 0, events []
each player: coins = max(saved coins, rewards coins) + (survived ? 10 : 0)
             at (slot.x -+ 55, slot.y + 125), v 0, spin/roll/launch/muzzle 0, grace 2, iframe 0
enemies within 120 of a player: y = max(48, y - 145), stun 1.5       # room at the exit; the wave isn't advanced
```

### 14.5 Drawing (`render`, `L14050-14097`)

The camera is forced to 1x in the room (`camFollow`, `L8527`). `secretText(text, x, y, size=16, col='#d9f9ff')`:
bold monospace, 4px stroke `#111620`, centred.

- **intro**: the normal scene with nobody in it (no players, enemies, notes, blood, bodies, floaters, plants, husks,
  bits; janitor hidden; shake 0), then `drawSuction` (`L13986-14033`), with `t = s.t`, `hx = slot.x`,
  `hy = slot.y - 12`, `power = clamp((t - 0.5)/1, 0, 1)`:
  - after 0.35 s three Gary heads in the cabinet window: for i 0..2, a `#0d1721` rect `(hx-22+16i, slot.y-65, 15, 18)`
    and the top 30% of `JANITOR_SPRITES.front1` into `(hx-21+16i, slot.y-65, 14, 18)`.
  - a cyan cone `#64f8ff` at alpha `power x 0.2`: `(hx-10, hy) (hx-190, hy+240) (hx+190, hy+240) (hx+10, hy)`; the slot
    mouth: `#46e7f4` rect `(hx-13, hy-5, 26, 9)`, `#e0ffff` `(hx-8, hy-3, 16, 4)`.
  - from 1 s to 4.6 s, 15 notes sucked in: `f = ((t-1)*0.65 + i/15) % 1`, `a = 2.4i`, at
    `(hx + cos(a)*(1-f)*175, hy + 30 + (1-f)*200)`, rotated `a + t`: `#58b37a` 12x6 with a `#b6f5c3` 4x4 middle.
  - each player, from where they stood (`origins`): until 1.5 s standing (`secretSprite` at `(o.x, o.y + 12)`); 1.5 to
    4.15 s dragged to the slot (`f = min(1, (t-1.5)/2.1)`, smoothstep ease, to `(hx + side*11, hy + 12)`, `side` -1 for
    player 0), turned feet-first to angle `pi + side*0.22` (ramping in over the first third), shrinking to 82%,
    stretched to 112%, wobbling (`sin(t*30)*2*f`, then `sin(t*55)*2` once there); past halfway, a flailing arm
    (stroke 7 `#b76c43` then 4 `#eda66b`: `(x+12side, y+43) (x+25side, y+51) (x+side*(28 + sin(t*24)*5), y+65)`);
    under 70% skid marks (stroke 2, `#68bf44` player 0 / `#e4a24c` player 1: `(x-9,y+25)-(x-13,y+42)` and
    `(x+9,y+25)-(x+13,y+42)`); 4.15 to 4.43 s popping in (`f = (t-4.15)/0.28`, scale `0.82(1-f)`, stretch `1+f`).
    `secretSprite(p, x, y, angle, scale, stretch)` (`L13951`): the character's first `front_run` (or `front_a` /
    `front`) frame, 80 tall, pivot at the boots.
  - Gary (`drawSecretGary`, `L13963`) at `(slot.x + 62, slot.y + 22)`, mirrored, 58 tall: `swing_hit` until 0.4 s,
    `angry` until 4.8 s, then `pocket`.
  - texts: `...` at `(hx, hy+116)` 18px from 3.6 to 4.15 s; `POP!` at `(hx, hy+52)` 24px `#c5ffff` from 4.15 to 4.55 s;
    a note `#58b37a` 10x5 at `(hx+70, slot.y-5)` from 4.8 to 5.6 s (he pockets it); after 5.6 s a fade to
    rgba(5,9,18, min(1, (t-5.6)/0.5)).
- **landing / bonus / payout / return**: the normal scene drawn over the machine floor (`drawMachineFloor`,
  `L13928-13950`: `MACHINE_ART` stretched to 860x520 (fallback: `#202936` and a cyan frame with INSIDE THE MACHINE);
  four `COG_ART` gears 200x200 centred on the four corners, turning `w.t*0.12*dir + offset` with
  `[[0,0,1,0],[860,0,-1,0.2],[0,520,-1,0.4],[860,520,1,0.6]]` (a turn in 52 s; diagonal gears agree, neighbours
  counter-rotate); 12 chasing lamps 9x3 at `(82 + 62i, 109)`, `#d9ffff` when `(floor(t*7) + i) % 4 == 0` else
  `#235e72`). No breather text, no game over overlay, no HUD money or wave line in the room.
  - landing and return: the players are drawn tumbling in (`drawJared` with `launch`) from `(430, 505)` (landing) or
    from the slot (return) to their spot, eased `1 - (1-f)^2`, up an arc of 45, over 0.85 / 1.15 s.
  - In the room: the hazards (`drawBonusHazards`, `L14034-14049`: skipped once `hp <= 0`; a floor ellipse 38x17,
    warning `t < 1.25`: stroke `#fa965f`, fill rgba(242,94,61,0.12), plus a countdown arc radius 23 from the top,
    `2pi x t/1.25`; after: stroke `#ffdad1`, fill rgba(255,147,103,0.35); the skull block at `y = warning ? h.y - 35 :
    h.y - 13`: rects `(x-16, y-17, 32, 25)` + `(x-10, y+8, 20, 7)` in `#c1ced2` (warning) / `#ee9774` (stamped), eyes
    `#202735` `(x-11,y-9,8,8)` `(x+3,y-9,8,8)`, nose `(x-2,y+1,4,6)`, three hp pips `(x-12+9i, y-24, 6, 3)` `#66e5ed` /
    `#343f50`).
  - Top panel rgba(8,15,24,0.92) `(283, 87, 294, 27)`: `HOUSE MONEY  Ns` (`ceil(max(0, 20 - t))`) at (430, 107) 17px,
    or `PAYOUT` / `INSIDE THE MACHINE`. Bottom panel rgba(8,15,24,0.9) `(180, 482, 500, 33)`: `BANKED $<earned>`
    (+ `  + $10 EACH` in a survived payout) at (430, 496) 13px `#b1efb7`; `COLLECT CASH  /  SHOOT SKULLS  /  DODGE
    STAMPS` at (430, 509) 10px `#9db7c3`.
  - landing: `YOU ARE THE PRIZE` (430, 208) 22px `#e7d387`, and a dark veil rgba(8,15,24, (1-f)x0.7).
  - payout: `THANK YOU FOR YOUR CUSTOM` or `FAULT DETECTED — EJECTING` (430, 320) 20px; after 1.05 s a white-cyan
    flash rgba(190,250,255, min(1, (t-1.05)/0.55)).
  - return: `PLEASE CHECK THE PAYOUT TRAY` (430, 350) 18px `#f6d17a`; flash rgba(190,250,255, max(0, 1 - 3t)).

Pictures: `MACHINE_ART.src` (`assets/MACHINE_ART_src.jpg`, 860x520), `COG_ART.src` (`assets/COG_ART_src.png`,
256x256), `JANITOR_SPRITES` (`front1`, `swing_hit`, `angry`, `pocket`).

### 14.6 Sounds (`secretAudio`, `L13972-13985`), played from the render on both screens, once per beat

Beat = in intro by time: `hammer` (< 0.5 s), `reels` (< 1.5), `suction` (< 4.15), `pop` (< 4.6), `quiet`; otherwise
the phase name. On a change of beat:
- hammer: `sNoise(0.12, 1400, Q2, 0.3, bandpass -> 250)` + `sTone(0.1, 130 -> 60, 0.2, square)`
- reels: `sTone(0.6, 650 -> 170, 0.12, triangle)`
- suction: `sNoise(2.6, 180, Q1, 0.15, lowpass -> 1300)` (rising) + `sTone(2.6, 65 -> 280, 0.07, sawtooth)`
- pop: `sTone(0.13, 600 -> 50, 0.3, sine)` + `sNoise(0.1, 1400, Q1, 0.22, lowpass -> 120)`
- landing: `sNoise(0.15, 450, Q1, 0.2, lowpass -> 70)`
- payout: `sTone(0.35, 440 -> 880, 0.14, triangle)`
- quiet, bonus, return: nothing.

### 14.7 Over the network

`ss = secretPacket(w)` (`L13798`): `{ used, phase, t (3 decimals), room, clock: w.t, origins, earned, hazards (whole
objects), survived }`. The guest uses `ss.clock` as its `t` and no extrapolation while it's active (`L8404`, `L8412`).

---------------------------------------------------------------------------------------------------------------

## 15. The vending machine

"Bought, not won. Three rockets, then it's rubbish." It sells one thing: the **nuke launcher** (weapons spec: 3
rockets, `T.launcherRounds`), for `T.vendPrice` ($2500).

### 15.1 Where

`vendHere(w) = T.vendShow && w.started` (`L756`): **only in a run** ("b215: only out in the run, not in the lobby";
the lounge's wardrobe spot used to be its lobby place, b221). `vendPos(w)` (`L757`): `(ARENA.w x T.vendX, 18 + 54 +
T.vendDrop)` = **(705.2, 154)** in a run (the lobby value `(235, 154)` is unused). Not solid. Not in the bonus room.

### 15.2 Buying (`L7253-7273`)

All of: `vendHere`, not game over, `!vendSold`, not in the bonus room, the player isn't already holding the launcher,
`coins >= 2500`, **no move input and not firing**, within `T.vendRadius` (56). Then `p.buy += dt`; when
`buy >= T.vendHold` (0.8 s):
```
buy = 0;  coins -= 2500
if w.started: vendSold = true          # "the lobby never runs out" (dead: it's never in the lobby now)
prevWeapon = weapon;  giveWeapon(p, 'launcher')     # rockets = 3, banner "NUKE LAUNCHER!" 1400 ms
cooldown = 0.35                                      # no shot straight away
floater '-$2500' at (vp.x, vp.y - 40), '#e0473f'
sTone(0.08, 500 -> 900, 0.2, square);  sTone(0.25, 90 -> 60, 0.3, square)     # ka-CHUNK
```
Any frame the conditions fail, `buy = 0` (stepping away or moving resets the hold). One launcher per wave for the
whole room (shared `vendSold`); **restocks** when the next wave starts (`startWave`: `vendSold = false`).

### 15.3 Drawing (`L12012-12050`)

```
key = vendSold ? 'sold' : (floor(w.t * 2.5) % 2 ? 'idle_b' : 'idle_a')     # idle blinks every 0.4 s
h = T.vendHeight (150);  dw = 150 * 176/300 = 88                          # VEND_SPRITES are 176x300: "a clean 2:1"
shadow: ellipse (vp.x, vp.y + 4), radii (dw*0.45 = 39.6, 7), rgba(0,0,0,0.35)
draw at (round(vp.x - dw/2), round(vp.y + 6 - h), 88, 150), nearest
```
`VEND_SPRITES` (`L9435`): `idle_a`, `idle_b` (the display showing `$2500` and "3 ROUNDS INCL", lights blinking),
`sold` (the display reads SOLD OUT). An olive military locker with hazard stripes and the trefoil, the launcher
behind glass.

Text, when any living player is within `vendRadius` and not game over (the first in list order), centred:
- bold 13px at `(vp.x, vp.y + 28)`: `SOLD OUT — back next wave` `#e0473f`, or `NUKE LAUNCHER — $2500` `#f6d17a`.
- if not sold, 12px at `(vp.x, vp.y + 44)`: `you’ve already got one` `#8b93a4` (holding the launcher), or
  `you’re $N short` `#8b93a4`, or `stand still to buy` `#9be29b`.
- if `buy > 0`: a hold bar 70x6 at `(vp.x - 35, vp.y + 50)`: back rgba(20,22,28,0.8), fill `#9be29b` to
  `70 x buy/vendHold`.

In the HTML's first person it would be a still `idle_a` cut-out (`L4051-4053`), but first person is lobby-only there,
where the machine isn't.

---------------------------------------------------------------------------------------------------------------

## 16. Floaters (the floating words)

Step (`L8199-8203`): `t += dt; y -= 34*dt` (rises 34 units a second); removed when `t > 0.9`.

Draw top-down (`L12625-12637`), in the world (through the camera, so they scale with zoom), after the nuke and over
everything else in the world: alpha `t < 0.6 ? 1 : 1 - (t - 0.6)/0.3`; bold 13px monospace, centred; a shadow copy
rgba(0,0,0,0.6) at +1,+1; then the text in `col` (default `#7fd89a`).

First person (b308, `shroomWords`, `L4069-4079`): "floating words (+$, OOF, WHEEE!) and Gothica's speech, where they
are in the room (hidden behind walls)": anchored at ground `(f.x, f.y + 40)`, height `40 + f.t*30`, projected, hidden
if a wall is nearer in that screen column; bold 16px, same alpha and shadow.

Every floater in the game:

| text | colour | at | from |
|---|---|---|---|
| `$n` (kill pay) | killer's `P_COLOURS`, or `#7fd89a` when split | `(x, y - 10)` | `payKill` `L6504`, `L6510` |
| `$3` | shooter's colour | `(d.x, d.y - 20)` | a dummy knocked down `L7787` |
| `-$2500` | `#e0473f` | `(vp.x, vp.y - 40)` | buying the launcher `L7269` |
| `SPLAT!` | `#e9c98f` | `(x, y - 30)` | a full-power potato bursts `L6978` |
| `SPLASH!` | `#8fd3ff` | `(x, y - 50)` | a dive into the pool `L5679` |
| `POTATOES!` | `#d8b878` | `(ropeX, ropeY - 30)` | the bell rope `L10004` |
| `WHEEE!` / `OOF` | `#f7a8ff` / `#ffd0d0` | over Gothica (`- dz - 40` / `- 40`) | throwing Gothica `L10330`, `L10346` |
| `+2` (`'+' + PROT.heal`) | `#7dff9a` | `(g.x, g.y - 46)` | Gothica eats a potato (Protect mode) `L13020` |
| `YUM!` / `BLEH!` | `#7fd89a` / `#9aa0a8` | `(p.x, p.y - 70)` | a snag from the barbecue `L2067` |
| `*cough*` | `#e8e2d2` | the mouth, `- 18` | the bong / vape, 35% of the time `L5176`, `L5617` |
| `LOAD IT EVEN`, `N KG`, `N REP(S)`, the rep count | `#ffb070`, `#f6d17a`, `#8fd3ff` | over the bench / leg press | the gym `L974-1021` |
| blackjack results, `need 10 coins`, `Gothica's busy!` | various | `(q.x, q.y - 70)` | `bjFloat` `L5253-5319` |

Only `payKill` caps the list at 30. They're sent in full each snapshot (`fl`).

---------------------------------------------------------------------------------------------------------------

## 17. The big banner (shared)

`banner = { text, until }` (`L6876`), drawn last of all (`L12665-12675`) so nothing covers it: bold 34px sans, centred
at `(430, 90)` on the screen (not the world), 5px stroke rgba(20,22,28,0.9), fill `#f6d17a`, while
`performance.now() < until`. This system's banners: the prize label (1600 ms), MACHINE IS LIVE (1600 ms), GARY KEEPS
THE CHANGE (1800 ms); via `giveWeapon`: BLASTERS!, SHOTGUN!, NUKE LAUNCHER! (1400 ms). The banner is a local variable
on the host and is **not** in the snapshot: the guest never sees it (20.4).

---------------------------------------------------------------------------------------------------------------

## 18. The kill counter and the HUD money

### 18.1 Kills

`p.kills += 1` on a **bullet** kill (`L7767-7768`, the bullet's owner) and a **rocket** kill (`L7106`, the rocket's
owner). Punches, thrown and lobbed potatoes, potato bursts, shrapnel and the nuke don't count; dummies don't count.
`totalKills = sum of p.kills` (`L12461`).

### 18.2 The HUD (`L12458-12479`), drawn on the screen (not through the camera), inside the shake

- Top line, 12px monospace `#6d7486` at `(26, 38)`: in a run `wave N   M left   K killed` (three spaces between);
  with `?debug` it's prefixed `b331   ` and followed by the network readout; in the lobby nothing (non-debug); in the
  bonus room nothing.
- Wallet, one line per player in player order, bold 17px monospace, in `P_COLOURS[p.id]`, at
  `(26, 64 + 22*i)`: `$<coins>`. Both players' wallets show on both screens. Next to it at x = 88 the launcher's
  rockets (`☢ n`) or the spud ammo (weapons spec). Hidden in the bonus room.
- Game over (`L12677-12695`): `made it to wave N — K killed` (classic mode) uses `totalKills`.

Reference: `godot/reference/wave.png` (`$2500  ● 20` in red top-left, `wave 1   6 left   0 killed` above it),
`reference/lobby_topdown.png` (`$2500` over the slot in the lobby).

---------------------------------------------------------------------------------------------------------------

## 19. Sounds

All synthesised (Web Audio), master gain 0.5 (`audioInit`, `L11194`). `sNoise(dur, freq, q, gain, type, sweepTo)`
(`L11213`): a looping 1.2 s white-noise buffer -> BiquadFilter `type` (lowpass/bandpass) at `freq`, `Q = q`,
exponential ramp of the cutoff to `max(40, sweepTo)` over `dur` (if `sweepTo`) -> gain from `gain` exponentially to
0.0008 over `dur`; stops at `dur + 0.02`. `sTone(dur, f0, f1, gain, wave)` (`L11228`): an oscillator (`wave`, default
sine) at `f0`, exponential ramp to `max(20, f1)` over `dur` if `f1` (0 = steady), same gain envelope.
`vary(n, amt = 0.12) = n * (1 + (rand - 0.5) * amt)` (`L11242`).

| sound | recipe | when |
|---|---|---|
| `SFX.hit` (`L11322`) "wet thud on an enemy" | `sNoise(0.075, vary(900), 1.6, 0.24, lowpass -> 240)` + `sTone(0.05, vary(190) -> 80, 0.10, triangle)` | fx HIT |
| `SFX.kill(big)` (`L11326`) "meatier, with a downward drop" | `sNoise(big ? 0.34 : 0.22, vary(1100), 1.1, big ? 0.5 : 0.36, lowpass -> 130)` + `sTone(big ? 0.26 : 0.18, vary(160) -> 38, big ? 0.32 : 0.22, sawtooth)` | fx KILL (small), fx BOOM (big) |
| `SFX.cash` (`L11341`) "a note landing on you" | `sTone(0.07, vary(1180, 0.16), 0, 0.11, triangle)` + `sTone(0.09, vary(1760, 0.16), 0, 0.07, sine)` | a note picked up (host only) |
| vending buy | `sTone(0.08, 500 -> 900, 0.2, square)` + `sTone(0.25, 90 -> 60, 0.3, square)` | the launcher bought (host only) |
| secret beats | 14.6 | both screens |

`playEventSounds(list)` (`L11371-11382`) maps events: HIT -> hit, KILL -> kill(false), HURT -> hurt, DOWN -> down,
BOOM -> kill(true), LAUNCH -> sfxRocket, BLAST -> sfxBlast (WALL, SPLASH, DIVE: none). The host plays from
`world.events` every frame (`L12805`); the guest from each snapshot's `x` once (`L12731-12735`). See 23.1 for a
repeat bug on the host.

---------------------------------------------------------------------------------------------------------------

## 20. Over the network (for milestone 4)

The host simulates; the guest draws `worldFromSnapshot(snap, age)` (`L8403`). Snapshots go every 50 ms
(`L11104-11107`). This system's fields (`snapshot`, `L8300-8399`):

| key | content | guest rebuild |
|---|---|---|
| `fz` | `round(freeze * 1000)` | `freeze = fz/1000`; age forced to 0 while > 0 |
| `sk` | `round(shake)` | `shake` |
| `fl` | floaters `[round x, round y, text, round(t*100), col]` | as is (no ageing) |
| `sl` | `[round slot.x, round slot.y, round(flash*100), round(cool*10), PRIZES index or -1, decoy0, decoy1]` | `prize = PRIZES[i >= 0 ? i : 0]`; `busy` and `broken` not here |
| `jn[8]`, `jn[9]` | sign 0 stand / 1 floor / 2 gone; `slot.broken` 0/1 | `sign` ('gone' if no `jn`), `slot.broken` |
| `vs` | `vendSold` 0/1 | |
| `p[i][13]`, `[15]` | `kills`, `coins` | |
| `p[i][18]`, `[19]`, `[21]`, `[41]` | `round(spin*100)`, `round(speed*10)`, `round(magnet*10)`, `round(buy*100)` | `/100`, `/10`, `/10`, `/100` |
| `c` | notes `[round x, round y, round(life*10), round(arm*100), round vx, round vy, pull]` | no `rot`, `spin`, `phase` (they draw with 0), not extrapolated |
| `bl` | sprays `[round x, round y, round(a*50), round(t*100), big, round(scale*100)]` | `a/50`, `t/100`, `scale/100` |
| `cp` | corpses `[round x, round y, t, round(rot*50), round(life*50), round(max*50), flip, round odo, part, mask, round z]` | no `vx`, `vy`, `vz`, `spin` |
| `sp` | splats `[round x, round y, k, round(life*4), round(a*50), round(scale*100)]` | `life/4` |
| `x` | `w.events` (then cleared) | `playEvents` (sparks) + `playEventSounds` |
| `ss` | the secret packet (14.7) | |
| `tm` | `round(w.t*100)` | `t = tm/100 + age` (b293: "was 0 outside the secret room, so the slot reels and the vending machine stood still for the guest") |

Not sent: `bits` (the guest makes its own from events), `GORE_FX` (each screen its own), the gore caches, `banner`.

### 20.4 What the guest misses (fix in milestone 4)

- **The banner** (prize names, MACHINE IS LIVE, weapon banners): local to the host. Send it (text + time left) or as an
  event.
- **The cash pickup sound** and the vending buy sound: played inside the host's sim. Make them events.
- **Gore flecks**: corpse `vx`/`vy` aren't sent, so on the guest the flecks' velocity is NaN and they never draw.
  Send pieces' velocity (or let the guest spawn flecks with only the random part).
- Notes' flutter (`rot`, `phase`) and corpse motion between packets: not extrapolated (bodies and notes step at 20 Hz
  on the guest). Fine to send `vx, vy` and extrapolate.
- The sparks that `burst` makes directly (potato flesh, magnet pickup) have no event.

---------------------------------------------------------------------------------------------------------------

## 21. History worth keeping (the `bNNN` notes)

- **b215**: no nuke vending machine in the lobby; only out in the run (`L755`, commit `295b353`).
- **b221**: the wardrobe went where the vending machine used to stand in the lounge (`L1939`); b253: the arcade
  cabinets sit beside the slot machine on the lounge's top wall (`L2489`).
- **b224**: the test buttons (shotgun, nuke, magnet) and their keys only with `?debug` (`L602`).
- **b288**: gore: limbs cut along the outline with red stumps, the body keeps what's left (`L6341`); a pool of blood
  spreads out from under a body that's lost parts (`L11594`); corpses kept to 90 "because every piece goes over the
  network" (`L6444`); commit `6cce78d` "Gore: limbs fly off on kills, cut along the outline".
- **b293**: the guest's clock is the host's (`tm`), so the slot reels and the vending machine animate for the guest
  (`L8412`); rockets and blasts are cleared on entering the machine, "or one in the air went off in here" (`L13822`).
- **b308**: floating words in first person, where they are in the room, hidden behind walls (`L4068`).
- **b312**: the tweaks (sliders, the secret preview, the C and J test keys) hidden until "Show tweaks" (`L605`).
- Comments with no b-number but worth keeping: "Cash from a kill goes straight to whoever earned it" (the old coin
  scatter, `dropCoins`, is dead code); "the corpse shoves whatever it falls into"; "the kill: a fan of sprays along the
  shot line, the world stutters, then the body's blood hits the floor. This is the 0.2 s that has to land. The body
  doesn't vanish: it gets thrown by whatever killed it, tumbles, and fades. That's the beat that was missing between
  the shot and the cash." (`L6337-6340`); `T.splatAlpha` "floor stains: dark now, so they can carry more opacity";
  the magnet ring "slow, shallow breath: it was flickering fast enough to be distracting".

---------------------------------------------------------------------------------------------------------------

## 22. Edge cases, quirks and bugs (as the HTML has them)

22.1 **Event sounds repeat on the host.** `playEventSounds(world.events)` runs every rendered frame (`L12805`), but
`world.events` is only emptied by `snapshot()`: every 50 ms when hosting, every 0.25 s when playing alone (the
"B/tick" measurement, `L12807-12811`). So each hit/kill sound is re-triggered every frame until then (up to ~15
times alone at 60 fps). Almost certainly unintended: **in Godot play each event once** (and compare the loudness by
ear; if the HTML's stacked thud is what the owner likes, raise the gain instead).

22.2 The kill counter misses punch, potato, splat, shrapnel and nuke kills (18.1).

22.3 A split kill pay can create money: `each = max(1, round(n / alive))` (a $5 brute with two players alive pays $3
each); the floater shows the original `$n`.

22.4 SPEED BOOST, CASH MAGNET (and the shotgun clock) only count down in a run: won in the lobby, they last until
Start (which zeroes them).

22.5 BUST in the lobby really drops a brute into the lounge (the enemies step runs in the lobby); SCREEN CLEAR in the
lobby really drops the bomb (kills it, throws everyone). Only `dropTestNuke` checks `started`.

22.6 **You can't beat the janitor to his notes**, despite the comment: they're armed (untouchable) for 0.5 s but he
pockets everything within 90 of the slot 0.43 s after paying (0.18 s more of 'bend' + 0.25 s into 'pocket'), and they
only fly ~40 units. Keep (it's his joke) or make the arm 0.3 s so a magnet or a quick player can snatch them.

22.7 The OUT OF ORDER sign stands on the cabinet in the lobby too (`sign` starts 'stand' in every new world, and the
lobby slot works), see `reference/lobby_topdown.png`.

22.8 The slot prompt and the vending text use the first player in range in list order, not the local player: in
co-op the guest standing at the machine sees the host's numbers if the host is also in range.

22.9 A pull starts with no move input, even mid-roll (a roll with no stick input); the puller is then rooted where he
is. Firing doesn't block a pull (it does block buying).

22.10 If the run ends while `shake > 0`, the sim stops (`world.over`) and the shake never decays: the screen keeps
jittering under the DOWN overlay. In Godot decay the shake in real time or zero it on game over.

22.11 Notes can't expire while armed (the `continue` skips the removal); harmless (every `arm` < `life`).

22.12 The magnet ring is drawn at **half** the real reach (230 vs 460).

22.13 `slot.sym` is never used. `slot.busy` isn't sent: the guest's drawing only needs the players' `spin`.

22.14 The corpse clamp uses the arena rectangle even in the tall lobby (only matters for a BUST brute killed in the
yard/bedroom, which can't happen in practice).

22.15 `goreBodyImage` returning null for a masked body (no labels) draws nothing for the body (its pieces still fly).

22.16 `testCash = 2500` is a testing value ("Set 0 before release"): with it every run starts able to buy the
launcher. Keep it a tunable in Godot, defaulting to the HTML's 2500 until the owner says otherwise.

22.17 The spray frames' pixel sizes differ (frame 0 is small): each is drawn at the same width, so frame 0 is
enlarged ~3x. Reproduce by scaling each frame to the same width, not by atlas cell size.

---------------------------------------------------------------------------------------------------------------

## 23. In Godot

### 23.1 What to build on (milestone 1 contracts, `godot/scripts/`)

- `GameData` (autoload): `data["T"]` (all the numbers above), `data["ETYPE"]`, `data["FX"]`, `data["P_COLOURS"]`,
  `data["ARENA"]`, `data["calls"]["slot"]` (`{x: 90, y: 110}`), `data["calls"]["vendPos"]` (`{x: 235, y: 154}`, the
  unused lobby spot); `manifest["BLOOD_SPRITES"]` (`hit`/`boom`/`splat` arrays), `manifest["SLOT_SPRITES"]`,
  `manifest["VEND_SPRITES"]`, `manifest["ENEMY_SPRITES"]` (the `front` pictures for gore), `manifest["MACHINE_ART.src"]`,
  `manifest["COG_ART.src"]`, `manifest["JANITOR_SPRITES"]`; `tex(path)`; `world_to_3d(x, y, z)` / `from_3d(v)`;
  `UNIT` 0.025. `PRIZES` and `FX_LOOK` aren't in `game_data.json`: put them in a constants script (2.).
- `Player` (CharacterBody3D): `html_pos()`, `place()`, `facing`, `moving`, `dz`, `frozen`, `steer` (non-contract,
  readable: the stand-still test), `vel` (non-contract).
- `CharSprite`: not used directly (the bonus-room tumble reuses whatever draws players; `secretSprite` is just the
  `front_run` frame).
- `CameraRig`: `mode` (`TOP_DOWN` / `FIRST_PERSON`), `mode_changed`, `camera()` (for shake via `h_offset`/`v_offset`,
  which the rig doesn't touch; for screen projection), `set_mode()` (forcing top-down in the bonus room cinematics).
- `Interactable`: optional E on the slot and vending machine (23.6).
- The milestone 2 specs' shared pieces: `ArenaSim` (enemies spec 12.1: the world step, `enemy_killed` signal, `fx`
  signal, `rnd()`), `WeaponSim` (weapons spec 18.3: bullets, `potato_splat`, `detonate`, `punch_land`), the synth
  autoload (`Synth` in the weapons spec, `Sfx` in the enemies spec: **one** autoload, whichever name the integration
  picks), the HUD banner API (`WaveHud`/`weapon_hud`: one `Banner.show(text, secs)`).

### 23.2 Contract additions this system needs (agree them; don't edit others' files)

- **Player**: `id` (0/1) and `alive` (both other specs ask too); `speed_mul: float = 1.0` (the max-speed multiplier:
  SPEED BOOST sets 1.55 while it runs); `hp` writable (+2 HEALTH; enemies spec's `PlayerVitals` may own it); a
  "rooted" state for the pull (use `frozen` plus `vel = 0`, or the weapons spec's `can_shoot()` false while pulling);
  a way to tell "no move input this step" (`steer == Vector2.ZERO`) and "fire held" (the weapons spec's `InputFrame`).
- **The kill path**: `ArenaSim.kill_enemy(e, dir: Vector2, big: bool, owner: int, counts: bool)` (enemies spec 12.1)
  calls `GoreSim.on_kill(e, dir, big)` and `LootSim.on_kill(e.x, e.y, e.t, owner, counts)` in the HTML order (5.4):
  shrapnel/KILL fx, corpse, shake, killBurst, splat, payKill, remove, kills.
- **Hits**: `GoreSim.spray(x, y, dir, big)` from `WeaponSim` on bullet hits (5.3); `GoreSim.fx(kind, x, y)` (or
  `ArenaSim.fx`, whoever owns the event list) for every effect.
- **CameraRig** (Player and cameras task): ideally `shake_offset: Vector2` applied in both modes; until then this
  system sets `camera().h_offset/v_offset` each frame (they're zero otherwise; check with that task).

### 23.3 Scripts and scenes (proposed; new files owned by this task)

| file | class | job |
|---|---|---|
| `scripts/loot/loot_defs.gd` | `LootDefs` (static) | `PRIZES`, `SYM_COUNT`, `FX_LOOK`, `FX` ids, `pick_prize(rng)`, colour constants |
| `scripts/gore/gore_sim.gd` | `GoreSim` (RefCounted, owned by the world sim) | lists `blood`, `splats`, `corpses`, `bits`, `events`; `shake`, `freeze`; `fx()`, `burst()`, `spray()`, `kill_burst()`, `splat()`, `make_corpse()`; `step(dt)` for 4.10, 4.16-4.18, 4.21; `snapshot()`/`apply_snapshot()` parts |
| `scripts/gore/gore_cutter.gd` | `GoreCutter` (static, cached) | 7.1/7.2 on `Image`s -> `ImageTexture`s + crop offsets; `body(path, mask)`, `part(path, part)` |
| `scripts/gore/gore_view.gd` | `GoreView` (Node3D) | draws splats, blood pools, corpses and parts, flecks, sprays, sparks (23.5) |
| `scripts/loot/loot_sim.gd` | `LootSim` (RefCounted) | per-player wallet (`coins`, `kills`, `speed`, `magnet`, `spin`, `buy`), `coins` list, `floaters`, `pay_kill()`, the note step (11.4), the slot (13.2-13.4), the vending machine (15.2), restock on `wave_started`, run/lobby resets (3.3) |
| `scripts/loot/slot_machine.gd` | `SlotMachine` (Node3D) | the cabinet view: sprite, reels, sign, recharge bar, prompt, win flash; optional `Interactable` child |
| `scripts/loot/vending_machine.gd` | `VendingMachine` (Node3D) | the cabinet view, texts, hold bar; optional `Interactable` child |
| `scripts/loot/coin_view.gd` | `CoinView` (Node3D) | the notes (MultiMesh), streaks, magnet and speed rings |
| `scripts/loot/floater_view.gd` | `FloaterView` (Node3D) | a pool of `Label3D` |
| `scripts/loot/bonus_room.gd` | `BonusRoom` (Node) + `bonus_room_view.gd` | section 14: phases, save/restore of the whole world state, hazards, the cinematic |
| `scripts/ui/money_hud.gd` | `MoneyHud` (Control under the HUD CanvasLayer) | the wallet lines; the kill count goes in the enemies spec's top line (`WaveHud`), read from `LootSim.total_kills()` |

Build nodes in code, like milestone 1. The world sim (`ArenaSim`) owns one `GoreSim` and one `LootSim` and steps them
at 1/120 in the order of section 4; the views read the sim (or a snapshot-rebuilt copy on the guest) and never write
it. Keep positions in HTML units in the sim; convert with `GameData.world_to_3d()` only in views.

RNG: use the world's LCG (`ArenaSim.rnd()`) for everything the HTML draws from `rnd(w)` (prizes, decoys, corpse
throws, sprays, splats, coin throws); use a separate `RandomNumberGenerator` for sparks (5.2) so pure-show effects don't
shift the gameplay sequence (a harmless deviation: nothing replays the HTML's seed).

### 23.4 Simulation and timing

- Hit-stop: `ArenaSim` checks `gore.freeze` first in its step (4.1) and returns. The Player is moved by the Player
  task: to freeze him too, set `player.frozen` while `freeze > 0` (the contract has it) or skip as the enemies spec
  suggests. Mouse look and the camera keep working (it's a sim freeze).
- Shake decays in the sim step (90/s) for parity, plus: on game over set it to 0 (22.10).
- Events: `fx()` appends to the event list (cap 40 per snapshot interval) **and** emits `fx(kind, x, y)` for local
  sound and sparks immediately. Each event's sound plays exactly once (22.1).
- Floaters, corpses, sprays, splats, notes and sparks step in the sim at 1/120 (they're part of the snapshot). Flecks
  run in the view at frame rate with `gdt = min(0.05, delta)`.

### 23.5 Drawing in 3D (both views)

Materials: unshaded or lit per the look pass (1.5); nearest filtering; alpha blending for blood, alpha scissor for
cut-outs. A shared **billboard-with-roll** shader (`shaders/billboard_roll.gdshader`: faces the camera, then rotates by
a `roll` uniform about the view axis; the enemies spec wants the same for lean) is used by sprays, corpses in flight,
parts and sparks. Decals are **not** available in the Compatibility renderer: floor marks are quads.

- **Splats** (6.4): flat quads lying on the floor, `y = 0.002 + 0.00001 x index` (m) against z-fighting, size
  `63 x scale` units wide by the picture's aspect, rotated `a` about the vertical (the HTML's screen plane *is* the
  ground, so the image's x/y map straight onto ground x/y), alpha `min(1, life/3) x 0.62`. Six `MultiMeshInstance3D`s
  (one per `splat_k` picture, 140 instances max between them), per-instance colour alpha. Same for the
  blood **pools** under bodies (8.3), a seventh pass with their own growth.
- **Sprays** (6.2): a pool of 48 quads with `billboard_roll`, placed at the ground point lifted to mid-body
  (`z = 0.45 x r x enemyScale` of the type hit, ~23 units for a grunt), sized `dw x dh` (6.2), pivot offset so the quad
  spans `-0.35 dw .. +0.65 dw` along its x, `roll` = the **screen-space** angle of the spray direction: project
  `p` and `p + dir x 20` with `camera.unproject_position()` and take `atan2`. Top-down that reproduces the HTML; in
  first person a spray going away from you points up/down the screen. When the projected length is under 25% of the
  full (shooting straight away), use roll = a random angle fixed per spray so it still bursts. Frames: the 8 `hit` or
  `boom` textures, each scaled to the same width (22.17), frame = `min(7, floor(t/0.34 x 8))`, alpha
  `1 - (t/0.34)^3`.
- **Corpses** (8.3): a pool of 90. Each: a floor shadow (a dark disc, radius `0.9 r sk`, alpha `sa x body alpha`), the
  picture quad (`billboard_roll`, `roll = rot`, flipped when `flip`) with its pivot at the cut-out's centre for parts
  and at 55% down the picture for bodies; body height `r x 3.4` units; part size `pc.w x k` by `pc.h x k`. Height:
  parts at `z`; the body's pivot at `0.45 h` above the floor. **Settling:** when a body's `|v| < 20` and `spin < 0.5`
  (or after 0.6 s), and a part once it has landed and stopped bouncing, ease the quad over 0.15 s to lie flat on the
  floor (face up, pivot 1 unit up, rotated `rot` about the vertical, alpha unchanged). Top-down a flat body looks like
  the HTML's; first person you see it lying there instead of a card standing on its head. Fade alpha
  `min(1, life/max x 2.2)`.
- **Flecks** (8.4): one `MultiMeshInstance3D` (260 max) of 2x2 / 2x3-unit camera-facing squares, colours as 8.4, spawned
  from airborne parts at 30/s.
- **Sparks** (9): one `MultiMeshInstance3D` of 3x3-unit camera-facing squares at the ground point lifted 10 units (so
  they read over the floor in first person), per-instance colour and alpha `life/max`.
- **Notes** (11.5): bake the note into a 16x10 `ImageTexture` twice (normal inner `#58b37a`, bright `#7fd89a`). Two
  `MultiMeshInstance3D`s (normal and bright: bright while `arm > 0` or `pull`) of flat quads at `z = 3 + bob`,
  rotated `rot x 0.25` about the vertical, scaled by `flat` along their local short axis. The blink when `life < 2`
  hides the instance. Shadow: a small dark ellipse quad on the floor. Streaks: 4 quads per fast note behind
  it along `-v`. Optional (decision): give notes in the air (`arm > 0`) a little height
  (`z = 3 + 18 x sin(pi x arm/arm0)`) so the JACKPOT shower reads in first person; `arm0` is known when spawned (send
  it in the snapshot too).
- **Magnet ring**: a thin floor ring (a flat torus or a line loop mesh) of radius `230 x pulse` around the player,
  colour rgba(246,209,122,0.28); **speed ring**: an ellipse ring `18.2 x 8.4`, centred 12 units south of his feet
  (in 3D make it a circle of radius 18 round his feet; the HTML's squash is just the top-down look).
- **Floaters** (16): a pool of `Label3D` (bold monospace font, outline 2 px black at 0.6 as the shadow, `col`), at the
  ground point `(f.x, f.y_spawn + off)` with height `off + 34 x t` where `off` is the spawn's upward offset (10 for
  `$n`, 20, 30, 40, 50, 70 as in the table), so the words rise straight up from where they happened. Top-down:
  `pixel_size` so the text is 13 units tall, `no_depth_test = true`, drawn on top. First person: `fixed_size = true`,
  sized to about 3% of the view height (16 px of 520), depth test **on** (hidden behind walls, b308).
- **Shake** (10.2): every frame, `amt = min(40, shake)`, offset `o = (rand - 0.5) x amt` per axis in HTML screen
  units; top-down: `camera.h_offset/v_offset = o x (VIEW_H / zoom x UNIT x sin(pitch)) / 520` metres (so 1 unit of
  shake is 1/520 of the screen height, like the HTML at any zoom); first person: `o x 0.0015` m (small, a jolt rather
  than a slide; the enemies spec suggests a rotation, which needs the rig). The HUD doesn't shake (a deliberate
  simplification; offset the HUD's root Control by `o x viewport_h/520` px if the owner misses it).

### 23.6 The slot machine and the vending machine in 3D

- **Cabinets**: build them the way the World task builds the arcade cabinets (`CABINETS`), so they match: either an
  upright picture with the same tip-back shader `CharSprite` uses (top-down shows the whole picture like the HTML,
  first person shows it standing), or a box wearing the picture on its front. Size: slot `86.4 x 124.2` units
  (2.16 x 3.1 m drawn; as a real object ~86 wide, 30 deep, about 2 m tall with the picture's lower 124 units mapped to
  the front face); vending `88 x 150` units drawn (2.2 x 3.75 m; make the box about 2.3 m tall, 0.8 m deep). Feet
  (the picture's bottom minus 6 units) on the floor line `(x, y)`. Non-solid for parity (the HTML's are walk-through),
  or player-only collision as a deliberate change; enemies pass through either way.
- **Slot frames**: swap the texture: `win` while `flash > 0`, `spin` while anyone spins, else `idle_a`/`idle_b` every
  1/3 s; alpha 0.38 broken, 0.55 recharging.
- **Reels**: a small `SubViewport` (about 80x44 px, transparent) whose `Control._draw()` reproduces 13.5's reel code
  (window, three clipped columns, `drawSym` with `draw_circle`/`draw_colored_polygon`/`draw_rect`), shown as a quad on
  the cabinet face at the reel window (`cy = 0.503 h` down from the top, centred on `cols[1]`), slightly in front of
  it, only while spinning or flashing. The same view in both modes; in first person, standing at the slot (within
  46 units, ~1.15 m), the window is readable.
- **Sign**: a 44x28 card texture drawn once (13.5) on a quad: standing on the cabinet face at `(x + 4, y - 44)` (i.e.
  44 units up the front, tilted -0.06 rad), or lying flat on the floor at `(x + 30, y + 26)` rotated 0.5 rad.
- **Recharge bar**, **prompt**, **vending texts and hold bar**: `Label3D`s / small quads under the machine at the HTML
  offsets (top-down they read as in the HTML). First person: also show the line in the E prompt area (the HUD's prompt
  label), since text on the floor is hard to see from eye height.
- **Activation**: keep the HTML rule (stand still in range: no `steer`, and for buying not firing) so it plays the
  same. Also add an `Interactable` to each with `label_for` = `PLAY $5` / `BUY $2500` (or "" when it can't), whose
  `act()` starts the pull at once / starts the hold (an explicit button for pad and touch players; E also works in first
  person). Log as a decision.
- **Spin ring** on the puller: a floor arc (or a billboard ring round his middle) radius 28, closing over 1.6 s.
- **Positions**: slot `(90, 110)` in the lobby, `(430, 110)` in the run; vending `(705.2, 154)` in the run only.
  The run's room layout is the enemies spec's `ArenaRoom` (12.6).

### 23.7 First person for this system

The HTML only has first person in the lobby; the plan wants everything working in both views:
- Gore: sprays, bodies, parts and flecks are all 3D-positioned (23.5), so they work from eye height as is. Bodies
  settle flat (23.5), so you see corpses lying on the floor in front of you. Splats are floor quads.
- Notes: flat on the floor; the magnet pull and the streaks read from eye height; a pickup plays `cash`.
- Floaters: fixed-size, depth-tested `Label3D`s (b308's rule).
- Shake: small camera jolts (23.5). Hit-stop: sim only, the look keeps moving.
- Machines: real cabinets; the reels on the face; the prompt in the HUD's E area; E works.
- HUD money and kills: CanvasLayer, the same in both views (top-left).
- **The bonus room**: its art (`MACHINE_ART`, the cogs, the lamps) is a flat top-down picture, and its cinematic is
  2D. Force the top-down view (`CameraRig.set_mode(TOP_DOWN)`, zoom 1x) for the whole secret sequence and put back
  the player's view after `return` (decision; first person inside the room can come later with a proper 3D room).
  The room's floor is a quad with `MACHINE_ART` over the arena, the cogs as four turning quads at the corners, the
  lamps as 12 small quads; the hazards as floor rings plus a skull block quad hovering 35 units up while it warns.

### 23.8 Sound in Godot

Through the shared synth autoload (weapons spec 18.8: each recipe baked to an `AudioStreamWAV` on first use, cached,
4-6 `vary` variants): `SFX.hit`, `SFX.kill(false/true)`, `SFX.cash`, the vending ka-chunk, the six secret beats
(19, 14.6). Trigger hit/kill from `fx` events once each (22.1). In first person use `AudioStreamPlayer3D` at the event
point for hit/kill (positional), plain players for cash and UI sounds.

### 23.9 Network readiness (milestone 4)

`GoreSim.snapshot()` / `LootSim.snapshot()` return the arrays of section 20 in the same packing (keep `PRIZES` order,
FX ids, part ids). Add what the HTML misses (20.4): the banner, cash/buy sound events, corpse piece velocities (for
flecks), notes' `rot`/`phase`/`arm0`. The guest's views read the rebuilt state only. The bonus room saves and restores
the **whole** world state on the host (every sim's state, as a deep copy: `ArenaSim`, `WeaponSim`, `GoreSim`,
`LootSim`, player positions/hp/weapons), so each sim needs `save_state() -> Dictionary` and `load_state(d)`.

### 23.10 Checks when it's built

- A blaster kill on a grunt: green sparks, the body thrown along the shot (230..405 units/s) tumbling, one arm and one
  leg flying up (8 units, 100..200 up) and bouncing with small stains, a fan of five sprays unfurling over ~0.1 s,
  the world freezing 3 steps, a 5 shake, a stain under the body, `$1` in your colour rising 30 units in 0.9 s, the
  wallet +1, kills +1.
- A shotgun kill: everything off (head, both arms, both legs), bigger sprays, a pool spreading under the torso, 16
  shake, 6-step freeze.
- A brute: BOOM sparks (36 orange), shards, `$5`.
- Bodies fade from ~3.2 s and are gone at 7 s; stains last 45 s (fading the last 3 s); at most 140.
- Slot (lobby): stand still at it with $5+: rooted 1.6 s, reels land two decoys, then three of a kind, the banner,
  8 s recharge bar; BUST drops a brute 90 away; JACKPOT throws 18 notes in a ring that can't be picked up for 0.85 s.
- Magnet: a gold ring of radius 230 breathing; notes within 460 fly to you; each kill also throws one note only you
  can take.
- Vending (run): $2500, stand still 0.8 s (the green bar fills), `-$2500`, NUKE LAUNCHER!, SOLD OUT until the next
  wave.
- The secret: shoot the janitor once as he leaves after fixing the machine; on his next swing: suction cinematic
  (6.1 s), the room for 20 s (notes every 0.23 s, stamps you shoot or dodge), payout, back by the slot with what you
  collected (+$10 each if you lived), GARY KEEPS THE CHANGE.
- Compare with `godot/reference/wave.png` (HUD) and `lobby_topdown.png` (the slot with its sign and `$2500`).

---------------------------------------------------------------------------------------------------------------

## 24. HTML function index

| what | where |
|---|---|
| `T` (tuning), `RANGES` | L255-479, L481 |
| `ARENA`, `P_COLOURS` | L615, L616 |
| `PRIZES`, `SYM_COUNT` | L624-633, L634 |
| `ETYPE` (coins, r, mass, colour), `eRad`, `eMaxHp` | L667-673, L675, L676 |
| `newPlayer` (coins, kills, spin, speed, magnet, buy) | L711-729 |
| `fillLobby` (lobby cash) | L733-749 |
| `vendHere`, `vendPos` | L756, L757-760 |
| `lobbySolidBoxes` (the slot isn't solid) | L3431 |
| first person: slot/vend cut-outs, floating words (b308) | L4048-4053, L4069-4079 |
| `splash` (dive: DIVE fx, shake 8, SPLASH!) | L5676-5681 |
| `buildWorld`, `newWorld`, `rnd`, `addPlayer` | L6029-6053, L6023, L6060, L6065 |
| `FX`, `FX_LOOK` | L6072, L6073-6075 |
| `fx`, `burst`, `burstShrapnel` | L6238, L6246, L6257 |
| `pickPrize`, `award` | L6270, L6278-6327 |
| `spray` | L6331-6335 |
| `GORE_LABELS`/`GORE_CUTS`, `goreLabels`, `goreCut`, `goreBodyImage`, `gorePart` | L6346, L6347-6399, L6400-6423, L6424, L6425 |
| `GORE_FX`, `goreClock`, `makeCorpse` | L6428, L6429-6445 |
| `killBurst`, `splat` | L6447-6474, L6476-6482 |
| `payKill`, `dropCoins` (unused) | L6486-6513, L6515-6524 |
| `startWave` (restock) | L6575-6591 |
| `banner`, `giveWeapon` | L6876, L6878-6887 |
| `potatoSplat` (SPLAT!, shake 5), `punchLand` (kill path, shake 3) | L6972-7006, L7010-7046 |
| `detonate` (rocket kills, dummies) | L7080-7145 |
| `stepBase`: freeze, timers, pulling, buying, starting a pull | L7162, L7221-7226, L7228-7240, L7253-7273, L7275-7287 |
| `stepBase`: wall bounce shake, speed cap | L7340-7344, L7511 |
| `stepBase`: bullet hits/kills, dummies ($3) | L7745-7769, L7774-7790 |
| `stepBase`: shrapnel kills, janitor notes and pocketing, MACHINE IS LIVE | L7838-7854, L7964-7989 |
| `stepBase`: nuke kills, shake decay, husk kills | L8000-8036, L8038, L8076-8084 |
| `stepBase`: slot position and flash, floaters, corpses, blood, splats, slot cool, coins, sparks | L8194-8197, L8199-8203, L8205-8230, L8232-8239, L8240, L8242-8285, L8287-8295 |
| `snapshot`, `worldFromSnapshot` | L8300-8399, L8403-8497 |
| `camFollow` (1x in the bonus room) | L8521-8535 |
| debug J (break the slot, send the janitor) | L8638-8645 |
| `EIMG`, `cycleIndex`, `enemyFrame` | L9303, L9317, L9321 |
| `BLOOD_SPRITES`/`BLOOD`, `VEND_SPRITES`/`VEND_IMG`, `SLOT_SPRITES`/`SLOT_IMG` | L9374-9378, L9435-9437, L9446-9448 |
| snapshot sends | L11104-11107 |
| `playEvents`, `stepBits` (guest) | L11125-11138, L11140-11149 |
| `SND`, `audioInit`, `sNoise`, `sTone`, `vary` | L11156, L11194, L11213, L11228, L11242 |
| `SFX` (hit, kill, cash), `playEventSounds` | L11310-11353 (L11322, L11326, L11341), L11371-11382 |
| `renderBase`: shake, splats, corpses and pools, flecks, sign on the floor | L11528-11533, L11569-11581, L11583-11628, L11629-11635, L11638 |
| `renderBase`: sparks, `drawSym`, `drawSign` | L11802-11808, L11863-11906, L11967-11988 |
| `renderBase`: vending machine, slot machine and reels, prompt, notes | L12012-12050, L12052-12154, L12140-12153, L12156-12199 |
| `renderBase`: spin ring, magnet ring, speed ring, blood sprays | L12347-12354, L12404-12413, L12414-12418, L12420-12438 |
| `renderBase`: HUD line and kills, wallet, floaters, banner, game over | L12458-12464, L12466-12479, L12625-12637, L12665-12675, L12677-12695 |
| `advanceSimulation`, `frame` (guest events, host event sounds, snapshot measuring) | L12705, L12720 (L12731-12735, L12805, L12807-12811) |
| `restartGame`, `startGame` (run resets) | L13541, L13549-13607 |
| `giveTestMagnet` | L13641-13658 |
| `MACHINE_ART`, `COG_ART`, `BONUS_BOUNDS`, `secretActive`, `secretPacket` | L13792, L13794, L13796, L13797, L13798 |
| `beginSlotSecret`, `enterMachine`, `finishMachine`, `restoreFromMachine`, `step` | L13805, L13819, L13835, L13841, L13860-13923 |
| `secretText`, `drawMachineFloor`, `secretSprite`, `drawSecretGary`, `secretAudio`, `drawSuction`, `drawBonusHazards`, `render` | L13924, L13928, L13951, L13963, L13973, L13986, L14034, L14050-14097 |
| preview-secret button | L14098-14110 |
