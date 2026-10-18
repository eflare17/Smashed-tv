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
