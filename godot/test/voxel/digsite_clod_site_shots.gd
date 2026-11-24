extends SceneTree
## Pictures of the clods in the site (integration/dirt_physics_plan.md, stage 3; under a display, software-rendered here:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_site_shots.gd -- --nosave --out=res://integration/dirt_shots
## ). In the yard: the bulldozer driven across with its blade just clear of the ground (it cuts nothing: the clods are
## all there is to see), 100 clods a second poured ahead of it (clods_1_push, clods_2_push_side); 300 dropped into the
## tip truck's tray (clods_3_tray_falling, clods_4_tray); the debug key's throw, on foot (clods_5_thrown,
## clods_6_landing, clods_7_melted). Nothing's drawn between the shots, and the game's held still for each.
## Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var out := "res://integration/dirt_shots"
var busy := false
var made := 0
var asked := 0
var rng := RandomNumberGenerator.new()
var acc := 0.0
var let := 0
var shot_k := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	rng.seed = 11
	y.boot(self)

func _hold(on: bool) -> void:
	y.ds().terrain.paused = on
	y.ds().dirt_paused = on

func _shot(name: String) -> void:
	busy = true
	asked += 1
	_hold(true)
	RenderingServer.render_loop_enabled = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("clods_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	print("DSCLODSHOT %s %s %d bytes, %d clods awake" % ["ok  " if size > 20000 else "FAIL", path, size, y.ds().dirt.awake()])
	if size > 20000:
		made += 1
	RenderingServer.render_loop_enabled = false
	_hold(false)
	busy = false

func _view(yaw: float, pitch: float, dist: float) -> void:
	y.arena.look_yaw = yaw
	y.arena.look_pitch = pitch
	y.ds().machines.cam_dist = dist

func _process(dt: float) -> bool:
	if busy:
		return false
	t += dt
	var d := y.ds()
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
				d.terrain.build_now(3000.0)
				var c := y.centre()
				y.park(y.machine("tip truck"), c.x - 7.0, c.z + 1.0, 0.0)
				var dz := y.park_dozer()
				y.mount(dz)
				_view(PI * 0.8, -0.3, 8.5)
				step = 2
				mark = t
		2:
			# the dozer across, its blade 6 cm clear of the ground, clods poured ahead of it
			var dz := y.dozer()
			var el := t - mark - 1.0
			if el < 0.0:
				return false
			y.drive_dozer(dz, 1.0, 0.06)
			var e: Array = dz.edge_ends()
			var f := dz.forward()
			acc += 100.0 * dt
			while acc >= 1.0:
				acc -= 1.0
				var p: Vector3 = (e[0] as Vector3).lerp(e[1], rng.randf_range(0.05, 0.95)) + f * rng.randf_range(0.3, 1.3)
				d.dirt.spawn(Vector3(p.x, y.level_m() + rng.randf_range(0.5, 1.3), p.z), f * dz.speed * 0.5, DsMats.DIRT, [125, 500, 500, 500, 2000][rng.randi() % 5])
			if shot_k == 0 and el > 3.0:
				shot_k = 1
				_shot("1_push")
			elif shot_k == 1 and el > 4.0:
				shot_k = 2
				_view(PI * 0.5, -0.1, 9.0)
				_shot("2_push_side")
			elif shot_k == 2 and el > 4.1:
				y.drive_dozer(dz, 0.0, 0.06)
				d.dirt.land_all()
				y.mount(y.machine("tip truck"))
				_view(0.5, -0.75, 7.5)
				step = 3
				mark = t
				let = 0
		3:
			var truck := y.machine("tip truck") as DsTruck
			if let < 300 and t - mark > 0.5:
				for i in 10:
					var l := DsTruck.TRAY_AT + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(1.5, 2.5), rng.randf_range(-1.9, 1.9))
					d.dirt.spawn(truck.global_transform * l, Vector3.ZERO, DsMats.DIRT, [125, 500, 500, 500, 2000][rng.randi() % 5])
				let += 10
			if shot_k == 2 and let >= 200:
				shot_k = 3
				_shot("3_tray_falling")
			elif shot_k == 3 and t - mark > 4.0:
				shot_k = 4
				_shot("4_tray")
			elif shot_k == 4:
				d.dirt.land_all()
				d.machines.get_off()
				var c := y.centre()
				d._put(Vector3(c.x + 4.0, y.level_m() + 0.05, c.z + 6.0), 0.0, -0.22)
				step = 4
				mark = t
		4:
			var el := t - mark
			if shot_k == 4 and el > 0.5:
				d.throw_clods()
				shot_k = 5
				mark = t
			elif shot_k == 5 and el > 0.25:
				d.throw_clods()
				shot_k = 6
			elif shot_k == 6 and el > 0.6:
				shot_k = 7
				_shot("5_thrown")
			elif shot_k == 7 and el > 1.3:
				shot_k = 8
				_shot("6_landing")
			elif shot_k == 8 and el > 6.0:
				shot_k = 9
				_shot("7_melted")
			elif shot_k == 9:
				print("DSCLODSHOT done %d of %d pictures" % [made, asked])
				return true
	return false
