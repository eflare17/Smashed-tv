extends SceneTree
## A clip of the night's work (30-31 Oct), for the movie maker (under a display: godot --write-movie out.avi --fixed-fps
## 30 --rendering-method forward_plus -s res://test/voxel/stkilda_night_clip.gd): K and the rain comes in on the
## forecourt (the puddles filled for the clip, not over a minute), a look round; N and night, walking over the puddles
## at Mr Moon; then by day (still raining) a row of blasts at a building's foot and the wall comes away in slabs that
## tip and smash; walking through the pile kicks bricks along, a blast throws them up; and grunts blown at a wall
## tumble, bounce off it and land. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var b: VoxelBreakables.Building
var c := 0
var n := Vector2.ZERO
var k := 0
var group := []

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(key: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = down
	Input.parse_input_event(e)

func _tap(key: Key) -> void:
	_key(key, true)
	_key(key, false)

func _look(dx: float, dy: float = 0.0) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(dx, dy)
	Input.parse_input_event(e)

func _boom(p: Vector3) -> void:
	arena.melee["grenades"].explode(p, "bench")

func _next() -> void:
	step += 1
	t = 0.0

func _process(dt: float) -> bool:
	t += dt
	if step == 0 and t < 2.0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			var s := sk.arrive_spot()
			sk._put(s[0], float(s[1]), 0.05)
			_next()
		1:
			# dry, then K: the rain comes in
			if t > 1.5 and not sk.rain.raining:
				_tap(KEY_K)
				sk.rain.fill = 0.6
			if sk.rain.raining:
				sk.rain.fill = minf(1.0, sk.rain.fill + dt * 0.1)
			if t > 6.5:
				_next()
		2:
			# a look round: right, then back past the start to the left
			_look(4.0 if t < 3.0 else -4.0)
			if t > 6.0:
				_tap(KEY_N)
				_next()
		3:
			# night: walking over the puddles toward Mr Moon, looking down at them a little
			if t < 0.05:
				var s := sk.arrive_spot()
				sk._put((s[0] as Vector3) + Vector3(0, 0, 0), float(s[1]), -0.12)
			if t > 2.0 and t < 2.1:
				_key(KEY_W, true)
			if t > 5.5:
				_key(KEY_W, false)
				_tap(KEY_N)
				_next()
		4:
			# by day again (still raining): a big building's wall, from across the street
			if t > 2.5:
				for bb in sk.breaks.list:
					if not bb.over and (b == null or bb.alive.size() > b.alive.size()):
						b = bb
				c = b.cols.size() / 2
				n = b.cols[c].n
				sk._put(b.block_at(c, 0) + Vector3(n.x, 0, n.y) * 22.0, atan2(n.x, n.y), 0.22)
				k = -4
				_next()
		5:
			# a row of blasts along its foot, one every 0.25 s
			if t > 1.2 and k <= 4 and t > 1.2 + (k + 4) * 0.25:
				_boom(b.block_at((c + k * 2 + b.cols.size()) % b.cols.size(), 0) + Vector3(n.x, 0, n.y) * 0.4)
				k += 1
			if t > 9.0:
				# walk at the pile
				var foot := b.block_at(c, 0) + Vector3(n.x, 0, n.y) * 1.5
				sk._put(Vector3(foot.x, 0.05, foot.z) + Vector3(n.x, 0, n.y) * 7.0, atan2(n.x, n.y), -0.35)
				_key(KEY_W, true)
				_next()
		6:
			if t > 2.2:
				_key(KEY_W, false)
				_next()
		7:
			# step back, and a blast on the pile
			if t < 0.1:
				var foot := b.block_at(c, 0) + Vector3(n.x, 0, n.y) * 1.5
				sk._put(Vector3(foot.x, 0.05, foot.z) + Vector3(n.x, 0, n.y) * 12.0, atan2(n.x, n.y), -0.1)
			if t > 0.8 and t < 0.85:
				_boom(b.block_at(c, 0) + Vector3(n.x, 0, n.y) * 2.0 + Vector3.UP * 0.2)
			if t > 4.0:
				_next()
		8:
			# grunts by another building's wall, a grenade among them: blown at the wall, off it, tumbling
			var wall: VoxelBreakables.Building = null
			for bb in sk.breaks.list:
				if bb != b and not bb.over and bb.whole and bb.alive.size() > 60:
					wall = bb
					break
			var wc := wall.cols.size() / 3
			var wn: Vector2 = wall.cols[wc].n
			var at := wall.block_at(wc, 0) + Vector3(wn.x, 0, wn.y) * 4.0
			for j in 5:
				var g := arena.spawn_kind("grunt", Vector3(at.x, 0.0, at.z) + Vector3(wn.y, 0, -wn.x) * (j - 2) * 1.2)
				g.set_meta("park", true)
				group.append(g)
			sk._put(Vector3(at.x, 0.05, at.z) + Vector3(wn.x, 0, wn.y) * 10.0 + Vector3(wn.y, 0, -wn.x) * 4.0, atan2(wn.x, wn.y) + 0.35, 0.05)
			set_meta("boom_at", Vector3(at.x, 0.3, at.z) + Vector3(wn.x, 0, wn.y) * 1.6)
			_next()
		9:
			if t > 1.5 and t < 1.55:
				_boom(get_meta("boom_at"))
			if t > 7.0:
				quit()
	return false
