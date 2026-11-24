# Dig Site: physical dirt plan

Branch `claude/digsite-dirt-physics`. Scope: `godot/scripts/voxel/digsite/` and `godot/test/voxel/` only.
Never touched: `Smashed.html`, `html-version-b331`, `emu/`.

Status: stages 1 to 4 built (see `dirt_physics_progress.md`); the rest is plan. Facts marked "checked" were read in the code while writing this;
every timing is a target to be measured in stage 1 and 2, not a measurement.

## What we're building

Today the Dig Site moves dirt by teleporting 12.5 cm blocks around a grid, and the lumps you see are decoration that
collides with nothing. The machines stop dead with a text message when they meet resistance.

We are changing two things.

1. **Dirt that breaks off becomes real lumps.** Whatever a blade, bucket, shovel or blast knocks loose turns into
   clods that fall, bounce, roll down heaps, get shoved along by the blade, spill off its ends, and pour from a
   bucket into the truck (or miss it). When a clod comes to rest it melts back into the ground, so the ground can
   hold any amount of dirt at no cost; only the few hundred lumps actually moving are simulated.
2. **Machines get weight.** No more instant stops: a loaded dozer lugs down, its tracks slip, its nose dips, the
   engine labours, and hydraulics ease in and out.

It is the same trick as the St Kilda bricks (fly, land, become part of a static pile), with rolling, machine
collisions and the Dig Site's own ground added. It works in co-op (the host owns the dirt) and nothing is lost on save.

## Decisions and why

- **Winner: "debris-first"** (both judges). GDScript on the existing native API, so the committed Windows DLL stays
  valid. The native library cannot be rebuilt in this sandbox as it stands: no godot-cpp checkout, no mingw; `scons`
  is downloadable by pip (checked), mingw is unconfirmed. A native speed-up is an optional late stage behind a spike.
- **The grid is the only sleeper.** Resting clods are deposited and deleted. No wake list: a blade or blast re-cuts
  the ground through the normal break-off path.
- **No clod-against-clod contacts in GDScript.** Body comes from a cheap per-cell "awake heap" floor raise.
- **Dozer starts at a 35% clod share** of blade spill (crest and blade ends); the tested grid heap keeps the rest.
  The judges disagreed here (100% vs 30-40%); the share is one constant, raised in stage 9 only if mass and frame
  numbers allow.
- **Machine feel comes early** (stage 4): it is independent of clods and the quickest cure for "clunky".

## Facts checked in the code

| Fact | Where | Consequence |
|---|---|---|
| `grid.height_at` returns **cell units** and includes the mm layer; `terrain.height_at(x, z)` wraps it into world metres | `dig_site_layer.cpp:371`, `ds_terrain.gd:158` | Clods use `terrain.height_at`; no new surface query |
| `put_layer(x, z, mm, m)` is bound and always lands everything | `dig_site_layer.cpp:405`, `dig_site_grid.cpp:509` | Exact-mass deposits are possible |
| `lay_put` clamps edge (`LRIM`) columns inward; a full column overflows to its lowest neighbour | `dig_site_layer.cpp:178-227` | No edge fallback needed |
| `put_layer` **and `pour_at`** both work from the column's top (`height_mm`) | `dig_site_layer.cpp:33`, `dig_site_blade.cpp:272` | Neither can deposit under a roof. A clod settling in a tunnel must use `fill_sphere` (whole cells) at its own position; see "Tunnels" |
| `drop_column` returns fewer than asked when the column hits the roof | `dig_site_dirt.cpp:222` | Any use must check the return |
| `blade_sweep(..., take_most, heap, share)` is bound; ops `dig/fill/drop/cut/pour` are registered in `hook` | `dig_site_grid.cpp:472`, `ds_terrain.gd:194-199` | Host can call `put_layer` directly; the existing `ch` diff carries it. No new net op |
| Hard stops live at `ds_machine.gd:500`, `ds_dozer.gd:224/228/245`, `ds_dingo.gd:339` | grep | Stage 4's edit list |
| `keepout_boxes()` returns `[[Transform3D, half_extents]]` | `ds_dozer.gd:141` | Collider format for clods |
| `digsite_dingo_test`, `digsite_fleet_test`, `digsite_ground_test` do not load (`:=` on untyped members) | harness map | Repaired in stage 1 |
| `digsite_test` already fails 1 of 6 ("Travel Home") | harness map | Recorded as known, not a regression |

Not checked: the dozer's machine id (tests must find it by type), mingw availability, any timing.

## Technical model

### Files

- New `scripts/voxel/digsite/ds_dirt.gd` (class `DsDirt`): the clod simulation and its drawing. Ported from the brick
  tier of `scripts/voxel/stkilda/voxel_breakables.gd` (struct-of-arrays, one `RenderingServer.multimesh_set_buffer`).
- `ds_clods.gd` (shader lumps on resting dirt) stays as the cosmetic skin; it hides the settle.
- Tests in `test/voxel/`, shared helper `test/voxel/digsite_yard.gd`.

### A clod

Struct-of-arrays: position, velocity, spin, basis, material (5 bits), `mm` (mass in column-mm; one cell = 125),
radius, age, rest timer, 16-bit id. Swap-remove on delete (no slot leak).

| Size | Edge | Carries | Used by |
|---|---|---|---|
| Crumb | 12 cm | 125 mm | hand tools, bucket lip |
| Clod | 20 cm | 500 mm | default: blade, pour |
| Chunk | 35 cm | 2000 mm | blast, rock, cave-in |

Spawns bias to the middle size. Under load (>20% / >50% of the cap) spawns merge 2x / 3x, as bricks do.
Remainders below 125 mm never become a clod: they go straight to `put_layer`.

### Step (host or solo only, fixed 60 Hz, seeded integer RNG, id-ordered)

1. Semi-implicit Euler, gravity 9.8.
2. **Ground**: `terrain.height_at` every frame within 0.5 m of the ground, every other frame above. Normal from two
   extra samples, cached per 0.25 m cell for the frame.
3. **Bounce** when normal speed < -2 m/s (restitution 0.25); otherwise **roll**: tangential gravity minus friction
   0.7, spin = v / r.
4. **Awake heap**: a 0.25 m hash counts awake clods per cell and raises the local floor by `count * r`, so a stream
   piles before it settles. *As built in stage 2*: the raise is capped (`HEAP_FULL`, 1500 mm in a square); a clod
   coming down on a full square settles there and then. Uncapped, a stream stood metres of floor under itself and
   threw clods 9 m away (progress log, stage 2).
5. **Machines**: oriented boxes from `keepout_boxes()`, one body box per machine, and the truck tray (floor + 4
   walls, new `tray_boxes()`). Broadphase: only clods within a machine's bounding radius are tested. Push out along
   least penetration, take the box's point velocity. Clods above 0.6 of blade height get a sideways push toward the
   nearer blade end (windrows). *As built in stage 3*: the broadphase is a bit a box in each 1 m square it is over;
   a clod is put out by the face it came in at (where it and the box were a step ago), not by least penetration,
   unless it was inside then too; it loses 30% a step of its speed across the face. At a blade's face clods stack
   (each on those counted before it in its square, to 1.25 m), which is what gets them over 0.6 of its height.
6. **Settle** when speed < 0.4 m/s for 0.25 s **and** slope < 30 degrees, or age > 6 s, or overflow. Never while
   inside a blade or bucket box (avoids a settle/re-cut flicker). *As built in stage 2*: also when slow for 1 s
   whatever the slope (`STUCK_S`), so a clod on a 30 to 35 degree flank does not wait out its 6 s.
7. **Deposit**: summed per column, flushed once a frame with `grid.put_layer`, at most 200 clods a frame. The clod
   shrinks to zero over 0.15 s. *As built in stage 2*: spread evenly over 2 x 2, 4 x 4 or 6 x 6 columns by the clod's
   size, not bilinearly over 4 (a chunk's 2000 mm on four columns is a 500 mm spike), and a clod waits a step if its
   middle column has had 36 mm that step (`DEP_COL`).
8. **Budget**: `CLOD_US` cap (target 2000). When over, force-deposit the slowest, then the oldest (*as built*:
   clods on the ground first, then the front of the list; sorting costs more than it saves).
   Cap `FLY_MAX` is set from the stage 2 measurement: **800** (expected 800-1000 here, not the 1500 first proposed).

### Tunnels

A clod is "under a roof" when `grid.get_cell` above it is solid below the column top. It deposits with
`grid.fill_sphere(pos, r, m, cells, true)` in whole cells and checks the return. Leftover mm (sub-cell, or cells
that did not fit) go into a per-material `_owed` counter that tops up the next underground deposit and is flushed to
the surface by `land_all()`. `_owed` counts in the mass invariant.
*As built in stage 3*: under a roof a clod also moves by the cells (floor, walls, roof), since the surface there is
the hill over it; only a clod already in a hole treats a solid cell as a wall (one buried by a rising heap pops up, as
in stage 2). `land_all()` tries a wider ball before the surface. Owed measured 0 mm in stage 3's test.

### Mass invariant (asserted in every stage's test)

`grid.ground_mm() + dirt.mass_mm() + dirt.owed_mm() + buckets + trays + backpacks + shovel carry` is constant,
exact to the mm.

### Co-op and save

- Host simulates and deposits; deposits reach guests through the existing `ch` diff. Guests' tool ops spawn nothing real.
- Machine-touched clods: `net.send_fast` on a free id, 12 Hz, nearest clods first, split into packets under the
  existing part size: u16 id, position quantised to 2 cm, material + size byte. Guests interpolate; an id absent for
  0.5 s is removed.
- Blast clods (touch no machine): one reliable `net.event("clods", seed, origin, n, vel)`; guests run cosmetic,
  massless clods from the same seed. This is also the fallback for everything if streaming costs too much.
- `dirt.land_all()` deposits every clod on save, on leaving, and on host change. No save format change.

### Budgets (this 4-core box, headless, `--fixed-fps 60`, CPU only)

| Number | Target |
|---|---|
| `dirt.step_us` at the cap | mean <= 2.0 ms, p95 <= 4.0 ms |
| Whole frame while dozing | p95 <= stage 1 baseline p95 + 3.0 ms, and <= 12 ms |
| `terrain.layer_us + show_us` | within 20% of stage 1 baseline |
| All clods at rest | `step_us` <= 0.05 ms |

A gaming PC is several times faster than this box; the box numbers are the gate.

### Standing rules for every stage

- Run headless: `/root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/<name>.gd -- --nosave`.
  Exit codes are always 0: read the `... done N passed, M failed` line.
- **Regression set must stay as it is at the end of stage 1**: dirt 12/0, tools 15/0, dynamite 12/0, support 13/0,
  cave 9/0, tunnel 7/0, walkin 2/0, plus dingo, fleet and ground once repaired, and `digsite_test` no worse than
  5 passed 1 failed. The save pair (`--save=<path> --phase=1` then `--phase=2`) and the sync pair
  (`--host=CODE` / `--join=CODE`) are run from stage 1 on and recorded.
- No native change without both the `.so` and the `.dll` rebuilt, and every new native call gated by `has_method`.
- Each stage ends with the yard shots re-taken for a before/after pair.

## Stages

### Stage 1: test yard and baseline

- **Goal**: numbers and pictures of today's game, so every later stage is judged against them.
- **Files**: add `test/voxel/digsite_yard.gd` (helper: boot arena, travel to the Dig Site, level a 24 x 24 m patch,
  find the dozer by type, park it at the patch edge, drive it by script, frame timer, mass sum);
  add `test/voxel/digsite_yard_test.gd`; add `test/voxel/digsite_yard_shots.gd`;
  repair `digsite_dingo_test.gd`, `digsite_fleet_test.gd`, `digsite_ground_test.gd` (`var g = ...` for untyped members).
  No game code changes.
- **Test**: `test/voxel/digsite_yard_test.gd`. Drives the dozer 20 s, blade down, straight across the patch. Prints
  `DSYARD frames, mean, p95, worst ms; layer_us, show_us mean and p95; metres moved; heap height ahead; ground_mm
  before/after` and writes them to `integration/voxel_shots/dirt/baseline.txt`.
  Pass: patch flat to +-1 cell before the run; dozer moves >= 10 m; `ground_mm` + blade/bucket load identical before
  and after (0 mm drift); two runs give the same `ground_mm` and metres moved within 1%; frame p95 recorded
  (no limit yet); the three repaired tests load and print a `done` line.
- **Shots**: `xvfb-run -a /root/godot/godot --path godot -s res://test/voxel/digsite_yard_shots.gd -- --out=<dir>`
  saves 4 PNGs (start, mid-push, heap, side view). Pass: 4 files, each non-blank (> 20 kB).
- **Owner sees**: nothing in the game; four "before" pictures and a baseline table.
- **Out of scope**: any clod code, any tuning, any machine change.

### Stage 2: clod core spike on a bare grid (the riskiest question)

- **Goal**: answer "what does one clod cost in GDScript against this grid?" and fix `FLY_MAX` from the answer.
  Second, time-boxed question: can the native library be rebuilt here for Linux **and** Windows?
- **Files**: add `scripts/voxel/digsite/ds_dirt.gd` (spawn, fall, bounce, roll, awake heap, settle, bilinear
  batched deposit, usec cap, `mass_mm`, `land_all`; no drawing, no machines); add `test/voxel/digsite_clod_test.gd`,
  `test/voxel/digsite_clod_perf.gd`. Bare `DigSiteGrid` 128x96x128 as `digsite_dirt_test` uses, no arena.
- **Tests**:
  - `digsite_clod_test.gd`: drop 1000 clods from 3 m onto one spot. Pass: all deposited within 8 s; mass exact to
    the mm; pile slope 28-38 degrees after slump; no single column more than 250 mm above its neighbours at any
    tick; a clod released on a 40 degree heap travels > 1 m downhill before settling; two runs give identical
    `section_hashes`.
  - `digsite_clod_perf.gd`: hold 400, 800, 1200, 1500 awake for 10 s each. Prints us per clod and `step_us`
    mean/p95. Pass: `FLY_MAX` set to the largest count with mean <= 2.0 ms and p95 <= 4.0 ms; the usec cap holds
    p95 <= 4.0 ms at 2x that count by force-depositing; mass exact.
    *As tested*: each count is held three times and fits only if all three do; the check is that `FLY_MAX` (800)
    fits every time. A larger count fitting on a good minute (1200 does, about one run in five) is printed as a
    note, not failed: the constant stays where it always fits.
- **Fallback ladder** if 800 awake does not fit: ground check every third frame for airborne clods; drop the awake
  heap; `FLY_MAX` 500 with 2x coarser spawns. If 500 does not fit, stop and report before stage 3.
- **Native probe (max half a day, outside the work tree)**: pip scons, clone godot-cpp 4.4, build Linux, try mingw.
  Pass to unlock stage 9's native part: unmodified sources rebuild to a `.so` that passes `digsite_dirt_test` 12/0
  **and** a `.dll` is produced. Otherwise the plan stays GDScript-only; record the result in this file.
  **Result (24 Nov): passed.** `scons` and `x86_64-w64-mingw32-g++` (13-win32) are on this box; godot-cpp 4.4
  (`b0e3b1e`) built for Linux and Windows (`template_release`), and `native/build.sh` on a copy of the unmodified
  sources gave a `.so` that passes `digsite_dirt_test` 12/0 (and `digsite_clod_test` 10/0) and a 1.56 MB PE32+ `.dll`.
  Stage 9's native part is unlocked; the committed binaries were not replaced. Details in the progress log.
- **Owner sees**: nothing in the game; a per-clod cost table and the chosen cap.
- **Out of scope**: drawing, machines, break-off, net, native code changes.

### Stage 3: clods in the site (draw, colliders, tunnels)

- **Goal**: clods exist in the real Dig Site, are drawn, collide with machine boxes and settle correctly under roofs.
- **Files**: `ds_dirt.gd` (MultiMesh draw, shrink on settle, box colliders with broadphase, blade roll-over rule,
  tunnel deposit and `_owed`); `dig_site.gd` (create and step `DsDirt` on host/solo); `ds_machine.gd` (body box);
  `ds_truck.gd` (`tray_boxes()`); a debug spawn (`dirt.spawn(p, v, m, mm, seed)`) for tests.
  Add `test/voxel/digsite_clod_site_test.gd`.
- **Test**: in the yard. (a) 500 clods poured in front of a scripted moving box for 5 s: none end inside the box,
  mean travel >= 3 m. (b) 300 dropped into the parked truck's tray boxes: >= 95% rest inside, 0 pass through the
  floor. (c) 100 spawned inside a dug tunnel: after settling, the surface columns above gained 0 mm and the mass
  sum is exact. (d) `land_all()` leaves 0 clods. Budgets: `step_us` mean <= 2.0 ms, p95 <= 4.0 ms; frame p95 <=
  baseline + 3.0 ms; mass exact.
  *As tested*: the frame baseline is taken in the same run: the run replayed with no clods, each clod's dirt laid
  where and when it settled (stricter than stage 1's dozing p95, which the test is 8 ms under). Time cap off.
- **Owner sees**: with a debug key (K, on foot), lumps that fall, roll, bounce off machines and melt into the ground.
- **Out of scope**: tools creating clods, absorbing into buckets/trays, co-op.

### Stage 4: machine weight

- **Goal**: remove the clunk from driving, independent of clods.
- **Files**: `ds_machine.gd` (`_drive`: drive force vs resistance over mass, track slip, yaw inertia eased ~4/s,
  pitch spring from acceleration and load at 2-4 degrees, landing thud); `ds_dozer.gd`, `ds_dingo.gd`,
  `ds_bobcat.gd` (hard stops replaced, eased actuators like the excavator's `ARM_EASE`); `ds_truck.gd`;
  `ds_sfx.gd` (engine pitch from throttle, lug from resistance/drive; slip clatter).
  Add `test/voxel/digsite_feel_test.gd`.
- **Test**: yard. Dozer at full throttle into a 1.5 m bank built by the test. Pass: speed falls from > 2 m/s to
  < 0.3 m/s over > 0.3 s; no frame-to-frame speed drop > 25% of top speed; slip > 0.5 while stalled; yaw rate
  changes by <= `turn_rate * dt * 6` a frame; peak pitch between 1.5 and 5 degrees; on the flat, top speed within
  10% of stage 1's and the 20 s push moves >= 80% of the baseline metres. Frame p95 <= baseline + 0.5 ms; mass exact.
  *As built and tested* (`digsite_feel_test.gd`, 22 checks): speed is measured from where the dozer is each frame, not
  only from what it says. The frame baseline is the same test run on stage 3's game the same hour (`--write-base`,
  four pairs back to back). Added: a drop from 1 m (the thud) and the Bobcat at the same bank (the hard stop every
  machine had). The pitch checked is the body's rock on its tracks (`sway`: its look only, the blade doesn't feel it).
  The dozer is held at a bank by the firm face ahead of its edge (`BANK_*`), not by "the blade's full": a full blade
  in the open lugs and creeps (it spills off its ends), and only what it cannot move at all (a jam) stalls it.
- **Owner sees**: the dozer leans into a load, tracks spin and throw dust, the engine labours, the blade and arms
  ease instead of snapping; no more instant stop on "blade's full".
- **Out of scope**: camera, key remapping, gamepad, guest-side prediction.

### Stage 5: dozer break-off and push

- **Goal**: the dozer's wave of dirt is made of real clods.
- **Files**: `ds_dozer.gd` (`_tool`: `CLOD_SHARE` 0.35 of the spill taken as counts via `take_most` and spawned at
  the crest and both blade ends with blade velocity plus roll-up; `_tumble` particles reduced; `push_load` adds
  clod mm in a box ahead of the blade); `ds_dirt.gd` (`mass_in(box)`).
  Add `test/voxel/digsite_dozer_clod_test.gd`.
- **Test**: yard, same 20 s push as stage 1. Pass: mass exact every second and at the end; clods spawned > 200;
  peak awake <= `FLY_MAX`; heap ahead >= 0.3 m and >= 80% of baseline heap height; windrow > 0 mm in the columns
  0.5-1.5 m outside each blade end; metres moved >= 80% of stage 4's; `step_us` mean <= 2.0 ms; frame p95 <=
  baseline + 3.0 ms; `layer_us + show_us` within 20% of baseline. Fleet test still passes.
- **Shots**: yard shots plus an `xvfb-run` clip (`--write-movie`, 30 fps, 10 s) checked by eye for clods overlapping
  on the blade face and popping at settle.
- **Owner sees**: dirt rolling up the blade, tumbling over and off the ends into windrows.
- **Out of scope**: buckets, truck, share above 35%.

### Stage 6: buckets, pouring and the truck

- **Goal**: a pour is a stream of clods that can miss.
- **Files**: `ds_machine.gd` (`let_go` emits clods from the lip at a rate set by curl, <= 40 a frame, replacing
  the timer and `_land_falling`); `ds_dingo.gd`, `ds_bobcat.gd`, `ds_excavator.gd` (overflow and 10% lip tear
  become clods; clods **at rest** inside the bucket box are absorbed into `bucket{}` while there is room);
  `ds_truck.gd` (clods at rest inside the tray boxes and below the rim go to `tray_load`; tipping emits clods).
  Add `test/voxel/digsite_pour_test.gd`.
- **Test**: yard, dingo with a full scripted bucket. (a) Pour centred over the tray: `tray_load` gains >= 85% of
  the poured mm, the rest is on the ground. (b) Pour offset 2 m: tray gains 0. (c) Truck tips: >= 95% of
  `tray_load` is on the ground behind it within 10 s. Mass exact in all three; `step_us` mean <= 2.0 ms; frame
  p95 <= baseline + 3.0 ms. Dingo test still passes.
- **Owner sees**: dirt pouring out of the bucket, rattling into the tray, spilling over the side if badly aimed.
- **Out of scope**: clods stacking as a visible volume inside the tray (the tray level is still the counted load).

### Stage 7: blasts, hand tools and cave-ins

- **Goal**: every other source of loose dirt uses the same clods.
- **Files**: `ds_blasts.gd` (counts go to `dirt.spawn`; own ballistics and `_dump_spread` removed; `busy()`
  includes awake blast clods); `ds_tools.gd` (10-20% of a cut thrown back as crumbs, taken from the carry
  remainder; the rest to the backpack as now); cave events (`take_cave_events` -> small `dig_sphere` on flagged
  roof cells, <= 200 cells an event, spawned as chunks; the rest stays the grid's LOOSE fall).
  Extend `digsite_dynamite_test.gd`, `digsite_tools_test.gd`, `digsite_cave_test.gd`; add
  `test/voxel/digsite_blast_clod_test.gd`.
- **Test**: one stick on the yard. Pass: mass exact after `land_all()`; >= 90% of blast mm lands within 3x the
  blast radius; peak awake <= `FLY_MAX` (coarsening works); `step_us` p95 <= 4.0 ms; worst frame during the blast
  <= baseline worst + 8 ms. Dynamite 12/0, tools 15/0, cave 9/0, tunnel 7/0 unchanged.
- **Owner sees**: blasts throw chunks that bounce and roll; a shovel flicks crumbs; a cave-in drops lumps.
- **Out of scope**: detaching whole connected slabs of a bank (needs native code).

### Stage 8: co-op and save

- **Goal**: guests see the same lumps; nothing is lost on save or host change.
- **Files**: `ds_dirt.gd` (pack/unpack batch, guest interpolation, cosmetic seeded clods for blasts); `ds_net.gd`
  (fast id and `clods` event registered); `ds_save.gd` and the leave/host-change path (`land_all()` first).
  Extend `digsite_sync_test.gd`, `digsite_save_test.gd`.
- **Test**: (a) host/join pair with `--lag=150 --loss=10`, host dozes 20 s: guest clod count within 15% of the
  host's, sampled each second after the first; guest spawns 0 mass clods; section hashes equal within 4 s of the
  last clod settling; clod traffic <= 6 kB/s. (b) Save pair with >= 100 clods airborne at save: `ground_mm` +
  loads identical after reload. Host `step_us` and frame budgets as stage 5.
- **Owner sees**: a friend watching the dozer sees the same wave of dirt; quitting mid-pour loses nothing.
- **Out of scope**: guest-side prediction of driving; saving bucket and tray loads (unchanged from today).

### Stage 9: polish, perf sweep, optional native batch

- **Goal**: finish the feel and spend any spare budget.
- **Files**: `ds_machines.gd` (camera: +8% distance at full speed, 2-3 cm shake from slip and thud);
  `ds_sfx.gd` (clod impact ticks); `ds_dozer.gd` (`CLOD_SHARE` raised stepwise to at most 1.0);
  add `test/voxel/digsite_dirt_sweep.gd`. Only if stage 2's probe passed: native `height_many` / `put_many` in
  `native/src/`, both binaries rebuilt, calls gated by `has_method`.
- **Test**: `digsite_dirt_sweep.gd`: 60 s scripted session (push, scoop, pour into truck, one blast) at the cap.
  Pass: whole-frame p95 <= 12 ms and <= baseline + 3.0 ms; `step_us` mean <= 2.0 ms; mass exact;
  `CLOD_SHARE` is the highest value at which stage 5's test still passes. Full regression set as at stage 1.
  If native: `digsite_dirt_test` 12/0 on the new `.so`, and the game still runs with the old binaries swapped back.
- **Owner sees**: the camera breathes with the machine, clods tick as they land, more of the pushed dirt is real.
- **Out of scope**: clod-against-clod contacts, slab detach, gamepad and key remapping.

## Open risks

1. **GDScript cost per clod is unknown.** Both judges expect 3-6 ms at 1500 on this box. Stage 2 decides the cap;
   "thousands" means settled dirt in the grid, with hundreds awake.
2. **No real stacking.** Clods on the blade face and in the tray will overlap; the awake heap only helps vertically.
   Only a screen check (stage 5 clip) can judge this, and this box renders in software.
3. **Tunnel deposits are whole cells.** Sub-cell remainders wait in `_owed` and surface at `land_all()`; small, but
   it is dirt appearing above ground. Stage 3 measures how much.
4. **Settle pop** for the 35 cm chunk (2000 mm into four columns). Mitigated by shrink and the shader lumps; unproven.
5. **Dozer behaviour changes twice** (traction in stage 4, break-off in stage 5); the fleet test is the guard.
6. **Guest view is approximate.** Streamed clods near a lerped 20 Hz machine can clip the blade on the guest.
7. **Native rebuild may never be possible here**, and a DLL built here cannot be run here. The plan does not depend on it.
8. **Pre-existing failure** in `digsite_test` ("Travel Home") is carried, not fixed, by this work.
