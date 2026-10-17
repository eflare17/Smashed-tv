extends Node3D
## Skeleton: the lounge floor picture on the ground, a light, and a camera looking down at it.
## (Milestone 1 replaces this with the world, the player and the cameras.)

func _ready() -> void:
	var lounge: Texture2D = GameData.tex(GameData.manifest["LOUNGE_IMG.src"])
	var a: Dictionary = GameData.data["ARENA"]
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2((a["w"] - a["wall"] * 2) * GameData.UNIT, (a["h"] - a["wall"] * 2) * GameData.UNIT)
	floor.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = lounge
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor.material_override = mat
	floor.position = GameData.world_to_3d(a["w"] / 2.0, a["h"] / 2.0)
	add_child(floor)
	var cam := Camera3D.new()
	cam.position = GameData.world_to_3d(a["w"] / 2.0, a["h"] * 0.95, 700)
	add_child(cam)
	cam.look_at(GameData.world_to_3d(a["w"] / 2.0, a["h"] / 2.0))
	cam.current = true
