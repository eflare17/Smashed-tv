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

- **Tunnels and cave-ins (stage 7).** Tunnels are just the voxel ground dug sideways (the tools and machines dig
  anywhere; collision is the ground's own faces, so you walk in them). Under the ground the hard hat's lamp comes on
  (a spotlight on the camera). Cave-ins are in C++ (`native/src/dig_site_cave.cpp`): a roof is a firm cell with air
  under it; its span is twice the distance (in the air under it, any way round) to the nearest solid thing holding
  it up. Each material's limit is `DsMats.SPAN` (topsoil 1.5 m, dirt 2 m, clay 2.5 m, sand 0.75 m, gravel 1 m,
  stone 6 m, hard rock 8 m; bedrock, the edge, wood and concrete never). Too wide: a warning event (DsCaves: groan,
  crumble, dust trickling), then 3 s later (60 dirt ticks) the roof cells round it that are also too wide, and two
  over each, turn loose and fall; the dirt slumps them, and a roof above can go next (a sinkhole if it's shallow).
  Held up meanwhile (a post: stage 8), it settles instead. A fall hurts players under it (30 at most, once per 2 s).
  The host decides; the guest gets "cave" events for the sound and dust, and the ground through the usual chunks.
- A single "span" number is a simplification: it ignores roof thickness and depth (stage 8 adds depth pressure for
  supports).

- **Supports (stage 8).** `ds_supports.gd` (DsSupports). The hammer's right click puts a post (2 x 2 blocks) from
  the floor to the roof where you aim, out of the backpack: a wooden prop (the site office sells 5 for $10) or a
  concrete support (made at the office from 8 stone, 4 sand, 4 gravel; used first when you're past the wooden
  depth). Posts are WOOD/CONCRETE blocks of the ground, so stage 7's span is measured to them: a post in a room's
  middle halves its span. Weight by depth (from the ground's top over the post): wood holds for good to 5 m; past
  that it creaks, groans (worse as it goes) and gives way in 40 s (8 s at 9 m and deeper); its blocks drop loose and
  the roof it held is on its own again. Concrete holds to 30 m (the whole site). The office also buys ore now
  (V: coal $1, iron $2, gold $5, gems $15), so props can be paid for from digging. B/C/V at the office counter.
  The host keeps the post list and the weight; a guest's post is a DsNet action ("post"); creaks go as "sup" events.
- Posts can't bend visibly (they're blocks); the warning is the sound and the message.

- **Dynamite (stage 9).** `ds_blasts.gd` (DsBlasts) and the Dynamite weapon (`dynamite_ds`, key 4 with the
  explosives; sold at the office: X, 3 sticks for $15). Left click lights a stick where you aim (or at your feet); 4 s
  fuse with sparks. The blast is C++ (`blast_sphere`): blocks within 1.3 m x the material's `DsMats.BLAST` (soil
  1.0, clay 0.85, stone 0.6, hard rock 0.45, wood 0.9, concrete 0.4; bedrock and edge never) blown out, a shell to
  1.35 times that cracked loose. What's blown out flies as ~22 chunks (their share of each material) that land as
  loose blocks round the crater, so nothing's made or lost and blasted ore lies there to shovel up. Hurts players
  within 4.5 m (70 at the middle), shakes the view. Anything it wakes is checked for cave-ins; a prop whose foot is
  blown away gives way (so the roof it held can fall).
  In co-op a guest's stick is a DsNet action ("dyn"); the host blows it up and lands the chunks; the guest gets
  "dyn" and "boom" events (the stick, the bang, chunks to watch), the ground through the chunks.

- **More machines (stage 10).** On the same DsMachine base, parked by the gate:
  - Bobcat (`ds_bobcat.gd`): a DsDingo with wheels and a cab, faster, a 520-block bucket 1.8 m wide.
  - All four machines now use the digger game's models (DsProps: the Dingo with its little tracks, the Bobcat, the
    8 m tip truck with its tray hinged at the back, the excavator) and its loader arm geometry (pivot, arm length,
    bucket on the pin, its floor's angle the curl).
  - Excavator (`ds_excavator.gd`): the digger game's own, after the owner said the first one "looks trash compared to
    the other one". Its model (`ds_props.gd`, `ds_kit.gd`, `ds_track_rig.gd`: copies of earthmover's props.gd,
    mesh_kit.gd, track_rig.gd, renamed) and its arm: you steer the bucket's pin (R/F up/down, T/G out/in) and the boom
    and stick solve for it (elbow up), Z/X swing the house, right mouse curls the bucket in (digging in the ground),
    left opens it (pours from under the pin: over the truck, into it). 5.6 m boom; breaks stone (not hard rock).
  - Tip truck (`ds_truck.gd`): six wheels, steered (it only turns rolling), 5 m/s, climbs 22 degrees. Any bucket poured
    over its tray fills the tray (2400 blocks); R tips it and it pours out behind (spilling round when a column's
    full). Parked by the site office, L loads concrete supports ($8 each, up to 12); on foot at its back, G takes one
    into your backpack ("hauls concrete supports down").
  - Machines don't collide with each other (kinematic, each only against the ground); the player bumps into them.

- **Smooth ground (the owner, 8 Nov: "I want the ground to be smooth, not so Minecraft looking").** The brief said
  "chunky blocky look to match Smashed"; the owner changed that after seeing it. The cells stay 12.5 cm blocks (the
  digging, the dirt, cave-ins, the network are unchanged); only the drawing (and so the collision) changed:
  `native/src/dig_site_mesh.cpp` draws each section as a smooth surface (naive surface nets over each cell's 3x3x3
  share of solid cells: flat ground sits exactly on the blocks' tops, slopes and dug edges come out smooth), with
  smooth normals and colours blended vertex to vertex (grass on up-facing topsoil). The whole site is ~635k
  triangles. A change now redraws the sections within 2 cells. Machines ride a blended height (the four nearest
  columns) and check the slope just ahead of their leading wheels, so they still won't climb a pit's wall. Tool bites
  aim a few cm in (the surface can sit half a block off the blocks).
- **Smoother surface (the owner, 8 Nov, after asking about godot_voxel: "give it a go").** Rather than move to Zylann's
  Voxel Tools (it would have meant rebuilding the dirt, the cutter, cave-ins, supports, dynamite and the co-op sync
  around it, for level of detail a 64 m site doesn't need), the mesher's surface is relaxed: constrained surface nets.
  Each vertex moves to the average of the vertices it shares a crossed face with, 4 times (`RELAX`), never out of its
  own cube, so the surface stays within half a block of the blocks (flat ground exactly on their tops, a one-block
  roof or wall kept: cubes on a thin wall's two sides aren't neighbours) while rims, walls and tunnel arches come out
  smooth instead of crinkled. Normals come from the relaxed triangles. Each section works out `PAD` (6) cubes past its
  sides so its edge vertices match its neighbour's; that also closed the pinhole cracks that showed sky or grass in
  tunnels. Rows of cubes that are all solid or all air are skipped, so a section meshes in ~1.5 ms (was ~2 ms; the
  slowest 3 ms, was 9). The cells, digging, dirt, machines and network are unchanged.
- **The paddock sheet under the site (fixed, 8 Nov):** the far grass was one 1.2 km plane 1 m under ground level,
  right under the site too, so any hole over a metre deep showed a flat green floor. It's now four strips round the
  site's grass bands.

- **Driving view and the level (the owner, 8 Nov: "a level type thing ... so you can see what angle it is and
  also like a third person view ... and be able to move the camera around").** Driving now starts seen from behind
  the machine (DsMachines._third_cam): the mouse swings the camera round it (the arena's look), the wheel brings it
  nearer or further, V switches to the seat and back; you're shown on it (your Jared). `ds_gauge.gd`: two dials top
  right, the machine side on tipped by its nose and from behind by its lean, with degrees, white / amber (70% of what
  it climbs) / red, and red marks at its limit; TOO STEEP when it's stopped for it.

- **Digging feel and the bulldozer (the owner, 8 Nov: "the digging currently feels really terrible ... it's so much
  better already on the web version ... put a bulldozer in there and just the physics of the dirt and the
  digging").** The machines now dig the way the web digger game's DirtSim.blade does, ported to C++
  (`native/src/dig_site_blade.cpp`): a blade or bucket edge is swept as a line of rows; every cell above the edge
  (up to its mouth) is cut: loose dirt at once, firm ground only a few cells a column a frame (so firm ground bites
  slowly and loose piles scoop easily), rock stops it. What's cut goes into the bucket while there's room; the rest
  is banked just ahead of the edge, up to the heap's height, then rolls off the ends, then into the lowest spot
  near. Cutting through that heap again is what pushing is. `load_ahead` counts the loose dirt banked against the
  edge and slows the machine (it bogs down pushing a big heap). Rows are swept by distance travelled (at 3 fps a
  blade still cuts every cell it passed) and spill ahead of the front edge.
  - Bulldozer (`ds_dozer.gd`, the digger game's dozer model and tracks): R/F lift and drop the blade, drive to cut
    and push. Nothing goes in a bucket: all of it is banked and pushed.
  - Dingo and Bobcat: their buckets fill as they drive in (loose first, firm slowly), and once full they push.
  - Excavator: the teeth cut the same way, firm ground at a set rate (9 cells a second), and the arm slows in it.
  - Pouring (every bucket and the truck): `pour_at` spreads a load ring by ring round where it falls, capped at the
    bucket's height (it used to stack one tower per column), with a stream of falling dirt drawn while it pours.
  - Shovel: a spade-shaped slice (the cutter, aimed where you look) instead of a sphere; right click tips the scoop
    in a heap. Both are DsNet ops ("cut", "pour"), so a guest's are predicted and checked like digs.
  - Tests: the fleet test drives the bulldozer (blocks moved and banked, slowed by the load, none made or lost); the
    other machine and tool tests pass unchanged, alone and in co-op with lag.

- **Second pass on the digging, after looking it over myself (8 Nov, later).** Measuring the bulldozer headless at
  60, 20 and 5 fps turned up real faults in the first pass: the blade re-cut everything above its edge every frame,
  so a stalled blade pumped a heap taller than itself and the results changed with frame rate; the machine dived
  into its own cut; loose dirt slumped back through the blade and in under the tracks, and the machine rode up onto
  its own heap; a slow frame left steps it then couldn't climb. Fixed, mostly by porting more of the digger game:
  - The cutter moves only what the edge sweeps through: each column loses `share` of what stands above the edge
    (its travel this step over 0.25 m), from the top down, with random rounding (`blade_sweep(..., share)`). No
    travel, nothing moved. The row behind the face clears what's left (so no firm step is left behind a moving
    blade); further rows sweep loose dirt only.
  - Machines step in slices of at most ~1/45 s, so a slow frame drives and digs the same as quick ones.
  - Blades, buckets and machine bodies are solid to loose dirt (`block_blade`, `free_at` in the dirt sim): it banks
    against them instead of slumping through, but isn't held up by them (what tumbles over a blade falls behind it,
    where the strip back to the tracks is swept clear every step).
  - Steady blade (the digger game's): while working, the blade keeps to its height averaged over the last 2.5 m, so
    the machine pitching under it doesn't cut waves; never lifted much past the tracks' bottoms.
  - CUT (Q; T/G deeper/shallower in 5 cm steps; R turns it off): holds the edge a set depth under where the ground
    began (`start_top`, kept from when the site was made), so it takes an even layer off and follows the land.
  - Drag: cutting firm ground slows it (CUT_BOG), on top of the heap's weight; a cell is only cut if there's room
    for it in front (up to 0.5 m over the heap), so an overloaded blade stalls ("The blade's full") instead of
    stacking a tower or passing through what it can't shift.
  - Slope check: loose dirt isn't a wall, and a lip it can step up isn't either; only a bank rising past its step is.
  - Loaders: the same share and solid bucket; extra loose-only rows back to the front wheels, so a Dingo scoops a
    loose heap to a full bucket instead of riding up it.
  - Grass only on ground still at its starting height: a scrape or cut shows soil (it used to stay green until the
    cut went past the 0.5 m of topsoil).
  - Keys: while driving, 1-6, C, F, Q, R no longer also reach the weapons.
  - Measured (headless, 15 s, blade held down the whole time): CUT 20 cm pushes at ~1.3 m/s with a 1.6-2 m heap and
    leaves the ground 12-25 cm under where it began, the same at 60 and 5 fps (the fleet test checks it); a deep cut
    stalls with a full blade after ~11 m; a shallow blade spreads its heap into the dip ahead and drives on.
  - Not done: the excavator's teeth are as before (firm ground by time, not travel).

- **The look (the owner, 8 Nov: "the web version looks miles ahead of it ... make it look even better than the
  web version").** Rendered side by side, the first Dig Site was pastel plastic on a plane: the arena's filmic
  tonemapping and grey sky, flat vertex colours, no grass, no outlines, one smooth beige for every kind of dirt. The
  digger game's cel-shaded look is brought over (`ds_look.gd`, `shaders/`), applied only while you're at the site
  (the arena's sky, sun, tonemapping and field of view are swapped on arrival and put back on the way home):
  - Toon light (`ds_toon.gdshaderinc`: a hard terminator, one band, a crisp shadow edge) on every Dig Site material:
    the machines and props (`ds_prop.gdshader`, vertex colours), the fence, office and pines (`ds_flat.gdshader`).
  - Ink: black lines from the depth buffer (`ds_outline.gdshader`, a full-screen quad drawn after everything; the
    threshold raised from the digger game's 0.03 to 0.05, or the surface-nets ripples in flat grass drew squiggles).
  - The site's own sky (`ds_sky.gdshader`: saturated blue, painted clouds), a warm sun at the digger game's angle
    with hard two-split shadows, flat ambient light, linear tonemapping, deeper SSAO, no glow. Camera 52 degrees.
  - The ground (`ds_ground.gdshader`, on the true 3D surface-nets mesh): the mesher now also gives each vertex, in
    CUSTOM0, its loose share, a cavity shade, grass and rock flags. Grass in two patchy greens with a crisp ragged
    border (only on firm topsoil still at the height it was made); soil as lumps with dark gaps where it's loose (the
    digger game's clods.png, from above, and from the side on a wall), smooth and darker where cut; strata bands on
    steep firm faces; rock in flat greys; hollows darker and warmer. The cavity shade is the digger game's
    ring-average height drop (0.75 / 2 / 4.5 m rings) worked out per vertex in C++ from the column tops, so it also
    darkens a tunnel's inside, which a heightmap can't. Material colours (`DsMats.COL`) warmed to the digger game's
    red-brown soil.
  - Grass blades and clods: `decor_section` (C++) lays MultiMesh buffers per section, rebuilt with the section's mesh:
    36 blades/m2 on untouched topsoil (so digging takes the grass with it), lumps on loose dirt sized by how deep it
    lies and part sunk in (`ds_grass.gdshader`, `ds_clod.gdshader`, drawn after the ink). ~150k blades over the site,
    three triangles each.
  - Round the site: a paddock plane to the horizon and 46 pines (`DsProps.pine`, the digger game's), none across the
    gate.
  - Dust and exhaust (`DsMachine._dust_fx`): puffs off the tracks as a machine drives, smoke from its stack while
    it's driven (faster under throttle), dust where a bucket or the tray pours.
  - Nothing in the grid, the dirt or the network changed; the tests are unchanged.
- Heaps flickering away while digging (the owner, 8 Nov: "it just starts to dig and then it disappears"): the
  section redraw was starved, so a dug section showed nothing for a few frames. `DsTerrain.step` now redraws the
  sections near a player (within 20 m of the section's edge) as their own batch, 15 times a second, at most 6 at a
  time, double-buffered: the meshes, grass, clods and collision are built into new resources over a frame or two
  (8 ms a frame) and swapped in together in a later frame, so the old mesh stays up until the new one is ready. The
  far sections keep their own budget, capped by a running average of the build time. Column tops are cached in C++
  (`top_cached`, cleared per column on change, and by network chunks) so the cavity shade and the decor don't rescan
  columns.
- Loader buckets can't dig below their wheels, and a pass scrapes off one clean layer, grass and all (the owner, 8 Nov:
  "the bucket's going lower than the tires", again after a first fix, then "scrape off like the whole layer of
  grass"). Arms right down, the Bobcat's lip was 18 cm under its wheels; limiting the arms against the body wasn't
  enough, as the front wheels drop into the bucket's own cut, the machine tips nose down, the bucket with it, and it
  goes in deeper still (measured: 59 cm down in 4 s). `DsDingo._hold` now works in the world each frame:
  - the bucket self-levels (its floor keeps its angle to level however the body tips);
  - arms right down, it floats: the lip rides 6 cm (`DIG_MOST`) under the firm ground 30 cm ahead of it, not yet cut
    (loose dirt there doesn't count, so into a heap it scoops from the bottom), up or down as the body bobs and rolls;
    higher, the arms only lift if the lip would go under that;
  - never more than 18 cm under its wheels (`FLOAT_DOWN`: it doesn't dive into a pit ahead), and never lifted over the
    higher of where arms-right-down put it and 6 cm under its highest wheel (it cuts into a bank rather than riding up
    it, and a machine in a pit stays in it: the Dingo test);
  - it takes any block its lip goes into (the cutter's given the lip half a block lower, `BITE`: it takes blocks whose
    middle is over the edge), so a pass peels the top 12.5 cm off evenly. Where the site's own terraces cross the
    bucket at a slant, the last strip of the upper one loses two layers, which leaves the scraped floor flush.
  The guest is sent the arms and bucket as held. The fleet test checks the lip never goes deeper than that
  (`digsite_fleet_test.gd`).
- **Dirt through the blade and bucket, and jumpy heaps (the owner, 9 Nov: "The dirt clips through the bucket and the
  blade. Also it's really jumpy. Have a look at the web one").** Recorded the digger game's own push and excavate
  demos (Dozer Drive, the earthmover branch) and went frame by frame against ours:
  - Bucket loads: the excavator's was a box that poked out through the bucket. Ported the digger game's newest load
    (fc0f290): built from the bucket's own hollow, inside the shell and side plates, lumpy on top, heaped out of the
    open side past 78%, at 18 levels (`DsExcavator.load_meshes`). The Dingo and Bobcat use the same builder on their
    buckets' triangle (floor, back, side plates' slope), lumps scaled to the bucket; the digger game's loaders still
    have the box.
  - Lumps: they were laid again from scratch every time a section was redrawn, so they shuffled about every heap 15
    times a second, and big ones beside a blade poked through it. Now `DsClods` lays them once at fixed spots (28 a
    m2, a 4 m patch per section column) and `ds_clod.gdshader` (the digger game's clod.gdshader on our grid) finds
    each one's height, size and soil from the ground's textures: dirt arriving brings lumps up, scraping takes them
    away, moving ground turns them over. Near a blade or bucket (`keepout_boxes()` on the bulldozer, loaders and
    excavator) a lump's kept smaller than its distance from the steel.
  - Gliding ground: each column's top as its shown mesh has it, and how far the surface is still drawn off it, easing
    to nothing (`dig_site_show.cpp`: snapshot when a section's mesh is made, committed when it's shown, so it always
    matches the mesh on screen). Down at 24/s (dirt gone: the surface mustn't hang up into a blade), up at 9/s. The
    ground shader lifts or drops a column's top vertices by it; two textures (offsets RF, tops/loose depth/material
    RGBA8) uploaded at most 30 times a second. The near redraw went from 15 to 30 a second (the mesher's faster now).
  - The bulldozer: with the heap full it reported "jammed" but crept on, so firm ground stood up through the blade.
    Now it stops dead when what's between the blade and the tracks can't be cleared. The blocked cells start 0.2 m
    ahead of the edge (the blade's top curls out that far) and go up to the sky (dirt that spilled over used to rest
    on top of them, floating over the blade); its heap's 1.25 m over the edge (was 1.6, level with the blade's top).
- **9 Nov ("honestly this looks trash its still so jumpy ... analise the video and tell me what you will do"):**
  telemetry from a fixed-rate run (every frame: camera, machine, ground) against the digger game's own:
  - The machine climbed each 12.5 cm block in one frame (it rode the highest of its four corners) and the camera was
    bolted to it: body hops of up to 6 cm a frame, camera jolts up to 9 cm. Now (`DsMachine._drive`) it rests where
    the digger game's do, on its corners' average or a crest between its tracks if that's higher, eased to at 10/s,
    with pitch and roll from the corners' averages; off a real drop (over 0.3 m) it still falls. The camera
    (`DsMachines._third_cam`) follows on a spring (9/s along the ground, 4/s up and down) and its keep-out-of-the-
    ground lift is eased too. Measured on the bulldozer clip: body change a frame, 95th percentile 4.0 -> 1.6 cm,
    frames over 2 cm 98 -> 15; camera jolt 95th percentile 3.7 -> 0.3 cm, frames over 1 cm 139 -> 1.
  - Each step now poses the machine before its tool works (it used to only when the frame was split into several
    steps), so the Bobcat's depth hold works out "the ground ahead" from where it is now. The fleet test checks its
    lip against the ground the hold used (the firm ground ahead, or its highest wheel).
  - The ground itself still changed a block at a time (dirt settled every other frame, a section was redrawn every
    third or so, up to 15 blocks a frame). So, the next stage:
- **The loose layer (9 Nov, the digger game's dirt in mm on our blocks):** `native/src/dig_site_layer.cpp`. Each
  column also keeps the loose dirt lying on its top cell in mm (`fr`, 0 to 187, and `fm`, its material); its surface
  stands at (top + 1) x 125 mm + fr. Putting dirt on a column adds to its layer, 125 mm of it becoming a loose cell on
  top once it's 188 deep (so a layer going up and down by a few mm doesn't make and unmake cells); taking it off takes
  the layer first, then turns the top cell into layer (a loose one always, a firm one only for a blade or bucket at its
  firm rate, never rock). The cells keep everything solid, so tunnels, cave-ins, supports, blasts and the network work
  as before; the layer is the fine part on top.
  - Slumping: DirtSim._slump_chunk ported, in blocks of 16 x 16 columns that are awake: a quarter of how far a column
    stands past the angle of repose (84 mm over a column's 125, 119 to a corner: 34 degrees) slides to its neighbour,
    straight and corner neighbours each tick, 60 ticks a second (`DsTerrain.LAYER_HZ`, 1.5 ms budget a tick). Not
    into a column a blade, bucket or machine body stands over. The cell sim (`dig_site_dirt.cpp`) leaves loose cells
    with nothing but solid over them to the layer; it still drops dirt through air, slumps it in tunnels and lets firm
    walls give way. A heap of 1800 blocks dropped in one spot settles in 2.2 s to a 34-degree cone; no surface moves
    more than a few mm a tick doing it (`digsite_dirt_test.gd`).
  - Blades and buckets (`blade_sweep`, `load_ahead`, `pour_at`): DirtSim.blade/_spill/load_ahead in mm. A column
    loses share of what stands above the edge off its top (so a blade moving a tenth of a column moves a tenth of
    what's there, not a whole block one time in ten); what's cut goes in the bucket or is laid ahead up to the heap's
    top, then further, then off the ends, all in mm. Firm ground is cut at the machine's rate in mm (the digger
    game's bed_rate: firm_most blocks' worth at full sweep), and what's left of a firm block under the edge stays
    firm: the layer can be firm ground (`FIRM_LAYER` in its material byte), so a cut floor stands exactly where the
    edge went. (First go: a cut block turned wholly loose and only the part over the edge went, which left a skin of
    loose lumps all down the cut; cutting whole blocks instead left 12.5 cm steps the tracks bumped over, 3.1 cm a
    frame. The firm layer: 2.0 cm.) A firm layer doesn't slump; loose dirt landing on it loosens it. Firm ground over
    a blade's mouth is still cut from under (cells). A full blade's dirt that has nowhere to go goes back where it
    came from as it was (`lay_restore`: firm stays firm): put back loose, it was left in the cut under the tracks and
    the bulldozer drove off leaving a trail of lumps.
    Results are mm: buckets, trays and pours count mm (`load_n`, capacities x 125), the spade turns mm into whole
    blocks for the backpack and carries the rest (`DsTools._carry`), the bulldozer's load is in blocks again
    (`load_ahead` / 125).
  - What machines ride on: `DsTerrain.height_at` (C++ `height_at`, the four columns' surfaces blended, layer and all).
  - Drawing (`dig_site_show.cpp`): a section's mesh is still made from the cells now and then; each column's offset is
    how far its true surface stands off its meshed top (cells changed since, and the layer), exact every frame on the
    host (a guest eases to the host's at 14/s). Half-float offsets (RH) and RGBA8 meshed top / loose depth (eighths of
    a cell) / surface material, uploaded every frame anything moved. The ground shader leans the lit normal by the
    offsets' slope, and draws loose dirt on top (even a thin layer the mesh doesn't have yet) in its own colour; grass
    under it shrinks away; the lumps ride the true surface. Offsets up to 2 m are drawn (3 cells was too few: a blade
    heaps and cuts faster than the near redraw, and past 3 the surface stood where the mesh had it, half a metre into
    the blade). The terrain runs after the machines each frame, so what they moved is drawn that frame: telemetry,
    drawn top against true top, worst point a frame, 0.5 mm.
  - Network: the layer goes in the same diffs, a 16 x 16 block of columns at a time (index with the top bit set, 256
    mm + 256 materials), with a guest's arrival and in the drifted-section fixes; section checksums take in the layer.
  - Conservation: `ground_mm()` (every solid cell's 125 and all the layer), `loose_mm()`, `mat_mm(m)`. The tests count
    mm now (a layer can take another material's dirt, so per-material counts can shift where two meet; the total
    never does).
  - Known: the player walks on the cells' collision, so their feet sink into the loose layer by up to 18 cm (loose
    dirt; machines ride the true surface).
  - The excavator's "won't stab deeper than 0.8 m" read the ground in its teeth's own column, which is cut exactly to
    them now, so it never read deep: the bucket went on down 1.8 m and couldn't lift out to pour. It reads the ground
    beside the bucket too, the lower side (the Bobcat's spoil heap beside it in the fleet test stopped it at 7 cm when
    it took the higher). A bucket's pour is spread over the columns under its mouth (filling the one under it first
    stood a 2 m spike up for half a second before it slumped).
  - The tops / loose depth / material texture (1 MB) goes up 30 times a second while dirt moves, at once when a
    section's mesh is shown (the meshed tops must match the mesh that frame); the offsets every frame anything moved.
  - Proof (fixed camera beside the path, blade 0.2 m down, flat out 12 s, both games at 30 frames a second;
    `ds_fixed`/`web_fixed` scripts, telemetry every frame, the ground as 41 x 41 points 0.5 m apart round the dozer):
    the body moves at most 2.00 cm a frame (95% under 0.71 cm, none over 2 cm; the digger game's: 1.78, 0.88, none);
    the ground moves every frame in both (360 of 360), the most any point moves in a frame a median 60 mm, 95% under
    129, at most 175 (the digger game's: 97, 319, 650); what's drawn is within 0.5 mm of the simulated surface every
    frame. Before all this: body hops to 6 cm, camera jolts to 9 cm, the ground in whole blocks every second or third
    frame. Costs a frame: the layer 0.34 ms (95%: 0.58), its drawing brought up to date and uploaded 0.85 ms (95%:
    1.15, software renderer; less on a real GPU).
- **9 Nov, the capped look pass ("I want this to be better than the web version"):** the web game is the same
  engine, so its pieces were copied, not invented:
  - Exhaust: the bulldozer's came out 2 m behind its stack (the excavator's didn't slew with its house), and the
    puffs were drawn before the grass, which is in the see-through pass too, so the grass painted over every puff with
    nothing but grass behind it: smoke and dust only ever showed against the sky. Puffs now draw after the grass and
    lumps (render priority 2), come out of the stack's top (`exhaust_at()`), bigger and slower than the digger game's.
  - Work dust (`DsMachine.work_fx`, the digger game's clods and dust): flying lumps and dust at a working blade or
    bucket; on the bulldozer, lumps tumbling down the heap's face too, more the more it carries (`_tumble`).
  - Track marks: tracks and tyres wear the grass bare where they go (`DsTerrain.wear_tracks`, the digger game's
    `_wear_tracks`), a byte a column uploaded as a texture 10 times a second; the ground shows packed topsoil there
    and the grass shrinks away. Each game wears its own from the machines' poses (nothing to send).
  - Grass: the digger game's blade sizes (0.72 to 1.3 wide, up to 0.4 m tall: ours were about half) at its "High"
    density, 64 a square metre.
  - PC extras: 40 lumps a square metre (28); ambient occlusion was already on. (A light distance haze came out again
    at once: the owner, "the web one's got this cartoonish charm ... nice vibrant green. The other one's got like
    kind of a fog". The ground's and grass's greens are the digger game's own now (ours were about 10% darker), with
    the colour turned up a touch (saturation 1.18, contrast 1.04): the same colours come out a shade duller in the
    PC renderer than in its browser one. Sun, sky and ambient light were already its.)

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
7. Tunnels and cave-ins: done (`test/voxel/digsite_cave_test.gd` 9 checks; `digsite_tunnel_test.gd` alone and two copies, with and without lag).
8. Supports: done (`test/voxel/digsite_support_test.gd`: alone 13 checks; two copies, with and without lag).
9. Dynamite: done (`test/voxel/digsite_dynamite_test.gd`: alone 12 checks; two copies, with and without lag).
10. Bobcat, excavator, tip truck: done (`test/voxel/digsite_fleet_test.gd`: alone 15 checks; two copies, with and without lag).

## Dozer hydraulics and engine shake (9 Nov)

- The owner asked to "actually see the hydraulics" and for a small shake like the web game's, but gentler.
- **Lift cylinders (DsDozer):**
  - Each side has a yellow barrel (0.62 m) pinned to a bracket on the hood's side, with hoses, and a chrome rod pinned to a bracket on the blade's back.
  - Every pose re-aims both along the pin-to-pin line. The rod's length is the gap minus the barrel, so it slides out as the blade drops (about 0.2 m showing with the blade raised, 1.2 m at full down).
  - The old fixed steel rams in DsProps.dozer_blade are gone.
- **Shake:**
  - Only the body, blade and cylinders shake (a `_shake` node). The tracks and frames stay on the ground. The blade's cutting edge is still worked out without the shake, so digging isn't affected.
  - Vertical shake is 2.2 mm idling, rising to 7.7 mm at full speed (the web's is 6 mm rising to 20 mm). Pitch shake is 0.8 mrad, and the dozer leans back slightly when loaded.
  - It only runs with someone driving. It uses speed and driver, which are already synced, so the guest sees the same shake.

### All machines (9 Nov, "do all three")

- **DsRam** (ds_ram.gd) is the shared part. It has a painted barrel with hoses at one pin and a chrome rod at the other, and `aim(a, b)` sets it each pose. A truck's ram has stages, each sliding out of the one before by the same amount.
- **Where each machine's rams go:**
  - **Dozer:** two lift rams.
  - **Excavator:** boom, stick and bucket rams. Before, each was one stretched piece. Now they have charcoal barrels sized at 56% of their length as built, with chrome rods.
  - **Dingo and Bobcat:** a lift ram each side, from the body to the underside of the arm. Tilt rams run from the arms' cross bar to the back of the bucket: one on the Dingo, two on the Bobcat. The pin positions are vars set in each machine's `_init`.
  - **Tip truck:** a 6-stage telescopic ram from the chassis behind the cab to a bracket out in front of the tray's front wall, so it stays clear of the wall when the tray is fully tipped (a pin on the wall's top clipped through it).
  - **Pin fixes:** the excavator boom ram's top pin was 22 cm below the curved boom, so it now has a lug under the boom. The bucket ram's pin was 20 cm above the bucket and is now on its back plate.
- **Shake:**
  - Moved into DsMachine (`shake_node`, `shake_idle`, `shake_work`, `shake_pitch`, `shake_hz`). Each machine shakes a node holding its body and tools, never its wheels or tracks.
  - Machines don't all buzz in step: each runs at its own rate and phase.
  - `shake_effort()` adds to the shake while the machine works: arms or tray moving, the excavator's arm or slew. `shake_lean()` leans it under load.
  - It's all drawn on top of the sim: no machine's digging reads the shaken node. The shaken node's transform is read only by the clod keep-out boxes, which are off by a few mm at most.

## Excavator digs with a curl, not a stab (10 Nov)

- The owner asked for it to "actually need a curl and dig into it. At the moment, it just goes straight into the ground."
- **Before:** lowering the bucket cut the ground under it, so F alone sank it 0.8 m straight down.
- **Now (DsExcavator):**
  - Only a curl in (yours or its own) or a drag towards the machine cuts. Lowering, pushing out and opening don't cut. For those, `_keep_out` keeps every part of the bucket's shell (back, floor, heel, teeth: `SHELL`) within BITE = 0.35 m of the ground. It rides the arm up to stay there, or stays put if the arm can't lift it. So let down, it bites in and rests on the ground. Curled in while it's lowered, it lands on its back.
  - Like the web game, it curls by itself while dragged through the ground (CURL_ASSIST 0.8 rad/s), and while lifting a load (CURL_LIFT 1.6 rad/s), unless you're tipping it.
  - It starts cutting from more open (curl over CURL_EMPTY + 0.1, was + 0.4), so a scoop from open takes the whole arc.
  - FIRM_RATE went from 9 to 120 firm blocks a second per column. At 9, the teeth skated over each column in about a tenth of a second, so a dragged bite was a 9 cm scrape. Now the effort holds the arm back instead (BOG_AT 40 blocks a tick for full bog). A drag in and down fills the bucket heaped (1.2 m³) in under a second and leaves a pit.
- The fleet test now opens the bucket before letting it down (alone and as the guest). It checks the bucket rests at no more than BITE, then digs by dragging in and down while curling.
