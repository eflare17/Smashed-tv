class_name ZombieAnim
extends RefCounted
## The zombie's moves on its mixamorig bones (Skeleton3D bone poses): idle, walk, run, attack, hit, death, scream,
## rise. Each move is played by progress u (0..1: a cyclic move's phase, a one-shot's way through) and comes from
## a real Mixamo clip when there is one (assets/models/zombie/anims/<move>.fbx, exported "without skin" on the same
## skeleton), otherwise from the procedural version here. A change of move crossfades; "hit" made in code is a
## flinch laid over whatever is playing (a hit clip replaces it instead).
##
## The procedural poses are written as rotations in the character's own frame at rest (+x his left, +y up, +z
## forward; degrees, applied y then x then z like Godot's euler), each relative to its parent's: a bone's local
## rotation is then inv(parent's global rest) * delta * (its global rest), so a knee bends about the leg's own
## sideways axis wherever the hip has swung it. Handy rules for this skeleton: an arm down is z -deg for the left
## and +deg for the right, forward is y -deg left / +deg right; a leg forward is x -deg, a knee bends x +deg; the
## spine leans forward x +deg; the head turns to his left y +deg.

const DIR := "res://assets/models/zombie/anims/"
const MOVES := ["idle", "walk", "run", "attack", "hit", "death", "scream", "rise"]
const LOOPING := {"idle": true, "walk": true, "run": true}
const FADE := 0.18                ## seconds of crossfade between moves

## Clips found in DIR: move -> {anim: Animation, tracks: {bone name: [rot track, pos track]}, hips_y: float} or {}.
static var _clips: Dictionary = {}

var skel: Skeleton3D
var n := 0
var parent := PackedInt32Array()
var idx: Dictionary = {}            # bone name without "mixamorig_" -> index
var names: PackedStringArray = []
var rest_l: Array[Quaternion] = []
var pre: Array[Quaternion] = []     # inv(parent's global rest rotation)
var post: Array[Quaternion] = []    # own global rest rotation
var hips := 0
var hips_rest := Vector3.ZERO
## This zombie's own way of moving (0..1): which leg drags, how its head hangs, how high its arms reach.
var seed := 0.37
var move := ""
var cur: Array[Quaternion] = []     # the pose shown (local rotations), and the hips' position
var cur_hips := Vector3.ZERO
var _from: Array[Quaternion] = []
var _from_hips := Vector3.ZERO
var _fade := 1.0
var _tmp: Array[Quaternion] = []

func _init(s: Skeleton3D) -> void:
	skel = s
	n = s.get_bone_count()
	parent.resize(n)
	for i in n:
		var nm := s.get_bone_name(i)
		names.append(nm)
		idx[nm.trim_prefix("mixamorig_").trim_prefix("mixamorig:")] = i
		parent[i] = s.get_bone_parent(i)
		rest_l.append(s.get_bone_rest(i).basis.get_rotation_quaternion())
	for i in n:
		post.append(s.get_bone_global_rest(i).basis.get_rotation_quaternion())
		pre.append(s.get_bone_global_rest(parent[i]).basis.get_rotation_quaternion().inverse() if parent[i] >= 0 else Quaternion.IDENTITY)
	hips = idx.get("Hips", 0)
	hips_rest = s.get_bone_rest(hips).origin
	cur.assign(rest_l)
	_from.assign(rest_l)
	_tmp.assign(rest_l)
	cur_hips = hips_rest
	_from_hips = hips_rest

# ---------------------------------------------------------------- clips

## The clip for a move, or {} (looked for once per game).
static func clip(m: String) -> Dictionary:
	if _clips.has(m):
		return _clips[m]
	var out := {}
	var path := DIR + m + ".fbx"
	for p in [path, DIR + m + ".glb", DIR + m + ".gltf"]:
		if ResourceLoader.exists(p):
			out = _load_clip(p)
			if not out.is_empty():
				print("ZombieAnim: the %s clip from %s" % [m, p])
				break
	_clips[m] = out
	return out

static func _load_clip(path: String) -> Dictionary:
	var ps = load(path)
	if not (ps is PackedScene):
		return {}
	var root: Node = ps.instantiate()
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false).front() if not root.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false).front() if not root.find_children("*", "Skeleton3D", true, false).is_empty() else null
	var out := {}
	if ap:
		var best: Animation = null
		for an in ap.get_animation_list():
			if an == "RESET":
				continue
			var a := ap.get_animation(an)
			if best == null or a.length > best.length:
				best = a
		if best:
			var tracks := {}
			for t in best.get_track_count():
				# "Skeleton3D:mixamorig_Hips" (bones), or ".../mixamorig_Spine/mixamorig_Hips" when the bones came in
				# as plain nodes (a file with no skin can): the bone's name either way
				var np := best.track_get_path(t)
				var bone := String(np.get_concatenated_subnames())
				if bone == "" and np.get_name_count() > 0:
					bone = String(np.get_name(np.get_name_count() - 1))
				if bone == "":
					continue
				bone = bone.trim_prefix("mixamorig_").trim_prefix("mixamorig:")
				if not tracks.has(bone):
					tracks[bone] = [-1, -1]
				match best.track_get_type(t):
					Animation.TYPE_ROTATION_3D: tracks[bone][0] = t
					Animation.TYPE_POSITION_3D: tracks[bone][1] = t
			var hy := 1.0
			var hi := sk.find_bone("mixamorig_Hips") if sk else -1
			if hi >= 0:
				hy = sk.get_bone_rest(hi).origin.y
			else:
				var hn := root.find_child("mixamorig_Hips", true, false)
				if hn is Node3D:
					hy = (hn as Node3D).position.y
			out = {"anim": best, "tracks": tracks, "hips_y": hy}
	root.free()
	return out

static func has_clip(m: String) -> bool:
	return not clip(m).is_empty()

## How long a clip runs (seconds), or the fallback when the move is procedural.
static func length(m: String, fallback: float) -> float:
	var c := clip(m)
	return (c.anim as Animation).length if not c.is_empty() and (c.anim as Animation).length > 0.05 else fallback

# ---------------------------------------------------------------- playing

## Shows move m at progress u (dt for the crossfade). hit >= 0: the flinch laid over it (0..1 through it).
func apply(m: String, u: float, dt: float, hit := -1.0) -> void:
	if m != move:
		_from.assign(cur)
		_from_hips = cur_hips
		_fade = 0.0 if move != "" else 1.0
		move = m
	_fade = minf(1.0, _fade + dt / FADE)
	if hit >= 0.0 and has_clip("hit"):
		_pose_clip("hit", hit)
	else:
		var c := clip(m)
		if c.is_empty():
			_pose_code(m, u)
		else:
			_pose_clip(m, u)
		if hit >= 0.0:
			_overlay_hit(hit)
	if _fade < 1.0:
		var k := smoothstep(0.0, 1.0, _fade)
		for i in n:
			_tmp[i] = _from[i].slerp(_tmp[i], k)
		_tmp_hips = _from_hips.lerp(_tmp_hips, k)
	cur.assign(_tmp)
	cur_hips = _tmp_hips
	for i in n:
		skel.set_bone_pose_rotation(i, cur[i])
	skel.set_bone_pose_position(hips, cur_hips)

var _tmp_hips := Vector3.ZERO

func _pose_clip(m: String, u: float) -> void:
	var c := clip(m)
	var a: Animation = c.anim
	var t := clampf(u, 0.0, 1.0) * a.length
	if LOOPING.has(m):
		t = fposmod(u, 1.0) * a.length
	var tr: Dictionary = c.tracks
	for i in n:
		_tmp[i] = rest_l[i]
	_tmp_hips = hips_rest
	for bone in tr:
		var bi: int = idx.get(bone, -1)
		if bi < 0:
			continue
		var rt: int = tr[bone][0]
		if rt >= 0:
			_tmp[bi] = a.rotation_track_interpolate(rt, t)
		if bi == hips and tr[bone][1] >= 0:
			# the clip's hips, scaled to this skeleton; a cyclic move stays in place (no root motion)
			var p := a.position_track_interpolate(tr[bone][1], t) * (hips_rest.y / maxf(0.001, float(c.hips_y)))
			if LOOPING.has(m):
				p.x = hips_rest.x
				p.z = hips_rest.z
			_tmp_hips = p

## The procedural move m at u.
func _pose_code(m: String, u: float) -> void:
	var d: Dictionary
	match m:
		"walk": d = walk_pose(u, 1.0)
		"run": d = walk_pose(u, 1.8)
		"attack": d = attack_pose(u)
		"death": d = death_pose(u)
		"scream": d = scream_pose(u)
		"rise": d = rise_pose(u)
		_: d = idle_pose(u)
	_from_deltas(d)

## Bone deltas (degrees, the character's frame) to local rotations; "_hips" is the hips' offset (metres).
func _from_deltas(d: Dictionary) -> void:
	for i in n:
		_tmp[i] = rest_l[i]
	for k in d:
		if k == "_hips":
			continue
		var bi: int = idx.get(k, -1)
		if bi < 0:
			continue
		var e: Vector3 = d[k]
		var dq := Quaternion.from_euler(e * (PI / 180.0))
		_tmp[bi] = (pre[bi] * dq * post[bi]).normalized()
	_tmp_hips = hips_rest + (d.get("_hips", Vector3.ZERO) as Vector3)

## The flinch: the chest and head knocked back, arms thrown out, easing back by the end.
func _overlay_hit(u: float) -> void:
	var w := sin(clampf(u, 0.0, 1.0) * PI) * (1.0 - clampf(u, 0.0, 1.0) * 0.4)
	if u < 0.15:
		w = u / 0.15
	var side := 1.0 if seed > 0.5 else -1.0
	var o := {"Spine": Vector3(-16, 6 * side, 0), "Spine1": Vector3(-10, 0, 0), "Neck": Vector3(-14, 0, 0),
		"Head": Vector3(-22, 18 * side, 10 * side), "LeftArm": Vector3(0, 20, 30), "RightArm": Vector3(0, -20, -30),
		"LeftForeArm": Vector3(0, -20, 0), "RightForeArm": Vector3(0, 20, 0)}
	for k in o:
		var bi: int = idx.get(k, -1)
		if bi < 0:
			continue
		var e: Vector3 = o[k] * w
		# laid over: the extra rotation in the bone's rest frame of the character, after what it already does
		var dq := Quaternion.from_euler(e * (PI / 180.0))
		_tmp[bi] = (_tmp[bi] * (post[bi].inverse() * dq * post[bi])).normalized()
	_tmp_hips += Vector3(0, -0.02, -0.06) * w

# ---------------------------------------------------------------- the moves made in code

static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in a:
		out[key] = (a[key] as Vector3).lerp(b.get(key, Vector3.ZERO), k)
	for key in b:
		if not out.has(key):
			out[key] = Vector3.ZERO.lerp(b[key], k)
	return out

## Key poses [[u, pose], ...] played through u, eased between keys.
static func _keys(keys: Array, u: float) -> Dictionary:
	if u <= keys[0][0]:
		return keys[0][1]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if u <= b[0]:
			var k := (u - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return _mix(a[1], b[1], smoothstep(0.0, 1.0, k))
	return keys[-1][1]

func _fingers(d: Dictionary, curl: float) -> void:
	for side in ["Left", "Right"]:
		var s := -1.0 if side == "Left" else 1.0
		for f in ["Index", "Middle", "Ring", "Pinky"]:
			for j in [1, 2, 3]:
				d[side + "Hand" + f + str(j)] = Vector3(0, 0, s * curl * (0.8 if j == 1 else 1.0))

## Standing, hunched, arms hanging forward, swaying and breathing (u: a 3 s breath).
func idle_pose(u: float) -> Dictionary:
	var a := u * TAU
	var tilt := (seed - 0.5) * 36.0
	var d := {
		"_hips": Vector3(0.02 * sin(a), -0.05, 0),
		"Hips": Vector3(0, 3 * sin(a), 2.5 * sin(a)),
		"Spine": Vector3(13 + 2 * sin(a * 2.0), -3 * sin(a), -2 * sin(a)),
		"Spine1": Vector3(8, 0, 0),
		"Spine2": Vector3(6 + 2 * sin(a * 2.0 + 0.6), 0, 0),
		"Neck": Vector3(10, 0, 0),
		"Head": Vector3(14 + 4 * sin(a + 1.0), 10 * sin(a * 0.5 + seed * 6.0), tilt),
		"LeftShoulder": Vector3(0, 0, -6), "RightShoulder": Vector3(0, 0, 6),
		"LeftArm": Vector3(0, -30 - 6 * sin(a), -58), "RightArm": Vector3(0, 26 + 6 * sin(a + 0.8), 62),
		"LeftForeArm": Vector3(0, -24, 0), "RightForeArm": Vector3(0, 30, 0),
		"LeftHand": Vector3(0, 0, -22), "RightHand": Vector3(0, 0, 24),
		"LeftUpLeg": Vector3(-6, 0, 3), "RightUpLeg": Vector3(-4, 0, -3),
		"LeftLeg": Vector3(14, 0, 0), "RightLeg": Vector3(10, 0, 0),
		"LeftFoot": Vector3(-8, 0, 0), "RightFoot": Vector3(-6, 0, 0),
		"FrontCloth1": Vector3(2 * sin(a), 0, 0), "BackCloth1": Vector3(-2 * sin(a), 0, 0),
	}
	_fingers(d, 16)
	return d

## The shamble (u: one full stride, both feet; k: 1 a walk, ~2 a run). One leg drags.
func walk_pose(u: float, k: float) -> Dictionary:
	var a := u * TAU
	var drag_left := seed < 0.5
	var al := 20.0 * k * (0.6 if drag_left else 1.0)        # each leg's swing
	var ar := 20.0 * k * (1.0 if drag_left else 0.6)
	var sl := sin(a)
	var sr := sin(a + PI)
	var knee_l := 10.0 + 38.0 * k * maxf(0.0, sin(a + 1.3)) * (0.5 if drag_left else 1.0)
	var knee_r := 10.0 + 38.0 * k * maxf(0.0, sin(a + PI + 1.3)) * (1.0 if drag_left else 0.5)
	var lean := 16.0 + 10.0 * (k - 1.0)
	var tilt := (seed - 0.5) * 30.0
	var reach := 1.0 if k < 1.4 else 1.25
	var d := {
		"_hips": Vector3(0.03 * sin(a), -0.05 - 0.035 * absf(cos(a)) * k, 0),
		"Hips": Vector3(0, 7 * sin(a), 5 * sin(a) * (1.0 if drag_left else -1.0)),
		"Spine": Vector3(lean, -8 * sin(a), -3 * sin(a)),
		"Spine1": Vector3(6, -3 * sin(a), 0),
		"Spine2": Vector3(4, 0, 0),
		"Neck": Vector3(8, 0, 0),
		"Head": Vector3(10 + 6 * absf(sin(a)), 8 * sin(a * 0.5 + seed * 5.0), tilt + 6 * sin(a)),
		"LeftShoulder": Vector3(0, 0, -4), "RightShoulder": Vector3(0, 0, 4),
		# reaching for you, the left a bit higher, loose at the elbows and swinging with the steps
		"LeftArm": Vector3(0, (-82 - 6 * sr) * reach, -2 + 6 * sin(a * 2.0)),
		"RightArm": Vector3(0, (70 + 6 * sl) * reach, 22 - 6 * sin(a * 2.0 + 1.0)),
		"LeftForeArm": Vector3(0, -10 - 6 * sin(a * 2.0), 0), "RightForeArm": Vector3(0, 18, 0),
		"LeftHand": Vector3(0, 0, -14), "RightHand": Vector3(0, 0, 18),
		"LeftUpLeg": Vector3(-al * sl - 4, 0, 2), "RightUpLeg": Vector3(-ar * sr - 4, 0, -2),
		"LeftLeg": Vector3(knee_l, 0, 0), "RightLeg": Vector3(knee_r, 0, 0),
		"LeftFoot": Vector3(-(knee_l * 0.45) + al * sl * 0.3 + (12.0 if drag_left else 0.0), 0, 0),
		"RightFoot": Vector3(-(knee_r * 0.45) + ar * sr * 0.3 + (0.0 if drag_left else 12.0), 0, 0),
		"FrontCloth1": Vector3(10 * k + 6 * sin(a * 2.0), 0, 4 * sin(a)),
		"FrontCloth2": Vector3(5 * k, 0, 0),
		"BackCloth1": Vector3(-4 * k + 5 * sin(a * 2.0 + 0.5), 0, -4 * sin(a)),
		"BackCloth2": Vector3(-3 * k, 0, 0),
	}
	_fingers(d, 14)
	return d

## The claw swipe (u through wind-up 0..0.45, the swipe 0.45..0.62, recovery to 1): the right arm up and back,
## the chest turned away, then down and across with a lunge.
func attack_pose(u: float) -> Dictionary:
	var base := walk_pose(0.25, 0.4)
	var wind := {
		"Spine": Vector3(4, -26, -6), "Spine1": Vector3(0, -10, 0), "Head": Vector3(0, 18, 0),
		"RightArm": Vector3(0, 28, -72), "RightForeArm": Vector3(0, 70, 0), "RightHand": Vector3(0, 0, -20),
		"LeftArm": Vector3(0, -60, -30), "LeftForeArm": Vector3(0, -30, 0),
		"_hips": Vector3(0, -0.08, -0.06), "LeftUpLeg": Vector3(-10, 0, 3), "RightUpLeg": Vector3(8, 0, -3),
		"LeftLeg": Vector3(22, 0, 0), "RightLeg": Vector3(18, 0, 0),
	}
	var swipe := {
		"Spine": Vector3(30, 30, 8), "Spine1": Vector3(10, 12, 0), "Head": Vector3(14, -14, 0),
		"RightArm": Vector3(0, 118, 44), "RightForeArm": Vector3(0, 10, 0), "RightHand": Vector3(0, 0, 30),
		"LeftArm": Vector3(0, -20, -70), "LeftForeArm": Vector3(0, -20, 0),
		"_hips": Vector3(0, -0.14, 0.14), "LeftUpLeg": Vector3(-34, 0, 3), "RightUpLeg": Vector3(14, 0, -3),
		"LeftLeg": Vector3(40, 0, 0), "RightLeg": Vector3(10, 0, 0), "LeftFoot": Vector3(-10, 0, 0),
	}
	var d: Dictionary
	if u < 0.45:
		d = _mix(base, _mix(base, wind, 1.0), smoothstep(0.0, 1.0, u / 0.45))
	elif u < 0.62:
		d = _mix(_mix(base, wind, 1.0), _mix(base, swipe, 1.0), smoothstep(0.0, 1.0, (u - 0.45) / 0.17))
	else:
		d = _mix(_mix(base, swipe, 1.0), base, smoothstep(0.0, 1.0, (u - 0.62) / 0.38))
	_fingers(d, 12 if u < 0.62 else 30)
	return d

## Falling backwards, dead (u over the fall): the knees go, the body tips back about the feet, lands, settles.
func death_pose(u: float) -> Dictionary:
	var stand := idle_pose(0.0)
	var buckle := {
		"_hips": Vector3(0, -0.3, -0.05), "Hips": Vector3(-8, 0, 0),
		"Spine": Vector3(-6, 0, 0), "Neck": Vector3(-10, 0, 0), "Head": Vector3(-28, 10, 0),
		"LeftArm": Vector3(0, 10, -20), "RightArm": Vector3(0, -10, 20), "LeftForeArm": Vector3(0, -30, 0), "RightForeArm": Vector3(0, 30, 0),
		"LeftUpLeg": Vector3(-30, 0, 4), "RightUpLeg": Vector3(-24, 0, -4), "LeftLeg": Vector3(60, 0, 0), "RightLeg": Vector3(52, 0, 0),
		"LeftFoot": Vector3(-20, 0, 0), "RightFoot": Vector3(-20, 0, 0),
	}
	var tip := {
		"_hips": Vector3(0, -0.62, -0.42), "Hips": Vector3(-55, 0, 6),
		"Spine": Vector3(-8, 0, 0), "Neck": Vector3(-10, 0, 0), "Head": Vector3(-30, 20, 0),
		"LeftArm": Vector3(0, 40, -5), "RightArm": Vector3(0, -40, 5), "LeftForeArm": Vector3(0, -20, 0), "RightForeArm": Vector3(0, 20, 0),
		"LeftUpLeg": Vector3(-30, 0, 6), "RightUpLeg": Vector3(-38, 0, -6), "LeftLeg": Vector3(40, 0, 0), "RightLeg": Vector3(34, 0, 0),
		"FrontCloth1": Vector3(-30, 0, 0), "BackCloth1": Vector3(20, 0, 0),
	}
	var land := {
		"_hips": Vector3(0, -1.0, -0.8), "Hips": Vector3(-90, 0, 4),
		"Spine": Vector3(-6, 0, 0), "Spine1": Vector3(-4, 0, 0), "Neck": Vector3(-4, 0, 0), "Head": Vector3(-14, 26, 0),
		"LeftArm": Vector3(0, 12, -2), "RightArm": Vector3(0, -24, 18), "LeftForeArm": Vector3(0, -20, 0), "RightForeArm": Vector3(0, 46, 0),
		"LeftUpLeg": Vector3(-8, 0, 10), "RightUpLeg": Vector3(-20, 0, -8), "LeftLeg": Vector3(10, 0, 0), "RightLeg": Vector3(34, 0, 0),
		"LeftFoot": Vector3(30, 0, 0), "RightFoot": Vector3(20, 0, 0),
		"FrontCloth1": Vector3(-60, 0, 0), "FrontCloth2": Vector3(-20, 0, 0), "BackCloth1": Vector3(80, 0, 0),
	}
	var bounce := land.duplicate()
	bounce["_hips"] = Vector3(0, -0.9, -0.82)
	bounce["Hips"] = Vector3(-82, 0, 4)
	bounce["Head"] = Vector3(-30, 20, 0)
	var settle := land.duplicate()
	settle["Head"] = Vector3(-8, 40, 0)
	settle["_hips"] = Vector3(0, -1.02, -0.8)
	var d := _keys([[0.0, stand], [0.16, buckle], [0.48, tip], [0.6, land], [0.68, bounce], [0.78, land], [1.0, settle]], u)
	_fingers(d, 20)
	return d

## The scream (u over it): a breath in, hunched, then head thrown back and arms flung out, shaking with it.
func scream_pose(u: float) -> Dictionary:
	var idle := idle_pose(0.0)
	var breathe := {
		"_hips": Vector3(0, -0.12, 0), "Spine": Vector3(26, 0, 0), "Spine1": Vector3(10, 0, 0), "Neck": Vector3(10, 0, 0), "Head": Vector3(26, 0, 0),
		"LeftArm": Vector3(0, -10, -74), "RightArm": Vector3(0, 10, 74), "LeftForeArm": Vector3(0, -40, 0), "RightForeArm": Vector3(0, 40, 0),
		"LeftUpLeg": Vector3(-14, 0, 6), "RightUpLeg": Vector3(-10, 0, -6), "LeftLeg": Vector3(26, 0, 0), "RightLeg": Vector3(22, 0, 0),
	}
	var j := sin(u * 90.0) * 2.5 + sin(u * 137.0) * 1.5        # the shake
	var roar := {
		"_hips": Vector3(0, -0.06, -0.04), "Spine": Vector3(-14 + j * 0.5, 0, 0), "Spine1": Vector3(-10, 0, 0), "Spine2": Vector3(-6, 0, 0),
		"Neck": Vector3(-14, 0, 0), "Head": Vector3(-34 + j, j, 0),
		"LeftArm": Vector3(0, 30 + j, -14), "RightArm": Vector3(0, -30 - j, 14),
		"LeftForeArm": Vector3(0, -24 + j, 0), "RightForeArm": Vector3(0, 24 - j, 0),
		"LeftHand": Vector3(0, 0, 20), "RightHand": Vector3(0, 0, -20),
		"LeftUpLeg": Vector3(-8, 0, 8), "RightUpLeg": Vector3(-6, 0, -8), "LeftLeg": Vector3(14, 0, 0), "RightLeg": Vector3(12, 0, 0),
	}
	var d := _keys([[0.0, idle], [0.2, breathe], [0.34, roar], [0.82, roar], [1.0, idle]], u)
	_fingers(d, 6 if u > 0.25 and u < 0.85 else 26)
	return d

## Climbing out of the ground (u through it; the view raises the whole body from under the ground with it):
## arms up out of the dirt, clawing down to pull, then standing.
func rise_pose(u: float) -> Dictionary:
	var reach := {
		"_hips": Vector3(0, -0.1, 0), "Spine": Vector3(-8, 0, 0), "Neck": Vector3(-10, 0, 0), "Head": Vector3(-24, 0, 0),
		"LeftArm": Vector3(0, -30, 72), "RightArm": Vector3(0, 30, -72), "LeftForeArm": Vector3(0, -30, 0), "RightForeArm": Vector3(0, 30, 0),
		"LeftUpLeg": Vector3(-20, 0, 0), "RightUpLeg": Vector3(-20, 0, 0), "LeftLeg": Vector3(40, 0, 0), "RightLeg": Vector3(40, 0, 0),
	}
	var claw := {
		"_hips": Vector3(0, -0.45, 0.05), "Spine": Vector3(40, 10, 0), "Spine1": Vector3(12, 0, 0), "Neck": Vector3(6, 0, 0), "Head": Vector3(-6, 0, 0),
		"LeftArm": Vector3(0, -70, -40), "RightArm": Vector3(0, 60, 30), "LeftForeArm": Vector3(0, -50, 0), "RightForeArm": Vector3(0, 60, 0),
		"LeftUpLeg": Vector3(-62, 0, 8), "RightUpLeg": Vector3(-50, 0, -8), "LeftLeg": Vector3(100, 0, 0), "RightLeg": Vector3(86, 0, 0),
		"LeftFoot": Vector3(-30, 0, 0), "RightFoot": Vector3(-30, 0, 0),
	}
	var claw2 := claw.duplicate()
	claw2["Spine"] = Vector3(34, -10, 0)
	claw2["LeftArm"] = Vector3(0, -50, -55)
	claw2["RightArm"] = Vector3(0, 76, 20)
	var d := _keys([[0.0, reach], [0.3, reach], [0.5, claw], [0.66, claw2], [0.8, claw], [1.0, idle_pose(0.0)]], u)
	_fingers(d, 34)
	return d

## How far under the ground (metres) the body is while rising, at u.
static func rise_depth(u: float) -> float:
	return lerpf(1.75, 0.0, smoothstep(0.0, 0.82, u))
