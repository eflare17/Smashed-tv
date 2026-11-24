extends SceneTree
## The test yard's pictures (integration/dirt_physics_plan.md; under a display, software-rendered here:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_yard_shots.gd -- --nosave --out=<dir> [--tag=before]
## ). The same run as digsite_yard_test.gd (the levelled patch, the bulldozer blade down straight across it), four
## PNGs: <tag>_1_start, <tag>_2_mid_push, <tag>_3_heap, <tag>_4_side. Each stage re-takes them for a before/after pair.
## Nothing's drawn between the shots (this box draws a frame or two a second), so the run is the test's, tick for tick.
## Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
# [name, seconds into the drive, look yaw, look pitch, camera distance]
const SHOTS := [
	["1_start", 0.0, -0.45, -0.32, 9.0],          # from behind and to one side, the flat patch ahead
	["2_mid_push", 6.0, -0.7, -0.42, 9.0],        # pushing: the heap growing on the blade
	["3_heap", 14.0, PI * 0.78, -0.3, 9.5],       # from in front, looking back at the heap and the blade
	["4_side", 14.0, -PI * 0.5, -0.12, 11.0],      # side on: the heap's profile, the cut behind
]

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var out := "res://integration/dirt_shots"
var tag := "before"
var lift := -0.1
var k := 0
var drive_t := 0.0
var busy := false
var made := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
		elif a.begins_with("--lift="):
			lift = float(a.trim_prefix("--lift="))
	y.boot(self)

func _shot(name: String) -> void:
	busy = true
	RenderingServer.render_loop_enabled = true
	for i in 3:                       # (the view settled, the changed ground's sections drawn)
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%s_%s.png" % [tag, name])
	root.get_texture().get_image().save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	print("DSYARDSHOT %s %s %d bytes %s" % ["ok  " if size > 20000 else "FAIL", path, size, "" if size > 20000 else "(blank? under 20 kB)"])
	if size > 20000:
		made += 1
	RenderingServer.render_loop_enabled = false
	busy = false

func _process(dt: float) -> bool:
	if busy:
		return false                  # (held while a picture's taken: the dozer's stood still, see below)
	t += dt
	match step:
		0:
			if t > 1.5:
				RenderingServer.render_loop_enabled = false
				y.travel()
				step = 1
				mark = t
		1:
			if y.arrived() and t - mark > 1.0:
				y.level()
				step = 2
				mark = t
		2:
			if t - mark > 1.0:
				var dz := y.park_dozer()
				y.mount(dz)
				y.ds().machines.cam_dist = 9.0
				step = 3
				mark = t
		3:
			if t - mark > 2.0:
				step = 4
		4:
			var dz := y.dozer()
			if k >= SHOTS.size():
				print("DSYARDSHOT done %d of %d pictures" % [made, SHOTS.size()])
				return true
			var s: Array = SHOTS[k]
			if drive_t >= float(s[1]):
				# (the view turned, a few undrawn ticks for it to come round and the ground's sections to catch up)
				y.ds().terrain.paused = true
				y.drive_dozer(dz, 0.0, lift if drive_t > 0.0 else DsDozer.START_LIFT)   # (the first: its blade still up)
				dz.speed = 0.0
				y.arena.look_yaw = float(s[2])
				y.arena.look_pitch = float(s[3])
				y.ds().machines.cam_dist = float(s[4])
				step = 5
				mark = t
			else:
				y.ds().terrain.paused = false
				y.drive_dozer(dz, 1.0, lift)
				drive_t += dt
		5:
			if t - mark > 0.5:
				_shot(str(SHOTS[k][0]))
				k += 1
				step = 4
	return false
