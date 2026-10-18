extends RefCounted
## Every number of the yard's digging and ploughing (PLAN.md "Later: digging", level 2), in HTML units and game
## hours. Owned by the digging part (scripts/dig/).

## The depth grid: square cells CELL units across over the yard, its corner heights stored per vertex.
## The region covers both yard areas (calls.lobbyAreas 5 and 6) with the house inside it (never diggable).
const CELL := 8.0
const X0 := 0.0
const Y0 := 48.0
const NX := 214                     # cells across (to x 1712)
const NY := 230                     # cells down (to y 1888)
## The meshes: CHUNK x CHUNK cells each.
const CHUNK := 32
## Depths are kept in half units (int8 when saved or sent): up to +-63 units.
const QUANT := 2.0

## The shovel: one press lowers the hole by STEP, down to MAX_DEPTH (about waist-deep: his eyes are at 62,
## the body 66 tall). The hole's floor is flat out to R_IN, then slopes up to the rim at R_OUT.
const STEP := 9.0
const MAX_DEPTH := 36.0
const R_IN := 13.0
const R_OUT := 30.0
## Where the hole goes: this far in front of him.
const REACH := 30.0
## The pile beside it: a mound PILE_R wide, PILE_PER_STEP higher a press (to PILE_MAX), PILE_OFF from the hole.
const PILE_R := 22.0
const PILE_PER_STEP := 3.5
const PILE_MAX := 15.0
const PILE_OFF := 56.0
## Filling takes dirt back from a pile within this distance.
const PILE_FIND := 110.0
## No digging this close to anything solid (the shed, garage, tank, trampoline, fences, crop beds...).
const MARGIN := 22.0

## Finds, rolled when a hole first reaches the bottom (each spot once): chances out of 1, the rest nothing.
const FINDS := [
	{"kind": "spuds", "p": 0.30, "min": 2, "max": 5},       # potatoes: each loads the spud gun (spudPellets)
	{"kind": "coins", "p": 0.25, "min": 3, "max": 18},      # dollars, into the shared Wallet
	{"kind": "bone", "p": 0.07, "min": 1, "max": 1},
	{"kind": "stash", "p": 0.02, "min": 120, "max": 250},   # a rare buried stash: dollars, and a seed
]

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
