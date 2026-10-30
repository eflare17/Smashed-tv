extends SceneTree
## Luna Park's own buildings you can smash (VoxelBreakables.add_park): in St Kilda, stood before the Ghost Train with
## the pistol out, looking at it, clicks (as you would) knock its blocks out; a grenade's blast at a shop's foot
## knocks a hole; and the trip home builds them again. -- --out=dir for pictures (under a display, Forward+).
## Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var gt: VoxelBreakables.Building
var shop: VoxelBreakables.Building
var t := 0.0
var step := 0
var out := ""
var fails := []
var start := 0
var snapped := false
var frames := 0
var gc := 0
var stood := Vector3.ZERO
var stood_yaw := 0.0

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _click() -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		Input.parse_input_event(e)

func _named(nm: String) -> VoxelBreakables.Building:
	for b in sk.breaks.list:
		if String(b.data.get("id", "")) == nm:
			return b
	return null

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			gt = _named("GhostTrain")
			shop = _named("CafeLuna")
			_check(gt != null, "the Ghost Train's breakable")
			_check(shop != null, "Cafe Luna's breakable")
			_check(_named("LunaPalace") != null, "Luna Palace is breakable")
			if gt == null:
				step = 99
				return false
			start = gt.standing
			# 10 m out from the middle of its front, facing it, the pistol out
			var c := 0
			var best := -INF
			var spot = sk.get_meta("luna_spots", {}).get("Luna Park - Ghost Train")
			var me: Vector3 = spot[0] if spot else gt.block_at(0, 0)
			for k in gt.cols.size():
				var d := -gt.block_at(k, 0).distance_to(me)
				if d > best:
					best = d
					c = k
			var n: Vector2 = gt.cols[c].n
			var at := gt.block_at(c, 0) + Vector3(n.x, 0, n.y) * 10.0
			gc = c
			stood = Vector3(at.x, 0.05, at.z)
			stood_yaw = atan2(n.x, n.y)
			sk._put(stood, stood_yaw, 0.12)
			arena._switch(func(): arena.loadout.select(arena.loadout.index_of("pistol")))
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			step = 1
			t = 0.0
		1:
			if t > 1.0 and not snapped:
				snapped = true
				_shot("luna_before")
			if t > 1.5:
				step = 2
				t = 0.0
		2:
			if t < 3.0:
				if fmod(t, 0.3) < dt:
					_click()
				return false
			_check(not gt.whole, "clicking at it: in blocks now")
			_check(gt.chipped > 0, "bricks knocked out (%d)" % gt.chipped)
			_check((sk.get_node("GhostTrain") as Node3D).visible, "its own model still there (holes in it)")
			_shot("luna_shot")
			step = 20
			t = 0.0
		20:
			if t < 0.6:
				return false
			snapped = false
			# a grenade's blast at Cafe Luna's foot
			var c := 0
			var far := INF
			var mid := sk.arrive_spot()[0] as Vector3
			for k in shop.cols.size():
				var d := Vector2(shop.block_at(k, 0).x - mid.x, shop.block_at(k, 0).z - mid.z).length()
				if d < far:
					far = d
					c = k
			start = shop.standing
			arena.melee["grenades"].explode(shop.block_at(c, 0) + Vector3((shop.cols[c].n as Vector2).x, 0, (shop.cols[c].n as Vector2).y) * 0.3, "bench")
			_check(shop.standing < start, "a blast at Cafe Luna: a hole (%d)" % (start - shop.standing))
			# and one at the foot of the Ghost Train's front, seen from where you stood
			var gn: Vector2 = gt.cols[gc].n
			arena.melee["grenades"].explode(gt.block_at(gc + 3, 0) + Vector3(gn.x, 0, gn.y) * 0.3, "bench")
			sk._put(stood, stood_yaw, 0.12)
			step = 3
			t = 0.0
		3:
			if t > 1.2 and not snapped:
				snapped = true
				_shot("luna_blast")
				step = 4
				frames = 0
		4:
			frames += 1
			if frames > 10:
				sk.home()
				_check(gt.whole and shop.whole and (sk.get_node("GhostTrain") as Node3D).visible, "home: built again")
				step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
