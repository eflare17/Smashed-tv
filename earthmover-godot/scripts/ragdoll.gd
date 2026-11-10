class_name Ragdoll
extends Node3D
## The rider thrown off the bike, gone floppy. He's fifteen points (head, shoulders, waist, hips, elbows, hands, knees, boots)
## joined by sticks that keep their length: his chest and his hips each stiff, folding at the waist between them, his head nodding
## on his shoulders, his arms and legs free to swing at the joints. He runs into what's solid: the bike sliding after him, trees,
## machines, sheds and the site fence. Once he's stopped he gets himself up onto his feet. Each point
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
const WAIST_FOLD := 0.74         # of his body's length, the closest his shoulders come to his hips: bent forward about 85 degrees
const WAIST_BACK := 0.04         # m: how far his waist goes in front of the line from hips to shoulders, arching back
const NOD := 0.7                 # radians his head nods forward or back from in line with his chest
const WALL_BOUNCE := 0.2         # of the speed into something solid, back off it
const BIKE_R := 0.28             # m: how thick the bike is, lying there
const BIKE_CLEAR := 0.25         # s after he's thrown before the bike's solid to him: he starts astride it
const REACH := 3.0               # m: solid things further than this from him aren't looked at
const RISE := 1.3                # s he takes getting up
const STILL := 0.5               # m/s: every bit of him slower than this, he's stopped

enum { HEAD, SH_L, SH_R, HIP_L, HIP_R, ELB_L, ELB_R, HAND_L, HAND_R, KNEE_L, KNEE_R, BOOT_L, BOOT_R, WAIST_L, WAIST_R, COUNT }

var sim: DirtSim
var points := PackedVector3Array()
var _was := PackedVector3Array()
var _ease := PackedFloat32Array()   # how easily each point's moved when a stick pulls it: one over its weight
var _sticks: Array[Array] = []      # [a, b, length, only keeps them apart]
var _rest := PackedVector3Array()
var _parts: Array[Array] = []       # [the piece, a, b (or CHEST, PELVIS, NECK below), its frame sitting on the bike]
var _left := 0.0

const CHEST := -1
const PELVIS := -2
const NECK := -3

var walls: Array = []            # what's solid on the site: [a, b, radius, how high], as a machine's footprint is, standing up off the ground
var edge := 0.0                  # m from the middle he can't get past: the site fence, or 0 for where machines stop
var bike_a := Vector3.ZERO       # the bike lying there, from its back axle
var bike_b := Vector3.ZERO       # to its front
var bike_vel := Vector3.ZERO     # and how it's sliding
var bike_solid := false
var shoved := Vector3.ZERO       # kg m/s he's taken off the bike running into it, since last asked
var _shove_left := 0.0           # kg m/s he still has to give the bike: never more than he came off with
var rising := -1.0               # s into getting up, or -1 lying where he fell
var _near: Array = []
var _age := 0.0
var _bike_on := false
var _fell: PackedVector3Array
var _crouch: PackedVector3Array
var _stand: PackedVector3Array

# Up on his feet, and halfway there, crouched: [head, shoulder, hip, elbow, hand, knee, boot, waist], x the way he faces, y up
# off the ground, z out to his side.
const STAND: Array[Vector3] = [Vector3(0.03, 1.565, 0.0), Vector3(0.0, 1.36, 0.19), Vector3(0.0, 0.88, 0.11), Vector3(-0.02, 1.12, 0.26), Vector3(0.06, 0.91, 0.27), Vector3(0.04, 0.47, 0.13), Vector3(0.0, 0.07, 0.13), Vector3(0.0, 1.12, 0.15)]
const CROUCH: Array[Vector3] = [Vector3(0.42, 0.93, 0.0), Vector3(0.26, 0.82, 0.19), Vector3(-0.08, 0.48, 0.11), Vector3(0.36, 0.6, 0.25), Vector3(0.42, 0.4, 0.22), Vector3(0.22, 0.36, 0.17), Vector3(-0.05, 0.07, 0.14), Vector3(0.08, 0.66, 0.15)]

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
		_rest[WAIST_L + k] = (_rest[SH_L + k] + _rest[HIP_L + k]) * 0.5
		_rest[ELB_L + k] = Props.rider_joint("elbow", z)
		_rest[HAND_L + k] = Props.rider_joint("hand", z)
		_rest[KNEE_L + k] = Props.rider_joint("knee", z)
		_rest[BOOT_L + k] = Props.rider_joint("boot", z)
		# kg, roughly: the body's weight shared over its six corners.
		_ease[SH_L + k] = 1.0 / 7.0
		_ease[WAIST_L + k] = 1.0 / 7.0
		_ease[HIP_L + k] = 1.0 / 9.0
		_ease[ELB_L + k] = 1.0 / 2.0
		_ease[HAND_L + k] = 1.0 / 1.0
		_ease[KNEE_L + k] = 1.0 / 5.0
		_ease[BOOT_L + k] = 1.0 / 3.0
	# His chest and his hips, each stiff, hinged along his waist.
	_stick(SH_L, SH_R)
	_stick(WAIST_L, WAIST_R)
	_stick(HIP_L, HIP_R)
	var sh_mid := (_rest[SH_L] + _rest[SH_R]) * 0.5
	var waist_mid := (_rest[WAIST_L] + _rest[WAIST_R]) * 0.5
	var neck := _rest[HEAD].distance_to(sh_mid)
	var chest := sh_mid.distance_to(waist_mid)
	var waist_out := _rest[WAIST_R].distance_to(waist_mid)
	for k in 2:
		_stick(SH_L + k, WAIST_L + k)
		_stick(SH_L + k, WAIST_R - k)
		_stick(WAIST_L + k, HIP_L + k)
		_stick(WAIST_L + k, HIP_R - k)
		# He folds forward at the waist only so far.
		_apart(SH_L + k, HIP_L + k, WAIST_FOLD * _rest[SH_L + k].distance_to(_rest[HIP_L + k]))
		# His head's on his shoulders, nodding only so far either way.
		_stick(HEAD, SH_L + k)
		_apart(HEAD, WAIST_L + k, sqrt(neck * neck + chest * chest + 2.0 * neck * chest * cos(NOD) + waist_out * waist_out))
		_stick(SH_L + k, ELB_L + k)
		_stick(ELB_L + k, HAND_L + k)
		_stick(HIP_L + k, KNEE_L + k)
		_stick(KNEE_L + k, BOOT_L + k)
		# An elbow or knee folds only so far.
		_apart(SH_L + k, HAND_L + k, 0.45 * (_rest[SH_L + k].distance_to(_rest[ELB_L + k]) + _rest[ELB_L + k].distance_to(_rest[HAND_L + k])))
		_apart(HIP_L + k, BOOT_L + k, 0.4 * (_rest[HIP_L + k].distance_to(_rest[KNEE_L + k]) + _rest[KNEE_L + k].distance_to(_rest[BOOT_L + k])))
	# His legs don't pass through each other.
	_apart(KNEE_L, KNEE_R, 0.16)
	_apart(BOOT_L, BOOT_R, 0.16)
	# The pieces of him.
	var kit := MeshKit.new()
	Props.rider_chest(kit)
	_part(kit, mat, CHEST, CHEST)
	kit = MeshKit.new()
	Props.rider_pelvis(kit)
	_part(kit, mat, PELVIS, PELVIS)
	kit = MeshKit.new()
	Props.rider_head(kit)
	_part(kit, mat, NECK, NECK)
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

## A stick from `a` to `b` as long as they are sitting on the bike.
func _stick(a: int, b: int) -> void:
	_sticks.append([a, b, _rest[a].distance_to(_rest[b]), false])

## `a` and `b` are never closer than `least` m.
func _apart(a: int, b: int, least: float) -> void:
	_sticks.append([a, b, least, true])

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
	_age = 0.0
	rising = -1.0
	shoved = Vector3.ZERO
	_shove_left = 0.0
	for e in _ease:
		_shove_left += vel.length() / e
	_bike_on = false
	visible = true
	_draw()

func step(dt: float) -> void:
	_age += dt
	if rising >= 0.0:
		_rise(dt)
		_draw()
		return
	_look_round()
	_left += dt
	var n := 0
	while _left >= STEP and n < 12:
		_left -= STEP
		n += 1
		_move()
	if _left >= STEP:
		_left = 0.0
	_draw()

## What's solid and near enough to matter this frame, and whether he's clear of the bike yet.
func _look_round() -> void:
	var hips := (points[HIP_L] + points[HIP_R]) * 0.5
	var at := Vector2(hips.x, hips.z)
	_near.clear()
	for w: Array in walls:
		if Geometry2D.get_closest_point_to_segment(at, w[0], w[1]).distance_to(at) - float(w[2]) < REACH:
			_near.append(w)
	if bike_solid and not _bike_on and _age > BIKE_CLEAR:
		_bike_on = true
		for k in COUNT:
			if Geometry3D.get_closest_point_to_segment(points[k], bike_a, bike_b).distance_to(points[k]) < BIKE_R + THICK:
				_bike_on = false
				break

func _move() -> void:
	var fall := -9.8 * STEP * STEP
	for k in COUNT:
		var p := points[k]
		var v := (p - _was[k]) * AIR_KEEP
		_was[k] = p
		points[k] = p + v + Vector3(0.0, fall, 0.0)
	_ground(true)
	_solid(true)
	for r in ROUNDS:
		_pull()
		_ground(false)
		_solid(false)

## The sticks pulled back to length, and his joints kept bending only the way they do.
func _pull() -> void:
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
	_waist()

## Knees bend only the one way.
func _knees() -> void:
	var f := _facing(points, WAIST_L, HIP_L)
	for k in 2:
		var mid := (points[HIP_L + k] + points[BOOT_L + k]) * 0.5
		var off := (points[KNEE_L + k] - mid).dot(f)
		if off < KNEE_FRONT:
			points[KNEE_L + k] += f * (KNEE_FRONT - off) * 0.5

## He folds forward at the waist, and arches back hardly at all.
func _waist() -> void:
	var f := _forward(points)
	var mid := (points[SH_L] + points[SH_R] + points[HIP_L] + points[HIP_R]) * 0.25
	var off := ((points[WAIST_L] + points[WAIST_R]) * 0.5 - mid).dot(f)
	if off > WAIST_BACK:
		var move := f * (off - WAIST_BACK) * 0.5
		points[WAIST_L] -= move
		points[WAIST_R] -= move

## Nothing goes under the dirt. Coming down onto it, a point bounces a little and drags.
func _ground(landing: bool) -> void:
	var area := edge if edge > 0.0 else Machine.AREA
	for k in COUNT:
		var p := points[k]
		p.x = clampf(p.x, -area, area)
		p.z = clampf(p.z, -area, area)
		var floor_y := sim.height_at(Vector2(p.x, p.z)) + THICK
		if p.y < floor_y:
			if landing:
				p = _land(k, p, floor_y)
			else:
				p.y = floor_y
		points[k] = p

## Point `k`, come down to `floor_y` at `p`: it bounces a little and drags.
func _land(k: int, p: Vector3, floor_y: float) -> Vector3:
	var w := _was[k]
	var vy := p.y - w.y
	var flat := Vector2(p.x - w.x, p.z - w.z)
	var l := flat.length()
	var grip := SCRAPE if k in [SH_L, SH_R, HIP_L, HIP_R, WAIST_L, WAIST_R] else CATCH
	if l > 0.0:
		flat *= maxf(l - grip * STEP * STEP, 0.0) / l
	p.y = floor_y
	_was[k] = Vector3(p.x - flat.x, p.y + minf(vy, 0.0) * BOUNCE, p.z - flat.y)
	return p

## He doesn't go through what's standing on the site, nor the bike.
func _solid(landing: bool) -> void:
	for w: Array in _near:
		for k in COUNT:
			_wall(k, w, landing)
	if _bike_on:
		for k in COUNT:
			_bike(k, landing)

## Point `k` against one solid thing: onto the top of it coming down from above, or else pushed back out of its side.
func _wall(k: int, w: Array, landing: bool) -> void:
	var p := points[k]
	var a: Vector2 = w[0]
	var b: Vector2 = w[1]
	var r := float(w[2]) + THICK
	var flat := Vector2(p.x, p.z)
	var top := sim.height_at(flat) + float(w[3]) + THICK
	if p.y >= top:
		return
	var was := Vector2(_was[k].x, _was[k].z)
	var near := Geometry2D.get_closest_point_to_segment(flat, a, b)
	var out := flat - near
	var d := out.length()
	# Something thin, like the fence, he could be clean through in a step.
	var through := a != b and Geometry2D.segment_intersects_segment(was, flat, a, b) != null
	if d >= r and not through:
		return
	if _was[k].y >= top - 0.1:
		if landing:
			points[k] = _land(k, p, top)
		else:
			p.y = top
			points[k] = p
		return
	var n := out / d if d > 0.0001 else Vector2.ZERO
	if through or d <= 0.0001:
		# Back out the side he came in from.
		var line := (b - a).normalized() if a != b else Vector2.RIGHT
		var across := Vector2(-line.y, line.x)
		n = across if (was - a).dot(across) >= 0.0 else -across
		near = flat - across * (flat - a).dot(across)
	var to := near + n * r
	var push := to - flat
	var v := flat - was
	# Moved out, without that throwing him; and what speed he had into it mostly lost.
	var w3 := _was[k] + Vector3(push.x, 0.0, push.y)
	if landing:
		var into := v.dot(n)
		if into < 0.0:
			v -= n * into * (1.0 + WALL_BOUNCE)
			v *= 0.92
			w3 = Vector3(to.x - v.x, w3.y, to.y - v.y)
	_was[k] = w3
	points[k] = Vector3(to.x, p.y, to.y)

## Point `k` against the bike lying there: pushed off it, and the bike shoved by as much as he's stopped.
func _bike(k: int, landing: bool) -> void:
	var p := points[k]
	var near := Geometry3D.get_closest_point_to_segment(p, bike_a, bike_b)
	var out := p - near
	var d := out.length()
	var r := BIKE_R + THICK
	if d >= r or d < 0.0001:
		return
	var n := out / d
	if n.y < 0.0:
		# Never down into the dirt.
		n.y = 0.0
		if n.length() < 0.01:
			return
		n = n.normalized()
	var push := n * (r - d)
	var v := (p - _was[k]) / STEP
	points[k] = p + push
	_was[k] += push
	if landing:
		var into := (v - bike_vel).dot(n)
		if into < 0.0:
			var change := -n * into * (1.0 + WALL_BOUNCE)
			_was[k] -= change * STEP
			# Only a real knock shoves the bike: lying on it he just rests there.
			if into < -0.5:
				var give := (change / _ease[k]).limit_length(_shove_left)
				_shove_left -= give.length()
				shoved -= give

## Every bit of him has all but stopped.
func settled() -> bool:
	for k in COUNT:
		if points[k].distance_to(_was[k]) > STILL * STEP:
			return false
	return true

## He gets himself up: over onto his hands and knees, then onto his feet, facing the way he was lying.
func get_up() -> void:
	if rising >= 0.0:
		return
	rising = 0.0
	_fell = points.duplicate()
	var hips := (points[HIP_L] + points[HIP_R]) * 0.5
	var boots := (points[BOOT_L] + points[BOOT_R]) * 0.5
	var lie := (points[SH_L] + points[SH_R]) * 0.5 - hips
	lie.y = 0.0
	var f := _forward(points)
	var face := Vector3(f.x, 0.0, f.z)
	if lie.length() > 0.15:
		# Face down he pushes up the way his head is; on his back he sits up, toward his feet.
		face = lie if f.y < 0.0 else -lie
	face = face.normalized() if face.length() > 0.001 else Vector3.RIGHT
	var base := hips.lerp(boots, 0.5)
	base.y = sim.height_at(Vector2(base.x, base.z))
	var frame := Transform3D(Basis(face, Vector3.UP, face.cross(Vector3.UP)), base)
	_crouch = _pose(frame, CROUCH)
	_stand = _pose(frame, STAND)

## How long he's been up on his feet, or under 0 if he isn't yet.
func stood() -> float:
	return rising - RISE if rising >= 0.0 else -1.0

func _pose(frame: Transform3D, of: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(COUNT)
	out[HEAD] = frame * of[0]
	var order := [SH_L, HIP_L, ELB_L, HAND_L, KNEE_L, BOOT_L, WAIST_L]
	for n in order.size():
		for k in 2:
			var at: Vector3 = of[n + 1]
			out[int(order[n]) + k] = frame * Vector3(at.x, at.y, at.z * (-1.0 if k == 0 else 1.0))
	return out

func _rise(dt: float) -> void:
	rising += dt
	var u := clampf(rising / RISE, 0.0, 1.0)
	const CUT := 0.45
	for k in COUNT:
		if u < CUT:
			points[k] = _fell[k].lerp(_crouch[k], smoothstep(0.0, 1.0, u / CUT))
		else:
			points[k] = _crouch[k].lerp(_stand[k], smoothstep(0.0, 1.0, (u - CUT) / (1.0 - CUT)))
	for r in 4:
		_pull()
		_ground(false)
	_was = points.duplicate()

## The way he faces, square to his body from `top` (the left of its two points) down to `low`.
func _facing(at: PackedVector3Array, top: int, low: int) -> Vector3:
	var up := at[top] + at[top + 1] - at[low] - at[low + 1]
	var f := up.cross(at[top + 1] - at[top])
	return f.normalized() if f.length() > 0.0001 else Vector3.RIGHT

## The way his body faces, taken from shoulders to hips.
func _forward(at: PackedVector3Array) -> Vector3:
	return _facing(at, SH_L, HIP_L)

## A piece sitting at `from`, standing up along `up`, as square as can be to `side`.
func _block(from: Vector3, up: Vector3, side: Vector3) -> Transform3D:
	var y := up.normalized() if up.length() > 0.0001 else Vector3.UP
	var f := y.cross(side)
	if f.length() < 0.0001:
		f = y.cross(Vector3.BACK) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	f = f.normalized()
	return Transform3D(Basis(f, y, f.cross(y)), from)

## Where a piece sits: his chest, hips and head off their corners, an arm or leg piece from `a` along to `b`.
func _frame(at: PackedVector3Array, a: int, b: int) -> Transform3D:
	var sh := (at[SH_L] + at[SH_R]) * 0.5
	var waist := (at[WAIST_L] + at[WAIST_R]) * 0.5
	if a == CHEST:
		return _block(waist, sh - waist, at[SH_R] - at[SH_L])
	if a == PELVIS:
		var hips := (at[HIP_L] + at[HIP_R]) * 0.5
		return _block(hips, waist - hips, at[HIP_R] - at[HIP_L])
	if a == NECK:
		return _block(sh, at[HEAD] - sh, at[SH_R] - at[SH_L])
	# His arms go by his chest, his legs by his hips.
	var arm := a in [SH_L, SH_R, ELB_L, ELB_R]
	var f := _facing(at, SH_L, WAIST_L) if arm else _facing(at, WAIST_L, HIP_L)
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
