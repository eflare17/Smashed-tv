class_name VoxelEnemies
extends Node3D
## The fight's enemies in blocks (grunt, swarmer, brute, the batter with his nail bat): each frame, after
## the fight's EnemyView has placed its pictures, the ones with a voxel model (assets/voxel/<enemy>/) are hidden and a
## posed block enemy stands in each one's place, facing where it walks, its legs going by its odo, white while it
## flashes. Owned by the voxel session; VoxelSwitch adds it once a fight exists, and it only acts in blocks mode.
##
## It walks the enemies in EnemyView's own order (the ones still spawning have no picture), so the n-th picture is the
## n-th enemy shown. Corpses, gore, shadows and hp bars stay the fight's.

const MODELS := ["grunt", "swarmer", "brute", "batter"]

var fight: Node
var _actors: Array = []          # [{root: Node3D, skel: Skeleton3D, mesh: MeshInstance3D, mat, key, yaw}]
var _flash_col := Color(2.6, 2.6, 2.6)

func _ready() -> void:
	process_priority = 950
	top_level = true

var _low := false

func _process(_dt: float) -> void:
	var on := VoxelSwitch.mode == "blocks"
	var lp := VoxelChar._look_pass()
	var low := lp != null and String(lp.get("quality")) != "high"
	if low != _low:
		_low = low
		# the low look: made again at half detail (a wave can hold twenty of them)
		for a in _actors:
			if not a.is_empty():
				(a.root as Node3D).queue_free()
		_actors.clear()
	var used := 0
	var shown := 0
	var f = fight if fight and is_instance_valid(fight) else null
	var sim = f.sim if f else null
	var ev = f.get("eview") if f else null
	if on and sim and ev and ev.visible and ev.is_visible_in_tree():
		var pool: Array = ev.get("_pool")
		for e in sim.enemies:
			if e.spawn > 0.0:
				continue
			var key: String = sim.e_key[e.t]
			var pic: Sprite3D = pool[used] if used < pool.size() else null
			used += 1
			if not (key in MODELS) or not VoxelModel.has_model(key) or pic == null:
				continue
			if not pic.visible:
				continue
			pic.visible = false
			var a := _actor(shown, key, sim, e.t)
			shown += 1
			if a.is_empty():
				continue
			_pose(a, e, sim)
	for i in range(shown, _actors.size()):
		(_actors[i].root as Node3D).visible = false

func _actor(i: int, key: String, sim, et: int) -> Dictionary:
	while _actors.size() <= i:
		_actors.append({})
	var a: Dictionary = _actors[i]
	if not a.is_empty() and a.key == key:
		(a.root as Node3D).visible = true
		return a
	if not a.is_empty():
		(a.root as Node3D).queue_free()
	var md := VoxelModel.get_model(key)
	if md == null:
		return {}
	# as tall as the picture: the enemy's radius x T.enemyScale for the sprite's rows
	md.voxel_m = float(sim.e_rad(et)) * float(sim.tv("enemyScale", 3.4)) / float(md.rig.get("ref_rows", 80)) * GameData.UNIT
	var root := Node3D.new()
	root.name = "Block_" + key
	add_child(root)
	var sk := md.make_skeleton()
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	var att := []
	var lod := 1 if _low else 0
	if key == "batter":
		var g: Array = md.rig.get("grip_r", [-21.5, 35.0, 0.0])
		var grip_l := Vector3(-float(g[0]), float(g[1]), 0.0) * md.voxel_m
		att.append({"arrays": VoxelModel.weapon_arrays("bat", lod, md.voxel_m), "bone": "hand_l",
			"xform": Transform3D(Basis(Vector3.RIGHT, PI / 2.0), grip_l)})
	mi.mesh = md.build_mesh(key + "|enemy|%d" % lod, "", lod, att)
	var mat := ShaderMaterial.new()
	mat.shader = VoxelChar.shader_for(_low)
	mat.set_shader_parameter("tip", 0.5)
	mi.material_override = mat
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = md.make_skin()
	a = {"root": root, "skel": sk, "mesh": mi, "mat": mat, "key": key, "yaw": 0.0, "model": md}
	_actors[i] = a
	return a

func _pose(a: Dictionary, e, sim) -> void:
	var root: Node3D = a.root
	root.global_position = GameData.world_to_3d(e.x, e.y, 0.0)
	var v := Vector2(e.vx, e.vy)
	var sp := v.length()
	var swinging: bool = String(a.key) == "batter" and e.st != EnemySim.CHASE
	if swinging and Vector2(e.sdx, e.sdy).length() > 0.01:
		v = Vector2(e.sdx, e.sdy)
	if sp >= 12.0 or swinging:
		var want := atan2(v.x, v.y)
		a.yaw = float(a.yaw) + wrapf(want - float(a.yaw), -PI, PI) * (0.5 if swinging else 0.25)
	var moving: bool = sp >= 12.0 and e.stun <= 0.0
	# their walk cycle is enemyStride x 4 units; the characters' is 91
	var odo: float = e.odo * VoxelAnim.CYCLE / maxf(1.0, float(sim.tv("enemyStride", 10)) * 4.0)
	var p := VoxelAnim.pose({"t": Time.get_ticks_msec() / 1000.0 + float(e.t), "moving": moving, "speed": sp * 2.0,
		"odo": odo, "weapon": ""})
	# fists up a little: they come at you
	if moving:
		p.rot["arm_r"] = (p.rot.get("arm_r", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(-0.4, 0, 0))
		p.rot["arm_l"] = (p.rot.get("arm_l", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(-0.4, 0, 0))
	if String(a.key) == "batter":
		_bat_arms(p, e, sim, swinging)
	var md: VoxelModel = a.model
	var sk: Skeleton3D = a.skel
	var rot: Dictionary = p.rot
	for i in md.bone_names.size():
		if md.bone_parent[i] >= 0:
			sk.set_bone_pose_rotation(i, rot.get(md.bone_names[i], Quaternion.IDENTITY))
	var r := maxi(0, md.bone("hips"))
	var face := Quaternion(Vector3.UP, float(a.yaw))
	sk.set_bone_pose_position(r, face * ((md.bone_pivot[r] + (p.pos as Vector3) * 0.5) * md.voxel_m))
	sk.set_bone_pose_rotation(r, face * (rot.get("hips", Quaternion.IDENTITY) as Quaternion))
	(a.mat as ShaderMaterial).set_shader_parameter("modulate", _flash_col if e.flash > 0.0 else Color.WHITE)

# the batter: the bat hangs from his left hand as he walks; the wind-up lifts it back over his shoulder, the swing
# sweeps it across in front, the recovery follows through (EnemySim's WINDUP, SWING, RECOVER)
func _bat_arms(p: Dictionary, e, sim, swinging: bool) -> void:
	var rot: Dictionary = p.rot
	if not swinging:
		rot["arm_l"] = (rot.get("arm_l", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(-0.25, 0, 0.1))
		rot["forearm_l"] = Quaternion.from_euler(Vector3(-0.5, 0, 0))
		rot["hand_l"] = Quaternion.from_euler(Vector3(-0.6, 0, 0))
		return
	var dur := 0.38
	match e.st:
		EnemySim.WINDUP:
			dur = sim.tv("batWindup", 0.38)
		EnemySim.SWING:
			dur = 0.16
		_:
			dur = sim.tv("batRecover", 0.55)
	var k := 1.0 - clampf(e.st_t / maxf(0.01, dur), 0.0, 1.0)
	var arm: Vector3
	var chest := Vector3.ZERO
	match e.st:
		EnemySim.WINDUP:
			arm = Vector3(-0.5, 0.0, 0.3).lerp(Vector3(2.5, 0.3, 0.5), k)
			chest = Vector3(-0.1, 0.5 * k, 0.0)
		EnemySim.SWING:
			arm = Vector3(2.5, 0.3, 0.5).lerp(Vector3(-1.4, -1.0, 0.2), k)
			chest = Vector3(0.1, lerpf(0.5, -0.6, k), 0.0)
		_:
			arm = Vector3(-1.4, -1.0, 0.2).lerp(Vector3(-0.5, 0.0, 0.2), k)
			chest = Vector3(0.1, lerpf(-0.6, 0.0, k), 0.0)
	rot["arm_l"] = Quaternion.from_euler(arm)
	rot["forearm_l"] = Quaternion.from_euler(Vector3(-0.3, 0, 0))
	rot["hand_l"] = Quaternion.from_euler(Vector3(-1.2, 0, 0))
	rot["arm_r"] = Quaternion.from_euler(Vector3(-0.6, 0.4, -0.2))
	rot["forearm_r"] = Quaternion.from_euler(Vector3(-1.0, 0, 0))
	rot["chest"] = Quaternion.from_euler(chest)
