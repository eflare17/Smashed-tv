extends SceneTree
## The Dig Site's clods self-test (dirt_physics_plan.md, stage 2; headless:
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_test.gd -- --nosave
## ), on a small grid of its own (no arena), DsDirt alone: 1000 clods dropped from 3 m onto one spot (a stream, 10 a
## tick) are all back in the ground within 8 s; not a millimetre's made or lost, at any tick; the ground never spikes
## under them (no column more than 250 mm over all four of its neighbours, at any tick); slumped, the pile stands at 28
## to 38 degrees; a clod let go on a firm 40 degree bank rolls more than a metre down it before it settles; and the
## whole thing run twice gives the same ground (section_hashes). Owned by the voxel session.

const W := 128
const H := 96
const D := 128
const SURF := 64
const MM := 125
const CELL := 0.125
const N := 1000
const A_TICK := 10              # clods let go a tick
const HALF := 30                # the columns watched: this many each way from the spot

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSCLOD ok   ", what)
	else:
		failed += 1
		print("DSCLOD FAIL ", what)

func _grid() -> DigSiteGrid:
	var g := DigSiteGrid.new()
	g.setup(W, H, D, SURF)
	DsMats.apply(g)
	g.generate(77)
	return g

# a tick as the game runs it: the loose layer every tick, the cells every third (no time budget: the same every run)
func _tick(g: DigSiteGrid, n: int) -> void:
	g.layer_step(1000000)
	if n % 3 == 0:
		g.settle(1000000)

# the watched columns' surfaces (cells)
func _heights(g: DigSiteGrid, cx: int, cz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var s := HALF * 2 + 1
	out.resize(s * s)
	var i := 0
	for z in range(cz - HALF, cz + HALF + 1):
		for x in range(cx - HALF, cx + HALF + 1):
			out[i] = g.height_at(x + 0.5, z + 0.5)
			i += 1
	return out

# the most any watched column stands over all four of its straight neighbours (mm), each over the ground as it was
func _spike(now: PackedFloat32Array, was: PackedFloat32Array) -> float:
	var s := HALF * 2 + 1
	var worst := 0.0
	for z in range(1, s - 1):
		var row := z * s
		for x in range(1, s - 1):
			var c := row + x
			var h := now[c] - was[c]
			if h <= 0.0:
				continue
			var m := maxf(maxf(now[c - 1] - was[c - 1], now[c + 1] - was[c + 1]), maxf(now[c - s] - was[c - s], now[c + s] - was[c + s]))
			if h - m > worst:
				worst = h - m
	return worst * MM

# The drop: -> {ok fields}. 1000 clods (500 mm each: the middle size) from 3 m over one spot, 10 a tick
func _drop(watch: bool) -> Dictionary:
	var g := _grid()
	g.wake_all()
	g.layer_wake_all()
	var t := 0
	while t < 400 and (g.awake_count() > 0 or g.layer_awake() > 0):
		_tick(g, t)
		t += 1
	var dirt := DsDirt.new()
	dirt.setup(g)
	dirt.fly_max = N
	dirt.cap_us = 0
	dirt.seed_ = 20261124
	var cx := W / 2
	var cz := D / 2
	var was := _heights(g, cx, cz)
	var total: int = g.ground_mm()
	var want := total + N * DsDirt.CLOD
	var spot := Vector3((cx + 0.5) * CELL, g.height_at(cx + 0.5, cz + 0.5) * CELL + 3.0, (cz + 0.5) * CELL)
	var let_go := 0
	var real := 0
	var drift := 0
	var spike := 0.0
	var spike_at := 0
	var most_awake := 0
	var gone_at := -1
	var us := 0
	var ticks := 0
	while ticks < 900:
		for k in A_TICK:
			if let_go < N:
				var o := Vector3(dirt.randf01() - 0.5, 0.0, dirt.randf01() - 0.5) * 0.3
				var v := Vector3(dirt.randf01() - 0.5, 0.0, dirt.randf01() - 0.5) * 0.6
				if dirt.spawn(spot + o, v, DsMats.DIRT, DsDirt.CLOD):
					real += 1
				let_go += 1
		dirt.step(1.0 / 60.0)
		us += dirt.step_us
		_tick(g, ticks)
		ticks += 1
		most_awake = maxi(most_awake, dirt.awake())
		if watch:
			var m: int = g.ground_mm() + dirt.mass_mm() + dirt.owed_mm()
			var have := total + let_go * DsDirt.CLOD
			drift = maxi(drift, absi(m - have))
			var s := _spike(_heights(g, cx, cz), was)
			if s > spike:
				spike = s
				spike_at = ticks
		if let_go == N and dirt.awake() == 0 and gone_at < 0:
			gone_at = ticks
			break
	# the slump: the grid's own, till it's still
	var slump := 0
	while slump < 6000 and (g.awake_count() > 0 or g.layer_awake() > 0):
		_tick(g, ticks + slump)
		slump += 1
		if watch and slump % 4 == 0:
			var s := _spike(_heights(g, cx, cz), was)
			if s > spike:
				spike = s
				spike_at = ticks + slump
	var out := {"gone_at": gone_at, "real": real, "drift": drift, "spike": spike, "spike_at": spike_at, "most": most_awake,
		"end": g.ground_mm() + dirt.mass_mm() + dirt.owed_mm() - want, "slump": slump, "us": us / maxi(1, ticks),
		"settled": dirt.settled_n, "shed": dirt.shed_n, "hashes": g.section_hashes(), "loose": g.loose_mm()}
	# the pile: its top, and how far out it's three quarters and a quarter that, eight ways
	var now := _heights(g, cx, cz)
	var s := HALF * 2 + 1
	var mid := HALF * s + HALF
	var high := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			high = maxf(high, now[mid + dz * s + dx] - was[mid + dz * s + dx])
	var degs := []
	for a in 8:
		var dx := [1, 1, 0, -1, -1, -1, 0, 1][a] as int
		var dz := [0, 1, 1, 1, 0, -1, -1, -1][a] as int
		var unit := sqrt(float(dx * dx + dz * dz))
		var r75 := -1.0
		var r25 := -1.0
		for k in range(1, HALF):
			var c := mid + dz * k * s + dx * k
			var h := now[c] - was[c]
			if r75 < 0.0 and h < high * 0.75:
				r75 = k * unit
			if r25 < 0.0 and h < high * 0.25:
				r25 = k * unit
				break
		if r25 > r75 and r75 > 0.0:
			degs.append(rad_to_deg(atan(high * 0.5 / (r25 - r75))))
	var deg := 0.0
	for x in degs:
		deg += x
	out["deg"] = deg / maxi(1, degs.size())
	out["degs"] = degs
	out["high"] = high
	return out

# A firm bank at 40 degrees, rising toward +z (cells and a firm layer for the odd mm, so it's a true plane; the grid's
# not ticked: it's the clod that's tested), and a clod let go at rest near its top: -> how far down it it went (m)
func _bank() -> Dictionary:
	var g := _grid()
	var dirt := DsDirt.new()
	dirt.setup(g)
	dirt.cap_us = 0
	var x0 := 48
	var x1 := 80
	var z0 := 40
	var len_ := 32              # columns up the bank: 4 m, rising 3.36
	var rise := tan(deg_to_rad(40.0))
	var base := SURF + 2
	for z in range(z0, z0 + len_ + 8):
		var up := minf(float(z - z0) + 0.5, float(len_)) * rise   # cells over base at the column's middle
		var top_mm := int(round(up * MM))
		var whole := top_mm / MM
		for x in range(x0, x1):
			for y in range(0, H):
				if y < base + whole:
					if (g.get_cell(x, y, z) & DsMats.MASK) == 0:
						g.set_cell(x, y, z, DsMats.DIRT)
				else:
					g.set_cell(x, y, z, 0)
			g.set_layer(x, z, top_mm - whole * MM, DsMats.DIRT | 0x80)
	# (flat in front of it, at base)
	for z in range(z0 - 24, z0):
		for x in range(x0, x1):
			for y in range(0, H):
				if y < base:
					if (g.get_cell(x, y, z) & DsMats.MASK) == 0:
						g.set_cell(x, y, z, DsMats.DIRT)
				else:
					g.set_cell(x, y, z, 0)
			g.set_layer(x, z, 0, DsMats.DIRT)
	var zc := z0 + len_ - 4
	var xc := (x0 + x1) / 2
	var a := (g.height_at(xc + 0.5, zc + 2.5) - g.height_at(xc + 0.5, zc - 1.5)) / 4.0
	var total: int = g.ground_mm()
	var r := DsDirt.radius_of(DsDirt.CLOD)
	var p := Vector3((xc + 0.5) * CELL, g.height_at(xc + 0.5, zc + 0.5) * CELL + r, (zc + 0.5) * CELL)
	dirt.spawn(p, Vector3.ZERO, DsMats.DIRT, DsDirt.CLOD)
	var last := p
	var fastest := 0.0
	var ticks := 0
	var on_bank := Vector3.ZERO
	while dirt.awake() > 0 and ticks < 1200:
		dirt.step(1.0 / 60.0)
		ticks += 1
		if dirt.awake() > 0:
			last = Vector3(dirt.px[0], dirt.py[0], dirt.pz[0])
			fastest = maxf(fastest, Vector3(dirt.vx[0], dirt.vy[0], dirt.vz[0]).length())
			if last.z >= z0 * CELL:
				on_bank = last
	return {"deg": rad_to_deg(atan(a)), "went": (p - last).length(), "down": p.z - last.z, "fell": p.y - last.y, "ticks": ticks,
		"fastest": fastest, "on_bank": (p - on_bank).length(), "mass": g.ground_mm() + dirt.mass_mm() - total - DsDirt.CLOD, "awake": dirt.awake()}

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var a := _drop(true)
	print("DSCLOD   the drop: %d clods (%d real), most awake %d, all gone at tick %d (%.2f s); step %d us mean; %d settled, %d shed; slump %d ticks; %d ms" % [
		N, a.real, a.most, a.gone_at, a.gone_at / 60.0, a.us, a.settled, a.shed, a.slump, Time.get_ticks_msec() - t0])
	check(a.real == N, "%d clods dropped from 3 m onto one spot, every one a clod (%d)" % [N, a.real])
	check(a.gone_at > 0 and a.gone_at <= 480, "all back in the ground within 8 s (%.2f s)" % (a.gone_at / 60.0))
	check(a.drift == 0 and a.end == 0, "not a millimetre made or lost, at any tick (most off %d mm; at the end %d)" % [a.drift, a.end])
	check(a.loose == N * DsDirt.CLOD, "all of it loose dirt on the ground (%d mm of %d)" % [a.loose, N * DsDirt.CLOD])
	check(a.spike <= 250.0, "the ground never spikes: no column more than 250 mm over its neighbours (most %.0f mm, at tick %d)" % [a.spike, a.spike_at])
	var ds := ""
	for x in a.degs:
		ds += "%.0f " % x
	print("DSCLOD   the pile: %.2f m high; eight ways: %s" % [a.high * CELL, ds])
	check(a.deg >= 28.0 and a.deg <= 38.0, "slumped, the pile stands at 28 to 38 degrees (%.1f)" % a.deg)
	var b := _bank()
	print("DSCLOD   the bank: %.1f degrees; the clod went %.2f m (%.2f along, %.2f down), %.2f m of it on the bank, in %d ticks; fastest %.2f m/s" % [
		b.deg, b.went, b.down, b.fell, b.on_bank, b.ticks, b.fastest])
	check(absf(b.deg - 40.0) < 0.5, "a firm bank at 40 degrees (%.1f)" % b.deg)
	check(b.down > 1.0 and b.on_bank > 1.0 and b.awake == 0, "a clod let go on it rolls more than 1 m down it before it settles (%.2f m)" % b.on_bank)
	check(b.mass == 0, "and it's all in the ground after (%d mm off)" % b.mass)
	var c := _drop(false)
	var same: bool = (a.hashes as PackedInt32Array) == (c.hashes as PackedInt32Array)
	check(same and a.gone_at == c.gone_at, "run twice, the ground's the same (section_hashes; gone at %d and %d)" % [a.gone_at, c.gone_at])
	print("DSCLOD done %d passed, %d failed" % [passed, failed])
	quit()
