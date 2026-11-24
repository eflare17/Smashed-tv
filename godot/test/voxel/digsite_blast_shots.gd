extends SceneTree
## Stage 7's pictures (integration/dirt_physics_plan.md; under a display, software-rendered here:
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_blast_shots.gd -- --nosave --out=<dir>
## ). On the yard, on foot: a stick of dynamite 7 m off, a third of a second after the bang (blast_1_bang: the clods
## going up), a second after (blast_2_fall: coming down, bouncing), at rest (blast_3_crater: the crater and its rim);
## the shovel's bite (blast_4_flick: crumbs off it); and in a 4 m room dug in the dirt as its roof goes
## (blast_5_cave: lumps coming down). The clods are held still while a picture's taken (this box draws a frame or two a
## second). Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var out := "res://integration/dirt_shots"
var busy := false
var made := 0
var at := Vector3.ZERO
var v := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	y.boot(self)

func _shot(name: String) -> void:
	busy = true
	y.ds().dirt_paused = true
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("blast_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	print("DSBLASTSHOT %s %s %d bytes; %d clods awake" % ["ok  " if size > 20000 else "FAIL", path, size, y.ds().dirt.n])
	if size > 20000:
		made += 1
	RenderingServer.render_loop_enabled = false
	y.ds().dirt_paused = false
	busy = false

func _next() -> void:
	step += 1
	mark = t

func _process(dt: float) -> bool:
	if busy:
		return false
	t += dt
	var ds := y.ds()
	match step:
		0:
			if t > 1.5:
				RenderingServer.render_loop_enabled = false
				y.travel()
				_next()
		1:
			if y.arrived() and t - mark > 1.0:
				y.level()
				_next()
		2:
			if t - mark > 1.0:
				var p := y.centre() + Vector3(0, 0, -3)
				at = Vector3(p.x, ds.terrain.top_at(p.x, p.z), p.z)
				ds._put(at + Vector3(0, 0.1, 7.0), 0.0, -0.12)
				y.arena.inv.add("dynamite", 1)
				v.booms = ds.blasts.booms
				ds.blasts.light(at + Vector3(0, 0.02, 0))
				_next()
		3:
			if ds.blasts.booms > int(v.booms):
				_next()
		4:
			if t - mark > 0.33:
				_shot("1_bang")
				_next()
		5:
			if t - mark > 0.6:
				_shot("2_fall")
				_next()
		6:
			if not ds.blasts.busy() and t - mark > 1.5:
				ds._put(at + Vector3(0, 0.1, 5.0), 0.0, -0.45)
				_shot("3_crater")
				_next()
		7:
			# the shovel: a few bites at your feet, the last one's crumbs in the air
			if t - mark > 0.5:
				var p := y.centre() + Vector3(7, 0, 4)
				ds._put(Vector3(p.x, ds.terrain.top_at(p.x, p.z) + 0.1, p.z), 0.0, -0.95)
				v.n = 0
				_next()
		8:
			if t - mark > 0.7:
				var w = y.arena.melee["shovel"]
				w._cd = 0.0
				w._t = -1.0
				v.fl = ds.tools.flicked
				w.press(MOUSE_BUTTON_LEFT)
				v.n = int(v.n) + 1
				_next()
		9:
			if ds.tools.flicked > int(v.fl) or t - mark > 1.0:
				_next()
		10:
			if t - mark > 0.22:
				if int(v.n) < 3:
					step = 8
					mark = t
				else:
					_shot("4_flick")
					_next()
		11:
			# a 4 m room in the dirt, 1 m of roof over it, you at its side looking across
			if t - mark > 1.0:
				var c := y.centre() + Vector3(-7, 0, 6)
				var top := ds.terrain.top_at(c.x, c.z)
				var fl := top - 3.0
				var yy := 0.06
				while yy < 2.0:
					var z := 0.06
					while z < 4.0:
						var x := 0.06
						while x < 4.0:
							ds.tools.dig_at(Vector3(c.x - 2.0 + x, fl + yy, c.z - 2.0 + z), 0.11, 9)
							x += 0.125
						z += 0.125
					yy += 0.125
				ds._put(Vector3(c.x, fl + 0.05, c.z + 1.7), 0.0, 0.25)
				v.falls = ds.caves.falls
				v.lumps = ds.caves.lumps_n
				_next()
		12:
			if ds.caves.lumps_n > int(v.lumps) or t - mark > 20.0:
				_next()
		13:
			if t - mark > 0.3:
				print("DSBLASTSHOT   the roof: %d falls, %d blocks as lumps" % [ds.caves.falls - int(v.falls), ds.caves.lumps_n - int(v.lumps)])
				_shot("5_cave")
				_next()
		14:
			if t - mark > 0.2:
				print("DSBLASTSHOT done %d of 5 pictures" % made)
				return true
	return false
