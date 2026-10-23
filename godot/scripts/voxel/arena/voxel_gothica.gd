class_name VoxelGothica
extends Node3D
## Gothica in the house (the owner, 23 Oct: "get the character Gothica brought into the game"). She lives in the
## bedroom and the games room: strolls between the places she likes (the mirror, the rug, the end of the beds, by the
## wardrobe; in the games room behind the couch and either side of the TV), stands about a while at each (breathing,
## shifting her weight, looking round), now and then goes through to the other room along the arena's south wall.
## E at her: a hop and a word, and she follows you (walking, or running to keep up when you're well ahead) round the
## house; out into the fight she won't go, she waits in the bedroom doorway. E again: she stays where she is. Walk
## into her and she's bumped. Her body: VoxelBody (the "gothica" model: her chest sculpted round), posed here
## (a sway in her hips walking, her chest the other way), with VoxelJiggle answering everything she does. Each game
## has its own (co-op: not sent; she's company, not part of the fight). Owned by the voxel session.

const WALK := 1.35              # metres a second
const RUN := 3.4
const REACH := 2.2              # E from this far
## Where she goes (world x, z), and which way she faces standing there (radians, 0 = +z; null: whichever).
const NODES := {
	"b_door": [Vector2(-2.2, 23.4), null], "b_mid": [Vector2(-2.0, 26.0), null],
	"b_mirror": [Vector2(-1.1, 28.95), 0.0], "b_rug": [Vector2(0.6, 27.2), PI * 0.8],
	"b_beds": [Vector2(2.4, 27.6), PI], "b_ward": [Vector2(-3.95, 26.7), 0.3],
	"a_bed": [Vector2(-2.2, 20.7), null], "a_mid": [Vector2(-6.0, 20.7), null], "a_games": [Vector2(-9.7, 20.7), null],
	"g_door": [Vector2(-9.7, 23.4), null], "g_front": [Vector2(-9.7, 24.7), 0.0],
	"g_left": [Vector2(-13.0, 24.2), null], "g_left_back": [Vector2(-13.0, 28.4), PI * 0.5],
	"g_right": [Vector2(-6.3, 24.2), null], "g_right_back": [Vector2(-6.3, 28.4), -PI * 0.5],
}
const EDGES := [["b_door", "b_mid"], ["b_mid", "b_mirror"], ["b_mid", "b_rug"], ["b_rug", "b_beds"], ["b_mid", "b_ward"],
	["b_rug", "b_mirror"], ["b_door", "a_bed"], ["a_bed", "a_mid"], ["a_mid", "a_games"], ["a_games", "g_door"],
	["g_door", "g_front"], ["g_front", "g_left"], ["g_front", "g_right"], ["g_left", "g_left_back"],
	["g_right", "g_right_back"]]
const SPOTS := ["b_mirror", "b_rug", "b_beds", "b_ward", "g_front", "g_left_back", "g_right_back"]
const SAY_FOLLOW := ["Lead the way.", "Right behind you.", "Fine. But I'm not cleaning up.", "Where are we going?",
	"Don't walk too fast."]
const SAY_STAY := ["I'll be here.", "Go on, I'll wait.", "Don't get yourself killed.", "I'm staying put."]
const SAY_WAIT := ["Not out there.", "I'll wait here.", "Have fun getting stabbed."]

var arena: Node3D
var body: VoxelBody
var jig: VoxelJiggle
var following := false
var path: Array = []            # node names still to walk to
var at_node := "b_mirror"
var idle_t := 3.0
var face := 0.0                 # the way to face while standing (radians)
var speed := 0.0
var hop_t := -1.0               # a hop under way: its time (s), < 0 none
var _say: Label3D
var _say_t := 0.0
var _t := 0.0
var _step_side := 0.0
var _adj := {}
var _waiting := false
var _hy := 0.0                  # the hop: height, speed up
var _hv := 0.0
var _landing := false
var goal := Vector3.INF         # somewhere to go straight to (cut scenes, tests), or INF
var goal_run := false

func setup(arena_: Node3D) -> void:
	arena = arena_
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for e in EDGES:
		for k in 2:
			if not _adj.has(e[k]):
				_adj[e[k]] = []
			_adj[e[k]].append(e[1 - k])
	body = VoxelBody.new()
	add_child(body)
	body.setup("gothica", 0.0125, 1, arena._mat)
	body.alive = true
	var p: Vector2 = NODES[at_node][0]
	body.global_position = Vector3(p.x, 0.0, p.y)
	face = float(NODES[at_node][1])
	body.yaw = face
	jig = VoxelJiggle.new()
	jig.setup(body)
	_say = Label3D.new()
	_say.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_say.font_size = 40
	_say.pixel_size = 0.0035
	_say.outline_size = 10
	_say.modulate = Color(0.92, 0.82, 1.0)
	_say.no_depth_test = true
	_say.visible = false
	add_child(_say)

## Whether she's what you're looking at, near enough for E.
func pick(eye: Vector3, dir: Vector3) -> bool:
	var mid := body.global_position + Vector3(0, 1.0, 0)
	var to := mid - eye
	var d := to.length()
	return d < REACH and to.normalized().dot(dir) > 0.82 - 0.25 * (1.0 - d / REACH)

func line() -> String:
	return "E  Gothica: %s" % ("stay here" if following else "come with me")

## E: a hop, a word, and she follows (or stays).
func interact() -> void:
	following = not following
	_waiting = false
	hop_t = 0.0
	say((SAY_FOLLOW if following else SAY_STAY).pick_random())
	if not following:
		path.clear()
		idle_t = randf_range(6.0, 12.0)
		face = _yaw_to(arena.player.global_position)

func say(t: String) -> void:
	_say.text = t
	_say.visible = true
	_say_t = 2.8

func _yaw_to(p: Vector3) -> float:
	var d := p - body.global_position
	return atan2(d.x, d.z)

func _process(dt: float) -> void:
	if body == null or arena == null:
		return
	_t += dt
	_brain(dt)
	_move(dt)
	_pose(dt)
	jig.step(dt)
	_say_t -= dt
	_say.visible = _say_t > 0.0
	_say.global_position = body.global_position + Vector3(0, 2.0, 0)
	_say.modulate.a = clampf(_say_t / 0.5, 0.0, 1.0)

# ---------------------------------------------------------------- where to go

func _nearest(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for n in NODES:
		var q: Vector2 = NODES[n][0]
		var d := Vector2(p.x, p.z).distance_squared_to(q)
		if d < bd:
			bd = d
			best = n
	return best

# the nodes from a to b (not a itself), by the fewest steps
func _route(a: String, b: String) -> Array:
	if a == b:
		return [b]
	var prev := {a: ""}
	var q := [a]
	while not q.is_empty():
		var n: String = q.pop_front()
		if n == b:
			break
		for m in _adj.get(n, []):
			if not prev.has(m):
				prev[m] = n
				q.append(m)
	if not prev.has(b):
		return [b]
	var out := []
	var c := b
	while c != a:
		out.push_front(c)
		c = prev[c]
	return out

static func in_house(p: Vector3) -> bool:
	return VoxelBedroom.in_house(p) or VoxelGamesRoom.in_room(p) or (p.z > 19.5 and p.z < 22.6 and p.x > -11.5 and p.x < -0.8)

func _brain(dt: float) -> void:
	var me := body.global_position
	if following:
		var pp: Vector3 = arena.player.global_position
		if not in_house(pp):
			# out into the fight (or the yard): she waits in the bedroom doorway
			if not _waiting:
				_waiting = true
				say(SAY_WAIT.pick_random())
				path = _route(_nearest(me), "b_door")
			if path.is_empty():
				face = PI
			return
		_waiting = false
		var d := Vector2(pp.x - me.x, pp.z - me.z).length()
		var same := _nearest(pp) == _nearest(me) or d < 2.6
		if same:
			path.clear()
			if d > 1.3:
				path = ["@"]                              # (straight to you)
			else:
				face = _yaw_to(pp)
		elif path.is_empty() or path.back() != _nearest(pp):
			path = _route(_nearest(me), _nearest(pp))
		return
	if not path.is_empty():
		return
	idle_t -= dt
	if idle_t > 0.0:
		return
	# off somewhere else: mostly in the room she's in, sometimes the other one
	var here := at_node.begins_with("b_")
	var choices := SPOTS.filter(func(s): return s != at_node and (s.begins_with("b_") == here or randf() < 0.25))
	if choices.is_empty():
		choices = SPOTS.filter(func(s): return s != at_node)
	path = _route(_nearest(me), choices.pick_random())
	idle_t = randf_range(5.0, 11.0)

func _move(dt: float) -> void:
	var me := body.global_position
	var want := 0.0
	var target := me
	if path.is_empty() and goal != Vector3.INF and hop_t < 0.0:
		var to0 := Vector3(goal.x - me.x, 0.0, goal.z - me.z)
		var d0 := to0.length()
		want = RUN if goal_run else WALK
		if d0 < 0.1 + speed * 0.12:
			goal = Vector3.INF
			want = 0.0
		else:
			face = atan2(to0.x, to0.z)
			body.global_position = me + to0 / d0 * minf(d0, speed * dt)
	elif not path.is_empty() and hop_t < 0.0:
		var nm: String = path[0]
		if nm == "@":
			var pp: Vector3 = arena.player.global_position
			target = pp + (me - pp).normalized() * 1.1
		else:
			var q: Vector2 = NODES[nm][0]
			target = Vector3(q.x, 0.0, q.y)
		var to := Vector3(target.x - me.x, 0.0, target.z - me.z)
		var d := to.length()
		var far := 0.0
		if following:
			far = Vector2(arena.player.global_position.x - me.x, arena.player.global_position.z - me.z).length()
		want = RUN if far > 4.5 else WALK
		if d < 0.12 + speed * 0.08:
			path.pop_front()
			if nm != "@":
				at_node = nm
				if path.is_empty() and NODES[nm][1] != null:
					face = float(NODES[nm][1])
		else:
			face = atan2(to.x, to.z)
			var step := minf(d, speed * dt)
			body.global_position = me + to / d * step
	# speeding up and slowing down (not at once: the springs feel it)
	speed = move_toward(speed, want, dt * (5.0 if want > speed else 7.0))
	if want == 0.0 and speed > 0.0:
		body.global_position += Vector3(sin(body.yaw), 0, cos(body.yaw)) * speed * dt * 0.5
	body.yaw = lerp_angle(body.yaw, face, 1.0 - exp(-dt * (9.0 if speed > 0.3 else 4.0)))
	# bumped: walked into, she's shoved a little and steps back
	var pp2: Vector3 = arena.player.global_position
	var away := Vector3(me.x - pp2.x, 0.0, me.z - pp2.z)
	if away.length() < 0.45 and absf(pp2.y - me.y) < 1.0:
		var push := away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		body.global_position += push * (0.45 - away.length())
		var v: Vector3 = arena.player.velocity
		if v.length() > 0.8 and _say_t < 1.0:
			var local := body.global_transform.basis.inverse() * (v * 0.35)
			jig.kick(Vector3(local.x, 0.2, local.z))
	# a hop: down into a crouch, pushed up off her feet (a tenth of a second), flying, caught on bent knees and back up
	if hop_t >= 0.0:
		hop_t += dt
		var k := hop_t
		if k < 0.16:
			var u := k / 0.16
			_hy = -0.07 * u * u * (3.0 - 2.0 * u)
			_hv = 0.0
		elif k < 0.26:
			_hv += 19.0 * dt                              # (the push: about two g)
			_hy += _hv * dt
		elif not _landing:
			_hv -= 9.8 * dt
			_hy += _hv * dt
			if _hy <= 0.0 and _hv < 0.0:
				_landing = true
		else:
			# the knees take it: slowed to a stop over a few centimetres, then up again
			_hv += (-_hy * 170.0 - _hv * 19.0) * dt
			_hy += _hv * dt
			if k > 1.3:
				hop_t = -1.0
				_landing = false
				_hy = 0.0
				_hv = 0.0
	var y := _hy if hop_t >= 0.0 else 0.0
	body.global_position.y = y

# ---------------------------------------------------------------- her body

func _pose(dt: float) -> void:
	body.speed = speed
	body.anim_speed = VoxelAnim.MAX_SPEED * clampf(speed / RUN, 0.45, 1.0) if speed > 0.1 else -1.0
	var before := body.odo
	body.odo += speed * dt
	body.animate(dt, speed > 0.1)
	var sk := body.skeleton
	var md := body.model
	var hips := md.bone("hips")
	var chest := md.bone("chest")
	var head := md.bone("head")
	if speed > 0.1:
		# a sway in her hips as she goes, her chest turning against it; a heel coming down jolts her
		var cyc := body.cycle_m()
		var ph := body.odo / cyc * TAU
		var k := clampf(speed / WALK, 0.0, 1.0)
		var run := clampf((speed - WALK) / (RUN - WALK), 0.0, 1.0)
		sk.set_bone_pose_rotation(hips, sk.get_bone_pose_rotation(hips) * Quaternion.from_euler(Vector3(0, 0.07 * sin(ph) * k, 0.07 * sin(ph) * k)))
		sk.set_bone_pose_rotation(chest, sk.get_bone_pose_rotation(chest) * Quaternion.from_euler(Vector3(-0.04 * run, -0.05 * sin(ph) * k, -0.06 * sin(ph) * k)))
		var side := signf(cos(before / cyc * TAU))
		var now := signf(cos(ph))
		if side != now and side != 0.0:
			jig.kick(Vector3(0.0, -0.06 * (1.0 - run), 0.0))      # (a walk's heel: running, the stride's own bounce does it)
	else:
		# standing: breathing, her weight shifting from foot to foot now and then, looking about
		var shift := sin(_t * 0.45) * 0.5 + sin(_t * 0.17) * 0.5
		sk.set_bone_pose_rotation(hips, sk.get_bone_pose_rotation(hips) * Quaternion.from_euler(Vector3(0, 0.05 * shift, 0.05 * shift)))
		sk.set_bone_pose_rotation(chest, sk.get_bone_pose_rotation(chest) * Quaternion.from_euler(Vector3(0.025 * sin(_t * 1.4), -0.03 * shift, -0.045 * shift)))
		sk.set_bone_pose_rotation(head, sk.get_bone_pose_rotation(head) * Quaternion.from_euler(Vector3(0, 0.25 * sin(_t * 0.31), 0.04 * shift)))
	# her arms held a little out from her sides (her shape shows from the side; nothing through her skirt)
	for nm in ["arm_l", "arm_r"]:
		var ab := md.bone(nm)
		var sx2 := 1.0 if nm == "arm_l" else -1.0
		sk.set_bone_pose_rotation(ab, sk.get_bone_pose_rotation(ab) * Quaternion.from_euler(Vector3(0, 0, sx2 * 0.14)))
	if hop_t >= 0.0:
		# arms flung up over her head with the hop, elbows bent, down again as she lands
		var u := clampf(sin(clampf((hop_t - 0.05) / 0.75, 0.0, 1.0) * PI), 0.0, 1.0)
		for nm in ["arm_l", "arm_r"]:
			var sx := 1.0 if nm == "arm_l" else -1.0
			sk.set_bone_pose_rotation(md.bone(nm), Quaternion.from_euler(Vector3(-0.35 * u, 0, sx * 2.5 * u)))
			sk.set_bone_pose_rotation(md.bone("fore" + nm), Quaternion.from_euler(Vector3(0, 0, sx * 0.6 * u)))
