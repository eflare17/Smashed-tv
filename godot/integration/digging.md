Status: done

Ground core: done

# Digging (level 3: smooth caves) and ploughing: integration note (branch `claude/godot-digging`)

PLAN.md "Later: digging". Level 2 (holes you can stand in) and ploughing were built and published first; the
owner found the digging flat ("no feel / feedback", "holes look bad") and asked (18 Oct) for **deep and
explorable** digging with **smooth caves**, **for farming too**. This is that: level 3, which took over
level 2's ground (the plan's "level 2's depth grid seeds it"; nothing saved by level 2 is kept, see Decisions).

## What works

- **The earth under the yard is a density volume** (`DigVolume`): samples every 8 units across, down and deep,
  from the yard's top down about 8 m to bedrock (z -320 .. +24 units). Earth where the density is above 0;
  untouched it's flat ground at 0. Only the 16-sample chunks that were dug or filled are stored (int8, sparse),
  so an untouched yard costs nothing. Only the yard can be dug (the same mask as before: grass, clear of the
  house, deck, every yard solid, the vegetable patch and the farm's things by 22 units); the house floors,
  lobby and arena are as they were, and nothing can be dug under the shed, garage or tank.
- **Drawn smooth** (`DigMesher`): marching tetrahedra (no case tables to get wrong), normals from the density's
  gradient. The ground's top in a dug chunk wears the yard picture (or its soil: furrows, dug-over dirt); the
  rest is earth tinted by depth: brown dirt, red clay from about 2 m, grey stone from about 5 m, darker the
  deeper. Untouched ground stays the cheap flat yard (three meshes for the whole yard, as before). Untouched
  cells inside dug chunks go out as long flat strips.
- **One terrain shader** (in `DigGround`) for the flat yard and the caves, in both looks: lit ("high") and the
  phone's unlit "low" with the look's own tint and lamps. It replaces the look pass's lit material for these
  meshes (the look pass only converts StandardMaterial3Ds, so it leaves them alone) and checks the look's
  quality twice a second (F8 or the automatic drop still switch it).
  - **Top-down cutaway:** while he's underground, the earth over him within about 6 m isn't drawn, and what's
    cut shows as a slice of dark earth (earth seen from inside, and a floor under everything shown only then),
    so his tunnels and caves read as lit hollows in the earth.
  - **A lamp** round him underground in both views (it's dark down there).
- **Collision:** the World's endless ground plane becomes slabs round the yard; inside it, a flat box for each
  untouched 16-cell column and each dug chunk's triangles (ConcavePolygonShape3D), on layer 1: anything physical
  lands in holes and tunnels (rays tested).
- **Moving in the earth** (`Dig._move_body`, stepping after the Player): he stands on the floor under him, steps
  up 14-unit lips, falls down shafts (gravity), climbs ledges he walks into up to 60 units (about chest high,
  so he can get out of a hole or up a step in a tunnel), and walls stop him (he slides along them). His capsule
  has a collision exception with the ground. Untouched lawn takes the old fast path. First person: his eyes go
  down with him. Online, the other player's feet come over the network (`feet` messages), so you see them down
  their hole.
- **The shovel** (the rack against the shed's east wall, E: TAKE SHOVEL / PUT BACK SHOVEL):
  - **Hold E to dig** (pad A, the round touch button taps): a dig every 0.28 s, a capsule of earth about a body
    wide. **Standing still, it digs straight down under him** (a shaft, 16 units a dig: he drops into it; in
    first person when looking well down). **Walking, it digs ahead**: top-down from the floor in front (never
    more than 40 below his feet), so he goes down a ramp; **in first person where he looks**: ahead into a wall
    (tunnels), up, down in front.
  - **Feel:** the shovel swings down hard (top-down and the first-person picture), dirt chunks burst out
    (coloured by the layer: dirt, clay, stone), the screen shakes a little, a chunky sound.
  - **Q / pad X / the touch FILL button** puts earth back in front of him (never into anyone, never above the
    ground's top), so holes can be filled level again.
- **Finds you pick up:** every bit of earth dug out may hide something, fixed by where it is (the same on both
  screens): about 0.35% of it near the top, 0.55% in the clay, 0.8% in the stone. Near the top potatoes (spud
  ammo), coins, bones, now and then a stash (cash and a seed you can't buy); in the clay more coins, gems,
  bones, stashes; in the stone gems, fossils, coins, rich stashes. A find pops out of the earth in an arc (a
  pixel-art picture, bobbing and glinting) and "A GEM!" rises over it; walk over it to pick it up (coins, gems,
  fossils and stashes into the Wallet, potatoes into the spud gun). Finds lying about vanish after 2 minutes.
- **Farming:** the hoe ploughs as before (walking with it, slower: it's hand work); planting works on ploughed
  soil and now also on **dug-over ground filled back in level** (dug ground is dirt; holes aren't plantable
  until filled). Crops on the farm's "field" plots as before; soil grows back on the game clock (weedy after 36
  game hours untended, grass after 72); a hole's ground stays dirt.
- **Saved** to `user://smashed-dig.json` (the soil, its ages and the stored chunks, deflated; about 1.6 KB for
  a yard with 18 dug chunks) 2 s after a change and when the window closes.
- **Online:** the host owns the ground. Each dig, fill and ploughing goes to the other game as an op (the host
  passes a guest's on to it again: digging, filling and ploughing twice is the same as once, so nothing doubles
  up) and the host sends the whole ground every 15 s and on joining (a few hundred bytes to a few KB). Each
  player sees the other's tool, and their feet in holes and tunnels. Finds are the digger's own.

## Install (done on this branch)

`scripts/main.gd`, after the farm:

```gdscript
	FarmInstall.install(self)
	DigInstall.install(self)            # digging and ploughing the yard (after the farm: its field plots)
```

It adds `main/Dig` (the ground's data, tools, moving in the earth, finds, saving, online), `main/DigUI` (the
first-person tool, the touch FILL button, floaters, sounds) and `World/DigGround` (meshes and collision).

## API (for a push tiller, a ride-on, a level 4...)

- `Dig.instance.grid` (`DigGrid`): the ground's top: `soil` per 8-unit cell (`D.GRASS`, `ROWS_X`, `ROWS_Y`,
  `DIRT`; `D` is `scripts/dig/dig_data.gd`), `age`, `mask`; `soil_at`, `set_soil(x, y, r, kind)`, `plough`,
  `plough_cell`, `mark_dug`, `plant_spot`, `grow_back`, `cell_level`, `height_at` / `depth_at`.
- `Dig.instance.grid.vol` (`DigVolume`): the earth: `f_at(x, y, z)`, `solid`, `surface_height`,
  `floor_below(x, y, z)`, `raycast(from, dir, max)`, `carve(a, b, r)` (a capsule), `fill(c, r, z_top)`.
- `Dig.instance`: `carve(a, b, r, player)` / `fill(c, r, player)` (with the effects, finds and the network),
  `dig_now(p)`, `fill_now(p)`, `feet_of(p)`, `drop_to(p, z)`, `tool_of` / `set_tool`, `apply_op(op)`;
  signals `found(pid, kind, n)`, `floater`, `sound`, `tool_changed`, `changed`.
- Everything that changes the ground goes through these, so it's drawn, saved and sent with no more work. A new
  kind of change: add an op in `Dig._net_op` / `Dig.apply_op`.

## Changes to other parts' files (all small, and why)

- `scripts/main.gd`: the install line above.
- `scripts/farm/farm_data.gd`: `FIELD_PLOTS := 48`.
- `scripts/farm/farm_state.gd`: 48 plots of a new zone "field" at the end of `plots` (open while placed,
  `on`); `field_plot(x, y)`, `field_free(i)`, `field_near(x, y, r)`; `plot_open` and `grow` use one
  `_is_open`; `to_dict` / `from_dict` carry the field plots' places (old saves load as before).
- `scripts/farm/farm_world.gd`: a field plot's plant and E spot move to where it's planted.
- `test/farm/test_farm_logic.gd`: the plot count includes the field plots.
- `scripts/net/net.gd`: `signal message(d)`, emitted for any message type it doesn't know (the dig's). The dig
  sends with `Net.me._send(d)`.
- `scripts/combat/fight_hud.gd`: one row each in the controls help (Tab / pad d-pad down).

## Input actions

None added. E / pad A / the HUD button is `interact` (hold it to keep digging); fill is the existing
`lobby_alt` (Q / pad X); touch has its own FILL button (DigUI).

## Tests

- `test/dig/dig_test.tscn` (inside the real game):
  `godot --headless --path <copy> --fixed-fps 60 res://test/dig/dig_test.tscn` ends `DIG TESTS: 87 passed, 0 failed`.
  The mask; the volume (carving, the hole's floor, the lawn beside it level, nothing under the garage, bedrock
  stays, the smooth mesh); collision (rays into the hole, on the lawn, the house floor, past the region);
  moving (falling down a shaft, its walls holding him, walking a tunnel along its floor, climbing out of a
  chest-deep pit, the lawn as before); the rack, E digging, held E digging on, digging on down a ramp, first
  person digging where he looks, none by the tank, the cutaway on underground and off on top; finds (the same
  everywhere, the rate per layer, the kinds per layer, popping out and picked up, each reward); filling with Q
  (level, never above the top, dirt left, nothing to fill on the lawn); the hoe ploughing and slowing him,
  planting on furrows, growing like a bed's, **filled-in dug ground plantable**, not in a hole, weedy then grass,
  tended soil and a hole's dirt staying, the field plot freed; the save (same ground back) and the field plots
  in the farm's save; ops the same on both games (twice is once), ploughing over the network, no finds for the
  replay, snapshots; speed.
- `test/dig/net_drive.gd`: two headless games over ENet:
  `godot --headless --path $W --fixed-fps 60 -- --host=TEST --netdrive=res://test/dig/net_drive.gd &` then the
  same with `--join=127.0.0.1`. The guest digs (the host sees it), the host ploughs and digs a shaft and drops
  down it (the guest sees all three and the host down in it), each sees the other's tool. Both end
  `DRIVE DONE fails=0`.
- `test/dig/make_mask.gd` (`-s`): rebuilds `dig_mask_data.gd`.
- `test/dig/dig_shot.tscn`: the game for web screenshots and frame times: `?digdemo` (holes deeper each, a ramp
  down to a cave, a shaft, ploughed rows with crops), `in` (stand in the cave), `at=`, `fp`, `yaw=`, `pitch=`,
  `zoom=`, `tool=`, `look=`, `perf`, `nodig`.
- Web screenshots looked at: top-down holes and the ramp; top-down in the cave with the cutaway and the lamp;
  first person inside the cave (clay walls) and from the lawn looking into the holes and ramp; the phone in
  portrait (low look, touch: DIG, FILL, the cutaway).
- The existing tests, re-run with it installed: `test/combat/logic_test.tscn` 53 passed, 0 failed;
  `test/lobby_life/run.tscn` 286 passed, 0 failed; `scenes/arcade/arcade_test.tscn -- --logic` 0 failed;
  `test/farm/test_farm_logic.gd` 76 passed, 0 failed; `scenes/farm/farm_test.tscn -- selftest` 40 passed,
  0 failed; the online session's `test/net/drive.gd` passes on both sides.

## Speed

- Natively: a dig takes about 2 ms; each chunk it changes redraws in 2-8 ms (a chunk with a big hole's walls
  the most). Chunks redraw **one a frame**, nearest the player first, so a dig never stalls a frame for long.
  His steps on the earth: about 1 ms a second of game.
- The game's script time per frame is the same with and without dug ground (natively, 16-22 ms a frame in the
  headless test either way: the rest of the game).
- Drawing: an untouched yard is the same three draws as before. Dug ground adds a draw per dug chunk and its
  triangles: the demo yard (four holes, a ramp, a cave, a shaft) is about 27k triangles and 33 draws more. In
  this container's browser (SwiftShader, software rendering) that's slower (about 100 ms against 60 ms a frame
  at 480 x 270), but for a phone's GPU it's small. **Not measured on a real phone.** If phones struggle:
  merge chunk meshes, or a coarser mesh for far chunks.

## Decisions

- **Smooth, not blocky** (the owner's pick). Marching tetrahedra rather than marching cubes: no 256-case table
  to get wrong, smooth enough with gradient normals, about twice the triangles.
- **8-unit samples, 8 m deep, 16-sample chunks, stored only when touched.** About a body wide for the smallest
  tunnel, deep enough to explore (three layers), cheap when untouched.
- **Players walk on the volume themselves** (`_move_body`), not by physics: the Player has no gravity (y from
  dz), so the floor, falling, steps, climbing and walls are done on the density; physics collision is for
  everything else.
- **Climbing up to 60 units** (chest high) so a hole never traps him; deeper shafts need a ramp or digging
  steps.
- **Standing still digs straight down, walking digs ahead** (the owner couldn't dig straight down, 18 Oct): no
  extra button, so it works the same on a phone. Top-down, walking and digging goes down a ramp; level tunnels,
  digging up and into walls are first person's (dig where you look).
- **Finds hang on places** (a hash of the sample), so both screens agree with no messages, each spot gives at
  most once, and deeper is richer. They're picked up by walking over them, so there's a moment of "what's
  that?".
- **The cutaway** cuts a 6 m circle above his feet + 1.75 m, with a dark-earth slice: the simplest way to see
  underground from above without a second camera.
- **Level 2's save isn't read** (its format was a 2D depth grid; level 2 was live for about an hour). Old
  saves are ignored and start from untouched ground; the farm's field plots are kept.
- **Dug ground is plantable once filled back level** (the "for farming too"): dig to turn the turf, fill, plant;
  or plough.
- Earlier decisions that still stand: the shed's rack for the tools; Q / pad X to fill; the hoe slows him to
  0.6; planting with no tool or the hoe; grows back in 72 game hours; field plots are the farm's own; the mask
  computed ahead.

## What's left

- A push tiller / ride-on (fast ploughing; PLAN.md's "petrol hoe" is for later).
- Gothica and enemies don't know about holes (Gothica stays in the lounge; the arena isn't dug).
- Real-phone speed check; if needed, merged or simplified cave meshes.
- Ideas the owner might like: mushrooms or crops that grow underground; selling gems and fossils at the garage
  rather than straight cash; a lantern to buy; ladders.
