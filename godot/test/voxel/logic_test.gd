extends Node
## Headless checks for the block characters (scripts/voxel): the .vox reader and writer, the greedy mesher, the
## model and its rig, the animation poses, and VoxelChar standing in for a CharSprite inside the real game.
##   godot --headless --fixed-fps 60 --path godot res://test/voxel/logic_test.tscn
## Exit code 0 when everything passes.

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: ", what)

func _ready() -> void:
	_vox_round_trip()
	_mesher()
	_model()
	_goth()
	_poses()
	await _in_game()
	print("voxel logic: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _vox_round_trip() -> void:
	# a small hand-made grid: save, load, same voxels and colours
	var s := Vector3i(3, 4, 2)
	var cells := PackedInt32Array()
	cells.resize(s.x * s.y * s.z)
	cells[0] = 0xff0000 + 1
	cells[1 + 3 * (2 + 4 * 1)] = 0x00ff80 + 1
	cells[2 + 3 * (3 + 4 * 0)] = 0x102030 + 1
	var v := VoxFile.from_model_grid({"size": s, "cells": cells})
	check(v.size == Vector3i(3, 2, 4), "vox axes: model y is the file's z")
	var path := "user://voxel_test.vox"
	check(v.save_file(path) == OK, "vox saves")
	var back := VoxFile.load_file(path)
	check(back != null and back.count() == 3, "vox loads three voxels")
	var g := back.model_grid()
	check(g.size == s, "grid size round trip")
	check(g.cells == cells, "voxels and colours round trip")
	# a real part from the builder
	var head := VoxFile.load_file("res://assets/voxel/jared/head.vox")
	check(head != null and head.count() > 10000, "jared's head loads (%d voxels)" % (head.count() if head else 0))
	var again := VoxFile.parse(head.to_bytes())
	check(again.size == head.size and again.xyzi == head.xyzi and again.palette == head.palette, "a part rewrites byte for byte")

func _mesher() -> void:
	var one := PackedInt32Array([0x808080 + 1])
	var m := VoxMesher.mesh({"size": Vector3i(1, 1, 1), "cells": one})
	check(m.quads == 6, "one voxel: 6 quads (%d)" % m.quads)
	# a 4 x 3 x 2 box of one colour: greedy makes 6 quads
	var s := Vector3i(4, 3, 2)
	var c := PackedInt32Array()
	c.resize(24)
	c.fill(0x336699 + 1)
	m = VoxMesher.mesh({"size": s, "cells": c})
	check(m.quads == 6, "a one-colour box is 6 quads (%d)" % m.quads)
	check(m.verts.size() == 24 and m.indices.size() == 36, "4 vertices and 2 triangles a quad")
	# two colours side by side across x: 10 quads (the shared face is never made)
	c[0] = 0xff0000 + 1
	var two := PackedInt32Array([0xff0000 + 1, 0x00ff00 + 1])
	m = VoxMesher.mesh({"size": Vector3i(2, 1, 1), "cells": two})
	check(m.quads == 10, "two colours: 10 quads (%d)" % m.quads)
	# front faces are clockwise seen from outside (what Godot draws as the front)
	var ok := true
	for q in m.quads:
		var a: Vector3 = m.verts[m.indices[q * 6]]
		var b: Vector3 = m.verts[m.indices[q * 6 + 1]]
		var cc: Vector3 = m.verts[m.indices[q * 6 + 2]]
		var n: Vector3 = m.normals[m.indices[q * 6]]
		if (b - a).cross(cc - a).dot(n) >= 0.0:
			ok = false
	check(ok, "every quad winds clockwise toward its normal")
	# a real part: greedy is well under one quad per face
	var g := VoxFile.load_file("res://assets/voxel/jared/torso.vox").model_grid()
	var faces := VoxMesher.face_count(g)
	m = VoxMesher.mesh(g)
	check(m.quads > 0 and m.quads < faces * 0.6, "torso: %d quads for %d faces" % [m.quads, faces])
	var low := VoxMesher.mesh(VoxMesher.downsample(g))
	check(low.quads < m.quads * 0.6, "the low look's half blocks: %d quads" % low.quads)

func _model() -> void:
	var md := VoxelModel.get_model("jared")
	check(md != null, "jared's model loads")
	if md == null:
		return
	check(absf(md.voxel_m - 0.0125) < 0.002, "a voxel is a sprite pixel: %.4f m" % md.voxel_m)
	for b in ["hips", "chest", "head", "arm_r", "forearm_r", "hand_r", "arm_l", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]:
		check(md.bone(b) >= 0, "bone " + b)
	var ps := md.parts_for("classic")
	check(ps.has("hair_classic") and not ps.has("hair_mullet") and ps.has("glasses"), "the classic look's parts")
	check(md.parts_for("mullet").has("hair_mullet") and not md.parts_for("mullet").has("hair_classic"), "a style swaps the hair")
	var mesh := md.build_mesh("test", "classic", 0, VoxelWeapons.attachments(md, "blaster", 0))
	check(mesh != null and mesh.get_surface_count() == 1, "one surface (one draw call)")
	var arr := mesh.surface_get_arrays(0)
	var h := 0.0
	for v in arr[Mesh.ARRAY_VERTEX]:
		h = maxf(h, v.y)
	check(h > 1.7 and h < 2.2, "about 2 m tall like the picture (%.2f)" % h)
	check((arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 4, "every vertex on a bone")
	var tys := md.build_mesh("test_tyson", "classic", 0, [], CharFrames.palette("tyson2"))
	check(tys.get_surface_count() == 1, "the Tornado Tyson recolour builds")
	for w in ["spud", "blaster", "shotgun", "launcher"]:
		check(not VoxelModel.weapon_arrays(w, 0, md.voxel_m).is_empty(), "weapon " + w)

func _goth() -> void:
	var g := VoxelModel.get_model("goth")
	check(g != null, "Gothica's model loads")
	if g == null:
		return
	check(g.parts.has("hair") and g.parts.has("skirt"), "her hair and skirt are parts")
	var mesh := g.build_mesh("test_goth", "classic", 0, VoxelWeapons.attachments(g, "", 0))
	var h := 0.0
	for v in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		h = maxf(h, v.y)
	check(h > 1.7 and h < 2.2, "Gothica is as tall as her picture (%.2f)" % h)
	check(VoxelModel.model_for_sheet("goth") == "goth", "the goth sheet shows her blocks")

func _poses() -> void:
	var idle := VoxelAnim.pose({"t": 1.0})
	check(idle.rot.has("chest"), "idle breathes")
	var a := VoxelAnim.pose({"moving": true, "speed": 160.0, "odo": 0.0})
	var b := VoxelAnim.pose({"moving": true, "speed": 160.0, "odo": VoxelAnim.CYCLE / 4.0})
	var la: Quaternion = a.rot.get("thigh_l", Quaternion.IDENTITY)
	var lb: Quaternion = b.rot.get("thigh_l", Quaternion.IDENTITY)
	var rb: Quaternion = b.rot.get("thigh_r", Quaternion.IDENTITY)
	check(la.angle_to(lb) > 0.4, "the walk swings the thigh with odo")
	check(lb.get_euler().x < -0.3 and rb.get_euler().x > 0.3, "a quarter cycle: left leg forward, right back")
	var bl := VoxelAnim.pose({"weapon": "blaster"})
	check((bl.rot.arm_r as Quaternion).get_euler().x < -1.2 and (bl.rot.arm_l as Quaternion).get_euler().x < -1.2, "blasters: both arms aim")
	var sg := VoxelAnim.pose({"weapon": "spud"})
	check((sg.rot.arm_r as Quaternion).get_euler().x < -1.2, "spud gun: the right arm aims")
	var r0 := VoxelAnim.pose({"action": "roll", "roll_t": 0.5})
	check((r0.turn as Quaternion).get_angle() > 2.0, "the roll turns him over")
	var v := VoxelAnim.pose({"action": "victory", "t": 0.3})
	check(absf((v.rot.arm_r as Quaternion).get_euler().z) > 1.2, "victory raises the arms")
	var th := VoxelAnim.pose({"weapon": "spud", "act": "charge"})
	var hand: Vector3 = (th.rot.arm_r as Quaternion) * Vector3.DOWN
	check(hand.y > 0.5 and hand.z < 0.0, "the throw winds up behind the head")
	for p in ["sit", "lie", "bench", "legpress", "swim", "carry", "carried", "lift"]:
		check(not VoxelAnim.pose({"pose": p, "t": 0.5}).rot.is_empty(), "lobby pose " + p)

func _in_game() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var sw := VoxelSwitch.install(main)
	sw.set_mode("blocks", false)
	for i in 5:
		await get_tree().process_frame
	var pl: Player = main.player
	var vc := pl.sprite.get_node_or_null("Blocks") as VoxelChar
	check(vc != null, "the player's sprite gets blocks")
	if vc:
		check(vc.mesh_inst != null and vc.mesh_inst.mesh != null, "the blocks have a mesh")
		check(not (pl.sprite.get("_spr") as Node3D).visible, "the picture is hidden")
		check(vc.weapon != "", "holding a weapon (%s)" % vc.weapon)
		# walk him a bit: the pose follows
		Input.action_press("move_right")
		for i in 40:
			await get_tree().physics_frame
		await get_tree().process_frame
		check(bool(vc.last_state.get("moving", false)), "walking shows as moving")
		check(float(vc.last_state.get("speed", 0.0)) > 30.0, "speed from his movement (%.0f)" % float(vc.last_state.get("speed", 0.0)))
		Input.action_release("move_right")
		for i in 30:
			await get_tree().physics_frame
		await get_tree().process_frame
		var f := pl.sprite.facing
		check(absf(wrapf(vc.yaw - atan2(f.x, f.y), -PI, PI)) < 0.3, "turned to the sprite's facing (%.2f)" % vc.yaw)
	var gv: Node = main.gothica.sprite.get_node_or_null("Blocks")
	check(gv is VoxelChar and (main.gothica.sprite.get("_spr") as Node3D).visible == not VoxelModel.has_model("goth"), "Gothica: blocks when she has a model")
	sw.set_mode("pixel", false)
	await get_tree().process_frame
	check(pl.sprite.get_node_or_null("Blocks") == null, "pixel: the blocks go")
	check((pl.sprite.get("_spr") as Node3D).visible, "pixel: the picture is back")
	main.queue_free()
