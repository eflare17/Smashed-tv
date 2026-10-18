# Lobby life (milestone 3): integration note

Mirror fix: done. Cause: `LobbyMirror.wear` only handled `char_id == "juicy"`, but the fight session puts weapon sheets (`juicy_spud`, `juicy_shotgun`, `juicy_launcher`) on the player's CharSprite. Now every `juicy*` CharSprite in the tree is found (rescan every 0.4 s) and wears the hair and print; frames without a HAIR_FIT entry (victory, extras) get the hair slid by the sunglasses' offset from the run frame 0; the print goes on every frame except the roll frames (rolls get hair only if sunglasses are found, otherwise nothing, as in the HTML game). The reflection copies the real sprite (its sheet, roll action, moving, odo, facing with y turned round: facing the glass shows his front, facing away his back). Test scenes: `?lobby=mirror,walk,hair=5,art,skin=juicy_spud[,fp]`. `t_look.gd` covers it. Test harness: `LobbyLife.existing(main)` reuses the LobbyLife main.gd already installs (two installs made E go to two mirrors).

Status: done (all things built and tested; polish items listed under "What's left"). 286+ logic checks pass (`run.tscn`, no `--test`).

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

The things add more with `LobbyLife.ensure_action`:
- `lobby_hair`: F (mirror, Shift+F goes back)
- `table_deal`: B / pad X, `table_hit`: H / pad Y, `table_stand`: T / pad B (table, bong, cards)

## Contract changes wanted
- `Player.coins` (the wallet), so lobby money and the fighting session's money are one. Until it exists, LobbyLife keeps its own.
- A Player hook to replace his sprite cleanly (a pose/override texture), instead of hiding `player.sprite` each frame.
- `Hud`: a public way to route the E button while the player is frozen (now done through `hud._ebtn`).

## Decisions (so far)
- The wardrobe also offers a character change ("change clothes", from the owner's brief) besides the HTML's ART/shirt-picture button.
- The vending machine stands in the lounge (`calls.vendPos` 235, 154), because the HTML only has it during a run.
- The slot machine can also be started with E ("SPIN $5"), for pad and touch players. The HTML starts it when you stand still near it.

## Table, gym, rope (built by a helper, tested: t_table, t_gym, t_rope)
- Table: SIT at a chair, BONG / HIT (6.2 s); a second hit 3..30 s after the first starts the 13.8 s mantis trip (local player only); blackjack with Gothica dealing (bet 10, blackjack pays 25). Sit panel, CARDS circle and blackjack panel are real buttons (touch ok). First person sits low and can look round.
- Gym: bench, plate tree, leg press with the HTML's labels; `LobbyGym` has `signal rep(player, machine, reps)`, `lifting(p)`, `reps(p)`, `machine_of(p)`, `watch_spot(machine)`, `watch_at(machine)`, `holding_plate(p)`, `drop_plate(p)` (the pool calls it on a dive).
- Rope: PULL rings the bell, 10 potatoes drop; walking over one gives +10 `spud_ammo` (player meta, cap 200), `signal picked`.
- Player meta `carrying_goth` blocks sitting, the gym and the rope.
- Decisions: Tyson reuses Jared's sit/bench/leg-press art (recoloured); the top-down seated zoom is skipped.
- Left: second seat for a second player, generic seated pose for non-Jared, potato spin, run-start auto-rack of held plates; wanted Player hook to suppress roll while holding a plate.

## Pool, tower, ducks and Gothica's life (built by a helper: t_pool, t_goth)
- Pool: ladder (push up at the foot or E "CLIMB"), board, fall, swim, climb out at an edge; ducks; waterline shader on the swimmer (reads CharSprite's private `_SHADER_CODE`, `_mat`, `_path`); splash/ripple/drips in `pool_fx.gd`. API: `splash(x,y,big)`, `in_water`, `water_rect`, `tower_geo`, `shove_ducks`, `on_tower(p)`, `diving(p)`, `swimming(p)`; signals `dived`, `splashed`. The trip clock (shroom) holds while `on_tower`.
- Gothica (`goth_life.gd`, now a LobbyThing): E "PICK UP"/"PUT DOWN" (juicy/jared only, meta `carrying_goth`), thrown off the board by the pool's E (`throw_from_board`) or dropped off its tip (`drop_off_board`), cartwheel, swims 3.5 s, climbs out; "OOF" if she misses. Watches lifts through the gym's `rep` signal ("Wow, you're really strong!" at 5 reps). Claims: cards > watch > rest.
- Decisions: top-down heights on the tower are adjusted so the screen height matches the art (first person uses true heights); first person climbs/walks the board slowly, house cut away above eye height ~140; extras E dives / climbs out; "^" instead of an arrow glyph.
- Test scenes: `?lobby=pool[,climb|board|dive|swim|splash|wet][,fp]`, `?lobby=goth_life[,carry|throw|swim|floor][,fp]` (thing keys, not `goth`).
- Left: first-person board sag/creak, whoosh/somersault, FP splash arpeggio; Gothica's jiggle and the over-head tip.

## Left for the main session
- Add `LobbyLife.install(self)` at the end of `main.gd`'s `_ready()`; connect `LobbyLife.sleep_requested` to the day clock; the fighting session picks up `prize` signals and `rockets` / `spud_ammo` / `food` metas.
- Wanted: a Player hook to suppress roll/shoot while holding a plate; `Player.coins` as the shared wallet (LobbyLife keeps its own until then).
