class_name VoxelAnim
extends RefCounted
## The block characters' animations, made in code: a pose (each bone's turn, and the whole body's lift and turn) from
## what the character is doing, the same things CharSprite is told (moving, odo, the roll, victory, the weapon and its
## actions) plus the lobby's poses. Owned by the voxel session. All static, so tests can ask for any pose.
##
## Bones (rig.json): hips (the root) > chest > head; chest > arm_r > forearm_r > hand_r (and _l); hips > thigh_l >
## shin_l > foot_l (and _r). Every bone's rest is unturned, so a turn is in the model's own axes: +x is the
## character's left, +y up, +z forward. A turn about +x by a positive angle swings a hanging limb backward (and
## leans the chest forward); about +z by a positive angle swings a hanging limb toward +x (the left arm outward).
##
## The state (a Dictionary, all optional): t (seconds, for breathing), moving, speed (HTML units a second), odo (HTML
## units walked), action ("", "roll", "tumble", "victory"), roll_t (0..1), weapon ("", "fists", "spud", "lob",
## "blaster", "shotgun", "launcher"), act ("", "reload", "throw", "charge", "pickup", "punch"), act_f (0..1 through
## it), recoil (0..1, just fired), gun (0 or 1: which blaster fired), pose (lobby: "sit", "lie", "bench", "legpress",
## "swim", "carry", "carried", "lift", "victory"), pose_f (0..1, a rep or a stroke), aim_pitch (radians, + up).
##
## The result: {rot: {bone: Quaternion}, pos: Vector3 (voxels: lifts the whole body), turn: Quaternion (the whole body,
## about pivot), pivot: Vector3 (voxels)}.

const CYCLE := 91.0          # HTML units for a whole run cycle (two steps): the sprites' 7 frames x T.runStride 13
const MAX_SPEED := 160.0     # HTML units a second where the run is at its fullest

static func q(x: float = 0.0, y: float = 0.0, z: float = 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))

static func pose(s: Dictionary) -> Dictionary:
	var t := float(s.get("t", 0.0))
	var rot := {}
	var out := {"rot": rot, "pos": Vector3.ZERO, "turn": Quaternion.IDENTITY, "pivot": Vector3(0, 50, 0)}
	var action := String(s.get("action", ""))
	var lobby := String(s.get("pose", ""))
	if lobby != "":
		_lobby(s, out, lobby, t)
		return out
	if action == "roll" or action == "tumble":
		_roll(s, out, action)
		return out
	if action == "victory":
		_victory(out, t)
		return out
	_base(s, out, t)
	_arms(s, out, t)
	return out

# the legs, hips, chest and head: standing (breathing) or walking / running by odo
static func _base(s: Dictionary, out: Dictionary, t: float) -> void:
	var rot: Dictionary = out.rot
	var moving := bool(s.get("moving", false))
	var speed := float(s.get("speed", 0.0))
	var amp := clampf(speed / MAX_SPEED, 0.45, 1.0) if moving else 0.0
	var ph := float(s.get("odo", 0.0)) / CYCLE * TAU
	var breathe := sin(t * 2.1)
	if amp <= 0.0:
		rot["chest"] = q(0.02 * breathe)
		rot["head"] = q(-0.015 * breathe, 0.06 * sin(t * 0.37), 0.0)
		rot["thigh_l"] = q(0.0, 0.0, 0.03)
		rot["thigh_r"] = q(0.0, 0.0, -0.03)
		rot["foot_l"] = q(0.0, 0.0, -0.03)
		rot["foot_r"] = q(0.0, 0.0, 0.03)
		out.pos = Vector3(0, 0.4 * breathe - 0.4, 0)
		return
	for side in [["l", 0.0], ["r", PI]]:
		var p: float = ph + side[1]
		var sw := sin(p)                               # + : this leg forward
		var thigh := -sw * 0.62 * amp
		var knee := (0.15 + 0.95 * maxf(0.0, cos(p - 0.35))) * amp   # bends as the leg comes through
		var foot := -(thigh + knee) * 0.7 + 0.12 * amp * maxf(0.0, -sw)
		rot["thigh_" + side[0]] = q(thigh)
		rot["shin_" + side[0]] = q(knee)
		rot["foot_" + side[0]] = q(foot)
	rot["hips"] = q(0.0, 0.10 * sin(ph) * amp, 0.0)
	rot["chest"] = q(0.10 * amp, -0.18 * sin(ph) * amp, 0.0)
	rot["head"] = q(-0.08 * amp, 0.08 * sin(ph) * amp, 0.0)
	out.pos = Vector3(0, -3.0 * amp + 3.2 * amp * absf(cos(ph)), 0)

# the arms, by the weapon held and what it's doing
static func _arms(s: Dictionary, out: Dictionary, t: float) -> void:
	var rot: Dictionary = out.rot
	var moving := bool(s.get("moving", false))
	var speed := float(s.get("speed", 0.0))
	var amp := clampf(speed / MAX_SPEED, 0.45, 1.0) if moving else 0.0
	var ph := float(s.get("odo", 0.0)) / CYCLE * TAU
	var swing := sin(ph) * amp
	var breathe := sin(t * 2.1)
	var weapon := String(s.get("weapon", ""))
	var act := String(s.get("act", ""))
	var f := float(s.get("act_f", 0.0))
	var recoil := float(s.get("recoil", 0.0))
	var aim := clampf(float(s.get("aim_pitch", 0.0)), -0.6, 0.6)
	# free arms swing with the opposite leg; big lats hold them out a little
	var free_l := [q(0.62 * swing, 0.0, 0.14 + 0.02 * breathe), q(-0.35 - 0.45 * amp), q()]
	var free_r := [q(-0.62 * swing, 0.0, -0.14 - 0.02 * breathe), q(-0.35 - 0.45 * amp), q()]
	var l: Array = free_l
	var r: Array = free_r
	match weapon:
		"blaster":
			# both guns out in front (alternate kicks)
			var kl := recoil if int(s.get("gun", 0)) == 1 else 0.0
			var kr := recoil if int(s.get("gun", 0)) == 0 else 0.0
			r = [q(-1.42 - aim + 0.25 * kr, 0.22, -0.05), q(-0.12 + 0.2 * kr), q(0.0)]
			l = [q(-1.42 - aim + 0.25 * kl, -0.22, 0.05), q(-0.12 + 0.2 * kl), q(0.0)]
		"spud", "lob":
			r = [q(-1.40 - aim + 0.3 * recoil, 0.12, -0.05), q(-0.10 + 0.25 * recoil), q()]
			if amp <= 0.0:
				l = [q(-0.05, 0.0, 0.22), q(-0.9), q()]
		"shotgun":
			r = [q(-0.45 - aim * 0.5 + 0.15 * recoil, 0.05, -0.12), q(-1.15 + 0.15 * recoil), q(0.0, 0.0, 0.0)]
			l = [q(-1.15 - aim + 0.15 * recoil, -0.55, 0.12), q(-0.55), q()]
		"launcher":
			r = [q(-0.55, 0.15, -0.35), q(-1.55), q()]
			l = [q(-1.05, -0.45, 0.25), q(-0.95), q()]
		"fists":
			var guard_r := [q(-0.55, 0.25, -0.1), q(-2.05), q()]
			var guard_l := [q(-0.55, -0.25, 0.1), q(-2.05), q()]
			r = guard_r
			l = guard_l
	match act:
		"reload":
			# both hands meet in front of the chest
			var k := sin(f * PI)
			r = [q(-0.75 - 0.2 * k, 0.45, -0.05), q(-1.45 + 0.2 * k), q()]
			l = [q(-0.65 - 0.15 * k, -0.55, 0.05), q(-1.55), q()]
		"charge":
			# the potato wound up behind the head
			r = [q(2.5, 0.0, -0.35), q(-1.2), q()]
			l = [q(-0.9, -0.2, 0.15), q(-0.3), q()]
			rot["chest"] = q(-0.12, 0.35, 0.0)
		"throw":
			var a := lerpf(2.5, -1.35, smoothstep(0.0, 0.6, f))
			r = [q(a, 0.0, -0.3 * (1.0 - f)), q(lerpf(-1.2, -0.1, smoothstep(0.0, 0.5, f))), q()]
			l = [q(-0.9 + 1.2 * f, -0.2, 0.15), q(-0.3), q()]
			rot["chest"] = q(-0.12 + 0.4 * smoothstep(0.1, 0.6, f), lerpf(0.35, -0.3, smoothstep(0.0, 0.6, f)), 0.0)
		"pickup":
			var k2 := sin(clampf(f, 0.0, 1.0) * PI)
			rot["chest"] = q(0.95 * k2)
			rot["head"] = q(-0.4 * k2)
			rot["thigh_l"] = q(-0.75 * k2)
			rot["thigh_r"] = q(-0.75 * k2)
			rot["shin_l"] = q(1.3 * k2)
			rot["shin_r"] = q(1.3 * k2)
			rot["foot_l"] = q(-0.55 * k2)
			rot["foot_r"] = q(-0.55 * k2)
			out.pos = Vector3(0, -14.0 * k2, -4.0 * k2)
			r = [q(-0.7 * k2, 0.0, -0.1), q(-0.2), q()]
		"punch":
			# a jab with the right (fists): out and back
			var k3 := sin(clampf(f, 0.0, 1.0) * PI)
			r = [q(lerpf(-0.55, -1.5, k3), lerpf(0.25, 0.1, k3), -0.1), q(lerpf(-2.05, -0.05, k3)), q()]
			rot["chest"] = q(0.05, -0.35 * k3, 0.0)
	rot["arm_r"] = r[0]
	rot["forearm_r"] = r[1]
	rot["hand_r"] = r[2]
	rot["arm_l"] = l[0]
	rot["forearm_l"] = l[1]
	rot["hand_l"] = l[2]

# the dive roll: tucked, turning forward once through it, with its hop; tumbling: turning by odo
static func _roll(s: Dictionary, out: Dictionary, action: String) -> void:
	var rot: Dictionary = out.rot
	var f := clampf(float(s.get("roll_t", 0.0)), 0.0, 1.0)
	var lift := 0.0
	var spin := 0.0
	var tuck := 1.0
	if action == "roll":
		var ph := CharFrames.roll_phase(f)
		lift = float(ph["lift"])
		spin = smoothstep(0.05, 0.85, f) * TAU
		tuck = sin(clampf(f / 0.9, 0.0, 1.0) * PI)
		tuck = clampf(tuck * 1.6, 0.0, 1.0)
	else:
		spin = float(s.get("odo", 0.0)) / 26.0 * TAU / 4.0
	rot["thigh_l"] = q(-1.7 * tuck)
	rot["thigh_r"] = q(-1.7 * tuck)
	rot["shin_l"] = q(2.1 * tuck)
	rot["shin_r"] = q(2.1 * tuck)
	rot["chest"] = q(0.55 * tuck)
	rot["head"] = q(0.45 * tuck)
	rot["arm_l"] = q(-1.0 * tuck, 0.0, 0.25)
	rot["arm_r"] = q(-1.0 * tuck, 0.0, -0.25)
	rot["forearm_l"] = q(-1.6 * tuck)
	rot["forearm_r"] = q(-1.6 * tuck)
	out.pivot = Vector3(0, 52, 2)
	out.turn = q(spin)
	# (HTML units to voxels: two voxels a unit)
	out.pos = Vector3(0, lift * 2.0 - 22.0 * tuck, 6.0 * tuck)

# the victory dance: a double-biceps flex, pumping, with little hops
static func _victory(out: Dictionary, t: float) -> void:
	var rot: Dictionary = out.rot
	var k := 0.5 + 0.5 * sin(t * 9.0)
	rot["arm_r"] = q(0.0, 0.0, -1.45 - 0.1 * k)
	rot["arm_l"] = q(0.0, 0.0, 1.45 + 0.1 * k)
	rot["forearm_r"] = q(0.0, 0.0, -1.55 - 0.35 * k)
	rot["forearm_l"] = q(0.0, 0.0, 1.55 + 0.35 * k)
	rot["chest"] = q(-0.08 * k)
	rot["head"] = q(-0.15 * k, 0.0, 0.0)
	rot["thigh_l"] = q(0.0, 0.0, 0.12)
	rot["thigh_r"] = q(0.0, 0.0, -0.12)
	out.pos = Vector3(0, 4.0 * absf(sin(t * 4.5)), 0)

# the lobby's poses (lobby life shows a picture of its own for these; the blocks do them in 3D)
static func _lobby(s: Dictionary, out: Dictionary, p: String, t: float) -> void:
	var rot: Dictionary = out.rot
	var f := float(s.get("pose_f", 0.0))
	var breathe := sin(t * 2.1)
	match p:
		"sit":
			rot["thigh_l"] = q(-1.5, 0.0, 0.08)
			rot["thigh_r"] = q(-1.5, 0.0, -0.08)
			rot["shin_l"] = q(1.5)
			rot["shin_r"] = q(1.5)
			rot["chest"] = q(0.02 * breathe)
			rot["arm_l"] = q(-0.5, 0.0, 0.15)
			rot["arm_r"] = q(-0.5, 0.0, -0.15)
			rot["forearm_l"] = q(-0.9)
			rot["forearm_r"] = q(-0.9)
			out.pos = Vector3(0, -27, -8)
		"lie":
			# on his back on the bed, head on the pillow: the whole body turned back about the feet, which lie 40 voxels
			# (20 units) south of where he's put (LobbyBed's spot is 70 units down from the bed's head end)
			out.pivot = Vector3(0, 0, 0)
			out.turn = q(-PI / 2.0)
			out.pos = Vector3(0, 44, 56)
			rot["chest"] = q(0.02 * breathe)
			rot["arm_l"] = q(0.0, 0.0, 0.12)
			rot["arm_r"] = q(0.0, 0.0, -0.12)
		"bench":
			# lying on the bench, pressing the bar up (pose_f: 0 down at the chest, 1 arms straight)
			out.pivot = Vector3(0, 0, 0)
			out.turn = q(-PI / 2.0)
			out.pos = Vector3(0, 26, 0)
			rot["thigh_l"] = q(-1.4, 0.0, 0.25)
			rot["thigh_r"] = q(-1.4, 0.0, -0.25)
			rot["shin_l"] = q(1.4)
			rot["shin_r"] = q(1.4)
			var up := smoothstep(0.0, 1.0, f)
			rot["arm_l"] = q(lerpf(-0.6, -1.55, up), 0.0, lerpf(1.0, 0.25, up))
			rot["arm_r"] = q(lerpf(-0.6, -1.55, up), 0.0, lerpf(-1.0, -0.25, up))
			rot["forearm_l"] = q(lerpf(-1.9, -0.05, up))
			rot["forearm_r"] = q(lerpf(-1.9, -0.05, up))
		"legpress":
			out.pivot = Vector3(0, 0, 0)
			out.turn = q(-0.9)
			out.pos = Vector3(0, 20, 0)
			var push := smoothstep(0.0, 1.0, f)
			rot["thigh_l"] = q(lerpf(-2.2, -1.3, push))
			rot["thigh_r"] = q(lerpf(-2.2, -1.3, push))
			rot["shin_l"] = q(lerpf(2.2, 0.2, push))
			rot["shin_r"] = q(lerpf(2.2, 0.2, push))
			rot["arm_l"] = q(-0.3, 0.0, 0.3)
			rot["arm_r"] = q(-0.3, 0.0, -0.3)
		"lift", "carry":
			# arms out in front, holding something (a plate, Gothica across them)
			rot["arm_l"] = q(-1.0, -0.25, 0.1)
			rot["arm_r"] = q(-1.0, 0.25, -0.1)
			rot["forearm_l"] = q(-0.9)
			rot["forearm_r"] = q(-0.9)
			rot["chest"] = q(-0.12)
			_legs_walk(s, out)
		"carried":
			# lying across someone's arms: turned on her back, knees over one arm
			out.pivot = Vector3(0, 50, 0)
			out.turn = q(-PI / 2.0 + 0.2, 0.0, 0.0)
			rot["thigh_l"] = q(-1.2)
			rot["thigh_r"] = q(-1.2)
			rot["shin_l"] = q(1.3 + 0.1 * sin(t * 6.0))
			rot["shin_r"] = q(1.3 + 0.1 * sin(t * 6.0 + 1.0))
			rot["arm_l"] = q(-2.6, 0.0, 0.4)
			rot["arm_r"] = q(-0.8, 0.0, -0.3)
			rot["head"] = q(-0.5)
		"swim":
			# face down, arms stroking in turn, legs kicking
			out.pivot = Vector3(0, 0, 0)
			out.turn = q(PI / 2.0)
			out.pos = Vector3(0, -40, 0)
			var a := t * 4.0
			rot["arm_l"] = q(-PI + fmod(a, TAU) * 0.0 + -1.4 * sin(a), 0.0, 0.2)
			rot["arm_r"] = q(-PI + -1.4 * sin(a + PI), 0.0, -0.2)
			rot["thigh_l"] = q(0.3 * sin(t * 9.0))
			rot["thigh_r"] = q(-0.3 * sin(t * 9.0))
			rot["head"] = q(-0.7)
		"victory":
			_victory(out, t)
		_:
			_base(s, out, t)
			_arms(s, out, t)

static func _legs_walk(s: Dictionary, out: Dictionary) -> void:
	var keep: Dictionary = out.rot.duplicate()
	var tmp := {"rot": {}, "pos": Vector3.ZERO}
	_base(s, tmp, float(s.get("t", 0.0)))
	for b in ["hips", "thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]:
		if tmp.rot.has(b):
			out.rot[b] = tmp.rot[b]
	out.pos = tmp.pos
	for b in keep:
		out.rot[b] = keep[b]
