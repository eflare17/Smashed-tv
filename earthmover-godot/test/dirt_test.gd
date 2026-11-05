extends SceneTree
## Checks the dirt without drawing anything. Run: godot --headless --path . -s test/dirt_test.gd
## Fails if any soil is lost or made in any tick, if soil rests steeper than it should, if rock gives way, or if the grid
## never goes back to sleep.

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func flat(height := 0) -> DirtSim:
	var s := DirtSim.new()
	s.bed.fill(height)
	return s

## Runs until asleep, checking the total every tick. Returns the ticks taken, or -1 if the total ever changed or it never slept.
func settle(s: DirtSim, max_ticks: int, expect: int) -> int:
	for t in max_ticks:
		s.step(1.0 / 60.0, 1000000)
		if s.total() != expect:
			print("  total changed at tick %d: %d, expected %d" % [t, s.total(), expect])
			return -1
		if s.awake_count() == 0 and s.air_amt.size() == 0:
			return t
	return -1

func steepest_loose(s: DirtSim) -> int:
	var worst := 0
	for j in range(1, DirtSim.CELLS - 1):
		for i in range(1, DirtSim.CELLS - 1):
			var n := j * DirtSim.CELLS + i
			if s.soil[n] <= 0:
				continue
			var h := s.bed[n] + s.soil[n]
			for m in [n - 1, n + 1, n - DirtSim.CELLS, n + DirtSim.CELLS]:
				worst = maxi(worst, h - s.bed[m] - s.soil[m])
	return worst

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# A tower of soil on one cell slumps into a cone at the angle it should, none lost.
	var a := flat()
	var mid := DirtSim.CELLS / 2
	a.put(mid, mid, 4000000)
	var start := a.total()
	var ticks := settle(a, 20000, start)
	check(ticks >= 0, "a dropped tower settles with no soil lost (%d ticks)" % ticks)
	check(steepest_loose(a) <= DirtSim.SOIL_LIMIT, "nothing rests steeper than 34 degrees (steepest step %d mm, limit %d)" % [steepest_loose(a), DirtSim.SOIL_LIMIT])
	check(a.height_mm(mid, mid) > 500 and a.height_mm(mid, mid) < 5500, "it's a pile, not a flat sheet (%d mm high)" % a.height_mm(mid, mid))
	# Round rather than leaning: the same height either side of the middle.
	var lean: int = abs(a.height_mm(mid - 10, mid) - a.height_mm(mid + 10, mid)) + abs(a.height_mm(mid, mid - 10) - a.height_mm(mid, mid + 10))
	check(lean < 168, "the pile is centred to within half a cell each way (difference %d mm)" % lean)

	# Scooping and pouring by the store loses nothing, tick by tick, with chunks in the air.
	var b := flat(1000)
	b.store = 1000000
	var b_total := b.total()
	var ok := true
	for t in 900:
		if t % 3 == 0:
			b.pour(Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)), 2.0, 6, 400, 3.0, rng)
		if t % 5 == 0:
			b.scoop(Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)), 1.5, 60)
		b.step(1.0 / 60.0, 1000000)
		if b.total() != b_total:
			ok = false
			print("  changed at tick %d by %d" % [t, b.total() - b_total])
			break
	check(ok, "900 ticks of random scooping and pouring: the total never changes")
	check(settle(b, 30000, b_total) >= 0, "then it all settles, still the same")

	# More chunks than the air can hold still all land.
	var c := flat()
	c.store = 500000
	var c_total := c.total()
	for t in 60:
		c.pour(Vector2.ZERO, 1.0, 40, 200, 6.0, rng)
		c.step(1.0 / 60.0, 1000000)
	check(c.total() == c_total, "over the chunk limit, nothing's lost")
	check(c.air_amt.size() <= DirtSim.AIR_MAX, "the air stays within its limit (%d)" % c.air_amt.size())

	# A deep hole in firm ground: its too-steep walls give way, and the total holds.
	var d := flat(2000)
	var d_total := d.total()
	for j in range(mid - 6, mid + 7):
		for i in range(mid - 6, mid + 7):
			d.store += d.take(i, j, 3000)
	check(d.total() == d_total, "digging a shaft moves soil to the store exactly")
	var d_ticks := settle(d, 40000, d_total)
	check(d_ticks >= 0, "its walls collapse and settle with no soil lost (%d ticks)" % d_ticks)
	check(d.loose_total() > 0, "the collapse made loose soil (%.1f m3)" % DirtSim.to_m3(d.loose_total()))

	# Rock doesn't give way or get scraped, and it says it stopped the blade.
	var e := flat(0)
	for n in e.rock.size():
		e.rock[n] = 1
	var e_total := e.total()
	var e_got := e.take(mid, mid, 500)
	check(e_got == 0 and e.total() == e_total, "rock can't be dug")
	var e_blade: Array = e.blade(Vector2(-2, 0), Vector2(2, 0), Vector2(0, 1), -200, 40)
	check(e_blade[0] == 0 and e_blade[2], "rock stops the blade")

	# The blade carries soil along, loses none, and meets more load the more it holds.
	var f := flat(0)
	for j in range(mid - 4, mid + 40):
		for i in range(mid - 10, mid + 11):
			f.soil[j * DirtSim.CELLS + i] = 300
	var f_total := f.total()
	var empty_load := f.load_ahead(Vector2(-2.15, -3), Vector2(2.15, -3), Vector2(0, 1), 300)
	var y := -3.0
	var f_moved := 0
	var f_ok := true
	for t in 360:
		y += 2.0 / 60.0
		var r: Array = f.blade(Vector2(-2.15, y), Vector2(2.15, y), Vector2(0, 1), 0, 40)
		f_moved += int(r[0])
		f.step(1.0 / 60.0, 1000000)
		if f.total() != f_total:
			f_ok = false
			break
	var heavy_load := f.load_ahead(Vector2(-2.15, y), Vector2(2.15, y), Vector2(0, 1), 0)
	check(f_ok, "pushing with the blade for 6 seconds: the total never changes")
	check(f_moved > 0, "the blade moved soil (%.1f m3 handled)" % DirtSim.to_m3(f_moved))
	check(heavy_load > empty_load + 1.0, "load builds up against it (%.1f t, was %.1f t)" % [heavy_load, empty_load])
	check(f.height_at(Vector2(0, y - 2.0)) < 0.1, "it leaves scraped ground behind it (%.2f m)" % f.height_at(Vector2(0, y - 2.0)))

	print("\n%s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
