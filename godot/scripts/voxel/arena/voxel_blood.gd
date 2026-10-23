class_name VoxelBlood
extends Node3D
## Ultra Gore (the owner, 23 Oct: "ultra gore mode with dripping etc"). The blood that comes after a hit, each game its
## own (it follows the cuts, which both games make: VoxelBody.on_wound), so nothing more goes over the network:
## - wounds: every hole keeps bleeding a while (drips, fewer and fewer), every stump spurts in pulses like a heartbeat,
##   slowing over STUMP_T seconds; a cut-off piece drips from where it lies; they ride the part they're in;
## - drops: little red cubes falling; on the floor they make pools that grow and run together, wet and dark red,
##   drying darker over a minute; on a wall or a pillar (shot through, or thrown) a splat stays there;
## - a hit near your eye in first person splashes your view: drops that run down and fade;
## - a drip into a pool, a spurt's pulse, a splat: little wet sounds.
## Stage 2: whoever walks through a fresh pool leaves bloody footprints for a few steps (fainter each); a body crawling
## on its arms leaves a smear behind it; blood runs down a body from each hole and stump (a decal growing down it); a
## melee weapon gets bloodier with every hit (a coat over its view model, wet and shiny, drying dark) and drips.
## The settings' Gore (level): 0 Normal (holes drip a little, small pools, no spurts or screen), 1 Ultra, 2 Extreme
## (more of everything, for big PCs). Owned by the voxel session.

const STUMP_T := 7.0            # seconds a stump spurts
const HOLE_T := 9.0             # seconds a hole bleeds
const PULSE := 0.72             # seconds a heartbeat
const GRAV := 9.8
const CAPS := [[250, 90, 40, 6], [900, 320, 160, 30], [1800, 600, 320, 50]]   # per level: drops, pools, splats, wounds
const POOL_MAX := 0.55          # metres: a pool's widest
const DROP_AREA := 0.003        # square metres one drop adds to a pool
const LIM_NEAR := VoxelArena.ARENA - 0.9  # (closer to a wall than this: see if a drop's hit it)

static var level := 1
var arena: Node3D
var wounds: Array = []          # {node: Node3D, local: Vector3, dir: Vector3 (node's space), s: strength, kind, t, next}
var _dp := PackedVector3Array() # drops: place, velocity, life
var _dv := PackedVector3Array()
var _dl := PackedFloat32Array()
var _drops: MultiMeshInstance3D
## Pools and splats are rings (a MultiMesh instance each, the oldest reused): {i: its instance, p, r, b: when made}
## (a pool's b moves on when fresh blood lands in it). _grid finds the pools near a point (0.6 m squares).
var pools: Array = []
var _pool_next := 0
var _grid := {}
var _pools: MultiMeshInstance3D
var splats: Array = []          # {i, xf, b}
var _splat_next := 0
var _splats: MultiMeshInstance3D
var _ring_level := -1
var _screen: Control
var _sdrops: Array = []         # screen drops: {p: Vector2, r, a, v}
var _sound_t := 0.0
var _t := 0.0
var cost_us := 0                # (the last frame's time in here: the stress test)
var stats := {"drops": 0, "pooled": 0, "splatted": 0, "screen": 0, "spurts": 0, "prints": 0, "smears": 0, "runs": 0}

const PRINTS := [60, 300, 700]  # per level: footprints and smears kept (each)
const RUNS := [0, 24, 48]       # per level: runs down bodies kept
const STEP := 0.55              # metres a step
const WET_STEPS := 10           # steps a fresh pool leaves on your feet
var _prints := {}               # rings (_ring): footprints, smears
var _smears := {}
var _walk := {}                 # who's walking (instance id) -> {p, d: since the last step, foot: -1/1, wet: steps left}
var runs: Array = []            # {d: Decal, len, w, t, top, down, out (the part's space)}
var _weapons: Array = []        # [{w: VoxelMelee, mat: ShaderMaterial, wet}]
static var _run_tex: Texture2D
static var _coat_shader: Shader

func setup(arena_: Node3D) -> void:
	arena = arena_
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.36, 0.01, 0.02)
	red.roughness = 0.3
	red.metallic_specular = 0.6
	_drops = _mm(BoxMesh.new(), red, false)
	(_drops.multimesh.mesh as BoxMesh).size = Vector3(0.02, 0.026, 0.02)
	var wet := StandardMaterial3D.new()
	wet.vertex_color_use_as_albedo = true
	wet.vertex_color_is_srgb = true
	wet.roughness = 0.16
	wet.metallic_specular = 0.55
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.002
	disc.radial_segments = 14
	disc.rings = 1
	_pools = _mm(disc, wet, true)
	var splat := disc.duplicate()
	splat.radial_segments = 9
	var wet2 := wet.duplicate()
	_splats = _mm(splat, wet2, true)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.draw.connect(_draw_screen)
	layer.add_child(_screen)
	VoxelBody.on_wound = wound
	var prt := StandardMaterial3D.new()
	prt.vertex_color_use_as_albedo = true
	prt.vertex_color_is_srgb = true
	prt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	prt.roughness = 0.35
	var st := SurfaceTool.new()
	var heel := BoxMesh.new()
	heel.size = Vector3(0.09, 0.002, 0.095)
	var sole := BoxMesh.new()
	sole.size = Vector3(0.115, 0.002, 0.155)
	st.append_from(heel, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.09)))
	st.append_from(sole, 0, Transform3D(Basis.IDENTITY, Vector3(0.007, 0, -0.055)))
	_prints = _ring(st.commit(), prt)
	var smear := BoxMesh.new()
	smear.size = Vector3(1.0, 0.002, 1.0)
	_smears = _ring(smear, prt)

func _mm(mesh: Mesh, mat: Material, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _cap(i: int) -> int:
	return int(CAPS[clampi(level, 0, 2)][i])

## A body bled (VoxelBody.on_wound): where (world), how hard, which way out (world), "hole" or "stump", riding node.
func wound(node: Node3D, at: Vector3, dir: Vector3, strength: float, kind: String, frame = null) -> void:
	if not is_instance_valid(node):
		return
	if kind == "stump" and level == 0:
		kind = "hole"
	var inv: Transform3D = (frame as Transform3D if frame != null else node.global_transform).affine_inverse()
	var local := inv * at
	var again := false
	for w in wounds:
		# the same place cut again (a chainsaw, a flamethrower: every frame): that wound bleeds afresh, a smaller gush
		if w.node == node and w.kind == kind and (w.local as Vector3).distance_to(local) < 0.12:
			w.t = minf(float(w.t), 0.5)
			w.s = minf(3.2, maxf(float(w.s), strength))
			again = true
			break
	if not again:
		wounds.append({"node": node, "local": local, "dir": (inv.basis * dir).normalized(), "s": strength, "kind": kind, "t": 0.0,
			"next": 0.0})
		while wounds.size() > _cap(3):
			wounds.pop_front()
		_run(node, at, dir, inv)
	# the first gush, and a splash on your view if it was right in your face
	var n := int(clampf(strength * (8.0 if kind == "stump" else 4.0), 2.0, 24.0) * (0.5 if level == 0 else 1.0) * (0.2 if again else 1.0))
	for k in n:
		_drop(at, dir * randf_range(0.3, 1.5) + _rand3(0.45) + Vector3.UP * randf_range(0.1, 0.9))
	_near_eye(at, strength)
	if kind == "stump":
		stats.spurts += 1

## A piece became a body of its own where it lay (VoxelPieces._settle): its dripping goes on from that.
func rehome(old: Node3D, node: Node3D) -> void:
	for w in wounds:
		if w.node == old and is_instance_valid(node):
			var xf := (old as Node3D).global_transform
			var inv := node.global_transform.affine_inverse()
			w.local = inv * (xf * (w.local as Vector3))
			w.dir = (inv.basis * (xf.basis * (w.dir as Vector3))).normalized()
			w.node = node

## A cut-off piece (a RigidBody3D) drips from where it lies a while.
func piece(rb: Node3D) -> void:
	if level == 0 or not is_instance_valid(rb):
		return
	wounds.append({"node": rb, "local": Vector3.ZERO, "dir": Vector3.DOWN, "s": 0.7, "kind": "hole", "t": 0.0, "next": 0.3})
	while wounds.size() > _cap(3):
		wounds.pop_front()

## A shot through a body: blood out the far side along its way (it splats on what's behind).
func spray(at: Vector3, dir: Vector3, cubes: int) -> void:
	var n := int(clampf(cubes * 0.35, 3.0, 16.0) * (0.4 if level == 0 else 1.0))
	for k in n:
		_drop(at, dir * randf_range(2.5, 7.0) + _rand3(0.7) + Vector3.UP * randf_range(-0.2, 0.6))
	_near_eye(at, cubes / 20.0)

func _rand3(r: float) -> Vector3:
	return Vector3(randf_range(-r, r), randf_range(-r, r), randf_range(-r, r))

func _drop(p: Vector3, v: Vector3) -> void:
	if _dp.size() >= _cap(0):
		return
	_dp.append(p)
	_dv.append(v)
	_dl.append(4.0)
	stats.drops += 1

# a splash on the screen when it happened right in front of your eye (first person)
func _near_eye(at: Vector3, strength: float) -> void:
	if level == 0 or arena == null or arena.top_down or not arena.cam.current:
		return
	var eye: Vector3 = arena.cam.global_position
	var fwd: Vector3 = -arena.cam.global_transform.basis.z
	var to := at - eye
	var d := to.length()
	if d > 1.9 or to.normalized().dot(fwd) < 0.45:
		return
	if _t - float(_screen.get_meta("last", -9.0)) < 0.35:
		return                                          # (one splash at a time, not one a pellet)
	_screen.set_meta("last", _t)
	var n := int(clampf(strength * 4.0 * (1.9 - d), 3.0, 8.0))
	var sz: Vector2 = _screen.size
	for k in n:
		# away from the middle (where you're looking) more often than not
		var a := randf() * TAU
		var rr := sqrt(randf_range(0.12, 1.0)) * 0.48
		var p := Vector2(0.5 + cos(a) * rr * 1.1, 0.48 + sin(a) * rr) * sz
		var blobs := []
		for j in randi_range(3, 6):
			blobs.append([Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)), randf_range(0.35, 0.8)])
		_sdrops.append({"p": p, "r": randf_range(14.0, 40.0) * sz.y / 720.0, "a": randf_range(0.9, 1.0),
			"v": randf_range(4.0, 28.0), "tr": 0.0, "blobs": blobs})
	stats.screen += n
	while _sdrops.size() > 24:
		_sdrops.pop_front()

func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _ring_level != level:
		_rings()
	_walkers_step()
	_runs_step(dt)
	_weapons_step(dt)
	var dry := int(_t) != int(_t + dt)          # (pools and splats a shade darker once a second, all together)
	_t += dt
	if dry:
		_dry_all()
	_sound_t = maxf(0.0, _sound_t - dt)
	_wounds_step(dt)
	_drops_step(dt)
	_screen_step(dt)
	cost_us = Time.get_ticks_usec() - t0

func _wounds_step(dt: float) -> void:
	for i in range(wounds.size() - 1, -1, -1):
		var w: Dictionary = wounds[i]
		var node = w.node
		if not is_instance_valid(node) or not (node as Node3D).is_inside_tree() or not (node as Node3D).is_visible_in_tree():
			wounds.remove_at(i)
			continue
		w.t = float(w.t) + dt
		var life := STUMP_T if w.kind == "stump" else HOLE_T
		if float(w.t) > life:
			wounds.remove_at(i)
			continue
		var xf: Transform3D = (node as Node3D).global_transform
		var at: Vector3 = xf * (w.local as Vector3)
		var dir: Vector3 = (xf.basis * (w.dir as Vector3)).normalized()
		var fade := 1.0 - float(w.t) / life
		w.next = float(w.next) - dt
		if w.kind == "stump":
			# a heartbeat: a jet out of it (a stream for a quarter second, an arc), weaker each time
			if float(w.next) <= 0.0:
				w.next = PULSE * (1.0 + float(w.t) / life)
				w.jet = 0.24
				w.speed = randf_range(2.0, 3.0) * (0.35 + fade)
				if _sound_t <= 0.0 and arena and arena.sound:
					_sound_t = 0.12
					arena.sound.play("hit_flesh", at, -18.0, randf_range(0.55, 0.7))
			if float(w.get("jet", 0.0)) > 0.0:
				w.jet = float(w.jet) - dt
				var k := float(w.jet) / 0.24             # (strong at the start of a beat, falling off)
				w.acc = float(w.get("acc", 0.0)) + clampf(float(w.s) * 100.0 * fade, 40.0, 220.0) * dt   # (drops a second)
				var n := int(w.acc)
				w.acc = float(w.acc) - n
				for j in n:
					var v0 := dir * float(w.speed) * (0.55 + 0.45 * k) + _rand3(0.12) + Vector3.UP * 0.3
					var u := randf() * dt                # (spread through the frame: a stream, not clumps, at any frame rate)
					_drop(at + _rand3(0.008) + v0 * u, v0 + Vector3.DOWN * GRAV * u)
			elif randf() < dt * 10.0 * fade:
				_drop(at, _rand3(0.1))
		else:
			if float(w.next) <= 0.0:
				w.next = randf_range(0.12, 0.5) / maxf(0.2, float(w.s) * fade)
				_drop(at + _rand3(0.01), dir * randf_range(0.0, 0.3) + _rand3(0.08))

func _drops_step(dt: float) -> void:
	var n := _dp.size()
	var i := 0
	while i < n:
		var v := _dv[i]
		v.y -= GRAV * dt
		var p := _dp[i] + v * dt
		_dl[i] -= dt
		var gone := _dl[i] <= 0.0
		var ground := _floor_at(p) if p.z > 22.0 else 0.0           # (only the yard's ground isn't flat: z 22.5 on)
		if not gone and p.y <= ground:
			_land(Vector3(p.x, ground, p.z))
			gone = true
		elif not gone and (absf(p.x) > LIM_NEAR or absf(p.z) > LIM_NEAR or (absf(absf(p.x) - 8.0) < 0.75 and absf(absf(p.z) - 8.0) < 0.75)):
			var wall := _wall_hit(_dp[i], p)                         # (near a wall or a pillar only)
			if not wall.is_empty():
				_splat(wall.p, wall.n, v)
				gone = true
		if gone:
			n -= 1
			_dp[i] = _dp[n]
			_dv[i] = _dv[n]
			_dl[i] = _dl[n]
			continue
		_dp[i] = p
		_dv[i] = v
		i += 1
	_dp.resize(n)
	_dv.resize(n)
	_dl.resize(n)
	var mm := _drops.multimesh
	mm.instance_count = n
	for k in n:
		var vv := _dv[k]
		var stretch := clampf(1.0 + vv.length() * 0.25, 1.0, 2.6)
		var b := Basis.IDENTITY.scaled(Vector3(1.0, stretch, 1.0))
		mm.set_instance_transform(k, Transform3D(b, _dp[k]))

# the floor under p (the yard's dug ground is lower in its middle; everywhere else the floor)
func _floor_at(p: Vector3) -> float:
	if arena and arena.yard and VoxelYard.in_yard(p) and arena.yard.ground and arena.yard.ground.has_method("surface_y"):
		return float(arena.yard.ground.surface_y(p))
	return 0.0

# the arena's walls and pillars a drop went into between a and b: {p, n} or {}
func _wall_hit(a: Vector3, b: Vector3) -> Dictionary:
	if b.y > 3.5 or b.y < 0.0:
		return {}
	var lim := VoxelArena.ARENA - 0.5
	if absf(a.x) < lim + 0.6 and absf(a.z) < lim + 0.6 and not VoxelArena.safe(a):
		if absf(b.x) >= lim and absf(a.x) < lim:
			return {"p": Vector3(signf(b.x) * (lim - 0.003), b.y, b.z), "n": Vector3(-signf(b.x), 0, 0)}
		if absf(b.z) >= lim and absf(a.z) < lim and not (b.z > 0.0 and _doorway(b.x)):
			return {"p": Vector3(b.x, b.y, signf(b.z) * (lim - 0.003)), "n": Vector3(0, 0, -signf(b.z))}
	for c: Vector3 in VoxelArena.PILLARS:
		var h := VoxelArena.PILLAR_HALF
		if absf(b.x - c.x) < h and absf(b.z - c.z) < h and not (absf(a.x - c.x) < h and absf(a.z - c.z) < h):
			var dx := a.x - c.x
			var dz := a.z - c.z
			if absf(dx) > absf(dz):
				return {"p": Vector3(c.x + signf(dx) * (h + 0.003), b.y, b.z), "n": Vector3(signf(dx), 0, 0)}
			return {"p": Vector3(b.x, b.y, c.z + signf(dz) * (h + 0.003)), "n": Vector3(0, 0, signf(dz))}
	return {}

func _doorway(x: float) -> bool:
	return (x > VoxelBedroom.DOOR_X0 and x < VoxelBedroom.DOOR_X1) or (x > VoxelYard.DOOR_X0 and x < VoxelYard.DOOR_X1)

# a drop on the floor: into the pool it's in (it grows), or a new little one
func _land(p: Vector3) -> void:
	stats.pooled += 1
	var c := Vector2i(floori(p.x / 0.6), floori(p.z / 0.6))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var near = _grid.get(c + Vector2i(dx, dz))
			if near == null:
				continue
			for pl: Dictionary in near:
				var d := Vector2(pl.p.x - p.x, pl.p.z - p.z).length()
				if d < float(pl.r) + 0.05:
					var area := PI * float(pl.r) * float(pl.r) + DROP_AREA
					pl.r = minf(POOL_MAX, sqrt(area / PI))
					pl.b = maxf(float(pl.b), _t - 6.0)       # (fresh blood in it: wet again)
					_pool_show(pl)
					if _sound_t <= 0.0 and arena and arena.sound and randf() < 0.25:
						_sound_t = 0.09
						arena.sound.play("hit_flesh", p, -24.0, randf_range(1.6, 2.1))
					return
	var old = pools[_pool_next]
	if old != null:
		(_grid[old.c] as Array).erase(old)
	var pl := {"i": _pool_next, "p": p + Vector3(0, 0.0015 + randf() * 0.0015, 0), "r": randf_range(0.022, 0.04), "b": _t, "c": c}
	pools[_pool_next] = pl
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(pl)
	_pool_next = (_pool_next + 1) % pools.size()
	_pool_show(pl)

func _pool_show(pl: Dictionary) -> void:
	var r := float(pl.r)
	_pools.multimesh.set_instance_transform(pl.i, Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), pl.p))
	_pools.multimesh.set_instance_color(pl.i, _dry(_t - float(pl.b)))

func _splat(p: Vector3, n: Vector3, v: Vector3) -> void:
	stats.splatted += 1
	# flat on the wall (the disc's axis along n), longer the way it was going and the harder it hit
	var along := v - n * v.dot(n)
	if along.length() < 0.05:
		along = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
	along = along.normalized()
	var s := randf_range(0.012, 0.03)
	var stretch := clampf(1.0 + along.length() * v.length() * 0.18, 1.0, 3.0)
	var b := Basis(along * s * stretch, n, along.cross(n) * s)
	var sp := {"i": _splat_next, "xf": Transform3D(b, p + n * 0.002), "b": _t}
	splats[_splat_next] = sp
	_splat_next = (_splat_next + 1) % splats.size()
	_splats.multimesh.set_instance_transform(sp.i, sp.xf)
	_splats.multimesh.set_instance_color(sp.i, _dry(0.0))
	if _sound_t <= 0.0 and arena and arena.sound and randf() < 0.3:
		_sound_t = 0.1
		arena.sound.play("hit_flesh", p, -16.0, randf_range(1.2, 1.5))

# the rings sized for the gore level (and emptied)
func _rings() -> void:
	_ring_level = level
	pools.clear()
	pools.resize(_cap(1))
	splats.clear()
	splats.resize(_cap(2))
	_pool_next = 0
	_splat_next = 0
	_grid.clear()
	_ring_size(_prints, PRINTS[clampi(level, 0, 2)])
	_ring_size(_smears, PRINTS[clampi(level, 0, 2)])
	for r in runs:
		if is_instance_valid(r.d):
			r.d.queue_free()
	runs.clear()
	var none := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for mm: MultiMesh in [_pools.multimesh, _splats.multimesh]:
		mm.instance_count = pools.size() if mm == _pools.multimesh else splats.size()
		for k in mm.instance_count:
			mm.set_instance_transform(k, none)

# every pool and splat a shade darker (once a second)
func _dry_all() -> void:
	for pl in pools:
		if pl != null:
			_pools.multimesh.set_instance_color(pl.i, _dry(_t - float(pl.b)))
	for sp in splats:
		if sp != null:
			_splats.multimesh.set_instance_color(sp.i, _dry(_t - float(sp.b)))

## Pools and splats there are now.
func pool_count() -> int:
	return pools.size() - pools.count(null)

func splat_count() -> int:
	return splats.size() - splats.count(null)

# fresh blood's colour, darker as it dries over a minute
func _dry(t: float) -> Color:
	return Color(0.4, 0.015, 0.02).lerp(Color(0.17, 0.03, 0.025), clampf(t / 60.0, 0.0, 1.0))

func _screen_step(dt: float) -> void:
	if _sdrops.is_empty():
		if _screen.has_meta("drawn"):
			_screen.remove_meta("drawn")
			_screen.queue_redraw()
		return
	for i in range(_sdrops.size() - 1, -1, -1):
		var d: Dictionary = _sdrops[i]
		d.a = float(d.a) - dt * 0.32
		d.p = (d.p as Vector2) + Vector2(0, float(d.v) * dt)
		d.tr = float(d.tr) + float(d.v) * dt
		d.v = maxf(0.0, float(d.v) - dt * 6.0)
		if float(d.a) <= 0.0:
			_sdrops.remove_at(i)
	_screen.set_meta("drawn", true)
	_screen.queue_redraw()

func _draw_screen() -> void:
	for d in _sdrops:
		var a := clampf(float(d.a) * 1.8, 0.0, 1.0)      # (solid till it's nearly gone, then fading)
		var p: Vector2 = d.p
		var r := float(d.r)
		var trail := float(d.tr)
		if trail > 1.0:
			_screen.draw_rect(Rect2(p.x - r * 0.22, p.y - trail, r * 0.44, trail), Color(0.38, 0.01, 0.02, a * 0.5))
		_screen.draw_circle(p, r * 0.8, Color(0.3, 0.0, 0.01, a * 0.92))
		for bl in d.blobs:
			_screen.draw_circle(p + (bl[0] as Vector2) * r, r * float(bl[1]), Color(0.36, 0.01, 0.02, a * 0.9))
		_screen.draw_circle(p + Vector2(-r * 0.25, -r * 0.3), r * 0.12, Color(1.0, 0.7, 0.7, a * 0.25))

## Everything gone (the fight started over).
func clear() -> void:
	wounds.clear()
	_dp.resize(0)
	_dv.resize(0)
	_dl.resize(0)
	_drops.multimesh.instance_count = 0
	_rings()
	_sdrops.clear()

# ---------------------------------------------------------------- rings: a MultiMesh of flat marks, the oldest reused

func _ring(mesh: Mesh, mat: Material) -> Dictionary:
	return {"mi": _mm(mesh, mat, true), "next": 0, "n": 0, "cap": 0}

func _ring_size(r: Dictionary, cap: int) -> void:
	r.cap = cap
	r.next = 0
	r.n = 0
	var mm: MultiMesh = r.mi.multimesh
	mm.instance_count = cap
	var none := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for k in cap:
		mm.set_instance_transform(k, none)

func _ring_put(r: Dictionary, xf: Transform3D, col: Color) -> void:
	if int(r.cap) == 0:
		return
	var mm: MultiMesh = r.mi.multimesh
	mm.set_instance_transform(r.next, xf)
	mm.set_instance_color(r.next, col)
	r.next = (int(r.next) + 1) % int(r.cap)
	r.n = mini(int(r.n) + 1, int(r.cap))

# ---------------------------------------------------------------- footprints, crawling smears

# how fresh the pool under p is (1 just spilt .. 0.3 at 40 s; 0: no pool, or dry)
func _wet_at(p: Vector3) -> float:
	var c := Vector2i(floori(p.x / 0.6), floori(p.z / 0.6))
	var best := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var near = _grid.get(c + Vector2i(dx, dz))
			if near == null:
				continue
			for pl: Dictionary in near:
				var age := _t - float(pl.b)
				if age < 40.0 and Vector2(pl.p.x - p.x, pl.p.z - p.z).length() < float(pl.r) * 0.95 + 0.04:
					best = maxf(best, clampf(1.0 - age / 40.0, 0.3, 1.0))
	return best

func _walkers_step() -> void:
	if arena == null:
		return
	var who := []
	if arena.player:
		who.append(arena.player)
	if arena.net and arena.net.other and is_instance_valid(arena.net.other.avatar):
		who.append(arena.net.other.avatar)
	for b in arena.bodies:
		if is_instance_valid(b) and b.alive and not b.fragment and b.visible:
			who.append(b)
	var seen := {}
	for n: Node3D in who:
		var id := n.get_instance_id()
		seen[id] = true
		var p := n.global_position
		var w = _walk.get(id)
		if w == null:
			_walk[id] = {"p": p, "d": 0.0, "foot": 1.0, "wet": 0}
			continue
		var mv := Vector2(p.x - w.p.x, p.z - w.p.z)
		var dist := mv.length()
		var floor_y := _floor_at(p) if p.z > 22.0 else 0.0
		w.p = p
		if dist > 2.0 or absf(p.y - floor_y) > 0.15:
			continue                                     # (in the air, up on something, or put somewhere else)
		var wet := _wet_at(p)
		if wet > 0.0:
			if int(w.wet) == 0 and n == arena.player and arena.sound and _sound_t <= 0.0:
				_sound_t = 0.1
				arena.sound.play("hit_flesh", p, -20.0, randf_range(1.7, 2.0))      # (a squelch: you've trodden in it)
			w.wet = maxi(int(w.wet), int(WET_STEPS * wet) + 2)
		if dist < 0.0005:
			continue
		w.d = float(w.d) + dist
		var head := Vector3(mv.x, 0.0, mv.y).normalized()
		var crawl := n is VoxelBody and (n as VoxelBody).legs_lost() >= 2
		if crawl:
			if float(w.d) >= 0.1:
				w.d = 0.0
				var bs := Basis.looking_at(head, Vector3.UP) * Basis.from_scale(Vector3(randf_range(0.2, 0.3), 1.0, 0.16))
				_ring_put(_smears, Transform3D(bs, Vector3(p.x, floor_y + 0.0034, p.z)), Color(0.32, 0.01, 0.02, randf_range(0.6, 0.85)))
				stats.smears += 1
		elif float(w.d) >= STEP:
			w.d = 0.0
			w.foot = -float(w.foot)
			if int(w.wet) > 0:
				var k := float(w.wet) / float(WET_STEPS)
				var side := Vector3(-head.z, 0.0, head.x) * 0.1 * float(w.foot)
				var bs := Basis.looking_at(head, Vector3.UP).rotated(Vector3.UP, randf_range(-0.12, 0.12))
				var at := Vector3(p.x, floor_y + 0.0038, p.z) + side
				_ring_put(_prints, Transform3D(bs, at), Color(0.3, 0.012, 0.018, clampf(0.25 + k * 0.7, 0.3, 0.95)))
				w.wet = int(w.wet) - 1
				stats.prints += 1
	if Engine.get_process_frames() % 120 == 0:
		for id in _walk.keys():
			if not seen.has(id):
				_walk.erase(id)

# ---------------------------------------------------------------- runs down bodies (decals)

func _run(node: Node3D, at: Vector3, dir: Vector3, inv: Transform3D) -> void:
	if RUNS[clampi(level, 0, 2)] == 0 or node is RigidBody3D:
		return
	var down := Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	if down.length() < 0.25:
		return                                           # (a hole facing straight up or down: nothing to run down)
	down = down.normalized()
	var d := Decal.new()
	d.texture_albedo = _run_texture()
	d.normal_fade = 0.3
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 20.0
	d.distance_fade_length = 6.0
	node.add_child(d)
	var r := {"d": d, "len": randf_range(0.18, 0.4), "w": randf_range(0.09, 0.14), "t": 0.0, "top": inv * at,
		"down": (inv.basis * down).normalized(), "out": (inv.basis * dir).normalized()}
	runs.append(r)
	stats.runs += 1
	while runs.size() > RUNS[clampi(level, 0, 2)]:
		var o: Dictionary = runs.pop_front()
		if is_instance_valid(o.d):
			o.d.queue_free()
	_run_place(r, 0.02)

func _run_place(r: Dictionary, l: float) -> void:
	var out: Vector3 = r.out
	var down: Vector3 = r.down
	# Y out of the body (a decal projects along -Y), Z down it (the texture's top at the wound)
	var b := Basis(out.cross(down).normalized(), out, down)
	r.d.transform = Transform3D(b, (r.top as Vector3) + down * l * 0.5)
	r.d.size = Vector3(float(r.w), 0.16, l)

func _runs_step(dt: float) -> void:
	for i in range(runs.size() - 1, -1, -1):
		var r: Dictionary = runs[i]
		if not is_instance_valid(r.d):
			runs.remove_at(i)
			continue
		if float(r.t) >= 5.0:
			continue
		r.t = float(r.t) + dt
		var k := clampf(float(r.t) / 5.0, 0.0, 1.0)
		_run_place(r, maxf(0.02, float(r.len) * (1.0 - (1.0 - k) * (1.0 - k))))     # (fast at first, slowing)

# the run's picture: a blot at the top, streaks down from it of different lengths, each ending in a fat drip
static func _run_texture() -> Texture2D:
	if _run_tex:
		return _run_tex
	var w := 64
	var h := 256
	var a := PackedFloat32Array()
	a.resize(w * h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for y in 44:
		for x in w:
			var e := Vector2((x - 32.0) / 28.0, (y - 16.0) / 15.0).length() + sin(x * 0.7) * 0.06 + cos(y * 0.9) * 0.05
			a[y * w + x] = clampf((1.0 - e) * 6.0, 0.0, 1.0)
	for s in 6:
		var cx := rng.randf_range(12.0, 52.0)
		var sw := rng.randf_range(2.0, 5.0)
		var ln := rng.randf_range(70.0, 248.0)
		var ph := rng.randf() * TAU
		for y in range(12, int(ln)):
			var x0 := cx + sin(y * 0.04 + ph) * 2.0
			var ww := sw * (1.0 - 0.3 * float(y) / ln)
			for x in range(maxi(0, int(x0 - ww - 2)), mini(w, int(x0 + ww + 3))):
				a[y * w + x] = maxf(a[y * w + x], clampf(ww - absf(x - x0) + 0.5, 0.0, 1.0))
		var br := sw * 1.5
		for y in range(maxi(0, int(ln - br - 2)), mini(h, int(ln + br + 2))):
			for x in range(maxi(0, int(cx - br - 2)), mini(w, int(cx + br + 3))):
				var x0 := cx + sin(y * 0.04 + ph) * 2.0
				var d := Vector2(x - x0, y - ln).length()
				a[y * w + x] = maxf(a[y * w + x], clampf(br - d + 0.5, 0.0, 1.0))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := a[y * w + x]
			img.set_pixel(x, y, Color(0.3 + 0.08 * v, 0.008, 0.016, v))
	img.generate_mipmaps()
	_run_tex = ImageTexture.create_from_image(img)
	return _run_tex

# ---------------------------------------------------------------- bloody weapons

## A melee weapon hit something (VoxelMelee.spray): more blood on it.
func weapon_hit(wpn: Node, cubes: int) -> void:
	if level == 0 or wpn.shooter == null or not wpn.shooter.local or wpn.view == null:
		return
	wpn.blood_k = minf(1.0, float(wpn.blood_k) + 0.07 + cubes * 0.003)
	var e: Dictionary = {}
	for x in _weapons:
		if x.w == wpn:
			e = x
	if e.is_empty():
		var m := ShaderMaterial.new()
		m.shader = _coat()
		e = {"w": wpn, "mat": m, "wet": 1.0}
		_weapons.append(e)
	e.wet = 1.0
	_coat_meshes(wpn.view, e.mat)                       # (every hit: a weapon's view may have new parts since)

func _coat_meshes(n: Node, mat: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_overlay == null:
			(c as MeshInstance3D).material_overlay = mat
		_coat_meshes(c, mat)

func _weapons_step(dt: float) -> void:
	for e in _weapons:
		var wpn = e.w
		if not is_instance_valid(wpn):
			continue
		e.wet = maxf(0.0, float(e.wet) - dt / 45.0)        # (dry in 45 s; the coat stays, dark)
		var m: ShaderMaterial = e.mat
		m.set_shader_parameter("amount", float(wpn.blood_k))
		m.set_shader_parameter("wet", float(e.wet))
		# a wet one drips (in front of you, off whatever part of it)
		if wpn.view.visible and float(e.wet) > 0.25 and randf() < dt * 4.0 * float(e.wet) * float(wpn.blood_k):
			var parts: Array = wpn.view.find_children("*", "MeshInstance3D", true, false)
			if not parts.is_empty():
				var mi: MeshInstance3D = parts[randi() % parts.size()]
				_drop(mi.global_transform * mi.get_aabb().get_center(), _rand3(0.05))

static func _coat() -> Shader:
	if _coat_shader:
		return _coat_shader
	_coat_shader = Shader.new()
	_coat_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform float amount = 0.0;
uniform float wet = 1.0;
varying vec3 op;
void vertex() { op = VERTEX; }
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void fragment() {
	vec3 p = op * 22.0;
	float n = noise(p) * 0.65 + noise(p * 2.9 + 7.0) * 0.35;
	float a = smoothstep(1.0 - amount * 0.55, 1.0 - amount * 0.55 + 0.05, n);
	if (a < 0.02) { discard; }
	ALBEDO = mix(vec3(0.07, 0.01, 0.008), vec3(0.17, 0.004, 0.008), wet);
	ROUGHNESS = mix(0.75, 0.12, wet);
	SPECULAR = 0.6;
	ALPHA = a;
}
"""
	return _coat_shader
