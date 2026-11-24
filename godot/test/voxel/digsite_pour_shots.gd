extends SceneTree
## A pour's pictures (integration/dirt_physics_plan.md, stage 6; under a display, software-rendered here:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_pour_shots.gd -- --nosave --out=<dir>
## ). The pour test's yard: the Bobcat nosed up to the tip truck's side, its bucket full, tipping it over the tray's
## rim (pour_1_stream), what's landed in the tray (pour_2_tray); backed off so its lip's over the side wall, tipping
## again (pour_3_miss: some in, some down the side); then the truck tipping its tray (pour_4_tip) and the heap behind
## it once the clods have come to rest (pour_5_heap). Nothing's drawn between the pictures (this box draws a frame or
## two a second); the game runs on while one's taken. Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var out := "res://integration/dirt_shots"
var busy := false
var made := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	y.boot(self)

func _shot(name: String) -> void:
	busy = true
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("pour_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	var d: DsDirt = y.ds().dirt
	print("DSPOURSHOT %s %s %d bytes; %d clods awake, the tray %d mm, the Bobcat's bucket %d mm" % ["ok  " if size > 20000 else "FAIL", path, size, d.n, _truck().load_n, _bobcat().load_n])
	if size > 20000:
		made += 1
	RenderingServer.render_loop_enabled = false
	busy = false

func _view(yaw: float, pitch: float, dist: float) -> void:
	y.arena.look_yaw = yaw
	y.arena.look_pitch = pitch
	y.ds().machines.cam_dist = dist

func _truck() -> DsTruck:
	return y.machine("tip truck") as DsTruck

func _bobcat() -> DsBobcat:
	return y.machine("Bobcat") as DsBobcat

func _fill(d: DsDingo) -> void:
	d.bucket = {DsMats.DIRT: d.capacity}
	d.load_n = d.capacity
	d.curl = 0.0
	d.curl_cmd = 0.0

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
				y.level()
				step = 2
				mark = t
		2:
			if t - mark > 1.0:
				var tk := _truck()
				var bc := _bobcat()
				var c := y.centre() + Vector3(-2.0, 0.0, -3.0)
				y.park(tk, c.x, c.z, 0.0)
				var tm: Vector3 = tk.global_transform * DsTruck.TRAY_AT
				bc.arm = 0.7
				bc.curl = 0.0
				y.park(bc, tm.x + DsTruck.TRAY.x * 0.5 + bc.length * 0.5, tm.z, PI * 0.5)
				y.mount(bc)
				_view(PI * 0.5 - 0.9, -0.5, 8.0)
				step = 3
				mark = t
		3:
			if t - mark > 0.8:
				_fill(_bobcat())
				_bobcat().curl_cmd = -1.0
				step = 4
				mark = t
		4:
			if t - mark > 1.25:
				_shot("1_stream")
				step = 5
				mark = t
		5:
			if _bobcat().load_n == 0 and y.ds().dirt.n == 0 and t - mark > 1.0:
				_bobcat().curl_cmd = 0.0
				_view(PI * 0.5 + 0.5, -0.75, 7.5)
				_shot("2_tray")
				step = 6
				mark = t
		6:
			if t - mark > 0.3:
				var bc := _bobcat()
				bc.curl = 0.0
				y.park(bc, bc.global_position.x + 0.46, bc.global_position.z, PI * 0.5)
				bc._pour_p = Vector3.INF
				_view(PI * 0.5 - 0.9, -0.5, 8.0)
				step = 7
				mark = t
		7:
			if t - mark > 0.8:
				_fill(_bobcat())
				_bobcat().curl_cmd = -1.0
				step = 8
				mark = t
		8:
			if t - mark > 1.45:
				_shot("3_miss")
				step = 9
				mark = t
		9:
			if _bobcat().load_n == 0 and y.ds().dirt.n == 0 and t - mark > 1.0:
				var bc := _bobcat()
				bc.curl_cmd = 0.0
				y.park(bc, bc.global_position.x - 11.0, bc.global_position.z - 4.0, PI * 0.5)
				var tk := _truck()
				y.mount(tk)
				_view(PI * 0.5 - 0.5, -0.22, 13.0)
				tk.tip_cmd = 1.0
				step = 10
				mark = t
		10:
			if t - mark > 2.0:
				_shot("4_tip")
				step = 11
				mark = t
		11:
			if _truck().load_n == 0 and y.ds().dirt.n == 0 and t - mark > 1.0:
				_shot("5_heap")
				step = 12
				mark = t
		12:
			if t - mark > 0.2:
				print("DSPOURSHOT done %d of 5 pictures" % made)
				return true
	return false
