# Voxel Arena

A small arena shooter on the Digger Game's voxel ground. Rockets blow real craters in it.
It is a separate Unity project (Unity 6000.3.2f1, built-in pipeline). It started as a copy of `voxel-dozer-unity/`,
and nothing in it touches the Digger Game or its save. Its product name is `voxel-arena`, so its files go in
`AppData/LocalLow/DefaultCompany/voxel-arena/`.

## What's in it (first slice)
- **The arena:** 32 x 32 m of diggable ground: 0.5 m of soil over 1.5 m of clay over rock, flat, with three low
  mounds. Walls 3 m high, with a 3 m door in the middle of each side. The ground takes about 34 MB.
- **You:** the Digger Game's worker with a gun, 3 health, running at 6.5 m/s (Smashed's speed).
- **Rifle:** 8 shots a second, instant hit with a tracer. One hit kills a grunt. A hit on the ground chips out a
  15 cm bit with a puff of dust.
- **Rocket:** one every 0.8 s, 25 m/s, with a smoke trail. It blows a 1.2 m crater and throws the dirt out as clods
  that land and settle. No dirt is ever made or lost. It kills every grunt within 2.5 m. Rockets don't hurt you.
- **Grunts:** Smashed's grunt, with the same look, colours, two walk frames, speeds and wave sizes (25, then 31, ...).
  They come through the doors in bursts and run at you over the ground, down into craters and out again. They
  burst into gibs.
- **Getting touched:** costs 1 health. As in Smashed, the grunts close by die with it and you are safe for 2 s.
  At 0 health the round starts again on fresh ground.

## Controls
| | Keyboard and mouse | Pad |
|---|---|---|
| Switch view (over the shoulder / from above) | Tab | Back |
| Move | W A S D | left stick |
| Aim | mouse | right stick |
| Rifle | left mouse | right trigger |
| Rocket | right mouse | left trigger |
| Free the mouse | Esc (click to take it back) | |

Over the shoulder, W walks the way you look and the cross is the aim. From above, W is always up the screen and
you shoot at the mouse.

## Running it
- In the editor: open the project, then **Tools > Arena > Play**. **Tools > Arena > Rebuild scene** remakes the scene.
- The Windows game: `-executeMethod ArenaBuilder.BuildWindows` makes `Builds/VoxelArena/VoxelArena.exe`.

## Tests
Close any Unity that has this project open first. Then run:

```
"C:/Program Files/Unity/Hub/Editor/6000.3.2f1/Editor/Unity.exe" -projectPath <full path to voxel-arena-unity> -executeMethod ArenaBuilder.Test -logFile Logs/test.log
```

It exits 0 when every check passes and 1 when any fails. Each check is logged as `ARENA_CHECK <name> ok|FAIL`,
and the run ends with `ARENA_TEST_RESULT` or `ARENA_TEST_FAILED`. The checks:
- the ground is under 100 MB;
- a rocket blows a crater over half a metre deep, the dirt flies as clods, and the dirt volume is exactly the same
  afterwards (`SolidCount + LoadVoxels`, and a full recount);
- one bullet kills a grunt and it bursts into gibs;
- the rifle fires about 8 a second and chips the ground, with the volume still exact;
- a grunt runs down into a crater and out again to reach you;
- a real wave comes through the doors and reaches you, costing 1 health, and the round restarts at 0 health;
- frame time with 30 grunts on the field stays under 25 ms on average.

`-executeMethod ArenaBuilder.RecordClip` films a captioned clip with sound into `Logs/clip`.

## Sounds
`rifle`, `rocket_launch`, `explosion`, `grunt_die` and `hurt` are made in code (`SoundBank.cs`). To use a recorded
one instead, drop a file with that name into `Assets/Resources/Sounds/`, for example `explosion.wav`.

## Code
`Assets/Arena/Scripts`:
- `VoxelWorld*.cs`, `HeavyFX`, `GameAudio`, `SoundBank`, `Pad`, `Ui`, `FollowCamera`: copies of the Digger Game's,
  cut down for the arena.
- `ArenaGame`: waves, health, HUD.
- `ArenaPlayer`: you.
- `Weapons`: the rifle and rockets.
- `Grunts`, `Gibs`, `VoxModel`: Smashed's grunt and gibs.

`Assets/Arena/Editor/ArenaBuilder.cs` builds the scene and runs the tests and the clip.
