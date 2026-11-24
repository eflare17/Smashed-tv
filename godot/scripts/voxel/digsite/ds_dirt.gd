class_name DsDirt
extends RefCounted
## The Dig Site's dirt that's come loose (the owner, 24 Nov: the Dig Site "feels pretty clunky"; the dirt should break
## off, tumble, pile and settle like the buildings' bricks): clods. Each is a lump of so many mm of dirt (as the grid
## counts it: a block's 125 over a column) that falls, bounces, rolls down slopes and comes to rest; resting, it melts
## back into the ground (DigSiteGrid.put_layer) and is gone from here, so only what's moving costs anything.
## There are no clod against clod contacts: what gives a stream its body is the "awake heap", the clods lying in each
## quarter-metre square raise its floor by their own volume, so they pile, and roll off the pile, before they settle
## (up to HEAP_FULL: a clod coming down on a square that full is part of the heap, and settles there and then; without
## that a stream onto one spot stood 3 m of clods on each other and threw them 9 m, measured).
## A clod's dirt goes onto the columns under it evenly (2 x 2, 4 x 4 or 6 x 6 of them by its size), not split four
## ways as the plan had it: a chunk's 2000 mm on four columns is a 500 mm spike, and the plan allows 250.
## This is the core alone (dirt_physics_plan.md, stage 2): no drawing, no machines, no tunnels, no network.
## Nothing's made or lost: grid.ground_mm() + mass_mm() + owed_mm() never changes.
## Runs where the dirt runs (solo, or the host), a step every 1/60 s. With cap_us 0 it's the same every run (its random
## numbers are its own, from `seed_`); the time cap, when it bites, is by the clock. Owned by the voxel session.

const CELL := 0.125             # a column's side (DsTerrain.CELL)
const INV_CELL := 8.0
const MM := 125                 # a block, in mm over a column
const G := 9.8
const REST := 0.25              # of its speed kept in a bounce ...
const BOUNCE_V := 2.0           # ... hitting the ground faster than this (m/s into it); slower, it rolls
const BOUNCE_GRIP := 0.6        # (and of its speed along the ground)
const MU := 0.7                 # friction rolling: holds on anything under 35 degrees
const HEAP_M := 0.00025         # m a quarter-metre square's floor rises per mm lying awake in it (its 4 columns' worth)
const HEAP_FULL := 1500        # mm lying awake in a square at most: the floor rises no more for it, and a clod coming down on that many settles there and then (the stream's own heap)
const NAP_MOST := 6             # steps at most a clod in the air goes without the ground under it looked at
const SLOPE_KEEP := 3           # steps a square's slopes are kept once worked out (the ground moves a few mm a step at most)
const SKIN := 0.02               # m over the ground a clod's still on it (rolling down a bank it's on it every step, not every other by the rounding)
const HEAP_UP := 0.05           # m a frame a clod's lifted at most as the heap under it grows
const SLOW := 0.4               # m/s: slower than this ...
const REST_S := 0.25            # ... for this long ...
const SLOPE2 := 0.3333          # ... on less than 30 degrees (tan squared), it settles;
const STUCK_S := 1.0            # slow for this long, whatever it lies on (a heap's flank at its own angle: plan's rule plus this, see the progress log)
const AGE_S := 6.0              # or at this age, the next time it touches the ground;
const AGE_MOST := 9.0           # at this, wherever it is
const DEP_FRAME := 200          # clods settling a frame at most
const DEP_COL := 36             # mm on a column in a frame from settling clods before the next one there waits (the ground rises evenly: no spikes)
const CRUMB := 125              # the sizes (mm): a crumb, 12 cm; a clod, 20 cm; a chunk, 32 cm
const CLOD := 500
const CHUNK := 2000
const FLY_MAX := 800            # clods awake at once (stage 2's measurement on the 4-core box: digsite_clod_perf)
const CLOD_US := 2000           # a step's time: over it, the slowest (then the oldest) are settled where they are

var grid                        # DigSiteGrid
var origin := Vector3.ZERO      # its corner in the world
var fly_max := FLY_MAX
var cap_us := CLOD_US           # (0: no time cap)
var seed_ := 1:
	set(v):
		seed_ = v
		_rng = v & 0x7fffffff
var step_us := 0                # the last step's time
var us_per_clod := 0.0          # (smoothed)
var settled_n := 0              # clods settled so far; of them shed_n forced by the caps; direct_n spawns that went straight to ground
var shed_n := 0
var direct_n := 0
var frame := 0

# the clods (struct of arrays; a clod deleted is swapped with the last)
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pz := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var vz := PackedFloat32Array()
var rad := PackedFloat32Array()
var nap := PackedByteArray()      # steps it's sure to be in the air yet (the ground's not looked at)
var rest := PackedFloat32Array()  # how long it's been slow
var age := PackedFloat32Array()
var cmm := PackedInt32Array()     # its dirt (mm)
var cmat := PackedByteArray()
var cid := PackedInt32Array()     # (16 bits: the network's, stage 8)
var gnd := PackedByteArray()      # on the ground last step
var n := 0

var _w := 0
var _d := 0
var _hw := 0                    # quarter-metre squares across, and deep
var _hd := 0
var _hm := PackedInt32Array()   # the awake heap: mm lying in each square (last step's) ...
var _hn := PackedInt32Array()   # ... and this step's, as it's counted
var _ht := PackedInt32Array()   # the squares in _hm, and in _hn
var _hnt := PackedInt32Array()
var _gst := PackedInt32Array()  # each square's slopes, worked out when a clod on it asks and kept SLOPE_KEEP steps (_gst: good till this frame)
var _gxm := PackedFloat32Array()  # (rise per metre toward +x on its low-x half, and its high-x half; and z)
var _gxp := PackedFloat32Array()
var _gzm := PackedFloat32Array()
var _gzp := PackedFloat32Array()
var _dep := PackedInt32Array()  # this frame's settled dirt by column (mm), laid all at once ...
var _depm := PackedByteArray()
var _dept := PackedInt32Array() # ... the columns with any
var _mass := 0
var _owed := 0                  # (stage 3's tunnels: dirt that couldn't be laid yet)
var _rng := 1
var _next_id := 0
var _x0 := 0.0
var _x1 := 0.0
var _z0 := 0.0
var _z1 := 0.0

func setup(g, at := Vector3.ZERO) -> void:
	grid = g
	origin = at
	_w = g.get_w()
	_d = g.get_d()
	_hw = (_w + 1) / 2
	_hd = (_d + 1) / 2
	for a in [_hm, _hn, _gst]:
		a.resize(_hw * _hd)
		a.fill(0)
	for a in [_gxm, _gxp, _gzm, _gzp]:
		a.resize(_hw * _hd)
		a.fill(0.0)
	_gst.fill(-1)
	_dep.resize(_w * _d)
	_dep.fill(0)
	_depm.resize(_w * _d)
	# (clods keep off the grid's rim: the edge ring takes no loose dirt, and a chunk's 6 columns must fit)
	_x0 = origin.x + 12 * CELL
	_x1 = origin.x + (_w - 12) * CELL
	_z0 = origin.z + 12 * CELL
	_z1 = origin.z + (_d - 12) * CELL

## The dirt in the clods (mm), and what's owed the ground (stage 3)
func mass_mm() -> int:
	return _mass

func owed_mm() -> int:
	return _owed

func awake() -> int:
	return n

func _rnd() -> int:
	_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
	return _rng >> 8

## 0 .. 1
func randf01() -> float:
	return float(_rnd() & 0xffff) / 65536.0

static func radius_of(mm: int) -> float:
	return 0.0625 * pow(float(mm) / MM, 1.0 / 3.0)   # (half the side of a cube of it)

## A clod of mm of m at p (world), going at v. None (false) if it's under a crumb or there are fly_max already (or the
## time cap's biting): the dirt goes straight to the ground under p instead. Either way all of it's kept.
func spawn(p: Vector3, v: Vector3, m: int, mm: int) -> bool:
	if mm <= 0:
		return false
	if mm < CRUMB or n >= _room():
		direct_n += 1
		_lay(clampf(p.x, _x0, _x1), clampf(p.z, _z0, _z1), mm, m)
		return false
	if n == px.size():
		_grow(maxi(64, n * 2))
	px[n] = clampf(p.x, _x0, _x1)
	py[n] = p.y
	pz[n] = clampf(p.z, _z0, _z1)
	vx[n] = v.x
	vy[n] = v.y
	vz[n] = v.z
	rad[n] = radius_of(mm)
	nap[n] = 0
	rest[n] = 0.0
	age[n] = 0.0
	cmm[n] = mm
	cmat[n] = m
	cid[n] = _next_id
	gnd[n] = 0
	_next_id = (_next_id + 1) & 0xffff
	n += 1
	_mass += mm
	return true

## mm of m come loose about p, as clods: mostly the middle size, some crumbs and chunks (bigger ones as the awake
## fill up: twice over a fifth of fly_max, three times over half), each off at v and up to `spread` m/s more any way,
## from within `within` m of p. What's left under a crumb goes straight to the ground. How many clods.
func spawn_mass(p: Vector3, v: Vector3, m: int, mm: int, spread := 0.5, within := 0.1) -> int:
	var made := 0
	var coarse := 1
	if n * 5 > fly_max:
		coarse = 3 if n * 2 > fly_max else 2
	while mm >= CRUMB:
		var k := _rnd() % 10
		var one := CLOD
		if k == 0:
			one = CHUNK
		elif k < 3:
			one = CRUMB
		one = mini(one * coarse, mm)
		if one < CRUMB:
			break
		var o := Vector3(randf01() - 0.5, randf01() - 0.5, randf01() - 0.5) * 2.0
		var u := Vector3(randf01() - 0.5, randf01() - 0.5, randf01() - 0.5) * 2.0
		if spawn(p + o * within, v + u * spread, m, one):
			made += 1
		mm -= one
	if mm > 0:
		_lay(clampf(p.x, _x0, _x1), clampf(p.z, _z0, _z1), mm, m)
	return made

# how many clods there's room for: fly_max, fewer while a step at that many would run over the time cap
func _room() -> int:
	if cap_us > 0 and us_per_clod > 0.0:
		return mini(fly_max, int(cap_us / us_per_clod))
	return fly_max

# clod i's dirt onto the columns under it: a crumb's on 2 x 2, a clod's 4 x 4, a chunk's 6 x 6 (about twice its own
# width: it melts to a low mound), shared evenly, the odd mm on the middle one. With `gently` it waits (false) while
# its middle column's had DEP_COL this frame already.
func _deposit(i: int, gently: bool) -> bool:
	var mm := cmm[i]
	var cx := (px[i] - origin.x) * INV_CELL
	var cz := (pz[i] - origin.z) * INV_CELL
	var mx := int(cx)
	var mz := int(cz)
	if gently and _dep[mz * _w + mx] >= DEP_COL:
		return false
	var k := 2
	if mm >= 1000:
		k = 6
	elif mm >= 250:
		k = 4
	var bx := int(cx - 0.5) - (k >> 1) + 1
	var bz := int(cz - 0.5) - (k >> 1) + 1
	var q := mm / (k * k)
	var m := cmat[i]
	if q > 0:
		for z in range(bz, bz + k):
			var row := z * _w
			for x in range(bx, bx + k):
				var c := row + x
				if _dep[c] == 0:
					_dept.append(c)
					_depm[c] = m
				_dep[c] += q
	var left := mm - q * k * k
	if left > 0:
		var c := mz * _w + mx
		if _dep[c] == 0:
			_dept.append(c)
			_depm[c] = m
		_dep[c] += left
	return true

# mm of m straight onto the ground at world (x, z) (what never became a clod), spread as a clod's is
func _lay(x: float, z: float, mm: int, m: int) -> void:
	var cx := (x - origin.x) * INV_CELL
	var cz := (z - origin.z) * INV_CELL
	var k := 4 if mm >= 250 else 2
	var bx := int(cx - 0.5) - (k >> 1) + 1
	var bz := int(cz - 0.5) - (k >> 1) + 1
	var q := mm / (k * k)
	if q > 0:
		for zz in range(bz, bz + k):
			for xx in range(bx, bx + k):
				grid.put_layer(xx, zz, q, m)
	if mm - q * k * k > 0:
		grid.put_layer(int(cx), int(cz), mm - q * k * k, m)

func _remove(i: int) -> void:
	_mass -= cmm[i]
	n -= 1
	if i != n:
		px[i] = px[n]
		py[i] = py[n]
		pz[i] = pz[n]
		vx[i] = vx[n]
		vy[i] = vy[n]
		vz[i] = vz[n]
		rad[i] = rad[n]
		nap[i] = nap[n]
		rest[i] = rest[n]
		age[i] = age[n]
		cmm[i] = cmm[n]
		cmat[i] = cmat[n]
		cid[i] = cid[n]
		gnd[i] = gnd[n]

# room for `most` clods (the arrays only ever grow: n is how many are in use)
func _grow(most: int) -> void:
	for a in [px, py, pz, vx, vy, vz, rad, nap, rest, age, cmm, cmat, cid, gnd]:
		a.resize(most)

# the frame's settled dirt laid on the ground
func _flush() -> void:
	for c in _dept:
		grid.put_layer(c % _w, c / _w, _dep[c], _depm[c])
		_dep[c] = 0
	_dept.clear()

## Every clod settled where it is, now (a save, leaving, the host changing): all of it's in the ground after
func land_all() -> void:
	for i in range(n - 1, -1, -1):
		_deposit(i, false)
		_remove(i)
		settled_n += 1
	_flush()
	if _owed > 0:
		_owed = 0   # (stage 3 lays it on the surface here)
	for c in _ht:
		_hm[c] = 0
	_ht.clear()

# a quarter-metre square's slopes: the ground at its middle and its four neighbours', each with its awake heap
func _slopes(hc: int) -> void:
	var hx := hc % _hw
	var hz := hc / _hw
	var x := hx * 2.0 + 1.0
	var z := hz * 2.0 + 1.0
	var k := CELL
	var hm := HEAP_M
	var full := HEAP_FULL
	var c: float = grid.height_at(x, z) * k + mini(_hm[hc], full) * hm
	var xm := c
	var xp := c
	var zm := c
	var zp := c
	if hx > 0:
		xm = grid.height_at(x - 2.0, z) * k + mini(_hm[hc - 1], full) * hm
	if hx < _hw - 1:
		xp = grid.height_at(x + 2.0, z) * k + mini(_hm[hc + 1], full) * hm
	if hz > 0:
		zm = grid.height_at(x, z - 2.0) * k + mini(_hm[hc - _hw], full) * hm
	if hz < _hd - 1:
		zp = grid.height_at(x, z + 2.0) * k + mini(_hm[hc + _hw], full) * hm
	_gxm[hc] = (c - xm) * 4.0
	_gxp[hc] = (xp - c) * 4.0
	_gzm[hc] = (c - zm) * 4.0
	_gzp[hc] = (zp - c) * 4.0
	_gst[hc] = frame + SLOPE_KEEP

## A step of dt (1/60 s)
func step(dt: float) -> void:
	if n == 0:
		step_us = 0
		if not _ht.is_empty():
			for c in _ht:
				_hm[c] = 0
			_ht.clear()
		return
	var t0 := Time.get_ticks_usec()
	frame += 1
	var settled := 0
	# the time cap: with more awake than a step has time for, that many settled where they are (ones on the ground
	# first; then from the front of the list, the oldest about: a clod deleted is swapped with the last, so it's not
	# strictly by age, and "the slowest" is "on the ground" here. Sorting 800 a step would cost more than it saves)
	var room := _room()
	if n > room:
		var shed := mini(n - room, DEP_FRAME)
		var i := n - 1
		while i >= 0 and shed > 0:
			if gnd[i] != 0:
				_deposit(i, false)
				_remove(i)
				shed -= 1
				settled += 1
				shed_n += 1
			i -= 1
		while shed > 0 and n > 0:
			_deposit(0, false)
			_remove(0)
			shed -= 1
			settled += 1
			shed_n += 1
	var ox := origin.x
	var oy := origin.y
	var oz := origin.z
	var gdt := G * dt
	var hw := _hw
	var i := 0
	while i < n:
		var r := rad[i]
		var uy := vy[i] - gdt
		var ux := vx[i]
		var uz := vz[i]
		var x := px[i] + ux * dt
		var y := py[i] + uy * dt
		var z := pz[i] + uz * dt
		var a := age[i] + dt
		age[i] = a
		# (well up in the air: the ground's not looked at till it could be there)
		var np := nap[i]
		if np > 0 and a < AGE_MOST:
			nap[i] = np - 1
			px[i] = x
			py[i] = y
			pz[i] = z
			vy[i] = uy
			i += 1
			continue
		if x < _x0 or x > _x1:
			x = clampf(x, _x0, _x1)
			ux = 0.0
		if z < _z0 or z > _z1:
			z = clampf(z, _z0, _z1)
			uz = 0.0
		var cx := (x - ox) * INV_CELL
		var cz := (z - oz) * INV_CELL
		var hc := (int(cz) >> 1) * hw + (int(cx) >> 1)
		var mm := cmm[i]
		var ht: float = oy + grid.height_at(cx, cz) * CELL
		var heap := _hm[hc] - mm
		var h := ht + mini(heap, HEAP_FULL) * HEAP_M if heap > 0 else ht
		if y - r > h + SKIN:
			# (how many steps it can't come down in: falling as it is and a metre a second faster, the ground rising
			# under it as steeply as dirt lies)
			var k := int((y - r - h - 0.05) / ((absf(ux) + absf(uz)) * 0.7 + 1.0 - minf(uy, 0.0)) * 60.0) - 1
			if k > 0:
				nap[i] = mini(k, NAP_MOST)
			px[i] = x
			py[i] = y
			pz[i] = z
			vx[i] = ux
			vy[i] = uy
			vz[i] = uz
			gnd[i] = 0
			if a >= AGE_MOST and settled < DEP_FRAME:
				_deposit(i, false)
				_remove(i)
				settled += 1
				continue
			i += 1
			continue
		# on the ground (on a square that's full of them: it's part of the heap now)
		if heap >= HEAP_FULL and settled < DEP_FRAME and _deposit(i, true):
			_remove(i)
			settled += 1
			continue
		if y < ht + r:
			y = ht + r
		if y < h + r:
			y = minf(h + r, y + HEAP_UP)
		if _gst[hc] < frame:
			_slopes(hc)
		var gx := _gxp[hc] if (int(cx) & 1) != 0 else _gxm[hc]
		var gz := _gzp[hc] if (int(cz) & 1) != 0 else _gzm[hc]
		var g2 := gx * gx + gz * gz
		var inv := 1.0 / sqrt(1.0 + g2)
		var nx := -gx * inv
		var nz := -gz * inv
		var vn := ux * nx + uy * inv + uz * nz
		if vn < -BOUNCE_V:
			var k := (1.0 + REST) * vn
			ux = (ux - k * nx) * BOUNCE_GRIP
			uy = uy - k * inv
			uz = (uz - k * nz) * BOUNCE_GRIP
			rest[i] = 0.0
			gnd[i] = 0
		else:
			if vn < 0.0:
				ux -= vn * nx
				uy -= vn * inv
				uz -= vn * nz
			var sp := sqrt(ux * ux + uy * uy + uz * uz)
			var f := MU * gdt * inv
			if sp <= f:
				ux = 0.0
				uy = 0.0
				uz = 0.0
			else:
				f = 1.0 - f / sp
				ux *= f
				uy *= f
				uz *= f
			gnd[i] = 1
			# it lies in this square's heap
			if _hn[hc] == 0:
				_hnt.append(hc)
			_hn[hc] += mm
			if sp < SLOW:
				var rs := rest[i] + dt
				rest[i] = rs
				if ((rs >= REST_S and g2 < SLOPE2) or rs >= STUCK_S or a >= AGE_S) and settled < DEP_FRAME and _deposit(i, a < AGE_MOST):
					_hn[hc] -= mm
					_remove(i)
					settled += 1
					continue
			else:
				rest[i] = 0.0
				if a >= AGE_S and settled < DEP_FRAME and _deposit(i, a < AGE_MOST):
					_hn[hc] -= mm
					_remove(i)
					settled += 1
					continue
		px[i] = x
		py[i] = y
		pz[i] = z
		vx[i] = ux
		vy[i] = uy
		vz[i] = uz
		i += 1
	settled_n += settled
	_flush()
	# this step's heap is the next one's
	for c in _ht:
		_hm[c] = 0
	var sw := _hm
	_hm = _hn
	_hn = sw
	var st := _ht
	_ht = _hnt
	_hnt = st
	_hnt.clear()
	step_us = Time.get_ticks_usec() - t0
	var per := float(step_us) / maxf(1.0, float(n + settled))
	us_per_clod = per if us_per_clod <= 0.0 else us_per_clod * 0.9 + per * 0.1
