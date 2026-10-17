# Spec: enemies and waves (the arena run)

Porting spec for the wave arena of `Smashed.html` (build b331): enemy types, spawning, the wave director,
chasing, separation, the batter's wind-up and swing, contact damage, player health, iframes, death, game
over and restart, the walk rigs, the enemy sprites, the arena itself (what the lobby turns into when a run
starts), brute shrapnel, and the janitor ("Gary") with all his phases.

Line numbers (`L1234`) are in `Smashed.html` at b331. All positions, speeds and sizes are **HTML units**
(1 unit = 0.025 m, `GameData.UNIT`); `(x, y)` is the ground (x east, y south / down the screen), `z` is height.
"T.name" means the tuning table `T` (`L255-479`, also in `data/game_data.json` under `"T"`). Times are seconds.

Things this system touches but does not own (they have, or will have, their own specs): weapons and bullets,
gore/corpses/blood (`makeCorpse`, `killBurst`, `splat`), coins and payouts (`payKill`), the slot machine and its
secret bonus room, the vending machine, Protect Gothica mode, potatoes. Where those call into, or are called by,
this system, the hook is described here.

---------------------------------------------------------------------------------------------------------------

## 1. Constants and tuning

### 1.1 The arena

`ARENA = { w: 860, h: 520, wall: 18 }` (`L615`). The run is played inside this rectangle and nowhere else.
- Player limits: `x ∈ [wall + T.radius, w − wall − T.radius] = [32, 828]`, `y ∈ [32, 488]` (`L7520-7524`).
- Enemy limits: `wall + eRad(e)` from each side (`L7656-7660`).
- Shrapnel dies outside `[wall, w − wall] × [wall, h − wall]` (`L7811-7813`).
- There are **no solids** in the run: the slot machine and the vending machine are walk-through for everyone
  (`lobbySolids` returns at once when `w.started`, `L5773`).

### 1.2 T values used by this system (b331)

| T key | value | meaning |
|---|---|---|
| `enemyScale` | 3.4 | enemy sprite height = radius × this |
| `enemyStride` | 10 | units travelled per animation frame (rigs: cycle length scales with `max(0.4, enemyStride/10)`) |
| `enemyBob` | 2 | units of bounce on passing frames |
| `enemyLean` | 7 | degrees of tilt at full sideways speed |
| `enemySpeed` | 40 | base speed (b175: halved from 80; old saved sliders are ignored, `L6798`) |
| `enemyHp` | 3 | grunt hp ("one grunt hp" = 3) |
| `enemyRadius` | 15 | grunt radius |
| `stagger` | 0.13 | stun after a hit |
| `staggerMass` | 1 | 1 = stun divided by mass |
| `knockback` | 170 | hit shove |
| `contactDmg` | 1 | × the type's `dmg` |
| `contactPush` | 320 | shove on the player when touched |
| `playerHp` | 5 | |
| `overheal` | 6 | max hp is `playerHp + overheal` = 11 (slot machine health prize) |
| `iframes` | 0.9 | invulnerable after any hurt |
| `radius` | 14 | player radius |
| `rollInvuln` | 0.30 | roll iframes |
| `spriteScale` | 4.6 | player (and janitor) sprite height = 14 × this = 64.4 |
| `hpHeight` | 1.05 | hp pips height above his feet, × sprite height |
| `shrapCount` | 8 | |
| `shrapSpeed` | 270 | |
| `shrapLife` | 1.1 | |
| `shrapDmg` | 1 | |
| `shrapFriendly` | 1 | shrapnel also hurts non-brute enemies |
| `swarmWave` | 3 | first wave with swarmers |
| `bruteWave` | 5 | first wave with brutes |
| `baseEnemy` | 3 | the filler type: 0 grunt, 3 batter (slider only allows 0 or 3) |
| `batWave` | 4 | first wave with *extra* batters (ignored while the batter is the filler) |
| `batRange` | 60 | batter starts his wind-up this close |
| `batWindup` | 0.38 | wind-up (the tell) |
| `batReach` | 46 | bat reach from his centre |
| `batRecover` | 0.55 | standing open after a swing |
| `waveBase` | 6 | enemies in wave 1 |
| `waveGrowth` | 3 | extra per wave |
| `waveSpeedUp` | 6 | % faster per wave |
| `spawnGap` | 0.45 | between spawns |
| `intermission` | 2.2 | breather between waves |
| `killShake`, `killShakeBig` | 5, 3.2 | screen shake on a kill |
| `janitorWave` | 1 | janitor turns up in the breather after this wave |
| `janitorSpeed` | 105 | his amble |
| `janitorScale` | 0.9 | |
| `janitorHits` | 3 | hammer blows on the cabinet |
| `janitorPay` | 3 | notes that fall out |
| `janitorRage` | 340 | chase speed |
| `gripeTime` | 3.4 | |
| `chaseGiveUp` | 8 | |
| `whackForce` | 980 | |
| `launchTime` | 1.1 | |
| `launchDrag` | 0.25 | speed kept per second while launched |
| `playerBounce` | 0.55 | speed kept bouncing off a wall while launched |
| `janitorLead` | 0.28 | seconds of lead when he aims at you |
| `testCash` | 2500 | cash at run start (testing value; 0 for release) |
| `slotDrop` | 38 | slot machine y = wall + 54 + slotDrop = 110 |

### 1.3 ETYPE (`L665-676`, also `game_data.json` "ETYPE")

Index `t` is stored on each enemy. Multipliers apply to the T values above.

| t | key | speed | hp | r | dmg | mass | colour | coins | melee | radius | max hp `eMaxHp` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | grunt | 1.00 | 1.00 | 1.00 | 1 | 1.0 | `#6fd3a0` | 1 | – | 15 | 3 |
| 1 | swarmer | 1.85 | 0.34 | 0.60 | 1 | 0.45 | `#e8c34f` | 1 | – | 9 | 1 |
| 2 | brute | 0.52 | 2.80 | 1.60 | 2 | 2.8 | `#b06bd8` | 5 | – | 24 | 8 |
| 3 | batter | 1.10 | 1.35 | 1.00 | 2 | 1.1 | `#d94a4a` | 3 | yes | 15 | 4 |

All four have `facesRight: true` (their side/diag art faces right).
- `eRad(e) = T.enemyRadius × ETYPE[e.t].r` (`L675`).
- `eMaxHp(t) = max(1, round(T.enemyHp × ETYPE[t].hp))` (`L676`).
- Design note in the source: "the grunt is the baseline, the swarmer punishes standing still, the brute punishes
  ignoring it"; "the batter doesn't hurt on touch — only the swing does, and it's telegraphed".
- **With b331 tuning (`baseEnemy` 3) grunts never appear in waves**: the batter is the filler. Grunts only come
  back if `baseEnemy` is set to 0. Keep grunt fully working anyway.
- `BAT = { CHASE: 0, WINDUP: 1, SWING: 2, RECOVER: 3 }` (`L674`), the batter's state in `e.st`.

### 1.4 The random numbers

`rnd(w)` (`L6060`): an LCG on `w.seed` (starts at 1 in `buildWorld`):
`seed = (seed × 1664525 + 1013904223) mod 2^32; return seed / 2^32`. Every game-affecting random number in the
sim uses it (spawn sides, wave shuffle, shrapnel rotation, particle bursts, corpses, coins...). GDScript 64-bit ints
reproduce it exactly. Exact sequences only match the HTML if every `rnd` call in the whole sim is ported in the same
order, which isn't required; the point is that the sim is deterministic and host-owned.

---------------------------------------------------------------------------------------------------------------

## 2. State

### 2.1 World fields (`buildWorld`, `L6029-6053`)

| field | start (new world / lobby) | meaning |
|---|---|---|
| `started` | false | lobby until Start |
| `over` | false | game over: the sim stops |
| `wave` | 0 | current wave number (0 before the first) |
| `pending` | 0 | enemies still to spawn this wave |
| `queue` | [] | ETYPE indices still to spawn, in order |
| `spawnTimer` | 0 | countdown to the next spawn |
| `breather` | 1.2 (set to `T.intermission` = 2.2 by `startGame`) | > 0 = between waves |
| `enemies` | [] | |
| `ebullets` | [] | shrapnel |
| `janitor` | `{phase:'idle', t:0, x:0, y:0, vx:0, flip:0, hits:0, flinch:0, from:0, shots:0, target:-1, resume:'enter', spent:0}` | plus later `paid`, `took`, `odo`, `wdx`, `wdy`, `secretReturn` |
| `sign` | 'stand' | the OUT OF ORDER sign: 'stand' (taped to the cabinet), 'floor' (thrown down), 'gone' |
| `slot.broken` | false in the lobby, true at run start | the cabinet the janitor fixes |
| `freeze` | 0 | hit-stop: while > 0 the whole sim step is skipped |
| `shake` | 0 | screen shake amount, decays 90/s |
| `events` | [] | `[kind, x, y]` effect events, max 40, for sound and for the network guest |
| `seed` | 1 | RNG |
| `mode` / `goth` / `gothDown` | – / null / false | Protect Gothica (set by `startGame`) |

### 2.2 An enemy (`spawnEnemy`, `L6555-6569`)

```
{ x, y, vx: 0, vy: 0, t, hp: eMaxHp(t), flash: 0, spawn: 0.35,
  st: 0, stT: 0, sdx: 0, sdy: 1, odo: 0 }       // plus, when first used: stun, hit
```
- `spawn` > 0: materialising. It doesn't move, can't be hit, doesn't hurt, isn't counted as a threat by Gothica.
- `flash`: white hit flash timer (set to 0.08 on a hit; 0.1 from a rocket blast).
- `stun`: stagger timer (see 4.3; it is `undefined` → treated as 0).
- `st`, `stT`: batter state and its timer. `sdx, sdy`: the batter's locked swing direction. `hit`: swing landed.
- `odo`: distance walked (drives the walk animation).
- The slot machine's "bust" prize adds a brute directly (`L6319-6325`): at 90 units from the player in a random
  direction, `t: 2`, `spawn: 0.6`, `stun: 0`. It can happen in the lobby too (the lobby machine isn't broken), giving a
  single brute in the lounge with no wave director. If it kills you there, it's game over in the lobby.

### 2.3 Player fields this system uses (`newPlayer`, `L711-731`)

| field | start | meaning |
|---|---|---|
| `hp` | `T.playerHp` (5) | integer in practice (damage is 1 or 2); may be up to 11 with overheal |
| `alive` | true | |
| `iframe` | 0 | invulnerable and blinking while > 0 |
| `grace` | 0 | invulnerable, **no blink** (1.0 at each wave start) |
| `launch` | 0 | thrown (janitor whack, rocket blast): no control while > 0 |
| `roll`, `rollCd` | 0 | the dive roll |
| `vx, vy` | 0 | velocity; pushes are added to it |
| `kills` | 0 | shown on the HUD and the game-over line |
| `coins` | 0 (lobby: `max(lobbyCash 40, testCash 2500)`) | |

### 2.4 Shrapnel (`ebullets`)

`{ x, y, vx, vy, life }` (`L6263-6265`).

---------------------------------------------------------------------------------------------------------------

## 3. The run: start, the arena, game over, restart

### 3.1 Starting a run — `startGame()` (`L13549-13607`)

Triggered by Enter (`L8651`, only when `!world.started` and not a key repeat), the Start buttons (`startBtn`,
`fsStart`, disabled while started or for the network guest, `L13608-13620`), a gamepad Menu button, and (when the
title poster is showing) a tap near the bottom message (`L8722`). Refused when: the secret bonus room is active,
already started, the player is the network guest (the host owns the world), or gun calibration is on.

In order:
1. `started = true`, `mode = gameMode` ('classic' or 'protect'), `goth = protect ? newGoth(world) : null`,
   `gothDown = false`, `breather = T.intermission` (2.2), `dummies = []`, `cans = []`.
2. Each player: any gym plate goes back on the rack (`rackPlate`), `lift = leg = null`.
3. Each player: `food = 0` (no snags in the run, b330); off the trampoline (`tramp = 0, air = null, tz = 0, tv = 0`,
   and `dz = 0` unless diving, b326); **if in the yard** (`inYard(p)`, b322) he's put at the back door:
   `x = BACK_DOOR.x (645)`, `y = ARENA.h − wall − radius − 6 = 482`, velocity 0.
   Then: `coins = T.testCash`, `rockets = 0, dump = 0, buy = 0`, `hp = T.playerHp`, `weapon = 'spud'`,
   `blasters = 0`, `ammo = max(ammo, spudPellets × spudStart)` (potatoes gathered in the lobby come with you),
   `reload = 0, wTime = 0, speed = 0, magnet = 0, roll = 0, rollCd = 0`.
   If on the dive tower or in the pool: out of the pool (`y = POOL.y1 + radius`) or to the tower foot
   (`y = towerGeo().baseY`), `dive = dz = vz = vx = vy = 0`.
4. World: coins cleared, plants cleared, `plantTimer = 1.5`, three plants pre-grown (`plantSpud(world, 0.3 / 0.6 /
   0.9)`), corpses, blood and splats cleared, `slot.cool = 0`, `slot.busy = −1`, **`slot.broken = true`**,
   **`sign = 'stand'`**, janitor reset: `phase 'idle', hits 0, paid 0, took 0, shots 0, spent 0, target −1,
   resume 'enter', t 0, flinch 0`.
5. Not reset: `wave` is still 0, `seed` carries on, player positions (except the yard/pool cases) stay where they
   were. A player standing in the **bedroom** (y > 520) is snapped by the arena clamp on the next step to y = 488.

### 3.2 What the lobby becomes

`lobbyTall(w) = !w.started && T.loungeFloor && !cal.on && !secretActive(w)` (`L1977`). Once started it is false,
and everything keyed on it switches to the plain arena:
- The world is just the 860 × 520 rectangle: `worldW/worldH` = 860/520 (`L2121-2122`); the yard, the bedroom, the
  doors and their art are gone (`drawLowerLobby` returns), and movement is the plain rectangle clamp (no
  `lobbyClamp`, no solids).
- The floor: no lounge picture (`loungeOn` is false, `L11539`). Plain fill `#1b1e26`, a grid of 1-px lines
  `#232733` every 40 units from `wall` to `w − wall` / `h − wall` (`L11548-11556`), the four walls filled `#2b3040`
  18 wide (`L11558-11562`).
- Lobby props vanish: dive tower, gym bench/rack/leg press, wardrobe, mirror, the arcade cabinets (they are only
  drawn when `towerOn = !w.started && ...`, `L12219`), the pool and ducks, the target dummies, the cans, the
  barbecue, lobby Gothica (in Protect mode she becomes the run's `w.goth`).
- The slot machine moves to the middle of the top wall: `slot.x = ARENA.w × 0.5 = 430` (lobby: `T.loungeSlotX` 90),
  `slot.y = wall + 54 + T.slotDrop = 110` (set every step, `L8194-8195`). It is broken, with the sign taped on.
- The vending machine appears (`vendHere` = only in a run): `(ARENA.w × T.vendX, wall + 54 + T.vendDrop) =
  (705.2, 154)`.
- Potato plants start growing wild (only while started).
- First person ends (`drawShroom` calls `endShroom` when `w.started`, `L4271`; `fpCan` needs `!started`).
- Zoom: the lobby-only 2× zoom drops to 1.5× (`zoomWanted`).
- Screenshot of a run: `godot/reference/wave.png` (game over over wave 1: the dark grid floor, the broken slot
  machine with its sign, the vending machine top right, batters, plants).

### 3.3 Game over

`w.over` is set when (classic mode) **every** player is dead (`L7597, 7683, 7833`: checked after each death; not
in Protect mode, where it's set only when Gothica's hp reaches 0, `protHurt`, `L12946`).
- The sim stops completely: `advanceSimulation` only calls `step` while `!world.over` (`L12710, 12798`). Nothing
  moves, particles freeze, timers stop. Rendering continues.
- Edge case: `shake` decays inside the step, so a shake in progress at the moment of death never decays (the screen
  keeps jittering). Recommended fix in Godot: let shake decay even when over (or zero it).
- Overlay (`L12677-12695`), drawn over everything, in screen space: fill whole screen `rgba(20,22,28,0.78)`;
  centred at (430, 238) bold 40 px `#e0473f` **"DOWN"** (Protect: "GOTHICA'S DOWN"); at (430, 268) 16 px
  `#cfd4de` **"made it to wave N — K killed"** (`N = w.wave`, `K` = sum of players' `kills`; Protect: "you kept
  her safe to wave N — best: wave B"); at (430, 294) 13 px `#8b93a4` "press R, or tap here to restart".

### 3.4 Restart — `restartGame()` (`L13541-13548`)

R (any time: in the lobby, mid-run or over, `L8631`), the full-screen Restart button (`L13621`), or a tap/click
within `|x − 430| < 220, |y − 260| < 60` while over (`L8708-8713`). Refused for the network guest.
`world = newWorld()` (a fresh lobby: `buildWorld` + `fillLobby`, every player new from `newPlayer` with hp 5 at
`(380, 260)` / `(480, 260)`, lobby cash, blasters), and player 2 is re-added if there were two. `accumulator = 0`.
So a restart always lands back in the lobby, never straight into a new run.

### 3.5 The step order (`stepBase`, `L7160` onwards; driven by `step`, `L13860`)

Fixed step `FIXED_DT = 1/120` with an accumulator (frame time clamped to 0.1, `L12701-12715`). Per step:
1. **Hit-stop**: `if (w.freeze > 0) { w.freeze -= dt; return; }` — the whole world, players included, holds.
2. `w.t += dt`.
3. **Players** (`L7168-7526`): per player, `iframe` and `muzzle` count down and `cooldown` (even when dead); then
   `if (!p.alive) continue`; `roll`, `rollCd`, `grace` count down; weapon timers; slot spin; vending; roll start
   (sets `iframe = max(iframe, T.rollInvuln)`, `L7316`); launched movement (`L7321-7347`); roll movement; normal
   movement; firing; speed cap; integrate; arena clamp.
4. **Wave director** (`L7527-7541`).
5. **Enemies** (`L7546-7634`): timers, target, stun, batter state machine, chase steering, integrate.
6. **Separation** (`L7636-7655`), then **enemy clamp** (`L7656-7660`).
7. **Contact damage** (`L7660-7686`).
8. **Bullets** (`L7688-7806`): the janitor first, then enemies, then lobby props and walls.
9. **Shrapnel** (`L7808-7857`).
10. **Janitor** (`L7859-7998`) — skipped while the secret bonus room is active.
11. Nuke, rockets, shake decay (`shake −= 90·dt`), plants, Gothica (`stepGoth`, including her contact damage),
    potato rain, gym, blackjack, thrown potatoes (they hit enemies), punches landing, lobby dummies/cans, slot
    machine position, floaters, corpses, blood, splats, coins, particles.

`step()` (`L13860`) runs `stepBase` normally; while the slot machine's secret is active the wave director and the
janitor are paused (the bonus room has its own hazards), see 9.6.

---------------------------------------------------------------------------------------------------------------

## 4. Waves and enemies

### 4.1 The wave director (`L7527-7541`)

Runs only when `!w.over && w.started && !secretActive(w)`:
```
if breather > 0:
    breather -= dt
    if breather <= 0: startWave(w)
elif pending > 0:
    spawnTimer -= dt
    if spawnTimer <= 0:
        spawnEnemy(w, queue.shift()); pending -= 1; spawnTimer = T.spawnGap
elif enemies.length == 0:
    breather = T.intermission
```
So: 2.2 s after Start, wave 1 begins; the first enemy spawns on the very next step (`spawnTimer = 0`), then one
every 0.45 s; the wave ends when everything spawned is dead; then a 2.2 s breather (longer if the janitor is
working, 9.3). "Left" on the HUD counts only `enemies.length` (spawned and alive), not the queue.

### 4.2 `startWave(w)` (`L6575-6592`)

```
wave += 1; vendSold = false
queue = waveMix(w, wave); pending = queue.length; spawnTimer = 0
for each player:
    if !alive: alive = true; x = 430; y = 260; vx = vy = 0; roll = 0; rollCd = 0   # died mid-roll: don't slide out
    hp = max(hp, T.playerHp)       # top up, keep any overheal
    grace = 1.0                    # wave-start protection: invulnerable, no blink
```
(Comment: "everyone comes back for a new wave — no permanent benching".) Both dead players reappear on the same
spot (430, 260).

### 4.3 Wave size, mix and speed (`L6526-6553`)

```
waveSize(n)      = T.waveBase + (n − 1) × T.waveGrowth                         # 6, 9, 12, 15...
waveEnemySpeed(n)= T.enemySpeed × (1 + (n − 1) × T.waveSpeedUp / 100)          # 40, 42.4, 44.8...

waveMix(w, n):
  total    = waveSize(n)
  brutes   = n >= bruteWave ? floor((n − bruteWave) / 2) + 1 : 0
  swarmers = n >= swarmWave ? (n − swarmWave + 1) × 2 : 0
  base     = (baseEnemy == 3) ? 3 : 0
  batters  = (base != 3 && n >= batWave) ? floor((n − batWave) / 2) + 1 : 0
  brutes   = min(brutes,  floor(total / 4))
  batters  = min(batters, floor(total / 4))
  swarmers = min(swarmers, floor(total / 2))
  fillers  = max(0, total − brutes − swarmers − batters)
  q = [base]×fillers + [1]×swarmers + [2]×brutes + [3]×batters
  Fisher-Yates shuffle with rnd: for i = len−1 down to 1: j = floor(rnd × (i+1)); swap q[i], q[j]
```
(Comment: "swarmers arrive first to change the pace, brutes later to force you to commit fire somewhere".)

With b331 tuning (filler = batter). "Top speed" = `2.2 × speed × type speed` (4.4):

| wave | total | batters | swarmers | brutes | `waveEnemySpeed` | batter / swarmer / brute top speed |
|---|---|---|---|---|---|---|
| 1 | 6 | 6 | 0 | 0 | 40.0 | 96.8 / 162.8 / 45.8 |
| 2 | 9 | 9 | 0 | 0 | 42.4 | 102.6 / 172.6 / 48.5 |
| 3 | 12 | 10 | 2 | 0 | 44.8 | 108.4 / 182.3 / 51.3 |
| 4 | 15 | 11 | 4 | 0 | 47.2 | 114.2 / 192.1 / 54.0 |
| 5 | 18 | 11 | 6 | 1 | 49.6 | 120.0 / 201.9 / 56.7 |
| 6 | 21 | 12 | 8 | 1 | 52.0 | |
| 7 | 24 | 12 | 10 | 2 | 54.4 | |
| 8 | 27 | 13 | 12 | 2 | 56.8 | |
| 10 | 33 | 14 | 16 | 3 | 61.6 | |
| 12 | 39 | 16 | 19 (capped) | 4 | 66.4 | |
| 15 | 48 | 18 | 24 | 6 | 73.6 | |

`game_data.json` → `calls.waveSizes` (`[n, size, speed]`) and `calls.waveMix` (one shuffled sample) confirm these.
The speed is recomputed every step from `w.wave` (`L7544`), so it applies to every enemy alive, including a bust
brute in wave 0 (`40 × 0.94 = 37.6`).

### 4.4 Spawning — `spawnEnemy(w, type)` (`L6555-6569`)

```
t = type || 0
m = ARENA.wall + T.enemyRadius × ETYPE[t].r + 2           # grunt/batter 35, swarmer 29, brute 44
repeat (up to 12 tries, stop as soon as not within 150 of a living player):
    side = floor(rnd × 4)
    0: x = m + rnd × (860 − 2m), y = m          (top)
    1: x = 860 − m, y = m + rnd × (520 − 2m)    (right)
    2: x = m + rnd × (860 − 2m), y = 520 − m    (bottom)
    3: x = m, y = m + rnd × (520 − 2m)          (left)
push enemy (2.2) with spawn = 0.35
```
`nearAnyPlayer(w, x, y, 150)`: any living player closer than 150. After 12 tries it spawns wherever the last try
landed, even next to you.

### 4.5 Each enemy, each step (`L7546-7634`)

```
flash = max(0, flash − dt); spawn = max(0, spawn − dt)
if spawn > 0: continue                                   # (stun is not counted down while spawning)
target = nearest living player (by distance); best = that distance
if Protect mode: [target, best] = protTarget(...)       # Gothica instead, if she's nearer and on the ground (b294)
stun = max(0, stun − dt)
espeed = waveEnemySpeed(wave) × ETYPE[t].speed × (stun > 0 ? 0 : 1)
if batter: (4.6) — may `continue`
if target:
    d = |target − e| or 1
    v += (target − e)/d × espeed × 6 × dt                # steer
sp = |v|; if sp > 0: v −= v/sp × min(sp, espeed × 5 × dt)   # friction
cap = espeed × 2.2; if |v| > cap: v = v/|v| × cap
x += vx·dt; y += vy·dt; odo += |v|·dt
```
Feel: net acceleration straight at you is `espeed × 1` per second (6 forward minus 5 friction), so an enemy takes
2.2 s to reach top speed `2.2 × espeed`; turning is sluggish (the friction fights the old velocity), so enemies
overshoot and curve. With no living target they coast to a stop.

**Stagger quirk (keep it):** while `stun > 0`, `espeed = 0`, so `cap = 0` and the velocity is set to zero on that
step. A hit's knockback impulse is therefore wiped on the next step; a stunned chaser simply *stops dead* for the
stun time. Knockback only really moves planted batters (wind-up/swing/recover). Contact pushes (no stun) and
separation do move enemies. This is how the game feels now ("fire visibly holds him"), so port it as is.

Stun sources: bullet hit `max(stun, T.stagger / mass)` (grunt 0.13, swarmer 0.29, brute 0.046, batter 0.118);
punch `stagger × 1.5 / mass`; thrown potato and potato splat `T.stagger`; rocket blast survivor 0.6; a corpse
falling into it (`killBurst`, within 46) `stagger × 0.6`; leaving the bonus room 1.5.

### 4.6 The batter: wind-up and swing (`L7563-7621`)

```
stT = max(0, stT − dt)
if st == CHASE and stun <= 0 and target and best < T.batRange (60):
    st = WINDUP; stT = T.batWindup (0.38)
    sdx, sdy = (target − e)/best             # aim locked at the tell
if st != CHASE:
    v *= 0.001^dt                            # planted: bleed off momentum, no steering
    x += vx·dt; y += vy·dt                   # (odo does not advance)
    if st == WINDUP and stT <= 0: st = SWING; stT = 0.16; hit = false
    if st == SWING and !hit and stT <= 0.08:            # the bat is horizontal: the moment
        hit = true
        for each player (alive, iframe <= 0, grace <= 0):
            d = |p − e|; if d > T.batReach + T.radius (60): skip
            if ((p − e)·(sdx, sdy)) / d < 0.25: skip    # behind him (outside ~±75.5°) = safe
            hurt: hp −= T.contactDmg × 2 = 2; iframe = T.iframes
                  p.v += (sdx, sdy) × T.contactPush × 1.4 (448); fx HURT at p
                  if hp <= 0: death (5.4)
        Protect: Gothica in reach (d <= batReach + 12 = 58) and in the arc → protHurt(2, sdx, sdy)
        v += (sdx, sdy) × espeed × 1.6        # a little lunge (zero if he's stunned)
    elif st == SWING and stT <= 0: st = RECOVER; stT = T.batRecover (0.55)
    elif st == RECOVER and stT <= 0: st = CHASE
    continue                                  # skips the chase steering
```
- Timeline from the tell: 0.38 wind-up, then the hit lands 0.08 s into the 0.16 s swing (0.46 s after the tell),
  then 0.08 s more swing, then 0.55 s recovery: 1.09 s committed, then he chases again.
- Being shot during wind-up does **not** cancel it (stun only stops a wind-up from starting).
- He never deals contact damage (`melee: true`): he only hurts with the swing.
- `sdy` is not sent over the network (only `sdx`, for the pose flip).
- The death branch of the swing doesn't free the slot machine (`slot.busy`) the way the contact and shrapnel deaths
  do (5.4). A player mid-spin can be batted to death, leaving the machine claimed; release it in Godot.

### 4.7 Separation (`L7636-7655`)

Every pair (including enemies still spawning), O(n²):
```
want = eRad(a) + eRad(b); d = |b − a|
if 0 < d < want:
    push = want − d; n = (b − a)/d
    a −= n × push × mb/(ma+mb);  b += n × push × ma/(ma+mb)     # heavier shoves lighter
```
Position-only (no velocity change). Then each enemy is clamped into the arena (1.1). Enemies don't collide with
players, the janitor, Gothica or props; they can stand on the player (contact damage handles that).

### 4.8 Contact damage (`L7660-7686`)

For each enemy not spawning and not melee, each player alive with `iframe <= 0 && grace <= 0`:
```
d = |p − e|; if d > eRad(e) + T.radius: skip
hp −= T.contactDmg × ETYPE.dmg        # 1, or 2 for a brute
iframe = T.iframes (0.9)
n = (p − e)/d
p.v += n × T.contactPush (320)
e.v −= n × T.contactPush × 0.6 / mass  # the enemy bounces off
fx HURT at p
if hp <= 0: death (5.4)
```
Protect mode: `stepGoth` (`L13044-13054`) does the same against Gothica (reach `eRad + 12`, damage through
`protHurt`, which has its own `PROT.hurtFor` 0.9 invulnerability).

### 4.9 Taking damage and dying (enemies)

Hit by a bullet (`L7732-7771`): swept test, segment old→new bullet position against a circle of radius
`eRad(e) + T.bulletSize/2` (`segmentHit`, `L7147`); the nearest enemy along the segment is hit (spawning ones are
skipped); the bullet is moved to the impact point. Then:
```
hp −= b.dmg || 1                 # blaster 1, spud gun 1.5 (enemyHp × dmgFrac), shotgun pellets 1 each
flash = 0.08
stun = max(stun, T.stagger / (staggerMass ? mass : 1))
v += bulletDir × T.knockback × (b.kb || 1) / mass     # brutes barely flinch (wiped next step anyway, 4.5)
fx HIT at bullet; blood spray (big if kb > 1.5: the shotgun)
```
Kill sequence (the same everywhere an enemy dies; `L7754-7768`):
```
big = shotgun (kb > 1.5), or rockets / nuke (always big)
if brute: burstShrapnel(x, y)   else fx KILL at e
makeCorpse(e, dir, big)          # gore spec
shake = max(shake, T.killShake × (big ? T.killShakeBig : 1))
killBurst(e.x, e.y, dir, big)    # blood fan, shoves enemies within 46, hit-stop freeze = T.hitStop × (big ? hitStopBig : 1)
splat(e.x, e.y)                  # floor stain
payKill(x, y, t, owner)          # coins: straight to the killer's wallet (owner −1 = split between living players)
remove the enemy
owner.kills += 1                 # ONLY for bullet and rocket kills (punches, thrown potatoes, potato splats,
                                 # shrapnel and the nuke don't count; keep or fix, but know it)
```
All the places enemies take damage and can die: bullets (`L7732`), punches (`punchLand`, `L7010`), thrown and lobbed
potatoes (husks, `L8044-8095`), a full-power potato bursting (`potatoSplat`, `L6972`), rockets (`detonate`,
`L7080`), the nuke prize (`L8005-8040`: kills **every** enemy, spawning or not, big, owner −1), shrapnel (4.10).
`dropCoins` (`L6515`) exists but is never called (kills pay into the wallet, b-era change); don't port it.

### 4.10 Shrapnel (brute death)

`burstShrapnel(w, x, y)` (`L6256-6266`) — "the brute goes off like a grenade: evenly spaced pieces, slightly rotated
each time so you can't learn a safe angle":
```
fx BOOM at (x, y)
n = round(T.shrapCount) (8); if n <= 0: return
rot = rnd × 2π
for i in 0..n−1: a = rot + i/n × 2π; push { x, y, v: (cos a, sin a) × T.shrapSpeed (270), life: T.shrapLife (1.1) }
```
Each step (`L7808-7857`):
```
x += vx·dt; y += vy·dt; life −= dt
gone = life <= 0 or outside [18, 842] × [18, 502]
Protect: |Gothica − s| < 16 → protHurt(T.shrapDmg, dir); gone if it hurt her
players (alive, iframe <= 0, grace <= 0) within T.radius + 4 (18):
    hp −= T.shrapDmg (1); iframe = T.iframes; p.v += dir × T.contactPush × 0.8 (256); fx HURT
    if hp <= 0: death (frees slot.busy); gone (one victim per piece)
if T.shrapFriendly: enemies (not spawning, NOT brutes: "other brutes shrug it off") within eRad(e):
    hp −= 1; flash = 0.08; fx HIT at s       # no stun, no knockback
    if hp <= 0: fx KILL; corpse (dir = shrapnel v, not big); shake killShake; killBurst; splat;
                payKill(owner −1 = shared); remove (no kills++). gone
```
Range: 270 × 1.1 = 297 units. No chain reactions (brutes are immune, so a shrapnel kill never makes more).

---------------------------------------------------------------------------------------------------------------

## 5. Player health

### 5.1 Numbers

- `hp` starts at `T.playerHp` (5) in the lobby and at run start; topped up to at least 5 at every wave start
  (overheal kept); the slot machine's "+2 HEALTH" prize stacks to `playerHp + overheal` = 11.
- Damage: contact 1 (brute 2), batter swing 2, shrapnel 1. The janitor never damages (he launches).

### 5.2 Invulnerability

A player can be hurt only if `alive && iframe <= 0 && grace <= 0`.
- `iframe = T.iframes` (0.9) after every hurt (set, not maxed: the hurt only happens when it was 0 anyway).
- Roll: `iframe = max(iframe, T.rollInvuln)` (0.3) at roll start.
- Rocket blast yeet: `max(iframe, 0.6)`; nuke: `max(iframe, 0.5)`; janitor whack: `max(iframe, launchTime + 0.3)` = 1.4.
- `grace` = 1.0 at every wave start (2 after the bonus room, 1.5 on a Protect-mode respawn): invulnerable,
  **not drawn blinking**. `iframe` counts down even while dead; `grace` only while alive.

### 5.3 Being pushed and launched

Pushes add to `p.vx, p.vy`; the normal movement code's acceleration/friction (`T.accel` 2200, `T.friction` 1900,
cap `T.maxSpeed` 260 × boosts) bleeds them off. Over `maxSpeed` the speed is clamped each step (`L7512-7514`), so a
448 push is effectively capped at 260 at once — except while **launched** (`p.launch > 0`, `L7321-7347`): no
input, no cap, `v *= T.launchDrag^dt` (0.25 per second), integrate, bounce off the arena walls keeping
`T.playerBounce` (0.55) of the speed; a bounce faster than 120 shakes 14, fx WALL, and plays
`sNoise(0.14, 500, 1.1, 0.34, lowpass, 90)` + `sTone(0.12, 120, 46, 0.2, square)`. When launch ends, `v *= 0.3`.

### 5.4 Death

At every place `hp` can drop (`L7594-7598` swing, `L7679-7684` contact, `L7829-7834` shrapnel, bonus room hazards):
```
if hp <= 0:
    alive = false
    if slot.busy == p.id: slot.busy = −1; p.spin = 0      # (not in the swing branch)
    fx DOWN at p
    if !Protect && every player dead: w.over = true
```
A dead player: not drawn at all (`L12236`), no input, no collisions, not targeted, skipped by coins and plants.
Revived by the next `startWave` (classic) or by Protect mode after `PROT.respawn` (4 s) next to Gothica.

### 5.5 Drawing

- **Blink**: while `iframe > 0`, skip drawing him when `floor(iframe × 20) % 2 == 0` (10 Hz, 50 ms on/off,
  `L12259`). Grace never blinks.
- **HP pips** (`L12386-12397`), over his head (inside the dive/trampoline height offset):
  `shown = max(T.playerHp, ceil(hp))`; `chScale = CHARS[ch].scale × (NEW_ART char ? T.altScale : 1)`;
  `pipY = round(p.y + r × 0.9 − r × T.spriteScale × T.hpHeight × chScale)`; pip `i` is a 4×4 square at
  `x = round(p.x − shown × 3 + i × 6)`, colour: `i < hp` → (`i >= playerHp` ? gold `#f6d17a` : the player colour
  `P_COLOURS[id]` = P1 `#e0473f`, P2 `#4f9fe8`), else `rgba(255,255,255,0.15)`.
- **HUD** (`L12458-12464`), screen top-left at (26, 38), 12 px monospace `#6d7486`, only in a run:
  `"wave N   L left   K killed"` (N = `w.wave`, L = `enemies.length`, K = total kills). With `?debug` the build
  number comes first. Wallets under it (coins spec).

---------------------------------------------------------------------------------------------------------------

## 6. Drawing the enemies (`L11723-11800`)

Order in the HTML frame: splats, corpses, the floor sign, the hammer, **the janitor, the enemies**, particles,
husks, bullets, the slot machine and its sign, coins, **shrapnel**, the players (depth sorted), blood sprays, then
the HUD. (Enemies are always under the players in 2D; in 3D depth sorts it.)

Per enemy (`ty = ETYPE[e.t]`, `r = eRad`):

1. **Spawning** (`spawn > 0`): no sprite. A ring, stroke `ty.colour`, alpha 0.7, line 2, radius
   `r × (0.6 + spawn × 1.6)` around `(x, y)` — it shrinks onto him (from 1.16r to 0.6r over 0.35 s). Then `continue`.
2. **Batter wind-up** (`st == WINDUP`): a ring, `rgba(217,74,74,0.85)`, line 2, radius
   `T.batReach × (0.5 + left × 0.8)`, `left = clamp(stT / T.batWindup, 0, 1)` — "shrinking ring = time left to roll"
   (from 59.8 to 23).
3. Pose: `pose = enemyPose(e)` (6.1) and frame `enemyFrame(set, pose.img, odo, pose.frame)`.
4. **Shadow**: ellipse at `(x, y + 0.8r)`, radii `0.9r × 0.35r`, `rgba(0,0,0,0.3)`.
5. Size: `h = r × T.enemyScale × poseScale` — grunt 51, swarmer 30.6, brute 81.6, batter 51 (swing pose ×
   `401/325` = 62.9). Width = `h × imageAspect`.
6. Feet at `footY = y + 0.8r`. (2D-projection offset: in 3D put the feet at `(x, y)`.)
7. Flash: while `flash > 0` the sprite is drawn with CSS filter `brightness(2.6) saturate(0.2)` (nearly white).
8. Lean: `running = (st == 0)`; `top = T.enemySpeed × type.speed × 2.2` (base speed, not the wave speed);
   `lean = running ? clamp(vx / top, −1, 1) × 7° : 0`; if `stun > 0`: `lean += (vx >= 0 ? −1 : 1) × 0.14` rad
   ("rocked back by the hit"). The lean is a rotation about the feet, applied **only** when neither a rig nor the
   batter layout draws him (so in practice: idle poses of grunt/swarmer/brute, and the batter's swing pose). Since
   stunned enemies have `vx = 0`, the stun rock is −0.14 rad (tilt left on screen).
9. Flip: `scale(−1, 1)` about the feet when `pose.flip`.
10. Draw, first that applies:
    - a walk rig exists for this type and pose (`ENEMY_WALK_RIGS[key].views[pose]`: grunt, swarmer, brute in
      front/back/side/diag) → `drawOtherEnemyRig` (6.3);
    - batter in a `BATTER_WALK` pose (front/back/side/diag/idle) → `drawBatterRig` (6.4) for side/front/back;
      otherwise (idle, or art not loaded) the picture laid out by `batterWalkGeometry` (6.5);
    - otherwise the plain picture: `drawImage(img, round(−dw × anchor), round(−h + bob), dw, h)`, `anchor` =
      `ENEMY_ANCHOR[key][pose]` or 0.5 (batter swing: 0.401, `L9285`).
11. If the art isn't loaded: a filled circle of radius r in `ty.colour` (white while flashing).
12. **HP bar** when `maxHp > 1 && hp < maxHp`: at `(x − r, y + 0.8r − r × enemyScale − 5)`, `2r × 3`, background
    `rgba(20,22,28,0.75)`, fill `#f6d17a` for `2r × hp/max`.

### 6.1 Which pose — `enemyPose(e)` (`L9341-9369`)

Batter states first:
```
if st in (WINDUP, SWING, RECOVER):
    flip = sdx < −0.2
    dur  = WINDUP: T.batWindup | SWING: 0.16 | RECOVER: T.batRecover
    prog = 1 − clamp(stT / dur, 0, 1)
    base = WINDUP: 0 | SWING: 2 | RECOVER: 4
    return { img: 'swing', flip, frame: base + (prog < 0.5 ? 0 : 1) }     # swing_0..swing_5
```
(Frames: 0 bat on the shoulder, 1 bat raised overhead; 2 mid-swing, 3 follow-through low; 4, 5 hunched recovery.)

Then movement: `sp = |v|`; `sp < 12` → `{img:'idle', flip:false}`. Otherwise
`oct = round(atan2(vy, vx) / (π/4))`, wrapped to 0..7 (0 = east, 2 = south/toward the camera, y down),
`R = facesRight` (true for all):

| oct | direction | img | flip |
|---|---|---|---|
| 0 | E | side | !R (no) |
| 1 | SE | batter: side; others: diag | !R (no) |
| 2 | S (toward camera) | front | no |
| 3 | SW | batter: side; others: diag | R (yes) |
| 4 | W | side | R (yes) |
| 5 | NW | batter: side; others: back | yes |
| 6 | N (away) | back | no |
| 7 | NE | side | !R (no) |

Quirks to keep: there is no away-diagonal enemy art, so NE shows the side view and NW the back view mirrored.
The batter never uses his diag art ("Batter diagonal art repeats a split-legged contact pose: use the complete
eight-frame side cycle so the feet actually pass each other").

### 6.2 Frame helpers

- `cycleIndex(frames, odo) = floor(odo / (T.enemyStride × 4 / n)) % n` (`L9317`): a cycle covers 40 units.
- `enemyFrame(set, pose, odo, explicit)`: a single picture as is; an array → `frames[explicit]` (clamped) or
  `frames[cycleIndex]`.
- `enemyBob(set, pose, odo)` (`L9330`): arrays of 4+ frames only: the last frame of each half-cycle is the passing
  frame, `−T.enemyBob`; with 8 frames the one before it gets `−enemyBob × 0.5`. (With the current art only the
  batter has arrays, and his walk is rigged, so this is effectively unused.)

### 6.3 The walk rigs: grunt, swarmer, brute — `drawOtherEnemyRig` (`L9216-9283`)

"Every enemy walks with planted feet and bending knees": the top of the sprite (cut off at the waist) is drawn
over two procedural legs whose planted foot slides back exactly as fast as the body moves forward.

```
ENEMY_WALK_RIGS = {
 grunt:   {stride:12, lift:9,  bob:.7,  width:9,  base:'#247235', light:'#4f9b55', dark:'#174425', boot:'#303631',
           views:{front:[29,45], back:[30,46], side:[32,44], diag:[33,45]}},
 swarmer: {stride:16, lift:13, bob:1,   width:6,  base:'#cc9f16', light:'#f4cc38', dark:'#80621a', boot:'#38352c',
           views:{front:[29,46], back:[30,47], side:[39,45], diag:[34,47]}},
 brute:   {stride:8,  lift:5,  bob:.45, width:12, base:'#6b3aa6', light:'#9b63d2', dark:'#3d2361', boot:'#2a1f3e',
           views:{front:[35,53], back:[29,54], side:[30,53], diag:[34,53]}}   // b290: colours matched to his armour
}
views[pose] = [anchor, cut]: anchor = the x (source px) of the body's centre line; cut = the waist row.
```
All three sprites are 80 px tall. Drawing (into a 128 × 112 canvas, origin at (64, 96) = between the feet):
```
im    = set[pose] (first frame if an array)
view  = (brute and pose == 'back') ? 'side' : pose     # the brute's "back" picture is really a second side pose
scale = h / 80
travel = stride × 2 / 0.6 × scale × max(0.4, T.enemyStride / 10)    # units of odo per full cycle
phase = ((odo mod travel) + travel) mod travel / travel
frame = floor(phase × 96); p = frame / 96                # cached per (key, pose, frame): 96 frames a cycle
rise  = −bob × (1 − cos(p × 4π))                         # body dips/rises twice a cycle
cfg   = rig + {cut, armour: key == 'brute'}
spread = view == 'side' ? 2 : width × 0.58
far leg:  enemyRigLeg(hip = (−spread, cut − 80 + rise), foot = enemyRigFoot(p + 0.5), view, cfg, near = false)
near leg: enemyRigLeg(hip = ( spread, cut − 80 + rise), foot = enemyRigFoot(p),       view, cfg, near = true)
upper body: the picture with everything from row cut + 3 down cleared (enemyRigUpper), drawn at (−anchor, −80 + rise)
blit the canvas at (−64·scale, −96·scale), size 128·scale × 112·scale
```
`enemyRigFoot(phase, cfg)`: `phase` wrapped to 0..1; stance `phase < 0.6`: `x = stride × (1 − 2 × phase / 0.6)`,
lift 0; swing: `t = (phase − 0.6) / 0.4`, `x = stride × (−1 + 2 × smoothstep(t))`, `lift = cfg.lift × sin(πt)`
(`smoothstep(t) = t²(3 − 2t)`).

`enemyRigLeg(g, hip, foot, view, cfg, near)` (`L9238`):
```
profile = view == 'side'; diagonal = view == 'diag'
ankle.x = hip.x + (profile ? foot.x : diagonal ? foot.x × 0.65 : foot.x × 0.06)
ankle.y = −4 − foot.lift + (profile ? 0 : foot.x × (diagonal ? 0.13 : 0.18))
length  = (80 − cut − 4) × 0.58
knee    = batterKnee(hip, ankle, length, (profile || diagonal) ? 1 : (near ? 1 : −1) × 0.3)
segment(a, b, width, shin): round caps and joins
    stroke #17201d width + 2; stroke (near ? base : dark) width; then a 2-wide highlight line offset 1 px left
    in (near ? light : base);
    armour (brute): at the segment's middle, rotated along it, a plate rect (−0.4w, −(shin ? 4 : 5), 0.8w, shin ? 8 : 10)
    filled (near ? light : base), outlined 1 px dark
thigh: segment(hip, knee, width); shin: segment(knee, ankle, width × 0.78)
boot at the ankle (side/diag boots are longer, toe forward = +x):
    #171b1c rect (−0.43w, −3, 0.85w + (side/diag ? 5 : 0), 7)
    cfg.boot rect (−0.33w, −2, 0.65w + (side/diag ? 4 : 0), 5)
    sole line (near ? #7b7b71 : #51564f) rect (−0.33w, 2, 0.65w + (side/diag ? 4 : 0), 1)
```
`batterKnee(hip, ankle, length, bend)` (`L9139`) — a two-bone knee:
`d = max(0.001, |ankle − hip|)`, `half = min(length, d/2)`, `out = sqrt(max(0, length² − half²))`,
`knee = (hip + ankle)/2 + (dy/d, −dx/d) × out × bend` (with `dx, dy = ankle − hip`).

The rig is drawn without the lean rotation, but with the flip.

### 6.4 The batter's rig — `drawBatterRig` (`L9128-9214`)

"A two-joint leg rig: a planted foot travels backwards exactly as far as the character travels forwards; the
returning foot lifts and bends." Only for poses side, front and back (diag and idle aren't rigged).
```
im = set[pose][0]                                # first frame only; frames 1..n of the walk arrays are unused
sourceHeight = side ? 96 : 88; scale = h / sourceHeight
travel = (34 / 0.6) × scale × max(0.4, T.enemyStride / 10)         # BATTER_RIG_TRAVEL = 56.67
phase = (odo mod travel)/travel; frame = floor(phase × 96); p = frame/96     # cached per (pose, frame)
canvas 128 × 128, origin (64, 112)
rise = −0.8 × (1 − cos(p × 4π)); hipY = (side ? −42 : −37) + rise    # only the body rises; planted boots stay down
far  = batterFoot(p + 0.5); near = batterFoot(p)
drawRigLeg(hip = (side ? −2 : −5, hipY), far,  pose, near = false, phase = p + 0.5, denim = set.side[0])
drawRigLeg(hip = (side ?  2 :  5, hipY), near, pose, near = true,  phase = p,       denim = set.side[0])
upper = batterUpper(im, pose); anchor = side ? 36 : BATTER_WALK[pose].anchors[0] (front 27.3, back 27.2)
draw upper at (−anchor, −sourceHeight + rise)
blit at (−64·scale, −112·scale), 128·scale square
```
`batterFoot(phase)`: stance 0.6: `phase < 0.6` → `x = 17 − 34 × phase / 0.6`, lift 0; else
`t = (phase − 0.6) / 0.4`, `x = −17 + 34 × smoothstep(t)`, `lift = 12 sin(πt)`.

`batterUpper(im, pose)` cuts the old spread legs away but keeps the low-hanging bat: side: clear
`(20, 54) → (w, h)` and `(0, 71) → (20, h)`; front/back: clear `(0, 51, 50, h)` and `(50, 81) → (w, h)`.

`drawRigLeg(g, hip, foot, pose, near, phase, denim)` (`L9155-9186`): jeans and boots.
```
side = pose == 'side'
ankle = side ? (foot.x, −5 − foot.lift)
             : (hip.x + sin(phase × 2π) × 1.5, −5 + foot.x × 0.15 − foot.lift × 0.7)
knee  = batterKnee(hip, ankle, side ? 23 : 20, side ? 1 : (near ? 1 : −1) × 0.35)
base  = near ? #244965 : #162e40;  light = near ? #42657b : #2b4658
bone(a, b, width, shin): round caps/joins; stroke #101c26 width + 2; stroke base width;
    denim texture: clip to the trapezoid (±width/2 at a, ±0.4·width at b), draw the denim picture's source rect
    (shin ? (51, 71, 7, 11) : (39, 55, 9, 14)) stretched over width × length, alpha near ? 0.9 : 0.5;
    a 1-px light line offset 1 px left
thigh: bone(hip, knee, near ? 9 : 8); shin: bone(knee, ankle, near ? 7 : 6)
knee patch (rips in the jeans), not for 'back': (near ? #b78c66 : #785d49) rect (round(knee.x) − 2, round(knee.y) − 1, 4, 3)
boot at the ankle; side view: rotate −0.32 × sin(phase × 2π) while the foot is lifted
    sole/upper #111820 polygon: side (−4,−4) (3,−4) (4,0) (10,3) (10,5) (−4,5); front/back (−4,−4) (4,−4) (5,5) (−5,5)
    (near ? #797b78 : #454b4e) rect (−3,−3,6,6); (near ? #b1aaa0 : #777b79) rects (−2,−2,4,1) and (−2,0,4,1)
    #aaa99f rect (−3, 3, side ? 12 : 7, 1)
```

### 6.5 The batter's static layout — `BATTER_WALK` / `batterWalkGeometry` (`L9075-9087`)

"The batter frames are tightly cropped around both the body and the bat. Align the body, not the crop centre":
```
BATTER_WALK = { front: {height:88, anchors:[27.3,26.6,43.9,44.4], lean:0},
                back:  {height:88, anchors:[27.2,24.3,27.9,24.2], lean:0},
                side:  {height:96, anchors:[53.7,51,49.1,47.8,49.6,48.3,50.5,48.5], lean:17},
                diag:  {height:80, anchors:[65.6,65.8,65.7,65.8], lean:20},
                idle:  {height:88, anchors:[22.9], lean:0} }
geometry: scale = h / layout.height; size = image × scale;
          x = −(anchors[index % n] − layout.lean) × scale; y = −h
```
In practice only `idle` reaches it (stood still), with bob 0. The batter walking bob (`L11762`) is
`−enemyBob × 0.18 × (1 − cos(odo / max(1, enemyStride × 4) × 4π))` when walking (`running`, `|v| >= 12`, not stunned).
`drawSmoothBatterStep` (`L9099`, cross-fading the 8 side frames) is dead code: not called.

### 6.6 ENEMY_SPRITES (manifest `ENEMY_SPRITES`)

| type | pictures (px) |
|---|---|
| grunt | `front` 58×80, `diag` 60×80, `side` 60×80, `back` 59×80, `idle` 56×80 (green tracksuit) |
| swarmer | `front` 58×80, `diag` 69×80, `side` 76×80, `back` 59×80, `idle` 48×80 (yellow) |
| brute | `front` 70×80, `diag` 62×80, `side` 53×80, `back` 50×80 (really a side pose), `idle` 60×80 (purple armour) |
| batter | `front_0..3` ~70×88, `diag_0..3` 88×~77, `side_0..7` ~63×96, `back_0..3` ~68×88, `idle` 46×88, `swing_0..5` 125×144 |

Paths: `assets/ENEMY_SPRITES/<type>/<pose>.png` (batter: `<pose>_<i>.png`). Side and diag art faces right. All
pixel art: nearest filtering.

---------------------------------------------------------------------------------------------------------------

## 7. Drawing shrapnel (`L12201-12216`)

Per piece, at `(x, y)` rotated to `atan2(vy, vx)`: an outer triangle `#ff4d3d` (9,0) (−6,−6) (−6,6) and an inner one
`#ffd9c2` (4,0) (−3,−2.5) (−3,2.5). On the floor plane in 2D; in 3D float it about 14 units up (waist high) and lay
it flat facing the camera, or make it a small flat dart that turns with its velocity.

---------------------------------------------------------------------------------------------------------------

## 8. The wave banner and other text

- **Wave banner** (`L12557-12577`), whenever `breather > 0 && started && !over`: centred bold 26 px `#cfd4de`
  **"WAVE n"** with `n = wave + 1` at (430, 250); under it 14 px `#8b93a4` at (430, 276):
  `waveSize(n) + " incoming"` plus, if any apply, `" — " + list.join(" and ")` where the list is
  `swarmers` (n >= swarmWave), `batters` (baseEnemy != 3 && n >= batWave), `brutes` (n >= bruteWave). E.g.
  "WAVE 5 / 18 incoming — swarmers and brutes". Protect mode, before wave 1: a third line in `#f7a8ff` at y 288:
  "keep Gothica alive · potatoes heal her" (+ " · E picks her up" for a character who can carry her). It shows for
  the whole breather, including the extra time the janitor holds it.
- **Banner** (the big gold message, `L12666-12676`): `banner = {text, until}`; bold 34 px `#f6d17a` with a 5 px
  stroke `rgba(20,22,28,0.9)`, centred at (430, 90), drawn last. This system sets "MACHINE IS LIVE" for 1.6 s when the
  janitor finishes.

---------------------------------------------------------------------------------------------------------------

## 9. The janitor (Gary)

He has no health and never dies. "What he has is patience, and exactly two of it." He fixes the broken slot
machine in the first breather of the run: walks in from the bottom, throws the OUT OF ORDER sign down, hammers the
cabinet three times, bends down, notes fall out, pockets whatever's left, the machine goes live, he walks out.
Shoot him once: knocked flat, he complains. Shoot him again: he stares, then charges and whacks you across the
room (unhurt), then trudges back to work.

### 9.1 State (`buildWorld` `L6037`, reset in `startGame` `L13597-13606`)

`phase, t (time in phase), x, y, vx (only used while 'down'), flip, hits, flinch (never set above 0: the flinch
frames are dead), from (−1 once he enters; makes his work side the left, see below), shots, target (player index),
resume (phase to go back to), spent (1 = done reacting to bullets), paid, took, odo, wdx/wdy (walk direction),
secretReturn`.

`JAN_PHASES = ['idle','enter','yeet','swing','bend','pocket','exit','done','down','rise','gripe','regrab','stare',
'chase','whack','giveup','trudge']` (`L9391`; the index goes over the network).

### 9.2 Phases (`L7859-7998`), skipped entirely while the bonus room is active

`sx, sy` = the slot machine, (430, 110) in a run. Every step: `flinch = max(0, flinch − dt)`.

- **idle** → **enter** when `started && !over && slot.broken && wave >= T.janitorWave (1) && breather > 0`
  (i.e. the breather after wave 1): `t = 0, hits = 0, from = −1, x = sx + 60 (490), y = ARENA.h + 40 (560)
  (below the bottom wall, off screen), flip = true`.

For every phase other than idle and done:
- If phase ≠ exit: `breather = max(breather, 0.6)` — "hold the breather while he's actually working, but let the
  game get going again the moment the machine is live".
- `t += dt`; and at the end of the block `odo += T.janitorSpeed × dt` (always; walking phases add their own on top,
  so walk frames advance twice as fast: a frame per 13 odo = every 6.5 units walked).

Work:
- **enter**: walk at `T.janitorSpeed` (105) straight to `(sx + 34, sy + 26)` = (464, 136); `wdx, wdy` = direction,
  `flip = dx < 0`; when within 8: **yeet**, `t = 0`, `flip = true` (faces left, at the cabinet).
- **yeet**: at `t > 0.18`, if `sign == 'stand'`: `sign = 'floor'`; at `t > 0.30`: **swing**.
- **swing**: each time `t > 0.30`: `t = 0`, `hits += 1`; if `secretReturn && !slotSecret.used`: begin the slot
  machine's secret (`beginSlotSecret`) and **return from the whole step**; else fx WALL at
  `(sx + (from < 0 ? −14 : 14), sy − 6)` = (416, 104), sound `sNoise(0.07, 2200, 3, 0.24, bandpass, 700)` +
  `sTone(0.05, 340, 130, 0.12, square)` (a clank); when `hits >= T.janitorHits` (3): **bend** (t keeps counting).
  So three blows 0.3 s apart.
- **bend**: at `t > 0.22` (once, `paid`): `T.janitorPay` (3) notes: for i in 0..2, `a = −π/2 + (i − 1) × 0.55`,
  coin at `(sx, sy + 6)` with velocity `(cos a × 150, sin a × 90)`, `life = T.coinLife + 3` (9), `arm = 0.5`,
  random rot/spin/phase (coins spec); at `t > 0.40`: **pocket**.
- **pocket**: at `t > 0.25` (once, `took`): every coin within 90 of `(sx, sy)` is removed — "he takes whatever's still
  lying there — you can beat him to it"; at `t > 0.42`: **exit**, `slot.broken = false`, `slot.flash = 0.9`, banner
  "MACHINE IS LIVE" for 1.6 s.
- **exit**: `y += T.janitorSpeed × dt` (straight down, `wdx = 0, wdy = 1`); when `y > ARENA.h + 40`: **done**.
  (The breather is no longer held, so the next wave can start while he's still walking out; enemies ignore him.)
- **done**: nothing; not drawn. He doesn't come back this run (the machine stays fixed).

Shot once:
- **down**: `x += vx × dt`, `vx *= 0.02^dt` (slides ±90 the way the bullet went); at `t > 0.9`: **rise**.
- **rise**: at `t > 0.7`: **gripe**.
- **gripe**: at `t > T.gripeTime` (3.4): **regrab**.
- **regrab**: at `t > 0.5`: back to `resume` (or 'enter'), `t = 0`.

Shot twice:
- **stare**: faces the target (`flip = target.x < x`); at `t > 0.75`: **chase**.
- **chase**: `tp = players[target] || players[0]`; if none, dead, or `t > T.chaseGiveUp` (8): **giveup**. Else aim
  ahead: `a = tp.pos + tp.v × T.janitorLead (0.28)` ("aim where you're going, not where you are — rolling delays,
  never escapes"); move at `T.janitorRage` (340) toward it; `flip = dx < 0`; `odo += 340 × dt`. When
  `|tp − jn| < T.radius + 22` (36): **whack**: `tp.v = unit(tp − jn) × T.whackForce` (980),
  `tp.iframe = max(iframe, T.launchTime + 0.3)` (1.4), `tp.launch = T.launchTime` (1.1), `tp.roll = 0`,
  `shake = max(shake, 22)`, `freeze = max(freeze, 0.06)`, fx HURT at the player (red bits and the hurt sound, but
  no damage), sound `sNoise(0.22, 900, 1.2, 0.5, lowpass, 140)` + `sTone(0.18, 150, 50, 0.3, square)`.
- **whack**: "a beat of nothing, then he adjusts his cap and plods off": at `t > 1.1`: **trudge**, `spent = 1`.
- **giveup** (hands on knees): at `t > 1.6`: **trudge**, `spent = 1`.
- **trudge**: walk at `janitorSpeed` to `(sx + 34, sy + 26)`; within 8: phase = `secretReturn ? 'swing' :
  resume == 'enter' ? 'yeet' : (resume || 'swing')`, `t = 0`.

### 9.3 Being shot (`L7700-7729`)

Only player bullets (`w.bullets`), not punches, thrown potatoes, rockets or shrapnel. Tested before enemies:
phase not idle/done, `!spent`, and the bullet's segment hits a circle of radius 20 at `(jn.x, jn.y − 16)` (his torso
on screen). The bullet is always consumed with fx HIT. Then:
- phase **chase** or **stare**: if the shooter isn't his target, he switches to them: `target = owner`,
  `phase = 'stare'`, `t = 0` (else nothing).
- phase **gripe** or **regrab**: `shots += 1`, `phase = 'stare'`, `t = 0`, `target = owner` ("shooting a man
  mid-complaint is how you find out about Gary").
- phase in `['down','rise','whack','giveup','trudge']`: no reaction.
- any other phase (enter, yeet, swing, bend, pocket, exit): `shots += 1`;
  - first shot: if `phase == 'exit' && !slot.broken && !slotSecret.used`: the **hidden door** —
    `secretReturn = true, hits = 0, resume = 'trudge'`; else `resume = phase`. Then `phase = 'down'`, `t = 0`,
    `vx = (bullet vx || 1) > 0 ? 90 : −90`, sound `sTone(0.2, 300, 120, 0.2, square)`.
  - later shots: `phase = 'stare'`, `t = 0`, `target = owner`.

Once `spent`, bullets pass straight through him. The janitor's breather hold means a chase (up to 8 s + 1.6 s) also
holds the next wave back.

The **secret** (slot machine spec): a finished repair plus a shot while he's leaving sends him back
(down → rise → gripe → regrab → resume 'trudge' → walk to the cabinet → 'swing'), and his first swing calls
`beginSlotSecret(w)`: the world is saved, the 20-second bonus room runs inside the machine, then the run is restored
exactly (wave, queue, enemies; enemies within 120 of the returning players are moved up 145 and stunned 1.5 s), the
janitor is 'done'. While `secretActive(w)` the wave director and janitor don't run. The tweaks-only **J** key forces a
janitor visit for testing (`L8638-8646`: broken, sign up, idle, `wave = max(wave, janitorWave)`, `breather = 5.2`).

### 9.4 Drawing (`L11640-11721`)

- **Hammer** while phase ∈ {down, rise, gripe}: `hammer_prop` 26 wide (aspect kept), top-left at
  `(round(jn.x + 22), round(jn.y + 4))`, drawn under him. It's lying on the floor where he dropped it.
- Not drawn when idle or done. Frame `key`:
  - `flinch > 0` (never happens): `flinch` / `flinch_recover`.
  - enter, exit, trudge: `janWalkKey(jn, wdx, wdy)`: if `|dy| > |dx| × 1.2`: `dy < 0` → back1-4 ("up"), else
    front1-4 ("down"); otherwise walk1-4 (side); frame `floor(odo / 13) % 4`.
  - chase: charge_a/charge_b by `floor(odo / 13) % 2`.
  - down: `list[t < 0.35 ? 0 : 1]` — **bug**: `JAN_ANIM` has the key `down` twice (`L9403` `['down_flat',
    'down_elbow']` and `L9415` `['front1'..'front4']`); in JS the second wins, so knocked down he shows front1 then
    front2 (standing). In Godot use `down_flat` then `down_elbow`, as intended.
  - rise: getting_up (`t < 0.45`) then angry.
  - swing: `list[min(3, floor(t / 0.30 × 4))]`: swing_start, swing_up, swing_down, swing_hit (one blow per 0.3 s).
  - everything else: `list[min(n − 1, floor(t / 0.4 × n))]` with `JAN_ANIM` (`L9394-9416`):
    yeet `yeet_wind, yeet` (switches at 0.2 s, sign lands at 0.18); bend `crouch_start, bend`; pocket
    `stand_up, pocket`; gripe `angry`; regrab `pickup`; stare `angry`; whack `swing_hit`; giveup `giveup`.
- Shadow: ellipse at `(x, y + 0.85r)` radii `0.9r × 0.36r`, `rgba(0,0,0,0.34)` (r = `T.radius` 14).
- Size: `h = 14 × T.spriteScale × T.janitorScale × (front/back frames ? JAN_VERT_SCALE 0.94 : 1)` = 57.96
  (54.48 for front/back), feet at `(x, y + 0.9r)`, centred horizontally, mirrored when `flip` **except** front/back
  frames ("never mirror a front or back view"). Side art faces right.
- **Gripe bubble**: text "HEY! I'M JUST TRYING TO DO MY JOB!", bold 11 px; box `textWidth + 16` × 22, x centred on
  him but kept inside the arena walls (+4), top at `jn.y − 14 × 4.6 × 0.9 − 30`; fill `#f2efe6`, a tail triangle
  down to his head (±5, 8 long), 2 px `#14161c` border, text `#14161c` at box top + 15.
- **Give up**: after `t > 0.3`, "..." bold 12 px `#8b93a4` at `jn.y − 57.96 − 12`.
- **The sign** (`drawSign`, `L11967-11988`; slot machine spec owns it): a drawn card ~46 × 30: shadow
  `rgba(0,0,0,0.35)` (−23,−14,46,30), card `#c8a56b` (−22,−13,44,28), top strip `#a8854f` 3 high, tape
  `rgba(255,255,255,0.5)` (−24,−16,10,5) and (14,11,10,5), "OUT OF" / "ORDER" bold 8 px `#2b2118` at y −2 / 8.
  Standing: at `(slot.x + 4, slot.y − 44)` rotated −0.06 (taped to the cabinet front). On the floor: at
  `(slot.x + 30, slot.y + 26)` rotated 0.5 and squashed to 45 % height (lying flat).

JANITOR_SPRITES (all 96 px tall): walk1-4 (37-54 wide), front1-4 (44-45), back1-4 (42-43), yeet_wind, yeet,
swing_start, swing_up, swing_down, swing_hit, crouch_start, bend, stand_up, pocket, flinch, flinch_recover,
down_flat (79), down_elbow (72), getting_up, angry, pickup, charge_a, charge_b, giveup; `hammer_prop` 40 × 25.
Paths `assets/JANITOR_SPRITES/<key>.png`.

---------------------------------------------------------------------------------------------------------------

## 10. Effects and sounds

### 10.1 fx events (`L6072-6077`, `fx` `L6238`)

`fx(w, kind, x, y)`: a burst of `n` square particles (`burst`: random direction, speed `speed × (0.3..1.0)`,
life 0.25-0.6, `max` 0.6, drawn 3 × 3 at alpha `life/max`, drag `0.9^(dt × 60)`), and an event `[kind, x, y]`
pushed to `w.events` (max 40). Kinds used here:

| kind | n | colour | speed | sound (`playEventSounds`, `L11371`) |
|---|---|---|---|---|
| HIT 0 | 4 | `#f6d17a` | 180 | `SFX.hit` |
| KILL 1 | 14 | `#6fd3a0` | 260 | `SFX.kill(false)` |
| WALL 2 | 3 | `#5a6274` | 120 | none |
| HURT 3 | 10 | `#e0473f` | 220 | `SFX.hurt` |
| DOWN 4 | 24 | `#e0473f` | 300 | `SFX.down` |
| BOOM 5 | 36 | `#ff9a6a` | 420 | `SFX.kill(true)` |

The machine running the world plays sounds from its own events each frame; the network guest plays them from the
snapshot's `x` list and makes its own particles (`playEvents`, `L11125`). Sounds played directly in the sim (janitor
knockdown, clank, whack, launched wall bounce) are host-only: the guest doesn't hear them (fix in Godot by making
them events).

### 10.2 Synthesis (`L11156-11242`)

Master gain 0.5. `vary(n, amt = 0.12) = n × (1 + (rand − 0.5) × amt)` (±6 %).
- `sTone(dur, f0, f1, gain, wave)`: one oscillator (`sine`/`square`/`sawtooth`/`triangle`), frequency starts at
  `f0` and ramps **exponentially** to `max(20, f1)` over `dur` (no ramp if `f1` is 0); gain starts at `gain` and
  ramps exponentially to 0.0008 over `dur`; stops at `dur + 0.02`.
- `sNoise(dur, freq, q, gain, type, sweepTo)`: looped white noise (1.2 s buffer) through a WebAudio biquad (`type`
  lowpass/bandpass, cutoff `freq`, `Q = q`), cutoff ramping exponentially to `max(40, sweepTo)` over `dur`; gain
  exponential from `gain` to 0.0008. (WebAudio quirk: for lowpass the Q is a resonance in dB; for bandpass it's the
  ordinary Q.)
- Exponential ramp: `v(t) = v0 × (v1 / v0)^(t / dur)`.

| sound | recipe |
|---|---|
| `SFX.hit` (wet thud on an enemy) | `sNoise(0.075, vary(900), 1.6, 0.24, lowpass, 240)` + `sTone(0.05, vary(190), 80, 0.10, triangle)` |
| `SFX.kill(big)` | `sNoise(big ? 0.34 : 0.22, vary(1100), 1.1, big ? 0.5 : 0.36, lowpass, 130)` + `sTone(big ? 0.26 : 0.18, vary(160), 38, big ? 0.32 : 0.22, sawtooth)` |
| `SFX.hurt` ("you took one: unmistakable") | `sTone(0.30, 420, 120, 0.34, sawtooth)` + `sNoise(0.16, 1600, 1.4, 0.20, bandpass, 300)` |
| `SFX.down` ("you're out") | `sTone(0.75, 300, 55, 0.40, sawtooth)` + `sNoise(0.5, 700, 1.0, 0.26, lowpass, 90)` |
| janitor knocked down | `sTone(0.2, 300, 120, 0.2, square)` |
| janitor hammer clank | `sNoise(0.07, 2200, 3, 0.24, bandpass, 700)` + `sTone(0.05, 340, 130, 0.12, square)` |
| janitor whack | `sNoise(0.22, 900, 1.2, 0.5, lowpass, 140)` + `sTone(0.18, 150, 50, 0.3, square)` |
| launched player hits a wall | `sNoise(0.14, 500, 1.1, 0.34, lowpass, 90)` + `sTone(0.12, 120, 46, 0.2, square)` |

No sound for a wave starting, a spawn, or the batter's wind-up.

---------------------------------------------------------------------------------------------------------------

## 11. Over the network (for milestone 4)

The host simulates; the guest only draws. The host sends `{t: 'snap', s: snapshot(world)}` every 50 ms (20 Hz,
`L11104-11107`) over PeerJS; the guest rebuilds a drawable world with `worldFromSnapshot(s, age)` where
`age = min(0.25, seconds since the packet)` (0 while `fz > 0`, and in the bonus room), extrapolating moving things
by `velocity × age` (`L8403-8496`). Fields this system needs (`snapshot`, `L8300-8399`):

| key | content |
|---|---|
| `w` | `wave` |
| `o` | `over ? 1 : 0` |
| `br` | `round(breather × 100)` |
| `st` | `started ? 1 : 0` |
| `tm` | `round(t × 100)` (b293: the clock, for the guest's animations) |
| `fz` | `round(freeze × 1000)` |
| `sk` | `round(shake)` |
| `md`, `gd`, `gt` | mode, Gothica down, Gothica's state (Protect spec) |
| `e` | per enemy `[round x, round y, round vx, round vy, hp, round(spawn × 100), flash > 0 ? 1 : 0, t, st, round(sdx × 100), round(odo × 100)/100, round(stT × 100), round(stun × 100)]` — the guest: `x + vx·age`, `odo + |v|·age` (b291: the walk keeps stepping between packets), `flash` 1/0 |
| `s` | shrapnel `[round x, round y, round vx, round vy]` (life not sent), extrapolated |
| `jn` | `[JAN_PHASES index, round x, round y, flip, hits, round(flinch × 100), round(t × 100), round odo, sign (0 stand / 1 floor / 2 gone), slot.broken, shots, target, spent, round(wdx × 100), round(wdy × 100)]` (not extrapolated) |
| `p` | per player `[0 id, 1 x, 2 y, 3 vx, 4 vy, 5 fx×100, 6 fy×100, 7 hp, 8 alive, 9 iframe×100, ..., 13 kills, ..., 20 launch×100, ..., 36 roll×100, ...]` (`grace` isn't sent; it doesn't show) |
| `x` | the events since the last snapshot, `[kind, x, y]` (then cleared) |

Not sent: `sdy`, `hit`, `pending`/`queue`/`spawnTimer` (the guest's "N incoming" uses `waveSize`), the janitor's
`resume/paid/took/vx/secretReturn`. Guest buttons: Start and Restart are host-only; the guest sees "waiting for the
host to start". When the guest connects to a host whose game is over, the host makes a new world first (`L10805`).

---------------------------------------------------------------------------------------------------------------

## 12. In Godot

### 12.1 Shape of it

Keep the HTML split: **a pure simulation in HTML units** (no physics bodies for enemies) and **views** that read
it. The sim is what the host runs and what the snapshot packs (milestone 4); the views draw either the live sim or a
state rebuilt from a snapshot, exactly like `render(view)`. New files (milestone 2; names are a proposal):

| file | class | job |
|---|---|---|
| `scripts/arena/etype.gd` | `EType` (static) | ETYPE from `GameData.data.ETYPE`, `rad(t)`, `max_hp(t)`, BAT consts |
| `scripts/arena/arena_sim.gd` | `ArenaSim` (Node) | the world state of 2.1, `rnd()`, fixed 1/120 accumulator, steps 3.5 items 4-10 (wave director, enemies, batter, separation, clamp, contact, shrapnel, janitor), `start_run()`, `restart()`, `snapshot()`, `apply_snapshot(s, age)`, signals |
| `scripts/arena/wave_director.gd` | `WaveDirector` (static funcs) | `wave_size`, `wave_mix`, `wave_speed`, `spawn_point` |
| `scripts/arena/janitor_sim.gd` | `JanitorSim` (RefCounted) | 9.2-9.3 |
| `scripts/arena/enemy_view.gd` | `EnemyView` (Node3D) | one per enemy: billboard, pose, rig, flash, rings, shadow, hp bar |
| `scripts/arena/rig_baker.gd` | `RigBaker` (Node) | bakes the walk-rig frames (12.4) |
| `scripts/arena/janitor_view.gd` | `JanitorView` (Node3D) | his frames, hammer, bubble, "..." |
| `scripts/arena/shrapnel_view.gd` | `ShrapnelView` (MultiMeshInstance3D) | one instance per piece |
| `scripts/arena/arena_room.gd` | `ArenaRoom` (Node3D) | the arena look and switching the lobby on/off (12.6) |
| `scripts/arena/player_vitals.gd` | `PlayerVitals` (Node, child of each Player) | hp, alive, iframe, grace, hurt(), blink, pips |
| `scripts/ui/wave_hud.gd` | `WaveHud` (CanvasLayer) | top-left line, wave banner, the big banner, game over overlay |
| `scripts/audio/sfx.gd` | `Sfx` (autoload, shared) | `tone()` / `noise()` as 10.2 |
| `scenes/arena.tscn` | | ArenaSim + ArenaRoom + views container + WaveHud, instanced by `main.tscn` |

Signals from `ArenaSim`: `fx(kind, x, y)`, `enemy_spawned(e)`, `enemy_killed(e, dir: Vector2, big: bool, owner:
int)` (gore, coins and kills counters hook here), `player_hurt(id, dmg)`, `player_down(id)`, `wave_started(n)`,
`breather_started`, `game_over`, `banner(text, secs)`, `janitor_paid(x, y)`. Weapons call in with
`ArenaSim.damage_enemy(i, dmg, dir, knock, stun, big, owner)` and `ArenaSim.hit_janitor(seg_from, seg_to, owner)`;
one `kill_enemy()` implements 4.9 so every weapon kills the same way.

Represent enemies as small `RefCounted` objects (or Dictionaries) with exactly the fields of 2.2. Positions stay in
HTML units; views convert with `GameData.world_to_3d(x, y, z)`.

### 12.2 Timing

`ArenaSim._process(delta)`: `acc += min(delta, 0.1)`; while `acc >= 1/120`: `step(1/120)`. Freeze (hit-stop) and
`over` gate the step as in 3.5. The Player is stepped by the Player task, probably in `_physics_process`; for the
hit-stop to freeze him too, Player should skip its movement while `ArenaSim.frozen()` (ask the Player task, or have
`PlayerVitals` set `player.frozen` for the freeze, which the contract already has).

### 12.3 What the Player contract needs (request these from the Player task; don't edit `player.gd` yourself)

The milestone 1 `Player` exposes `html_pos()`, `place()`, `facing`, `moving`, `frozen`, `dz`. This system also needs:
- **Velocity in HTML units that persists**: pushes add to it and the HTML accel/friction (2200/1900, cap 260) bleed it
  off. If M1 already keeps `velocity` across frames with that accel/friction, `PlayerVitals` can add impulses as
  `player.velocity += Vector3(ix, 0, iy) × UNIT`. Ask for `add_impulse(v: Vector2)` to make it explicit.
- **Launch**: `launch(v: Vector2, secs: float)`: no input, no cap, `v *= launchDrag^dt`, bounce off walls keeping
  0.55 (5.3), `v *= 0.3` at the end. The janitor whack and the rocket blast both use it.
- **Roll state**: `rolling()` (so roll start can grant `iframe = max(iframe, 0.3)`, and a whack can cancel the roll).
- An `alive` switch: hidden, no input, no collision while dead; `revive_at(x, y)`.
Until those exist, `PlayerVitals` can hold `alive/hp/iframe/grace` and toggle `player.frozen` + `visible`.

### 12.4 Enemy views

- `EnemyView` is a Node3D at `world_to_3d(e.x, e.y)` holding: a shadow (a flat ellipse quad on the floor; the HTML's
  `0.9r × 0.35r` ellipse is a squashed circle in a 3/4 view, so in 3D use a circle of radius about `0.9r`, black,
  alpha 0.3), a sprite quad, the hp bar (a Sprite3D/quad pair billboarded above the head at
  `r × enemyScale + 5` up), and the rings (flat torus/line rings on the floor: the spawn ring in the type's colour,
  the batter's red wind-up ring `batReach × (0.5 + left × 0.8)`).
- **Feet on the origin** (drop the HTML's `+0.8r` screen offset). Sprite height in metres = `r × enemyScale ×
  poseScale × UNIT` (grunt 1.28 m, swarmer 0.77, brute 2.04, batter 1.28, janitor 1.45 next to the player's 1.61).
- **Billboarding**: rotate the node to face the camera about the vertical axis only (like `CharSprite`), done in
  code so a second rotation about the view axis can add the lean / stun rock (8.).
- **Which pose**: the HTML picks it from screen-space velocity with the camera always looking north. In 3D use the
  angle between the enemy's ground velocity `m` and `c`, the ground direction from the enemy toward the camera:
  `θ = angle(m) − angle(c)`, `oct = round((θ + π/2) / (π/4)) mod 8`, then the table in 6.1 (flip = mirror the quad).
  For the top-down camera use `c = −(camera forward projected on the ground)` for every enemy (reproduces the HTML
  exactly); in first person use `c = camera position − enemy position`. Check against `CharSprite`'s choice so
  players and enemies agree.
- **Flash**: a ShaderMaterial (unshaded, alpha scissor/blend, nearest filter) with a `flash` uniform:
  `rgb = mix(vec3(lum), rgb × 2.6, 0.2)` clamped (CSS `brightness(2.6) saturate(0.2)`).
- **Rigs**: bake the HTML rig drawings once. `RigBaker` owns one SubViewport (transparent background) with a
  Node2D whose `_draw()` reproduces 6.3/6.4 with `draw_line` (+ `draw_circle` at ends for round caps),
  `draw_colored_polygon` for boots, `draw_polygon(points, colors, uvs, texture)` for the denim trapezoid, and
  `draw_texture_rect_region` for the upper body (pre-cut once with `Image.fill_rect(rect, Color(0,0,0,0))` as
  `enemyRigUpper`/`batterUpper` do). Draw a whole grid of frames in one pass, grab the viewport image once, make
  `AtlasTexture`s. Budget: HTML caches 96 phases per cycle; 32 phases (128 × 112 cells, poses × 32 per type) keeps it
  under ~30 MB of VRAM for all four types, which matters on the web; make the count a constant. The rig canvas
  origin (feet) is at (64, 96) (batter: (64, 112) in a 128 square), scale = `h / 80` (batter `h / 96` side, `h / 88`
  front/back). Phase from `odo` exactly as 6.3/6.4.
- Static frames (idle poses, the batter's swing and idle) are plain `ENEMY_SPRITES` textures with the anchors of
  6.4/6.5 and `ENEMY_ANCHOR`/`ENEMY_POSE_SCALE` (swing: anchor 0.401, ×401/325).
- **Shrapnel**: `ShrapnelView` MultiMesh of little flat two-tone darts (the triangles of 7) about 14 units up,
  oriented along velocity, facing up for the top-down camera and toward the camera in first person.

### 12.5 The janitor view

A billboard like the enemies with `JANITOR_SPRITES`; walk frames by `janWalkKey` but with `wdx, wdy` judged
relative to the camera (front frames when walking toward it, back frames away, side frames otherwise, mirrored with
`flip` except front/back). Use `down_flat`/`down_elbow` for 'down' (fix of the duplicate-key bug). Hammer: a flat
quad on the floor (`hammer_prop`, 26 units wide) with its top-left at `(x + 22, y + 4)`. The gripe bubble and "...":
a `Label3D` (billboard, no depth test, outline) or a Control placed with `camera.unproject_position()` at his head
height (58 + 30 units up), styled as 9.4. The OUT OF ORDER sign belongs to the slot machine, but its 'stand' →
'floor' switch is driven by `w.sign` here (in 3D: a card on the cabinet's face, then a card lying flat on the floor
at `(slot.x + 30, slot.y + 26)` turned 0.5 rad).

### 12.6 The arena room (what the lobby becomes)

The run happens in the lounge's footprint (0..860 × 0..520). `ArenaRoom.enter_run()` / `exit_run()`:
- Hide every lobby prop and its collision (furniture, gym, tower, pool and ducks, cabinets, dummies, cans, lobby
  Gothica), the bedroom, the yard and the bbq; **close the door gaps** (the bedroom door in the bottom wall and the
  back door) so the walls are a plain rectangle 18 thick; the yard and bedroom aren't reachable. Ask the World task
  for a way to do this (e.g. `WorldBuilder.set_run_mode(on)` or groups "lobby_only" / "door_gap"), since they own
  those nodes.
- Floor: unshaded `#1b1e26` with 1-unit `#232733` grid lines every 40 units from the wall line (a tiny shader on
  the floor plane, or a generated 40 × 40 tile). Walls `#2b3040`.
- The slot machine at (430, 110) and the vending machine at (705.2, 154) (their own specs); in the HTML they're
  walk-through. Keep them non-solid for parity, or give them player-only collision as a deliberate change (enemies
  would still pass through).
- `ArenaSim.start_run()` does 3.1 (including moving yard players to (645, 482) and snapping bedroom players
  inside); `restart()` reloads the lobby (a fresh lobby state for every system: simplest is to reload the main scene
  with the chosen characters and the second player kept).
- Clamp: players in the run are clamped to [32, 828] × [32, 488] (the walls do it if the player's collision radius
  is 14 and the walls are at 18).

### 12.7 HUD (`WaveHud`, a CanvasLayer, so it's the same in both views)

Top-left run line (5.5), the wave banner (8), the big gold banner (shared: other systems set banners too; make it a
small `Banner` API on the HUD), the game over overlay (3.3) with a Restart button (R, the pad's Start/View as the
HTML's restart bindings). HP pips over each player's head in top-down (a billboarded strip at the 5.5 height); in
first person show your own pips in the HUD corner instead (you can't see your head).

### 12.8 First person in the arena

The HTML only allows first person in the lobby (starting a run ends it). Milestone 2 wants shooting in both views,
so allow V in the run, with the same simulation underneath (all hits and ranges stay 2D on the ground):
- Enemies, the janitor and shrapnel are billboards facing the camera position; poses from 12.4 with
  `c = camera − enemy`, so a batter coming at you shows his front, one crossing shows his side.
- The batter's tell must read without the top-down view: the red floor ring still draws (visible when he's in
  front); add a short rising whoosh at wind-up start (new: `sTone(0.38, 180, 520, 0.12, sawtooth)` panned/
  positional) and keep his swing pose.
- Threats you can't see: small red chevrons at the screen edge for enemies within ~150 units outside the view cone,
  and a red flash on the side you were hit from (new). Positional audio (AudioStreamPlayer3D) for hit/kill/hurt.
- Hurt/iframes: you can't see yourself blink; pulse a faint red vignette while `iframe > 0`.
- Shake: apply to the camera in both views, but in first person as a small rotation jitter (≈ `shake × 0.15°`),
  not a positional one.
- The janitor's whack in first person: the camera rides the launch (the Player is thrown), maybe a small roll tilt.
- Death in first person: the camera drops to ~10 units over 0.4 s and tilts; it stays there until the next wave
  revives you at (430, 260) (classic) or the overlay shows. In two-player, the dead player could switch to watching
  the partner from top-down; optional.
- The hit-stop freezes the sim, not mouse look.

### 12.9 Sound

`Sfx` autoload (shared with every system): synthesise each recipe of 10.2 into an `AudioStreamWAV` (mono 16-bit,
22 050 Hz) the first time it's asked for — oscillator with the exponential frequency ramp, white noise through an
RBJ biquad with the exponential cutoff sweep, exponential gain envelope to 0.0008 — and cache it; play through a pool
of `AudioStreamPlayer`s on a bus at −6 dB (master 0.5). `vary()` can be done by caching 3-4 variants per sound or by
`pitch_scale = 1 ± 0.06`. Trigger sounds from the sim's `fx` events (and make the janitor's and the wall-bounce
sounds events too, so the guest hears them in milestone 4).

### 12.10 Network (milestone 4)

`ArenaSim.snapshot()` returns the fields of 11 in the same packed arrays (a Dictionary of Arrays sends well with
Godot's multiplayer); `apply_snapshot(s, age)` rebuilds plain view state with the same extrapolation. Views must only
read view state, never the live sim internals, so the guest path is free. Keep `JAN_PHASES` order and the ETYPE
indices stable: they go over the wire.

### 12.11 Checks against the HTML

- Wave 1 is six batters, 0.45 s apart, starting 2.2 s after Start; "WAVE 1 / 6 incoming" during the breather.
- A batter reaching you: ring shrinks for 0.38 s, hit 0.08 s into the swing for 2 hearts, only in front of him.
- After wave 1: Gary walks up from the bottom to (464, 136), the sign flops down at 0.18 s, three clanks 0.3 s apart,
  three notes, he pockets what's left at 0.25 s, "MACHINE IS LIVE", walks out; wave 2 starts about 0.6 s later.
- Shoot him once: flat on his back (slides), up, the bubble for 3.4 s, picks up the hammer, carries on. Again:
  stares 0.75 s, charges at 340, throws you ~1.1 s across the room unhurt, waits 1.1 s, trudges back; bullets pass
  through him afterwards.
- A brute's death throws 8 shards in a ring; they hurt you (1) and kill swarmers/batters/grunts but not brutes.
- All players down: everything stops, "DOWN / made it to wave N — K killed"; R goes back to the lobby.
- Compare with `godot/reference/wave.png`.
