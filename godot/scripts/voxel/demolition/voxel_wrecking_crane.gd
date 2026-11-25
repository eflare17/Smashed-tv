class_name VoxelWreckingCrane
extends Node3D
## The wrecking ball crane in Demolition (the owner, 24 Nov, asked for it in the first version): a tracked crane parked
## at the west end of the street. Walk up to it and E puts you in the cab; W/S drive the tracks, A/D turn it, the left
## and right arrows swing the boom round, the up and down arrows pay the cable out and in, E gets you out again.
##
## The ball is a point on a cable worked out here, not by a physics engine (there's none in this game): a verlet point
## pulled down by gravity and held at `cable` metres from the boom's tip, stepped at a fixed STEP so it swings the same
## on any machine, with next to no damping. So it keeps its own momentum: driving forward drags it behind, swinging the
## boom throws it out, and stopping lets it carry on -- the weight is the whole point, and you line a swing up a few
## seconds before it lands.
##
## What it smashes: every step, the ball's own sample points are asked of VoxelBreakables.solid (is this inside a wall
## still standing?). Where one is, the blow goes in at the speed the ball was doing -- under SMASH it's a chip
## (breakables' strike), above it a hole (breakables' blast, its radius growing with the speed), which knocks whole
## blocks out, and the system's own rules then drop or tip over whatever is left hanging. A ball that smashed keeps
## most of its speed and carries on through; one that only thudded bounces back off the wall.

const BOOM := 16.0               # m, the boom's length
const PITCH := 0.72              # rad, how far up it points
const PIVOT := Vector3(0.0, 1.6, 0.6)    # the boom's pivot on the deck (local)
const R := 1.05                  # m, the ball's radius
const CABLE := Vector2(2.2, 11.0)        # m, how short and how long the cable goes
const CABLE_SPD := 2.2           # m/s paying out
const SLEW_SPD := 0.55           # rad/s, the boom round (it takes a moment to get there and to stop)
const SLEW_ACC := 1.1
const SLEW_MAX := 1.5            # rad either side of straight ahead
const SPEED := 3.6               # m/s flat out on the tracks
const ACC := 2.2                 # m/s/s (heavy: it takes its time)
const DRAG := 0.7                # how fast it rolls to a stop
const TURN := 0.75               # rad/s turning on the spot
const STEP := 1.0 / 120.0        # s a step of the ball
const G := 9.8
const MAX_V := 14.0              # m/s the ball can ever be doing (50 km/h: a hard swing, and no faster)
const DAMP := 0.9995             # of its speed a step (next to nothing: it swings and swings)
const THUD := 1.6                # m/s: slower than this and the ball just rests on the wall
const SMASH := 3.2               # m/s: faster than this and it takes a hole out instead of a chip
const BITE := Vector2(0.9, 0.14)         # m: the hole it takes, and how much more a metre a second
const HIT_GAP := 0.05            # s between blows at most ...
const HIT_MOVE := 0.3            # ... and this far apart
const ENTER_R := 5.5             # m from the cab you can get in from

var level: VoxelDemolition
var driving := false
var pos := Vector3.ZERO          # the crane's own (the tracks on the ground)
var yaw := 0.0
var slew := 0.0                  # the boom round, from straight ahead
var cable := 7.0
var ball := Vector3.ZERO
var speed := 0.0                 # along the tracks
var slew_v := 0.0
var smashes := 0                 # holes it has taken out (the tests, the HUD)
var chips := 0                   # lesser blows
var _prev := Vector3.ZERO        # where the ball was a step ago (verlet)
var _at := Vector3.ZERO          # where it was parked
var _yaw0 := 0.0
var _t := 0.0                    # time owed to the ball's steps
var _hit_t := 0.0
var _touch := 0                  # steps since it was last in a wall (it can't wind up while it's grinding on one)
var _hit_at := Vector3.INF
var _base: Node3D
var _turret: Node3D
var _boom: Node3D
var _cable_mi: MeshInstance3D
var _ball_mi: MeshInstance3D

func setup(l: VoxelDemolition, at: Vector3, yaw_: float) -> void:
	level = l
	name = "Crane"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (it moves every frame, not on physics ticks)
	_at = at
	_yaw0 = yaw_
	_build()
	park()

func _build() -> void:
	_base = Node3D.new()
	_base.name = "Base"
	add_child(_base)
	var body := StaticBody3D.new()           # (you walk into it, and shots stop at it)
	body.collision_layer = 1 | SkData.LAYER_WORLD
	body.collision_mask = 0
	_base.add_child(body)
	var black := Color("#2b2b30")
	var paint := Color("#e0a21c")
	for s in [-1.0, 1.0]:
		_box(_base, null, Vector3(1.2, 0.95, 5.8), Vector3(s * 1.5, 0.48, 0.0), black)          # the tracks
		for i in 7:
			_box(_base, null, Vector3(1.32, 0.18, 0.3), Vector3(s * 1.5, 0.48, -2.4 + i * 0.8), Color("#4a4a52"))
	_box(_base, body, Vector3(4.4, 0.7, 4.6), Vector3(0.0, 1.2, 0.0), paint)                    # the deck
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = PIVOT
	_base.add_child(_turret)
	_box(_turret, null, Vector3(2.0, 2.0, 2.2), Vector3(-0.9, 0.95, 1.1), paint.darkened(0.12))  # the cab
	_box(_turret, null, Vector3(1.5, 1.4, 0.12), Vector3(-0.9, 1.15, 0.02), Color("#2a3b4a"))    # its glass
	_box(_turret, null, Vector3(3.2, 1.3, 1.1), Vector3(0.0, 0.65, 2.2), black)                  # the counterweight
	_boom = Node3D.new()
	_boom.name = "Boom"
	_boom.rotation = Vector3(-PITCH, 0.0, 0.0)      # (its -z points up and forward)
	_turret.add_child(_boom)
	_box(_boom, null, Vector3(0.6, 0.6, BOOM), Vector3(0.0, 0.0, -BOOM * 0.5), paint)            # the boom
	for i in 6:
		_box(_boom, null, Vector3(0.74, 0.12, 0.12), Vector3(0.0, 0.0, -2.0 - i * 2.4), black)   # its rungs
	_cable_mi = MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.1, 0.1, 1.0)
	_cable_mi.mesh = cm
	_cable_mi.material_override = _mat(Color("#55585e"))
	add_child(_cable_mi)
	_ball_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	_ball_mi.mesh = sm
	_ball_mi.material_override = _mat(Color("#3b3f45"))
	add_child(_ball_mi)

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.metallic = 0.3
	return m

func _box(parent: Node3D, body: StaticBody3D, size: Vector3, at: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = at
	parent.add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = at
		body.add_child(cs)

## Parked somewhere else from now on (the tests and the pictures stand it where they want it).
func place(at: Vector3, yaw_: float) -> void:
	_at = at
	_yaw0 = yaw_
	park()

## Back where it started, the ball hanging still (a new run).
func park() -> void:
	driving = false
	pos = _at
	yaw = _yaw0
	slew = 0.0
	slew_v = 0.0
	speed = 0.0
	cable = 7.0
	smashes = 0
	chips = 0
	_t = 0.0
	_place()
	ball = tip() - Vector3(0, cable, 0)
	_prev = ball
	_draw()

## The boom's tip (world): where the cable hangs from.
func tip() -> Vector3:
	return _boom.global_transform * Vector3(0.0, 0.0, -BOOM)

## Where you sit (the player's feet, in the cab).
func seat() -> Vector3:
	return pos + Basis(Vector3.UP, yaw) * Vector3(-0.9, 2.3, 1.2)

## Where you're put down getting out (beside the tracks).
func kerb() -> Vector3:
	return pos + Basis(Vector3.UP, yaw) * Vector3(-4.2, 0.05, 0.0)

func ball_speed() -> float:
	return (ball - _prev).length() / STEP

func can_enter() -> bool:
	return not driving and level.arena.player.global_position.distance_to(seat()) < ENTER_R

func enter() -> void:
	if driving:
		return
	driving = true
	level.arena.player.velocity = Vector3.ZERO

func leave() -> void:
	if not driving:
		return
	driving = false
	speed = 0.0
	level.arena.player.global_position = kerb()
	level.arena.player.velocity = Vector3.ZERO
	level.arena.player.reset_physics_interpolation()

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	dt = minf(dt, 0.1)
	if driving:
		_controls(dt)
		level.arena.player.global_position = seat()
		level.arena.player.velocity = Vector3.ZERO
	# the tracks (they roll on whether you're in it or not, so it coasts to a stop)
	if absf(speed) > 0.001:
		pos += Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -1.0) * speed * dt
		speed = move_toward(speed, 0.0, DRAG * dt)
	slew = clampf(slew + slew_v * dt, -SLEW_MAX, SLEW_MAX)
	if absf(slew) >= SLEW_MAX:
		slew_v = 0.0
	_place()
	_hit_t = maxf(0.0, _hit_t - dt)
	_t = minf(_t + dt, 0.25)                 # (a long frame: catch some of it up, not all)
	while _t >= STEP:
		_t -= STEP
		_swing()
	_draw()

func _controls(dt: float) -> void:
	var push := (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	if push != 0.0:
		speed = clampf(speed + push * ACC * dt, -SPEED * 0.6, SPEED)
	var turn := (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
	yaw += turn * TURN * dt
	var round_ := (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0)
	if round_ != 0.0:
		slew_v = clampf(slew_v + round_ * SLEW_ACC * dt, -SLEW_SPD, SLEW_SPD)
	else:
		slew_v = move_toward(slew_v, 0.0, SLEW_ACC * dt)
	var reel := (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0)
	if reel != 0.0:
		cable = clampf(cable + reel * CABLE_SPD * dt, CABLE.x, CABLE.y)

func _place() -> void:
	_base.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_turret.transform = Transform3D(Basis(Vector3.UP, slew), PIVOT)

# one step of the ball: gravity, the cable, the ground, and whatever wall it's in
func _swing() -> void:
	var v := ball - _prev                    # (its speed, times STEP)
	_prev = ball
	ball += v * DAMP + Vector3(0.0, -G, 0.0) * STEP * STEP
	# The cable pulls the ball to where the tip is now, not where it was, and that difference is its speed: so driving
	# and swinging the boom throw the ball about, and it keeps going after the tip stops. What the cable takes out is
	# the speed along itself (a rope tugs, it doesn't catapult); the speed across it -- the swing -- it leaves alone.
	var anchor := tip()
	var d := ball - anchor
	var len_ := d.length()
	if len_ > cable and len_ > 0.001:
		ball = anchor + d * (cable / len_)
		var n := d / len_
		var vel := (ball - _prev) / STEP
		_prev = ball - (vel - n * vel.dot(n) * 0.9) * STEP
	if ball.y < R:
		var g := ball - _prev
		_shift(Vector3(0.0, R - ball.y, 0.0))
		_prev = ball - Vector3(g.x * 0.86, -g.y * 0.25, g.z * 0.86)      # (dragging along the ground)
	_walls()
	# How fast it can ever be going. The cable can only pull so hard, and a ball grinding on masonry is being slowed by
	# it: without the lower cap on the step after a wall, a ball jammed between two buildings -- the wall shoving it one
	# way and the cable yanking it back the other, every step -- winds itself up to a speed nothing could swing at.
	_touch = maxi(0, _touch - 1)
	var cap := MAX_V * (0.4 if _touch > 0 else 1.0)
	var now := ball - _prev
	var sp := now.length() / STEP
	if sp > cap:
		_prev = ball - now * (cap / sp)

# The ball put somewhere rather than thrown there (out of a wall it's in, up out of the ground): where it was goes with
# it, so being put there counts as no speed at all -- otherwise the cable snapping it back next step reads as a yank.
func _shift(by: Vector3) -> void:
	ball += by
	_prev += by

# back on the cable after being put somewhere (again: no speed in it)
func _on_cable() -> void:
	var d := ball - tip()
	var len_ := d.length()
	if len_ > cable and len_ > 0.001:
		_shift(d * (cable / len_ - 1.0))

# the walls the ball is in this step
func _walls() -> void:
	var wb: VoxelBreakables = level.breaks
	if wb == null:
		return
	var v := (ball - _prev) / STEP
	var sp := v.length()
	var dir := v / sp if sp > 0.001 else Vector3.DOWN
	var out := Vector3.ZERO
	var at := ball
	for s in [dir * R * 0.9, Vector3.ZERO, Vector3(R * 0.8, 0, 0), Vector3(-R * 0.8, 0, 0), Vector3(0, 0, R * 0.8),
			Vector3(0, 0, -R * 0.8), Vector3(0, -R * 0.8, 0)]:
		var q: Vector3 = ball + s
		var o := wb.solid(q)
		if o != Vector3.ZERO:
			out = o
			at = q
			break
	if out == Vector3.ZERO:
		return
	_touch = 4
	_shift(out * 0.3)                        # (out of the wall it's in)
	if sp >= THUD and _hit_t <= 0.0 and (_hit_at == Vector3.INF or _hit_at.distance_to(at) > HIT_MOVE):
		_hit_t = HIT_GAP
		_hit_at = at
		if sp >= SMASH:
			wb.blast(at, clampf(BITE.x + sp * BITE.y, 0.8, 2.6))   # a hole, the faster the bigger
			smashes += 1
			_prev = ball - v * (STEP * 0.78)                      # (it carries on through)
			_on_cable()
			return
		chips += wb.strike(at + out * 1.3, -out, 1.8, 0.45, sp * 1.6)
	var into := v.dot(out)
	var back := v - out * into * 1.5         # (off the face, most of its speed gone)
	_prev = ball - back * (STEP * 0.4)
	_on_cable()

func _draw() -> void:
	var anchor := tip()
	var d := ball - anchor
	var len_ := maxf(d.length(), 0.05)
	_ball_mi.position = ball
	var z := d / len_                        # (the cable box's own z runs down it, scaled to its length)
	var up := Vector3.UP if absf(z.y) < 0.99 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	_cable_mi.transform = Transform3D(Basis(x, z.cross(x), z * len_), anchor + d * 0.5)
