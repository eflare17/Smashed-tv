class_name VoxelDemolitionProps
extends Node3D
## Demolition's chain-reaction props (phase B): the petrol station's pumps under its canopy, gas bottles stacked against
## the walls, and a fuel tanker parked in the street. Shoot one (or put the wrecking ball through it, or a grenade near
## it) and it goes up: VoxelBreakables.blast takes a real bite out of whatever is beside it, the arena's debris throws
## fire and smoke, everything near is hurt and thrown -- and every other prop within `reach` is lit with a short fuse,
## so a shot at the tanker runs down the pumps and the bottles a beat at a time.
##
## It can't run away with itself: a prop goes off once (`gone`), no more than AT_ONCE in a frame and never closer
## together than GAP, so the whole eleven of them lit at once is a run of bangs a frame apart, not one frame's worth
## of work. The fire and smoke are cut down on the web and on a phone. Nothing here is native, threaded or physical:
## the blast is breakables' own, the fire is the arena's debris cubes and flames.

## each kind: how big it is, its colour, the hole its blast takes out, how far it sets others off, what it does to
## whoever's near, and how many fire and smoke cubes it throws
const KINDS := {
	"bottle": {"size": Vector3(0.52, 1.15, 0.52), "col": "#c6392c", "r": 2.5, "reach": 5.0, "hurt": 45.0, "fire": 10, "smoke": 7},
	"pump": {"size": Vector3(0.9, 1.75, 0.7), "col": "#e6dfcc", "r": 3.4, "reach": 6.5, "hurt": 60.0, "fire": 16, "smoke": 10},
	"tanker": {"size": Vector3(2.5, 2.7, 8.0), "col": "#cfd3d8", "r": 6.4, "reach": 9.5, "hurt": 95.0, "fire": 30, "smoke": 20},
}
## where they stand (from VoxelDemolition.AT): the three pumps under the canopy, two stacks of bottles against the
## petrol station and the lock-ups, a stack by the brick shop, and the tanker out on the road
const PLAN := [
	["pump", Vector3(9.0, 0.0, 10.4)],
	["pump", Vector3(12.0, 0.0, 10.4)],
	["pump", Vector3(15.0, 0.0, 10.4)],
	["bottle", Vector3(7.4, 0.0, 6.4)],
	["bottle", Vector3(8.1, 0.0, 6.4)],
	["bottle", Vector3(7.75, 1.15, 6.4)],
	["bottle", Vector3(23.0, 0.0, 6.3)],
	["bottle", Vector3(23.7, 0.0, 6.3)],
	["bottle", Vector3(-6.0, 0.0, -5.6)],
	["bottle", Vector3(-5.3, 0.0, -5.6)],
	["tanker", Vector3(8.0, 0.0, 2.3)],
]
const AT_ONCE := 3               # blasts a frame at most (the ceiling; GAP below is what really holds them apart) ...
const AT_ONCE_WEB := 2
const GAP := 0.12                # ... and this long between one and the next, so eleven of them is a run of bangs
const FUSE := Vector2(0.22, 0.45)        # s before a prop lit by another's blast goes off ("a beat later")
const BALL_V := 2.5              # m/s the wrecking ball must be doing to set one off

var level: VoxelDemolition
var list: Array = []             # [{kind, at, node, body, gone, lit}]
var booms := 0                   # props gone off this run
var chained := 0                 # ... of them, set off by another prop
var _fuse: Array = []            # [[prop, s left]]
var _cool := 0.0
var _rng := RandomNumberGenerator.new()

func setup(l: VoxelDemolition) -> void:
	level = l
	name = "Props"
	_rng.seed = 20261126
	_build()

func small() -> bool:
	return OS.has_feature("web") or VoxelTouch.active

func _build() -> void:
	for p in PLAN:
		var kind := String(p[0])
		var at: Vector3 = VoxelDemolition.AT + (p[1] as Vector3)
		var spec: Dictionary = KINDS[kind]
		var size: Vector3 = spec.size
		var node := Node3D.new()
		node.name = "Prop%d" % list.size()
		node.position = at
		add_child(node)
		var body := StaticBody3D.new()
		body.collision_layer = 1 | SkData.LAYER_WORLD        # (a shot stops at it, and you walk into it)
		body.collision_mask = 0
		body.set_meta("prop", list.size())
		node.add_child(body)
		# (`at` is its middle, where its blast goes off from; the shapes below sit in the prop node's own frame)
		list.append({"kind": kind, "at": at + Vector3(0.0, size.y * 0.5, 0.0), "node": node, "body": body,
			"gone": false, "lit": false})
		match kind:
			"tanker":
				_box(node, body, Vector3(size.x, 0.35, size.z), Vector3(0.0, 0.5, 0.0), Color("#3a3d42"))     # the trailer
				_box(node, body, Vector3(size.x, 1.9, size.z * 0.72), Vector3(0.0, 1.75, 0.6), Color(String(spec.col)))   # the tank
				_box(node, body, Vector3(size.x * 0.95, 1.5, 2.0), Vector3(0.0, 1.3, -size.z * 0.5 + 0.2), Color("#b8352a"))  # the cab
				for s in [-1.0, 1.0]:
					for k in 3:
						_box(node, null, Vector3(0.3, 0.9, 0.9), Vector3(s * size.x * 0.5, 0.45, -2.4 + k * 2.4), Color("#23242a"))
				var sign_ := _box(node, null, Vector3(0.06, 0.8, 3.0), Vector3(size.x * 0.5 + 0.03, 1.8, 0.8), Color("#e0b100"))
				sign_.name = "Flammable"
			"pump":
				_box(node, body, size, Vector3(0.0, size.y * 0.5, 0.0), Color(String(spec.col)))
				_box(node, null, Vector3(size.x * 0.7, 0.45, 0.06), Vector3(0.0, size.y * 0.75, size.z * 0.5 + 0.03), Color("#2b3b4c"))
				_box(node, null, Vector3(0.12, 0.5, 0.12), Vector3(size.x * 0.5, size.y * 0.6, 0.0), Color("#24262b"))
			_:
				_box(node, body, Vector3(size.x, size.y * 0.88, size.z), Vector3(0.0, size.y * 0.44, 0.0), Color(String(spec.col)))
				_box(node, null, Vector3(size.x * 0.45, size.y * 0.14, size.z * 0.45), Vector3(0.0, size.y * 0.94, 0.0), Color("#8d9095"))

func _box(parent: Node3D, body: StaticBody3D, size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	m.metallic = 0.25
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = at
		body.add_child(cs)
	return mi

## Where the props stand (VoxelDemolition.prop_spots, the pictures, the tests).
func spots() -> Array:
	var out := []
	for p in list:
		out.append(p.at)
	return out

func left() -> int:
	var n := 0
	for p in list:
		if not bool(p.gone):
			n += 1
	return n

## Every prop back as it was (a new run, going home).
func reset() -> void:
	for p in list:
		p.gone = false
		p.lit = false
		(p.node as Node3D).visible = true
		(p.body as StaticBody3D).collision_layer = 1 | SkData.LAYER_WORLD
	_fuse.clear()
	_cool = 0.0
	booms = 0
	chained = 0

# ---------------------------------------------------------------- setting them off

## The prop a shot hit (VoxelArena.fire, through VoxelDemolition.world_shot): lit at once. True if it was one.
func world_shot(collider: Object) -> bool:
	if collider == null or not (collider is Node) or not (collider as Node).has_meta("prop"):
		return false
	return light(int((collider as Node).get_meta("prop")), 0.0, false)

## Props within r of p lit (a grenade, another prop's blast, anything with a radius). How many.
func blast_at(p: Vector3, r: float, chain := false) -> int:
	var n := 0
	for i in list.size():
		var prop: Dictionary = list[i]
		if bool(prop.gone) or bool(prop.lit):
			continue
		if (prop.at as Vector3).distance_to(p) <= r:
			if light(i, _rng.randf_range(FUSE.x, FUSE.y), chain):
				n += 1
	return n

## Prop i lit, going off in `delay` seconds. chain: it was another prop that did it (the count). False: nothing to light.
func light(i: int, delay: float, chain := false) -> bool:
	if i < 0 or i >= list.size():
		return false
	var prop: Dictionary = list[i]
	if bool(prop.gone) or bool(prop.lit):
		return false
	prop.lit = true
	if chain:
		chained += 1
	_fuse.append([i, maxf(0.0, delay)])
	level.arena.flames.emit(prop.at, 4, Vector3.UP * 1.5, 1.6, 0.4)
	return true

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	if _fuse.is_empty():
		_cool = 0.0
		return
	_cool = maxf(0.0, _cool - dt)
	var n := 0
	var most := AT_ONCE_WEB if small() else AT_ONCE
	var i := 0
	while i < _fuse.size():
		var f: Array = _fuse[i]
		f[1] = float(f[1]) - dt
		if float(f[1]) <= 0.0 and _cool <= 0.0 and n < most:
			_fuse.remove_at(i)
			_go(int(f[0]))
			n += 1
			_cool = GAP
			continue
		i += 1

# one prop up: the hole, the fire, whoever's near, and the next one along
func _go(i: int) -> void:
	var prop: Dictionary = list[i]
	if bool(prop.gone):
		return
	prop.gone = true
	prop.lit = false
	booms += 1
	(prop.node as Node3D).visible = false
	(prop.body as StaticBody3D).collision_layer = 0
	var spec: Dictionary = KINDS[String(prop.kind)]
	var at: Vector3 = prop.at
	var r := float(spec.r)
	if level.breaks:
		level.breaks.blast(at, r)                  # (a real hole in whatever's beside it)
	_fire(at, spec)
	# everything near thrown and hurt (the enemies on the forecourt, you if you're standing there)
	for b in level.arena.bodies:
		if not is_instance_valid(b) or not b.alive:
			continue
		var off := b.position + Vector3(0, b.height * 0.5, 0) - at
		var d := off.length()
		if d > r * 1.5:
			continue
		var k := 1.0 - d / (r * 1.5)
		b.launch((off.normalized() if d > 0.1 else Vector3.UP) * (4.0 + 8.0 * k) + Vector3.UP * 3.0, 6.0)
		b.hurt(float(spec.hurt) * k)
	level.arena.hurt_players_near(at, r * 1.3, 55.0)
	level.arena.sound.play("grenades_boom", at, 3.0, _rng.randf_range(0.82, 0.95))
	# the next one along, a beat later
	blast_at(at, float(spec.reach), true)

func _fire(at: Vector3, spec: Dictionary) -> void:
	var cut := 0.45 if small() else 1.0       # (the web and the phone: half the fire, half the smoke)
	var fire := maxi(3, int(float(spec.fire) * cut))
	var smoke := maxi(2, int(float(spec.smoke) * cut))
	# a ball of fire the size of the blast, not one spark where it stood: each flame lit its own way out and up
	var r := float(spec.r) * 0.45
	for j in fire:
		var p := at + Vector3(_rng.randf_range(-r, r), _rng.randf_range(-r * 0.35, r), _rng.randf_range(-r, r))
		var out := p - at
		level.arena.flames.emit(p, 1, (out.normalized() if out.length() > 0.1 else Vector3.UP) * 3.0 + Vector3.UP * 2.0,
				_rng.randf_range(4.0, 9.0), _rng.randf_range(0.5, 1.1))
	level.arena.debris.throw(at, Vector3.UP * 1.6, Color("#f0a01e"), fire)
	level.arena.debris.throw(at + Vector3(0, 0.8, 0), Vector3.UP * 2.2, Color("#2e2b29"), smoke)

## The wrecking ball through a prop (VoxelDemolition's frame): one going fast enough sets it off.
func ball_at(p: Vector3, sp: float) -> bool:
	if sp < BALL_V:
		return false
	for i in list.size():
		var prop: Dictionary = list[i]
		if bool(prop.gone) or bool(prop.lit):
			continue
		var size: Vector3 = (KINDS[String(prop.kind)] as Dictionary).size
		var off: Vector3 = p - (prop.at as Vector3)
		if absf(off.x) < size.x * 0.5 + 1.1 and absf(off.y) < size.y * 0.5 + 1.1 and absf(off.z) < size.z * 0.5 + 1.1:
			return light(i, 0.0, false)
	return false
