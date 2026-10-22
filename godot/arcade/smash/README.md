# Smash — arcade mini-game (stage 2)

A Smash TV-style arena shooter, made to run on its own or on an arcade cabinet screen through a SubViewport.
Everything is in this folder and is built in code: no imported assets (sounds are synthesised too), no
autoloads, no statics, no physics bodies, and nothing outside this folder is changed. The one file it writes
is its own high-score table, `user://arcade_smash_scores.cfg`.

## Run it

- Browser (nothing to install): https://eflare17.github.io/Smashed-tv/smash-play/ — `smash-play/` in the repo's
  top folder, reusing the main game's web engine from `godot-play/`. After changing the game, rebuild it with
  `bash godot/arcade/smash/build_web.sh` and commit `smash-play/`.
- Windows: double-click **`Play Smash.bat`** in the repo's top folder. It finds Godot 4.4 (the `GODOT`
  environment variable, the PATH, or the Desktop / Downloads / Documents / Program Files folders), or offers to
  download Godot 4.4.1 once into `%LOCALAPPDATA%\SmashedTV`, then runs this scene (`play_smash.ps1`).
- Editor: open `res://arcade/smash/smash.tscn` and press **F6** (Run Current Scene).
- Command line: `godot --path godot res://arcade/smash/smash.tscn`

## The game

- **Attract mode**: it starts like an arcade machine, with a bot playing a demo under the title, the high-score
  table and the controls, in turn. Fire or Enter starts a game. The demo is silent unless `attract_sound` is on.
- **Rooms**: each room is 2 waves. Clearing it lights one door green and shuts the others; walk out through the
  green door to fade into the next room (new colours, harder). Grunts don't use the door you came in by
  during a room's first wave.
- **Brutes** (from room 2, more each room): big, slow, 6 hits (each flashes him red and knocks him back), shove
  grunts aside, 500 points, and half the time drop a power-up.
- **Power-ups**: killed grunts sometimes drop a crate (brutes often do). It lasts 9 s and blinks before it goes.
  - SPREAD: 5-way shot, 10 s.
  - ROCKETS: a blast that kills every grunt within 2.6 m and takes 4 off a brute, 10 s.
  - SHIELD: grunts that touch you pop and brutes get clubbed, you can't be hurt, 8 s.
  - SPEED: 1.6x, 10 s.
  The timers show under the room / wave line. Dying loses them.
- **The host** drops down in the top-right corner with a speech bubble and a gibberish voice. He says
  "I'D BUY THAT FOR A DOLLAR!" for pickups and big rocket kills, plus lines for a new game, room clear, death,
  game over, a high score and every 150 kills. Important lines cut in; the rest wait out a 7 s cooldown.
- **Feel**: synthesised sounds for every event, a muzzle flash, camera shake (kills, blasts, deaths), a red flash
  when you're hit, explosion flashes with scorch marks, and dust when you have SPEED.
- **High scores**: top 10 with initials and the room reached. Type the letters, or press up / down to change a
  letter and fire to move on (Enter finishes, Backspace goes back).

## Controls

Twin-stick. The input actions are added at runtime by `smash_input.gd`, only if missing, and are all named
`arcade_smash_*`, so `project.godot` stays untouched.

| | Keyboard / mouse | Pad |
|---|---|---|
| Start a game | Enter (or fire) | Start (or RT) |
| Move | WASD | left stick, d-pad |
| Aim + fire | arrow keys, or the left mouse button (fires at the cursor) | right stick (pushing it fires); RT / RB fire where you face |
| First-person view on/off | C | Y |
| Initials | type them, or arrows + fire / Enter | d-pad or stick + RT / Start |
| Debug: +50 grunts | F2 | |
| Debug overlay on/off | F3 | |
| Debug: god mode on/off | F4 | |

In first person the mouse looks around (it's captured; press C to get it back), WASD moves relative to the view,
fire shoots straight ahead, and the arrow keys or right stick turn the view.

## Files

Each script is preloaded under a `Smash*` name (`SmashHud`, `SmashSfx`...) because the main game has global
classes called `Hud` and `Sfx`, and a global class name wins over a local constant of the same name.

| File | What it does |
|---|---|
| `smash.tscn` / `smash.gd` | scene root: states, player, power-ups, rooms and waves, kills, cameras and shake; the per-frame order |
| `smash_horde.gd` | the grunt pool: packed arrays, a spatial grid (counting sort), push-apart, two MultiMeshes (walk frames) |
| `smash_brutes.gd` | the brute pool: HP, hit flash, knock-back, shoving grunts, two MultiMeshes with colours |
| `smash_shots.gd` | bullets and rockets (one pool, a MultiMesh each); rockets report where they went off |
| `smash_gibs.gd` | chunks, blood / scorch splats and explosion flashes (pooled, one MultiMesh each, fade out) |
| `smash_pickups.gd` | the power-up crates (4 fixed slots) |
| `smash_host.gd` | the TV host: his own little SubViewport, drop-down, mouth flaps, speech bubble |
| `smash_sfx.gd` | every sound, synthesised at start-up, and the host's babble |
| `smash_hud.gd` | top bar, banner, crosshair, debug overlay, hurt flash, room fade, attract screens, initials |
| `smash_scores.gd` | the high-score table (load, save, insert) |
| `smash_bot.gd` | the attract-mode demo player |
| `smash_vox.gd` | voxel meshes (grunt, brute, player, host, arena, rocket, crate...) and the splat / blast textures |
| `smash_input.gd` | the `arcade_smash_*` actions |
| `smash_bench.tscn` | headless smoke test (27 checks) + stress bench (below) |

## Performance

Nothing is created or freed during play. Grunts (up to 4096), brutes (128), shots (512), chunks (3000), splats
(600), blasts (32) and pickups (4) live in fixed pools, and each is drawn by a MultiMesh filled from one float
buffer per frame. Rooms change colour through their materials, so nothing is rebuilt. The host's viewport only
renders while he's on screen. Everything is unshaded vertex colour with no shadows, and there are no physics
bodies.

Bench (`godot --headless --path godot --fixed-fps 60 res://arcade/smash/smash_bench.tscn`): every grunt piled
onto the player in god mode (the worst case for the push-apart), simulation time per frame on the cloud
test machine:

| grunts | 250 | 500 | 1000 | 1500 | 2000 | 3000 | 4000 |
|---|---|---|---|---|---|---|---|
| sim ms | 0.6 | 1.4 | 2.6 | 3.1 | 4.7 | 10.2 | 19.9 |

A grunt is 496 triangles, so 2000 grunts is about 1M triangles in 2 draw calls.

## Putting it on a cabinet (later)

- Instance `smash.tscn` inside a `SubViewport`. The root sets `own_world_3d = true` on that SubViewport so the
  arena doesn't appear in the main game's 3D world. Its cameras and HUD draw only in that viewport.
- Set `input_enabled = false` while the cabinet isn't being played: it ignores all input and keeps running its
  demo, like a real machine. `attract_sound` (off by default) lets the idle demo make noise.
- Mouse aiming uses the SubViewport's mouse position, so the SubViewportContainer (or whatever shows the screen)
  has to forward input to it.
- `state`, `score`, `room`, `wave`, `lives` and `game_over` are plain properties on the root.
