extends SceneTree
## Every weapon on St Kilda's walls (VoxelBreakables.strike and the rest, from each weapon): stood before a building's
## wall, each weapon taken out and used as you would (a click, or the button held), each at its own bit of the wall:
## the sledgehammer, bat, chainsaw, spear, sword (a chip), laser, harpoon, gravity gun and pick knock bricks out; the
## flamethrower scorches it (no bricks out); the freeze ray freezes it and its ice shot shatters what's frozen; and the
## shovel scoops the rubble lying at the wall's foot into the backpack. -- --out=dir for pictures (under a display,
## Forward+). Prints PASS or FAIL. Owned by the St Kilda session.

# weapon, metres from the wall, look up (radians), seconds held (0: a click), what it should do
const RUNS := [
	["hammer", 1.8, 0.0, 0.0, "bricks"],
	["bat", 1.5, 0.0, 0.0, "bricks"],
	["chainsaw", 1.0, -0.1, 1.5, "bricks"],
	["spear", 2.0, 0.0, 0.0, "bricks"],
	["sword", 1.6, 0.0, 0.0, "chip"],
	["laser", 5.0, 0.0, 1.0, "bricks"],
	["harpoon", 6.0, 0.0, 0.0, "bricks"],
	["gravity", 6.0, 0.0, 0.0, "bricks"],
	["pick", 1.8, 0.0, 0.0, "bricks"],
	["flamethrower", 3.0, 0.0, 1.5, "scorch"],
	["freezeray", 5.0, 0.0, 1.5, "freeze"],
	["shovel", 3.4, -0.75, 0.0, "scoop"],         # (back where the hammer's bricks landed, looking down at them)
]

var arena: VoxelArena
var sk: VoxelStKilda
var b: VoxelBreakables.Building
var t := 0.0
var step := 0
var run := 0
var phase := 0
var out := ""
var fails := []
var c0 := 0
var before := 0
var damaged0 := 0
var bricks0 := 0

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

func _mouse(button: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func _damaged() -> int:
	var n := 0
	for d in b.damaged:
		n += d
	return n

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
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# the longest straight wall of the biggest of the town's buildings
			for bb in sk.breaks.list:
				if not bb.over and (b == null or bb.alive.size() > b.alive.size()):
					b = bb
			var best := 0
			var run_n := 0
			for k in b.cols.size():
				run_n = run_n + 1 if k > 0 and (b.cols[k].dir as Vector2).is_equal_approx(b.cols[k - 1].dir) else 1
				if run_n > best:
					best = run_n
					c0 = k - run_n + 1
			c0 += 2
			step = 1
			t = 0.0
		1:
			var r: Array = RUNS[run]
			match phase:
				0:
					# stood before its own bit of the wall (3 blocks apart), facing it, the weapon out
					var c := c0 if String(r[4]) == "scoop" else c0 + run * 3     # (the shovel: at the hammer's rubble)
					var n: Vector2 = b.cols[c].n
					var at := b.block_at(c, 0) + Vector3(n.x, 0, n.y) * (float(r[1]) + VoxelBreakables.THICK * 0.5)
					sk._put(Vector3(at.x, 0.05, at.z), atan2(n.x, n.y), float(r[2]))
					arena._switch(func(): arena.loadout.select(arena.loadout.index_of(String(r[0]))))
					before = b.chipped
					damaged0 = _damaged()
					bricks0 = arena.inv.count("brick")
					phase = 1
					t = 0.0
				1:
					if t > 0.7:
						_mouse(MOUSE_BUTTON_LEFT, true)
						if float(r[3]) == 0.0:
							_mouse(MOUSE_BUTTON_LEFT, false)
						phase = 2
						t = 0.0
				2:
					if t > float(r[3]):
						if float(r[3]) > 0.0:
							_mouse(MOUSE_BUTTON_LEFT, false)
						if String(r[4]) == "freeze":
							_check(b.any_frozen, "freezeray: the wall's frozen")
							# its ice shot (the right click) at it: what's frozen shatters
							before = b.chipped
							_mouse(MOUSE_BUTTON_RIGHT, true)
							_mouse(MOUSE_BUTTON_RIGHT, false)
						phase = 3
						t = 0.0
				3:
					if t > 1.2:
						var got := b.chipped - before
						match String(r[4]):
							"bricks":
								_check(got >= 2, "%s: bricks knocked out of the wall (%d)" % [r[0], got])
							"chip":
								_check(got >= 1 and got <= 3, "%s: just a chip off the wall (%d)" % [r[0], got])
							"scorch":
								_check(_damaged() > damaged0 and got == 0, "%s: the wall scorched, no bricks out" % r[0])
							"freeze":
								_check(got >= 5, "freezeray: its ice shot shatters what's frozen (%d)" % got)
							"scoop":
								var gotb := arena.inv.count("brick") - bricks0
								_check(gotb > 0, "%s: rubble scooped into the backpack (%d bricks)" % [r[0], gotb])
						_shot("weapons_%s" % r[0])
						run += 1
						phase = 0
						t = 0.0
						if run >= RUNS.size():
							step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
