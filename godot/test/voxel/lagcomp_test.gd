extends SceneTree
## Lag compensation (two copies, the host first, both with --lag=MS: -s test/voxel/lagcomp_test.gd -- --host=CODE
## --via=enet --nosave --lag=150, then --join=CODE ...; add --norewind to the host for the old way): the host walks a
## brute side to side at about 3 m/s; the guest stands 6 m off and shoots the pistol at where it sees it, 12 shots.
## The host counts the shots that hit it (a change to the body within a moment of the guest's press arriving).
## With lag compensation as many land as with no lag at all (about 5 of 12: the test's own aim); without, at 150 ms,
## about 2. Owned by the voxel session.

var arena: Node
var role := ""
var code := ""
var t := 0.0
var step := 0
var mark := 0.0
var v := {}
var hits := 0
var shots := 0
var _last_change := -10.0
const SHOTS := 12
const PATH_Z := 10.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
			code = a.trim_prefix("--host=")
		elif a.begins_with("--join="):
			role = "guest"
			code = a.trim_prefix("--join=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _f(who: String, k: String) -> String:
	return "user://lagcomp_%s_%s_%s" % [code, who, k]

func _tell(k: String, val: String) -> void:
	var f := FileAccess.open(_f(role, k), FileAccess.WRITE)
	f.store_string(val)
	f.close()

func _heard(k: String) -> String:
	var p := _f("guest" if role == "host" else "host", k)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var n = arena.net
	if not v.has("clean"):
		v.clean = true
		for k in ["ready", "done", "shot"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_f(role, k)))     # (only its own: the other's may be new)
	if t > 200.0:
		print("LAGCOMP FAIL timed out at step %d" % step)
		return true
	if n == null or not n.linked or (role == "guest" and not n._got_world):
		return false
	return _host(dt) if role == "host" else _guest(dt)

func _host(dt: float) -> bool:
	var n = arena.net
	match step:
		0:
			arena.frozen = true
			arena.godmode = true
			arena.waves.queue.clear()
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			v.b = arena.spawn_kind("brute", Vector3(10, 0, PATH_Z))
			VoxelBody.immortal = true
			# (every change to it counted: a hit)
			var rec: Callable = VoxelBody.net_rec
			VoxelBody.net_rec = func(body, what, args, pose) -> void:
				if body == v.b and what != "hurt":
					_last_change = t
				rec.call(body, what, args, pose)
			mark = t
			step = 1
		1:
			_walk()
			if t - mark > 2.0:
				n._ensure(v.b)
				_tell("ready", str(n._bodies.find_key(v.b)))
				step = 2
		2:
			_walk()
			# a shot told (the guest writes its count): did the body change within a moment of the press arriving?
			var s := int(_heard("shot")) if _heard("shot") != "" else 0
			if s > shots:
				shots = s
				v.shot_t = t
				v.counted = false
			if v.has("shot_t") and not v.counted and t - float(v.shot_t) > 0.6:
				v.counted = true
				if _last_change > float(v.shot_t) - 0.6:
					hits += 1
			if _heard("done") != "" and (not v.has("shot_t") or v.counted):
				print("LAGCOMP host: %d of %d shots hit (rewind %s)" % [hits, shots, "off" if arena._opts.has("norewind") else "on"])
				if not arena._opts.has("norewind"):
					# (with none at all this test's aim lands about 5 of 12; without the rewind, at 150 ms, about 2)
					print("LAGCOMP %s the guest's shots land through the lag (%d of %d, at least 4)" % ["ok  " if hits >= 4 else "FAIL", hits, shots])
				_tell("done", str(hits))
				print("LAGCOMP done")
				return true
	return false

func _walk() -> void:
	var b: VoxelBody = v.b
	if is_instance_valid(b):
		b.global_position = Vector3(10.0 + 2.5 * sin(t * 1.2), 0, PATH_Z)
		b.yaw = 0.0

func _guest(dt: float) -> bool:
	var n = arena.net
	match step:
		0:
			if _heard("ready") == "":
				return false
			v.nid = int(_heard("ready"))
			arena.godmode = true
			var pi: int = arena.loadout.index_of("pistol")
			arena._switch(func(): arena.loadout.select(pi))
			arena.loadout.switch_t = 0.0
			arena.player.global_position = Vector3(10, 0, PATH_Z + 6.0)
			arena.player.velocity = Vector3.ZERO
			mark = t
			step = 1
		1:
			var bv = n._bodies.get(v.nid)
			if not is_instance_valid(bv):
				return false
			var b: VoxelBody = bv
			arena.player.global_position = Vector3(10, 0, PATH_Z + 6.0)
			# aim at the brute's chest, where this game shows it
			var eye: Vector3 = arena.cam.global_position
			var to: Vector3 = b.global_position + Vector3(0, 1.3, 0) - eye
			arena.look_yaw = atan2(-to.x, -to.z)
			arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
			arena._camera(dt)
			if t - mark > 0.7 and shots < SHOTS and t - mark > 1.5:
				mark = t - 0.8
				var pist = arena.melee["pistol"]
				pist.clip = pist.clip_max
				n.local_input("press", [MOUSE_BUTTON_LEFT, Vector2.ZERO])
				n.local_input("release", MOUSE_BUTTON_LEFT)
				shots += 1
				_tell("shot", str(shots))
			if shots >= SHOTS and not v.has("told"):
				v.told = true
				v.done_t = t
				_tell("done", "1")
			if v.has("told") and (_heard("done") != "" or t - float(v.done_t) > 30.0):
				print("LAGCOMP guest: %s of %d hit (the host's count)" % [_heard("done"), SHOTS])
				print("LAGCOMP done")
				return true
	return false
