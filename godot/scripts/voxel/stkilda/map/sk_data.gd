# (Copied from stkilda-godot scripts/game_data.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkData
extends RefCounted
## Manifolds & Mullets: the workshop's layout and palette. Everything is in metres: x across (east), z toward
## the street (south, the front of the shop), y up. The workshop's front wall (the roller door) sits on z = 0.

## The shed: 26 m across, 18 m deep, the front wall on z = 0.
const SHED_X0 := -13.0
const SHED_X1 := 13.0
const SHED_Z0 := -18.0
const SHED_Z1 := 0.0
const WALL_H := 6.0
## The roller door, in the front wall (x from, x to), and how high it opens.
const DOOR_X0 := -12.0
const DOOR_X1 := -1.0
const DOOR_H := 4.6
## The two hoist bays: the middle of each (x), cars drive in nose first (facing -z).
const BAY_X := [-9.0, -4.0]
const BAY_Z := -8.0
## The office in the front right corner: x from, x to, and its back wall (z).
const OFFICE_X0 := 1.5
const OFFICE_X1 := 13.0
const OFFICE_Z0 := -7.0
## Out the front: the car park, then the footpath, then the street.
const PARK_Z1 := 13.0
const PATH_Z1 := 16.5
const ROAD_Z1 := 27.0

## Physics layers: 1 world, 2 players.
const LAYER_WORLD := 1 << 0
const LAYER_PLAYERS := 1 << 1

## The brand: mint/aqua green everywhere, maroon roof beams, orange hoists, metallic greys.
const C_MINT := Color("#5fd3b3")
const C_MINT_DARK := Color("#36a68a")
const C_MINT_LIGHT := Color("#a6eeda")
const C_MAROON := Color("#7a1f2b")
const C_MAROON_DARK := Color("#55141e")
const C_ORANGE := Color("#f07a1a")
const C_ORANGE_DARK := Color("#c25a0e")
const C_STEEL := Color("#9aa3ad")
const C_STEEL_DARK := Color("#5d6670")
const C_STEEL_LIGHT := Color("#c9d0d7")
const C_CONCRETE := Color("#a7a49c")
const C_CONCRETE_DARK := Color("#8d8a83")
const C_ASPHALT := Color("#3d4148")
const C_LINE := Color("#f2f2ee")
const C_PATH := Color("#c4bcae")
const C_GRASS := Color("#a09a58")       # dry country-town grass
const C_GRASS_DARK := Color("#848449")
const C_INK := Color("#1a1c2c")
const C_WHITE := Color("#f4f4f4")
const C_GLASS := Color("#8fd0e0")
const C_YELLOW := Color("#ffd54a")

## The whole site on the ground (x, z), for keeping the camera in.
func site_rect() -> Rect2:
	return Rect2(-30.0, -24.0, 60.0, 24.0 + ROAD_Z1 + 3.0)
