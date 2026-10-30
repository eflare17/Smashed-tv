class_name VoxelGunShotgun
extends VoxelGun
## The shotgun (the game's block pump gun): six shells in the tube. Left click fires nine pellets and pumps (the grip
## racks back and forward, a red shell flies out); the holes are big up close and smaller further off, and a body hit
## hard at point blank is thrown back off its feet. Right click fires both barrels' worth: two shells, eighteen pellets,
## a wider spread and a big kick; at point blank it blows a whole chunk out of them (a carved ball, pieces flying) and
## throws them across the room. R (or firing empty) loads shell by shell; a click with one in fires, stopping the
## reload. Owned by the voxel session.

const PELLETS := 9
const SPREAD := 4.5
const HOLE := 1.7               # a pellet's hole at point blank, cubes ...
const FALLOFF := 11.0           # ... half that this many metres off
const PUMP_T := 0.55
const DOUBLE_PELLETS := 18
const WALL := 0.15              # what a pellet takes from a St Kilda wall's block (VoxelBreakables.WALL_HP: 1)
const DOUBLE_SPREAD := 6.5
const DOUBLE_PUMP_T := 0.95
const SHELL_T := 0.42           # seconds a shell takes to load
const CLOSE := 2.6              # metres: point blank
const KNOCK := 6.0              # m/s a point-blank blast throws them
const CHUNK_R := 0.16           # metres: the chunk both barrels blow out at point blank

var _pump: MeshInstance3D
var _pump_t := 0.0              # seconds into a pump (0: none)
var _pump_total := PUMP_T
var _shell_t := 0.0             # seconds into loading the next shell

func _init() -> void:
	vox = "shotgun"
	vox_scale = 0.0046
	rest = Vector3(0.2, -0.24, -0.36)
	aimed_at = Vector3(0.08, -0.2, -0.32)
	shell_size = Vector3(0.016, 0.016, 0.045)
	shell_col = Color(0.75, 0.12, 0.1)
	clip = 6
	clip_max = 6
	reload_total = SHELL_T * 6.0
	_cd_total = PUMP_T

func _gun_build() -> void:
	_pump = box(_model, Vector3(0.045, 0.04, 0.12), Vector3(0, 0.03, -0.2), mat(Color(0.35, 0.22, 0.12)))

func bar_text() -> String:
	return "%d/%d" % [clip, clip_max]

func press(button: int) -> void:
	if _pump_t > 0.0:
		return
	if clip <= 0:
		sfx("dry_fire")
		start_reload()
		return
	var a := aim()
	if a.is_empty():
		return
	reload_t = 0.0                 # a shot stops the loading
	_shell_t = 0.0
	if button == MOUSE_BUTTON_RIGHT and clip >= 2:
		_blast(a, DOUBLE_PELLETS, DOUBLE_SPREAD, true)
		clip -= 2
		_pump_total = DOUBLE_PUMP_T
		shot_fx(a[2], 1.6, 0)
		sfx("shotgun_double")
	else:
		_blast(a, PELLETS, SPREAD, false)
		clip -= 1
		_pump_total = PUMP_T
		shot_fx(a[2], 1.1, 0)
		sfx("shotgun_shot")
	_pump_t = 0.001
	_cd = _pump_total
	_cd_total = _pump_total
	if top_down():
		shooter.avatar.attack = 0.2

# the pellets, then what a close blast does to whoever took it
func _blast(a: Array, pellets: int, spread: float, both: bool) -> void:
	var hits: Array = arena.fire(a[0], a[1], pellets, spread, HOLE, {"muzzle": a[2], "falloff": FALLOFF, "wall": WALL})
	var by := {}
	for h in hits:
		var b: VoxelBody = h.body
		if not is_instance_valid(b):
			continue
		if not by.has(b):
			by[b] = []
		by[b].append(h)
	for b in by:
		var hs: Array = by[b]
		var near: float = hs.map(func(x): return float(x.dist)).min()
		if near > CLOSE or hs.size() < 3:
			continue
		var d: Vector3 = (a[1] as Vector3)
		if both:
			# a whole chunk blown out of them where the most pellets went in
			var at: Vector3 = hs[0].point + d * CHUNK_R * 0.6
			var r: Dictionary = b.carve(at, at, CHUNK_R, 0.06, 2)
			spray(r, d, 4.0)
			fling(b, r, d * 6.0 + Vector3.UP * 2.0, Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
			hit_stop(0.08, 0.05)
		var k := KNOCK * (1.4 if both else 1.0) * (1.0 - near / CLOSE * 0.5)
		b.launch(Vector3(d.x, 0, d.z).normalized() * k + Vector3.UP * k * 0.45, 5.0)

func step(dt: float) -> void:
	if _pump_t > 0.0:
		var before := _pump_t
		_pump_t += dt
		if before < _pump_total * 0.3 and _pump_t >= _pump_total * 0.3 and is_out():
			sfx("shotgun_pump")
			eject()
		if _pump_t >= _pump_total:
			_pump_t = 0.0
			if clip == 0:
				start_reload()
	# shell by shell (reload_t kept to what's left, so the base's countdown can't cut the last one short)
	if reload_t > 0.0:
		_shell_t += dt
		if _shell_t >= SHELL_T:
			_shell_t = 0.0
			clip += 1
			if is_out():
				sfx("shell_in")
		reload_t = 0.0 if clip >= clip_max else SHELL_T * (clip_max - clip) - _shell_t + dt
	super.step(dt)

func start_reload() -> void:
	if reload_t > 0.0 or clip >= clip_max:
		return
	reload_t = SHELL_T * (clip_max - clip)
	reload_total = reload_t
	_shell_t = 0.0

func _reload_done() -> void:
	pass                            # (the shells went in one by one)

func _pose() -> void:
	super._pose()
	# the pump: back and forward
	var k := 0.0
	if _pump_t > 0.0:
		var f := _pump_t / _pump_total
		k = sin(clampf((f - 0.15) / 0.6, 0.0, 1.0) * PI)
	_pump.position = Vector3(0, 0.03, -0.2 + 0.07 * k)

func _reload_pose() -> Array:
	if reload_t <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	# turned on its side, loading the tube from below; a little push with each shell
	var push := sin(clampf(_shell_t / SHELL_T, 0.0, 1.0) * PI)
	return [Vector3(-0.03, -0.05 + 0.015 * push, 0.03), Vector3(-0.25, 0.25, 0.7)]

func cooling() -> float:
	if reload_t > 0.0:
		return clampf(float(clip_max - clip) / float(clip_max), 0.0, 1.0)
	return clampf(_cd / maxf(_cd_total, 0.001), 0.0, 1.0)

func hand_pose() -> String:
	return "shotgun"

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.55, col.g * 0.55, col.b * 0.6, col.a)
	for b in [[Rect2(0.2, 2.0, 2.4, 1.4), dim], [Rect2(2.6, 1.7, 2.4, 1.2), col], [Rect2(5.0, 1.75, 4.8, 0.55), col],
			[Rect2(5.0, 2.35, 4.4, 0.45), dim]]:
		ci.draw_rect(Rect2(r.position + (b[0] as Rect2).position * u, (b[0] as Rect2).size * u), b[1])
