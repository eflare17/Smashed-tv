class_name Mission
extends RefCounted
## The jobs: a driveway pegged out, a pile of cracker dust beside it, and one machine to spread it with. Finishing one can open the
## next. The site is laid out from these numbers, so a new driveway job is only a new entry in LIST.

static var save_path := "user://progress.cfg"
const COVERED_MM := 30          # a cell counts as done with this much dust on it
const PASS := 0.9               # how much of the driveway has to be done
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
		"done": "",
	},
]

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

## The ground kept flat for the job: the house, the driveway, the pile and the street out front.
static func site(m: Dictionary) -> Rect2:
	var top := house_front(m) - 11.0
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

static func mark_done(id: String) -> void:
	var f := ConfigFile.new()
	f.load(save_path)
	f.set_value("done", id, true)
	f.save(save_path)

static func open(m: Dictionary) -> bool:
	return not m.has("needs") or is_done(m["needs"])
