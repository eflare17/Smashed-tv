extends Node3D
## Smash arcade: prizes, the game-show loot. Cash, gold bars, toasters, VCRs and the odd new car pop out of kills
## (and the boss), bounce, spin, and fly to the player once you're close; each is worth score. Pooled (packed
## arrays, swap-remove) with a MultiMesh per kind, plus a few floating "+$1000" labels (fixed pool) when you grab
## one. They last LIFE seconds and blink before they go.

const SmashVox := preload("smash_vox.gd")

const MAX := 64
const CASH := 0
const GOLD := 1
const TOASTER := 2
const VCR := 3
const CAR := 4
const NAMES := ["CASH", "GOLD BAR", "TOASTER", "VCR", "NEW CAR"]
const VALUES := [1000, 2500, 5000, 7500, 25000]
const LIFE := 10.0
const REACH := 0.8
const MAGNET := 2.5
const GRAVITY := 18.0
const POPS := 8
const POP_LIFE := 0.9

var half := 10.0

var count := 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var kind := PackedByteArray()
var age := PackedFloat32Array()

var _mm: Array[MultiMesh] = []
var _bufs: Array[PackedFloat32Array] = []
var _pops: Array[Label3D] = []
var _pop_t := PackedFloat32Array()
var _next_pop := 0

func _init() -> void:
	name = "SmashPrizes"
	pos.resize(MAX)
	vel.resize(MAX)
	kind.resize(MAX)
	age.resize(MAX)
	var mat := SmashVox.flat_material()
	for k in NAMES.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = SmashVox.prize_mesh(k)
		mm.mesh.surface_set_material(0, mat)
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 8, 40))
		add_child(mi)
		_mm.append(mm)
		var buf := PackedFloat32Array()
		buf.resize(MAX * 12)
		_bufs.append(buf)
	_pop_t.resize(POPS)
	for i in POPS:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 56
		l.outline_size = 12
		l.pixel_size = 0.012
		l.modulate = SmashVox.GOLD_LIGHT
		l.visible = false
		add_child(l)
		_pops.append(l)

func clear() -> void:
	count = 0
	for l in _pops:
		l.visible = false
	_pop_t.fill(0.0)

func set_label_size(pixel: float) -> void:
	for l in _pops:
		l.pixel_size = pixel

func spawn(p: Vector2, k: int) -> void:
	if count >= MAX:
		return
	var a := randf() * TAU
	var out := Vector2(cos(a), sin(a)) * randf_range(1.0, 3.0)
	pos[count] = Vector3(p.x, 0.6, p.y)
	vel[count] = Vector3(out.x, randf_range(4.0, 6.5), out.y)
	kind[count] = k
	age[count] = 0.0
	count += 1

func _remove(i: int) -> void:
	count -= 1
	pos[i] = pos[count]
	vel[i] = vel[count]
	kind[i] = kind[count]
	age[i] = age[count]

## Moves them; returns the kinds the player picked up this frame.
func step(delta: float, player: Vector2, alive: bool) -> PackedInt32Array:
	var got := PackedInt32Array()
	var lim := half - 0.4
	var i := 0
	while i < count:
		age[i] += delta
		if age[i] >= LIFE:
			_remove(i)
			continue
		var p := pos[i]
		var v := vel[i]
		var flat := Vector2(p.x, p.z)
		var to := player - flat
		var d := to.length()
		if alive and d < MAGNET and age[i] > 0.4:
			flat += to / maxf(d, 0.001) * minf(d, 9.0 * delta)
			p = Vector3(flat.x, lerpf(p.y, 0.5, minf(1.0, delta * 8.0)), flat.y)
			v = Vector3.ZERO
		else:
			v.y -= GRAVITY * delta
			p += v * delta
			if p.y < 0.15:
				p.y = 0.15
				v = Vector3(v.x * 0.5, -v.y * 0.4, v.z * 0.5)
				if absf(v.y) < 1.0:
					v = Vector3.ZERO
			p.x = clampf(p.x, -lim, lim)
			p.z = clampf(p.z, -lim, lim)
		if alive and Vector2(p.x, p.z).distance_to(player) < REACH and age[i] > 0.4:
			got.append(kind[i])
			_pop(p, "+$%d" % VALUES[kind[i]])
			_remove(i)
			continue
		pos[i] = p
		vel[i] = v
		i += 1
	for k in POPS:
		if _pop_t[k] > 0.0:
			_pop_t[k] -= delta
			var l := _pops[k]
			l.position.y += delta * 1.5
			l.modulate.a = clampf(_pop_t[k] / POP_LIFE * 1.5, 0.0, 1.0)
			l.visible = _pop_t[k] > 0.0
	return got

func _pop(p: Vector3, text: String) -> void:
	var l := _pops[_next_pop]
	_pop_t[_next_pop] = POP_LIFE
	_next_pop = (_next_pop + 1) % POPS
	l.text = text
	l.position = p + Vector3(0, 0.8, 0)
	l.modulate.a = 1.0
	l.visible = true

func draw() -> void:
	# one pass per kind, so each kind's buffer is copied out and back once
	for k in NAMES.size():
		var b := _bufs[k]
		var n := 0
		for i in count:
			# blink for the last two seconds
			if kind[i] != k or (age[i] > LIFE - 2.0 and int(age[i] * 8.0) % 2 == 1):
				continue
			var p := pos[i]
			var a := age[i] * 3.0
			var cs := cos(a)
			var sn := sin(a)
			var o := n * 12
			n += 1
			b[o] = cs; b[o + 1] = 0.0; b[o + 2] = sn; b[o + 3] = p.x
			b[o + 4] = 0.0; b[o + 5] = 1.0; b[o + 6] = 0.0; b[o + 7] = p.y
			b[o + 8] = -sn; b[o + 9] = 0.0; b[o + 10] = cs; b[o + 11] = p.z
		_bufs[k] = b
		_mm[k].buffer = b
		_mm[k].visible_instance_count = n
