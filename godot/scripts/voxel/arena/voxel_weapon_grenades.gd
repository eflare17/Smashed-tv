class_name VoxelWeaponGrenades
extends VoxelGun
## The grenade launcher (the owner, 20 Oct: six new weapons, each doing something different): the game's own green
## block launcher held over the right shoulder, with a revolving drum of six round its waist. Left click lobs a
## bouncing grenade (16 m/s along the aim, a little up, falling): a stubby dark-green shell with a red light blinking,
## tumbling as it flies. It bounces off the walls, pillars and floor with a clink and rolls to a stop, blinking faster;
## a body hit square at speed sets it off at once, otherwise it goes off 2.2 s after it left. Right click fires a
## sticky bomb, flatter and faster: a grey puck blinking green that sticks to whatever it hits first, a wall, the floor
## or a body (on a body it rides on the arm, leg or head it hit as they move, and drops to the floor if that part comes
## off); up to six can be out. R sets them all off, one after another, with a beep; with none out it reloads: the drum
## swings out, the spent cases drop and the rounds click in one by one (1.8 s for six). Both use the drum's rounds.
## The blast (blast(), 2.8 m round): every body in reach, standing, dead or a lying piece, has a crater blown out of the
## side facing it (bigger the nearer; at point blank the limbs whose joints are close are torn off whole), is hurt by
## how near it was, thrown away and up, and the near ones catch fire; frozen ones shatter; a wall or pillar between
## shelters them. The cubes fly out from the blast, the pieces lying about are tossed, the cubes lying about jump.
## A fireball of flame cubes, a flash, a shock ball, smoke and a glowing scorch on the floor; the view kicks by how
## near you were. Top-down it fires level toward the mouse. Owned by the voxel session.

const SHOT_T := 0.7             # seconds between grenades ...
const STICKY_T := 0.45          # ... and sticky bombs
const OPEN_T := 0.3             # the reload: the drum swung out ...
const LOAD_T := 0.2             # ... a round clicked in, each ...
const CLOSE_T := 0.3            # ... swung shut (six: 1.8 s)
const SPEED := 16.0             # m/s a grenade leaves at ...
const LOFT := 0.12              # ... aimed this much up (a share of its speed)
const GRAVITY := 9.8
const FUSE := 2.2               # seconds till a grenade goes off by itself
const IMPACT_V := 7.0           # m/s: a body hit this fast sets it off at once (slower: it bounces off)
const BOUNCE := 0.5             # the share of its speed into a surface it bounces back with ...
const SLIDE := 0.75             # ... and of its speed along it
const ROLL_DRAG := 2.2          # rolling on the floor it slows by this (a second, exponential)
const GREN_R := 0.05            # its radius, metres (it bounces off this far out)
const STICKY_SPEED := 20.0
const STICKY_LOFT := 0.03
const STICKY_G := 4.0           # the sticky bomb falls slower (it's flatter)
const STICKY_R := 0.04          # its radius for hitting bodies
const STICKY_MAX := 6
const BEEP_T := 0.15            # R: the beep, then they go off ...
const CHAIN_T := 0.08           # ... this far apart, oldest first
const BLAST_R := 2.8            # metres a blast reaches (from the body's side facing it)
const CRATER_MIN := 0.10        # the crater's radius at the edge ...
const CRATER_MAX := 0.22        # ... and at point blank
const SINK := 0.4               # its middle this share of its radius in past the surface
const HP_PER_CUBE := 0.02       # the health a body cube the crater takes costs (carve's own, by cube size)
const TEAR_D := 0.45            # a blast this near a body's side tears off ...
const TEAR_R := 0.62            # ... the limbs whose joints are within this of it (half that at TEAR_D)
const TEAR := ["head", "arm_l", "arm_r", "thigh_l", "thigh_r", "forearm_l", "forearm_r", "shin_l", "shin_r",
	"hand_l", "hand_r", "foot_l", "foot_r"]
const HURT := 70.0              # health a blast takes at point blank (k^1.5 of it further off), plus HURT_MIN
const HURT_MIN := 4.0
const OUT := 6.5                # the throw: away * OUT * (0.3 + k) + up * LIFT * (0.45 + 0.7 k), m/s
const LIFT := 5.0
const IGNITE_K := 0.6           # nearer than this (k) they catch fire a little
const COVER := 0.35             # behind a wall or pillar: this share of the blast, no crater
const BACK := 0.3               # the trace to a body starts this far back of the blast (a blast right on it)
const DIG_MS := 9.0             # craters further off are dug over the next frames, this many ms a frame at most
const SMOKE_MAX := 500
const SCORCHES := 10
const OLIVE := Color(0.2, 0.26, 0.12)
const STEEL := Color(0.22, 0.23, 0.2)
const BRASS := Color(0.72, 0.56, 0.24)
# the launcher's own .vox (voxels, its mesh space: the grip at the origin, the barrel toward +z): the tube's waist,
# where the drum goes round it
const WAIST_Y := 14.0
const DRUM_Z0 := -28.0
const DRUM_Z1 := -8.0
const DRUM_R := 12.5

var _proj := []                 # grenades and sticky bombs out: [{kind, p, v, t, mode, rot, ...}] (see fly)
var _chain := []                # R: the sticky bombs still to go off, oldest first
var _chain_t := 0.0
var _digs := []                 # craters still to dig (blast's jobs), with what each blast did: [[job, info]]
var _spent_ms := 0.0            # this frame's blasts so far (the craters queued get what's left of DIG_MS)
var _shots := 0                 # rounds fired (the drum's turn)
var _drum: Node3D
var _drum_ang := 0.0            # the drum's turn now (radians), easing toward _shots' sixths
var _drum_spin := 0.0           # extra turn: the flourish as it shuts
var _caps: Array[Node3D] = []   # the rounds in the drum (in its slots and on its back face), one a chamber
var _led: MeshInstance3D        # the detonator light on top: green with stickies out, red as they go off
var _led_mat: StandardMaterial3D
var _det_k := 0.0               # 1 just pressed the detonator, falling back
var _click_t := 0.0             # seconds till the drum clicks round after a shot (0: none due)
var _clock := 0.0
var _smoke: MultiMeshInstance3D
var _sp_p := PackedVector3Array()
var _sp_v := PackedVector3Array()
var _sp_life := PackedFloat32Array()
var _sp_span := PackedFloat32Array()
var _sp_size := PackedFloat32Array()
var _sp_shade := PackedFloat32Array()
var _sp_n := 0
var _booms := []                # each blast's flash and shock ball fading: [{t, light, ball}]
var _lights: Array[OmniLight3D] = []
var _balls: Array[MeshInstance3D] = []
var _scorch: Array[MeshInstance3D] = []
var _scorch_t := PackedFloat32Array()
var _scorch_next := 0
var _trail_t := 0.0

func _init() -> void:
	vox = "launcher"
	vox_scale = 0.0042
	rest = Vector3(0.25, -0.285, -0.5)
	aimed_at = rest
	shell_size = Vector3(0.03, 0.03, 0.045)
	shell_col = Color(0.5, 0.48, 0.22)
	clip = 6
	clip_max = 6
	reload_total = OPEN_T + LOAD_T * 6.0 + CLOSE_T
	_cd_total = SHOT_T

# ---------------------------------------------------------------- the launcher

## The game's block launcher at scale metres a voxel, without the bits of the character's head that the sprite it was
## built from had over its waist (cached).
static var _meshes := {}
static func launcher_mesh(scale: float) -> ArrayMesh:
	var ck := "%.5f" % scale
	if _meshes.has(ck):
		return _meshes[ck]
	var am := ArrayMesh.new()
	var meta: Dictionary = VoxelModel.weapon_meta()
	if meta.has("launcher"):
		var vf := VoxFile.load_file(VoxelModel.DIR + "weapons/" + String(meta.launcher.file))
		if vf != null:
			var g := vf.model_grid()
			var s: Vector3i = g.size
			var cells: PackedInt32Array = g.cells
			# (the head sat over the waist, z 42-77: what's above the tube there, its hair and skin, the glasses' blue)
			for z in range(42, mini(78, s.z)):
				for y in range(20, s.y):
					for x in s.x:
						var i := x + s.x * (y + s.y * z)
						if cells[i] == 0:
							continue
						var k := cells[i] - 1
						var r := (k >> 16) & 255
						var gr := (k >> 8) & 255
						var bl := k & 255
						var green := gr >= r - 2 and gr >= bl
						if y >= 29 or (y >= 23 and not green) or (z >= 48 and z <= 73 and y >= 25) or (z >= 50 and bl > r + 10):
							cells[i] = 0
			g["cells"] = cells
			var o: Array = meta.launcher.origin
			am = VoxelBody.array_mesh(VoxMesher.mesh(g, Vector3(o[0], o[1], o[2]), scale))
	_meshes[ck] = am
	return am

func _gun_build() -> void:
	var s := vox_scale
	var mi: MeshInstance3D = _model.get_child(0)
	mi.mesh = launcher_mesh(s)
	_muzzle = Vector3(0, 17.5 * s, -41.0 * s)
	_flash.position = _muzzle + Vector3(0, 0, -0.05)
	_flash.scale = Vector3.ONE * 1.25
	_model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# the drum round the waist: a hexagonal cylinder turning about the tube, a round showing in a slot on each face
	# and its brass base on the back face (toward you)
	_drum = Node3D.new()
	_model.add_child(_drum)
	_drum.position = Vector3(0, WAIST_Y * s, -(DRUM_Z0 + DRUM_Z1) * 0.5 * s)
	var dl := DRUM_Z1 - DRUM_Z0
	var steel := mat(STEEL, 0.55, 0.45)
	var rim := mat(Color(0.12, 0.13, 0.12), 0.6, 0.4)
	for e in [[DRUM_R, dl, 0.0, steel], [DRUM_R + 0.8, 1.4, dl * 0.5 - 0.7, rim], [DRUM_R + 0.8, 1.4, -dl * 0.5 + 0.7, rim]]:
		_drum.add_child(_hex(float(e[0]) * s, float(e[1]) * s, float(e[2]) * s, e[3]))
	var slot := mat(Color(0.05, 0.05, 0.05), 0.2, 0.8)
	var shell := mat(OLIVE.lightened(0.15), 0.2, 0.55)
	var brass := mat(BRASS, 0.8, 0.35)
	var r_in := DRUM_R * cos(PI / 6.0)
	for j in 6:
		var ch := Node3D.new()                    # chamber j: its local +y out through face j
		_drum.add_child(ch)
		ch.rotation = Vector3(0, 0, j * TAU / 6.0)
		box(ch, Vector3(7.0, 0.8, dl - 3.0) * s, Vector3(0, r_in + 0.1, 0) * s, slot)
		var full := Node3D.new()                  # what shows while it's loaded
		ch.add_child(full)
		box(full, Vector3(5.0, 1.3, dl - 5.0) * s, Vector3(0, r_in + 0.45, -0.5) * s, shell)
		box(full, Vector3(5.6, 1.5, 1.6) * s, Vector3(0, r_in + 0.5, dl * 0.5 - 4.0) * s, brass)
		box(full, Vector3(4.6, 4.6, 0.7) * s, Vector3(0, DRUM_R * 0.6, dl * 0.5 + 0.2) * s, shell)
		box(full, Vector3(2.2, 2.2, 0.9) * s, Vector3(0, DRUM_R * 0.6, dl * 0.5 + 0.4) * s, brass)
		_caps.append(full)
	# the detonator light, on top behind the drum
	_led_mat = mat(Color(0.2, 1.0, 0.35), 0.0, 0.5, 4.0)
	box(_model, Vector3(5.0, 1.6, 5.0) * s, Vector3(-4.0 * s, 24.6 * s, 34.0 * s), mat(Color(0.08, 0.08, 0.08), 0.3, 0.6))
	_led = box(_model, Vector3(2.2, 1.4, 2.2) * s, Vector3(-4.0 * s, 25.6 * s, 34.0 * s), _led_mat)
	_led.visible = false
	_fx_build()

# the blast's looks, all in the world: smoke (one MultiMesh), flash lights, shock balls and scorch marks (pools)
func _fx_build() -> void:
	_smoke = MultiMeshInstance3D.new()
	_smoke.top_level = true
	_smoke.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = sm
	_smoke.multimesh = MultiMesh.new()
	_smoke.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_smoke.multimesh.use_colors = true
	_smoke.multimesh.mesh = bm
	_smoke.multimesh.instance_count = SMOKE_MAX
	_smoke.multimesh.visible_instance_count = 0
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)
	_sp_p.resize(SMOKE_MAX)
	_sp_v.resize(SMOKE_MAX)
	_sp_life.resize(SMOKE_MAX)
	_sp_span.resize(SMOKE_MAX)
	_sp_size.resize(SMOKE_MAX)
	_sp_shade.resize(SMOKE_MAX)
	for i in 4:
		var l := OmniLight3D.new()
		l.top_level = true
		l.light_color = Color(1.0, 0.62, 0.3)
		l.omni_range = 7.0
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_lights.append(l)
		var ball := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		sph.radial_segments = 12
		sph.rings = 6
		ball.mesh = sph
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bmat.albedo_color = Color(1.0, 0.75, 0.4, 0.0)
		ball.material_override = bmat
		ball.top_level = true
		ball.visible = false
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ball)
		_balls.append(ball)
	# scorch: dark in the middle fading out, with a ring of embers that glow and die
	var soot := Gradient.new()
	soot.set_color(0, Color(1, 1, 1, 0.95))
	soot.set_color(1, Color(1, 1, 1, 0.0))
	soot.add_point(0.6, Color(1, 1, 1, 0.7))
	var ember := Gradient.new()
	ember.set_color(0, Color(0, 0, 0))
	ember.set_color(1, Color(0, 0, 0))
	ember.add_point(0.42, Color(0.15, 0.03, 0.0))
	ember.add_point(0.62, Color(1.0, 0.42, 0.08))
	ember.add_point(0.8, Color(0.5, 0.08, 0.0))
	var tex_soot := _radial(soot)
	var tex_ember := _radial(ember)
	for i in SCORCHES:
		var sc := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE
		sc.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.03, 0.024, 0.02, 1.0)
		m.albedo_texture = tex_soot
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_texture = tex_ember
		m.emission_energy_multiplier = 0.0
		sc.material_override = m
		sc.top_level = true
		sc.visible = false
		sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sc)
		_scorch.append(sc)
	_scorch_t.resize(SCORCHES)

# a hexagonal prism along z (a flat face up), radius r to its corners, length l, its middle at z
static func _hex(r: float, l: float, z: float, m: Material) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 0, z)
	root.rotation = Vector3(0, 0, PI / 6.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = l
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.rotation = Vector3(PI / 2.0, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

static func _radial(g: Gradient) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func hand_mesh() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = launcher_mesh(shooter.avatar.model.voxel_m * 0.55)
	mi.material_override = arena._mat
	return mi

func bar_text() -> String:
	var n := sticky_count()
	return "%d/%d" % [clip, clip_max] + (" •%d" % n if n > 0 else "")

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.55, col.g * 0.6, col.b * 0.5, col.a)
	var green := Color(0.55, 0.75, 0.35, col.a)
	for b in [[Rect2(0.1, 0.9, 1.3, 2.6), dim], [Rect2(1.4, 1.4, 2.6, 1.6), green], [Rect2(4.0, 0.8, 2.0, 2.8), col],
			[Rect2(6.0, 1.2, 3.6, 2.0), green], [Rect2(9.2, 1.1, 0.6, 2.2), Color(0.95, 0.3, 0.2, col.a)],
			[Rect2(6.4, 3.2, 1.0, 1.5), dim], [Rect2(4.4, 1.3, 0.5, 0.5), dim], [Rect2(5.1, 2.6, 0.5, 0.5), dim]]:
		ci.draw_rect(Rect2(r.position + (b[0] as Rect2).position * u, (b[0] as Rect2).size * u), b[1])

# ---------------------------------------------------------------- firing

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_fire("grenade")
	elif button == MOUSE_BUTTON_RIGHT:
		_fire("sticky")

func _fire(kind: String) -> void:
	if _cd > 0.0 or reload_t > 0.0:
		return
	if kind == "sticky" and sticky_count() >= STICKY_MAX:
		sfx("dry_fire")
		sfx("grenades_beep", Vector3.INF, -12.0, 0.6)
		_cd = 0.25
		return
	if clip <= 0:
		sfx("dry_fire")
		_cd = 0.25
		start_reload()
		return
	var a := aim()
	if a.is_empty():
		return
	var from: Vector3 = a[2]
	var ad: Vector3 = a[1]
	if ad.length() < 0.5:
		ad = look()                             # (top-down, the mouse right on Jared)
	# standing against a wall, the muzzle's through it: it leaves from this side
	var q := PhysicsRayQueryParameters3D.create(a[0], from, 1)
	q.exclude = shooter.exclude()
	var wh := get_world_3d().direct_space_state.intersect_ray(q)
	if not wh.is_empty():
		from = (wh.position as Vector3) + ((a[0] as Vector3) - from).normalized() * 0.08
	var dir := _toward(a[0], ad, from)
	var sticky := kind == "sticky"
	var v := dir * (STICKY_SPEED if sticky else SPEED) + Vector3.UP * (STICKY_SPEED * STICKY_LOFT if sticky else SPEED * LOFT)
	_spawn(kind, from, v)
	clip -= 1
	_shots += 1
	_cd = STICKY_T if sticky else SHOT_T
	_cd_total = _cd
	shot_fx(from, 0.9 if sticky else 1.3, 0)
	sfx("grenades_fire", Vector3.INF, -3.0 if sticky else 0.0, 1.18 if sticky else 1.0)
	_click_t = 0.2
	last = {"fired": kind, "rounds": clip, "out": sticky_count()}

# the way from the muzzle to whatever the aim's line meets first (a body, a wall, the floor; else 40 m out)
func _toward(from: Vector3, dir: Vector3, muzzle: Vector3) -> Vector3:
	var reach := 40.0
	for b in arena.bodies:
		var h: Dictionary = b.trace(from, dir, reach)
		if not h.is_empty():
			reach = float(h.dist)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1)
	q.exclude = shooter.exclude()
	var wh: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var to: Vector3 = wh.position if not wh.is_empty() else from + dir * reach
	var d := to - muzzle
	return d.normalized() if d.length() > 0.3 and d.dot(dir) > 0.0 else dir

## How many sticky bombs are out (flying, stuck or dropped).
func sticky_count() -> int:
	var n := 0
	for st in _proj:
		if st.kind == "sticky":
			n += 1
	return n

## R: the sticky bombs out go off one after another (a beep first); none out: reload.
func reload_key() -> void:
	if not _chain.is_empty():
		return
	if sticky_count() == 0:
		start_reload()
		return
	for st in _proj:
		if st.kind == "sticky":
			st.chained = true
			_chain.append(st)
	_chain_t = -BEEP_T
	_det_k = 1.0
	sfx("grenades_beep")
	last = {"detonate": _chain.size()}

func start_reload() -> void:
	if reload_t > 0.0 or clip >= clip_max:
		return
	var missing := clip_max - clip
	reload_total = OPEN_T + LOAD_T * missing + CLOSE_T
	reload_t = reload_total
	if is_out():
		# the drum swung out, the spent cases dropping (put away, it reloads unheard and unseen)
		sfx("grenades_open")
		for i in missing:
			eject()

func _reloading(from: float, to: float) -> void:
	var e0 := reload_total - from
	var e1 := reload_total - to
	# a round in at the end of each LOAD_T after the drum is out
	var n0 := clampi(floori((e0 - OPEN_T) / LOAD_T), 0, clip_max)
	var n1 := clampi(floori((e1 - OPEN_T) / LOAD_T), 0, clip_max)
	for i in n1 - n0:
		if clip < clip_max:
			clip += 1
			if is_out():
				sfx("grenades_load", Vector3.INF, -2.0, randf_range(0.95, 1.05))
	var shut := reload_total - CLOSE_T * 0.6
	if e0 < shut and e1 >= shut:
		_drum_spin += TAU
		if is_out():
			sfx("grenades_close")

func _reload_pose() -> Array:
	if reload_t <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var e := reload_total - reload_t
	var k := minf(_ease(e / OPEN_T), _ease(reload_t / CLOSE_T))
	# a nudge as each round goes in
	var f := fmod(maxf(0.0, e - OPEN_T), LOAD_T) / LOAD_T if e > OPEN_T and reload_t > CLOSE_T else 0.0
	var push := sin(f * PI) * 0.01
	return [Vector3(-0.05, 0.03 + push, 0.05) * k, Vector3(0.25, 0.3, 0.6) * k]

static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

# ---------------------------------------------------------------- grenades and sticky bombs in the world

func _spawn(kind: String, from: Vector3, v: Vector3) -> void:
	var node := Node3D.new()
	node.top_level = true
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	var parts := sticky_model(node) if kind == "sticky" else grenade_model(node)
	var st := launch_state(kind, from, v)
	st.node = node
	st.lamp = parts.lamp
	st.light = parts.light
	st.blink = 0.0
	node.global_transform = Transform3D(st.rot, from)
	_proj.append(st)

## A grenade or sticky bomb leaving from at v (static, for the checks): {kind, p (its middle; a sticky bomb's base),
## v, t (seconds out), mode ("fly", "roll", "stuck", "fall", "rest"; "hit": going off; "gone"), rot, spin (axis * radians a second),
## bounces, body, part, local (stuck on a body: where, in that part's bone space), n (the surface's normal)}.
static func launch_state(kind: String, from: Vector3, v: Vector3) -> Dictionary:
	var side := v.cross(Vector3.UP)
	var axis := side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	return {"kind": kind, "p": from, "v": v, "t": 0.0, "mode": "fly", "bounces": 0,
		"rot": dir_basis(v) if kind == "grenade" else Basis(),
		"spin": axis * 16.0 if kind == "grenade" else Vector3.UP * 22.0,
		"body": null, "on_body": false, "part": "", "local": Transform3D(), "n": Vector3.UP, "node": null, "lamp": null,
		"light": null, "blink": 0.0, "chained": false}

## One step of a grenade or sticky bomb (static, for the checks): it moves dt, falling; bounces off the world (space:
## the physics space, or null for just the floor) and off bodies hit slowly; rolls on the floor once it barely bounces.
## A sticky bomb sticks to what it hits (stick: on a body it keeps where, in the part's bone space). Returns what
## happened: {} or {what: "bounce" / "impact" (a body hit at speed: it goes off at 'at') / "stick" / "land", at, speed,
## on ("body" / "floor" / "wall"), body, part}.
static func fly(st: Dictionary, dt: float, bodies: Array, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Dictionary:
	var sticky: bool = st.kind == "sticky"
	var mode: String = st.mode
	st.t = float(st.t) + dt
	if mode != "fly" and mode != "roll" and mode != "fall":
		return {}
	var p0: Vector3 = st.p
	var v: Vector3 = st.v
	var floor_y := 0.0 if sticky else GREN_R
	if mode == "roll":
		var kd := exp(-ROLL_DRAG * dt)
		v = Vector3(v.x * kd, 0.0, v.z * kd)
		if v.length() < 0.05:
			st.v = Vector3.ZERO
			return {}
	else:
		v.y -= (STICKY_G if sticky and mode == "fly" else GRAVITY) * dt
	var p1 := p0 + v * dt
	var seg := p0.distance_to(p1)
	if seg < 0.000001:
		st.v = v
		return {}
	var dir := (p1 - p0) / seg
	# the nearest thing on the way: the floor, the world, a body
	var best := seg + 1.0
	var at := p1
	var n := Vector3.UP
	var on := ""
	var hit_b: VoxelBody = null
	var hit_part := ""
	if p1.y < floor_y and dir.y < 0.0:
		best = maxf(0.0, (p0.y - floor_y) / -dir.y)
		at = p0 + dir * best
		on = "floor"
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p0, p1 + dir * (0.0 if sticky else GREN_R), 1)
		q.exclude = exclude
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			var wd := p0.distance_to(wh.position) - (0.0 if sticky else GREN_R)
			if wd < best:
				best = maxf(0.0, wd)
				n = wh.normal
				at = (wh.position as Vector3) + n * (0.0 if sticky else GREN_R)
				on = "floor" if n.y > 0.7 else "wall"
	if mode != "fall":
		for b in bodies:
			if not is_instance_valid(b):
				continue
			var h := thick_trace(b, p0, dir, minf(best, seg) + (0.0 if sticky else GREN_R), STICKY_R if sticky else GREN_R)
			if not h.is_empty() and float(h.dist) < best + (0.0 if sticky else GREN_R):
				best = float(h.dist)
				hit_b = b
				hit_part = h.part
				n = h.normal if (h.normal as Vector3).length() > 0.5 else -dir     # (a trace into the first cell gives none)
				at = h.point
				on = "body"
	if on == "":
		st.p = p1
		st.v = v
		return {}
	var speed := v.length()
	if mode == "fall":
		# a sticky bomb dropped off a part: down on the floor, flat
		st.mode = "rest"
		st.p = Vector3(at.x, 0.0, at.z) if on == "floor" else at
		st.v = Vector3.ZERO
		st.n = Vector3.UP if on == "floor" else n
		st.rot = up_basis(st.n)
		return {"what": "land", "at": st.p, "speed": speed, "on": on}
	if sticky:
		st.mode = "stuck"
		st.v = Vector3.ZERO
		st.n = n
		st.rot = up_basis(n)
		st.p = at
		if hit_b != null:
			st.body = hit_b
			st.on_body = true
			st.part = hit_part
			var bx := bone_xform(hit_b, hit_part)
			st.local = bx.affine_inverse() * Transform3D(st.rot, at)
		return {"what": "stick", "at": at, "speed": speed, "on": on, "body": hit_b, "part": hit_part}
	if hit_b != null and speed >= IMPACT_V:
		st.mode = "hit"
		st.p = at - dir * 0.04
		return {"what": "impact", "at": st.p, "speed": speed, "on": on, "body": hit_b, "part": hit_part}
	# a bounce: the speed into the surface turned back and damped, the speed along it kept mostly
	var vn := n * v.dot(n)
	v = (v - vn) * SLIDE - vn * (BOUNCE if hit_b == null else 0.3)
	at += n * (GREN_R if hit_b != null else 0.002)
	st.bounces = int(st.bounces) + 1
	if on == "floor" and absf(v.y) < 1.2 and at.y < floor_y + 0.1:
		st.mode = "roll"                    # (on a pillar's top it goes on hopping, and falls off its edge)
	if st.mode == "roll":
		v.y = 0.0
		at.y = floor_y
	st.p = at
	st.v = v
	st.spin = (st.spin as Vector3) * 0.6 + n.cross(v) * 0.2
	return {"what": "bounce", "at": at, "speed": absf(vn.dot(n)) if vn.length() > 0.0 else 0.0, "on": on, "body": hit_b, "part": hit_part}

## A sticky bomb stuck on a body follows the part it's on (static, for the checks): st.p, st.n and st.rot moved to
## where that part is now. False if the body is gone or that part has come off.
static func ride(st: Dictionary) -> bool:
	if not is_instance_valid(st.body):
		return false
	var b: VoxelBody = st.body
	var pt: Dictionary = b.parts.get(String(st.part), {})
	if pt.is_empty() or bool(pt.gone) or int(pt.left) <= 0:
		return false
	var x := bone_xform(b, String(st.part)) * (st.local as Transform3D)
	st.p = x.origin
	st.rot = x.basis.orthonormalized()
	st.n = (st.rot as Basis).y
	return true

## A part's bone, world.
static func bone_xform(b: VoxelBody, part: String) -> Transform3D:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[part].bone))

## A body traced with a ray as thick as r: the middle one and four round it (the models have one-cube slits a thin
## ray slips through, a seam down a chest); the nearest hit, or {}.
static func thick_trace(b: VoxelBody, from: Vector3, dir: Vector3, max_d: float, r: float) -> Dictionary:
	var best := b.trace(from, dir, max_d)
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var up := side.cross(dir).normalized()
	for o in [side, -side, up, -up]:
		var h := b.trace(from + (o as Vector3) * r * 0.8, dir, max_d)
		if not h.is_empty() and (best.is_empty() or float(h.dist) < float(best.dist)):
			best = h
	return best

## y along n (a sticky bomb's face down on a surface).
static func up_basis(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))

## -z along d (a grenade's nose along its flight).
static func dir_basis(d: Vector3) -> Basis:
	if d.length_squared() < 0.000001:
		return Basis()
	var nd := d.normalized()
	return Basis.looking_at(nd, Vector3.UP if absf(nd.y) < 0.98 else Vector3.BACK)

## A grenade's boxes under parent (its middle at the origin, the nose -z): a stubby dark-green shell rounded off,
## a brass band, the fuze, a red light. Returns {lamp, light}.
static func grenade_model(parent: Node3D) -> Dictionary:
	var shell := mat(OLIVE, 0.25, 0.55)
	box(parent, Vector3(0.062, 0.062, 0.1), Vector3.ZERO, shell)
	box(parent, Vector3(0.072, 0.05, 0.088), Vector3.ZERO, shell)
	box(parent, Vector3(0.05, 0.072, 0.088), Vector3.ZERO, shell)
	box(parent, Vector3(0.068, 0.068, 0.016), Vector3(0, 0, 0.034), mat(BRASS, 0.8, 0.35))
	box(parent, Vector3(0.034, 0.034, 0.014), Vector3(0, 0, -0.055), mat(Color(0.1, 0.11, 0.08), 0.4, 0.5))
	var lamp := box(parent, Vector3(0.02, 0.014, 0.02), Vector3(0, 0.04, -0.012), mat(Color(1.0, 0.12, 0.06), 0.0, 0.5, 8.0))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.15, 0.08)
	light.omni_range = 1.5
	light.light_energy = 0.0
	light.position = Vector3(0, 0.07, 0)
	parent.add_child(light)
	return {"lamp": lamp, "light": light}

## A sticky bomb's parts under parent (its base at the origin, facing +y): a grey puck with claws round the rim and a
## green light on top. Returns {lamp, light}.
static func sticky_model(parent: Node3D) -> Dictionary:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.064
	cm.height = 0.032
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(Color(0.62, 0.64, 0.68), 0.6, 0.35)
	mi.position = Vector3(0, 0.016, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var dark := mat(Color(0.12, 0.12, 0.13), 0.5, 0.5)
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		box(parent, Vector3(0.02, 0.014, 0.02), Vector3(cos(a) * 0.064, 0.005, sin(a) * 0.064), dark)
	box(parent, Vector3(0.11, 0.006, 0.02), Vector3(0, 0.031, 0), mat(Color(0.95, 0.75, 0.1), 0.2, 0.5))
	box(parent, Vector3(0.036, 0.01, 0.036), Vector3(0, 0.035, 0), dark)
	var lamp := box(parent, Vector3(0.024, 0.012, 0.024), Vector3(0, 0.042, 0), mat(Color(0.2, 1.0, 0.3), 0.0, 0.5, 8.0))
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.4)
	light.omni_range = 1.6
	light.light_energy = 0.0
	light.position = Vector3(0, 0.08, 0)
	parent.add_child(light)
	return {"lamp": lamp, "light": light}

func _proj_step(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = shooter.exclude()
	var big := 2.2 if top_down() else 1.0          # seen from up top they're drawn bigger
	for st in _proj.duplicate():
		if st.mode == "gone":
			continue
		var kind: String = st.kind
		if st.mode == "stuck" and bool(st.on_body) and not ride(st):
			# the part it was on came off (or the body's gone): it drops
			st.mode = "fall"
			st.on_body = false
			st.body = null
			st.v = Vector3.ZERO
		var ev := fly(st, dt, arena.bodies, space, ex)
		if not ev.is_empty():
			_event(st, ev)
		if st.mode == "gone":
			continue
		if kind == "grenade" and float(st.t) >= FUSE:
			_detonate(st, "fuse")
			continue
		# the look: tumbling in flight, rolling along the floor, still once it stops
		var v: Vector3 = st.v
		var rot: Basis = st.rot
		if st.mode == "fly":
			var w: Vector3 = st.spin
			if w.length() > 0.001:
				rot = Basis(w.normalized(), w.length() * dt) * rot
			if kind == "grenade":
				_trail_t += dt
				if _trail_t > 0.025:
					_trail_t = 0.0
					_puff(st.p, -v * 0.05, 0.05, 0.5, 0.75)
		elif st.mode == "roll" and v.length() > 0.02:
			var ax := Vector3.UP.cross(v).normalized()
			rot = Basis(ax, v.length() / GREN_R * dt) * rot
		elif st.mode == "fall":
			rot = Basis(Vector3.RIGHT, 6.0 * dt) * rot
		st.rot = rot.orthonormalized()
		var node: Node3D = st.node
		node.global_transform = Transform3D((st.rot as Basis) * Basis.from_scale(Vector3.ONE * big), st.p)
		# the light: a grenade blinks faster and faster as its fuse runs down (ticking once it's down); a sticky bomb
		# slowly, fast once it's about to go
		var rate := lerpf(2.5, 11.0, clampf(float(st.t) / FUSE, 0.0, 1.0)) if kind == "grenade" else (14.0 if bool(st.chained) else 1.6)
		var was := fmod(float(st.blink), 1.0) < 0.35
		st.blink = float(st.blink) + rate * dt
		var on := fmod(float(st.blink), 1.0) < 0.35
		(st.lamp as Node3D).visible = on
		(st.light as OmniLight3D).light_energy = (1.2 if kind == "grenade" else 1.4) * (1.0 if on else 0.0) * big
		if on and not was and kind == "grenade" and st.mode != "fly":
			sfx("grenades_tick", st.p, -14.0)
	for i in range(_proj.size() - 1, -1, -1):
		if _proj[i].mode == "gone":
			_proj.remove_at(i)

# a bounce's clink, a sticky bomb's clank or thwap, a body hit square
func _event(st: Dictionary, ev: Dictionary) -> void:
	match String(ev.what):
		"bounce":
			if float(ev.speed) > 1.0:
				sfx("grenades_bounce", ev.at, clampf(-14.0 + float(ev.speed) * 1.5, -14.0, 0.0), randf_range(0.9, 1.1))
				if ev.on == "body" and is_instance_valid(ev.body):
					(ev.body as VoxelBody).hit_react(st.v, 6, String(ev.part))
		"impact":
			_detonate(st, "impact")
		"stick":
			var flesh: bool = ev.on == "body"
			sfx("grenades_stick_flesh" if flesh else "grenades_stick", ev.at, -2.0)
			if flesh and is_instance_valid(ev.body):
				(ev.body as VoxelBody).hit_react((ev.at as Vector3) - eye(), 4, String(ev.part))
			last = {"fired": "sticky", "stuck": ("body:" + String(ev.part)) if flesh else String(ev.on), "out": sticky_count(),
				"rounds": clip}
		"land":
			sfx("grenades_stick", ev.at, -8.0, 1.2)

# it goes off where it is (a sticky bomb a little off the surface it's on)
func _detonate(st: Dictionary, how: String) -> void:
	if st.mode == "gone":
		return
	var p: Vector3 = st.p
	if st.kind == "sticky":
		p += (st.n as Vector3) * 0.05
	st.mode = "gone"
	if is_instance_valid(st.node):
		(st.node as Node3D).queue_free()
	explode(p, how, st)

func _chain_step(dt: float) -> void:
	if _chain.is_empty():
		return
	_chain_t += dt
	while not _chain.is_empty() and _chain_t >= 0.0:
		var st: Dictionary = _chain.pop_front()
		if st.mode != "gone":
			_detonate(st, "remote")
			_chain_t -= CHAIN_T
	if _chain.is_empty():
		_chain_t = 0.0

# ---------------------------------------------------------------- the blast

## The middle of a body's part's grid, world.
static func part_middle(b: VoxelBody, n: String) -> Vector3:
	var p: Dictionary = b.parts[n]
	var bi: int = p.bone
	var m := bone_xform(b, n) * Transform3D(Basis.IDENTITY, -b.model.bone_pivot[bi] * b.model.voxel_m)
	return m * ((Vector3(p.origin) + Vector3(p.grid.size) * 0.5) * b.vm)

## What a blast at p aims at on a body: [the middle of its part nearest p, the middle of its chest (or, a lying piece
## with none, of its biggest part)], world.
static func aim_points(b: VoxelBody, p: Vector3) -> Array:
	var near := Vector3.INF
	var chest := Vector3.INF
	var most := 0
	var torso: bool = b.parts.has("torso") and not bool(b.parts.torso.gone) and int(b.parts.torso.left) > 0
	for n in b.parts:
		var pt: Dictionary = b.parts[n]
		if bool(pt.gone) or int(pt.left) <= 0:
			continue
		var m := part_middle(b, n)
		if near == Vector3.INF or m.distance_to(p) < near.distance_to(p):
			near = m
		if (torso and n == "torso") or (not torso and int(pt.left) > most):
			most = int(pt.left)
			chest = m
	if near == Vector3.INF:
		near = b.global_position + Vector3(0, 0.3, 0)
	return [near, chest if chest != Vector3.INF else near]

## A blast at p (static, for the checks). Every body with a side within BLAST_R (alive, dead or a lying piece) is
## traced from p toward its middle: where the trace meets it a crater is due (CRATER_MIN..MAX by nearness; a job:
## the point kept in the part's bone space, dug at once for one at point blank or a lying piece (while DIG_MS lasts:
## it's about to be made a rigid piece again), else by dig()
## later); at point blank the limbs with a joint near enough are torn off whole (sever); near ones catch fire; each is
## hurt by how near, and thrown away and up. A wall or pillar between (space; null: none) shelters it: COVER of the
## blast, no crater. push: which way a direct hit throws them (a grenade's flight, into a sticky bomb's surface), or
## ZERO. Returns {hits: [{body, d (metres to its side), k (nearness 1..0), part, res (the crater dug at
## once, or {}), torn: [sever results], ignited, shattered, v (the throw), away}], jobs: [crater jobs], ms}.
static func blast(bodies: Array, p: Vector3, space: PhysicsDirectSpaceState3D = null, exclude: Array[RID] = [], push: Vector3 = Vector3.ZERO) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out := {"hits": [], "jobs": [], "ms": 0.0}
	var near := []
	for b in bodies:
		if not is_instance_valid(b) or (b as VoxelBody).cubes_left() <= 0:
			continue
		var vb: VoxelBody = b
		var off := vb.global_position - p
		if Vector2(off.x, off.z).length() > BLAST_R + vb.height + 0.5:
			continue
		var aims := aim_points(vb, p)
		var dm := p.distance_to(aims[0])
		if dm <= BLAST_R + 0.6:
			near.append([dm, vb, aims])
	near.sort_custom(func(x, y): return x[0] < y[0])
	var dug_now := false                   # (one point-blank crater dug at once; any more wait their turn)
	for e in near:
		var b: VoxelBody = e[1]
		# traced toward the nearest part's middle (then the chest's): where it meets the body is the side facing it
		var mid: Vector3 = e[2][0]
		var dm := p.distance_to(mid)
		var dir := (mid - p) / dm if dm > 0.001 else Vector3.DOWN
		var h := thick_trace(b, p - dir * BACK, dir, dm + BACK + 0.6, 0.05)
		if h.is_empty():
			mid = e[2][1]
			dm = p.distance_to(mid)
			dir = (mid - p) / dm if dm > 0.001 else Vector3.DOWN
			h = thick_trace(b, p - dir * BACK, dir, dm + BACK + 0.6, 0.05)
		var d := maxf(0.0, float(h.dist) - BACK) if not h.is_empty() else maxf(0.0, dm - 0.25)
		if d > BLAST_R:
			continue
		var k := 1.0 - d / BLAST_R
		var cover := false
		if space != null:
			var to: Vector3 = h.point if not h.is_empty() else mid
			var q := PhysicsRayQueryParameters3D.create(p, to, 1)
			q.exclude = exclude
			var wh := space.intersect_ray(q)
			if not wh.is_empty() and p.distance_to(wh.position) < p.distance_to(to) - 0.05:
				cover = true
				k *= COVER
		var hit := {"body": b, "d": d, "k": k, "part": String(h.get("part", "")), "res": {}, "torn": [], "ignited": 0,
			"shattered": false, "v": Vector3.ZERO, "away": dir, "was_alive": b.alive}
		out.hits.append(hit)
		if not h.is_empty() and not cover:
			var bx := bone_xform(b, String(h.part)).affine_inverse()
			var job := {"body": b, "part": String(h.part), "r": lerpf(CRATER_MIN, CRATER_MAX, k * k), "from": p, "k": k,
				"at": bx * (h.point as Vector3), "dir": (bx.basis * dir).normalized()}
			if (d < TEAR_D and not dug_now) or (b.fragment and (Time.get_ticks_usec() - t0) / 1000.0 < DIG_MS):
				dug_now = dug_now or not b.fragment
				hit.res = dig(job)
				if bool(hit.res.get("shattered", false)):
					hit.shattered = true
					continue
			else:
				out.jobs.append(job)
		# point blank: the limbs whose joints are near torn off whole
		if d < TEAR_D and not cover:
			var tr := TEAR_R * (1.0 - 0.5 * d / TEAR_D)
			for n in TEAR:
				if not b.parts.has(n) or bool(b.parts[n].gone):
					continue
				if bone_xform(b, n).origin.distance_to(p) < tr:
					var sr := b.sever(n)
					if bool(sr.get("shattered", false)):
						hit.res = sr
						hit.shattered = true
						break
					if not (sr.pieces as Array).is_empty():
						(hit.torn as Array).append(sr)
			if hit.shattered:
				continue
		if k > IGNITE_K and d >= TEAR_D and not h.is_empty() and not cover:
			hit.ignited = b.ignite(h.point, lerpf(0.05, 0.14, (k - IGNITE_K) / (1.0 - IGNITE_K)))
		b.hurt(HURT * pow(k, 1.5) + HURT_MIN)
		if b.cubes_left() <= 0:
			hit.shattered = true               # (frozen: the blow shattered it)
			continue
		var off := Vector3(b.global_position.x - p.x, 0.0, b.global_position.z - p.z)
		var away := off.normalized() if off.length() > 0.05 else Vector3.ZERO
		var pf := Vector3(push.x, 0.0, push.z)
		if d < TEAR_D and pf.length() > 0.1:
			away = (away + pf.normalized() * 1.5).normalized()       # hit square: on along the shot
		if away.length() < 0.5:
			away = Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.FORWARD
		var v := (away * OUT * (0.3 + k) + Vector3.UP * LIFT * (0.45 + 0.7 * k)) * (0.6 if b.key == "brute" else 1.0)
		b.launch(v, 3.0 + 9.0 * k)
		hit.v = v
		hit.away = away
	out.ms = (Time.get_ticks_usec() - t0) / 1000.0
	return out

## Digs one of blast's craters (static, for the checks): a ball where the trace met the part (wherever that part is
## now), its middle a little in. Returns carve's result plus ms ({} if the body or the part is gone).
static func dig(job: Dictionary) -> Dictionary:
	if not is_instance_valid(job.body):
		return {}
	var b: VoxelBody = job.body
	var part := String(job.part)
	if not b.parts.has(part) or bool(b.parts[part].gone):
		return {}
	var t0 := Time.get_ticks_usec()
	var x := bone_xform(b, part)
	var r: float = job.r
	var c: Vector3 = x * (job.at as Vector3) + (x.basis * (job.dir as Vector3)).normalized() * r * SINK
	var res := b.carve(c, c, r, HP_PER_CUBE, 3 if r > 0.16 else 2)
	res["centre"] = c
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return res

## A blast at p (how: "impact", "fuse" or "remote"): blast() on the bodies, then what shows and is heard.
func explode(p: Vector3, how: String, st: Dictionary = {}) -> void:
	var t0 := Time.get_ticks_usec()
	var lying: Array = arena.pieces.list().duplicate()     # (the pieces about before this blast's own fly off)
	var ex: Array[RID] = shooter.exclude()
	var push := Vector3.ZERO
	if st.get("kind", "") == "grenade" and how == "impact":
		push = (st.v as Vector3).normalized()
	elif st.get("kind", "") == "sticky" and bool(st.get("on_body", false)):
		push = -(st.n as Vector3)
	var bl := blast(arena.bodies, p, get_world_3d().direct_space_state, ex, push)
	var info := {"boom": how, "shot": String(st.get("kind", "")), "flew_s": snappedf(float(st.get("t", 0.0)), 0.01),
		"bounces": int(st.get("bounces", 0)), "bodies": 0, "cut": 0, "torn": 0, "pieces": 0, "killed": 0, "shattered": 0,
		"ignited": 0, "blast_ms": snappedf(float(bl.ms), 0.1), "carve_ms": 0.0, "queued": (bl.jobs as Array).size(),
		"pushed": 0, "popped": 0, "ms": 0.0}
	var kmax := 0.0
	for hit in bl.hits:
		var b: VoxelBody = hit.body
		info["bodies"] = int(info.bodies) + 1
		kmax = maxf(kmax, float(hit.k))
		var res: Dictionary = hit.res
		if not res.is_empty():
			_crater_fx(b, res, p, float(hit.k), info)
		for sr in hit.torn:
			_torn_fx(b, sr, p, float(hit.k), hit.v, info)
		if bool(hit.shattered):
			info["shattered"] = int(info.shattered) + 1
			continue
		info["ignited"] = int(info.ignited) + int(hit.ignited)
		if bool(hit.was_alive) and is_instance_valid(b) and not b.alive:
			info["killed"] = int(info.killed) + 1
	for job in bl.jobs:
		_digs.append([job, info])
	_spent_ms += float(bl.ms)
	# the pieces lying about tossed, the cubes lying about thrown up
	var pushed := 0
	for pc in lying:
		if not is_instance_valid(pc.rb):
			continue
		var rb: RigidBody3D = pc.rb
		var off := rb.global_position - p
		var d := off.length()
		if d > BLAST_R * 1.3:
			continue
		var k := 1.0 - d / (BLAST_R * 1.3)
		var away := off / d if d > 0.01 else Vector3.UP
		rb.sleeping = false
		rb.apply_central_impulse((away * (3.0 + 7.0 * k) + Vector3.UP * (2.0 + 4.0 * k)) * rb.mass)
		rb.angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 9.0 * k
		pushed += 1
	var popped := 0
	if p.y < 1.5:
		popped = arena.debris.pop(Vector3(p.x, 0.0, p.z), BLAST_R * 0.9, 3.0 + 3.5 * (1.0 - p.y / 1.5), 1200)
	info["pushed"] = pushed
	info["popped"] = popped
	_boom_fx(p)
	sfx("grenades_boom", p, 3.0, randf_range(0.92, 1.05))
	var kd := eye().distance_to(p)
	shooter.kick = maxf(float(shooter.kick), 2.0 * clampf(1.0 - kd / 16.0, 0.15, 1.0))
	if kmax > 0.15:
		hit_stop(0.04 + 0.05 * kmax, 0.07)
	info["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	last = info

# a crater's cubes fly out from the blast; what it knocked off is flung on the same way
func _crater_fx(b: VoxelBody, res: Dictionary, p: Vector3, k: float, info: Dictionary) -> void:
	var bits: Array = res.bits
	arena.knocked += bits.size()
	var c: Vector3 = res.get("centre", b.global_position + Vector3(0, 0.9, 0) if is_instance_valid(b) else p + Vector3.UP)
	var away := (c - p).normalized() if c.distance_to(p) > 0.01 else Vector3.UP
	arena.debris.burst(bits, (away + Vector3.UP * 0.25).normalized(), 3.0 + 6.0 * k)
	info["cut"] = int(info.cut) + int(res.cut)
	info["carve_ms"] = snappedf(float(info.carve_ms) + float(res.get("ms", 0.0)), 0.1)
	if bool(res.get("shattered", false)):
		sfx("shatter", p, 2.0)
		return
	if is_instance_valid(b) and not (res.pieces as Array).is_empty():
		info["pieces"] = int(info.pieces) + (res.pieces as Array).size()
		fling(b, res, away * (4.0 + 8.0 * k) + Vector3.UP * (2.0 + 3.0 * k) + b.air_v * 0.5,
			Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (6.0 + 10.0 * k))

# a limb torn off whole flies off its own way, out from the blast
func _torn_fx(b: VoxelBody, sr: Dictionary, p: Vector3, k: float, thrown: Vector3, info: Dictionary) -> void:
	if not is_instance_valid(b):
		return
	var c := Vector3.ZERO
	var n := 0
	for e in sr.pieces:
		c += (e.xform as Transform3D) * (e.box_at as Vector3)
		n += 1
	c /= float(maxi(1, n))
	var away := (c - p).normalized() if c.distance_to(p) > 0.02 else Vector3.UP
	info["torn"] = int(info.torn) + (sr.parts as Array).size()
	info["pieces"] = int(info.pieces) + n
	arena.pieces.spawn(b, sr.pieces, away * (6.0 + 8.0 * k) + Vector3.UP * (2.5 + 3.0 * k) + thrown * 0.4,
		Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (8.0 + 10.0 * k))

# the craters further off, dug while there's budget_ms left this frame (one at least, if one_anyway)
func _dig_step(budget_ms: float, one_anyway: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var guess := 0.0                    # the next one costs about what the last did: not begun if that runs over
	var first := one_anyway
	while not _digs.is_empty():
		if not first and (Time.get_ticks_usec() - t0) / 1000.0 + guess > budget_ms:
			break
		first = false
		var e: Array = _digs.pop_front()
		var job: Dictionary = e[0]
		var info: Dictionary = e[1]
		var res := dig(job)
		if not res.is_empty():
			guess = float(res.ms)
			_crater_fx(job.body, res, job.from, float(job.k), info)
			info["queued"] = maxi(0, int(info.queued) - 1)

# the fireball (flame cubes out and up), the flash, the shock ball, smoke rolling up, the scorch on the floor
func _boom_fx(p: Vector3) -> void:
	var fl: VoxelFlames = arena.flames
	for i in 80:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1))
		if d.length() < 0.05:
			d = Vector3.UP
		d = d.normalized()
		fl.emit(p + d * 0.15, 1, d * randf_range(2.0, 7.5) + Vector3.UP * 0.8, randf_range(4.0, 8.0), randf_range(0.22, 0.55))
	for i in 14:
		fl.emit(p, 1, Vector3(randf_range(-0.7, 0.7), randf_range(0.8, 2.2), randf_range(-0.7, 0.7)), randf_range(7.0, 10.0), randf_range(0.6, 1.0))
	if p.y < 0.6:
		for i in 22:
			var a := randf() * TAU
			fl.emit(Vector3(p.x, 0.05, p.z), 1, Vector3(cos(a), 0.15, sin(a)) * randf_range(4.0, 7.5), randf_range(4.0, 6.5), randf_range(0.25, 0.45))
	for i in 30:
		var d2 := Vector3(randf_range(-1, 1), randf_range(0.0, 1.0), randf_range(-1, 1)).normalized()
		_puff(p + d2 * randf_range(0.1, 0.5), d2 * randf_range(0.6, 2.2) + Vector3.UP * 0.9, randf_range(0.08, 0.16), randf_range(1.4, 2.6), randf_range(0.0, 0.2))
	# the flash and the shock ball: the least recently used of the four
	var slot := 0
	var oldest := -1.0
	for i in _lights.size():
		var used := -1.0
		for bm in _booms:
			if bm.light == _lights[i]:
				used = float(bm.t)
		if used < 0.0:
			slot = i
			break
		if used > oldest:
			oldest = used
			slot = i
	_booms = _booms.filter(func(bm): return bm.light != _lights[slot])
	var l := _lights[slot]
	l.global_position = p + Vector3(0, 0.3, 0)
	l.visible = true
	var ball := _balls[slot]
	ball.global_position = p
	ball.visible = true
	_booms.append({"t": 0.0, "light": l, "ball": ball})
	if p.y < 1.6:
		var sc := _scorch[_scorch_next]
		_scorch_t[_scorch_next] = 0.0
		_scorch_next = (_scorch_next + 1) % SCORCHES
		var size := 2.3 * (1.0 - p.y / 1.6 * 0.55)
		sc.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(size, 1.0, size)), Vector3(p.x, 0.004 + 0.0006 * _scorch_next, p.z))
		sc.visible = true

func _fx_step(dt: float) -> void:
	for bm in _booms:
		bm.t = float(bm.t) + dt
		var k := clampf(float(bm.t) / 0.25, 0.0, 1.0)
		var l: OmniLight3D = bm.light
		l.light_energy = 6.0 * (1.0 - k) * (1.0 - k)
		var kb := clampf(float(bm.t) / 0.13, 0.0, 1.0)
		var ball: MeshInstance3D = bm.ball
		ball.scale = Vector3.ONE * lerpf(0.3, BLAST_R * 1.15, 1.0 - pow(1.0 - kb, 2.5))
		var bmat: StandardMaterial3D = ball.material_override
		bmat.albedo_color = Color(1.0, 0.6, 0.25, 0.4 * (1.0 - kb))
		if k >= 1.0:
			l.visible = false
			ball.visible = false
	_booms = _booms.filter(func(bm): return float(bm.t) < 0.25)
	for i in SCORCHES:
		var sc := _scorch[i]
		if not sc.visible:
			continue
		_scorch_t[i] += dt
		var t := _scorch_t[i]
		var m: StandardMaterial3D = sc.material_override
		m.emission_energy_multiplier = 3.0 * exp(-t * 1.3)
		m.albedo_color = Color(0.03, 0.024, 0.02, clampf((40.0 - t) / 3.0, 0.0, 1.0))
		if t > 40.0:
			sc.visible = false
	_smoke_step(dt)

# smoke: a grey cube puff at p drifting at v, size metres (it grows), living life seconds; shade 0 dark .. 1 pale
func _puff(p: Vector3, v: Vector3, size: float, life: float, shade: float) -> void:
	var i := _sp_n
	if _sp_n >= SMOKE_MAX:
		i = randi() % SMOKE_MAX
	else:
		_sp_n += 1
	_sp_p[i] = p
	_sp_v[i] = v
	_sp_life[i] = life
	_sp_span[i] = life
	_sp_size[i] = size
	_sp_shade[i] = shade

func _smoke_step(dt: float) -> void:
	var mm := _smoke.multimesh
	var i := 0
	while i < _sp_n:
		_sp_life[i] -= dt
		if _sp_life[i] <= 0.0:
			_sp_n -= 1
			_sp_p[i] = _sp_p[_sp_n]
			_sp_v[i] = _sp_v[_sp_n]
			_sp_life[i] = _sp_life[_sp_n]
			_sp_span[i] = _sp_span[_sp_n]
			_sp_size[i] = _sp_size[_sp_n]
			_sp_shade[i] = _sp_shade[_sp_n]
			continue
		var k := _sp_life[i] / _sp_span[i]               # 1 just puffed .. 0 gone
		var v := _sp_v[i] * exp(-dt * 1.8)
		v.y += 0.5 * dt
		_sp_v[i] = v
		_sp_p[i] += v * dt
		var s := _sp_size[i] * (0.6 + 1.0 * (1.0 - k))
		var g := lerpf(0.07, 0.42, _sp_shade[i])
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(i * 0.7, i * 1.3, 0.0)).scaled(Vector3.ONE * s), _sp_p[i]))
		mm.set_instance_color(i, Color(g, g * 0.96, g * 0.92, 0.4 * k * clampf((1.0 - k) * 8.0, 0.0, 1.0)))
		i += 1
	mm.visible_instance_count = _sp_n

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	_clock += dt
	_det_k = maxf(0.0, _det_k - dt * 3.0)
	if _click_t > 0.0:
		_click_t -= dt
		if _click_t <= 0.0 and is_out():
			sfx("grenades_drum", Vector3.INF, -4.0)
	_proj_step(dt)
	_chain_step(dt)
	_dig_step(DIG_MS - _spent_ms, _spent_ms <= 0.0)
	_spent_ms = 0.0
	_fx_step(dt)
	if clip == 0 and reload_t <= 0.0 and _cd <= 0.0:
		start_reload()
	super.step(dt)
	_drum_step(dt)

func _pose() -> void:
	super._pose()
	# a launcher's kick: the nose thrown up more; a nod as you thumb the detonator; a slow sway
	_model.rotation.x += 0.22 * _kick - 0.14 * _det_k
	_model.rotation.y += 0.1                # (its nose turned in a little, toward the middle)
	_model.position += Vector3(0.0, -0.012 * _kick - 0.02 * _det_k + sin(_clock * 1.7) * 0.003, 0.025 * _kick)

# the drum: a sixth of a turn after each shot (eased), a whole turn as it shuts; the rounds left in it shown; the
# detonator light on with sticky bombs out
func _drum_step(dt: float) -> void:
	var want := _shots * TAU / 6.0 + _drum_spin
	_drum_ang = lerpf(_drum_ang, want, 1.0 - exp(-dt * 14.0))
	var out_k := 0.0
	if reload_t > 0.0:
		out_k = minf(_ease((reload_total - reload_t) / OPEN_T), _ease(reload_t / CLOSE_T))
	_drum.rotation.z = -_drum_ang          # (chamber _shots % 6 at the top)
	_drum.position.x = -0.022 * out_k
	var top := _shots % 6
	for j in 6:
		_caps[j].visible = posmod(j - top, 6) < clip
	var n := sticky_count()
	_led.visible = n > 0 and (not _chain.is_empty() or fmod(_clock * 1.6, 1.0) < 0.5)
	_led_mat.albedo_color = Color(1.0, 0.15, 0.1) if not _chain.is_empty() else Color(0.2, 1.0, 0.35)
	_led_mat.emission = _led_mat.albedo_color

# ---------------------------------------------------------------- checks

static func _grunt(host: Node, at: Vector3 = Vector3.ZERO) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, StandardMaterial3D.new())
	b.position = at
	b.animate(0.0, false)
	return b

# a blast on its own with every crater dug at once (the checks)
static func _blast_all(bodies: Array, p: Vector3) -> Dictionary:
	var bl := blast(bodies, p)
	var t0 := Time.get_ticks_usec()
	for job in bl.jobs:
		var r := dig(job)
		for hit in bl.hits:
			if hit.body == job.body:
				hit.res = r
	bl["dig_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return bl

static func _hit(bl: Dictionary, b: VoxelBody) -> Dictionary:
	for hit in bl.hits:
		if hit.body == b:
			return hit
	return {}

## Grunts at the origin facing +z (chest about y 1.0, head 1.43-1.8): blasts in front of the chest, at point blank, by
## the feet, further off and out of reach, on a dead one and a frozen one; six at once (the cost); a grenade at a
## grunt (impact), at the floor (bounces, rolls), slowly into one (bounces off); sticky bombs on the chest (riding
## along as he moves), on an arm (dropping when it comes off), on the floor; the weapon bar.
static func checks(host: Node) -> Array:
	var out := []
	var imm := VoxelBody.immortal
	VoxelBody.immortal = false
	var made := []
	var none: Array[RID] = []
	# the launcher itself, without the sprite's head
	var raw: ArrayMesh = VoxelArena._gun_mesh("launcher", 0.0042)
	var clean := launcher_mesh(0.0042)
	var nr := raw.get_surface_count()
	var nc := clean.get_surface_count()
	var vr := (raw.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if nr > 0 else 0
	var vc := (clean.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if nc > 0 else 0
	out.append([vc > 1000 and vc < vr, "the launcher's mesh, the head bits over its waist taken out (%d of %d vertices)" % [vc, vr]])
	# 0.6 m in front of the chest
	var b := _grunt(host)
	made.append(b)
	var bl := _blast_all([b], Vector3(0, 1.05, 0.8))
	var h := _hit(bl, b)
	var res: Dictionary = h.get("res", {})
	var cut_near := int(res.get("cut", 0))
	out.append([cut_near > 300 and (res.parts as Array).has("torso") if not res.is_empty() else false,
		"a blast 0.6 m off the chest blows a crater out of it (%d cubes, %s)" % [cut_near, str(res.get("parts", []))]])
	var tr := b.trace(Vector3(0, 1.05, 1.0), Vector3(0, 0, -1), 2.0)
	out.append([tr.is_empty() or float(tr.point.z) < 0.12, "on the side facing it: the chest's front is dug in (now at z %.2f)" % (float(tr.point.z) if not tr.is_empty() else -1.0)])
	out.append([b.airborne and b.air_v.z < -2.0 and b.air_v.y > 2.0, "and he's thrown away from it and up (%s m/s)" % str(b.air_v.snapped(Vector3.ONE * 0.1))])
	out.append([b.hp < 70.0 and b.alive, "hurt (hp %.0f) but alive" % b.hp])
	out.append([int(h.get("ignited", 0)) > 0 and b.burning(), "near enough to catch fire (%d cubes alight)" % int(h.get("ignited", 0))])
	# point blank
	var bp := _grunt(host, Vector3(4, 0, 0))
	made.append(bp)
	var hp0 := bp.trace(Vector3(4, 1.05, 1.0), Vector3(0, 0, -1), 2.0)
	var t0 := Time.get_ticks_usec()
	bl = blast([bp], (hp0.point as Vector3) + Vector3(0, 0, 0.04))
	var ms_pb := (Time.get_ticks_usec() - t0) / 1000.0
	h = _hit(bl, bp)
	var torn := []
	for sr in h.get("torn", []):
		torn.append_array(sr.parts)
	out.append([torn.has("head") and torn.has("arm_l") and torn.has("arm_r") and not bp.alive and int(h.res.get("cut", 0)) > 800,
		"point blank tears him apart: a crater (%d cubes) and %s off whole, dead (%.1f ms)" % [int(h.res.get("cut", 0)), ", ".join(torn), ms_pb]])
	# by the feet
	var bf := _grunt(host, Vector3(8, 0, 0))
	made.append(bf)
	bl = _blast_all([bf], Vector3(8.25, 0.05, 0.3))
	h = _hit(bl, bf)
	var fparts: Array = (h.res as Dictionary).get("parts", [])
	var legs := []
	for sr in h.get("torn", []):
		legs.append_array(sr.parts)
	out.append([(fparts.has("foot_l") or fparts.has("shin_l")) and bf.legs_lost() >= 1 and bf.air_v.y > 3.0,
		"on the floor by his feet: the foot dug out (%s), the leg off (%s), thrown up (%.1f m/s)" % [str(fparts), ", ".join(legs), bf.air_v.y]])
	# further off, out of reach
	var bm := _grunt(host, Vector3(12, 0, 0))
	var bo := _grunt(host, Vector3(16, 0, 0))
	made.append_array([bm, bo])
	bl = _blast_all([bm], Vector3(12, 1.0, 2.4))
	h = _hit(bl, bm)
	var cut_far := int((h.res as Dictionary).get("cut", 0))
	out.append([cut_far > 30 and cut_far < cut_near and bm.air_v.length() < 7.0 and bm.hp > 75.0,
		"2.2 m off: a smaller crater (%d cubes), a softer throw (%.1f m/s), less hurt (hp %.0f)" % [cut_far, bm.air_v.length(), bm.hp]])
	bl = _blast_all([bo], Vector3(16, 1.0, 3.5))
	out.append([(bl.hits as Array).is_empty() and bo.hp == 100.0 and not bo.airborne, "3.3 m off: untouched"])
	# a dead one lying there, a frozen one
	var bd := _grunt(host, Vector3(20, 0, 0))
	made.append(bd)
	bd.hurt(500.0)
	bd.dead_t = 2.0
	bd.animate(0.0, false)
	bl = _blast_all([bd], Vector3(20, 0.3, 1.2))
	h = _hit(bl, bd)
	out.append([not h.is_empty() and int((h.res as Dictionary).get("cut", 0)) > 30 and bd.airborne,
		"a dead one lying there is dug into and thrown too (%d cubes)" % int((h.get("res", {}) as Dictionary).get("cut", 0))])
	var bz := _grunt(host, Vector3(24, 0, 0))
	made.append(bz)
	bz.chill(1.0)
	bl = _blast_all([bz], Vector3(24, 1.0, 1.5))
	h = _hit(bl, bz)
	out.append([bz.frozen() == false and bz.cubes_left() == 0 and not bz.alive and bool(h.get("shattered", false)),
		"a frozen one shatters (%d cubes left)" % bz.cubes_left()])
	# six round one blast: the frame it goes off in (the nearest dug at once, the rest queued) and every crater
	var six := []
	for i in 6:
		var a := i * TAU / 6.0
		var dd := 0.9 + 0.3 * i
		six.append(_grunt(host, Vector3(30 + cos(a) * dd, 0, sin(a) * dd)))
	made.append_array(six)
	t0 = Time.get_ticks_usec()
	bl = blast(six, Vector3(30, 0.5, 0))
	var ms_blast := (Time.get_ticks_usec() - t0) / 1000.0
	var first := 0.0
	var most := 0.0
	var dug := 0
	var cubes := 0
	for job in bl.jobs:
		var r := dig(job)
		if not r.is_empty():
			dug += 1
			cubes += int(r.cut)
			most = maxf(most, float(r.ms))
			if dug == 1:
				first = float(r.ms)
	out.append([(bl.hits as Array).size() == 6 and dug == (bl.jobs as Array).size() and ms_blast + first < 20.0,
		"six caught in one blast: %.1f ms the frame it goes off (with the first queued crater, %.1f ms), %d more craters dug after (%d cubes, %.1f ms the dearest)" % [ms_blast + first, first, dug, cubes, most]])
	# a grenade at a grunt 5 m off: it goes off on him
	var bg := _grunt(host, Vector3(40, 0, 0))
	made.append(bg)
	var st := launch_state("grenade", Vector3(40, 1.2, 5.0), Vector3(0, SPEED * LOFT, -SPEED))
	var ev := {}
	for i in 60:
		ev = fly(st, 1.0 / 60.0, [bg], null, none)
		if not ev.is_empty():
			break
	out.append([String(ev.get("what", "")) == "impact" and ev.body == bg and float(st.t) < 0.5,
		"a grenade into a grunt goes off on him (%s at %.2f s, on the %s)" % [String(ev.get("what", "-")), float(st.t), String(ev.get("part", "-"))]])
	# straight at the top of his chest, where a thin ray slips in at the collar: they all go off on its front
	var slips := 0
	var thin := 0
	for iy in 4:
		for ix in 13:
			var o := Vector3(40.0 - 0.06 + 0.01 * ix, 1.22 + 0.02 * iy, 1.0)
			var th := bg.trace(o, Vector3(0, 0, -1), 2.0)
			if th.is_empty() or (th.point as Vector3).z < 0.1:
				thin += 1
			var sg := launch_state("grenade", o, Vector3(0, 0, -SPEED))
			var e2 := {}
			for j in 20:
				e2 = fly(sg, 1.0 / 60.0, [bg], null, none)
				if not e2.is_empty():
					break
			if String(e2.get("what", "")) != "impact" or (e2.at as Vector3).z < 0.1:
				slips += 1
	out.append([slips == 0 and thin > 0, "grenades at the top of his chest all go off on its front (%d of 52 slip in; a thin ray: %d)" % [slips, thin]])
	# a grenade at the floor: bounces, rolls, slows, never under the floor
	st = launch_state("grenade", Vector3(0, 1.2, 0), Vector3(0, SPEED * LOFT, -SPEED * 0.5))
	var bounces := 0
	var low := 9.0
	for i in int(FUSE * 60.0):
		ev = fly(st, 1.0 / 60.0, [], null, none)
		if String(ev.get("what", "")) == "bounce":
			bounces += 1
		low = minf(low, (st.p as Vector3).y)
	out.append([bounces >= 2 and String(st.mode) == "roll" and (st.v as Vector3).length() < 2.0 and low >= GREN_R - 0.001 and float(st.t) >= FUSE - 0.01,
		"a grenade on the floor bounces (%d), rolls and slows (%.1f m/s), stays on it, and is due to go off (%.1f s)" % [bounces, (st.v as Vector3).length(), float(st.t)]])
	# slowly into a grunt: bounces off
	var bs := _grunt(host, Vector3(44, 0, 0))
	made.append(bs)
	st = launch_state("grenade", Vector3(44, 1.0, 1.0), Vector3(0, 0, -4.0))
	ev = {}
	for i in 30:
		ev = fly(st, 1.0 / 60.0, [bs], null, none)
		if not ev.is_empty():
			break
	out.append([String(ev.get("what", "")) == "bounce" and ev.body == bs and (st.v as Vector3).z > 0.0,
		"a slow grenade bounces off a body (%s)" % String(ev.get("what", "-"))])
	# a sticky bomb on the chest, riding along as he moves
	var bc := _grunt(host, Vector3(48, 0, 0))
	made.append(bc)
	st = launch_state("sticky", Vector3(48, 1.1, 3.0), Vector3(0, 0, -STICKY_SPEED))
	ev = {}
	for i in 30:
		ev = fly(st, 1.0 / 60.0, [bc], null, none)
		if not ev.is_empty():
			break
	var at0: Vector3 = st.p
	bc.position += Vector3(1.0, 0, 0)
	bc.yaw = 0.5
	bc.animate(0.3, true)
	var rides := ride(st)
	var moved := (st.p as Vector3) - at0
	var hs := bc.trace((st.p as Vector3) + (st.n as Vector3) * 0.2, -(st.n as Vector3), 0.4)
	out.append([String(ev.get("what", "")) == "stick" and ev.body == bc and String(ev.part) == "torso",
		"a sticky bomb sticks to the chest (%s on the %s)" % [String(ev.get("what", "-")), String(ev.get("part", "-"))]])
	out.append([rides and moved.x > 0.7 and not hs.is_empty() and float(hs.dist) < 0.3,
		"and rides on it as he moves and turns (moved %s, on his side: %s)" % [str(moved.snapped(Vector3.ONE * 0.01)), str(not hs.is_empty())]])
	# on an arm: it drops when the arm comes off
	var ba := _grunt(host, Vector3(52, 0, 0))
	made.append(ba)
	st = launch_state("sticky", Vector3(52.5, 1.2, 3.0), Vector3(0, 0, -STICKY_SPEED))
	ev = {}
	for i in 30:
		ev = fly(st, 1.0 / 60.0, [ba], null, none)
		if not ev.is_empty():
			break
	var arm := String(ev.get("part", ""))
	var on_arm := ride(st)
	ba.sever("arm_l")
	out.append([arm.ends_with("_l") and on_arm and not ride(st), "one on an arm (the %s) lets go when the arm comes off" % arm])
	# into the floor
	st = launch_state("sticky", Vector3(56, 1.2, 0), Vector3(0, -6.0, -STICKY_SPEED * 0.5))
	ev = {}
	for i in 60:
		ev = fly(st, 1.0 / 60.0, [], null, none)
		if not ev.is_empty():
			break
	out.append([String(ev.get("on", "")) == "floor" and absf((st.p as Vector3).y) < 0.001 and (st.n as Vector3).y > 0.99,
		"one into the floor sticks there, face down (%s)" % str((st.p as Vector3).snapped(Vector3.ONE * 0.01))])
	# the weapon bar
	var w := VoxelWeaponGrenades.new()
	var full := w.bar_text()
	w.clip = 4
	w._proj = [{"kind": "sticky"}, {"kind": "sticky"}, {"kind": "grenade"}]
	var two := w.bar_text()
	w.free()
	out.append([full == "6/6" and two == "4/6 •2", "the weapon bar: rounds, and the sticky bombs out (%s, %s)" % [full, two]])
	for x in made:
		(x as Node).queue_free()
	VoxelBody.immortal = imm
	return out
