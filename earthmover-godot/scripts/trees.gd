class_name Trees
extends Node3D
## The trees on the site. Hit one and it goes over, slowly at first, then bounces when it lands. The blade can then shove
## it along the ground. They don't touch the soil simulation, so the soil total is unaffected.

signal knocked(at: Vector3)
signal landed(at: Vector3)

const STANDING := 0
const FALLING := 1
const DOWN := 2
const LIE := 1.5                # radians from upright when it's on the ground
const BLADE_REACH := 0.5        # m from the cutting edge to the trunk that counts as a hit
const HIT_SPEED := 0.15         # m/s

class Pine:
	var node: MeshInstance3D
	var base := Vector2.ZERO
	var high := 10.0
	var yaw := 0.0
	var wide := 1.0          # how much wider or slimmer than usual
	var state := 0
	var dir := Vector2.ZERO
	var angle := 0.0
	var vel := 0.0
	var hit_ground := false

var list: Array[Pine] = []
var down := 0
var _sim: DirtSim

func setup(s: DirtSim, mat: Material, spots: Array[Vector2], rng: RandomNumberGenerator) -> void:
	_sim = s
	var meshes: Array[ArrayMesh] = []
	for i in 3:
		var kit := MeshKit.new()
		Props.pine(kit, Vector3.ZERO, 10.0, rng)
		meshes.append(kit.mesh())
	# And some taller and slimmer, with four tiers, so they're not all one cone (review, 10 Nov). Their own dice, so the rest of
	# the site comes out as it did.
	var vary := RandomNumberGenerator.new()
	vary.seed = 4417
	for i in 2:
		var kit := MeshKit.new()
		Props.pine(kit, Vector3.ZERO, 10.0, vary, 4, 8)
		meshes.append(kit.mesh())
	for at: Vector2 in spots:
		var t := Pine.new()
		t.base = at
		t.high = rng.randf_range(6.5, 11.0)
		t.yaw = rng.randf() * TAU
		t.wide = vary.randf_range(0.8, 1.2)
		t.node = MeshInstance3D.new()
		t.node.mesh = meshes[rng.randi() % meshes.size()]
		t.node.material_override = mat
		add_child(t.node)
		list.append(t)
		_place(t)

func _place(t: Pine) -> void:
	var look := Basis(Vector3.UP, t.yaw).scaled(Vector3(t.wide, 1.0, t.wide) * t.high / 10.0)
	if t.angle > 0.0:
		# Its up axis tipped towards dir. It rests on its branches, so it rises a little as it goes over.
		look = Basis(Vector3(t.dir.y, 0.0, -t.dir.x), t.angle) * look
	var lift := sin(t.angle) * t.high * 0.1
	t.node.transform = Transform3D(look, Vector3(t.base.x, _sim.height_at(t.base) + lift - 0.05, t.base.y))

## Where the middle of a fallen tree lies.
func _middle(t: Pine) -> Vector2:
	return t.base + t.dir * t.high * 0.4

func update(dt: float, d: Machine) -> void:
	for t: Pine in list:
		match t.state:
			STANDING:
				if d.hit_speed() > HIT_SPEED and _touching(t, d):
					_knock(t, d)
				_place(t)
			FALLING:
				# A rod tipping over: barely moving at first, then all at once.
				_shove(t, d, dt)
				t.vel += 1.5 * 9.8 / t.high * sin(t.angle + 0.05) * dt
				t.angle += t.vel * dt
				if t.angle >= LIE:
					t.angle = LIE
					if not t.hit_ground:
						t.hit_ground = true
						down += 1
						var mid := _middle(t)
						landed.emit(Vector3(mid.x, _sim.height_at(mid), mid.y))
					if t.vel > 0.5:
						t.vel *= -0.22
					else:
						t.vel = 0.0
						t.state = DOWN
				_place(t)
			DOWN:
				_shove(t, d, dt)
				_place(t)

## A second machine being driven: it can knock trees and shove them too. Only the one call to update() makes them fall.
func also(dt: float, d: Machine) -> void:
	for t: Pine in list:
		if t.state == STANDING:
			if d.hit_speed() > HIT_SPEED and _touching(t, d):
				_knock(t, d)
		else:
			_shove(t, d, dt)

## Online: the trees that aren't standing, for a guest to draw.
func net_state() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in list.size():
		var t := list[k]
		if t.state != STANDING:
			out.append_array([k, t.base.x, t.base.y, t.dir.x, t.dir.y, t.angle])
	return out

func net_take(s: PackedFloat32Array, down_count: int) -> void:
	var was_down := down
	down = down_count
	for n in s.size() / 6:
		var t := list[int(s[n * 6])]
		if t.state == STANDING:
			t.state = FALLING
			knocked.emit(Vector3(t.base.x, _sim.height_at(t.base), t.base.y))
		t.base = Vector2(s[n * 6 + 1], s[n * 6 + 2])
		t.dir = Vector2(s[n * 6 + 3], s[n * 6 + 4])
		t.angle = s[n * 6 + 5]
		if down > was_down and t.angle >= LIE and not t.hit_ground:
			t.hit_ground = true
			var mid := _middle(t)
			landed.emit(Vector3(mid.x, _sim.height_at(mid), mid.y))
	for t: Pine in list:
		_place(t)

## The blade carries a tree along: its roots while it's going over, so it falls ahead of the machine and not onto the cab, and
## the whole trunk once it's down. With the blade lifted high, the machine drives over a fallen one instead.
func _shove(t: Pine, d: Machine, dt: float) -> void:
	if d.speed <= 0.1 or not d.can_shove(t.state == DOWN):
		return
	var f := d.forward()
	for point: Vector2 in [t.base, _middle(t)]:
		var on_blade := Geometry2D.get_closest_point_to_segment(point, d.blade_a, d.blade_b)
		if on_blade.distance_to(point) < 1.2 and (point - on_blade).dot(f) > -0.4:
			t.base = (t.base + f * d.speed * dt).clamp(Vector2(-31.0, -31.0), Vector2(31.0, 31.0))
			return

func _touching(t: Pine, d: Machine) -> bool:
	if absf(d.speed) > HIT_SPEED and t.base.distance_to(d.spot) < d.body_reach:
		return true
	return Geometry2D.get_closest_point_to_segment(t.base, d.blade_a, d.blade_b).distance_to(t.base) < BLADE_REACH

func _knock(t: Pine, d: Machine) -> void:
	var push := d.push_dir()
	var away := (t.base - d.spot).normalized()
	t.dir = (push + away * 0.5).normalized()
	t.state = FALLING
	t.vel = 0.2 + absf(d.speed) * 0.18
	d.jolt()
	knocked.emit(Vector3(t.base.x, _sim.height_at(t.base), t.base.y))

## A tree right by the camera would fill the screen, so it isn't drawn.
func clear_view(from: Vector3) -> void:
	for t: Pine in list:
		t.node.visible = Vector2(from.x, from.z).distance_to(t.base) > 6.5
