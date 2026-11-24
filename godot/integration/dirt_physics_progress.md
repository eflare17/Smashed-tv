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
