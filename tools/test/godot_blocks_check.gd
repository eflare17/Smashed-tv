## Checks a block character installed by tools/add_godot_character.py loads and plays in the Godot port.
## Copy this file into a copy of godot/ (with the character installed there), make a scene with one Node using it
## (or run it with the voxel tests), and run headless: godot --headless --fixed-fps 60 --path <copy> res://t_blocks.tscn
## $CH picks the character id (default jared_blocks, the test character from sprite_blocks_shots.js).
extends Node
var fails := 0
func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: fails += 1
func _ready() -> void:
	await get_tree().process_frame
	var m := VoxelModel.get_model(_id())
	var j := VoxelModel.get_model("jared")
	check(m != null, "the sprite maker's model loads")
	check(m.bone_names.size() == 15 and m.bone_names == j.bone_names, "same 15 bones as Jared")
	check(absf(m.voxel_m - j.voxel_m) < 0.002, "block size %.4f m (Jared %.4f)" % [m.voxel_m, j.voxel_m])
	var am := m.build_mesh("t", "classic", 0)
	var tris := am.surface_get_array_index_len(0) / 3
	check(tris > 10000, "mesh: %d triangles" % tris)
	var h := 0.0
	for n in m.parts: h = maxf(h, (m.parts[n].origin.y + m.grid(n).size.y) * m.voxel_m)
	check(h > 1.6 and h < 2.2, "%.2f m tall (Jared ~%.2f)" % [h, 150 * j.voxel_m])
	check(VoxelModel.model_for_sheet(_id()) == _id(), "its sheet shows as blocks")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var sw := VoxelSwitch.install(main)
	sw.set_mode("blocks", false)
	var pl: Player = main.player
	pl.char_id = _id()
	for i in 10: await get_tree().process_frame
	var vc := pl.sprite.get_node_or_null("Blocks") as VoxelChar
	check(vc != null and vc.model_name == pl.char_id, "the player as the new character gets its blocks (%s)" % (vc.model_name if vc else "none"))
	if vc:
		check(vc.mesh_inst != null and vc.mesh_inst.mesh != null, "with a mesh")
		Input.action_press("move_right")
		for i in 40: await get_tree().physics_frame
		await get_tree().process_frame
		check(bool(vc.last_state.get("moving", false)), "walking")
		Input.action_release("move_right")
	print("fails: %d" % fails)
	get_tree().quit(1 if fails else 0)

func _id() -> String:
	return OS.get_environment("CH") if OS.get_environment("CH") != "" else "jared_blocks"
