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

**After verification, round 1** (24 Nov; test and documents only, no game code and nothing in `ds_dirt.gd`)

- **`digsite_clod_perf` was flaky**: the verifier's run 2 of 5 failed its first check because 1200 awake fit in all
  three of its repeats (mean 1731 to 1965 us, p95 2969 us), with the box's load at about 6, not on a quiet one as
  predicted above. The check asked for equality ("`FLY_MAX` is the largest count that fits"), so it failed when the box
  had a good minute. It is now one-sided: **`FLY_MAX` itself fits in every repeat** (and is one of the counts held);
  a larger count that fits too prints `DSCLODPERF note 1200 fit as well this time` and fails nothing. That loosens
  one side of the plan's wording, on this evidence: over the verifier's 5 runs and the 7 here (three repeats of each count in each) 1200 fit all three once and 800 fit every single time, so 800 is the count that holds on a bad day, which is
  what a cap is for. The side that matters is as strict as before: 800 over the limits in any one repeat still fails.
  Checked both ways: with `FLY_MAX` put to 400 for a run (`--counts=400,800`) the check passes with the note; with
  `--counts=400,1200` (800 not held) it fails.
- **Seven runs back to back** after the change (load average 3.4 to 5.5): 5/0 every time. 800: mean 1168 to 1906 us,
  p95 3002 us at most over 21 repeats (limits 2000 and 4000). 1200: "over" in all seven (its best repeat 1705 us, its
  worst 2874; p95 up to 4369). The time cap with 1600 offered: p95 2373 to 3008 us, mean 2011 to 2043. Mass 0 mm off.
  At rest 0.39 to 0.47 us.
- `digsite_clod_test` again: 10/0, the same numbers as above to the digit (6.62 s, 79 mm, 31.5 degrees, 4.58 m).
- **The guards, all run to the end this time**, one after another in one session (the verifier saw only the dirt
  test before it had to return):

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet / ground | 14/0, 20/0, 22/0 |
| `digsite_test` | 6/0 |
| save pair (`--save=<path> --phase=1`, then `--phase=2`) | 4/0, 6/0 |
| sync pair (`--host=YARD1 --via=enet` / `--join=127.0.0.1 --via=enet`) | host 6/0, guest 9/0 |

- The plan's technical model now says what was built (the capped heap, the even deposit, `STUCK_S`, the shed order)
  and its stage 2 says how the perf verdict is taken.
- Untracked `godot/.facts` and two `stkilda_*.gd.uid` files in the work tree are not this branch's (the tests and the
  import write them); they are left alone and not committed.

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

## Stage 2: clod core spike on a bare grid (done, 24 Nov)

**The answer**: a clod costs **1.4 to 2.1 us a step** in GDScript against this grid (1.4 to 1.5 when the box is quiet).
**`FLY_MAX` = 800.** The native library **can** be rebuilt here for Linux and Windows.

**What was built** (nothing in the game uses it yet: no game code changed)

- `scripts/voxel/digsite/ds_dirt.gd` (`DsDirt`, a `RefCounted`): clods as struct-of-arrays on a `DigSiteGrid`.
  `setup(grid, origin)`, `spawn(p, v, material, mm)`, `spawn_mass(p, v, material, mm, spread, within)` (crumbs 125,
  clods 500, chunks 2000 mm; 2x and 3x coarser over a fifth and a half of the cap; under a crumb goes straight to the
  ground), `step(dt)`, `mass_mm()`, `owed_mm()`, `awake()`, `land_all()`, `fly_max`, `cap_us`, `seed_`, `step_us`.
  Fall (gravity 9.8), bounce (over 2 m/s into the ground: restitution 0.25), roll (friction 0.7, the slope from the
  ground and the awake heap), the awake heap (quarter-metre squares), settle (under 0.4 m/s for 0.25 s on under 30
  degrees; or 6 s old), a batched deposit (`put_layer`, once a step, 200 clods a step at most), the time cap
  (`CLOD_US` 2000: over it, clods are settled where they are and spawns go straight to the ground). No drawing, no
  spin, no machines, no tunnels, no network: stage 3 on.
- `test/voxel/digsite_clod_test.gd`, `test/voxel/digsite_clod_perf.gd`. Bare 128 x 96 x 128 grid, no arena.

**Commands** (from the repository's root)

    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_test.gd -- --nosave
    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_perf.gd -- --nosave --out=res://integration/dirt_shots

(3 s and 30 s. The perf test's options: `--counts=400,800`, `--secs=10`, `--reps=3`; `--out` writes `clod_perf.txt`.)

**`digsite_clod_test`: `DSCLOD done 10 passed, 0 failed`**

| Criterion | Measured |
|---|---|
| 1000 clods from 3 m onto one spot (10 a tick, 500 mm each), all deposited within 8 s | 6.62 s (tick 397); 702 awake at most |
| Mass exact to the mm | 0 mm off at every tick and at the end; all 500000 mm is loose dirt on the ground |
| No column more than 250 mm over its neighbours, at any tick | 79 mm at most (a column over all four straight neighbours, each measured over the ground as it was) |
| Pile slope 28 to 38 degrees after slump | 31.5 (eight ways: 30 28 30 31 33 31 33 36); 1.29 m high |
| A clod let go on a 40 degree heap goes over 1 m downhill before settling | 4.58 m down the bank (to its foot), fastest 4.2 m/s, settled 0.5 m past it |
| Two runs, identical `section_hashes` | identical; all gone at tick 397 both times |

The slope is the rise from a quarter to three quarters of the pile's height over the run between them, averaged over
eight directions. The "40 degree heap" is a firm bank built for the test (cells and a firm layer, a true plane; the
grid is not ticked in that part): loose dirt will not stand at 40.

**`digsite_clod_perf`: `DSCLODPERF done 5 passed, 0 failed`** (three whole runs back to back, load average 2 to 3.5
from another job; each run holds each count three times, turn about; the last run's table is in
`integration/dirt_shots/clod_perf.txt`)

| Awake | `step_us` mean over the 9 runs | p95 at most | a clod | Verdict (2.0 ms mean, 4.0 ms p95) |
|---|---|---|---|---|
| 400 | 647 to 1012 | 1205 | 1.6 to 2.5 us | fits |
| 800 | 1189 to 1671 | 2272 | 1.5 to 2.1 us | fits, every run |
| 1200 | 1649 to 2457 | 3542 | 1.4 to 1.9 us | on the line: over in at least one run of every three |
| 1500 | 2038 to 3196 | 4909 | 1.5 to 2.2 us | over |

| Criterion | Measured |
|---|---|
| `FLY_MAX` (800) fits in every run (see "after verification" below) | 800 fits in all three; 1200 did not here |
| The time cap holds p95 <= 4.0 ms at 2x (1600 offered) | p95 2778 to 3052 us (the middle run of each three), mean 2012 to 2017; it kept 1015 to 1292 awake, settled 1500 to 4900 by force and turned 3400 to 3800 spawns straight to the ground |
| Mass exact | 0 mm off in every run |
| All clods at rest: `step_us` <= 0.05 ms | 0.0004 ms (0.4 us) |

The workload: clods let go a dozen at a time from 1 to 2.5 m up, all over the middle 10 x 10 m, topped up every tick;
half to two thirds of them are on the ground at any time (the dear half). The grid slumps under them with the game's
kind of budget (2 ms); its time is not in `step_us` (it was 0.9 to 1.5 ms a tick here: "grid" in the table).

**How the verdict is taken, and why**: the box is shared and the same code's step time moved by a third between one
run and the next (800 awake: 1189 us, then 1671 us). So each count is held three times and **fits only if every one of
its runs does** (a cap has to hold on a bad day). That is stricter than one run, not looser. 1200 is honestly on the
line (best 1649 us, usually 1900 to 2300): now and then it fits, and the test then says so in a note (it used to fail:
see "after verification" below). `FLY_MAX` is one constant; the time cap adapts anyway (with 1600 offered it kept 1000 to 1300 awake inside 2 ms).

**What it took to get there** (the per-clod cost, same test, back to back): as first written 2.3 to 2.45 us; ground
looked at only when an airborne clod could have reached it (up to 6 steps, the fallback ladder's first rung, done
better) 2.05 to 2.2 us; a square's slopes kept 3 steps instead of worked out every step (5 `height_at` calls each)
1.46 us. The awake heap stayed: the ladder's other rungs were not needed.

**Where it differs from the plan, and why**

- **The awake heap is capped** (`HEAP_FULL`, 1500 mm in a square), and a clod coming down on a full square settles
  there and then (the plan's "or overflow"). Uncapped, as the plan had it, 1000 clods onto one spot stood 3.4 m of
  floor under the stream and threw them out at 8 m/s to 9 m away: the "pile" was 0.29 m high at 4 degrees. With it
  off, the test fails at 4.7 degrees.
- **The deposit is not bilinear over 4 columns.** A clod's dirt goes evenly onto 2 x 2, 4 x 4 or 6 x 6 columns by its
  size. A chunk's 2000 mm on four columns is a 500 mm spike, against the plan's own 250 mm. And a clod waits a step if
  its middle column has had 36 mm that step (`DEP_COL`), so the ground rises evenly: 79 mm worst. (Without the wait:
  133 mm, still passes, and clods settle sooner, 4.9 s. A knob for stage 9.)
- **`STUCK_S`**: slow for 1 s settles whatever the slope (the plan's rule leaves a clod on a 30 to 35 degree flank
  waiting for its 6 s). Without it the drop takes 7.65 s, with it 6.62.
- **A 2 cm contact skin**: rolling down a bank a clod was "in the air" every other step by rounding, so friction only
  half applied (6.1 m/s down the test's bank; 4.2 with the skin).
- **Bounces keep 60% of their speed along the ground** (0.85 threw clods 5.7 m from a 3 m drop).
- **Shedding at the time cap** takes clods on the ground first, then the front of the list: not strictly "slowest,
  then oldest" (sorting 800 a step costs more than it saves).
- No spin or basis yet (drawing: stage 3). The id is kept (16 bits).

**Native probe: passed** (outside the work tree, in the scratchpad's `native_probe/`)

- `scons` 4 and `x86_64-w64-mingw32-g++` 13-win32 are installed here. godot-cpp branch 4.4 (`b0e3b1e`) built
  `template_release` for Linux, then for Windows with `use_mingw=yes` (about 25 minutes each at `-j2` on this box).
- `native/build.sh` on a copy of the **unmodified** sources: 34 s, a `.so` (798528 bytes, the committed one's size)
  and a `.dll` (PE32+ x86-64, 1558016 bytes; the committed one is 1557504; imports only KERNEL32 and msvcrt).
- The rebuilt `.so`, put in the tree for the run and taken out again: `digsite_dirt_test` 12/0, `digsite_clod_test`
  10/0. The committed binaries are unchanged (`git status` clean on `native/bin`).
- The `.dll` could not be run here (no Windows): "produced" is all that is claimed for it.
- So stage 9's native part is unlocked. godot-cpp must be rebuilt if the scratchpad is cleared (it is not in the repo).

**Guards** (`-- --nosave`; no game code changed in this stage)

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet | 14/0, 20/0 |
| ground | 21/1, then 22/0, 22/0, 21/1 over four runs: the one failing is "no frame over 16 ms building (worst 17.6 ms)", a wall-clock check on a loaded box |
| `digsite_test` | 5/1 once (the failing line was not captured; the plan's known one is "Travel Home"), then 6/0 three times |
| save pair | 4/0, 6/0 |
| sync pair over enet | host 6/0, guest 9/0 |

**After verification, round 1** (24 Nov; test and documents only, no game code and nothing in `ds_dirt.gd`)

- **`digsite_clod_perf` was flaky**: the verifier's run 2 of 5 failed its first check because 1200 awake fit in all
  three of its repeats (mean 1731 to 1965 us, p95 2969 us), with the box's load at about 6, not on a quiet one as
  predicted above. The check asked for equality ("`FLY_MAX` is the largest count that fits"), so it failed when the box
  had a good minute. It is now one-sided: **`FLY_MAX` itself fits in every repeat** (and is one of the counts held);
  a larger count that fits too prints `DSCLODPERF note 1200 fit as well this time` and fails nothing. That loosens
  one side of the plan's wording, on this evidence: over the verifier's 5 runs and the 7 here (three repeats of each count in each) 1200 fit all three once and 800 fit every single time, so 800 is the count that holds on a bad day, which is
  what a cap is for. The side that matters is as strict as before: 800 over the limits in any one repeat still fails.
  Checked both ways: with `FLY_MAX` put to 400 for a run (`--counts=400,800`) the check passes with the note; with
  `--counts=400,1200` (800 not held) it fails.
- **Seven runs back to back** after the change (load average 3.4 to 5.5): 5/0 every time. 800: mean 1168 to 1906 us,
  p95 3002 us at most over 21 repeats (limits 2000 and 4000). 1200: "over" in all seven (its best repeat 1705 us, its
  worst 2874; p95 up to 4369). The time cap with 1600 offered: p95 2373 to 3008 us, mean 2011 to 2043. Mass 0 mm off.
  At rest 0.39 to 0.47 us.
- `digsite_clod_test` again: 10/0, the same numbers as above to the digit (6.62 s, 79 mm, 31.5 degrees, 4.58 m).
- **The guards, all run to the end this time**, one after another in one session (the verifier saw only the dirt
  test before it had to return):

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet / ground | 14/0, 20/0, 22/0 |
| `digsite_test` | 6/0 |
| save pair (`--save=<path> --phase=1`, then `--phase=2`) | 4/0, 6/0 |
| sync pair (`--host=YARD1 --via=enet` / `--join=127.0.0.1 --via=enet`) | host 6/0, guest 9/0 |

- The plan's technical model now says what was built (the capped heap, the even deposit, `STUCK_S`, the shed order)
  and its stage 2 says how the perf verdict is taken.
- Untracked `godot/.facts` and two `stkilda_*.gd.uid` files in the work tree are not this branch's (the tests and the
  import write them); they are left alone and not committed.

**What the owner will see**: nothing in the game. The cost table above and the cap: 800 clods moving at once.

**Known gaps and things later stages must know**

- `Yard.mass()` does not count clods yet: there is no `DsDirt` in the site until stage 3 (add `dirt.mass_mm() +
  dirt.owed_mm()` there).
- **A native hang, found by accident**: `put_layer` on a column at the grid's roof whose neighbours are all at the
  roof too never returns (`lay_put` passes the spare to the lowest neighbour, which passes it back). The first perf
  workload built a ridge to the roof (100 m3 poured along one 20 m path) and hung there. The game's site is far from
  that, and the perf test now spreads its dirt, but stage 3 should keep clods from depositing within a metre of the
  roof, or stage 9 fix `lay_put`.
- Deposits can outrun the slump: the layer's budget (`LAYER_US` 1500 in the game) decides how fast a heap spreads.
  With 1500 awake the grid's tick here took 1.4 to 1.8 ms of its 2 ms. Stage 5 should watch `layer_us` while dozing.
- With `cap_us` on, runs are not bit-identical (the cap is by the clock). The determinism check runs with it off.
- Clods are kept 1.5 m in from the grid's side (the edge ring takes no loose dirt).
- The perf numbers are for clods alone on a bare grid: drawing (stage 3) and machine boxes (stage 3 on) come on top,
  inside the same 2 ms.

## Stage 3: clods in the site (done, 24 Nov)

**What was built**

- `scripts/voxel/digsite/ds_dirt.gd`, on top of stage 2's core:
  - **Drawing** (`make_draw(parent)`): one MultiMesh of the lumps the loose dirt already wears (`DsLook.clod_mesh`), one
    buffer a step. An instance's transform is only where the clod is; the new `shaders/ds_dirt.gdshader` sizes, shapes
    and turns it from the instance's custom data (material, radius and a shape number packed in one float; how far it
    has turned; the level line it turns about), so a clod costs seven numbers a step to draw. Rolling, a clod turns at
    its speed over its radius; thrown, it tumbles. Lit and coloured as the lumps on the ground are, drawn after the ink.
  - **Shrink on settle**: a settled clod is drawn 0.15 s more, shrinking into the ground (256 at once at most).
  - **Box colliders** (`set_boxes([[Transform3D, half size, kind]])`): a clod inside a box is put out by the face it
    came in at (the one it was furthest outside a step ago, with the box where it was then: a thin tray wall or a quick
    blade does not let it through); it keeps the box's own speed at that point, loses its speed into the face (bounces
    if it hit hard) and 30% a step of its speed across it (it is carried). **Broadphase**: each box marks the 1 m
    squares it is over (a bit a box, redone only when a box has moved); a clod looks at a box only in a marked square,
    and a clod napping in the air wakes there. Kinds: `K_BODY`, `K_BLADE`, `K_BUCKET`, `K_TRAY`.
  - **The blade's rules**: a clod a blade is shoving does not settle (it would be cut again at once); at the face they
    stack, each on those counted before it in its quarter-metre square (up to 1.25 m); one over 0.6 of the blade's
    height is sent along the face to the nearer end at 1.6 m/s (the roll-over rule: off the end it is a windrow). At a
    blade standing still a clod settles as anywhere. On top of a body or a blade a clod slides off the side. Off the
    ground on a bucket or in a tray it is held and does not age.
  - **Tunnels**: a clod well under the surface with ground over it goes by the cells, not the surface (`_cave`: a
    solid cell across is a wall, under its feet the floor, over its head the roof). At rest its dirt goes back where
    it lies in whole loose blocks (`fill_sphere`), not on the hill over it; what will not fit is owed (`owed_mm()`, in
    the mass sum) and tried again with the next clod there; `land_all()` puts what is still owed down (a wider ball,
    then the surface). A spawn turned away under a roof goes the same way.
  - Also: `last_id`, `settle_log` (tests), `hits_n`, `buried_n`, `draw_us` (in `step_us`).
- `dig_site.gd`: makes the site's `DsDirt` (`dirt`), steps it 60 times a second where the dirt runs (solo, or the host),
  hands it every machine's boxes while there are clods (`clod_boxes()`, plus `extra_boxes` for tests); `land_all()` on
  leaving and on quitting; the debug key.
- `ds_machine.gd`: `body_box()` (its footprint, `body_high` tall) and `clod_boxes()` (body + its `keepout_boxes()` as
  blade or bucket). `ds_truck.gd`: `tray_boxes()` (floor and four walls in the tray's own frame, so they tip with it;
  the tailgate goes once it is tipping), its chassis and cab as bodies. Dozer, Bobcat, excavator: their heights.
- `test/voxel/digsite_clod_site_test.gd`, `test/voxel/digsite_clod_site_shots.gd`; `digsite_yard.gd`'s `mass()` counts
  the clods and what they owe.

**Commands** (from the repository's root)

    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_site_test.gd -- --nosave --out=res://integration/dirt_shots
    xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_site_shots.gd -- --nosave --out=res://integration/dirt_shots

(50 s and 60 s. The test writes `integration/dirt_shots/clod_site.txt`.)

**`digsite_clod_site_test`: `DSCLODSITE done 14 passed, 0 failed`** (seven runs in a row after the last change to the
clods; the physics numbers are the same to the digit every run, the timings are the range over them)

| Criterion | Measured |
|---|---|
| (a) 500 clods poured over 5 s in front of a scripted moving box (the dozer blade's size, 2 m/s for 6 s): none end inside it | 0 settled inside it; and on no frame was any clod's middle inside it (58304 box hits; 301 awake at most) |
| (a) mean travel >= 3 m | 4.42 m (least 0.01, most 12.06) |
| (b) 300 dropped into the parked truck's tray: >= 95% rest inside | 300 of 300, the fastest going 0.00 m/s 5 s on |
| (b) 0 through the floor | 0 |
| (c) 100 let go in a dug tunnel (1 m across, 6 m long, a 0.4 m roof): the surface over it gained 0 mm | 0 mm, 0 of 1425 columns changed; all 100 put back under the roof: 400 loose blocks in the tunnel = the 50000 mm let go; owed 0 mm |
| (d) `land_all()` leaves 0 clods | 300 before (the tray's), 0 after, 0 mm in clods, 0 owed |
| `step_us` mean <= 2.0 ms, p95 <= 4.0 ms (drawing in it, time cap off) | mean 828 to 942 us, p95 1417 to 1825 us, over 1022 steps with up to 400 awake; drawing 64 to 79 us of it |
| frame p95 <= baseline + 3.0 ms | 11.85 to 13.64 ms against the baseline's 12.53 to 13.80 ms in the same run: -1.3 to +0.6 ms |
| mass exact | 0 mm off at all 42 checks (every second and after each part) |

**The frame baseline, and why it is what it is.** The plan's "baseline + 3.0 ms" means stage 1's dozing p95 (21.85 ms):
this test's 11.85 to 13.64 ms is 8.2 to 10.0 ms *under* that, so the plan's criterion as written passes with nothing to
see. The test holds a stricter one, measured back to back in the same run: after (d) the run is played again frame for
frame with no clods, each clod's dirt laid straight on the ground (or in the tunnel) where and when its clod settled,
and the clods' frames must be within 3.0 ms of *that* at p95. A first version compared with the scene doing nothing at
all (3 s before (a)): that is still printed (clods awake are +1.6 to +5.4 ms over it at p95, +1.3 to +2.8 ms at the
mean), but it failed two runs of the first four at +3.3 and +4.1 ms, and most of that is not the clods: dirt landing makes the
ground slump and redraw its sections whoever laid it (the baseline replay alone is +3 to +4.5 ms over the idle scene).
What the clods themselves add shows in the mean: 0.2 to 1.3 ms a frame over the baseline, with 300 to 400 awake.

**Stage 2's tests after the change**: `digsite_clod_test` 10/0 with the same numbers to the digit (397 ticks, 79 mm,
31.5 degrees, 4.58 m): the clods' look takes nothing from their random numbers, and the tunnel rule only applies to a
clod that was already in a hole (a first version sent clods buried by a fast-rising pile down that path: 364 ticks and
119 mm, still passing but not the same; fixed). `digsite_clod_perf` 5/0: 800 awake mean 1334 to 1497 us, p95 2216 us at
most (limits 2000 and 4000): the new checks in the loop (a box about? under a roof?) and the spin cost about 0.1 us a clod.

**Two things found and fixed on the way**

- **The time cap turned clods away for no reason.** `us_per_clod` was a step's time over its clods whatever their
  number: with three clods left a step's own overhead made one look like 20 us, and the next 13 of 300 let go were
  refused (laid straight on the ground). It is now taken only from steps with 64 clods or more (`PER_FROM`).
- **A clod pushed along the ground was only "at the blade" every other step** (it drops a few mm behind between
  steps), so it settled under the blade's nose: mean travel 1.27 m. A box now counts as touched within 12 mm
  (`TOUCH`): 4.42 m.

**Shots** (`integration/dirt_shots/`, looked at): `clods_1_push.png`, `clods_2_push_side.png` (the bulldozer, blade just
clear of the ground so it cuts nothing, clods poured ahead: lumps stacked up the blade's face and rolling ahead of it,
melted ones as low lumpy mounds behind); `clods_3_tray_falling.png`, `clods_4_tray.png` (300 into the truck's tray:
lying on its floor inside the walls); `clods_5_thrown.png`, `clods_6_landing.png`, `clods_7_melted.png` (the debug
key's throw on foot: in the air, on the ground, gone into it). The lumps match the ground's own.

**What the owner will see**: at the Dig Site, on foot, **K** throws a barrow's worth of dirt out ahead of you (a debug
key: it is dirt from nowhere). The lumps fly, tumble, bounce, roll and after a moment shrink into the ground as a low
mound. Throw them at a machine and they bounce off it; into the truck's tray and they lie in it; drive the dozer into
them and it shoves them along, stacked on its blade. Nothing the tools or machines do makes clods yet (stage 5 on).

**Guards** (one after another in one session, after the last change; `-- --nosave` unless said)

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet / ground | 14/0, 20/0, 22/0 |
| `digsite_test` | 6/0 |
| `digsite_clod_test` / `digsite_clod_perf` | 10/0 / 5/0 |
| save pair (`--save=<path> --phase=1`, then `--phase=2`) | 4/0, 6/0 |
| sync pair (`--host=YARD1 --via=enet` / `--join=127.0.0.1 --via=enet`) | host 6/0, guest 9/0 |
| `digsite_yard_test` phase 1, 2 (no clods are made by the dozer yet) | 6/0, 7/0: 14.54 m (14.66 the run before: 0.81% apart), frame p95 20.63 ms, mass exact |

The yard shots were taken again (`stage3_1_start.png` to `stage3_4_side.png`): the dozer's push is stage 1's, as it
should be (nothing a machine does makes clods yet).

**Known gaps and things later stages must know**

- **Clods lying in a tray or on a bucket stay clods** (awake, counted against `FLY_MAX`, about 2.5 us each a step)
  until `land_all()`: stage 6 takes them into the load. In a tray they lie in one layer, overlapping: no stacking.
- **A bucket's box is its whole hollow, solid**: clods cannot get into a bucket yet (stage 6).
- **The time cap can drop a clod through a tray**: over the cap it settles ones on the ground first, then from the
  front of the list wherever they are, and a tray's clod then lands on the ground under the truck (seen once, with the
  cap on and the box loaded). Stage 6 should take tray clods off the list before that matters.
- **Owed dirt measured 0 mm** here (risk 3): every clod is a whole number of blocks, so dirt is only owed when the
  tunnel has no room within the ball. `land_all()` then tries a wider ball and only after that the surface.
- A clod up against a vertical bank **in the open** still goes by the smooth surface, as in stage 2 (the loose layer
  is up to two blocks deep with no cell to show for it, so the cells cannot say where open ground is). Under a roof,
  walls are walls.
- The clods step at 60 Hz and are drawn where they are: at a higher frame rate they move in 60 Hz steps (stage 9).
- Guests see no clods and the debug key does nothing for them (stage 8). The minute's autosave does not put clods
  down (leaving and quitting do): with only the debug key making them nothing real is lost; stage 8 settles it.
- `put_layer` at the grid's roof (stage 2's note) is still unguarded.
- The site test runs with `cap_us = 0` so that it is the same every run; the cap itself is `digsite_clod_perf`'s.

## Stage 4: machine weight (done, 24 Nov)

**What was built** (no clods in it: this is how the machines drive)

- `ds_machine.gd`, `_drive`: **a drive against what holds it back, over its weight**, instead of a speed it is moved
  toward. The drive pulls `accel * PULL` (2.5) m/s2 standing and nothing at top speed; what a machine is pushing
  (`drive_resist(dir)`, a subclass's) pulls the other way, as a share of that. Flat out with resistance r it settles
  at (1 - r) of its top speed, the same speeds the old code clamped it to, but it gets there by slowing; at r >= 1 it
  stalls. Let go, its brakes bring it to a stand. A slope as steep as it climbs is 0.4 of resistance.
  - **Track slip**: from r 0.35 its tracks turn faster than it goes, at r 1 (or held at a bank) they turn at 0.7 of
    what is asked with the machine standing. `track_v` drives the track and wheel models, `slip` (0 to 1) the dust: a
    second emitter throws dirt and lumps out behind slipping tracks.
  - **Turning eased** at 4/s, changing by no more than `turn_rate * 5` a second (it was instant).
  - **Banks seen coming** (`_look_ahead`): the old code set speed to 0 in the frame a step, a slope or a bank was met
    (`ds_machine.gd:500`). Now, going faster than 0.5 m/s, it looks where it could just stop for what would stop it,
    and holds its speed to what it can still stop from in what is left, so it arrives nearly standing. What is left
    when it gets there (0.5 m/s as tested) is a bump: a clunk and a kick of the nose.
  - **Body rock** (`sway`, both games, from what both know): a spring (10 rad/s, damping 0.4) on the body, nose up
    pulling away, down braking, down 1.2 degrees leaning into a load; 3.2 degrees asked at the most. It turns the
    body and what is on it (`shake_node`), not the tracks, and the tool does not feel it: digging is unchanged.
  - **Landing thud**: coming down faster than 1.6 m/s and stopped, the body drops on its springs (`bob`) and comes
    back, a thump, dust from under it.
  - The guest sees the slip: it rides in the state's driver number (the whole number is who, the rest half the slip),
    so the message is the same length.
- `ds_dozer.gd`: its three hard stops are gone (`speed = minf(speed, 0)` on a jam, on rock, and `_jam`'s clamp).
  `drive_resist` is the old load and cutting slow-down, plus: the heap ahead nearly brim full (`full`, 12 height
  samples where the blade lays what it cuts: up to 0.45), a firm face standing over the edge just ahead (`bank`, 6
  samples 0.31 and 0.75 m ahead: up to 1.4, so a bank holds it from just before the blade meets it), what it could not
  move at all (a jam: 2.2, fading at 3/s) and rock (3.0). The blade's rams ease in and out (`LIFT_EASE` 5/s). New
  message at a bank: "Too deep a bite: back up, or raise the blade".
- `ds_dingo.gd` (and the Bobcat through it): `drive_resist` for the dirt banked on the bucket and for rock (it stalls
  in a hand's width instead of `speed = 0`); arms and bucket eased (`ARM_EASE` 5/s, the excavator's).
  `ds_truck.gd`: the tray's ram eased; it rocks less (`sway_k` 0.7). `ds_excavator.gd`: its tracks show `track_v`.
- `ds_sfx.gd`: revs come up with the throttle before the machine moves and with tracks turning though it is not
  moving; held back the engine drops in pitch and gets louder (`lug`); the track clatter follows the tracks' speed and
  is louder and faster slipping.
- `test/voxel/digsite_feel_test.gd`, `test/voxel/digsite_feel_shots.gd`.

**Commands** (from the repository's root)

    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_feel_test.gd -- --nosave
    xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_feel_shots.gd -- --nosave --out=res://integration/dirt_shots

(70 s and 50 s. The test writes `integration/dirt_shots/feel.txt` and reads its baseline from
`integration/dirt_shots/feel_base.txt`: "p95 metres top". The baseline is the same test on stage 3's game
(`fd001a4` checked out beside, this test file copied in) with `--write-base --out=<dir>`; `--base=<file>` reads one
from elsewhere; `--debug` prints the run frame by frame.)

**`digsite_feel_test`: `DSFEEL done 22 passed, 0 failed`** (five runs after the last change; everything but the frame
times is the same to the digit every run). "Before" is the same test on stage 3's game: 12 passed, 8 failed.

| Criterion | Before (stage 3) | Measured |
|---|---|---|
| (c) dozer flat out into a 1.5 m bank the test builds (blade carried 0.35 m up): from over 2 m/s to under 0.3 m/s takes > 0.3 s | 0.02 s | 0.42 s, over 0.47 m (top 3.17 m/s) |
| (c) no frame loses more than 25% of top speed (0.80 m/s), as it moved and as it says | 2.78 m/s in one frame | 0.093 m/s |
| (c) slip > 0.5 while stalled (2 s, throttle full on) | no slip | 1.00 at the least; it stands still (0.00 m/s) |
| (c) peak pitch 1.5 to 5 degrees | 0 | 3.96 degrees nose down, 0.28 s before it stops; 1.20 leaning on the bank after |
| (b) yaw rate changes by <= `turn_rate * dt * 6` a frame (0.0800 rad/s), hard over one way, then the other, then let go | 1.6000 | 0.0667; it reaches 0.798 of 0.80 rad/s and stops turning |
| (a) on the flat, top speed within 10% of stage 1's 3.2 m/s | 3.20 | 3.20 (90% of it in 2.07 s, as before: 2.05; let go it stands in 1.10 s) |
| (d) the 20 s push moves >= 80% of the baseline metres | 14.66 m | 12.29 m: 84% (the most a frame lost: 0.136 m/s, before 2.07) |
| (d) frame p95 <= baseline + 0.5 ms | 20.99, 21.37, 20.13, 21.16 ms | 20.30, 20.98, 18.87, 20.60 ms: -0.69, -0.39, -1.26, -0.56 |
| mass exact | 0 mm | 0 mm after (a), (c), (f), (d) and at every second of (d) |
| (e) added: dropped 1 m it lands with a thud, body 2 to 10 cm down and back | none | 3.4 cm, then 0.0 |
| (f) added: the Bobcat, bucket up, flat out at the same bank: no frame loses more than 25% of its top speed (0.75 m/s) | not run | 0.506 m/s (the last bump); it stands 0.30 m off the face, wheels spinning |

**The frame baseline and how it was taken.** Four pairs back to back in one session with nothing else running (load
1.1): stage 3's game, then this one, each the whole test, the p95 of (d)'s 1201 frames. Every pair has the new game
under the old. The committed `feel_base.txt` is the first pair's baseline (20.985 ms); a later run should take its
own the same hour, since this box's p95 moves by a millisecond between runs. Not the same work on both sides: the new
dozer bogs sooner, so after 5 s it moves less dirt a frame than the old one did. What the weight itself costs is small
(18 ground samples a dozer step, one bank look a step at speed, two springs).

**Where a criterion's meaning had to be chosen**

- "Speed" is how far it really moved along its nose in the frame, and also what it says; both are checked.
- "Peak pitch" is the body's rock (`sway`). The ground's own pitch under it is printed (0 degrees in the bank run).
- 80% of the baseline metres passes at 84%, and that is a real change, not noise (the run is the same every time). The
  old dozer covered its last 5 m in lurches: stopped dead by a jam, off again at up to 2 m/s, stopped dead again (2.07
  m/s lost in a frame, 165 frames of "the blade's full"). The new one lugs down to a crawl with its tracks slipping
  (mean slip 0.69 over the 20 s) and creeps. Stage 5 holds its metres against this stage's 12.29 m.

**Three attempts that did not work** (so the next stage does not repeat them)

- Holding the dozer back by how full the heap ahead is, hard enough to stall it: it stalled for good at 9.2 to 10 m
  (63 to 69% of the baseline). A full blade in the open is not stuck: it spills off its ends and the heap slumps on.
  Adding the windrows' room did not tell a bank from a heap either (both read 0.92 full).
- Letting the jam alone stop it at a bank: 0.25 s from 2 m/s (fails), and the blade ends 1.4 m into the face.
- What does tell a bank from a heap is that a bank is firm: hence `bank`, firm ground over the edge just ahead.

**Shots** (`integration/dirt_shots/`, looked at): `feel_1_bite.png` (side on, 0.95 m/s and falling, nose 3.7 degrees
down, the blade in the bank's face), `feel_2_stalled.png` (from behind, stalled, dust thrown out behind the tracks, the
new message on the screen), `feel_3_let_go.png` (side on again, throttle off: level). The yard's four again as
`stage4_1_start.png` to `stage4_4_side.png`: the push looks as before, the dozer a little short of where it got to.

**What the owner will see**: drive the bulldozer at a bank and it no longer stops as if it had hit glass. It comes in
braking, the nose dips, the blade bites in about half a metre, and it stands there with its tracks spinning, throwing
dirt out behind, the engine lower and louder, until you back off or raise the blade. Pushing a growing heap it slows
steadily to a crawl instead of stop, go, stop. Every machine pulls away with its nose up, rocks when it stops, eases
into a turn, brakes for a bank or a step it cannot climb, and thumps down if it drops off an edge. Blades, arms,
buckets and the truck's tray ease in and out instead of snapping to speed.

**Guards** (one after another, after the last change to the machines; `-- --nosave` unless said)

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet / ground | 14/0, 20/0, 22/0 |
| `digsite_test` | 6/0 |
| `digsite_clod_test` / `digsite_clod_site_test` / `digsite_clod_perf` | 10/0 / 14/0 / 5/0 |
| save pair | 4/0, 6/0 |
| sync pair (enet) | host 6/0, guest 9/0 |
| `digsite_yard_test` phase 1, 2 | 6/0, 7/0: 12.29 m both runs (0.01% apart), frame p95 20.47 ms, mass exact |

**Known gaps and things later stages must know**

- **The dozer goes 16% less far in the yard's 20 s push** (12.29 m against 14.66 m). `baseline.txt` is still stage
  1's game; stage 5's "80% of stage 4's metres" is 9.83 m.
- **At a bank the blade bites 0.69 m in and stalls for good** until the driver backs off or raises it; the old one
  cut 1.6 m in before it jammed. Taking a thinner cut (blade higher) goes on. `BANK_MOST` is the knob.
- **What cannot be seen coming still stops it in a frame**: turning into a bank, backing into one faster than the
  look reaches, ground slumping in front. It is then a bump of whatever speed it had. As tested the most was 0.5 m/s.
- **The dozer looks no further than its blade when the blade is low** (ground over the edge is the blade's to cut):
  with the blade up it brakes for a bank as any machine does.
- **Sound was not listened to** (no audio here): the engine and clatter changes run without error, their levels are
  a guess to be judged by ear.
- **The guest's view**: its machines rock and slip from the host's 20 Hz state; a thud is seen from the height
  change. No guest-side prediction (out of scope). The sync pair passes; nobody looked at a guest's screen.
- The body's rock dips the blade's picture by up to 14 cm at the peak (the blade is on the body); the edge that cuts
  does not move.
- Camera shake and pull-back with speed are stage 9.

## Stage 5: dozer break-off and push

**What was built**

- `ds_dozer.gd`: of what the blade's front moves on ahead each step (the spill: the grid's `blade_sweep`, `moved` +
  `taken`), `CLOD_SHARE` 0.35 is owed to clods. Once a clod's worth is owed (`CLOD_FROM` 500 mm) it is taken out of the
  sweep as counts by material (`take_most`, 3000 mm a step at most, from each end of the edge in turn) and let go
  (`_break_off`) in pieces of 1000 mm through `DsDirt.spawn_mass`:
  - most at the heap's crest, 0.5 to 0.85 m ahead of the edge across the whole blade, with the blade's speed plus
    0.5 m/s on and 1.1 to 2.3 m/s up (rolled up and over, to tumble down the heap's front);
  - the rest off the blade's two ends, 0.3 m outside, going out at 0.9 to 2.0 m/s: 12% of the clods with the heap
    ahead empty, up to 40% with it brim full (`full`, stage 4's), so the windrows grow as the blade fills.
  The grid's heap keeps the other 65%, as tested before. No native change: `take_most` and `counts` were already bound.
- `push_load` (what weighs on the dozer and shows as "pushing N t") adds the clods' mm in a box ahead of the blade:
  blade wide, 1.6 m ahead of the edge, as high as the heap is looked at; counted every third step.
- `ds_dirt.gd`: `mass_in(transform, half)`, the mm in the clods whose middles are in a box.
- The cosmetic `_tumble` particles: 12 instead of 40 where the wave is real clods (solo or host); a guest keeps 40,
  it sees no clods until stage 8.
- `test/voxel/digsite_dozer_clod_test.gd` (the stage's test) and `test/voxel/digsite_dozer_clod_clip.gd` (the clip).
- Tests that counted the ground alone now count the clods with it, because the last of them are still rolling when a
  push ends (they roll down the heap for the 6 s a clod has): `digsite_fleet_test` (`_ground()`),
  `digsite_yard_test` (the total, clods in it, is what must be the same: 767 mm were in clods at the end),
  `digsite_save_test` (phase 1 waits for the clods to be at rest before it writes what the site is like: 6.0 s after
  the dozer stopped). Without these three edits yard failed 1 and the save pair 1 and 2; not a mm was lost in
  either (the yard's drift was 0, and phase 2's ground was the whole of what there was before the push).

**Commands** (from the repository's root)

    /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_dozer_clod_test.gd -- --nosave
    xvfb-run -a /root/godot/godot --path godot --fixed-fps 30 --write-movie <dir>/clip.png -s res://test/voxel/digsite_dozer_clod_clip.gd -- --nosave
    xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_yard_shots.gd -- --nosave --out=res://integration/dirt_shots --tag=stage5

(64 s; 4 min; 60 s. The test does the yard's 20 s push twice in the one run, back to back: with the dozer's
`clod_share` 0, which is stage 4's blade and the baseline, then with the clods. `--order=ba` does them the other way
round. It writes `integration/dirt_shots/dozer_clod.txt`.)

**`digsite_dozer_clod_test`: `DSDOZCLOD done 16 passed, 0 failed`** (three runs: baseline first, clods first, and the
committed one; the numbers below are baseline first / clods first)

| Criterion | Baseline (share 0, same run) | Measured |
|---|---|---|
| the baseline is stage 4's push | 12.29 m (stage 4: 12.29) | |
| mass exact every second, at the end, and after `land_all` | 0 mm | 0 mm; 0 mm left in clods |
| the clods are 35% of the spill | | 34.9% / 35.0% (237085 of 678380 mm) |
| clods spawned > 200 | 0 | 499 / 507 |
| peak awake <= `FLY_MAX` 800 | 0 | 210 / 213; none put down by the caps |
| heap ahead >= 0.3 m and >= 80% of the baseline's | 1.22 m | 1.23 / 1.21 m: 101% / 100% |
| windrow > 0 mm in the columns 0.5 to 1.5 m outside each blade end | 39577 and 53191 mm (212 and 270 columns) | 63991 and 75408 mm (438 and 585 columns) / 70661 and 71666 |
| metres >= 80% of stage 4's (9.83 m) | 12.29 m | 12.52 / 12.64 m: 102% / 103% |
| `step_us` mean <= 2.0 ms | | 0.26 / 0.27 ms (p95 0.75 / 0.77, worst 2.2 / 4.2) |
| frame p95 <= baseline + 3.0 ms | 16.93 / 17.27 ms | 18.46 / 18.52 ms: +1.53 / +1.25 (means +1.05 / +0.99) |
| `layer_us + show_us` within 20% of the baseline's | mean 518 / 526 us | 539 / 542 us: +4% / +3% |
| added: the dozer standing, the clods come to rest and are gone | | 1.03 / 1.08 s |

The frame's extra 1.0 ms mean is more than the clods' own step (0.26 ms): the rest is drawing them and the machines'
boxes handed over each step. The clod run is not the same to the digit in the two orders (499 or 507 clods): the
clods' random numbers carry on from the run before. Each order by itself repeats.

At `--fixed-fps 30` the same test is 15 passed, 1 failed, and the failure is the baseline's own check: stage 4's
push goes 12.19 m at 30 frames a second, not 12.29 (nothing to do with clods). With clods there: 513 let go, 34.9%,
197 awake at the most, mass exact.

**Clip and shots** (`integration/dirt_shots/`, looked at): `dozer_clods.mp4` (10 s, 30 fps, 960 x 540: 5 s from in
front of the blade, 5 s from behind and above), stills from it `dozer_clods_1_front.png` and
`dozer_clods_2_behind.png`, and the yard's four again as `stage5_1_start.png` to `stage5_4_side.png`. Seen: lumps
coming up over the crest and rolling down the heap's front, lumps going off both ends of the blade and lying beside
the cut, one or two thrown a couple of metres onto the grass. No lump seen through the blade's face or the bonnet,
none hanging in the air. The clods are a darker brown than the lumpy skin on the heap they land in, so the moment one
melts in is a small change of shade as well as of shape; at a few frames a second here that could not be judged as
motion. Checked frame by frame only in stills.

**What the owner will see**: push with the bulldozer and the top of its wave is loose lumps: they come up the blade,
tip over the crest, bounce and roll down the front of the heap, and pour off both ends of the blade to lie in rows
beside the cut, more of them the fuller the blade. The rows beside the cut are about half as big again as before.
The dozer goes as far as it did (12.5 m against 12.3 in 20 s). Stop, and the lumps settle into the heap within a
second or so (stragglers on a steep flank within 6 s).

**Guards** (one after another; `-- --nosave` unless said)

| Test | Result |
|---|---|
| dirt / tools / dynamite / support / cave / tunnel / walkin | 12/0, 15/0, 12/0, 13/0, 9/0, 7/0, 2/0 |
| dingo / fleet / ground | 14/0, 20/0, 22/0 |
| `digsite_test` | 6/0 |
| `digsite_clod_test` / `digsite_clod_site_test` / `digsite_clod_perf` | 10/0 / 14/0 / 5/0 |
| `digsite_feel_test` | 22/0: (d) 12.52 m, frame p95 19.07 ms against the committed 20.98 |
| save pair | 4/0, 6/0 (after the edit above; before it 3/1 and 4/2) |
| sync pair (enet) | host 6/0, guest 9/0 |
| `digsite_yard_test` phase 1, 2 | 6/0, 7/0 (after the edit above; before it 5/1 and 6/1): 12.52 m both runs, frame p95 17.21 and 17.40 ms, mass exact |

**Known gaps and things later stages must know**

- **A guest sees no clods** (stage 8): it sees the host's heap and windrows grow through the grid as before, with the
  old particles. The windrows a guest sees are the real ones (the clods' deposits).
- **The timed save while playing** (`DsSave.save` every 60 s) does not land the clods first; leaving and quitting
  do. A crash between would lose what was in the air at that save (hundreds of mm). Stage 8's.
- **The "Blade -0.NN m" readout flickers** while pushing a heap (-0.02 to -0.9 from frame to frame, seen in the
  clip). It is not from this stage: with the share 0 it has as many such frames (381 of 1201 under -0.1 m against
  401). It reads the ground under the edge before the sweep clears it. Worth a fix in stage 9.
- **The share is of the blade's front spill, not of everything the blade moves**: 6.1% of all the mm it shifted (most
  of that is the sweep clearing behind the edge, the same dirt many times over).
- **Clods on a steep heap flank keep rolling slowly** until their 6 s is up (34 of 177 after a 5 s push in the save
  test). It reads as the heap trickling; if it reads as jitter, `STUCK_S` is the knob.
- `feel.txt` was re-written by the guard run (this stage's game: 12.52 m). `feel_base.txt` is still stage 3's.
- The clod's shade against the skin, and popping at settle, need judging at full frame rate on a real GPU.
