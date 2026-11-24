extends SceneTree
## A guest's view of the host's clods (integration/dirt_physics_plan.md, stage 8): two copies, the host headless, the
## guest under a display (software-rendered here; nothing's drawn between its pictures, so it keeps up):
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_sync_shots.gd -- --nosave --host=YARD1 --via=enet --lag=150 --loss=10
##   xvfb-run -a /root/godot/godot --path godot --fixed-fps 60 -s res://test/voxel/digsite_sync_shots.gd -- --nosave --join=127.0.0.1 --via=enet --lag=150 --loss=10 --out=res://integration/dirt_shots
## The host levels the yard's patch and pushes across it with the bulldozer for 20 s; the guest stands beside the
## patch and takes sync_guest_1_wave.png when it's shown 150 of the host's clods (or the most there were), and
## sync_guest_2_rest.png 2 s after the last has gone. Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
var y := Yard.new()
var role := ""
var out := "res://integration/dirt_shots"
var t := 0.0
var step := 0
var mark := 0.0
var busy := false
var made := 0
var most := 0
var _paced := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
		elif a.begins_with("--join="):
			role = "guest"
		elif a.begins_with("--out="):
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
	var path := dir.path_join("sync_guest_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	var size := FileAccess.get_file_as_bytes(path).size()
	var d: DsDirt = y.ds().dirt
	print("DSSYNCSHOT %s %s %d bytes; %d of the host's clods shown (the host's %d), %d of its own" % ["ok  " if size > 20000 else "FAIL", path, size, d.qn, d.host_n, d.n])
	if size > 20000:
		made += 1
	RenderingServer.render_loop_enabled = false
	busy = false

func _next(s: int) -> void:
	step = s
	print("DSSYNCSHOT   %s step %d at %.1f s" % [role, s, t])
	mark = t

func _process(dt: float) -> bool:
	var now := Time.get_ticks_usec()
	if _paced > 0 and now - _paced < 16667:
		OS.delay_usec(16667 - (now - _paced))
	_paced = Time.get_ticks_usec()
	if busy:
		return false
	if t == 0.0 and role == "guest":
		RenderingServer.render_loop_enabled = false
	t += dt
	if t > 240.0:
		print("DSSYNCSHOT FAIL %s timed out at step %d" % [role, step])
		return true
	var n = y.arena.net
	var ds: DigSite = y.ds()
	match step:
		0:
			if n != null and n.linked and (role == "host" or n._got_world) and t > 2.0:
				y.arena.godmode = true
				if role == "host":
					y.arena.phone.travel("digsite")
				else:
					RenderingServer.render_loop_enabled = false
				_next(1)
		1:
			if y.arrived() and (ds.net.guest_here if role == "host" else ds.net.synced) and t - mark > 2.0:
				if role == "host":
					y.level()
				_next(2 if role == "host" else 10)
		2:
			if t - mark > 3.0:
				var dz := y.park_dozer()
				y.mount(dz)
				_next(3)
		3:
			if t - mark > 3.0:
				_next(4)
		4:
			y.drive_dozer(y.dozer(), 1.0 if t - mark < 20.0 else 0.0, -0.1)
			if t - mark > 40.0:
				return true
		10:
			# (beside the patch, 7 m from the dozer's line, looking across at where it is 4 s into its push)
			var c := y.centre()
			var at := c + Vector3(7.0, 0.0, 6.0)
			ds._put(Vector3(at.x, ds.terrain.top_at(at.x, at.z) + 0.05, at.z), 1.55, -0.22)
			var d: DsDirt = ds.dirt
			most = maxi(most, d.shown())
			if d.shown() >= 150 or (most > 60 and d.shown() < most - 15):
				_shot("1_wave")
				_next(11)
		11:
			var d: DsDirt = ds.dirt
			if d.shown() > 0 or d.host_n > 0:
				mark = t
			if t - mark > 2.0:
				_shot("2_rest")
				_next(12)
		12:
			print("DSSYNCSHOT done %d of 2 pictures" % made)
			return true
	return false
