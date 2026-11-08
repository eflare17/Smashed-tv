extends SceneTree
## Getting to the machines the way a player does (headless: --fixed-fps 60 -s test/voxel/digsite_walkin_test.gd --
## --nosave): travel to the Dig Site, then walk from where you arrive (the gate) to the Dingo holding W, the real key,
## and press E, the real key, to get on. (The owner, 8 Nov: "I saw the dig site, but I couldn't get to the machines":
## a wall round the site the tests never walked into.) Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSWALK ok   ", what)
	else:
		failed += 1
		print("DSWALK FAIL ", what)

func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _process(dt: float) -> bool:
	t += dt
	if t > 60.0:
		check(false, "timed out at step %d" % step)
		print("DSWALK done %d passed, %d failed" % [passed, failed])
		return true
	var ds: DigSite = arena.digsite
	match step:
		0:
			if t > 1.5:
				arena.phone.travel("digsite")
				step = 1
				mark = t
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				print("DSWALK   arrived at %s" % str(arena.player.global_position))
				step = 2
				mark = t
		2:
			# face the Dingo and walk at it
			var d: DsMachine = ds.machines.list[0]
			var p: Vector3 = arena.player.global_position
			var to := d.global_position - p
			arena.look_yaw = atan2(-to.x, -to.z)
			arena.look_pitch = 0.0
			_key(KEY_W, true)
			if ds.machines.near == d or t - mark > 15.0:
				_key(KEY_W, false)
				check(ds.machines.near == d, "walked from the gate to the Dingo (%.1f m from it, at %s)" % [Vector2(to.x, to.z).length(), str(p)])
				_key(KEY_E, true)
				step = 3
				mark = t
		3:
			if t - mark > 0.3:
				_key(KEY_E, false)
				check(ds.machines.driving == ds.machines.list[0], "E gets you on it")
				print("DSWALK done %d passed, %d failed" % [passed, failed])
				return true
	return false
