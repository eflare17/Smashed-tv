extends SceneTree
## The barbecue (headless): in the back yard, solid; looked at with nothing to cook it says how to get a carcass; E
## puts a chicken carcass from the backpack on the grill (three at most, the fourth stays in the backpack); it browns
## as it cooks; cooked after COOK_T, E takes it off as a roast chicken; left past BURN_T it's a burnt chicken; H eats a
## roast chicken (VoxelChickens' item, as a flamethrower's kill), only when hurt; sold at the buyer; the burnt one in the shredder; top-down, E
## standing at it; saved and loaded mid-cook. With --host=CODE / --join=CODE (two copies, the host first): the guest
## puts a carcass on the host's grill, it cooks in both games, the guest takes it off (a roast chicken in the guest's
## backpack, not the host's). Prints "BBQ ok/FAIL ..." and "BBQ done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var v0 := {}

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("BBQ %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	arena._unhandled_input(e)

func _bbq() -> VoxelBarbecue:
	return arena.yard.barbecue

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

# stand in front of the barbecue (on the yard's side) looking at its grill
func _look_at_grill() -> void:
	var g := VoxelBarbecue.AT + Vector3(0, VoxelBarbecue.GRILL_Y, 0)
	var from := VoxelBarbecue.AT + Vector3(0.0, 0, -1.3)
	_place(from, 0.0, 0.0)
	var to := g - (from + Vector3(0, 1.65, 0))
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _near() -> String:
	arena._camera(0.0)
	arena._storage_step(0.0)
	return arena._near_bbq

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	var bb := _bbq()
	match step:
		0:
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			arena.frozen = true
			arena.inv.from_data([])
			arena.cash = 0
			bb.from_data({})
			check(VoxelYard.in_yard(VoxelBarbecue.AT) and bb.get_parent() == arena.yard, "the barbecue in the back yard")
			var q := PhysicsRayQueryParameters3D.create(VoxelBarbecue.AT + Vector3(0, 0.5, -1.5), VoxelBarbecue.AT + Vector3(0, 0.5, 0))
			v0.solid = not arena.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
			_look_at_grill()
			mark = t
			step = 1
		1:
			if t - mark > 0.3:
				check(bool(v0.solid), "solid (you bump into it)")
				var n := _near()
				check(n == "grill" and arena._use_label.text.contains("kill a chicken"), "looked at, nothing to cook: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena._say_text.contains("Nothing to cook"), "E with no carcass: \"%s\"" % arena._say_text)
				arena.inv.add("chicken_carcass", 4)
				_near()
				check(arena._use_label.text.contains("put a chicken carcass on (4"), "with carcasses: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(float(bb.grill[0]) == 0.0 and arena.inv.count("chicken_carcass") == 3, "E: one on the grill (3 left in the backpack)")
				for i in 3:
					bb.put()
				check(bb._free() == -1 and arena.inv.count("chicken_carcass") == 1, "three on the grill at most, the fourth stays in the backpack")
				bb._show(0.016)
				var v: Node3D = bb._views[0]
				check(v != null and v.has_meta("mat"), "a carcass shown on the grill")
				v0.raw = (v.get_meta("mat") as StandardMaterial3D).albedo_color
				bb.grill[1] = -1.0
				bb.grill[2] = -1.0
				arena.inv.add("chicken_carcass", 2)
				bb.grill[0] = VoxelBarbecue.COOK_T * 0.5
				_near()
				check(arena._use_label.text.contains("cooking 50%"), "cooking: \"%s\"" % arena._use_label.text)
				bb._show(0.016)
				var half: Color = (v.get_meta("mat") as StandardMaterial3D).albedo_color
				check(half.v < (v0.raw as Color).v and half.b < half.r, "it browns as it cooks")
				check(bb._light.light_energy > 0.0 or bb._lit > 0.0, "the burners going")
				_key(KEY_E)
				check(arena.inv.count("roast_chicken") == 0 and float(bb.grill[1]) == 0.0, "E while it's cooking: another goes on, nothing comes off")
				bb.grill[1] = -1.0
				arena.inv.add("chicken_carcass", 1)
				bb.grill[0] = VoxelBarbecue.COOK_T - 0.05
				mark = t
				step = 2
		2:
			if t - mark > 0.3:
				check(VoxelBarbecue.state_of(float(bb.grill[0])) == "cooked" and arena._say_text.contains("roasted"), "roasted after %d s, and says so: \"%s\"" % [int(VoxelBarbecue.COOK_T), arena._say_text])
				_near()
				check(arena._use_label.text.contains("take off 1 roast chicken"), "roasted: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("roast_chicken") == 1 and float(bb.grill[0]) < 0.0, "E: a roast chicken in the backpack, the grill empty")
				# burnt
				bb.put()
				bb.grill[0] = VoxelBarbecue.BURN_T - 0.05
				mark = t
				step = 3
		3:
			if t - mark > 0.3:
				check(VoxelBarbecue.state_of(float(bb.grill[0])) == "burnt", "left on past %d s: burnt" % int(VoxelBarbecue.BURN_T))
				bb._show(0.016)
				var c: Color = (bb._views[0].get_meta("mat") as StandardMaterial3D).albedo_color
				check(c.v < 0.2, "burnt black (%.2f)" % c.v)
				bb.take()
				check(arena.inv.count("burnt_chicken") == 1, "taken off: a burnt chicken")
				# eaten
				arena.player_hp = 30.0
				_key(KEY_H)
				check(absf(arena.player_hp - (30.0 + VoxelChickens.ROAST_HP)) < 0.01 and arena.inv.count("roast_chicken") == 0, "H: the barbecued chicken eaten, +%d health (%.0f)" % [int(VoxelChickens.ROAST_HP), arena.player_hp])
				arena.inv.add("roast_chicken", 1)
				arena.player_hp = VoxelArena.HP_MAX
				_key(KEY_H)
				check(arena.inv.count("roast_chicken") == 1, "not hurt: not eaten")
				# sold, shredded
				var farm: VoxelFarm = arena.yard.farm
				arena.inv.add("roast_chicken", 1)
				check(farm.sell_value() == 2 * VoxelChickens.ROAST_PRICE + VoxelBarbecue.BURNT_PRICE + arena.inv.count("chicken_carcass") * VoxelChickens.CARCASS_PRICE, "the buyer's offer counts roast ($%d) and burnt ($%d)" % [VoxelChickens.ROAST_PRICE, VoxelBarbecue.BURNT_PRICE])
				var shr: VoxelShredder = arena.yard.shredder
				shr.queue = {}
				arena.inv.remove("chicken_carcass", arena.inv.count("chicken_carcass"))
				shr.feed()
				check(int(shr.queue.get("burnt_chicken", 0)) == 1 and arena.inv.count("roast_chicken") == 2, "the shredder takes the burnt one, not the roast ones")
				arena.cash = 0
				var got: int = farm.sell()
				check(got == 2 * VoxelChickens.ROAST_PRICE and arena.inv.count("roast_chicken") == 0, "roast chickens sold: $%d" % got)
				# top-down
				arena.top_down = true
				arena.inv.add("chicken_carcass", 1)
				_place(VoxelBarbecue.AT + Vector3(0, 0, -0.9), 0.0, 0.0)
				mark = t
				step = 4
		4:
			if t - mark > 0.3:
				var n := _near()
				check(n == "grill" and arena._use_label.text.contains("put a chicken carcass on"), "top-down, standing at it: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(float(bb.grill[0]) >= 0.0 and arena.inv.count("chicken_carcass") == 0, "top-down: E puts it on")
				arena.top_down = false
				# saved and loaded mid-cook
				bb.grill[0] = 12.0
				var d := bb.to_data()
				bb.from_data({})
				check(float(bb.grill[0]) < 0.0, "(cleared)")
				bb.from_data(d)
				check(absf(float(bb.grill[0]) - 12.0) < 0.01, "saved and loaded mid-cook")
				bb.from_data({})
				step = 99
		99:
			print("BBQ done %d passed, %d failed" % [passed, failed])
			return true
	return false

func _coop() -> bool:
	var n = arena.net
	var bb := _bbq()
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 3):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if Time.get_ticks_msec() > 60000:
			print("BBQ FAIL never linked (%s)" % n.status_text)
			print("BBQ done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	if role == "host":
		match step:
			0:
				arena.frozen = true
				arena.inv.from_data([])
				bb.from_data({})
				mark = t
				step = 1
			1:
				if float(bb.grill[0]) >= 0.0:
					check(true, "co-op: the guest's carcass on the host's grill")
					bb.grill[0] = VoxelBarbecue.COOK_T - 1.0
					bb._changed()
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the guest's carcass never came")
					step = 99
			2:
				if float(bb.grill[0]) < 0.0:
					check(arena.inv.count("roast_chicken") == 0, "co-op: the guest took it off (not into the host's backpack)")
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: never taken off")
					step = 99
			3:
				if not n.linked or t - mark > 60.0:
					step = 99
			99:
				print("BBQ done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				arena.inv.from_data([["chicken_carcass", 1]])
				check(bb.put() >= 0 and arena.inv.count("chicken_carcass") == 0, "co-op: the guest puts a carcass on")
				mark = t
				step = 1
			1:
				if VoxelBarbecue.state_of(float(bb.grill[0])) == "cooked":
					check(true, "co-op: cooked in the guest's game too (the host's)")
					check(bb.take() == 1, "co-op: the guest takes it off")
					mark = t
					step = 2
				elif t - mark > 40.0:
					check(false, "co-op: never cooked in the guest's game (%.1f)" % float(bb.grill[0]))
					step = 99
			2:
				if arena.inv.count("roast_chicken") == 1:
					check(true, "co-op: the roast chicken in the guest's backpack (given by the host)")
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: the roast chicken never came")
					step = 99
			3:
				if t - mark > 3.0:
					step = 99
			99:
				print("BBQ done %d passed, %d failed" % [passed, failed])
				return true
	return false
