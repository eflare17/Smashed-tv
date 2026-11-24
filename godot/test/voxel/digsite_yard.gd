extends RefCounted
## The dirt-physics work's test yard (integration/dirt_physics_plan.md, stage 1): what its tests and shots share. Boots
## the arena, travels to the Dig Site, levels a 24 x 24 m patch of it (firm dirt, nothing loose), finds the bulldozer
## by type, parks it on the patch's edge heading across, drives it by script; a frame timer; and the mass sum (the
## ground, every bucket and tray, what's falling, the backpack, the spade's carry: all in mm over a column).
## Used as: const Yard := preload("res://test/voxel/digsite_yard.gd"); var y := Yard.new(); y.boot(self). No game code
## is changed by it. Owned by the voxel session.

const PATCH := 24.0                         # m across (x and z)
const CENTRE := Vector3(0.0, 0.0, -2.0)     # the patch's middle, from the site's (clear of the parked machines at z 24+)
const SOFT := 12                            # cells under the patch's top made plain dirt (1.5 m: a blade never meets rock)
const MM := 125

var tree: SceneTree
var arena: Node
var level_y := 0                # the patch's top cell (cell y), once levelled
var levelled := {}              # what level() did: {level, raised, lowered, was_min, was_max}

func boot(t: SceneTree) -> void:
	tree = t
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	t.root.add_child(arena)

func ds() -> DigSite:
	return arena.digsite

func grid():
	return ds().terrain.grid

func travel() -> void:
	arena.godmode = true
	arena.phone.travel("digsite")

func arrived() -> bool:
	return ds() != null and ds().active and not arena.phone._going

# ---------------------------------------------------------------- the patch

func centre() -> Vector3:
	return DigSite.AT + CENTRE

## The patch's columns: [x0, z0, x1, z1] (cells, x1 and z1 past the end)
func patch_cells() -> Array:
	var tr: DsTerrain = ds().terrain
	var a := tr.cell_of(centre() - Vector3(PATCH * 0.5, 0, PATCH * 0.5))
	var n := roundi(PATCH / DsTerrain.CELL)
	return [a.x, a.z, a.x + n, a.z + n]

## The patch made flat: every column's top at one level (the most common one there now, so as little as can be is
## changed), firm dirt for SOFT cells under it (topsoil on top as the site's made), nothing above, no loose layer.
## The dirt's let come to rest after. -> levelled
func level() -> Dictionary:
	var g = grid()
	var pc := patch_cells()
	var seen := {}
	var lo := 1 << 30
	var hi := -1
	for z in range(pc[1], pc[3]):
		for x in range(pc[0], pc[2]):
			var top: int = g.column_top(x, z)
			seen[top] = int(seen.get(top, 0)) + 1
			lo = mini(lo, top)
			hi = maxi(hi, top)
	var best := -1
	for k in seen:
		if best < 0 or int(seen[k]) > int(seen[best]):
			best = k
	level_y = best
	var raised := 0
	var lowered := 0
	var h: int = g.get_h()
	for z in range(pc[1], pc[3]):
		for x in range(pc[0], pc[2]):
			var top: int = g.column_top(x, z)
			for y in range(level_y + 1, mini(top + 1, h)):
				g.set_cell(x, y, z, 0)
				lowered += 1
			if top < level_y:
				raised += level_y - top
			for y in range(level_y - SOFT + 1, level_y + 1):
				g.set_cell(x, y, z, DsMats.TOPSOIL if y > level_y - 4 else DsMats.DIRT)
			g.set_layer(x, z, 0, 0)
	# (to rest: nothing in the patch should move, its rim's steps are well under what firm dirt stands at)
	var n := 0
	while n < 600 and (g.awake_count() > 0 or g.layer_awake() > 0):
		g.layer_step(1000000)
		if n % 3 == 0:
			g.settle(1000000)
		n += 1
	levelled = {"level": level_y, "raised": raised, "lowered": lowered, "was_min": lo, "was_max": hi, "rest_ticks": n}
	return levelled

## The patch's level in the world (m)
func level_m() -> float:
	return ds().terrain.origin.y + (level_y + 1) * DsTerrain.CELL

## How far the patch's surface is from its level, in cells: [lowest, highest] (every column, the loose layer and all)
func flatness() -> Array:
	var g = grid()
	var pc := patch_cells()
	var lo := INF
	var hi := -INF
	for z in range(pc[1], pc[3]):
		for x in range(pc[0], pc[2]):
			var hh: float = g.column_top(x, z) + 1 + float(g.get_layer(x, z) & 255) / MM - (level_y + 1)
			lo = minf(lo, hh)
			hi = maxf(hi, hh)
	return [lo, hi]

# ---------------------------------------------------------------- machines

## The first machine of a kind ("bulldozer", "excavator", ...: DsMachine.kind), or null: never by id
func machine(kind: String) -> DsMachine:
	for m: DsMachine in ds().machines.list:
		if m.kind == kind:
			return m
	return null

func dozer() -> DsDozer:
	for m: DsMachine in ds().machines.list:
		if m is DsDozer:
			return m as DsDozer
	return null

## A machine put down at (x, z) (world), heading yaw, at rest
func park(m: DsMachine, x: float, z: float, yaw: float) -> void:
	m.yaw = yaw
	m.speed = 0.0
	m.throttle = 0.0
	m.steer = 0.0
	m.pitch = 0.0
	m.roll = 0.0
	m._vy = 0.0
	m.global_position = Vector3(x, m.ground_y(x, z), z)
	if m is DsDozer:
		# (its blade's steadying forgets where it was parked: it averages its edge's height over the last few metres
		# driven, and carried here it would hold the blade up to 0.45 m off where it's set until it had driven them)
		m._edge_avg = NAN
		m._steady = 0.0
	m._pose_now()

## Where the yard's dozer starts: on the patch's +z edge (its tracks wholly on the patch), heading -z across it
func dozer_start() -> Vector3:
	return centre() + Vector3(0.0, 0.0, PATCH * 0.5 - 2.4)

func park_dozer() -> DsDozer:
	var dz := dozer()
	var at := dozer_start()
	dz.lift = DsDozer.START_LIFT
	park(dz, at.x, at.z, 0.0)
	return dz

## You on a machine, its controls the script's (as the fleet test's)
func mount(m: DsMachine) -> void:
	var d := ds()
	if d.machines.driving:
		d.machines.get_off()
	var at = m.global_position - m.right() * (m.width * 0.5 + 0.8)
	d._put(Vector3(at.x, m.ground_y(at.x, at.z) + 0.05, at.z), 0.0, 0.0)
	d.machines._process(0.0)
	d.machines.use()
	m.auto = true

## The dozer's controls: throttle (-1 .. 1), and its blade's edge set this far over (under: -) its tracks' bottoms
func drive_dozer(dz: DsDozer, throttle: float, lift: float) -> void:
	dz.throttle = throttle
	dz.steer = 0.0
	dz.lift_cmd = 0.0
	dz.lift = clampf(lift, DsDozer.LIFT_MIN, DsDozer.LIFT_MAX)

## The highest the ground stands over the patch's level within reach m ahead of the dozer's blade (m), across its width
func heap_ahead(dz: DsDozer, reach := 3.0) -> float:
	var tr: DsTerrain = ds().terrain
	var e: Array = dz.edge_ends()
	var f := dz.forward()
	var top := -INF
	for i in 9:
		var p: Vector3 = (e[0] as Vector3).lerp(e[1], i / 8.0)
		var k := 0.0
		while k <= reach:
			top = maxf(top, tr.height_at(p.x + f.x * k, p.z + f.z * k))
			k += 0.125
	return top - level_m()

# ---------------------------------------------------------------- mass

## Everything there is, in mm over a column: the ground (blocks and the loose layer), every machine's bucket or tray
## and what's falling from it, the backpack's blocks and the spade's carry, and the clods (with what they owe the ground).
func mass() -> Dictionary:
	var d := ds()
	var ground: int = d.terrain.grid.ground_mm()
	var loads := 0
	var falling := 0            # (nothing's "falling" any more: what a bucket pours is clods, stage 6)
	for m: DsMachine in d.machines.list:
		var l = m.get("load_n")
		if l != null:
			loads += int(l)
	var pack := 0
	var names := {}
	for it: String in DsMats.ITEM:
		if it != "" and not names.has(it):
			names[it] = true
			pack += int(arena.inv.count(it)) * MM
	var carry := 0
	for k in d.tools._carry:
		carry += int(d.tools._carry[k])
	# (the clods, and what they owe the ground: DsDirt, stage 3 on)
	var clods := 0
	if d.dirt != null:
		clods = d.dirt.mass_mm() + d.dirt.owed_mm()
	return {"ground": ground, "loads": loads, "falling": falling, "pack": pack, "carry": carry, "clods": clods,
		"total": ground + loads + falling + pack + carry + clods}

# ---------------------------------------------------------------- timing

## A frame timer: tick() once a frame (from _process), then stats(). Whole frames, wall clock, in ms (headless with
## --fixed-fps 60 a frame takes as long as its work does: nothing waits for a display).
class FrameTimer:
	var frames := PackedFloat32Array()
	var layer := PackedFloat32Array()
	var show := PackedFloat32Array()
	var _was := 0

	func start() -> void:
		frames.clear()
		layer.clear()
		show.clear()
		_was = Time.get_ticks_usec()

	func tick(tr: DsTerrain) -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - _was) / 1000.0)
		_was = now
		layer.append(float(tr.layer_us))
		show.append(float(tr.show_us))

	static func of(a: PackedFloat32Array) -> Dictionary:
		if a.is_empty():
			return {"n": 0, "mean": 0.0, "p95": 0.0, "worst": 0.0}
		var s := a.duplicate()
		s.sort()
		var sum := 0.0
		for v in s:
			sum += v
		return {"n": s.size(), "mean": sum / s.size(), "p95": s[mini(s.size() - 1, int(s.size() * 0.95))], "worst": s[s.size() - 1]}

	func stats() -> Dictionary:
		return {"frame": of(frames), "layer": of(layer), "show": of(show)}
