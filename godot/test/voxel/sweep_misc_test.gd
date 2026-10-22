extends SceneTree
## The whole-game bug sweep's fixes, the odds and ends (headless): an open padlock held up close shows its shackle up
## and aside (a shut one shut); the mirror off (the setting) or seen from outside the bedroom renders nothing and shows
## a plain sheen, not a frozen reflection; Tornado Tyson in blocks wears his own hair and a plain singlet, not Juicy
## Jared's mirror look (Jared keeps his); switching to pixel while carrying Gothica hides her own sprite again (the
## lobby's carry picture draws her). Prints "SWM ok/FAIL ..." and "SWM done N passed, M failed". Owned by the voxel
## session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var _switch_done := false

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("SWM %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var lv: VoxelLockView = arena.lock_view if arena else null
	var c: VoxelStorage = arena.stash.by_id["bed_chest_1"] if arena else null
	match step:
		0:
			arena.frozen = true
			# (51) an open padlock held up close: its shackle up and swung aside, as the hint says
			c.set_lock(true, false)
			_place(c.front() + Vector3(0, 0, 0.9), 0.0, -0.7)
			arena.open_lock(c, false)
			mark = t
			step = 1
		1:
			if t - mark > 0.1:
				var sh: Node3D = lv.model._shackle
				check(absf(sh.rotation.y + PI * 0.5) < 0.05 and sh.position.y > VoxelPadlock.H * 0.5 + 0.01,
					"an open padlock up close shows its shackle open (turned %.2f, up %.3f)" % [sh.rotation.y, sh.position.y])
				arena.close_lock()
				c.set_lock(true, true)
				arena.open_lock(c, false)
				mark = t
				step = 2
		2:
			if t - mark > 0.1:
				var sh2: Node3D = lv.model._shackle
				check(absf(sh2.rotation.y) < 0.01 and absf(sh2.position.y - VoxelPadlock.H * 0.5) < 0.001,
					"a locked one shows it shut (turned %.2f)" % sh2.rotation.y)
				arena.close_lock()
				c.set_lock(true, false)
				# (52) the mirror: renders in the bedroom, in front of it
				_place(Vector3(-1.4, 0, 27.4), PI, -0.12)
				mark = t
				step = 3
		3:
			if t - mark > 0.15:
				var m: VoxelMirror = arena.house.mirror
				arena._camera(0.0)
				m._process(0.0)
				check(m._vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS and m._gm.albedo_texture != null,
					"the mirror renders and shows its reflection in the bedroom")
				VoxelMirror.enabled = false
				m._process(0.0)
				check(m._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and m._gm.albedo_texture == null
					and m._gm.albedo_color == VoxelMirror.SHEEN, "the mirror off: nothing renders, a plain sheen (not a frozen reflection)")
				VoxelMirror.enabled = true
				m._process(0.0)
				check(m._gm.albedo_texture != null, "on again: the reflection back")
				# the games room's couch, under 9 m from the glass but through the wall
				_place(Vector3(-9.15, 0, 26.4), 0.0, 0.0)
				mark = t
				step = 4
		4:
			if t - mark > 0.15:
				var m2: VoxelMirror = arena.house.mirror
				arena._camera(0.0)
				m2._process(0.0)
				var eye: Vector3 = arena.cam.global_position
				check(eye.distance_to(m2.centre) < VoxelMirror.NEAR_ENOUGH and m2._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED
					and m2._gm.albedo_texture == null, "from the games room (%.1f m, through the wall): not rendered, the sheen" % eye.distance_to(m2.centre))
				_tyson_check()
				arena.queue_free()
				arena = null
				step = 5
		5:
			step = 6
			_switch_check()
		6:
			if _switch_done:
				step = 99
		99:
			print("SWM done %d passed, %d failed" % [passed, failed])
			return true
	return false

# (the main game's classes need its GameData autoload, which isn't there yet when this script compiles: loaded here)
func _cls(path: String):
	return load(path)

func _colors(vc) -> PackedColorArray:
	if vc.mesh_inst == null or vc.mesh_inst.mesh == null:
		return PackedColorArray()
	return vc.mesh_inst.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]

# (81) Tornado Tyson shares Jared's blocks but not his mirror look
func _tyson_check() -> void:
	var model_cls = _cls("res://scripts/voxel/voxel_model.gd")
	var char_cls = _cls("res://scripts/voxel/voxel_char.gd")
	var look = _cls("res://scripts/lobby_life/lobby_look.gd")
	var vlook = _cls("res://scripts/voxel/voxel_look.gd")
	if not model_cls.has_model("jared"):
		check(true, "(no Jared blocks: Tyson's look skipped)")
		return
	look._loaded = true                         # (not the saved look: this run's own)
	var keep := [look.style, look.art_front, look.art_back, look.place_front]
	var keys: Array = look.beards().map(func(b): return String(b.key))
	var tyson0 = char_cls.new()
	tyson0._ensure("tyson2")
	var plain := _colors(tyson0)
	look.style = maxi(0, keys.find("mohawk"))
	var art := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	art.fill(Color(1, 0, 1))
	look.art_front = art
	look.art_back = null
	look.place_front = Rect2(0, 0, 1, 1)
	look.rev += 1
	var jared = char_cls.new()
	jared._ensure("juicy")
	var model = model_cls.get_model("jared")
	var printed = model.grid("torso")
	var jcol := _colors(jared)
	check(jared.style == "mohawk" and not is_same(printed, vlook._orig_torso), "Jared wears the mirror's mohawk and print")
	var jmesh = jared.mesh_inst.mesh
	var tyson = char_cls.new()
	tyson._ensure("tyson2")
	check(tyson.style == "classic" and String(tyson._key).ends_with("|0"), "Tornado Tyson keeps his own hair (%s)" % tyson.style)
	check(not plain.is_empty() and _colors(tyson) == plain, "and a plain singlet (no print from Jared's look)")
	check(is_same(model.grid("torso"), printed), "Jared's print still on the shared torso after")
	# his weapon switching (P2, the co-op avatar, a lobby pose) builds his own meshes, not Jared's over again
	var tmesh = tyson.mesh_inst.mesh
	var us := Time.get_ticks_usec()
	tyson.weapon = "shotgun"
	tyson._ensure("tyson2")
	tyson.weapon = ""
	tyson._ensure("tyson2")
	var back_us := Time.get_ticks_usec() - us
	check(not is_same(tyson.model, model) and is_same(tyson.mesh_inst.mesh, tmesh) and model._meshes.has(jared._key)
		and is_same(model.grid("torso"), printed), "Tyson's weapon switch and back: his own cached mesh, Jared's meshes kept (%.1f ms)" % (back_us / 1000.0))
	jared._key = ""
	us = Time.get_ticks_usec()
	jared._ensure("juicy")
	var again_us := Time.get_ticks_usec() - us
	check(not jcol.is_empty() and _colors(jared) == jcol, "Jared built again: still printed")
	check(is_same(jared.mesh_inst.mesh, jmesh), "and from the cache, not meshed again (%.1f ms)" % (again_us / 1000.0))
	# one body going from Jared's sheet to Tyson's takes Tyson's blocks (and back)
	var both = char_cls.new()
	both._ensure("juicy")
	both._ensure("tyson2")
	var as_tyson := is_same(both.model, tyson.model) and _colors(both) == plain
	both._ensure("juicy")
	check(as_tyson and is_same(both.model, model) and _colors(both) == jcol, "one body from Jared's sheet to Tyson's and back: each one's own look")
	both.free()
	# (put this run's look back)
	look.style = keep[0]
	look.art_front = keep[1]
	look.art_back = keep[2]
	look.place_front = keep[3]
	look.rev += 1
	for vc in [tyson0, jared, tyson]:
		vc.free()

# (126) pixel while carrying Gothica: she's hidden again (the lobby's carry picture draws her)
func _switch_check() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var sw = _cls("res://scripts/voxel/voxel_switch.gd").install(main)
	sw.set_mode("blocks", false)
	for i in 5:
		await process_frame
	var ll = _cls("res://scripts/lobby_life/lobby_life.gd").current
	var pl = main.get("player")
	var goth = main.get("gothica")
	if ll == null or goth == null or pl == null or not _cls("res://scripts/voxel/voxel_model.gd").has_model("goth"):
		check(true, "(no lobby or no Gothica blocks: the carry switch skipped)")
	else:
		var gl = ll.things.get("goth_life")
		var gp: Vector2 = goth.html_pos2()
		pl.place(gp.x, gp.y + 20.0)
		await process_frame
		gl.pick_up(pl)
		for i in 30:
			await process_frame
		check(gl.carrier == pl and goth.visible, "blocks: carried, her blocks shown in his arms")
		sw.set_mode("pixel", false)
		for i in 3:
			await process_frame
		check(gl.carrier == pl and not goth.visible, "pixel while carrying her: her own sprite hidden again (not drawn twice)")
		gl._put_down(pl)
		await process_frame
		check(goth.visible, "put down: she stands there again")
	main.queue_free()
	await process_frame
	_switch_done = true
