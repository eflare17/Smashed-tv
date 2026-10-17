# Smashed TV in Godot: the plan

The HTML game (`Smashed.html`, saved on the branch `html-version-b331`) stays live and untouched. This
folder is the Godot 4.4.1 version, built alongside it, milestone by milestone, each one playable on the web.

## Ground rules (every agent)

- **Godot 4.4.1**, the Compatibility renderer (it's the one that runs in a web browser and on phones).
  GDScript only. Pixel art is drawn with nearest filtering, never blurred.
- **The HTML game is the spec.** `data/game_data.json` holds its measurements and tuning, read from the running
  game (rooms, the yard, solid things and their heights, the trampoline, the pool, furniture, enemy and weapon
  numbers, every value in its `T` table). `reference/*.png` are screenshots of it. When in doubt, read
  `Smashed.html` itself: it's the source of truth for how things behave.
- **Positions:** the HTML game's `(x, y)` is the ground (x across, y down the screen = north-south) and `z` is
  height. `GameData.world_to_3d(x, y, z)` turns them into Godot's 3D space (1 HTML unit = 0.025 m: his eyes,
  62 up, are 1.55 m). Keep using HTML units in tuning and data; convert at the edge.
- **Art:** every picture from the HTML game is in `assets/`, listed in `assets/manifest.json` by the name it had
  there (`CHARS`, `ENEMY_SPRITES`, `LOUNGE_IMG.src`, `YARD_IMG@1985`...). The repo's `art/` folder is in
  `assets/art/`. Load with `GameData.tex(path)`.
- **Own your files.** Each agent writes only the files its task names. Shared interfaces are the stubs in
  `scripts/` (their `class_name`, signals and the functions marked CONTRACT); change a contract only if your
  task says so.
- **Test in your own copy.** Copy `godot/` to a folder of your own, run Godot there (two Godots importing the
  same folder at once break each other), then copy your files back. Godot:
  `/tmp/claude-0/-home-user-Smashed-tv/40d03639-c1d3-588b-80f5-e1432bd44625/scratchpad/godot/Godot_v4.4.1-stable_linux.x86_64`
  (`--headless --path <dir> --import`, then `--headless --path <dir> --export-release "Web" build/web/index.html`).
  Look at it running: serve the folder (`python3 -m http.server <port> --directory <dir>`, a port of your own),
  then `NO_PROXY=127.0.0.1 node /tmp/claude-0/-home-user-Smashed-tv/40d03639-c1d3-588b-80f5-e1432bd44625/scratchpad/gd_shot.mjs http://127.0.0.1:<port>/build/web/index.html out.png 15000`
  saves a screenshot and prints the console (errors included). Look at the screenshot.
- **Never touch `Smashed.html`** or anything outside `godot/`. Don't commit or push: that's done after.

## Decided with the owner (17 Oct)

- **Controls:** PC first (keyboard and mouse), with full **gamepad** support (Xbox, PlayStation, Steam
  Controller; menus usable without a mouse), and **really good phone and tablet** support. Every control goes
  through Godot input actions (move, look, fire, roll, interact, ...) that the keyboard/mouse, a pad and touch all
  drive; the game notices the last device used and shows the matching prompts ("E", the pad button, or an
  on-screen button). Touch: top-down twin sticks with roll and E buttons; first person left-thumb move, drag to
  look, fire and jump buttons; sizes scale with the screen (tablets get a real layout); landscape. Each arcade
  game gets its own controls per device (Snake: swipe / d-pad; Bricks: drag the paddle / stick; Sand Miner:
  on-screen walk, jump, dig). Test phone speed from milestone 1; lighter settings on phones if needed.
- **Views:** top-down and first person both fully supported, everything working in both (decided for the owner;
  they can change it).
- **What comes across:** everything (decided for the owner; they can trim it).
- **Lighting:** dynamic, from the day and night cycle (1.4).

## What the HTML game has (the inventory)

**Places.** The lounge (wood floor and rug: the table and two chairs, a bong, cards; the gym: bench press with a
bar and plates, a plate rack, a leg press with horns, a bell rope that rains potatoes; the pool with a dive tower,
ladder and springboard, rubber ducks; three arcade cabinets (Sand Miner, Bricks/Mega Drive, a broken one); the slot
machine; a vending machine; a mushroom that sends you on a trip; dummies and cans to shoot). The bedroom below
(bed, nightstand, wardrobe that opens, full-length mirror). The backyard (b322 to b330): a back door onto a deck,
a barbecue you can cook on and an esky of snags, an outdoor table and chairs, a garage, a ute in the driveway, a
shed, fences, a crop bed, a water tank, a trampoline with a net (bounce, bounce higher, jump off). The wave arena
(the Smash TV room: enemies come in waves).

**People.** Playable: Juicy Jared, Tornado Tyson, Gothica (and old-art versions). Each has run cycles in five
directions (front, front-diagonal, side, back-diagonal, back; the other side by flipping), standing frames, a
4-frame roll, some a victory dance; weapon versions (spud gun, shotgun, nuke launcher). Hair styles from the
mirror (Jared). A shirt picture printed on Jared's singlet. Gothica also wanders the lobby: walks round the
furniture, watches you lift, deals cards, says things, can be carried by Jared and thrown off the board.

**Fighting.** Fists, the spud gun (potatoes as ammo, growing on the floor, reload, pickup), the potato throw (wind
up, lob, landing ring), blasters, shotgun, nuke launcher (rockets, blasts), a weapon bar (1-6). Enemies: grunt,
swarmer, brute, batter (wind-up swing); walk rigs; gore (cut into pieces, corpses); coins and cash; the slot
machine prizes; the vending machine; the janitor; waves with breathers; Protect Gothica mode; game over.

**Views.** Top-down (the main view, with zoom levels), first person (V: mouse look, clicks shoot, E prompt,
phones with sticks and a fire button), the mushroom trip.

**Other.** Online co-op with a friend (PeerJS: host and join by room code, the host runs the game), the arcade
games (Snake, Bricks, Sand Miner), the Mega Drive/SNES emulator cabinet, sounds (all made in code), the tuning
panel, the farm plans (FARM.md).

## Milestones

1. **The 3D world (now).** The lounge, bedroom and yard as real 3D: floors with their art, walls with the door
   gaps, every solid thing at its height (boxes wearing their part of the art, roofs where the HTML game has
   them), furniture and machines as upright sprites or boxes. The player (choose Juicy Jared, Tornado Tyson or
   Gothica) walking with the HTML game's speed and feel, colliding with walls and solids, rolling. Characters as
   sprites that pick the right one of five directions (and flip) for where the camera is. Two cameras: top-down
   (like the HTML game, following you) and first person (V; mouse look with the pointer captured; Esc lets go).
   E with an on-screen prompt for what it does. The trampoline (climb on, bounce, Shift higher, jump off). Gothica
   wandering. A build label. Exported for the web. **The test of the whole idea: does it feel better?**
1.4. **The day and night cycle** (decided by the owner, 17 Oct): the lighting is dynamic, driven by one game
   clock (an autoload `GameClock`): day number, time of day, signals `hour_changed`, `day_started`. **A day is 20
   real minutes** (7 am to 9 pm in about 14 minutes, the night in about 6), one tunable number. The sun, sky,
   ambient light and indoor lamps follow it. Lying in the bed skips to 7 am and the next day (online: when both
   players are in bed). Online, the host's clock is the one; it goes to the guest in the snapshot. A save of the
   day and time. **Why:** the owner's friend is building a trading game in the spirit of Dope Wars and Schedule I
   that will plug in later: each day is a market day (prices change, events happen) through `day_started`. Build
   the hooks, not the trading.
1.5. **The look pass.** The big visual jump, in the "HD-2D" style (pixel-art characters in a lit 3D world,
   like Octopath Traveller): real lighting and soft shadows, a sky in the yard (sunny or golden hour), warm lamps
   indoors, glow on the arcade screens and the pool, a light haze in the distance and a gentle blur on far-off
   things. Some effects are limited in the web build: use what the Compatibility renderer can do.
   (Later, whenever there are models: real 3D models for the furniture, machines and buildings instead of boxes
   wearing pictures. That needs the models made first.)
2. **Fighting.** Weapons, shooting in both views, enemies and waves in the arena, gore, coins, the weapon bar,
   Protect Gothica.
3. **Lobby life.** The pool and dive tower, the gym, the table and the bong, cards with Gothica, the mirror and
   hair, the shirt picture, the wardrobe, the mushroom, the slot and vending machines, the barbecue.
4. **Playing together online.**
5. **Extras.** Arcade games, Sand Miner, the farm, phone controls polish, the emulator cabinet (web build: open
   EmulatorJS over the game through JavaScriptBridge, as the HTML game does; the library, the console picker,
   and a friend joining as player 2 over the milestone 4 connection). With it, the **Google Drive games folder**
   (decided: built here, not in the HTML game): "Connect Google Drive" in the cabinet's menu, signing in with
   Google, listing the games in a folder shared with your friend by Gmail. Needs the OAuth client ID from the
   owner (Google Cloud project, Drive API on, consent screen in Testing with the friends as test users, origin
   https://eflare17.github.io).

## Milestone 1: who does what

| Part | Files | Job |
|---|---|---|
| World | `scripts/world/*` | Build every room, wall, solid and prop from `game_data.json`, with collision. |
| Characters | `scripts/actors/char_sprite.gd`, `scripts/actors/char_frames.gd` | Pick and animate the right frame. |
| Player and cameras | `scripts/player/*`, `scripts/camera/*`, `scripts/ui/*` | Moving, rolling, E, the two views, the prompt and HUD. |
| Trampoline and Gothica | `scripts/lobby/trampoline.gd`, `scripts/npc/*` | The trampoline, and Gothica wandering the lobby. |
| Putting it together | `scenes/main.tscn`, `scripts/main.gd` | Wire it all up, export, test, fix what doesn't fit. |
