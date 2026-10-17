class_name CharSprite
extends Node3D
## CONTRACT. A character drawn the HTML game's way: an upright picture that always faces the camera, showing
## whichever of its five directions (front, diag, side, bdiag, back; the other side flipped) matches the angle
## between where the character faces and where the camera is. Feet on this node's origin.
## Owned by the Characters task.

## Which character: a key of the manifest's CHARS ("juicy", "tyson2", "goth", ...).
@export var char_id: String = "juicy"
## Where the character faces, on the ground, in HTML axes (x across, y down the screen).
var facing: Vector2 = Vector2(0, 1)
## Running (walk cycle) or standing.
var moving: bool = false
## Distance walked, in HTML units: the walk cycle steps through frames with it, like the HTML game's odo.
var odo: float = 0.0
## "" normally; "roll" (0..1 through it in roll_t), "victory".
var action: String = ""
var roll_t: float = 0.0

## Call every frame with the camera that's drawing (it picks the angle).
func update_view(_camera: Camera3D) -> void:
	pass
