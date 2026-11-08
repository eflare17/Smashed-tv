# Dig Site: notes, decisions and open questions

The Dig Site is a 3D voxel digging and mining location in the PC voxel arena (Smashed), reached through the phone's
Travel app, co-op from the start. Code lives in `godot/scripts/voxel/digsite/`, scenes in `godot/scenes/voxel/digsite/`.

## Decisions

- **The branch.** The phone (and St Kilda, its first place) was on `claude/stkilda-voxel`, a branch made from
  `claude/godot-voxel`. `claude/godot-voxel` was fast-forwarded onto it (8 Nov) so the Dig Site sits next to St Kilda
  on the phone. Nothing was rewritten: `claude/stkilda-voxel` was this branch plus 39 commits.
- **Where it is.** Like the gun range (3 km west of the arena), the Dig Site is 3 km east of it in the arena's own
  world (`DigSite.AT = (3000, 0, 0)`), under its sky. So the player, the backpack, the tools, the co-op link and
  the other player's avatar all just work there. The arena waits while you're there (`VoxelArena.elsewhere()`).
- **Co-op travel.** The phone's Travel was off in co-op (St Kilda's choice). It now offers Home and the Dig Site with a
  mate: the host's choice takes both players (message "D" `go`); a guest's choice is asked of the host (`want`), who
  then sends both. St Kilda, its game and the gun range stay off in co-op.
- **The scene.** `scenes/voxel/digsite/dig_site.tscn` is a plain Node3D with `dig_site.gd`. The arena instances it
  and calls `setup(arena)`.

- **The ground (stage 2).** `DigSiteGrid`, a C++ GDExtension in `scripts/voxel/digsite/native/` (built like
  `addons/mine_sim`: `GODOT_CPP=<godot-cpp> sh scripts/voxel/digsite/native/build.sh`, Linux .so and Windows .dll
  committed in `bin/`). The yard's voxel terrain is GDScript and 12.5 cm blocks; the Dig Site uses the same block size
  but 512 x 192 x 512 cells (64 m x 24 m x 64 m: 4 m of air over 20 m of ground), 50 M cells, a byte each (the
  material in the low 5 bits, a LOOSE bit for stage 4). That's too much for GDScript, so the cells, generation,
  digging and meshing are C++; streaming and the scene nodes are GDScript (`ds_terrain.gd`). Materials (names,
  colours, hardness, what a block becomes in the backpack) in `ds_mats.gd`, mirrored in the C++ enum.
- **Sections and chunks.** Drawn and collided in sections of 32 x 64 x 32 cells (4 m x 8 m x 4 m: 16 x 3 x 16 of
  them). Changes are also tracked in 16^3 data chunks for the network (stage 5). Only changed sections rebuild,
  nearest first, at most 4 ms a frame (one more section can run over: the worst frame seen is ~7 ms with everything
  dirty). Collision (a concave shape from the same faces) only within ~15 m of a player. Drawing covers the whole
  site from anywhere on it (R_MESH 96 m): with the far ground undrawn you'd see the sky through it. Underground
  sections have no faces until dug, so this costs little. Arriving builds what it can in 0.9 s while the screen's
  black, then the rest streams in.
- **The seed.** Fixed for now (`DigSite.SEED`). Co-op sends the host's (stage 5), saves keep each site's (stage 12).
- **Layers.** Topsoil (grass on top) ~0.5 m, dirt to ~3 m, clay to ~7 m, stone to ~15 m, hard rock to bedrock at 20 m,
  boundaries wavy. Pockets: sand, gravel and clay lenses in the soil, coal shallow in the stone, iron deeper, gold
  deeper still, gems right down. A 1 m ring of undiggable EDGE round it so no hole opens onto nothing.

## Open questions

- Pre-existing, not from the Dig Site: St Kilda's own test prints thousands of "Out of bounds set index" errors from
  `sk_crowd.gd:345` headless (it still says PASS). Worth a look by whoever owns St Kilda.

## Stages

1. Scene + phone travel: done.
2. 3D voxel ground: done (`test/voxel/digsite_ground_test.gd`, 20 checks).
