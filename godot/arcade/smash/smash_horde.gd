extends Node3D
## Smash arcade: the grunt pool. Grunts are plain data in fixed-size packed arrays (live ones packed at the front,
## a dead one swaps with the last), so nothing is created or freed during play. They're drawn by two MultiMeshes,
## one per walk frame, filled straight from a float buffer each frame. A uniform grid (rebuilt each frame with a
## counting sort) finds neighbours for the crowd push-apart and for bullet hits.

const SmashVox := preload("smash_vox.gd")

const MAX := 4096
const RADIUS := 0.33
const INSIDE := 255
## Cells just wider than a grunt pair (2 * RADIUS), so the 3x3 cells around a grunt hold every possible overlap.
const CELL := 0.7
const INV_CELL := 1.0 / CELL
## Grid covers -GRID_HALF..GRID_HALF metres on X and Z, enough for the corridors behind the doors.
const GRID_HALF := 20.0
const GRID_W := 58
## Crowd overlaps handled per grunt per pass are capped so a huge pile-up degrades the push-apart, not the frame rate.
const MAX_NEIGHBOURS := 8

## Door inward normals: N, S, W, E.
const DOOR_N := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

var half := 12.0
var door_half := 1.5

var count := 0
var pos := PackedVector2Array()
var facing := PackedVector2Array()
var speed := PackedFloat32Array()
var phase := PackedFloat32Array()
## Each grunt veers a little off the straight line (stored as cos/sin) so they don't form one conga line.
var veer := PackedVector2Array()
## INSIDE, or the door it is still walking in through.
var door := PackedByteArray()
var dead := PackedByteArray()

## Kills this frame (filled by kill(), read and cleared by the scene root).
var kill_pos := PackedVector2Array()
var kill_dir := PackedVector2Array()

var _cell_of := PackedInt32Array()
var _cell_start := PackedInt32Array()
var _cell_fill := PackedInt32Array()
var _cell_items := PackedInt32Array()

## Each grunt runs the push-apart every other frame (odd / even indices alternate), at double strength.
var _tick := 0

var _mm: Array[MultiMesh] = []
var _buf_a := PackedFloat32Array()
var _buf_b := PackedFloat32Array()

func _init() -> void:
	name = "SmashHorde"
	pos.resize(MAX)
	facing.resize(MAX)
	veer.resize(MAX)
	speed.resize(MAX)
	phase.resize(MAX)
	door.resize(MAX)
	dead.resize(MAX)
	_cell_of.resize(MAX)
	_cell_items.resize(MAX)
	_cell_start.resize(GRID_W * GRID_W + 1)
	_buf_a.resize(MAX * 12)
	_buf_b.resize(MAX * 12)
	# the basis' Y row never changes (turning is only about Y): set it once, draw() skips those floats
	for i in MAX:
		_buf_a[i * 12 + 5] = 1.0
		_buf_b[i * 12 + 5] = 1.0
	var mat := SmashVox.flat_material()
	for f in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = SmashVox.grunt_mesh(f)
		mm.mesh.surface_set_material(0, mat)
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-GRID_HALF, -1, -GRID_HALF), Vector3(GRID_HALF * 2, 4, GRID_HALF * 2))
		add_child(mi)
		_mm.append(mm)

func clear() -> void:
	count = 0
	kill_pos.clear()
	kill_dir.clear()

## Puts a grunt in the corridor behind door `d`, `depth` metres back from the wall. False if the pool is full.
func spawn(d: int, depth: float, spd: float) -> bool:
	if count >= MAX:
		return false
	var n: Vector2 = DOOR_N[d]
	var t := Vector2(n.y, -n.x)
	var i := count
	count += 1
	pos[i] = -n * (half + depth) + t * randf_range(-door_half + RADIUS, door_half - RADIUS)
	facing[i] = n
	speed[i] = spd
	phase[i] = randf() * TAU
	var a := randf_range(-0.45, 0.45)
	veer[i] = Vector2(cos(a), sin(a))
	door[i] = d
	dead[i] = 0
	return true

## Debug/bench helper: a grunt already inside the arena.
func spawn_inside(p: Vector2, spd: float) -> bool:
	if not spawn(0, 1.0, spd):
		return false
	pos[count - 1] = p
	door[count - 1] = INSIDE
	return true

func build_grid() -> void:
	_cell_start.fill(0)
	for i in count:
		var p := pos[i]
		var c := _cell(p.x, p.y)
		_cell_of[i] = c
		_cell_start[c + 1] += 1
	for c in GRID_W * GRID_W:
		_cell_start[c + 1] += _cell_start[c]
	_cell_fill = _cell_start.duplicate()
	for i in count:
		var c := _cell_of[i]
		_cell_items[_cell_fill[c]] = i
		_cell_fill[c] += 1

func _cell(x: float, z: float) -> int:
	var cx := clampi(int((x + GRID_HALF) * INV_CELL), 0, GRID_W - 1)
	var cz := clampi(int((z + GRID_HALF) * INV_CELL), 0, GRID_W - 1)
	return cz * GRID_W + cx

## Moves every grunt toward `target` and pushes them apart. Returns true if one touched the target
## (within `touch` metres) while `can_touch`.
func step(delta: float, target: Vector2, touch: float, can_touch: bool) -> bool:
	var touched := false
	var touch2 := touch * touch
	var r2 := (RADIUS * 2) * (RADIUS * 2)
	var lim := half - RADIUS
	var lat := door_half - RADIUS
	for i in count:
		var p := pos[i]
		var d := door[i]
		var dir: Vector2
		if d == INSIDE:
			var to := target - p
			var l2 := to.length_squared()
			if l2 > 0.0001:
				dir = to / sqrt(l2)
				if l2 > 9.0:
					var v := veer[i]
					dir = Vector2(dir.x * v.x - dir.y * v.y, dir.x * v.y + dir.y * v.x)
			else:
				dir = facing[i]
		else:
			dir = DOOR_N[d]
		p += dir * (speed[i] * delta)
		if (i + _tick) & 1 == 0:
			# push apart from neighbours in the 3x3 cells around; the items are sorted by cell, so each
			# row of three cells is one contiguous run
			var cx := clampi(int((p.x + GRID_HALF) * INV_CELL), 1, GRID_W - 2)
			var cz := clampi(int((p.y + GRID_HALF) * INV_CELL), 1, GRID_W - 2)
			var push := Vector2.ZERO
			var seen := 0
			for gz in range(cz - 1, cz + 2):
				var c := gz * GRID_W + cx
				for k in range(_cell_start[c - 1], _cell_start[c + 2]):
					var j := _cell_items[k]
					if j == i:
						continue
					var dd := p - pos[j]
					var l2 := dd.length_squared()
					if l2 < r2 and l2 > 0.000001:
						var l := sqrt(l2)
						push += dd * ((RADIUS * 2 - l) / l)
						seen += 1
						if seen >= MAX_NEIGHBOURS:
							break
			p += push * 0.9
		if d == INSIDE:
			p = Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim))
			if can_touch and (p - target).length_squared() < touch2:
				touched = true
		else:
			# still in the corridor: keep within the door's width until clear of the wall
			var n: Vector2 = DOOR_N[d]
			var t := Vector2(n.y, -n.x)
			var depth := p.dot(n) + half
			var side := clampf(p.dot(t), -lat, lat)
			p = n * (depth - half) + t * side
			if depth > RADIUS + 0.1:
				door[i] = INSIDE
		pos[i] = p
		facing[i] = dir
		phase[i] += delta * speed[i] * 2.4
	_tick += 1
	return touched

## Index of a live grunt within `r` of `p`, or -1.
## `r` + RADIUS must stay under CELL.
func hit_test(p: Vector2, r: float) -> int:
	var cx := clampi(int((p.x + GRID_HALF) * INV_CELL), 1, GRID_W - 2)
	var cz := clampi(int((p.y + GRID_HALF) * INV_CELL), 1, GRID_W - 2)
	var rr := (r + RADIUS) * (r + RADIUS)
	for gz in range(cz - 1, cz + 2):
		var c := gz * GRID_W + cx
		for k in range(_cell_start[c - 1], _cell_start[c + 2]):
			var j := _cell_items[k]
			if j < count and dead[j] == 0 and (pos[j] - p).length_squared() < rr:
				return j
	return -1

## Pushes every grunt out of the circle at `c` (a brute's or the boss's body).
func push_out(c: Vector2, r: float) -> void:
	var rr := r + RADIUS
	var span := ceili(rr * INV_CELL)
	var cx := clampi(int((c.x + GRID_HALF) * INV_CELL), span, GRID_W - 1 - span)
	var cz := clampi(int((c.y + GRID_HALF) * INV_CELL), span, GRID_W - 1 - span)
	for gz in range(cz - span, cz + span + 1):
		var row := gz * GRID_W + cx
		for k in range(_cell_start[row - span], _cell_start[row + span + 1]):
			var j := _cell_items[k]
			if j >= count:
				continue
			var d := pos[j] - c
			var l2 := d.length_squared()
			if l2 < rr * rr and l2 > 0.000001:
				pos[j] = c + d * (rr / sqrt(l2))

## Kills the grunts touching the circle at `p` (the shield, the boss's charge).
func kill_near(p: Vector2, r: float) -> void:
	var rr := r + RADIUS
	var span := ceili(rr * INV_CELL)
	var cx := clampi(int((p.x + GRID_HALF) * INV_CELL), span, GRID_W - 1 - span)
	var cz := clampi(int((p.y + GRID_HALF) * INV_CELL), span, GRID_W - 1 - span)
	for gz in range(cz - span, cz + span + 1):
		var row := gz * GRID_W + cx
		for k in range(_cell_start[row - span], _cell_start[row + span + 1]):
			var j := _cell_items[k]
			if j < count and (pos[j] - p).length_squared() < rr * rr:
				kill(j, (pos[j] - p).normalized())

## Kills every grunt (the smart bomb), each blown away from `p`.
func kill_all(p: Vector2) -> void:
	for i in count:
		kill(i, (pos[i] - p).normalized())

func kill(i: int, from_dir: Vector2) -> void:
	if dead[i] != 0:
		return
	dead[i] = 1
	kill_pos.append(pos[i])
	kill_dir.append(from_dir)

## Kills every grunt within `r` of `p` (used to clear the respawn spot).
func kill_radius(p: Vector2, r: float) -> void:
	var r2 := r * r
	for i in count:
		if (pos[i] - p).length_squared() < r2:
			kill(i, (pos[i] - p).normalized())

## Removes this frame's dead (swap with the last live one). Call after all kill()s, before the next build_grid().
func compact() -> void:
	var i := 0
	while i < count:
		if dead[i] != 0:
			count -= 1
			pos[i] = pos[count]
			facing[i] = facing[count]
			speed[i] = speed[count]
			phase[i] = phase[count]
			veer[i] = veer[count]
			door[i] = door[count]
			dead[i] = dead[count]
		else:
			i += 1

func draw() -> void:
	var na := 0
	var nb := 0
	for i in count:
		var p := pos[i]
		var f := facing[i]
		var ph := phase[i]
		var y := absf(sin(ph)) * 0.06
		if int(ph / PI) & 1 == 0:
			var o := na * 12
			na += 1
			_buf_a[o] = f.y; _buf_a[o + 2] = f.x; _buf_a[o + 3] = p.x
			_buf_a[o + 7] = y
			_buf_a[o + 8] = -f.x; _buf_a[o + 10] = f.y; _buf_a[o + 11] = p.y
		else:
			var o := nb * 12
			nb += 1
			_buf_b[o] = f.y; _buf_b[o + 2] = f.x; _buf_b[o + 3] = p.x
			_buf_b[o + 7] = y
			_buf_b[o + 8] = -f.x; _buf_b[o + 10] = f.y; _buf_b[o + 11] = p.y
	_mm[0].buffer = _buf_a
	_mm[0].visible_instance_count = na
	_mm[1].buffer = _buf_b
	_mm[1].visible_instance_count = nb
