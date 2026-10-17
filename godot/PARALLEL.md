# Building in parallel: the extra sessions

The owner asked (17 Oct, 12:50 UTC) for extra cloud sessions so the Godot build goes faster. Each session works
on its own branch, in its own files, and the main session (branch `claude/github-game-repo-tdm9yz`) merges them.

| Session | Branch | Builds | Owns (only writes these) |
|---|---|---|---|
| Main | `claude/github-game-repo-tdm9yz` | Finish M1, M1.4 day/night, M1.5 look, merging, M4 online | everything not listed below, `scripts/main.gd`, `scenes/main.tscn`, the contracts |
| Fighting | `claude/godot-fighting` | M2: weapons, shooting in both views, enemies, waves, arena, gore, coins, weapon bar, Protect Gothica | `scripts/combat/`, `scripts/enemies/`, `scripts/arena/`, `scenes/combat/`, `test/combat/`, `integration/fighting.md` |
| Lobby life | `claude/godot-lobby` | M3: pool and dive tower, gym, table and bong, cards with Gothica, mirror and hair, shirt picture, wardrobe, mushroom trip, slot and vending machines, barbecue, Gothica's extra life (watching lifts, carry and throw, speech) | `scripts/lobby_life/`, `scenes/lobby_life/`, `test/lobby_life/`, `integration/lobby.md` |
| Arcade | `claude/godot-arcade` | M5 part: the arcade cabinets' games (Snake, Bricks, Sand Miner) with per-device controls, the emulator cabinet (EmulatorJS over the game via JavaScriptBridge, as the HTML game does: library, console picker) | `scripts/arcade/`, `scenes/arcade/`, `test/arcade/`, `integration/arcade.md` |

## Rules for every extra session

- Read `PLAN.md` (ground rules, decisions with the owner) first. **The HTML game (`../Smashed.html`) is the spec.**
- **Never** touch `Smashed.html`, `godot-play/`, main, or another session's files. Don't edit `scripts/main.gd`,
  `scenes/main.tscn` or any existing script: if you need a change in one, write it in your integration note
  (exact code), and work around it meanwhile (subclass, a wrapper, connect from outside).
- **Hook in from outside.** Give your part one entry point: a script with
  `static func install(main: Node) -> void` that adds your nodes to the running game (it can reach `main.world`,
  `main.player`, `main.rig`, `main.hud`, `main.gothica`, `main.trampoline`). Your test scene instantiates
  `scenes/main.tscn` and calls your install, so you test inside the real game. The main session adds the one
  call to `main.gd` when it merges.
- **Interactables:** extend `Interactable` (`scripts/interact/interactable.gd`, group "interactable", `label_for`,
  `act`), so E and the on-screen button work for you in both views.
- **Input:** add input actions in code at startup (`InputMap.add_action` if missing) rather than editing
  `project.godot`; list them in your note. Keyboard/mouse, gamepad and touch for everything.
- **Setup:** `bash godot/tools/setup_godot.sh` installs Godot and the web template (prints the binary path).
  Import `--headless --path godot --import`, export `--headless --path godot --export-release "Web" build/web/index.html`,
  serve `python3 -m http.server <port> --directory godot`, screenshot
  `NO_PROXY=127.0.0.1 node godot/tools/gd_shot.mjs http://127.0.0.1:<port>/build/web/index.html out.png 15000`
  (prints the console). Look at your screenshots. Headless runs with `--fixed-fps 60` are good for logic tests.
- **Commit and push often** to your branch (`git push -u origin <branch>`), so nothing is lost. Keep commits to
  your own files (and `integration/<name>.md`).
- **Don't stop to ask** (the owner is asleep): make the call that best fits the HTML game and log it in your
  integration note under "Decisions". End with the note listing: what works, how to install it (the exact
  `main.gd` lines), input actions added, contract changes wanted, what's left.
