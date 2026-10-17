class_name WorldBuilder
extends Node3D
## CONTRACT. Builds the lobby, bedroom and yard (floors, walls, solids, props) with collision, from
## GameData.data. Owned by the World task.

## Build everything as children of this node.
func build() -> void:
	pass

## The solid boxes on the ground, in HTML units: [{x0, y0, x1, y1, h}], for walking round things
## (Gothica uses it).
func ground_boxes() -> Array:
	return []
