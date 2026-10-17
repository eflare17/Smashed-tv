class_name CameraRig
extends Node3D
## CONTRACT. The two views. Owned by the Player and cameras task.
enum Mode { TOP_DOWN, FIRST_PERSON }
signal mode_changed(mode: int)
var mode: int = Mode.TOP_DOWN
var target: Player
func camera() -> Camera3D:
	return null
