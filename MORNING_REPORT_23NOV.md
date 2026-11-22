# Digger Game: overnight report (23 Nov 2026)

Good morning. This is what happened overnight, in plain words.

**The short version:** all six steps are done (step 6, a second sweep of everything mixed together, was added during the night). There's a creek and rain, ice and a freeze gun, gas that
explodes, and the Voxel Arena's grunt as the first enemy. Each step has its own commit and its own test, and
every new test passes. The older tests still pass too (the only failure is the old TreeTest one that was
already failing before). There's a new Windows build in its own folder. **Nothing is merged into
`voxel-dozer`**: say "merge" when you're happy.

- **The build:** `voxel-dozer-unity/Builds/DiggerGameOvernight2/DiggerGame.exe`, in the worktree
  `.claude/worktrees/voxel-blade-auto-e7e360`. Your own `Builds/DiggerGame` wasn't touched.
- Branch: `claude/digger-overnight-23nov-c484e6` (pushed).
- Starting point, tagged: `before-overnight-23nov` (the tip of `voxel-dozer`, `5d83d52`).
- Your save was backed up before any test ran, and put back after every test.

---

## How to try each thing

| What | Where / keys |
|---|---|
| **Creek** | Look at the face just left of the mine door. Water seeps out 2 m up, falls down the face and spreads at the foot, and some runs in at the door. Dig a hole or a channel near it and the water runs in. Fill the hole and the water is pushed out. |
| **Rain** | About 3 minutes into a game, then every 5 to 9 minutes, for a minute. It says "Rain!". |
| **Freeze gun** | **5** on foot (the bumpers reach it too). Shoot water and it turns to ice. Walk on it. Break it with the pick or jackhammer (1) or the rifle (4). |
| **Cold gas (blue)** | Pockets in the walls of the deep tunnel. Dig into one and blue gas sinks out and freezes any water it touches. |
| **Green gas** | Pockets in the walls of the deep tunnel. Dig into one and a green haze rises to the roof. Shoot it (4) or hit it with the jackhammer: boom. |
| **Grunts** | They come out of the deep tunnel once there's a way through. The rifle (4) kills them. Off switch: **Esc > Settings > Enemies**. |
| **Water numbers** | F3 (debug) shows the water, gas and ice, and how long the water takes each step. |

---

## What each step does

| Step | What | Commit | Test |
|---|---|---|---|
| 1 | Bug and polish sweep | `63fb7ce`, `1b1b507` | all 34 older tests |
| 2 | Water: creek and rain | `a406503` | `WaterTest` |
| 3 | Ice: freeze gun and cold gas | `a52c0f4` | `IceTest` |
| 4 | Gas that explodes | `9d393b1` | `GasTest` |
| 5 | First enemy: the grunt | `5007570` | `GruntTest` |
| 6 | Second sweep: everything mixed, and the water tied to Quality | `a4a5cc0` | `MixTest` + all 34 older tests |

### 1. Bug and polish sweep
I played the whole game through by test, start to finish (34 tests: dig, cart, dump, money, upgrades, gold,
pockets, jackhammer, backpack, all the carts, Dingo, road job, goals, ending, hints, save, menu, pad, sound).
Everything worked. Small fixes:
- **F8 no longer starts trailer mode.** F8 is the free-coins test key, and it was also quietly starting trailer
  mode, which stops the game saving. Trailer mode mid-game is now **F7**.
- The **Mountain Road panel** no longer pops up deep inside the mine (the road runs overhead there).
- The opening message now says **H shows every control**.
- The help (H) now explains **E on loose gold** (into your pockets) and **E at the gold shed**.
- "Gold lost" tells pad players to use the d-pad, not Shift+wheel.

### 2. Water
- The creek is always running. The water goes where the ground takes it: down the face, across the floor, into
  holes and channels, and in at the mine door.
- It can't flood the site. The creek has a set flow, the ground soaks water away slowly, and there's a cap on
  how much water there can be at once (about 14 cubic metres). Dig a drain to lead it off, or fill a hole to
  push it out.
- Water is kept completely apart from the dirt, so the dirt's books stay exact (the tests check this every time).
- Speed: it only works where there's water or gas, using all the CPU cores. The worst step in the tests was
  about 3 ms, in heavy rain.

### 3. Ice
- Ice is solid. You can stand on it. The pick, jackhammer or rifle breaks it into loose bits that melt back to
  water after about 7 seconds. Left alone, ice melts back slowly (about a minute and a half).
- **Freeze gun (5):** free, 4 shots a second. It freezes water along the shot and where it lands.
- **Cold-gas pockets:** three, in the deep tunnel walls. Cold gas sinks and freezes water it touches.

### 4. Gas that explodes
- **Green-gas pockets:** four, in the deep tunnel walls. The haze rises, fills the tunnel from the roof down,
  and slowly thins away.
- A rifle shot through the haze, or a jackhammer blow in it, sets it off. You get a crater with the dirt thrown
  out as clods (every bit kept), a flash, a boom and a shake, and the haze nearby goes off after it. It never
  hurts you.

### 5. The grunt
- It's the Voxel Arena's 1.5 m grunt, with the same look, the same walk and the same burst into little cubes.
  I copied it over without merging that branch.
- One comes out of the deep tunnel now and then: the first after about 1.5 minutes, then about every
  35 seconds. There are never more than 3 at once. They only come when there's a way through.
- The rifle kills one with a shot. A gas blast kills any it reaches. A machine you're driving squashes them.
- If one reaches you, it knocks you back and you drop 5 coins (or nothing if you have none). You never die.
- **Esc > Settings > Enemies (grunts)** turns them on or off, and it remembers your choice.

### 6. Second sweep: the new things mixed together
I played it through again by test, with everything on, looking at how the new things mix:

| Mix | Result |
|---|---|
| A grunt walking through a puddle | fine, it wades straight through |
| Gas going off next to ice | the blast breaks the ice into bits (they melt), dirt kept |
| A grunt caught in a blast | it dies (bursts into cubes) |
| Water at the dump, round the cart, under the Dingo | pays nothing, nothing goes in the cart, the Dingo doesn't move |
| The dozer driving through a puddle | fine, dirt kept |
| Save and load with water, ice, gas, an open pocket and a grunt about | loads clean: dry, no grunts, the pocket stays used up, the dirt exactly the same |
| A flood well over the cap (about 10,000 cells), with rain | about 6 ms a frame on average, the water step peaks around 8 ms |

Fixes from this sweep:
- **Ice could stop melting** (and a still pool stop soaking away) once nothing nearby moved. Fixed: anywhere
  with water, ice or gas keeps working.
- **No rain while a film plays** (trailer mode, the ending, the opening).
- **Grunts stand still during the ending**, and don't come out then.
- **Riding the motor cart runs grunts down**, like the dozer and the Dingo do.
- **Holding the cart:** a grunt knocks you off the handle as well as back.
- In a flood, at most 48 new patches of water grid are made per step, so it doesn't hitch.

**Water and gas follow the Quality setting** (Esc > Settings > Quality). There's no new menu item:

| Quality | Water works within | Water cap | Rain lands within |
|---|---|---|---|
| Low | 22 m of you | 3,500 cells (about 7 m3) | 7 m |
| Medium | 48 m of you | 7,000 cells (about 14 m3), the same as before | 10 m |
| High | 70 m of you | 12,000 cells | 13 m |
| Ultra | the whole site | 20,000 cells | 16 m |

Water further away than that just waits, still, until you come back. High and Ultra also keep twice as much
water grid in memory (64 MB instead of 32 MB). That part only changes when the game starts, so restart after
changing Quality to get it.

---

## Guesses I made (all easy to change)

- **Where the creek is:** water seeps out of the face just left of the mine door, 2 m up. My first try was on
  the floor, but the parked Dingo and the rock spires hid it. My second was on the hilltop, but you couldn't see
  it from below. Now it falls down the face, so you can see it.
- **The creek's size and the soaking:** the creek gives about 35 small cells of water a second, and the
  ground soaks a little up all the time. In practice it makes a pool about 2 x 4 m at the foot of the face.
- **Rain:** first at about 3 minutes, then every 5 to 9 minutes, for 60 seconds, landing within 10 m of you.
  The creek runs twice as hard while it rains.
- **Water isn't saved.** A loaded game starts dry, and gas pockets you've already dug open stay used up.
- **Water grid size:** 12.5 cm cells, so a thin puddle can look a bit blocky.
- **The dozer, carts and loose dirt don't feel water or ice.** Only you (and the grunts) can stand on ice.
- **Cold gas sinks, green gas rises.** You said green drifts up. Cold sinking is my guess (cold air sinks), and
  it means it reaches puddles on the floor.
- **Where the pockets are:** 4 green and 3 blue, set into the deep tunnel walls between 14 m and 31 m in, at
  about head height (where the gold seam is). Nothing shows them before you break in. A message tells you
  what you've found.
- **Blast size:** about 1 to 2.5 m across, bigger with more gas. Blasts that chain through the haze are
  limited so a big cloud can't go on forever.
- **Freeze gun:** free from the start, like the rifle. It holds no ammo and doesn't affect grunts.
- **Grunts:** 1.5 m/s (you walk at 2.6), 5 coins when one gets you, then it backs off for 1.6 s. They're
  **on by default**. They don't come while the tunnel is still blocked by the cave-ins. Once you're inside, they
  come from deeper than you, but only if there's at least 6 m of open tunnel ahead of you. While you're outside,
  they only come once the whole tunnel is dug through.

## What isn't done / not checked

- **Not played by hand.** Everything was checked by the tests, and the build was started for 40 seconds with
  no errors. Have a look at how the water and the green haze look in the real game, especially in the dark
  tunnel. The haze may need to be stronger or fainter.
- **Grunt spawning in a real game isn't tested end to end.** The test checks that they don't come while the tunnel
  is blocked, and checks everything a grunt does once it's out. It doesn't dig the whole tunnel through and
  wait for one to walk out.
- No pump (as you said).
- The water isn't in the multiplayer plan yet (there's no multiplayer yet anyway).
- Old: TreeTest still fails its UI-size-125% check, as before.
- The Medium area (48 m) is new: before, all water everywhere was worked on. In normal play near the mine it
  makes no difference.

---

## Rollback

Everything is on the branch. Nothing touched `voxel-dozer`, so not merging is a full rollback. If you merge
and then want something out:

```
git revert 5007570
```
takes out just the grunts (do it after reverting step 6, which touches the grunts too). Or switch them off in Settings.

```
git revert a4a5cc0 5007570 9d393b1 a52c0f4 a406503
```
takes out step 6, the grunts, gas, ice and water (they share code, so take them out together).

```
git reset --hard before-overnight-23nov
```
on `voxel-dozer` puts it back to exactly how it was before tonight (only do this if nothing else has gone onto it
since).
