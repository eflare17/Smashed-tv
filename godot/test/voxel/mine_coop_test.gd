extends SceneTree
## The shared mine's two-game test (headless, two copies, the host first: --fixed-fps 60 -s test/voxel/mine_coop_test.gd
## -- --host=CODE --via=enet --nosave, then the same with --join=CODE; --lag=120 --loss=10 on both for a bad line).
## The host stays up in the arena; the guest goes down: the host's ground comes over (the same seed, the same stuff in
## it), the guest's Mole blue; the guest digs a hole and it's in the host's ground (the host's game running it from the
## arena), the guest's Mole where it is in the host's game; the host goes down too and digs: the hole and the host's
## Mole in the guest's game; sand dropped in the host's game lands the same in the guest's; the guest goes back up: its
## own ground back, the host told. The two games pass what they see through a file each (user://). Owned by the voxel
## session.

var arena: Node
var m: VoxelMine
var role := ""
var code := ""
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}
var slow := 1.0                 # (a bad line: the waits longer)
var mark_ms := 0

const MATS := [MineTiles.DIRT, MineTiles.CLAY, MineTiles.STONE, MineTiles.SAND, MineTiles.WATER, MineTiles.COAL]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
			code = a.trim_prefix("--host=")
		elif a.begins_with("--join="):
			role = "guest"
			code = a.trim_prefix("--join=")
		elif a.begins_with("--lag="):
			slow = 2.0
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("MCOOP ok   ", what)
	else:
		failed += 1
		print("MCOOP FAIL ", what)

func _path(who: String) -> String:
	return "user://mcoop_%s_%s.json" % [code, who]

func _tell(k: String, val) -> void:
	var d = _heard(role)
	d[k] = val
	var f := FileAccess.open(_path(role) + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(_path(role) + ".tmp"), ProjectSettings.globalize_path(_path(role)))     # (whole, never half-written)

func _heard(who: String) -> Dictionary:
	if not FileAccess.file_exists(_path(who)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path(who)))
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _theirs(k: String):
	return _heard("guest" if role == "host" else "host").get(k)

## What the other game told (k), once it's been there secs (in the game's time and the clock's: what it says has had
## time to come over a bad line too); null till then
func _settled(k: String, secs: float):
	var val = _theirs(k)
	if val == null:
		return null
	if not v.has("seen_" + k):
		v["seen_" + k] = [t, Time.get_ticks_msec()]
	var s0: Array = v["seen_" + k]
	if t - float(s0[0]) < secs or (Time.get_ticks_msec() - int(s0[1])) / 1000.0 < secs:
		return null
	return val

func _totals() -> Array:
	var out := []
	for mt in MATS:
		out.append(m.ground.sim.count_rect(0, 0, MineGround.CW, MineGround.CH, mt))
	return out

## How much of the ship-sized box at p is dug out (air) in this game's ground
func _air(p: Vector2) -> float:
	var r := MineGround.cells_of(p, Vector2(0.3, 0.3))
	return float(m.ground.sim.count_rect(r.position.x, r.position.y, r.size.x, r.size.y, MineTiles.AIR)) / float(r.size.x * r.size.y)

func _sand_at(x: float) -> int:
	var r := MineGround.cells_of(Vector2(x, 1.0), Vector2(2.5, 3.0))
	return m.ground.sim.count_rect(r.position.x, r.position.y, r.size.x, r.size.y, MineTiles.SAND)

func _pic(p: Vector2) -> String:
	var c := MineGround.cell(p)
	var out := ""
	for y in range(c.y - 8, c.y + 8):
		for x in range(c.x - 8, c.x + 8):
			var mt := m.ground.sim.get_cell(x, y)
			out += "." if mt == MineTiles.AIR else ("#" if mt != MineTiles.SAND else "s")
		out += "\n"
	return out

func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if typeof(a) == TYPE_ARRAY and a.size() == 2 else Vector2.INF

func _next(s: int) -> void:
	step = s
	mark = t
	mark_ms = Time.get_ticks_msec()

## Waited this long since the step began, in the game's time and the clock's (a bad line holds things back by the clock)
func _waited(secs: float) -> bool:
	return t - mark >= secs and (Time.get_ticks_msec() - mark_ms) / 1000.0 >= secs

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	m = arena.mine
	var n = arena.net
	if step == 0:
		if not v.has("clean"):
			v.clean = true
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(role)))
			_tell("start", true)
		if n == null or not n.linked or (role == "guest" and not n._got_world):
			if t > 40.0:
				check(false, "never linked")
				return _done()
			return false
		_next(1)
	if step > 1 and step < 99 and not n.linked:
		check(false, "the link went (step %d)" % step)
		return _done()
	if t - mark > 90.0 * slow and step < 99:
		check(false, "stuck at step %d" % step)
		return _done()
	if int(t / 3.0) != int((t - dt) / 3.0):
		print("MCOOP stat %s t=%.1f real=%.1f ch=%d bytes=%d late=%d pending=%d" % [role, t, Time.get_ticks_msec() / 1000.0, m.net.stats.ch, m.net.stats.ch_bytes, n._late.size(), m.net._pending.size()])
	return _host() if role == "host" else _guest()

func _done() -> bool:
	print("MCOOP done %d passed, %d failed" % [passed, failed])
	return true

func _host() -> bool:
	var net: MineNet = m.net
	match step:
		1:
			# up in the arena; the guest's coming down
			if net.guest_down:
				_tell("seed", m.ground.seed_)
				_tell("tot", _totals())
				check(not m.active, "the guest's down the host's mine; the host's still up in the arena")
				_next(2)
		2:
			var gp := _v2(_settled("dug", 1.0 * slow))
			if gp != Vector2.INF:
				check(_air(gp) > 0.8, "the guest's hole is in the host's ground (%.0f%% dug out at %s), the host up top" % [_air(gp) * 100.0, str(gp)])
				check(net.other_on and net.other.visible and net.other.p.distance_to(gp) < 0.6, "the guest's Mole where it is in the host's game (%s, %s)" % [str(net.other.p if net.other else Vector2.INF), str(gp)])
				check(net.other and int(net.other._upg.get("coat", 0)) == 1, "the guest's Mole blue")
				m.enter()
				_next(3)
		3:
			if t - mark > 2.0:
				check(m.active and not net.shared, "the host down its own mine with the guest")
				m.ship.place(Vector2(38.0, 1.5))
				m.auto = {}
				_next(4)
		4:
			if t - mark > 1.2 and not v.has("down"):
				v.down = true
				m.auto = {"down": true}
			if t - mark > 4.5 and not v.has("stop"):
				v.stop = true
				m.auto = {}
			if t - mark > 5.5:
				v.hp = m.ship.p
				check(_air(m.ship.p + Vector2(0, 0.0)) > 0.8 and m.ship.p.y < -1.0, "the host dug down (%s)" % str(m.ship.p))
				_tell("hp", [m.ship.p.x, m.ship.p.y])
				# sand dropped from the sky, out of the way
				m.ground.set_box(Vector2(46.0, 3.5), Vector2(0.6, 0.6), MineTiles.SAND)
				_next(5)
		5:
			if t - mark > 4.0:
				_tell("sand", _sand_at(46.0))
				print("HOST PIC at hp\n", _pic(v.hp))
				_next(6)
		6:
			if _settled("left", 1.0 * slow) != null:
				check(not net.guest_down and not net.other.visible, "the guest's gone back up: the host told, its Mole gone")
				_next(99)
		99:
			if not v.has("told"):
				v.told = true
				_tell("done", true)
			if t - mark > 1.0:
				return _done()
	return false

func _guest() -> bool:
	var net: MineNet = m.net
	match step:
		1:
			m._build()
			v.own_seed = m.ground.seed_
			v.own_tot = _totals()
			m.enter()
			check(not m.active, "going down waits for the host's ground")
			_next(2)
		2:
			if m.active and net.shared:
				var hs = _theirs("seed")
				var ht = _theirs("tot")
				if hs == null or ht == null:
					return false
				check(int(hs) == m.ground.seed_, "the host's ground came over (seed %d, the guest's own %d)" % [m.ground.seed_, int(v.own_seed)])
				var tot := _totals()
				var ok := true
				for i in tot.size():
					if absf(float(tot[i]) - float(ht[i])) > maxf(60.0, float(ht[i]) * 0.01):
						ok = false
				check(ok, "the same stuff in it (%s, the host's %s)" % [str(tot), str(ht)])
				check(int(m.ship._upg.get("coat", 0)) == 1, "the guest's Mole blue")
				m.ship.place(Vector2(30.0, 1.5))
				m.auto = {}
				_next(3)
		3:
			if t - mark > 1.5 and not v.has("down"):
				v.down = true
				m.auto = {"down": true}
			if t - mark > 5.0 and not v.has("stop"):
				v.stop = true
				m.auto = {}
			if t - mark > 6.0:
				check(_air(m.ship.p) > 0.8 and m.ship.p.y < -1.0, "the guest dug down (%s)" % str(m.ship.p))
				check(not net._pending.is_empty() or net._seq > 0, "its digs sent to the host (%d)" % net._seq)
				_tell("dug", [m.ship.p.x, m.ship.p.y])
				_next(4)
		4:
			var hp := _v2(_settled("hp", 1.0 * slow))
			if hp != Vector2.INF:
				print("GUEST PIC at hp\n", _pic(hp))
				check(_air(hp) > 0.8, "the host's hole is in the guest's ground (%.0f%% at %s)" % [_air(hp) * 100.0, str(hp)])
				check(net.other_on and net.other.visible and net.other.p.distance_to(hp) < 0.6, "the host's Mole where it is in the guest's game (%s, %s)" % [str(net.other.p if net.other else Vector2.INF), str(hp)])
				check(net.other and int(net.other._upg.get("coat", 1)) == 0, "the host's Mole yellow")
				check(_air(m.ship.p) > 0.8, "the guest's own hole still there (not shut by the host's updates)")
				_next(5)
		5:
			var hsand = _settled("sand", 1.0 * slow)
			if hsand != null:
				var mine_sand := _sand_at(46.0)
				check(int(hsand) > 50 and absi(mine_sand - int(hsand)) <= 2, "the host's sand fell the same in the guest's game (%d, the host's %d)" % [mine_sand, int(hsand)])
				m.leave()
				_next(6)
		6:
			if t - mark > 2.0:
				check(not m.active and not net.shared, "the guest back up")
				check(m.ground.seed_ == int(v.own_seed) and _totals() == v.own_tot, "its own ground back (seed %d)" % m.ground.seed_)
				_tell("left", true)
				_next(99)
		99:
			if _theirs("done") != null or t - mark > 30.0:
				return _done()
	return false
