class_name VoxelGun
extends VoxelMelee
## What the guns share (the owner, 20 Oct: "the pistol and shotgun need some work"): the game's own block gun in your
## hands, a clip or tube that runs out (R reloads; firing empty reloads too), a flash and a light at the muzzle with the
## tracer starting there, the kick, spent shells flying out of the side and lying where they land, the sounds. The
## shots go through VoxelArena.fire (traced into the bodies, holes knocked out). Subclasses (voxel_gun_pistol.gd,
## voxel_gun_shotgun.gd) say how each fires and reloads. Owned by the voxel session.

const MAX_SHELLS := 160         # spent shells lying about (the oldest go)

var vox := "blaster"            # the .vox gun shown
var vox_scale := 0.0055         # metres a voxel of it, first person
var rest := Vector3(0.2, -0.2, -0.42)    # where it's held, camera space
var aimed_at := Vector3(0.0, -0.12, -0.34)
var shell_size := Vector3(0.011, 0.011, 0.028)
var shell_col := Color(0.86, 0.66, 0.25)
var clip := 12
var clip_max := 12
var reload_t := 0.0             # seconds left of a reload (0: none)
var reload_total := 1.0
var _cd := 0.0                  # seconds till it can fire again
var _cd_total := 0.1
var _kick := 0.0                # 1 just fired, falling back to 0
var _aim_k := 0.0
var _model: Node3D              # the gun, under view (moved for kick, aim, reload)
var _muzzle := Vector3.ZERO     # the barrel's end, in _model's space
var _flash: MeshInstance3D
var _light: OmniLight3D
var _flash_t := 0.0
var _shells: MultiMeshInstance3D
var _sp := PackedVector3Array()  # shells: position, velocity, spin axis*speed, turned so far
var _sv := PackedVector3Array()
var _sw := PackedVector3Array()
var _sb: Array[Basis] = []
var _s_rest := PackedByteArray()
var _sn := 0
var _s_next := 0

func _build() -> void:
	_model = Node3D.new()
	view.add_child(_model)
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = VoxelArena._gun_mesh(vox, vox_scale)
	mi.mesh = mesh
	mi.material_override = arena._mat
	mi.rotation = Vector3(0, PI, 0)               # the .vox barrel is +z; the camera looks down -z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mi)
	# the muzzle: the barrel's far end, a little above the grip's line
	var bb := mesh.get_aabb()
	_muzzle = Vector3(-(bb.position.x + bb.size.x * 0.5), bb.position.y + bb.size.y * 0.72, -(bb.position.z + bb.size.z))
	_flash = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.07, 0.07, 0.11)
	_flash.mesh = fm
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(1.0, 0.85, 0.4)
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash.material_override = mat2
	_flash.position = _muzzle + Vector3(0, 0, -0.05)
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(_flash)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.4)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.top_level = true
	add_child(_light)
	_model.position = rest
	# spent shells: one draw call, lying where they land
	_shells = MultiMeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = shell_size
	var smat := StandardMaterial3D.new()
	smat.albedo_color = shell_col
	smat.metallic = 0.7
	smat.roughness = 0.35
	sm.material = smat
	_shells.multimesh = MultiMesh.new()
	_shells.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_shells.multimesh.mesh = sm
	_shells.multimesh.instance_count = MAX_SHELLS
	_shells.multimesh.visible_instance_count = 0
	_shells.top_level = true
	add_child(_shells)
	_sp.resize(MAX_SHELLS)
	_sv.resize(MAX_SHELLS)
	_sw.resize(MAX_SHELLS)
	_sb.resize(MAX_SHELLS)
	_s_rest.resize(MAX_SHELLS)
	_gun_build()

## For a subclass: anything more on the gun (a magazine, a pump grip).
func _gun_build() -> void:
	pass

func cooling() -> float:
	if reload_t > 0.0:
		return clampf(reload_t / reload_total, 0.0, 1.0)
	return clampf(_cd / maxf(_cd_total, 0.001), 0.0, 1.0)

func bar_text() -> String:
	return "%d/%d" % [clip, clip_max]

func busy() -> bool:
	return false

func reload_key() -> void:
	start_reload()

## Starts reloading (if it isn't full or already at it).
func start_reload() -> void:
	if reload_t > 0.0 or clip >= clip_max:
		return
	reload_t = reload_total
	_reload_began()

func _reload_began() -> void:
	pass

func on_deselect() -> void:
	shooter.aiming = false

## Where a shot comes from and goes: [from (the eye, or Jared's chest), dir, muzzle (world)]; [] if nowhere to aim.
func aim() -> Array:
	var a: Array = shooter.aim()
	if a.is_empty():
		return []
	var mz: Vector3 = a[0] + (a[1] as Vector3) * 0.5
	if not top_down():
		mz = _model.global_transform * _muzzle
	return [a[0], a[1], mz]

## The flash, the light, the kick (k: how hard), a shell out of the side (n of them).
func shot_fx(muzzle: Vector3, k: float = 1.0, shells: int = 1) -> void:
	_flash_t = 0.05
	_light.global_position = muzzle
	_kick = minf(1.6, _kick + k)
	shooter.kick = maxf(float(shooter.kick), 0.6 * k)
	shooter.avatar.recoil = 1.0
	for i in shells:
		eject()

## A spent shell thrown out of the ejection port (the gun's right side), up and back.
func eject() -> void:
	var fr := frame()
	var from: Vector3 = (_model.global_transform * (_muzzle * 0.35)) if not top_down() else shooter.player.global_position + Vector3(0, 1.1, 0)
	var i := _s_next
	_s_next = (_s_next + 1) % MAX_SHELLS
	_sn = mini(_sn + 1, MAX_SHELLS)
	_sp[i] = from + fr.x * 0.04
	_sv[i] = fr.x * randf_range(1.6, 2.4) + fr.y * randf_range(1.2, 2.0) + fr.z * randf_range(0.2, 0.6)
	_sw[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(12.0, 25.0)
	_sb[i] = Basis.looking_at(fr.x, Vector3.UP)
	_s_rest[i] = 0

func step(dt: float) -> void:
	_cd = maxf(0.0, _cd - dt)
	_kick = maxf(0.0, _kick - dt * 6.0)
	_flash_t = maxf(0.0, _flash_t - dt)
	_flash.visible = _flash_t > 0.0
	_flash.rotation.z = randf() * TAU
	_light.light_energy = 3.0 * _flash_t / 0.05
	if reload_t > 0.0:
		var before := reload_t
		reload_t = maxf(0.0, reload_t - dt)
		_reloading(before, reload_t)
		if reload_t <= 0.0:
			_reload_done()
	var aiming: bool = shooter.aiming and shooter.weapon == weapon_id
	_aim_k = move_toward(_aim_k, 1.0 if aiming else 0.0, dt * 6.0)
	_pose()
	_shells_step(dt)

## The one out (a holstered gun goes on reloading and pumping, unheard and unseen).
func is_out() -> bool:
	return shooter.weapon == weapon_id

## For a subclass: the reload going on (from: seconds left before this frame, to: after), and done.
func _reloading(_from: float, _to: float) -> void:
	pass

func _reload_done() -> void:
	clip = clip_max

## The gun in hand: held, aimed in, kicking, lowered and turned while reloading (_reload_pose).
func _pose() -> void:
	var at := rest.lerp(aimed_at, _aim_k)
	var rot := Vector3(0.18 * _kick, 0, 0)
	var rp := _reload_pose()
	_model.position = at + Vector3(0, 0.0, 0.06 * _kick) + rp[0]
	_model.rotation = rot + rp[1]

## For a subclass: [offset, turn] while reloading.
func _reload_pose() -> Array:
	if reload_t <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var k := sin(clampf(1.0 - reload_t / reload_total, 0.0, 1.0) * PI)
	return [Vector3(-0.04, -0.08, 0.04) * k, Vector3(-0.5, 0.35, 0.2) * k]

func _shells_step(dt: float) -> void:
	if _sn == 0:
		return
	var mm := _shells.multimesh
	for i in _sn:
		if _s_rest[i] == 1:
			continue
		var v := _sv[i]
		v.y -= 9.8 * dt
		var p := _sp[i] + v * dt
		var w := _sw[i]
		if p.y < shell_size.x * 0.5:
			p.y = shell_size.x * 0.5
			if absf(v.y) > 0.6:
				sfx("shell_drop", p, -8.0)
			v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)
			w *= 0.5
			if v.length() < 0.25:
				# lying on its side, turned any way
				_s_rest[i] = 1
				_sb[i] = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI / 2.0)
				mm.set_instance_transform(i, Transform3D(_sb[i], Vector3(p.x, shell_size.x * 0.5, p.z)))
				continue
		if w.length() > 0.001:
			_sb[i] = Basis(w.normalized(), w.length() * dt) * _sb[i]
		_sv[i] = v
		_sp[i] = p
		_sw[i] = w
		mm.set_instance_transform(i, Transform3D(_sb[i], p))
	mm.visible_instance_count = _sn

func hand_mesh() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelArena._gun_mesh(vox, shooter.avatar.model.voxel_m)
	mi.material_override = arena._mat
	return mi

func hand_pose() -> String:
	return "spud"
