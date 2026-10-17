# Weapons and shooting: porting spec

Source: `Smashed.html` (build b331). Everything here was read from the code; line numbers are the HTML file's
(`L1234`). Numbers are given as `T.name (value)`, where `T` is the tuning table (`data/game_data.json` → `T`,
HTML `L255`). Positions are HTML units: `x` across, `y` down the screen (north to south on the ground), `z` / `dz` /
`h` up. Directions in the HTML are vectors `(ax, ay)` on the ground. The simulation runs in fixed steps of
`FIXED_DT = 1/120` s (`advanceSimulation`, `L12705`). `rnd(w)` is the world's own random number generator
(`L6060`, an LCG: `seed = (seed*1664525 + 1013904223) mod 2^32`, returning `seed / 2^32`, with `seed` starting at 1 in
every new world). `Math.random()` is used only for things that are just for show.

What this spec covers: fists, the spud gun (ammo, reload, pickup, potatoes growing on the floor, husks), the potato
throw ("lob": wind-up, lob, landing ring), blasters, shotgun, the nuke launcher (rockets, blasts) and the nuke itself
(the slot machine's SCREEN CLEAR), muzzles and barrels for each character and weapon skin (`MUZZLE_BY_CHAR`,
calibration), the weapon bar (`HOTBAR`), weapon sprite sets, first-person shooting (the shots, the guns in your hands,
`FP_BLASTER`), the sounds, and what goes over the network.

Other specs own the systems this one calls into: enemies and waves, gore (`makeCorpse`, `killBurst`, `splat`,
`spray`), coins (`payKill`), the janitor, the slot machine and vending machine, the character sprites (`poseFor`),
the camera and first person, and the networking layer. This spec gives the exact calls and arguments where weapons hand
off to them.

---

## 1. The six weapons at a glance

| id | bar label | how you get it | ammo | rate limit | per hit | notes |
|---|---|---|---|---|---|---|
| `fists` | FISTS (`POW`) | always | none | `fireRate` 3.2/s | `T.punchDmg` 0.7 × `T.enemyHp` 3 = **2.1** | lunge, shove ×2.8, lands at 55% of the swing |
| `spud` | SPUD | always (start of run) | `p.ammo` pellets, 10 per potato | the jab between shots, `T.spudReload` 0.42 s | `dmgFrac` 0.5 × 3 = **1.5** | husk thrown after every 10th shot |
| `lob` | THROW | always | 10 pellets (one potato) per throw | wind-up and throw animation | 6.6 × (1 + 0.5 × power) = **7.26 to 9.9** | full power bursts (splat) on landing |
| `blaster` | BLAST | slot prize REAL GUNS!, and in the lobby | infinite | `T.fireRate` 9.5/s | **1** | two guns, shots alternate |
| `shotgun` | SHOT | slot prize SHOTGUN! (or debug G) | `T.shotgunTime` 12 s on a clock | `fireRate` 2.4/s | 5 pellets × **1** | the clock only runs in a run |
| `launcher` | NUKE | vending machine, $`T.vendPrice` 2500 | `p.rockets`, `T.launcherRounds` 3 | `T.launcherRate` 1.1/s | blast: **12** at the centre, 4.2 at the edge | lobs to a spot; empties itself after the last rocket |

Enemy health for reference (`eMaxHp`, `L676`: `max(1, round(T.enemyHp × ETYPE.hp))`): grunt 3, swarmer 1, brute 8,
batter 4.

---

## 2. The weapon table (`WEAPONS`, L636)

Also in `game_data.json` → `WEAPONS`. Missing fields fall back to `T` values (see `firePlayer`).

```js
fists:    { name:'fists', pellets:1, fireRate:3.2, fists:true, skin:null, flash:0, flashTime:0 }
lob:      { name:'potato', pellets:1, fireRate:1.5, lob:true, ammo:true, flash:0, flashTime:0,
            skin:{ juicy:'juicy_spud', tyson2:'tyson2_spud' } }
spud:     { name:'spud gun', pellets:1, spread:4, fireRate:8, speed:360, life:0.9, size:4, recoil:190,
            knockMul:0.8, dmgFrac:0.5, flash:0.7, flashTime:0.05, ammo:true, jab:true,
            skin:{ juicy:'juicy_spud', tyson2:'tyson2_spud' } }
blaster:  { name:'blasters', pellets:1, skin:null, flash:1.0, flashTime:0.055 }
launcher: { name:'nuke launcher', pellets:1, rocket:true, flash:2.2, flashTime:0.12,
            skin:{ juicy:'juicy_launcher', tyson2:'tyson2_launcher' } }
shotgun:  { name:'shotgun', pellets:5, spread:20, fireRate:2.4, speed:520, life:0.42, size:5, recoil:220,
            knockMul:2.2, flash:1.7, flashTime:0.075,
            skin:{ jared:'jared_shotgun', tyson:'tyson_shotgun', juicy:'juicy_shotgun', tyson2:'tyson2_shotgun' } }
```

What the flags mean:
- `fists`: the punch path (no projectile).
- `lob`: the throw path. Its `fireRate` 1.5 is **never used**: the lob branch doesn't touch `cooldown`.
- `ammo`: uses `p.ammo`. `jab`: the spud-gun reload cycle (jab after each shot, husk after each potato).
- `rocket`: the launcher path. Its rate is `T.launcherRate`, not `fireRate` (`wFireRate`, `L6874`).
- `skin`: which sprite sheet the character wears while holding it (§11.1), and which barrel map is used (§10).
  `null` or a missing entry means the character's own sheet (the blasters are drawn in every base sheet).
- `flash`: how big the muzzle flash is (× `T.flashSize`). `flashTime`: how long it lasts (`p.muzzle`).

`weaponOf(p)` (`L6873`) returns `WEAPONS[p.weapon]`, or `WEAPONS.blaster` if the id is unknown.
`wFireRate(p)` = `T.launcherRate` for the rocket, else `g.fireRate || T.fireRate`.

### 2.1 Every T value this spec uses

Shots: `bulletSpeed` 620, `fireRate` 9.5, `spread` 4 (degrees), `bulletLife` 1.4, `bulletSize` 4, `recoil` 60,
`knockback` 170, `stagger` 0.13, `staggerMass` 1, `enemyHp` 3, `enemyRadius` 15, `radius` 14 (the player),
`killShake` 5, `killShakeBig` 3.2.
Barrels and flash: `spriteScale` 4.6, `muzzleFwd` 30, `muzzleSide` 7, `muzzleUp` 18, `dualGuns` 1, `flashSize` 13,
`shotgunFlash` 1.7, `hpHeight` 1.05.
Shotgun: `shotgunTime` 12.
Spud gun: `spudPellets` 10, `spudStart` 0, `spudMaxAmmo` 200, `spudReload` 0.42, `jabRun` 1, `spudPickup` 0.36,
`spudThrow` 0.5, `spudThrowSpd` 520, `spudThrowFrac` 1, `spudEmpty` 0.18.
Plants: `spudGrow` 9, `spudRate` 5, `spudMax` 6.
Throw: `lobWhole` 2.2, `lobCharge` 0.3, `lobNear` 110, `lobFar` 430, `lobPowDmg` 1.5, `splatRadius` 72, `splatDmg` 0.9,
`splatKnock` 1.8.
Fists: `punchTime` 0.24, `punchReach` 40, `punchDmg` 0.7, `punchKnock` 2.8, `punchLunge` 170.
Launcher: `launcherRounds` 3, `launcherRate` 1.1, `launcherRecoil` 320, `lobTime` 0.75, `lobHeight` 110, `lobMax` 420,
`lobMin` 50, `lobDefault` 220, `blastRadius` 110, `blastDmg` 4, `blastEdge` 0.35, `blastPush` 520, `blastSelf` 1.4,
`blastYeet` 620, `blastSize` 340, `blastTime` 0.6, `blastShake` 18.
Buying it: `vendShow` 1, `vendPrice` 2500, `vendRadius` 56, `vendHold` 0.8, `vendX` 0.82, `vendDrop` 82,
`loungeVendX` 235, `testCash` 2500 (testing: you start every run and lobby with $2500).
The nuke: `nukeFall` 1.9, `nukeBoom` 0.85, `nukeSize` 340, `nukeShake` 26.
Lobby targets: `dummyHp` 6, `dummyRespawn` 2.5. Rope: `ropeCount` 10, `ropeCool` 20, `ropeX` 345, `ropeY` 152.
Gore hand-offs use `hitStop` 0.022, `hitStopBig` 2.2.

Slider ranges (`RANGES`, `L481`; `[min, max, step]`), for a tuning panel: bulletSpeed [150,1400,10],
fireRate [1,30,0.5], spread [0,25,0.5], bulletLife [0.3,4,0.1], bulletSize [2,10,1], recoil [0,400,10],
muzzleFwd [0,90,1], muzzleSide [-30,30,1], muzzleUp [0,60,1], shotgunFlash [1,4,0.1], shotgunTime [3,60,1],
spudPellets [4,60,1], spudStart [0,6,1], spudMaxAmmo [10,400,10], spudReload [0.2,2,0.05], spudPickup [0.15,1.5,0.02],
spudThrow [0.2,2,0.05], spudThrowSpd [150,1200,20], spudThrowFrac [0,4,0.25], lobWhole [0.5,6,0.1],
lobCharge [0.1,3,0.05], lobNear [40,300,5], lobFar [150,700,10], lobPowDmg [1,4,0.1], splatRadius [20,200,2],
splatDmg [0,4,0.1], splatKnock [0,6,0.1], punchTime [0.1,0.6,0.02], punchReach [16,90,2], punchDmg [0.1,4,0.1],
punchKnock [0.5,8,0.1], punchLunge [0,500,10], spudGrow [2,40,0.5], spudRate [1,30,0.5], spudMax [0,20,1],
spudEmpty [0.05,1,0.01], nukeFall [0.4,3,0.05], nukeBoom [0.3,2,0.05], nukeSize [120,700,10], nukeShake [0,60,1],
launcherRounds [1,10,1], launcherRate [0.3,4,0.1], launcherRecoil [0,900,10], lobTime [0.3,2,0.05],
lobHeight [0,300,5], lobMax [150,860,10], lobMin [0,300,5], lobDefault [50,500,10], blastRadius [30,200,2],
blastDmg [0.5,10,0.1], blastEdge [0,1,0.05], blastPush [0,1500,20], blastSelf [0,4,0.1], blastYeet [0,1500,20],
blastSize [60,600,10], blastTime [0.2,2,0.05], blastShake [0,60,1].

---

## 3. State

### 3.1 On each player (`newPlayer`, L711)

| field | start | meaning |
|---|---|---|
| `weapon` | `'spud'` (then `fillLobby` sets `'blaster'`) | the weapon in hand |
| `blasters` | 0 (lobby: 1) | 1 once the blasters are earned; they then stay for the run |
| `wTime` | 0 | shotgun seconds left |
| `rockets` | 0 | launcher rounds left |
| `dump` | 0 | seconds until an empty launcher is put away |
| `buy` | 0 | seconds stood still at the vending machine |
| `prevWeapon` | `'spud'` | set when buying the launcher; never read (dead) |
| `ammo` | 0 (lobby: `T.spudPellets × 2` = 20) | spud pellets; 10 = one potato |
| `reload` | 0 | jab timer (spud gun), counts down from `T.spudReload` |
| `pickup` | 0 | bend-and-grab timer, from `T.spudPickup` |
| `throw` | 0 | throw timer (a husk or a whole potato), from `T.spudThrow` |
| `threw` | (unset) | 1 once this throw's object has left his hand |
| `throwWhole`, `throwPow`, `throwDx`, `throwDy`, `throwDist`, `throwTx`, `throwTy` | (unset) | the pending whole-potato throw |
| `charge` | (unset → 0) | wind-up, 0..1 |
| `charging` | (unset → 0) | 1 while the potato is being wound up |
| `lobPow`, `lobDist` | (unset) | the last throw's power and distance |
| `punch` | (unset) | punch timer, from `T.punchTime` |
| `punched` | (unset) | 1 once this punch has landed |
| `click` | 0 | dry-fire click countdown |
| `dryHint` | 0 | seconds to show "need a spud" |
| `cooldown` | 0 | fire-rate gate; may go to −dt, never lower |
| `muzzle` | 0 | flash time left |
| `mdx`, `mdy` | 0, 1 | which way the flash points |
| `gun` | 0 | which of two guns fires next |
| `lastGun` | 0 | which gun fired last (the flash is drawn there) |
| `firing` | 0 | 1 while fire is held (the body turns to the shot) |
| `adx`, `ady` | 0, 1 | the last aim direction while firing |
| `fx`, `fy` | 0, 1 | facing |
| `tx`, `ty` | 0, 0 | the landing spot (launcher, potato) |
| `aimOn` | 0 | 1 when the landing ring should be drawn |
| `lobHeld` | 0 | launcher on a stick: aiming, fire on release |
| `tapFire`, `lastTap` | (unset) | launcher touch-tap firing |
| `shots` | 0 | shots fired, all weapons (the guest's flash is keyed off it) |
| `kills` | 0 | kills (bullets and rockets only, see §17) |

### 3.2 In the world (`buildWorld`, L6029)

| field | start | meaning |
|---|---|---|
| `bullets` | `[]` | `{owner, x, y, vx, vy, life, kb, size, dmg, spud, rot}` |
| `husks` | `[]` | thrown potatoes: `{owner, x, y, vx, vy, rot, spin, life}` (spent) or `{owner, whole:true, lob:true, x, y, dz, vz, vx, vy, dmg, pow, rot, spin, life}` (whole) |
| `rockets` | `[]` | `{owner, sx, sy, h0, tx, ty, t, H, id}` |
| `blasts` | `[]` | `{x, y, t, id}` |
| `blastId` | 0 | id counter for rockets and blasts (the smoke trail is keyed by rocket id) |
| `nuke` | `null` | `{x, y, t, phase:'fall'|'boom'}` |
| `plants` | `[]` | `{x, y, t, wob}`; ready when `t ≥ T.spudGrow` |
| `plantTimer` | 0 | seconds to the next wild sprout (run only) |
| `vendSold` | false | launcher bought this wave |
| `shake` | 0 | screen shake, decays 90/s |
| `freeze` | 0 | hit-stop seconds |
| `events` | `[]` | `[kind, x, y]` effects for the network (max 40 between snapshots) |

Also outside the world: `RAIN` (`L9993`, potatoes in the air from the rope or a thrown potato that didn't burst),
`banner` (`L6876`, `{text, until}` in `performance.now()` ms), `HOTBAR` (`L9881`), `MUZZLE_BY_CHAR` and `TOUCHED`
(`L6608`), the smoke puffs (`SMOKE`, `L11441`), `FP_TRACERS` (`L4232`), `lobHint` (`L6877`), `cal` (`L8578`,
calibration: `{on, oct, i, gun}`).

### 3.3 Who sets what, and when

- **New player** (`newPlayer`, L711): as in §3.1.
- **Lobby** (`fillLobby`, L733, on every new world): every player gets `weapon = 'blaster'`, `blasters = 1`,
  `rockets = 0`, `dump = 0`, `ammo = T.spudPellets × 2` (20), `coins = max(coins, T.lobbyCash, T.testCash)`.
- **Start of a run** (`startGame`, L13549), per player: `rockets = 0`, `dump = 0`, `buy = 0`, `weapon = 'spud'`,
  `blasters = 0`, `ammo = max(ammo, T.spudPellets × T.spudStart)` (so the 20 from the lobby come with you),
  `reload = 0`, `wTime = 0`, `coins = T.testCash`. The world: plants cleared, `plantTimer = 1.5`, then three plants
  already growing: `plantSpud(world, 0.3)`, `(0.6)`, `(0.9)`.
- **Restart** (`restartGame`, L13541): a fresh `newWorld()` (so back to the lobby state).
- **Death** keeps the weapon and ammo. `startWave` (L6575) revives the dead with weapons untouched.

---

## 4. Getting and losing weapons

`hasWeapon(p, id)` (L9888): `spud`, `fists`, `lob` always; `blaster` if `p.blasters`; `shotgun` if `p.wTime > 0`;
`launcher` if `p.rockets > 0`.

`giveWeapon(p, id)` (L6878):
```
p.weapon = id
p.wTime  = id == 'shotgun' ? T.shotgunTime : 0      // note: giving anything else zeroes the shotgun clock
if id == 'launcher': p.rockets = T.launcherRounds
if id == 'blaster':  p.blasters = 1
if id != 'spud':     banner = { text: WEAPONS[id].name.toUpperCase() + '!', until: now + 1400 }
```
Banners: "BLASTERS!", "SHOTGUN!", "NUKE LAUNCHER!", "FISTS!", "POTATO!".

Prizes (`award`, L6278; the slot machine spec owns the machine):
- `blasters` (REAL GUNS!): if `p.blasters` already, `p.ammo = min(T.spudMaxAmmo, p.ammo + T.spudPellets × 2)`
  instead; else `giveWeapon(p, 'blaster')`.
- `shotgun` (SHOTGUN!): `giveWeapon(p, 'shotgun')`.
- `clear` (SCREEN CLEAR): `w.nuke = {x: ARENA.w/2, y: ARENA.h/2, t: 0, phase: 'fall'}` and the falling whistle (§8.8).
- The award banner (`prize.label`, 1600 ms) is set first, then `giveWeapon`'s own banner replaces it.

Buying the launcher (`stepBase`, L7253; the vending machine spec owns the machine and its drawing): each step,
if `vendHere(w)` (`T.vendShow && w.started`: **only in a run**, b215) and `!w.over && !w.vendSold && !secret` and
`p.weapon != 'launcher'` and `p.coins ≥ T.vendPrice` and no move input and not shooting and within `T.vendRadius`
(56) of `vendPos(w)` = `(ARENA.w × T.vendX, ARENA.wall + 54 + T.vendDrop)` = (705.2, 154), then `p.buy += dt`; at
`T.vendHold` (0.8 s): `buy = 0`, `coins −= 2500`, `vendSold = true` (in a run), `prevWeapon = weapon`,
`giveWeapon(p, 'launcher')`, `cooldown = 0.35`, a floater `-$2500` (`#e0473f`) at the machine's y − 40, sounds
`sTone(0.08, 500→900, 0.2, square)` + `sTone(0.25, 90→60, 0.3, square)`. Otherwise `buy = 0`. `startWave` sets
`vendSold = false` (restocked every wave).

Losing them:
- **Shotgun clock** (L7221): only while `w.started`: `wTime −= dt`; at 0, if holding the shotgun, switch to
  `blaster` if `p.blasters`, else `spud`. The lobby never runs the clock.
- **Empty launcher** (L7243): firing the last rocket sets `dump = 0.7`. When it runs out: if still holding the
  launcher, switch to `blaster`/`spud` as above; banner "EMPTY!" for 1000 ms; `sTone(0.05, 700→300, 0.15, square)`.
  While `dump > 0` you can't fire or switch.

Switching (L7206), before anything else for that player in the step: if `inp.wsel` names a weapon, isn't the one in
hand, `hasWeapon`, and not `dump` and not `spin` (pulling the slot machine): `weapon = wsel`, `lobHeld = 0`,
`aimOn = 0`, `sTone(0.04, 520→880, 0.08, square)`. Switching does **not** clear `reload`, `pickup`, `throw`,
`charging` or `charge` (see §17).

---

## 5. What happens in a step (`stepBase`, L7160): the weapon parts, in order

1. **Hit-stop**: if `w.freeze > 0`: `freeze −= dt` and the whole step is skipped.
2. `w.t += dt`.
3. **For each player:**
   1. Build `inp`. Carrying Gothica, holding a plate, sitting, on the bench / leg press / in bed: `shoot = false`
      (and `roll = false`). Mid-air off the trampoline (b327): no steering, **can still shoot**.
   2. Weapon switch (`inp.wsel`), §4.
   3. Timers that run even when dead: `iframe`, `muzzle = max(0, muzzle − dt)`,
      `cooldown = max(cooldown − dt, −dt)` ("never bank more than one frame of credit: otherwise a roll or a
      stint dead lets the gun dump 4 rounds in one frame afterwards").
   4. Dead: stop here for this player.
   5. Shotgun clock; spin (slot machine: no shooting while it turns, `continue`); empty-launcher `dump`; buying the
      launcher; starting a slot spin; the dive tower (`continue` while diving: no shooting).
   6. Movement intent, starting a roll. Blown away (`launch > 0`): `continue`, no shooting. Rolling (`roll > 0`):
      `continue`, no shooting. Then acceleration/friction, which also sets `fx, fy` to the move direction.
   7. **Aim**: `ax, ay = inp.ax, inp.ay`; `alen = |(ax, ay)|`; `firing = inp.shoot ? 1 : 0`; if `alen > 0.001`,
      `fx, fy = (ax, ay)/alen`.
   8. Launcher block (if the weapon is the rocket), §8.7, else `aimOn = 0, lobHeld = 0`.
   9. Potato-throw block (if the weapon is `lob`), §8.5; **else** if `inp.shoot` and not the launcher: the normal
      fire block, §8.1; **else** if `cooldown < 0`: `cooldown = 0`.
   10. Speed cap, move, walls (recoil and the punch lunge were added to `vx, vy` above, so they move him this step).
4. Wave director, enemies, ...
5. **Bullets** (§9.1), then shrapnel, the janitor.
6. **The nuke** (§8.8), **`stepRockets`** (§8.7), `w.shake = max(0, shake − 90·dt)`, **`stepPlants`** (§9.4),
   Gothica, **`stepRain`** (§9.5), the gym, blackjack.
7. **Husks in flight** (§9.2).
8. **Player action timers** (L8094), each player: punch (lands the punch), throw (releases the husk/potato, then
   queues a reload), reload (jab sound), `dryHint`, pickup (then queues a reload). §8.
9. Lobby playground (dummies come back up), solids, floaters, corpses, blood, coins, particles.

So a bullet fired this step moves its first `dt` in the same step.

---

## 6. Input: what aims and what fires

The input for a player is `{mx, my, ax, ay, shoot, roll, st, tc, tap, tx, ty, lt, lx, ly, wsel, sq, bq, ba}`
(`localInput0`, L8985; the guest's arrives as `t:'in'`, L10845). Weapon fields:

- `ax, ay`: the aim. **Not normalised** when it comes from the mouse: it's `cursor_world − player`, so its length is
  the distance to the cursor (the launcher and potato use that as range).
- `shoot`: fire held.
- `st`: the aim is a stick (pad right stick, touch aim stick); its length 0..1 is a push amount.
- `tc`: this device has seen touch (`touchSeen`).
- `tap, tx, ty`: launcher touch: a tap counter (new value = new shot) and the tapped world spot.
- `lt, lx, ly`: potato touch: a finger on the landing spot.
- `wsel`: a weapon id to switch to (from the bar, keys 1–6, the pad).

Player 0's sources, first match wins (L9008):
1. **Touch, potato**: the aim-side finger is down and has moved < 12 px, and you hold the potato →
   `lt = screenToWorld(finger)`, `shoot = true` (winding up on that spot).
2. **Touch, potato tap**: `lobTap` (set by a quick tap on the move side: up within 250 ms, moved < 12) is live for
   130 ms → `lt` = the spot, `shoot = true`.
3. **Touch aim stick** active → `shoot = true`, `st = true`, `ax, ay = stick` (−1..1 each, max radius 52 px =
   `STICK_MAX`), zeroed under 0.06.
4. **Pad right stick** (deadzone 0.22) → `st = true`, `ax, ay = stick`, `shoot = RT` (b317: the stick only aims;
   RT fires). The last stick aim is remembered in `PAD.aim[0]`.
5. **RT alone** (and the mouse hasn't moved in 1.5 s) → `shoot = true`, `st = true`, aim = `PAD.aim[0]`.
6. **Mouse** over the canvas → `shoot = mouse.down || RT`, `ax, ay = screenToWorld(mouse) − player` (on the
   guest, the player is taken from the snapshot moved on by its age).

`tapShot` (launcher touch): a quick tap (up within 300 ms, moved < 12 px, launcher in hand with rockets) sets
`tapShot = {id: id+1, x, y, until: now + 150}`; while live, `inp.tap/tx/ty` are sent ("held for a moment so a
network update can't miss it").

Player 1 on the same keyboard (`localInput1`, L9038): arrows move, **Space** fires (no aim: `ax = ay = 0`, so he
fires the way he faces), Ctrl rolls; or pad 1 (right stick aims with `st`, RT fires). Player 1 has **no weapon
switching** (only player 0's bar and pad buttons feed `wsel`).

Weapon selection:
- Keys **1–6** (not repeats, L8630): `selectSlot(i)`.
- Pad 0: **LB** (button 4) or **d-pad left** (14): previous owned weapon in bar order; **Y** (3) or **d-pad right**
  (15): next (`padCycleWeapon`, L8940).
- Tap a bar slot; drag one onto another to swap (§12).
- `selectSlot(i)` (L9936): if `hasWeapon(p, HOTBAR.order[i])`, `HOTBAR.want = id` (picked up as `inp.wsel` by the
  next `localInput0`); else the slot flashes red for 350 ms.
- b293: if a frame was too short to run a sim step (over 120 fps), the `wsel` (and a roll) is carried into the
  next frame's input (`carryInput`, L12704).

First person changes the input: §13.2.

---

## 7. Facing while shooting

`facingVec(p)` (L9563) decides which way the body is drawn: if `p.firing` and `(adx, ady)` is non-zero, that;
else if moving, the move input; else `(fx, fy)`. So the body turns to the shot while fire is held. `sectorOf`
(L9575) turns it into one of 8 sectors with hysteresis (hold the current sector until the angle is more than
22.5° + 10° from its centre). The barrel map, though, uses `octOf(ax, ay)` (L6850), plain rounding, no hysteresis.

---

## 8. Firing each weapon

### 8.1 The normal fire block (blasters, shotgun, spud gun, fists) (L7485)

```
if inp.shoot (and not the launcher, and not lob):
    if alen > 0.001: ax, ay /= alen else ax, ay = normalise(fx, fy)
    fx, fy = ax, ay;  adx, ady = ax, ay
    if cooldown <= 0:
        if reload > 0 or pickup > 0 or throw > 0 or dump > 0:  nothing   (mid-jab, bent over, binning a husk)
        elif weapon.ammo and ammo < 1:                          dry fire (below)
        else: firePlayer(w, p, ax, ay); cooldown += 1 / wFireRate(p)
elif cooldown < 0: cooldown = 0
```

Dry fire: `click −= 1/120`; `dryHint = 1.2`; if `click ≤ 0`: `click = T.spudEmpty` and
`sTone(0.03, 900→500, 0.12, square)`; then `cooldown += T.spudEmpty`. (Because this block only runs when the
cooldown is up, i.e. every 0.18 s, `click` falls by 1/120 per 0.18 s: you hear the first click at once and then one
about every 4 s. See §17.)

`firePlayer(w, p, ax, ay)` (L6889). Nothing happens while calibrating (`cal.on`). Then by weapon:

### 8.2 Blasters (and the shared bullet code)

```
base    = atan2(ay, ax)
spread  = (g.spread ?? T.spread) degrees → radians      // blaster: T.spread 4
speed   = g.speed || T.bulletSpeed                       // 620
life    = g.life  || T.bulletLife                        // 1.4
pellets = g.pellets || 1
gun     = (pellets > 1 or rocket) ? 0 : (T.dualGuns ? p.gun : 0)   // two-handed weapons use gun 0
p.lastGun = gun
if pellets == 1: p.gun = p.gun ? 0 : 1                   // alternate hands (blasters AND the spud gun)
m = muzzlePoint(p, ax, ay, gun)                           // §10
for i in 0..pellets-1:
    t = pellets == 1 ? 0 : (i/(pellets-1) - 0.5) * 2      // -1..1 across the cone
    a = base + t*spread*0.5 + (rnd-0.5)*spread*0.35
    bullets.push({ owner: p.id, x: m.x, y: m.y,
        vx: cos(a)*speed*(0.9 + rnd*0.2),                 // NB: separate random factors for vx and vy
        vy: sin(a)*speed*(0.9 + rnd*0.2),
        life, kb: g.knockMul || 1, size: g.size || T.bulletSize,
        dmg: g.dmgFrac ? max(0.1, T.enemyHp*g.dmgFrac) : (g.dmg || 1),
        spud: g.jab ? 1 : 0, rot: rnd*6.28 })
if g.ammo: ammo = max(0, ammo - 1)
if g.jab: (spud gun reload cycle, §8.4)
p.vx -= ax*(g.recoil ?? T.recoil);  p.vy -= ay*(...)      // blaster recoil T.recoil 60
sound: g.jab ? SFX.pop : pellets > 1 ? SFX.shotgun : SFX.shot
p.muzzle = g.flashTime || 0.055;  p.mdx, p.mdy = ax, ay;  p.shots++
```
The order of `rnd` calls per pellet is: angle jitter, vx factor, vy factor, rot. (Keep it if you want the same
shots from the same seed.)

Blaster numbers: 9.5 shots/s (cooldown 0.105 s), ±0.7° jitter, 620 ± 10% speed, 1.4 s life (about 870 units),
size 4, damage 1, knock ×1, recoil 60, flash ×1.0 for 0.055 s, guns alternate.

### 8.3 Shotgun

Five pellets, cone 20°: centre offsets −10°, −5°, 0°, +5°, +10°, each ±3.5° jitter; speed 520 ± 10%; life 0.42 s
(about 220 units); size 5; damage 1 each; `kb` 2.2 (over 1.5, so hits and kills count as **big**: bigger blood,
`killShakeBig`, big corpses); recoil 220; 2.4 shots/s (0.417 s); always gun 0; flash × `T.shotgunFlash` 1.7 for
0.075 s; `SFX.shotgun`.

### 8.4 Spud gun

Bullet: speed 360 ± 10%, life 0.9 s (about 325 units), size 4, spread 4° (±0.7° jitter), damage
`max(0.1, 3 × 0.5)` = 1.5, `kb` 0.8, recoil 190 ("kicks like a mule for a toy"), flash ×0.7 for 0.05 s, `spud: 1`
(drawn as a potato chunk), `SFX.pop`, guns alternate (but the spud barrel maps put both guns on the same spot for most
facings).

After the ammo is taken (`ammo −= 1`), the **jab cycle**:
```
if ammo > 0 and ammo % T.spudPellets == 0:  throw = T.spudThrow; threw = 0    // a potato is spent: chuck the husk
elif ammo == 0:                             throw = T.spudThrow; threw = 0    // the last one: chuck it too
else:                                       reload = T.spudReload             // jab the next pellet in
```
`fireRate` 8 makes the cooldown 0.125 s, but the next shot also waits for `reload` (0.42 s) to finish: **the jab
between every shot is the fire rate**. Every 10th shot is followed by the husk throw (0.5 s) and then a jab (0.42 s)
if there's ammo left. Firing is blocked while `reload`, `pickup` or `throw` is running.

Timers, in the player-timer pass (L8101):
- **throw**: counts down. Release when it crosses `T.spudThrow × (1 − 3/5)` = 0.2 s left (so 0.3 s in, "three
  fifths through", the release frame) and `!threw`: `threw = 1`; with `f = facingVec(p)` (unit):
  - not a whole potato (the spent husk): push `{owner, x: p.x + f.x·14, y: p.y − 14 + f.y·8,
    vx: f.x × T.spudThrowSpd, vy: f.y × T.spudThrowSpd, rot: rnd·6.28, spin: (rnd − 0.5)·22, life: 1.2}`.
  - a whole potato: §8.5.
  - Sound: `sNoise(0.08, 900, Q 1.4, 0.16, bandpass → 300)`.
  - When `throw` reaches 0: if `ammo > 0` and the weapon in hand has `jab`: `reload = T.spudReload`.
- **reload**: counts down; the stab lands at `T.spudReload × (1 − 2.5/6)` = 0.245 s left (2.5 frames into the
  6-frame jab): `SFX.jab()`.
- **dryHint**: counts down to 0.
- **pickup**: counts down; at 0, if the weapon in hand has `jab`: `reload = T.spudReload` (jab the new potato in).

Ammo comes from potatoes on the floor (§9.4): walking over a ready one adds `T.spudPellets` (10) up to
`T.spudMaxAmmo` (200, "twenty whole potatoes", b170) and starts `pickup` (0.36 s).

Dry: firing with `ammo < 1` → click and "need a spud" (§8.1, §11.6).

### 8.5 The potato throw (`lob`) (L7450)

Runs instead of the normal fire block when the `lob` weapon is in hand. Hold fire to wind up, let go to throw.

```
busy = reload > 0 or pickup > 0 or throw > 0
dir = alen > 0.001 ? (ax, ay)/alen : normalise(fx, fy)
dist:  st (a stick)  → T.lobNear + (T.lobFar − T.lobNear) × clamp((alen − 0.15)/0.8, 0, 1)
       mouse (alen>0) → min(alen, T.lobFar)
       else (keys)   → T.lobNear
if inp.lt (a finger on the spot): d = (lx − x, ly − y); if |d| > 1: dir = d/|d|; dist = min(|d|, T.lobFar)

if shoot and !busy and ammo >= T.spudPellets:           // winding up
    charge = min(1, charge + dt / T.lobCharge);  charging = 1
    fx, fy = adx, ady = dir;  firing = 1
    m = ARENA.wall + 6
    tx = clamp(x + dir.x·dist, m, worldW − m);  ty = clamp(y + dir.y·dist, m, worldH − m)
    aimOn = 1                                            // the landing ring
elif charging and !busy:                                 // let go: throw
    charging = 0;  lobPow = 0.2 + 0.8·charge;  charge = 0;  aimOn = 0
    tl = |(tx, ty) − (x, y)|;  if tl > 1: dir = that direction
    lobDist = max(20, tl);  fx, fy = dir
    firePlayer(w, p, dir)
elif shoot and !busy and ammo < T.spudPellets:           // nothing whole left
    click −= 1/120;  dryHint = 1.2
    if click <= 0: click = T.spudEmpty; sTone(0.03, 900→500, 0.12, square)    // a click every 0.18 s here
else: charging = 0; charge = 0; aimOn = 0
```
`worldW/worldH` are the yard's size (2003 × 1998) in the lobby (`lobbyTall`), else the arena's (860 × 520).
A full wind-up takes `T.lobCharge` 0.3 s (b180/b181: was 1.1, then 0.55). A one-step tap gives power 0.22.

`firePlayer` for `lob` (L6900): if `ammo < 10`, nothing. Else `ammo −= 10`; `throw = T.spudThrow` (0.5),
`threw = 0`, `throwWhole = 1`, `throwPow = lobPow || 0.5`, `throwDx, throwDy = dir`,
`throwDist = lobDist || T.lobNear`, `throwTx, throwTy = tx, ty` ("the spot itself: he may run before it leaves his
hand"); `fx, fy = dir`; `shots++`. No cooldown, no flash, no sound yet.

At the release point of the throw timer (0.3 s later), the whole potato (L8111):
```
dist = throwDist; (tx, ty) = (throwDx, throwDy)
if throwTx defined: d = (throwTx − x, throwTy − y); if |d| > 8: dist = |d|; (tx, ty) = d/|d|   // re-aim from where he is now
pow = throwPow;  tf = 0.78 − 0.33·pow  (flight time: 0.714 s for a tap, 0.45 s at full power);  G = 1000
husks.push({ owner, whole: true, lob: true,
    x: x + tx·12, y: y + ty·6, dz: 28, vz: G·tf/2 − 28/tf,
    vx: tx·(dist − 12)/tf, vy: ty·(dist − 6)/tf,          // lands exactly on the spot after tf seconds
    dmg: T.enemyHp × T.spudThrowFrac × T.lobWhole × (1 + (T.lobPowDmg − 1)·pow),   // 6.6 × (1 + 0.5·pow)
    pow, rot: rnd·6.28, spin: (rnd − 0.5)·(14 + 16·pow), life: 3 })
sTone(0.12, 300 + 300·pow → 700 + 400·pow, 0.12, triangle)    // plus the throw whoosh
```
In flight it falls with gravity 1000 (§9.2). It hits the first enemy it passes low enough to touch; at full power
(`pow ≥ 0.98`) it bursts (`potatoSplat`) on that hit or on landing; otherwise on landing it bounces and lies there as
a ready potato you can pick up again (§9.5). In water it splashes and is gone.

`potatoSplat(w, x, y, owner)` (L6972): `R = T.splatRadius` (72).
- Effects: `burst(16, '#e9c98f', 280)` (flesh), `burst(10, '#8a5a2b', 200)` (skin), `fx(HIT)`,
  `shake = max(shake, 5)`, floater `SPLAT!` at y − 30 in `#e9c98f`, sound `sNoise(0.12, 500, 1.3, 0.3, lowpass → 500)`
  + `sTone(0.06, 140→60, 0.2, sine)`.
- Every enemy not spawning within `R + eRad`: `f = min(1, d/R)`;
  `hp −= max(0.1, T.enemyHp × T.splatDmg × (1 − 0.7f))` (2.7 at the centre, 0.81 at the edge); `flash = 0.08`;
  `stun = max(stun, T.stagger)`; knock `T.knockback × T.splatKnock × (1 − 0.5f) / mass` outwards (straight up the
  screen, `(0, −1)`, if dead centre). Killed: shrapnel if a brute (`burstShrapnel`) else `fx(KILL)`;
  `makeCorpse(w, e, u·200, false)`; `shake = max(shake, T.killShake)`; `killBurst(..., u·200, false)`; `splat`;
  `payKill(w, x, y, type, owner ?? −1)`; remove.
- Lobby dummies within `R + 14` (not down): `hp −= 1`, `flash = 0.1`, `wob = 1`, `fx(HIT)`.

### 8.6 Fists (L6892)

`firePlayer`: `punch = T.punchTime` (0.24), `punched = 0`; lunge `vx += ax·170, vy += ay·170`; `fx, fy = ax, ay`;
`shots++`; `sNoise(0.07, 400, 1.2, 0.12, bandpass → 120)` (the swing). Cooldown `1/3.2` = 0.3125 s. No flash.

The punch lands in the timer pass (L8095) when `punch` crosses `T.punchTime × 0.55` (0.132 s left, so 0.108 s in):
`punchLand(w, p)` (L7010):
```
f = normalise(fx, fy);  hit point h = (x, y) + f × T.punchReach × 0.6     // 24 ahead
each enemy (not spawning) within T.punchReach × 0.7 + eRad (28 + eRad) of h:
    hp −= max(0.1, T.enemyHp × T.punchDmg)                                // 2.1
    flash = 0.08;  stun = max(stun, T.stagger × 1.5 / (T.staggerMass ? mass : 1))
    v += f × T.knockback × T.punchKnock / mass                            // 476 / mass
    fx(HIT) at e − f × eRad × 0.5
    killed: as the splat, with direction f·200, owner p.id
each lobby dummy within 28 + 14 of h (not down): hp −= 1, flash 0.1, wob 1, fx(HIT)
if anything was hit: shake = max(shake, 3); sNoise(0.06, 250, 1.6, 0.25, lowpass → 400) + sTone(0.05, 110→60, 0.18, sine)
```
Every enemy in reach is hit (not just the nearest).

### 8.7 The nuke launcher (L7392, L6920, L7052–L7145)

**Aiming** (every step while the launcher is in hand, alive and not rolling):
```
f0 = |(fx, fy)| or 1
if st (stick):   live = alen > 0.25;  dir = live ? (ax,ay)/alen : (fx,fy)/f0
                 dist = T.lobMin + (T.lobMax − T.lobMin) × clamp((alen − 0.15)/0.8, 0, 1)
elif alen > 0:   live = true; dir = (ax,ay)/alen; dist = min(alen, T.lobMax)        // mouse: the cursor
else:            live = !inp.tc; dir = (fx,fy)/f0; dist = T.lobDefault             // keyboard: 220 ahead; touch: nothing yet
m = ARENA.wall + 6
if inp.tap and inp.tap != lastTap:                    // touch: tapped a spot, aim there and fire
    lastTap = tap; lobHeld = 0
    tx, ty = clamp(inp.tx, inp.ty) to [m, worldW − m] × [m, worldH − m]; aimOn = 1
    if |(tx,ty) − (x,y)| > 1: dir = towards it
    tapFire = 1
elif lobHeld and !st:                                  // stick just let go: fire where it was pointing
    dir = (adx, ady)                                   // (tx, ty) keep their last value
else:
    tx, ty = clamp(x + dir.x·dist, y + dir.y·dist);  aimOn = live
fx, fy = adx, ady = dir
fire = false
if st and !tapFire:  if live: lobHeld = 1, firing = 1  else lobHeld = 0   // back to the middle: cancelled
else:
    if tapFire: fire = true; tapFire = 0
    elif lobHeld: fire = true; lobHeld = 0
    elif shoot: fire = true
    firing = shoot
if cooldown > 0: tapFire = 0                           // a tap during the cooldown is lost
elif fire and dump <= 0 and rockets > 0: firing = 1; firePlayer(w, p, dir); cooldown += 1/T.launcherRate   // 0.909 s
elif cooldown < 0: cooldown = 0
```

**Firing** (`firePlayer`, rocket path): if `rockets ≤ 0`, nothing. `gun = 0`; `m = muzzlePoint(p, dir, 0)`.
```
dist = |(tx, ty) − (x, y)|
rockets.push({ owner: p.id, sx: m.x, sy: p.y, h0: max(0, p.y − m.y),      // ground point under the muzzle; its height
               tx, ty, t: 0,
               H: T.lobHeight × (0.35 + 0.65 × min(1, dist / T.lobMax)),   // 38.5 .. 110
               id: ++w.blastId })
rockets −= 1; if rockets <= 0: dump = 0.7                                   // "one beat to realise, then it's gone"
vx −= dir.x × T.launcherRecoil; vy −= dir.y × 320
shake = max(shake, 6)
fx(LAUNCH) at m − dir·10
sfxRocket()
muzzle = 0.12; mdx, mdy = dir; shots++
```

**Flight** (`rocketAt(r, t)`, L7052): every rocket takes `T.lobTime` (0.75 s) whatever the range.
```
D = max(0.05, T.lobTime);  s = clamp(t/D, 0, 1)
ground = (sx + (tx − sx)·s, sy + (ty − sy)·s)
h      = h0·(1 − s) + 4·H·s·(1 − s)
ground velocity = ((tx − sx)/D, (ty − sy)/D)
dh/dt  = (−h0 + 4·H·(1 − 2s)) / D
screen direction (height counts as up): (vx, vy − dh/dt); if its length < 1: (0, s < 0.5 ? −1 : 1)
ang = atan2 of that
```
`stepRockets` (L7064): `t += dt`; at `t ≥ T.lobTime`: remove and `detonate(w, tx, ty, owner, tx − sx, ty − sy)`.
Then each blast: `t += dt`, removed at `T.blastTime` (0.6). Rockets don't hit anything on the way: they always land
on the spot.

**Detonation** (`detonate`, L7080): `R = T.blastRadius` (110, "220 across: it cost $2500, it should feel it").
```
blasts.push({x, y, t: 0, id: ++blastId});  shake = max(shake, 18);  freeze = max(freeze, 0.06)
fx(BLAST); sfxBlast()
each enemy (not spawning) within R + eRad:
    f = min(1, d/R);  hp −= T.enemyHp × T.blastDmg × (1 − f·(1 − T.blastEdge))     // 12 → 4.2
    flash = 0.1
    dead: brute → burstShrapnel else fx(KILL); makeCorpse(dx||vx, dy||vy, big=true); killBurst(big=true);
          splat; payKill(owner); remove; shooter.kills++
    alive: push T.blastPush × (1 − 0.5f) / mass outwards; stun = max(stun, 0.6)
lobby only (!started):
    dummies within R + 16 (not down): hp = 0; down = T.dummyRespawn; killBurst at (d.x, d.y − 14), big; splat at (d.x, d.y + 8)
    cans within 2.5R: v += outward × 700; spin = 25
every live player within R × T.blastSelf (154):                 // you: not hurt, thrown across the room
    k = 1 − d/reach
    u = outward (or, dead centre, opposite to the rocket's travel)
    v = u × T.blastYeet × (0.4 + 0.6k)                           // replaces his velocity: 248 .. 620
    roll = 0; launch = max(launch, 0.25 + 0.5k); iframe = max(iframe, 0.6)
```
`launch` is the player's "blown away" state (owned by the player/janitor spec: no control, drag `T.launchDrag`,
bounces off walls).

### 8.8 The nuke (SCREEN CLEAR) (L8000)

Started by the slot prize `clear`, or debug key **N** (`dropTestNuke`, L13660, run only, one at a time):
`w.nuke = {x: 430, y: 260, t: 0, phase: 'fall'}`, plus `SND.whistle = startWhistle(T.nukeFall)` (any old whistle
stopped).

Each step: `t += dt`.
- `fall` and `t ≥ T.nukeFall` (1.9): `phase = 'boom'`, `t = 0`, `shake = T.nukeShake` (26),
  `freeze = max(freeze, 0.05)`; whistle stopped; the `nuke` clip (gain 1.0) or the fallback
  `sNoise(1.1, 700, 0.7, 0.85, lowpass → 60)` + `sTone(0.9, 90→26, 0.5, sawtooth)`. Every enemy dies:
  shrapnel/`fx(KILL)`, `makeCorpse(e − nuke, big)`, `killBurst(big)`, `splat`, `payKill(owner −1)`; enemies cleared.
  Each live player: `push = max(0, 1 − d/420) × 520` outwards added to `v`, `iframe = max(iframe, 0.5)`.
- `boom` and `t ≥ T.nukeBoom` (0.85): `nuke = null`.

---

## 9. Everything in flight, each step

### 9.1 Bullets (L7688)

For each bullet (newest first): `old = (x, y)`; `x += vx·dt`, `y += vy·dt`; `life −= dt`. Then, in this order:

1. **The janitor** (if he's about and not `spent`): segment `old→new` against the circle at `(jn.x, jn.y − 16)`
   radius 20 (`segmentHit`). Hit: `fx(HIT)` at the bullet, the bullet is removed, his reaction (janitor spec), and
   the loop moves on.
2. **Enemies**: among enemies not spawning, the one the segment reaches first, using circle radius
   `eRad(e) + T.bulletSize/2` (note: `T.bulletSize`, not this bullet's size). Hit:
   ```
   bullet moved back to the touch point
   hp −= dmg;  flash = 0.08;  stun = max(stun, T.stagger / (T.staggerMass ? mass : 1))
   v += bulletDir × T.knockback × kb / mass                  // brutes barely flinch
   fx(HIT) at the bullet; spray(w, x, y, vx, vy, kb > 1.5)   // blood, big for the shotgun
   dead: big = kb > 1.5
         brute → burstShrapnel else fx(KILL)
         makeCorpse(w, e, vx, vy, big); shake = max(shake, T.killShake × (big ? T.killShakeBig : 1))
         killBurst(w, e.x, e.y, vx, vy, big); splat; payKill(w, x, y, type, owner); remove; owner.kills++
   ```
   A bullet stops at the first enemy (no piercing).
3. **Lobby props** (only before the run starts), if no enemy was hit:
   - dummies (not down): within 20 of `(d.x, d.y − 14)` ("the sack, not the post"): `hp −= 1`, `flash 0.08`,
     `wob 0.5`, `fx(HIT)`, `spray(big = kb > 1.5)`. At 0: `down = T.dummyRespawn` (2.5),
     `killBurst((d.x, d.y − 14), big)`, `splat((d.x, d.y + 8))`, the shooter gets **$3** with a floater `$3` in his
     colour at y − 20. A dummy stops the bullet.
   - cans within 10: `v += dir·260`, `spin = (rnd − 0.5)·30`, `fx(WALL)`; stops the bullet.
4. **Walls**: in the lobby (`lobbyTall`), outside every `lobbyAreas` rectangle (`game_data.json` →
   `calls.lobbyAreas`); in the arena, outside `[18, 842] × [18, 502]`. A wall hit makes `fx(WALL)` there.
5. Removed if it hit something, hit a wall, or `life ≤ 0`.

Bullets **pass through furniture and solids** (only walls stop them), never hurt players or Gothica, and never hit
the vending or slot machine. In the slot machine's secret room, bullets within 29 of a hazard's `(x, y − 35)` are
removed and take `dmg` off it (L13886).

`segmentHit(x0, y0, x1, y1, cx, cy, r)` (L7147): returns 0 if the start is already inside, else the first `t` in
`[0, 1]` where the segment meets the circle, or `null`.

### 9.2 Husks and whole potatoes (L8044)

```
old = (x, y);  x += vx·dt;  y += vy·dt
lob (whole):  vz −= 1000·dt;  dz += vz·dt
else (husk):  vx, vy *= 0.5^dt                       // slows down
rot += spin·dt;  life −= dt;  gone = life <= 0
if lob and dz <= 0:                                  // came down on nothing
    gone
    in the pool (inWater) → fx(SPLASH)
    elif pow >= 0.98 → potatoSplat(x, y, owner)
    else → RAIN.push({x, y, dz: 0, vz, vx: vx·0.3, vy: vy·0.3, squash: 0, delay: 0, bounces: 0, rot, spin, fromThrow: true})
for each enemy (not spawning), unless already gone:
    if lob and dz > eRad·1.6 + 10: skip               // sailing over his head
    if segment old→new misses circle eRad + 6: skip
    hp −= max(0.1, dmg ?? T.enemyHp × T.spudThrowFrac × (whole ? T.lobWhole : 1))   // a husk: 3, kills a grunt
    flash = 0.08; stun = max(stun, T.stagger)
    whole: v += dir × T.knockback × 1.5 / mass
    fx(HIT) at the potato
    dead: as a bullet kill (not big), direction (vx, vy), owner
    gone; struck; stop
if struck and lob and pow >= 0.98: potatoSplat(x, y, owner)
off the floor (lobby: !lobbyInside; arena: outside [24, 836] × [24, 496]): gone
```
Husks don't hit dummies, cans or the janitor. Kills by husks, splats and punches don't add to `kills` (§17).

### 9.3 Rockets and blasts

§8.7: `stepRockets` after the nuke, each step.

### 9.4 Potato plants (`plantSpud` L5979, `stepPlants` L5994)

Nothing happens if `w.over` or the slot secret is on.
- **Wild growth, run only**: `plantTimer −= dt`; at ≤ 0: `plantSpud(w, 0)`, `plantTimer = T.spudRate` (5).
- `plantSpud(w, progress)`: if there are `T.spudMax` (6) plants, nothing. Else up to 12 tries of
  `x = m + rnd·(860 − 2m)`, `y = m + 60 + rnd·(520 − 2m − 60)` with `m = 18 + 40 = 58` ("keep clear of the slot
  machine": y from 118 to 462), retrying while within 90 of the slot machine, within 90 of the vending machine (in a
  run), within 70 of another plant, or within 60 of a player. Push `{x, y, t: progress × T.spudGrow, wob: 0}` (after
  12 failed tries it goes wherever the last try was).
- Each plant: `t += dt`, `wob = max(0, wob − dt)`. Ready when `t ≥ T.spudGrow` (9 s from sprout). A ready plant is
  picked up by the first live player who is not mid-`reload`/`pickup`/`throw`, within `T.radius + 14` (28), with
  `ammo < T.spudMaxAmmo`: `ammo = min(200, ammo + 10)`, `pickup = T.spudPickup` (0.36), the plant is removed,
  `fx(WALL)`, sounds `sNoise(0.12, 600, 1.2, 0.3, lowpass → 120)` ("shunk") + `sTone(0.08, 220→160, 0.14, triangle)`.
  You pick potatoes up with any weapon in hand.

### 9.5 Potatoes falling (`RAIN`, `pullRope` L9997, `stepRain` L10007)

`RAIN` holds potatoes in the air: ten from the gym's bell rope (lobby; the rope itself is another spec's: E at the
rope, `T.ropeCount` 10, `T.ropeCool` 20 s, each `{x: 318 + rnd·262, y: 126 + rnd·108, dz: 380 + rnd·160, vz: 0,
delay: 0.35 + i·0.12 + rnd·0.08, spin: (rnd − 0.5)·10, ...}`), and whole potatoes that landed without bursting.
Each step, after `delay` runs out: `squash = max(0, squash − 9·dt)`; `vz −= 1500·dt`; `dz += vz·dt`; `x, y += v·dt`;
`rot += spin·dt`. On reaching the floor (`dz ≤ 0`): `dz = 0`, `hit = −vz`,
`keep = [0.45, 0.36, 0.28][min(2, bounces)]`, `bounces++`; if `hit > 110` and `bounces ≤ 3`: bounce
(`vz = hit·keep`, `v = v·0.6 + (rnd − 0.5)·hit·0.08` each axis, `spin ×= 0.55`, `squash = 1`, a dust puff
`burst(3, '#b9a58a', 40)` at y + 4 if `hit > 300`). Otherwise it settles: removed from `RAIN`, clamped to
`[30, 830] × [30, 490]`; in the pool → `fx(SPLASH)`; else pushed out of the lobby's solid boxes (radius 10, lobby only)
and added as a **ready plant** `{x, y, t: T.spudGrow, wob: 0.3}`. One thud per frame for the hardest landing,
at most every 50 ms: `sNoise(0.05, 220 + hit·0.2, 1.4, min(0.22, 0.06 + hit/3000), lowpass → 300)`.

`RAIN` is not part of the world or the snapshot (the guest doesn't see the bounce, only the plant when it lands).

---

## 10. Muzzles and barrels (L6603–L6871)

A barrel is an offset from the player's position `(p.x, p.y)` (his centre; his feet are at `p.y + T.radius × 0.9`
= `p.y + 12.6`), in **screen pixels as drawn** (x right, y down), for one of 8 facings (`0=E 1=SE 2=S 3=SW 4=W
5=NW 6=N 7=NE`), two per facing (left/right gun; two-handed weapons have both the same). Because it's a screen
offset, `−y` mixes height with depth; the barrel's height above his feet is `12.6 − o.y`.

`BARREL_SETS` (L6605), one map per character **and** weapon skin: `jared, tyson, juicy, tyson2, goth, inky,
jared_shotgun, tyson_shotgun, juicy_shotgun, tyson2_shotgun, juicy_spud, tyson2_spud, juicy_launcher,
tyson2_launcher`.

`barrelKey(p)` (L6774) = `weaponOf(p).skin[p.ch]` if there is one, else `p.ch` (so fists, the blasters, and any
weapon without art for that character use the character's own map; `lob` uses the spud map for juicy/tyson2).

Building the maps (`defaultMuzzle`, L6612, run at load):
1. `buildDefault()` for every set: for each facing, `a = oct·π/4`, `(ax, ay) = (cos a, sin a)`,
   `f = (ax·T.muzzleFwd, ay·T.muzzleFwd − T.muzzleUp)`, gun 0 = `f + (−ay, ax)·T.muzzleSide`, gun 1 = `f − (−ay, ax)·T.muzzleSide`,
   rounded to 0.1.
2. `applyCalibrated()`: the hand-placed `CALIBRATED` facings (L6633) replace those, and are marked `TOUCHED`.
3. `useChar(calChar())` → `deriveMirrors` for the current player's set only: facings not `TOUCHED` are filled:
   NE = copy of E, W = `mirror(E)`, SW = `mirror(SE)`, NW = `mirror(N)`, where `mirror([a, b]) = [(−b.x, b.y), (−a.x, a.y)]`
   (flip across his centre line; hands swap over).
4. Saved tuning (`localStorage 'jucy-jared-tuning-v1'`) can replace whole maps; then three one-off fixes run while
   the saved `mv` is below their number (a fresh browser has `mv = 0`, so all of them run):
   - b156 (`mv < 1`): `juicy_spud` and `tyson2_spud`, facings SE and SW, both guns =
     `barrelFromScreen(±21, −38)` ("the spud gun's diagonal run art holds the gun higher").
   - b158 (`mv < 3`): the same two sets, N, both guns = `barrelFromScreen(10, −66)` ("straight up, spuds leave the
     top of the raised gun").
   - b157 (`mv < 2`): `juicy` and `tyson2`, NE = mirror of NW ("up-right was drawn mirrored, so its blaster muzzles
     never matched the art").
   `deriveMirrors` also runs for the set being calibrated, for player 0's character when it is picked
   (`setChar`), and for every set on "reset muzzles".

`barrelToScreen(o)` (L6856): `scale = T.radius·T.spriteScale/(14·4.6)` (1 at the defaults);
`x = o.x·scale`, `y = (o.y − 12.6)·scale + T.radius·0.9`. With the default tuning it changes nothing.
`barrelFromScreen` is its inverse.

`muzzlePoint(p, ax, ay, gun)` (L6866): `map = MUZZLE_BY_CHAR[barrelKey(p)]` (or jared's);
`pair = map[octOf(ax, ay)]`; `o = barrelToScreen(pair[T.dualGuns ? gun & 1 : 0])`; returns `(p.x + o.x, p.y + o.y)`.
**Bullets and rockets start there**, on the ground plane, so a shot fired east by Juicy starts 41.6 units *north*
of him. That is the 2D game's way of drawing "chest height"; see §18.4 for what to do in 3D.

### 10.1 The maps as the game uses them (default tuning, fresh browser)

Offsets `(x, y)` per facing; gun 0, then gun 1. Rows marked *derived* are what `deriveMirrors` makes; the HTML only
applies them when that set is the one player 0 picked or is calibrating, so a fresh game uses the *raw* value; use
the derived ones in Godot (that is the design: "calibrate four, get eight").

**jared** (all hand-placed; b249: E is the user's own drag-in)
```
E  (7,-6.4) (24,-23.4)      SE (-8,-12.5) (-16.5,-7)    S  (-20,7) (20.5,6)       SW (16.5,-7) (8,-12.5)
W  (-30,-28.5) (-13.5,-18)  NW (20,-41.5) (-22,-40.5)   N  (20.5,-42) (-20,-40.5) NE (13.5,-18) (30,-28.5)
```
**tyson**: as jared except **E (29,-27.9) (13,-10.9)**.
**tyson2**: as jared except **E (13.5,-18) (30,-28.5)** and **NE (22,-40.5) (-20,-41.5)** (b157).
**juicy** (b249: the user's drag-in for E, SE, S, SW, W)
```
E  (26.5,-41.6) (19,-33.6)  SE (-11,-29.6) (26,-33.6)   S  (-12,-33.1) (10.5,-34.6) SW (6.5,-27.6) (-25.5,-31.1)
W  (-29,-41.1) (-20.5,-35.1) NW (20,-41.5) (-22,-40.5)  N  (20.5,-42) (-20,-40.5)   NE (22,-40.5) (-20,-41.5)
```
**jared_shotgun, tyson_shotgun, juicy_shotgun, tyson2_shotgun** (two-handed: both the same)
```
E (22,-22)  SE (14,-14)  S (2,4)  SW (-14,-14)  W (-22,-22)  NW (-14,-38)  N (2,-44)  NE (14,-38)
```
**juicy_launcher, tyson2_launcher** (both the same)
```
E (31,-28)  SE (15,-13)  S (-10,-26)  SW (-15,-13)  W (-31,-28)  NW (-20,-42)  N (0,-56)  NE (21,-42)
```
**juicy_spud, tyson2_spud** (generic, plus the b156/b158 fixes)
```
E  (30,-11) (30,-25)   SE (21,-38) (21,-38)   S (-7,12) (7,12)   SW (-21,-38) (-21,-38)
W  (-30,-25) (-30,-11) N  (10,-66) (10,-66)
NW raw (-16.3,-44.2) (-26.2,-34.3), derived (-10,-66) (-10,-66)
NE raw (26.2,-34.3) (16.3,-44.2),   derived (30,-11) (30,-25)
```
**goth, inky** (generic: never calibrated)
```
E  (30,-11) (30,-25)   SE (16.3,8.2) (26.2,-1.7)   S (-7,12) (7,12)   SW (-26.2,-1.7) (-16.3,8.2)
W  (-30,-25) (-30,-11) N  (7,-48) (-7,-48)
NW raw (-16.3,-44.2) (-26.2,-34.3), derived (7,-48) (-7,-48)
NE raw (26.2,-34.3) (16.3,-44.2),   derived (30,-11) (30,-25)
```

### 10.2 Calibration (a tuning tool)

Toggled with **C** (only with the tweaks shown, b312, and not online) or the Calibrate button. While on: player 0 is
held at the arena centre facing `cal.oct`, `muzzle = 0`, `cooldown = 0`, bullets are cleared, the simulation doesn't
run, the camera is off; firing does nothing. **[** / **,** and **]** / **.** step the facing. Both barrels are drawn
as crosshairs (±11 px lines and a radius-5 circle; the active one gold `#f6d17a` 2 px, the other at 50%; labels "1",
"2"). Clicking picks the nearer barrel (`calPick`) and drags it (`calPlace`): the offset is stored with
`barrelFromScreen`, the facing marked `TOUCHED`, mirrors re-derived, and the tuning saved. A title reads
`CALIBRATING <set> — facing <East|South-East|...>  (i of 8)` (+ `· auto` if not touched) and the help line
`drag each crosshair onto a barrel  ·  [ and ] change direction  ·  C to play`. The host sends its maps to the guest
in `cfg` (§15).

---

## 11. Drawing (top-down)

### 11.1 Weapon sprite sets (what the character wears)

The skin is `weaponOf(p).skin[p.ch] || p.ch`. Sets in `assets/manifest.json` → `CHARS`:

| set | frames | size | notes |
|---|---|---|---|
| `juicy` (blasters) | `{front,diag,side,bdiag,back}_run` × 7, `*_a/_b`, `back`, `back_a/b`, `roll1..4` | 160 tall (rolls 96×96) | the blasters are part of the base art |
| `juicy_spud` (spud gun and potato) | `*_run` × 7, `*_a/_b`, `back`, `back_b`, `roll1..4`, **`reload` × 6, `reload_side` × 6, `pickup` × 4, `throw_side` × 5, `throw_front` × 5** | 160 tall | |
| `juicy_shotgun` | `front_a/b, diag_a/b, side_a/b, bdiag_a/b, back, back_b, roll1..4` | **96 tall** | no run cycle: a/b pairs |
| `juicy_launcher` | the same keys as the shotgun | 160 tall | no run cycle |
| `jared_shotgun` | a/b pairs, `back`, `overhead`, `roll1..4` | 96 | old art |
| `tyson_shotgun` | a/b pairs, `back`, `back_b`, `victory` × 4, `roll1..4` | 96 | old art |
| `tyson2`, `tyson2_spud`, `tyson2_shotgun`, `tyson2_launcher` | `recolourOf` juicy / juicy_spud / juicy_shotgun / juicy_launcher, `palette {green: 22, blue: 125, boost: 1.15}` | | made at load (below) |

Goth, Inky, Jared and Tyson have no spud or launcher sheets: they hold those weapons in their own art (their
blasters). Goth and Inky have no shotgun sheet either.

**Recolour** (`recolourImage`, L9483), for the tyson2 sets, per source image: find `top`/`bot`, the first and last
rows with any pixel of alpha > 76; for each pixel with alpha > 76, `frac = (y − top)/(bot − top)`, in HSL:
hue 75..185 with saturation > 0.2 → hue = `palette.green` (22); hue 185..265 with saturation > 0.28 and
`0.22 < frac < 0.58` (the torso band: blue is shared with the sunglasses and denim) → hue = `palette.blue` (125);
then saturation `min(1, s × boost)`, lightness kept. (Shared with the characters spec.)

**Which frame** (`drawJared`, L10475; the characters spec owns the rest of it). Weapon poses, checked in this order
after the tower fall:
1. `punch > 0` and the character's `victory` has ≥ 8 frames: `victory` frame 2, flipped if `fx < 0`. (No character in
   the manifest has 8, so in practice punches use the normal pose.)
2. `charging` and the skin has `throw_side`: `throw_side` if sideways (`|fv.x| > |fv.y| × 0.9`, `fv = facingVec`),
   flipped if `fv.x < 0`; else `throw_front`; **frame 0** (held while winding up).
3. `throw > 0` and the skin has `throw_side`: the same choice, frame `min(n − 1, floor((1 − throw/T.spudThrow)·n))`
   (5 frames over 0.5 s; the potato leaves on frame 3).
4. `pickup > 0` and `pickupSkin(p, skin)` (the skin itself if it has `pickup`, else the character's spud skin if
   that has one, so juicy/tyson2 bend down whatever they hold): `pickup` from that skin, frame
   `floor((1 − pickup/T.spudPickup)·4)`, not flipped.
5. `reload > 0` and the skin has `reload`: `reload_side` if sideways and it exists (flipped if `fv.x < 0`), else
   `reload`; frame `floor((1 − reload/T.spudReload)·6)`. **On the move** (`T.jabRun` and speed > 30): the legs come
   from the run cycle (`side_run` for `reload_side`, else `front_run`), frame `floor(odo/T.runStride) % 7`,
   stitched under the jab's top half (`jabRunImage`, below).
6. Then the usual: blown away, rolling, celebrating, or `poseFor` (directions, run cycle or a/b pairs).

`poseFor` flips with the default tuning (`gun` = the skin ends in `_shotgun`, `lnc` = ends in `_launcher`,
`alt` = juicy/tyson2/goth/inky):

| facing | frame | juicy, juicy_spud, tyson2.. | juicy_launcher, tyson2_launcher | any `_shotgun` | goth | jared, tyson |
|---|---|---|---|---|---|---|
| E | side | – | – | – | – | – |
| SE | diag | – | – | flip | flip | – |
| S | front | – | – | – | – | – |
| SW | diag | flip | flip | – | – | flip |
| W | side | flip | flip | flip | flip | flip |
| NW | bdiag | flip | flip | flip | flip | – |
| N | back | – | – | – | – | – |
| NE | bdiag | – | – | – | – | flip |

(Inky is as juicy. With no run cycle the a/b pair alternates every 26 units walked: `floor(odo/26) % 2`. The run
cycle steps a frame every `T.runStride` 13 units.)

**Size**: height `h = T.radius × T.spriteScale × CHARS[ch].scale × pscale × (alt ? T.altScale : 1)`, i.e. 80 for the
new art (160-px frames at exactly 2:1) and 64.4 for jared/tyson; width keeps the frame's aspect (× `T.altWide` 1);
feet at `p.y + 12.6`; centred on `p.x`. `pscale` for weapon skins:
- `juicy_shotgun` / `tyson2_shotgun` (`JUICY_SHOTGUN_SCALE`, L9300): front_a/b 1.1852, diag_a/b 1.2308, side_a 1.2308,
  side_b 1.2468, bdiag_a/b 1.2308, back/back_b 1.0.
- `tyson_shotgun` (`TYSON_SHOTGUN_SCALE`): front 1.0, diag_a 1.1026, diag_b 1.1125, side 1.1719, bdiag_a 1.1294,
  bdiag_b 1.0988, back/back_b 1.0787.
- `jared_shotgun` (`SHOTGUN_POSE_SCALE`): back 1.0, bdiag_a 1.0, bdiag_b 1.0105, diag_a 1.1566, diag_b 1.0549,
  front 1.1034, side 1.0.
(These were measured because the shotgun frames were padded differently; without them he grows and shrinks as he turns.)

**jabRunImage** (L10423), cached per (skin, frame, legs frame): `waistOf(image)` scans rows 40..149 for the first row
where at least `max(8, 35% of the opaque pixels)` are "shorts" coloured (`g > r+15, b > r+20, |g−b| < 35,
75 < r < 200, b > 115`) and returns `{y, cx, hw}` (centre and half width of those pixels over the next 8 rows). The
result is a canvas 40 px wider each side: rows above `top.y + 3` from the jab frame; rows below from the run frame,
shifted to line its waist up (`dy = top.y − legs.y`, `dx = top.cx − legs.cx`); then, in the first 24 rows under the
cut, the jab frame's pixels further than `max(hw) + 3` from the centre are put back on top ("hands, gun and potato
that sit beside the hips stay from the jab frame"). If either waist isn't found, no stitch (the plain jab frame).

### 11.2 Muzzle flash (L12288)

Drawn with the player (after his sprite, in the same lift for `dz`), at `m = muzzlePoint(p, normalise(fx, fy),
p.lastGun)`, while `p.muzzle > 0`:
```
dur   = flashTime || 0.055;  t = clamp(muzzle/dur, 0, 1)          // 1 at the shot
mul   = weapon == shotgun ? T.shotgunFlash : (flash || 1);  scale = mul × T.flashSize   // 13
grow  = t > 0.55 ? 1 : 0.55 + 0.8t
len   = scale·grow·(1.6 + 0.5(1 − t));  wid = scale·grow·0.62
angle = atan2(mdy || fy, mdx || fx); drawn rotated to it, at m:
  disc radius 1.5·len, #ffd479, alpha 0.22t                         (light on the floor)
  cone (len,0) (0.35wid,−wid) (−0.5wid,0) (0.35wid,wid), #ff9a3d, alpha 0.9(0.4 + 0.6t)
  cross (0.55len,0) (0,−1.15wid) (−0.45wid,0) (0,1.15wid), #ffd479, same alpha
  core (0.55len,0) (0.2wid,−0.42wid) (−0.2wid,0) (0.2wid,0.42wid), #fffbe8, alpha t
```
Flash sizes: blaster 13, spud 9.1, shotgun 22.1, launcher 28.6. Fists and potato: none.

### 11.3 Shots, potatoes, plants (renderBase)

- **Bullets** (L11838): spud bullets are a tumbling potato chunk at `(x, y)`, rotated `rot + w.t·14`: ellipse
  4.6 × 3.6 `#5a3b22` (skin), ellipse at (0.6, 0.4) 3.4 × 2.6 `#e8d3a0` (flesh), 2 × 2 square at (−1, −1)
  `#c9a56b` (a bruise). Others: a round-capped line `size` wide (4, shotgun 5) from `(x, y)` back to
  `(x − vx·0.02, y − vy·0.02)` (about 12 units for the blaster), colour `#f6d17a` (player 0) or `#a8d8ff` (player 1).
- **Husks** (L11813), with `SPUD_SPRITES[4]` (72 × 49): whole/lobbed ones get a shadow at `(x, y + 6)`,
  ellipse 12sf × 5sf, black at 0.3sf alpha, `sf = max(0.35, 1 − dz/260)`. The picture is drawn at `(x, y − dz)`,
  rotated by `rot`, **28** wide for a whole potato, **22** for a husk (height by aspect), plus four cored holes
  (radius 1.5, `rgba(47,29,16,0.9)`) at (−3,−2) (2,−3) (3,2) (−2,3) (drawn on whole ones too).
- **Plants** (L11990): stage `f = min(1, t/T.spudGrow)`; picture `SPUD_SPRITES[f ≥ 1 ? 4 : min(3, floor(4f))]`
  (0: 72×50 sprout, 1: 72×63, 2: 72×70, 3: 72×64, 4: 72×49 the potato lying there). Shadow ellipse 13 × 5 at
  `(x, y + 6)`, black 0.28. Picture 30 wide, bottom at `y + 8`. Ready: a glint, circle at `(x, y − 10)` radius
  `3 + 2g`, `rgba(255,240,180, 0.35g)`, `g = 0.5 + 0.5·sin(w.t·5 + x)`. (`wob` isn't drawn.)
- **Falling potatoes** (`drawRain`, L10069): shadow at `(x, y + 6)` 13sf × 5sf, alpha `0.28sf`,
  `sf = max(0.3, 1 − dz/300)`; picture `SPUD_SPRITES[4]` 30 wide at `(x, y − dz)`, scaled `(1 + 0.3·squash,
  1 − 0.3·squash)` then rotated by `rot`.
- Draw order in `renderBase`: ... particles, bullets/husks (with the floor things), plants, falling potatoes, the
  landing rings (§11.4), ..., players (with their flash and bars), ...; then, over everything in world space:
  rockets, blasts, the nuke, floaters; then the HUD.

### 11.4 Landing rings (`drawLobMarkers`, L11397)

`R = T.blastRadius` (110) for **both** the launcher and the potato (the potato's actual splat is 72; see §17).
`pulse = 0.5 + 0.5·sin(now_s·8)`. For each live player with `aimOn` and (launcher with rockets, or `lob` while
`charging`), in his colour (`P_COLOURS`: `#e0473f` player 0, `#4f9fe8` player 1):
- filled ellipse at `(tx, ty)`, radii `R × 0.62R`, alpha `0.14 + 0.06·pulse`;
- dashed outline `[8, 6]`, dash offset `−14·pulse`, alpha 0.85, 2 px; a cross ±7 × ±5 at the centre;
- the path: 9 squares 3 × 3 (alpha 0.35) at `s = k/10`, `k = 1..9`:
  `x = p.x + (tx − p.x)s`, `y = p.y − 30 + (ty − p.y + 30)s − 4·H·s(1 − s)` with `H = T.lobHeight × 0.6` (66).
For each rocket in flight, at its target: outline ellipse `R × 0.62R`, `rgba(224,71,63, 0.45 + 0.5s)`, 2 px; and a
filled ellipse growing to it, radii `R·s × 0.62R·s`, `rgba(224,71,63, 0.08 + 0.22s)`, `s = min(1, t/T.lobTime)`.

### 11.5 Rockets, smoke, blasts, the nuke

**Rockets** (`drawRockets`, L11445), `q = rocketAt(r, r.t)`:
- Smoke (local to each screen, not networked): the tail is at `(q.x − cos(ang)·24, q.y − q.h − sin(ang)·24)`; a puff
  every 6 px along the tail's path (max 300 puffs): position jittered ±2, velocity `((rand − 0.5)·14,
  (rand − 0.5)·14 − 6)`, radius 2.5..5, life 0.8..1.4 s, colour `#6f6f6f` or `#8a8a8a` (`#bdbdbd` after half its
  life). Drawn as a pixel cross of two rectangles (`2q × 1.4q` and `1.4q × 2q`, `q = max(2, round(r(1 + 1.6f)))`),
  alpha `0.75(1 − f)`. A trail is forgotten 1 s after its rocket goes.
- Shadow at `(q.x, q.y)`: ellipse `14sh × 5sh`, black 0.3, `sh = max(0.35, 1 − q.h/220)`.
- Picture: `ROCKET_SPRITES.lit_b` / `lit_c` alternating at 20 Hz (`floor(now·20) % 2 ? lit_c : lit_b`), 122 × 43 drawn
  at **half size** (61 × 21.5), translated to `(q.x, q.y − q.h)`, rotated by `q.ang`, drawn at `(−dw + 22, −dh/2)` (the
  nose 22 px ahead of the point; the art faces right). `cold` and `lit_a` (on the rail, ignition) are unused.

**Blasts** (`drawBlasts`, L11505), `f = min(0.999, t/T.blastTime)`:
- a ring on the floor: ellipse radius `R(0.6 + 0.5f)` × 0.55 of that, `rgba(255,200,120, 0.5(1 − f))`, 3 px;
- `NUKE_SPRITES.boom[floor(8f)]` (146 × 150), width `T.blastSize(0.55 + 0.6f)` (187 → 391), height by aspect, drawn at
  `(x − w/2, y − 0.62h)`;
- first 15%: a white disc radius `1.6R`, `rgba(255,246,224, 0.8(1 − f/0.15))`.

**The nuke** (L12584):
- falling, `f = min(1, t/T.nukeFall)`: a shadow ellipse `sr = 14 + 46f` × `0.42sr`, black `0.18 + 0.35f`, outlined
  `rgba(224,71,63, 0.35 + 0.5f)` 2 px; the bomb `NUKE_SPRITES.bomb[min(3, floor(4f))]` (bomb_0 112×128, others ~73×128),
  height `40 + 120f`, bottom at `−60 + (y + 10)f`, centred on x;
- boom, `f = min(0.999, t/T.nukeBoom)`: `boom[floor(8f)]`, width `T.nukeSize(0.55 + 0.75f)` (187 → 442), centred on
  `(x, y)`; first 22%: the whole arena white, `rgba(255,246,224, 0.85(1 − f/0.22))`.

### 11.6 Bars and words over his head, the HUD

Measured from `r = T.radius` and drawn in his lift:
- **Throw power** while `charging`: a 34 × 4 bar at `y = round(p.y + 0.9r − r·spriteScale·hpHeight) − 8`
  (p.y − 63); background `rgba(20,22,28,0.75)`; fill `#d8b878`, `charge × 34` wide; at full charge it flashes
  `#ffb070` / `#ff6a3d` at 12 Hz ("hot: this one bursts").
- **Shotgun time** (holding it, `wTime > 0`): the same bar, fill `#f6d17a`, `wTime/T.shotgunTime`; under 3 s it blinks
  red `#e0473f` (`floor(wTime·6) % 2 == 0`).
- **"need a spud"** while `dryHint > 0`, the weapon uses ammo, and `ammo ≤ 0`: bold 11 px, centred,
  at `y = round(p.y − r·spriteScale·0.95) − 6` (p.y − 67), `#d8b878` with a black 0.6 shadow 1 px down-right, alpha
  `min(1, dryHint·2)`.
- **HUD** (top left, per player, L12466): `$coins` bold 17 px monospace in the player's colour at
  `(26, 64 + 22i)`; then at x = 88: `☢ n` (gold `#f6d17a`, red when 0) if holding the launcher, else if the weapon
  uses ammo `● n` (`#d8b878`) or `○ 0` (`#e0473f`).
- **Banner** (L12666): bold 34 px, centred at `(430, 90)`, 5 px stroke `rgba(20,22,28,0.9)`, fill `#f6d17a`, until
  its time. Drawn last.
- **Touch hint** (L12640): on a touch device, the first 4 s with a full launcher: "TAP WHERE YOU WANT IT TO LAND",
  bold 22 px at y = 124, fade in over 0.25 s and out over the last 0.5 s.

### 11.7 Effect bursts (`fx`, L6238)

`fx(w, kind, x, y)` throws out `n` bits (3 × 3 squares, `alpha = life/0.6`, drag `0.9^(60dt)`, life 0.25..0.6 s, speed
`speed × (0.3 + 0.7rnd)`, random angle) and records `[kind, x, y]` in `w.events` (≤ 40). `FX_LOOK`:
HIT 4 `#f6d17a` 180 · KILL 14 `#6fd3a0` 260 · WALL 3 `#5a6274` 120 · HURT 10 `#e0473f` 220 · DOWN 24 `#e0473f` 300 ·
BOOM 36 `#ff9a6a` 420 · LAUNCH 8 `#c9c9c9` 140 · BLAST 40 `#ffb347` 520 · SPLASH 10 `#e6f7ff` 200 · DIVE 16 `#ffffff` 260.
(Owned with gore/effects; listed here because weapons fire HIT, WALL, LAUNCH, BLAST, SPLASH, KILL, BOOM.)
