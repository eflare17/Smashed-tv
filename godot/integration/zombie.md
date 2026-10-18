# The skeleton zombie: integration note (branch `claude/godot-zombie`)

Status: in progress

The owner's Mixamo model (`assets/models/zombie/zombie.fbx`, "Skeletonzombie T Avelange", mixamorig skeleton,
T-pose) as a realistic 3D enemy: a night zombie in the backyard and a new enemy type in the arena runs.

## Progress

- [x] The model imports (Godot's own FBX importer). Its five embedded 2048 textures are discarded at import
  (`zombie.fbx.import`, committed: `.gitignore` lets this folder's `.import` files through) and replaced by four
  small ones made from them: `zombie_albedo.png` (1024), `zombie_normal.png` (1024), `zombie_cloth.png` (512, the
  ragged loincloth with its alpha), `zombie_glow.png` (512, the glowing scratches). Lossy, mipmapped: about 650 KB
  in the web build instead of ~17 MB.
- [x] The procedural moves on the mixamorig bones (`scripts/zombie/zombie_anim.gd`): idle, walk (a shamble,
  one leg dragging), run, the claw swipe, a hit flinch, the death fall, the scream, climbing out of the ground.
  Each move plays a Mixamo clip from `assets/models/zombie/anims/<move>.fbx` instead when there is one.
- [x] The model in the game's look (`zombie_model.gd`): lit with a normal map in "high", LookPass's low-look tint
  and lamp pools (LOW_FN) in "low"; its glowing scratches at night; a white flash when hit; dithered fade.
- [x] Enemy type 4 in the FightSim (`zombie_sim.gd`): rises, screams, shambles, charges, claws, staggers, falls
  whole; in the arena from wave 3 (`zombieWave`), up through the floor.
- [x] The yard at night (`zombie_night.gd`), the 3D view (`zombie_view.gd`), sounds made in code (`zombie_sfx.gd`).
