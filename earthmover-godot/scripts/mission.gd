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
const FILL_PASS := 0.9          # how much of the trench has to be filled in
const FALL_SLACK := 0.03         # m: a pipe may rise this much between lengths and the water still gets over it
const DRAIN_S := 6.0            # seconds the flooded lawn takes to drain once the pipe's joined
const SPREAD_MM := 50           # what spreading with the bucket leaves behind

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
		"drain": Vector2(6.6, 8.45),
		"flood": Vector2(5.6, 2.2),
		"flood_r": Vector2(3.0, 2.3),
		"hint": "ATTACH the trencher, LOWER it and dig from the downpipe to the drain. ATTACH again to lay pipe along it. Then SPREAD to fill it in",
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
		"flood": Vector2(-6.0, -15.5),
		"flood_r": Vector2(2.6, 2.0),
		"hollow_mm": 250,
		"water_mm": -80,
		"rise": Vector2(0.3, -18.3),
		"rise_r": 3.2,
		"rise_mm": 300,
		"drain": Vector2(6.5, -21.2),
		"fence_z": -22.7,
		"hint": "Trench from the flood to the drain pit, going DOWN all the way: LOWER the trencher further under the rise. Then lay pipe and fill it in",
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
	var rise: Vector2 = m["rise"]
	var rise_r: float = m["rise_r"]
	for j in range(1, DirtSim.CELLS - 1):
		for i in range(1, DirtSim.CELLS - 1):
			var p := Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			var n := j * DirtSim.CELLS + i
			var change := 0
			var d := ((p - c) / (r * 1.35)).length()
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

static func joined(points: PackedVector3Array, m: Dictionary) -> bool:
	return not pipe_run(points, m).is_empty()

## Where along the run the water stops, as an index into it, or -1 if it gets all the way. A downpipe's water runs down any
## pipe; a flood's only goes in below its surface and only runs downhill.
static func water_stops_at(run: PackedVector3Array, m: Dictionary) -> int:
	if kind(m) != "flood" or run.is_empty():
		return -1
	if run[0].y > water_y(m):
		return 0
	for k in range(1, run.size()):
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
