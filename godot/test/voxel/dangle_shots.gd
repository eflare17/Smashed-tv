extends SceneTree
## Screenshots of the hanging limbs (not headless: under a display). -- --out=dir. Each sheet is four frames, a fifth of
## a second apart, left to right then down:
## dangle_close: close up on a grunt's forearm hanging by the skin of its elbow (the stretched strip, the blood dripping),
##   shoved so it swings; dangle_walk: a grunt with a hanging forearm walking at you, the arm flopping; dangle_knee: a
##   shin hanging from a knee shot through, shoved so it swings; dangle_tear: strained through, the forearm tearing
##   off. Plus dangle_hanging (one close frame, big) and dangle_bone (front on: the broken bone in the gap). Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var g: VoxelBody
var frames: Array[Image] = []
var _next_frame := 0.0
var _sheet := ""

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _grab() -> void:
	await RenderingServer.frame_post_draw
	frames.append(root.get_texture().get_image())

# four frames on one sheet (each half size)
func _save_sheet(name: String) -> void:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var sheet := Image.create(w, h, false, frames[0].get_format())
	for i in mini(4, frames.size()):
		var f: Image = frames[i].duplicate()
		f.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(f, Rect2i(0, 0, w / 2, h / 2), Vector2i((i % 2) * (w / 2), (i / 2) * (h / 2)))
	sheet.save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)
	frames.clear()

func _body(at: Vector3, yaw: float) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = at
	b.yaw = yaw
	b.hp = 1e9
	b.speed = 1.4
	b.died.connect(arena._on_died)
	arena.bodies.append(b)
	return b

func _clear() -> void:
	for x in arena.bodies:
		x.queue_free()
	arena.bodies.clear()

func _tunnel(b: VoxelBody, nm: String, r: float, below: int) -> void:
	for k in 3:
		var p: Dictionary = b.parts[nm]
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var aim := b._joint_in(p, int(p.bone)) + Vector3(0, -below - k, 0)
		var best := -1
		var bd := INF
		for i in cells.size():
			if cells[i] == VoxelBody.BONE_V:
				var d := Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)).distance_to(aim)
				if d < bd:
					bd = d
					best = i
		var w := b._cell_world(nm, best)
		b.carve(w + Vector3(0, 0, 0.3), w - Vector3(0, 0, 0.3), r)
		if b.loose.has(nm):
			return

func _hold(b: VoxelBody) -> void:
	for nm in b._dangle:
		b._dangle[nm].strain = -99.0          # (kept on for the pictures)

var shot_cam: Camera3D

# a camera of its own for the pictures (the HUD and your gun out of the way), from, looking at
func _look(from: Vector3, at: Vector3) -> void:
	if shot_cam == null:
		shot_cam = Camera3D.new()
		shot_cam.fov = 55.0
		arena.add_child(shot_cam)
		arena._hud_layer.visible = false
		arena.net_menu.visible = false
		arena.settings_menu.visible = false
	shot_cam.current = true
	shot_cam.global_position = from
	shot_cam.look_at(at)
	arena.player.global_position = Vector3(0, 0, 4)        # (you, out of the way)

# four frames, every 0.2 s from now, then the sheet
func _start_sheet(name: String) -> void:
	_sheet = name
	_next_frame = t
	frames.clear()

func _sheet_step() -> bool:
	if _sheet == "":
		return true
	if frames.size() >= 4:
		_save_sheet(_sheet)
		_sheet = ""
		return true
	if t >= _next_frame:
		_next_frame = t + 0.25
		_grab()
	return false

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if not _sheet_step():
		return false
	match step:
		0:
			# close up: the elbow shot through, shoved, swinging
			arena.frozen = true
			_clear()
			g = _body(Vector3(0, 0, -2.0), 0.0)
			_tunnel(g, "forearm_l", 0.03, 2)
			_hold(g)
			var elbow: Vector3 = g.skeleton.global_transform * g.skeleton.get_bone_global_pose(int(g.parts.forearm_l.bone)).origin
			_look(elbow + Vector3(0.75, 0.05, 0.85), elbow + Vector3(0, -0.2, 0))
			step = 1
			t = 10.0
		1:
			if t > 11.0:
				g.knock = Vector3(2.5, 0, 0.8)
				t = 20.0
				step = 2
		2:
			if t > 20.15:
				_start_sheet("dangle_close")
				step = 3
		3:
			t = 30.0
			step = 4
		4:
			if t > 32.5:
				_shot("dangle_hanging")
				step = 41
		41:
			if t > 32.8:
				# front on, low: the broken bone in the gap
				var el: Vector3 = g.skeleton.global_transform * g.skeleton.get_bone_rest(int(g.parts.forearm_l.bone)).origin
				el = g.skeleton.global_transform * g.skeleton.get_bone_global_pose(g.model.bone_parent[int(g.parts.forearm_l.bone)]) * g.skeleton.get_bone_rest(int(g.parts.forearm_l.bone)).origin
				_look(el + Vector3(0.1, -0.12, 0.55), el + Vector3(0, -0.04, 0))
				step = 42
		42:
			if t > 33.3:
				_shot("dangle_bone")
				step = 43
		43:
			if t > 33.6:
				step = 5
		5:
			if t > 33.0:
				# walking at you: the forearm flopping
				_clear()
				arena.frozen = false
				arena.godmode = true
				g = _body(Vector3(0.3, 0, -5.0), 0.0)
				_tunnel(g, "forearm_l", 0.03, 2)
				_hold(g)
				_look(Vector3(0.6, 1.4, -1.0), Vector3(0.2, 1.0, -5.0))
				arena.player.global_position = Vector3(0, 0, -1.0)
				t = 40.0
				step = 6
		6:
			_look(Vector3(1.9, 1.25, -1.2), g.global_position + Vector3(0, 0.85, 0))
			arena.player.global_position = Vector3(0, 0, 0.5)
			if t > 41.0:
				_start_sheet("dangle_walk")
				step = 7
		7:
			if t > 42.2:
				# a knee shot through: the shin hanging (standing still, shoved so it swings)
				_clear()
				arena.frozen = true
				g = _body(Vector3(0, 0, -3.0), 0.0)
				_tunnel(g, "shin_r", 0.025, 3)
				_hold(g)
				var knee: Vector3 = g.skeleton.global_transform * g.skeleton.get_bone_global_pose(int(g.parts.shin_r.bone)).origin
				_look(knee + Vector3(-0.6, 0.3, 1.0), knee + Vector3(0, -0.14, 0))
				t = 50.0
				step = 8
		8:
			if t > 50.6 and not g.has_meta("kicked"):
				g.set_meta("kicked", true)
				g.knock = Vector3(-2.0, 0, 0.6)
			if t > 50.75:
				_start_sheet("dangle_knee")
				step = 9
		9:
			if t > 52.2:
				# strained through: tearing off
				_clear()
				arena.frozen = true
				g = _body(Vector3(0, 0, -2.0), 0.0)
				_tunnel(g, "forearm_l", 0.03, 2)
				var elbow2: Vector3 = g.skeleton.global_transform * g.skeleton.get_bone_global_pose(int(g.parts.forearm_l.bone)).origin
				_look(elbow2 + Vector3(1.0, 0.1, 1.1), elbow2 + Vector3(0, -0.3, 0))
				g.knock = Vector3(2.5, 0, 0)
				t = 60.0
				step = 10
		10:
			if t > 60.6:
				for nm in g._dangle:
					g._dangle[nm].strain = 0.97
				_start_sheet("dangle_tear")
				_next_frame = t + 0.05
				step = 11
		11:
			return true
	return false
