class_name Dig
extends Node
## Digging under the yard (PLAN.md "Later: digging": level 3, smooth caves, with level 2's ploughing): the earth
## as a density volume (DigVolume, in grid.vol) drawn smooth and made solid by DigGround; a shovel and a hoe from
## the shed's tool rack; finds you pick up; planting on ploughed or dug-over soil (the farm's field plots); soil
## growing back on the game clock; saving; the online sync (the host owns the ground).
##
## Tools (one per player, empty-handed at the start): E at the rack against the shed's east wall takes the
## shovel or the hoe (or puts it back).
## - The shovel: E digs, and keeps digging while held (DIG_EVERY). Top-down it digs in front of him and a little
##   below his feet, so digging on and walking in he goes down a ramp; in first person it digs where he looks
##   (down, ahead, up). Q / pad X / the touch FILL button puts earth back in front of him.
## - The hoe: walking with it ploughs the grass he walks over into furrows (slower walking: it's hand work).
## - On ploughed or dug-over level soil, E plants the picked seed (any tool but the shovel); the farm takes over.
##
## Moving in the earth: Player walks at his own height (y from dz). This node steps right after him
## (process_physics_priority 45: after the Player and the Net, before the Fight) and moves him on the volume
## (DigBody's rules, below): stands him on the floor under him, steps up small ledges, climbs bigger ones he walks
## into (up to CLIMB), falls into shafts, and keeps him out of the walls (his capsule has a collision exception
## with the ground's body). Top-down, while he's underground, the earth over him near him isn't drawn.

const D := preload("res://scripts/dig/dig_data.gd")
const MaskData := preload("res://scripts/dig/dig_mask_data.gd")
const DigMask := preload("res://scripts/dig/dig_mask.gd")
const U := 0.025

static var instance: Dig

signal changed
## A find picked up by player pid: kind "spuds", "coins", "bone", "stash", "gem", "fossil"; n how many (dollars
## for coins, gems, fossils and the stash).
signal found(pid: int, kind: String, n: int)
## A word over the ground (HTML units).
signal floater(text: String, colour: Color, at: Vector2)
## A sound: "dig", "fill", "find", "plough", "tool".
signal sound(name: String)
## A player's tool changed.
signal tool_changed(player: Node, tool: String)

var grid := DigGrid.new()
var ground: DigGround
var main: Node
var world: Node3D
var ui: Node
## Saving (off in tests).
var persist := true
var save_path := D.SAVE_PATH

var _tools: Dictionary = {}           # player instance id -> "shovel" / "hoe" / ""
var _tool_meshes: Dictionary = {}     # player instance id -> Node3D held tool
var _excepted: Dictionary = {}        # player instance id -> true (collision exception made)
var _bodies: Dictionary = {}          # player instance id -> {feet, vz, prev: Vector2, climb: float}
var _spot: _Spot
var _racks: Array = []
var _rack_meshes: Dictionary = {}     # "shovel"/"hoe" -> Node3D leaning on the shed
var _dirty := false
var _save_t := 0.0
var _last_hours := -1.0
var _grow_t := 0.0
var _plough_cells := PackedInt32Array()   # ploughed here, not yet sent
var _plough_t := 0.0
var _swing := 0.0
var _dig_cd := 0.0
var _shake := 0.0
var _pickups: Array = []
var _fx: Array = []                   # CPUParticles3D, reused
var _fx_next := 0
## Online.
var _net_hooked := false
var _was_guest := false
var _was_live := false
var _snap_t := 0.0
var _quiet := 0.0
var _remote_feet := 0.0
var _feet_t := 0.0
var _feet_sent := 0.0

func _enter_tree() -> void:
	instance = self
	add_to_group("dig")

func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _dirty and persist:
		save()
	RenderingServer.global_shader_parameter_set("dig_cut", Vector4.ZERO)

## Builds the ground in the World (main.world) and the shed's rack. Called by DigInstall.
func setup(m: Node) -> void:
	main = m
	world = m.get("world")
	process_physics_priority = 45
	var mk: PackedByteArray = MaskData.mask()
	if mk.size() != D.NX * D.NY:
		# (no stored mask, or the grid changed size: work it out from the data and the yard picture)
		var t := GameData.tex(String((GameData.manifest.get("YARD_IMG@1985", [""]) as Array)[0]))
		var im: Image = t.get_image() if t else null
		if im and im.is_compressed():
			im.decompress()
		mk = DigMask.build(GameData.data, im)
	grid.set_mask(mk)
	if persist:
		load_save()
	ground = DigGround.new()
	world.add_child(ground)
	ground.setup(grid, grid.vol, world)
	grid.changed.connect(_on_grid_changed)
	grid.vol.changed.connect(_on_grid_changed)
	_spot = _Spot.new()
	_spot.dig = self
	_spot.name = "DigSpot"
	add_child(_spot)
	for t in ["shovel", "hoe"]:
		var r := _Rack.new()
		r.dig = self
		r.tool = t
		r.name = "Rack_" + t
		var at := rack_pos(t)
		r.position = GameData.world_to_3d(at.x, at.y, 0.0)
		add_child(r)
		_racks.append(r)
		var mesh := tool_mesh(t)
		mesh.name = "RackTool_" + t
		# leaning on the shed's east wall, blade down
		mesh.position = GameData.world_to_3d(at.x - 4.0, at.y, 0.0)
		mesh.rotation = Vector3(0.0, 0.0, deg_to_rad(16.0))
		add_child(mesh)
		_rack_meshes[t] = mesh
	for i in 4:
		_fx.append(_make_fx())

static func rack_pos(t: String) -> Vector2:
	return Vector2(D.RACK.x, D.RACK.y + (-24.0 if t == "shovel" else 24.0))

func _on_grid_changed() -> void:
	_dirty = true
	changed.emit()

## ---------------------------------------------------------------- tools

func tool_of(p: Node) -> String:
	return _tools.get(p.get_instance_id(), "") if p else ""

func set_tool(p: Node, t: String) -> void:
	if p == null:
		return
	if tool_of(p) == t:
		return
	_tools[p.get_instance_id()] = t
	_show_tool(p, t)
	tool_changed.emit(p, t)
	if p == _local():
		for k in _rack_meshes:
			_rack_meshes[k].visible = k != t
		_net_send({"k": "tool", "tool": t})

func _show_tool(p: Node, t: String) -> void:
	var id := p.get_instance_id()
	var old = _tool_meshes.get(id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	_tool_meshes.erase(id)
	if t == "" or not (p is Node3D):
		return
	var m := tool_mesh(t)
	m.name = "DigTool"
	p.add_child(m)
	_tool_meshes[id] = m

## A shovel or a hoe as a few boxes (a wooden handle, a steel blade), standing on its blade's foot at the origin,
## HTML units scaled to metres.
static func tool_mesh(t: String) -> Node3D:
	var root := Node3D.new()
	var wood := Color8(150, 104, 58)
	var steel := Color8(150, 156, 166)
	var dark := Color8(84, 88, 96)
	var handle_h := 58.0
	if t == "shovel":
		_box(root, Vector3(0, 13 + handle_h / 2.0, 0), Vector3(3, handle_h, 3), wood)
		_box(root, Vector3(0, 13 + handle_h + 2, 0), Vector3(10, 3, 3), wood)         # the D grip
		_box(root, Vector3(0, 7, 0), Vector3(12, 14, 2), steel)                        # the blade
		_box(root, Vector3(0, 13.5, 0), Vector3(5, 3, 3), dark)
	else:
		_box(root, Vector3(0, 4 + handle_h / 2.0, 0), Vector3(3, handle_h + 8, 3), wood)
		_box(root, Vector3(0, 3, 5), Vector3(14, 6, 2), steel)                         # the blade, square to the handle
		_box(root, Vector3(0, 6, 2), Vector3(3, 3, 6), dark)
	return root

static var _tool_mats: Dictionary = {}
static func _box(parent: Node3D, at: Vector3, size: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size * U
	mi.mesh = b
	mi.position = at * U
	var key := c.to_html()
	if not _tool_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tool_mats[key] = m
	mi.material_override = _tool_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Where a player's held tool is drawn: at his side, leaning forward (seen from above an upright tool would be a
## dot); a dig swings it down hard.
func _pose_tools() -> void:
	for id in _tool_meshes.keys():
		var mv = _tool_meshes[id]
		if not is_instance_valid(mv):
			_tool_meshes.erase(id)
			_tools.erase(id)
			continue
		var m: Node3D = mv
		var p := m.get_parent() as Node3D
		if p == null:
			continue
		var f: Vector2 = p.get("facing") if p.get("facing") is Vector2 else Vector2(0, 1)
		if f.length() < 0.001:
			f = Vector2(0, 1)
		f = f.normalized()
		var side := Vector2(-f.y, f.x)
		var sw := sin(clampf(_swing, 0.0, 1.0) * PI) if p == _local() else 0.0
		var off := f * (4.0 + 10.0 * sw) + side * 15.0
		m.position = Vector3(off.x, 6.0 * sw, off.y) * U
		var yaw := atan2(f.x, f.y)
		m.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 1.0 + 0.9 * sw)
		m.visible = not (p.has_method("is_first_person") and p.is_first_person())

## ---------------------------------------------------------------- where E works

func _local() -> Node:
	return main.get("player") if main else null

static func pos_of(p: Node) -> Vector2:
	if p is Node3D:
		var h := GameData.from_3d(p.global_position)
		return Vector2(h.x, h.y)
	return Vector2.ZERO

static func facing_of(p: Node) -> Vector2:
	var f = p.get("facing")
	if p.has_method("is_first_person") and p.is_first_person():
		var a := float(p.get("look_ang"))
		f = Vector2(cos(a), sin(a))
	return f.normalized() if f is Vector2 and f.length() > 0.001 else Vector2(0, 1)

## Puts p's feet on the floor under (his x, y) at or below z (a teleport into a cave: tests, demos).
func drop_to(p: Node, z: float) -> void:
	var hp := pos_of(p)
	var f := grid.vol.floor_below(hp.x, hp.y, z)
	_bodies[p.get_instance_id()] = {"feet": f, "vz": 0.0, "prev": hp, "climb": -INF}
	p.global_position = GameData.world_to_3d(hp.x, hp.y, f)
	if p.has_method("reset_physics_interpolation"):
		p.reset_physics_interpolation()

## Where his feet are (HTML z, units: 0 on the untouched ground, down in a hole or a tunnel).
func feet_of(p: Node) -> float:
	var b = _bodies.get(p.get_instance_id())
	return float(b.feet) if b else 0.0

## The point in front of him on the ground (for planting and the hoe).
func target_of(p: Node) -> Vector2:
	return pos_of(p) + facing_of(p) * D.REACH

## What the shovel would dig now: {a, b (HTML units, a capsule's ends), r, at (Vector2)}, or {} if nothing there
## can be dug (no earth within reach, or ground that can't be dug).
func dig_shape(p: Node) -> Dictionary:
	var hp := pos_of(p)
	var feet := feet_of(p)
	var vol := grid.vol
	if p.has_method("is_first_person") and p.is_first_person():
		var a := float(p.get("look_ang"))
		var ly := float(p.get("look_y"))
		var dir := Vector3(cos(a) * cos(ly), sin(a) * cos(ly), -sin(ly))
		var eye := Vector3(hp.x, hp.y, feet + 62.0)
		var hit = vol.raycast(eye, dir, D.FP_REACH)
		if hit == null:
			return {}
		var c: Vector3 = hit + dir * 6.0
		if not _diggable3(c):
			return {}
		return {"a": c, "b": c, "r": D.DIG_R, "at": Vector2(c.x, c.y)}
	var f := facing_of(p)
	var t := hp + f * D.REACH
	var ft := vol.floor_below(t.x, t.y, feet + D.STEP)
	var bottom := maxf(maxf(ft - D.DIG_DOWN, feet - D.DIG_MAX), D.ZMIN + 2.0 * D.CELL + 1.0)
	var a3 := Vector3(t.x, t.y, bottom)
	var b3 := Vector3(t.x, t.y, feet + D.DIG_UP)
	if not _diggable3(a3):
		return {}
	# (something to dig: earth in the capsule)
	var any := false
	for z in [bottom - D.DIG_R * 0.6, feet + 10.0, feet + 34.0]:
		if vol.solid(t.x, t.y, z):
			any = true
			break
	if not any:
		return {}
	return {"a": a3, "b": b3, "r": D.DIG_R, "at": t}

## Can the earth at c be dug (its column is diggable and it's above the bedrock)?
func _diggable3(c: Vector3) -> bool:
	return grid.diggable_at(c.x, c.y) and c.z > D.ZMIN + 2.0 * D.CELL and c.z < D.ZMAX

## What E does here for p (the DigSpot's label).
func label_for(p: Node) -> String:
	if p != _local() or p.get("on_tramp") or p.get("frozen"):
		return ""
	var t := tool_of(p)
	if t == "shovel":
		var sh := dig_shape(p)
		if sh.is_empty() or _field_near(sh.at, D.SPOT * 0.75) >= 0:
			return ""
		return "DIG"
	# planting on ploughed or dug-over soil (any tool but the shovel): the spot he stands on or faces
	return _plant_label(p)

func _plant_label(p: Node) -> String:
	if absf(feet_of(p)) > 4.0:
		return ""
	var spot = _plant_spot_for(p)
	if spot == null:
		return ""
	var fm = Farm.instance
	var s: int = fm.state.seed_pick(Farm.pid_of(p))
	if s < 0:
		return ""
	return "PLANT " + FarmData.STRAINS[s].short

## The free planting spot for p: the one he faces, else the one he's on.
func _plant_spot_for(p: Node):
	if Farm.instance == null:
		return null
	for at in [target_of(p), pos_of(p) + facing_of(p) * 8.0]:
		var spot = grid.plant_spot(at.x, at.y)
		if spot != null and _field_near(spot, D.SPOT * 0.75) < 0:
			return spot
	return null

func _field_near(at: Vector2, r: float) -> int:
	return Farm.instance.state.field_near(at.x, at.y, r) if Farm.instance else -1

## E (the DigSpot's act).
func act(p: Node) -> void:
	var l := label_for(p)
	if l == "DIG":
		dig_now(p)
	elif l.begins_with("PLANT"):
		plant_at(p)

## One dig for player p, where dig_shape says: the earth goes, dirt flies, finds pop out. Returns the samples dug
## out (empty if nothing was).
func dig_now(p: Node) -> Array:
	var sh := dig_shape(p)
	if sh.is_empty():
		return []
	_dig_cd = D.DIG_EVERY
	return carve(sh.a, sh.b, sh.r, p)

## Takes out a capsule of earth (a guest's own dig, the host replaying it, a test). p: who dug (gets the finds;
## null: no finds).
func carve(a: Vector3, b: Vector3, r: float, p: Node = null) -> Array:
	var out := grid.vol.carve(a, b, r)
	# at the ground's top it's dug-over dirt from now on (the hole's own cells: filled in, they're soil to plant)
	if maxf(a.z, b.z) + r > -6.0 and minf(a.z, b.z) - r < 4.0:
		grid.mark_dug(a.x, a.y, r - 4.0)
	if out.is_empty():
		return out
	grid.stats.digs += 1
	if p != null:
		_swing = 1.0
		_shake = maxf(_shake, 0.6)
		sound.emit("dig")
		_burst(a.lerp(b, 0.15), _earth_colour(a.z))
		_net_op(["carve", a.x, a.y, a.z, b.x, b.y, b.z, r])
		for s in out:
			var f := find_at(s.x, s.y, s.z)
			if not f.is_empty():
				_count_find(f)
				_spawn_pickup(f, Vector3(D.X0 + s.x * D.CELL, D.Y0 + s.y * D.CELL, D.ZMIN + s.z * D.CELL))
	return out

## Q / pad X / the touch FILL button: earth back in front of him.
func fill_now(p: Node) -> bool:
	var c = fill_centre(p)
	if c == null:
		return false
	return fill(c, D.FILL_R, p)

func fill_centre(p: Node):
	var hp := pos_of(p)
	var feet := feet_of(p)
	var c: Vector3
	if p.has_method("is_first_person") and p.is_first_person():
		var a := float(p.get("look_ang"))
		var ly := float(p.get("look_y"))
		var dir := Vector3(cos(a) * cos(ly), sin(a) * cos(ly), -sin(ly))
		var eye := Vector3(hp.x, hp.y, feet + 62.0)
		var hit = grid.vol.raycast(eye, dir, D.FP_REACH)
		if hit == null:
			return null
		c = hit - dir * 10.0
	else:
		var t := hp + facing_of(p) * (D.REACH + 4.0)
		c = Vector3(t.x, t.y, grid.vol.floor_below(t.x, t.y, feet + 20.0) + 4.0)
	if not _diggable3(c) or c.z > -2.0:
		return null
	# never into anyone
	for q in _players():
		var qp := pos_of(q)
		var qf := feet_of(q)
		var seg := DigVolume._seg_dist(c, Vector3(qp.x, qp.y, qf), Vector3(qp.x, qp.y, qf + 66.0))
		if seg < D.FILL_R + 14.0:
			return null
	return c

func fill(c: Vector3, r: float, p: Node = null) -> bool:
	var ok := grid.vol.fill(c, r, 0.0)
	if ok and p != null:
		_swing = 1.0
		_shake = maxf(_shake, 0.3)
		sound.emit("fill")
		_burst(c, _earth_colour(c.z))
		_net_op(["fill", c.x, c.y, c.z, r])
	return ok

func can_fill(p: Node) -> bool:
	return tool_of(p) == "shovel" and fill_centre(p) != null

## ---------------------------------------------------------------- finds

## What's buried at sample (i, j, k): {} or {kind, n, band}. The same on every screen (it hangs on the place).
static func find_at(i: int, j: int, k: int) -> Dictionary:
	var z := D.ZMIN + k * D.CELL
	var band := 0
	for b in D.BAND_Z.size():
		if -z >= float(D.BAND_Z[b]):
			band = b
	var h := _hash3(i, j, k)
	if float(h % 100000) / 100000.0 >= float(D.FIND_P[band]):
		return {}
	var table: Array = D.FIND_TABLE[band]
	var total := 0
	for e in table:
		total += int(e[1])
	var h2 := _hash3(i + 7919, j + 104729, k + 1299709)
	var pick := h2 % total
	for e in table:
		pick -= int(e[1])
		if pick < 0:
			var lo := int(e[2])
			var hi := int(e[3])
			return {"kind": String(e[0]), "n": lo + (h2 / 7) % (hi - lo + 1), "band": band}
	return {}

static func _hash3(i: int, j: int, k: int) -> int:
	var h := (i * 73856093) ^ (j * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff

func _count_find(f: Dictionary) -> void:
	match String(f.kind):
		"spuds": grid.stats.spuds += int(f.n)
		"coins": grid.stats.coins += int(f.n)
		"bone": grid.stats.bones += 1
		"stash": grid.stats.stashes += 1
		"gem": grid.stats.gems += 1
		"fossil": grid.stats.fossils += 1

## A find popping out of the earth at `at` (HTML units) and landing on the floor nearby, to be picked up.
func _spawn_pickup(f: Dictionary, at: Vector3) -> void:
	var pk := _Pickup.new()
	pk.dig = self
	pk.kind = String(f.kind)
	pk.n = int(f.n)
	world.add_child(pk)
	var land := Vector2(at.x, at.y) + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	var floor_z := grid.vol.floor_below(land.x, land.y, at.z + 20.0)
	pk.start(at, Vector3(land.x, land.y, floor_z))
	_pickups.append(pk)
	floater.emit(_find_word(pk.kind), Color("#ffe9a8"), Vector2(at.x, at.y))

static func _find_word(kind: String) -> String:
	return {"spuds": "SPUDS!", "coins": "COINS!", "bone": "A BONE!", "stash": "A STASH!", "gem": "A GEM!",
		"fossil": "A FOSSIL!"}.get(kind, "!")

## Picking it up: spuds load his spud gun (the fight's fighter), money into the Wallet (a stash brings a seed you
## can't buy too), a bone is a bone.
func pick_up(pk: Node, p: Node) -> void:
	_pickups.erase(pk)
	_award(p, pk.kind, pk.n, pos_of(p))
	pk.queue_free()

func _award(p: Node, kind: String, n: int, at: Vector2) -> void:
	var pid := Farm.pid_of(p)
	match kind:
		"spuds":
			var fight = Fight.me if Fight.me else null
			var ff = fight.fighter_of(p) if fight else null
			if ff:
				var per := int(fight.sim.tv("spudPellets", 10))
				ff.ammo = mini(int(fight.sim.tv("spudMaxAmmo", 200)), ff.ammo + n * per)
			floater.emit("+%d SPUDS" % n, Color("#e8d27a"), at)
		"coins", "gem", "fossil":
			_pay(n)
			floater.emit(("+$%d" % n) if kind == "coins" else ("%s +$%d" % [kind.to_upper(), n]), Color("#ffd36b"), at)
		"bone":
			floater.emit("A BONE!", Color("#f2efe4"), at)
		"stash":
			_pay(n)
			var fm = Farm.instance
			if fm:
				var s := 2 + grid.rng.randi() % 4            # a seed you can't buy (GDP, BD, AG or WW)
				fm.state.add_seed(pid, s, 1)
				floater.emit("STASH! +$%d +1 %s SEED" % [n, FarmData.STRAINS[s].short], Color("#ffd36b"), at)
			else:
				floater.emit("STASH! +$%d" % n, Color("#ffd36b"), at)
	sound.emit("find")
	found.emit(pid, kind, n)

func _pay(n: int) -> void:
	var w := get_node_or_null("/root/Wallet")
	if w and w.has_method("add_cash"):
		w.add_cash(n, "dig")

## ---------------------------------------------------------------- planting

## Plants p's picked seed on the ploughed or dug-over spot he's at (a farm field plot from then on).
func plant_at(p: Node) -> String:
	var spot = _plant_spot_for(p)
	var fm = Farm.instance
	if spot == null or fm == null:
		return ""
	var pid := Farm.pid_of(p)
	var s: int = fm.state.seed_pick(pid)
	if s < 0:
		return ""
	var i: int = fm.state.field_plot(spot.x, spot.y)
	if i < 0:
		floater.emit("NO ROOM", Color("#ff9a7a"), spot)
		return ""
	var r: String = fm.state.plant(i, pid, s)
	if r == "":
		fm.state.field_free(i)
		return ""
	fm.say(r, spot)
	fm.sound.emit("plant")
	fm._save_soon()
	return r

## ---------------------------------------------------------------- the effects

func _make_fx() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.7
	p.explosiveness = 0.95
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 3.0 * U
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0 * U
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child.call_deferred(p)
	return p

func _burst(at: Vector3, col: Color) -> void:
	if _fx.is_empty():
		return
	var p: CPUParticles3D = _fx[_fx_next % _fx.size()]
	_fx_next += 1
	if not p.is_inside_tree():
		return
	p.global_position = GameData.world_to_3d(at.x, at.y, at.z + 6.0)
	p.color = col
	p.restart()
	p.emitting = true

static func _earth_colour(z: float) -> Color:
	var depth := -z
	if depth > 210.0:
		return Color8(120, 118, 122)
	if depth > 90.0:
		return Color8(150, 96, 64)
	return Color8(112, 80, 50)

func _shake_cam(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 4.0)
		var a := 0.035 * _shake
		cam.h_offset = randf_range(-a, a)
		cam.v_offset = randf_range(-a, a)
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

## ---------------------------------------------------------------- every step

## Q / pad X (lobby_alt) with the shovel: fill in front. (The touch FILL button calls fill_now.)
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("lobby_alt") or event.is_echo():
		return
	var p := _local()
	if p == null or tool_of(p) != "shovel" or p.get("frozen") or not p.get("controls_enabled"):
		return
	if fill_now(p):
		get_viewport().set_input_as_handled()

func _players() -> Array:
	var players := get_tree().get_nodes_in_group("player")
	var n = _net()
	var p2 = n.get("p2") if n else null
	if p2 and is_instance_valid(p2) and not players.has(p2):
		players.append(p2)                   # (the online other player isn't in the group)
	return players

func _physics_process(dt: float) -> void:
	if main == null:
		return
	var me := _local()
	for p in _players():
		if not (p is CharacterBody3D) or not p.is_inside_tree():
			continue
		var id: int = p.get_instance_id()
		if not _excepted.has(id) and ground and ground.body():
			p.add_collision_exception_with(ground.body())
			_excepted[id] = true
		_move_body(p, dt, p == me)
	if me:
		_plough_step(me, dt)
		# held E with the shovel digs on
		_dig_cd = maxf(0.0, _dig_cd - dt)
		if _dig_cd <= 0.0 and tool_of(me) == "shovel" and me.get("controls_enabled") and not me.get("frozen") \
				and Input.is_action_pressed("interact") and me.get("focus") == _spot:
			dig_now(me)
	_swing = maxf(0.0, _swing - dt * 4.0)

## Moves p on the earth (see the class notes): walls, the floor, steps, climbing, falling.
func _move_body(p: Node, dt: float, local: bool) -> void:
	var id := p.get_instance_id()
	var hp := pos_of(p)
	var b: Dictionary = _bodies.get(id, {})
	if b.is_empty():
		b = {"feet": 0.0, "vz": 0.0, "prev": hp, "climb": -INF}
		_bodies[id] = b
	var vol := grid.vol
	var dz := float(p.get("dz"))
	if not local:
		# (the other player online: their own game moves them on the ground; their feet come with them)
		b.feet = _remote_feet if DigGrid.in_region(hp.x, hp.y) else 0.0
		b.prev = hp
		var want := GameData.world_to_3d(hp.x, hp.y, float(b.feet) + dz).y
		if absf(p.global_position.y - want) > 0.00001:
			p.global_position.y = want
		return
	if p.get("on_tramp") or p.get("frozen") or not DigGrid.in_region(hp.x, hp.y) \
			or (absf(b.feet) < 0.01 and not vol.touched_near(hp.x, hp.y)):
		# (untouched ground, the trampoline, lobby poses: as before)
		b.feet = 0.0
		b.vz = 0.0
		b.prev = hp
		var want0 := dz * U
		if absf(p.global_position.y - want0) > 0.00001:
			p.global_position.y = want0
		return
	var feet: float = b.feet
	var prev: Vector2 = b.prev
	# climbing a ledge he walked into: up first, then onto it
	if float(b.climb) > feet:
		feet = minf(float(b.climb), feet + D.CLIMB_SPEED * dt)
		b.vz = 0.0
		if feet < float(b.climb) - 0.01:
			hp = prev
		else:
			b.climb = -INF
			# up: on over the edge
			var on := prev + (hp - prev).normalized() * 2.0 if hp != prev else prev
			hp = on
	# walls: back to where he was (sliding along them if he can)
	if hp != prev and _blocked(hp, feet):
		# (the ledge's top is looked for a little past the wall's foot, where he'd stand on it)
		var ledge := _ledge(prev + (hp - prev).normalized() * (D.BODY_R + 14.0), feet)
		if ledge > -INF:
			b.climb = ledge                       # (walked into a ledge he can get up: up he goes)
		var a := Vector2(hp.x, prev.y)
		var c := Vector2(prev.x, hp.y)
		var v: Vector2 = p.get("vel") if p.get("vel") is Vector2 else Vector2.ZERO
		if not _blocked(a, feet):
			hp = a
			v.y = 0.0
		elif not _blocked(c, feet):
			hp = c
			v.x = 0.0
		else:
			hp = prev
			v = Vector2.ZERO
		p.set("vel", v)
	# the floor under him: up small steps, down by falling
	var fl := vol.floor_below(hp.x, hp.y, feet + D.STEP)
	if fl >= feet - 0.5:
		feet = fl
		b.vz = 0.0
	else:
		b.vz = float(b.vz) - D.GRAVITY * dt
		feet = maxf(fl, feet + float(b.vz) * dt)
		if feet <= fl:
			b.vz = 0.0
	b.feet = feet
	b.prev = hp
	var pos := GameData.world_to_3d(hp.x, hp.y, feet + dz)
	if p.global_position.distance_squared_to(pos) > 0.0000001:
		p.global_position = pos

## Would his body at (x, y) with his feet at `feet` be in the earth? (Knee, chest and head height, round him.)
func _blocked(at: Vector2, feet: float) -> bool:
	var vol := grid.vol
	for h in [D.STEP + 4.0, 40.0, 60.0]:
		var z: float = feet + h
		for o in [Vector2.ZERO, Vector2(D.BODY_R, 0), Vector2(-D.BODY_R, 0), Vector2(0, D.BODY_R), Vector2(0, -D.BODY_R)]:
			if vol.solid(at.x + o.x, at.y + o.y, z):
				return true
	return false

## A ledge he could climb onto at `at`: its top (feet height), if it's within CLIMB and there's room to stand
## there; else -INF.
func _ledge(at: Vector2, feet: float) -> float:
	var vol := grid.vol
	var top := vol.floor_below(at.x, at.y, feet + D.CLIMB + 2.0)
	if top <= feet + D.STEP or top > feet + D.CLIMB:
		return -INF
	if vol.solid(at.x, at.y, top + D.CLIMB + 2.0) or _blocked(at, top):
		return -INF
	return top

func _plough_step(p: Node, dt: float) -> void:
	if tool_of(p) != "hoe" or p.get("on_tramp") or p.get("frozen") or float(p.get("roll")) > 0.0:
		return
	var here := pos_of(p)
	if not grid.diggable_at(here.x, here.y) or absf(feet_of(p)) > 2.0:
		return
	# hand work: walking with the hoe in the ground is slower (his speed held to 0.6 of the most)
	var v: Vector2 = p.get("vel")
	var cap := Player._t("maxSpeed") * 0.6
	if v.length() > cap:
		p.set("vel", v / v.length() * cap)
	if not bool(p.get("moving")) or v.length() < 20.0:
		return
	var at := here + v.normalized() * D.PLOUGH_AHEAD
	var cells := grid.plough(at.x, at.y, v)
	if not cells.is_empty():
		for i in cells:
			_plough_cells.append(i * 4 + grid.soil[i])
		_plough_t += dt
		if _plough_t > 0.18:
			_plough_t = 0.0
			sound.emit("plough")

func _process(dt: float) -> void:
	if main == null:
		return
	_pose_tools()
	_shake_cam(dt)
	_update_cut()
	_net_step(dt)
	_grow(dt)
	if persist and _dirty and not _is_guest():
		_save_t += dt
		if _save_t > 2.0:
			save()

## Is the earth over him cut away just now (top-down, underground)?
var cut_on := false

## Top-down, with him underground: the earth over him near him isn't drawn. Underground in either view, a lamp
## lights the earth round him (it's dark down there).
func _update_cut() -> void:
	var p := _local()
	var on := false
	var lamp := Vector4.ZERO
	if p and feet_of(p) < -24.0:
		var lp := GameData.from_3d(p.get_global_transform_interpolated().origin)
		var lw := GameData.world_to_3d(lp.x, lp.y, feet_of(p) + 40.0)
		lamp = Vector4(lw.x, lw.y, lw.z, D.LAMP_R * U)
	RenderingServer.global_shader_parameter_set("dig_lamp", lamp)
	if p and not (p.has_method("is_first_person") and p.is_first_person()):
		var feet := feet_of(p)
		if feet < -24.0:
			var hp := GameData.from_3d(p.get_global_transform_interpolated().origin)
			var w := GameData.world_to_3d(hp.x, hp.y, feet + D.CUT_OVER)
			RenderingServer.global_shader_parameter_set("dig_cut", Vector4(w.x, w.y, w.z, D.CUT_R * U))
			on = true
	if not on:
		RenderingServer.global_shader_parameter_set("dig_cut", Vector4.ZERO)
	cut_on = on
	if ground and ground.bottom:
		ground.bottom.visible = on

## Soil grows back on the game clock (the host's: a guest follows the host's snapshots), crops keep theirs.
func _grow(dt: float) -> void:
	_grow_t += dt
	if _grow_t < 0.5:
		return
	_grow_t = 0.0
	var clock := get_node_or_null("/root/GameClock")
	if clock == null or not clock.has_method("total_hours"):
		return
	var h: float = clock.total_hours()
	if _last_hours < 0.0 or _is_guest():
		_last_hours = h
		return
	var d := h - _last_hours
	_last_hours = h
	if d <= 0.0 or d > 24.0 * 30.0:
		return
	grow_back(d)

## Game hours pass (also from tests): untended soil ages and grows back; spots whose soil has gone and whose
## crop is gone free their field plot.
func grow_back(hours: float) -> void:
	var tended: Array = []
	var fm = Farm.instance
	if fm:
		for p in fm.state.plots:
			if p.zone == "field" and p.on and p.s >= 0:
				tended.append(Vector2(p.x, p.y))
	grid.grow_back(hours, tended)
	if fm:
		for i in fm.state.plots.size():
			var p: Dictionary = fm.state.plots[i]
			if p.zone == "field" and p.on and p.s < 0 and grid.plant_spot(p.x, p.y) == null:
				fm.state.field_free(i)

## ---------------------------------------------------------------- saving

func save() -> void:
	_dirty = false
	_save_t = 0.0
	if not persist:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(grid.to_json_dict()))

func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	return d is Dictionary and grid.unpack(d)

## Everything back to grass (and the save with it).
func wipe() -> void:
	grid.clear()
	if persist:
		save()

func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT) and _dirty and persist and not _is_guest():
		save()

## ---------------------------------------------------------------- online (the host's ground)

func _net():
	return Net.me if Net.me and is_instance_valid(Net.me) else null

func _is_guest() -> bool:
	var n = _net()
	return n != null and n.live and n.role == "client"

func _net_send(d: Dictionary) -> void:
	var n = _net()
	if n and n.live:
		d["t"] = "dig"
		n._send(d)

## A change of the ground goes to the other game as an op: a guest's to the host (which replays it and passes
## it back: digging and filling and ploughing twice is the same as once), the host's to the guest.
func _net_op(op: Array) -> void:
	if _is_guest():
		_quiet = 1.5
	_net_send({"k": "op", "op": op})

func _net_step(dt: float) -> void:
	var n = _net()
	if n == null:
		return
	if not _net_hooked and n.has_signal("message"):
		n.message.connect(_on_net)
		_net_hooked = true
	var live: bool = n.live
	var guest := _is_guest()
	# a guest going back to its own game: its own ground again
	if _was_guest and not guest:
		grid.clear()
		if persist:
			load_save()
	_was_guest = guest
	if live and not _was_live:
		_snap_t = 99.0                           # just connected: the host sends the ground now
		_net_send({"k": "tool", "tool": tool_of(_local())})
	_was_live = live
	if not live:
		_plough_cells = PackedInt32Array()
		return
	_quiet = maxf(0.0, _quiet - dt)
	if not _plough_cells.is_empty():
		_net_op(["plough", _plough_cells])
		_plough_cells = PackedInt32Array()
	# where our feet are (in a hole, a tunnel), ten times a second while it changes
	_feet_t += dt
	var me := _local()
	if me and _feet_t > 0.1:
		_feet_t = 0.0
		var f := feet_of(me)
		if absf(f - _feet_sent) > 0.5:
			_feet_sent = f
			_net_send({"k": "feet", "f": f})
	if guest:
		return
	# the host: the whole ground now and then (ops keep both up to date between)
	_snap_t += dt
	if _snap_t > 15.0:
		_snap_t = 0.0
		_net_send({"k": "snap", "p": grid.pack()})

func _on_net(d: Dictionary) -> void:
	if String(d.get("t", "")) != "dig":
		return
	match String(d.get("k", "")):
		"op":
			var op: Array = d.get("op", [])
			apply_op(op)
			if not _is_guest():
				_net_send({"k": "op", "op": op})     # (passed on to the guest: the host's ground is the one)
		"snap":
			if _is_guest() and _quiet <= 0.0:
				grid.unpack(d.get("p", {}))
		"feet":
			_remote_feet = float(d.get("f", 0.0))
		"tool":
			var n = _net()
			var p2 = n.get("p2") if n else null
			if p2 and is_instance_valid(p2):
				var t := String(d.get("tool", ""))
				_tools[p2.get_instance_id()] = t
				_show_tool(p2, t)

## Applies a change from the other game (no finds: they're the digger's).
func apply_op(op: Array) -> void:
	if op.is_empty():
		return
	match String(op[0]):
		"carve":
			if op.size() >= 8:
				carve(Vector3(float(op[1]), float(op[2]), float(op[3])), Vector3(float(op[4]), float(op[5]), float(op[6])), float(op[7]))
		"fill":
			if op.size() >= 5:
				fill(Vector3(float(op[1]), float(op[2]), float(op[3])), float(op[4]))
		"plough":
			if op.size() >= 2:
				var any := false
				for c in op[1]:
					var i := int(c) / 4
					if i >= 0 and i < D.NX * D.NY and grid.plough_cell(i % D.NX, i / D.NX, int(c) % 4):
						any = true
				if any:
					grid._changed()

## ---------------------------------------------------------------- the E spots, and finds lying about

## Where the tool works, in front of the local player: E there digs or plants.
class _Spot extends Interactable:
	var dig: Dig
	func _ready() -> void:
		reach = 60.0
	func _physics_process(_dt: float) -> void:
		var p := dig._local() if dig else null
		if p == null:
			return
		var at := dig.target_of(p)
		global_position = GameData.world_to_3d(at.x, at.y, dig.feet_of(p))
	func label_for(player: Node) -> String:
		return dig.label_for(player) if dig else ""
	func act(player: Node) -> void:
		if dig:
			dig.act(player)
	func ground_distance(player: Node3D) -> float:
		# where his tool is: always just in front of him, so nearer than what he faces anyway
		return 14.0 if player == dig._local() else INF

## The tool rack against the shed: E takes the shovel or the hoe, or puts it back.
class _Rack extends Interactable:
	var dig: Dig
	var tool := ""
	func _ready() -> void:
		reach = 34.0
	func label_for(player: Node) -> String:
		if dig == null:
			return ""
		return ("PUT BACK " if dig.tool_of(player) == tool else "TAKE ") + tool.to_upper()
	func act(player: Node) -> void:
		if dig == null:
			return
		var had := dig.tool_of(player)
		dig.set_tool(player, "" if had == tool else tool)
		dig.sound.emit("tool")
		if had != tool:
			dig.floater.emit(("SHOVEL: HOLD E TO DIG, Q FILLS" if tool == "shovel" else "HOE: WALK TO PLOUGH, E PLANTS"),
				Color("#e6e8ee"), Dig.pos_of(player))

## A find lying where it popped out: it bobs and glints; walk over it to pick it up.
class _Pickup extends Node3D:
	var dig: Dig
	var kind := ""
	var n := 0
	var _t := 0.0
	var _land := Vector3.ZERO
	var _flying := true
	var _spr: Sprite3D
	func start(from: Vector3, land: Vector3) -> void:
		_land = land
		_spr = Sprite3D.new()
		_spr.texture = Dig.find_tex(kind)
		_spr.pixel_size = 0.0045
		_spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_spr.shaded = false
		_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_spr.position = Vector3(0, 6.0 * U, 0)
		add_child(_spr)
		global_position = GameData.world_to_3d(from.x, from.y, from.z)
		# out of the earth in an arc, onto the floor
		var tw := create_tween()
		var top := GameData.world_to_3d((from.x + land.x) / 2.0, (from.y + land.y) / 2.0, maxf(from.z, land.z) + 30.0)
		tw.tween_property(self, "global_position", top, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(self, "global_position", GameData.world_to_3d(land.x, land.y, land.z), 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func(): _flying = false)
	func _process(dt: float) -> void:
		_t += dt
		if _spr:
			_spr.position.y = (6.0 + 2.5 * sin(_t * 5.0)) * U
			_spr.modulate = Color(1, 1, 1) * (1.0 + 0.35 * maxf(0.0, sin(_t * 3.0)))
		if _t > D.FIND_LIFE:
			dig._pickups.erase(self)
			queue_free()
			return
		if _flying or dig == null:
			return
		var p := dig._local()
		if p == null:
			return
		var hp := Dig.pos_of(p)
		if Vector2(hp.x - _land.x, hp.y - _land.y).length() < D.PICK_R and absf(dig.feet_of(p) - _land.z) < 40.0:
			dig.pick_up(self, p)

## The finds' pictures: 16 x 16 pixel art made here.
static var _find_texs: Dictionary = {}
static func find_tex(kind: String) -> Texture2D:
	if _find_texs.has(kind):
		return _find_texs[kind]
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ink := Color8(30, 22, 16)
	match kind:
		"spuds":
			_blob(im, Vector2(5.5, 9), 4.0, 3.2, Color8(176, 132, 74), ink)
			_blob(im, Vector2(10.5, 7), 4.2, 3.4, Color8(196, 150, 86), ink)
			im.set_pixel(10, 6, Color8(120, 84, 44))
			im.set_pixel(5, 9, Color8(120, 84, 44))
		"coins":
			_blob(im, Vector2(6, 10), 4.0, 4.0, Color8(232, 186, 48), ink)
			_blob(im, Vector2(10, 6), 4.0, 4.0, Color8(250, 210, 70), ink)
			im.set_pixel(9, 5, Color8(255, 246, 190))
		"bone":
			for x in range(3, 13):
				im.set_pixel(x, 7, Color8(240, 236, 220))
				im.set_pixel(x, 8, Color8(222, 216, 196))
			for c in [Vector2(3, 6), Vector2(3, 9), Vector2(12, 6), Vector2(12, 9)]:
				_blob(im, c, 1.8, 1.8, Color8(240, 236, 220), Color8(150, 142, 120))
		"stash":
			_blob(im, Vector2(8, 10), 5.0, 4.5, Color8(150, 110, 66), ink)
			for x in range(6, 11):
				im.set_pixel(x, 4, Color8(120, 84, 44))
			im.set_pixel(8, 10, Color8(250, 210, 70))
			im.set_pixel(8, 9, Color8(250, 210, 70))
			im.set_pixel(8, 11, Color8(250, 210, 70))
		"gem":
			var pts := [Vector2(8, 2), Vector2(13, 7), Vector2(8, 14), Vector2(3, 7)]
			for y in 16:
				for x in 16:
					if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), PackedVector2Array(pts)):
						im.set_pixel(x, y, Color8(80, 220, 230) if x + y < 15 else Color8(40, 160, 200))
			im.set_pixel(7, 5, Color8(230, 255, 255))
		"fossil":
			_blob(im, Vector2(8, 8), 6.0, 5.5, Color8(214, 200, 168), ink)
			for k in 18:
				var a := k * 0.55
				var r := 1.0 + k * 0.25
				var x := int(8 + cos(a) * r)
				var y := int(8 + sin(a) * r)
				if x >= 0 and y >= 0 and x < 16 and y < 16:
					im.set_pixel(x, y, Color8(140, 120, 90))
	var t := ImageTexture.create_from_image(im)
	_find_texs[kind] = t
	return t

static func _blob(im: Image, c: Vector2, rx: float, ry: float, col: Color, edge: Color) -> void:
	for y in 16:
		for x in 16:
			var d := pow((x + 0.5 - c.x) / rx, 2.0) + pow((y + 0.5 - c.y) / ry, 2.0)
			if d <= 1.0:
				im.set_pixel(x, y, edge if d > 0.62 else col)
