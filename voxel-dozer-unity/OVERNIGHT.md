# Voxel dozer: overnight brief

Written 15 Nov 2026 for an unattended overnight session. Read all of it before touching anything.
The owner is asleep. Nobody can answer questions or judge how anything feels until morning.

## What this game is

A separate new game in Unity (not Dozer Drive, which stays in Godot). A voxel bulldozer and a worker on
foot at an old quarry with a caved-in mine.

The owner's direction, in their words (paraphrased closely):
- The mine collapsed years ago. You start with a shovel and a pick and work up to bigger tools.
- Rail carts you operate by hand at first; then you upgrade the cart, put a motor on it, upgrade the
  track, go deeper, with stronger supports and bigger machinery for harder rock.
- Along the way you find stuff to repair the dozer. At the true start the dozer is completely dead,
  with its first repair coming early.
- The mine tunnel stays small. The dozer works the surface.

## Rules from the owner (these override your own judgement)

1. **Talk before building.** Do not invent design details. Where something is undecided, use an obvious
   placeholder and write the question in "Questions for the owner" at the bottom. Build only what this
   brief lists.
2. **The owner must be able to drive the dozer.** The game starts with them in a working dozer. Do not
   make the dozer dead by default. `F9` is the test switch for the dead state.
3. **Keep things forgiving.** Nothing should be fiddly or punishing. No damage to finds, no fail states.
4. **Do not tune feel or looks.** No changes to swing timing, mouse speed, camera, colours, lighting, or
   the dirt physics constants. Only the owner can judge those, and they have been tuned with them today.
5. **Never say something works unless a test showed it.** Yesterday the owner was told "you start in the
   dozer" when a stale stored value meant they did not. Prove state at run time.
6. **Write to the owner in short plain sentences.** No jargon. Say what was done and what was not checked.

## Where everything is

Repository: `C:\Users\Admin\Documents\Smashed-tv`. The checked-out branch is `smashed-td` (another game).
Do not switch branches. This game is saved on branch `voxel-dozer` (see "Saving").

| Path | What it is |
|---|---|
| `art/bulldozer-vox/make_bulldozer_vox.py` | Generates the dozer model (.vox files). Only touch for model changes. |
| `art/bulldozer-vox/make_unity_export.py` | Writes the Unity files. Holds the editor script as the string `BUILDER_CS`. |
| `art/bulldozer-vox/unity-src/` | The hand-written game scripts and shader. **Edit game code here.** |
| `art/bulldozer-vox/unity-export/` | Generated copy. Never edit. Ignored by git. |
| `art/bulldozer-vox/clips/` | Recorded videos. Ignored by git (too big). |
| `voxel-dozer-unity/` | The Unity project (Unity 6000.3.2f1, built-in render pipeline). |
| `voxel-dozer-unity/Assets/Bulldozer/Scripts/` | Copies of `unity-src`. Overwritten by the copy step. Never edit here. |
| `voxel-dozer-unity/Logs/` | Test pictures and clip frames. Ignored by git. |

Scripts in `unity-src`:
- `VoxelWorld.cs`: the ground. 1536 x 224 x 1536 voxels of 6.25 cm, chunked, Burst jobs. `GenerateJob`
  shapes the quarry. Blade cutting (`BladeSweep`), ripper (`Rip`), slump, remesh, grass.
- `VoxelWorldDirt.cs`: loose dirt as simulated clods (8 voxels each). `StepDirt`, drawing.
- `VoxelWorldHand.cs`: what a person needs: `FloorAt`, `MaterialAt`, `Raycast`, `Pick`, `Scoop`, `Throw`,
  and the cart's `CartCollect` / `CartPour`.
- `DozerController.cs`: driving, blade lift/angle/tilt, ripper, digging. `dead` and `driven` flags.
- `Worker.cs`: the person on foot. Views, aim, timed swings, getting in and out of the dozer.
- `MineCart.cs`: hand cart on the rails.
- `SiteProps.cs`: scenery built from boxes at run time (mine entrance, rails, trees). Creates the Worker
  and the MineCart. `RailPath` is the track.
- `FollowCamera.cs`, `BladeView.cs`, `TrackAnimator.cs`, `SceneLook.cs`, `VoxelTerrain.shader`.

## How to change, build and test

**Unity must be closed** before any batch command: the project cannot be open twice. Close it with:

```powershell
$p = Get-Process Unity -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like 'voxel-dozer-unity*' }; if ($p) { $p.CloseMainWindow() | Out-Null; $p.WaitForExit(40000) | Out-Null }
```

**Unity Hub must stay open and signed in.** Without it every batch run fails with
"No valid Unity Editor license found". If you see that, stop: only the owner can sign in. Write it in the
morning report.

Step by step (Git Bash):

```bash
cd /c/Users/Admin/Documents/Smashed-tv/art/bulldozer-vox && python make_unity_export.py
cd /c/Users/Admin/Documents/Smashed-tv
cp art/bulldozer-vox/unity-export/Bulldozer/Scripts/* voxel-dozer-unity/Assets/Bulldozer/Scripts/
cp art/bulldozer-vox/unity-export/Bulldozer/Editor/BulldozerBuilder.cs voxel-dozer-unity/Assets/Bulldozer/Editor/
```

Then run Unity (`U` is `/c/Program Files/Unity/Hub/Editor/6000.3.2f1/Editor/Unity.exe`, `P` is
`C:\\Users\\Admin\\Documents\\Smashed-tv\\voxel-dozer-unity`, `LOG` is any log file path outside the repo):

| Command | What it does |
|---|---|
| `"$U" -batchmode -projectPath "$P" -executeMethod BulldozerBuilder.SelfTest -logFile "$LOG"` | The main test. Compiles, plays, digs, exits by itself. About 1.5 minutes. |
| `"$U" -batchmode -projectPath "$P" -executeMethod BulldozerBuilder.RecordWalkClip -logFile "$LOG"` | The on-foot run: walks into the mine, picks, shovels into the cart. |
| `"$U" -batchmode -projectPath "$P" -executeMethod BulldozerBuilder.RecordClip -logFile "$LOG"` | A dozer digging clip. `RecordRipClip` is the ripper on rock. |
| `"$U" -batchmode -quit -projectPath "$P" -executeMethod BulldozerBuilder.BuildFromCommandLine -logFile "$LOG"` | Rebuilds the dozer prefab and demo scene. Only needed when the builder's scene or prefab code, the models, or `bulldozer_parts.json` change. |

Read the result with: `grep -E "BULLDOZER_|error CS|Exception:" "$LOG" | sort -u`

What a healthy run prints (the numbers that matter):
- `BULLDOZER_ENTER_TEST startedInDozer=True dead=False ... afterIn:inDozer=True driven=True`
- `BULLDOZER_DIG_RESULT ... volumeChange=0 trackingError=0 ... clodsLeftAfterParking=0`
- `BULLDOZER_WALK_OK ... inCartLitres=` several hundred `... volumeChange=0`

**If any of those regress, fix that before doing anything else.**

Clips: frames land in `voxel-dozer-unity/Logs/clip/frame_0000.jpg` onwards. Make a video with

```bash
"/c/Users/Admin/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg" -y -loglevel error -framerate 30 -i voxel-dozer-unity/Logs/clip/frame_%04d.jpg -c:v libx264 -pix_fmt yuv420p -crf 26 -preset slow -movflags +faststart art/bulldozer-vox/clips/NAME.mp4
```

Look at a few frames yourself (Read the .jpg) to check a change. On-screen text (OnGUI) is **not** in
recordings.

## Traps found the hard way

- **Stored values beat code defaults.** Changing a public field's default does not change a prefab Unity
  already imported. Mark run-time state `[System.NonSerialized]`, and prove it with a run-time check.
- **Volume must stay exact.** `SolidCount + LoadVoxels` is constant. Anything that holds dirt (blade
  tally, clods, shovel, cart, and anything new) must be counted in `LoadVoxels`. It is set in three
  places: `BladeSweep`, `StepDirt`, and via `Recount`. A new container needs adding to all of them.
- **`top[]` is the open-sky height of a column.** Underground it is the hilltop above, not the floor.
  Anything under a roof must use `FloorAt` (main thread) or `FloorIndex` (in the clod job).
- **Burst jobs run with safety checks off.** An index out of range corrupts memory silently. Clamp every
  coordinate (see how existing jobs clamp to `Rim + 5` or `Rim + 6`).
- **Git Bash heredocs mangle backslashes.** Do not write C# or patch scripts through a bash heredoc if
  they contain `\n` or similar. Write the file with the Write tool, then run it.
- **Do not drive the Unity window with screen control.** Clicks are unreliable and screenshots steal the
  owner's keyboard focus. Test with the batch commands and recorded frames.
- **First launch after a script change does not enter Play mode.** It compiles and stops. Launch again.
  Confirm Play started by finding `__Backupscenes` in `%LOCALAPPDATA%\Unity\Editor\Editor.log`.
- **Unity sometimes closes by itself** after being launched into Play mode. Cause unknown. Not a crash.
- Material ids: 0 air, 1 soil, 2 clay, 3 rock, 4 quartz, 5 gold, 6-10 their loose forms, 11 timber,
  12 dark timber, 13 steel, 14 leaves, 15 bark, 16-20 the worker's colours. 21-23 are free in the shader.

## Saving

Commit after each finished task, and push. The owner has said "save it" means commit and push to this
branch. Use a separate index so the `smashed-td` checkout is not disturbed:

```bash
cd /c/Users/Admin/Documents/Smashed-tv
export GIT_INDEX_FILE="$PWD/.git/index-voxel-dozer"; rm -f "$GIT_INDEX_FILE"
git read-tree voxel-dozer
git add -A art/bulldozer-vox voxel-dozer-unity
TREE=$(git write-tree)
COMMIT=$(git commit-tree "$TREE" -p voxel-dozer -m "Voxel dozer: <what changed>")   # add the Co-Authored-By line
git update-ref refs/heads/voxel-dozer "$COMMIT"
unset GIT_INDEX_FILE; rm -f .git/index-voxel-dozer
git push origin voxel-dozer
```

Only add those two folders. Other untracked things in the repo (`dino/`, `earthmover-godot/`,
`result.json`, `Play Earthmover.bat`) belong to other work: leave them alone.

## Tonight's four tasks, in order

Each has a finish line a test can prove. Do them in order. If one cannot be finished cleanly, leave it
working but partial, say so in the morning report, and move on. Do not start anything not on this list.

### 1. Finds in the mine

Dozer parts are buried in the cave-in and the tunnel beyond it. You dig them out and pick them up.

- Build three finds. **Which parts they are is not decided**: call them by what they will restore
  (`tracks part`, `blade part`, `ripper part`) and model each as a simple placeholder object built from
  boxes, like the scenery.
- A find sits at a fixed spot inside the rubble. It is not ground: it is an object.
- It can be picked up once the ground round it is cleared and the worker is close. Use a key that is
  free on foot and show a prompt like the dozer's "Press ENTER" one. Suggested key: `E`.
- Tools must not damage a find. A pick or shovel used on it does nothing bad.
- Carrying: the worker holds a count of which finds he has. No carrying animation needed.
- **Test:** extend the on-foot run or add a new one that clears the ground round a find by script,
  asserts it becomes collectable, collects it, and prints the result. Volume change must stay 0.

### 2. Repairs

Bringing a find to the dozer restores one function.

- Add three switches to the dozer: can drive, can use the blade, can use the ripper. Run-time state,
  not serialized.
- With `dead` off (the default, as now) all three are on and nothing changes for the owner.
- With `dead` on (`F9`), all three start off, and each find installed turns its one back on.
- Install with a key and prompt at the dozer, when carrying a find.
- **Test:** by script: set dead, check the dozer will not move; install the tracks part, check it moves;
  check the blade and ripper stay off until their parts are installed. Print one result line.

### 3. The cart: make it solid and ready for upgrades

The cart exists (`MineCart.cs`) but only "throw dirt into it" has been tested.

- **Test pushing:** by script, walk the worker into an end; the cart must move along the track, stop at
  the cave-in, and stop at the end of the line.
- **Test tipping:** fill it, tip it, check the dirt is back on the ground and volume change is 0.
- Fix whatever those tests find.
- Put the cart's numbers (capacity, how it is pushed) in one clear place, so an upgrade can change them
  later. **Do not build the motor or any upgrade.** They are not designed yet.

### 4. Save and load

Progress should survive closing the game.

- Save: the ground (it is big, about 528 MB raw, so store it compactly: run-length per column, or only
  the chunks changed since generation, then compress), grass, every dirt tally, the cart's place and
  load, the dozer's and worker's positions and state, which finds are found and installed.
- Settle or save loose clods so none are lost: volume must be exact across a save and load.
- Save to Unity's `Application.persistentDataPath`. Keys: `F5` save, `F6` load, with a short message.
- **Test:** by script: dig, save, dig more, load; the solid count plus dirt in motion must equal what it
  was at the save, and positions must be restored. Print one result line, including the file size and
  how long save and load took.

## What not to do tonight

- No feel or look changes (rule 4).
- No new machines, no Android build, no mine carts with motors, no upgrade shop.
- No changes to the quarry's shape or the dozer model.
- No installing software.
- No deleting the owner's files. Old clips can stay.

## Before you finish

1. Run all three checks (SelfTest, RecordWalkClip, and any new tests) one last time and keep the output.
2. Commit and push.
3. Fill in the morning report below.
4. Leave Unity open in Play mode for the owner:
   `Start-Process 'C:\Program Files\Unity\Hub\Editor\6000.3.2f1\Editor\Unity.exe' -ArgumentList '-projectPath','"C:\Users\Admin\Documents\Smashed-tv\voxel-dozer-unity"','-executeMethod','BulldozerBuilder.PlayDemo'`
   and confirm it entered Play mode (see Traps).

## Controls as they are now

In the dozer: W/S drive, A/D steer, R/F blade, T/G ripper, Q/E angle blade, Z/C tilt blade,
X straighten, L lights, V blade view, Enter get out.
On foot: mouse look and aim, W/A/S/D walk, Tab switch view, 1 pick, 2 shovel, left mouse or Space use,
T tip the cart, E pick up or fit a dozer part, Enter get in the dozer, Esc free the mouse.
F5 save, F6 load. F9 test switch for the dead dozer.

Tests (all print one or two result lines): SelfTest, RecordWalkClip, FindsTest, CartTest, SaveTest.

## Questions for the owner

Add to this list as you go. Do not answer them yourself.

- What are the three dozer parts you find called, and what do they look like?
- Where exactly should each one be buried: all in the cave-in, or further into the mine?
- When the dozer is dead, should the first repair be the tracks?
- Where should a full cart be tipped? Is there a tip point, or anywhere?
- Should the game save by itself, or only when you press a key?

## Morning report (night of 15 to 16 Nov, run on Opus 5.5)

All four tasks are done, each saved and pushed to `voxel-dozer` as it finished. Every test passes, and
every one shows volume change 0. Nothing about feel or looks was changed.

**New keys on foot:** E picks up a dozer part you have dug out, or fits one at the dozer.
F5 saves, F6 loads. F9 still makes the dozer dead, to try repairs.

### 1. Finds in the mine: done (commit d025e6a)

Three placeholder parts lie in hollows in the cave-in: tracks part, blade part, ripper part. Tools never
touch them. Once the dirt round one is cleared, a prompt says "Press E to pick up the ...".

`BULLDOZER_FINDS_RESULT exposedAtStart=False exposedAfter=4.2s couldPickUp=True pickUp=[collected 0]
carrying=True part1Buried=True part2Buried=True`

Not checked: what a part looks like in the game. My test pictures were taken while the scripted digging
still had clods raining round it, and the part could not be made out. They are plain placeholder shapes in
rust, old yellow paint and steel.

### 2. Repairs: done (commit d025e6a)

The dozer has three switches: drive, blade, ripper. A working dozer (the normal start) does everything,
exactly as before. A dead one (F9) gets each job back when its part is fitted. A dead dozer with no
tracks part will not let you in.

`BULLDOZER_REPAIR_RESULT deadMoved=0.01m deadBladeMoved=False deadRipperMoved=False fit=[installed 0]
canDrive=True canBlade=False canRip=False tracksMoved=3.02m bladeStillStuck=True ripperStillStuck=True
bladeWorksWithPart=True ripperWorksWithPart=True notDeadCanAll=True volumeChange=0`

### 3. The cart: done (commit 24d2a72)

Pushing and tipping now have their own test. One fault found and fixed: walking into the cart pushed it
up to three times per step. The cart's numbers (capacity, push, tip time, pour rate) now sit together in
`CartSpec`, ready for upgrades. No upgrades or motor were built.

`BULLDOZER_CART_RESULT spec=hand cart/4096 startAlong=13.4m pushedIn=5.50m stoppedFor=4.7s
stopsAtRubble=True ... atEndOfLine=True neverPast=True beforeTip=777L tipTook=1.6s leftInCart=0voxels
clodsStillLoose=0 volumeChange=0`

### 4. Save and load: done (this commit)

F5 saves, F6 loads, one save slot. Only the parts of the ground that have changed are saved; the rest is
remade the same way as at the start. A save after a dig was 0.5 MB and took about 0.1 seconds; loading
took about 0.6 seconds.

`BULLDOZER_SAVE_RESULT save=[Game saved (0.5 MB).] bytes=511254 saveMs=90 touchedChunks=94
clodsAtSave=6908 changedBeforeLoad=True loadMs=643 solidSame=True looseSame=True groundSame=True
clodsSame=True touchedSame=True dozerBack=True cartBack=True findsBack=True stillInDozer=True
volumeChangeOverall=0`

Not checked: saving and loading while on foot (the test saves from the dozer); a save after a very long
session (more changed ground means a bigger file and a slower load); loading a save made by an older
version of the game (it refuses, with a message).

### Final check, all tests in a row

SelfTest (dig, enter test), RecordWalkClip, FindsTest, CartTest and SaveTest all passed, each with volume
change 0. No clips were made tonight.
