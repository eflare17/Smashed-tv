# Earthmover: overnight plan

The owner, 4 Nov 2026, going to bed: "look pretty good 2 me so far, i need to go 2 bed, can you set up a over night plan?"

Everything goes in `earthmover-godot/`. This file is kept up to date through the night.

## The plan, in order

1. **Finish the look test.** Fix what the screenshots show: the cab view (the hood fills the screen), thin green lines
   where soil meets packed ground, faint ripples on the ground, and the seam where the grass ends.
2. **Put the look test on the phone.** Export the APK and copy it to `G:\My Drive\EarthmoverLook.apk`, as with St Kilda.
3. **Step 1, the dirt sandbox.** Tap to drop or remove dirt and watch it slump. The soil total stays on screen, and a test
   fails if any soil is ever lost or created.
4. **Step 2, the bulldozer.** Drive it and push dirt, with resistance from the pile, on keyboard and phone controls. This
   is the test of whether the game feels good.
5. **Stop there and write the morning summary.** Step 3 onwards waits, because the agreed rule is that each step gets
   tried on the phone first.

## Limits for tonight

- **No installs.** This PC has no C++ compiler, and installing one means downloads the owner should OK first. So tonight's
  simulation is GDScript, kept separate from the game so it can move to C++ later. It may be too slow to judge the final
  grid size, and any such limit gets written down here.
- **No game design decisions.** The goal, setting, driver, tunnels and snow stay open. Where something is needed, it gets a
  plain placeholder listed below.
- **No commits, pushes or publishing.** Nothing goes on the website. The only thing that leaves this PC is the APK going to
  the owner's own Google Drive.
- **Hands off other work.** No changes to Smashed, the dino game, or other sessions' Godot windows.
- **Stuck or failing:** write down what happened and move on. Never call something working unless it was checked.

## Waiting for the owner

- Try the look test on the S25: are the ink, colours and grass right, and what FPS does it show?
- OK to install a C++ compiler and Android NDK (needed for the real, faster simulation)?
- Still open: the game's goal, setting and driver, no tunnels, snow, and grass growing back.

## Placeholders chosen tonight

All of these are first guesses, easy to change:

- The player starts the Dirt mode with 150 m3 of soil in hand.
- The bulldozer's numbers in `scripts/dozer.gd`: 20 t, top speed 11.5 km/h, blade lift range, how hard soil drags.
- Tracks sink into loose soil and grip about half as well on it. Added because otherwise it drove straight over the pile.
- Tracks wear the grass bare where they drive.
- A lowered blade can dig itself in until the machine stalls. It's raised to get free.
- The app opens in Drive mode, and its icon is Godot's default.

## Progress: finished 4 Nov 2026, about 11:10 pm

Done, in the order planned, then stopped as agreed. Nothing committed, pushed or published.

**On Google Drive:** `Earthmover.apk` (try this one, it includes the look test as Look mode) and `EarthmoverLook.apk` (the
earlier look test alone). They install side by side.

**On the PC:** `Play Earthmover.bat` in the repo folder. W A S D drive, Q and E lower and raise the blade, right drag looks.

What's in it:

- **Look:** toon light, ink lines, flat-shaded dozer and pines, painted sky, grass that hides itself using the dirt grid.
- **Dirt:** hold a finger on the ground to drop or remove soil. It falls as chunks, slumps to about 34 degrees, buries the
  grass, and steep firm walls collapse. Rock doesn't give way.
- **Drive:** the left thumb is a stick, RAISE and LOWER are on the right, the right side drags to look. The blade pushes
  soil. A load slows the machine, enough load stops it with TRACKS SLIPPING on screen, and raising the blade frees it.

Checked:

- `test/dirt_test.gd` and `test/drive_test.gd` both pass. The soil total stays exact at every tick through scooping,
  pouring, collapses and pushing.
- Simulated touches on the PC: the stick with a second finger on RAISE, the dirt tool, and the menu buttons all work.
- 120 FPS on the PC at 1600 x 900, in the phone's renderer. The dirt code took about 3 ms a tick at its busiest.

Not checked:

- **Nothing has run on the S25.** Its speed is unknown. The dirt code is GDScript, so expect it to cost several times more
  there. The readout shows FPS and "Dirt code" ms to report back.
- **Whether it feels good.** The tests show what it does, and only driving it can answer that. The bulldozer's numbers are
  the first thing to tune.
- **Real fingers on the phone.** The touch checks were simulated on the PC.

## Fix, 5 Nov 2026: "I couldn't seem 2 move it, it just changed camera angle"

The dozer started with its blade down, 6 m from the big pile and facing it. Full throttle stalled it after 4.6 m, and a light
push barely moved it, but steering still worked and the camera swung with it. The old test only asked for 1.5 m of movement.
Now it starts on open ground, 15 m of free run from the pile, with the blade raised 0.5 m, and a test checks the first push.
Also added: an always-visible DRIVE ring, a key list on PC, a big warning when it's stuck, and tracks that hold when not
driven (it used to roll down slopes). Two pines moved out of the way. The stall strength itself wasn't changed.
Still not known: which device the owner tried it on. It's still only been checked with simulated input.

Known rough edges: some faint shadow speckle remains on the steepest soil, and a few patches of ink scribble on sharp
folds. Grass stops at the patch's edge, 32 m from the middle. Soil doesn't compact or swell yet (that's step 4).

## Fix 2, 5 Nov 2026: "there is still no controls, it just moves the camera"

The exact cause on the S25 isn't proven: the phone isn't connected, and everything was checked with simulated input on the PC.
Changed so each likely cause can't happen: one finger anywhere drives and only a second finger looks; the controls rebuild if
the screen size changes after start (a portrait start test passes); a stuck stick finger clears itself; Look mode is gone from
the Mode button; GO and BACK buttons stay. The app is now "Dozer Drive" (com.eflare17.dozerdrive) with its own icon, so it can't
be mixed up with the two old apps. `G:\My Drive\DozerDrive.apk` is the one to use; the old APKs are in `G:\My Drive\old earthmover`.

## 5 Nov 2026: bug pass, trees, feel

S25 report from the owner's screenshot: 120 FPS at 2340 x 1080 on Adreno 830, dirt code 0.2 ms a tick when idle. Speed isn't a limit yet.

Bugs fixed: the grass past the grid read the grid, so soil on its edge smeared to the horizon (shader `outside` flag); the dozer kept "moving" against the area limit and heaped soil there (it now really stops, at +-26 m, with a fence and message); soil can't reach the outer 6 cells; Reset re-added input actions; mode changes left stale fingers; a saw-tooth on diagonal soil edges (the ground mesh smooths heights slightly, only checked in PC screenshots).

Added: 20 knockable trees (`scripts/trees.gd`), code-made sound (`scripts/sfx.gd`), dust, clods, exhaust, camera shake, vibration. Soil drag lowered from 0.62 to 0.5, and the "too much" warning waits 1.2 s.

Not checked: nobody has heard the sounds (only their levels were measured), and vibration and all of this feel on the S25 are untested.

## 5 Nov 2026: sinking into piles

Tracks sank in proportion to soil depth, so a machine on a 3 m pile went under by over a metre. Sink is now capped at 0.2 m, and the machine sits on a sharp crest. A new test checks both with and without LEVEL.
Known rough edge, not fixed: pushing with the blade down, the nose bobs about 5 degrees either way and leaves waves in the ground.

## 5 Nov 2026: LEVEL reworked

The owner wanted LEVEL to flatten down to the ground. It now holds the blade 1 cm above the firm ground ahead of it, following it wherever it goes, with soil drag at 15%. It only lifts when truly stuck. RAISE and LOWER set the height above the firm ground.
Measured over 8 runs across the big pile, never stopping: deepest soil where it stood 4.0 to 1.4 m, average 1.45 to 0.33 m. Three runs on one line leave about 0.3 m on that line, as the sides slump in. Soil is conserved, so it collects where it's pushed, including against the fence, where the blade can't reach all of it.

## 5 Nov 2026: tower ahead of the blade

Soil stacked as high as 9.75 m ahead of a fast blade, as slumping couldn't keep up. The blade now heaps soil to 1.1 m above its edge and lays the rest further ahead, then past its ends as windrows, in the same tick (`DirtSim._spill`). Same 8-run measure: tallest ahead of the blade 4.01 m (the pile's own height), then 1.3 to 2.7 m; deepest anywhere 1.67 m where the fence heap had reached 3.46 m; where the pile stood, average 0.41 m and deepest 1.67 m.
Spilled soil does jump up to a few metres in one tick. It looks fine in PC screenshots, but how it looks in motion is unchecked. The question of whether soil should thin out as it's pushed is still with the owner.

## 5 Nov 2026: soil spreading too wide

The owner found the spill unrealistically wide. Now the heap goes to 1.6 m above the edge and up to 3 m ahead; side ridges only go 0.7 m past the blade's ends and stand 0.9 m lower than the heap. Overflow still goes to the lowest place seen.
Measured on a 0.5 m strip as wide as the 4.3 m blade: spread 7.5-8 m before, 6.5-7 m now. Most of what's left is the ridges' natural slope. Eight runs on the big pile: tallest ahead 4.27 m on the first, then 1.7 to 2.6 m; where the pile stood, average 0.29 m and deepest 1.23 m; deepest anywhere 3.22 m, by the fence (it was 1.6 m with the wide spill).

## 5 Nov 2026: feel pass and the excavator

Owner agreed a 2-hour plan: dozer feel first, then an excavator. Code now shares `scripts/machine.gd` (driving, resting on the ground, ruts, body sway) and `scripts/track_rig.gd` (moving cleats and wheels).

Dozer: blade holds its height over 2.5 m of travel while working (`_steady_blade`). Measured with blade down: pitch was -2.9 to 4.5 degrees, now -0.8 to 1.4; ground left -0.14 to 0.28 m, now -0.08 to 0.10. Fine ripples remain (roughness 0.13 to 0.10 m per m). Not applied under LEVEL, which has its own control. Drive is now a speed control that eases on over about 1.7 s, with a floor so a timid push still walks. Body sways on accel, braking and turns. Tracks run separately and spin when stuck. Ruts in loose soil. Tumbling lumps on the blade. New sounds: track clatter, hydraulic whine, low soil rumble, steel clunk, soil pour.

Excavator (`scripts/excavator.gd`, test `test/dig_test.gd`): house swings, the player moves the bucket pin up/down/in/out and the boom and stick solve for it. The bucket holds 1.2 m3 in `DirtSim.held`, cuts only when dragged inward, curls itself while dragged, and pours real falling chunks as it tips. Firm ground is slower: half a bucket in 2.4 s, against one full bite of the pile in about 2.6 s. Rock stops the teeth. Starts at `GroundData.digger_spot()`, between the pile and pit. Machines are solid to each other, and the driven one stops at gap 0.

Controls: "Now:" button swaps machines. Excavator left thumb swings (button swaps it to drive), right thumb moves the arm, CURL and DUMP buttons. Chase view sits at the rear right in dig mode so the arm does not hide the bucket. All checked by simulated touch (`--demo=touchdig`, `--demo=touchswap`) on PC.

Not checked: nothing has run on the S25. Nobody has heard any sound or felt any vibration. All feel numbers are first guesses. Starting with the bucket fully open wastes soil, as it falls straight back out (moved_m3 counts it again).

## 5 Nov 2026: web version

Asked for by the owner, to share. Live folder is `dozer-drive/` on main, using the shared `godot-play` engine (its wasm is byte-identical to this export), so the game itself is a 136 KB pck. Page made from the Destruction Simulator loading page. Web mode needs `SUN_WEB` at half and `Props.c` without the colour conversion: measured against a phone-mode picture, ground and prop colours then match closely. Phones on the web start on Low grass. Ran in a real browser with a scripted dig (1.2 m3 in the bucket, total unchanged, dirt code 3.2 ms a tick). Browser frame rate and everything on a phone browser are unmeasured.

## 5 Nov 2026: dump truck, Bobcat, Dingo and trencher

Owner asked for all three, plus attachments once offered, with trenches for pipes to come. `scripts/truck.gd`, `scripts/loader.gd` (Bobcat and Dingo), test `test/fleet_test.gd`. The Now: button cycles all five; parked machines step at a quarter rate.
Truck: road steering, 8 m3 tray, catches falling soil through `DirtSim.catchers`, TIP pours chunks out the back. An excavator put 1.11 m3 in over 2 scripted bites in the test.
Bobcat 0.5 m3, Dingo 0.12 m3. Full bucket with edge down pushes like a blade.
Trencher (Dingo ATTACH): two grid cells wide (50 cm), not the 25 cm first told to the owner, as one cell showed as a crack. Spoil lands 1.05 to 1.65 m to the right. Cut walls stand to 1.15 m (`DirtSim.clean_cut`, `CUT_WALL_MM`). Tracks moved out to clear the slot.
`test/drive_test.gd` tower check depends on the slump time budget: one failure at 4.36 m against a 4.31 limit on a busy PC, then 4.19 to 4.24 on three reruns.
Not checked: anything on the S25, any feel, any sound. Pipes are next, after the owner tries trenching. Web version: IPv4 down at the router on 5 Nov from about 09:00, so GitHub unreachable; the retry publishes from a separate checkout in the scratchpad, and stops at about 22:23.

## 5 Nov 2026: deeper trenches, pipes

Owner said trenches do not dig very deep. Causes: the chain took 2.2 s to reach its 1 m limit, and the ground shader smoothing drew the floor about a seventh too high and softened the lips. Now 1.5 m at 0.9 m/s, walls hold to 1.7 m, and the shader does not smooth across a drop over 0.2 to 0.35 m. Diagonal trench edges look stepped.
Bug found from a screenshot: steering with the chain down dug a crater, as depth was measured from the machine. Now from the firm ground either side, the Dingo bridges the slot (`Loader._ground_at`), and turning is cut to 30% with the chain down. Test: 30 s of steady steering, floor -0.90 m at 0.90 m set, machine stayed at 0.
Pipes (`scripts/pipes.gd`): third Dingo attachment. Lays joined lengths on the floor behind the machine when over ground 0.2 m below either side. Takes no soil. Cannot be picked up or removed, and digging one up leaves it floating.
Excavator curls by itself lifting a load. Tested fill: two Bobcat buckets tipped over a 1.5 m slot raise the floor to -0.69 m; the bucket was filled by the test, not by a scripted scoop of the ridge.

## 5 Nov 2026: cracker dust and the first jobs

Owner's idea: a first small mission spreading cracker dust on a driveway with the Dingo, which unlocks the Bobcat for a bigger one. Agreed: free play stays, with every machine; only the job path locks anything.
Dust: `DirtSim.dust` per cell, never more than the soil there, moved in step with it everywhere (slump, blade, bite, take/put, air, bucket, tray). The Dirt mode's Remove and Drop tools turn it into plain soil. Separate `dust_tex` for the look; solid from 30 mm, patchy under.
Spreading: backing up with the bucket low (edge within 0.22 m of firm ground) on the Bobcat or Dingo floats on firm ground and leaves exactly 50 mm (`DirtSim.drag`). Excess is carried along. Never cuts firm ground.
Jobs: `scripts/mission.gd`, data in LIST. Done is 90% of cells with 30 mm of dust. No failure, timer or score. Long driveway (4 x 20 m, Bobcat, 8 m3 pile) was my stand-in for "a bigger mission", for the owner to change. Saved in user://progress.cfg; demos don't write it.
Bugs found by the bot: rolling drag was a fixed 7000 N, more than the Dingo's grip on loose soil, so it froze near heaps (now scales with mass under 20 t). A bucket lowered on rock stopped the machine dead (now 90 mm of scrape).
Test: `test/mission_test.gd`, bot in `test/spread_bot.gd`. Bot times 408 s and 784 s, not a player's. Tipped from raised, the far side of a load is beyond the lowered edge, so it needs a creep forward first. Bot needed 8 m3 for the long job, and the piles have spare on purpose.
`test/drive_test.gd` tower check still flaky: 4.21 to 4.34 m against 4.31 (range before dust: 4.19 to 4.36).
Not checked: anything on the S25, any feel. Flying clods stay brown when scooping dust; the gauge says IN DIRT for dust. Web version not rebuilt: the queued push is the older build.

## SPREAD button (5 Nov, owner feedback)
Dumps pour from the middle half of the bucket and cracker dust stands at 45 degrees (soil 34), so a Dingo load stands about 43 cm and a Bobcat load about 58 cm. SPREAD (Bobcat, Dingo) lowers the bucket by itself; driving either way lays out 50 mm. RAISE, CURL or DUMP turn it off. Backing up with a hand-lowered bucket still spreads too. The touch checks need a real window: the headless window is tiny, so buttons overlap the thumb.

## CUT on the dozer (5 Nov, owner idea)
CUT holds the blade a set depth (5 to 50 cm, default 20, + and - buttons) below where the ground began (DirtSim.start_ground), so overlaps do not go deeper. Reads the land 0.4 m behind the edge (CUT_READ), sweeps two extra rows for loose soil that slid behind, top speed 2 m/s, RAISE turns it off. Dirt mode tools re-mark the start ground where used. test/cut_test.gd measures it: about 18 cm at 20, 37 cm at 40.

## Play with a friend (5 Nov, owner asked; web only for now)
Published to the live link. `scripts/online.gd`, transports copied from Smashed into `scripts/net/` (PeerJS on the web, ENet for PC checks; room prefix dozerdrive-). Host runs every machine and all the dirt; guest sends thumbs 20 Hz and draws. Machines 20 Hz, changed chunks 8 Hz (deflate, 10 a message), about 50 KB/s while working. Game side is by player number (`drivers`); the transports still take one guest, so 4 players means extending those. No menu option on the APK, since ENet there is same-wifi only. Dirt tools, Mode and Reset are hidden online. No prediction: a guest feels a little delay.
Checks: `--online=host:ABCD --demo=nethost` and `--online=join:ABCD --demo=netguest`; on the web `?online=...&demo=...`, and `?report` prints the ground checksum. Host and guest ground matched exactly over ENet and over PeerJS between two browsers. Not tried on phones or across two networks.

## Bucket picture (5 Nov)
Owner asked for an easier way to tell where the bucket is and its angle. scripts/bucket_view.gd draws a live side-on picture, top right, for the excavator, Bobcat and Dingo bucket: arm, bucket at its true angle, real ground along the arm, height over the ground and angle in degrees, orange with POURS when a loaded bucket is tipped past what it holds. Machines supply it through side_view() and side_ground(). test/bucket_view_test.gd checks it matches the real teeth. On the web link and in the APK.

## Two players on the jobs (5 Nov)
Owner's decision: one machine each of the same kind, finishing a job unlocks the next for both. Host a game now asks what to play (open jobs or free play). Starting a job reloads the scene, so Online.carry_over() lifts the connection out of the old game and Online.arrive() puts it in the new one; that also lets the host go on to the next job with the same room code. A guest learns the job from the snapshot, follows, and asks for all the ground again (READY). The host's game says when the job is done. Friend starts 3 m from the host's machine on the side away from the driveway. Check: --online=host:ABCD --mission=driveway --demo=nethost and --online=join:ABCD --demo=netguest; on the web ?online=host:ABCD&mission=driveway&demo=nethost.

## Truck in the picture, dozer picture, hide button (5 Nov)
Owner asked for the truck in the side picture to line up with, the picture on the dozer, and a way to hide it. The excavator and loaders draw the truck from the side (faint until the arm's line crosses the tray) with a word: SWING or TURN left/right, REACH OUT/IN or GO FORWARD/BACK UP, RAISE, OVER THE TRUCK: DUMP. Word is Claude's choice. Dozer has the picture too; its small bar now only shows while the picture is hidden. HIDE/SHOW sits beside the picture and is remembered in user://settings.cfg. test/bucket_view_test.gd lines up and dumps by following the words.

## Dirt looks (5 Nov)
Owner wants pushed dirt to look more like Dirt Town (Skyturns, on Steam). textures/clods.png, baked by test/make_clods.gd, holds lumps as normals, gap depth and shade; the ground shader reads it where loose dirt lies, using how deep it is (second channel of dust_tex). Worn ground stays smoother and darker. Dirt colour is now #a65c33 everywhere. Sun shadow bias raised to 0.7 to remove ripple marks on steep faces. Moisture and compaction: saved for later.

## Real lumps of dirt (6 Nov)
The owner said the painted clods were "better but still not great". Added `shaders/clod.gdshader` and `_build_clods` in `game.gd`: 3D lumps in 8 m chunks, about 22 per square metre, drawn only on chunks with loose dirt (`GroundView.loose_here`). Each lump reads height and depth from the grid textures, so it needs no rebuilding, and it rolls and shuffles as the height under it changes. Looks only: the simulation is untouched. Far chunks draw fewer, and the Grass setting cuts them down to 40% at most. Adds about 150k triangles with the starting pile near. Not tried on the phone yet.
Same day, after a close-up check against Dirt Town's store screenshots: the lumps had been drawn inside out (the index order was anticlockwise; Godot's front faces are clockwise). Fixed, and the lumps made bigger (0.07 to 0.34 m, 28 per square metre) so they cover the heap; heaps lit softly (ground.gdshader has its own light() now, soft where `v_soft`), lumps drawn after the ink pass so they get no outlines, dirt darker (#7d4329 for props), and flying and falling dirt now uses the same faceted lump in place of boxes. Near chunks are drawn whole out to 22 m. About 250k triangles more than with no lumps, near the big pile.

## Trench backfill (6 Nov)
The owner found a trench couldn't be filled back in. The dirt was all there (measured), but pushing it back spilled some and spreading left a 5 cm layer everywhere, and SPREAD across a trench dipped the bucket in and dug the fill back out. Now: the trencher's dirt swells 35% (`DirtSim.SWELL_PCT`, counted in `swelled` so `total()` still never changes); it lands 0.95 to 1.5 m out (plus 0.25 m per m deep), clear enough not to slide back in; and the spreading bucket's edge goes no lower than 3 cm under the highest firm ground under its floor (`REACH_BELOW`, checked over the bucket and 0.8 m back), so it rides over a trench. With SPREAD runs from the ridge across a 1.5 m trench, two rounds leave most of it within 6 cm of the old ground, with dirt to spare; the first metre, where the cut starts, stays about 30 cm low. Track ruts still squeeze soft backfill a little. fleet_test checks the swell and that SPREAD leaves a filled trench filled.

## Stars, and the roof water job (6 Nov)
Driveway jobs: 70% one star, 80% two, 90% three and done by itself (`Mission.STARS`); from one star a FINISH button shows in the top bar. The best stars are saved (`Mission.stars`); a job done before stars counts as three. The end menu shows the stars and offers "Try again for 3 stars".
Roof water (`roof_water`, kind "pipe", Dingo, after the long driveway): the first driveway already laid in cracker dust, a gutter and downpipe on the house's right front corner, a flooded lawn round its foot (a water sheet over mud, `_add_flood`), a drain grate at the street edge. Dig a trench from the downpipe to the drain, lay pipe along it: once one run of pipe has an end within 2.5 m of each (`Mission.joined`) the lawn drains over 6 s. Then fill the trench in: done at 90% of trencher-cut cells within 10 cm of where they started (`Mission.filled_in`). The trick for the last of it: a SPREAD bucket over a low trench cell rakes spare loose soil from up to 2.5 m round in (`DirtSim.rake_into`), which fixes the short first metre. mission_test plays it through with the real Dingo. Known: drive_test's scraping-sound level check is random and now and then reads 1.05+ (unseeded noise), unrelated.

## Backyard flood (6 Nov)
`backyard`, kind "flood", Dingo, after roof water. The site reaches 23.5 m behind the house front (`Mission.site`); `Mission._shape` sinks a hollow (250 mm) where the flood sits (water at -80 mm) and raises a 300 mm rise between it and a drain pit at the back paling fence. Water only runs downhill: `Mission.pipe_run` gives the joined run from the flood to the drain, `water_stops_at` the first point that climbs more than 3 cm (`FALL_SLACK`) over the one before, or the inlet if it's above the water. A flag with "WATER STOPS HERE / DIG DEEPER" (fixed-size Label3D) stands there. Pipe now rests on the trench's firm floor (`Pipes.settle`, every 0.25 s in a job), so re-cutting deeper under it drops it. The trencher readout says FLOOR GOING DOWN / UP / LEVEL over the last half metre. mission_test plays it: one depth gets flagged (at the hollow's edge, as the floor climbs out of it), dug again falling from -0.8 to -1.1 m flows, then filled in. The start menu is compacter to fit six choices.
Then the owner asked for the backyard flooded with a trampoline and a floating outdoor set. The flood's now a ragged-edged dip over most of the yard (`basin_mm` 250 over an 11 x 5.5 m ellipse, water at -50 mm) with the deeper hollow at one end and the rise an island; the drain pit stays dry. Shallow edges keep their grass standing through the water, deeper is mud. Draining lowers the water level (over 10 s) so the yard comes up out of it. `_add_backyard_things`: a trampoline standing in it (an obstacle), and a white plastic table and four chairs that bob, wander, get shoved aside by machines and settle on the mud once it's gone (`_update_floaters`, local to each game, not sent online). My reading: the trampoline stands, only the set floats.
Hold-to-skip for testing (owner's ask): in the start menu's job list, each open job not yet done has a HOLD TO SKIP beside it (`_skip_row`); held 1.5 s it marks the job done with no stars (the list says SKIPPED) and redraws it, so the next opens. `TEST_SKIP` in game.gd turns it off: the owner wants to lock it once testing's done.

## Pipe laying made easier (6 Nov)
From the owner's phone screenshot: pipe was going on the trench wall and up out of its end. `_work_pipe` now looks 0.6 m either side of the layer (`PIPE_SNAP`) for the lowest firm ground and lays there; whether that's a trench is judged 0.45 m either side of it. Laid 0.4 m off line and drifting, it stays within 0.19 m of the line and down in the slot. Pipe jobs show a yellow hoop (radius = how near a pipe end must be) and words at each end, START THE PIPE HERE / END THE PIPE HERE (a flood's start is words only, START THE PIPE IN THE WATER); each goes green once a run of pipe ends in it (`Mission.ends_reached`), all go once the water runs. The banner says which end is still to reach. Once joined, `_add_joins` draws lengths from the downpipe's foot into the trench and from the trench into the drain.
Then: the owner couldn't find where the backyard pipe starts (looked for a pipe on the house). The backyard now has an `inlet` spot in the water with a hoop like the drain's (`Mission.source` uses it), so the pipe has to start within 2.5 m of it. Both ends of pipe jobs have a big yellow arrow over them that bobs and flashes until a pipe reaches that end. And a pipe job opens with a look round (`_start_tour`, 5.6 s, any tap or key ends it; not in checks or demos): the camera goes to the start (THE PIPE STARTS HERE), then the drain (AND ENDS HERE, AT THE DRAIN), then back. Also the scraping sound is capped at 0.95 so its test can't fail at random.

## GRADE (6 Nov)
The owner couldn't get the backyard pipe to run: a trench at one depth follows the ground, deep in the flooded dip and climbing out of it. Now, with the trencher on, the SPREAD button is GRADE (a laser level): the chain goes to 0.45 m, the floor there is taken as the start, and from then the chain's depth is set so the floor falls 3 cm for every metre nearer the drain (`grade_toward`, set to the job's drain). RAISE or changing attachment turns it off. Without GRADE the readout shows the same aim ("TRENCH 0.62 m DEEP   AIM 0.85 m   GO DEEPER"). Whether the water gets through is now judged only between the last of the pipe in the start's ring and the first in the drain's, so a trench ramping up where the chain lifts out by the drain doesn't stop it. The flag says WATER STOPS HERE / DIG DEEPER FROM HERE / TO THE DRAIN; the banner DIG DEEPER FROM THE FLAG TO THE DRAIN, or START THE PIPE DEEPER, UNDER THE WATER if it's the start that's dry. mission_test digs the backyard with GRADE and the water gets through first time.

## Trench picture (6 Nov)
From the owner's phone screenshot: told to dig deeper, but couldn't see how. With the trencher on, the side picture (top right, where the bucket picture goes) now draws the trench side-on along the way the machine faces, 7 m behind the chain to 2 m ahead (`BucketView._draw_trench`): the ground, the slot cut so far (the flood drawn in it where the ground's under water), its floor green, or red where it climbs more than 5 cm over any floor before it on the way to the drain (`trench_line`), the aim floor dashed, the chain and its teeth, a white tick where the teeth ought to be and a red arrow down when they're short. Top: DEPTH and AIM; bottom: LOWER IT TO DIG / ON THE AIM: KEEP GOING / GO DEEPER x m: LOWER / RED GOES UPHILL: DIG IT DEEPER / GRADE ON: JUST DRIVE (`trench_word`). The picture's depth range follows the trench (0.9 to 1.85 m). Change to the aim: dug deeper than it, it comes down to that depth, as coming back up to the old aim would be uphill. 5 cm, not 3, before it says red: the chain leaves 3 cm bumps that don't stop the water. mission_test has a player who only does what the picture says (LOWER while it says so), and the water gets through first time with no red; and lifting the chain partway shows red. `--demo=trenchview` for a picture of it.

## Filling in, stars and a steadier Dingo (6 Nov)
- Pipe jobs now give stars for how much of the trench is filled back in: 70/80/90% for 1/2/3, like the driveway. FINISH shows from
  1 star once the water's through; 90% finishes by itself. The menu and the end screen show stars for every job.
- A pile of plain fill dirt beside the trench in both pipe jobs (`fill`, `fill_m3` in Mission.LIST; DirtSim.add_pile).
- Dirt falling within 0.75 m of a trench that's still low tips into it (DirtSim._land, FUNNEL), so DUMPing beside it fills it.
- The easy way, now in the hints and the banner: SPREAD on, drive along the trench. One run fills about 88%, two fill it.
- Dingo: settles onto the ground slower (7 a second, was 16), leans no more than 8 degrees sideways (side_lean_most), half the
  jiggle. Steering off the touch stick has a dead zone (STEER_DEAD 0.18) and builds gently to full lock.
- test/fill_feel_test.gd checks the run along, the lean, and the tip-in. `--demo=touchsteer` prints the steering from a thumb.

## The trench aim is the job's own line, with a depth stop (6 Nov)
- The owner held LOWER to the bottom (1.5 m); the aim followed the chain down and then asked for 1.75 m. Fixed:
  Mission.trench_plan works out one floor line per job from the ground at the start: water source to drain, falling
  GRADE_FALL a metre, at least PLAN_COVER 0.3 m under the ground everywhere, and 0.1 m under the water at a flood's start.
  Loader.plan holds it; the aim is that line wherever you are within PLAN_NEAR 1.5 m of it.
- Depth stop: on a job, the chain won't go more than DEPTH_STOP 2 cm below the line by hand, because digging deeper and
  coming back up would be a rise. GRADE follows the line. Free play keeps the old aim (from where you start, follows you down).
- "TOO DEEP x m: RAISE" in the picture if it still ends up 10 cm under (the ground beside dropping away).
- mission_test too_deep_test: LOWER held at the start stops at the aim (0.32 m), the aim never passes 0.84 m, water through.

## On foot (6 Nov, big run step 1)
- scripts/worker.gd: Worker extends Machine, so the camera, buttons and online work as for any machine. Push the stick to walk
  (2.2 m/s, 1.1 back), sideways to turn (tank style, like the machines). Arms and legs swing. Upright on the ground, no track wear.
- Two workers, one per player, appended last to game.machines so every machine keeps its number. Hidden (and footprint far
  away) while in a machine. game._sync_people() every tick: hides a worker whose player isn't on foot, shows the Dingo's
  driver (now a separate mesh, Props.dingo_driver) only while someone's in it. Guests set visibility from online.drivers.
- "Get out" in the top bar, next to Menu (F on a keyboard): steps off on whichever of 16 spots round the machine has most
  room (left side first). GET IN: a big button where the right thumb rests, shown with the machine's name when he's within
  0.9 m of one nobody's in. Online: ask("out") / ask("in"), host does it. The quick switch skips workers.
- Checks: `--demo=touchwalk` (also with --mission=roof_water): out, walk, home in, GET IN, all by touch. The net demo's guest
  now gets out, walks and gets back in; host sees it.
- Known, not from this: drive_test's "no tower ahead of the blade" is borderline when the dirt runs out of its 4 ms a tick
  (4.32-4.41 m against 4.31); with no time limit it passes at 4.28. The touchswap and touchmenu checks are older than the
  machine list and the SKIP rows.

## FINISH or KEEP GOING at every star (6 Nov)
- Owner: no option to stop at 1 or 2 stars in the backyard, and wants to choose to carry on too, on every job type. FINISH was
  there, but only small in the top bar, and 90% ended the job by itself.
- Now each new star brings up a card mid-screen: "2 STARS!", "Finish now, or keep going for 90%", FINISH and KEEP GOING
  (real multi-touch buttons, kept clear of the machine buttons below). Nothing ends by itself, 3 stars included. The top-bar
  FINISH stays for later. Same code for driveway, pipe and flood jobs (_score / _can_score); a new job kind just needs those.
- Online: only the host gets the card; both finish together. The net job demo's host taps FINISH at 3 stars.
- `--demo=fillstars` with --mission=driveway / roof_water / backyard: fills a share at a time, prints the card, taps KEEP GOING
  then FINISH.

## Big run steps 2 to 5 (6 Nov, owner: "keep going with the plan... go, go, go")
Picks below are Claude's unless said; the owner agreed the list, not the details.

### Hand tools and the garden patch (step 2)
- On foot: SHOVEL and RAKE buttons pick a tool up or put it down (green while held). With the shovel, the bottom-right button
  says DIG, then THROW, or THROW IN BARROW when a barrow's right in front. A shovelful is 0.012 m3 (Worker.SCOOP), loose soil
  comes freely, firm ground 24 mm a cell at a time. Thrown as four clods on an arc (sim.launch), so a barrow's tray catches them.
- scripts/barrow.gd: Barrow extends Machine. PUSH BARROW (the GET IN button) takes the handles; the worker's drawn pushing it.
  Holds eight shovelfuls (0.096 m3), TIP lifts the handles and pours it over the wheel. Get out lets go. A sim catcher, like
  the truck. Free play has one by the cracker dust.
- Rake (DirtSim.rake): walking with it out, loose soil in a strip ahead that stands above the strip's average is drawn into
  what's below it, the lowest getting most. Whole mm, loose only, so it never digs and never loses soil. Slower walk.
- Garden patch job (after Backyard flood, "machine": On foot): a sunken patch by the driveway (10 cm, flat bottomed, 1.1 m
  across), garden soil heaped by the fence, a barrow. Done within 3.5 cm of level, 70/80/90% for the stars. Starts on foot.
- test/hand_test.gd: 8 shovelfuls fill a barrow, TIP empties it, four loads and raking get the patch to 100%, no soil lost.
  `--mission=garden --demo=touchhand` does it all with the real buttons.

### Pads: pegged-out ground and its tint
- scripts/pad.gd: an outline of pegs, a level, how far above and below counts as done, and the cells inside (less a margin for
  a dam's sloping sides). score() is the share at level. The ground shader tints inside: red to take off, blue to fill, green
  done, with a line every 10 cm off. Pegs and pink string drawn by game._add_pad.

### Big machines on the big site (step 3)
- The world's size is now set per site: DirtSim.set_world(half) before anything's built (CELLS, CHUNKS, GroundData sizes,
  Machine.AREA are static vars; shaders take HALF/LAST as uniforms). The big site is 96 m across (385 cells), a rolling paddock.
- Big dozer and big excavator are the same classes made 1.9 times bigger (Machine.size, make_big before setup): the machine's
  own transform carries the scale, so everything worked out in its own space comes out bigger. Weight and engine x size cubed,
  so they handle like the small ones. Blade heaps and spills further (DirtSim.blade scale), the bucket holds 8.2 m3, both bite
  firm ground faster. The big dozer's CUT goes to 1 m. Buttons are the small ones' ("Big " is dropped when matching).
- Free play: big machines (start menu) puts them on the big site with two stockpiles. On a phone it starts with Low grass
  (twice the ground); on the PC, High.
- Farm dam job (after Garden patch): 24 x 14 m pegged out, 1 m deep, a tank and a shed beside it. The floor counts (1.5 m in
  from the pegs), within 15 cm. Inside the pegs CUT stops at the floor; the excavator's readout says how far to the floor.
  Finishing fills it with water. Online, the friend gets the other big machine.
- test/big_test.gd: the big dozer pushes eight times the load, the big excavator takes three times the bite, CUT passes dig the
  dam to 93-100% and never below the floor, no soil lost.

### The scout ute (step 4)
- scripts/ute.gd: white single cab, steel tray, bull bar, beacon; 40 km/h, road steering. In both free plays and the dam job.
- Free play only: PEG drops a survey peg beside the driver's door (up to 12), the button above says UNDO PEG, then CLOSE IT UP
  from three. Closing makes a pad round the outside of the pegs, levelled to the ground's average inside (cut and fill
  balance), within 5 cm. The dozer's CUT and the excavator's readout work to it. Stars and the FINISH / KEEP GOING card like a
  job; FINISH says PAD DONE and pulls the pegs. PULL PEGS or NEW PEGS start again. Pegs go to a friend online (PEGS message).
- `--machine=Ute --demo=touchute`: drives, four pegs, closes, levels, FINISH.

### The PC build (step 5)
- Same game, not a branch: project renderer is Forward+ on desktop, Mobile on phones, Compatibility on the web.
- On the PC (_pc_look): soft shading in corners (SSAO), screen-space reflections, sky reflections, 4 shadow splits, 4x MSAA,
  High grass, and shaders/water_pc.gdshader: moving ripples, the ground seen through and bent, darker deep, foam at the edges.
- "Windows" export preset, embedded pack: build/DozerDrive.exe, copied to G:\My Drive\Dozer Drive PC\. Not signed, so
  Windows may warn the first time.

### Also
- Start and host menus in two columns, so seven jobs and two free plays fit on a phone. Hints wrap clear of the buttons.
- online: place_id() says where the host is ("big" for big free play) so a friend follows onto the big site.
- This PC's test window draws at about 4 frames a second even for the build before this work, so on-screen speed here says
  nothing; phone speed on the big site is still to be tried.

## The mine (7 Nov 2026)
Owner: the big machines should look different, "more like mining", so unlocking them feels like a different thing. Agreed
(owner's picks from a list): mine-white colours, the big site becomes a mine, free play with them stays open from the start,
and a haul truck now. Farm dam is to be swapped for a mine job, to be worked out with the owner next: until then it keeps the
green paddock (only the mine is new).
- Big dozer and excavator (Props.* with `mine`): fleet white with grey, black tracks, hi-vis stripes, painted fleet numbers in
  block letters (Props.stencil: DZ-01, EX-01, HT-01), safety-yellow handrails and ladders, a spinning orange beacon
  (Machine.beacon, turned in game._process). Dozer: closed cab (one block of glass, so the seat view still sees out), walkways
  over the tracks, one big ripper tooth, U-blade wings. Excavator: cab up on a riser (cab_eye follows), ladder, rails round the
  engine deck, chevrons on the counterweight, a grey rock bucket with five big teeth.
- Haul truck: Truck with `haul` set before setup (the truck's sizes became vars; the consts stay for the road truck). About
  11 m long and 7 wide, cab up on a deck on the left, a stair across the front, a canopy over the cab, tray rim 5 m up. Holds
  40 m3 (about five full big buckets), 65 t empty, 30 km/h empty. On the mine `truck` IS the haul truck, so the bucket view,
  TIP and online all work as they did; "Haul " is dropped when matching buttons.
- The mine (GroundData `mine`, game `mine` = big site with no job): a stepped pit (first bench 2.5 m down, floor 5 m down, faces
  at 1.5:1), a ramp cut down its south side onto the bench then the floor, a haul road from the parking area past the top of
  the ramp to the dump, windrows of loose dirt along the road and the ramp's open edge, and a bund all round instead of the
  fence. Red dirt (ground and clod shader colours, Props.set_dirt for lumps and buckets, red dust), no grass at all, no trees.
  Two site huts, four lighting towers, red flat-topped hills, spinifex and gums out past the bund.
- Free play: the excavator and haul truck start on the pit floor by a 70 m3 heap of broken rock, ready to load; the dozer and
  ute up by the parking area; a 45 m3 stockpile at the dump. Menu entry is now "Free play: the mine".
- test/mine_test.gd: levels where they should be, windrows and bund there, the haul truck takes a full load up the ramp (slowest
  4 m/s) and the big dozer climbs it too, a big bucket tipped over the tray all lands in it, no soil lost.
- `--machine="Big excavator" --demo=mineload`: a full bucket tipped into the haul truck, with a picture as it pours.
- Online checked: the friend follows onto the mine and gets the haul truck; both games' ground matches.

## Owner's fixes, 7-8 Nov 2026

- On foot the SHOVEL and RAKE buttons never showed (the button check turned "On foot" into "On Foot"). Fixed; `test/onfoot_test.gd` gets out in free play and on the mine and checks them.
- The barrow: the button that says PUSH BARROW says LET GO BARROW while pushing it (the top bar says Let go), and letting go leaves him a step behind the handles. No engine sound on foot or with the barrow.
- Farm dam: floor dug deeper than the dam's 1 m counts (`Mission.DAM_DEEPER_OK`); the owner had read 6% on a dug-out dam because blue (too deep) didn't count and wasn't explained. The hint says green is deep enough.
- Excavator bucket, owner's ask: holds 1.8x (small 2.16 m3, big about 14.8 m3), drawn 20% bigger all round (`BUCKET_GROW`), digs firm ground and tips out faster to match. Same drag in dig_test: loose 1.11 to 2.07 m3, pile 0.81 to 1.48, firm 0.82 to 1.36. Trucks unchanged, so the haul truck fills in about 3 big buckets and the road truck in about 4 small ones.
- Farm dam water, owner's ask: they'd used the old blue "too deep" tint as water to dig down to, and it went when deeper started counting. Now a sheet of water lies hidden under the dam inside the pegs at the floor's depth plus `DAM_TOL` (`Mission.dam_water_y`), so it shows just where the floor counts; dug deeper, the water's deeper. When it's done the fill rises from that sheet. Hint: "dig until you hit water". `big_test` checks it's hidden to start with and that where it shows matches the score.

## Buried find job, 8 Nov 2026

Talked through with the owner one step at a time: a surprise each time, found with pegs and a beep, and knocks cost a little. The
owner then said to work out the rest and set it up; those picks are Claude's and are marked (pick) below.

- `Mission` "buried_find" after Farm dam (its done line now says BURIED FIND UNLOCKED), on the paddock (pick), starting in the big
  excavator with the big dozer there too (pick). A 22 x 14 m pegged patch with the farm's tank and shed beside it.
- `Find` (scripts/find.gd): an old car, dinosaur bones or gold (a big nugget in quartz with small ones round it), picked from a seed,
  at a random spot and angle inside the pegs, its top 1 m down for the car and 0.8 m for the others (pick). Built from boxes, wheels
  and rough lumps, drawn where it lies, so it shows as it's dug down to.
- `DirtSim.hard`: per cell, the lowest the firm ground can be dug or slump to (BED_FLOOR everywhere else). A find sets it to its top
  less 4 cm, one cell early where it steps down inside itself so the drawn ground's slope stays hidden in the taller part.
- The excavator's teeth stop on it like rock, and can still be dragged along its top to scrape it clean. `touch_speed` is how fast
  they came down onto it (or across into its side): over `Excavator.KNOCK_SPEED` x size (about half stick on the big one) is a knock,
  at most one a second. Each knock is marked on it and costs 3% (pick). A soft touch makes no clunk.
- The beep starts 5 m off and goes from about one a second to ten a second (pick), from the bucket's teeth or the dozer's blade, with
  an orange light under the banner for playing with the sound down.
- The score is how much of its top has no more than 12 cm of dirt on it (pick), less the knocks; stars at 70/80/90% as usual. The
  banner says BURIED FIND till 6% of it is uncovered, then names it ("It's an old car!" on screen too) and counts the knocks. The
  end screen says what it was.
- Online, the place id carries the seed (buried_find#1234) so a friend's game lays the same find.
- `test/find_test.gd` covers all of it, in the sim and in the whole game.
- Owner played it, 8 Nov evening: "really hard to dig it up without knocking it, and then it knocks and then pauses", and you can't
  see where the bucket is. Asked what Claude thought; all three fixes went in:
  - No pause: touching the find no longer zeroes the arm's speeds. The bucket just can't go into it; the move's tried again without
    the lowering, then without the curl, then the curl alone. Only a knock clunks or shakes.
  - Soft landing: let down over the find, the bucket eases off in the last 0.35 m x size, to 30% of the speed asked
    (`SOFT_LANDING`, `SOFT_SLOWEST`). Flat out it lands at about 1.1 m/s. A knock is now over 1.6 m/s x size (3 m/s on the big one),
    and only coming down onto it or swinging the house into its side counts: the arm dragged or curled against its side is a touch.
    In practice a knock is a curl or swing slam.
  - Bucket view: a fourth View (Chase, High, Cab, Bucket) for the excavator and loaders, skipped in anything else. Looks down at
    70 degrees from further round than the chase view (`BUCKET_SIDE`), following the teeth smoothly; drag to look round, pinch to
    zoom. The readout says ON IT: GENTLY when the bucket's resting on the find, not ROCK: CAN'T DIG.
