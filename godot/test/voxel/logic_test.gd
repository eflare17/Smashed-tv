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
	_holes()
	_sword()
	_vacuum()
	_loadout()
	_carve()
	_fixes()
	_melee_checks()
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

# the PC arena's shooting: a ray into a grunt finds a cube exactly, a hit knocks a round hole there
func _grunt() -> VoxelBody:
	var b := VoxelBody.new()
	add_child(b)
	b.setup("grunt", 0.023, 1, StandardMaterial3D.new())
	b.animate(0.0, false)
	return b

# a sword cut: a level sweep at the height h (metres) from 2 m in front
func _cut(b: VoxelBody, h: float) -> Dictionary:
	return b.slice(Vector3(0, h, 2.0), Vector3(0, -1, 0), Vector3(0, 0, -1), 2.6, 0.17, b.vm * 0.9)

func _sword() -> void:
	var b := _grunt()
	var r := _cut(b, 0.27)
	check(int(r.cut) > 50, "a sword cut through the shins cuts cubes out (%d)" % r.cut)
	check(b.parts.foot_l.gone and b.parts.foot_r.gone, "the feet come off with the shins below the cut")
	check(b.legs_lost() == 2 and b.alive, "legs cut off: he crawls on, alive")
	check((r.pieces as Array).size() >= 4, "the shins' lower halves and the feet are pieces (%d)" % (r.pieces as Array).size())
	check(not b.parts.shin_l.gone and int(b.parts.shin_l.left) > 0, "the shins' tops stay on")
	b.queue_free()
	var b2 := _grunt()
	var r2 := _cut(b2, 63.0 * 0.023)
	check(b2.parts.head.gone and bool(r2.head_off), "cut at the neck, the head comes off whole")
	check(not b2.alive and bool(r2.killed), "and that kills him")
	check(not b2.parts.arm_l.gone, "his arms stay on")
	b2.queue_free()
	var b3 := _grunt()
	var r3 := _cut(b3, 1.1)
	check(b3.parts.head.gone and b3.parts.arm_l.gone and b3.parts.arm_r.gone, "cut through the middle, the top half comes off (head, arms)")
	check(int(b3.parts.torso.left) > 0 and not b3.alive, "the bottom half stays, dead")
	b3.queue_free()

func _vacuum() -> void:
	var d := VoxelDebris.new()
	add_child(d)
	d.set_process(false)
	d.setup(0.023)
	var bits := []
	for i in 200:
		bits.append({"pos": Vector3(randf_range(-0.2, 0.2), 1.0, randf_range(-0.2, 0.2)), "col": VoxelBody.BONE if i < 50 else Color8(20, 140, 40)})
	for i in 30:
		bits.append({"pos": Vector3(6.0, 0.3, 0.0), "col": Color8(20, 140, 40)})
	d.burst(bits, Vector3(0, 0, 1), 1.0)
	for i in 600:
		d._process(1.0 / 60.0)
	check(d.lying() == 230 and d.count() == 0, "knocked-out cubes come to rest and stay (%d lying, %d flying)" % [d.lying(), d.count()])
	# the brush over the pile; the 30 cubes 6 m off are outside it
	d.nozzle = Vector3(0, 1.0, -2.5)
	d.brush = Vector3(0, 0, 0.4)
	d.brush_r = 1.4
	d._process(1.0 / 60.0)
	check(d.count() > 0 and d.count() <= 60, "the brush pulls them loose at a steady rate (%d the first frame)" % d.count())
	for i in 240:
		d._process(1.0 / 60.0)
	var got: int = d.got.blocks + d.got.bone
	check(got > 150 and d.got.bone > 30, "they go up the beam as resources (%d: %d bone, %d blocks)" % [got, d.got.bone, d.got.blocks])
	check(d.lying() >= 30, "only the ones inside the brush (%d still lying)" % d.lying())
	d.brush = Vector3.INF
	for i in 600:
		d._process(1.0 / 60.0)
	check(d.lying() + got == 230, "let go, the ones in the air fall back (%d lying)" % d.lying())
	d.queue_free()

func _loadout() -> void:
	var l := VoxelLoadout.new()
	check(l.slots.size() == 8 and l.id() == "blaster", "eight weapon slots, the blaster out first")
	check(l.select(2) and l.id() == "sword" and not l.usable(), "3 takes out the sword; it comes up for a moment first")
	l.step(VoxelLoadout.SWITCH_T + 0.01)
	check(l.usable(), "then it's up")
	l.swap_last()
	check(l.id() == "blaster", "Q: back to the last one")
	l.cycle(-1)
	check(l.id() == "vacuum", "the wheel goes round the end (%s)" % l.id())
	check(not l.select(7) and not l.select(99), "the one out, or no such slot: nothing happens")
	l.cool("shotgun", 1.0)
	l.step(0.5)
	check(not l.ready_to("shotgun") and absf(l.cooling("shotgun") - 0.5) < 0.01 and l.ready_to("blaster"), "cooldowns kept per weapon")
	l.keep_only(["blaster", "sword", "vacuum"])
	check(l.slots.size() == 3 and l.index_of("vacuum") == 2, "only the weapons there are")

func _carve() -> void:
	var b := _grunt()
	var hp0 := b.hp
	# a ball in the chest: a crater, no pieces, health off
	var r := b.carve(Vector3(0, 1.0, 0.25), Vector3(0, 1.0, 0.25), 0.18)
	check(int(r.cut) > 100 and (r.pieces as Array).is_empty() and b.hp < hp0, "a ball carved from the chest: a crater (%d cubes), health off" % r.cut)
	# a tunnel through the shin: the foot and the shin below come off
	var r2 := b.carve(Vector3(-0.25, 0.25, 1.0), Vector3(-0.25, 0.25, -1.0), 0.09)
	check((r2.pieces as Array).size() >= 1 and b.parts.foot_r.gone, "a tunnel right through the shin: what's below comes off (%d pieces)" % (r2.pieces as Array).size())
	b.queue_free()
	var b2 := _grunt()
	b2.launch(Vector3(0, 4.0, -3.0), 6.0)
	check(b2.airborne and b2.floored(), "launched: in the air")
	for i in 120:
		b2.react_step(1.0 / 60.0)
		b2.animate(1.0 / 60.0, false)
	check(not b2.airborne and b2.down_t > 0.0 and absf(b2.position.y) < 0.001 and b2.position.z < -1.0, "landed back down the way it flew, lying there (%.2f m)" % b2.position.z)
	for i in 180:
		b2.react_step(1.0 / 60.0)
	check(not b2.floored(), "then back up")
	b2.queue_free()

# the review's finds, kept fixed
func _fixes() -> void:
	var b := _grunt()
	# a blade just nicking the front of the knee: nothing comes off
	var kb := b.model.bone("shin_l")
	var knee: Vector3 = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(kb).origin
	var eye := Vector3(knee.x, knee.y - b.vm * 0.3, knee.z + 0.6)
	var r := b.slice(eye, Vector3.UP, Vector3(0, 0, -1), 0.6 - 0.12, -1.0, b.vm * 0.5)
	check((r.pieces as Array).is_empty() and b.legs_lost() == 0, "a nick at the front of the knee takes nothing off (%d pieces)" % (r.pieces as Array).size())
	# a shave down the side of each thigh: still two legs
	for sx in [-1.0, 1.0]:
		b.slice(Vector3(0.21 * sx, 0.47, 0.06), Vector3.BACK, Vector3(sx, 0, 0), 0.2, -1.0, b.vm * 0.6)
	check(b.legs_lost() == 0, "a shave off the thighs isn't a lost leg (%d)" % b.legs_lost())
	b.queue_free()
	# a chop down the middle: one half comes off, not both kept
	var b2 := _grunt()
	var r2 := b2.slice(Vector3(0, 1.65, 1.5), Vector3.RIGHT, Vector3(0, -0.4, -1).normalized(), 2.6, 0.17, b2.vm * 0.9)
	check(not (r2.pieces as Array).is_empty() and not b2.alive, "a chop down the middle takes a half off (%d pieces)" % (r2.pieces as Array).size())
	b2.queue_free()
	# every part starts as one lump of touching cubes
	var b3 := _grunt()
	var lumpy := []
	for n in b3.parts:
		var g: Dictionary = b3.parts[n].grid
		if VoxelBody._lumps(g.cells, g.size, Vector3i.ZERO, (g.size as Vector3i) - Vector3i.ONE).size() > 1:
			lumpy.append(n)
	check(lumpy.is_empty(), "every part is one lump to start with %s" % str(lumpy))
	# hit again in the air: it keeps turning over
	b3.launch(Vector3(0, 5, -2), 6.0)
	for i in 20:
		b3.react_step(1.0 / 60.0)
	var t0 := b3.tumble
	b3.launch(Vector3(0, 4, -2), 6.0)
	check(b3.tumble >= t0, "hit again in the air, the tumble carries on (%.2f -> %.2f)" % [t0, b3.tumble])
	b3.queue_free()
	# flying cubes bounce off the walls
	var d := VoxelDebris.new()
	add_child(d)
	d.set_process(false)
	d.setup(0.023)
	d.bound = 2.0
	d.burst([{"pos": Vector3(1.9, 1.0, 0), "col": Color8(1, 2, 3)}], Vector3(1, 0, 0), 8.0)
	for i in 300:
		d._process(1.0 / 60.0)
	check(d.lying() == 1 and absf(d._lp[0].x) <= 2.0, "flying cubes stay inside the walls (x %.2f)" % d._lp[0].x)
	d.queue_free()

# each melee weapon's own checks (VoxelMelee.checks)
func _melee_checks() -> void:
	for id in VoxelArena.MELEE:
		var path: String = VoxelArena.MELEE[id]
		if not ResourceLoader.exists(path):
			continue
		var scr: Script = load(path)
		var out: Array = scr.checks(self)
		for c in out:
			check(bool(c[0]), "%s: %s" % [id, c[1]])

func _holes() -> void:
	var mat := StandardMaterial3D.new()
	var b := VoxelBody.new()
	add_child(b)
	b.setup("grunt", 0.023, 1, mat)
	b.animate(0.0, false)
	var from := Vector3(0, 1.2, 3.0)
	var h := b.trace(from, Vector3(0, 0, -1), 10.0)
	check(not h.is_empty(), "a shot at a grunt's chest hits him")
	if h.is_empty():
		b.queue_free()
		return
	check(String(h.part) in ["torso", "arm_l", "arm_r", "hand_l", "hand_r", "pelvis"], "it lands on his body (%s)" % h.part)
	var part: Dictionary = b.parts[h.part]
	var before: int = part.left
	var res := b.damage(h, 1.9)
	check((res.bits as Array).size() > 5 and int(part.left) < before, "a hole: %d cubes out" % (res.bits as Array).size())
	check(b.dirty_parts().has(h.part) or bool(part.dirty), "only the hit part is meshed again")
	var z0 := b.position.z
	b.hit_react(Vector3(0, 0, -1), (res.bits as Array).size(), String(h.part))
	check(b.stagger > 0.2, "a hit staggers him (no pushing forward)")
	for i in 12:
		b.react_step(1.0 / 60.0)
	check(b.position.z < z0 - 0.05, "and shoves him back along the shot (%.2f m)" % (z0 - b.position.z))
	b.position = Vector3.ZERO
	b.knock = Vector3.ZERO
	var h2 := b.trace(from, Vector3(0, 0, -1), 10.0)
	check(not h2.is_empty() and float(h2.dist) > float(h.dist), "the next shot goes deeper into the hole")
	var flesh := false
	var cells: PackedInt32Array = part.grid.cells
	for c in cells:
		if c != 0:
			var k := c - 1
			if ((k >> 16) & 255) > 90 and ((k >> 8) & 255) < 50 and (k & 255) < 60:
				flesh = true
				break
	check(flesh, "there's flesh inside")
	for i in 30:
		var hh := b.trace(from, Vector3(0, 0, -1), 10.0)
		if hh.is_empty() or not b.alive:
			break
		b.damage(hh, 1.9)
	check(b.alive, "thirty chest shots don't kill him (ten times tougher)")
	check(b.brain_start > 50, "he has a brain (%d cubes)" % b.brain_start)
	# shots into the head: dead only once a quarter of the brain is gone
	var shots := 0
	for i in 200:
		if not b.alive:
			break
		# spread over the face, a few cubes apart, like a player's shots
		var off := Vector3(((i % 5) - 2) * 0.035, b.height * 0.86 + (((i / 5) % 5) - 2) * 0.035, 3.0)
		var hh := b.trace(off, Vector3(0, 0, -1), 10.0)
		if hh.is_empty():
			continue
		b.damage(hh, 1.9)
		shots += 1
	print("voxel logic: a grunt took %d blaster shots to the head (%d of %d brain cubes)" % [shots, b.brain_lost, b.brain_start])
	check(not b.alive, "head shots kill him (%d shots)" % shots)
	check(float(b.brain_lost) >= float(b.brain_start) * 0.25, "a quarter of the brain gone when he dies (%d of %d)" % [b.brain_lost, b.brain_start])
	b.queue_free()

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
	# carrying Gothica: both as blocks, the lobby's carry picture hidden
	var ll := LobbyLife.current
	if ll and VoxelModel.has_model("goth"):
		var gp: Vector2 = main.gothica.html_pos2()
		pl.place(gp.x, gp.y + 20.0)
		await get_tree().process_frame
		ll.things["goth_life"].pick_up(pl)
		for i in 30:
			await get_tree().process_frame
		var gb := main.gothica.sprite.get_node_or_null("Blocks") as VoxelChar
		check(vc != null and vc.lobby_pose == "carry", "carrying: his blocks hold her (%s)" % (vc.lobby_pose if vc else "-"))
		check(gb != null and gb.lobby_pose == "carried" and gb.is_visible_in_tree(), "carried: her blocks lie in his arms")
		ll.things["goth_life"]._put_down(pl)
		for i in 5:
			await get_tree().process_frame
		check(gb != null and gb.lobby_pose == "", "put down: she stands again")
	# a run: grunts, swarmers and brutes in blocks (their pictures hidden)
	if Fight.me:
		Fight.me.start_run(true)
		var blocks := 0
		for i in 400:
			await get_tree().process_frame
			var ve := main.get_node_or_null("VoxelEnemies")
			if ve:
				blocks = 0
				for c in ve.get_children():
					if c.visible:
						blocks += 1
				if blocks > 0:
					break
		check(blocks > 0, "enemies in blocks in a run (%d)" % blocks)
	sw.set_mode("pixel", false)
	await get_tree().process_frame
	check(pl.sprite.get_node_or_null("Blocks") == null, "pixel: the blocks go")
	check((pl.sprite.get("_spr") as Node3D).visible, "pixel: the picture is back")
	main.queue_free()
