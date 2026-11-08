extends SceneTree
## Ruts: every machine presses its tracks or tyres into loose soil as deep as its weight sends them (owner, 9 Nov), and as wide as
## they are. Run: godot --headless --path . -s test/rut_test.gd
## These test what it does to the dirt, not whether it looks right: only seeing it can tell that.

const DT := 1.0 / 60.0
const LOOSE := 400               # mm of loose soil laid over the test strip
var fails := 0
var ground := GroundData.new()

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

## A fresh flat world with a strip of loose soil across the middle, or none.
func new_sim(loose: bool) -> DirtSim:
	var s := DirtSim.new()
	if loose:
		for j in range(DirtSim.CELLS / 2 - 24, DirtSim.CELLS / 2 + 25):
			for i in range(4, DirtSim.CELLS - 4):
				s.soil[j * DirtSim.CELLS + i] = LOOSE
	return s

func make(s: DirtSim, what: String) -> Machine:
	var view := GroundView.new(ground, s, ground.height_texture(), ground.data_texture())
	var mat := StandardMaterial3D.new()
	var at := Vector2(-18.0, 0.0)
	var dir := Vector2(1.0, 0.0)
	var m: Machine
	match what:
		"Dingo", "Bobcat":
			var l := Loader.new()
			root.add_child(l)
			l.setup(s, view, mat, at, dir, what)
			m = l
		"Ute":
			m = Ute.new()
			root.add_child(m)
			(m as Ute).setup(s, view, mat, at, dir)
		"Dozer", "Big dozer":
			var d := Dozer.new()
			if what == "Big dozer":
				d.make_big(1.9)
			root.add_child(d)
			d.setup(s, view, mat, at, dir)
			m = d
		"Excavator", "Big excavator":
			var e := Excavator.new()
			if what == "Big excavator":
				e.make_big(1.9)
			root.add_child(e)
			e.setup(s, view, mat, at, dir)
			e.dig_mode = false
			m = e
		_:
			var t := Truck.new()
			t.haul = what.begins_with("Haul")
			root.add_child(t)
			t.setup(s, view, mat, at, dir)
			if what.ends_with("full"):
				t.tray_mm = t.capacity
			m = t
	# Whatever it digs with, up off the ground.
	for k in int(0.8 / DT):
		if m is Dozer:
			(m as Dozer).lift_cmd = 1.0
		elif m is Loader:
			(m as Loader).lift_cmd = 1.0
		m.step(DT)
	if m is Dozer:
		(m as Dozer).lift_cmd = 0.0
	elif m is Loader:
		(m as Loader).lift_cmd = 0.0
	return m

## Drives it `metres` along, forward or back. False if the total ever changed.
func drive(s: DirtSim, m: Machine, metres: float, back := false) -> bool:
	var from := m.spot.x
	var start := s.total()
	var same := true
	m.throttle = -1.0 if back else 1.0
	for k in int(40.0 / DT):
		m.step(DT)
		s.step(DT, 1000000)
		same = same and s.total() == start
		if absf(m.spot.x - from) >= metres:
			break
	m.throttle = 0.0
	for k in int(1.5 / DT):
		m.step(DT)
		s.step(DT, 1000000)
		same = same and s.total() == start
	return same

## How deep the prints are along both tracks between x0 and x1, and how wide: [mean of the deepest cell across each print in mm,
## mean count of cells pressed at least half that deep across one print, highest ridge in mm].
func measure(s: DirtSim, m: Machine, before: PackedInt32Array, x0: float, x1: float) -> Array:
	var deep := 0.0
	var wide := 0.0
	var count := 0
	var ridge := 0
	var x := x0
	while x <= x1:
		for z: float in [-m.track_z, m.track_z]:
			var most := 0
			var drops: Array[int] = []
			var y := z - m.rut_half - 0.75
			while y <= z + m.rut_half + 0.75:
				var c := DirtSim.cell_of(Vector2(x, y))
				var n := c.y * DirtSim.CELLS + c.x
				var drop := before[n] - (s.bed[n] + s.soil[n])
				if absf(y - z) <= m.rut_half + 0.13:
					most = maxi(most, drop)
					drops.append(drop)
				ridge = maxi(ridge, -drop)
				y += DirtSim.CELL_M
			deep += most
			for d in drops:
				if d * 2 >= most and most > 0:
					wide += 1.0
			count += 1
		x += DirtSim.CELL_M
	return [deep / maxf(count, 1.0), wide / maxf(count, 1.0), ridge]

func heights(s: DirtSim) -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(s.bed.size())
	for n in h.size():
		h[n] = s.bed[n] + s.soil[n]
	return h

## One pass of `what` over the loose strip: [depth, width, ridge, machine], checked against what it should be.
func one_pass(what: String, want_mm: int) -> Array:
	var s := new_sim(true)
	var m := make(s, what)
	var before := heights(s)
	var x0 := m.spot.x
	var same := drive(s, m, 14.0)
	var got := measure(s, m, before, x0 - m.track_rear + 1.0, m.spot.x - m.track_rear - 1.0)
	print("      %-16s %3d mm deep (meant %3d), %.1f cells wide, ridge %d mm" % [what, int(got[0]), want_mm, got[1], got[2]])
	check(same, "%s: driving over loose soil, the total never changes" % what)
	check(got[0] > want_mm * 0.7 and got[0] < want_mm * 1.35, "%s presses in about %d mm (%d mm)" % [what, want_mm, int(got[0])])
	# The print is drawn pressed flat, without lumps, all along both tracks.
	m.view.sync(0.1, 100000000)
	var along := 0
	var shown := 0
	var x := x0 - m.track_rear + 1.0
	while x <= m.spot.x - m.track_rear - 1.0:
		for z: float in [-m.track_z, m.track_z]:
			along += 1
			var c := DirtSim.cell_of(Vector2(x, z))
			var n := c.y * DirtSim.CELLS + c.x
			if m.view.pressed(n) and m.view.dust_data[n * 2 + 1] == 0 and m.view.data[n * 4 + 2] == 255:
				shown += 1
		x += DirtSim.CELL_M
	check(shown >= along * 0.9, "%s: its print shows pressed flat, no lumps (%d of %d)" % [what, shown, along])
	return [got[0], got[1], got[2], m]

func _init() -> void:
	var depth := {}
	var width := {}
	for row: Array in [["Dingo", 10], ["Ute", 15], ["Bobcat", 20], ["Dozer", 50], ["Excavator", 50], ["Truck", 50],
			["Truck full", 100], ["Big dozer", 80], ["Big excavator", 80], ["Haul truck", 50], ["Haul truck full", 100]]:
		var got := one_pass(row[0], row[1])
		depth[row[0]] = got[0]
		width[row[0]] = got[1]
		check(got[2] < row[1] * 1.5, "%s: what's squeezed out makes a low ridge, not a wall (%d mm)" % [row[0], got[2]])
	check(depth["Dingo"] < depth["Ute"] and depth["Ute"] < depth["Bobcat"] and depth["Bobcat"] < depth["Dozer"]
			and depth["Dozer"] < depth["Big dozer"] and depth["Truck"] < depth["Truck full"],
			"heavier goes deeper: Dingo, ute, Bobcat, dozer, big dozer; and a loaded truck deeper than an empty one")
	check(width["Big dozer"] > width["Dozer"] and width["Dozer"] > width["Dingo"] and width["Haul truck"] > width["Big dozer"],
			"a bigger track makes a wider print (Dingo %.1f, dozer %.1f, big dozer %.1f, haul truck %.1f cells)" % [width["Dingo"], width["Dozer"], width["Big dozer"], width["Haul truck"]])

	# Back and forth over the same line: a little deeper the second time, then no deeper, so it never digs a trench.
	var s := new_sim(true)
	var m := make(s, "Dozer")
	var before := heights(s)
	var x0 := m.spot.x
	drive(s, m, 14.0)
	var x1 := m.spot.x
	var first: float = measure(s, m, before, x0 - m.track_rear + 1.0, x1 - m.track_rear - 1.0)[0]
	var same := drive(s, m, 14.0, true)
	var second: float = measure(s, m, before, x0 - m.track_rear + 1.0, x1 - m.track_rear - 1.0)[0]
	for k in 3:
		same = drive(s, m, 14.0) and same
		same = drive(s, m, 14.0, true) and same
	var eighth: float = measure(s, m, before, x0 - m.track_rear + 1.0, x1 - m.track_rear - 1.0)[0]
	print("      dozer back and forth: %d mm after one pass, %d after two, %d after eight" % [int(first), int(second), int(eighth)])
	check(same, "back and forth eight times: the total never changes")
	check(second >= first and second < first + 0.8 * m.rut_mm, "a second pass presses it only a little deeper (%d to %d mm)" % [int(first), int(second)])
	check(eighth < m.rut_mm * (Machine.RUT_AGAIN + 0.5), "eight passes and it's still a rut, not a trench (%d mm)" % int(eighth))

	# Dirt pushed onto a print covers it: it's lumpy again there.
	m.view.sync(0.1, 100000000)
	var p := DirtSim.cell_of(Vector2((x0 + x1) * 0.5 - m.track_rear, m.track_z))
	var pn := p.y * DirtSim.CELLS + p.x
	var was_pressed := m.view.pressed(pn)
	s.put(p.x, p.y, 150)
	s.dirty[(p.y >> 4) * DirtSim.CHUNKS + (p.x >> 4)] = true
	m.view.sync(0.1, 100000000)
	check(was_pressed and not m.view.pressed(pn) and m.view.dust_data[pn * 2 + 1] > 0, "dirt pushed onto a print covers it up again")

	# Firm ground takes no print at all, even from a loaded truck.
	var f := new_sim(false)
	var t := make(f, "Truck full")
	var firm := heights(f)
	drive(f, t, 14.0)
	var changed := 0
	for n in firm.size():
		if firm[n] != f.bed[n] + f.soil[n]:
			changed += 1
	check(changed == 0, "a loaded truck on firm ground leaves no rut (%d cells changed)" % changed)

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
