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
## Stage 3 (dirt_physics_plan.md) put them in the site: drawn (one MultiMesh, a buffer a step: make_draw), knocked
## about by the machines' boxes (set_boxes: a body, a blade, a bucket, a truck's tray: pushed out the way they came in,
## taking the box's speed there), stacked up a blade's face and shoved off its ends, and at home under a roof (in a
## tunnel the ground's surface is the hill over it: there a clod goes by the cells round it, and its dirt is put back
## in whole blocks where it lies, DigSiteGrid.fill_sphere, what won't fit owed till it will).
## Stage 8, co-op: the host's clods are the dirt; a guest's are pictures of them with nothing in them (`ghost`). The
## host packs its clods 12 times a second into a few hundred bytes (net_pack: the new ones first, then the rest in
## turn, the ones near the guest twice as often when there are more than fit; and the numbers of those gone); the
## guest shows each where it was last said to be, gliding there (net_unpack: "puppets"). A blast's clods aren't sent
## one by one: the guest throws its own from the same random numbers (DsBlasts) and runs them here, weighing nothing.
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
const MELT_MIN := 5             # mm a column's settled dirt is laid on it a step at the least, and MELT_K of what's waiting (a clod melts in over
const MELT_MOST := 26           # ... and this at the most (the ground under a lump rises under 30 mm a frame)
const MELT_K := 0.25            # a sixth of a second, as it's seen shrinking, not in one step: the ground under a pour rises smoothly: stage 9, the owner's "boulder flickers")
const CRUMB := 125              # the sizes (mm): a crumb, 12 cm; a clod, 20 cm; a chunk, 32 cm
const CLOD := 500
const CHUNK := 2000
const FLY_MAX := 800            # clods awake at once (stage 2's measurement on the 4-core box: digsite_clod_perf)
const CLOD_US := 2000           # a step's time: over it, the slowest (then the oldest) are settled where they are
# the machines' boxes (set_boxes): what a box is
const K_BODY := 1               # a machine's body: clods are pushed out of it, and slide off its top
const K_BLADE := 2              # a dozer's blade: clods at its face don't settle (they'd be cut again at once), they stack up it and go off its ends
const K_BUCKET := 3             # a bucket, a tray: a clod lying in one stays a clod (stage 6 takes them into the load)
const K_TRAY := 4
const BOX_REST := 0.15          # of its speed kept bouncing off a box
const BOX_GRIP := 0.3           # of its speed across a box's face lost a step (it's carried along)
const PER_FROM := 64            # clods in a step before its time says what one costs
const PUSH_V := 0.2             # m/s a box's face comes at a clod: it's being shoved
const TOUCH := 0.012            # m off a box's face a clod's still at it (pushed along the ground it drops a few mm behind between steps)
const BOX_PAD := 0.45           # m round a box its squares are marked (the biggest clod, and a step's travel)
const HEAP_FACE := 5000         # mm stacked up a blade's face in a square at most (1.25 m) ...
const OVER := 0.6               # ... and a clod over this much of the blade's height goes sideways ...
const WINDROW_V := 1.6          # ... toward its nearer end, this fast (m/s), getting there at ...
const WINDROW_A := 9.0          # ... this (m/s2): off the end it's a windrow
const SLIDE_V := 0.2            # m/s more a step a clod on a body's top slides to its side
const CAVE := 0.19              # m under the ground's surface a clod's middle is: it's in a hole under a roof or by a wall (or in the ground): the cells decide
const SHRINK_S := 0.15          # a settled clod's seen shrinking into the ground this long
const GHOSTS := 256             # of those at once
const POUR_FREE := 0.3          # s a clod let go from a bucket goes through buckets' boxes (it's coming out of one: spawn's `free`)
const HELD_S := 0.15            # s a clod's been on a bucket or in a tray, and lies still there, before it's part of the load (take_in)
const HELD_SLIDE := 1.0         # s on top of a bucket or a tray's wall and not taken in: it slides off (it's not in it)
const HELD_MOST := 8.0          # s held and neither: it ages again (and is put down in the end, as any clod)
const DRAW_K := 1.3             # a lump's drawn radius, of its clod's half side (as much dirt as the cube)
# co-op (stage 8)
const NET_Q := 0.02             # m: a clod's place is sent to this
const NET_ONE := 9              # bytes a clod sent: its number (2), where it is (3 x 2), its material and size (1)
const NET_HEAD := 5             # a packet's first bytes: its own number, how many clods the host has (2), a lap in packets, how many gone
const NET_GONE := 60            # numbers of clods gone in a packet at most, each sent NET_GONE_X times (the line loses some)
const NET_GONE_X := 3
const NET_LAP := 6              # packets a lap of all the clods may take (half a second) before the far ones go every other lap
const NET_NEAR := 15.0          # m from the guest a clod's near
const NET_T_SEND := 1.0 / 12.0
const NET_LOST := 0.5           # s a puppet's not heard of before it's gone (longer when a lap is: _plost)
const N_NEW := 0                # (cnet) a clod not sent yet; sent; one the guest has already (a blast's: thrown there too)
const N_SENT := 1
const N_OWN := 2
const N_DUE := 4                # sent, and to go again in the next packet (its turn was skipped: _remove)
const NET_WAIT := 3.5           # laps a puppet's not heard of before it's gone (two more when the far ones go every other lap)

var grid                        # DigSiteGrid
var origin := Vector3.ZERO      # its corner in the world
var fly_max := FLY_MAX
var cap_us := CLOD_US           # (0: no time cap)
var seed_ := 1:
	set(v):
		seed_ = v
		_rng = v & 0x7fffffff
var step_us := 0                # the last step's time (its drawing in it: draw_us)
var draw_us := 0
var hits_n := 0                 # (tests: clods a box pushed, so far)
var buried_n := 0               # (tests: clods put back under a roof)
var log_on := false             # (tests: where each clod settled, settle_log: id, x, y, z, how (0 on the ground, 1 under a roof), ...)
var settle_log := PackedFloat32Array()
var last_id := -1               # the last clod spawn() made
var us_per_clod := 0.0          # (smoothed)
var settled_n := 0              # clods settled so far; of them shed_n forced by the caps; direct_n spawns that went straight to ground
var shed_n := 0
var direct_n := 0
var frame := 0
var held_n := 0                 # clods at a bucket's or a tray's boxes last step (the machines only look for ones to take in while there are any)
var taken_n := 0                # (tests: clods taken into a bucket or a tray so far)
var hit_n := 0                  # the last step's bounces off the ground: how many, the hardest's speed into it (m/s),
var hit_v := 0.0                # where, and how much dirt was in it (what DigSite ticks for: stage 9)
var hit_at := Vector3.ZERO
var hit_mm := 0
var ghost := false              # a guest's: its clods are pictures (nothing in them, nothing laid on the ground)
var net_on := false             # (the host's, a guest there) the clods gone are remembered for the next packet
var net_tag := N_NEW            # what a new clod's marked (N_OWN while a blast the guest throws too is thrown)
var host_n := 0                 # (the guest's) how many clods the host said it has, last

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
var hld := PackedFloat32Array()   # how long it's been on a bucket or in a tray (take_in takes the ones lying still)
var cmm := PackedInt32Array()     # its dirt (mm)
var cmat := PackedByteArray()
var cid := PackedInt32Array()     # (16 bits: the network's, stage 8)
var gnd := PackedByteArray()      # on the ground last step (2: in a hole under a roof, _cave)
var ang := PackedFloat32Array()   # how it's drawn: turned this far (rad) about (axx, 0, azz), turning at spn (rad/s: rolling, its speed over its radius)
var spn := PackedFloat32Array()
var axx := PackedFloat32Array()
var azz := PackedFloat32Array()
var csz := PackedFloat32Array()   # its material, drawn size and shape packed as the shader takes them (_pack)
var cnet := PackedByteArray()     # (co-op) N_NEW, N_SENT, N_OWN
var n := 0
# the settled, shrinking away (drawn only: their dirt's in the ground)
var gx := PackedFloat32Array()
var gy := PackedFloat32Array()
var gz := PackedFloat32Array()
var gbase := PackedFloat32Array()
var gsize := PackedFloat32Array()
var gang := PackedFloat32Array()
var gax := PackedFloat32Array()
var gaz := PackedFloat32Array()
var gt := PackedFloat32Array()
var gn := 0
# a guest's puppets: the host's clods as last heard of (number -> which, _pat), each gliding from where it was shown
# to where it's said to be over the time between its last two hearings
var qn := 0
var _pat := {}
var qid := PackedInt32Array()
var qfx := PackedFloat32Array()
var qfy := PackedFloat32Array()
var qfz := PackedFloat32Array()
var qtx := PackedFloat32Array()
var qty := PackedFloat32Array()
var qtz := PackedFloat32Array()
var qt := PackedFloat32Array()    # when it was last heard of (_now)
var qgap := PackedFloat32Array()  # how long it takes to get there
var qsz := PackedFloat32Array()
var qr := PackedFloat32Array()
var qang := PackedFloat32Array()
var qax := PackedFloat32Array()
var qaz := PackedFloat32Array()
var _now := 0.0
var _plost := NET_LOST
var _pseq := -1
var _nseq := 0                    # (the host's) the next packet's number
var _ncur := 0                    # where its turn's got to in the clods, and how many laps it's done
var _nlap := 0
var _nnew := 0                    # clods not sent yet, or due again (N_NEW, N_DUE): they go first
var _pint := NET_T_SEND           # (the guest's) the time between the host's packets, as they come
var _plast := 0.0
var _ngone := PackedInt32Array()  # numbers gone to send (times left << 16 | number)
var _nzero := 0                   # packets yet to say "none" (the last clod's gone: said NET_GONE_X times)

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
var melt := true                # (tests: false, settled dirt's laid in the step it settles, as before stage 9)
var dep_wait := DEP_COL * 3     # mm waiting on a column before the next clod there waits (melting: a quarter of what's waiting is laid a step, so about DEP_COL a step still gets down)
var _melt := 0                  # mm settled and not laid yet (in mass_mm)
var _dep := PackedInt32Array()  # settled dirt by column (mm) waiting to be laid (_flush: some each step) ...
var _depm := PackedByteArray()
var _dept := PackedInt32Array() # ... the columns with any
var _mass := 0
var _owed := 0                  # dirt that couldn't be put back under a roof yet (under a block of it, or no room there), by material:
var _owed_by := PackedInt32Array()
var _owed_at := PackedVector3Array()   # ... and where each was last tried (cells)
var _h := 0
# the machines' boxes this step: where each is and was a step ago, half its size, its kind; and the metre squares each
# is over (a bit a box), so only clods near one look at it
var _bn := 0
var _bxf: Array[Transform3D] = []
var _binv: Array[Transform3D] = []
var _bprev: Array[Transform3D] = []
var _bpinv: Array[Transform3D] = []
var _bhalf := PackedVector3Array()
var _bkind := PackedByteArray()
var _bw := 0
var _bd := 0
var _bm := PackedInt64Array()
var _bmt := PackedInt32Array()
var _hp := Vector3.ZERO         # (_hit's answer: where the clod is, how it's going)
var _hv := Vector3.ZERO
var _hpush := false            # (and whether the box is coming at it)
var _settled := 0               # (this step's)
var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _buf := PackedFloat32Array()
var _shown := -1
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
	_h = g.get_h()
	_bw = (_w + 7) / 8
	_bd = (_d + 7) / 8
	_bm.resize(_bw * _bd)
	_bm.fill(0)
	_owed_by.resize(32)
	_owed_by.fill(0)
	_owed_at.resize(32)
	for a in [gx, gy, gz, gbase, gsize, gang, gax, gaz, gt]:
		a.resize(GHOSTS)
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
	return _mass + _melt

## mm settled and still melting into the ground (laid within a few steps)
func melting_mm() -> int:
	return _melt

func owed_mm() -> int:
	return _owed

## How many clods there are (1 with none, while the last ones' dirt is still melting into the ground)
func awake() -> int:
	return n if n > 0 or _melt == 0 else 1

## The dirt in the clods whose middles are in a box (mm): t the box's middle and axes in the world, half its size (a
## dozer's load ahead of its blade)
func mass_in(t: Transform3D, half: Vector3) -> int:
	if n == 0:
		return 0
	var inv := t.affine_inverse()
	var cx := t.origin.x
	var cz := t.origin.z
	var r2 := half.length_squared()
	var hx := half.x
	var hy := half.y
	var hz := half.z
	var sum := 0
	for i in n:
		var dx := px[i] - cx
		var dz := pz[i] - cz
		if dx * dx + dz * dz > r2:
			continue
		var l: Vector3 = inv * Vector3(px[i], py[i], pz[i])
		if absf(l.x) <= hx and absf(l.y) <= hy and absf(l.z) <= hz:
			sum += cmm[i]
	return sum

## The clods lying still in a box taken out of the dirt (a bucket's or a truck's tray's, taking them into its load:
## stage 6): t the box's middle and axes in the world now and `was` a call ago (dt s: what's still against a moving box
## is still), half its size; up to `room` mm, whole clods only. A clod's taken when it's been at a bucket's or a
## tray's boxes for HELD_S and is slower than SLOW against the box. -> the mm taken; by material in `out` (material -> mm, added to)
func take_in(t: Transform3D, was: Transform3D, half: Vector3, room: int, dt: float, out: Dictionary) -> int:
	if n == 0 or room <= 0:
		return 0
	var inv := t.affine_inverse()
	var cx := t.origin.x
	var cz := t.origin.z
	var r2 := half.length_squared()
	var hx := half.x
	var hy := half.y
	var hz := half.z
	var idt := 1.0 / maxf(dt, 0.0001)
	var sum := 0
	var i := n - 1
	while i >= 0:
		var dx := px[i] - cx
		var dz := pz[i] - cz
		if dx * dx + dz * dz <= r2:
			var p := Vector3(px[i], py[i], pz[i])
			var l: Vector3 = inv * p
			if absf(l.x) <= hx and absf(l.y) <= hy and absf(l.z) <= hz and age[i] >= 0.0:
				var rel := Vector3(vx[i], vy[i], vz[i]) - (p - was * l) * idt
				if rel.length_squared() < SLOW * SLOW and hld[i] >= HELD_S and cmm[i] <= room - sum:
					var m := cmat[i]
					out[m] = int(out.get(m, 0)) + cmm[i]
					sum += cmm[i]
					_gone(i, 2)
					_remove(i)
					taken_n += 1
		i -= 1
	return sum

## mm of m straight onto the ground under p (world): what's too little for a clod
func lay(p: Vector3, m: int, mm: int) -> void:
	if mm > 0 and not ghost:
		_lay(clampf(p.x, _x0, _x1), clampf(p.z, _z0, _z1), mm, m)

## Whether there's room for `more` clods now (fly_max, the time cap): a pour over a truck's tray that there's none
## for goes in the tray as it did before the clods, not on the ground under the truck
func has_room(more := 1) -> bool:
	return n + more <= _room()

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
## `free` s (POUR_FREE) it goes through buckets' boxes: it's poured from one.
func spawn(p: Vector3, v: Vector3, m: int, mm: int, free := 0.0) -> bool:
	if mm <= 0:
		return false
	if mm < CRUMB or n >= _room():
		if ghost:
			return false
		direct_n += 1
		var x := clampf(p.x, _x0, _x1)
		var z := clampf(p.z, _z0, _z1)
		var c := Vector3((x - origin.x) * INV_CELL, (p.y - origin.y) * INV_CELL, (z - origin.z) * INV_CELL)
		if int(grid.column_top(int(c.x), int(c.z))) > int(c.y):
			# (under a roof: in blocks where it is, not on the ground over it)
			var total := mm + _owed_by[m]
			var put: int = grid.fill_sphere(c, pow(float(total / MM), 1.0 / 3.0) + 1.5, m, total / MM, true) if total >= MM else 0
			_owed += total - put * MM - _owed_by[m]
			_owed_by[m] = total - put * MM
			_owed_at[m] = c
		else:
			_lay(x, z, mm, m)
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
	hld[n] = 0.0
	age[n] = -free                  # (under 0: just let go from a bucket)
	if ghost:
		mm = 0                      # (a picture: as big as the host's, nothing in it)
	cnet[n] = net_tag
	if net_tag == N_NEW:
		_nnew += 1
	cmm[n] = mm
	cmat[n] = m
	cid[n] = _next_id
	gnd[n] = 0
	# (how it's drawn: its own shape and tumble from its number; not from the clods' random numbers, which are the dirt's)
	var k := (((_next_id + 1) * 2654435761) >> 9) & 0x3fffffff
	var t := (k & 1023) * (TAU / 1024.0)
	ang[n] = t * 3.0
	spn[n] = 2.0 + ((k >> 10) & 7)
	axx[n] = cos(t)
	azz[n] = sin(t)
	csz[n] = _pack(m, rad[n] * DRAW_K, ((k >> 13) & 255) / 256.0)
	last_id = _next_id
	_next_id = (_next_id + 1) & 0xffff
	n += 1
	_mass += mm
	return true

## mm of m come loose about p, as clods: mostly the middle size, some crumbs and chunks (bigger ones as the awake
## fill up: twice over a fifth of fly_max, three times over half), each off at v and up to `spread` m/s more any way,
## from within `within` m of p. What's left under a crumb goes straight to the ground. How many clods.
func spawn_mass(p: Vector3, v: Vector3, m: int, mm: int, spread := 0.5, within := 0.1, free := 0.0) -> int:
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
		if spawn(p + o * within, v + u * spread, m, one, free):
			made += 1
		mm -= one
	if mm > 0:
		_lay(clampf(p.x, _x0, _x1), clampf(p.z, _z0, _z1), mm, m)
	return made

# What the shader's given of a lump (its instance's custom x): its material, its radius (m, under 0.5, in 800ths) and
# a number 0 .. 1 for its shape, in one float: m + floor(size * 400) / 800 + shape / 1600
static func _pack(m: int, size: float, shape: float) -> float:
	return m + floorf(minf(size, 0.49) * 400.0) / 800.0 + shape / 1600.0

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
	if gently and _dep[mz * _w + mx] >= dep_wait:
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
	_melt += mm
	_gone(i, 0)
	return true

# clod i's settled (how: 0 on the ground, 1 under a roof): it's seen shrinking away where it lay, and the tests told
func _gone(i: int, how: int) -> void:
	if log_on:
		settle_log.append_array(PackedFloat32Array([cid[i], px[i], py[i], pz[i], how]))
	if _mm == null or gn >= GHOSTS:
		return
	var f := (csz[i] - floorf(csz[i])) * 800.0
	var size := floorf(f) / 400.0
	gx[gn] = px[i]
	gy[gn] = py[i]
	gz[gn] = pz[i]
	gsize[gn] = size
	gbase[gn] = csz[i] - floorf(f) / 800.0
	gang[gn] = ang[i]
	gax[gn] = axx[i]
	gaz[gn] = azz[i]
	gt[gn] = SHRINK_S
	gn += 1

func _solid(x: int, y: int, z: int) -> bool:
	return grid.get_cell(x, y, z) != 0

# whether clod i has ground over it (it's in a tunnel: its dirt can't be laid on the column's top)
func _roofed(i: int) -> bool:
	return grid.column_top(int((px[i] - origin.x) * INV_CELL), int((pz[i] - origin.z) * INV_CELL)) > int((py[i] - origin.y) * INV_CELL)

# Clod i's dirt put back where it lies under a roof, in whole blocks (loose), lowest first, within a ball big enough
# for it; with what its material's owed from before. What's left (under a block, or no room) is owed. The clod's gone.
func _bury(i: int) -> void:
	var m := cmat[i]
	var c := Vector3((px[i] - origin.x) * INV_CELL, (py[i] - origin.y) * INV_CELL, (pz[i] - origin.z) * INV_CELL)
	var total := cmm[i] + _owed_by[m]
	var cells := total / MM
	var put := 0
	if cells > 0:
		put = grid.fill_sphere(c, pow(float(cells), 1.0 / 3.0) + 1.5, m, cells, true)
	var left := total - put * MM
	_owed += left - _owed_by[m]
	_owed_by[m] = left
	_owed_at[m] = c
	buried_n += 1
	_gone(i, 1)
	_remove(i)

# what's owed put down: in blocks where it was last tried, a wider ball; what's left then (under a block, mostly) on
# the ground over it
func _pay_owed() -> void:
	if _owed <= 0:
		return
	for m in _owed_by.size():
		var mm := _owed_by[m]
		if mm <= 0:
			continue
		var c := _owed_at[m]
		var cells := mm / MM
		if cells > 0:
			mm -= MM * int(grid.fill_sphere(c, pow(float(cells), 1.0 / 3.0) + 4.0, m, cells, true))
		if mm > 0:
			grid.put_layer(clampi(int(c.x), 12, _w - 13), clampi(int(c.z), 12, _d - 13), mm, m)
		_owed_by[m] = 0
	_owed = 0

# mm of m straight onto the ground at world (x, z) (what never became a clod), spread as a clod's is
func _lay(x: float, z: float, mm: int, m: int) -> void:
	if ghost:
		return
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
	var c := cnet[i]
	if c == N_NEW or c == N_DUE:
		_nnew -= 1
	if net_on and (c == N_SENT or c == N_DUE):
		_ngone.append(((NET_GONE_X - 1) << 16) | cid[i])
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
		hld[i] = hld[n]
		cmm[i] = cmm[n]
		cmat[i] = cmat[n]
		cid[i] = cid[n]
		gnd[i] = gnd[n]
		ang[i] = ang[n]
		spn[i] = spn[n]
		axx[i] = axx[n]
		azz[i] = azz[n]
		csz[i] = csz[n]
		cnet[i] = cnet[n]
		# (the last clod's come down here, behind where the packets' turn has got to, before its own turn came:
		# it would wait a whole lap more. It goes in the next packet.)
		if net_on and i < _ncur and n >= _ncur and cnet[i] == N_SENT:
			cnet[i] = N_DUE
			_nnew += 1

# room for `most` clods (the arrays only ever grow: n is how many are in use)
func _grow(most: int) -> void:
	for a in [px, py, pz, vx, vy, vz, rad, nap, rest, age, hld, cmm, cmat, cid, gnd, ang, spn, axx, azz, csz, cnet]:
		a.resize(most)

# the settled dirt laid on the ground: a share of what's waiting on each column (all of it: all at once)
func _flush(all := false) -> void:
	var keep := 0
	var whole := all or not melt
	for j in _dept.size():
		var c := _dept[j]
		var v := _dep[c]
		if v > 0:                   # (a guest's picture has nothing in it: nothing's laid, the ground's not touched)
			var lay := v if whole else mini(v, clampi(int(v * MELT_K), MELT_MIN, MELT_MOST))
			grid.put_layer(c % _w, c / _w, lay, _depm[c])
			v -= lay
			_dep[c] = v
			_melt -= lay
			if v > 0:
				_dept[keep] = c
				keep += 1
	_dept.resize(keep)

## Every clod settled where it is, now (a save, leaving, the host changing): all of it's in the ground after, what
## was owed too
func land_all() -> void:
	if ghost:
		drop_ghosts()
		return
	for i in range(n - 1, -1, -1):
		if _roofed(i):
			_bury(i)
		else:
			_deposit(i, false)
			_remove(i)
		settled_n += 1
	_flush(true)
	_pay_owed()
	for c in _ht:
		_hm[c] = 0
	_ht.clear()
	gn = 0
	if _mm:
		_draw(0.0)

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

# ---------------------------------------------------------------- the machines' boxes

var _bstale := true             # (no step with clods since the boxes were last given: where they were then says nothing of their speed)

## The machines' boxes for the next step: [[Transform3D (the box's middle, in the world), half its size, kind (K_*;
## 0: not there now)]], 62 at most, the same boxes in the same order every time: a box's speed is how far it's gone
## since the last call. Called each step there are clods (DigSite).
func set_boxes(list: Array) -> void:
	var k := mini(list.size(), 62)
	var moved := k != _bn or _bstale
	if moved:
		_bxf.resize(k)
		_binv.resize(k)
		_bprev.resize(k)
		_bpinv.resize(k)
		_bhalf.resize(k)
		_bkind.resize(k)
		for b in k:
			var t: Transform3D = list[b][0]
			_bxf[b] = t
			_binv[b] = t.affine_inverse()
			_bprev[b] = t
			_bpinv[b] = _binv[b]
			_bhalf[b] = list[b][1]
			_bkind[b] = list[b][2]
		_bn = k
		_bstale = false
	else:
		for b in k:
			var box: Array = list[b]
			var t: Transform3D = box[0]
			_bprev[b] = _bxf[b]
			_bpinv[b] = _binv[b]
			if t != _bxf[b]:
				moved = true
				_bxf[b] = t
				_binv[b] = t.affine_inverse()
			if _bkind[b] != int(box[2]) or _bhalf[b] != (box[1] as Vector3):
				moved = true
				_bhalf[b] = box[1]
				_bkind[b] = box[2]
	if not moved:
		return
	# the metre squares each is over
	for c in _bmt:
		_bm[c] = 0
	_bmt.clear()
	for b in k:
		if _bkind[b] == 0:
			continue
		var t := _bxf[b]
		var h := _bhalf[b]
		var bs := t.basis
		var ex := absf(bs.x.x) * h.x + absf(bs.y.x) * h.y + absf(bs.z.x) * h.z + BOX_PAD
		var ez := absf(bs.x.z) * h.x + absf(bs.y.z) * h.y + absf(bs.z.z) * h.z + BOX_PAD
		var x0 := maxi(0, floori(t.origin.x - ex - origin.x))
		var x1 := mini(_bw - 1, floori(t.origin.x + ex - origin.x))
		var z0 := maxi(0, floori(t.origin.z - ez - origin.z))
		var z1 := mini(_bd - 1, floori(t.origin.z + ez - origin.z))
		var bit := 1 << b
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var c := z * _bw + x
				if _bm[c] == 0:
					_bmt.append(c)
				_bm[c] |= bit

# A clod (at l in box b's own frame, within its radius r of it; `was` where it was a step ago, v how it's going) put
# out of the box: by the face it came in at (the one it was furthest outside a step ago, the box where it was then:
# so a thin wall or a quick box doesn't let it through); if it was inside then too, by the nearest face, never the
# bottom. It keeps the box's own speed there, and of its speed against that: none into the face (a bounce if it hit
# hard), less across it (it's carried). A blade's: one high up its face goes off toward the nearer end. On top of a
# body or a blade it slides off the side. -> _hp, _hv, _hpush
func _hit(b: int, l: Vector3, r: float, was: Vector3, v: Vector3, dt: float, held := 0.0) -> void:
	var h := _bhalf[b]
	var e := Vector3(h.x + r, h.y + r, h.z + r)
	var lp: Vector3 = _bpinv[b] * was
	var sx := absf(lp.x) - e.x
	var sy := absf(lp.y) - e.y
	var sz := absf(lp.z) - e.z
	var k := 1
	var sgn := 1.0
	if maxf(sx, maxf(sy, sz)) > -0.01:
		if sx >= sy and sx >= sz:
			k = 0
		elif sz > sy:
			k = 2
		sgn = -1.0 if lp[k] < 0.0 else 1.0
	else:
		var dx := e.x - absf(l.x)
		var dy := e.y - l.y
		var dz := e.z - absf(l.z)
		if dx <= dy and dx <= dz:
			k = 0
		elif dz < dy:
			k = 2
		if k != 1:
			sgn = -1.0 if l[k] < 0.0 else 1.0
	l[k] = sgn * (e[k] + 0.001)
	var t := _bxf[b]
	var p: Vector3 = t * l
	var bv: Vector3 = (p - _bprev[b] * l) / dt
	var nrm: Vector3 = t.basis[k] * sgn
	var rel := v - bv
	var vn := rel.dot(nrm)
	if vn < 0.0:
		rel -= nrm * (vn * (1.0 + BOX_REST) if vn < -BOUNCE_V else vn)
	rel -= (rel - nrm * rel.dot(nrm)) * BOX_GRIP
	var kind := _bkind[b]
	var off_x := absf(l.x) - h.x
	var off_z := absf(l.z) - h.z
	if k == 1 and sgn > 0.0 and (off_x > 0.0 or off_z > 0.0):
		# (on top, but its middle's past the box's edge: it's hanging on the edge by its own width, and goes on off
		# it. Without this what a bucket poured down the outside of a truck's tray lay in a row along its floor's edge)
		var ka := 0 if off_x > off_z else 2
		rel += t.basis[ka] * (SLIDE_V if l[ka] >= 0.0 else -SLIDE_V)
	elif kind == K_BLADE and k != 1:
		var ka := 2 if h.z >= h.x else 0
		if k != ka and l.y > h.y * (2.0 * OVER - 1.0):
			var along: Vector3 = t.basis[ka]
			var cur := rel.dot(along)
			rel += along * (move_toward(cur, WINDROW_V if l[ka] >= 0.0 else -WINDROW_V, WINDROW_A * dt) - cur)
	elif kind <= K_BLADE and k == 1 and sgn > 0.0:
		# (on top of a body or a blade: off its nearer long side)
		var ka := 0 if h.x <= h.z else 2
		rel += t.basis[ka] * (SLIDE_V if l[ka] >= 0.0 else -SLIDE_V)
	elif k == 1 and sgn > 0.0 and held >= HELD_SLIDE and (kind == K_BUCKET or minf(h.x, h.z) < 0.15):
		# (on top of a bucket, or of a tray's wall, and not taken into the load: off its nearer side)
		var ka := 0 if h.x <= h.z else 2
		rel += t.basis[ka] * (SLIDE_V if l[ka] >= 0.0 else -SLIDE_V)
	hits_n += 1
	_hpush = bv.dot(nrm) > PUSH_V
	_hp = p
	_hv = bv + rel

# ---------------------------------------------------------------- under a roof

# Clod i, its middle well under the ground's surface and ground over it (at x, y, z after this step's move, going at
# ux, uy, uz, aged a): in a tunnel, or gone into a wall. Here the cells decide, not the surface: a solid cell where it
# would go across is a wall (it stays where it was across), one under its feet is the floor (it bounces, rolls on the
# flat, comes to rest), one over its head stops it rising. At rest (as on the surface: slow REST_S, or old) its
# dirt's put back where it lies, in whole blocks (_bury). (Only with ground over it: the loose layer is up to two
# blocks deep with no cell to show for it, so in the open the cells can't say where the ground is.)
# -> 0 it's stepped, 1 it's settled and gone, 2 it's just in the ground a little (the surface's rule has it), 3 it
# met a wall in the open (it's back where it was across: _hp, _hv; the surface's rule has it there)
func _cave(i: int, x: float, y: float, z: float, ux: float, uy: float, uz: float, a: float, dt: float) -> int:
	var ox := origin.x
	var oy := origin.y
	var oz := origin.z
	var r := rad[i]
	var cx := int((x - ox) * INV_CELL)
	var cy := int((y - oy) * INV_CELL)
	var cz := int((z - oz) * INV_CELL)
	if grid.get_cell(cx, cy, cz) != 0:
		if gnd[i] != 2:
			return 2                # (it wasn't in a hole: it's come down into the ground, or the ground's come up round it)
		var qx := int((px[i] - ox) * INV_CELL)
		var qz := int((pz[i] - oz) * INV_CELL)
		if (qx != cx or qz != cz) and grid.get_cell(qx, cy, qz) == 0:
			x = px[i]
			z = pz[i]
			ux *= -0.2
			uz *= -0.2
			cx = qx
			cz = qz
			if int(grid.column_top(cx, cz)) <= cy:
				_hp = Vector3(x, y, z)
				_hv = Vector3(ux, uy, uz)
				return 3
		else:
			var up := 1
			while up <= 3 and grid.get_cell(cx, cy + up, cz) != 0:
				up += 1
			if up > 3:
				if int(grid.column_top(cx, cz)) - cy < 8:
					return 2
				# (deep in the ground: it's closed over it. Its dirt's owed)
				px[i] = x
				py[i] = y
				pz[i] = z
				_bury(i)
				settled_n += 1
				return 1
			y = oy + (cy + up) * CELL + r
	if uy > 0.0 and grid.get_cell(cx, int((y + r - oy) * INV_CELL), cz) != 0:
		uy = 0.0
	var fy := int((y - r - SKIN - oy) * INV_CELL)
	var done := false
	if grid.get_cell(cx, fy, cz) != 0:
		var top := oy + (fy + 1) * CELL
		if y < top + r:
			y = top + r
		if uy < -BOUNCE_V:
			uy = -uy * REST
			ux *= BOUNCE_GRIP
			uz *= BOUNCE_GRIP
			rest[i] = 0.0
		else:
			if uy < 0.0:
				uy = 0.0
			var sp := sqrt(ux * ux + uz * uz)
			var f := MU * G * dt
			if sp <= f:
				ux = 0.0
				uz = 0.0
				spn[i] = 0.0
			else:
				spn[i] = sp / r
				axx[i] = uz / sp
				azz[i] = -ux / sp
				f = 1.0 - f / sp
				ux *= f
				uz *= f
			if sp < SLOW:
				rest[i] += dt
				done = rest[i] >= REST_S or a >= AGE_S
			else:
				rest[i] = 0.0
				done = a >= AGE_S
	else:
		done = a >= AGE_MOST
	px[i] = x
	py[i] = y
	pz[i] = z
	vx[i] = ux
	vy[i] = uy
	vz[i] = uz
	gnd[i] = 2                      # (in a hole: what it meets solid next is a wall, a floor)
	nap[i] = 0
	if not done:
		return 0
	if _roofed(i):
		_bury(i)
	else:
		_deposit(i, false)
		_remove(i)
	settled_n += 1
	return 1

# ---------------------------------------------------------------- each step

## A step of dt (1/60 s)
func step(dt: float) -> void:
	hit_n = 0
	hit_v = 0.0
	if n == 0:
		step_us = 0
		draw_us = 0
		held_n = 0
		_bstale = true
		if not _dept.is_empty():
			_flush()
		if not _ht.is_empty():
			for c in _ht:
				_hm[c] = 0
			_ht.clear()
		if _mm and (gn > 0 or qn > 0 or _shown != 0):
			_draw(dt)
			step_us = draw_us
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
			if gnd[i] == 1:
				_deposit(i, false)
				_remove(i)
				shed -= 1
				settled += 1
				shed_n += 1
			i -= 1
		while shed > 0 and n > 0:
			if _roofed(0):
				_bury(0)
			else:
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
	var nb := _bn
	var bmask := _bm
	var bw := _bw
	var binv := _binv
	var bhalf := _bhalf
	var bkind := _bkind
	var held := 0
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
		# (well up in the air, no machine about: the ground's not looked at till it could be there)
		var np := nap[i]
		if np > 0 and a < AGE_MOST and (nb == 0 or bmask[int(z - oz) * bw + int(x - ox)] == 0):
			nap[i] = np - 1
			px[i] = x
			py[i] = y
			pz[i] = z
			vy[i] = uy
			i += 1
			continue
		# the machines' boxes over this metre square
		var tk := 0
		if nb > 0:
			var bm := bmask[int(z - oz) * bw + int(x - ox)]
			if bm != 0:
				var b := 0
				var rt := r + TOUCH
				while bm != 0:
					if (bm & 1) != 0:
						var l: Vector3 = binv[b] * Vector3(x, y, z)
						var hh := bhalf[b]
						# (one just poured from a bucket goes through buckets: a < 0)
						if absf(l.x) < hh.x + rt and absf(l.y) < hh.y + rt and absf(l.z) < hh.z + rt and (a >= 0.0 or bkind[b] != K_BUCKET):
							_hit(b, l, r, Vector3(px[i], py[i], pz[i]), Vector3(ux, uy, uz), dt, hld[i])
							x = _hp.x
							y = _hp.y
							z = _hp.z
							ux = _hv.x
							uy = _hv.y
							uz = _hv.z
							# (a blade's only a blade to it while it's shoving it: at a blade standing still a clod settles as anywhere)
							var kd := bkind[b]
							if kd == K_BLADE and not _hpush:
								kd = K_BODY
							if kd > tk:
								tk = kd
					bm >>= 1
					b += 1
		if tk >= K_BUCKET:
			held += 1
			hld[i] += dt
		else:
			hld[i] = 0.0
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
		if y < ht - CAVE and int(grid.column_top(int(cx), int(cz))) > int((y - oy) * INV_CELL):
			# (well under the surface, ground over it: in a tunnel, or come up against a wall)
			var how := _cave(i, x, y, z, ux, uy, uz, a, dt)
			if how == 0:
				i += 1
				continue
			if how == 1:
				continue
			if how == 3:
				# (a wall in the open: it's back where it was across, and goes by the surface there)
				x = _hp.x
				z = _hp.z
				ux = _hv.x
				uz = _hv.z
				cx = (x - ox) * INV_CELL
				cz = (z - oz) * INV_CELL
				hc = (int(cz) >> 1) * hw + (int(cx) >> 1)
				ht = oy + grid.height_at(cx, cz) * CELL
		var heap := _hm[hc] - mm
		var h := ht + mini(heap, HEAP_FULL) * HEAP_M if heap > 0 else ht
		if tk == K_BLADE:
			# (at a blade's face they stack: each on those counted before it in its square this step)
			heap = _hn[hc]
			h = ht + mini(heap, HEAP_FACE) * HEAP_M
		if y - r > h + SKIN:
			# (how many steps it can't come down in: falling as it is and a metre a second faster, the ground rising
			# under it as steeply as dirt lies)
			var k := int((y - r - h - 0.05) / ((absf(ux) + absf(uz)) * 0.7 + 1.0 - minf(uy, 0.0)) * 60.0) - 1
			if k > 0:
				nap[i] = mini(k, NAP_MOST)
			if tk >= K_BUCKET and a > 0.0 and hld[i] < HELD_MOST:
				# (off the ground on a bucket or in a tray: it's held there, it doesn't age)
				a = 0.0
				age[i] = 0.0
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
		var free := tk != K_BLADE
		if heap >= HEAP_FULL and free and settled < DEP_FRAME and _deposit(i, true):
			_remove(i)
			settled += 1
			continue
		if y < ht + r:
			y = ht + r
		if y < h + r:
			y = minf(h + r, y + HEAP_UP)
		if _gst[hc] < frame:
			_slopes(hc)
		var sx := _gxp[hc] if (int(cx) & 1) != 0 else _gxm[hc]
		var sz := _gzp[hc] if (int(cz) & 1) != 0 else _gzm[hc]
		var g2 := sx * sx + sz * sz
		var inv := 1.0 / sqrt(1.0 + g2)
		var nx := -sx * inv
		var nz := -sz * inv
		var vn := ux * nx + uy * inv + uz * nz
		if vn < -BOUNCE_V:
			hit_n += 1
			if -vn > hit_v:
				hit_v = -vn
				hit_at = Vector3(x, y, z)
				hit_mm = cmm[i]
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
				spn[i] = 0.0
			else:
				# (rolling: it turns as fast as it goes, about the line across its way)
				spn[i] = sp / r
				if sp > 0.3:
					axx[i] = uz / sp
					azz[i] = -ux / sp
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
				var rs := rest[i] + dt if free else 0.0
				rest[i] = rs
				if ((free and ((rs >= REST_S and g2 < SLOPE2) or rs >= STUCK_S or a >= AGE_S)) or a >= AGE_MOST) and settled < DEP_FRAME and _deposit(i, a < AGE_MOST):
					_hn[hc] -= mm
					_remove(i)
					settled += 1
					continue
			else:
				rest[i] = 0.0
				if ((free and a >= AGE_S) or a >= AGE_MOST) and settled < DEP_FRAME and _deposit(i, a < AGE_MOST):
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
	held_n = held
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
	if _mm:
		_draw(dt)
	step_us = Time.get_ticks_usec() - t0
	# (what a clod costs, from steps with enough of them to say: a handful's time is mostly the step's own, and made
	# a clod look so dear that the next ones let go were refused, 13 of 300 in stage 3's test)
	if n + settled >= PER_FROM:
		var per := float(step_us) / float(n + settled)
		us_per_clod = per if us_per_clod <= 0.0 else us_per_clod * 0.9 + per * 0.1

# ---------------------------------------------------------------- drawing

## The clods drawn, under `parent`: one MultiMesh of lumps (DsLook.clod_mesh), a buffer a step. Each instance is where
## its clod is (no turn or size in its transform: the shader, shaders/ds_dirt.gdshader, turns and sizes it from the
## instance's custom data: _pack, its turn, the line it turns about), so a clod costs seven numbers a step to draw.
func make_draw(parent: Node3D) -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = DsLook.clod_mesh(1)
	var most := FLY_MAX + GHOSTS
	_mm.instance_count = most
	_buf.resize(most * 16)
	_buf.fill(0.0)
	for i in most:
		_buf[i * 16] = 1.0
		_buf[i * 16 + 5] = 1.0
		_buf[i * 16 + 10] = 1.0
	_mm.buffer = _buf
	_mm.visible_instance_count = 0
	_shown = 0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/voxel/digsite/shaders/ds_dirt.gdshader")
	mat.render_priority = 1
	var cols := PackedVector3Array()
	for c: Color in DsMats.COL:
		cols.append(Vector3(c.r, c.g, c.b))
	while cols.size() < 16:
		cols.append(Vector3(0.45, 0.25, 0.16))
	mat.set_shader_parameter("soil_cols", cols)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Dirt"
	_mmi.multimesh = _mm
	_mmi.material_override = mat
	_mmi.top_level = true
	_mmi.custom_aabb = AABB(origin, Vector3(_w, _h, _d) * CELL)
	_mmi.visible = false
	parent.add_child(_mmi)
	_mmi.global_transform = Transform3D.IDENTITY

# the buffer brought up to date and shown: the clods, then the settled ones shrinking away
func _draw(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var buf := _buf
	var most := _mm.instance_count
	var k := mini(n, most)
	var o := 0
	var i := 0
	while i < k:
		var a := ang[i] + spn[i] * dt
		ang[i] = a
		buf[o + 3] = px[i]
		buf[o + 7] = py[i]
		buf[o + 11] = pz[i]
		buf[o + 12] = csz[i]
		buf[o + 13] = a
		buf[o + 14] = axx[i]
		buf[o + 15] = azz[i]
		o += 16
		i += 1
	# (a guest's) the host's clods, each on its way to where it was last said to be
	var q := 0
	var now := _now
	while q < qn and i < most:
		var f := minf((now - qt[q]) / qgap[q], 1.0)
		var x := qfx[q] + (qtx[q] - qfx[q]) * f
		var z := qfz[q] + (qtz[q] - qfz[q]) * f
		if f < 1.0:
			# (rolling: it turns as fast as it goes, about the line across its way)
			var ux := (qtx[q] - qfx[q]) / qgap[q]
			var uz := (qtz[q] - qfz[q]) / qgap[q]
			var sp := sqrt(ux * ux + uz * uz)
			if sp > 0.3:
				qax[q] = uz / sp
				qaz[q] = -ux / sp
			qang[q] += minf(sp / qr[q], 12.0) * dt
		buf[o + 3] = x
		buf[o + 7] = qfy[q] + (qty[q] - qfy[q]) * f
		buf[o + 11] = z
		buf[o + 12] = qsz[q]
		buf[o + 13] = qang[q]
		buf[o + 14] = qax[q]
		buf[o + 15] = qaz[q]
		o += 16
		i += 1
		q += 1
	var j := 0
	while j < gn:
		var t := gt[j] - dt
		if t <= 0.0:
			gn -= 1
			if j != gn:
				gx[j] = gx[gn]
				gy[j] = gy[gn]
				gz[j] = gz[gn]
				gbase[j] = gbase[gn]
				gsize[j] = gsize[gn]
				gang[j] = gang[gn]
				gax[j] = gax[gn]
				gaz[j] = gaz[gn]
				gt[j] = gt[gn]
			continue
		gt[j] = t
		if i < most:
			var f := t / SHRINK_S
			buf[o + 3] = gx[j]
			buf[o + 7] = gy[j] - gsize[j] * (1.0 - f) * 0.6
			buf[o + 11] = gz[j]
			buf[o + 12] = gbase[j] + floorf(gsize[j] * f * 400.0) / 800.0
			buf[o + 13] = gang[j]
			buf[o + 14] = gax[j]
			buf[o + 15] = gaz[j]
			o += 16
			i += 1
		j += 1
	if i > 0:
		_mm.buffer = buf
	if i != _shown:
		_shown = i
		_mm.visible_instance_count = i
		_mmi.visible = i > 0
	draw_us = Time.get_ticks_usec() - t0

# ---------------------------------------------------------------- co-op (stage 8)

## How many clods are to be seen here: its own, and (a guest's) the host's
func shown() -> int:
	return n + qn

## (a guest's) every picture gone: its own clods (nothing in them) and the host's
func drop_ghosts() -> void:
	if ghost:
		for i in range(n - 1, -1, -1):
			_remove(i)
		for c in _ht:
			_hm[c] = 0
		_ht.clear()
	qn = 0
	_pat.clear()
	_pseq = -1
	_pint = NET_T_SEND
	host_n = 0
	gn = 0
	if _mm:
		_draw(0.0)

## (the host's) a guest's just come: every clod's new to it
func net_reset() -> void:
	_nnew = 0
	for i in n:
		cnet[i] = N_NEW
	_nnew = n
	_ngone.clear()
	_ncur = 0
	_nzero = 0

## (the host's) whether there's anything to say: clods, or ones gone the guest's yet to hear of
func net_due() -> bool:
	return n > 0 or not _ngone.is_empty() or _nzero > 0

## (the host's) the next packet, `most` bytes at most: its number; how many clods the guest should be seeing (those
## not its own: a blast's it threw itself); how many packets a lap of them takes now (128 more: the far ones go every
## other lap); the numbers of those gone since; then clods, NET_ONE bytes each: the ones never sent first, then the
## rest in turn from where the last packet stopped. `near`: where the guest is (far ones wait when a lap's long).
func net_pack(near: Vector3, most: int) -> PackedByteArray:
	var b := PackedByteArray()
	var own := 0
	for i in n:
		if cnet[i] == N_OWN:
			own += 1
	var mine := n - own
	var g := mini(_ngone.size(), NET_GONE)
	var room := maxi(0, (most - NET_HEAD - g * 2) / NET_ONE)
	var lap := ceili(float(mine) / maxf(1.0, float(room)))
	var skip := lap > NET_LAP
	b.resize(NET_HEAD + g * 2 + mini(room, mine) * NET_ONE)
	b[0] = _nseq & 255
	_nseq += 1
	b.encode_u16(1, mine)
	b[3] = mini(lap, 127) | (128 if skip else 0)
	b[4] = g
	var o := NET_HEAD
	for k in g:
		var e := _ngone[k]
		b.encode_u16(o, e & 0xffff)
		o += 2
		if (e >> 16) > 0:
			_ngone.append(e - 0x10000)
	if g > 0:
		_ngone = _ngone.slice(g)
	if mine == 0:
		_nzero = maxi(0, _nzero - 1)
		return b.slice(0, o)
	_nzero = NET_GONE_X
	var sent := 0
	var picked := PackedInt32Array()
	if _nnew > 0:
		var i := n - 1                  # (the new ones are mostly the last)
		while i >= 0 and sent < room and _nnew > 0:
			if cnet[i] == N_NEW or cnet[i] == N_DUE:
				cnet[i] = 3
				_nnew -= 1
				picked.append(i)
				sent += 1
			i -= 1
	var seen := 0
	var far2 := NET_NEAR * NET_NEAR
	while sent < room and seen < n:
		if _ncur >= n:
			_ncur = 0
			_nlap += 1
		var i := _ncur
		_ncur += 1
		seen += 1
		if cnet[i] != N_SENT:
			continue
		if skip and (_nlap & 1) != 0:
			var dx := px[i] - near.x
			var dz := pz[i] - near.z
			if dx * dx + dz * dz > far2:
				continue
		picked.append(i)
		sent += 1
	var ox := origin.x
	var oy := origin.y
	var oz := origin.z
	var inv := 1.0 / NET_Q
	for i in picked:
		cnet[i] = N_SENT
		b.encode_u16(o, cid[i])
		b.encode_u16(o + 2, clampi(roundi((px[i] - ox) * inv), 0, 65535))
		b.encode_u16(o + 4, clampi(roundi((py[i] - oy) * inv), 0, 65535))
		b.encode_u16(o + 6, clampi(roundi((pz[i] - oz) * inv), 0, 65535))
		# (its size: which power of two blocks its radius is nearest, 0 .. 7)
		var k := clampi(roundi(log(rad[i] * 16.0) * 4.328085), 0, 7)
		b[o + 8] = (cmat[i] & 31) | (k << 5)
		o += NET_ONE
	return b.slice(0, o)

## (a guest's) a packet from the host taken: the clods in it shown (new ones where they are, known ones set gliding
## there), the ones gone taken away. One older than the last taken is dropped (the line can swap them).
func net_unpack(b: PackedByteArray) -> void:
	if b.size() < NET_HEAD:
		return
	var seq := b[0]
	if _pseq >= 0:
		var d := (seq - _pseq) & 255
		if d == 0 or d > 128:
			return
		# (how often they really come: a host at 30 frames a second sends 10 a second, a busy one fewer)
		_pint = clampf(lerpf(_pint, (_now - _plast) / d, 0.2), NET_T_SEND, 0.5)
	_pseq = seq
	_plast = _now
	host_n = b.decode_u16(1)
	var lap := b[3] & 127
	# (how long one may go unheard of: NET_WAIT laps as the packets come, so one lost and a turn late don't drop it;
	# two more when the far ones go every other lap)
	_plost = maxf(NET_LOST, (NET_WAIT + 2.0 if (b[3] & 128) != 0 else NET_WAIT) * lap * _pint)
	var g := b[4]
	var o := NET_HEAD
	if b.size() < o + g * 2:
		return
	for k in g:
		var at: int = _pat.get(b.decode_u16(o), -1)
		if at >= 0:
			_pdrop(at)
		o += 2
	if host_n == 0:
		while qn > 0:
			_pdrop(qn - 1)
		return
	var ox := origin.x
	var oy := origin.y
	var oz := origin.z
	var now := _now
	while o + NET_ONE <= b.size():
		var id := b.decode_u16(o)
		var x := ox + b.decode_u16(o + 2) * NET_Q
		var y := oy + b.decode_u16(o + 4) * NET_Q
		var z := oz + b.decode_u16(o + 6) * NET_Q
		var ms := b[o + 8]
		o += NET_ONE
		var at: int = _pat.get(id, -1)
		if at < 0:
			if qn >= FLY_MAX:
				continue
			if qn == qid.size():
				for a in [qid, qfx, qfy, qfz, qtx, qty, qtz, qt, qgap, qsz, qr, qang, qax, qaz]:
					a.resize(maxi(64, qn * 2))
			at = qn
			qn += 1
			_pat[id] = at
			qid[at] = id
			qfx[at] = x
			qfy[at] = y
			qfz[at] = z
			qgap[at] = NET_T_SEND
			var r := 0.0625 * pow(2.0, (ms >> 5) / 3.0)
			qr[at] = r
			var k := (((id + 1) * 2654435761) >> 9) & 0x3fffffff
			var t := (k & 1023) * (TAU / 1024.0)
			qang[at] = t * 3.0
			qax[at] = cos(t)
			qaz[at] = sin(t)
			qsz[at] = _pack(ms & 31, r * DRAW_K, ((k >> 13) & 255) / 256.0)
		else:
			# (from where it's shown now)
			var gap := qgap[at]
			var f := minf((now - qt[at]) / gap, 1.0)
			qfx[at] += (qtx[at] - qfx[at]) * f
			qfy[at] += (qty[at] - qfy[at]) * f
			qfz[at] += (qtz[at] - qfz[at]) * f
			qgap[at] = clampf(now - qt[at], NET_T_SEND, 0.6)
		qtx[at] = x
		qty[at] = y
		qtz[at] = z
		qt[at] = now

func _pdrop(at: int) -> void:
	_pat.erase(qid[at])
	qn -= 1
	if at != qn:
		for a in [qid, qfx, qfy, qfz, qtx, qty, qtz, qt, qgap, qsz, qr, qang, qax, qaz]:
			a[at] = a[qn]
		_pat[qid[at]] = at

## (a guest's) a frame of dt: its clock on, the puppets not heard of for too long gone (their clods settled and every
## word of it lost, or the host's gone quiet)
func ghost_tick(dt: float) -> void:
	_now += dt
	var i := qn - 1
	while i >= 0:
		if _now - qt[i] > _plost:
			_pdrop(i)
		i -= 1
