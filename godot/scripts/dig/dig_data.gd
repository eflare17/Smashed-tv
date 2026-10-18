extends RefCounted
## Every number of the yard's digging and ploughing (PLAN.md "Later: digging", levels 2 and 3), in HTML units and game
## hours. Owned by the digging part (scripts/dig/).

## The depth grid: square cells CELL units across over the yard, its corner heights stored per vertex.
## The region covers both yard areas (calls.lobbyAreas 5 and 6) with the house inside it (never diggable).
const CELL := 8.0
const X0 := 0.0
const Y0 := 48.0
const NX := 214                     # cells across (to x 1712)
const NY := 230                     # cells down (to y 1888)
## The earth under it (level 3, smooth caves): samples every CELL from ZMIN (bedrock, about 8 m down) up to ZMAX
## (DigVolume, drawn by DigMesher).
const ZMIN := -320.0
const ZMAX := 24.0
## The flat yard meshes: CHUNK x CHUNK cells each.
const CHUNK := 32
## The shovel (level 3): each dig takes out a capsule of earth DIG_R round (about a body wide). Top-down it goes
## REACH in front of him, from the floor there (DIG_DOWN under it, never more than DIG_MAX under his feet: held,
## it digs a hole in front of him; stepping in and digging on, he goes down a ramp) up to DIG_UP over his feet;
## in first person it's a ball where he looks (up to FP_REACH away). Held, it digs again every DIG_EVERY s.
const DIG_R := 17.0
const REACH := 26.0
const DIG_DOWN := 0.0
const DIG_MAX := 40.0
const DIG_UP := 58.0
const FP_REACH := 80.0
const DIG_EVERY := 0.28
## Standing still (in first person, looking down past LOOK_DOWN), it digs straight down under him instead: a
## shaft SHAFT_R round, SHAFT_STEP deeper a dig (he drops into it).
const SHAFT_R := 17.0
const SHAFT_STEP := 16.0
const LOOK_DOWN := 0.4
## Filling puts a ball of FILL_R back in front of him (never into anyone, never over the ground's top).
const FILL_R := 16.0
## No digging this close to anything solid (the shed, garage, tank, trampoline, fences, crop beds...).
const MARGIN := 22.0
## Moving in the earth: he steps up STEP, climbs ledges up to CLIMB (at CLIMB_SPEED), falls at GRAVITY.
const STEP := 14.0
const CLIMB := 60.0
const CLIMB_SPEED := 150.0
const GRAVITY := 1500.0
const BODY_R := 9.0
## Top-down, underground: the earth over him within CUT_R isn't drawn (from CUT_OVER above his feet).
const CUT_R := 230.0
const CUT_OVER := 70.0
## The lamp round him underground: its reach.
const LAMP_R := 260.0

## Finds: each bit of earth dug out (a sample going from earth to air) may hold one, by where it is (the same for
## both players online). Chance a sample, by depth: near the top, the clay, the stone.
const FIND_P := [0.0035, 0.0055, 0.008]
## What, by depth band: [kind, weight, min, max] (spuds: potatoes, each loads the spud gun; coins, stash, gem,
## fossil: dollars; a stash brings a seed you can't buy too).
const FIND_TABLE := [
	[["spuds", 45, 2, 5], ["coins", 35, 3, 18], ["bone", 15, 1, 1], ["stash", 5, 120, 250]],
	[["coins", 30, 8, 30], ["bone", 20, 1, 1], ["gem", 20, 40, 90], ["spuds", 15, 3, 6], ["stash", 15, 150, 300]],
	[["gem", 40, 60, 140], ["fossil", 25, 80, 180], ["coins", 20, 15, 40], ["stash", 15, 200, 400]],
]
## How deep each band starts (units down).
const BAND_Z := [0.0, 90.0, 210.0]
## Finds lying about vanish after this long (s); he picks one up within PICK_R.
const FIND_LIFE := 120.0
const PICK_R := 30.0

## The hoe: ploughs the cells within PLOUGH_R of a point PLOUGH_AHEAD in front of him as he walks.
const PLOUGH_R := 11.0
const PLOUGH_AHEAD := 12.0
## Ploughed soil and dug-over dirt grow back: weedy after WEEDY_HOURS untended, grass after REGROW_HOURS.
## A crop within TEND_R keeps its soil tended.
const WEEDY_HOURS := 36.0
const REGROW_HOURS := 72.0
const TEND_R := 26.0
## Planting on ploughed soil: spots on a SPOT grid, all the cells within SPOT_NEED ploughed, one crop per spot.
const SPOT := 32.0
const SPOT_NEED := 10.0

## Soil kinds (per cell).
const GRASS := 0
const ROWS_X := 1                   # furrows running across (east-west)
const ROWS_Y := 2                   # furrows running down (north-south)
const DIRT := 3                     # dug over and filled in

## The shed's tool rack (against the shed's east wall), and how near E reaches it.
const RACK := {"x": 432.0, "y": 1600.0}
const RACK_REACH := 44.0

## Saving.
const SAVE_PATH := "user://smashed-dig.json"
