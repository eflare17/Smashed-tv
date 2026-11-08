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

- **Hand tools (stage 3).** The arena's own shovel and pick (VoxelTool) dig the Dig Site's ground when you're there
  (`DsTools` does the digging: a block a block into the backpack, by DsMats.ITEM). The shovel keeps its yard tiers
  (the tool bench). New: a Hammer (weapon `hammer_ds`, group 6; the arena's "hammer" is the sledgehammer) that chips a
  block or two now and builds supports in stage 8. The pick and the hammer have Dig Site tiers (Steel pick, Diamond
  pick; Framing hammer, Nail gun), made at the site office's counter (E) out of ore dug there. Gems need a steel
  pick. Tiers are saved in the arena save (`digsite_tools`). New items: sand, gravel, coal, iron ore, gem (gold is the
  yard's gold nugget).
- One block = one item, so a rusty shovel scoop is ~14 dirt. Fine for now; may want to divide later if the backpack
  fills too fast.

- **Loose dirt (stage 4).** In C++ (`native/src/dig_site_dirt.cpp`), a cellular version of the digger game's
  dirt_sim. A cell is firm (as made) or loose (dug and dumped: the LOOSE bit). Loose cells fall into air and slump
  wherever the drop over 1, 2 or 3 cells out is more than ~34 degrees allows (eight ways round), so piles stand at
  ~31-34 degrees. A firm soil wall stands straight up to its material's height (`DsMats.WALL`: topsoil 1.25 m,
  dirt 1.5 m, clay 2.5 m, sand 0.4 m, gravel 0.6 m) and gives way past that or past ~60 degrees: its rim turns
  loose and slumps. Rock never gives way here (cave-ins are stage 7). Cells only swap with air, so nothing is ever
  made or lost (`test/voxel/digsite_dirt_test.gd` counts every material before and after).
  Only awake 16^3 chunks are worked on (woken by a change within 4 cells), 20 ticks a second, 2.5 ms a tick at
  most; the rest waits. Dumped dirt (the shovel's right click, machines' buckets) is loose.
- The stage 4 commit also carries the C++ for stage 5's sync (chunk diffs, checksums), built in the same library.

- **Co-op sync (stage 5).** `ds_net.gd` (DsNet), the layer later stages plug into, after the shared mine's MineNet:
  - The host owns the ground and runs the dirt. Arriving, the guest says "hello" and gets the host's seed plus every
    chunk changed since the ground was made (zstd, in 48 KB parts). Its own site is kept aside and put back when it
    goes home.
  - The host sends the 16^3 chunks changed since last time, 15 times a second (zstd), with the number of the guest's
    last action it has done.
  - Actions (`act(kind, args)`, handlers by `register_op`): "dig", "fill", "drop" now; later stages add theirs. The
    guest does each at once on its own copy (instant, and its backpack gets what came up) and sends it; until the
    host's chunks confirm it, the guest re-does it on top of each update.
  - Every 2 s the host sends its sections' checksums (each chunk's hashed only when changed); the guest (with nothing
    of its own pending) compares and asks for any section that's drifted, and gets its chunks back.
  - Events (`event`, `register_event`): one-off fx, e.g. the other player's tool dust and sound. Fast states
    (`send_fast`, first byte 68, `register_fast` by id): unreliable, for machines from stage 6.
  - Players and tool swings were already synced by the arena's net. Tested with two copies, also at 150 ms lag and
    10% loss (`test/voxel/digsite_sync_test.gd`).
  - Rough edges: the guest's backpack takes its own dig's result, not the host's (a race could differ by a few
    blocks). Joining a session while the host is already at the site: travel again to get there.

- **Machines (stage 6).** `ds_machine.gd` (DsMachine, the base the later machines share), `ds_dingo.gd`,
  `ds_machines.gd` (parking, getting on and off, driving, the net). Kinematic, not physics bodies: the ground's top
  under four corners sets height, pitch and roll; it won't climb a slope past `max_climb` (Dingo 28 degrees) or a step
  over `step_up` (26 cm), stops dead and says so; it drops into holes (gravity) and has to find a ramp out. The
  Dingo: W/S, A/D (skid steer), R/F arms, right mouse curls the bucket, left tips it. Bucket low and driving forward:
  it bites soil and clay (not rock) into the bucket (260 blocks); tipped, it pours loose dirt where its edge is.
  The driver stands on the back plate; the view turns with it. In co-op the host's game moves every machine and
  sends their state 20 times a second (fast, byte 68 + id); a guest asks to drive ("drive" event, the host says yes in
  the next state) and sends its controls 20 times a second (id + 128). The guest's view of the machine it drives lags
  by the round trip (no prediction yet).
- Ground drawing: the whole site on screen is ~0.6-1.3 M triangles (a face per block side: the chunky look keeps
  each block's shade). Fine on a PC GPU; greedy meshing would cut it if needed.

## Open questions

- Pre-existing, not from the Dig Site: St Kilda's own test prints thousands of "Out of bounds set index" errors from
  `sk_crowd.gd:345` headless (it still says PASS). Worth a look by whoever owns St Kilda.

## Stages

1. Scene + phone travel: done.
2. 3D voxel ground: done (`test/voxel/digsite_ground_test.gd`, 20 checks).
3. Hand tools: done (`test/voxel/digsite_tools_test.gd`, 15 checks).
4. Loose dirt: done (`test/voxel/digsite_dirt_test.gd`, 10 checks; 2 more in the ground test).
5. Co-op sync: done (`test/voxel/digsite_sync_test.gd`, two copies, with and without lag).
6. Dingo: done (`test/voxel/digsite_dingo_test.gd`: alone 14 checks; two copies, with and without lag).
