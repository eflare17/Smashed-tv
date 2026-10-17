# Arcade (milestone 5 part): integration note

## Handoff

**State: done and pushed** (`claude/godot-arcade`, last commit "Arcade: input actions (added in code), integration
note"). Nothing is half-done; there's no uncommitted work. Everything below this section is the full note.

- **Done and working** (tested headless, 42 checks, and in the real web export with screenshots): both cabinets
  with E / PLAY in both views and live little screens; the full-screen overlay; Snake, Bricks and Sand Miner with
  keys, pad and touch controls; high scores shared with the HTML game; the Mega Drive / SNES menu with the
  IndexedDB library, console picker, add files / folder / zip, and EmulatorJS over the game (loaded from the local
  `emu/`); input actions added in code.
- **Next steps, in order** (none block merging):
  1. Main session: add `Arcade.install(self)` at the end of `main.gd`'s `_ready()`; fighting session: call
     `Arcade.close_all()` when a run starts.
  2. Try a real Mega Drive / SNES ROM in the web build (only a dummy file was tested here).
  3. Milestone 4: wire the friend hooks (see "Hooks for other sessions": `friend_send`, `on_friend_message`,
     `friend_gone`, and the two PeerJS lines `SmashedMD.streamTo` / `SmashedMD.answerCall`).
  4. Google Drive: fill `SmashedMD.driveConnect` once the owner gives the OAuth client ID (`ArcadeMd.DRIVE_CLIENT_ID`).
  5. Measure Sand Miner on a real phone.
- **Gotchas found:**
  - Godot's default font has no ✕ ♥ ◀ ▶: they are drawn as shapes (`ArcadeGame.cross` / `heart`, triangles).
  - A file picker opened from GDScript comes a frame after the click; browsers want it inside the click. The page
    catches the click on the Add buttons itself (`setPickRects` in `md_bridge_js.gd`). In Playwright, register the
    `filechooser` listener and wait ~0.5 s before clicking, or the first chooser is missed (a harness race).
  - In the test VM the web build runs at a few frames a second and dt is capped at 0.05, so game time runs slow
    there; a quick swipe can begin and end in one frame (handled: swipes are latched).
  - `--check-only` reports "Identifier not found: GameData" (autoloads aren't loaded in that mode): harmless; run
    the real test instead.
  - The JS lives in a GDScript raw string (`r"""..."""`): keep backslashes out or mind them.
  - The emulator base path probes give 404s in the console before finding `emu/data/`: expected.
- **How to test:** copy `godot/` to a scratch folder with `scenes/arcade/arcade_test.tscn` as the main scene, then
  `godot --headless --path <copy> --fixed-fps 60 -- --logic` (prints `ARCADE TEST ok/FAIL`, exit 1 on a fail).
  For the web, export, serve the folder above the copy with a symlink to the repo's `emu/` next to it, and open
  `.../build/web/index.html?open=miner&play` (also `open=bricks|snake|bricksgame`, `&fp`, `&at[=y]`, `&touch`,
  `&astate`), screenshot with `godot/tools/gd_shot.mjs`.

Branch `claude/godot-arcade`. Files: `scripts/arcade/`, `scenes/arcade/arcade_test.tscn`, `test/arcade/arcade_test.gd`,
this note. Nothing else touched.

## Install (the one line for `scripts/main.gd`)

At the end of `main.gd`'s `_ready()` (after the World is built, so the cabinets' pictures exist):

```gdscript
	Arcade.install(self)
```

It uses `main.world` (its `props["cab_miner"]` / `props["cab_bricks"]` for the live screens), `main.player`,
`main.rig`, `main.hud`. Nothing in `main.tscn` changes.

When a wave run starts (milestone 2's start), add, like the HTML game's `drawArcade` / `mdClose` closing on
`v.started`:

```gdscript
	Arcade.close_all()
```

## What works

Tested headless (`--logic`, 42 checks, all pass) and in the real web export (screenshots looked at: top-down,
first person, each game, the menu, a phone in landscape, EmulatorJS loading a game).

- **The cabinets** (CABINETS in game_data.json): Sand Miner at x 172 and Bricks at x 242. E (or the HUD's round
  button, or the pad's A) says **PLAY** exactly where the HTML game's `arcadeNear` does (within 30 across, from 4
  behind the feet line `cabY` to 46 in front, on the floor, not on the trampoline), in both views. Each has its
  **little screen running live** on its face (the HTML game's `mini()` animations, drawn in a 36 x 30 SubViewport on
  a quad that leans with the World's prop shader, so it sits in the bezel top-down and in first person). The
  Bricks cabinet shows the picture of the Mega Drive game being played (`mdCabPic`).
- **The overlay** (`drawArcade`): the room dimmed, the cabinet round the 480 x 320 screen in its colours, the
  lit marquee title, SCORE and HI, scanlines, PUSH TO START / GAME OVER (YOU WIN! for a full Snake board) /
  PUSH TO PLAY AGAIN, the controls line for the device in use, and the round X. Blown up to fill the window
  (leaving the sides for the touch buttons). You stand still while playing: the player's controls, the camera's
  view/zoom keys and the HUD are off, the pointer is let go in first person (and taken back after, on the desktop).
  E, Esc, the pad's B (or View) or the X walks away. The press that opened it never starts the game.
- **High scores**: kept per game; on the web in `localStorage["smashedArcadeHi"]`, the same key as the HTML game,
  so on the same site the two share their high scores; `user://arcade_hi.json` elsewhere.
- **Spud Snake** (`snake.gd`): the HTML game's exactly (24 x 16, 0.13 s a step, 3% quicker a potato down to 0.06,
  the tail square is free unless eating, filling the board wins). Keys WASD / arrows, pad d-pad or left stick,
  touch swipe (drag from where the finger lands; a quick flick inside one frame still counts).
- **Brick Brawl** (`bricks.gd`): the HTML game's exactly (8 x 5 wall, ceil(level / 2) rows of two-hit bricks, 1 a
  crack / 5 a brick, 3 lives, ball 250 + 25 a level, the paddle steers the ball). Keys / d-pad / stick move the
  paddle at 380/s; the **mouse** over the screen or a **finger dragging** puts the paddle where it points; space,
  up, A, a click or a tap launches.
- **Sand Miner** (`sand_miner.gd`): a full port of `makeSandMiner` (the 384 x 256 falling-sand world and its
  generation, caves of water and sand, the eight ores and their values, the shovel and its dig timing, nuggets that
  pop out and come to you, the launcher with its five levels and costs, dirt / sticky clay / sand ammo, the aim arc,
  the toast messages, the inventory and launcher HUD, parallax hills and clouds, the miner's sprite sheet and the ore
  sheet from `assets/`). 60 ticks a second like the HTML game. Score = ore collected by value. Controls:
  keys A/D, W or Space jump (swim up), mouse left digs / right or F launches, Q ammo, U upgrade; pad left stick,
  A jump, right stick aims, RT digs, LT or RB launches, X ammo, Y upgrade; touch: on-screen < > JUMP LAUNCH AMMO
  UPGRADE buttons down the sides, and your finger on the screen is the shovel (LAUNCH throws to where you last
  touched). Speed: about 0.9 ms a tick including the picture (desktop, headless); see Decisions.
- **The Mega Drive / SNES cabinet** (`arcade_md.gd` + `md_bridge_js.gd`): E at Bricks opens its menu, as in the
  HTML game (b303 to b306): + Add games (files or a .zip, unpacked like `mdUnzip`), + Add a folder (desktop
  browsers), Play Bricks, Play Snake, Connect Google Drive (the hook, below), the console picker (All, Mega Drive,
  Super Nintendo, and Master System / Game Gear once you have one, remembered in `localStorage["smashed-console"]`),
  the library list (picture, name, console tag and size, Remove with a confirm). Pad and keys work in it (focus
  starts on Play Bricks; B / Esc closes). Picking a game opens **EmulatorJS over the whole game** in an iframe
  (the HTML game's `mdPlay`, cores by file ending), with a bar: name, Set picture, Library, Close; Esc inside the
  emulator closes it too. Pictures are taken automatically a few seconds in (`mdSnap`) and saved with the game.
  The library is the **same IndexedDB** (`smashed-megadrive`) as the HTML game, so on the same site the games added
  in either show up in both.
  The emulator's files are looked for at `../emu/data/` (the site: `godot-play/` next to `emu/`), then `emu/data/`,
  `../../emu/data/`, `../../../emu/data/`, then EmulatorJS's own CDN (like `mdBasePath`). Tested: the local
  `emu/` loaded and EmulatorJS showed its START GAME screen (with a dummy file: no real ROM here). Off the web the
  menu says the console games are in the web version; Bricks and Snake work.
- **The broken cabinet** (the slot machine with its OUT OF ORDER sign) is untouched: not ours, stays as it is.

## Input actions added (in code, `Arcade.add_actions()`, only if missing)

| Action | Keys | Pad |
|---|---|---|
| `arcade_left` / `arcade_right` / `arcade_up` / `arcade_down` | A D W S, arrows | d-pad, left stick (dead zone 0.3) |
| `arcade_fire` (start, launch the ball, Sand Miner jump) | Space, Enter | A |
| `arcade_launch` (Sand Miner) | F | RB, LT |
| `arcade_dig` (Sand Miner; the mouse's left button digs too) | | RT |
| `arcade_ammo` / `arcade_upgrade` (Sand Miner) | Q / U | X / Y |
| `arcade_close` (walk away) | Esc, E | B, View |

The pad's right stick (Sand Miner's aim) is read as an analogue axis. Touch has no actions: swipes, drags and the
overlay's own on-screen buttons. The menu uses Godot's `ui_*` actions.

## Hooks for other sessions

- **Milestone 4 (the friend as player 2).** `Arcade.instance().md` takes:
  - `md.friend_send = func(msg: Dictionary): ...` (send to the other player), `md.friend_name = "<my character>"`;
  - on a message: `if Arcade.instance().md.on_friend_message(msg): return` (true if it was the Mega Drive's);
  - `md.friend_gone()` when the connection drops; signal `md.friend_joined` when the friend asks to join.
  The messages are the HTML game's (`{t:'md', on, name, who, sys, pic}`, `mdjoin`, `mdleave`, `mdpad`); the
  offer is re-sent every 3 s while playing, the "X is playing Y. Join as player 2 / No thanks" banner shows on the
  friend's side, and Join opens the watch screen (touch pad, keys, a pad) and sends the friend's buttons as `mdpad`,
  which the host's emulator presses as player 2 (`SmashedMD.applyPad`).
  The picture and sound must go as a WebRTC media call made in the page's JavaScript: on `friend_joined` the
  host's page runs `SmashedMD.streamTo(peerJsPeer, friendPeerId)`; the friend's page hands the incoming PeerJS call
  to `SmashedMD.answerCall(call)`. If milestone 4 isn't PeerJS, `SmashedMD.watch(mediaStream)` shows any stream.
- **Google Drive games folder (later).** `ArcadeMd.DRIVE_CLIENT_ID` (empty now: the button says it needs the owner's
  Google sign-in set up) and `SmashedMD.driveConnect(clientId)` in `md_bridge_js.gd`, a stub to fill: sign in with
  Google Identity Services, list the shared folder's ROMs, emit `{ev:'drive_list', games}`, download and play one.
- **Others:** `Arcade.is_open()` (something of ours has the screen; `main.get_meta("arcade_open")` too) and
  `Arcade.close_all()`.

## Contract changes wanted

None needed. Nice to have: if milestone 2 adds click-to-fire that reads the mouse outside `_unhandled_input`, it
should skip while `Arcade.is_open()` (the overlay marks key and pad events handled in `_input`, and its full-screen
Control stops mouse clicks, so `_unhandled_input` / GUI-ordered handlers already don't see them).

## Decisions (made for the owner; easy to change)

1. **Snake has no cabinet in the HTML game any more** (b302 turned the Snake cabinet into Sand Miner). It's in the
   Mega Drive menu as **Play Snake** next to Play Bricks, on the Bricks cabinet's colours.
2. **Bricks: the mouse or a finger puts the paddle where it points** (the HTML game only had a relative drag);
   the owner asked for "drag the paddle". Keys and sticks still move it at 380/s.
3. **Sand Miner on touch has on-screen buttons** (< > JUMP LAUNCH AMMO UPGRADE), as decided with the owner, instead
   of the HTML game's drag-to-walk; the finger on the screen is still the shovel.
4. **Sand Miner pad layout**: A jump, right stick aims, RT dig, LT / RB launch, X ammo, Y upgrade, B leaves.
5. **Sand Miner speed-ups**: the sand only runs in 16 x 16 chunks where something moved, and the world picture is
   repainted only where it changed (plus visible water every 16 frames, twinkles drawn on top). It plays the same.
6. The menu is Godot UI (pad-friendly) rather than the HTML game's DOM box; only the running emulator (and the
   friend's watch screen) is DOM, because EmulatorJS is a web page.
7. The file picker is opened by the page inside the click itself (Godot tells the page where its Add buttons are):
   browsers, iOS Safari especially, only allow a picker during the click.
8. The miner's labels and the default font: the font has no ✕ ♥ ◀ ▶, so those are drawn as shapes.

## What's left

- A real ROM test (none here): the load path, EmulatorJS and the iframe are tested with a dummy file.
- Player 2 over milestone 4 (hooks ready, needs the connection and the 2 lines of PeerJS wiring above).
- Google Drive folder (needs the owner's OAuth client ID).
- Sounds are made in code like the HTML game's `sTone` / `sNoise`; the web build needs a first click before audio
  plays (browser rule), which the E press normally is.
- Phone speed on a real device: Sand Miner ran smoothly in the test browser (software GL), not measured on a phone.

## Testing

`scenes/arcade/arcade_test.tscn` (script `test/arcade/arcade_test.gd`) runs the real `main.tscn` and calls
`Arcade.install`. In a test copy with it as the main scene:
`godot --headless --path <copy> --fixed-fps 60 -- --logic` prints `ARCADE TEST ok/FAIL` lines (exit 1 on a fail).
The web build takes `?open=miner|bricks|snake|bricksgame`, `&play`, `&fp`, `&at[=y]`, `&touch`, `&astate`
(prints `ASTATE ...` twice a second).
