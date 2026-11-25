extends SceneTree
## "Demolition" (VoxelDemolition): 7 on the phone takes you to the town block; its eight buildings are all there and
## counted; a blast knocks blocks out and the score rises; a wide hole low in the tower block leaves blocks hanging and
## they come down; the water tower's legs knocked out brings the tank down; the crane drives, its ball swings with real
## speed and a swing smashes a wall; the share down and the clock track; hitting the target keeps a best in
## user://demolition.cfg; the phone home takes the lot away and leaves the arena as it was.
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/demolition_test.gd
## Prints PASS / FAIL lines and "DEMOLITION: X passed, Y failed". Owned by the Demolition session.

const D := preload("res://scripts/voxel/demolition/voxel_demolition.gd")

var arena: VoxelArena
var dem: VoxelDemolition
var t := 0.0
var step := 0
var passed := 0
var failed := 0
var had_best := false
var blocks0 := 0
var down0 := 0
var fell := 0
var tank0 := 0
var tank_fell := 0
var swing_top := 0.0             # the fastest the ball went
var ball0 := Vector3.ZERO
var crane_at := Vector3.ZERO
var home_at := Vector3.ZERO
var was_frozen := false
var left0 := 0.0
var swing_t := 0.0
var hit_down := 0

func _initialize() -> void:
	had_best = FileAccess.file_exists(D.BEST_FILE)
	seed(20261125)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)

func _hold(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _of(nm: String) -> VoxelBreakables.Building:
	for b in dem.breaks.list:
		if String(b.data.id) == nm:
			return b
	return null

# the middle of a building's wall, a metre or so up and just outside it
func _wall_spot(b: VoxelBreakables.Building, c: int, y: float) -> Vector3:
	var cc: Dictionary = b.cols[c]
	var n: Vector2 = cc.n
	var at: Vector3 = b.block_at(c, 0)
	return Vector3(at.x + n.x * 0.3, y, at.z + n.y * 0.3)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 or (arena.phone and arena.phone._going):
		return false
	match step:
		0:
			arena.waves.queue.clear()
			arena.godmode = true
			home_at = arena.player.global_position
			was_frozen = arena.frozen
			_key(KEY_P)
			step = 1
			t = 1.0
		1:
			_key(KEY_7)                       # (Demolition: last on the phone)
			step = 2
			t = 0.0
		2:
			dem = arena.demolition
			_check(dem.active and dem.running, "7 on the phone: Demolition on, the run going")
			_check(dem.breaks.list.size() == D.TOWN.size(), "%d buildings built" % dem.breaks.list.size())
			var all := true
			var names := []
			for spec in D.TOWN:
				var b := _of(String(spec.name))
				if b == null or b.standing <= 0 or b.cols.is_empty():
					all = false
				else:
					names.append("%s %d" % [spec.name, b.standing])
			_check(all, "every one registered with blocks standing (%s)" % ", ".join(names))
			blocks0 = dem.blocks0
			_check(blocks0 > 400, "%d blocks in the block" % blocks0)
			_check(dem.down() == 0 and dem.share() == 0.0, "nothing down yet")
			_check(_of("WaterTower").standing < _of("WaterTower").alive.size(),
					"the water tower's on legs (%d of %d blocks)" % [_of("WaterTower").standing, _of("WaterTower").alive.size()])
			var glassy := 0
			for c in _of("Office").cols.size():
				if bool(_of("Office").cols[c].glass):
					glassy += 1
			_check(glassy > _of("Office").cols.size() / 3, "the office is glass-fronted (%d columns glazed)" % glassy)
			left0 = dem.left()
			step = 3
			t = 0.0
		3:
			# a blast on the brick shop: a hole in it, the score up
			var shop := _of("BrickShop")
			dem.breaks.blast(_wall_spot(shop, 2, 1.6), 2.6)
			_check(dem.down() > 0, "a blast knocks blocks out (%d down)" % dem.down())
			_check(dem.share() > 0.0 and dem.share() < 0.2, "the share down tracks it (%.1f%%)" % (dem.share() * 100.0))
			down0 = dem.down()
			# a wide hole low in the tower block: what's over it has nothing holding it up
			var tower := _of("TowerBlock")
			for c in [3, 6, 9]:
				dem.breaks.blast(_wall_spot(tower, c, 1.2), 2.6)
			fell = dem.breaks.falling_count()
			_check(fell > 0, "a wide hole low in the tower block: %d blocks coming down" % fell)
			_check(dem.down() > down0, "the score rose with it (%d down)" % dem.down())
			step = 4
			t = 0.0
		4:
			if t < 2.5:
				return false              # (let them land and smash)
			_check(dem.breaks.bricks_lying() > 0, "%d bricks lying in the street" % dem.breaks.bricks_lying())
			# the water tower: its legs out from under it
			var tank := _of("WaterTower")
			tank0 = tank.standing
			for k in tank.ring.size():
				var a: Vector2 = tank.ring[k]
				var mid := Vector2.ZERO
				for v in tank.ring:
					mid += v
				mid /= tank.ring.size()
				if k < 2:                 # (two of its four legs)
					var p := a + (mid - a).normalized() * 0.4
					dem.breaks.blast(Vector3(p.x, 1.4, p.y), 2.8)
			tank_fell = dem.breaks.falling_count()
			_check(tank.standing < tank0 - 8, "the water tower's legs out: %d of %d blocks gone with them" % [tank0 - tank.standing, tank0])
			_check(tank_fell > 0, "the tank comes down (%d blocks falling)" % tank_fell)
			step = 5
			t = 0.0
		5:
			if t < 2.0:
				return false
			# the crane: put it in the street facing the office, get in, drive
			var office := _of("Office")
			var face := _wall_spot(office, 2, 1.0)
			# beside the office's back wall, the boom pointing along it: swinging the boom round carries the ball into it
			dem.crane.place(Vector3(face.x - 13.0, 0.0, face.z - 3.0), -PI / 2.0)
			_check(not dem.crane.driving, "the crane's parked")
			dem.crane.enter()
			_check(dem.crane.driving, "E: in the cab")
			crane_at = dem.crane.pos
			ball0 = dem.crane.ball
			_hold(KEY_W, true)
			step = 6
			t = 0.0
		6:
			if t < 1.2:
				return false
			_hold(KEY_W, false)
			_check(dem.crane.pos.distance_to(crane_at) > 1.0, "it drives (%.1f m)" % dem.crane.pos.distance_to(crane_at))
			_check(arena.player.global_position.distance_to(dem.crane.seat()) < 0.2, "you're in the seat, not walking")
			_check(dem.crane.ball.distance_to(ball0) > 0.5, "the ball's come with it, swinging behind")
			# the boom swung out away from the wall, then back round: the ball comes at it with real speed
			_hold(KEY_LEFT, true)
			hit_down = dem.down()
			step = 7
			t = 0.0
		7:
			swing_top = maxf(swing_top, dem.crane.ball_speed())
			if t < 1.4:
				return false
			_hold(KEY_LEFT, false)
			_hold(KEY_RIGHT, true)
			step = 8
			t = 0.0
		8:
			swing_top = maxf(swing_top, dem.crane.ball_speed())
			swing_t += dt
			if swing_t < 5.0:
				return false
			_hold(KEY_RIGHT, false)
			_check(swing_top > 2.5 and swing_top < VoxelWreckingCrane.MAX_V - 1.0,
					"the ball swings with weight behind it, and the cable never catapults it (%.1f m/s at its fastest)" % swing_top)
			_check(dem.crane.smashes > 0, "a swing smashes the wall (%d holes, %d chips)" % [dem.crane.smashes, dem.crane.chips])
			_check(dem.down() > hit_down + 5, "the crane's own score: %d blocks down to it" % (dem.down() - hit_down))
			_check(dem.left() < left0 - 5.0, "the clock's running down (%.0f s left of %.0f)" % [dem.left(), left0])
			dem.crane.leave()
			_check(not dem.crane.driving and arena.player.global_position.distance_to(dem.crane.kerb()) < 0.5, "E: out, on the kerb")
			step = 9
			t = 0.0
		9:
			# the target hit: the banner, the best kept (the block's counted down to what's already down)
			dem.blocks0 = ceili(float(dem.standing()) / (1.0 - D.TARGET))     # (as if the block had been this much bigger)
			step = 10
			t = 0.0
		10:
			if t < 0.2:
				return false
			_check(dem.won and dem.over and not dem.running, "the target hit: the run's done")
			_check(dem._end.visible and dem._end.text.contains("THE BLOCK'S DOWN"), "the banner's up")
			_check(dem.best_time > 0.0 and dem.best_score > 0, "a best kept (%s, %d blocks)" % [VoxelParkGame._clock(dem.best_time), dem.best_score])
			var cf := ConfigFile.new()
			_check(cf.load(D.BEST_FILE) == OK and float(cf.get_value("best", "time", 0.0)) > 0.0, "and written to %s" % D.BEST_FILE)
			step = 11
			t = 0.0
		11:
			_key(KEY_P)
			step = 12
			t = 0.5
		12:
			_key(KEY_1)                       # (Home)
			step = 13
			t = 0.0
		13:
			if t < 0.5:
				return false
			_check(not dem.active and not dem.running, "the phone home: Demolition's off")
			var standing := 0
			for b in dem.breaks.list:
				standing += b.standing
			_check(standing == blocks0, "every building built again (%d blocks of %d)" % [standing, blocks0])
			_check(dem.breaks.bricks_lying() == 0 and dem.breaks.falling_count() == 0 and dem.breaks.bricks_flying() == 0,
					"the rubble's gone")
			_check(not dem.visible and dem.process_mode == Node.PROCESS_MODE_DISABLED, "the level's put away")
			_check(arena.player.global_position.distance_to(home_at) < 1.5, "you're back where you were in the arena")
			_check(arena.frozen == was_frozen and not VoxelBody.wall_at.is_valid(), "the arena's as it was")
			_check(arena.demolition.crane.pos.distance_to(D.AT + D.CRANE_AT) < 0.01, "the crane's parked again")
			step = 99
		99:
			if not had_best:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(D.BEST_FILE))
			print("DEMOLITION: %d passed, %d failed" % [passed, failed])
			print("PASS" if failed == 0 else "FAIL")
			quit(0 if failed == 0 else 1)
	return false
