extends SceneTree
## "Luna Park: Invasion" (VoxelParkInvasion): 6 on the phone starts it; every ride with seats has enemies riding it (the
## scenery riders they replace hidden); a rider stays on its seat as the ride moves and is hit where it's drawn; one
## shot dead (VoxelArena.fire) drops the count and falls off as a body; the rest of its ride get off; walking up to a
## ride gets them off too; a thrower throws from its seat; a ride cleared pays $20 and counts; a part of the park's
## group comes once; the lot cleared shows the banner and keeps a best time; Home takes every one away and puts the
## scenery riders back. Fixed seeds, the player put where it's wanted, kills through the bodies' own damage.
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/luna_invasion_test.gd
## Prints PASS / FAIL lines and "LUNA INVASION: X passed, Y failed". Owned by the St Kilda session.

const I := preload("res://scripts/voxel/stkilda/voxel_park_invasion.gd")

var arena: VoxelArena
var sk: VoxelStKilda
var inv: VoxelParkInvasion
var t := 0.0
var step := 0
var passed := 0
var failed := 0
var had_best := false
var seats_hidden: Array = []     # [a seat, where they sat] of the scenery riders taken off
var victim: Dictionary
var vb: VoxelBody
var ride: Dictionary
var track: Array = []            # [rec, where its body was]
var left0 := 0
var cash0 := 0
var thrown0 := 0
var walker: Dictionary
var seat_y := 0.0
var sweep_t := 0.0
var sweep_n := 0

func _initialize() -> void:
	had_best = FileAccess.file_exists(VoxelParkInvasion.BEST_FILE)
	seed(20261124)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

func _park() -> Array:
	return arena.bodies.filter(func(b): return b.has_meta("park"))

# stood `back` m from a spot (toward where you arrive, so inside the park's wall or on the forecourt)
func _stand(at: Vector3, back: float) -> void:
	var home: Vector3 = sk.arrive_spot()[0]
	var d := Vector3(home.x - at.x, 0, home.z - at.z)
	d = d.normalized() if d.length() > 0.5 else Vector3(0, 0, -1)
	var p := at + d * back
	sk._put(Vector3(p.x, 0.05, p.z), atan2(d.x, d.z), 0.0)

func _made(r: Dictionary) -> bool:
	return r.body != null and is_instance_valid(r.body)

func _next(s: int) -> void:
	step = s
	t = 0.0

func _process(dt: float) -> bool:
	t += dt
	if arena.phone and arena.phone._going:
		return false
	match step:
		0:
			if t < 1.5:
				return false
			arena.waves.queue.clear()
			arena.godmode = true
			sk = arena.stkilda
			_check(VoxelPhone.PLACES.any(func(p): return p[0] == "invasion" and p[1] == "Luna Park: Invasion"), "the phone lists Luna Park: Invasion")
			_key(KEY_P)
			_next(1)
		1:
			if t > 0.2:
				_key(KEY_1 + VoxelPhone.PLACES.size() - 1)
				_next(2)
		2:
			if t < 0.3:
				return false
			inv = sk.invasion
			_check(sk.active and inv.running, "picked on the phone: in St Kilda, the invasion on")
			# again, with a fixed seed (the same riders and groups every run)
			inv.seed_ = 7
			inv.start()
			_check(inv.running and not sk.game.running and inv._hud.visible, "started again: running, its line on screen")
			_check(inv.rides.size() >= 8, "rides with seats found (%d)" % inv.rides.size())
			var thin := inv.rides.filter(func(r): return (r.riders as Array).size() < 2)
			_check(thin.is_empty(), "every one has 2 or more enemies riding (%s)" % ", ".join(inv.rides.map(func(r): return "%s %d" % [r.name, (r.riders as Array).size()])))
			_check(inv._hud.text.begins_with("Luna Park invasion: rides cleared 0/%d, enemies left %d" % [inv.rides.size(), inv.left()]), "the line: " + inv._hud.text)
			for h in inv._hidden:
				seats_hidden.append([h[0], h[1]])
			_check(not seats_hidden.is_empty() and seats_hidden.all(func(h): return ((h[0] as Array)[2] as Transform3D).basis.get_scale().x < 0.01),
				"the scenery riders they replace are hidden (%d)" % seats_hidden.size())
			left0 = inv.left()
			ride = inv.rides.filter(func(r): return r.name == "ConeyDrop")[0]     # (its seats are where they're drawn without a screen too)
			_stand((ride.node as Node3D).global_position, 14.0)
			_next(3)
		3:
			if t < 0.5:
				return false
			var made := inv._recs.filter(_made)
			_check((ride.riders as Array).all(_made), "near the Coney Drop its riders are real enemies (%d made in all)" % made.size())
			_check(made.all(func(r): return (r.body as VoxelBody).has_meta("riding") and (r.body as VoxelBody).has_meta("park")), "marked riding, and the park's")
			var far := inv._recs.filter(func(r): return not _made(r) and inv._seat_xf(r).origin.distance_to(arena.player.global_position) > I.NEAR_OFF)
			_check(not far.is_empty(), "the far rides' riders aren't made yet (%d waiting)" % far.size())
			track.clear()
			for r in made:
				track.append([r, (r.body as VoxelBody).global_position])
			_next(4)
		4:
			if t < 1.0:
				return false
			var moved := 0.0
			var off := 0.0
			var n := 0
			for tr in track:
				var r: Dictionary = tr[0]
				if not _made(r) or r.state != I.SEATED:
					continue
				var b: VoxelBody = r.body
				n += 1
				moved = maxf(moved, b.global_position.distance_to(tr[1]))
				off = maxf(off, b.global_position.distance_to(inv._body_xf(b, inv._seat_xf(r)).origin))
			_check(n > 0 and moved > 0.2, "a rider goes round with its ride (%.2f m in a second, %d watched)" % [moved, n])
			_check(off < 0.3, "each is where its seat is (%.3f m off at most)" % off)
			# one on the Coney Drop, hit where it's drawn
			victim = (ride.riders as Array).filter(func(r): return r.state == I.SEATED and _made(r))[0]
			vb = victim.body
			var aim := vb.skeleton.global_transform * vb.skeleton.get_bone_global_pose(vb.model.bone("head")).origin
			var from := aim + Vector3(0.3, 2.0, 0.2)
			var h := vb.trace(from, (aim - from).normalized(), 10.0)
			_check(not h.is_empty() and aim.y > 0.8, "a ray at its head, up on the ride (%.1f m up), hits it: %s" % [aim.y, h.get("part", "nothing")])
			left0 = inv.left()
			seat_y = vb.global_position.y
			_next(5)
		5:
			# shot (the guns' own fire) from just above its head till it drops
			if vb.alive and t < 4.0:
				for k in 4:
					if not vb.alive:
						break
					var aim := vb.skeleton.global_transform * vb.skeleton.get_bone_global_pose(vb.model.bone("head")).origin
					var from := aim + Vector3(0.05, 1.2, 0.0)
					arena.fire(from, (aim - from).normalized(), 1, 0.0, 4.0)
				return false
			_check(not vb.alive, "shot dead on its seat")
			_check(inv.kills == 1 and inv.left() == left0 - 1, "a kill counted, one fewer left (%d, was %d)" % [inv.left(), left0])
			_next(6)
		6:
			if t < 0.1:
				return false
			_check(not vb.has_meta("riding") and (vb.airborne or vb.global_position.y < seat_y - 0.05), "the body's let go and falling (%.2f m up, was %.2f)" % [vb.global_position.y, seat_y])
			_next(7)
		7:
			if t < 2.5:
				return false
			var mid := (ride.node as Node3D).global_position
			_check(is_instance_valid(vb) and arena.bodies.has(vb) and vb.global_position.y < 0.2 and vb.global_position.distance_to(mid) < 30.0,
				"it's lying by the ride (%.1f m from its middle, %.2f m up)" % [vb.global_position.distance_to(mid), vb.global_position.y])
			var still := (ride.riders as Array).filter(func(r): return r.state == I.SEATED and r.kind != "thrower")
			_check(ride.alert and still.is_empty(), "their ride hit: the rest (not throwers) got off")
			var offs := (ride.riders as Array).filter(func(r): return r.state == I.OFF and _made(r))
			_check(offs.all(func(r): return not (r.body as VoxelBody).has_meta("riding") and (r.body as VoxelBody).global_transform.basis.is_equal_approx(Basis.IDENTITY)),
				"those that got off are the arena's to walk (%d)" % offs.size())
			# the ride cleared: the others killed (their own hurt)
			var rest := (ride.riders as Array).filter(func(r): return r.state != I.DEAD)
			for k in rest.size():
				if k == rest.size() - 1:
					cash0 = arena.cash
					_check(inv.paid == 0 and not ride.cleared, "not cleared while one's left")
				(rest[k].body as VoxelBody).hurt(99999.0)
			var pay := arena.cash - cash0                 # (the ride's $20, the kill's own cash, the announcer's bonus if there's one)
			_check(ride.cleared and inv.cleared == 1, "the Coney Drop cleared (%d ride)" % inv.cleared)
			_check(inv.paid == I.RIDE_CASH and pay >= I.RIDE_CASH, "clearing it paid $%d (your cash up $%d with the kill's)" % [inv.paid, pay])
			_next(8)
		8:
			if t < 0.3:
				return false
			_check(inv._hud.text.contains("rides cleared 1/%d" % inv.rides.size()), "the line: " + inv._hud.text)
			# walking up to a ride: a rider (not a thrower) on a low seat gets off
			var low := inv._recs.filter(func(r): return r.state == I.SEATED and r.kind != "thrower" and inv._seat_xf(r).origin.y < 4.0 and not (r.at as Dictionary).has("car"))
			if low.is_empty():
				_check(false, "a low seat to walk up to")
				_next(10)
				return false
			walker = low[0]
			_stand(inv._seat_xf(walker).origin, 5.0)
			_next(9)
		9:
			if t < 2.0:
				return false
			var b: VoxelBody = walker.body
			_check(walker.state == I.OFF and _made(walker) and not b.has_meta("riding") and b.global_position.y < 0.3,
				"within %d m: it's off the %s and on the ground" % [int(I.GET_OFF), inv.rides[int(walker.ride)].title])
			_next(10)
		10:
			# a thrower throws from its seat
			var th := inv._recs.filter(func(r): return r.state == I.SEATED and r.kind == "thrower" and not (r.at as Dictionary).has("car"))
			if th.is_empty():
				_check(false, "a thrower on a ride (this seed)")
				_next(12)
				return false
			walker = th[0]
			_stand(inv._seat_xf(walker).origin, 13.0)
			thrown0 = arena.kinds.thrown
			_next(11)
		11:
			if arena.kinds.thrown == thrown0 and t < 8.0:
				return false
			_check(arena.kinds.thrown > thrown0 and walker.state == I.SEATED, "a thrower on the %s throws at you, still sat (%d thrown)" % [inv.rides[int(walker.ride)].title, arena.kinds.thrown - thrown0])
			_next(12)
		12:
			# a part of the park's group comes once
			var a: Dictionary = inv.areas.filter(func(x): return x.name == "Coney Drop")[0]
			_check(a.done and int(a.came) + inv._due.count(inv.areas.find(a)) == int(a.n), "the Coney Drop's group came: %d of %d in, the rest due" % [a.came, a.n])
			var un := inv.areas.filter(func(x): return not x.done)
			_check(not un.is_empty(), "the parts you haven't been near haven't sent theirs (%d waiting)" % un.size())
			_stand(a.at, 60.0)
			_next(13)
		13:
			if t < 0.3:
				return false
			var a: Dictionary = inv.areas.filter(func(x): return x.name == "Coney Drop")[0]
			_stand(a.at, 10.0)
			_next(14)
		14:
			if t < 1.0:
				return false
			var a: Dictionary = inv.areas.filter(func(x): return x.name == "Coney Drop")[0]
			_check(int(a.came) + inv._due.count(inv.areas.find(a)) == int(a.n) and int(a.more) == 0, "away and back: no second group (%d of %d)" % [a.came, a.n])
			_next(15)
		15:
			# the lot: stood by each part and each rider not made yet in turn, everything alive killed (its own hurt)
			inv._gap = 0.0
			for b in _park():
				if b.alive:
					b.hurt(99999.0)
			sweep_t -= dt
			if inv.running and sweep_t <= 0.0:
				sweep_t = 0.12
				var todo := []
				for a in inv.areas:
					if not a.done:
						todo.append(a.at)
				for r in inv._recs:
					if r.state == I.SEATED and not _made(r):
						todo.append(inv._seat_xf(r).origin)
				if not todo.is_empty():
					sweep_n += 1
					_stand(todo[sweep_n % todo.size()], 6.0)
			if inv.running and t < 60.0:
				return false
			_check(inv.over and not inv.running and inv.left() == 0, "everything killed: over (%d left, %.0f s of sweeping)" % [inv.left(), t])
			_check(inv.cleared == inv.rides.size(), "every ride cleared (%d/%d)" % [inv.cleared, inv.rides.size()])
			_check(inv._end.visible and inv._end.text.begins_with("LUNA PARK CLEARED") and inv._end.text.contains(VoxelParkGame._n(inv.kills)), "the banner: " + inv._end.text.replace("\n", " | "))
			var cf := ConfigFile.new()
			_check(cf.load(VoxelParkInvasion.BEST_FILE) == OK and float(cf.get_value("best", "time", 0.0)) > 0.0 and inv.best_time > 0.0, "a best time kept (%.1f s)" % inv.best_time)
			_check(inv.kills >= left0, "the kills counted (%d)" % inv.kills)
			_next(16)
		16:
			if t < 0.3:
				return false
			sk.home()
			_check(not sk.active and not inv.running and not inv.over and not inv._hud.visible and not inv._end.visible, "Home: stopped, nothing on screen")
			_check(_park().is_empty(), "its enemies all gone (%d left)" % _park().size())
			_check(inv._hidden.is_empty() and seats_hidden.all(func(h): return ((h[0] as Array)[2] as Transform3D).is_equal_approx(h[1])), "the scenery riders back on their seats")
			_next(99)
		99:
			if not had_best:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(VoxelParkInvasion.BEST_FILE))
			print("LUNA INVASION: %d passed, %d failed" % [passed, failed])
			quit(0 if failed == 0 else 1)
	return false
