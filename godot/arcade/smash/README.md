# Smash — arcade mini-game (stage 1)

A Smash TV-style arena shooter, made to run on its own or on an arcade cabinet screen through a SubViewport.
Everything is in this folder and is built in code: no imported assets, no autoloads, no statics, no physics
bodies, and nothing outside this folder is changed.

## Run it

- Editor: open `res://arcade/smash/smash.tscn` and press **F6** (Run Current Scene).
- Command line: `godot --path godot res://arcade/smash/smash.tscn`

## Controls

Twin-stick. The input actions are added at runtime by `smash_input.gd`, only if missing, and are all named
`arcade_smash_*`, so `project.godot` stays untouched.

| | Keyboard / mouse | Pad |
|---|---|---|
| Move | WASD | left stick, d-pad |
| Aim + fire | arrow keys, or the left mouse button (fires at the cursor) | right stick (pushing it fires); RT / RB fire where you face |
| First-person view on/off | C | Y |
| Restart after game over | Enter (or fire) | Start |
| Debug: +50 grunts | F2 | |
| Debug overlay on/off | F3 | |
| Debug: god mode on/off | F4 | |

In first person the mouse looks around (it's captured; press C to get it back), WASD moves relative to the view,
fire shoots straight ahead, and the arrow keys or right stick turn the view.

## Files

| File | What it does |
|---|---|
| `smash.tscn` / `smash.gd` | scene root: player, cameras, waves, lives, score, debug keys; the per-frame order |
| `smash_horde.gd` | the grunt pool: packed arrays, a spatial grid (counting sort), push-apart, two MultiMeshes (walk frames) |
| `smash_shots.gd` | the bullet pool (one MultiMesh) |
| `smash_gibs.gd` | death chunks and blood splats (pooled, one MultiMesh each, fade out) |
| `smash_hud.gd` | wave / score / lives, banner, crosshair, debug overlay |
| `smash_vox.gd` | voxel meshes (grunt, player, arena, bullet, chunk) and the splat texture |
| `smash_input.gd` | the `arcade_smash_*` actions |
| `smash_bench.tscn` | headless smoke test + stress bench (below) |

## Performance

Nothing is created or freed during play. Grunts, bullets, chunks and splats live in fixed packed arrays (grunts
up to 4096, bullets 512, chunks 3000, splats 600). Each pool is drawn by a MultiMesh filled from one float
buffer per frame. Everything is unshaded vertex colour with no shadows, and there are no physics bodies.

Bench (`godot --headless --path godot --fixed-fps 60 res://arcade/smash/smash_bench.tscn`): every grunt piled
onto the player in god mode (the worst case for the push-apart), simulation time per frame on the cloud
test machine:

| grunts | 250 | 500 | 1000 | 1500 | 2000 | 3000 | 4000 |
|---|---|---|---|---|---|---|---|
| sim ms | 0.8 | 1.1 | 2.3 | 3.3 | 5.4 | 9.5 | 18.5 |

A grunt is 496 triangles, so 2000 grunts is about 1M triangles in 2 draw calls.

## Putting it on a cabinet (later)

- Instance `smash.tscn` inside a `SubViewport`. The root sets `own_world_3d = true` on that SubViewport so the
  arena doesn't appear in the main game's 3D world. Its cameras and HUD draw only in that viewport.
- Set `input_enabled = false` while the cabinet isn't being played. The game reads the global `Input`, so it
  would otherwise react to the player walking around.
- Mouse aiming uses the SubViewport's mouse position, so the SubViewportContainer (or whatever shows the screen)
  has to forward input to it.
- `score`, `wave`, `lives` and `game_over` are plain properties on the root.
