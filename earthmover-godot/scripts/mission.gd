class_name Mission
extends RefCounted
## The jobs: a driveway pegged out, a pile of cracker dust beside it, and one machine to spread it with; then piping the roof water
## out to the street. Finishing one can open the next. The site is laid out from these numbers, so a new job of a kind already
## here is only a new entry in LIST.

static var save_path := "user://progress.cfg"
const COVERED_MM := 30          # a cell counts as done with this much dust on it
const PASS := 0.7               # the least of a driveway done that finishes it: one star
const STARS := [0.7, 0.8, 0.9]  # how much done for each star. The last finishes the job by itself
const LAID_MM := 60             # cracker dust on a driveway done in an earlier job
const PIPE_REACH := 2.5          # m: a pipe's end this close to the downpipe or the drain joins it
const FILLED_MM := 100          # a trench cell's filled in once it's within this of the ground it was cut from
const FILL_PASS := 0.9          # how much of the trench filled in for three stars (STARS, like a driveway)
const FALL_SLACK := 0.03         # m: a pipe may rise this much between lengths and the water still gets over it
const DRAIN_S := 6.0            # seconds the flooded lawn takes to drain once the pipe's joined
const SPREAD_MM := 50           # what spreading with the bucket leaves behind
const PLAN_COVER := 0.3          # m: the planned trench floor is at least this far under the ground
const PLAN_UNDER_WATER := 0.1    # m: and for a flood, this far under the water where it starts

const LIST := [
	{
		"id": "driveway",
		"title": "Driveway",
		"machine": Loader.DINGO,
		"rect": Rect2(-1.5, 0.0, 3.0, 8.0),
		"pile": Vector2(-4.5, 6.5),
		"pile_m3": 2.0,
		"start": Vector2(-4.5, 11.5),
		"dir": Vector2(0.0, -1.0),
		"hint": "Scoop the cracker dust, DUMP it on the driveway, then tap SPREAD and drive over the heap to flatten it",
		"done": "BOBCAT UNLOCKED",
	},
	{
		"id": "long_driveway",
		"title": "Long driveway",
		"machine": Loader.BOBCAT,
		"needs": "driveway",
		"rect": Rect2(-2.0, -12.0, 4.0, 20.0),
		"pile": Vector2(-6.5, 5.5),
		"pile_m3": 8.0,
		"start": Vector2(-6.5, 12.0),
		"dir": Vector2(0.0, -1.0),
		"hint": "Same job, bigger machine. Scoop, DUMP, then tap SPREAD and drive over the heap to flatten it",
		"done": "ROOF WATER UNLOCKED",
	},
	{
		# The rain off the roof floods the lawn: a pipe from the downpipe out to the drain in the street, then fill the trench in.
		"id": "roof_water",
		"title": "Roof water",
		"kind": "pipe",
		"machine": Loader.DINGO,
		"needs": "long_driveway",
		"rect": Rect2(-1.5, 0.0, 3.0, 8.0),
		"laid": true,
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(10.0, 5.0),
		"dir": Vector2(0.0, -1.0),
		"friend": Vector2(12.5, 5.0),
		"downpipe": Vector2(6.6, -0.05),
		# Spare dirt for filling the trench in, off to the side of it.
		"fill": Vector2(11.0, 2.5),
		"fill_m3": 1.0,
		"drain": Vector2(6.6, 8.45),
		"flood": Vector2(5.6, 2.2),
		"flood_r": Vector2(3.0, 2.3),
		"hint": "ATTACH the trencher, LOWER it and dig from the downpipe to the drain. ATTACH again to lay pipe along it. Then SPREAD along the trench to fill it",
		"done": "BACKYARD FLOOD UNLOCKED",
	},
	{
		# A low patch out the back holds the rain. Water only runs downhill: the pipe from it to the drain pit at the back fence has to
		# fall all the way, so under the rise between them the trench goes deeper.
		"id": "backyard",
		"title": "Backyard flood",
		"kind": "flood",
		"machine": Loader.DINGO,
		"needs": "roof_water",
		"rect": Rect2(-1.5, 0.0, 3.0, 8.0),
		"laid": true,
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(2.5, -12.0),
		"dir": Vector2(0.0, -1.0),
		"friend": Vector2(5.5, -12.0),
		# Most of the yard sits in a shallow dip and is under water, with a deeper hollow at one end. The rise stands out of it.
		"flood": Vector2(-2.0, -16.5),
		"flood_r": Vector2(11.0, 5.5),
		"basin_mm": 250,
		"hollow": Vector2(-6.0, -15.5),
		"hollow_r": Vector2(2.0, 1.6),
		"hollow_mm": 150,
		"water_mm": -50,
		"rise": Vector2(0.3, -18.3),
		"rise_r": 3.2,
		"rise_mm": 300,
		"drain": Vector2(7.5, -21.4),
		# Where the pipe's to start: a spot in the water on the near side of the rise, marked like the drain.
		"inlet": Vector2(-2.5, -16.0),
		"fill": Vector2(3.9, -16.0),
		"fill_m3": 1.5,
		"trampoline": Vector2(-5.5, -17.9),
		"floaters": [["table", Vector2(-3.4, -14.6)], ["chair", Vector2(-2.5, -13.8)], ["chair", Vector2(-4.4, -15.4)], ["chair", Vector2(-2.2, -15.6)], ["chair", Vector2(-4.7, -13.7)]],
		"fence_z": -22.7,
		"hint": "Trench from the ring in the water to the drain pit, going DOWN all the way. With the trencher on, tap GRADE and it does that for you. Then lay pipe and SPREAD along the trench to fill it",
		"done": "",
	},
]

static func kind(m: Dictionary) -> String:
	return m.get("kind", "driveway")

## How many stars this much of a driveway done is worth.
static func stars_for(cover: float) -> int:
	var n := 0
	for need: float in STARS:
		if cover >= need - 0.0001:
			n += 1
	return n

## Where the water comes from, and how near it a pipe's end has to be to take it.
static func source(m: Dictionary) -> Array:
	if m.has("inlet"):
		return [m["inlet"], PIPE_REACH]
	if kind(m) == "flood":
		var r: Vector2 = m["flood_r"]
		return [m["flood"], maxf(r.x, r.y) + 0.6]
	return [m["downpipe"], PIPE_REACH]

## The height of the standing water, for a flood job.
static func water_y(m: Dictionary) -> float:
	return float(m.get("water_mm", 70)) / 1000.0

## The ground shaped for a flood job: a hollow the water sits in and a rise between it and the drain.
static func _shape(sim: DirtSim, m: Dictionary) -> void:
	var c: Vector2 = m["flood"]
	var r: Vector2 = m["flood_r"]
	var hc: Vector2 = m["hollow"]
	var hr: Vector2 = m["hollow_r"]
	var rise: Vector2 = m["rise"]
	var rise_r: float = m["rise_r"]
	for j in range(1, DirtSim.CELLS - 1):
		for i in range(1, DirtSim.CELLS - 1):
			var p := Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			var n := j * DirtSim.CELLS + i
			var change := 0
			# A ragged edge, so the water's shore wanders like a real one.
			var q := (p - c) / (r * 1.35)
			var ang := q.angle()
			var d := q.length() * (1.0 + 0.1 * sin(ang * 3.0 + 0.4) + 0.07 * sin(ang * 7.0 + 1.9) + 0.04 * sin(ang * 13.0 + 0.3))
			if d < 1.0:
				change -= int(m["basin_mm"] * (1.0 - d * d) * (1.0 - d * d))
			d = ((p - hc) / (hr * 1.35)).length()
			if d < 1.0:
				change -= int(m["hollow_mm"] * (1.0 - d * d) * (1.0 - d * d))
			var e := p.distance_to(rise) / rise_r
			if e < 1.0:
				change += int(m["rise_mm"] * (0.5 + 0.5 * cos(PI * e)))
			if change != 0:
				sim.bed[n] += change
				sim.dirty[(j >> 4) * DirtSim.CHUNKS + (i >> 4)] = true
	sim.mark_start_ground()

## The pile, and for a job after the driveways, the driveway already done. Returns the dust put down.
static func lay_out(sim: DirtSim, m: Dictionary) -> int:
	var had := 0
	if kind(m) == "flood":
		_shape(sim, m)
	if m.has("fill"):
		sim.add_pile(m["fill"], m["fill_m3"], false)
	if m["pile_m3"] > 0.0:
		had += sim.add_dust_pile(m["pile"], m["pile_m3"])
	if m.get("laid", false):
		var r: Rect2 = m["rect"]
		var a := DirtSim.cell_of(r.position)
		var b := DirtSim.cell_of(r.end)
		for j in range(a.y, b.y):
			for i in range(a.x, b.x):
				sim.soil[j * DirtSim.CELLS + i] += LAID_MM
				sim.dust[j * DirtSim.CELLS + i] += LAID_MM
				sim.dirty[(j >> 4) * DirtSim.CHUNKS + (i >> 4)] = true
				had += LAID_MM
	return had

## One joined run of pipe from where the water is to the drain, in that order, or nothing.
static func pipe_run(points: PackedVector3Array, m: Dictionary) -> PackedVector3Array:
	var from: Array = source(m)
	var from_at: Vector2 = from[0]
	var from_reach: float = from[1]
	var drain: Vector2 = m["drain"]
	var first := 0
	for k in range(1, points.size() + 1):
		if k < points.size() and points[k].distance_to(points[k - 1]) <= Pipes.JOIN_WITHIN + 0.01:
			continue
		if k - first >= 2:
			var run := points.slice(first, k)
			var a := Vector2(run[0].x, run[0].z)
			var b := Vector2(run[run.size() - 1].x, run[run.size() - 1].z)
			if b.distance_to(from_at) <= from_reach and a.distance_to(drain) <= PIPE_REACH:
				run.reverse()
				a = Vector2(run[0].x, run[0].z)
				b = Vector2(run[run.size() - 1].x, run[run.size() - 1].z)
			if a.distance_to(from_at) <= from_reach and b.distance_to(drain) <= PIPE_REACH:
				return run
		first = k
	return PackedVector3Array()

## Whether any run of pipe has an end at where the water comes from, and whether any has one at the drain.
static func ends_reached(points: PackedVector3Array, m: Dictionary) -> Array:
	var from: Array = source(m)
	var from_at: Vector2 = from[0]
	var drain: Vector2 = m["drain"]
	var at_source := false
	var at_drain := false
	var first := 0
	for k in range(1, points.size() + 1):
		if k < points.size() and points[k].distance_to(points[k - 1]) <= Pipes.JOIN_WITHIN + 0.01:
			continue
		if k - first >= 2:
			for e: Vector3 in [points[first], points[k - 1]]:
				var p := Vector2(e.x, e.z)
				at_source = at_source or p.distance_to(from_at) <= float(from[1])
				at_drain = at_drain or p.distance_to(drain) <= PIPE_REACH
		first = k
	return [at_source, at_drain]

static func joined(points: PackedVector3Array, m: Dictionary) -> bool:
	return not pipe_run(points, m).is_empty()

## Where along the run the water stops, as an index into it, or -1 if it gets all the way. A downpipe's water runs down any
## pipe; a flood's only goes in below its surface and only runs downhill.
static func water_stops_at(run: PackedVector3Array, m: Dictionary) -> int:
	if kind(m) != "flood" or run.is_empty():
		return -1
	# The water goes in at the last of the pipe inside the start's ring, and is at the drain at the first inside the drain's:
	# what the pipe does outside that stretch doesn't matter.
	var from: Array = source(m)
	var drain: Vector2 = m["drain"]
	var first := 0
	for k in run.size():
		if Vector2(run[k].x, run[k].z).distance_to(from[0]) <= float(from[1]):
			first = k
	var last := run.size() - 1
	for k in range(first, run.size()):
		if Vector2(run[k].x, run[k].z).distance_to(drain) <= PIPE_REACH:
			last = k
			break
	if run[first].y > water_y(m):
		return first
	for k in range(first + 1, last + 1):
		if run[k].y > run[k - 1].y + FALL_SLACK:
			return k
	return -1

## How much of every trench cut on the site is filled back in, 0 to 1. Nothing cut, nothing filled.
static func filled_in(sim: DirtSim, m: Dictionary) -> float:
	if sim.start_ground.size() != sim.bed.size():
		return 0.0
	var r := site(m)
	var a := DirtSim.cell_of(r.position)
	var b := DirtSim.cell_of(r.end)
	var cut := 0
	var full := 0
	for j in range(maxi(a.y, 1), mini(b.y, DirtSim.CELLS - 1)):
		for i in range(maxi(a.x, 1), mini(b.x, DirtSim.CELLS - 1)):
			var n := j * DirtSim.CELLS + i
			if sim.clean_cut[n] == 0:
				continue
			cut += 1
			if sim.bed[n] + sim.soil[n] >= sim.start_ground[n] - FILLED_MM:
				full += 1
	return float(full) / cut if cut > 0 else 0.0

static func find(id: String) -> Dictionary:
	for m: Dictionary in LIST:
		if m["id"] == id:
			return m
	return {}

## The job after this one, or nothing.
static func after(m: Dictionary) -> Dictionary:
	for other: Dictionary in LIST:
		if other.get("needs", "") == m["id"]:
			return other
	return {}

static func house_front(m: Dictionary) -> float:
	return (m["rect"] as Rect2).position.y - 0.5

static func road(_m: Dictionary) -> Rect2:
	return Rect2(-80.0, 9.0, 160.0, 6.0)

## The ground kept flat for the job: the house, the driveway, the pile and the street out front, and a flood job's backyard.
static func site(m: Dictionary) -> Rect2:
	# A flood job has the backyard as well.
	var top := house_front(m) - (23.5 if kind(m) == "flood" else 11.0)
	return Rect2(-14.0, top, 28.0, 16.0 - top)

## How much of the driveway has enough dust on it, 0 to 1.
static func coverage(sim: DirtSim, m: Dictionary) -> float:
	var r: Rect2 = m["rect"]
	var a := DirtSim.cell_of(r.position)
	var b := DirtSim.cell_of(r.end)
	var done := 0
	var all := 0
	for j in range(a.y, b.y):
		for i in range(a.x, b.x):
			all += 1
			if sim.dust[j * DirtSim.CELLS + i] >= COVERED_MM:
				done += 1
	return float(done) / maxi(all, 1)

static func is_done(id: String) -> bool:
	var f := ConfigFile.new()
	if f.load(save_path) != OK:
		return false
	return f.get_value("done", id, false)

## Done, with this many stars: the best kept.
## Skipped, it's done with none: that opens what comes after, and playing it properly later still earns them.
static func mark_done(id: String, stars_now := 3) -> void:
	var f := ConfigFile.new()
	f.load(save_path)
	f.set_value("done", id, true)
	f.set_value("stars", id, maxi(int(f.get_value("stars", id, 0)), stars_now))
	f.save(save_path)

## The most stars this job's had. One done before there were stars was done to the old 90%, which is three.
static func stars(id: String) -> int:
	var f := ConfigFile.new()
	if f.load(save_path) != OK or not f.get_value("done", id, false):
		return 0
	return int(f.get_value("stars", id, 3))

static func open(m: Dictionary) -> bool:
	return not m.has("needs") or is_done(m["needs"])

## The trench floor this job wants: a straight line from where the water comes from to the drain, falling Loader.GRADE_FALL each
## metre, low enough to be at least PLAN_COVER under the ground everywhere along it (so under the rise too), and for a flood
## under the water where it starts. Worked out once from the ground as it was, so it doesn't move about with the digging.
## {from, way, length, y0}: the floor's y at `from`, in m.
static func trench_plan(sim: DirtSim, m: Dictionary) -> Dictionary:
	var from: Vector2 = source(m)[0]
	var to: Vector2 = m["drain"]
	var length := from.distance_to(to)
	var way := (to - from) / length
	var y0 := INF
	var d := 0.0
	while d <= length + 0.001:
		var at := DirtSim.cell_of(from + way * d)
		var ground := float(sim.start_ground[at.y * DirtSim.CELLS + at.x]) / 1000.0
		y0 = minf(y0, ground - PLAN_COVER + Loader.GRADE_FALL * d)
		d += 0.25
	if kind(m) == "flood":
		y0 = minf(y0, water_y(m) - PLAN_UNDER_WATER)
	return {"from": from, "way": way, "length": length, "y0": y0}
