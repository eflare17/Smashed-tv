extends SceneTree
## Stage 6, chickens (headless): two hens to start, a coop for four with two nest boxes; the run safe from the enemies;
## the gate (E) opened and shut; grain bought at the sacks (E) and put in the feeder (E) with worms; a hungry hen
## walking in to eat; a fed hen laying in a nest box, a hungry one not; eggs hatching faster the better fed the hens,
## into a chick that grows up, but not past the coop's cap; eggs collected (E), sold at the buyer, eaten (H) for
## health; the coop upgraded at its sign (more chickens, more nest boxes); poo dropped as cubes, vacuumed up as chicken
## poo, fed to a plant and to the worm farm; hens running off from a player; the gate open, hens out roaming the yard,
## shut, nobody through; never anywhere they can't be; the chickens saved and loaded. With --host=CODE / --join=CODE
## (two copies, the host first): the host's hens in the guest's game and moving, the guest opening the gate, feeding,
## collecting the host's eggs (theirs, not the host's), upgrading the host's coop; the host's hens' poo in both games.
## Killing them (24 Oct): a blow in the run or the coop does nothing but send it flapping (and says why); out in the
## yard a blow hurts (feathers, a run), three kill a hen, one a chick (the real input path, top-down, with a tool), a
## grenade's blast kills out there but not in the run; dead, a carcass where it fell, picked up with E (first person and
## top-down) as a chicken carcass, sold at the buyer, shredded; its place in the coop freed; carcasses saved. Co-op: the
## guest's blow kills the host's hen (a "hit" op), both see the carcass, the guest picks it up (theirs, not the host's).
## Prints "CHICKENS ok/FAIL ..." and "CHICKENS done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var v0 := {}
var _went := {}                 # hen id -> the regions it's been in (the roaming check)
var _crossed := 0
var _nowhere := 0

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("CHICKENS %s %s" % ["ok" if ok else "FAIL", what])

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

func _ch() -> VoxelChickens:
	return arena.yard.chickens

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

# stand 1.2 m from world point p (on the side toward from_dir) looking at it
func _look_at(p: Vector3, from_dir := Vector3(0, 0, -1)) -> void:
	var from := p + from_dir.normalized() * 1.2
	_place(Vector3(from.x, 0, from.z), 0.0, 0.0)
	var to := p - Vector3(from.x, 1.65, from.z)
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

# what the look lands on now (the camera moved first)
func _near() -> String:
	arena._camera(0.0)
	arena._storage_step(0.0)
	return arena._near_hen

func _clear() -> void:
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo(dt)
	return _coop()

func _hen(i: int) -> Dictionary:
	return _ch().hens[i]

func _still(h: Dictionary) -> void:
	h.st = "idle"
	h.t = 9999.0
	h.path = []

func _solo(dt: float) -> bool:
	var ch := _ch()
	match step:
		0:
			_clear()
			arena.frozen = true
			arena.spawn(1)
			for b in arena.bodies:
				b.position = Vector3(0, 0, -15)
			arena.inv.from_data([])
			arena.cash = 0
			ch._fresh()
			check(ch.hens.size() == 2 and ch.level == 0 and ch.cap() == 4 and ch.nest_count() == 2 and not ch.gate, "two hens to start; a coop for 4 with 2 nest boxes; the gate shut")
			for i in ch.hens.size():
				var o: Dictionary = ch.hens[i]
				_still(o)
				o.x = 24.0
				o.z = 25.0 + i
			check(VoxelArena.safe(Vector3(25, 0, 28)) and VoxelArena.safe(Vector3(29, 0, 37)) and not VoxelArena.safe(Vector3(15, 0, 15)), "the run and the coop are safe from the enemies")
			# the gate
			_look_at(Vector3(VoxelChickens.GATE_X, 0.8, 30.5), Vector3(-1, 0, 0))
			mark = t
			step = 1
		1:
			if t - mark > 0.2:
				var n := _near()
				check(n == "gate" and arena._use_label.text.contains("open the gate"), "at the gate: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(ch.gate, "E: the gate open")
				_near()
				check(arena._use_label.text.contains("shut the gate"), "open: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(not ch.gate, "E again: shut")
				# the sacks
				_look_at(VoxelChickens.SACKS + Vector3(0, 0.5, 0), Vector3(-1, 0, 0.3))
				mark = t
				step = 2
		2:
			if t - mark > 0.2:
				var n := _near()
				check(n == "sacks", "at the feed sacks (%s): \"%s\"" % [n, arena._use_label.text])
				_key(KEY_E)
				check(arena.inv.count("grain") == 0 and arena._say_text.contains("Not enough"), "no cash, no grain")
				arena.cash = 7
				_key(KEY_E)
				check(arena.inv.count("grain") == VoxelChickens.GRAIN_BUY and arena.cash == 2, "E: %d grain for $%d ($%d left)" % [VoxelChickens.GRAIN_BUY, VoxelChickens.GRAIN_COST, arena.cash])
				arena.inv.add("worm", 2)
				ch.food = 0.0
				_look_at(VoxelChickens.FEEDER + Vector3(0, 0.4, 0), Vector3(1, 0, 0))
				mark = t
				step = 3
		3:
			if t - mark > 0.2:
				var n := _near()
				check(n == "feeder" and arena._use_label.text.contains("put in"), "at the feeder: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(int(ch.food) == 16 and arena.inv.count("grain") == 0 and arena.inv.count("worm") == 0, "E: 10 grain and 2 worms in: %d feed" % int(ch.food))
				# a hungry hen goes in to eat; the other one's fed full and ready to lay
				_place(Vector3(20, 0, 30), 0, 0)
				var a := _hen(0)
				a.full = 0.2
				a.lay = 0.0
				a.x = 25.0
				a.z = 27.0
				a.st = "idle"
				a.t = 0.0
				var b := _hen(1)
				b.full = 1.0
				b.lay = VoxelChickens.LAY_T
				b.x = 24.0
				b.z = 30.0
				b.st = "idle"
				b.t = 0.0
				v0.food = ch.food
				mark = t
				step = 4
		4:
			_watch(ch)
			var a := _hen(0)
			var eggs := 0
			for k in ch.nests.size():
				eggs += (ch.nests[k] as Array).size()
			if float(a.full) > 0.5 and eggs > 0:
				check(ch.food < float(v0.food), "a hungry hen walked in and ate (full %.2f, feed %d)" % [float(a.full), int(ch.food)])
				check(true, "a fed hen went up into a nest box and laid (%d egg)" % eggs)
				check(float(_hen(1).lay) < 10.0, "laid: her clock back to the start")
				step = 5
				mark = t
			elif t - mark > 90.0:
				check(false, "eating / laying never happened (full %.2f, eggs %d, st %s / %s)" % [float(a.full), eggs, a.st, _hen(1).st])
				step = 5
				mark = t
		5:
			_watch(ch)
			# a hungry hen doesn't lay
			var c := _hen(0)
			c.full = 0.1
			c.lay = 0.0
			ch.food = 0.0
			v0.lay = 0.0
			mark = t
			step = 6
		6:
			_watch(ch)
			_hen(0).full = 0.1
			if t - mark > 10.0:
				check(float(_hen(0).lay) == 0.0, "a hungry hen doesn't lay (%.1f)" % float(_hen(0).lay))
				# fed full lays twice as fast as half fed
				var r1: float = _lay_rate(1.0)
				var r2: float = _lay_rate(0.5)
				check(absf(r1 / maxf(r2, 0.0001) - 2.0) < 0.15, "fed full, eggs come twice as fast as half fed (%.3f vs %.3f a second)" % [r1, r2])
				# hatching: faster fed
				for k in ch.nests.size():
					ch.nests[k] = []
				ch.nests[0] = [0.0]
				for o in ch.hens:
					o.full = 1.0
					_still(o)
				ch._live(10.0)
				var p1 := float(ch.nests[0][0])
				ch.nests[0] = [0.0]
				for o in ch.hens:
					o.full = 0.0
				ch._live(10.0)
				var p2 := float(ch.nests[0][0])
				check(p1 > p2 * 2.5, "eggs hatch faster the better fed the hens (%.3f vs %.3f in 10 s: 3x)" % [p1, p2])
				# one about to hatch
				ch.nests[0] = [0.999]
				for o in ch.hens:
					o.full = 0.8
				mark = t
				step = 7
		7:
			if ch.hens.size() == 3:
				var chick: Dictionary = ch.hens[2]
				check(float(chick.age) < 0.1 and (ch.nests[0] as Array).is_empty(), "an egg hatched: a chick (3 chickens)")
				check(ch._views.has(int(chick.id)) and (ch._views[int(chick.id)] as VoxelChicken).chick, "the chick shown small and yellow")
				chick.age = 0.995
				mark = t
				step = 8
			elif t - mark > 3.0:
				check(false, "the egg never hatched")
				step = 8
				mark = t
		8:
			if t - mark > 2.0:
				var chick: Dictionary = ch.hens[2] if ch.hens.size() > 2 else {}
				check(not chick.is_empty() and float(chick.age) >= 1.0 and not (ch._views[int(chick.id)] as VoxelChicken).chick, "the chick grew up into a hen")
				# the cap: four, and an egg ready to hatch stays an egg
				ch._hatch(Vector2(29, 37), 1.0)
				ch.nests[1] = [1.0]
				for o in ch.hens:
					o.poo = 0.0
				mark = t
				step = 9
		9:
			if t - mark > 1.0:
				check(ch.hens.size() == 4 and (ch.nests[1] as Array).size() == 1, "the coop full (4 of 4): the egg doesn't hatch")
				for o in ch.hens:
					_still(o)
					o.x = 24.0 + randf()
					o.z = 25.0 + randf()
				_look_at(Vector3(VoxelChickens.NEST_X, VoxelChickens.NEST_Y + 0.1, VoxelChickens.NEST_Z + VoxelChickens.NEST_DZ), Vector3(-1, 0, 0))
				mark = t
				step = 10
		10:
			if t - mark > 0.2:
				var n := _near()
				check(n == "nest1" and arena._use_label.text.contains("no room to hatch") and arena._use_label.text.contains("E  collect"), "at the nest box: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("egg") == 1 and (ch.nests[1] as Array).is_empty(), "E: the egg collected")
				# sold at the buyer, eaten for health
				arena.inv.add("egg", 2)
				arena.player_hp = 50.0
				_key(KEY_H)
				check(absf(arena.player_hp - 70.0) < 0.01 and arena.inv.count("egg") == 2, "H: an egg eaten, +20 health (%.0f)" % arena.player_hp)
				arena.player_hp = VoxelArena.HP_MAX
				_key(KEY_H)
				check(arena.inv.count("egg") == 2, "not hurt: no egg eaten")
				arena.cash = 0
				var got: int = arena.yard.farm.sell()
				check(got == 2 * VoxelChickens.EGG_PRICE and arena.inv.count("egg") == 0, "eggs sold at the buyer: $%d" % got)
				# the upgrade
				_look_at(VoxelChickens.SIGN + Vector3(0, 1.45, 0), Vector3(0, 0, -1))
				mark = t
				step = 11
		11:
			if t - mark > 0.2:
				var n := _near()
				check(n == "sign" and arena._use_label.text.contains("upgrade to 8 chickens"), "at the coop's sign: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(ch.level == 0 and arena._say_text.contains("Not enough"), "not enough: no upgrade")
				arena.cash = 120
				arena.inv.add("stone", 160)
				_key(KEY_E)
				check(ch.level == 1 and ch.cap() == 8 and ch.nest_count() == 4 and arena.cash == 20 and arena.inv.count("stone") == 10, "E: upgraded ($100, 150 stone): room for 8, 4 nest boxes")
				# poo
				var h := _hen(0)
				h.x = 24.5
				h.z = 26.0
				h.y = 0.0
				h.full = 1.0
				for o in ch.hens:
					o.poo = 0.0
				h.poo = VoxelChickens.POO_T - 0.01
				_still(h)
				_place(Vector3(20, 0, 30), 0, 0)
				v0.lying = arena.debris.lying()
				mark = t
				step = 12
		12:
			if t - mark > 2.0:
				var d: int = arena.debris.lying() - int(v0.lying)
				check(d == VoxelChickens.POO_CUBES, "a hen pooed: %d cubes on the ground" % d)
				check((ch._nest_nodes[3][0] as Node3D).visible and not (ch._nest_nodes[4][0] as Node3D).visible, "the new nest boxes there")
				check(VoxelItems.of_colour(VoxelChickens.POO[0]) == "poo" and VoxelItems.of_colour(VoxelChickens.POO[2]) == "poo" and VoxelItems.is_cubes("poo"), "poo cubes are chicken poo to the vacuum")
				# the vacuum on it
				_hen(0).x = 26.5
				var vi: int = arena.loadout.index_of("vacuum")
				arena._switch(func(): arena.loadout.select(vi))
				arena.loadout.switch_t = 0.0
				arena.vacuum.brush_r = VoxelVacuum.R_MAX
				_look_at(Vector3(24.5, 0.0, 26.0), Vector3(0, 0, 1))
				arena.hold_suck = true
				mark = t
				step = 13
		13:
			if t - mark > 3.0:
				arena.hold_suck = false
				check(arena.inv.count("poo") == VoxelChickens.POO_CUBES, "vacuumed up: %d chicken poo in the backpack" % arena.inv.count("poo"))
				# fed to a plant (20 a feed) and the worm farm
				var farm: VoxelFarm = arena.yard.farm
				arena.yard.ground.load_chunks({})
				var key := farm.spot_of(Vector3(10.1, 0, 28.1))
				arena.yard.till([key])
				arena.yard.ground.finish()
				farm.plants[key] = {"s": 0, "g": 0.2, "wet": 100.0, "dry": 0.0, "wilt": 0, "fed": 0}
				check(not farm.fertilise(key), "12 poo: not enough to feed a plant")
				arena.inv.add("poo", 30)
				check(farm.fertilise(key) and int(farm.plants[key].fed) == 1 and arena.inv.count("poo") == 22, "%d poo: a plant fed (%d left)" % [VoxelFarm.POO_FEED, arena.inv.count("poo")])
				farm.worms = {"n": 3, "food": 0.0, "eaten": 0.0, "cast": 0, "born": 0.0}
				farm.service_wormery()
				check(absf(float(farm.worms.food) - 22 * 1.5) < 0.01 and arena.inv.count("poo") == 0, "poo in the worm farm (worth 1.5 a cube: %.0f)" % float(farm.worms.food))
				# running at a hen
				var h := _hen(1)
				h.x = 25.0
				h.z = 28.0
				h.st = "idle"
				h.t = 5.0
				_place(Vector3(25.3, 0, 28.3), 0, 0)
				mark = t
				step = 14
		14:
			if t - mark > 0.2:
				check(String(_hen(1).st) == "flee", "a hen runs off flapping from a player (%s)" % _hen(1).st)
				# roaming: the gate open
				_place(Vector3(15, 0, 24), 0, 0)
				ch.food = 60.0
				for o in ch.hens:
					o.st = "idle"
					o.t = 0.0
					o.full = 0.9
					o.x = 24.0 + randf() * 2.0
					o.z = 28.0 + randf() * 4.0
				ch.set_gate(true)
				_went.clear()
				mark = t
				step = 15
		15:
			_watch(ch)
			var out := 0
			for o in ch.hens:
				if VoxelChickens.region_of(Vector2(o.x, o.z)) == VoxelChickens.YARD:
					out += 1
			if out >= 2:
				check(true, "the gate open: hens out roaming the yard (%d)" % out)
				ch.set_gate(false)
				v0.sides = _sides(ch)
				_crossed = 0
				mark = t
				step = 16
			elif t - mark > 120.0:
				check(false, "nobody went out into the yard (%d)" % out)
				step = 16
				mark = t
		16:
			_watch(ch)
			var s := _sides(ch)
			for id in s:
				if v0.sides.has(id) and (s[id] == VoxelChickens.YARD) != (v0.sides[id] == VoxelChickens.YARD):
					_crossed += 1
			v0.sides = s
			if t - mark > 40.0:
				check(_crossed == 0, "the gate shut: nobody through it in 40 s")
				check(_nowhere == 0, "the hens never anywhere they can't be (%d)" % _nowhere)
				# saved and loaded
				ch.level = 2
				ch.food = 33.0
				ch.nests[5] = [0.4, 0.6]
				var before := ch.to_data()
				arena.stash.save_path = "user://chickens_test_save.json"
				arena.stash.save()
				ch._fresh()
				arena.stash.load_save()
				var after := ch.to_data()
				check(after.level == 2 and int(after.food) == 33 and (after.nests[5] as Array).size() == 2 and (after.hens as Array).size() == (before.hens as Array).size() and not after.gate, "the chickens saved and loaded (level, feed, eggs, %d hens)" % (after.hens as Array).size())
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://chickens_test_save.json"))
				step = 17
		17:
			# killing them: one in the run, a hen and a chick out in the yard
			ch._fresh()
			arena.inv.from_data([])
			ch.gate = true
			ch._told_safe = false
			var a := _hen(0)
			a.x = 25.0
			a.z = 28.0
			var b := _hen(1)
			b.x = 15.0
			b.z = 30.0
			var c := ch._hatch(Vector2(17.0, 33.0), 0.3)
			for o in ch.hens:
				_still(o)
				o.y = ch._ground_y(float(o.x), float(o.z))
			var si: int = arena.loadout.index_of("sword")
			arena._switch(func(): arena.loadout.select(si))
			arena.loadout.switch_t = 0.0
			v0.ids = [int(a.id), int(b.id), int(c.id)]
			# a blow in the run
			_look_at(Vector3(25.0, 0.2, 28.0), Vector3(-1, 0, 0))
			mark = t
			step = 20
		20:
			if t - mark < 0.2:
				return false
			var a = ch._hen_by(int(v0.ids[0]))
			for o in ch.hens:
				_still(o)
			arena._camera(0.0)
			var got: int = ch.attack(arena.melee["sword"])
			check(got == int(a.id) and int(a.hurt) == 0 and ch.hens.size() == 3 and String(a.st) == "flee", "in the run: the sword lands but does nothing, it flaps off (%s, hurt %d)" % [a.st, int(a.hurt)])
			check(arena._say_text.contains("safe in there"), "says why: \"%s\"" % arena._say_text)
			ch._strike_t.clear()
			ch.strike(int(a.id), 3, Vector3(24, 0, 28))
			check(ch.hens.size() == 3 and int(a.hurt) == 0 and ch.carcasses.is_empty(), "in the run even a big blow doesn't hurt it")
			ch.blast(Vector3(float(a.x), 0.3, float(a.z)), 3.0, 50.0)
			check(ch.hens.size() == 3 and int(a.hurt) == 0, "nor a grenade's blast")
			# out in the yard
			_look_at(Vector3(15.0, 0.2, 30.0), Vector3(-1, 0, 0))
			mark = t
			step = 21
		21:
			if t - mark < 0.2:
				return false
			var b = ch._hen_by(int(v0.ids[1]))
			_still(b)
			arena._camera(0.0)
			var got: int = ch.attack(arena.melee["sword"])
			check(got == int(b.id) and int(b.hurt) == 1 and String(b.st) == "flee" and ch._feathers.size() >= 5, "out in the yard: a sword blow hurts the hen, feathers fly (%d), it runs (%s)" % [ch._feathers.size(), b.st])
			check(ch.attack(arena.melee["sword"]) == -1, "a second swing at once doesn't land (the sword's own pace)")
			v0.at = Vector2(float(b.x), float(b.z))
			mark = t
			step = 18
		18:
			if t - mark > 0.5:
				var b = ch._hen_by(int(v0.ids[1]))
				b.hit_ms = 0
				ch._strike_t.clear()
				ch.strike(int(b.id), 1, Vector3(14, 0, 30))
				check(ch.hens.size() == 3 and int(b.hurt) == 2, "two blows: still alive")
				b.hit_ms = 0
				var at := Vector2(float(b.x), float(b.z))
				ch.strike(int(b.id), 1, Vector3(14, 0, 30))
				check(ch.hens.size() == 2 and ch._hen_by(int(v0.ids[1])) == null, "the third kills it (%d left)" % ch.hens.size())
				var cc = ch._carcass_by(int(v0.ids[1]))
				check(cc != null and Vector2(float(cc.x), float(cc.z)).distance_to(at) < 0.01 and not bool(cc.chick), "a chicken carcass where it fell")
				check(arena._say_text.contains("E picks up the carcass"), "says so: \"%s\"" % arena._say_text)
				ch._show(0.016)
				check(ch._carc_views.has(int(v0.ids[1])) and not ch._views.has(int(v0.ids[1])), "shown as a carcass, not a hen")
				# the chick, through the real input path: top-down, a tool (the shovel), the chick at your feet
				var c = ch._hen_by(int(v0.ids[2]))
				arena.top_down = true
				var vi: int = arena.loadout.index_of("shovel")
				arena._switch(func(): arena.loadout.select(vi))
				arena.loadout.switch_t = 0.0
				_place(Vector3(float(c.x) + 0.25, 0, float(c.z)), 0.0, 0.0)
				arena._clicked[MOUSE_BUTTON_LEFT] = true
				arena._shoot(0.016)
				check(ch._hen_by(int(v0.ids[2])) == null and ch._carcass_by(int(v0.ids[2])) != null and bool(ch._carcass_by(int(v0.ids[2])).chick), "top-down, a click with the shovel: the chick dies in one, a chick's carcass")
				# a grenade's blast out in the yard
				var d := ch._hatch(Vector2(12.0, 28.0), 1.0)
				_still(d)
				ch.blast(Vector3(12.3, 0.3, 28.0), 3.0, 50.0)
				check(ch._hen_by(int(d.id)) == null and ch._carcass_by(int(d.id)) != null, "a grenade's blast kills one out in the yard")
				var e := ch._hatch(Vector2(12.0, 26.0), 1.0)
				_still(e)
				ch.blast(Vector3(12.3, 0.3, 26.0), 2.0, 3.0)
				check(ch._hen_by(int(e.id)) != null and int(e.hurt) == 1, "a fire patch takes one blow")
				ch.hens.erase(e)
				arena.top_down = false
				mark = t
				step = 19
		19:
			if t - mark > 0.3:
				# picked up, first person
				var cc = ch._carcass_by(int(v0.ids[1]))
				_look_at(Vector3(float(cc.x), 0.05, float(cc.z)), Vector3(-1, 0, 0.2))
				mark = t
				step = 22
		22:
			if t - mark > 0.2:
				var n := _near()
				check(n == "carcass%d" % int(v0.ids[1]) and arena._use_label.text.contains("pick up the chicken carcass"), "at the carcass: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("chicken_carcass") == 1 and ch._carcass_by(int(v0.ids[1])) == null, "E: a chicken carcass in the backpack, gone from the ground")
				ch._show(0.016)
				check(not ch._carc_views.has(int(v0.ids[1])), "its model gone")
				# picked up top-down
				var ck = ch._carcass_by(int(v0.ids[2]))
				arena.top_down = true
				_place(Vector3(float(ck.x) + 0.3, 0, float(ck.z)), 0.0, 0.0)
				n = _near()
				check(n == "carcass%d" % int(v0.ids[2]) and arena._use_label.text.contains("chick's carcass"), "top-down, at your feet: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("chicken_carcass") == 2, "E: picked up top-down too (2)")
				arena.top_down = false
				# sold, shredded
				arena.cash = 0
				var farm: VoxelFarm = arena.yard.farm
				check(farm.sell_value() == 2 * VoxelChickens.CARCASS_PRICE, "the buyer offers $%d for two" % farm.sell_value())
				var shr: VoxelShredder = arena.yard.shredder
				arena.inv.remove("chicken_carcass", 1)
				shr.queue = {}
				shr.points = 0.0
				shr.bags = 0
				check(shr.feed() == 1 and int(shr.queue.get("chicken_carcass", 0)) == 1, "E at the shredder: the carcass goes in")
				shr._grind(1.0)
				check(absf(shr.points - VoxelChickens.CARCASS_POINTS) < 0.01, "ground into a quarter bag of blood and bone (%.0f points)" % shr.points)
				arena.inv.add("chicken_carcass", 1)
				var got: int = farm.sell()
				check(got == VoxelChickens.CARCASS_PRICE and arena.inv.count("chicken_carcass") == 0, "sold at the buyer: $%d" % got)
				# the coop's place freed: full, one out in the yard killed, an egg hatches into its place
				ch._fresh()
				ch.gate = true
				ch._hatch(Vector2(29, 37), 1.0)
				var f := ch._hatch(Vector2(15, 30), 1.0)
				for o in ch.hens:
					_still(o)
				for k in ch.nests.size():
					ch.nests[k] = []
				ch.nests[0] = [1.0]
				ch._live(0.1)
				check(ch.hens.size() == 4 and (ch.nests[0] as Array).size() == 1, "the coop full (4 of 4): the egg waits")
				ch.strike(int(f.id), 3, Vector3(14, 0, 30))
				check(ch.hens.size() == 3, "one killed out in the yard: 3 of 4")
				ch._live(0.1)
				check(ch.hens.size() == 4 and (ch.nests[0] as Array).is_empty(), "its place free: the egg hatched into it")
				# saved and loaded
				var dd := ch.to_data()
				ch.carcasses.clear()
				ch.from_data(dd)
				check(ch.carcasses.size() == 1 and int(ch.carcasses[0].id) == int(f.id), "the carcass saved and loaded")
				# roasted: the flamethrower's (or the laser's) kill, or burnt to death in a fire patch: a roast chicken
				ch._fresh()
				ch.gate = true
				var r1 := ch._hatch(Vector2(15, 28), 1.0)
				_still(r1)
				ch.strike(int(r1.id), 3, Vector3(14, 0, 28), true)
				var rc = ch._carcass_by(int(r1.id))
				check(rc != null and bool(rc.roast), "the flamethrower's kill: a roast chicken")
				var r2 := ch._hatch(Vector2(12, 26), 1.0)
				_still(r2)
				for k in VoxelChickens.HP:
					r2.hit_ms = 0
					ch.blast(Vector3(12.3, 0.3, 26.0), 2.0, 3.0)
				var rc2 = ch._carcass_by(int(r2.id))
				check(rc2 != null and bool(rc2.roast), "burnt to death in a fire patch: roast too")
				ch._show(0.016)
				check(ch._carc_views.has(int(r1.id)) and bool((ch._carc_views[int(r1.id)] as Node).get_meta("roast", false)), "shown roasted (golden, singed feathers)")
				arena.inv.from_data([])
				check(ch.take_carcass(int(r1.id)) and arena.inv.count("roast_chicken") == 1, "E: a roast chicken in the backpack")
				var dr := ch.to_data()
				ch.carcasses.clear()
				ch.from_data(dr)
				check(ch._carcass_by(int(r2.id)) != null and bool(ch._carcass_by(int(r2.id)).roast), "a roast carcass saved and loaded")
				# eaten (H, no eggs): the roast first, then a raw one; not hurt: none
				arena.inv.remove("egg", arena.inv.count("egg"))
				arena.inv.add("chicken_carcass", 1)
				arena.player_hp = 20.0
				check(ch.eat_meat() == "roast_chicken" and is_equal_approx(arena.player_hp, 20.0 + VoxelChickens.ROAST_HP), "H with no eggs: the roast first (+%d health)" % int(VoxelChickens.ROAST_HP))
				var hp0: float = arena.player_hp
				check(ch.eat_meat() == "chicken_carcass" and is_equal_approx(arena.player_hp, minf(VoxelArena.HP_MAX, hp0 + VoxelChickens.CARCASS_HP)), "then a raw one (+%d)" % int(VoxelChickens.CARCASS_HP))
				arena.inv.add("roast_chicken", 1)
				arena.player_hp = VoxelArena.HP_MAX
				check(ch.eat_meat() == "" and arena.inv.count("roast_chicken") == 1, "not hurt: nothing eaten")
				arena.inv.add("roast_chicken", 1)
				var got2: int = farm.sell()
				check(got2 == 2 * VoxelChickens.ROAST_PRICE, "roast chickens sell for more: $%d for 2" % got2)
				step = 99
		99:
			print("CHICKENS done %d passed, %d failed" % [passed, failed])
			return true
	return false

# eggs a second (laying progress) fed this full
func _lay_rate(full: float) -> float:
	var h: Dictionary = _ch()._hatch(Vector2(29, 37), 1.0)
	h.full = full
	h.lay = 0.0
	_still(h)
	_ch()._hen(h, 1.0)
	var r := float(h.lay)
	_ch().hens.erase(h)
	return r

func _sides(ch: VoxelChickens) -> Dictionary:
	var out := {}
	for o in ch.hens:
		out[int(o.id)] = VoxelChickens.region_of(Vector2(o.x, o.z))
	return out

func _watch(ch: VoxelChickens) -> void:
	for o in ch.hens:
		var p := Vector2(o.x, o.z)
		if VoxelChickens.region_of(p) == VoxelChickens.NONE:
			_nowhere += 1
			if _nowhere < 4:
				print("  (a hen nowhere: %s, %s)" % [str(p), o.st])

func _coop() -> bool:
	var n = arena.net
	var ch := _ch()
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 9):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if role == "host" and not v0.has("prep"):
			v0.prep = true
			ch._fresh()
			ch.food = 0.0
		if Time.get_ticks_msec() > 60000:
			print("CHICKENS FAIL never linked (%s)" % n.status_text)
			print("CHICKENS done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	if role == "host":
		match step:
			0:
				_clear()
				arena.frozen = true
				arena.inv.from_data([])
				mark = t
				step = 1
			1:
				if ch.gate:
					check(true, "co-op: the guest opened the host's gate")
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the gate never opened")
					step = 2
			2:
				if ch.food >= 10.0:
					check(int(ch.food) == 10, "co-op: the guest's grain in the host's feeder (%d)" % int(ch.food))
					ch.nests[0] = [0.1, 0.2]
					ch._changed()
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: the guest's feed never came")
					step = 3
			3:
				if (ch.nests[0] as Array).is_empty():
					check(arena.inv.count("egg") == 0, "co-op: the guest collected the host's eggs (not the host's)")
					mark = t
					step = 4
				elif t - mark > 30.0:
					check(false, "co-op: the eggs were never collected")
					step = 4
			4:
				if ch.level == 1:
					check(true, "co-op: the guest upgraded the host's coop")
					var h := _hen(0)
					h.full = 1.0
					h.poo = VoxelChickens.POO_T - 0.01
					# one out in the yard for the guest to kill
					var y := ch._hatch(Vector2(15.0, 30.0), 1.0)
					_still(y)
					v0.yard_id = int(y.id)
					arena.player.global_position = Vector3(10, 0, 20)
					ch._changed()
					mark = t
					step = 9
				elif t - mark > 30.0:
					check(false, "co-op: the upgrade never came")
					step = 9
					mark = t
			9:
				if v0.has("yard_id") and not v0.has("killed") and ch._carcass_by(int(v0.yard_id)) != null:
					v0.killed = true
					check(ch._hen_by(int(v0.yard_id)) == null, "co-op: the guest's blow (a hit op) killed the host's hen: a carcass in the host's game")
				if v0.has("killed") and not v0.has("taken") and ch._carcass_by(int(v0.yard_id)) == null:
					v0.taken = true
					check(arena.inv.count("chicken_carcass") == 0 and arena._say_text.contains("Your mate picked up"), "co-op: the guest picked it up: gone from the host's game, not in the host's backpack (\"%s\")" % arena._say_text)
				if not n.linked or t - mark > 120.0:
					if v0.has("yard_id") and not v0.has("taken"):
						check(false, "co-op: the guest's kill / pick-up never came (killed %s)" % str(v0.has("killed")))
					step = 99
			99:
				print("CHICKENS done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				if ch.hens.size() == 2:
					check(true, "co-op: the host's two hens in the guest's game")
					v0.p0 = Vector2(_hen(0).x, _hen(0).z)
					v0.p1 = Vector2(_hen(1).x, _hen(1).z)
					mark = t
					step = 1
				elif t - mark > 20.0:
					check(false, "co-op: the host's hens never came (%d)" % ch.hens.size())
					step = 1
			1:
				var moved := Vector2(_hen(0).x, _hen(0).z).distance_to(v0.p0) + Vector2(_hen(1).x, _hen(1).z).distance_to(v0.p1)
				if moved > 0.3:
					check(true, "co-op: the hens moving in the guest's game (as the host's)")
					ch.set_gate(true)
					arena.inv.from_data([["grain", 10], ["stone", 150]])
					arena.cash = 100
					ch.use("feeder")
					check(arena.inv.count("grain") == 0, "co-op: grain out of the guest's backpack into the feeder")
					mark = t
					step = 2
				elif t - mark > 40.0:
					check(false, "co-op: the hens never moved")
					step = 2
			2:
				if (ch.nests[0] as Array).size() == 2:
					check(true, "co-op: the host's eggs in the guest's nest box")
					ch.collect(0)
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: the host's eggs never showed")
					step = 3
					mark = t
			3:
				if arena.inv.count("egg") == 2:
					check(true, "co-op: the eggs in the guest's backpack (2)")
					check(ch.upgrade() and arena.cash == 0 and arena.inv.count("stone") == 0, "co-op: the guest paid for the upgrade")
					v0.lying = arena.debris.lying()
					mark = t
					step = 4
				elif t - mark > 30.0:
					check(false, "co-op: no eggs came (%d)" % arena.inv.count("egg"))
					step = 4
					mark = t
			4:
				if arena.debris.lying() - int(v0.lying) >= VoxelChickens.POO_CUBES:
					check(true, "co-op: the host's hen's poo in the guest's game (%d cubes)" % (arena.debris.lying() - int(v0.lying)))
					mark = t
					step = 5
				elif t - mark > 30.0:
					check(false, "co-op: the poo never came (%d)" % (arena.debris.lying() - int(v0.lying)))
					step = 5
					mark = t
			5:
				# the host's hen out in the yard: killed with a blow from the guest
				var y = null
				for o in ch.hens:
					if VoxelChickens.killable(Vector2(o.x, o.z)):
						y = o
				if y != null:
					v0.yard_id = int(y.id)
					ch.strike(int(y.id), VoxelChickens.HP, Vector3(float(y.x) - 1.0, 0, float(y.z)))
					check(ch._feathers.size() > 0, "co-op: the guest's blow seen at once (feathers)")
					mark = t
					step = 6
				elif t - mark > 30.0:
					check(false, "co-op: the host's yard hen never showed")
					step = 99
			6:
				if ch._carcass_by(int(v0.yard_id)) != null:
					check(ch._hen_by(int(v0.yard_id)) == null, "co-op: the carcass in the guest's game too (the host's)")
					ch._show(0.016)
					check(ch._carc_views.has(int(v0.yard_id)), "co-op: shown in the guest's game")
					check(ch.take_carcass(int(v0.yard_id)), "co-op: the guest picks it up")
					mark = t
					step = 7
				elif t - mark > 30.0:
					check(false, "co-op: the carcass never came to the guest")
					step = 99
			7:
				if arena.inv.count("chicken_carcass") == 1:
					check(true, "co-op: the chicken carcass in the guest's backpack (given by the host)")
					mark = t
					step = 8
				elif t - mark > 30.0:
					check(false, "co-op: the carcass was never given")
					step = 99
			8:
				if t - mark > 3.0:
					step = 99
			99:
				print("CHICKENS done %d passed, %d failed" % [passed, failed])
				return true
	return false
