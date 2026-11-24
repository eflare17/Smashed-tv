# Dig Site: physical dirt, progress log

Plan: `integration/dirt_physics_plan.md`. One section a stage, newest last.

## Stage 1: test yard and baseline (done, 24 Nov)

**What was built** (tests only; no game code changed)

- `test/voxel/digsite_yard.gd`: the helper every later stage's test uses (`const Yard := preload(...)`, `Yard.new()`).
  Boots the arena, travels to the Dig Site, levels a 24 x 24 m patch (centre `AT + (0, 0, -2)`, its most common
  level, firm dirt 1.5 m deep under it so a blade never meets rock, no loose layer), finds the bulldozer **by type**,
  parks it on the patch's +z edge heading -z, mounts it, drives it by script; `heap_ahead()`; `mass()` (ground +
  every bucket/tray + what's falling + backpack + the spade's carry, in mm); `FrameTimer` (whole frames, layer_us,
  show_us: n, mean, p95, worst).
- `test/voxel/digsite_yard_test.gd`: the baseline run and its checks. `test/voxel/digsite_yard_shots.gd`: the four pictures.
- Repaired `digsite_dingo_test.gd`, `digsite_fleet_test.gd`, `digsite_ground_test.gd`: two `:=` each on untyped
  members made `=` (6 lines). They load and pass.

**Commands** (from the repository's root; `godot` is the project)

    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_yard_test.gd -- --nosave --phase=1
    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_yard_test.gd -- --nosave --phase=2
    xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_yard_shots.gd -- --nosave --out=res://integration/dirt_shots --tag=before

Phase 1 leaves its `ground_mm` and metres in `user://digsite_yard_run1.txt`; phase 2 runs again, checks its own
against them and writes `integration/dirt_shots/baseline.txt`. Options: `--lift=-0.1` (blade's edge under the tracks,
m), `--secs=20`, `--out=dir`. The shots take about 90 s here (nothing is drawn between pictures).

**The baseline** (20 s, blade 10 cm under the tracks, throttle full, straight across; phase 2's run, in `baseline.txt`)

| Number | Measured | Criterion |
|---|---|---|
| Patch before the run | 0.00 to 0.00 cells off its level | flat to +-1 cell: pass |
| Metres moved | 14.66 | >= 10: pass |
| `ground_mm` + loads, before / after | 5264319250 / 5264319250 | 0 mm drift: pass |
| Two runs: `ground_mm`, metres | identical, identical (0.0000 %, 0.00 %) | within 1 %: pass |
| Frame while dozing (1201 frames) | mean 16.07, p95 21.85, worst 40.01 ms | recorded |
| Frame standing on the dozer (2 s before) | mean 9.18, p95 11.62 ms | recorded |
| `layer_us` | mean 256, p95 407 | recorded |
| `show_us` | mean 419, p95 616 | recorded |
| Heap ahead of the blade | 1.16 m at the end, 1.26 m at most; 1415 blocks banked; 41272 blocks' worth moved | recorded |
| Hard stops | "The blade's full: back up, or raise it" on 164 of 1201 frames; speed 0.00 m/s at the end | recorded |

`DSYARD done 7 passed, 0 failed` (phase 2; phase 1 is 6/0, it has no pair to check).

Noise, measured: five dozing runs this session gave frame p95 21.06, 21.85, 22.94, 23.02, 23.72 ms and mean 14.84 to
16.59 ms (another Godot job was running on the box for some of them). Standing p95 ran 9.95 to 13.47 ms.
`ground_mm` and metres were identical every time; "blocks' worth moved" and "banked" differ by a fraction of a percent
between runs (41080 vs 41272; 1417 vs 1415): the game's settle and layer ticks have wall-clock budgets
(`SETTLE_US`, `LAYER_US`), so runs are not bit-identical. Later mass checks must stay exact; shape checks need a tolerance.

The blade's depth matters a great deal to today's game, same run otherwise:

| `--lift` | Metres in 20 s | Frames stopped dead "blade's full" | Result |
|---|---|---|---|
| -0.20 | 8.96 | 544 (9 s of the 20) | fails the 10 m criterion |
| -0.10 (the baseline) | 14.66 | 164 | passes |
| -0.05 | 21.07 | 42 | passes, but its blade leaves the 24 m patch |

That is the clunk in numbers: at a 20 cm cut the dozer spends nearly half the run at a dead stop behind a text message.

**Shots** (`integration/dirt_shots/`, looked at): `before_1_start.png` (881 kB), `before_2_mid_push.png` (952 kB),
`before_3_heap.png` (860 kB), `before_4_side.png` (720 kB): 4 files, each over 20 kB: pass. They show the dozer on
the patch with its blade up; pushing at 6 s with windrows off the blade's ends; the heap from in front at 14 s; side on.
The lumps in them are the cosmetic `DsClods` skin on the loose layer.

**Guards** (all `-- --nosave` unless said)

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet / ground (repaired) | 14/0, 20/0, 22/0 |
| `digsite_test` | 6 passed, 0 failed (the plan expected 5/1: "Travel Home" passed here) |
| save pair (`--save=<path> --phase=1`, then `--phase=2`) | 4/0, 6/0 |
| sync pair, `--host=YARD1` / `--join=YARD1` as the test's header says | both time out at step 0: no link (the default transport is WebRTC through a signalling server this sandbox cannot use) |
| sync pair, `--host=YARD1 --via=enet` / `--join=127.0.0.1 --via=enet` | host 6/0, guest 9/0 |

The regression set from here on is therefore the plan's, with `digsite_test` at 6/0 and the sync pair run over enet.

**What the owner will see**: nothing in the game. Four "before" pictures and the table above.

**Known gaps and things later stages must know**

- **The plan's frame budget is unreachable as written.** "Whole frame while dozing: p95 <= baseline + 3.0 ms, and
  <= 12 ms": the baseline itself is p95 21 to 24 ms on this box (standing still is already 10 to 13 ms; the rest is
  mostly the changed sections' meshes being rebuilt, `DsTerrain.step`, which `layer_us`/`show_us` do not include).
  Proposed, with the evidence above: keep "p95 <= baseline p95 + 3.0 ms, measured back to back in the same session"
  and drop the absolute 12 ms (or apply it to the standing frame only after measuring it).
- The baseline lives in `integration/dirt_shots/baseline.txt`, not the plan's `integration/voxel_shots/dirt/`
  (this work's shots directory; `--out=` puts it anywhere).
- A dozer moved by script keeps its blade-steadying average from where it was (`_edge_avg`): carried to new ground
  it held the blade up to 0.45 m off its setting until it had driven a few metres. `Yard.park()` resets it
  (`_edge_avg`, `_steady`, pitch, roll). Any test that teleports the dozer needs the same.
- The patch is levelled with `set_cell`, so `start_top` (what CUT reads) is still the site as made: do not use CUT
  on the patch. Levelling also leaves the grass off wherever the ground was cut.
- At -0.05 the blade runs off the patch's far edge before 20 s; the baseline's -0.10 stays on it (blade ends 4 m short).
- The yard test's pair needs phase 1 first: `--phase=2` alone fails with "no first run's numbers".
- `mass()` counts no clods yet (there are none): stage 2 adds `dirt.mass_mm() + dirt.owed_mm()` to it.
