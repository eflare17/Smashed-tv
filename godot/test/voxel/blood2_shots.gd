extends SceneTree
## Screenshots of Ultra Gore's second stage (under a display, Forward+: -- --out=dir): blood_prints (walked through a
## pool: footprints going off, fainter each step), blood_crawl (a grunt with no legs dragging itself: the smear behind
## it), blood_runs (a grunt shot in the chest and shoulder, five seconds on: blood run down it), blood_bat (first
## person, the bat after a few hits: coated, dripping). Prints the blood's stats. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var cam: Camera3D
var crawler: VoxelBody
var walk_t := 0.0

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name, " ", arena.blood.stats, " runs ", arena.blood.runs.size())
	if "--debug" in OS.get_cmdline_user_args():
		for r in arena.blood.runs:
			print("  run at ", r.d.global_position, " size ", r.d.size, " shown ", r.d.is_visible_in_tree(), " y ", r.d.global_transform.basis.y.normalized())

func _body(at: Vector3, yaw: float) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = at
	b.yaw = yaw
	b.hp = 1e9
	arena.bodies.append(b)
	return b

func _look(from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 55.0
		arena.add_child(cam)
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena._hud_layer.visible = false
	cam.current = true
	cam.global_position = from
	cam.look_at(at)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			arena.frozen = true
			arena.godmode = true
			VoxelBody.immortal = true
			arena.waves.queue.clear()
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			# a pool to walk through: a grunt bled out at (0, -4)
			var g := _body(Vector3(0, 0, -4.0), 0.0)
			for k in 3:
				var r: Dictionary = g.sever(["head", "arm_l", "arm_r"][k])
			for k in 900:
				arena.blood._land(Vector3(randf_range(-0.35, 0.35), 0, -4.0 + randf_range(-0.35, 0.35)))
			g.visible = false
			arena.player.global_position = Vector3(-0.2, 0, -5.0)
			t = 10.0
			step = 1
		1:
			# walk through it and off towards the camera
			walk_t += dt
			var k := clampf(walk_t / 3.5, 0.0, 1.0)
			arena.player.global_position = Vector3(-0.2, 0, -5.0).lerp(Vector3(2.2, 0, 2.5), k)
			if k >= 1.0:
				arena.cam.get_children().map(func(c): c.visible = false)
				_look(Vector3(1.9, 1.3, -0.6), Vector3(0.5, 0, -2.4))
				t = 20.0
				step = 2
		2:
			if t > 20.2:
				_shot("blood_prints")
				step = 3
		3:
			# a grunt with both shins off, dragged along the floor (as crawling)
			crawler = _body(Vector3(-6.0, 0, -2.0), PI * 0.5)
			crawler.sever("shin_l")
			crawler.sever("shin_r")
			walk_t = 0.0
			step = 4
		4:
			walk_t += dt
			crawler.position = Vector3(-6.0, 0, -2.0).lerp(Vector3(-3.2, 0, -2.6), clampf(walk_t / 4.0, 0.0, 1.0))
			if walk_t > 4.3:
				_look(Vector3(-2.0, 1.6, -0.6), Vector3(-4.6, 0.0, -2.3))
				t = 25.0
				step = 5
		5:
			if t > 25.2:
				_shot("blood_crawl")
				step = 6
		6:
			# shot in the chest and shoulder, standing: blood runs down it
			var b := _body(Vector3(4.0, 0, -8.0), 0.0)
			var eye := Vector3(4.0, 1.4, -5.0)
			for aim in [Vector3(4.12, 1.25, -8.0), Vector3(3.8, 1.45, -8.0), Vector3(4.3, 1.5, -8.0), Vector3(3.95, 0.95, -8.0)]:
				arena.fire(eye, ((aim as Vector3) - eye).normalized(), 1, 0.0, 2.6)
			t = 30.0
			step = 7
		7:
			if t > 35.5:
				_look(Vector3(4.5, 1.4, -6.7), Vector3(4.0, 1.1, -8.0))
				step = 8
		8:
			if t > 35.7:
				_shot("blood_runs")
				step = 9
		9:
			# first person, the bat out, bloodied
			cam.current = false
			arena.cam.current = true
			arena._hud_layer.visible = true
			arena.player.global_position = Vector3(8.0, 0, 6.0)
			arena.look_yaw = 0.0
			arena.look_pitch = -0.15
			arena._switch(func(): arena.loadout.select(arena.loadout.index_of("bat")))
			arena.loadout.switch_t = 0.0
			for k in 6:
				arena.blood.weapon_hit(arena.melee["bat"], 40)
			t = 40.0
			step = 10
		10:
			if t > 41.5:
				_shot("blood_bat")
				step = 11
		11:
			return true
	return false
