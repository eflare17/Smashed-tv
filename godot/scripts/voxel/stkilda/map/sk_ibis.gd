# (Copied from stkilda-godot scripts/world/ibis.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkIbis
extends CharacterBody3D
## An Australian white ibis (a bin chicken), from the model the owner sent (reference/ibis.stl, cut down to 6,000
## smooth triangles by tools/stl_to_ibis.gd; its round stand left off). It's coloured here as the real ones are: a
## white body, the bare head and neck black, the long curved bill and the legs black, dark plumes over the tail. It's
## skinned onto a little skeleton (body, neck, a leg each), so it walks and pecks with no gaps where it bends.
##
## A few wander round Luna Park (the owner's pick, 2026-10-31): walking from spot to spot and pecking at the ground.
## Come close on foot and one of them chases you, squawking, and pecks at your feet when it catches you; hit it with the
## bat (SkWalker.swing) and feathers pop out and it goes bouncing off like a ball, then staggers up and runs off (hit).
## Cartoon: no blood.

const HEIGHT := 0.72                    # m to the top of its head, standing
const S := HEIGHT / 144.0               # model units to metres (the model's 144 tall above its stand)
const FOOT := 8.0                       # (the model's feet stand this high, on top of its stand)
const WALK := 0.9
const CHASE := 3.6                      # (a bit faster than walking: you have to run to get away)
const FLEE := 5.0
const SPOT := 6.5                       # it chases you when you come this close
const GIVE_UP := 18.0                   # and stops when you're this far off
const GRAVITY := 14.0

enum { WANDER, PECK, CHASE_YOU, TUMBLE, DAZED, RUN_OFF, BENT }
const BEND := 0.05                      # s the bat bends its neck back before it's sent flying

## Only one chases you at once.
static var chaser: SkIbis = null

static var _mesh: ArrayMesh
static var _squawk: Array = []
static var _shriek: AudioStreamWAV

var player: SkWalker                      # who it chases (main's walker; only while you're on foot)
var keep_off := 0.75                    # (how close it comes when it catches you)
var crowd: SkCrowd                        # (where's open to walk to: the crowd's own spots in the park)
var model: Node3D
var skel: Skeleton3D
var state := WANDER
var _t := 0.0                           # time in this state
var _to := Vector3.INF                  # where it's walking to
var _from := Vector3.ZERO               # (what hit it: it runs away from there)
var _spin := Vector3.ZERO               # (the tumble: axis * speed)
var _bounces := 0                       # (bounces left in it)
var _squash := 0.0                      # (1 just landed .. 0)
var _rest := 0.0                        # (lying still this long)
var _yaw := 0.0                         # (the way it faces, getting up)
var _lying := Transform3D.IDENTITY
var _away := Vector3.ZERO               # (the way the bat's sending it)
var _whip := 0.0                        # (its neck bent back by the bat: 1 right back .. 0)
var _whip_axis := Vector3.RIGHT         # (and which way: in the model's own space)
var _whip_head := 0.0                   # (the head behind it, on a spring)
var _whip_v := 0.0
var _kink := 0.5                        # (where the bat caught its neck: 0 low .. 1 high)
var _phase := 0.0
var _peck := 0.0                        # 0 head up .. 1 bill on the ground
var _pecks := 0
var _voice: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()

func _init(seed_: int = 0) -> void:
	_rng.seed = seed_
	name = "Ibis"
	collision_layer = 0
	collision_mask = SkData.LAYER_WORLD
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.18
	cap.height = 0.6
	cs.shape = cap
	cs.position.y = 0.3
	add_child(cs)
	model = SkIbis.build()
	add_child(model)
	skel = model.get_node("Skeleton") as Skeleton3D
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 6.0
	_voice.max_distance = 40.0
	add_child(_voice)
	add_to_group("ibis")

## The ibis on its own (no behaviour): a skeleton ("Skeleton": bones Root, Body, Neck, LegL, LegR, Head) with the skinned
## body on it, facing -z like the cast, feet at the origin.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "IbisModel"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	root.add_child(sk)
	for b in [["Root", -1, Vector3.ZERO], ["Body", 0, _g(Vector3(-14, 0, 48))], ["Neck", 1, _g(Vector3(12, 0, 98))],
			["LegL", 0, _g(Vector3(-20, 5, 46))], ["LegR", 0, _g(Vector3(-20, -5, 46))], ["Head", 2, _g(Vector3(16, 0, 118))]]:
		var i := sk.add_bone(b[0])
		sk.set_bone_parent(i, b[1])
		var at: Vector3 = b[2]
		if int(b[1]) >= 0:
			at -= sk.get_bone_global_rest(b[1]).origin
		sk.set_bone_rest(i, Transform3D(Basis(), at))
	sk.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _model_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mi.material_override = mat
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()
	return root

## A point on the model (its own units: Z up, the bill along +x, standing on its stand) to the game's (metres, Y up,
## the bill along -z, feet at 0).
static func _g(p: Vector3) -> Vector3:
	return Vector3(-p.y, p.z - FOOT, -p.x) * S

static func _model_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var src: ArrayMesh = load("res://assets/ibis/ibis_simple.res")
	var a := src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	# leave off its stand (the triangles down there; the feet start just above it)
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if (v[idx[t]].z + v[idx[t + 1]].z + v[idx[t + 2]].z) / 3.0 > 7.2:
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var white := Color("#ebe8e0")
	var black := Color("#1d1b1b")
	for i in v.size():
		var p := v[i]
		pos.append(_g(p))
		nrm.append(Vector3(-nm[i].y, nm[i].z, -nm[i].x))
		# colours: the bare black head and neck (and the bill), black legs, dark plumes over the tail, white the rest
		var c := white.lerp(Color("#d6d0c4"), clampf((62.0 - p.z) / 14.0, 0.0, 1.0))   # (a grubbier belly)
		c = c.lerp(Color("#3a3634"), smoothstep(-46.0, -62.0, p.x) * smoothstep(84.0, 74.0, p.z))
		c = c.lerp(black, smoothstep(98.0, 106.0, p.z) * smoothstep(-2.0, 6.0, p.x))
		c = c.lerp(Color("#2b2726"), smoothstep(46.0, 42.0, p.z))
		col.append(c)
		# weights: the legs up to the thighs, the neck from where it leaves the body (its top half and the head and bill
		# on a joint of their own, so a hit can kink it partway), the body the rest
		var leg := smoothstep(50.0, 42.0, p.z)
		var neck := smoothstep(90.0, 102.0, p.z) * smoothstep(-8.0, 6.0, p.x)
		var head := maxf(smoothstep(112.0, 126.0, p.z), smoothstep(22.0, 32.0, p.x) * smoothstep(99.0, 103.0, p.z))
		bones.append_array([1, 2, 5, 3 if p.y > 0.0 else 4])
		weights.append_array([(1.0 - leg) * (1.0 - neck), (1.0 - leg) * neck * (1.0 - head), (1.0 - leg) * neck * head, leg])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = keep
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _mesh

# ================================================================ what it does

func _ready() -> void:
	if _squawk.is_empty():
		for p in [0.9, 1.0, 1.12]:
			_squawk.append(SkSounds.squawk(p))
		_shriek = SkSounds.squawk(1.0, true)
	_phase = _rng.randf() * TAU
	_t = -_rng.randf() * 3.0

func _say(hurt := false) -> void:
	_voice.stream = _shriek if hurt else _squawk[_rng.randi() % _squawk.size()]
	_voice.play()

func _go(s: int) -> void:
	state = s
	_t = 0.0

## Hit by the bat, swung from `from` (the owner's picks, 2026-10-31): feathers pop out (3 to 6), and it's knocked away
## bouncing along like a ball, spinning: a different hit every time (how hard, which way it goes off, how high, how
## many bounces, the spin). Then it staggers to its feet and runs off.
##
## So you see the bat land (the owner's picks): the bat carries its neck with it for a moment (BENT), bending it the
## way the bat's going (`push`) and kinking it where the bat caught it (`at`: low on the neck bends it from the base,
## high up bends it from partway), the head whipping round a beat behind; a white puff where the bat lands (SkImpactPuff),
## the feathers bursting from there, and its body squashed by the blow.
func hit(from: Vector3, at := Vector3.INF, push := Vector3.ZERO) -> void:
	if state == TUMBLE or state == BENT:
		return
	if chaser == self:
		chaser = null
	_from = from
	if at == Vector3.INF:
		at = neck_point()
	var away := push if push.length() > 0.1 else global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -model.global_basis.z
	_away = away.rotated(Vector3.UP, _rng.randf_range(-0.3, 0.3))
	# first the bat bends its neck right back (BEND), then it goes (_launch)
	var local := model.global_basis.orthonormalized().inverse() * away
	local.y = 0.0
	_whip_axis = Vector3.UP.cross(local.normalized()).normalized() if local.length() > 0.01 else Vector3.RIGHT
	var lo := skel.global_transform * skel.get_bone_global_pose(2).origin
	var hi := skel.global_transform * skel.get_bone_global_pose(5).origin
	_kink = clampf((at.y - lo.y) / maxf(0.01, hi.y - lo.y), 0.0, 1.0)
	_whip = 0.0
	_whip_head = 0.0
	_whip_v = 0.0
	_squash = 1.0
	velocity = Vector3.ZERO
	SkImpactPuff.at_point(get_parent(), at, push if push.length() > 0.1 else away, _rng)
	SkFeather.burst(get_parent(), at, away, _rng.randi_range(3, 6), global_position.y, _rng)
	_say(true)
	_go(BENT)

func _launch() -> void:
	velocity = _away * _rng.randf_range(4.5, 7.5) + Vector3.UP * _rng.randf_range(4.0, 6.5)
	var tip := _away.cross(Vector3.UP).normalized()
	_spin = tip * -_rng.randf_range(9.0, 18.0) + Vector3.UP * _rng.randf_range(-8.0, 8.0)
	_bounces = _rng.randi_range(2, 4)
	_squash = 0.0
	_go(TUMBLE)

## Partway up its neck, where the bat catches it (world space).
func neck_point() -> Vector3:
	return skel.global_transform * (skel.get_bone_global_pose(2) * Vector3(0, 0.08, -0.04))

## Its neck bent back by the bat (and its body a little), kinked where it was caught, the head whipping round behind
## (a spring: it lags, then overshoots), easing straight again as it flies.
func _bend(dt: float, squash := true) -> void:
	_whip_v += ((_whip - _whip_head) * 420.0 - _whip_v * 16.0) * dt
	_whip_head += _whip_v * dt
	skel.set_bone_pose_rotation(1, Quaternion(_whip_axis, 0.3 * _whip))
	skel.set_bone_pose_rotation(2, Quaternion(_whip_axis, lerpf(1.1, 0.35, _kink) * _whip))
	skel.set_bone_pose_rotation(5, Quaternion(_whip_axis, lerpf(0.4, 1.2, _kink) * _whip_head))
	if not squash:
		return
	# (squashed by the blow)
	_squash = move_toward(_squash, 0.0, dt * 5.0)
	skel.scale = Vector3(1.0 + 0.08 * _squash, 1.0 - 0.1 * _squash, 1.0 + 0.08 * _squash)

func _physics_process(dt: float) -> void:
	_t += dt
	var want := Vector3.ZERO                 # (where it wants to go: speed included)
	match state:
		WANDER:
			if _t < 0.0:
				pass
			elif _to == Vector3.INF and crowd and crowd.ready_:
				_to = crowd.next_spot_near(global_position, 12.0, _rng)
			elif _to != Vector3.INF:
				var d := _to - global_position
				d.y = 0.0
				if d.length() < 0.3 or _t > 15.0:
					_to = Vector3.INF
					_pecks = _rng.randi_range(2, 5)
					_go(PECK)
				else:
					want = d.normalized() * WALK
			_look_for_you()
		PECK:
			if _t > 0.9:
				_pecks -= 1
				_t = 0.0
				if _pecks <= 0:
					_go(WANDER)
					_t = -_rng.randf_range(0.5, 3.0)
			_look_for_you()
		CHASE_YOU:
			var you := _you()
			if you == Vector3.INF or _t > 14.0 or global_position.distance_to(you) > GIVE_UP:
				chaser = null
				_go(WANDER)
				_t = -2.0
			else:
				var d := you - global_position
				d.y = 0.0
				if d.length() > keep_off:
					want = d.normalized() * CHASE
				else:
					_face(d)                     # (caught you: stands and pecks at your feet)
				if fmod(_t, 2.2) < dt:
					_say()
		BENT:
			_whip = smoothstep(0.0, BEND, _t)
			_bend(dt)
			if _t >= BEND:
				_launch()
			return
		TUMBLE:
			_whip = move_toward(_whip, 0.0, dt * 2.0)
			_bend(dt, false)
			# (spinning round its middle, not its feet)
			if _spin.length() > 0.01:
				var mid := Vector3(0, HEIGHT * 0.45, 0)
				var turn := Basis(_spin.normalized(), _spin.length() * dt)
				model.transform = Transform3D((turn * model.transform.basis).orthonormalized(), mid + turn * (model.position - mid))
			# (squashed flat a moment each time it lands, like a ball)
			_squash = move_toward(_squash, 0.0, dt * 6.0)
			skel.scale = Vector3(1.0 + 0.35 * _squash, 1.0 - 0.45 * _squash, 1.0 + 0.35 * _squash)
			var falling := velocity.y
			velocity.y -= GRAVITY * dt
			move_and_slide()
			if is_on_floor() and _t > 0.1:
				if _bounces > 0 and falling < -1.5:
					# a bounce: up again, lower each time, a bit slower, the spin kicked about
					_bounces -= 1
					_squash = 1.0
					velocity.y = -falling * _rng.randf_range(0.55, 0.75)
					velocity.x *= 0.8
					velocity.z *= 0.8
					_spin = _spin.rotated(Vector3.UP, _rng.randf_range(-1.0, 1.0)) * 0.8
				else:
					_bounces = 0
					_spin = _spin.move_toward(Vector3.ZERO, 12.0 * dt)
					velocity.x = move_toward(velocity.x, 0.0, 9.0 * dt)
					velocity.z = move_toward(velocity.z, 0.0, 9.0 * dt)
					_rest += dt
					if _rest > 0.5:
						var fwd := -model.transform.basis.z
						_yaw = atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length() > 0.1 else model.rotation.y
						_lying = model.transform.orthonormalized()
						skel.scale = Vector3.ONE
						_rest = 0.0
						_go(DAZED)
			return
		DAZED:
			# (back on its feet, wobbling)
			var up := Transform3D(Basis.from_euler(Vector3(0, _yaw, sin(_t * 9.0) * 0.2 * (1.0 - _t))), Vector3.ZERO)
			model.transform = _lying.interpolate_with(up, minf(1.0, _t / 0.3))
			if _t > 1.0:
				model.transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3.ZERO)
				_say()
				_go(RUN_OFF)
		RUN_OFF:
			var d := global_position - _from
			d.y = 0.0
			want = (d.normalized().rotated(Vector3.UP, sin(_t * 5.0) * 0.5)) * FLEE
			if _t > 4.0:
				_go(WANDER)
				_t = -2.0
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(want, 12.0 * dt)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	if want.length() > 0.1:
		_face(want)
	_animate(dt, h.length())

func _you() -> Vector3:
	if player == null or not player.visible or player.process_mode == Node.PROCESS_MODE_DISABLED or player.person == null:
		return Vector3.INF
	return player.global_position

func _look_for_you() -> void:
	if chaser != null and is_instance_valid(chaser):
		return
	var you := _you()
	if you != Vector3.INF and global_position.distance_to(you) < SPOT:
		chaser = self
		_say()
		_go(CHASE_YOU)

func _face(d: Vector3) -> void:
	if d.length() < 0.01:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-d.x, -d.z), 0.2)

## Legs swing as it walks, its head bobs; pecking tips it forward with its bill to the ground.
func _animate(dt: float, speed: float) -> void:
	var moving := speed > 0.15
	_phase += dt * (3.0 + speed * 4.5) if moving else 0.0
	var swing := sin(_phase) * clampf(speed / 1.5, 0.0, 1.0) * (0.55 if speed < 2.0 else 0.8)
	var pecking := state == PECK or (state == CHASE_YOU and speed < 0.3)
	var target := 0.0
	if pecking:
		var u := fmod(_t, 0.9) / 0.9 if state == PECK else fmod(_t, 0.6) / 0.6
		target = 1.0 if u > 0.25 and u < 0.6 else 0.0
	_peck = move_toward(_peck, target, dt * 6.0)
	var bob := sin(_phase * 2.0) * 0.12 * clampf(speed, 0.0, 1.0)
	var lean := -0.25 if speed > 2.5 else 0.0          # (running: neck stretched out in front)
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, -0.55 * _peck + lean * 0.4))
	skel.set_bone_pose_rotation(2, Quaternion(Vector3.RIGHT, -1.0 * _peck + bob + lean))
	skel.set_bone_pose_rotation(3, Quaternion(Vector3.RIGHT, swing))
	skel.set_bone_pose_rotation(4, Quaternion(Vector3.RIGHT, -swing))
	skel.set_bone_pose_rotation(5, Quaternion.IDENTITY)
