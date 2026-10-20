class_name VoxelGunPistol
extends VoxelGun
## The pistol (the game's block blaster): twelve rounds a clip. Left click fires one (held: one every SHOT_T); each shot
## kicks the aim wider (bloom) for a moment, so a held trigger sprays and tapped shots land true. Right click aims in:
## the view closes in, the shots go tight and dig a little deeper. R (or a click on empty) swaps the magazine: the old
## one drops out of the grip and a fresh one goes in. The game's own pistol sounds. Owned by the voxel session.

const SHOT_T := 0.16            # seconds between shots held
const HOLE := 2.2               # the hole's radius, cubes
const HOLE_AIMED := 2.5
const SPREAD := 0.7             # degrees, from the hip ...
const SPREAD_AIMED := 0.12      # ... aimed in
const BLOOM := 0.45             # degrees more per shot, fading at BLOOM_FADE a second
const BLOOM_FADE := 3.0

var _bloom := 0.0
var _mag: MeshInstance3D        # the magazine (drops out on a reload)

func _init() -> void:
	vox = "blaster"
	vox_scale = 0.0055
	rest = Vector3(0.2, -0.2, -0.42)
	aimed_at = Vector3(0.0, -0.13, -0.34)
	clip = 12
	clip_max = 12
	reload_total = 1.2
	_cd_total = SHOT_T

func _gun_build() -> void:
	_mag = box(_model, Vector3(0.03, 0.08, 0.04), Vector3(0, -0.06, 0.02), mat(Color(0.12, 0.12, 0.14), 0.5, 0.5))

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_try_fire()

func hold(button: int, _dt: float) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_try_fire()
	elif button == MOUSE_BUTTON_RIGHT and not top_down():
		arena._aiming = true

func release(button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		arena._aiming = false

func _try_fire() -> void:
	if _cd > 0.0:
		return
	if reload_t > 0.0:
		return
	if clip <= 0:
		sfx("dry_fire")
		_cd = 0.25
		start_reload()
		return
	var a := aim()
	if a.is_empty():
		return
	var aimed := _aim_k > 0.6
	var spread := (SPREAD_AIMED if aimed else SPREAD) + _bloom
	arena.fire(a[0], a[1], 1, spread, HOLE_AIMED if aimed else HOLE, {"muzzle": a[2]})
	clip -= 1
	_cd = SHOT_T
	_bloom = minf(_bloom + BLOOM, 3.0)
	shot_fx(a[2], 0.8)
	sfx("game:pistol", Vector3.INF, -2.0)
	if clip == 0:
		start_reload()

func step(dt: float) -> void:
	_bloom = maxf(0.0, _bloom - BLOOM_FADE * dt)
	super.step(dt)

func _reload_began() -> void:
	sfx("mag_out")

func _reloading(from: float, to: float) -> void:
	var k0 := 1.0 - from / reload_total
	var k1 := 1.0 - to / reload_total
	if k0 < 0.7 and k1 >= 0.7:
		sfx("mag_in")
	# the magazine: drops out, gone, a fresh one pushed up in
	var m := 0.0
	if k1 < 0.25:
		m = k1 / 0.25 * 0.25
	elif k1 < 0.55:
		m = 0.25 + (k1 - 0.25) * 2.0
	else:
		m = maxf(0.0, (0.85 - k1) / 0.3) * 0.25
	_mag.position = Vector3(0, -0.06 - m, 0.02)
	_mag.visible = not (k1 > 0.3 and k1 < 0.55)

func _reload_done() -> void:
	super._reload_done()
	_mag.position = Vector3(0, -0.06, 0.02)
	_mag.visible = true

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.55, col.g * 0.55, col.b * 0.6, col.a)
	for b in [[Rect2(2, 1.2, 5.5, 1.6), col], [Rect2(7.5, 1.6, 1.8, 0.8), col], [Rect2(2.6, 2.8, 1.3, 1.8), dim],
			[Rect2(4.0, 1.5, 1.0, 0.5), Color(0.4, 0.9, 1.0, col.a)]]:
		ci.draw_rect(Rect2(r.position + (b[0] as Rect2).position * u, (b[0] as Rect2).size * u), b[1])
