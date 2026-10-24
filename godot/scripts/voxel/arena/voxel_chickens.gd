class_name VoxelChickens
extends Node3D
## Chickens (the owner, 21 Oct, Stage 6: "feed chickens; collect chicken poo as fertiliser (optionally via the worm
## farm); collect eggs; eggs can hatch into more chickens; more feeding = faster breeding; walk-in chicken coop with a
## nesting area to check/collect eggs; chickens can be let out to roam the yard; max chicken cap tied to the coop,
## upgrading the coop raises the cap").
##
## A wired-in run east of the back yard, through a gate in the yard's fence; a walk-in coop in its far corner: nest
## boxes along one wall, perches, the feeder and the feed sacks. The hens wander and peck, go in to eat when they're
## hungry and the feeder has feed, go up into a nest box to lay when they've eaten enough (a hen fed full lays every
## LAY_T, half fed every twice that, hungry not at all), flap off when someone runs at them, and drop poo about (little
## brown cubes the vacuum takes, worth feeding plants or the worm farm). Eggs left in a nest hatch (in HATCH_T, faster
## the better fed the hens are) while there's room under the coop's cap; collected, they sell at the buyer's crate or
## (H) are eaten for health. The gate open, the hens roam the yard too (and come back in to eat and lay). The coop sign
## upgrades it: more nest boxes, more chickens.
##
## Co-op: the chickens are the host's (like the farm): a guest's gate, feeding, egg collecting and upgrading go to the
## host as requests, the host answers with what they got; where the hens are goes to the guest ten times a second, the
## rest every couple of seconds and on every change. Saved with the rest. Owned by the voxel session.
##
## Killing them (the owner, 24 Oct: "make it so you can kill the chickens. When you kill them they turn into a chicken
## carcass", "You can only kill them if they are out of the chicken coop"): out in the yard, any weapon or tool that
## lands on one (STRIKE; a grenade's blast or a fire patch through blast()) hurts it: it squawks, flaps, feathers fly
## and it runs; HP blows kill a hen, one a chick. Dead, it's a carcass on the ground (plucked, lying on its side, its
## feathers round it) that E picks up as a chicken carcass: sold at the buyer, or shredded for blood and bone. In the
## run or the coop they're safe: a blow only sends them flapping off (and says why, the first time). A guest's blows
## go to the host as "hit"s (the host's are the real chickens), its pick-ups as "take"s.

## The run (world metres), the gate in the yard's east fence, the coop in the run's south-east corner.
const X0 := 22.65
const X1 := 31.6
const Z0 := 22.5
const Z1 := 40.0
const GATE_X := 22.55           # (the yard's east fence line)
const GATE_Z0 := 29.8
const GATE_Z1 := 31.2
const COOP_X0 := 27.0
const COOP_X1 := 31.6
const COOP_Z0 := 34.0
const COOP_Z1 := 40.0
const DOOR_X0 := 28.7
const DOOR_X1 := 29.9
const DOOR_H := 2.1
const WALL_H := 2.5
const FENCE_H := 1.8
## Where the hens go through (outside, inside), the run's corner they go round.
const DOOR_OUT := Vector2(29.3, 33.3)
const DOOR_IN := Vector2(29.3, 34.7)
const GATE_PEN := Vector2(23.3, 30.5)
const GATE_YARD := Vector2(21.8, 30.5)
const CORNER := Vector2(26.5, 33.5)
## Inside the coop.
const FEEDER := Vector3(27.55, 0, 35.3)
const WATERER := Vector3(27.55, 0, 36.3)
const SACKS := Vector3(30.95, 0, 34.55)
const SIGN := Vector3(28.05, 0, 33.92)
const NEST_X := 31.25
const NEST_Z := 35.6            # the first nest's middle ...
const NEST_DZ := 0.68           # ... and the next along
const NEST_Y := 0.58            # where a hen sits in one
const NEST_EGGS := 3
## The coop's levels: how many chickens (chicks too), how many nest boxes, what the next costs (cash, then items).
const LEVELS := [
	{"cap": 4, "nests": 2},
	{"cap": 8, "nests": 4, "cash": 100, "cost": {"stone": 150}},
	{"cap": 16, "nests": 6, "cash": 300, "cost": {"stone": 400}},
]
const HUNGER_T := 300.0         # seconds from fed full to empty
const LAY_T := 120.0            # seconds an egg, fed full (half fed: twice that; under a quarter: none)
const HATCH_T := 150.0          # seconds an egg in a nest takes to hatch, at speed 1 (0.5 hungry hens .. 1.5 fed full)
const GROW_T := 240.0           # a chick to a hen
const POO_T := 45.0             # seconds between poos (fed)
const POO_CUBES := 12
const FEEDER_MAX := 60          # feed in the feeder
const EAT := 0.5                # a feed fills a hen this much
## What goes in the feeder (a feed each), out of the backpack.
const FEEDS := {"grain": 1, "worm": 3, "blood_bone": VoxelShredder.BAG_FEEDS}
const GRAIN_BUY := 10           # grain a buy ...
const GRAIN_COST := 5           # ... for this
const EGG_PRICE := 4            # at the buyer's crate
const EGG_HP := 20.0            # eaten (H)
const POO := [Color8(96, 72, 40), Color8(112, 86, 50), Color8(222, 218, 200)]
const WALK := 0.55
const RUN := 2.2
const SYNC_T := 2.0
const POS_HZ := 10.0
const START := 2                # hens to start with
## What each weapon or tool does to a chicken it lands on (VoxelArena.MELEE's ids): [reach (metres), how far off the
## look it still lands (degrees), damage, seconds before it can land again, held down it keeps landing]. Past RANGED
## metres it's a shot: the walls stop it.
const STRIKE := {
	"sword": [2.6, 55.0, 1, 0.3, false], "bat": [2.4, 50.0, 1, 0.35, false], "hammer": [2.4, 45.0, 2, 0.5, false],
	"chainsaw": [2.0, 35.0, 1, 0.3, true], "spear": [3.2, 15.0, 2, 0.4, false],
	"pistol": [40.0, 2.5, 1, 0.15, true], "shotgun": [25.0, 7.0, 3, 0.6, false], "laser": [20.0, 2.5, 1, 0.3, true],
	"flamethrower": [6.0, 14.0, 1, 0.4, true], "freezeray": [15.0, 3.0, 1, 0.4, true], "harpoon": [20.0, 3.0, 3, 0.6, false],
	"gravity": [10.0, 5.0, 1, 0.5, false],
	"shovel": [3.0, 40.0, 1, 0.4, false], "pick": [3.0, 40.0, 1, 0.4, false], "hoe": [3.0, 40.0, 1, 0.4, false],
}
const RANGED := 6.0
const HP := 3                   # blows a hen takes (a chick: one)
const CARCASS_PRICE := 15       # at the buyer's crate
const CARCASS_POINTS := 1000.0  # in the shredder (a quarter of a bag of blood and bone)
const CARCASS_MAX := 24         # lying about at once (past that the oldest goes)
const FEATHERS_MAX := 160

enum { PEN, COOP, YARD, NONE }

var arena: Node3D
var yard: Node3D
var level := 0
var gate := false               # open: they roam the yard
var food := 20.0
var nests := []                 # per nest box: [egg hatch progress 0..1, ...]
var hens := []                  # [{id, x, y, z, yaw, c, age, full, lay, poo, st, t, path, anim, nest, hurt, hit_ms}]
var carcasses := []             # [{id, x, y, z, yaw, c, chick}] (the host's, or alone; the guest's from the host's)
var _next_id := 1
var _views := {}                # hen id -> VoxelChicken
var _sync_t := 0.0
var _pos_t := 0.0
var _dirty := false              # (the host's: changed, the guest told in a moment)
var _dirty_t := 0.0
var _own = null
var _was_role := ""
var _gate_node: Node3D
var _gate_a := 0.0
var _nest_nodes := []           # per nest box: [its node, [egg meshes], its shelf's collision]
var _sign: Label3D
var _roof: Node3D
var _feed_mesh: MeshInstance3D
var _sack_nodes := []
var _carc_views := {}           # carcass id -> its node
var _feathers := []             # flying off a hit hen: [pos, vel, life, yaw, colour, ground y, phase]
var _feather_mm: MultiMesh
var _told_safe := false         # (the "safe in the coop" line: said once)
var _strike_t := {}             # weapon id -> seconds till it can land on a chicken again

## In the run or the coop: the enemies keep out and don't go for anyone here.
static func in_pen(p: Vector3) -> bool:
	return p.x > X0 - 0.1 and p.x < X1 + 0.3 and p.z > Z0 and p.z < Z1 + 0.3

static func in_coop(p: Vector3) -> bool:
	return p.x > COOP_X0 and p.x < COOP_X1 and p.z > COOP_Z0 and p.z < COOP_Z1

static func region_of(p: Vector2) -> int:
	if p.x > COOP_X0 + 0.02 and p.x < COOP_X1 and p.y > COOP_Z0 + 0.02 and p.y < COOP_Z1:
		return COOP
	if p.x >= GATE_X and p.x <= X1 and p.y >= Z0 and p.y <= Z1:
		return PEN
	if p.x > VoxelYard.X0 and p.x < GATE_X and p.y > VoxelYard.Z0 and p.y < VoxelYard.Z1:
		return YARD
	return NONE

func setup(arena_: Node3D, yard_: Node3D) -> void:
	arena = arena_
	yard = yard_
	_build()
	_fresh()

# a new coop: two hens, a bit of feed
func _fresh() -> void:
	level = 0
	gate = false
	food = 20.0
	nests = []
	for k in LEVELS[-1].nests:
		nests.append([])
	hens = []
	carcasses = []
	_next_id = 1
	for i in START:
		_hatch(Vector2(29.0 + i * 0.6, 37.0), 1.0, i)

func cap() -> int:
	return int(LEVELS[level].cap)

func nest_count() -> int:
	return int(LEVELS[level].nests)

func _is_guest() -> bool:
	return arena.net != null and arena.net.role == "guest" and arena.net.linked

func _is_host() -> bool:
	return arena.net != null and arena.net.role == "host" and arena.net.linked

# ---------------------------------------------------------------- the hens (the host's, or alone)

func _hatch(at: Vector2, age: float, coat := -1) -> Dictionary:
	var h := {"id": _next_id, "x": at.x, "y": 0.0, "z": at.y, "yaw": randf() * TAU, "c": coat if coat >= 0 else randi() % VoxelChicken.COATS.size(),
		"age": age, "full": 0.8, "lay": randf() * LAY_T * 0.5, "poo": randf() * POO_T, "st": "idle", "t": randf() * 2.0,
		"path": [], "anim": 0, "nest": -1, "hurt": 0, "hit_ms": 0}
	_next_id += 1
	hens.append(h)
	return h

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
		_live(dt)
	for id in _strike_t.keys():
		_strike_t[id] = float(_strike_t[id]) - dt
		if float(_strike_t[id]) <= 0.0:
			_strike_t.erase(id)
	_feathers_step(dt)
	if _is_host():
		_sync_t += dt
		_pos_t += dt
		if _dirty:
			_dirty_t += dt
		if _sync_t >= SYNC_T or _dirty_t >= 0.2:
			_sync_t = 0.0
			_dirty_t = 0.0
			_dirty = false
			_send_all()
		if _pos_t >= 1.0 / POS_HZ:
			_pos_t = 0.0
			_msg(["pos", _positions()])
	_show(dt)

func _live(dt: float) -> void:
	var fed_sum := 0.0
	var adults := 0
	for h in hens:
		_hen(h, dt)
		if float(h.age) >= 1.0:
			fed_sum += float(h.full)
			adults += 1
	# the eggs in the nests: hatching while there's room
	var speed := 0.5 + (fed_sum / adults if adults > 0 else 0.5)
	for k in nests.size():
		var eggs: Array = nests[k]
		for i in eggs.size():
			if float(eggs[i]) < 1.0:
				eggs[i] = minf(1.0, float(eggs[i]) + speed * dt / HATCH_T)
			elif hens.size() < cap() and k < nest_count():
				eggs.remove_at(i)
				var at := Vector2(NEST_X - 0.7, NEST_Z + k * NEST_DZ)
				_hatch(at, 0.0)
				_sound("peep", Vector3(at.x, 0.3, at.y))
				if in_pen(arena.player.global_position):
					arena.say("A chick hatched! (%d of %d chickens)" % [hens.size(), cap()], 2.5)
				_changed()
				break

func _hen(h: Dictionary, dt: float) -> void:
	var adult := float(h.age) >= 1.0
	h.full = maxf(0.0, float(h.full) - dt / HUNGER_T)
	if not adult:
		h.age = float(h.age) + dt / GROW_T
		if float(h.age) >= 1.0:
			h.age = 1.0
			_changed()
	elif float(h.full) >= 0.25:
		h.lay = minf(LAY_T, float(h.lay) + dt * float(h.full))
	if float(h.full) > 0.1:
		h.poo = float(h.poo) + dt * (0.5 + float(h.full))
		if float(h.poo) >= POO_T and String(h.st) != "sit":
			h.poo = 0.0
			_poo(Vector3(float(h.x), float(h.y), float(h.z)), randi() | 1)
	h.t = float(h.t) - dt
	var p := Vector2(float(h.x), float(h.z))
	# someone running at it: off it flaps
	if String(h.st) in ["idle", "walk", "peck"]:
		for pp in _players():
			var d := Vector2(pp.x - p.x, pp.z - p.y)
			if d.length() < 0.8 and absf(pp.y - float(h.y)) < 1.5:
				var away := (-d).normalized() if d.length() > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
				var to := p + away * 1.6
				if region_of(to) == region_of(p):
					h.path = [to]
					h.st = "flee"
					h.t = 1.2
					if randf() < 0.5:
						_sound("flap", Vector3(p.x, 0.3, p.y))
					else:
						_sound("cluck", Vector3(p.x, 0.3, p.y))
				break
	match String(h.st):
		"idle", "peck":
			h.anim = 2 if String(h.st) == "peck" else 0
			if float(h.t) <= 0.0:
				_next(h)
		"walk", "flee", "eat", "lay":
			var sp := RUN if String(h.st) == "flee" else WALK * (0.8 if not adult else 1.0)
			h.anim = 3 if String(h.st) == "flee" else 1
			if (h.path as Array).is_empty():
				_arrived(h)
			else:
				var to: Vector2 = h.path[0]
				# the gate shut in front of it: stays this side
				if not gate and _through_gate(p, to):
					h.path = []
					h.st = "idle"
					h.t = 1.0
					return
				var d := to - p
				var step := sp * dt
				if d.length() <= step:
					p = to
					(h.path as Array).pop_front()
				else:
					p += d / d.length() * step
				_face(h, d, dt)
				h.x = p.x
				h.z = p.y
			if String(h.st) == "flee" and float(h.t) <= 0.0:
				h.path = []
				h.st = "idle"
				h.t = 0.5
		"hop":
			# up into a nest box (or down out of it), wings going
			h.anim = 3
			var k := int(h.nest)
			var up := Vector3(NEST_X, NEST_Y, NEST_Z + k * NEST_DZ)
			var dn := Vector3(NEST_X - 0.62, 0.0, NEST_Z + k * NEST_DZ)
			var going_up := float(h.lay) >= LAY_T
			var a: Vector3 = dn if going_up else up
			var b: Vector3 = up if going_up else dn
			var f := clampf(1.0 - float(h.t) / 0.5, 0.0, 1.0)
			var at := a.lerp(b, f)
			at.y += sin(f * PI) * 0.25
			h.x = at.x
			h.y = at.y
			h.z = at.z
			h.yaw = -PI * 0.5 if going_up else PI * 0.5
			if float(h.t) <= 0.0:
				if going_up:
					h.st = "sit"
					h.t = 5.0
				else:
					h.st = "idle"
					h.nest = -1
					h.t = 1.0
		"sit":
			h.anim = 4
			if float(h.t) <= 0.0:
				var k2 := int(h.nest)
				if k2 >= 0 and k2 < nests.size() and (nests[k2] as Array).size() < NEST_EGGS:
					(nests[k2] as Array).append(0.0)
					_sound("egg_song", Vector3(NEST_X, 0.8, NEST_Z + k2 * NEST_DZ))
					_changed()
				h.lay = 0.0
				h.st = "hop"
				h.t = 0.5
	if not String(h.st) in ["hop", "sit"]:
		var gy := _ground_y(float(h.x), float(h.z))
		h.y = lerpf(float(h.y), gy, minf(1.0, dt * 10.0))

# what it does next: eat if it's hungry and there's feed, lay if it's ready and a nest has room, else wander about
func _next(h: Dictionary) -> void:
	var adult := float(h.age) >= 1.0
	var p := Vector2(float(h.x), float(h.z))
	var r := region_of(p)
	if float(h.full) < 0.6 and food >= 1.0 and _reach(r, COOP):
		h.path = _route(p, Vector2(FEEDER.x + 0.5, FEEDER.z))
		h.st = "eat"
		return
	if adult and float(h.lay) >= LAY_T and _reach(r, COOP):
		var k := _free_nest()
		if k >= 0:
			h.nest = k
			h.path = _route(p, Vector2(NEST_X - 0.62, NEST_Z + k * NEST_DZ))
			h.st = "lay"
			return
	if randf() < 0.45:
		h.st = "peck"
		h.t = randf_range(1.0, 4.0)
		return
	# somewhere else: mostly where it is; out into the run, back in; the yard when the gate's open
	var to_r := r
	var roll := randf()
	if r == COOP and roll < 0.5:
		to_r = PEN
	elif r == PEN and roll < 0.15:
		to_r = COOP
	elif r == PEN and gate and roll < 0.5:
		to_r = YARD
	elif r == YARD and (not gate or roll < 0.2):
		to_r = YARD if not gate else PEN
	h.path = _route(p, _somewhere(to_r))
	h.st = "walk"
	if randf() < 0.3:
		_sound("peep" if not adult else "cluck", Vector3(p.x, 0.3, p.y))

func _arrived(h: Dictionary) -> void:
	match String(h.st):
		"eat":
			_face(h, Vector2(-1, 0), 1.0)
			if food >= 1.0:
				food -= 1.0
				h.full = minf(1.0, float(h.full) + EAT)
				_changed()
			h.st = "peck"
			h.t = 3.0
		"lay":
			var k := int(h.nest)
			if k >= 0 and k < nest_count() and (nests[k] as Array).size() < NEST_EGGS and not _nest_busy(k, h):
				h.st = "hop"
				h.t = 0.5
			else:
				h.nest = -1
				h.st = "idle"
				h.t = 0.5
		_:
			h.st = "idle"
			h.t = randf_range(0.5, 2.5)

func _face(h: Dictionary, d: Vector2, dt: float) -> void:
	if d.length() < 0.001:
		return
	var want := atan2(-d.x, -d.y)
	h.yaw = lerp_angle(float(h.yaw), want, minf(1.0, dt * 10.0))

func _free_nest() -> int:
	var best := -1
	for k in nest_count():
		if (nests[k] as Array).size() < NEST_EGGS and not _nest_busy(k, null):
			if best < 0 or (nests[k] as Array).size() < (nests[best] as Array).size():
				best = k
	return best

func _nest_busy(k: int, me) -> bool:
	for o in hens:
		if o != me and int(o.nest) == k and String(o.st) in ["hop", "sit", "lay"]:
			return true
	return false

# can it get from region a to b now (the yard only with the gate open)
func _reach(a: int, b: int) -> bool:
	if a == b:
		return true
	if a == YARD or b == YARD:
		return gate
	return a != NONE and b != NONE

func _through_gate(a: Vector2, b: Vector2) -> bool:
	return (a.x < GATE_X) != (b.x < GATE_X) and absf(a.y - 30.5) < 2.0

## The way from a to b: through the coop's door, the gate, round the run's corner (straight lines between).
func _route(a: Vector2, b: Vector2) -> Array:
	var ra := region_of(a)
	var rb := region_of(b)
	var pts := []
	var chain := [ra]
	if ra != rb:
		if ra == COOP or rb == COOP:
			chain = [ra, PEN, rb] if ra != PEN and rb != PEN else [ra, rb]
		else:
			chain = [ra, rb]
	for i in range(1, chain.size()):
		var x: int = chain[i - 1]
		var y: int = chain[i]
		if x == COOP and y == PEN:
			pts.append_array([DOOR_IN, DOOR_OUT])
		elif x == PEN and y == COOP:
			pts.append_array([DOOR_OUT, DOOR_IN])
		elif x == PEN and y == YARD:
			pts.append_array([GATE_PEN, GATE_YARD])
		elif x == YARD and y == PEN:
			pts.append_array([GATE_YARD, GATE_PEN])
	pts.append(b)
	# round the coop's corner where a straight line through the run would cut through it
	var out := []
	var from := a
	for q: Vector2 in pts:
		if region_of(from) != COOP and region_of(q) != COOP and _cuts_coop(from, q):
			out.append(CORNER)
		out.append(q)
		from = q
	return out

func _cuts_coop(a: Vector2, b: Vector2) -> bool:
	var box := Rect2(COOP_X0 - 0.3, COOP_Z0 - 0.3, COOP_X1 - COOP_X0 + 0.6, COOP_Z1 - COOP_Z0 + 0.6)
	for i in range(1, 12):
		if box.has_point(a.lerp(b, i / 12.0)):
			return true
	return false

## Somewhere to wander to in a region (clear of the coop's things, the yard's props).
func _somewhere(r: int) -> Vector2:
	for tries in 20:
		var p: Vector2
		match r:
			COOP:
				p = Vector2(randf_range(28.2, 30.5), randf_range(35.2, 39.5))
			PEN:
				p = Vector2(randf_range(23.2, 31.1), randf_range(23.0, 39.5))
				if p.x > COOP_X0 - 0.5 and p.y > COOP_Z0 - 0.5:
					continue
			_:
				p = Vector2(randf_range(6.2, 21.4), randf_range(25.0, 37.4))
		return p
	return Vector2(25.0, 28.0)

func _ground_y(x: float, z: float) -> float:
	var g: VoxelTerrain = yard.ground
	var p := Vector3(x, 0, z)
	if not g.contains(p):
		return 0.0
	var c := g.cell_of(p)
	for y in range(VoxelTerrain.NY - 1, 0, -1):
		if g.at(c.x, y, c.z) != VoxelTerrain.AIR:
			return g.origin.y + (y + 1) * VoxelTerrain.CELL
	return g.origin.y

func _players() -> Array:
	var out := [arena.player.global_position]
	if arena.net and arena.net.linked and is_instance_valid(arena.net._o_body):
		out.append(arena.net._o_body.global_position)
	return out

# a little pile of poo where a hen was (the same cubes in both games: the seed)
func _poo(at: Vector3, seed: int) -> void:
	# (not in the gateway's sliver between the yard's cubes and the run's: they'd land in the arena's corner)
	if at.x > VoxelYard.X1 - 0.08 and at.x < X0 + 0.08:
		at.x = (VoxelYard.X1 - 0.08) if at.x < GATE_X else (X0 + 0.08)
	arena.debris.plop(at + Vector3(0, 0.1, 0), POO, POO_CUBES, seed)
	_msg(["poo", at, seed])

func _sound(name: String, at: Vector3) -> void:
	arena.sound.play(name, at, -8.0 if name != "egg_song" else -4.0)
	_msg(["snd", name, at])

# ---------------------------------------------------------------- what a player does (the arena calls these)

## What the look lands on (within reach): ["gate" / "feeder" / "sacks" / "sign" / "nest<k>" / "hen<id>", distance];
## ["", INF] for nothing.
func pick(eye: Vector3, dir: Vector3, reach := 2.6) -> Array:
	var boxes := {}
	if _gate_a < 0.5:
		boxes["gate"] = AABB(Vector3(GATE_X - 0.25, 0, GATE_Z0 - 0.05), Vector3(0.5, 1.3, GATE_Z1 - GATE_Z0 + 0.1))
	else:
		boxes["gate"] = AABB(Vector3(GATE_X, 0, GATE_Z0 - 0.25), Vector3(GATE_Z1 - GATE_Z0, 1.3, 0.5))
	boxes["feeder"] = AABB(FEEDER + Vector3(-0.35, 0, -0.35), Vector3(0.7, 0.8, 0.7))
	boxes["sacks"] = AABB(SACKS + Vector3(-0.5, 0, -0.35), Vector3(0.9, 0.9, 0.7))
	boxes["sign"] = AABB(SIGN + Vector3(-0.45, 1.1, -0.15), Vector3(0.9, 0.7, 0.3))
	for k in nest_count():
		boxes["nest%d" % k] = AABB(Vector3(NEST_X - 0.3, NEST_Y - 0.1, NEST_Z + k * NEST_DZ - 0.3), Vector3(0.6, 0.5, 0.6))
	for h in hens:
		var s := 0.4 if float(h.age) >= 1.0 else 0.22
		boxes["hen%d" % int(h.id)] = AABB(Vector3(float(h.x) - s * 0.5, float(h.y), float(h.z) - s * 0.5), Vector3(s, s * 1.2, s))
	for c in carcasses:
		var s2 := 0.6 if not bool(c.chick) else 0.36
		boxes["carcass%d" % int(c.id)] = AABB(Vector3(float(c.x) - s2 * 0.5, float(c.y) - 0.05, float(c.z) - s2 * 0.5), Vector3(s2, 0.3, s2))
	var best := ""
	var bd := INF
	for k in boxes:
		var hit = (boxes[k] as AABB).intersects_ray(eye, dir)
		if hit == null and (boxes[k] as AABB).has_point(eye):
			hit = eye
		if hit != null:
			var d := (hit as Vector3).distance_to(eye)
			if d <= reach and d < bd:
				bd = d
				best = k
	return [best, bd]

## What it says, looking at what pick found.
func line(tag: String) -> String:
	var inv: VoxelInventory = arena.inv
	if tag == "gate":
		return "E  shut the gate (keep them in the run)" if gate else "E  open the gate (the chickens roam the yard)"
	if tag == "feeder":
		var s := "Feeder: %d of %d feed" % [int(food), FEEDER_MAX]
		var have := []
		for id in FEEDS:
			if inv.count(id) > 0:
				have.append("%d %s" % [inv.count(id), VoxelItems.name_of(id).to_lower()])
		if not have.is_empty() and food < FEEDER_MAX - 0.5:
			return s + "     E  put in " + ", ".join(have)
		return s + ("  (buy grain at the sacks; worms do too)" if have.is_empty() else "  (full)")
	if tag == "sacks":
		return ("E  buy %d grain: $%d  (you've $%d)" if arena.cash >= GRAIN_COST else "Grain: %d for $%d (you've $%d: kills pay)") % [GRAIN_BUY, GRAIN_COST, arena.cash]
	if tag == "sign":
		var s2 := "Coop: %d of %d chickens, %d nest boxes" % [hens.size(), cap(), nest_count()]
		if level + 1 >= LEVELS.size():
			return s2 + " (as big as it gets)"
		var nx: Dictionary = LEVELS[level + 1]
		var need := ["$%d (%d)" % [int(nx.cash), arena.cash]]
		for id in nx.cost:
			need.append("%d %s (%d)" % [int(nx.cost[id]), VoxelItems.name_of(id).to_lower(), inv.count(id)])
		return s2 + ("     E  " if _can_upgrade() else "     ") + "upgrade to %d chickens: " % int(nx.cap) + ", ".join(need)
	if tag.begins_with("nest"):
		var k := int(tag.trim_prefix("nest"))
		var eggs: Array = nests[k]
		if eggs.is_empty():
			return "Nest box: empty"
		var most := 0.0
		for e in eggs:
			most = maxf(most, float(e))
		var s3 := "Nest box: %d egg%s" % [eggs.size(), "" if eggs.size() == 1 else "s"]
		s3 += (" (coop full: no room to hatch)" if most >= 1.0 else " (left, they hatch: %d%%)" % int(most * 100.0))
		return s3 + "     E  collect"
	if tag.begins_with("carcass"):
		var c = _carcass_by(int(tag.trim_prefix("carcass")))
		if c == null:
			return ""
		return "E  pick up the %s carcass" % ("chick's" if bool(c.chick) else "chicken")
	if tag.begins_with("hen"):
		var h = _hen_by(int(tag.trim_prefix("hen")))
		if h == null:
			return ""
		var full := float(h.full)
		var mood := "well fed" if full > 0.7 else ("peckish" if full > 0.25 else "hungry: fill the feeder")
		if float(h.age) < 1.0:
			return "Chick: growing up (%d%%), %s" % [int(float(h.age) * 100.0), mood]
		var lay := ", laying soon" if float(h.lay) > LAY_T * 0.8 else (", not laying" if full < 0.25 else "")
		var hurt := ", hurt" if int(h.get("hurt", 0)) > 0 else ""
		return "Hen: %s%s%s" % [mood, lay, hurt]
	return ""

## E on what pick found.
func use(tag: String) -> void:
	var inv: VoxelInventory = arena.inv
	if tag == "gate":
		set_gate(not gate)
	elif tag == "feeder":
		var room := FEEDER_MAX - food
		var put := {}
		var add := 0.0
		for id in FEEDS:
			var each := float(FEEDS[id])
			var n := mini(inv.count(id), int(floor(room / each)))
			if n > 0:
				inv.remove(id, n)
				put[id] = n
				add += n * each
				room -= n * each
		if add <= 0.0:
			arena.say("Feeder: %d of %d (buy grain at the sacks)" % [int(food), FEEDER_MAX], 2.0)
			return
		arena.sound.play("grain_pour", Vector3.INF, -6.0)
		arena.say("Feeder: %d of %d" % [mini(FEEDER_MAX, int(food + add)), FEEDER_MAX], 1.5)
		if _is_guest():
			_msg(["feed", put])
			food = minf(FEEDER_MAX, food + add)       # (shown at once; the host's is the real one)
		else:
			food = minf(FEEDER_MAX, food + add)
			_changed()
	elif tag == "sacks":
		if arena.cash < GRAIN_COST:
			arena.say("Not enough cash: $%d (kills pay: a grunt $1, a batter $3, a brute $5)" % arena.cash, 2.0)
			return
		arena.cash -= GRAIN_COST
		arena.receive({"id": "grain", "n": GRAIN_BUY}, "inv")
		arena.stash._dirty = true
		arena.sound.play("item_pick", Vector3.INF, -4.0)
		arena.say("+%d grain: E at the feeder puts it in ($%d left)" % [GRAIN_BUY, arena.cash], 2.0)
	elif tag == "sign":
		upgrade()
	elif tag.begins_with("nest"):
		collect(int(tag.trim_prefix("nest")))
	elif tag.begins_with("carcass"):
		take_carcass(int(tag.trim_prefix("carcass")))

func set_gate(open: bool) -> void:
	if open == gate:
		return
	gate = open
	arena.sound.play("gate_creak", Vector3(GATE_X, 1.0, (GATE_Z0 + GATE_Z1) * 0.5), -6.0, 1.0 if open else 0.85)
	if _is_guest():
		_msg(["gate", open])
	else:
		_changed()

## E at a nest box: its eggs into this player's backpack.
func collect(k: int) -> int:
	var eggs: Array = nests[k]
	var n := eggs.size()
	if n == 0:
		return 0
	arena.sound.play("egg_pick", Vector3.INF, -4.0)
	arena.say("+%d egg%s: sell them at the buyer, or H eats one (health)" % [n, "" if n == 1 else "s"], 2.5)
	if _is_guest():
		_msg(["eggs", k])
		eggs.clear()
		return n
	eggs.clear()
	arena.receive({"id": "egg", "n": n}, "inv")
	_changed()
	return n

func _can_upgrade() -> bool:
	if level + 1 >= LEVELS.size():
		return false
	var nx: Dictionary = LEVELS[level + 1]
	if arena.cash < int(nx.cash):
		return false
	for id in nx.cost:
		if arena.inv.count(id) < int(nx.cost[id]):
			return false
	return true

## E at the coop sign: the next level, paid out of this player's cash and backpack.
func upgrade() -> bool:
	if level + 1 >= LEVELS.size():
		return false
	if not _can_upgrade():
		arena.say("Not enough: " + line("sign").get_slice("upgrade", 1).strip_edges(), 2.5)
		return false
	var nx: Dictionary = LEVELS[level + 1]
	arena.cash -= int(nx.cash)
	for id in nx.cost:
		arena.inv.remove(id, int(nx.cost[id]))
	arena.stash._dirty = true
	arena.sound.play("hammer_hit", Vector3.INF, -6.0)
	arena.say("Coop upgraded: room for %d chickens, %d nest boxes" % [int(nx.cap), int(nx.nests)], 3.0)
	if _is_guest():
		_msg(["up", level + 1])
	level += 1
	_changed()
	return true

func _hen_by(id: int):
	for h in hens:
		if int(h.id) == id:
			return h
	return null

## H: an egg eaten for health (false: none, or not hurt).
func eat_egg() -> bool:
	if arena.inv.count("egg") < 1 or arena.player_hp >= VoxelArena.HP_MAX:
		return false
	arena.inv.remove("egg", 1)
	arena.player_hp = minf(VoxelArena.HP_MAX, arena.player_hp + EGG_HP)
	return true

## Items for VoxelItems: the egg, the grain, the poo (cubes the vacuum takes).
static func items() -> Dictionary:
	return {
		"egg": {"name": "Egg", "col": Color8(236, 222, 196), "stack": 99,
			"desc": "From the coop's nest boxes. Sells for $%d at the buyer; H eats one (+%d health)." % [EGG_PRICE, int(EGG_HP)]},
		"grain": {"name": "Grain", "col": Color8(214, 178, 96), "stack": 999, "desc": "Chicken feed. E at the coop's feeder puts it in."},
		"poo": {"name": "Chicken poo", "col": POO[0], "stack": 9999, "cubes": POO,
			"desc": "Vacuumed up in the run. Feeds a plant (%d at a time) or the worm farm." % VoxelFarm.POO_FEED},
		"chicken_carcass": {"name": "Chicken carcass", "col": VoxelChicken.PLUCK[0], "stack": 20,
			"desc": "A plucked chicken. Sells for $%d at the buyer, or the shredder makes blood and bone of it." % CARCASS_PRICE},
	}

# ---------------------------------------------------------------- killing them (out in the yard)

## Out in the yard (the gate was open): the only place one can be hurt.
static func killable(p: Vector2) -> bool:
	return region_of(p) == YARD

## The local player's weapon or tool w just swung or fired (VoxelArena._shoot on a press; held, again every
## STRIKE[3] s for the ones that keep going): the chicken it lands on, if any, hit. Returns that one's id, or -1.
func attack(w, held := false) -> int:
	var id: String = w.weapon_id
	if not STRIKE.has(id) or _strike_t.has(id):
		return -1
	var s: Array = STRIKE[id]
	if held and not bool(s[4]):
		return -1
	var h = target(w.eye(), w.look(), float(s[0]), float(s[1]), w.top_down(), w.shooter)
	if h == null:
		return -1
	_strike_t[id] = float(s[3])
	strike(int(h.id), int(s[2]), w.shooter.player.global_position)
	return int(h.id)

## The chicken a blow from eye along dir lands on (the nearest in reach, within cone degrees of the look, or right
## on its line; top-down: level, or where the mouse is), or null. A shot past RANGED metres doesn't go through walls.
func target(eye: Vector3, dir: Vector3, reach: float, cone: float, top_down := false, shooter = null):
	var best = null
	var bd := INF
	var mouse := Vector3.INF
	if top_down and shooter != null:
		mouse = shooter.mouse_floor()
	for h in hens:
		var adult := float(h.age) >= 1.0
		var c := Vector3(float(h.x), float(h.y) + (0.2 if adult else 0.1), float(h.z))
		var d: float
		var ok := false
		if top_down:
			var v2 := Vector2(c.x - eye.x, c.z - eye.z)
			d = v2.length()
			if d > reach:
				continue
			var f2 := Vector2(dir.x, dir.z)
			ok = d < 0.35 or (f2.length() > 0.01 and rad_to_deg(absf(v2.angle_to(f2))) <= cone)
			if not ok and mouse != Vector3.INF:
				ok = Vector2(mouse.x - c.x, mouse.z - c.z).length() < 0.6
		else:
			var v := c - eye
			d = v.length()
			if d > reach:
				continue
			var along := v.dot(dir)
			ok = along > 0.0 and (rad_to_deg(v.angle_to(dir)) <= cone or (v - dir * along).length() < (0.3 if adult else 0.2))
		if not ok or d >= bd:
			continue
		if reach > RANGED and is_inside_tree():
			var q := PhysicsRayQueryParameters3D.create(eye, c)
			q.collision_mask = 1
			if shooter != null:
				q.exclude = shooter.exclude()
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				continue
		best = h
		bd = d
	return best

## A blow of dmg on chicken id from a player standing at from. In the yard it hurts (kills at HP, a chick at one);
## in the run or the coop it only sends it flapping off. A guest's goes to the host.
func strike(id: int, dmg: int, from: Vector3) -> void:
	var h = _hen_by(id)
	if h == null:
		return
	var p := Vector2(float(h.x), float(h.z))
	if not killable(p) and not _told_safe:
		_told_safe = true
		arena.say("Not in the coop: they're safe in there. Open the gate and let them out into the yard first", 3.5)
	if _is_guest():
		_msg(["hit", id, dmg, from])
		if killable(p):
			_hit_fx(Vector3(p.x, float(h.y) + 0.2, p.y), int(h.c), float(h.age) < 1.0, false)
		return
	_hurt(h, dmg, from, 0)

## A grenade's blast or a fire patch at p (VoxelArena.hurt_players_near: the host's or alone): every chicken out in
## the yard within r hurt (a blast kills, a patch of fire takes a blow at a time).
func blast(p: Vector3, r: float, amount: float) -> void:
	if _is_guest():
		return
	for h in hens.duplicate():
		var c := Vector3(float(h.x), float(h.y) + 0.2, float(h.z))
		if c.distance_to(p) < r and killable(Vector2(c.x, c.z)):
			_hurt(h, HP if amount >= 20.0 else 1, p, -1)

# (the host's, or alone) the blow landing: by is who struck (0 the host, 1 the guest, -1 a blast)
func _hurt(h: Dictionary, dmg: int, from: Vector3, by: int) -> void:
	var p := Vector2(float(h.x), float(h.z))
	var away := p - Vector2(from.x, from.z)
	if not killable(p):
		_flee(h, away, 1.6)
		_sound("flap", Vector3(p.x, 0.3, p.y))
		return
	var now := Time.get_ticks_msec()
	if now - int(h.get("hit_ms", 0)) < 150:
		return                  # (one blow, one hit: a blast and its fire, a chainsaw's bites)
	h.hit_ms = now
	h.hurt = int(h.get("hurt", 0)) + maxi(1, dmg)
	var chick := float(h.age) < 1.0
	var dead := int(h.hurt) >= (1 if chick else HP)
	var at := Vector3(p.x, float(h.y) + 0.2, p.y)
	_hit_fx(at, int(h.c), chick, dead)
	_msg(["fx", at, int(h.c), chick, dead, by])
	if dead:
		_die(h, by)
	else:
		_flee(h, away, 3.5)
	_changed()

# off it runs, flapping, away from where the blow came (staying where it is: the yard, the run)
func _flee(h: Dictionary, away: Vector2, dist: float) -> void:
	if String(h.st) in ["hop", "sit"]:
		return
	var p := Vector2(float(h.x), float(h.z))
	var a := away.normalized() if away.length() > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0]:
		var to: Vector2 = p + a.rotated(turn) * dist
		if region_of(to) == region_of(p) and not _through_gate(p, to):
			h.path = [to]
			h.st = "flee"
			h.t = dist / RUN + 0.4
			h.nest = -1
			return

# dead: a carcass where it fell (its place in the coop free)
func _die(h: Dictionary, by: int) -> void:
	hens.erase(h)
	carcasses.append({"id": int(h.id), "x": float(h.x), "y": float(h.y), "z": float(h.z), "yaw": float(h.yaw), "c": int(h.c),
		"chick": float(h.age) < 1.0})
	while carcasses.size() > CARCASS_MAX:
		carcasses.pop_front()
	if by == 0 or (by == -1 and VoxelYard.in_yard(arena.player.global_position)):
		arena.say("Chicken killed: E picks up the carcass", 2.5)

# a blow landing, seen and heard: feathers, a squawk (killed: a burst of them, the last squawk)
func _hit_fx(at: Vector3, coat: int, chick: bool, dead: bool) -> void:
	var cols: Array = VoxelChicken.CHICK if chick else VoxelChicken.COATS[clampi(coat, 0, VoxelChicken.COATS.size() - 1)]
	var gy := _ground_y(at.x, at.z) if yard else 0.0
	for i in (22 if dead else 7) / (2 if chick else 1):
		if _feathers.size() >= FEATHERS_MAX:
			_feathers.pop_front()
		var v := Vector3(randf_range(-1.0, 1.0), randf_range(0.8, 2.4), randf_range(-1.0, 1.0)) * (1.4 if dead else 1.0)
		_feathers.append([at + Vector3(randf_range(-0.08, 0.08), randf_range(-0.05, 0.1), randf_range(-0.08, 0.08)), v,
			randf_range(7.0, 11.0), randf() * TAU, (cols[0] as Color).lerp(cols[1], randf()), gy, randf() * TAU])
	if dead:
		arena.sound.play("death_squawk", at, -3.0, 1.35 if chick else 1.0)
	else:
		arena.sound.play("squawk", at, -3.0, 1.4 if chick else 1.0)
	arena.sound.play("flap", at, -6.0)

func _feathers_step(dt: float) -> void:
	if _feather_mm == null:
		return
	var i := 0
	while i < _feathers.size():
		var f: Array = _feathers[i]
		f[2] = float(f[2]) - dt
		if float(f[2]) <= 0.0:
			_feathers.remove_at(i)
			continue
		var pos: Vector3 = f[0]
		if pos.y > float(f[5]) + 0.006:
			var v: Vector3 = f[1]
			v.y -= 4.0 * dt
			v *= maxf(0.0, 1.0 - 3.2 * dt)             # (light: they drift down)
			f[6] = float(f[6]) + dt * 5.0
			pos += (v + Vector3(sin(float(f[6])) * 0.35, 0.0, cos(float(f[6]) * 0.7) * 0.25)) * dt
			pos.y = maxf(pos.y, float(f[5]) + 0.006)
			f[1] = v
			f[3] = float(f[3]) + dt * 3.0
			f[0] = pos
		i += 1
	_feather_mm.visible_instance_count = _feathers.size()
	for k in _feathers.size():
		var f: Array = _feathers[k]
		var flying := (f[0] as Vector3).y > float(f[5]) + 0.007
		var b := Basis(Vector3.UP, float(f[3])) * Basis(Vector3.RIGHT, sin(float(f[6])) * 0.6 if flying else 0.0)
		_feather_mm.set_instance_transform(k, Transform3D(b, f[0]))
		_feather_mm.set_instance_color(k, f[4])

## Top-down: the carcass at the player's feet (within r metres), "carcass<id>" for use(); "" none.
func carcass_near(p: Vector3, r := 1.0) -> String:
	var best := ""
	var bd := r
	for c in carcasses:
		var d := Vector2(float(c.x) - p.x, float(c.z) - p.z).length()
		if d < bd:
			bd = d
			best = "carcass%d" % int(c.id)
	return best

## E at a carcass: into this player's backpack as a chicken carcass (a guest's: asked of the host, given back).
func take_carcass(id: int) -> bool:
	var c = _carcass_by(id)
	if c == null:
		return false
	carcasses.erase(c)
	arena.sound.play("item_pick", Vector3.INF, -4.0, 0.8)
	arena.say("+1 chicken carcass: sell it at the buyer ($%d), or the shredder makes blood and bone" % CARCASS_PRICE, 2.5)
	if _is_guest():
		_msg(["take", id])
		return true
	arena.receive({"id": "chicken_carcass", "n": 1}, "inv")
	_msg(["said", "Your mate picked up the chicken carcass"])
	_changed()
	return true

func _carcass_by(id: int):
	for c in carcasses:
		if int(c.id) == id:
			return c
	return null

# ---------------------------------------------------------------- co-op

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_chickens(m)

# (the host's or alone) something changed: saved; the guest told soon
func _changed() -> void:
	arena.stash._dirty = true
	_dirty = true

func _send_all() -> void:
	_msg(["all", to_data(true)])

func send_all() -> void:
	if _is_host():
		_send_all()

func _positions() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for h in hens:
		out.append_array([float(h.id), float(h.x), float(h.y), float(h.z), float(h.yaw), float(h.anim)])
	return out

func on_net(m: Array) -> void:
	var host := _is_host()
	match String(m[0]):
		"all":
			if _is_guest():
				if _own == null:
					_own = to_data()
				from_data(m[1])
		"pos":
			if _is_guest():
				var d: PackedFloat32Array = m[1]
				for i in range(0, d.size() - 5, 6):
					var h = _hen_by(int(d[i]))
					if h != null:
						h.x = d[i + 1]
						h.y = d[i + 2]
						h.z = d[i + 3]
						h.yaw = d[i + 4]
						h.anim = int(d[i + 5])
		"poo":
			if _is_guest():
				arena.debris.plop(m[1] + Vector3(0, 0.1, 0), POO, POO_CUBES, int(m[2]))
		"snd":
			if _is_guest():
				arena.sound.play(String(m[1]), m[2], -8.0 if String(m[1]) != "egg_song" else -4.0)
		"gate":
			if host:
				gate = bool(m[1])
				arena.sound.play("gate_creak", Vector3(GATE_X, 1.0, (GATE_Z0 + GATE_Z1) * 0.5), -6.0)
				_changed()
		"feed":
			if host and typeof(m[1]) == TYPE_DICTIONARY:
				var room := FEEDER_MAX - food
				for id in m[1]:
					if not FEEDS.has(id):
						continue
					var n := clampi(int(m[1][id]), 0, 999)
					var each := float(FEEDS[id])
					var keep := mini(n, int(floor(room / each)))
					food += keep * each
					room -= keep * each
					if n > keep:
						_msg(["give", {"id": id, "n": n - keep}])
				_changed()
		"eggs":
			var k := int(m[1])
			if host and k >= 0 and k < nests.size():
				var n := (nests[k] as Array).size()
				(nests[k] as Array).clear()
				if n > 0:
					_msg(["give", {"id": "egg", "n": n}])
				_changed()
		"up":
			if host:
				var to := int(m[1])
				if to == level + 1 and to < LEVELS.size():
					level = to
					_changed()
				# (already that level: theirs was paid for nothing; rare enough to let be)
		"hit":
			if host:
				var h = _hen_by(int(m[1]))
				if h != null and typeof(m[3]) == TYPE_VECTOR3:
					_hurt(h, clampi(int(m[2]), 1, HP), m[3], 1)
		"fx":
			# (the guest's own blow it saw at once; a kill it hears of here)
			if _is_guest() and typeof(m[1]) == TYPE_VECTOR3 and (bool(m[4]) or int(m[5]) != 1):
				_hit_fx(m[1], int(m[2]), bool(m[3]), bool(m[4]))
			if _is_guest() and bool(m[4]) and int(m[5]) == 1:
				arena.say("Chicken killed: E picks up the carcass", 2.5)
		"take":
			if host:
				var c = _carcass_by(int(m[1]))
				if c != null:
					carcasses.erase(c)
					_msg(["give", {"id": "chicken_carcass", "n": 1}])
					arena.say("Your mate picked up the chicken carcass", 2.0)
					_changed()
				else:
					_msg(["said", "Too late: your mate picked that one up"])
		"said":
			arena.say(String(m[1]), 2.0)
		"give":
			var g: Dictionary = m[1]
			if VoxelItems.has(String(g.get("id", ""))) and int(g.get("n", 0)) > 0:
				arena.receive({"id": String(g.id), "n": int(g.n)}, "inv")

# ---------------------------------------------------------------- saving

## The chickens as plain data (saving; with live, sending: what they're doing too).
func to_data(live := false) -> Dictionary:
	var hs := []
	for h in hens:
		var d := {"id": int(h.id), "x": float(h.x), "z": float(h.z), "c": int(h.c), "age": float(h.age), "full": float(h.full),
			"lay": float(h.lay)}
		if live:
			d["y"] = float(h.y)
			d["yaw"] = float(h.yaw)
			d["anim"] = int(h.anim)
		hs.append(d)
	var cs := []
	for c in carcasses:
		cs.append({"id": int(c.id), "x": float(c.x), "y": float(c.y), "z": float(c.z), "yaw": float(c.yaw), "c": int(c.c), "chick": bool(c.chick)})
	return {"level": level, "gate": gate, "food": food, "nests": nests.duplicate(true), "hens": hs, "carcasses": cs, "next": _next_id}

func from_data(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	level = clampi(int(d.get("level", 0)), 0, LEVELS.size() - 1)
	gate = bool(d.get("gate", false))
	food = clampf(float(d.get("food", 0.0)), 0.0, FEEDER_MAX)
	nests = []
	var ns = d.get("nests", [])
	for k in LEVELS[-1].nests:
		var eggs := []
		if typeof(ns) == TYPE_ARRAY and k < ns.size() and typeof(ns[k]) == TYPE_ARRAY:
			for e in ns[k]:
				if eggs.size() < NEST_EGGS:
					eggs.append(clampf(float(e), 0.0, 1.0))
		nests.append(eggs)
	hens = []
	var hs = d.get("hens", [])
	if typeof(hs) == TYPE_ARRAY:
		for o in hs:
			if typeof(o) != TYPE_DICTIONARY or hens.size() >= LEVELS[-1].cap:
				continue
			var p := Vector2(float(o.get("x", 29.0)), float(o.get("z", 37.0)))
			if region_of(p) == NONE:
				p = Vector2(29.0, 37.0)
			hens.append({"id": int(o.get("id", hens.size() + 1)), "x": p.x, "y": float(o.get("y", 0.0)), "z": p.y,
				"yaw": float(o.get("yaw", randf() * TAU)), "c": clampi(int(o.get("c", 0)), 0, VoxelChicken.COATS.size() - 1),
				"age": clampf(float(o.get("age", 1.0)), 0.0, 1.0), "full": clampf(float(o.get("full", 0.5)), 0.0, 1.0),
				"lay": clampf(float(o.get("lay", 0.0)), 0.0, LAY_T), "poo": randf() * POO_T, "st": "idle", "t": randf(),
				"path": [], "anim": int(o.get("anim", 0)), "nest": -1, "hurt": 0, "hit_ms": 0})
	carcasses = []
	var cs = d.get("carcasses", [])
	if typeof(cs) == TYPE_ARRAY:
		for o in cs:
			if typeof(o) != TYPE_DICTIONARY or carcasses.size() >= CARCASS_MAX:
				continue
			carcasses.append({"id": int(o.get("id", 0)), "x": float(o.get("x", 15.0)), "y": float(o.get("y", 0.0)), "z": float(o.get("z", 30.0)),
				"yaw": float(o.get("yaw", 0.0)), "c": clampi(int(o.get("c", 0)), 0, VoxelChicken.COATS.size() - 1), "chick": bool(o.get("chick", false))})
	_next_id = maxi(int(d.get("next", 1)), 1)
	for h in hens:
		_next_id = maxi(_next_id, int(h.id) + 1)
	for c in carcasses:
		_next_id = maxi(_next_id, int(c.id) + 1)

## For the save file (a guest in someone's game: its own chickens).
func save_data() -> Dictionary:
	return _own if _own != null else to_data()

# ---------------------------------------------------------------- showing it

func _show(dt: float) -> void:
	var seen := {}
	for h in hens:
		var id := int(h.id)
		seen[id] = true
		var v: VoxelChicken = _views.get(id)
		var chick := float(h.age) < 1.0
		if v == null:
			v = VoxelChicken.new()
			add_child(v)
			v.build(int(h.c), chick)
			v.position = Vector3(float(h.x), float(h.y), float(h.z))
			_views[id] = v
		elif v.chick != chick or v.coat != int(h.c):      # (the same id can be another bird: the host's, then ours again)
			v.build(int(h.c), chick)
		var to := Vector3(float(h.x), float(h.y), float(h.z))
		if _is_guest():
			v.position = v.position.lerp(to, minf(1.0, dt * 12.0)) if v.position.distance_to(to) < 2.0 else to
			v.rotation.y = lerp_angle(v.rotation.y, float(h.yaw), minf(1.0, dt * 12.0))
		else:
			v.position = to
			v.rotation.y = float(h.yaw)
		v.anim = int(h.anim)
		if chick:
			v.scale = Vector3.ONE * (1.0 + float(h.age) * 0.6)
		else:
			v.scale = Vector3.ONE
	for id in _views.keys():
		if not seen.has(id):
			(_views[id] as Node).queue_free()
			_views.erase(id)
	# the carcasses lying where they fell
	var cseen := {}
	for c in carcasses:
		var cid := int(c.id)
		cseen[cid] = true
		var cv: Node3D = _carc_views.get(cid)
		if cv == null:
			cv = VoxelChicken.carcass(int(c.c), bool(c.chick), cid * 7919 + 13)
			add_child(cv)
			_carc_views[cid] = cv
		cv.position = Vector3(float(c.x), float(c.y), float(c.z))
		cv.rotation.y = float(c.yaw)
	for cid in _carc_views.keys():
		if not cseen.has(cid):
			(_carc_views[cid] as Node).queue_free()
			_carc_views.erase(cid)
	# the gate swinging, the nests' boxes and eggs, the feeder's feed, the sign, the roof (off from above, inside)
	_gate_a = move_toward(_gate_a, 1.0 if gate else 0.0, dt * 2.5)
	_gate_node.rotation.y = _gate_a * PI * 0.5
	for k in _nest_nodes.size():
		var nn: Array = _nest_nodes[k]
		(nn[0] as Node3D).visible = k < nest_count()
		(nn[2] as CollisionShape3D).disabled = k >= nest_count()       # (a hidden one's shelf isn't there to bump into)
		var eggs: Array = nests[k]
		for i in NEST_EGGS:
			var e: MeshInstance3D = nn[1][i]
			e.visible = i < eggs.size()
			if e.visible:
				var wob := float(eggs[i]) > 0.85
				e.rotation.z = sin(Time.get_ticks_msec() * 0.02 + i) * 0.25 if wob else 0.0
	_feed_mesh.visible = food >= 1.0
	_feed_mesh.scale.y = 0.4 + 1.2 * clampf(food / FEEDER_MAX, 0.0, 1.0)
	_feed_mesh.position = FEEDER + Vector3(0, 0.08 + 0.03 * _feed_mesh.scale.y, 0)
	_sign.text = "COOP\n%d / %d chickens" % [hens.size(), cap()]
	_roof.visible = not (arena.top_down and in_coop(arena.player.global_position))

# ---------------------------------------------------------------- building it

func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D = self, solid := true, show := true) -> Node3D:
	var n: Node3D = StaticBody3D.new() if solid else Node3D.new()
	n.position = at
	parent.add_child(n)
	if show:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = m
		n.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		n.add_child(cs)
	return n

# chicken wire: a see-through diamond mesh
func _wire_mat(len_m: float, h: float) -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 32:
		for w in 2:
			img.set_pixel((i + w) % 32, i, Color(0.72, 0.74, 0.76, 1))
			img.set_pixel((31 - i + w) % 32, i, Color(0.72, 0.74, 0.76, 1))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.6
	m.roughness = 0.4
	m.uv1_scale = Vector3(len_m / 0.12, h / 0.12, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

# a run of fence from a to b (along x or z): posts, rails, wire, a wall nothing gets through
func _fence(a: Vector2, b: Vector2) -> void:
	var post := _mat(Color8(110, 80, 50), 0.85)
	var d := b - a
	var len_m := d.length()
	var mid := (a + b) * 0.5
	var along_x := absf(d.x) > absf(d.y)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(len_m, FENCE_H - 0.1)
	q.mesh = qm
	q.material_override = _wire_mat(len_m, FENCE_H)
	q.position = Vector3(mid.x, FENCE_H * 0.5, mid.y)
	q.rotation.y = 0.0 if along_x else PI * 0.5
	add_child(q)
	_box(Vector3(len_m if along_x else 0.1, FENCE_H, 0.1 if along_x else len_m), Vector3(mid.x, FENCE_H * 0.5, mid.y), post, self, true, false)
	for y in [0.08, FENCE_H - 0.04]:
		_box(Vector3(len_m if along_x else 0.06, 0.08, 0.06 if along_x else len_m), Vector3(mid.x, y, mid.y), post, self, false)
	var n := maxi(1, int(ceil(len_m / 2.0)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_box(Vector3(0.12, FENCE_H + 0.1, 0.12), Vector3(p.x, (FENCE_H + 0.1) * 0.5, p.y), post, self, false)

func _build() -> void:
	# the feathers flying off hit hens: one MultiMesh
	_feather_mm = MultiMesh.new()
	_feather_mm.transform_format = MultiMesh.TRANSFORM_3D
	_feather_mm.use_colors = true
	_feather_mm.mesh = VoxelChicken.feather_mesh()
	_feather_mm.instance_count = FEATHERS_MAX
	_feather_mm.visible_instance_count = 0
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = _feather_mm
	fmi.material_override = VoxelChicken.feather_mat()
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)
	var grass := _mat(Color8(70, 112, 44), 0.95)
	var dirt := _mat(Color8(112, 84, 56), 1.0)
	# the run's ground, scratched bare in patches; under it a floor nothing falls through
	_box(Vector3(X1 - X0 + 0.1, 0.5, Z1 - Z0), Vector3((X0 + X1) * 0.5 - 0.05, -0.25, (Z0 + Z1) * 0.5), grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for i in 9:
		var pm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := rng.randf_range(0.6, 1.4)
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.01
		pm.mesh = cm
		pm.material_override = dirt
		pm.position = Vector3(rng.randf_range(23.5, 30.5), 0.006, rng.randf_range(23.5, 33.0))
		add_child(pm)
	# the fences: north, east, south (the yard's fence, with the gate, is the west)
	_fence(Vector2(GATE_X, Z0), Vector2(X1, Z0))
	_fence(Vector2(X1, Z0), Vector2(X1, Z1))
	_fence(Vector2(GATE_X, Z1), Vector2(X1, Z1))
	# the gate: a timber frame with wire, hinged at its north end, swinging into the run
	var wood := _mat(Color8(150, 112, 70), 0.85)
	_gate_node = AnimatableBody3D.new()
	(_gate_node as AnimatableBody3D).sync_to_physics = false
	_gate_node.position = Vector3(GATE_X, 0, GATE_Z0)
	add_child(_gate_node)
	var gl := GATE_Z1 - GATE_Z0
	for y in [0.1, 0.7, 1.3]:
		_box(Vector3(0.06, 0.08, gl), Vector3(0, y, gl * 0.5), wood, _gate_node, false)
	for z in [0.03, gl - 0.03]:
		_box(Vector3(0.07, 1.3, 0.07), Vector3(0, 0.7, z), wood, _gate_node, false)
	var diag := _box(Vector3(0.05, 1.45, 0.05), Vector3(0, 0.7, gl * 0.5), wood, _gate_node, false)
	diag.rotation.x = atan2(gl, 1.2)
	var gw := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(gl, 1.2)
	gw.mesh = gq
	gw.material_override = _wire_mat(gl, 1.2)
	gw.position = Vector3(0, 0.7, gl * 0.5)
	gw.rotation.y = PI * 0.5
	_gate_node.add_child(gw)
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(0.1, 1.4, gl)
	gcs.shape = gsh
	gcs.position = Vector3(0, 0.7, gl * 0.5)
	_gate_node.add_child(gcs)
	_coop()

func _coop() -> void:
	var plank := _mat(Color8(168, 120, 72), 0.85)
	var batten := _mat(Color8(126, 86, 50), 0.85)
	var iron := _mat(Color8(104, 112, 108), 0.6, 0.5)
	var straw := _mat(Color8(214, 186, 96), 1.0)
	var t := 0.1
	var cx := (COOP_X0 + COOP_X1) * 0.5
	var cz := (COOP_Z0 + COOP_Z1) * 0.5
	var w := COOP_X1 - COOP_X0
	var d := COOP_Z1 - COOP_Z0
	# the walls: west, east, south whole; the north with the doorway
	_box(Vector3(t, WALL_H, d), Vector3(COOP_X0, WALL_H * 0.5, cz), plank)
	_box(Vector3(t, WALL_H, d), Vector3(COOP_X1 - 0.06, WALL_H * 0.5, cz), plank)
	_box(Vector3(w, WALL_H, t), Vector3(cx, WALL_H * 0.5, COOP_Z1 - 0.06), plank)
	_box(Vector3(DOOR_X0 - COOP_X0, WALL_H, t), Vector3((COOP_X0 + DOOR_X0) * 0.5, WALL_H * 0.5, COOP_Z0), plank)
	_box(Vector3(COOP_X1 - DOOR_X1, WALL_H, t), Vector3((DOOR_X1 + COOP_X1) * 0.5, WALL_H * 0.5, COOP_Z0), plank)
	_box(Vector3(DOOR_X1 - DOOR_X0, WALL_H - DOOR_H, t), Vector3((DOOR_X0 + DOOR_X1) * 0.5, (DOOR_H + WALL_H) * 0.5, COOP_Z0), plank)
	# battens down the outside (boards), the door's frame
	var x := COOP_X0 + 0.3
	while x < COOP_X1 - 0.1:
		if x < DOOR_X0 - 0.05 or x > DOOR_X1 + 0.05:
			_box(Vector3(0.05, WALL_H, 0.03), Vector3(x, WALL_H * 0.5, COOP_Z0 - 0.065), batten, self, false)
		x += 0.45
	var z := COOP_Z0 + 0.3
	while z < COOP_Z1 - 0.1:
		_box(Vector3(0.03, WALL_H, 0.05), Vector3(COOP_X0 - 0.065, WALL_H * 0.5, z), batten, self, false)
		z += 0.45
	for fx in [DOOR_X0, DOOR_X1]:
		_box(Vector3(0.08, DOOR_H, 0.14), Vector3(fx, DOOR_H * 0.5, COOP_Z0), batten, self, false)
	_box(Vector3(DOOR_X1 - DOOR_X0 + 0.08, 0.08, 0.14), Vector3((DOOR_X0 + DOOR_X1) * 0.5, DOOR_H, COOP_Z0), batten, self, false)
	# the roof: corrugated iron, a little overhang, its ridges
	_roof = Node3D.new()
	add_child(_roof)
	_box(Vector3(w + 0.4, 0.05, d + 0.4), Vector3(cx, WALL_H + 0.03, cz), iron, _roof, true)
	var rx := COOP_X0 - 0.15
	while rx < COOP_X1 + 0.2:
		_box(Vector3(0.04, 0.03, d + 0.4), Vector3(rx, WALL_H + 0.065, cz), iron, _roof, false)
		rx += 0.16
	# the floor: boards under straw
	_box(Vector3(w - 0.12, 0.02, d - 0.12), Vector3(cx, 0.01, cz), straw, self, false)
	# a light inside (it's a shed)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, WALL_H - 0.25, cz + 0.6)
	lamp.light_color = Color8(255, 214, 160)
	lamp.light_energy = 1.4
	lamp.omni_range = 5.5
	lamp.shadow_enabled = false
	add_child(lamp)
	var bulb := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.06
	bsm.height = 0.12
	bulb.mesh = bsm
	var bmat := _mat(Color8(255, 236, 190))
	bmat.emission_enabled = true
	bmat.emission = Color8(255, 220, 160)
	bmat.emission_energy_multiplier = 3.0
	bulb.material_override = bmat
	bulb.position = lamp.position + Vector3(0, 0.05, 0)
	add_child(bulb)
	# the nest boxes along the east wall, on a shelf, straw in each; the eggs in them
	var egg_m := SphereMesh.new()
	egg_m.radius = 0.035
	egg_m.height = 0.09
	var egg_mat := _mat(Color8(236, 222, 196), 0.5)
	for k in int(LEVELS[-1].nests):
		var nz := NEST_Z + k * NEST_DZ
		var nn := Node3D.new()
		nn.position = Vector3(NEST_X, 0, nz)
		add_child(nn)
		var shelf := _box(Vector3(0.6, 0.05, 0.62), Vector3(0, NEST_Y - 0.06, 0), batten, nn, true)
		_box(Vector3(0.6, 0.05, 0.62), Vector3(0, NEST_Y + 0.42, 0), plank, nn, false)
		for s in [-0.31, 0.31]:
			_box(Vector3(0.6, 0.47, 0.03), Vector3(0, NEST_Y + 0.18, s), plank, nn, false)
		_box(Vector3(0.04, 0.12, 0.62), Vector3(-0.29, NEST_Y + 0.02, 0), plank, nn, false)       # (the lip)
		_box(Vector3(0.5, 0.06, 0.56), Vector3(0.02, NEST_Y - 0.01, 0), straw, nn, false)
		for lx in [-0.25, 0.25]:
			_box(Vector3(0.05, NEST_Y - 0.08, 0.05), Vector3(lx, (NEST_Y - 0.08) * 0.5, 0.0), batten, nn, false)
		var eggs := []
		for i in NEST_EGGS:
			var e := MeshInstance3D.new()
			e.mesh = egg_m
			e.material_override = egg_mat
			e.position = Vector3(0.05 + (i % 2) * 0.07, NEST_Y + 0.06, -0.09 + i * 0.09)
			e.rotation.x = PI * 0.5
			nn.add_child(e)
			eggs.append(e)
		_nest_nodes.append([nn, eggs, shelf.get_child(shelf.get_child_count() - 1)])
	# the perches: a ladder of rails up the west wall's far end
	for i in 3:
		var py := 0.4 + i * 0.35
		var pxo := 27.35 + i * 0.3
		_box(Vector3(0.05, 0.05, 2.0), Vector3(pxo, py, 38.6), batten, self, false)
		for pz in [37.65, 39.55]:
			_box(Vector3(0.04, py, 0.04), Vector3(pxo, py * 0.5, pz), batten, self, false)
	# the feeder: a galvanised tube on a tray, feed showing in the tray; the waterer beside it
	var galv := _mat(Color8(170, 176, 178), 0.35, 0.8)
	var tube := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.13
	tm.bottom_radius = 0.13
	tm.height = 0.55
	tube.mesh = tm
	tube.material_override = galv
	tube.position = FEEDER + Vector3(0, 0.38, 0)
	add_child(tube)
	var tray := MeshInstance3D.new()
	var trm := CylinderMesh.new()
	trm.top_radius = 0.26
	trm.bottom_radius = 0.24
	trm.height = 0.08
	tray.mesh = trm
	tray.material_override = galv
	tray.position = FEEDER + Vector3(0, 0.08, 0)
	add_child(tray)
	# the feed in the tray, heaped higher the fuller the feeder
	_feed_mesh = MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.2
	fm.bottom_radius = 0.235
	fm.height = 0.06
	_feed_mesh.mesh = fm
	_feed_mesh.material_override = _mat(Color8(214, 178, 96), 1.0)
	_feed_mesh.position = FEEDER + Vector3(0, 0.1, 0)
	add_child(_feed_mesh)
	var wat := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.1
	wm.bottom_radius = 0.18
	wm.height = 0.35
	wat.mesh = wm
	wat.material_override = _mat(Color8(200, 60, 50), 0.5)
	wat.position = WATERER + Vector3(0, 0.18, 0)
	add_child(wat)
	# the feed sacks, by the door
	var sack := _mat(Color8(196, 176, 130), 1.0)
	for i in 3:
		var s := _box(Vector3(0.42, 0.55, 0.3), SACKS + Vector3(-0.25 + (i % 2) * 0.45, 0.28 + (i / 2) * 0.5, (i % 2) * 0.05), sack, self, i < 2)
		s.rotation = Vector3(0, 0.2 * (i - 1), (0.3 if i == 2 else 0.0))
	var sl := Label3D.new()
	sl.text = "GRAIN\n%d for $%d" % [GRAIN_BUY, GRAIN_COST]
	sl.font_size = 28
	sl.pixel_size = 0.003
	sl.outline_size = 8
	sl.position = SACKS + Vector3(-0.1, 1.25, 0)
	sl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sl)
	# the sign by the door: how many chickens, E upgrades
	_box(Vector3(0.8, 0.5, 0.04), SIGN + Vector3(0, 1.45, -0.02), _mat(Color8(222, 196, 150), 0.9), self, false)
	_sign = Label3D.new()
	_sign.font_size = 40
	_sign.pixel_size = 0.0035
	_sign.outline_size = 6
	_sign.modulate = Color8(40, 26, 14)
	_sign.outline_modulate = Color8(230, 200, 150)
	_sign.position = SIGN + Vector3(0, 1.45, -0.05)
	_sign.rotation.y = PI          # (facing the run: a Label3D reads from its +z side)
	add_child(_sign)
