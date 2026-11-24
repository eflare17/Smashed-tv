extends SceneTree
## Machine weight's pictures (integration/dirt_physics_plan.md, stage 4; under a display, software-rendered here:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_feel_shots.gd -- --nosave --out=<dir>
## ). The feel test's bank run, seen: the bulldozer flat out into the 1.5 m bank, side on as it bites in (its nose down,
## feel_1_bite), from behind as it stands stalled against it (its tracks throwing dirt, feel_2_stalled), and side on
## again once it's let go and rocked back (feel_3_let_go). Nothing's drawn between the pictures (this box draws a frame
## or two a second); the game runs on while one's taken. Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const BANK := 12
const BANK_Z := -5.0
const BANK_DEEP := 6.0
const BANK_HALF := 7.0

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var out := "res://integration/dirt_shots"
var busy := false
var made := 0
var fast := false

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
	var path := dir.path_join("feel_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	var dz := y.dozer()
	print("DSFEELSHOT %s %s %d bytes; speed %.2f m/s, slip %.2f, nose %.2f deg" % ["ok  " if size > 20000 else "FAIL", path, size, dz.speed, dz.slip, rad_to_deg(dz.sway)])
	if size > 20000:
		made += 1
	RenderingServer.render_loop_enabled = false
	busy = false

func _view(yaw: float, pitch: float, dist: float) -> void:
	y.arena.look_yaw = yaw
	y.arena.look_pitch = pitch
	y.ds().machines.cam_dist = dist

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
				var g = y.grid()
				var tr: DsTerrain = y.ds().terrain
				var c := y.centre()
				var a := tr.cell_of(c + Vector3(-BANK_HALF, 0, BANK_Z - BANK_DEEP))
				var b := tr.cell_of(c + Vector3(BANK_HALF, 0, BANK_Z))
				for z in range(a.z, b.z):
					for x in range(a.x, b.x):
						for yy in range(y.level_y + 1, y.level_y + 1 + BANK):
							g.set_cell(x, yy, z, DsMats.DIRT)
				step = 2
				mark = t
		2:
			if t - mark > 1.5:
				var dz := y.park_dozer()
				y.mount(dz)
				_view(-PI * 0.5, -0.1, 9.0)
				step = 3
				mark = t
		3:
			# flat out at the bank; the picture as it bites in (it was over 2 m/s, now under 1.2)
			var dz := y.dozer()
			y.drive_dozer(dz, 1.0, DsDozer.START_LIFT)
			fast = fast or dz.speed > 2.0
			if (fast and dz.speed < 1.2) or t - mark > 12.0:
				_shot("1_bite")
				step = 4
				mark = t
		4:
			var dz := y.dozer()
			y.drive_dozer(dz, 1.0, DsDozer.START_LIFT)
			if t - mark > 0.4:
				_view(-0.6, -0.3, 8.0)
			if t - mark > 1.4:
				_shot("2_stalled")
				step = 5
				mark = t
		5:
			var dz := y.dozer()
			y.drive_dozer(dz, 0.0, DsDozer.START_LIFT)
			_view(-PI * 0.5, -0.1, 9.0)
			if t - mark > 1.2:
				_shot("3_let_go")
				step = 6
				mark = t
		6:
			if t - mark > 0.2:
				print("DSFEELSHOT done %d of 3 pictures" % made)
				return true
	return false
