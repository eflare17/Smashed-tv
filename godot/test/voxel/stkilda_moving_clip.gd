extends SceneTree
## A clip (with --write-movie): every weapon on a St Kilda wall while you move, the way you'd play: stood before the
## wall, walking left and right along it (A / D) and swinging the view about (the mouse) the whole time, clicking
## again and again (or the button held, for the chainsaw, laser, flamethrower and freeze ray). Each weapon has its own
## bit of the biggest building's longest wall, its name in the corner. Owned by the St Kilda session.

# weapon, metres from the wall, look up (radians), held (or a click every so many seconds)
const RUNS := [
	["hammer", 1.8, 0.0, false, 1.0],
	["bat", 1.5, 0.0, false, 0.6],
	["chainsaw", 1.0, -0.1, true, 0.0],
	["spear", 2.0, 0.0, false, 0.7],
	["sword", 1.6, 0.0, false, 0.45],
	["laser", 5.0, 0.0, true, 0.0],
	["harpoon", 6.0, 0.0, false, 0.9],
	["gravity", 6.0, 0.0, false, 0.9],
	["pick", 1.8, 0.0, false, 0.6],
	["flamethrower", 3.0, 0.0, true, 0.0],
	["freezeray", 5.0, 0.0, true, 0.0],
	["shovel", 3.4, -0.75, false, 0.5],         # (back where the hammer's bricks landed, looking down at them)
]
const GO := 4.0            # seconds of each weapon
const WALK := 4.5          # walking speed (VoxelArena)

var arena: VoxelArena
var sk: VoxelStKilda
var b: VoxelBreakables.Building
var label: Label
var t := 0.0
var step := 0
var run := 0
var phase := 0
var c0 := 0
var gap := 3
var reach := 1.0           # how far each way you walk (m)
var yaw0 := 0.0
var pitch0 := 0.0
var next_click := 0.0
var key := KEY_NONE

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	var cl := CanvasLayer.new()
	cl.layer = 100
	root.add_child(cl)
	label = Label.new()
	label.position = Vector2(560, 150)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)

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

# the view to (yaw, pitch), by moving the mouse as you would
func _look(yaw: float, pitch: float) -> void:
	var sens := 0.0025 * arena.cam.fov / 80.0 * arena.mouse_sens
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(-(yaw - arena.look_yaw) / sens, -(pitch - arena.look_pitch) / sens)
	Input.parse_input_event(e)

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
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# the longest straight wall of the town's biggest building, shared out between the weapons
			for bb in sk.breaks.list:
				if not bb.over and (b == null or bb.alive.size() > b.alive.size()):
					b = bb
			var best := 0
			var run_n := 0
			for k in b.cols.size():
				run_n = run_n + 1 if k > 0 and (b.cols[k].dir as Vector2).is_equal_approx(b.cols[k - 1].dir) else 1
				if run_n > best:
					best = run_n
					c0 = k - run_n + 1
			gap = maxi(3, (best - 2) / (RUNS.size() - 1))
			reach = maxf(0.8, gap * 0.5 - 0.4)
			c0 += 1
			print("wall %d blocks, %d apart, walking %.1f m each way" % [best, gap, reach])
			step = 1
			t = 0.0
		1:
			var r: Array = RUNS[run]
			match phase:
				0:
					# stood before its own bit of the wall, at one end of the walk, facing it, the weapon out
					var c := c0 + gap / 2 if String(r[0]) == "shovel" else c0 + gap / 2 + run * gap
					c = mini(c, b.cols.size() - 1)
					var n: Vector2 = b.cols[c].n
					yaw0 = atan2(n.x, n.y)
					pitch0 = float(r[2])
					var right := Vector3(cos(yaw0), 0, -sin(yaw0))
					var at := b.block_at(c, 0) + Vector3(n.x, 0, n.y) * (float(r[1]) + VoxelBreakables.THICK * 0.5) - right * reach
					sk._put(Vector3(at.x, 0.05, at.z), yaw0, pitch0)
					arena._switch(func(): arena.loadout.select(arena.loadout.index_of(String(r[0]))))
					label.text = String(r[0])
					phase = 1
					t = 0.0
				1:
					if t > 0.6:
						if bool(r[3]):
							_mouse(MOUSE_BUTTON_LEFT, true)
						next_click = 0.0
						phase = 2
						t = 0.0
				2:
					# walking right then left along the wall, the view swinging about, hitting all the while
					var leg := 2.0 * reach / WALK
					_walk(KEY_D if int(t / leg) % 2 == 0 else KEY_A)
					var sweep := 0.3 if float(r[1]) < 3.0 else 0.2
					_look(yaw0 + sweep * sin(TAU * t / 1.7), pitch0 + 0.15 * sin(TAU * t / 1.1))
					if not bool(r[3]) and t >= next_click:
						_mouse(MOUSE_BUTTON_LEFT, true)
						_mouse(MOUSE_BUTTON_LEFT, false)
						next_click = t + float(r[4])
					if String(r[0]) == "freezeray" and t > GO - 1.0 and t - dt <= GO - 1.0:
						_mouse(MOUSE_BUTTON_LEFT, false)          # then its ice shot at what's frozen
						_mouse(MOUSE_BUTTON_RIGHT, true)
						_mouse(MOUSE_BUTTON_RIGHT, false)
					if t > GO:
						_walk(KEY_NONE)
						if bool(r[3]):
							_mouse(MOUSE_BUTTON_LEFT, false)
						phase = 3
						t = 0.0
				3:
					if t > 0.8:
						run += 1
						phase = 0
						t = 0.0
						if run >= RUNS.size():
							step = 99
		99:
			print("chipped %d" % b.chipped)
			quit(0)
	return false
