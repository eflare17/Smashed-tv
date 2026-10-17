# Milestone 2 (Fighting): the specs

Porting specs for the fighting half of `Smashed.html` (build b331), written so a Godot developer can rebuild each
system without reading the HTML. Line numbers (`L1234`) are the HTML file's. Numbers are `T.name (value)` from
`data/game_data.json` → `T`. Positions are HTML units (`GameData.world_to_3d()` converts at the edge).

This README was written after reading all four specs against the HTML's run: `startGame` (L13549), `step`
(L13860), `stepBase` (L7160-8296), `snapshot`/`worldFromSnapshot` (L8300-8497), `advanceSimulation`/`frame`
(L12705-12815), the fighting parts of `renderBase` (L11527-12697), and the milestone 1 code in `godot/scripts/`.
It has three parts: the specs, an order to build them in, and the **Gaps** (what's missing, what disagrees, what
was wrong and has been fixed).

---

## 1. The specs

| spec | covers | proposed files (all new) |
|---|---|---|
| [`weapons.md`](weapons.md) | The six weapons (fists, spud gun, potato throw, blasters, shotgun, nuke launcher) and the SCREEN CLEAR nuke; the weapon table; firing rules, cooldowns, recoil, the spud gun's jab/husk/pickup cycle; potatoes growing on the floor and falling from the rope; bullets, husks, rockets, blasts and their hit tests; muzzles and barrel maps per character and skin (calibration); weapon sprite sheets and poses; muzzle flash; the weapon bar (hotbar); first-person aiming, hands, tracers; weapon sounds (and the three MP3 clips); network fields. | `scripts/weapons/*` (`WeaponDefs`, `MuzzleMap`, `WeaponState`, `PlayerWeapons`, `WeaponSim`, `WeaponView`, muzzle flash, `fp_viewmodel`), `scripts/ui/hotbar.gd`, `scripts/ui/weapon_hud.gd`, `scripts/audio/synth.gd`, `assets/audio/` |
| [`enemies_waves.md`](enemies_waves.md) | The arena (what the lobby turns into at Start), `startGame`/`restartGame`, the step order, the wave director and wave mix, the four enemy types (`ETYPE`), chasing, separation, the batter's wind-up and swing, contact damage, player health, iframes, grace, launch, death and game over; the enemy sprites, poses and procedural walk rigs; brute shrapnel; the janitor (Gary) and all his phases; fx kinds and the hurt/down sounds; network fields. | `scripts/arena/*` (`EType`, `ArenaSim`, `WaveDirector`, `JanitorSim`, `EnemyView`, `RigBaker`, `JanitorView`, `ShrapnelView`, `ArenaRoom`, `PlayerVitals`), `scripts/ui/wave_hud.gd`, `scripts/audio/sfx.gd`, `scenes/arena.tscn` |
| [`gore_loot.md`](gore_loot.md) | Effects (`fx`, sparks), blood sprays and floor stains, gore cutting (limbs cut along the outline), corpses and flying parts, hit-stop and screen shake; money: kill pay, loose notes, the magnet, pickup, the wallet; the slot machine (prizes, reels, the OUT OF ORDER sign) and its secret bonus room; the vending machine; floaters; the shared banner; the kill counter and HUD money; network fields. | `scripts/gore/*` (`GoreSim`, `GoreCutter`, `GoreView`), `scripts/loot/*` (`LootDefs`, `LootSim`, `SlotMachine`, `VendingMachine`, `CoinView`, `FloaterView`, `BonusRoom`), `scripts/ui/money_hud.gd`, `shaders/billboard_roll.gdshader` |
| [`modes_hud.md`](modes_hud.md) | The mode picker (Classic / Protect Gothica); Protect Gothica in full (`PROT`, her AI, carrying, being hurt, her bar and speech, the best wave); the in-run HUD (top line, wallets and ammo, pips, banners, buttons, help overlay, rumble); game over and restart; the victory dance; the bonus room (summary); phone controls in a run (twin sticks, roll taps, tap-to-throw/fire, FIRE). | `scripts/modes/*` (`RunModes`, `ProtectSim`, `ProtectView`, `GothCarry`, `BonusRoom` (see Gaps B4)), `scripts/ui/wave_hud.gd` (owner), `scripts/ui/mode_picker.gd`, `scripts/ui/touch_controls.gd` |

Where the specs overlap they mostly agree on the numbers (checked: step order, the kill sequence, the snapshot
indices, the sounds, the HUD positions, the wave table, the prize table, the barrel maps' sources). The places they
didn't are listed in Gaps C and were fixed in the spec files.

All four agree on the shape of the port: **a pure simulation in HTML units, stepped at a fixed 1/120 s,
host-authoritative, with views that only read it** (so milestone 4 can pack the same state into snapshots), and
**first person allowed in the arena** (the HTML only allows it in the lobby; the plan wants both views everywhere).

---

## 2. An order to build milestone 2 in

Each step ends with something playable in the web export. Steps 0 and 1 are shared groundwork that every later
step leans on; do them first and agree them before parallel work starts (see Gaps B for the decisions they need).

0. **Contracts and groundwork** (one agent, small, everyone reviews).
   - Decide the open questions in Gaps B (one world sim, one RNG, one sound autoload, one banner API, who owns
     player state). Write the result into the stubs as CONTRACT comments, the way milestone 1 did.
   - `ArenaSim` skeleton (the "world sim"): fixed 1/120 accumulator (frame time clamped to 0.1, reset when the tab
     is hidden, L12716), `t`, `seed` + `rnd()`, `freeze`, `shake`, `events` + `fx()` (cap 40), `started`, `over`,
     `save_state()`/`load_state()` and `snapshot()` stubs, and the step order of `stepBase` with empty hooks.
   - **Players in the sim** (Gaps A1): an `InputFrame` (the HTML input record) built each frame by a `LocalInput`
     node from keyboard/mouse/pad/touch (first person via the `shroomInput` rules), and the HTML player block
     (L7169-7525) moved into a sim step the world sim drives at 1/120. The Player node keeps the collision and the
     view.
   - The `Sfx` autoload (both specs' synth recipes: `tone`, `noise`, `clip`, `vary`, baked to `AudioStreamWAV`),
     the input actions (Gaps A6), the `Banner` API on the HUD.
1. **Blasters in the lobby.** Bullets, segment hits, walls; the muzzle maps and flash; the lobby target dummies
   (Gaps A2) as the first thing to shoot; the hotbar with fists/spud/lob/blaster; first-person aim and the blaster
   hands. Checks: weapons §18.10 (blasters, bar, first person).
2. **The run.** `startGame` (the lobby becomes the arena: `ArenaRoom`), the wave director, enemies as plain
   billboards (idle/front/side/back pictures, no rigs yet), separation, contact damage, the batter's wind-up ring and
   swing, player health, iframes/grace, death, game over, restart; `WaveHud` (top line, wave banner, game over,
   wallets). Checks: enemies §12.11 without the janitor.
3. **Kills that land.** The kill sequence: fx sparks, sprays, splats, corpses and flying parts (gore cutting can come
   in 3b), hit-stop, shake; `payKill`, floaters, the wallet, the kill counter. Checks: gore §23.10 (kills).
4. **The other weapons.** Spud gun with plants/pickup/husks and the jab poses; the potato throw (wind-up, ring,
   splat, bounce into a pickup, the rope rain); fists; shotgun; the launcher (rockets, blasts, the yeet = the
   player's launch state); the nuke. Checks: weapons §18.10.
5. **Enemy looks.** The walk rigs (baked), lean, flash shader, hp bars, spawn rings; brute shrapnel.
6. **Gary and the machines.** The janitor's phases and frames; the slot machine (pull, reels, prizes, BUST,
   JACKPOT), the vending machine and the launcher sale, loose notes and the magnet, SPEED BOOST. Checks: gore §23.10
   (slot, magnet, vending), enemies §12.11 (Gary).
7. **Protect Gothica** and the mode picker. Checks: modes §12.12.
8. **Phones and first-person extras.** `TouchControls` (twin sticks, roll taps, tap-to-throw/fire, FIRE), the
   first-person additions (edge chevrons, hurt vignette, own pips, Gothica's HUD bar), pad polish (help overlay,
   rumble). Test on a phone.
9. **The bonus room** (gore §14, modes §6). It needs `save_state`/`load_state` from every sim, so it comes last;
   it can slip to milestone 3 with the slot machine's lobby side if time runs short.

Sound goes in with each step (each spec lists its recipes). Keep the snapshot packing (each spec's network section)
in mind but don't build networking: that's milestone 4.

---

## 3. Gaps

### A. Systems no spec covers (or only in passing)

**A1. Players inside the fixed-step sim (the biggest one).** Every spec assumes the HTML's one step: players,
then waves, enemies, bullets, ... at 1/120, with recoil, punch lunges, pushes, the janitor's whack and the blast's
yeet all written into `p.vx, p.vy` before the player moves in that same step. But the milestone 1 `Player`
(`scripts/player/player.gd`) steps **itself** in `_process` with a variable `dt` (capped 0.05), reads `Input`
directly, and keeps `vel` as a non-contract field. Nothing in the four specs says who moves the player in the run.
Each spec asks for its own bolt-on instead (weapons §18.2 `vel_html/add_vel/set_vel/blow_away`, enemies §12.3
`add_impulse/launch(v, secs)/revive_at`, gore §23.2 `speed_mul`/`steer`/`vel`, modes §12.3 `speed_mul`/`can_shoot`/
`can_roll`/`revive_at`). The HTML player block (L7169-7525) is not just movement: in order it applies carry/sit
input masks, weapon switching, timers that run while dead, the shotgun clock, the slot pull, the empty-launcher
`dump`, buying, the pull start, the dive tower, the roll start, the launched state (no cap, drag `T.launchDrag`,
wall bounce `T.playerBounce`), the roll, accel/friction, aim, the three fire blocks, the speed cap with
`T.speedMul` and `PROT.carrySlow`, integration and the arena clamp. Recommended: one per-player sim record (the
HTML's `newPlayer` fields: hp, alive, iframe, grace, launch, weapon state, coins, ...) owned by the world sim,
stepped from an `InputFrame` in exactly that order; the Player node becomes its body (collision against the lobby
solids via `move_and_slide` with the sim's velocity) and its view. This is groundwork step 0 and needs the Player
task's agreement.

**A2. The lobby target dummies.** Weapons and gore give only their hit rules. Their state and look aren't
specced anywhere:
- Two dummies, made by `fillLobby` (L735, also `game_data.json` → `calls.dummies`): `(730, 318)` and `(730, 390)`
  with the lounge floor on (`ARENA.w × 0.28 / 0.72, ARENA.h × 0.42` without), `{hp: T.dummyHp (6), flash: 0,
  down: 0, wob: 0}`. Emptied by `startGame` (lobby only).
- Step (L8150, lobby only): `flash −= dt` (min 0); `wob *= 0.02^dt`; while `down > 0`: `down −= dt`, and at 0
  `hp = T.dummyHp, wob = 0`. Bullets knock them down at hp ≤ 0 (`down = T.dummyRespawn` 2.5 s, $3 to the shooter);
  punches and potato splats only take hp (can go negative, no knock-down); a rocket blast within `blastRadius + 16`
  drops them at once.
- Drawing (L11928-11963): shadow ellipse at `(x, y + 16)` radii 15 × 5, `rgba(0,0,0,0.32)`. Down: at
  `(x, y + 12)` rotated 1.35 rad, rect `(−6, −26, 12, 34)` `#6b5636`. Up: at `(x, y + 16)` rotated
  `sin(w.t × 26) × wob × 0.35`: post `(−3, −18, 6, 18)` `#5a4a30`; sack ellipse at `(0, −30)` radii 14 × 17
  `#c8a86a` (white while `flash > 0`); two target rings at `(0, −32)`, radius 8 and 3.5, 2 px `rgba(20,22,28,0.55)`;
  a strap rect `(−14, −46, 28, 4)` `rgba(20,22,28,0.5)`. An hp bar while `hp < T.dummyHp`: `(x − 16, y − 36)`, 32 × 4,
  back `rgba(20,22,28,0.7)`, fill `#f6d17a` for `32 × hp/dummyHp` (clamp at 0: a punched dummy goes negative).
- First person (L4058-4066, L4331): a 30 × 50 cut-out drawn the same way (post `(12,32,6,18)`, sack centred
  `(15,20)` 14 × 17, rings at `(15,18)`, strap `(1,4,28,4)`), placed at `(x, y + 16)` with its `wob`, only while up.
- Snapshot `dm` (lobby only): `[x, y, hp, round(down × 10), flash > 0 ? 1 : 0, round(wob × 100)]`.
Suggest the weapons task owns them (they're its first test target; build step 1).

**A3. The cans.** Weapons §9.1 and §8.7 describe cans being shot and blasted, and `stepBase` steps and kicks them
(L8158-8188), but `fillLobby` makes **none** (`for (i = 0; i < 0; ...)`, b218) and `T.canCount` (3) is unused.
Don't port them (or port them switched off).

**A4. A second local player.** Covered only as an input source (weapons §6). Missing:
- **P** adds player 2 (L8625; not a key repeat; refused in the bonus room, where it's queued as `joinPending`; at
  most two). `addPlayer` (L6065) makes a bare `newPlayer(1)` at `(480, 260)` with the character picked for slot 1:
  in the lobby it gets `max(T.lobbyCash, T.testCash)` but **not** `fillLobby`'s blasters/20 pellets (spud gun, 0
  ammo); mid-run it joins at once with $0, 5 hp, the empty spud gun.
- Controls (`localInput1`, L9038): arrows move, Space fires the way he faces, Ctrl rolls; pad 1: left stick, right
  stick aims (`st`), RT fires (or RT alone along the last stick aim), B/RB/LT roll. No weapon switching, and no E:
  he can't carry Gothica (E on the host only acts for `players[0]`, L8653).
- His colour is `#4f9fe8` (bullets `#a8d8ff`); the camera follows player 0 only (`camFollow` L8521); both wallets
  and pips show. With a network guest connected, slot 1 is the guest instead.
Needs an owner (the Player task, with modes/HUD for the second wallet line).

**A5. Debug and test keys.** Spread across the specs, never listed together, and useful for testing milestone 2:
with `?debug` (`DEBUG`): **G** shotgun for player 0, **N** drop the test nuke (run only, one at a time), **M**
magnet + 14 notes, the build/network readout on the top line, the test buttons; with "Show tweaks" (`TWEAKS`):
**C** calibrate barrels (not online), **J** send the janitor (`slot.broken`, sign up, `wave ≥ janitorWave`,
`breather 5.2`), the secret preview; always: **P** add player 2, **R** restart, **Enter** start, **Tab** help, **Z**
zoom, **V** first person. All but R/Enter/Tab/Z/V are refused in the bonus room (L8624). Suggest a Godot debug flag
(`OS.is_debug_build()` or `?debug` read through `JavaScriptBridge` on the web) gating the same keys.

**A6. Input actions.** Milestone 1 has `move_*`, `interact`, `roll`, `toggle_view`. The specs ask for, between
them: `fire` (mouse left, RT), `weapon_1`..`weapon_6`, `weapon_prev` (LB, d-pad left), `weapon_next` (Y, d-pad
right), `start_run` (Enter, pad Menu), `restart` (R; pad Menu while over), `help` (Tab, d-pad down), `zoom` (Z,
d-pad up), `add_player` (P), the debug keys, and player 2's `p2_move_*` (arrows), `p2_fire` (Space), `p2_roll`
(Ctrl). One agent should add them all to `project.godot` in step 0.

**A7. Facing for drawing vs facing for aiming.** The HTML draws the body with `facingVec` (L9563): the aim while
fire is held, else the move direction while moving, else `fx, fy` (which follows the cursor). Milestone 1's Player
feeds `CharSprite.facing = facing`, which follows the cursor even while walking without shooting, so he walks
"backwards" where the HTML shows him running the way he goes. The husk throw also leaves along `facingVec`.
Weapons §7 describes `facingVec` but doesn't flag that milestone 1 differs; the sim needs `firing`, `adx/ady`,
`ix/iy` and a separate draw facing.

**A8. Number keys.** Milestone 1's `Hud` picks the character with keys 1-3 (`number_keys_pick`); the HTML uses
1-6 for the weapon bar **in the lobby too** (L8630; its character picker is a page menu). Modes §12.1 only says
"turn it off in a run". Move the character pick off the digits when the hotbar lands (a lobby menu or the
picker buttons).

**A9. The audio clips.** `pistol` (6 takes), `nuke`, `whistle` are base64 MP3s inside the HTML (`CLIPS`, L11160)
and not yet in `godot/assets/` (weapons §14). Extracting them is a task of its own (it touches only
`godot/assets/audio/`); until then the synth fallbacks play.

### B. Contradictions between the specs (decide once, in step 0)

| # | what | weapons | enemies_waves | gore_loot | modes_hud | recommended |
|---|---|---|---|---|---|---|
| B1 | who owns the world state and the step | `WeaponSim` owns bullets/husks/rockets/plants/rain/nuke **and** its own `rnd()` | `ArenaSim` owns the world (§2.1: `freeze`, `shake`, `events`, `seed`) and the step | `GoreSim` owns `shake`, `freeze`, `events`, `fx()`; `LootSim` the coins | `ProtectSim` stepped by `ArenaSim` | One world sim (`ArenaSim`) owns `t`, `seed`/`rnd()`, `freeze`, `shake`, `events`/`fx()`, `started`, `over` and calls each subsystem in the HTML order. Subsystems keep their lists but call the world's `rnd()` and `fx()`. One RNG, one event list. |
| B2 | the sound autoload | `Synth` (`scripts/audio/synth.gd`) | `Sfx` (`scripts/audio/sfx.gd`) | "one autoload, whichever name" | uses the same recipes | One autoload `Sfx` in `scripts/audio/sfx.gd`: `tone`, `noise`, `clip`, `vary`, `whistle`, plus a recipe table by name (`hit`, `kill`, `hurt`, `down`, `shot`, `shotgun`, `pop`, `jab`, `cash`, `rocket`, `blast`, ...). |
| B3 | the big banner | `scripts/ui/weapon_hud.gd` draws it | `WaveHud` "Banner API" | `Banner.show(text, secs)` | `WaveHud.show_banner(text, secs)`, raised by a sim event | `WaveHud.show_banner(text, secs)`, fed by a `banner` event in the world's event list (so the guest sees it in milestone 4). `weapon_hud.gd` keeps the over-head bars and the touch hint only. |
| B4 | the bonus room's file and owner | – | – | `scripts/loot/bonus_room.gd` + view, full detail (§14) | `scripts/modes/bonus_room.gd` + view (§6, a summary) | gore_loot's (it has the detail); modes_hud only hides the HUD while `room` is on. |
| B5 | `WaveHud` | names it (§12.1) with its contents | – | puts the kill count in its top line | "one file, one owner": modes | modes_hud owns it; enemies_waves §3.3, §5.5, §8 are its inputs. |
| B6 | player hp/alive/iframe/grace | asks `Player.id/alive/hp/iframe` | a `PlayerVitals` child node owns them | asks `Player.hp` writable, `id`, `alive` | asks `Player.id/alive/hp/iframe/grace/kills/coins` | The per-player sim record of A1 (no `PlayerVitals` node); views read it. |
| B7 | hurting and killing an enemy | enemies expose `take_hit(dmg, dir, knock, stun, owner, big, cause)` | `ArenaSim.damage_enemy(i, dmg, dir, knock, stun, big, owner)` + `kill_enemy()` | `ArenaSim.kill_enemy(e, dir, big, owner, counts)` → `GoreSim.on_kill`, `LootSim.on_kill` | – | `ArenaSim.hit_enemy(e, dmg, stun, push: Vector2, flash)` and `ArenaSim.kill_enemy(e, dir, big, owner, counts_kill, kill_shake)`, doing gore §5.4 in order. The per-path differences must survive: `killShake` only on bullet/punch/potato/husk/shrapnel paths (× `killShakeBig` only for bullets), rockets and the nuke skip it; shrapnel kills never `burstShrapnel`; `kills++` only for bullets and rockets (B13). |
| B8 | velocity, launch, revive | `vel_html()`, `add_vel()`, `set_vel()`, `blow_away(t)` | `add_impulse(v)`, `launch(v, secs)`, `revive_at(x, y)` | `vel`, `steer` | `speed_mul`, `can_shoot`, `can_roll`, `revive_at(x, y, hp, grace)` | Moot with A1 (they're the record's `vx, vy, launch, alive, speed, ...` fields, as in the HTML). If A1 is refused, agree one set of names with the Player task. |
| B9 | screen shake in first person | – | a small rotation (≈ `shake × 0.15°`) | a position jolt `o × 0.0015 m` | rotation (as enemies) | Rotation. One input: `CameraRig.shake = w.shake` each frame, the rig turns it into an offset (top-down) or a rotation (first person). |
| B10 | does the HUD shake | – | – | no (deliberate simplification) | yes in top-down, for parity; still in first person | Keep the HUD still in both (it's easier on phones); note it as a deliberate change. Owner's call. |
| B11 | your own pips in first person | "in the HUD corner" | – | – | 10 × 10 squares under your wallet line | modes_hud's. |
| B12 | freezing the Player during hit-stop | set `player.frozen` | set `player.frozen` (which the trampoline also uses) | `player.frozen` or skip | – | Moot with A1 (the sim step is skipped); otherwise a separate flag, not `frozen`. |
| B13 | the kill counter missing punch/potato/splat/shrapnel/nuke kills | §17.6 notes it | "keep or fix, but know it" | §22.2 notes it | – | Owner's decision; default: keep the HTML's (bullets and rockets only). |
| B14 | `testCash` 2500 | uses it | "testing value; 0 for release" | keep tunable, default 2500 | – | Keep 2500 from `game_data.json` until the owner says. |

Smaller naming differences (harmless, just pick one): the arena room switch (`ArenaRoom.enter_run()` vs asking the
World task for `set_run_mode(on)`), the `billboard_roll` shader (gore) that enemies also wants for the lean, the
floaters (gore's `FloaterView`, modes says the HUD doesn't own them: agreed).

### C. Factual errors found and fixed in the spec files

1. **enemies_waves.md §8** (Protect hint): the line is at y **298** (`ARENA.h/2 + 38`), not 288, and the text has two
   spaces either side of each `·` (`'keep Gothica alive  ·  potatoes heal her'`, L12574). Fixed.
2. **enemies_waves.md §4.6** and **modes_hud.md §2.4**: the batter's swing damage is `T.contactDmg × ETYPE[t].dmg`
   (the batter's `dmg` is 2), not a literal `× 2` (L7589, L7602). Same number; fixed the formula.
3. **enemies_waves.md §3.4**: after a restart, a re-added player 2 does **not** get blasters: `addPlayer` runs after
   `fillLobby`, so he gets the lobby cash and an empty spud gun (L13547, L6065). Fixed.
4. **weapons.md §3.3**: `fillLobby` gives "every player" the blasters and 20 pellets, but only the players already in
   the world when it runs (player 0); a player added later (P, a guest, the restart re-add) is a bare `newPlayer`.
   Fixed.
5. **gore_loot.md §16** (floaters): Gothica's eating floater reads **`+2`** (`'+' + PROT.heal`, L13020), not
   `+heal`. Fixed (modes_hud already had it right).
6. **gore_loot.md §11.4**: a note's `pull` is rewritten every step a player has it in reach (1 with a magnet, 0
   without), not "never cleared". Fixed.
7. **gore_loot.md §11.3**: the debug magnet's notes are clamped to `[28, 832] × [28, 492]` (10 inside the walls,
   `ARENA.wall + 10`, L13651), not "28 inside the walls". Fixed.
8. **modes_hud.md §3.3**: the throw-power and shotgun bars are at `y − 63` without the character scale, so they're 8
   above the pips only for the old art; for the new art (pips at `y − 71.4`) they're 8.4 *below* them (L12358,
   L12389). Fixed, with the recommendation to put them above the pips for everyone.
9. **modes_hud.md §6.1**: the secret is once per **world** (`slotSecret` isn't cleared by `startGame`; a restart makes
   a new world), not "once per run". Fixed.
10. **enemies_waves.md §3.1**: added what `startGame` does **not** clear (D3). **weapons.md §17**: added quirk 22,
    the doubled rocket/blast sounds (D1).

### D. HTML behaviour found in this review that no spec mentions

1. **Rocket and blast sounds play twice on the host**: `firePlayer` calls `sfxRocket()` and `detonate` calls
   `sfxBlast()` directly, and each also raises an `fx` event (`LAUNCH`, `BLAST`) that `playEventSounds` plays again
   (and again every frame until the event list is cleared, gore §22.1). Play them once, from the event. (Added to
   weapons §17.22.)
2. **A roll can start while launched.** The roll start (L7306) comes before the launched block (L7321), and only
   needs `roll <= 0 && rollCd <= 0`, so pressing roll while thrown by Gary or a blast replaces the launch velocity
   with a roll's (620, plus 0.3 s iframes) and then carries on as launched (drag, no cap, bounces). Enemies §5.3
   says launched means "no input". Keep or forbid; either way decide it.
3. **`startGame` leaves things over from the lobby** (L13549-13607): enemies (a BUST brute from the lobby slot walks
   into the run and wave 1 doesn't end until it's dead), bullets, shrapnel, husks, rockets, blasts, a falling SCREEN
   CLEAR, floaters, sparks, the rope's falling potatoes; per player `alive` (a player the brute killed stays down
   until wave 1), `spin` (a pull in progress pays out in the run, and `slot.busy = −1` lets the other player pull at
   the same time), `launch`, `iframe`, `kills`, `shots`; and `w.over`: if a lobby brute killed everyone, Start begins
   a run that's already over (frozen under "DOWN / made it to wave 0") until R. Recommended: clear the arena lists and
   revive everyone at Start. (Added to enemies §3.1.)
4. **A lobby BUST brute is boxed into the lounge**: the enemy clamp is always the `ARENA` rectangle (L7655), so in the
   tall lobby it can't follow you into the bedroom or the yard, and it walks through the furniture (enemies have no
   solids).
5. **The pull and the purchase can start mid-flight**: both are checked before the launched and roll blocks and only
   need no stick input (and, to buy, not firing), so a player thrown past the slot machine with the stick let go is
   stopped dead by a pull.
6. **The first three plants avoid the wrong spot**: `startGame` plants them while `slot.x` is still the lobby's 90
   (it's moved to 430 at the end of the next step), so they keep clear of `(90, 110)` instead of the run's cabinet at
   `(430, 110)`.
7. **Snapshot bug, janitor walk direction**: `jn[14]` is `round((wdy || 100) × 100)`, so an exact `wdy = 0` (walking
   straight across) goes out as 10000 and the guest shows his front frames. Send `wdy ?? 1`.
8. **Gothica competes with the players for ripe potatoes** in Protect mode: she eats (removes) plants within 14 when
   hurt; nobody gets the pellets. Intended, but worth a line in the HUD hint or a test.
9. **Local player 2 can't pick Gothica up** (A4), and can't switch weapons (weapons §17.18).
10. **Dummy hp bar** goes negative (drawn with negative width) after punches or splats take a dummy below 0 (A2).

### E. Milestone 1 code the specs lean on that doesn't exist yet

The specs' "In Godot" sections ask the milestone 1 owners for these (none are in `godot/scripts/` today): Player
`id`, `alive`, `hp`, velocity/launch/revive hooks, `speed_mul`, `can_shoot`/`can_roll` (A1, B6, B8); CharSprite
`skin_id` (weapon sheets: `CharFrames` already knows `_shotgun`/`_spud`/`_launcher` sheets and the shotgun pose
scales), weapon actions `reload`/`pickup`/`throw`/`charge` with progress, the jab-while-running stitch, `carry`, an
externally set `victory_t`, and read-backs `shown_oct`/`shown_flip` for the barrel; CameraRig shake input (B9) and a
way to force top-down for the bonus room (`set_mode` exists); World: a run-mode switch that hides lobby props and
closes the door gaps (enemies §12.6); lobby Gothica: hand over her position at Start and hide her in the run
(modes §12.3). Collect them into one request to the milestone 1 owners in step 0.
