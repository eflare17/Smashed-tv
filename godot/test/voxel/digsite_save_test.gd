extends SceneTree
## The Dig Site kept between games (DsSave; headless, two runs, the same --save= path):
##   --fixed-fps 60 -s test/voxel/digsite_save_test.gd -- --save=<path> --phase=1   digs with the dozer, goes home (saved)
##   --fixed-fps 60 -s test/voxel/digsite_save_test.gd -- --save=<path> --phase=2   a new game: the site's as it was left
## Owned by the voxel session.
var arena: Node
var phase := 1
var save_at := ""
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = int(a.trim_prefix("--phase="))
		elif a.begins_with("--save="):
			save_at = a.trim_prefix("--save=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSSAVE ok   ", what)
	else:
		failed += 1
		print("DSSAVE FAIL ", what)

func _done() -> bool:
	print("DSSAVE done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

# what the site's like: all its ground, its loose dirt, the surface at a row of spots, the dozer, the grass worn
func _facts() -> Dictionary:
	var ds: DigSite = arena.digsite
	var g: DigSiteGrid = ds.terrain.grid
	var hs := []
	for k in 12:
		var p: Vector3 = (v.from as Vector3) + (v.fwd as Vector3) * float(k)
		hs.append(snappedf(ds.terrain.surface_at(p.x, p.z), 0.001))
	var dz := ds.machines.by_id(5)
	var worn := 0
	for b in ds.terrain.wear:
		if b != 0:
			worn += 1
	return {"ground": g.ground_mm(), "loose": g.loose_mm(), "heights": hs, "dozer": [snappedf(dz.global_position.x, 0.01), snappedf(dz.global_position.z, 0.01), snappedf(dz.yaw, 0.001)], "worn": worn, "changed": g.modified_chunks().size()}

func _process(dt: float) -> bool:
	t += dt
	if t > 120.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var ds: DigSite = arena.digsite
	match step:
		0:
			if t > 1.5:
				arena.godmode = true
				check(DsSave.path(ds) == save_at + ".digsite", "it's kept beside the game's save (%s)" % DsSave.path(ds))
				if phase == 1 and FileAccess.file_exists(DsSave.path(ds)):
					DirAccess.remove_absolute(DsSave.path(ds))
				arena.phone.travel("digsite")
				_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				var dz := ds.machines.by_id(5) as DsDozer
				if phase == 2:
					var was: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_at + ".facts"))
					v.from = Vector3(was.from[0], 0.0, was.from[1])
					v.fwd = Vector3(was.fwd[0], 0.0, was.fwd[1])
					var now := _facts()
					check(int(now.ground) == int(was.ground) and int(now.loose) == int(was.loose), "a new game: not a millimetre of its ground different (%d, %d; %d loose)" % [now.ground, was.ground, now.loose])
					var same := true
					for k in 12:
						if absf(float(now.heights[k]) - float(was.heights[k])) > 0.002:
							same = false
					check(same, "the dozer's cut's where it was (%s)" % str(now.heights))
					check(absf(float(now.dozer[0]) - float(was.dozer[0])) < 0.02 and absf(float(now.dozer[1]) - float(was.dozer[1])) < 0.02 and absf(float(now.dozer[2]) - float(was.dozer[2])) < 0.01, "the dozer's parked where it was left (%s)" % str(now.dozer))
					check(int(now.worn) == int(was.worn) and int(now.worn) > 0, "the grass is worn where it was (%d columns)" % now.worn)
					check(int(now.changed) == int(was.changed) and int(now.changed) > 0, "and it's still what's changed from the ground as made (%d chunks: saved again next time)" % now.changed)
					return _done()
				v.from = dz.global_position
				v.fwd = dz.forward()
				v.ground = ds.terrain.grid.ground_mm()
				ds._put(dz.global_position - dz.right() * (dz.width * 0.5 + 0.8) + Vector3(0, 0.05, 0), 0.0, 0.0)
				ds.machines._process(0.0)
				ds.machines.use()
				dz.auto = true
				dz.lift = -0.2
				dz.throttle = 1.0
				_next(2)
		2:
			var dz := ds.machines.by_id(5) as DsDozer
			if t - mark > 5.0:
				dz.throttle = 0.0
				_next(3)
		3:
			if t - mark > 3.0:               # (the heap settled)
				var f := _facts()
				check(f.heights != [] and int(f.loose) > 100000 and int(f.ground) == int(v.ground), "the dozer's cut and pushed a heap (%d mm loose)" % f.loose)
				f["from"] = [v.from.x, v.from.z]
				f["fwd"] = [v.fwd.x, v.fwd.z]
				v.facts = f
				var t0 := Time.get_ticks_msec()
				ds.home()
				var ms := Time.get_ticks_msec() - t0
				check(FileAccess.file_exists(DsSave.path(ds)), "going home, it's saved (%d bytes, %d ms with the trip)" % [FileAccess.get_file_as_bytes(DsSave.path(ds)).size(), ms])
				var t1 := Time.get_ticks_usec()
				ds.active = true
				DsSave.save(ds)
				ds.active = false
				check((Time.get_ticks_usec() - t1) / 1000.0 < 40.0, "a save takes no time to notice (%.1f ms)" % ((Time.get_ticks_usec() - t1) / 1000.0))
				var ff := FileAccess.open(save_at + ".facts", FileAccess.WRITE)
				ff.store_string(JSON.stringify(f))
				ff.close()
				return _done()
	return false
