extends SceneTree
## A clip (with --write-movie): the dirt along Luna Park's wall and its bushes (VoxelParkDirt, VoxelParkBushes). A
## look along the strip from outside; digging down beside the wall with the shovel (sped up); walking down the
## trench, under the wall and into the park; a bush cut down with the chainsaw, dragged over to the hole (E), and
## pulled over the top of you down it: hidden. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var patch: VoxelParkDirt.Patch
var label: Label
var cam: Camera3D
var t := 0.0
var step := 0
var along := 8.0
var out := 1.0                  # which way across the patch (its z) is outside the park
var fwd := Vector3.ZERO         # the patch's +z, level (world)
var bush := -1
var next_click := 0.0
var dug := 0
var key := KEY_NONE

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	var cl := CanvasLayer.new()
	cl.layer = 100
	root.add_child(cl)
	label = Label.new()
	label.position = Vector2(80, 70)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)

func _at(a: float, across: float, y: float) -> Vector3:
	return patch.to_global(Vector3(a, y, across))

func _mouse(button: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _walk(k: Key) -> void:
	if k == key:
		return
	if key != KEY_NONE:
		_key(key, false)
	if k != KEY_NONE:
		_key(k, true)
	key = k

func _put(p: Vector3, yaw: float, pitch := 0.0) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

# the yaw that looks from a to b (VoxelArena: you look along (-sin yaw, 0, -cos yaw))
static func _yaw(a: Vector3, b: Vector3) -> float:
	return atan2(-(b.x - a.x), -(b.z - a.z))

func _weapon(id: String) -> void:
	arena._switch(func(): arena.loadout.select(arena.loadout.index_of(id)))

func _film(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.current = true

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 and step == 0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			sk.dirt.finish()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			patch = sk.dirt.patches[mini(3, sk.dirt.patches.size() - 1)]
			along = patch.x1 * VoxelTerrain.CELL / 2.0
			var z := patch.global_transform.basis.z
			fwd = Vector3(z.x, 0, z.z).normalized()
			var p := _at(along, 2.0, 0.0)
			out = -1.0 if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), sk.dirt.ring) else 1.0
			cam = Camera3D.new()
			cam.fov = 60.0
			arena.add_child(cam)
			_weapon("shovel")
			_put(_at(along, out * 2.2, 0.05), _yaw(_at(along, out * 2.2, 0), _at(along, 0, 0)), -0.85)
			step = 1
			t = 0.0
		1:
			# along the strip, from outside
			label.text = "Dirt along Luna Park's wall, bushes in it"
			_film(_at(along - 9.0, out * 9.0, 4.5), _at(along + 3.0, 0.0, 0.3))
			if t > 4.0:
				arena.cam.current = true
				step = 2
				t = 0.0
				next_click = 0.2
		2:
			# digging down beside the wall (each swing a bigger bite than the rusty shovel's: sped up)
			label.text = "Dig down beside the wall  (sped up)"
			if t >= next_click:
				next_click += 0.45
				_mouse(MOUSE_BUTTON_LEFT, true)
				_mouse(MOUSE_BUTTON_LEFT, false)
				var k := dug
				dug += 1
				var a := out * (1.5 - (k % 6) * 0.25)
				var y := -0.1 - (k / 6) * 0.45
				for w in [-0.5, 0.0, 0.5]:
					patch.wdig(_at(along + w, a, y), 0.62, VoxelTerrain.STONE)
			if t > 6.5:
				# (the rest dug while we weren't looking: down to 2.7 m, and under the wall)
				var a := -3.2
				while a <= 3.2:
					var ys := [-2.2, -1.7, -1.2, -0.8] if absf(a) < 0.75 else [-2.2, -1.7, -1.2, -0.8, -0.3, 0.2]
					for yy in ys:
						for w in [-0.5, 0.0, 0.5]:
							patch.wdig(_at(along + w, a, yy), 0.62, VoxelTerrain.STONE)
					a += 0.25
				patch.finish()
				_put(_at(along, out * 2.7, -2.3), _yaw(_at(along, out, 0), _at(along, -out, 0)), 0.05)
				step = 3
				t = 0.0
		3:
			label.text = "...and under it"
			if t > 0.6:
				_walk(KEY_W)
			if t > 2.4:
				_walk(KEY_NONE)
				label.text = "...into the park"
				arena.look_pitch = lerpf(arena.look_pitch, 1.0, dt * 2.0)
			if t > 4.4:
				# back outside, by a bush, the chainsaw out
				var best := -1
				var bd := INF
				for i in sk.bushes.list.size():
					var b: Dictionary = sk.bushes.list[i]
					var l := patch.to_local(b.at)
					if b.state == "grow" and signf(l.z) == out and absf(l.x - along) > 2.0:
						var d := (b.at as Vector3).distance_to(_at(along, out * 2.0, 0))
						if d < bd:
							bd = d
							best = i
				bush = best
				var b: Dictionary = sk.bushes.list[bush]
				var c: Vector3 = (b.at as Vector3) + Vector3(0, VoxelParkBushes.MID, 0)
				var away := (_at(along, out * 3.2, 0) - c)
				away.y = 0
				var stand := c + away.normalized() * 1.1
				stand.y = 0.05
				_weapon("chainsaw")
				_put(stand, _yaw(stand, c), -0.35)
				step = 4
				t = 0.0
		4:
			label.text = "Cut a bush down"
			if t > 0.5 and t < 3.0:
				_mouse(MOUSE_BUTTON_LEFT, true)
			if t > 3.0 or (t > 0.5 and sk.bushes.list[bush].state != "grow"):
				_mouse(MOUSE_BUTTON_LEFT, false)
				if sk.bushes.list[bush].state == "grow":       # (the blade missed it: cut it anyway)
					var b: Dictionary = sk.bushes.list[bush]
					var c: Vector3 = (b.at as Vector3) + Vector3(0, VoxelParkBushes.MID, 0)
					for k in VoxelParkBushes.HITS:
						b.cool = 0.0
						sk.bushes.strike(arena.cam.global_position, (c - arena.cam.global_position).normalized(), 3.0)
				step = 5
				t = 0.0
		5:
			if t > 1.2:
				_weapon("shovel")
				var b: Dictionary = sk.bushes.list[bush]
				var hole := _at(along, out * 1.2, 0)
				var stand: Vector3 = (b.at as Vector3).lerp(hole, 0.0) + ((b.at as Vector3) - hole).normalized() * -0.6
				stand.y = 0.05
				_put(stand, _yaw(stand, hole), 0.0)
				_key(KEY_E, true)
				_key(KEY_E, false)
				step = 6
				t = 0.0
		6:
			# dragging it over to the hole, and down in
			label.text = "Drag it to the hole  (E)"
			var pp := arena.player.global_position
			var behind := Vector3(sin(arena.look_yaw), 0, cos(arena.look_yaw))
			_film(pp + behind * 5.5 + Vector3(0, 4.0, 0) + fwd.cross(Vector3.UP) * 2.0, pp + Vector3(0, 0.5, 0))
			var hole := _at(along, out * 0.9, 0)
			arena.look_yaw = _yaw(pp, hole)
			if t > 0.3:
				_walk(KEY_W)
			if pp.y < -1.5 or t > 6.0:
				_walk(KEY_NONE)
				step = 7
				t = 0.0
		7:
			label.text = "...and pull it over you"
			var pp := arena.player.global_position
			_film(pp + Vector3(0, 6.0, 0) + fwd * out * 4.0, pp)
			if t > 0.8 and sk.bushes.dragging >= 0:
				_key(KEY_E, true)
				_key(KEY_E, false)
			if t > 3.0:
				arena.cam.current = true
				arena.look_pitch = 1.2
				step = 8
				t = 0.0
		8:
			label.text = "Hidden" if sk.bushes.hidden() else "(not hidden?)"
			if t > 3.0:
				quit()
				return true
	return false
