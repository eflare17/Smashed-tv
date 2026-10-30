extends SceneTree
## A clip of Luna Park's buildings smashed by three guns, for the movie maker (under a display: godot --write-movie
## out.avi --fixed-fps 30 --rendering-method forward_plus -s res://test/voxel/stkilda_luna_clip.gd): the pistol at the
## Ghost Train, the shotgun at Cafe Luna, the grenade launcher's sticky bombs along Luna Palace's front (R sets them
## off), each fired with clicks and keys as you would, the view sweeping along the wall; the bricks fall and pile up.
## Owned by the St Kilda session.

const PARTS := [
	# weapon, building, the spot to face (VoxelStKilda's luna_spots; "": where you arrive), columns along from there
	# (clear of the crowd), metres out, look up, seconds firing, seconds a left click (0: none), seconds a right click
	# (0: none), R after, mouse sweep a frame (px)
	["pistol", "GhostTrain", "Luna Park - Ghost Train", 0, 11.0, 0.12, 5.0, 0.22, 0.0, false, 3.0],
	["shotgun", "CafeLuna", "", 0, 7.0, 0.1, 5.0, 0.75, 0.0, false, 2.5],
	["grenades", "LunaPalace", "Luna Park - Luna Palace (dodgems)", 10, 12.0, 0.0, 4.2, 0.0, 0.65, true, 2.5],
]

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var part := -1
var phase := 0                  # 0 a look at it, 1 firing, 2 watching it come down
var left_t := 0.0
var right_t := 0.0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _click(button: MouseButton) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)

func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)

func _look(dx: float) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(dx, 0)
	Input.parse_input_event(e)

# (the biggest, where a model has more than one box: Luna Palace's main building, not its tower)
func _named(nm: String) -> VoxelBreakables.Building:
	var got: VoxelBreakables.Building = null
	for bb in sk.breaks.list:
		if String(bb.data.get("id", "")) == nm and (got == null or bb.alive.size() > got.alive.size()):
			got = bb
	return got

# you, `out` m before the column of b nearest `me` (on the side facing it) and `along` more, facing it, looking up `up`
func _stand(b: VoxelBreakables.Building, me: Vector3, along: int, out: float, up: float) -> void:
	var c := 0
	var best := INF
	for j in b.cols.size():
		var p := b.block_at(j, 0)
		var to := Vector2(me.x - p.x, me.z - p.z).normalized()
		var d := p.distance_to(me) * (2.0 - (b.cols[j].n as Vector2).dot(to))
		if d < best:
			best = d
			c = j
	c = (c + along) % b.cols.size()
	var n: Vector2 = b.cols[c].n
	var at := b.block_at(c, 0) + Vector3(n.x, 0, n.y) * out
	sk._put(Vector3(at.x, 0.05, at.z), atan2(n.x, n.y), up)

func _next() -> void:
	part += 1
	if part >= PARTS.size():
		quit()
		return
	var p: Array = PARTS[part]
	var b := _named(p[1])
	var spot = sk.get_meta("luna_spots", {}).get(p[2]) if p[2] != "" else null
	_stand(b, spot[0] if spot else sk.arrive_spot()[0], p[3], p[4], p[5])
	arena._switch(func(): arena.loadout.select(arena.loadout.index_of(p[0])))
	phase = 0
	t = 0.0
	left_t = 0.0
	right_t = 0.0

func _process(dt: float) -> bool:
	t += dt
	if part == -1:
		if t < 2.0:
			return false
		arena.godmode = true
		arena.waves.queue.clear()
		sk = arena.stkilda
		sk.go()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_next()
		return false
	var p: Array = PARTS[part]
	match phase:
		0:
			if t > 1.2:
				phase = 1
				t = 0.0
		1:
			# firing as the view sweeps along the wall: a quarter one way, half the other, a quarter back
			var T := float(p[6])
			_look(float(p[10]) * (-1.0 if t < T * 0.25 or t > T * 0.75 else 1.0))
			left_t -= dt
			right_t -= dt
			if float(p[7]) > 0.0 and left_t <= 0.0:
				left_t = float(p[7])
				_click(MOUSE_BUTTON_LEFT)
			if float(p[8]) > 0.0 and right_t <= 0.0:
				right_t = float(p[8])
				_click(MOUSE_BUTTON_RIGHT)
			if t > T:
				if bool(p[9]):
					_key(KEY_R)
				phase = 2
				t = 0.0
		2:
			if t > (7.0 if bool(p[9]) else 2.5):
				_next()
	return false
