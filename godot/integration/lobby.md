# Lobby life (milestone 3): integration note

Branch `claude/godot-lobby`. Owned files: `scripts/lobby_life/`, `scenes/lobby_life/`, `test/lobby_life/`, this note.

## Status (what works, what's left)

Everything is an Interactable (E, pad A and the Hud's round button, both views). Logic tests in
`test/lobby_life/t_<x>.gd` (run them all with the headless runner, see "How to test"); web screenshots looked at for
each thing, top-down and first person.

| thing | file | state |
|---|---|---|
| framework | `lobby_life.gd`, `lobby_thing.gd`, `lobby_pic.gd`, `lobby_ui.gd`, `lobby_sfx.gd`, `lobby_smoke.gd` | done |
| mirror + hair styles | `mirror.gd`, `lobby_look.gd` | done: reflection in the glass as you pass, close-up look, turn, 9 hair styles baked onto Jared's frames |
| wardrobe, shirt picture, change clothes | `wardrobe.gd`, `shirt_editor.gd`, `lobby_look.gd` | done: doors animate, ART picker (web `<input type=file>`) + editor, character change menu |
| bed | `bed.gd` | done: `sleep_requested` / `woke` |
| slot machine | `slot.gd` | done: reels, 8 prizes, notes, speed, magnet |
| vending machine | `vend.gd` | done, stands in the lounge at calls.vendPos |
| barbecue + esky | `bbq.gd` | done |
| mushroom trip | `shroom.gd` | done (screen shader, see decisions) |
| table, bong + trip, cards | `table.gd`, `table_trip.gd`, `table_cards.gd` | see the section below |
| gym, rope | `gym.gd`, `rope.gd` | see below |
| pool, tower, ducks | `pool.gd`, `pool_fx.gd` | see below |
| Gothica's extra life | `goth_life.gd` | see below |

### Signals other sessions can use
- `LobbyLife.sleep_requested(player)` / `woke(player)`: the day/night clock.
- `things["slot"].prize(player, kind)`: kinds `blasters, shotgun, health, speed, clear, cash, magnet, bust`. The lobby effects of
  health (+2 `player.hp` if it has one), speed (T.maxSpeed x1.55 for 10 s), cash, magnet are done here; the rest are for the fighting session.
  Player meta `slot_prize` holds the last kind.
- `things["vend"].prize(player, "launcher")`: player meta `rockets` = 3 and `weapon` = "launcher".
- `things["bbq"].ate(player, burnt)`; player meta `food` 0..3.

### Gotchas found
- `Player.frozen` stops his step **and** his focus, and `Player.use()` returns early when frozen. That's why LobbyLife routes E itself while he's held, writes `focus_label` after the Player's `_process`, and hooks the Hud's `_ebtn.pressed`.
- `free` is Object's own method name: never use it for a function (the framework's is `can_start`).
- The World's lounge furniture is static upright props (`WorldBuilder.props[...]`). Hide one (`visible = false`) and draw the live version yourself (mirror, wardrobe, slot do).
- The player sits *inside* the table's collision box; when he stands, place him outside it.
- CharSprite only resets its texture when the frame path changes. `LobbyMirror.wear(sprite)` sets `_mat`'s "tex" to the baked frame after the sprite updated (priority: LobbyLife is after the Player in the tree).
- Tornado Tyson is Juicy's art recoloured in the shader, so hair and shirt print apply to `char_id == "juicy"` only.
- `GameData.data["T"]` is read live (`CharFrames.t`), so the slot's speed prize writes T.maxSpeed.
- Variant-typed values (`x.get(...)`, JSON dictionaries) need an explicit `var x: Type =` (not `:=`) or the script fails to parse.
- Control children of a CanvasLayer root need `set_anchors_and_offsets_preset` (plain `set_anchors_preset` leaves size 0).
- Web: the first AudioContext needs a user gesture; the screen-texture shader (`hint_screen_texture`) works in the Compatibility web export.

### How to test
- Setup: `bash godot/tools/setup_godot.sh`, which installs `~/godot/godot`.
- Work in a copy, never in `godot/` itself:
  `W=<scratch>/work; mkdir -p $W; (cd godot && tar --exclude=./.godot --exclude=./build -cf - .) | (cd $W && tar xf -)`
  then `~/godot/godot --headless --path $W --import`.
- Logic tests: `~/godot/godot --headless --path $W res://test/lobby_life/run.tscn --fixed-fps 60 -- --test=mirror` (leave out `--test` to run everything).
- Web screenshots:
  1. In the copy only, set `project.godot`'s `run/main_scene="res://scenes/lobby_life/test_lobby.tscn"`.
  2. Export: `~/godot/godot --headless --path $W --export-release "Web" build/web/index.html`.
  3. Serve: `python3 -m http.server 8731 --directory $W` (in the background).
  4. Shoot: `NO_PROXY=127.0.0.1 node $W/tools/gd_shot.mjs "http://127.0.0.1:8731/build/web/index.html?lobby=<thing>[,fp][,extras]" out.png 20000`, then look at `out.png`.
  Scene names: `mirror` (`hair=N`, `turn`), `wardrobe` (`art`), `bed`, `slot` (`mid`, `jackpot`), `vend`, `bbq`, `shroom`, plus the other things' own.

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
