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
const HAND_TOL := 0.035          # m: a garden patch is done where it's this near level, above or below
const HAND_RIM := 0.15          # m in from the garden pegs before a cell counts
const DAM_TOL := 0.15            # m: a dam floor's done where it's no more than this above the floor
const DAM_DEEPER_OK := 10.0      # m: and dug deeper counts too: a deeper dam just holds more water, and it's not meant to be fiddly
const DAM_EDGE := 1.5            # m in from the pegs that counts as floor: the sides slope
## The farm road: boxed out `road_drop` under the ground as it was, following it over the rises. Forgiving, like the dam: a cell's
## done from 5 cm too high to 15 cm too deep, and the half metre by each line of pegs doesn't count.
const ROAD_TOL_UP := 0.05
const ROAD_TOL_DOWN := 0.15
const ROAD_EDGE := 0.5
const ROAD_STEP := 2.0           # m between the points down the middle of the road, and so between pegs on each side
## Bike jumps: tabletops built up on the paddock. Forgiving: a cell's right within 20 cm either way of the shape, the 40 cm by each
## line of pegs doesn't count, and nor does the flat between the jumps (it's tinted, so dirt left on the run-up shows).
const JUMP_TOL := 0.2
const JUMP_EDGE := 0.4
const JUMP_COUNTS_MM := 300     # a cell counts only where the jump's at least this high: lower, untouched ground would already be near enough
const HEAP_SLOPE := 0.62        # the heaps beside the track stand at this rise over run: about 32 degrees, so they don't slump
const HEAP_SPARE := 1.35        # the heaps hold this much more than the jumps take
const HEAP_GAP := 1.2           # m between the pegs and the foot of the heaps

## The water lying under a dam, hidden till it's dug down to: it shows just where the floor's deep enough to count.
static func dam_water_y(p: Pad) -> float:
	return p.level + DAM_TOL

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
		"hint": "ATTACH the trencher and drive from the downpipe to the drain: GRADE comes on and sets the depth. ATTACH again for pipe: it follows the trench. Then SPREAD along the trench to fill it",
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
		"hint": "Trench from the ring in the water to the drain pit, going DOWN all the way. GRADE comes on with the trencher and does that for you. Then lay pipe (it follows the trench) and SPREAD along the trench to fill it",
		"done": "STREET DRAIN UNLOCKED",
	},
	{
		# The owner's (9 Nov): the Bobcat's big trencher and 40 cm pipe. A new stormwater line along the street edge in front of the
		# house, about 40 m from a new pit with water lying round it in the gutter to a big drain at the other end. It has to fall
		# all the way, like the backyard, which over that far takes it down to about 1.5 m at the drain. The street's set further
		# out than in the other jobs, so there's room for the trench between it and the driveway.
		"id": "street_drain",
		"title": "Street drain",
		"kind": "street",
		"machine": Loader.BOBCAT,
		"needs": "backyard",
		"rect": Rect2(-1.5, 0.0, 3.0, 8.0),
		"laid": true,
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(-22.0, 9.0),
		"dir": Vector2(1.0, 0.0),
		"friend": Vector2(-22.0, 6.0),
		"inlet": Vector2(-20.0, 9.0),
		"drain": Vector2(20.0, 9.0),
		# The water lying round the new pit, from the gutter up onto the verge: the house side stays clear of what the trencher throws
		# out, so it can still be seen going once the pipe's in.
		"flood": Vector2(-20.3, 9.0),
		"flood_r": Vector2(3.4, 1.7),
		"road_z": 10.5,
		# The big pipe's 40 cm across: the trench starts deeper so it's buried from the pit on, and falls a little less, 2 cm a metre
		# (the Dingo's jobs fall 3), so it's about 1.4 m down at the big drain.
		"cover": 0.6,
		"fall": 0.02,
		"fill": Vector2(6.5, 6.0),
		"fill_m3": 2.0,
		"hint": "ATTACH the big trencher and drive from the pit to the big drain: GRADE comes on and keeps it going DOWN. ATTACH again for pipe: it follows the trench. Then SPREAD along the trench to fill it",
		"done": "GARDEN PATCH UNLOCKED",
	},
	{
		# By hand: a sunken patch of lawn by the driveway, filled level with the garden soil heaped by the fence. No machine, just a
		# shovel, a barrow and a rake.
		"id": "garden",
		"title": "Garden patch",
		"kind": "hand",
		"machine": "On foot",
		"needs": "street_drain",
		"rect": Rect2(-1.5, 0.0, 3.0, 8.0),
		"laid": true,
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(11.5, 3.0),
		"dir": Vector2(-1.0, 0.0),
		"friend": Vector2(11.5, 5.0),
		"patch": Vector2(5.0, 4.0),
		"patch_r": 1.1,
		"patch_mm": 100,
		"fill": Vector2(10.0, 6.8),
		"fill_m3": 0.45,
		"barrow": Vector2(8.6, 5.6),
		"barrow_dir": Vector2(-1.0, 0.0),
		"barrow2": Vector2(8.6, 7.6),
		"hint": "Grab the SHOVEL and fill the barrow from the dirt pile. GET IN the barrow, push it to the pegs, TIP it, then RAKE it level",
		"done": "FARM DAM UNLOCKED",
	},
	{
		# The big machines, out on a paddock: a farm dam dug out to its floor inside the pegs. The dirt can go anywhere outside it.
		"id": "farm_dam",
		"title": "Farm dam",
		"kind": "dam",
		"site": "big",
		"machine": "Big dozer",
		"needs": "garden",
		"rect": Rect2(),
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(-24.0, -6.0),
		"dir": Vector2(1.0, 0.0),
		"digger": Vector2(0.0, 8.0),
		"digger_dir": Vector2(0.0, -1.0),
		"dam": Rect2(-12.0, -13.0, 24.0, 14.0),
		"dam_deep": 1.0,
		"hint": "Dig the dam out inside the pegs until you hit water: that's deep enough. Red's still to come out. The dozer's CUT stops at the floor",
		"done": "BURIED FIND UNLOCKED",
	},
	{
		# Back on the paddock: something's buried inside the pegs, and what's a surprise each time (Find). A beep speeds up as the
		# bucket nears it; dig it out and uncover it, gently, as a hard knock marks it and costs a little.
		"id": "buried_find",
		"title": "Buried find",
		"kind": "find",
		"site": "big",
		"machine": "Big excavator",
		"needs": "farm_dam",
		"rect": Rect2(),
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(-24.0, -5.0),
		"dir": Vector2(1.0, 0.0),
		"digger": Vector2(0.0, 8.0),
		"digger_dir": Vector2(0.0, -1.0),
		"patch": Rect2(-11.0, -12.0, 22.0, 14.0),
		"hint": "Something's buried inside the pegs. The beep speeds up as the bucket gets near it. Then go gently: a hard knock marks it",
		"done": "FARM ROAD UNLOCKED",
	},
	{
		# The paddock once more: a farm road pegged out from the gate to the shed, curving over the rises, to be boxed out 10 cm
		# deep following the ground. When it's done, the farmer drives it in the ute.
		"id": "farm_road",
		"title": "Farm road",
		"kind": "road",
		"site": "big",
		"machine": "Big dozer",
		"needs": "buried_find",
		"rect": Rect2(),
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"start": Vector2(-37.0, 14.0),
		"dir": Vector2(1.0, 0.0),
		"digger": Vector2(-10.0, -10.0),
		"digger_dir": Vector2(0.64, 0.77),
		"ute": Vector2(-33.0, 23.0),
		"ute_dir": Vector2(1.0, 0.0),
		"track": [Vector2(-30.0, 14.0), Vector2(-18.0, 15.0), Vector2(-6.0, 7.0), Vector2(6.0, -3.0), Vector2(18.0, -10.0), Vector2(31.0, -11.0)],
		"road_half": 4.0,
		"road_drop": 0.1,
		"shed": Vector2(38.5, -11.0),
		"tank": Vector2(36.0, -21.0),
		"hint": "Box out the road 10 cm deep. Tap CUT and drive along it: on the road it stops at 10 cm. Push the dirt off the sides. Red's still to come off, green's done, blue's too deep",
		"done": "BIKE JUMPS UNLOCKED",
	},
	{
		# The owner's (9-10 Nov): a dirt bike track on the paddock, built with the normal dozer and excavator from heaps beside it,
		# then ridden. Three tabletops in a row, getting bigger: a face up, a flat top to land short on, and a landing down. Each is
		# [where its face starts along the track, its height, face, top and landing lengths], in m.
		"id": "bike_jumps",
		"title": "Bike jumps",
		"kind": "jumps",
		"site": "big",
		"normal_size": true,
		"machine": "Dozer",
		"needs": "farm_road",
		"rect": Rect2(),
		"pile": Vector2.ZERO,
		"pile_m3": 0.0,
		"line_from": Vector2(-40.0, -6.0),
		"line_dir": Vector2(1.0, 0.0),
		"jumps": [[14.0, 1.0, 2.0, 2.0, 2.5], [31.5, 1.5, 3.0, 2.5, 3.5], [53.5, 2.0, 4.0, 2.5, 4.5]],
		"jump_half": 2.0,
		"start": Vector2(-23.0, 8.5),
		"dir": Vector2(0.0, -1.0),
		"digger": Vector2(30.0, 4.0),
		"digger_dir": Vector2(-1.0, 0.0),
		"ute": Vector2(-38.0, 8.0),
		"ute_dir": Vector2(1.0, 0.0),
		"bike": Vector2(-38.5, -6.0),
		"bike_dir": Vector2(1.0, 0.0),
		"shed": Vector2(33.0, 18.0),
		"tank": Vector2(24.0, 21.0),
		"hint": "Push the dirt from the heaps onto the pegged jumps. Blue needs more, red's too high, green's right. Tap CUT and drive along a jump: it shapes it to the pegs. Then Get out, walk to the bike at the start of the track and ride them",
		"done": "",
	},
]

static func kind(m: Dictionary) -> String:
	return m.get("kind", "driveway")

## A job that's a trench and a pipe from where the water is to a drain.
static func is_pipe_job(m: Dictionary) -> bool:
	return kind(m) in ["pipe", "flood", "street"]

## A pipe job whose water only runs downhill, so the pipe has to fall all the way.
static func downhill(m: Dictionary) -> bool:
	return kind(m) in ["flood", "street"]

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
	elif kind(m) == "hand":
		_sink_patch(sim, m)
	elif kind(m) == "jumps":
		lay_heaps(sim, m)
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
	if not downhill(m) or run.is_empty():
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

static func road(m: Dictionary) -> Rect2:
	if kind(m) in ["dam", "find", "road", "jumps"]:
		return Rect2()
	return Rect2(-80.0, float(m.get("road_z", 9.0)), 160.0, 6.0)

## The ground kept flat for the job: the house, the driveway, the pile and the street out front, and a flood job's backyard.
## The street drain's is wider, for its 40 m along the street.
static func site(m: Dictionary) -> Rect2:
	if kind(m) == "street":
		var front := house_front(m) - 11.0
		return Rect2(-25.0, front, 50.0, road(m).end.y + 2.0 - front)
	if kind(m) == "dam":
		return (m["dam"] as Rect2).grow(7.0)
	if kind(m) == "find":
		return (m["patch"] as Rect2).grow(7.0)
	if kind(m) == "road":
		# Nothing's flattened: the road's to follow the paddock's rises.
		return Rect2()
	if kind(m) == "jumps":
		# Flat for the whole track and the heaps beside it.
		var from: Vector2 = m["line_from"]
		return Rect2(-44.0, from.y - 5.0, 88.0, 21.0)
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

## Open once the job before it's done; and one done already stays open, even if a job's been put in before it since.
static func open(m: Dictionary) -> bool:
	return not m.has("needs") or is_done(m["needs"]) or is_done(m["id"])

## The trench floor this job wants: a straight line from where the water comes from to the drain, falling Loader.GRADE_FALL each
## metre (or the job's own "fall"), low enough to be at least PLAN_COVER (or its own "cover") under the ground everywhere along it
## (so under the rise too), and for a flood under the water where it starts. Worked out once from the ground as it was, so it
## doesn't move about with the digging. {from, way, length, y0, fall}: the floor's y at `from`, in m, and its fall per m.
static func trench_plan(sim: DirtSim, m: Dictionary) -> Dictionary:
	var from: Vector2 = source(m)[0]
	var to: Vector2 = m["drain"]
	var length := from.distance_to(to)
	var way := (to - from) / length
	var cover: float = m.get("cover", PLAN_COVER)
	var fall: float = m.get("fall", Loader.GRADE_FALL)
	var y0 := INF
	var d := 0.0
	while d <= length + 0.001:
		var at := DirtSim.cell_of(from + way * d)
		var ground := float(sim.start_ground[at.y * DirtSim.CELLS + at.x]) / 1000.0
		y0 = minf(y0, ground - cover + fall * d)
		d += 0.25
	if kind(m) == "flood":
		y0 = minf(y0, water_y(m) - PLAN_UNDER_WATER)
	return {"from": from, "way": way, "length": length, "y0": y0, "fall": fall}

## The garden patch: a dip in the lawn, flat across the bottom and rising to the lawn at its edge.
static func _sink_patch(sim: DirtSim, m: Dictionary) -> void:
	var c: Vector2 = m["patch"]
	var r: float = m["patch_r"]
	var at := DirtSim.cell_of(c)
	var reach := int(ceil(r / DirtSim.CELL_M)) + 1
	for j in range(at.y - reach, at.y + reach + 1):
		for i in range(at.x - reach, at.x + reach + 1):
			var p := Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			var d := p.distance_to(c) / r
			if d >= 1.0:
				continue
			sim.bed[j * DirtSim.CELLS + i] -= int(m["patch_mm"] * (1.0 - pow(d, 4.0)))
			sim.dirty[(j >> 4) * DirtSim.CHUNKS + (i >> 4)] = true
	sim.mark_start_ground()

## Whether the job's done by bringing a pegged-out patch to one height, scored by its Pad.
static func is_pad_job(m: Dictionary) -> bool:
	return kind(m) in ["hand", "dam", "road", "jumps"]

## The middle of the farm road, a point every ROAD_STEP m: a smooth curve through the job's points.
static func track(m: Dictionary) -> PackedVector2Array:
	var ctrl: Array = m["track"]
	var out := PackedVector2Array()
	for k in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(k - 1, 0)]
		var p1: Vector2 = ctrl[k]
		var p2: Vector2 = ctrl[k + 1]
		var p3: Vector2 = ctrl[mini(k + 2, ctrl.size() - 1)]
		# Catmull-Rom between p1 and p2, finely, then taken every ROAD_STEP m along it.
		var steps := 40
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			if out.is_empty() or q.distance_to(out[out.size() - 1]) >= ROAD_STEP:
				out.append(q)
	var last: Vector2 = ctrl[ctrl.size() - 1]
	if out[out.size() - 1].distance_to(last) < ROAD_STEP * 0.5:
		out[out.size() - 1] = last
	else:
		out.append(last)
	return out

## How far a spot is from the middle of the road, in m.
static func off_track(points: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for k in points.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[k], points[k + 1])))
	return best

## The patch of ground the job's to bring to height, pegged out.
static func pad_for(sim: DirtSim, m: Dictionary) -> Pad:
	if kind(m) == "hand":
		var c: Vector2 = m["patch"]
		var r: float = m["patch_r"]
		# Only the dip counts, not its rim: the rim starts near enough level already, so the job began at 26% (review, 10 Nov).
		var p := Pad.new(Pad.ring(c, Vector2(r, r), 14), sim.height_at(c + Vector2(r + 1.0, 0.0)), HAND_TOL, HAND_TOL, HAND_RIM)
		p.title = String(m["title"]).to_upper()
		return p
	if kind(m) == "dam":
		var r: Rect2 = m["dam"]
		var level := sim.height_at(r.get_center()) - float(m["dam_deep"])
		var p := Pad.new(Pad.box(r), level, DAM_TOL, DAM_DEEPER_OK, DAM_EDGE)
		p.title = String(m["title"]).to_upper()
		return p
	if kind(m) == "road":
		var p := Pad.along(track(m), float(m["road_half"]), ROAD_EDGE, ROAD_TOL_UP, ROAD_TOL_DOWN)
		p.drop = float(m["road_drop"])
		p.title = String(m["title"]).to_upper()
		return p
	if kind(m) == "jumps":
		return _jumps_pad(m)
	return null

## ---------------------------------------------------------------- bike jumps

## How high a tabletop wants to be `u` m along from the foot of its face: up the face, along the top, down the landing.
static func tabletop(j: Array, u: float) -> float:
	var h: float = j[1]
	var face: float = j[2]
	var top: float = j[3]
	var land: float = j[4]
	if u <= 0.0 or u >= face + top + land:
		return 0.0
	if u < face:
		return h * u / face
	if u <= face + top:
		return h
	return h * (1.0 - (u - face - top) / land)

## How far along the track a spot is, in m from its start.
static func along_line(m: Dictionary, p: Vector2) -> float:
	return (p - (m["line_from"] as Vector2)).dot(m["line_dir"])

## How high the jumps want the ground built up at a spot, in m: nothing between jumps. Across the track it's the same all the way to
## the pegs.
static func jump_raise(m: Dictionary, p: Vector2) -> float:
	var u := along_line(m, p)
	var best := 0.0
	for j: Array in m["jumps"]:
		best = maxf(best, tabletop(j, u - float(j[0])))
	return best

## Where along the track a jump starts and ends, in m.
static func jump_span(j: Array) -> Vector2:
	return Vector2(float(j[0]), float(j[0]) + float(j[2]) + float(j[3]) + float(j[4]))

## Where a jump's lip is: the top of its face, along the track in m.
static func jump_lip(j: Array) -> float:
	return float(j[0]) + float(j[2])

## The middle of the track, a point every ROAD_STEP m from just before the first jump to just past the last, and at every bend in
## the jumps' shape too, so the string along the pegs follows it.
static func jump_line(m: Dictionary) -> PackedVector2Array:
	var from: Vector2 = m["line_from"]
	var dir: Vector2 = m["line_dir"]
	var jumps: Array = m["jumps"]
	var first := jump_span(jumps[0]).x - 1.0
	var last := jump_span(jumps[jumps.size() - 1]).y + 1.0
	var at: Array[float] = []
	var u := first
	while u < last:
		at.append(u)
		u += ROAD_STEP
	at.append(last)
	for j: Array in jumps:
		var u0 := float(j[0])
		for b: float in [u0, u0 + float(j[2]), u0 + float(j[2]) + float(j[3]), jump_span(j).y]:
			at.append(b)
	at.sort()
	var out := PackedVector2Array()
	var prev := -INF
	for a in at:
		if a - prev >= 0.4:
			out.append(from + dir * a)
			prev = a
	return out

## The jumps, pegged down both sides as one strip: the shape's built up on the ground as it began. Only the jumps count.
static func _jumps_pad(m: Dictionary) -> Pad:
	var p := Pad.along(jump_line(m), float(m["jump_half"]), JUMP_EDGE, JUMP_TOL, JUMP_TOL)
	p.title = String(m["title"]).to_upper()
	for n in p.shown:
		p.raise_mm[n] = int(jump_raise(m, _cell_spot(n)) * 1000.0)
	var counting := PackedInt32Array()
	for n in p.cells:
		if int(p.raise_mm[n]) >= JUMP_COUNTS_MM:
			counting.append(n)
	p.cells = counting
	return p

static func _cell_spot(n: int) -> Vector2:
	return Vector2(n % DirtSim.CELLS, n / DirtSim.CELLS) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M

## The jumps as if they'd been built, in loose dirt, `extra` m higher than wanted: the shape across the pegs, and past them sloping
## down as loose dirt stands. For checks and demos.
static func build_jumps(sim: DirtSim, m: Dictionary, extra := 0.0) -> void:
	if sim.start_ground.size() != sim.bed.size():
		sim.mark_start_ground()
	var from: Vector2 = m["line_from"]
	var dir: Vector2 = m["line_dir"]
	var side := Vector2(-dir.y, dir.x)
	var half: float = m["jump_half"]
	for n in sim.bed.size():
		var p := _cell_spot(n)
		var across := absf((p - from).dot(side))
		if across > half + 6.0:
			continue
		var up := jump_raise(m, p)
		if up <= 0.0:
			continue
		up += extra
		up -= maxf(across - half, 0.0) * HEAP_SLOPE
		if up <= 0.0:
			continue
		sim.soil[n] = maxi(sim.start_ground[n] + int(up * 1000.0) - sim.bed[n], 0)
		sim.wake(n % DirtSim.CELLS, n / DirtSim.CELLS)
		sim.dirty[((n / DirtSim.CELLS) >> 4) * DirtSim.CHUNKS + ((n % DirtSim.CELLS) >> 4)] = true

## How much dirt a jump takes, m3: its shape across the pegs, and what slumps off each side of it at the angle loose soil stands.
static func jump_m3(m: Dictionary, j: Array) -> float:
	var span := jump_span(j)
	var wide := 2.0 * float(m["jump_half"])
	var total := 0.0
	var step := 0.05
	var u := span.x
	while u < span.y:
		var h := tabletop(j, u - span.x + step * 0.5)
		total += (wide * h + h * h / 0.675) * step
		u += step
	return total

## The heaps beside the track: one by each jump, as long as it, holding what it takes and some to spare. Each is a long ridge as
## steep as HEAP_SLOPE with rounded ends, set just clear of the pegs. Returns the dirt put down, in mm over cells as DirtSim counts.
static func lay_heaps(sim: DirtSim, m: Dictionary) -> int:
	var put := 0
	var heaps := heap_lines(m)
	for jn in range(1, DirtSim.CELLS - 1):
		for i in range(1, DirtSim.CELLS - 1):
			var p := Vector2(i, jn) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			var mm := 0
			for h: Array in heaps:
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, h[0], h[1]))
				mm = maxi(mm, int((float(h[2]) - d * HEAP_SLOPE) * 1000.0))
			if mm > 0:
				sim.put(i, jn, mm)
				# Drawn from the start: as steep as they are, they don't slump, which is what would otherwise get them redrawn.
				sim.dirty[(jn >> 4) * DirtSim.CHUNKS + (i >> 4)] = true
				put += mm
	return put

## Each heap's ridge line, ends and height: [a, b, high].
static func heap_lines(m: Dictionary) -> Array:
	var from: Vector2 = m["line_from"]
	var dir: Vector2 = m["line_dir"]
	var side := Vector2(-dir.y, dir.x)
	var out: Array = []
	for j: Array in m["jumps"]:
		var span := jump_span(j)
		var length := span.y - span.x + 2.0
		var need := jump_m3(m, j) * HEAP_SPARE
		# A ridge of length L, H high, with cone ends, holds L * H^2 / s + (pi / 3) * H^3 / s^2. Worked out for H a few times over.
		var high := 1.0
		for k in 30:
			var held := length * high * high / HEAP_SLOPE + PI / 3.0 * pow(high, 3.0) / (HEAP_SLOPE * HEAP_SLOPE)
			high *= pow(need / held, 1.0 / 3.0)
		var off := float(m["jump_half"]) + HEAP_GAP + high / HEAP_SLOPE
		out.append([from + dir * (span.x - 1.0) + side * off, from + dir * (span.y + 1.0) + side * off, high])
	return out

## Who's on the job, for the menu: one machine each, or what's on site to share.
static func crew(m: Dictionary) -> String:
	match kind(m):
		"hand":
			return "both on foot"
		"dam":
			return "big dozer and big excavator"
		"find":
			return "big excavator and big dozer"
		"road":
			return "big dozer and big excavator"
		"jumps":
			return "dozer, excavator and dirt bike"
	return "two %ss" % m["machine"]
