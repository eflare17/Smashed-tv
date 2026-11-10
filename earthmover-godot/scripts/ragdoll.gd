class_name Ragdoll
extends Node3D
## The rider thrown off the bike, gone floppy. He's thirteen points (head, shoulders, hips, elbows, hands, knees, boots) joined
## by sticks that keep their length: his body and head held stiff, his arms and legs free to swing at the joints. Each point
## falls, bounces a little off the dirt and drags along it, so how he goes and how he ends up lying comes out of how he was
## thrown, not a set tumble. The pieces of the rider's model are hung off those points.

const STEP := 1.0 / 120.0
const ROUNDS := 8                # times a step the sticks are pulled back to length
const THICK := 0.07              # m: how far each point stays off the ground, about a limb's thickness
const BOUNCE := 0.18             # of the speed into the ground, back out of it (0.15 slid, 0.3 sent him flying)
const SCRAPE := 16.0             # m/s2: how hard the dirt slows his body dragging on it (8 till the owner asked for less slide, 10 Nov)
const CATCH := 36.0              # m/s2: and his hands, boots, head, knees and elbows, that dig in and tip him over
const TUMBLE := 0.95            # rad/s head over heels he's thrown off turning, for each m/s the bike was going
const SIDE_ROLL := 2.5           # rad/s he's thrown off rolling sideways, and a bit more the faster it was going
const AIR_KEEP := 0.999          # of a point's speed kept each step in the air
const KNEE_FRONT := 0.03         # m: a knee stays at least this far in front of the line from hip to boot, so it can't bend backwards

enum { HEAD, SH_L, SH_R, HIP_L, HIP_R, ELB_L, ELB_R, HAND_L, HAND_R, KNEE_L, KNEE_R, BOOT_L, BOOT_R, COUNT }

var sim: DirtSim
var points := PackedVector3Array()
var _was := PackedVector3Array()
var _ease := PackedFloat32Array()   # how easily each point's moved when a stick pulls it: one over its weight
var _sticks: Array[Array] = []      # [a, b, length, only keeps them apart]
var _rest := PackedVector3Array()
var _parts: Array[Array] = []       # [the piece, a, b (or -1 for the body), its frame sitting on the bike]
var _left := 0.0

func setup(s: DirtSim, mat: Material) -> void:
	sim = s
	top_level = true
	visible = false
	_rest.resize(COUNT)
	_ease.resize(COUNT)
	_rest[HEAD] = Props.rider_joint("head")
	_ease[HEAD] = 1.0 / 5.0
	for k in 2:
		var z := -1.0 if k == 0 else 1.0
		_rest[SH_L + k] = Props.rider_joint("shoulder", z)
		_rest[HIP_L + k] = Props.rider_joint("hip", z)
		_rest[ELB_L + k] = Props.rider_joint("elbow", z)
		_rest[HAND_L + k] = Props.rider_joint("hand", z)
		_rest[KNEE_L + k] = Props.rider_joint("knee", z)
		_rest[BOOT_L + k] = Props.rider_joint("boot", z)
		# kg, roughly: the body's weight shared over its four corners.
		_ease[SH_L + k] = 1.0 / 10.0
		_ease[HIP_L + k] = 1.0 / 12.0
		_ease[ELB_L + k] = 1.0 / 2.0
		_ease[HAND_L + k] = 1.0 / 1.0
		_ease[KNEE_L + k] = 1.0 / 5.0
		_ease[BOOT_L + k] = 1.0 / 3.0
	# His body and head, stiff.
	var stiff := [SH_L, SH_R, HIP_L, HIP_R, HEAD]
	for a in stiff.size():
		for b in range(a + 1, stiff.size()):
			_stick(stiff[a], stiff[b])
	for k in 2:
		_stick(SH_L + k, ELB_L + k)
		_stick(ELB_L + k, HAND_L + k)
		_stick(HIP_L + k, KNEE_L + k)
		_stick(KNEE_L + k, BOOT_L + k)
		# An elbow or knee folds only so far.
		_stick(SH_L + k, HAND_L + k, true, 0.45)
		_stick(HIP_L + k, BOOT_L + k, true, 0.4)
	# His legs don't pass through each other.
	_stick(KNEE_L, KNEE_R, true, 0.0, 0.16)
	_stick(BOOT_L, BOOT_R, true, 0.0, 0.16)
	# The pieces of him.
	var kit := MeshKit.new()
	Props.rider_body(kit)
	_part(kit, mat, -1, -1)
	for k in 2:
		var z := -1.0 if k == 0 else 1.0
		kit = MeshKit.new()
		Props.rider_upper_arm(kit, z)
		_part(kit, mat, SH_L + k, ELB_L + k)
		kit = MeshKit.new()
		Props.rider_forearm(kit, z)
		_part(kit, mat, ELB_L + k, HAND_L + k)
		kit = MeshKit.new()
		Props.rider_thigh(kit, z)
		_part(kit, mat, HIP_L + k, KNEE_L + k)
		kit = MeshKit.new()
		Props.rider_shin(kit, z)
		_part(kit, mat, KNEE_L + k, BOOT_L + k)
	points = _rest.duplicate()
	_was = _rest.duplicate()

## A stick from `a` to `b` as long as they are sitting on the bike; `apart` only keeps them at least `of` that apart (or `least` m).
func _stick(a: int, b: int, apart := false, of := 1.0, least := 0.0) -> void:
	var length := _rest[a].distance_to(_rest[b]) if not apart else 0.0
	if apart:
		length = maxf(least, of * (_limb(a, b)))
	_sticks.append([a, b, length, apart])

## How long the arm or leg is from `a` to `b` going through its joint.
func _limb(a: int, b: int) -> float:
	var mid := ELB_L + (a - SH_L) if a == SH_L or a == SH_R else KNEE_L + (a - HIP_L)
	if not (a in [SH_L, SH_R, HIP_L, HIP_R]):
		return 0.0
	return _rest[a].distance_to(_rest[mid]) + _rest[mid].distance_to(_rest[b])

func _part(kit: MeshKit, mat: Material, a: int, b: int) -> void:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	add_child(m)
	_parts.append([m, a, b, _frame(_rest, a, b)])

## Thrown off: `at` is where the rider was on the bike, going at `vel` and turning at `spin` rad/s about `axis`. On top of that
## he goes head over heels the faster it was going, and rolls a little sideways, `roll_way` (-1 or 1).
func throw(at: Transform3D, vel: Vector3, axis: Vector3, spin: float, roll_way := 1.0) -> void:
	points.resize(COUNT)
	_was.resize(COUNT)
	var mid := at * ((_rest[SH_L] + _rest[SH_R] + _rest[HIP_L] + _rest[HIP_R]) * 0.25)
	var up := at.basis.y.normalized()
	var side := at.basis.z.normalized()
	var flat := Vector3(vel.x, 0.0, vel.z)
	var going := flat.length()
	var ahead := flat / going if going > 0.1 else at.basis.x.normalized()
	var turning := axis * spin + Vector3.UP.cross(ahead) * going * TUMBLE + ahead * roll_way * (SIDE_ROLL + going * 0.1)
	for n in COUNT:
		var p := at * _rest[n]
		var v := vel + turning.cross(p - mid)
		# His arms fly up and out, and his boots come off the pegs.
		var out := -1.0 if n in [ELB_L, HAND_L, BOOT_L, KNEE_L] else 1.0
		if n == HAND_L or n == HAND_R:
			v += up * 2.2 + side * 1.2 * out
		elif n == ELB_L or n == ELB_R:
			v += up * 1.1 + side * 0.6 * out
		elif n == BOOT_L or n == BOOT_R:
			v += up * 0.9 + side * 0.4 * out
		points[n] = p
		_was[n] = p - v * STEP
	_left = 0.0
	visible = true
	_draw()

func step(dt: float) -> void:
	_left += dt
	var n := 0
	while _left >= STEP and n < 12:
		_left -= STEP
		n += 1
		_move()
	if _left >= STEP:
		_left = 0.0
	_draw()

func _move() -> void:
	var fall := -9.8 * STEP * STEP
	for k in COUNT:
		var p := points[k]
		var v := (p - _was[k]) * AIR_KEEP
		_was[k] = p
		points[k] = p + v + Vector3(0.0, fall, 0.0)
	_ground(true)
	for r in ROUNDS:
		for s: Array in _sticks:
			var a: int = s[0]
			var b: int = s[1]
			var d := points[b] - points[a]
			var l := d.length()
			if l < 0.0001 or (s[3] and l >= s[2]):
				continue
			var move := d * ((l - float(s[2])) / l / (_ease[a] + _ease[b]))
			points[a] += move * _ease[a]
			points[b] -= move * _ease[b]
		_knees()
		_ground(false)

## Knees bend only the one way.
func _knees() -> void:
	var f := _forward(points)
	for k in 2:
		var mid := (points[HIP_L + k] + points[BOOT_L + k]) * 0.5
		var off := (points[KNEE_L + k] - mid).dot(f)
		if off < KNEE_FRONT:
			points[KNEE_L + k] += f * (KNEE_FRONT - off) * 0.5

## Nothing goes under the dirt. Coming down onto it, a point bounces a little and drags.
func _ground(landing: bool) -> void:
	var area := Machine.AREA
	for k in COUNT:
		var p := points[k]
		p.x = clampf(p.x, -area, area)
		p.z = clampf(p.z, -area, area)
		var floor_y := sim.height_at(Vector2(p.x, p.z)) + THICK
		if p.y < floor_y:
			if landing:
				var w := _was[k]
				var vy := p.y - w.y
				var flat := Vector2(p.x - w.x, p.z - w.z)
				var l := flat.length()
				var grip := SCRAPE if k in [SH_L, SH_R, HIP_L, HIP_R] else CATCH
				if l > 0.0:
					flat *= maxf(l - grip * STEP * STEP, 0.0) / l
				p.y = floor_y
				w = Vector3(p.x - flat.x, p.y + minf(vy, 0.0) * BOUNCE, p.z - flat.y)
				_was[k] = w
			else:
				p.y = floor_y
		points[k] = p

## The way his chest faces, square to his body.
func _forward(at: PackedVector3Array) -> Vector3:
	var up := (at[SH_L] + at[SH_R] - at[HIP_L] - at[HIP_R])
	var side := at[SH_R] - at[SH_L]
	var f := up.cross(side)
	return f.normalized() if f.length() > 0.0001 else Vector3.RIGHT

## Where a piece sits: his body off its four corners, an arm or leg piece from `a` along to `b`.
func _frame(at: PackedVector3Array, a: int, b: int) -> Transform3D:
	var f := _forward(at)
	if a < 0:
		var y := (at[SH_L] + at[SH_R] - at[HIP_L] - at[HIP_R]).normalized()
		return Transform3D(Basis(f, y, f.cross(y)), (at[HIP_L] + at[HIP_R]) * 0.5)
	var along := at[b] - at[a]
	var y2 := along.normalized() if along.length() > 0.0001 else Vector3.UP
	var x := f - y2 * f.dot(y2)
	if x.length() < 0.001:
		x = (at[SH_R] - at[SH_L]).cross(y2)
	x = x.normalized()
	return Transform3D(Basis(x, y2, x.cross(y2)), at[a])

func _draw() -> void:
	for part: Array in _parts:
		var m: MeshInstance3D = part[0]
		var rest: Transform3D = part[3]
		m.transform = _frame(points, part[1], part[2]) * rest.affine_inverse()

## Online: where he is, to send, and taking that on the other end.
func net_points() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in points:
		out.append_array([p.x, p.y, p.z])
	return out

func net_take(s: PackedFloat32Array, k: float) -> void:
	if s.size() < COUNT * 3:
		return
	for n in COUNT:
		points[n] = points[n].lerp(Vector3(s[n * 3], s[n * 3 + 1], s[n * 3 + 2]), k)
	visible = true
	_draw()

## How far each stick is off its length at worst, as a share of it: for the tests.
func worst_stretch() -> float:
	var worst := 0.0
	for s: Array in _sticks:
		if s[3]:
			continue
		var l := points[s[0]].distance_to(points[s[1]])
		worst = maxf(worst, absf(l - float(s[2])) / float(s[2]))
	return worst
