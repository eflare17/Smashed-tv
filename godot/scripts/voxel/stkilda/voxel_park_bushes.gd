class_name VoxelParkBushes
extends Node3D
## Bushes in the dirt along Luna Park's wall (the owner, 31 Oct: "cut a bush down and drag it over top of the hole ...
## then hide in the hole or hide in the bushes"), both sides of the wall (VoxelParkDirt's strip), every EVERY m or so.
## A melee weapon cuts one down (HITS blows: the chainsaw's quickest), and it tips over off its stump. E by a cut one
## and you drag it behind you (slower, DRAG_SLOW); E again and you let go. Let go of it while you're down a hole and
## it's pulled over the top of you. You're hidden (hidden()) standing in a bush that's still growing, or down a hole
## with a cut one lying over it; a cut one lying over a hole hides the hole (covered()). For the night guards to come
## (the next step: they don't see what's hidden). All grown back the next time you come (reset).

const EVERY := 6.0              # m between bushes along the strip, about
const OUT := 2.4                # m out from the wall's line
const HITS := 3                 # blows to cut one down
const HIT_GAP := 0.12           # s: one blow at most this often (the chainsaw strikes every frame)
const R := 0.7                  # m: a bush's size (round its middle, MID up)
const MID := 0.55
const GRAB := 1.8               # m: how near to take hold of a cut one
const BEHIND := 1.5             # m behind you, dragged
const DRAG_SLOW := 0.6
const HIDE_IN := 0.65           # m from a growing bush's middle you're in it
const COVER := 1.0              # m from a lying bush's middle a hole's covered
const DOWN := -0.9              # m: your feet lower than this, you're down a hole
const TIP_T := 0.5
const LIE_Y := 0.5              # m: a cut bush's middle off the ground, lying on its side
const LEAVES := [Color("#2f6a26"), Color("#3f7d2e"), Color("#4f9a38"), Color("#5aa844"), Color("#386f2a")]

var sk: VoxelStKilda
var list: Array = []            # {node, stump, base (where it grew), at (where it is now), yaw, hp, state: grow|tip|lie|drag, t, cool, tip_axis}
var dragging := -1
var _meshes: Array[ArrayMesh] = []
var _stump: ArrayMesh
var _hud: Label
# (The owner, 25 Nov: the browser game "was a bit laggy" on a phone.) A bush and its stump used to be a MeshInstance3D
# each, two hundred of them along the strip and two hundred draw calls; now the stumps are one batch and the bushes
# still growing are one batch a kind, four calls in all. Only a bush that's been cut down leaves its batch and gets
# its own node to tip, lie and be dragged on; and a bush standing still has its transform left alone, instead of
# being written every frame for a shiver that finished a quarter of a second after the blow.
var _stumps: MultiMeshInstance3D
var _batch: Array[MultiMeshInstance3D] = []
const SHIVER := 0.35            # s a blow's shiver lasts (after it, a growing bush isn't touched again)

func setup(s: VoxelStKilda, dirt: VoxelParkDirt) -> void:
	sk = s
	name = "ParkBushes"
	for k in 3:
		_meshes.append(_bush_mesh(k))
	_stump = _stump_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1888
	for c in dirt.cuts:
		var o: Vector2 = c[0]
		var d: Vector2 = c[1]
		var across := Vector2(-d.y, d.x)
		var length: float = c[2]
		for side in [-1.0, 1.0]:
			var along := rng.randf_range(1.5, EVERY)
			while along < length - 1.5:
				var p: Vector2 = o + d * along + across * side * (OUT + rng.randf_range(-0.25, 0.4))
				_add(Vector3(p.x, 0.0, p.y), rng.randf() * TAU, rng.randi() % _meshes.size(), rng.randf_range(0.85, 1.15))
				along += EVERY * rng.randf_range(0.7, 1.3)
	_batches()
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hud.offset_left = -200
	_hud.offset_right = 200
	_hud.offset_top = -150
	_hud.offset_bottom = -110
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color("#9fe08a"))
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.text = "HIDDEN"
	_hud.visible = false
	sk.arena._hud_layer.add_child(_hud)

func _add(at: Vector3, yaw: float, kind: int, size: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[kind]
	mi.material_override = SkModels.baked_material()
	mi.position = at
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * size
	mi.visible = false              # (while it's growing, its kind's batch draws it)
	add_child(mi)
	list.append({"node": mi, "base": at, "at": at, "yaw": yaw, "size": size, "hp": HITS, "state": "grow",
		"t": SHIVER, "cool": 0.0, "tip_axis": Vector3.RIGHT, "lie": Basis(), "kind": kind, "slot": -1})

## The stumps in one batch, and the bushes in one a kind (every bush has a place in its kind's batch for as long as
## it's growing; cut down, its place is collapsed to nothing and its own node takes over).
func _batches() -> void:
	_stumps = _mmi("Stumps", _stump, list.size())
	for i in list.size():
		_stumps.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(list[i].yaw)), list[i].base))
	for kind in _meshes.size():
		var mine := []
		for i in list.size():
			if int(list[i].kind) == kind:
				list[i].slot = mine.size()
				mine.append(i)
		_batch.append(_mmi("Bushes%d" % kind, _meshes[kind], mine.size()))
		for i in mine:
			_grow_xf(list[i])

func _mmi(nm: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = SkModels.baked_material()
	add_child(mmi)
	return mmi

## A growing bush's place in its batch, written (the shiver after a blow, and once as it settles).
func _grow_xf(b: Dictionary) -> void:
	var shake := maxf(0.0, 1.0 - float(b.t) * 4.0) * 0.12 * sin(float(b.t) * 60.0)
	_batch[int(b.kind)].multimesh.set_instance_transform(int(b.slot),
		Transform3D(Basis(Vector3.UP, float(b.yaw)).rotated(Vector3.RIGHT, shake).scaled(Vector3.ONE * float(b.size)), b.at))

## In its batch (growing) or out of it (cut down: its place drawn as nothing, its own node shown instead).
func _in_batch(b: Dictionary, on: bool) -> void:
	(b.node as MeshInstance3D).visible = not on
	if on:
		_grow_xf(b)
	else:
		_batch[int(b.kind)].multimesh.set_instance_transform(int(b.slot), Transform3D(Basis().scaled(Vector3.ZERO), b.base))

## A cut bush lying on its side, its middle LIE_Y over at (b.at: where its middle is, on the ground).
func _lie_xf(b: Dictionary) -> Transform3D:
	var bs: Basis = (b.lie as Basis).scaled(Vector3.ONE * float(b.size))
	return Transform3D(bs, (b.at as Vector3) + Vector3(0, LIE_Y, 0) - bs * Vector3(0, MID, 0))

# a bush: a mound of leafy blocks, its middle MID up (a different one each kind)
static func _bush_mesh(kind: int) -> ArrayMesh:
	var h := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + kind * 17
	var b := 0.26
	for y in 5:
		for z in range(-3, 4):
			for x in range(-3, 4):
				var p := Vector3(x * b, 0.12 + y * b * 0.9, z * b)
				var d := Vector3(p.x, (p.y - MID) * 1.35, p.z).length()
				if d > R * rng.randf_range(0.8, 1.05):
					continue
				var s := b * rng.randf_range(1.0, 1.3)
				var cube := SkModels.box(h, Vector3(s, s, s), p + Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.04, 0.04)), LEAVES[rng.randi() % LEAVES.size()])
				cube.rotation.y = rng.randf_range(-0.3, 0.3)
	var mesh := SkModels.bake(h)
	h.free()
	return mesh

static func _stump_mesh() -> ArrayMesh:
	var h := Node3D.new()
	SkModels.box(h, Vector3(0.16, 0.18, 0.16), Vector3(0, 0.09, 0), Color("#5a3d24"))
	SkModels.box(h, Vector3(0.1, 0.12, 0.1), Vector3(0.12, 0.06, 0.05), Color("#6b4a2c"))
	var mesh := SkModels.bake(h)
	h.free()
	return mesh

## Put back as it was: all growing again.
func reset() -> void:
	dragging = -1
	sk.arena.speed_k = 1.0
	for b in list:
		b.state = "grow"
		b.hp = HITS
		b.at = b.base
		b.t = SHIVER
		var mi: MeshInstance3D = b.node
		mi.transform = Transform3D(Basis(Vector3.UP, b.yaw).scaled(Vector3.ONE * float(b.size)), b.base)
		_in_batch(b, true)

# ---------------------------------------------------------------- cutting one down (the melee weapons: VoxelMelee.wall_strike)

## A blow from `from` along dir, reach m: the nearest growing bush it meets takes it. True if it hit one.
func strike(from: Vector3, dir: Vector3, reach: float) -> bool:
	var best := -1
	var best_t := reach + R
	for i in list.size():
		var b: Dictionary = list[i]
		if b.state != "grow":
			continue
		var c: Vector3 = (b.at as Vector3) + Vector3(0, MID, 0)
		var t := (c - from).dot(dir)
		if t < 0.0 or t > best_t:
			continue
		if (from + dir * t).distance_to(c) <= R * float(b.size):
			best = i
			best_t = t
	if best < 0:
		return false
	var b: Dictionary = list[best]
	if b.cool > 0.0:
		return true
	b.cool = HIT_GAP
	b.hp -= 1
	var c: Vector3 = (b.at as Vector3) + Vector3(0, MID, 0)
	var bits := []
	for k in 8:
		bits.append({"pos": c + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.4), randf_range(-0.4, 0.4)), "col": LEAVES[k % LEAVES.size()]})
	sk.arena.debris.burst(bits, Vector3(dir.x, 0.3, dir.z).normalized(), 2.0)
	sk.arena.sound.play("crunch_%d" % (randi() % 2), c, -6.0, randf_range(1.3, 1.6))
	b.t = 0.0
	if b.hp <= 0:
		b.state = "tip"
		var flat := Vector3(dir.x, 0, dir.z)
		b.tip_axis = (flat.cross(Vector3.DOWN) if flat.length() > 0.01 else Vector3.RIGHT).normalized()
		_in_batch(b, false)         # (out of its kind's batch: its own node tips it over)
		sk.arena.say("Cut down: E to drag it", 1.5)
	else:
		_grow_xf(b)
	return true

# ---------------------------------------------------------------- dragging, hiding

func _process(dt: float) -> void:
	var player := sk.arena.player
	var pp := player.global_position
	for i in list.size():
		var b: Dictionary = list[i]
		b.cool = maxf(0.0, float(b.cool) - dt)
		var mi: MeshInstance3D = b.node
		var sz := Vector3.ONE * float(b.size)
		match String(b.state):
			"grow":
				if b.t < SHIVER:               # (just hit: a shiver; after it, it stands still and isn't touched again)
					b.t += dt
					_grow_xf(b)
			"tip":
				# over off its stump, round its foot, coming to lie on its side
				b.t += dt
				var k := smoothstep(0.0, 1.0, minf(float(b.t) / TIP_T, 1.0))
				var end := (Basis(b.tip_axis, 1.45) * Basis(Vector3.UP, float(b.yaw))).scaled(sz)
				var lift := LIE_Y - (end * Vector3(0, MID, 0)).y
				mi.transform = Transform3D((Basis(b.tip_axis, k * 1.45) * Basis(Vector3.UP, float(b.yaw))).scaled(sz), (b.base as Vector3) + Vector3(0, k * lift, 0))
				if b.t >= TIP_T:
					b.state = "lie"
					b.lie = Basis(b.tip_axis, 1.45) * Basis(Vector3.UP, float(b.yaw))
					var mid := (b.base as Vector3) + end * Vector3(0, MID, 0)
					b.at = Vector3(mid.x, 0.0, mid.z)
					mi.transform = _lie_xf(b)
			"drag":
				var f := Vector3(-sin(sk.arena.look_yaw), 0, -cos(sk.arena.look_yaw))
				var want := Vector3(pp.x, 0.0, pp.z) - f * BEHIND
				var at: Vector3 = (b.at as Vector3).lerp(want, minf(1.0, dt * 6.0))
				at.y = 0.0
				b.at = at
				var to := Vector3(pp.x - at.x, 0, pp.z - at.z)
				if to.length() > 0.1:
					b.yaw = atan2(-to.x, -to.z)
				b.lie = Basis(Vector3.UP, float(b.yaw)) * Basis(Vector3.RIGHT, -1.45)
				mi.transform = _lie_xf(b)
			"lie":
				pass
	# what E does here
	if sk.riding() or sk.near_ride:
		_hud.visible = false
		return
	if dragging >= 0:
		sk.arena._use_label.text = "E  let go of the bush" + ("  (over you)" if pp.y < DOWN else "")
	else:
		var near := _near_cut(pp)
		if near >= 0:
			sk.arena._use_label.text = "E  drag the bush"
	_hud.visible = hidden()

func _near_cut(p: Vector3) -> int:
	var best := -1
	var best_d := GRAB
	for i in list.size():
		var b: Dictionary = list[i]
		if b.state != "lie":
			continue
		var d := Vector2(p.x - b.at.x, p.z - b.at.z).length()
		if d < best_d:
			best = i
			best_d = d
	return best

func _unhandled_input(e: InputEvent) -> void:
	if not sk.active or sk.arena.phone.is_open() or sk.riding() or sk.near_ride:
		return
	if not (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_E):
		return
	var pp := sk.arena.player.global_position
	if dragging >= 0:
		let_go()
	else:
		var i := _near_cut(pp)
		if i < 0:
			return
		dragging = i
		list[i].state = "drag"
		sk.arena.speed_k = DRAG_SLOW
		sk.arena.sound.play("bag_drop", pp, -8.0, 0.7)
	get_viewport().set_input_as_handled()

## Let go of the bush you're dragging (down a hole: it's pulled over the top of you).
func let_go() -> void:
	if dragging < 0:
		return
	var b: Dictionary = list[dragging]
	var pp := sk.arena.player.global_position
	b.state = "lie"
	if pp.y < DOWN:
		b.at = Vector3(pp.x, 0.0, pp.z)
		(b.node as MeshInstance3D).transform = _lie_xf(b)
	dragging = -1
	sk.arena.speed_k = 1.0
	sk.arena.sound.play("bag_drop", pp, -6.0, 0.8)

## Is a hole at p hidden by a cut bush lying over it?
func covered(p: Vector3) -> bool:
	for b in list:
		if b.state == "lie" and Vector2(p.x - b.at.x, p.z - b.at.z).length() <= COVER:
			return true
	return false

## Are you hidden: in a growing bush, or down a hole with a cut one over it?
func hidden() -> bool:
	var p := sk.arena.player.global_position
	if p.y < DOWN and covered(p):
		return true
	for b in list:
		if b.state == "grow" and p.y > DOWN and Vector2(p.x - b.at.x, p.z - b.at.z).length() <= HIDE_IN * float(b.size):
			return true
	return false
