extends SceneTree
## Bodies knocked about (VoxelBody): one thrown sideways to the way it faces turns over head over heels the way it's
## thrown (not backward as it faces); one thrown down hard bounces before it lands; one thrown at a St Kilda building
## bounces off its wall and comes down outside it; and one shot dead from in front falls over away from the shot.
## -- --out=dir for pictures (under a display, Forward+). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var out := ""
var fails := []
var a: VoxelBody
var w: VoxelBody
var bounced := false
var was_down_fast := false
var wall: VoxelBreakables.Building
var shot_dir := Vector3.ZERO

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 and step == 0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			var s := sk.arrive_spot()
			sk._put(s[0], float(s[1]), 0.0)
			a = sk.spawn("grunt", (s[0] as Vector3) + Vector3(0, 0, -8))
			step = 1
			t = 0.0
		1:
			if t > 1.0:
				# thrown to its right, up and over
				a.yaw = 0.0
				a.launch(Vector3(6, 7, 0), 7.0)
				var world := Quaternion(Vector3.UP, a.yaw) * a.tumble_axis
				_check(absf(world.dot(Vector3.RIGHT)) < 0.05 and absf(world.y) < 0.05, "thrown sideways: it turns over across the way it's going (axis %s)" % world)
				step = 2
				t = 0.0
		2:
			if a.airborne and a.air_v.y < -VoxelBody.BOUNCE_V:
				was_down_fast = true
			if was_down_fast and a.airborne and a.air_v.y > 0.0:
				bounced = true
			if t > 0.25 and t < 0.3:
				_shot("tumble_1_air")
			if t > 3.0:
				_check(bounced, "it hit the ground hard and bounced")
				_check(not a.airborne, "and came down")
				# one thrown at a building's wall
				for bb in sk.breaks.list:
					if not bb.over and bb.whole and bb.alive.size() > 40:
						wall = bb
						break
				var c := wall.cols.size() / 3
				var n: Vector2 = wall.cols[c].n
				var at := wall.block_at(c, 0) + Vector3(n.x, 0, n.y) * 5.0
				w = arena.spawn_kind("grunt", Vector3(at.x, 0.0, at.z))
				w.set_meta("park", true)
				w.launch(-Vector3(n.x, 0, n.y) * 10.0 + Vector3.UP * 3.0, 5.0)
				step = 3
				t = 0.0
		3:
			if t > 3.0:
				var p := w.global_position
				_check(not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), wall.ring), "thrown at a wall: it bounced off, outside the building")
				# one shot dead from in front: falls over away from the shot
				var s := sk.arrive_spot()
				var me := arena.player.global_position
				var b := sk.spawn("grunt", (s[0] as Vector3) + Vector3(4, 0, -5))
				b.yaw = randf() * TAU
				shot_dir = Vector3(b.global_position.x - me.x, 0, b.global_position.z - me.z).normalized()
				b.knock = shot_dir * 1.0
				b.alive = false
				b.dead_t = 0.0
				a = b
				step = 4
				t = 0.0
		4:
			if t > 1.0:
				var world := Quaternion(Vector3.UP, a.yaw) * a.fall_axis
				var top := Quaternion(world, PI / 2.0 * a.fall_sign) * Vector3.UP
				_check(top.dot(shot_dir) > 0.9, "shot dead from in front: falls over away from the shot (%.2f)" % top.dot(shot_dir))
				_shot("tumble_2_dead")
				step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
