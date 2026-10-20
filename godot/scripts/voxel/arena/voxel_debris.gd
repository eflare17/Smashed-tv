class_name VoxelDebris
extends MultiMeshInstance3D
## The cubes a shot or a cut knocks out: thousands of little cubes in one draw call (a MultiMesh with a colour
## each), flung out, falling and bouncing. Once one comes to rest it stays where it lies (the owner, 20 Oct): it moves
## to a second MultiMesh that never changes unless a cube is picked up, so a floor covered in them costs nothing a
## frame. The vacuum gun sucks them up (the owner, 20 Oct): the ones in a cone in front of its nozzle lift off, fly in
## and count up as resources (blocks, meat, bone, brain); let go and the ones in the air fall again. Owned by the
## voxel session.

const MAX := 8000               # flying at once
const MAX_LIE := 150000         # lying on the floor (the oldest go when it's full)
const SUCK_RANGE := 7.0         # metres the vacuum reaches
const SUCK_COS := 0.9           # its cone (about 25 degrees round where it points)
const PICK_FRAME := 500         # lifted a frame at most (no spikes)

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _col := PackedColorArray()
var _rot := []
var _need := PackedByteArray()        # its transform must be set again (moving, shrinking, or swapped into this slot)
var _home := PackedByteArray()        # flying to you (picked up)
var _n := 0
var _floor := 0.0
var prof_us := 0
var last_ms := 0.0

var _lie: MultiMeshInstance3D
var _lp := PackedVector3Array()
var _lc := PackedColorArray()
var _ln := 0
var _cells := {}                      # 1 m floor cell -> PackedInt32Array of lying cubes there
var _kind := {}                       # colour (rgba32) -> resource name
var target := Vector3.INF             # the vacuum's nozzle (where sucked-up cubes fly), INF: not sucking
var aim := Vector3.FORWARD            # the way the vacuum points
var got := {"blocks": 0, "meat": 0, "bone": 0, "brain": 0}

func setup(cube_m: float) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * cube_m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	bm.material = mat
	multimesh = _mm(bm, MAX)
	_pos.resize(MAX)
	_vel.resize(MAX)
	_life.resize(MAX)
	_col.resize(MAX)
	_rot.resize(MAX)
	_need.resize(MAX)
	_home.resize(MAX)
	_floor = cube_m * 0.5
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_lie = MultiMeshInstance3D.new()
	_lie.multimesh = _mm(bm, MAX_LIE)
	_lie.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_lie)
	_lp.resize(MAX_LIE)
	_lc.resize(MAX_LIE)
	for c in VoxelBody.FLESH:
		_kind[(c as Color).to_rgba32()] = "meat"
	for c in VoxelBody.BRAIN:
		_kind[(c as Color).to_rgba32()] = "brain"
	_kind[VoxelBody.BONE.to_rgba32()] = "bone"

static func _mm(bm: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = n
	mm.visible_instance_count = 0
	return mm

func count() -> int:
	return _n

func lying() -> int:
	return _ln

## Counts a cube picked up, by its colour.
func take(col: Color, n: int = 1) -> void:
	var k: String = _kind.get(col.to_rgba32(), "blocks")
	got[k] = int(got[k]) + n

## Flings cubes out from where they were: bits = [{pos, col}], out along dir (the shot), with some spread.
func burst(bits: Array, dir: Vector3, power: float = 3.5) -> void:
	for b in bits:
		var v := dir * power * randf_range(0.4, 1.2) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.5), randf_range(-1, 1)) * power * 0.35
		_add(b.pos, v, b.col, 0)

## Cubes straight into the vacuum (a cut-off piece it pulled apart).
func suck(bits: Array) -> void:
	for b in bits:
		_add(b.pos, Vector3(randf_range(-1, 1), randf_range(1, 2.5), randf_range(-1, 1)), b.col, 1)

func _add(p: Vector3, v: Vector3, col: Color, home: int) -> void:
	var i := _n
	if _n >= MAX:
		i = randi() % MAX            # full: reuse a random one (laid down where it is first)
		if _home[i] == 0:
			_lay(_pos[i], _rot[i], _col[i])
		else:
			take(_col[i])
	else:
		_n += 1
	_pos[i] = p
	_vel[i] = v
	_life[i] = 0.0
	_col[i] = col
	_rot[i] = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	_need[i] = 1
	_home[i] = home

func _drop(i: int) -> void:
	_n -= 1
	_pos[i] = _pos[_n]
	_vel[i] = _vel[_n]
	_life[i] = _life[_n]
	_col[i] = _col[_n]
	_rot[i] = _rot[_n]
	_home[i] = _home[_n]
	_need[i] = 1

func _process(dt: float) -> void:
	if multimesh == null:
		return
	var t0 := Time.get_ticks_usec()
	_pick()
	var i := 0
	while i < _n:
		_life[i] += dt
		var v := _vel[i]
		var p := _pos[i]
		if _home[i] == 1:
			if target == Vector3.INF:
				_home[i] = 0
			else:
				# up a moment, then pulled in faster and faster
				var to := target - p
				var d := to.length()
				if d < 0.3:
					take(_col[i])
					_drop(i)
					continue
				v = v.lerp(to / d * minf(16.0, 3.0 + _life[i] * 30.0), minf(1.0, dt * 10.0))
				p += v * dt
				_vel[i] = v
				_pos[i] = p
				multimesh.set_instance_transform(i, Transform3D((_rot[i] as Basis).scaled(Vector3.ONE * clampf(d / 0.6, 0.3, 1.0)), p))
				if _need[i] == 1:
					multimesh.set_instance_color(i, _col[i])
					_need[i] = 0
				i += 1
				continue
		if target != Vector3.INF:
			# in the air in front of the vacuum: caught
			var tv := p - target
			var tl := tv.length()
			if tl <= SUCK_RANGE and tv.dot(aim) >= tl * SUCK_COS:
				_home[i] = 1
				_life[i] = 0.0
		v.y -= 9.8 * dt
		p += v * dt
		var rest := false
		if p.y < _floor:
			p.y = _floor
			v.y = -v.y * 0.25
			v.x *= 0.55
			v.z *= 0.55
			if absf(v.y) < 0.3:
				rest = true
		if rest or _life[i] > 10.0:
			# at rest: it stays there, on the floor that doesn't change
			_lay(Vector3(p.x, _floor, p.z), _rot[i], _col[i])
			_drop(i)
			continue
		_vel[i] = v
		_pos[i] = p
		multimesh.set_instance_transform(i, Transform3D(_rot[i] as Basis, p))
		if _need[i] == 1:
			multimesh.set_instance_color(i, _col[i])
			_need[i] = 0
		i += 1
	multimesh.visible_instance_count = _n
	prof_us += Time.get_ticks_usec() - t0
	last_ms = lerpf(last_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)

# ---------------------------------------------------------------- lying on the floor

static func _cell(p: Vector3) -> int:
	return (floori(p.x) + 1024) * 4096 + (floori(p.z) + 1024)

func _lay(p: Vector3, rot: Basis, col: Color) -> void:
	if _ln >= MAX_LIE:
		_unlay(randi() % MAX_LIE)
	var i := _ln
	_ln += 1
	_lp[i] = p
	_lc[i] = col
	# lying flat on a face, turned any way about the up axis
	var flat := Basis(Vector3.UP, rot.get_euler().y)
	_lie.multimesh.set_instance_transform(i, Transform3D(flat, p))
	_lie.multimesh.set_instance_color(i, col)
	_lie.multimesh.visible_instance_count = _ln
	var k := _cell(p)
	var li: PackedInt32Array = _cells.get(k, PackedInt32Array())
	li.append(i)
	_cells[k] = li         # (a packed array out of a dictionary is a copy: put it back)

# takes lying cube i away (the last one moves into its slot)
func _unlay(i: int) -> void:
	var ki := _cell(_lp[i])
	var li: PackedInt32Array = _cells[ki]
	li.remove_at(li.find(i))
	_cells[ki] = li
	var last := _ln - 1
	if i != last:
		var kl := _cell(_lp[last])
		var ll: PackedInt32Array = _cells[kl]
		ll[ll.find(last)] = i
		_cells[kl] = ll
		_lp[i] = _lp[last]
		_lc[i] = _lc[last]
		_lie.multimesh.set_instance_transform(i, _lie.multimesh.get_instance_transform(last))
		_lie.multimesh.set_instance_color(i, _lc[last])
	_ln = last
	_lie.multimesh.visible_instance_count = _ln

# the ones in the vacuum's cone lift off and fly into it
func _pick() -> void:
	if target == Vector3.INF or _ln == 0:
		return
	var near := []
	var cx := floori(target.x)
	var cz := floori(target.z)
	var rc := ceili(SUCK_RANGE)
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var k := (cx + dx + 1024) * 4096 + (cz + dz + 1024)
			if not _cells.has(k):
				continue
			for i in (_cells[k] as PackedInt32Array):
				var to := _lp[i] - target
				var d := to.length()
				if d <= 1.0 or (d <= SUCK_RANGE and to.dot(aim) >= d * SUCK_COS):
					near.append(i)
			if near.size() >= PICK_FRAME:
				break
		if near.size() >= PICK_FRAME:
			break
	if near.is_empty():
		return
	near.sort()
	near.reverse()
	for i in near:
		var p := _lp[i]
		var c := _lc[i]
		_unlay(i)
		_add(p, Vector3(randf_range(-0.3, 0.3), randf_range(0.8, 1.6), randf_range(-0.3, 0.3)), c, 1)
