# (Copied from stkilda-godot scripts/player/walker.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkWalker
extends CharacterBody3D
## Walking round as one of the cast (Jaymie or Sam). The person's model rides inside this body; WASD walks
## relative to the camera (Shift runs, Space jumps), the model turns to face where it's going, the legs and arms
## swing as it walks, and it steps up kerbs and wheel stops. Collides with the shop (layer 1).

const WALK := 3.2
const RUN := 6.5
const JUMP := 4.2
const GRAVITY := 14.0
const STEP := 0.35

var person: Node3D                 # the model being walked
var cam: SkFollowCam                 # for "forward"
var controls_enabled := true
var _phase := 0.0
var _swing := 0.0                  # 0 standing .. 1 walking
var _shove := 0.0                  # a shove under way (s left): both arms thrust out in front, hands forward

const SHOVE := 0.55                # how long a shove lasts
## The shove's pose: each arm (shoulder, elbow) out straight in front at chest height, a touch in towards the middle.
const SHOVE_L := [Vector3(1.5, 0, 0.18), Vector3(0.05, 0, 0)]
const SHOVE_R := [Vector3(1.5, 0, -0.18), Vector3(0.05, 0, 0)]

## A friend tagging along (the owner's idea, 2026-10-29): no controls, they walk after `lead` (you), keeping to their
## `spot` beside and behind you (in your facing: +z is behind) as you go, at your pace, running to catch up when
## they're off it. Left far behind (stuck, or you teleported), they catch up at once.
var lead: SkWalker = null
var spot := Vector3.ZERO
const LOST := 25.0

## A friend's velocity this step, toward their spot behind the one they follow.
func _keep_up() -> Vector3:
	var yaw := lead.person.global_rotation.y if lead.person else 0.0
	var want := lead.global_position + spot.rotated(Vector3.UP, yaw)
	var to := want - global_position
	to.y = 0.0
	var d := to.length()
	if d > LOST:
		global_position = want + Vector3(0, 0.2, 0)
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		return Vector3.ZERO
	var theirs := Vector3(lead.velocity.x, 0, lead.velocity.z)
	if d < 0.3 and theirs.length() < 0.3:
		return Vector3.ZERO
	# go as fast as they're going, plus a bit more the further off the spot (so they keep to it, not trail behind it)
	var own_run := SkJared.RUN if person is SkJared else RUN
	var v := theirs + to * 2.5
	var cap := maxf(own_run, theirs.length() * 1.1)       # (keep up, even with someone faster on their feet)
	return v.limit_length(cap)

## The bat (B, or BAT on a phone; the owner's idea, 2026-10-31): whoever you are pulls out a bat and swings it, two
## hands, back and then down and through low in front like a golf swing, so it sweeps along the ground: an ibis the
## bat itself catches gets knocked flying (SkIbis.hit). Juicy SkJared's Mixamo "swinging" is swinging up on a rope, so his
## walk is held still and his arms and back are turned by hand the same way (_jared_pose).
const BAT_TIME := 0.6
var _bat_t := -1.0                     # time into a swing (-1: not swinging)
var _bat: Node3D = null                # (what to take away after: the bat, or the bone holder it's on)
var _bat_root: Node3D = null           # (the bat itself)
var _bat_was: Array = []               # (where the bat was the step before: [handle end, tip])
var _bat_hit := false
var _thud: AudioStreamPlayer3D = null
var _jared_from := {}                  # (SkJared's bones as the swing started: bone -> its pose's rotation)

func swing() -> void:
	if _bat_t >= 0.0 or person == null:
		return
	_bat_t = 0.0
	_bat_hit = false
	_bat = SkWalker.bat()
	_bat_root = _bat
	_bat_was = []
	if person is SkJared:
		var j := person as SkJared
		var sk := j.model.find_child("Skeleton3D", true, false) as Skeleton3D
		var at := BoneAttachment3D.new()
		at.bone_name = "RightHand"
		sk.add_child(at)
		at.add_child(_bat)
		_bat.scale = Vector3.ONE * 0.72 / maxf(0.01, sk.global_basis.get_scale().x)
		_bat.rotation = Vector3(PI, 0, 0)
		_bat = at
		if j.anim:
			j.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_jared_from.clear()
		for b in ["RightArm", "LeftArm", "Spine1"]:
			var i := sk.find_bone(b)
			if i >= 0:
				_jared_from[i] = sk.get_bone_pose_rotation(i)
	else:
		person.get_node("Body/ArmR/Fore/Hand").add_child(_bat)

## SkJared's swing: his arms turned about his shoulders' line (back and up, then down and through), his back twisting
## with it, on top of where they were when he started; his walk held still meanwhile.
func _jared_pose(u: float, done: bool) -> void:
	var j := person as SkJared
	var sk := j.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if done:
		for i in _jared_from:
			sk.set_bone_pose_rotation(i, _jared_from[i])
		if j.anim:
			j.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		return
	var x := 0.0
	var twist := 0.0
	if u < 0.3:
		x = lerpf(0.0, -1.7, smoothstep(0.0, 0.3, u))
		twist = -0.45 * smoothstep(0.0, 0.3, u)
	elif u < 0.55:
		x = lerpf(-1.7, 1.5, smoothstep(0.3, 0.55, u))
		twist = lerpf(-0.45, 0.45, smoothstep(0.3, 0.55, u))
	else:
		x = lerpf(1.5, 0.0, smoothstep(0.7, 1.0, u))
		twist = 0.45 * (1.0 - smoothstep(0.7, 1.0, u))
	var side := person.global_basis.x.normalized()
	for i in _jared_from:
		var name_ := sk.get_bone_name(i)
		var axis := Vector3.UP if name_ == "Spine1" else side
		var angle := twist if name_ == "Spine1" else x
		# (that axis, in the space the bone turns in: its parent's)
		var parent := sk.get_bone_parent(i)
		var space := (sk.global_basis * sk.get_bone_global_pose(parent).basis).orthonormalized()
		var local := (space.inverse() * axis).normalized()
		sk.set_bone_pose_rotation(i, Quaternion(local, angle) * (_jared_from[i] as Quaternion))

## A bat: a tapered stick of wood with a knob on the end and tape on the handle, from the hand down (its own units:
## inside a person, who's scaled down, it comes out about 80 cm).
static func bat() -> Node3D:
	var root := Node3D.new()
	root.name = "Bat"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#c4904f")
	wood.roughness = 0.6
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color("#262321")
	tape.roughness = 0.9
	for part in [[0.035, 0.07, 0.8, -0.62, wood], [0.036, 0.036, 0.26, 0.0, tape], [0.05, 0.05, 0.04, 0.14, tape]]:
		var c := CylinderMesh.new()
		c.top_radius = part[0]
		c.bottom_radius = part[1]
		c.height = part[2]
		c.radial_segments = 10
		c.rings = 1
		c.material = part[4]
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.position.y = part[3]
		root.add_child(mi)
	return root

## The hit-stop (the owner's pick): the moment the bat lands everything freezes, near enough, for hit_stop_len s (real
## time), so the hit reads; then it carries on at whatever speed it was going.
static var hit_stop_len := 0.07
var _bat_carry := 0.0

func _hit_stop() -> void:
	var was := Engine.time_scale
	Engine.time_scale = was * 0.03
	await get_tree().create_timer(hit_stop_len, true, false, true).timeout
	Engine.time_scale = was

func _bat_swing(dt: float) -> void:
	if _bat_t < 0.0:
		return
	# (once it's caught something the bat slows right down, carrying it, for as long as the bird's neck is bending)
	_bat_t += dt * (0.2 if _bat_carry > 0.0 else 1.0)
	_bat_carry -= dt
	var u := _bat_t / BAT_TIME
	if person is SkJared:
		_jared_pose(minf(u, 1.0), u >= 1.0)
	# the bat itself has to catch it, with its thick end (the owner: so you see it connect): where the bat is now, and
	# the way it swept since the last step (it moves fast), against a bird's neck and body
	var bx := _bat_root.global_transform if _bat_root else Transform3D.IDENTITY
	var seg := [bx * Vector3(0, -0.5, 0), bx * Vector3(0, -1.02, 0)]
	if not _bat_hit and u > 0.3 and u < 0.75 and not _bat_was.is_empty():
		for n in get_tree().get_nodes_in_group("ibis"):
			var ib := n as SkIbis
			for p in [ib.neck_point(), ib.global_position + Vector3(0, 0.3, 0)]:
				for s in 6:
					var k := float(s) / 5.0
					var a: Vector3 = (_bat_was[0] as Vector3).lerp(seg[0], k)
					var b: Vector3 = (_bat_was[1] as Vector3).lerp(seg[1], k)
					var q := Geometry3D.get_closest_point_to_segment(p, a, b)
					if q.distance_to(p) < 0.22:
						# where on the bat, and how fast that bit of it was going (the way it pushes the bird)
						var along := clampf((q - a).dot(b - a) / maxf(0.0001, (b - a).length_squared()), 0.0, 1.0)
						var was: Vector3 = (_bat_was[0] as Vector3).lerp(_bat_was[1], along)
						var now: Vector3 = (seg[0] as Vector3).lerp(seg[1], along)
						ib.hit(global_position, q, (now - was) / maxf(0.0001, dt))
						_bat_hit = true
						break
				if _bat_hit:
					break
			if _bat_hit:
				break
		if _bat_hit:
			if _thud == null:
				_thud = AudioStreamPlayer3D.new()
				_thud.stream = SkSounds.whack()
				add_child(_thud)
			_thud.play()
			_bat_carry = SkIbis.BEND
			if cam:
				cam.kick(0.05)
			_hit_stop()
	_bat_was = seg
	if u >= 1.0:
		_bat_t = -1.0
		_bat_was = []
		_bat_root = null
		if _bat:
			_bat.queue_free()
			_bat = null

## The swing's pose (u: 0 .. 1 through it): both arms back and up, then down and through, the shoulders turning with it.
func _bat_pose(body: Node3D, arm_l: Node3D, arm_r: Node3D) -> void:
	var u := _bat_t / BAT_TIME
	var x := 0.0
	var twist := 0.0
	if u < 0.3:
		x = lerpf(0.0, -1.7, smoothstep(0.0, 0.3, u))           # back and up
		twist = -0.45 * smoothstep(0.0, 0.3, u)
	elif u < 0.55:
		x = lerpf(-1.7, 1.5, smoothstep(0.3, 0.55, u))          # down, low through the front, and up
		twist = lerpf(-0.45, 0.45, smoothstep(0.3, 0.55, u))
	else:
		x = lerpf(1.5, 0.0, smoothstep(0.7, 1.0, u))            # and back down
		twist = 0.45 * (1.0 - smoothstep(0.7, 1.0, u))
	arm_r.rotation = Vector3(x, 0, -0.3)
	arm_l.rotation = Vector3(x, 0, 0.3)
	arm_r.get_node("Fore").rotation = Vector3(0.15, 0, 0)
	arm_l.get_node("Fore").rotation = Vector3(0.15, 0, 0)
	body.rotation.y = twist
	body.rotation.x = lerpf(body.rotation.x, -0.15, 0.3)

## Shove someone (SkCrowd calls this when you walk into them): the arms snap out, hold, then ease back.
func shove() -> void:
	_shove = SHOVE

func _ready() -> void:
	collision_layer = SkData.LAYER_PLAYERS
	collision_mask = SkData.LAYER_WORLD
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.9
	cs.shape = cap
	cs.position.y = 0.95
	add_child(cs)

## Take over a person: move here to where they stand, and carry their model.
func take(p: Node3D) -> void:
	global_position = p.global_position
	var yaw := p.global_rotation.y
	if p.get_parent():
		p.get_parent().remove_child(p)
	add_child(p)
	p.position = Vector3.ZERO
	p.rotation = Vector3(0, yaw, 0)
	person = p
	_set_solid(p, false)
	velocity = Vector3.ZERO
	reset_physics_interpolation()

## Let go of the person, leaving them standing where they are (under new_parent).
func release(new_parent: Node) -> Node3D:
	var p := person
	if p == null:
		return null
	var xf := p.global_transform
	remove_child(p)
	new_parent.add_child(p)
	p.global_transform = xf
	_still(p)
	_set_solid(p, true)
	person = null
	return p

static func _set_solid(p: Node3D, on: bool) -> void:
	var s := p.get_node_or_null("Solid")
	if s:
		(s.get_child(0) as CollisionShape3D).disabled = not on

func _input_dir() -> Vector2:
	if not controls_enabled:
		return Vector2.ZERO
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	# the touch stick (and a pad) come in as the move_ actions
	var act := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if act.length() > v.length():
		return act
	return v.normalized()

func _physics_process(dt: float) -> void:
	var inp := _input_dir()
	var yaw := cam.yaw if cam else 0.0
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := (right * inp.x - fwd * inp.y).normalized()
	var run := Input.is_physical_key_pressed(KEY_SHIFT)
	var target := dir * ((SkJared.RUN if run else SkJared.WALK) if person is SkJared else (RUN if run else WALK))
	if lead:
		target = _keep_up()
		dir = target.normalized()
	if _bat_t >= 0.0:
		target *= 0.35                                  # (you slow right down to swing)
	var h := Vector3(velocity.x, 0, velocity.z)
	h = h.move_toward(target, (30.0 if dir != Vector3.ZERO else 22.0) * dt)
	velocity.x = h.x
	velocity.z = h.z
	if is_on_floor():
		if controls_enabled and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP
			if person is SkJared:
				(person as SkJared).jump()
	else:
		velocity.y -= GRAVITY * dt
	var before := global_position
	move_and_slide()
	# step up kerbs, wheel stops and the like: if a wall stopped us, try going over it
	if dir != Vector3.ZERO and is_on_wall() and is_on_floor():
		var moved := (global_position - before).length()
		if moved < h.length() * dt * 0.5:
			var xf := global_transform
			var ahead := dir * 0.25
			if not test_move(xf, Vector3.UP * STEP):
				var up := xf.translated(Vector3.UP * STEP)
				if not test_move(up, ahead):
					global_position += Vector3.UP * STEP + ahead
					apply_floor_snap()
	_animate(dt, h.length(), dir)
	_bat_swing(dt)

func _animate(dt: float, speed: float, dir: Vector3) -> void:
	if person == null:
		return
	if dir != Vector3.ZERO:
		var want := atan2(-dir.x, -dir.z)
		person.rotation.y = lerp_angle(person.rotation.y, want, 1.0 - exp(-dt * 12.0))
	var moving := speed > 0.3 and is_on_floor()
	if person is SkJared:                              # (SkJared walks by his own animation)
		(person as SkJared).animate(speed, moving)
		return
	_swing = move_toward(_swing, 1.0 if moving else 0.0, dt * 6.0)
	_phase += dt * speed * 2.6
	var s := sin(_phase) * _swing
	var amp := 0.55 if speed < 4.5 else 0.8
	var body: Node3D = person.get_node("Body")
	body.get_node("LegL").rotation.x = s * amp
	body.get_node("LegR").rotation.x = -s * amp
	body.position.y = absf(sin(_phase)) * 0.06 * _swing
	if _bat_t >= 0.0:
		_bat_pose(body, body.get_node("ArmL"), body.get_node("ArmR"))
		return
	body.rotation.y = lerpf(body.rotation.y, 0.0, 0.3)
	var carrying := person.has_meta("carry")         # Jaymie keeps the tablet up as she walks
	var arm_l: Node3D = body.get_node("ArmL")
	var arm_r: Node3D = body.get_node("ArmR")
	if carrying:
		var c: Array = person.get_meta("carry")
		arm_l.rotation = arm_l.rotation.lerp(c[0], 0.2)
		arm_l.get_node("Fore").rotation = arm_l.get_node("Fore").rotation.lerp(c[1], 0.2)
	else:
		arm_l.rotation = arm_l.rotation.lerp(Vector3(s * amp * 0.8, 0, 0), 0.3)
		arm_l.get_node("Fore").rotation = arm_l.get_node("Fore").rotation.lerp(Vector3(0.25 * _swing, 0, 0), 0.3)
	if person.has_meta("carry_r"):                   # Chloe keeps filming as she walks
		arm_r.rotation = arm_r.rotation.lerp(SkPeople.POSES.filming[2], 0.2)
		arm_r.get_node("Fore").rotation = arm_r.get_node("Fore").rotation.lerp(SkPeople.POSES.filming[3], 0.2)
		return
	arm_r.rotation = arm_r.rotation.lerp(Vector3(-s * amp * 0.8, 0, 0), 0.3)
	arm_r.get_node("Fore").rotation = arm_r.get_node("Fore").rotation.lerp(Vector3(0.25 * _swing, 0, 0), 0.3)
	# a shove: snap the arms out fast, hold them there a moment, then let the walk take them back
	if _shove > 0.0:
		_shove -= dt
		var k := 0.75 if _shove > SHOVE * 0.45 else 0.25
		for side in [[arm_l, SHOVE_L], [arm_r, SHOVE_R]]:
			var arm: Node3D = side[0]
			var pose: Array = side[1]
			arm.rotation = arm.rotation.lerp(pose[0], k)
			arm.get_node("Fore").rotation = arm.get_node("Fore").rotation.lerp(pose[1], k)
		body.rotation.x = lerpf(body.rotation.x, -0.12, k)       # (leaning into it)
	else:
		body.rotation.x = lerpf(body.rotation.x, 0.0, 0.2)

## Stand someone still (legs together, body level), keeping their arm pose.
static func _still(p: Node3D) -> void:
	if not p.has_node("Body"):
		return
	var body: Node3D = p.get_node("Body")
	body.position.y = 0.0
	body.get_node("LegL").rotation = Vector3.ZERO
	body.get_node("LegR").rotation = Vector3.ZERO
