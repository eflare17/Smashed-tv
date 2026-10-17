# Brief for lobby-life build agents

The owner's game Smashed TV (a single-file HTML canvas game, /home/user/Smashed-tv/Smashed.html, READ ONLY) is
being ported to Godot 4.4.1 (GDScript, Compatibility renderer, web export) in /home/user/Smashed-tv/godot/.
Read godot/PLAN.md (ground rules) and godot/PARALLEL.md. The HTML game is the spec: match behaviour, numbers,
text and art. The owner is asleep: never ask, make the call that best fits the HTML game and list it under
"Decisions" in your final report.

## The lobby-life framework (already written; read these files first)
- scripts/lobby_life/lobby_life.gd  `LobbyLife`: installed on the running game (main.gd: world, player, rig, hud,
  gothica, trampoline). Holds `things` (by name), `busy` (player -> LobbyThing holding him), `hold(p, thing)` /
  `release(p)` (freezes the Player: his own step stops and the thing moves him), `set_pose(p, LobbyPic)` (show a
  picture instead of his character sprite; null = normal), money `cash/add_cash/pay`, `ui` (LobbyUI), `sfx`
  (LobbySfx), `smoke` (LobbySmoke), helpers `T(k)`, `D(k)`, `calls(k)`, `hpos(node)`, `at(x,y,z)`, `is_jared(p)`,
  `ensure_action(name, keys, pads)` (add your input actions with this, in your thing's _ready).
  E while held: LobbyLife routes the interact action (key, pad A, the HUD's round button) to the holding thing's
  `busy_act(p)`; the prompt shows its `busy_label(p)`; other input goes to its `busy_input(p, event)`.
- scripts/lobby_life/lobby_thing.gd `LobbyThing extends Interactable` (scripts/interact/interactable.gd): label_for/act
  when he's free (return "" from label_for unless `can_start(p)` or it's your own business), busy_* while held,
  `put(p, x, y, z)` places him (HTML units; also sets p.dz so the camera and first person follow), `steer(p)`
  (WASD / stick, turned for first person). `hides_sprite(p)`.
- scripts/lobby_life/lobby_pic.gd `LobbyPic`: an upright picture (CharSprite's shader: stands at eye level, tips flat
  from above) with feet at its origin; `units_per_px` (0.5 for the HTML game's half-size art), `foot_px`, `lift`,
  `shift_x`, `flip`, `recolour_for` (Tyson's singlet colours on Jared's art), `LobbyPic.art("gym/plate_L.png")`.
- scripts/lobby_life/lobby_ui.gd `LobbyUI` (CanvasLayer 11): `say(node, text, dur, head)` speech bubbles,
  `float_text(x,y,z,text,col,dur)`, `info(text,dur)`, `menu(title, [[label, callable]...], cancel)` (pad/touch/mouse),
  `fx_root` (full-screen layers), `root` (add your own Controls: panels, buttons).
- scripts/lobby_life/lobby_sfx.gd `LobbySfx`: `play(name)`, `tone(...)`, `noise(...)` (add recipes as needed in your
  own file by calling tone/noise; don't edit lobby_sfx.gd).
- scripts/lobby_life/lobby_smoke.gd `LobbySmoke.puff(...)`.
- scripts/lobby_life/goth_life.gd `GothLife` (things["goth_life"]): `claim(owner, spot, speed_mul, face)` /
  `unclaim(owner)` / `at_spot(owner)` steer Gothica; `say(text, dur)`; `is_busy()` / `held`.
- scripts/lobby_life/test_lobby.gd + scenes/lobby_life/test_lobby.tscn: the game with LobbyLife installed; with
  `?lobby=<thing>[,fp][,more]` in the web build's address (or `-- --lobby=...`) it calls
  `things[<thing>].test_scene(tl, parts)` so your thing can set up a scene for a screenshot (tl.go(x,y),
  tl.fp(), tl.use(), tl.later(t, callable)).
- test/lobby_life/run.tscn + run.gd: headless logic tests: write test/lobby_life/t_<name>.gd with `func run(t)`
  (see t_core.gd; t.place, t.press_e, t.label, t.hold(action, sec), t.wait(sec), t.check(cond, what)).
- Existing game code to read (DON'T EDIT): scripts/player/player.gd (Player: frozen, dz, facing, odo, moving,
  sprite, read_steer, is_first_person, focus_label), scripts/actors/char_sprite.gd (CharSprite),
  scripts/actors/char_frames.gd, scripts/camera/camera_rig.gd (CameraRig: mode TOP_DOWN/FIRST_PERSON),
  scripts/world/world_builder.gd (WorldBuilder: props, solids `Solid_<name>` StaticBody3D, pool_water,
  ground_boxes()), scripts/npc/gothica.gd, scripts/lobby/trampoline.gd (a good example of a held activity),
  scripts/ui/hud.gd, scripts/game_data.gd (GameData.world_to_3d / from_3d: 1 HTML unit = 0.025 m; HTML (x, y)
  ground, z up), data/game_data.json, assets/manifest.json.

## Rules
- Write ONLY the files your task names (plus new files under scripts/lobby_life/art/<yours>/ and
  test/lobby_life/t_<yours>*.gd). Never edit Smashed.html, godot-play/, other scripts, project.godot, the shared
  framework files above, or another agent's files. If you need a change in a shared file, implement a local
  workaround in your file and describe the wanted change in your report.
- Don't git commit or push (the lead does).
- Both views must work (top-down and first person, V), with keyboard/mouse, gamepad and touch (the HUD's round E
  button works through busy_act; give any extra choice a LobbyUI menu/buttons too, so touch can do it).
- Test in YOUR OWN copy (two Godots importing one folder break each other): 
  `mkdir -p $W && cd /home/user/Smashed-tv/godot && tar --exclude=./.godot --exclude=./build -cf - . | (cd $W && tar xf -)`
  (re-run to refresh after edits), then `~/godot/godot --headless --path $W --import`, then logic tests
  `~/godot/godot --headless --path $W res://test/lobby_life/run.tscn --fixed-fps 60 -- --test=<name>`.
  Screenshots in the real web export: in $W edit project.godot's run/main_scene to "res://scenes/lobby_life/test_lobby.tscn"
  (only in your copy!), `~/godot/godot --headless --path $W --export-release "Web" build/web/index.html`, serve
  `python3 -m http.server <your port> --directory $W` (background), then
  `NO_PROXY=127.0.0.1 node $W/tools/gd_shot.mjs "http://127.0.0.1:<port>/build/web/index.html?lobby=<thing>" out.png 20000`
  (prints the console, errors included). LOOK at the screenshots (Read the png) — top-down and first person —
  and fix what looks wrong. Compare with the HTML game's look (reference/*.png are screenshots of it).
- Godot binary: ~/godot/godot (4.4.1). Watch for GDScript parse errors in the output ("SCRIPT ERROR", "Parse
  Error") — the whole project must stay error-free.
- Match the surrounding code style: doc comments (##) explaining what each part does and which HTML function it
  follows, HTML units in tuning, convert at the edge.
- Final report (short): what works, what you tested (and how), decisions, wanted changes to shared files, what's left.
