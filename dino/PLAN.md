# Dino game: the plan

A violent pixel dinosaur game. A separate Godot project (this `dino/` folder); the main Smashed TV game in
`godot/` is not touched. Built one small step at a time, and nothing gets decided without talking it through first.

## Decided with the owner (24 Oct)

- **You play a dinosaur.** You bite **real chunks** out of other dinosaurs, **at the spot you aim at**, so there
  are tactical spots to go for.
- **Levelling up:** eating earns XP. At each level you **choose** what to upgrade: bite size (bigger chunks), speed,
  attack speed, and so on.
- **Evolving:** at certain levels you become a different (bigger) dinosaur, and so on from there.
- **View:** side-on 2D pixel art (nearest filtering, never blurred).
- **Aiming:** the mouse points at the spot on the prey, and a click bites (your dino lunges at that spot).
- **Engine:** Godot 4.6.2 (the one in Downloads), GDScript.
- **Art:** placeholder pixel dinosaurs drawn in code for now. Real art comes later, once the bite feels right
  (the owner generates it from a spec).

## Decided with the owner (25 Oct): Option B, "The Territory"

- **XP from kills and from eating.** Level up and choose: bite size, speed, or attack speed.
- **The higher your level, the more you get attacked**, so you have less time to eat.
- **A run is a long procedurally generated map** (different every run) that you roam freely. Nothing scrolls,
  but the danger builds, so you keep moving. The far end leads to the next area (harder). Obstacles are on the way.
- Considered and not picked: A (auto-scroll chase: frantic, runner-like) and C (separate stages with upgrades
  between them). Middle ground kept in mind: B with a slow push from behind, if camping turns out to be a problem.

## Steps

1. **One bite that feels good** (now). You (one dino) and one prey dino in an empty side-on area. The prey runs
   but can't hurt you. Aim, bite, and a chunk comes out of exactly that spot (a hole in the sprite, pixels and
   blood flying). Enough chunks and it dies.
2. Levels and the upgrade choice: bite size, speed, attack speed.
3. Weak spots that do something (which spots, and what each does, is to be decided with the owner).
4. More prey, then prey that fights back.
5. Evolving into the next dinosaur.

## Step 1: built (24 Oct, overnight)

**Play it:** double-click `Play Dino.bat` in the repo's top folder (it uses Godot 4.6.2 from Downloads).
A/D or arrows move, W / Space jump, aim with the mouse, left click bites, F3 shows the zones, R starts over.

What's in it:
- **The bite:** click and your dino lunges, the neck shoots out, and the jaws snap at the spot you aimed at. It
  remembers the spot on the prey's body, so a running prey still gets bitten where you clicked. Past your reach it
  snaps at the nearest point it can reach. The aim marker is red on a spot you can bite, white in reach, and grey
  out of reach (with a dot where you'd actually bite). The zone name shows under the marker.
- **Chunks:** a jagged, tooth-notched hole is torn out of the sprite exactly there. The new edge goes dark red,
  with flesh behind it and the odd fleck of bone. The bitten pixels are held in your mouth for a moment, then
  swallowed. Bite clean through something (a tail, a leg at the hip, the neck) and it **falls off whole**,
  tumbling and bleeding.
- **Gore and feel:** pixels and blood spray out and stain the ground for good. Wounds keep dripping (more wounds,
  more blood). There's a white hit-flash, a short hit-stop, screen shake, and synthesised crunch, tear, snap,
  squawk, swallow, rip and thud sounds.
- **The prey:** wanders, and runs when you get close or bite it. It can't fight back. It dies when it has lost
  half of itself or most of its head, slumps over and bleeds out, and stays there (you can keep biting it). The
  next one walks in a couple of seconds later. Up to 3 bodies stay.
- **Tests:** `godot --headless --path dino --script res://tests/test_bite.gd`: 11 checks (bites take the right
  zone, the head comes off when the neck is bitten through, a leg comes off at the hip, the bot plays 1500 frames).
  All pass. `-- --shots=<folder>` saves screenshots and close-ups while a bot plays.

Placeholders I had to pick (all easy to change, none decided):
- **Death rule:** dies under 50% of its body or 35% of its head.
- **Numbers:** bite size 4.5 px radius, a bite every 0.42 s, reach 42 px, walk 75 px/s, jump. The prey wanders
  at 22 and runs at 68 (slower than you, so you can catch it).
- **The art:** you're a green raptor-ish shape and the prey is a long-necked tan shape on four legs. Placeholders.
- **Dinosaurs pass through each other** (no bumping into each other).
- A KILLS / CHUNKS counter at the top, in place of XP for now.

## Added after playing step 1 (owner's asks, 25 Oct)

- **Eat it completely, then grow:** once a prey is dead, keep biting. When there's under 5% of it left, the rest
  goes down in one gulp, the body is gone, and you **grow by 10%** (up to 2x; your reach and lunge grow with you).
  Pieces lying about (a bitten-off leg, tail or head) go down whole in one bite too. The top shows
  KILLS / EATEN / SIZE.
- **The bite lands where you click:** the teeth now meet exactly on the spot (checked by a test, 0 px off on head,
  neck, body, tail and legs). The neck visibly stretches out to it. The body lunges (or leaps, for a high spot, or
  steps back, for one right under your nose) so more spots are in range. The aim marker now predicts exactly
  where the bite will land: red or white means it lands right there, and grey means out of range (the dot shows
  where it would land instead). If the prey moves during the tiny wind-up, the bite follows the spot on its body
  (you clicked its neck, you get its neck).
- Placeholders: grow 10% per meal, max 2x, "eaten" under 5% left. Biting size doesn't grow with you (bite size
  is meant to be a level-up choice).

## Option B, first version: built (25 Oct)

- **Runs and areas:** each run gets a seed (shown top right; `-- --seed=<n>` replays one). Each area is generated
  from it: its length (longer each area), rocks and logs along the way, herds, and a look that cycles through
  jungle, badlands, swamp and volcano. A sign at the far end takes you to the next area, keeping your level, size
  and health.
- **Obstacles:** you can't walk through rocks or logs, but you can jump onto and over them. Prey turn back at them,
  and hunters jump them.
- **XP and levels:** kill prey +10, kill a hunter +25, each mouthful of a body +2, eating a whole body +15. The
  next level needs 30, then 50, 70... Each level pauses for **LEVEL UP! CHOOSE ONE**: bite size (+1), speed
  (+12%) or attack speed (15% quicker). Click a card or press 1 / 2 / 3.
- **Health:** a red bar top left. Eating heals (+3 a mouthful, +15 for a whole body). At zero, **YOU WERE EATEN**:
  the run's stats, then click or R for a new run on a new map.
- **Hunters:** red meat-eaters that walk in from off screen, close in, wind up (jaw open, flashing), and lunge.
  Their bite takes 14 health and knocks you back. Bite them like anything else: each bite staggers them, and
  dead, they're food. **The higher your level (and the further the area), the sooner and more of them come**:
  one every 14 s at level 1 in area 1, every 7 s at level 6, up to 6 at once.
- **Parts fall off where they hang:** bite away the hip and the leg drops; bite through the top of the neck and
  a hunter's head drops.
- Tests: 26 checks, all passing (levels, hunters biting and dying, the same seed giving the same area, rocks
  blocking and being jumped onto, the exit, game over and a new run). `tests/shot_screens.gd` photographs the
  level-up, an area of each look and the end of a run.

All the numbers above are placeholders to tune by playing.

## Questions for the morning

1. How does the bite feel? Too small, too slow, reach too short or too long?
2. Should any spot do something special yet (legs slow it down, neck is a quick kill...), or not until step 3?
3. Is the death rule right (half its body or most of its head)?
4. Ready for step 2 (levels and choosing upgrades)? If so: XP per chunk or per kill, and how many levels before
   the first evolution?

## Still to decide (ask, don't guess)

- Which spots matter, and what biting each one does (e.g. legs slow it?).
- The dinosaurs: which one you start as, the evolution order, and which ones are prey.
- How XP and levels work: XP per chunk or per kill, and the level-up numbers.
- The world: one long scrolling area, arenas, or levels.
- The name.
