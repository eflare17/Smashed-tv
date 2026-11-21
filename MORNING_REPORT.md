# Digger Game: overnight report (22 Nov 2026)

Good morning. This is what happened overnight on the Digger Game, in plain words.

**The short version:** the automatic cart, the bigger cart, a goal with an ending, first-time tips, two
new sounds and a price tune-up are all built, each in its own commit, each with its own test. All the new
tests pass. Every older test still passes except one that was already failing before I started (details
below). There's a new Windows build in its own folder. Nothing is pushed and nothing is merged into
`voxel-dozer`: that's your call.

- Branch: `claude/digger-overnight-694b14` (in the worktree `.claude/worktrees/voxel-mountain-road-02ab25`)
- Starting point, tagged: `before-overnight-22nov` (the tip of `voxel-dozer` when I started, `8b6f093`)
- Your save was backed up before any test ran (see "Your save" below). Every test put it back afterwards.

---

## What was built, step by step

| Step | What | Commit |
|---|---|---|
| 1 | Checked the project opens, compiles and its tests pass. Synced the Unity project's copy of the scripts. | `8f31c98` |
| 2 | **Automatic cart** | `4a4a938` |
| 3 | **Bigger cart** | `a351636` |
| 4 | **A goal and an ending** | `de36efb` |
| 5 | **First-time tips** | `45d9e0f` |
| 6 | **Sound**: gold sparkle, cart buffer clunk | `148ee9e` |
| 7 | **Price and pace tuning** (on its own, so it can be undone alone) | `9f0f866` |
| 8 | Tested everything, made the Windows build, wrote this report | (this commit) |

### 1. Checking the project
It opened, compiled and built. 20 of the 21 tests I ran passed. **Already broken before tonight:**
- **TreeTest** fails one check, the upgrade tree at UI size 125% (`uiSize125Scale`). The polish session's
  notes already mention this. I didn't touch it.
- **F8 does two things at once**: in the upgrades it's the test key (+10,000 coins and 50 L of gold), and it
  also turns on trailer mode, which stops the game saving. I didn't change it (not tonight's job), but
  watch out: pressing F8 in a real game means that session won't be saved.
- The Unity project's copy of the scripts was behind the real scripts (`TrailerMode.cs` and `TreeFelling.cs`
  were missing from it). Step 1's commit just brings it up to date; nothing in it is new.

### 2. Automatic cart
The last thing in the Hauling column. Once you own it, **G** (d-pad left on the pad), anywhere within 12 m
of the cart, sends it off by itself: it drives out to the hopper, tips, waits until it's empty and drives
back to exactly where you sent it from. You keep digging meanwhile.
- Price: 1,200 coins + 20 L of gold.
- Money and gold are counted by the hopper, exactly as when you tip by hand (dirt sold, gold kept).
- While it's out, you can't grab it, ride it or tip it by hand (it tells you so).
- Selling it back while it's out stops it where it is. A save made mid-trip loads with the cart standing
  where it was, still full (the trip itself isn't saved, on purpose: simpler and can't go wrong).
- The motor sound plays while it drives itself.
- The help (H) and CONTROLLER.md show the new key.
- Test: `AutoCartTest`.

### 3. Bigger cart
The other "coming" Hauling item is now real: **Bigger cart**, 900 coins (no gold, it's a level, not a new
machine), after Motor cart 3 and before the Automatic cart. The tub holds 2,000 L instead of 1,500 L, and
you can see it: an extra plank all round the top on steel corner posts. Sold back, it's 1,500 L again.
Test: `BigCartTest`.

### 4. A goal and an ending
See "Design choices" below for every decision. In short: two new goals (restore Dad's dozer; finish the
mountain road), and when both are done a short ending plays once, then you keep playing.
Test: `EndingTest`.

### 5. First-time tips
Eight short tips, each shown once, the first time it's useful, in a small box under the goal. See
"Design choices" for the list and the wording rules. Test: `HintsTest`.

### 6. Sound and feel
Most of what's on the list was already done by the polish session (pick sounds per material, shovel,
cart wheels, tip rumble, ka-ching, upgrade and goal sounds). I only added what was missing:
- a **gold sparkle**: a quick rising shimmer over a soft bell when gold goes down the hopper into your gold store;
- a **buffer clunk** when a motor cart driven fast stops dead at the end of the rails or against rubble.
Both are made in code like the other made-up sounds. **I couldn't listen to them**, so they may want
tweaking or swapping for an ElevenLabs recording (put `gold.wav` in `Assets/Resources/Sounds/` and it's used instead).

### 7. Price and pace tuning
I wrote a small model of when a player would buy each upgrade (`art/bulldozer-vox/pace_model.py`). It
used real sizes from the game (the first cave-in is about 22 m³, the second about 33 m³) and guesses for
how fast a person really digs. Treat the minutes as rough; the shape is what matters.

**What it found:** a long dead spot. Every upgrade after Cart 2 needed gold, and gold only shows up past
the second cave-in. So after about 8 minutes, you'd dig for around **19 minutes with nothing to buy**.

**What I changed** (all in `Upgrades.cs`, one commit):

| Upgrade | Before | Now |
|---|---|---|
| Motor cart | 800 coins + 10 L gold | **800 coins, no gold** |
| Pick 2 / 3 / 4 / 5 | 50 / 80 / 128 / 205 | 60 / 110 / 190 / 320 |
| Shovel 3 / 4 / 5 / 6 | 64 / 102 / 164 / 262 | 75 / 135 / 230 / 380 |
| Cart 2 | 300 | 450 |
| Backpack 7 / 8 | 1,573 / 2,516 | 1,400 / 1,900 |

The first upgrade (Shovel 2) is still 40 coins. In the model, the longest wait is now about 4 minutes,
and the gaps grow steadily from about 20 seconds to about 4 minutes, which is the "each one takes a bit
longer" feel from GAMEPLAN.md. **The one rule this bends:** GAMEPLAN says new machines cost gold. The motor
cart now doesn't (the jackhammer, backpack, Dingo and automatic cart still do). If you'd rather keep the rule,
another fix is to put a little gold in the first or second cave-in, but that changes the mine, so I left it for you.

---

## Design choices I made (steps 4 and 5)

You hadn't designed these, so here's every choice, so you can change any of them.

### The goal and the ending (step 4)
1. **The goal of the game** is: restore Dad's dozer, and finish the mountain road. Digging, earning and
   finding gold are what get you there, through the goals you already have.
2. **"Restore Dad's dozer"** means fitting all three buried parts (tracks, blade, ripper part). It's a new
   goal straight after "Clear all three cave-ins" (since the parts are in the cave-ins). Bonus 300 coins.
   (The dozer still drives from the start, as you asked earlier; the parts are a goal, not a lock.)
3. **"Finish the mountain road: every stretch ticked"** (all 15) is a new last goal, after "Push 50 m³".
   Bonus 250 coins, on top of the road's own 500.
4. **The ending plays when both are done**, a few seconds later, **once only**. It's remembered in the save.
   An older save that has already done both gets it once, shortly after loading.
5. **What the ending is** (about 20 seconds):
   - black bars slide in and every panel hides;
   - the camera flies up the finished road from the bottom to the top, 12 m above it (14 seconds), with two
     captions: "The mountain road is finished." then "Dad's dozer is working again.";
   - it rises high above the trees and turns to look back down the whole road;
   - a card: **"The mine and the road are done"**, with: dirt sold at the hopper (m³), dirt pushed by the
     dozer (m³), gold found (litres), coins earned, goals done;
   - a **Keep playing** button (or Enter, Space, E, A on the pad). Everything goes back as it was.
6. While it plays, the world keeps going; you and the dozer are just held still.
7. **The stats are counted from now on.** "Dirt sold" and "gold found" are new counts, so an old save starts
   them at zero. (Coins earned and dirt pushed were already counted.)
8. No music or voice: just the existing "goal" chime at the start.
9. Pictures from the test: `voxel-dozer-unity/Logs/ending_fly1.png`, `ending_fly2.png`,
   `ending_caption_screen.png`, `ending_card_screen.png` (in the worktree).

### The first-time tips (step 5)
1. **Where:** a small dark box with a blue "TIP" label, under the goal box at the top. If the help (H) is
   showing, it moves right so it doesn't cover it.
2. **When:** each one the first time it's useful, about 9 seconds (gold 11, road 12), one at a time; a
   new one waits until the current one has had at least 4 seconds.
3. **Once only, per computer** (not per save): a tip you've read doesn't come back in a new game.
4. Hidden in trailer mode, the prologue, the ending, the pause menu and the upgrade tree.
5. With a pad in use, the tips name the pad buttons instead of the keys.
6. **The eight tips, in order:**
   - *In the dozer:* Enter gets out, the mine is dug on foot.
   - *On foot:* aim at the rubble and hold left mouse; 1 is the pick, 2 the shovel.
   - *Dirt on the shovel:* use it again to throw; near the cart it lands in the cart; E at an end and W to push.
   - *Cart half full (or at the dump):* the hopper; E tips; soil, clay and rock sell on the spot.
   - *Enough coins for an upgrade:* U opens the tree.
   - *First gold in the store:* gold is kept, not sold; sell it at the shed or keep it for machines.
   - *A dozer part uncovered:* E picks it up, carry it to the dozer, E fits it; all three restore it.
   - *In the dozer near the road:* the pegs say CUT or FILL; green is on grade; B for blade auto, again for Grade.
7. There's no "show tips again" button yet. (To see them again: delete the `hint.*` keys, or I can add a
   menu button.)

---

## Try this (a checklist for each step)

Start the new build (see the next section). F8 gives coins and gold, but remember it also starts trailer
mode, which stops saving, so use it in a throwaway session.

**Automatic cart**
- [ ] U, Hauling: Cart 2 → Motor cart → Motor cart 2 → 3 → Bigger cart → Automatic cart.
- [ ] Fill the cart in the mine, step back, press **G**. It should drive out, tip, and come back to the same spot.
- [ ] Watch the coins go up when it tips. Try E on it while it's out (it should refuse).
- [ ] Sell back the Automatic cart while the cart is out: it should stop.

**Bigger cart**
- [ ] After buying it, the cart has an extra plank round the top and the cart bar says "of 2000 L".

**Goal and ending**
- [ ] Look at the goal box: there's a new "restore Dad's old dozer" goal after the cave-ins, and the road goal last.
- [ ] To see the ending without playing it all: it needs both goals done. (A quick way needs a test key; tell me if you want one.)

**Tips**
- [ ] Start a **New game**: you should get the dozer tip, then the digging tip when you get out, then the
      cart tip when you have dirt on the shovel, and so on. Each only once.

**Sound**
- [ ] Tip a load with gold in it: a sparkle as it goes into the gold store.
- [ ] Ride the motor cart flat out into the end of the rails: a clunk.

**Prices**
- [ ] Open U and check the new prices (Motor cart: no gold).

---

## How to play the new build

The new build is in its own folder, next to your usual one (which wasn't touched):

```
C:\Users\Admin\Documents\Smashed-tv\voxel-dozer-unity\Builds\DiggerGameOvernight\DiggerGame.exe
```

Double-click it, or run it from PowerShell:

```powershell
& "C:\Users\Admin\Documents\Smashed-tv\voxel-dozer-unity\Builds\DiggerGameOvernight\DiggerGame.exe"
```

It carries on from your save, like your normal build (read "Your save" first). I started it once in
trailer mode (which never loads or saves) and it ran for 40 seconds with no errors. I haven't played it by hand.

## Test results (the final run, all on tonight's code)

26 of 27 tests pass: SelfTest, CartTest, MotorCartTest, **AutoCartTest**, **BigCartTest**, UpgradeTest, DumpTest,
SaveTest, GoalsTest, **EndingTest**, **HintsTest**, HudTest, SoundTest, TrailerTest (trailer mode), MenuTest,
PadTest (controller), BackpackTest, JackTest, FindsTest, AutosaveTest (new game, carry on), RoadPileTest,
TreeFellTest, MountainRoadTest (the road job), RoadOldSaveTest (loads your real save, read only),
ResetGroundTest, DingoTest. **TreeTest** fails the same one check it failed before tonight (UI size 125%).

---

## Your save

- Backed up before anything ran: `%USERPROFILE%\AppData\LocalLow\DefaultCompany\voxel-dozer-unity\backup-overnight-22nov\`
  (`voxel-dozer-save-2026-11-22.bin` and the `.old` one). It's also in my scratchpad.
- Tests that write the save (SaveTest, AutosaveTest) had it copied back after every run. Checked: it's the
  same file it was at the start.
- **The new build uses the same save as your normal game.** That's fine both ways: the new build reads your
  save, and your old build can read a save the new one wrote (it just ignores the new ending section, and
  treats the bigger/automatic cart as Motor cart 3). But if you want to be safe, copy the save first.

---

## How to roll back

All of these are run in the folder `C:\Users\Admin\Documents\Smashed-tv`. None of them delete anything
from history; they just add an "undo" commit or move a branch. Nothing has been merged, so the simplest
rollback of all is: **don't merge this branch**, and `voxel-dozer` is exactly as you left it.

**The whole night** (if you've merged it and want it gone):
```powershell
git revert --no-edit before-overnight-22nov..claude/digger-overnight-694b14
```
(or, before merging: just don't merge, or delete the branch).

**One step** (for example the tips), using its commit from the table above:
```powershell
git revert --no-edit 45d9e0f
```
The steps build on each other in a few places, so revert later steps first if Git complains: the Bigger
cart (3) moved the Automatic cart's level, and the ending (4) and tips (5) both add a line to `SiteProps.cs`.

**Just the prices:**
```powershell
git revert --no-edit 9f0f866
```

After any revert, the game needs re-exporting into Unity and a new build, which I can do.

---

## Skipped, and why

- **Multiplayer**: deferred tonight, as agreed.
- **Phone check**: needs an Android install that you have to OK.
- **Listening to the new sounds and playing the ending by hand**: I can only check them with tests and pictures.
- **The F8 clash and the TreeTest failure**: both were there before tonight and aren't part of the plan;
  listed above so you know.

## Other notes

- The polish session committed one thing to `voxel-dozer` tonight (trailer-mode shots, `2475c57`). It doesn't
  touch the same code as tonight's work, so a merge should be straightforward, but it will need a merge.
- The tests (all in `BulldozerBuilder`): new ones are `AutoCartTest`, `BigCartTest`, `EndingTest`, `HintsTest`.
