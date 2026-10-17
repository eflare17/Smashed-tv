# Milestone 2 (fighting): integration note

Branch `claude/godot-fighting`. Everything is in the folders PARALLEL.md gives this session: `scripts/combat/`,
`scripts/enemies/`, `scripts/arena/`, `test/combat/` and this note. No existing file was edited.

## Install (the one line for `scripts/main.gd`)

At the end of `Main._ready()`, just before the `print("Smashed TV (Godot) ...")` line:

```gdscript
	FightInstall.install(self)
```

That's all. It adds the input actions below (in code) and one `Fight` node under Main, which reaches `main.player`,
`main.rig`, `main.hud`, `main.world`, `main.trampoline`, `main.gothica`. The web test (`test/combat/web_test.sh`)
inserts exactly this line into a scratch copy and exports it.

## What works

Tested in the real web export (screenshots looked at) and in headless logic tests (`test/combat/logic_test.tscn`:
43 checks against the specs' numbers, all passing).

- **Weapons** (godot/specs/weapons.md): fists (lunge, lands 0.108 s in, hits everything in reach), the spud gun
  (pellets, the jab between every shot, the husk thrown after each potato, "need a spud", dry clicks), the potato
  throw (hold to wind up 0.3 s with the power bar and landing ring, let go to lob; a full-power potato bursts with
  SPLAT!, a weaker one bounces and lies there as a pickup), blasters (9.5/s, alternating hands), the shotgun (5
  pellets in 20°, 12 s clock in a run), the nuke launcher (3 rockets on a lob arc to the ring, blasts that throw
  you without hurting you, EMPTY! and back to the last gun), the SCREEN CLEAR nuke (whistle, fall, white-out).
  Recoil, knockback, stagger, the barrel maps per character and weapon skin, muzzle flashes, the weapon sheets
  (spud/shotgun/launcher pictures) with the reload, pickup and throw frames, facing the shot while firing.
- **Potatoes**: three growing at the start of a run, one wild sprout every 5 s (max 6), ripe after 9 s, walk over
  one to pick it up (+10 pellets, bends over). `Fight.me.sim.rope_rain()` drops the bell rope's ten (for the lobby
  session's rope).
- **The weapon bar**: 1-6, the pad's LB / d-pad left and Y / d-pad right, click or tap a slot, drag a slot onto
  another to swap (saved in `user://smashed.cfg`), unowned slots flash red. Ammo, ∞, ☢ n and the shotgun clock.
- **Shooting in both views**: top-down aims at the mouse on the floor, the pad's right stick (RT fires), or the touch
  aim stick; first person fires straight ahead (click while the pointer is held, RT, or the touch FIRE button), and
  looking up throws the potato/launcher further (shroomInput). First person shows the blasters in your hands with
  the walk bob, kick, muzzle glow and tracers to the crosshair; a full-view flash for the other guns; your own pips;
  a red pulse while you can't be hurt; your shots appear from 70 units out.
- **Enemies** (enemies_waves.md): grunt, swarmer, brute, batter with the HTML's ETYPE numbers, the wave director
  (2.2 s breathers, 0.45 s spawn gap, wave sizes, speed-up, the mix with batters as the filler at b331 tuning),
  sluggish steering, separation, the arena clamp, contact damage, the batter's tell (red ring shrinking 0.38 s),
  swing (2 hearts, only in front), recovery; brute shrapnel (8 shards, hurts you and the small fry, not brutes).
  Pictures from `ENEMY_SPRITES`, the pose from the velocity as the camera sees it, white hit flash, hp bars, the
  spawn ring, and the **walk rigs** (planted feet and bending knees under grunt/swarmer/brute, baked on first use).
  The batter walks with his own frames and swings with the swing frames.
- **Gore** (gore_loot.md): sparks, hit sprays, death sprays fanning out, floor stains, the hit-stop, screen shake,
  corpses thrown and fading, the **gore cutting** (each enemy picture labelled into head, arms, legs and cut along its
  outline with red stumps; an arm and a leg fly off a normal kill, everything off a big one), flecks.
- **Money**: kill pay straight to the wallet with a floating `$n`, split when nobody owns the kill; loose notes
  (magnet bonus, JACKPOT shower, Gary's three) that drift in and blink out; CASH MAGNET and SPEED BOOST.
- **Health and game over**: 5 hearts (pips over his head, overheal in gold), iframes (blinking), the wave-start grace,
  being thrown (Gary's whack, blasts: no control, drag, wall bounces), death, everyone back at the next wave, and the
  DOWN / "made it to wave N — K killed" screen; R, the pad's Menu or a tap restarts to a fresh lobby (character and
  mode kept).
- **The arena**: the lobby becomes the dark grid room at Start (the World, the trampoline and lobby Gothica are hidden;
  the lobby's E things are taken out of the "interactable" group), the camera kept inside 860 x 520, a ceiling for
  first person. The slot machine moved to the top wall, broken with the OUT OF ORDER sign; the vending machine top
  right selling the launcher for $2500 (stand still 0.8 s, restocked each wave).
- **The janitor (Gary)**: all his phases: walks in after wave 1, throws the sign down, three hammer clanks, three
  notes, pockets what's left, MACHINE IS LIVE, walks out; shot once he's knocked flat and gripes in a speech bubble;
  shot again he stares, charges and whacks you across the room; "..." when he gives up. Then the slot machine pays
  out its eight prizes ($5 a pull, 1.6 s rooted, 8 s recharge).
- **Protect Gothica**: the mode picker (`<  Classic  >  Start (Enter)` at the top of the lobby), Gothica in the run
  with her bar, wandering, panicking, eating ripe potatoes to heal (+2), speech bubbles, enemies choosing her or you,
  Juicy Jared carrying her with E (the milestone 1 E prompt and round button: PICK UP / PUT DOWN), slow and unable to
  shoot or roll, she wriggles down after 4 s; players respawn next to her after 4 s; her down ends the run with the
  best wave saved.
- **Sounds**: every recipe in the specs synthesised (baked to WAVs on first use) plus the pistol, nuke and whistle
  recordings in `assets/sounds/`. A batter's wind-up whooshes in first person (new). The pad rumbles when you're hurt.
- **Phones** (code reviewed, not tested on a device): left half a floating move stick (it presses the move actions,
  so the lobby's Player walks with it too), right half the aim stick that fires, a second finger on a held side
  rolls, tap to fire the launcher there, hold on the spot to throw the potato there, FIRE and drag-to-look in first
  person, tap the game-over screen to restart.

## Input actions added (in code, by `FightInstall.add_actions()`)

| action | keyboard / mouse | pad |
|---|---|---|
| `fire` | left mouse | RT |
| `weapon_1` .. `weapon_6` | 1 .. 6 | |
| `weapon_prev` | Q | LB, d-pad left |
| `weapon_next` | | Y, d-pad right |
| `start_run` | Enter, keypad Enter | Menu (Start) |
| `restart` | R | (Menu when it's over) |

Debug keys (debug builds, or `?fight=keys`): G shotgun, N the nuke, M magnet and notes, J send the janitor.

## Contract changes wanted (and what the fighting does meanwhile)

1. **Hud** (`scripts/ui/hud.gd`): keys 1-3 pick the character, but the weapon bar needs 1-6 (README gap A8). The
   install sets `hud.number_keys_pick = false`; the character buttons still work. Please drop "1 2 3 character" from
   `KEY_HELP` and add "1-6 weapons   click shoot   Enter start   R restart".
2. **Player** (`scripts/player/player.gd`): in a run the sim moves him (README gap A1). Meanwhile the Fight node
   switches `controls_enabled` off, sets `collision_mask = 0`, places him every frame and redraws his sprite after
   his `_process`. Cleaner would be an explicit `driven_by_sim: bool` (no `_step`, but `_update_focus` kept), and
   `use()` callable while `controls_enabled` is off (it is: the Fight node calls it for E).
3. **CharSprite**: a public `show_frame(sheet, key, idx, flip)` for the weapon actions (reload, pickup, throw,
   wind-up); the Fight node calls the private `_show()` meanwhile, and sets `char_id` to the weapon sheet
   (`juicy_spud`, ...) after the Player sets it back each frame, which loses the sector hysteresis. A `skin_id`
   on CharSprite/Player would fix both.
4. **CameraRig**: a `shake` input (the Fight node nudges the camera after the rig has placed it, with a child node at
   process priority 200), and a `zoom_text()` that says 1.5x in a run (the zoom is right, the label says 2x).
5. **World**: a run-mode switch (`set_run_mode(on)`) would be nicer than hiding the whole World node; the arena is
   drawn by `ArenaRoom` meanwhile, and since the run moves the player without collisions the lobby's walls don't
   matter.
6. **Lobby session** (slot machine, vending machine, rope): call `Fight.me.award(player_node, "shotgun")` (keys:
   blasters, shotgun, health, speed, clear, cash, magnet, bust) for the lobby slot machine's prizes, and
   `Fight.me.sim.rope_rain()` for the bell rope's potatoes. The run's machines are this session's (`ArenaRoom`,
   `FightSim`).

## Decisions (made for the owner; easy to change)

- One simulation (`FightSim`) in HTML units at 1/120 s, one RNG (the HTML's LCG), host-style, so milestone 4 can
  snapshot it. In the lobby the milestone 1 Player still walks himself; the sim shoots for him and adds recoil to his
  velocity. In a run the sim drives him (the HTML's player step: rolls, being thrown, arena walls).
- At Start, leftovers from the lobby are cleared and everyone is revived (README D3, recommended).
- First person is allowed in the arena (the HTML only allows it in the lobby; the plan wants both views everywhere).
- Shots start 30 units ahead of him in the simulation (hits stay 2D on the ground, like the HTML); their pictures fly
  out of the gun drawn on his picture (the barrel maps) for the first 70 units, then at chest height (45).
- Heights over the floor (bullets, bars, pips, potatoes in the air) follow the characters' tipped-back "up" in the
  top-down view so they line up with the pictures; first person is true 3D.
- The dry click comes every 0.18 s in both fire paths (weapons 17.1), and switching weapon drops a wind-up (17.2).
- The landing ring for the potato is drawn at the splat's real radius (72), not the launcher's 110 (17.4).
- Rocket and blast sounds play once (from the event), not twice (17.22). Game over lets the shake settle.
- The kill counter keeps the HTML's rule (bullets and rockets only).
- `testCash` 2500 kept (testing money from game_data.json).
- The HUD doesn't shake (easier on phones; B10). Shake in first person is a small turn (B9).
- Gothica in someone's arms is drawn lying across them (the HTML swaps the carrier to its carry pictures; those
  belong to the lobby session's carry).
- Q also picks the previous weapon (the HTML has no key for it).
- Bullets still pass through furniture-height things (the run has none; in the lobby only walls stop them, as the
  HTML).

## What's left

- **The secret bonus room** inside the slot machine (gore_loot 14: shoot Gary as he leaves after the repair...). Not
  built; Gary simply carries on.
- **A second local player** (P, arrows / Space / Ctrl, pad 2). The sim takes any number of players
  (`sim.add_player`), but nothing adds one yet; the HUD lists every wallet.
- The batter's procedural rig (his own walk frames are used), the lean on idle poses, the slot machine's spinning
  reels drawn in the window (the machine shows its spin/win pictures and the banner says the prize).
- The tyson2 recolour for the first-person hands' skin tint (the hands are Juicy's colour for everyone).
- Calibration mode (C) and the tuning panel: not ported (the maps are the HTML's derived ones).
- Network snapshot packing (milestone 4).
- Tested only in Chromium's software renderer (4-5 fps for the whole game there, the same with and without the
  fight); the phone controls need a real phone.

## Testing

- Logic: `godot --headless --path godot res://test/combat/logic_test.tscn` (exit code 0 = all pass).
- The game headless with the fight: `godot --headless --fixed-fps 60 --path godot res://test/combat/game_test.tscn -- --fight=run,auto --secs=30`.
- Web: `bash godot/test/combat/web_test.sh out.png 20000 "fight=run,auto"` builds a scratch copy with the install line,
  serves it and screenshots. `node godot/test/combat/play_test.mjs <url> <dir>` plays it with real keys and clicks.
- Debug flags (`?fight=a,b` on the web, `--fight=a,b` after `--`): `run`, `protect`, `auto` (aims and fires at the
  nearest enemy), `fp`, `god`, `wave=N`, `weapon=ID`, `gallery` (a frozen scene with one of everything), `log`,
  `keys`.
