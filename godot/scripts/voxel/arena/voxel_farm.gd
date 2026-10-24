class_name VoxelFarm
extends Node3D
## Farming in the yard (the owner, 21 Oct, Stage 5: "bring the weed growing mechanics across; hoe dirt into rows, plant
## seeds, watering can; rebuild the fertilising system from scratch; worm farms (use worms found digging)").
##
## The weed growing is the HTML game's (b332, FARM.md, its STRAIN and WEED tables, the same numbers): six strains,
## Northern Lights and Sour Diesel seeds bought at the seed crate ($10, $30: cash from kills, a grunt $1, a batter
## $3, a brute $5), a plant grows in real time (NL 4 minutes, SD 6, ... White Widow 15) and every wave cleared jumps it
## ahead (NL 2 waves ... WW 6); watered it grows at full speed for 3 minutes, dry at half and it droops, dry for 2
## minutes it wilts and loses a bud; stages: seedling, young, fan leaves, ready with buds; E harvests the buds, sold at
## the buyer's crate (a plant's price for all its buds). What's new here: plants go in rows the hoe turns in the dug
## ground (on a grid three quarters of a metre apart), the watering can (filled at the water tank) is poured at them, and fertiliser is
## from scratch: worm castings from the worm farm (worms from digging, fed meat, brain or charred scraps), a plant fed
## once grows 35% faster and gives a bud more, twice 70% and two more.
##
## Co-op: the farm is the host's (like the chests): a guest's planting, watering, fertilising, harvesting and worm-farm
## feeding go to the host as requests, the host answers with what they got (buds, castings, a seed back), and the
## plants' state goes to the guest every couple of seconds and on every change. Seeds, buds, cash and the can are
## each player's own. Saved with the rest (the host's farm; a guest's own kept while away). Owned by the voxel session.

const STRAINS := [
	{"name": "Northern Lights", "short": "NL", "price": 40, "mins": 4.0, "waves": 2, "buds": 3, "seed": 10},
	{"name": "Sour Diesel", "short": "SD", "price": 75, "mins": 6.0, "waves": 3, "buds": 3, "seed": 30},
	{"name": "Granddaddy Purple", "short": "GDP", "price": 80, "mins": 6.0, "waves": 3, "buds": 4, "seed": 0},
	{"name": "Blue Dream", "short": "BD", "price": 140, "mins": 9.0, "waves": 4, "buds": 3, "seed": 0},
	{"name": "Acapulco Gold", "short": "AG", "price": 150, "mins": 10.0, "waves": 4, "buds": 2, "seed": 0},
	{"name": "White Widow", "short": "WW", "price": 300, "mins": 15.0, "waves": 6, "buds": 2, "seed": 0},
]
const WET_FOR := 180.0          # seconds a watering lasts ...
const WILT_AFTER := 120.0       # ... then seconds dry before it wilts
const DRY_SPEED := 0.5
const CAN := 8.0                # a full can waters eight plants
const SPOT := 0.75              # metres between plants (the planting grid: 6 blocks)
const FED_SPEED := 0.35         # a feed of castings: this much faster ...
const FED_MAX := 2              # ... at most twice a crop, a bud more each time
const KILL_CASH := {"grunt": 1, "swarmer": 1, "brute": 5, "batter": 3, "charger": 2, "thrower": 2, "shielder": 6, "boss": 40}
## The worm farm: worms eat scraps (cubes a second each), a casting for every CAST_EVERY cubes eaten; fed, they breed.
const WORM_EAT := 2.0
const CAST_EVERY := 300.0
const WORM_MAX := 60
const WORM_BREED := 0.004       # new worms a second per worm while there's food
const SCRAP := {"meat": 1.0, "brain": 1.0, "charred": 0.5, "poo": 1.5, "blood_bone": VoxelShredder.BAG_SCRAPS}   # what one of each is worth to them (burnt: less; manure: more; a bag of blood and bone: lots)
## Chicken poo (Stage 6) feeds a plant too, weaker than castings: this many of its cubes a feed.
const POO_FEED := 20
const FEED_MOST := 3000         # scraps put in at a time
const SYNC_T := 2.0
## The arena sends its enemies one at a time (each one a "wave" there); the HTML game's waves are crowds, so here a
## crop's wave jump comes every WAVE_ENEMIES of the arena's.
const WAVE_ENEMIES := 8
## Where the props stand in the yard.
const CRATE := Vector3(19.4, 0, 23.75)
const BUYER := Vector3(8.6, 0, 23.75)
const TANK := Vector3(21.0, 0, 38.4)
const WORMERY := Vector3(6.9, 0, 38.4)

var arena: Node3D
var yard: Node3D
var plants := {}                # spot key -> {s, g, wet, dry, wilt, fed}
var worms := {"n": 0, "food": 0.0, "eaten": 0.0, "cast": 0, "born": 0.0}
var _views := {}                # spot key -> VoxelPlant
var _sync_t := 0.0
var _check_t := 0.0
var _own = null                 # guest: their own farm while in someone's game
var _was_role := ""

func setup(arena_: Node3D, yard_: Node3D) -> void:
	arena = arena_
	yard = yard_
	_props()

func ground() -> VoxelTerrain:
	return yard.ground

func _is_guest() -> bool:
	return arena.net != null and arena.net.role == "guest" and arena.net.linked

func _is_host() -> bool:
	return arena.net != null and arena.net.role == "host" and arena.net.linked

# ---------------------------------------------------------------- spots

## The planting spot a world point is in (its key), -1 off the ground.
func spot_of(p: Vector3) -> int:
	var g := ground()
	var l := p - g.origin
	if l.x < 0.0 or l.z < 0.0 or l.x >= VoxelTerrain.NX * VoxelTerrain.CELL or l.z >= VoxelTerrain.NZ * VoxelTerrain.CELL:
		return -1
	return floori(l.x / SPOT) * 1000 + floori(l.z / SPOT)

## The middle of a spot's top (where its plant stands): its middle block's top face, or INF if not tilled there.
func spot_top(key: int) -> Vector3:
	var g := ground()
	var cx := (float(key / 1000) + 0.5) * SPOT
	var cz := (float(key % 1000) + 0.5) * SPOT
	var p := g.origin + Vector3(cx, 0, cz)
	var c := g.cell_of(p)
	for y in range(VoxelTerrain.NY - 1, 1, -1):
		var m := g.at(c.x, y, c.z)
		if m == VoxelTerrain.AIR:
			continue
		if m != VoxelTerrain.TILLED:
			return Vector3.INF
		return Vector3(p.x, g.origin.y + (y + 1) * VoxelTerrain.CELL, p.z)
	return Vector3.INF

static func stage_of(g: float) -> int:
	return 3 if g >= 1.0 else (2 if g >= 0.5 else (1 if g >= 0.2 else 0))

static func look_of(b: Dictionary) -> int:
	return (1 + int(b.wilt)) if (float(b.g) < 1.0 and float(b.wet) <= 0.0) else 0

## How many buds a plant gives now.
static func buds_of(b: Dictionary) -> int:
	return maxi(1, int(STRAINS[int(b.s)].buds) - int(b.wilt) + int(b.fed))

# ---------------------------------------------------------------- growing (the host's, or alone)

func _process(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if _was_role == "guest" and _own != null:
			from_data(_own)
			_own = null
		if role == "host":
			_send_all()
		_was_role = role
	if not _is_guest():
		_grow(dt)
		_worms(dt)
		_check_t += dt
		if _check_t > 1.0:
			_check_t = 0.0
			# a plant whose tilled ground was dug away is gone
			for key in plants.keys():
				if spot_top(key) == Vector3.INF:
					plants.erase(key)
					_changed(key)
	if _is_host():
		_sync_t += dt
		if _sync_t >= SYNC_T:
			_sync_t = 0.0
			_send_all()
	_show()

func _grow(dt: float) -> void:
	for key in plants:
		var b: Dictionary = plants[key]
		if float(b.g) >= 1.0:
			continue
		var wet := float(b.wet) > 0.0
		var speed := (1.0 if wet else DRY_SPEED) * (1.0 + FED_SPEED * int(b.fed))
		var st0 := stage_of(float(b.g))
		b.g = minf(1.0, float(b.g) + speed * dt / (float(STRAINS[int(b.s)].mins) * 60.0))
		if wet:
			b.wet = maxf(0.0, float(b.wet) - dt)
		else:
			b.dry = float(b.dry) + dt
			if int(b.wilt) == 0 and float(b.dry) >= WILT_AFTER:
				b.wilt = 1
				_changed(key)
		if stage_of(float(b.g)) != st0:
			_changed(key)
			arena.stash._dirty = true

## A wave cleared: everything growing jumps ahead (the HTML game's farmWave).
func on_wave() -> void:
	if _is_guest():
		return
	for key in plants:
		var b: Dictionary = plants[key]
		if float(b.g) < 1.0:
			b.g = minf(1.0, float(b.g) + 1.0 / float(STRAINS[int(b.s)].waves))
			_changed(key)

func _worms(dt: float) -> void:
	var n := int(worms.n)
	if n <= 0 or float(worms.food) <= 0.0:
		return
	var eat := minf(float(worms.food), n * WORM_EAT * dt)
	worms.food = float(worms.food) - eat
	worms.eaten = float(worms.eaten) + eat
	while float(worms.eaten) >= CAST_EVERY:
		worms.eaten = float(worms.eaten) - CAST_EVERY
		worms.cast = int(worms.cast) + 1
	if n < WORM_MAX:
		worms.born = float(worms.born) + n * WORM_BREED * dt
		if float(worms.born) >= 1.0:
			worms.born = float(worms.born) - 1.0
			worms.n = n + 1

# ---------------------------------------------------------------- what a player does (the arena and the tools call these)

## Plant seed s at spot key (this player's seed: out of their backpack first). False: not tilled, or taken.
func plant(key: int, s: int) -> bool:
	if plants.has(key) or spot_top(key) == Vector3.INF:
		return false
	if arena.inv.remove(seed_id(s), 1) < 1:
		return false
	if _is_guest():
		_msg(["plant", key, s])
		return true
	plants[key] = {"s": s, "g": 0.0, "wet": 0.0, "dry": 0.0, "wilt": 0, "fed": 0}
	_changed(key)
	return true

## Harvest the ready plant at key: its buds into this player's backpack (a guest's from the host).
func harvest(key: int) -> int:
	var b = plants.get(key)
	if b == null or float(b.g) < 1.0:
		return 0
	if _is_guest():
		_msg(["harvest", key])
		return buds_of(b)
	var n := buds_of(b)
	plants.erase(key)
	_changed(key)
	arena.receive({"id": bud_id(int(b.s)), "n": n}, "inv")
	return n

## The can poured on spot key: watered for WET_FOR. False if there's no plant, or it was watered just now.
func water(key: int) -> bool:
	var b = plants.get(key)
	if b == null or float(b.g) >= 1.0 or float(b.wet) > WET_FOR - 15.0:
		return false
	if _is_guest():
		_msg(["water", key])
		b.wet = WET_FOR                # (shown at once; the host's is the real one)
		return true
	b.wet = WET_FOR
	b.dry = 0.0
	_changed(key)
	return true

## What feeds a plant, out of this player's backpack: castings (one), a bag of blood and bone, else chicken poo
## (POO_FEED of it). "": none.
func feed_with() -> String:
	if arena.inv.count("castings") >= 1:
		return "castings"
	if arena.inv.count("blood_bone") >= 1:
		return "blood_bone"
	if arena.inv.count("poo") >= POO_FEED:
		return "poo"
	return ""

## A feed (worm castings, or chicken poo) for the plant at key (out of this player's backpack). False: none, or fed
## twice already.
func fertilise(key: int) -> bool:
	var b = plants.get(key)
	var w := feed_with()
	if b == null or float(b.g) >= 1.0 or int(b.fed) >= FED_MAX or w == "":
		return false
	arena.inv.remove(w, POO_FEED if w == "poo" else 1)
	if _is_guest():
		_msg(["fert", key, w])
		return true
	b.fed = int(b.fed) + 1
	_changed(key)
	return true

## E at the worm farm: the castings ready taken; else this player's worms and scraps put in. Returns what it did.
func service_wormery() -> String:
	if _is_guest():
		if int(worms.cast) > 0:
			_msg(["wcast"])
			return "castings"
		var feed := _take_feed()
		if feed.worms > 0 or feed.food > 0.0:
			_msg(["wfeed", feed.worms, feed.food])
			return "fed"
		return ""
	if int(worms.cast) > 0:
		arena.receive({"id": "castings", "n": int(worms.cast)}, "inv")
		worms.cast = 0
		_changed(-1)
		return "castings"
	var f := _take_feed()
	if f.worms > 0 or f.food > 0.0:
		worms.n = mini(WORM_MAX, int(worms.n) + f.worms)
		worms.food = float(worms.food) + f.food
		_changed(-1)
		return "fed"
	return ""

# this player's worms and up to FEED_MOST scraps out of their backpack
func _take_feed() -> Dictionary:
	var room := WORM_MAX - int(worms.n)
	var w: int = arena.inv.remove("worm", maxi(0, room)) if room > 0 else 0
	var food := 0.0
	var left := FEED_MOST
	for id in SCRAP:
		if left <= 0:
			break
		var k: int = arena.inv.remove(id, left)
		food += k * float(SCRAP[id])
		left -= k
	return {"worms": w, "food": food}

## The seed the player plants: the kind bought last, or any they've got (-1: none).
var pick := 0
func seed_pick() -> int:
	if arena.inv.count(seed_id(pick)) > 0:
		return pick
	for s in STRAINS.size():
		if arena.inv.count(seed_id(s)) > 0:
			return s
	return -1

## E at a seed crate bin: a seed of s for its price (this player's cash).
func buy(s: int) -> bool:
	var c := int(STRAINS[s].seed)
	if c <= 0 or arena.cash < c:
		return false
	arena.cash -= c
	arena.receive({"id": seed_id(s), "n": 1}, "inv")
	pick = s
	arena.stash._dirty = true
	return true

## What the buyer gives for everything this player has to sell (buds, eggs).
func sell_value() -> int:
	var v := 0.0
	for s in STRAINS.size():
		v += arena.inv.count(bud_id(s)) * float(STRAINS[s].price) / float(STRAINS[s].buds)
	v += arena.inv.count("egg") * VoxelChickens.EGG_PRICE
	v += arena.inv.count("chicken_carcass") * VoxelChickens.CARCASS_PRICE + arena.inv.count("roast_chicken") * VoxelChickens.ROAST_PRICE
	return int(round(v))

## E at the buyer's crate: every bud, egg and chicken carcass this player has, sold. Returns the cash.
func sell() -> int:
	var v := float(arena.inv.remove("egg", arena.inv.count("egg")) * VoxelChickens.EGG_PRICE)
	v += float(arena.inv.remove("chicken_carcass", arena.inv.count("chicken_carcass")) * VoxelChickens.CARCASS_PRICE)
	v += float(arena.inv.remove("roast_chicken", arena.inv.count("roast_chicken")) * VoxelChickens.ROAST_PRICE)
	for s in STRAINS.size():
		var n: int = arena.inv.count(bud_id(s))
		if n > 0:
			v += n * float(STRAINS[s].price) / float(STRAINS[s].buds)
			arena.inv.remove(bud_id(s), n)
	var cash := int(round(v))
	arena.cash += cash
	arena.stash._dirty = true
	return cash

static func seed_id(s: int) -> String:
	return "seed_" + String(STRAINS[s].short).to_lower()

static func bud_id(s: int) -> String:
	return "bud_" + String(STRAINS[s].short).to_lower()

## Items for VoxelItems: a seed and a bud of each strain, the castings.
static func items() -> Dictionary:
	var out := {}
	var leaf := [Color8(60, 130, 50), Color8(150, 190, 60), Color8(110, 60, 140), Color8(90, 160, 170), Color8(200, 160, 50), Color8(220, 225, 210)]
	for s in STRAINS.size():
		var st: Dictionary = STRAINS[s]
		out[seed_id(s)] = {"name": "%s seed" % st.name, "col": Color8(210, 196, 150), "stack": 99,
			"desc": "Plant it in hoed ground (E). Grows in %d min, or %d waves." % [int(st.mins), int(st.waves)]}
		out[bud_id(s)] = {"name": "%s bud" % st.name, "col": leaf[s], "stack": 999,
			"desc": "Sells for $%d at the buyer's crate." % int(round(float(st.price) / float(st.buds)))}
	out["castings"] = {"name": "Worm castings", "col": Color8(58, 44, 34), "stack": 999,
		"desc": "From the worm farm. E at a growing plant: faster, and a bud more."}
	return out

# ---------------------------------------------------------------- co-op

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_farm(m)

# (the host's or alone) a plant or the worm farm changed: shown now; the guest told
func _changed(key: int) -> void:
	arena.stash._dirty = true
	if _is_host():
		if key < 0:
			_msg(["w", worms])
		else:
			_msg(["p", key, plants.get(key)])

func _send_all() -> void:
	_msg(["all", to_data()])

func send_all() -> void:
	if _is_host():
		_send_all()

func on_net(m: Array) -> void:
	var host := _is_host()
	match String(m[0]):
		"all":
			if _is_guest():
				if _own == null:
					_own = to_data()
				from_data(m[1])
		"p":
			if _is_guest():
				if m[2] == null:
					plants.erase(int(m[1]))
				else:
					plants[int(m[1])] = _clean(m[2])
		"w":
			if _is_guest() and typeof(m[1]) == TYPE_DICTIONARY:
				worms = m[1]
		"plant":
			if host:
				var key := int(m[1])
				var s := clampi(int(m[2]), 0, STRAINS.size() - 1)
				if plants.has(key) or spot_top(key) == Vector3.INF:
					_msg(["give", {"id": seed_id(s), "n": 1}])      # (taken already: the seed back)
				else:
					plants[key] = {"s": s, "g": 0.0, "wet": 0.0, "dry": 0.0, "wilt": 0, "fed": 0}
					_changed(key)
		"harvest":
			var b = plants.get(int(m[1]))
			if host and b != null and float(b.g) >= 1.0:
				plants.erase(int(m[1]))
				_changed(int(m[1]))
				_msg(["give", {"id": bud_id(int(b.s)), "n": buds_of(b)}])
		"water":
			var bw = plants.get(int(m[1]))
			if host and bw != null and float(bw.g) < 1.0:
				bw.wet = WET_FOR
				bw.dry = 0.0
				_changed(int(m[1]))
		"fert":
			var bf = plants.get(int(m[1]))
			if host:
				if bf != null and float(bf.g) < 1.0 and int(bf.fed) < FED_MAX:
					bf.fed = int(bf.fed) + 1
					_changed(int(m[1]))
				else:
					var back := String(m[2]) if m.size() > 2 and String(m[2]) in ["poo", "blood_bone"] else "castings"
					_msg(["give", {"id": back, "n": POO_FEED if back == "poo" else 1}])
		"wcast":
			if host and int(worms.cast) > 0:
				_msg(["give", {"id": "castings", "n": int(worms.cast)}])
				worms.cast = 0
				_changed(-1)
		"wfeed":
			if host:
				var add := clampi(int(m[1]), 0, WORM_MAX)
				var keep := mini(add, WORM_MAX - int(worms.n))
				worms.n = int(worms.n) + keep
				worms.food = float(worms.food) + clampf(float(m[2]), 0.0, FEED_MOST * VoxelShredder.BAG_SCRAPS)     # (the most a take carries: all bags)
				if add > keep:
					_msg(["give", {"id": "worm", "n": add - keep}])
				_changed(-1)
		"give":
			var g: Dictionary = m[1]
			if VoxelItems.has(String(g.get("id", ""))) and int(g.get("n", 0)) > 0:
				arena.receive({"id": String(g.id), "n": int(g.n)}, "inv")

static func _clean(b) -> Dictionary:
	if typeof(b) != TYPE_DICTIONARY:
		return {}
	return {"s": clampi(int(b.get("s", 0)), 0, STRAINS.size() - 1), "g": clampf(float(b.get("g", 0.0)), 0.0, 1.0),
		"wet": maxf(0.0, float(b.get("wet", 0.0))), "dry": maxf(0.0, float(b.get("dry", 0.0))),
		"wilt": 1 if int(b.get("wilt", 0)) else 0, "fed": clampi(int(b.get("fed", 0)), 0, FED_MAX)}

# ---------------------------------------------------------------- saving

## The farm as plain data (saving, sending): {plants: {key: plant}, worms}.
func to_data() -> Dictionary:
	var p := {}
	for key in plants:
		p[str(key)] = plants[key]
	return {"plants": p, "worms": worms.duplicate()}

func from_data(d) -> void:
	plants.clear()
	if typeof(d) != TYPE_DICTIONARY:
		return
	var p = d.get("plants", {})
	if typeof(p) == TYPE_DICTIONARY:
		for k in p:
			var b := _clean(p[k])
			if not b.is_empty():
				plants[int(k)] = b
	var w = d.get("worms")
	if typeof(w) == TYPE_DICTIONARY:
		worms = {"n": clampi(int(w.get("n", 0)), 0, WORM_MAX), "food": maxf(0.0, float(w.get("food", 0.0))),
			"eaten": maxf(0.0, float(w.get("eaten", 0.0))), "cast": maxi(0, int(w.get("cast", 0))), "born": float(w.get("born", 0.0))}

## For the save file (a guest in someone's game: its own farm).
func save_data() -> Dictionary:
	return _own if _own != null else to_data()

# ---------------------------------------------------------------- showing it

func _show() -> void:
	for key in _views.keys():
		if not plants.has(key):
			(_views[key] as Node).queue_free()
			_views.erase(key)
	for key in plants:
		var b: Dictionary = plants[key]
		var v: VoxelPlant = _views.get(key)
		if v == null:
			var at := spot_top(key)
			if at == Vector3.INF:
				continue
			v = VoxelPlant.new()
			add_child(v)
			v.position = at
			v.rotation.y = float(key % 7) * 0.9      # (each turned its own way)
			_views[key] = v
		v.show_as(int(b.s), stage_of(float(b.g)), look_of(b), float(b.wet) > 0.0)

## Looking at a plant (its spot key and how far), from eye along dir: [key or -1, distance].
func plant_hit(eye: Vector3, dir: Vector3, reach := 2.6) -> Array:
	var best := -1
	var bd := INF
	for key in _views:
		var v: VoxelPlant = _views[key]
		var h: float = maxf(0.25, VoxelPlant._top(v.strain, v.stage, v.look))
		var box := AABB(v.global_position + Vector3(-0.3, 0, -0.3), Vector3(0.6, h, 0.6))
		var hit = box.intersects_ray(eye, dir)
		if hit != null:
			var d := (hit as Vector3).distance_to(eye)
			if d <= reach and d < bd:
				bd = d
				best = key
	return [best, bd]

## A line about the plant at key (what it is, how grown, watered or not).
func hint(key: int) -> String:
	var b = plants.get(key)
	if b == null:
		return ""
	var st: Dictionary = STRAINS[int(b.s)]
	if float(b.g) >= 1.0:
		return "%s: ready! %d buds" % [st.name, buds_of(b)]
	var s := "%s %d%%" % [st.name, int(float(b.g) * 100.0)]
	s += ", watered" if float(b.wet) > 0.0 else (", wilted (lost a bud)" if int(b.wilt) else ", dry: water it")
	if int(b.fed) > 0:
		s += ", fed x%d" % int(b.fed)
	return s

## What's at the props: "crate0" / "crate1" (the seed bins), "buyer", "tank", "wormery", or "".
func prop_at(eye: Vector3, dir: Vector3, reach := 2.4) -> String:
	var boxes := {"crate0": AABB(CRATE + Vector3(-0.6, 0, -0.3), Vector3(0.6, 0.8, 0.6)), "crate1": AABB(CRATE + Vector3(0.0, 0, -0.3), Vector3(0.6, 0.8, 0.6)),
		"buyer": AABB(BUYER + Vector3(-0.6, 0, -0.35), Vector3(1.2, 1.0, 0.7)), "tank": AABB(TANK + Vector3(-0.6, 0, -0.6), Vector3(1.2, 1.6, 1.2)),
		"wormery": AABB(WORMERY + Vector3(-0.45, 0, -0.35), Vector3(0.9, 1.0, 0.7))}
	var best := ""
	var bd := INF
	for k in boxes:
		var hit = (boxes[k] as AABB).intersects_ray(eye, dir)
		if hit != null:
			var d := (hit as Vector3).distance_to(eye)
			if d <= reach and d < bd:
				bd = d
				best = k
	return best

# ---------------------------------------------------------------- the props

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _solid(size: Vector3, at: Vector3, m: Material, parent: Node3D = self) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = at
	parent.add_child(sb)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	return sb

func _label(text: String, at: Vector3, size := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.outline_size = 8
	l.position = at
	add_child(l)

func _props() -> void:
	var wood := _mat(Color8(176, 136, 86))
	var dark := _mat(Color8(110, 80, 50))
	# the seed crate: two bins (Northern Lights left, Sour Diesel right), a SEEDS sign
	var crate := Node3D.new()
	crate.position = CRATE
	add_child(crate)
	_solid(Vector3(1.2, 0.5, 0.6), Vector3(0, 0.25, 0), wood, crate)
	_solid(Vector3(0.04, 0.55, 0.62), Vector3(0, 0.275, 0), dark, crate)
	for k in 2:
		var seeds := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.52, 0.04, 0.52)
		seeds.mesh = sm
		seeds.material_override = _mat([Color8(70, 130, 50), Color8(160, 190, 60)][k], 0.95)
		seeds.position = Vector3(-0.3 + 0.6 * k, 0.49, 0)
		crate.add_child(seeds)
	_label("SEEDS\nNL $10   SD $30", CRATE + Vector3(0, 0.95, -0.1), 40)
	# the buyer's crate (sell your buds), green
	_solid(Vector3(1.2, 0.8, 0.7), BUYER + Vector3(0, 0.4, 0), _mat(Color8(60, 120, 60)))
	_label("BUYER\nbuds for cash", BUYER + Vector3(0, 1.2, 0), 40)
	# the water tank: a corrugated round tank, a tap and a bucket
	var tank := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 1.5
	cm.radial_segments = 24
	tank.mesh = cm
	tank.material_override = _mat(Color8(150, 170, 178), 0.4, 0.6)
	tank.position = TANK + Vector3(0, 0.75, 0)
	add_child(tank)
	var tb := StaticBody3D.new()
	tb.position = TANK + Vector3(0, 0.75, 0)
	var tcs := CollisionShape3D.new()
	var tsh := CylinderShape3D.new()
	tsh.radius = 0.6
	tsh.height = 1.5
	tcs.shape = tsh
	tb.add_child(tcs)
	add_child(tb)
	_solid(Vector3(0.06, 0.06, 0.18), TANK + Vector3(0, 0.35, -0.66), _mat(Color8(200, 200, 205), 0.3, 0.9))
	_label("WATER\nE: fill the can", TANK + Vector3(0, 1.85, 0), 40)
	# the worm farm: three black bins stacked on legs, a lid, a tap at the bottom
	var wf := Node3D.new()
	wf.position = WORMERY
	add_child(wf)
	var black := _mat(Color8(34, 34, 38), 0.6)
	for k in 3:
		_solid(Vector3(0.8, 0.22, 0.6), Vector3(0, 0.25 + k * 0.24, 0), black, wf)
	_solid(Vector3(0.84, 0.05, 0.64), Vector3(0, 0.62 + 0.24, 0), _mat(Color8(60, 60, 66), 0.6), wf)
	_label("WORM FARM", WORMERY + Vector3(0, 1.3, 0), 40)
