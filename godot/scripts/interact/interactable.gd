class_name Interactable
extends Node3D
## CONTRACT. Something E can be used on. Put it in the scene (it adds itself to the "interactable" group);
## the player asks every one in range what E would do (label_for) and the nearest one with a label wins.
## Positions are this node's global_position; reach is in HTML units on the ground.

@export var reach: float = 40.0

func _enter_tree() -> void:
	add_to_group("interactable")

## What E does here for this player, in capitals like the HTML game ("SIT", "CLIMB ON"), or "" for nothing.
func label_for(_player: Node) -> String:
	return ""

## Do it.
func act(_player: Node) -> void:
	pass

## How far the player is, in HTML units on the ground.
func ground_distance(player: Node3D) -> float:
	var a: Vector3 = GameData.from_3d(global_position)
	var b: Vector3 = GameData.from_3d(player.global_position)
	return Vector2(a.x - b.x, a.y - b.y).length()
