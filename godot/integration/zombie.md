# The skeleton zombie: integration note (branch `claude/godot-zombie`)

Status: done

The owner's Mixamo model (`assets/models/zombie/zombie.fbx`, "Skeletonzombie T Avelange", mixamorig skeleton,
T-pose) as a realistic 3D enemy, kept realistic (not pixel-ified) but lit by the game's look: a night zombie in
the backyard and a new enemy type in the arena runs. Based on `claude/github-game-repo-tdm9yz` (a4615bd, the
commit that added the model).

## Install (one line in `scripts/main.gd`, already made on this branch)

Right after `FightInstall.install(self)` (it needs the Fight) and before `Net.install(self)`:

```gdscript
	ZombieInstall.install(self)         # the skeleton zombie: night zombies in the yard (the arena's are in the waves)
```

## What works

- **The model** imports with Godot's own FBX importer (ufbx). Its five embedded 2048 textures are discarded at
  import (`zombie.fbx.import` is committed: `godot/.gitignore` now lets this folder's `.import` files through) and
  replaced by four small ones made from them: `zombie_albedo.png` (1024), `zombie_normal.png` (1024),
  `zombie_cloth.png` (512, the ragged loincloth with its alpha), `zombie_glow.png` (512, its glowing scratches).
  Lossy and mipmapped: about 650 KB of textures and a 360 KB mesh in the web build (instead of ~17 MB). It stands
  1.85 m (the model is 2.06 m; the characters are about 1.6 m).
- **The look** (`zombie_model.gd`): "high" is really lit (the sun or moon with its shadow, the yard and house lamps,
  a normal map, wrap diffuse, a little specular); the phones' "low" look is unshaded with LookPass's own global
  day tint and lamp pools (`LookPass.LOW_FN`, the same globals as the world) plus a soft shape light, toned to
  match the high look. At night its scratches glow. A white flash when hit, a dithered fade when a corpse goes
  (no blending, so no sorting trouble). It sorts correctly against the sprite characters in both views.
- **Animation** (`zombie_anim.gd`): procedural, on the mixamorig bones (Skeleton3D bone poses): the arms out of the
  T-pose, idle sway and breathing, a shambling walk with a dragging leg (stride matched to the distance walked,
  so the feet don't slide), a run, the claw swipe (wind-up, swipe, recovery), a hit flinch laid over whatever it
  is doing, the death fall (knees go, tips back, lands, settles), the scream, climbing out of the ground (and
  sinking back). Each zombie gets its own seed (which leg drags, how its head hangs). Crossfades between moves.
  Any move can come from a real Mixamo clip instead (below).
- **The fight** (`zombie_sim.gd`): enemy type 4 in the FightSim (after the HTML game's four), the same `FT.Enemy`
  records, so every weapon, fists, potatoes, rockets, the nuke, gore (blood, splats, the kill pay of $4), the HUD
  and the online snapshot take it as they are. It climbs out of the ground, screams when it first sees you and
  then charges for a moment, shambles after you, claws (one heart, only in front, the wind-up shows), is
  staggered by hits but doesn't stop a swipe, and falls whole away from the blow. 8 hp (eight blaster hits, four
  punches).
- **The backyard at night** (`zombie_night.gd`): from 9:15 pm to 5:35 am, while someone is out in the yard,
  zombies climb out of the ground in the dark 330-820 units from you (away from you, not across the whole yard),
  one every 11-20 s, up to 2 at once (3 from 11 pm to 4 am, one more online). They keep to the yard (the yard's
  lobby areas minus its solids: the shed, garage, ute, tank, trampoline, fences, bushes, the deck furniture) and
  never come into the house; up on the trampoline you're out of reach. With nobody out there they mill about.
  At dawn they sink back into the ground. Knocked down out there isn't game over: "YOU CRAWLED BACK INSIDE", and
  you're on your feet in the lounge by the back door 3.5 s later; indoors you get a heart back every 5 s (all of
  them in the morning). Sleeping to morning sends them back down too.
- **The arena** (`enemy_sim.gd`'s wave mix): zombies from wave 3 (`zombieWave` in the T table, default 3: one,
  then one more every two waves, at most a quarter of a wave), rising up through the floor away from the
  players instead of coming in from a wall; half of them stop to scream. The wave banner says "zombies".
  Protect Gothica: they go for her too and their swipe hurts her.
- **Both views, every control**: they're the fight's enemies, so top-down and first person, keyboard and mouse,
  pad and touch all work as for the other enemies (nothing zombie-specific to press).
- **Online**: the host's game runs the night; the zombies are in the fight snapshot like any enemy (two new
  `FT.Enemy` fields, `zf` and `zt`, travel by the codec's reflection), so the guest sees them, its shots are the
  host's sim's, it gets clawed, knocked down and brought back inside, and sees them go at dawn (the host's clock).
  Checked with two native games over ENet (`test/zombie/net_zombie.gd`): 12/12 checks on host and guest.
- **Sound** (`zombie_sfx.gd`), made in code like `lobby_sfx.gd`: a rough voice (a jittery pulse train through
  three vowel formants, with breath noise) for five groans, the scream (driven, with a wobble), a swipe's whoosh
  and snarl, a grunt when hit, the death rattle with a thud, and dirt crumbling as one climbs out. Baked a sound a
  frame ahead of the first night, played where the zombie is (3D: from its side in first person). Each zombie
  groans every 3.5-8 s. The game's sound button mutes it with the rest.
- **Performance**: posing a zombie costs 0.06-0.17 ms a frame natively (GDScript), a settled corpse nothing; the
  mesh is 7.4k vertices on two surfaces (four draws with its shadow in "high"). At most 3-4 in the yard; a wave
  has at most a quarter zombies. The web export works in the browser (top-down and a portrait phone checked).
  The `GL_INVALID_OPERATION ... missing fragment shader outputs` warnings in the browser console are there
  without the zombie too.

## Adding real Mixamo animations later

Each move uses a clip when there is one in `godot/assets/models/zombie/anims/`, named for the move; otherwise
the procedural one. Moves and the Mixamo animations that suit them:

| file | move | Mixamo animation | loops |
|---|---|---|---|
| `idle.fbx` | standing, milling about | Zombie Idle | yes |
| `walk.fbx` | the shamble | Zombie Walk | yes |
| `run.fbx` | the charge after a scream | Zombie Running | yes |
| `attack.fbx` | the claw swipe | Zombie Attack | no |
| `hit.fbx` | when shot or punched | Zombie Reaction Hit | no |
| `death.fbx` | killed | Zombie Death | no |
| `scream.fbx` | first sight of you | Zombie Scream | no |
| `rise.fbx` | climbing out of the ground | (any "getting up" one; the body is raised out of the ground by code) | no |

1. On mixamo.com pick the same character (Skeletonzombie T Avelange), choose the animation, tick **In Place**
   for the walk, run and idle, and download as **FBX Binary, Without Skin**, 30 fps.
2. Save it as `godot/assets/models/zombie/anims/<move>.fbx` (the names above; `.glb` / `.gltf` work too).
   Godot's default import settings are fine; no `.import` file needs committing.
3. That's all: the game prints `ZombieAnim: the walk clip from ...` the first time it uses one.

How it plays them: the clip's bone rotations are used as they are (it must be the same skeleton), the hips'
height is scaled to this model, and the looping moves stay in place (any root motion is dropped). The game sets
the timing: a loop is played by the distance walked (so the feet match the ground), the swipe by the wind-up,
swipe and recovery times (0.55 s, 0.22 s, 0.7 s: the clip is stretched over them, its strike best at 45-62% of the
way through), death, the scream and the hit by the clip's own length. A hit clip replaces the move while it plays
(the code's flinch is laid over the move instead). The loader takes the bones by name either from a Skeleton3D
(`Skeleton3D:mixamorig_Hips`) or from plain nodes (`.../mixamorig_Hips`, how a file with no skin can come in);
tested with a clip made in Godot and saved as glTF on this skeleton.

## Files

New: `scripts/zombie/` (`zombie_install.gd`, `zombie_night.gd`, `zombie_sim.gd`, `zombie_view.gd`,
`zombie_model.gd`, `zombie_anim.gd`, `zombie_sfx.gd`), `assets/models/zombie/` (the four textures and the five
`.import` files), `test/zombie/` (tests, shots, gallery, the online drive), this note and `zombie_shots/`.

Small edits in other parts' files:
- `scripts/main.gd`: the install line.
- `scripts/combat/fight_types.gd`: `FT.Enemy.zf`, `FT.Enemy.zt`.
- `scripts/combat/fight_sim.gd`: the zombie added to the ETYPE arrays; `make_corpse` drops one whole body for it.
- `scripts/enemies/enemy_sim.gd`: zombies step with `ZombieSim.step`; in the lobby they keep to the yard instead
  of the arena clamp; the wave mix and banner; arena zombies rise from the floor.
- `scripts/enemies/enemy_view.gd`, `scripts/combat/fight_view.gd`: no sprite or cut-up corpse for a zombie (only
  its contact shadow and hp bar).
- `test/combat/logic_test.gd`: the HTML wave-mix check runs with zombies off; a zombie wave-mix check added.
- `godot/.gitignore`: the zombie folder's `.import` files are committed.

## Testing

All with `--fixed-fps 60` in a work copy:

- `res://test/zombie/zombie_test.tscn`: 34 checks (the type; rising, screaming, chasing, the claw and that it
  only lands in front; the yard rules: never in the house, not in solids, not up on the trampoline; eight hits
  kill it, it falls whole away from the shots and pays; a punch; down in the yard isn't game over; arena waves
  and rising from the floor; the snapshot; every move's bone rotations; then in the real game: zombies at night
  in the yard, drawn as models, knocked down you come to inside, gone at dawn, none by day). All pass.
- The others still pass: `test/combat/logic_test.tscn` 54/54, `test/lobby_life/run.tscn` 286/286,
  `scenes/arcade/arcade_test.tscn -- --logic` 0 failed, `test/dig/dig_test.tscn` 80/80.
- Online: `--host=TEST` / `--join=127.0.0.1` with `--netdrive=res://test/zombie/net_zombie.gd --zombie` (see the
  file's header): 6/6 on each side.
- Pictures: `res://test/zombie/zombie_shot.tscn -- --out DIR --hour=23 [--look=low] name,x,y,mode,zoom[,look_ang]`
  (xvfb-run; "arena..." names start a run), `res://test/zombie/gallery.tscn -- --out DIR [--side] [--low] [--night]`
  (the moves side by side).
- Debug: `--zombie` (`?zombie` on the web) makes it night for the zombies whatever the hour and logs each one
  climbing out; with the web build's `?hour=23.2&zombie&fight=at=1000:1200,god` you start in the yard at night,
  unhurt.

## Screenshots (`zombie_shots/`)

- `yard_night_topdown.jpg`, `yard_night_first_person.jpg`: the yard at 11 pm, high look (one shambling, one
  clawing, one screaming, one fallen).
- `yard_night_topdown_low.jpg`, `yard_night_first_person_low.jpg`: the same in the phones' low look.
- `arena.jpg`, `arena_first_person.jpg`: in a run.
- `phone_portrait_web.jpg`: the web build on a portrait phone (Chromium mobile emulation, low look, zoomed 2x): one
  winding up a swipe behind him.
- `yard_close_depth.jpg`: one just in front of him and one just behind (sorting against the sprite).
- `moves_gallery.jpg`: the procedural moves (idle, walk x3, run, the swipe's wind-up and strike, a flinch, the
  scream, rising, falling, lying).

## Decisions (made for the owner; easy to change)

- Zombies come only while someone is out in the yard at night, and never into the house (the owner: "not in the
  house"); the yard is the place to fight them.
- They climb out of the ground (fits the digging) rather than walking in over the fences.
- Down in the yard you come to inside instead of a game over; your cash is kept.
- $4 a kill (between the batter's $3 and the brute's $5), in the yard too.
- In the arena from wave 3, a quarter of a wave at most.
- The shamble is slower than the grunt (the player runs 260 units/s; a zombie 66, 115 for a moment after its
  scream): the danger is several at once in the dark.

## What's left (if wanted)

- Real Mixamo clips (above): the procedural moves are good stand-ins but a mocap walk and death will look better.
- No dirt mound or particles where one climbs out (the sound and the body coming up through the ground only).
- Zombies don't trample the farm's crops or fall into dug holes (they stand on the dug ground's height).
