class_name Player
extends CharacterBody3D
## CONTRACT. The player. Owned by the Player and cameras task. Others may read these:

signal interacted(target: Node)

## HTML-game state the other parts look at.
var char_id: String = "juicy"
var facing: Vector2 = Vector2(0, 1)      ## where he faces, HTML ground axes
var odo: float = 0.0                     ## distance walked, HTML units
var moving: bool = false
var dz: float = 0.0                      ## height off the ground, HTML units (the trampoline sets it)
var on_tramp: bool = false               ## up on the trampoline: the trampoline moves him up and down
var frozen: bool = false                 ## something else is in charge of him (the trampoline's climb on)

## Where he is in HTML units (x, y on the ground, z up).
func html_pos() -> Vector3:
	return GameData.from_3d(global_position)

## Put him somewhere, in HTML units.
func place(x: float, y: float) -> void:
	global_position = GameData.world_to_3d(x, y, 0.0)
