# Lobby life (milestone 3): integration note

Branch `claude/godot-lobby`. Owned files: `scripts/lobby_life/`, `scenes/lobby_life/`, `test/lobby_life/`, this note.

## Handoff (17 Oct, 13:15 UTC: moving to a fresh session)

### Done and working (tested headless: `t_core` 18/18 pass)
- **The framework**, all in `scripts/lobby_life/`:
  - `lobby_life.gd` (`LobbyLife`): `static func install(main)` adds the node to main, placed just before the Hud in main's children so it can override the Player's prompt each frame. It makes every thing (`things` dict by name).
    - **Busy system:** `hold(p, thing)` / `release(p)` freeze the Player (`player.frozen`) and hand him to the thing. While he's held, the thing gets `busy_step`, `busy_label` (written into `player.focus_label`), `busy_act` (E key / pad A / the Hud's round button, hooked through `hud._ebtn.pressed`) and `busy_input`.
    - **Poses:** `set_pose(p, LobbyPic)` replaces his character sprite with a picture.
    - **Money:** `cash`, `add_cash`, `pay`. It uses `player.coins` if that exists, else keeps its own count starting at max(lobbyCash, testCash) = 2500.
    - **Signals:** `sleep_requested(player)` and `woke(player)`, for the day/night clock.
    - **Helpers:** `T()`, `D()`, `calls()`, `hpos()`, `at()`, `is_jared()`, `ensure_action()`, `add_input_actions()`.
  - `lobby_thing.gd` (`LobbyThing extends Interactable`): the base class for every thing, with `put(p, x, y, z)` and `steer(p)`.
  - `lobby_pic.gd` (`LobbyPic`): an upright picture using CharSprite's shader (`CharSprite._shader(false)`), feet at its origin. Set `units_per_px` to 0.5 for the HTML game's half-size art. `recolour_for` gives Tornado Tyson's singlet colours.
  - `lobby_ui.gd` (`LobbyUI`, CanvasLayer 11): speech bubbles that follow people on screen, `float_text`, `info`, `menu()` (big buttons that work with pad, touch and mouse; B/Esc cancels), the `$` money line, `fx_root` for full-screen layers.
  - `lobby_sfx.gd` (`LobbySfx`): sounds made in code (tone and noise rendered to AudioStreamWAV), with named recipes in `play()`.
  - `lobby_smoke.gd` (`LobbySmoke.puff`): smoke and steam puffs, following the HTML's drawSmoke.
  - `goth_life.gd` (`GothLife`): steers Gothica from outside, without editing `gothica.gd`. `claim(owner, spot, speed_mul, face)`, `unclaim`, `at_spot`, `say`, `is_busy`, `held`. It runs at physics priority -10, before hers, and sets her `target`, `wait`, `_speed`, `facing` and `_enabled`.
- **Test scene** `scenes/lobby_life/test_lobby.tscn` (`test_lobby.gd`): makes `scenes/main.tscn`, installs LobbyLife, then reads `?lobby=<thing>[,fp][,...]` from the web address (or `-- --lobby=...` on the command line) and calls `things[<thing>].test_scene(tl, parts)`.
- **Headless runner** `test/lobby_life/run.tscn` (`run.gd`): runs `t_<name>.gd` files, each with `func run(t)`. Helpers: `t.place`, `t.press_e`, `t.label`, `t.hold`, `t.wait`, `t.check`. Only `t_core.gd` exists so far.
- **Specs extracted from Smashed.html**, exact, with HTML line numbers, in `scripts/lobby_life/specs/`:
  - `pool.md`: pool, tower, dive, swim, ducks
  - `gym.md`: bench, plate tree, leg press, rope and potatoes
  - `table.md`: chairs, bong, trip, blackjack
  - `bedroom.md`: mirror, hair, shirt picture, wardrobe, bed
  - `machines.md`: mushroom trip, slot, vending, barbecue, cash
  - `gothica.md`: carry, throw, watching lifts, speech
  - `BRIEF.md`: the build brief I gave each builder agent. **Read it: it's the how-to for this codebase and how to test.**
  - The `extract_*.py` scripts that pulled the art.
- **Art extracted** to `scripts/lobby_life/art/{pool,gym,table,bedroom,machines,gothica}/`, all listed in the specs. Most is drawn at half size, so `units_per_px` 0.5.

### Half-done
- `pool.gd`, `gym.gd`, `rope.gd`, `table.gd`, `mirror.gd`, `wardrobe.gd`, `bed.gd`, `shroom.gd`, `slot.gd`, `vend.gd` and `bbq.gd` are **stubs**: class name and an empty `test_scene`. The builder agents were stopped by the usage limit and then the handoff, before writing any code.
- `goth_life.gd` has the steering API only: no carry, throw or watching yet.
- `art/table/bong_vape.png` and `art/table/prop_nobong.png` were made by the table agent before it stopped. Their purpose is a guess from the names: the bong with the vape in its stem, and the table prop without its bong. Check them before use.

### Next steps, in order
Each step: build from its spec, write `test/lobby_life/t_<x>.gd`, take web screenshots top-down and with `,fp`, look at them, then commit and push.
1. **Table, bong and cards** (`table.gd`; split into `table_trip.gd` and `table_cards.gd` if large). Gothica deals via `goth_life.claim("cards", Vector2(165, 270), 2.4)`.
2. **Gym** (`gym.gd`). Expose `signal rep(player, machine, reps)`, `lifting(p)`, `reps(p)`, `watch_spot(machine)`, `holding_plate(p)`. Then **rope** (`rope.gd`): spud pickups, kept on player meta `spud_ammo` until weapons exist.
3. **Pool and dive tower** (`pool.gd`). Expose `splash(x,y,big)`, `in_water`, `water_rect`, `tower_geo`, `shove_ducks`, `on_tower(p)`. Give the player collision exceptions with `Solid_pool` and `Solid_tower` while swimming or climbing, as `trampoline.gd`'s `_exceptions` does.
4. **Gothica's life** (`goth_life.gd`): carry (only juicy/jared per the spec; player meta `carrying_goth`), throw off the board (`throw_from_board(p)`, `drop_off_board(p, vel)`, which the pool calls), watching lifts (connects to the gym's `rep` signal), and her speech.
5. **Bedroom**:
   - `mirror.gd`: hair styles baked onto Juicy's frames. Swap CharSprite's material `tex` after the Player updates; see the gotcha below.
   - The shirt picture: file picker on the web via JavaScriptBridge.
   - `wardrobe.gd`: opens and offers ART (the shirt picture) plus a character change. The HTML wardrobe can't change clothes; it only has the ART button.
   - `bed.gd`: emits `sleep_requested` and `woke`.
6. **Mushroom trip** (`shroom.gd`): switch to first person plus a screen-texture post-process shader, the timer bar and the music. Check that `hint_screen_texture` works in the web build.
7. **Slot, vending and barbecue** (`slot.gd`, `vend.gd`, `bbq.gd`). Prizes that need fighting systems emit `signal prize(player, kind)`. Put the vending machine at the lounge spot `calls.vendPos` (235, 154); the HTML only has it during a run.
8. Finish this note: what works, decisions, contract changes, what's left.

### Gotchas found
- `Player.frozen` stops his step **and** his focus, and `Player.use()` returns early when frozen. That's why LobbyLife routes E itself while he's held, writes `focus_label` after the Player's `_process`, and hooks the Hud's `_ebtn.pressed`.
- `free` is Object's own method name: never use it for a function (the framework's is `can_start`).
- The World's lounge furniture is static upright props (`WorldBuilder.props["bench" | "rack" | "legpress" | "table" | "rope" | "slot" | "tower" | "wardrobe" | "mirror"]`). Hide one (`visible = false`) and draw the live version yourself.
- The pool is a solid (`Solid_pool`, inset): nobody walks in. In the HTML too, the only way in is off the board.
- The player sits *inside* the table's collision box (chair points 121,302 and 209,302). When he stands, place him outside it (x ≤ 104 or ≥ 226) or `move_and_slide` sticks.
- CharSprite only resets its texture when the frame path changes (`current_path`, `_mat`). To bake in hair or a shirt print, set `_mat`'s "tex" again after each path change.
- Tornado Tyson is Juicy's art recoloured in the shader, so baked hair would show on both. The spec says hair is Juicy-only, so check `char_id`.
- `GameData.data["T"]` is read live (`CharFrames.t`), so a temporary speed multiplier for the slot's speed prize can go there.
- Gothica's own obstacle list only covers furniture near `NPC_AREA`. Claimed spots outside it (the gym) may need a straight path.
- The session usage limit hit with 7 parallel Opus agents. Run fewer at once.

### How to test
- Setup: `bash godot/tools/setup_godot.sh`, which installs `~/godot/godot`.
- Work in a copy, never in `godot/` itself:
  `W=<scratch>/work; mkdir -p $W; (cd godot && tar --exclude=./.godot --exclude=./build -cf - .) | (cd $W && tar xf -)`
  then `~/godot/godot --headless --path $W --import`.
- Logic tests: `~/godot/godot --headless --path $W res://test/lobby_life/run.tscn --fixed-fps 60 -- --test=core` (leave out `--test` to run everything).
- Web screenshots:
  1. In the copy only, set `project.godot`'s `run/main_scene="res://scenes/lobby_life/test_lobby.tscn"`.
  2. Export: `~/godot/godot --headless --path $W --export-release "Web" build/web/index.html`.
  3. Serve: `python3 -m http.server 8731 --directory $W` (in the background).
  4. Shoot: `NO_PROXY=127.0.0.1 node $W/tools/gd_shot.mjs "http://127.0.0.1:8731/build/web/index.html?lobby=table,fp" out.png 20000`, then look at `out.png`.
- An import takes about 13 s and an export about 30 s.

## Install (for the main session, when merging)
Add one line at the end of `_ready()` in `scripts/main.gd`:
```gdscript
	LobbyLife.install(self)
```
That's all. It finds `world`, `player`, `rig`, `hud` and `gothica` on main by name, and adds its input actions in code.

## Input actions added (in code, if missing)
- `lobby_alt`: Q / pad X
- `lobby_back`: Backspace / pad B
- `lobby_prev`: [ , / LB, d-pad left
- `lobby_next`: ] . / RB, d-pad right

The things add more with `LobbyLife.ensure_action`; list them here as they're built.

## Contract changes wanted
- `Player.coins` (the wallet), so lobby money and the fighting session's money are one. Until it exists, LobbyLife keeps its own.
- A Player hook to replace his sprite cleanly (a pose/override texture), instead of hiding `player.sprite` each frame.
- `Hud`: a public way to route the E button while the player is frozen (now done through `hud._ebtn`).

## Decisions (so far)
- The wardrobe also offers a character change ("change clothes", from the owner's brief) besides the HTML's ART/shirt-picture button.
- The vending machine stands in the lounge (`calls.vendPos` 235, 154), because the HTML only has it during a run.
- The slot machine can also be started with E ("SPIN $5"), for pad and touch players. The HTML starts it when you stand still near it.
