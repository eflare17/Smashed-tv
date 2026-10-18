class_name NetCodec
extends RefCounted
## Packing the fight (FightSim and its FT records) into plain arrays for the host's snapshot, and back on the guest
## (the HTML game's snapshot / worldFromSnapshot, done by reflection: every script variable of every record, in
## the order the script declares them, so both builds agree without a hand-written list).
## Owned by the Online task.
##
## On the guest the two players swap places (the host's player 0 becomes the guest's player 1 and the other way
## round), so the guest's own Fight keeps thinking of itself as player 0: its HUD, camera, weapon bar and aim all
## work unchanged. Every field that names a player is swapped with it.

## The sim's own variables that travel (the rest are tuning, caches, or the guest's own).
const SIM_VARS := ["t", "freeze", "shake", "started", "over", "mode", "wave", "pending", "spawn_timer", "breather",
	"enemies", "shards", "janitor", "sign", "slot", "vend_sold", "nuke", "bullets", "husks", "rockets", "blasts",
	"blast_id", "plants", "plant_timer", "rain", "bits", "blood", "splats", "corpses", "coins", "floaters", "dummies",
	"goth", "goth_down", "secret", "secret_used", "enemy_uid"]
## Fields (by record) that hold a player id.
const ID_FIELDS := {"Fighter": ["id"], "Bullet": ["owner"], "Husk": ["owner"], "Rocket": ["owner"], "Coin": ["owner"],
	"Janitor": ["target"], "Goth": ["carrier"], "Slot": ["busy"]}
## Fields never sent.
const SKIP := {"node": true, "saved": true}

static var _classes: Dictionary = {}     # name -> the FT inner class
static var _names: Dictionary = {}       # script -> name
static var _fields: Dictionary = {}      # name -> [field names]

static func _init_classes() -> void:
	if not _classes.is_empty():
		return
	var src := {"Inp": FT.Inp, "Fighter": FT.Fighter, "Bullet": FT.Bullet, "Husk": FT.Husk, "Rocket": FT.Rocket,
		"Blast": FT.Blast, "Plant": FT.Plant, "Rain": FT.Rain, "Enemy": FT.Enemy, "Shard": FT.Shard, "Bit": FT.Bit,
		"Blood": FT.Blood, "Splat": FT.Splat, "Corpse": FT.Corpse, "Coin": FT.Coin, "Floater": FT.Floater,
		"Dummy": FT.Dummy, "Nuke": FT.Nuke, "Janitor": FT.Janitor, "Goth": FT.Goth, "Slot": FT.Slot,
		"Hazard": FT.Hazard, "Secret": FT.Secret}
	for n in src:
		_classes[n] = src[n]
		var probe: Object = src[n].new()
		_names[probe.get_script()] = n
		var fl: Array = []
		for p in probe.get_property_list():
			if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) and not SKIP.has(p.name):
				fl.append(p.name)
		_fields[n] = fl

static func class_of(o: Object) -> String:
	_init_classes()
	return _names.get(o.get_script(), "")

## A record as [name, v1, v2...]; arrays and records inside are packed too.
static func pack(v):
	if v is Object:
		if v == null:
			return null
		var n := class_of(v)
		if n == "":
			return null
		var out := [n]
		for f in _fields[n]:
			out.append(pack(v.get(f)))
		return out
	if v is Array:
		var a := []
		a.resize(v.size())
		for i in v.size():
			a[i] = pack(v[i])
		return a
	return v

## Back from pack(). into: an existing record to fill in place (keeps references others hold).
static func unpack(v, into: Object = null):
	if v is Array and v.size() > 0 and v[0] is String and _is_class(v[0]):
		var n: String = v[0]
		var o: Object = into if into != null and class_of(into) == n else _classes[n].new()
		var fl: Array = _fields[n]
		for i in mini(fl.size(), v.size() - 1):
			var cur = o.get(fl[i])
			var nv = v[i + 1]
			if cur is Array and cur.is_typed():
				cur.assign(unpack(nv) if nv is Array else [])
			elif nv is Array:
				o.set(fl[i], unpack(nv))
			else:
				o.set(fl[i], nv)
		return o
	if v is Array:
		var a := []
		a.resize(v.size())
		for i in v.size():
			a[i] = unpack(v[i])
		return a
	return v

static func _is_class(n: String) -> bool:
	_init_classes()
	return _classes.has(n)

## The host's fight as a Dictionary.
static func pack_sim(sim: FightSim) -> Dictionary:
	var d := {}
	for k in SIM_VARS:
		d[k] = pack(sim.get(k))
	var ps := []
	for p in sim.players:
		ps.append(pack(p))
	d["players"] = ps
	return d

## Load the host's fight into the guest's sim, swapping players 0 and 1. keep_own: the guest's own player keeps
## where it is (its own prediction) unless the host has it far away, thrown, down or in the bonus room.
static func unpack_sim(sim: FightSim, d: Dictionary, keep_own: bool) -> void:
	_init_classes()
	for k in SIM_VARS:
		if not d.has(k):
			continue
		var cur = sim.get(k)
		var v = d[k]
		if v is Array and v.size() > 0 and v[0] is String and _is_class(v[0]):
			sim.set(k, unpack(v, cur if cur is Object else null))
		elif v == null:
			sim.set(k, null)
		elif v is Array:
			sim.set(k, unpack(v))
		else:
			sim.set(k, v)
	var ps: Array = d.get("players", [])
	for i in ps.size():
		var j := _swap(i)
		while sim.players.size() <= j:
			sim.players.append(FT.Fighter.new())
		var f: FT.Fighter = sim.players[j]
		var own := j == 0 and keep_own
		var keep := {}
		if own:
			for k in ["x", "y", "vx", "vy", "roll", "roll_cd", "rdx", "rdy", "odo", "moving", "fx", "fy", "ix", "iy"]:
				keep[k] = f.get(k)
		var node := f.node
		unpack(ps[i], f)
		f.node = node
		if own:
			var far := Vector2(float(keep.x) - f.x, float(keep.y) - f.y).length() > 48.0
			if not far and f.alive and f.launch <= 0.0 and (sim.secret == null or sim.secret.phase == "done"):
				for k in keep:
					f.set(k, keep[k])
	_swap_ids(sim)

static func _swap(i: int) -> int:
	return 1 if i == 0 else (0 if i == 1 else i)

static func _swap_ids(sim: FightSim) -> void:
	for f in sim.players:
		f.id = _swap(f.id)
	for list in [sim.bullets, sim.husks, sim.rockets, sim.coins]:
		for o in list:
			if o.owner >= 0:
				o.owner = _swap(o.owner)
	if sim.janitor and sim.janitor.target >= 0:
		sim.janitor.target = _swap(sim.janitor.target)
	if sim.goth and sim.goth.carrier >= 0:
		sim.goth.carrier = _swap(sim.goth.carrier)
	if sim.slot and sim.slot.busy >= 0:
		sim.slot.busy = _swap(sim.slot.busy)
	if sim.secret and sim.secret.origins.size() > 1:
		var o: Array = sim.secret.origins
		var a = o[0]
		o[0] = o[1]
		o[1] = a

## The guest's input for the wire, and back.
static func pack_inp(inp: FT.Inp) -> Array:
	return pack(inp)

static func unpack_inp(a) -> FT.Inp:
	var inp = unpack(a) if a is Array else null
	return inp if inp is FT.Inp else FT.Inp.new()
