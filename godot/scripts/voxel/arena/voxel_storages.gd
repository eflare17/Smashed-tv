class_name VoxelStorages
extends Node3D
## The arena's chests and cabinets, and keeping what's in them (the owner, 21 Oct, Stage 2). It builds them along the
## north wall, keeps the backpack and their insides saved between games (user://voxel_arena_save.json, a moment after
## anything changes and at quit), and is the one place the inventory screen moves stacks in and out of them through.
##
## Co-op: the host's chests are the real ones. The host's moves happen straight away; a guest's go to the host as a
## request (take this stack, put this one there) and come back as a "give" of what ends up in their hand or backpack,
## so two players at one chest can never make anything twice. Every change to a chest goes to the guest whole (a few
## hundred bytes). A guest keeps their own chests' save while away and gets them back on leaving. Also here: each
## player's vacuum clears the same lying cubes in the other's game (brush messages), the corpses and pieces a guest
## vacuums are given to them by the host, and stacks dropped on the floor fall in both games. Owned by the voxel
## session.

const SAVE_PATH := "user://voxel_arena_save.json"
const SAVE_WAIT := 1.5          # seconds after the last change before saving
const VB_HZ := 10.0             # vacuum brush messages a second
## [id, kind, position, yaw]: two chests and a cabinet against the north wall, facing the middle.
const PLACES := [["chest_a", "chest", Vector3(-3.2, 0, -20.95), 0.0], ["cabinet_a", "cabinet", Vector3(0.0, 0, -21.15), 0.0],
	["chest_b", "chest", Vector3(3.2, 0, -20.95), 0.0]]

var arena: Node3D
var list: Array[VoxelStorage] = []
var by_id := {}
var save_path := SAVE_PATH      # "" : never saved (tests)
var _dirty := false
var _save_t := 0.0
var _send := {}                 # host: storage id -> true (changed: to send)
var _own_chests = null          # guest: their own chests' data while the host's are shown (null: not a guest)
var _vb_t := 0.0
var _vb := Vector3.INF
var _vb_r := 0.0
var _was_role := ""

func setup(arena_: Node3D) -> void:
	arena = arena_
	for p in PLACES:
		var st := VoxelStorage.new()
		add_child(st)
		st.setup(String(p[0]), String(p[1]), arena.sound)
		st.position = p[2]
		st.rotation.y = float(p[3])
		list.append(st)
		by_id[st.sid] = st
		st.inv.changed.connect(_changed.bind(st))
	arena.inv.changed.connect(func(): _dirty = true; _save_t = 0.0)

## Walkers (players, enemies) kept out of them: [centre, half width, half depth], level.
func blocks() -> Array:
	var out := []
	for st in list:
		var h := st.half()
		if absf(sin(st.rotation.y)) > 0.7:
			h = Vector2(h.y, h.x)
		out.append([st.global_position, h.x, h.y])
	return out

## The one the player is looking at within reach (null if none).
func pick(eye: Vector3, dir: Vector3, reach: float = 1.6) -> VoxelStorage:
	var best: VoxelStorage = null
	var bs := 0.0
	for st in list:
		var s := st.pick_score(eye, dir, reach)
		if s > bs:
			bs = s
			best = st
	return best

func _changed(st: VoxelStorage) -> void:
	_dirty = true
	_save_t = 0.0
	if _is_host():
		_send[st.sid] = true

func _is_guest() -> bool:
	return arena.net != null and arena.net.role == "guest" and arena.net.linked

func _is_host() -> bool:
	return arena.net != null and arena.net.role == "host" and arena.net.linked

func _process(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if _was_role == "guest" and _own_chests != null:
			_set_all(_own_chests)        # (back from someone else's game: our own chests again)
			_own_chests = null
		if role == "host":
			send_all()
		_was_role = role
	if not _send.is_empty() and _is_host():
		for sid in _send:
			if by_id.has(sid):
				_msg(["set", sid, (by_id[sid] as VoxelStorage).inv.to_data()])
		_send.clear()
	if _dirty:
		_save_t += dt
		if _save_t >= SAVE_WAIT:
			save()
	_vb_t += dt
	if _vb != Vector3.INF and _vb_t >= 1.0 / VB_HZ and arena.net and arena.net.linked:
		_msg(["vb", _vb, _vb_r, _vb_t])
		_vb_t = 0.0
		_vb = Vector3.INF

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _dirty:
			save()

# ---------------------------------------------------------------- moving stacks (the inventory screen calls these)

## Up to n (n < 0: all) out of a storage's slot, expecting item id there. Alone or hosting: the stack taken, now.
## A guest: {} now, and the host gives it a moment later (where: "cursor" in the hand, "inv" in the backpack).
func take(st: VoxelStorage, slot: int, n: int, where: String) -> Dictionary:
	if _is_guest():
		var s := st.inv.at(slot)
		if not s.is_empty():
			_msg(["take", st.sid, slot, n, String(s.id), where])
		return {}
	return st.inv.take_at(slot, n)

## A stack put down in a storage's slot. Alone or hosting: what's left in the hand. A guest: {} (it's gone from the
## hand; what didn't go in, or what it swapped with, is given back into the hand).
func put(st: VoxelStorage, slot: int, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	if _is_guest():
		_msg(["put", st.sid, slot, stack.id, int(stack.n)])
		return {}
	return st.inv.put_at(slot, stack)

## A stack put anywhere in a storage (shift-click from the backpack). Returns what didn't fit (a guest: given back
## into the backpack).
func add(st: VoxelStorage, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	if _is_guest():
		_msg(["add", st.sid, stack.id, int(stack.n)])
		return {}
	var left := st.inv.add(stack.id, int(stack.n))
	return {} if left == 0 else {"id": stack.id, "n": left}

## The other player's vacuum took corpses or pieces in the host's game: what was in them, theirs.
func give_other(counts: Dictionary) -> void:
	for id in counts:
		if int(counts[id]) > 0:
			_msg(["give", {"id": id, "n": int(counts[id])}, "inv"])

## This player's vacuum brush on the lying cubes (each frame it sucks): the other game clears the same ones.
func vac_brush(at: Vector3, r: float) -> void:
	_vb = at
	_vb_r = r

## A stack dropped on the floor here: the other game drops the same cubes, thrown the same way (seed).
func dropped(at: Vector3, dir: Vector3, id: String, n: int, seed: int) -> void:
	_msg(["drop", at, dir, id, n, seed])

func open_changed(st: VoxelStorage) -> void:
	_msg(["lid", st.sid, st.open_here])

# ---------------------------------------------------------------- co-op messages

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_storage(m)

## The host's chests, all of them (the guest just came, or asked).
func send_all() -> void:
	if _is_host():
		_msg(["all", to_data(), _lids()])

func _lids() -> Array:
	var out := []
	for st in list:
		if st.open_here:
			out.append(st.sid)
	return out

func on_net(m: Array) -> void:
	var op := String(m[0])
	var host := _is_host()
	match op:
		"all":
			if not _is_guest():
				return
			if _own_chests == null:
				_own_chests = to_data()
			_set_all(m[1])
			for st in list:
				st.open_there = (m[2] as Array).has(st.sid)
		"set":
			if _is_guest() and by_id.has(String(m[1])):
				(by_id[String(m[1])] as VoxelStorage).inv.from_data(m[2])
		"take":
			var st: VoxelStorage = by_id.get(String(m[1]))
			if host and st and int(m[2]) >= 0 and int(m[2]) < st.inv.size():
				var s := st.inv.at(int(m[2]))
				if not s.is_empty() and String(s.id) == String(m[4]):
					var got := st.inv.take_at(int(m[2]), int(m[3]))
					_msg(["give", got, String(m[5])])
		"put":
			var st2: VoxelStorage = by_id.get(String(m[1]))
			var stack := {"id": String(m[3]), "n": int(m[4])}
			if host and VoxelItems.has(stack.id) and int(stack.n) > 0:
				var left := stack
				if st2 and int(m[2]) >= 0 and int(m[2]) < st2.inv.size():
					left = st2.inv.put_at(int(m[2]), stack)
				if not left.is_empty():
					_msg(["give", left, "cursor"])
		"add":
			var st3: VoxelStorage = by_id.get(String(m[1]))
			if host and VoxelItems.has(String(m[2])) and int(m[3]) > 0:
				var left2 := int(m[3])
				if st3:
					left2 = st3.inv.add(String(m[2]), int(m[3]))
				if left2 > 0:
					_msg(["give", {"id": String(m[2]), "n": left2}, "inv"])
		"give":
			var g: Dictionary = m[1]
			if not g.is_empty() and VoxelItems.has(String(g.get("id", ""))) and int(g.get("n", 0)) > 0:
				arena.receive({"id": String(g.id), "n": int(g.n)}, String(m[2]))
		"lid":
			var st4: VoxelStorage = by_id.get(String(m[1]))
			if st4:
				st4.open_there = bool(m[2])
		"vb":
			arena.debris.clear_near(m[1], float(m[2]), int(VoxelDebris.RATE * minf(float(m[3]), 0.5) * 1.3))
		"drop":
			if VoxelItems.has(String(m[3])):
				arena.drop_cubes(m[1], m[2], String(m[3]), clampi(int(m[4]), 0, VoxelItems.stack_max(String(m[3]))), int(m[5]))

# ---------------------------------------------------------------- saving

func to_data() -> Dictionary:
	var d := {}
	for st in list:
		d[st.sid] = st.inv.to_data()
	return d

func _set_all(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	for sid in d:
		if by_id.has(String(sid)):
			(by_id[String(sid)] as VoxelStorage).inv.from_data(d[sid])

## The backpack and the chests written out (a guest in someone's game: its own chests as they were).
func save() -> void:
	_dirty = false
	_save_t = 0.0
	if save_path == "":
		return
	var d := {"v": 1, "inv": arena.inv.to_data(), "storage": _own_chests if _own_chests != null else to_data()}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_save() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return
	if typeof(d.get("inv")) == TYPE_ARRAY:
		arena.inv.from_data(d.inv)
	_set_all(d.get("storage"))
	_dirty = false
