class_name VoxelDebris
extends MultiMeshInstance3D
## The cubes a shot or a cut knocks out: thousands of little cubes in one draw call (a MultiMesh with a colour
## each), flung out, falling and bouncing. Once one comes to rest it stays where it lies (the owner, 20 Oct): it moves
## to a second MultiMesh that never changes unless a cube is picked up, so a floor covered in them costs nothing a
## frame. The vacuum gun sucks them up like Astroneer's (the owner, 20 Oct): the ones inside its brush (a sphere where
## it points) come loose at a steady rate, swirl up the beam into the nozzle and count up as resources (blocks, meat,
## bone, brain); let go and the ones in the air fall again. Owned by the voxel session.

## How many at most (the settings, VoxelSettings: set before setup): flying at once; lying on the floor (the oldest go
## when it's full).
static var max_fly := 8000
static var max_lie := 150000
var MAX := 8000                 # (this one's, from max_fly at setup)
var MAX_LIE := 150000
const RATE := 1500.0            # cubes a second the brush pulls loose
const PICK_FRAME := 200         # lifted a frame at most (no spikes)

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
var nozzle := Vector3.ZERO            # where sucked-up cubes go in
var brush := Vector3.INF              # the brush's centre, INF: not sucking
var brush_r := 0.8                    # its radius, metres
var _budget := 0.0                    # cubes the brush may still pull loose this frame
var got := {"blocks": 0, "meat": 0, "bone": 0, "brain": 0, "charred": 0}    # everything ever sucked up (the HUD)
## Each cube sucked up, as an item for the backpack: func(item id, n) -> how many didn't fit (VoxelItems.of_colour).
var on_take: Callable
var bound := INF                      # metres from the middle (x and z) the walls stop flying cubes at
var rooms := []                       # Rect2s (x, z) off the arena with walls of their own: cubes in one stay in it
## A black hole (the gravity gun): flying cubes within well_r of well are pulled in (no falling near it), lying ones
## lift off toward it (a few hundred a frame), and at well_eat they're crushed to nothing. INF: none.
var well := Vector3.INF
var well_r := 3.5
var well_pull := 22.0
var well_eat := 0.3
var eaten := 0
var _ash := VoxelBody.ASH.to_rgba32()     # (ash cubes crumble away where they land: VoxelBody's burnt through)

func setup(cube_m: float) -> void:
	MAX = max_fly
	MAX_LIE = max_lie
	# moved every frame, not on physics ticks: no interpolation (it would lag and warn)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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

## A cube picked up (by its colour: what item it is), into the backpack.
func take(col: Color, n: int = 1) -> void:
	if col.to_rgba32() == _ash:
		return                          # (ash: lost)
	var k := VoxelItems.of_colour(col)
	got[k] = int(got.get(k, 0)) + n
	if on_take.is_valid():
		on_take.call(k, n)

## The lying cubes within r metres of centre gone, up to cap, nearest first, counted for nobody (the other player's
## vacuum took them in their game). Returns how many.
func clear_near(centre: Vector3, r: float, cap: int) -> int:
	if _ln == 0 or cap <= 0:
		return 0
	var near := []
	var rc := ceili(r)
	var cx := floori(centre.x)
	var cz := floori(centre.z)
	var r2 := r * r
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var k := (cx + dx + 1024) * 4096 + (cz + dz + 1024)
			if not _cells.has(k):
				continue
			for i in (_cells[k] as PackedInt32Array):
				var d2 := _lp[i].distance_squared_to(centre)
				if d2 <= r2:
					near.append(Vector2(d2, i))
	near.sort()
	var take_i := []
	for j in mini(cap, near.size()):
		take_i.append(int(near[j].y))
	take_i.sort()
	take_i.reverse()
	for i in take_i:
		_unlay(i)
	return take_i.size()

## n cubes of a colour thrown out from at along dir (a stack dropped from the backpack); they land and lie there.
## The same seed throws them the same way (co-op: they land in the same places in both games).
func throw(at: Vector3, dir: Vector3, col: Color, n: int, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else randi()
	for j in n:
		var v := dir * rng.randf_range(1.5, 3.5) + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.5, 2.0), rng.randf_range(-0.8, 0.8))
		_add(at + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1)), v, col, 0)

## n cubes dropped in a little heap at at, their colours taken in turn from cols (a hen's poo); the same seed drops
## them the same way.
func plop(at: Vector3, cols: Array, n: int, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else randi()
	for j in n:
		var v := Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.1, 0.5), rng.randf_range(-0.15, 0.15))
		_add(at + Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.0, 0.05), rng.randf_range(-0.04, 0.04)), v, cols[j % cols.size()], 0)

## Flings cubes out from where they were: bits = [{pos, col}], out along dir (the shot), with some spread.
func burst(bits: Array, dir: Vector3, power: float = 3.5) -> void:
	for b in bits:
		var v := dir * power * randf_range(0.4, 1.2) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.5), randf_range(-1, 1)) * power * 0.35
		_add(b.pos, v, b.col, 0)

## The cubes lying within r metres (level) of centre thrown back up into the air (a hammer's ground slam): up m/s
## upward, out from the middle, more the nearer; at most cap of them. Returns how many.
func pop(centre: Vector3, r: float, up: float = 4.0, cap: int = 1500) -> int:
	var near := []
	var rc := ceili(r)
	var cx := floori(centre.x)
	var cz := floori(centre.z)
	# the floor cells nearest the middle first (the nearest cubes go up), stopping at cap: no need to find them all
	var order := []
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var mid := Vector2(cx + dx + 0.5 - centre.x, cz + dz + 0.5 - centre.z)
			order.append(Vector2(mid.length_squared(), (cx + dx + 1024) * 4096 + (cz + dz + 1024)))
	order.sort()
	# (once there are enough, the cells as near as that one, within a cell's width, still count: then the nearest of
	# them all, so it's a round patch, not one cell's worth)
	var enough_at := INF
	for o in order:
		if sqrt(o.x) > enough_at + 1.42:
			break
		var k := int(o.y)
		if not _cells.has(k):
			continue
		for i in (_cells[k] as PackedInt32Array):
			var off := Vector2(_lp[i].x - centre.x, _lp[i].z - centre.z)
			var dl := off.length()
			if dl <= r:
				near.append(Vector2(dl, i))
		if near.size() >= cap and enough_at == INF:
			enough_at = sqrt(o.x)
	near.sort()
	var take_i := []
	for j in mini(cap, near.size()):
		take_i.append(int(near[j].y))
	take_i.sort()
	take_i.reverse()                     # taken from the end down, so the slots moved in are ones already seen
	var n := 0
	for i in take_i:
		var p := _lp[i]
		var c := _lc[i]
		var off2 := Vector3(p.x - centre.x, 0, p.z - centre.z)
		var k2 := 1.0 - clampf(off2.length() / maxf(r, 0.01), 0.0, 1.0)
		_unlay(i)
		_add(p, Vector3.UP * up * (0.4 + 0.8 * k2) * randf_range(0.7, 1.2) + off2.normalized() * up * 0.3 * k2, c, 0)
		n += 1
	return n

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
	_budget = minf(_budget + RATE * dt, float(PICK_FRAME)) if brush != Vector3.INF else 0.0
	_pick()
	if well != Vector3.INF:
		# (only the lying cubes it can reach: a ring further off in 3D would hop up and fall back for ever)
		var reach := sqrt(maxf(0.0, well_r * well_r - (well.y - _floor) * (well.y - _floor)))
		if reach > 0.05:
			pop(Vector3(well.x, 0.0, well.z), reach, 1.5, 150)
	var i := 0
	while i < _n:
		_life[i] += dt
		var v := _vel[i]
		var p := _pos[i]
		if _home[i] == 1:
			if brush == Vector3.INF:
				_home[i] = 0
			else:
				# up the beam: steered at a point on it a little nearer the nozzle, swirling round it, faster and
				# faster, shrinking as it goes in
				var ab := brush - nozzle
				var al := maxf(0.01, ab.length())
				var ax := ab / al
				var tt := clampf((p - nozzle).dot(ax) / al, 0.0, 1.0)
				var d := p.distance_to(nozzle)
				if d < 0.3:
					take(_col[i])
					_drop(i)
					continue
				var u := ax.cross(Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT).normalized()
				var w := ax.cross(u)
				var ph := _life[i] * 9.0 + float(i % 17) * 0.37
				var goal := nozzle + ab * maxf(0.0, tt - 0.2) + (u * cos(ph) + w * sin(ph)) * (0.03 + 0.16 * tt)
				var sp := minf(14.0, 3.0 + _life[i] * 18.0)
				v = v.lerp((goal - p).normalized() * sp, minf(1.0, dt * 9.0))
				p += v * dt
				_vel[i] = v
				_pos[i] = p
				multimesh.set_instance_transform(i, Transform3D((_rot[i] as Basis).scaled(Vector3.ONE * clampf((d - 0.25) / 1.2, 0.12, 1.0)), p))
				if _need[i] == 1:
					multimesh.set_instance_color(i, _col[i])
					_need[i] = 0
				i += 1
				continue
		if well != Vector3.INF:
			var wv := well - p
			var wd := wv.length()
			if wd < well_eat:
				eaten += 1
				_drop(i)
				continue
			if wd < well_r:
				# pulled in, faster the nearer, spiralling a little
				v = v * exp(-dt * 1.5) + (wv / wd * (1.0 + 2.5 * (1.0 - wd / well_r)) + wv.cross(Vector3.UP).normalized() * 0.4 * wd / well_r) * well_pull * dt     # (the swirl dies away near the middle, or they'd orbit it)
				p += v * dt
				_vel[i] = v
				_pos[i] = p
				multimesh.set_instance_transform(i, Transform3D((_rot[i] as Basis).scaled(Vector3.ONE * clampf(wd / well_r * 2.0, 0.3, 1.0)), p))
				if _need[i] == 1:
					multimesh.set_instance_color(i, _col[i])
					_need[i] = 0
				i += 1
				continue
		if brush != Vector3.INF and _budget >= 1.0 and p.distance_to(brush) <= brush_r:
			# in the air inside the brush: caught
			_home[i] = 1
			_life[i] = 0.0
			_budget -= 1.0
		v.y -= 9.8 * dt
		p += v * dt
		# the walls: a bounce back in (cubes lying outside could never be got at); a room off the arena (the bedroom)
		# keeps its own in by its own walls
		var room := _room_of(_pos[i]) if not rooms.is_empty() else -1      # (where it was: in a room, it stays in)
		if room >= 0:
			var rr: Rect2 = rooms[room]
			var m := 0.03
			if p.x < rr.position.x + m or p.x > rr.end.x - m:
				p.x = clampf(p.x, rr.position.x + m, rr.end.x - m)
				v.x = -v.x * 0.3
			if p.z < rr.position.y + m or p.z > rr.end.y - m:
				p.z = clampf(p.z, rr.position.y + m, rr.end.y - m)
				v.z = -v.z * 0.3
		else:
			if absf(p.x) > bound:
				p.x = signf(p.x) * bound
				v.x = -v.x * 0.3
			if absf(p.z) > bound:
				p.z = signf(p.z) * bound
				v.z = -v.z * 0.3
		var rest := false
		if p.y < _floor:
			p.y = _floor
			v.y = -v.y * 0.25
			v.x *= 0.55
			v.z *= 0.55
			if absf(v.y) < 0.3:
				rest = true
		if rest or _life[i] > 10.0:
			# at rest: it stays there, on the floor that doesn't change (ash crumbles to nothing)
			if _col[i].to_rgba32() != _ash:
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

func _room_of(p: Vector3) -> int:
	for i in rooms.size():
		var r: Rect2 = rooms[i]
		if p.x >= r.position.x and p.x <= r.end.x and p.z >= r.position.y and p.z <= r.end.y:
			return i
	return -1

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

# the ones inside the brush come loose (nearest the middle first), as many as the rate allows
func _pick() -> void:
	if brush == Vector3.INF or _ln == 0 or _budget < 1.0:
		return
	var near := []
	var cx := floori(brush.x)
	var cz := floori(brush.z)
	var rc := ceili(brush_r)
	var r2 := brush_r * brush_r
	# the floor cells nearest the brush's middle first, stopping once there are plenty to choose the nearest from
	var order := []
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var mid := Vector2(cx + dx + 0.5 - brush.x, cz + dz + 0.5 - brush.z)
			order.append(Vector2(mid.length_squared(), (cx + dx + 1024) * 4096 + (cz + dz + 1024)))
	order.sort()
	var want := int(_budget) * 3
	var enough_at := INF
	for o in order:
		if sqrt(o.x) > enough_at + 1.42:
			break
		var k := int(o.y)
		if not _cells.has(k):
			continue
		for i in (_cells[k] as PackedInt32Array):
			var d2 := _lp[i].distance_squared_to(brush)
			if d2 <= r2:
				near.append(Vector2(d2, i))
		if near.size() >= want and enough_at == INF:
			enough_at = sqrt(o.x)
	if near.is_empty():
		return
	near.sort()
	var n := mini(near.size(), int(_budget))
	_budget -= n
	var take_i := []
	for j in n:
		take_i.append(int(near[j].y))
	take_i.sort()
	take_i.reverse()
	for i in take_i:
		var p := _lp[i]
		var c := _lc[i]
		_unlay(i)
		# a little hop up toward the middle of the brush first
		_add(p, (brush - p) * 2.0 + Vector3(randf_range(-0.3, 0.3), randf_range(0.8, 1.5), randf_range(-0.3, 0.3)), c, 1)
