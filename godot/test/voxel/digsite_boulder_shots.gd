extends SceneTree
## The owner's "this big boulder flickers when I emptied the bucket" (24 Nov; integration/dirt_physics_plan.md, stage
## 9), in pictures (under a display, software-rendered here:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_boulder_shots.gd -- --nosave --out=<dir> --tag=after
##   (--before --tag=before: the fault as it was)
## ). The excavator where it's parked, on the grass, its bucket full of sand, dirt and clay; it's tipped out, and
## pictures are taken in bursts of consecutive frames while the clods land and melt in (boulder_<tag>_<k>.png), so a
## lump that changes from one frame to the next shows. Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var out := "res://integration/dirt_shots"
var tag := "after"
var busy := false
var made := 0
var bursts := [0.9, 1.8, 3.0, 5.0]
var burst_n := 3
var cam: Camera3D
var cam_dist := 4.5
var before := false          # --before: as it was (the clods' dirt laid the step they settle, the lumps' shader calm 0)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		if a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
		if a == "--before":
			before = true
		if a.begins_with("--dist="):
			cam_dist = float(a.trim_prefix("--dist="))
		if a.begins_with("--burst="):
			burst_n = int(a.trim_prefix("--burst="))
	y.boot(self)

func _burst(k: int) -> void:
	busy = true
	RenderingServer.render_loop_enabled = true
	for i in 2:
		await process_frame
	cam.make_current()
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	for i in burst_n:
		await process_frame
		cam.make_current()
		await RenderingServer.frame_post_draw
		var path := dir.path_join("boulder_%s_%d%s.png" % [tag, k, "abcdefgh"[i]])
		root.get_texture().get_image().save_png(path)
		var size := FileAccess.get_file_as_bytes(path).size()
		var x := y.machine("excavator") as DsExcavator
		print("DSBOULDERSHOT %s %s %d bytes; %d clods awake, the bucket %d mm" % ["ok  " if size > 20000 else "FAIL", path, size, y.ds().dirt.n, x.load_n])
		if size > 20000:
			made += 1
	RenderingServer.render_loop_enabled = false
	busy = false

func _process(dt: float) -> bool:
	if busy:
		return false
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
				var x := y.machine("excavator") as DsExcavator
				y.mount(x)
				x.wrist = Vector2(5.4, 2.4)
				x.curl = 2.7
				y.arena.look_yaw = x.yaw + 2.2
				y.arena.look_pitch = -0.45
				y.ds().machines.cam_dist = 9.0
				step = 2
				mark = t
		2:
			if t - mark > 0.8:
				var x := y.machine("excavator") as DsExcavator
				var c := DsExcavator.CAPACITY
				x.bucket = {DsMats.SAND: c / 2, DsMats.DIRT: c / 4, DsMats.CLAY: c / 4}
				x.load_n = c
				x.curl_cmd = -1.0
				if before:
					y.ds().dirt.melt = false
					DsLook.clod_mat().set_shader_parameter("calm", 0.0)
				# (its own camera: beside where the dirt lands, looking down at it)
				var pp := x.pour_point()
				var gy: float = y.ds().terrain.height_at(pp.x, pp.z)
				var side := x.forward().cross(Vector3.UP).normalized()
				cam = Camera3D.new()
				root.add_child(cam)
				cam.fov = 60.0
				cam.global_position = Vector3(pp.x, gy, pp.z) + side * cam_dist + x.forward() * cam_dist * 0.5 + Vector3(0, cam_dist * 0.55, 0)
				cam.look_at(Vector3(pp.x, gy + 0.3, pp.z))
				step = 3
				mark = t
		_:
			var k := step - 3
			if k >= bursts.size():
				print("DSBOULDERSHOT done %d of %d pictures" % [made, bursts.size() * burst_n])
				return true
			if t - mark > float(bursts[k]):
				step += 1
				_burst(k + 1)
	return false
