Status: in progress

# Digging level 2 and ploughing: integration note (branch `claude/godot-digging`)

PLAN.md "Later: digging": level 2 (holes you can stand in) and ploughing, with the yard's ground stored as a
depth grid so a voxel level 3 can take it over later.

## What works

- **The yard's ground is a deformable heightmap** (only the yard: the house floors, lobby and arena are as they
  were). A depth grid of 8-unit cells over both yard areas (214 x 230 cells, corner depths in half units),
  drawn as 7 x 8 chunks of 32 x 32 cells. Level grass wears the World's own yard picture (the same texture, so
  untouched ground looks exactly as before); dug, piled and ploughed cells wear a small pixel-art soil atlas
  (dug dirt, furrows, weedy furrows, weedy dirt), shaded by slope and depth so holes read even in the unlit
  phone look. The World's flat yard floor is hidden, its endless ground plane is swapped for four slabs round
  the region plus a `HeightMapShape3D` of the grid (layer 1, the world), so anything physical lands in holes.
- **Players stand in holes** in both views: `Dig` steps right after the Player (and the Net) and sets each
  player's height to his `dz` plus the ground under him; his capsule has a collision exception with the
  heightmap so a hole's wall never shoves him (he walks in and out). First person: the eyes go down with him.
  Online, the other player is stood in holes the same way.
- **What can't be dug** (`dig_mask.gd`, worked out ahead into `dig_mask_data.gd`): only grass in the yard
  (green in the yard picture), 22 units clear of every yard solid (shed, garage, ute, tank, trampoline, fences,
  crop beds, compost, bush, junk, the barbecue and table on the deck), the house and deck, the vegetable patch,
  the farm's weed bed, seed crate, signs and gates, and the tool rack. A hole only goes where all of it fits.
- **The shovel** (the tool rack against the shed's east wall: E "TAKE SHOVEL" / "PUT BACK SHOVEL"): E digs
  where he faces, 9 units a press, waist-deep (36) after four, flat-bottomed with sloping sides; the dirt goes in
  a round pile beside the hole (his right-hand side, or wherever it fits). At the bottom E says FILL; Q / pad X
  (the game's `lobby_alt`, "the second thing a place does") or the touch FILL button fills at any depth, taking
  the pile back. Filled in, it's dug-over dirt that grows back to grass.
- **Finds**, rolled when a hole first reaches the bottom (each spot once): potatoes 30% (2-5, each loads the
  spud gun with its `spudPellets`, as the rope's potatoes do), coins 25% ($3-18 into the shared Wallet), a bone
  7%, a rare stash 2% ($120-250 and a seed you can't buy: GDP, BD, AG or WW); otherwise "NOTHING". A word rises
  over the hole and a chime plays.
- **The hoe** (same rack): walking with it ploughs the grass under its blade into furrows running the way he
  walks (across or down the yard). It's hand work: he walks at 0.6 of his top speed with it in the ground.
- **Planting on ploughed soil**: with seeds picked (the farm's bag) and no shovel in hand, E on ploughed soil
  says "PLANT NL" (etc.) and plants on the nearest spot of a 32-unit grid (all of it ploughed). The farm takes
  it from there (water, fertilise, harvest, raids, saving and its online sync), exactly as at its beds: each
  planted spot is one of the farm's new "field" plots (48 of them).
- **Growing back on the game clock**: untended soil and filled-in dirt go weedy after 36 game hours and back to
  grass after 72 (a little over 3 game days). A crop keeps its soil tended; once harvested and grown over, its
  field plot is freed. Holes and piles stay until filled. (The host's clock; a guest follows the host.)
- **Saved** to `user://smashed-dig.json` (well under 1 KB: int8 depths, the soil, ages and searched spots,
  each deflated, as base64) 2 s after a change and when the window closes or loses focus. Field plots save with
  the farm.
- **Online**: the host owns the ground. A guest's dig, fill and ploughing apply on its own screen at once and go
  to the host as small ops (`{"t": "dig", "k": "op", ...}`; the host replays them without finds: the guest's
  game gave the guest its finds, into its own wallet and gun); the host sends a compact snapshot (the same pack,
  about 200 bytes) when the ground changed (at most every 0.4 s) and every 6 s; the guest ignores the host's for
  1.5 s after acting (as the farm does). Each player's held tool is sent too, so you see the other's shovel. A
  guest leaving gets its own saved ground back.
- **Controls**: keyboard/mouse (E, Q), pad (A, X), touch (the HUD's round E button; a FILL button above ROLL
  when there's a hole to fill). The held tool is a little 3D shovel or hoe at his side top-down, and drawn at
  the bottom right of the screen in first person (it pushes in as you dig). Sounds are made in code (a shovel's
  chunk, dirt going back, the hoe's scrape, a clink at the rack, a find's chime).

## Install (done on this branch)

`scripts/main.gd`, after the farm:

```gdscript
	FarmInstall.install(self)
	DigInstall.install(self)            # digging and ploughing the yard (after the farm: its field plots)
```

It adds `main/Dig` (the grid, tools, saving, online), `main/DigUI`, and `World/DigGround` (the meshes and the
heightmap, under the World so the look pass lights them like the rest of it). Idempotent.

## Changes to other parts' files (all small, and why)

- `scripts/main.gd`: the install line above.
- `scripts/farm/farm_data.gd`: `FIELD_PLOTS := 48`.
- `scripts/farm/farm_state.gd`: 48 plots of a new zone "field" at the end of `plots` (open while placed,
  `on`); `field_plot(x, y)`, `field_free(i)`, `field_near(x, y, r)`; `plot_open` and `grow` use one
  `_is_open` (the field's "on" as well as the land); `to_dict` / `from_dict` carry the field plots' places
  (`"field": [[x, y, on], ...]`; old saves load as before).
- `scripts/farm/farm_world.gd`: a field plot's plant and E spot move to where it's planted (on `refresh`).
- `test/farm/test_farm_logic.gd`: the plot count includes the field plots.
- `scripts/net/net.gd`: `signal message(d)`, emitted for any message type it doesn't know (the dig's), so a part
  can add its own messages without touching net.gd again. The dig sends with `Net.me._send(d)`.
- `scripts/combat/fight_hud.gd`: one row each in the controls help (Tab / pad d-pad down): the shovel and hoe.

## Input actions

None added. E / pad A / the HUD button is `interact` (through `Interactable`, both views); fill is the
existing `lobby_alt` (Q / pad X); touch has its own FILL button (DigUI).

## Tests

- `test/dig/dig_test.tscn` (inside the real game):
  `godot --headless --path <copy> --fixed-fps 60 res://test/dig/dig_test.tscn` ends `DIG TESTS: 77 passed, 0 failed`.
  The mask (lawn yes; every solid, the house, the deck, the vegetable patch, a margin no), the depth grid (four
  presses to 36, flat floor, rim, pile, FILL at the bottom, no hole under the garage), collision (rays land in
  the hole at -36, on the pile, on the lawn, on the house floor and past the region), the player standing in a
  hole, walking out, eyes low in first person, the rack and E digging, the find table and each find's reward
  (wallet, spud gun, stash seed), each spot finding once, filling with Q and E, the hoe ploughing (and slowing
  him), planting on the rows through E, the crop growing, weedy then grass on the clock (`advance_hours` too),
  tended soil staying, the field plot freed, the save (same ground back, 823 bytes) and the field plots in the
  farm's save, the host replaying a guest's ops without finds, snapshots (208 bytes, only changed chunks
  redrawn), and speed.
- `test/dig/make_mask.gd` (`-s`): rebuilds `dig_mask_data.gd` (and a picture of the mask to look at).
- `test/dig/dig_shot.tscn`: the game with `?digdemo`, `at=`, `in`, `fp`, `yaw=`, `pitch=`, `zoom=`, `tool=`,
  `perf` for web screenshots and frame times (set it as the main scene in a work copy and let `test/dig/` into
  the export).
- The existing tests, re-run with digging installed: `test/combat/logic_test.tscn` 53 passed, 0 failed;
  `scenes/arcade/arcade_test.tscn -- --logic` 0 failed; `test/farm/test_farm_logic.gd` 76 passed, 0 failed;
  `test/lobby_life/run.tscn` (see below).

## Decisions

- **Cells of 8 units, chunks of 32 cells.** Fine enough for round holes about a body wide, coarse enough that a
  chunk rebuilds in about 0.4 ms natively (a dig with its collision about 2.5 ms) and the yard is 56 chunks.
- **Players aren't pushed by the heightmap**: the Player walks by his own height (y from `dz`, no gravity), so
  `Dig` sets his height from the grid and gives his capsule a collision exception with the heightmap. A hole's
  steep wall would otherwise shove him out or trap him; this way he walks down in and climbs out. The
  heightmap is there for anything physical and for rays.
- **Waist-deep is 36 units** (his eyes are at 62), four presses of 9.
- **Fill is Q / pad X** (the game's `lobby_alt`, already "the second thing a place does"), and E fills once
  the hole is at the bottom, so E alone digs and fills.
- **Finds roll once per spot** (when the hole first reaches the bottom), so the yard can't be farmed for cash.
  Chances and amounts are in `dig_data.gd`.
- **The hoe slows him** to 0.6 of his top speed on diggable ground (hand work); a push tiller later can skip it.
- **Planting needs no tool** (any but the shovel, which digs), so you can plough, put the hoe back and plant.
- **Grows back in 72 game hours untended** (weedy at 36): about three and a half game days.
- **The farm's planting on ploughed soil** is the farm's own plots (a pool of 48 "field" plots) rather than a
  second crop system, so watering, fertiliser, harvesting, raids, the panel and the farm's online sync all just
  work there.
- **A mask computed ahead** (`dig_mask_data.gd`) instead of at start: it reads the yard picture's colours, which
  costs about 90 ms natively (more on a phone). Rebuild it with `make_mask.gd` if the yard data changes;
  `Dig` works it out at start if the stored one doesn't fit.
- **A level 3 can take over** `DigGrid.depth` (corner depths, positive down, `depth_at(x, y)`), the soil bytes,
  and `DigGround`'s place in the World; the tools, finds, saving and the network code don't depend on the mesh.

## What's left

- A push tiller / ride-on (fast ploughing): optional, later. `Dig._plough_step` takes the hoe's place.
- Gothica and enemies don't know about holes (Gothica stays in the lounge; the arena isn't dug).
- The other player's ground height online is set here from the grid on each screen (both have the same grid).
