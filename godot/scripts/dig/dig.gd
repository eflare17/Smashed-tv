class_name Dig
extends Node
## Digging level 2 and ploughing (PLAN.md "Later: digging"): the yard's ground as a depth grid (DigGrid) drawn
## and made solid by DigGround, a shovel and a hoe from the shed's tool rack, finds, planting on ploughed soil
## (the farm's field plots), soil growing back on the game clock, saving, and the online sync (the host owns the
## ground; a compact snapshot like the farm's).
##
## Tools (one per player, empty-handed at the start): E at the rack against the shed's east wall takes the
## shovel or the hoe (or puts it back). With the shovel, E digs where he faces (a step deeper each press, about
## waist-deep at the bottom, the dirt thrown in a pile beside the hole) and fills a hole that's at the bottom;
## lobby_alt (Q / pad X / the touch FILL button) fills at any depth. With the hoe, walking ploughs the grass he
## walks over into furrows (slower walking: it's hand work). On ploughed soil E plants your picked seed (any tool
## or none); the farm takes it from there (water, fertilise, harvest at the plot, as at its beds).
##
## Players stand in the holes: Player sets his own height (dz above y = 0); this node, stepping right after him
## (process_physics_priority 45: after the Player and the Net, before the Fight), adds the ground's height under
## him, and keeps his capsule out of the heightmap (a collision exception) so a hole's wall never shoves him.

const D := preload("res://scripts/dig/dig_data.gd")
const MaskData := preload("res://scripts/dig/dig_mask_data.gd")
const DigMask := preload("res://scripts/dig/dig_mask.gd")
const U := 0.025

static var instance: Dig

signal changed
## A find for player pid: kind "spuds", "coins", "bone", "stash"; n how many (dollars for coins and the stash).
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
var _spot: _Spot
var _racks: Array = []
var _rack_meshes: Dictionary = {}     # "shovel"/"hoe" -> Node3D leaning on the shed
var _dirty := false
var _save_t := 0.0
var _last_hours := -1.0
var _grow_t := 0.0
var _plough_cells := PackedInt32Array()   # ploughed here, not yet sent (online guest)
var _plough_t := 0.0
var _slow := false
var _swing := 0.0
## Online.
var _net_hooked := false
var _was_guest := false
var _was_live := false
var _snap_t := 0.0
var _snap_ver := -1
var _quiet := 0.0
var _last_remote_tool := ""

func _enter_tree() -> void:
	instance = self
	add_to_group("dig")

func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _dirty and persist:
		save()

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
	ground.setup(grid, world)
	grid.changed.connect(_on_grid_changed)
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
	var old: Node = _tool_meshes.get(id)
	if old and is_instance_valid(old):
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

## Where a player's held tool is drawn: at his side, toward where he faces, leaning forward; a dig swings it.
func _pose_tools() -> void:
	for id in _tool_meshes.keys():
		var m: Node3D = _tool_meshes[id]
		if not is_instance_valid(m):
			_tool_meshes.erase(id)
			continue
		var p := m.get_parent() as Node3D
		if p == null:
			continue
		var f: Vector2 = p.get("facing") if p.get("facing") is Vector2 else Vector2(0, 1)
		if f.length() < 0.001:
			f = Vector2(0, 1)
		f = f.normalized()
		var side := Vector2(-f.y, f.x)
		var off := f * 4.0 + side * 15.0
		m.position = Vector3(off.x, 0.0, off.y) * U
		var yaw := atan2(f.x, f.y)
		# (leaning well forward: seen from above an upright tool would be a dot)
		var lean := 1.0 + (0.5 * sin(clampf(_swing, 0.0, 1.0) * PI) if p == _local() else 0.0)
		m.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
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

## The point the tool works at: REACH in front of him.
func target_of(p: Node) -> Vector2:
	return pos_of(p) + facing_of(p) * D.REACH

## What E does here for p (the DigSpot's label).
func label_for(p: Node) -> String:
	if p != _local() or p.get("on_tramp") or p.get("frozen"):
		return ""
	var t := tool_of(p)
	var at := target_of(p)
	if t == "shovel":
		if _field_near(at, D.SPOT * 0.75) >= 0:
			return ""
		return grid.shovel_label(at.x, at.y)
	# planting on ploughed soil (any tool but the shovel): the spot he stands on or faces
	return _plant_label(p)

func _plant_label(p: Node) -> String:
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
		dig_at(p, target_of(p))
	elif l == "FILL":
		fill_at(p, target_of(p))
	elif l.begins_with("PLANT"):
		plant_at(p)

## One shovel press at `at` for player p: deeper, finds, the pile on his right-hand side.
func dig_at(p: Node, at: Vector2) -> Dictionary:
	var f := facing_of(p)
	var side := Vector2(-f.y, f.x)
	var r := grid.dig(at.x, at.y, side, true)
	if not r.get("ok", false):
		return r
	_swing = 1.0
	sound.emit("dig")
	_net_op(["dig", at.x, at.y, side.x, side.y])
	if r.bottom and r.find == "":
		floater.emit("NOTHING", Color("#c8b89a"), at)
	elif r.find != "":
		_award(p, String(r.find), int(r.n), at)
	return r

func fill_at(p: Node, at: Vector2) -> Dictionary:
	var r := grid.fill(at.x, at.y)
	if r.get("ok", false):
		_swing = 1.0
		sound.emit("fill")
		_net_op(["fill", at.x, at.y])
	return r

## The find goes to who dug it: spuds load his spud gun (the fight's fighter), coins and stashes into the
## Wallet (a stash brings a seed too), a bone is a bone.
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
		"coins":
			_pay(n)
			floater.emit("+$%d" % n, Color("#ffd36b"), at)
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

## Plants p's picked seed on the ploughed spot he's at (a farm field plot from then on).
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

## Q / pad X (lobby_alt) with the shovel: fill the hole in front at any depth. (The touch FILL button sends it.)
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("lobby_alt") or event.is_echo():
		return
	var p := _local()
	if p == null or tool_of(p) != "shovel" or p.get("frozen") or not p.get("controls_enabled"):
		return
	if can_fill(p):
		fill_at(p, target_of(p))
		get_viewport().set_input_as_handled()

## Is there a hole in front of p to fill?
func can_fill(p: Node) -> bool:
	var at := target_of(p)
	return grid.depth_at(at.x, at.y) > 0.01 and grid.shovel_label(at.x, at.y) != ""

## ---------------------------------------------------------------- every step

func _physics_process(dt: float) -> void:
	if main == null:
		return
	var me := _local()
	for p in get_tree().get_nodes_in_group("player"):
		if not (p is CharacterBody3D) or not p.is_inside_tree():
			continue
		var id := p.get_instance_id()
		if not _excepted.has(id) and ground and ground.body():
			p.add_collision_exception_with(ground.body())
			_excepted[id] = true
		if p.get("on_tramp"):
			continue
		var hp := GameData.from_3d(p.global_position)
		var gh := grid.height_at(hp.x, hp.y)
		var want := (float(p.get("dz")) + gh) * U
		if absf(p.global_position.y - want) > 0.00001:
			p.global_position.y = want
	if me:
		_plough_step(me, dt)
	_swing = maxf(0.0, _swing - dt * 4.0)

func _plough_step(p: Node, dt: float) -> void:
	_slow = false
	if tool_of(p) != "hoe" or p.get("on_tramp") or p.get("frozen") or float(p.get("roll")) > 0.0:
		return
	var here := pos_of(p)
	if not grid.diggable_at(here.x, here.y):
		return
	_slow = true
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
		_plough_cells.append_array(_with_kinds(cells))
		_plough_t += dt
		if _plough_t > 0.18:
			_plough_t = 0.0
			sound.emit("plough")

func _with_kinds(cells: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in cells:
		out.append(i * 4 + grid.soil[i])
	return out

func _process(dt: float) -> void:
	if main == null:
		return
	_pose_tools()
	_net_step(dt)
	_grow(dt)
	if persist and _dirty and not _is_guest():
		_save_t += dt
		if _save_t > 2.0:
			save()

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

func _net_live() -> bool:
	var n = _net()
	return n != null and n.live

func _net_send(d: Dictionary) -> void:
	var n = _net()
	if n and n.live:
		d["t"] = "dig"
		n._send(d)

## A guest's change goes to the host as an op (the guest's own grid already has it).
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
		_snap_ver = -1
	_was_guest = guest
	if live and not _was_live:
		_snap_t = 99.0                           # just connected: the host sends the ground now
		_net_send({"k": "tool", "tool": tool_of(_local())})
	_was_live = live
	if not live:
		return
	_quiet = maxf(0.0, _quiet - dt)
	if guest:
		if not _plough_cells.is_empty():
			_quiet = 1.5
			_net_send({"k": "op", "op": ["plough", _plough_cells]})
			_plough_cells = PackedInt32Array()
		return
	_plough_cells = PackedInt32Array()
	# the host: the ground when it changed (a few times a second at most), and every 6 s anyway
	_snap_t += dt
	if (_snap_ver != grid.version and _snap_t > 0.4) or _snap_t > 6.0:
		_snap_t = 0.0
		_snap_ver = grid.version
		_net_send({"k": "snap", "p": grid.pack()})

func _on_net(d: Dictionary) -> void:
	if String(d.get("t", "")) != "dig":
		return
	match String(d.get("k", "")):
		"op":
			if not _is_guest():
				apply_op(d.get("op", []))
		"snap":
			if _is_guest() and _quiet <= 0.0:
				var p: Dictionary = d.get("p", {})
				if int(p.get("ver", -1)) != _snap_ver:
					_snap_ver = int(p.get("ver", -1))
					grid.unpack(p)
		"tool":
			var n = _net()
			var p2 = n.get("p2") if n else null
			if p2 and is_instance_valid(p2):
				var t := String(d.get("tool", ""))
				_tools[p2.get_instance_id()] = t
				_show_tool(p2, t)

## The host replays a guest's change (no finds: the guest's own game gave them).
func apply_op(op: Array) -> void:
	if op.is_empty():
		return
	match String(op[0]):
		"dig":
			if op.size() >= 5:
				grid.dig(float(op[1]), float(op[2]), Vector2(float(op[3]), float(op[4])), false)
		"fill":
			if op.size() >= 3:
				grid.fill(float(op[1]), float(op[2]))
		"plough":
			if op.size() >= 2:
				var any := false
				for c in op[1]:
					var i := int(c) / 4
					if i >= 0 and i < D.NX * D.NY and grid.plough_cell(i % D.NX, i / D.NX, int(c) % 4):
						any = true
				if any:
					grid._changed()

## ---------------------------------------------------------------- the E spots

## Where the tool works, in front of the local player: E there digs, fills or plants.
class _Spot extends Interactable:
	var dig: Dig
	func _ready() -> void:
		reach = 60.0
	func _physics_process(_dt: float) -> void:
		var p := dig._local() if dig else null
		if p == null:
			return
		var at := dig.target_of(p)
		global_position = GameData.world_to_3d(at.x, at.y, 0.0)
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
			dig.floater.emit(("SHOVEL: E DIG, Q FILL" if tool == "shovel" else "HOE: WALK TO PLOUGH, E PLANT"),
				Color("#e6e8ee"), Dig.pos_of(player))
