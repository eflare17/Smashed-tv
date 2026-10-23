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
## vacuums are given to them by the host, and stacks dropped on the floor fall in both games.
##
## Stage 3: the chests at the ends of the bedroom's beds (one each, a padlock hanging open on each to start with) and
## their padlocks: locking (the code the wheels show), dialling (each turn tried), taking one off or hanging one on all
## go through here; in co-op through the host, which alone keeps the codes (a guest's game is only told locked or
## not). Owned by the voxel session.

const SAVE_PATH := "user://voxel_arena_save.json"
const SAVE_WAIT := 1.5          # seconds after the last change before saving
const VB_HZ := 10.0             # vacuum brush messages a second
## [id, kind, position, yaw, owner]: two chests and a cabinet against the north wall, facing the middle (anyone's); a
## chest at the foot of each bed in the bedroom is made after them (player 1's, player 2's).
const PLACES := [["chest_a", "chest", Vector3(-3.2, 0, -20.95), 0.0, 0], ["cabinet_a", "cabinet", Vector3(0.0, 0, -21.15), 0.0, 0],
	["chest_b", "chest", Vector3(3.2, 0, -20.95), 0.0, 0]]
const BED_CHESTS := ["bed_chest_1", "bed_chest_2"]

var arena: Node3D
var list: Array[VoxelStorage] = []
var by_id := {}
var save_path := SAVE_PATH      # "" : never saved (tests)
var _dirty := false
var _save_t := 0.0
var _send := {}                 # host: storage id -> true (changed: to send)
var _own_chests = null          # guest: their own chests' data while the host's are shown (null: not a guest)
var _own_locks = null           # ... and their padlocks
var _vb_t := 0.0
var _vb_s := 0.0                # seconds it sucked since the last brush message (the other game clears as much as that)
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
		st.belongs = int(p[4])
		list.append(st)
		by_id[st.sid] = st
		st.inv.changed.connect(_changed.bind(st))
	for i in [1, 2]:
		var bc := VoxelStorage.new()
		add_child(bc)
		bc.setup(BED_CHESTS[i - 1], "chest", arena.sound)
		bc.position = VoxelBedroom.chest_spot(i)
		bc.belongs = i
		bc.set_lock(true, false)          # (a padlock hanging open on it to start with)
		list.append(bc)
		by_id[bc.sid] = bc
		bc.inv.changed.connect(_changed.bind(bc))
	name_them()
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

## The one a first-person look lands on first within reach: [storage or null, how far].
func pick_ray(eye: Vector3, dir: Vector3, reach: float = 2.4) -> Array:
	var best: VoxelStorage = null
	var bd := INF
	for st in list:
		var d := st.hit_dist(eye, dir, reach)
		if d < bd:
			bd = d
			best = st
	return [best, bd]

## The one the player is near and facing (top-down) within reach (null if none).
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

## The bed chests' names as this player sees them: their own, their mate's (or the spare one, alone).
func name_them() -> void:
	var me := my_pid()
	var linked: bool = arena.net != null and arena.net.linked
	for st in list:
		if st.belongs == 0:
			st.title = String(VoxelStorage.KINDS[st.kind].name)
		elif st.belongs == me:
			st.title = "Your chest"
		else:
			st.title = "Mate's chest" if linked else "Spare chest"

## Which player this is: 2 a guest in someone's game, else 1 (alone or hosting: your own bed is player 1's).
func my_pid() -> int:
	return 2 if _is_guest() else 1

func _process(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if _was_role == "guest" and _own_chests != null:
			_set_all(_own_chests)        # (back from someone else's game: our own chests again)
			_set_locks(_own_locks)
			_own_chests = null
			_own_locks = null
		if role == "host":
			send_all()
		_was_role = role
		name_them()
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
	if not (arena.net and arena.net.linked):
		_vb = Vector3.INF            # (alone: nothing to tell, nor a stale brush on linking)
		_vb_s = 0.0
	elif _vb != Vector3.INF and _vb_t >= 1.0 / VB_HZ:
		_msg(["vb", _vb, _vb_r, _vb_s])
		_vb_t = 0.0
		_vb_s = 0.0
		_vb = Vector3.INF

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# quitting: a stack held on the inventory screen put back first (not lost), and everything saved (the plants'
		# growth and the worms' work don't mark it changed as they go)
		if arena.inv_ui and is_instance_valid(arena.inv_ui) and arena.inv_ui.is_open():
			arena.inv_ui.close()
		save()
	elif what == NOTIFICATION_EXIT_TREE:
		if _dirty:
			save()

# ---------------------------------------------------------------- moving stacks (the inventory screen calls these)

## Up to n (n < 0: all) out of a storage's slot, expecting item id there. Alone or hosting: the stack taken, now.
## A guest: {} now, and the host gives it a moment later (where: "cursor" in the hand, "inv" in the backpack).
func take(st: VoxelStorage, slot: int, n: int, where: String) -> Dictionary:
	if st.locked:
		return {}
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
	if st.locked:
		return stack
	if _is_guest():
		_msg(["put", st.sid, slot, stack.id, int(stack.n)])
		return {}
	return st.inv.put_at(slot, stack)

## A stack put anywhere in a storage (shift-click from the backpack). Returns what didn't fit (a guest: given back
## into the backpack).
func add(st: VoxelStorage, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	if st.locked:
		return stack
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
	_vb_s += get_process_delta_time()

## A stack dropped on the floor here: the other game drops the same cubes, thrown the same way (seed).
func dropped(at: Vector3, dir: Vector3, id: String, n: int, seed: int) -> void:
	_msg(["drop", at, dir, id, n, seed])

func open_changed(st: VoxelStorage) -> void:
	_msg(["lid", st.sid, st.open_here])

# ---------------------------------------------------------------- padlocks

## A locked padlock's wheels turned to code: open if it's the code (alone / hosting: now; a guest: the host says).
func try_code(st: VoxelStorage, code: String) -> void:
	if _is_guest():
		_msg(["try", st.sid, code])
	elif st.locked and code == st.combo:
		_lock_set(st, true, false)

## An open padlock shut, its code what the wheels show.
func lock(st: VoxelStorage, code: String) -> void:
	if _is_guest():
		st.set_lock(true, true)          # (shown shut straight away; the host keeps the code)
		_msg(["lock", st.sid, code])
	elif st.has_lock and not st.locked:
		st.combo = code
		_lock_set(st, true, true)

## An open padlock taken off the chest, into this player's backpack.
func lock_off(st: VoxelStorage) -> void:
	if not st.has_lock or st.locked:
		return
	if _is_guest():
		_msg(["lockoff", st.sid])
		return
	_lock_set(st, false, false)
	arena.receive({"id": "padlock", "n": 1}, "inv")

## A padlock from the backpack hung (open) on a chest that has none. False: none to hang or it has one.
func lock_on(st: VoxelStorage) -> bool:
	if st.has_lock or arena.inv.count("padlock") <= 0:
		return false
	arena.inv.remove("padlock", 1)
	if _is_guest():
		_msg(["lockon", st.sid])
	else:
		_lock_set(st, true, false)
	return true

# the host's (or alone): a padlock's state changed: shown, saved, told
func _lock_set(st: VoxelStorage, has: bool, shut: bool) -> void:
	var combo := st.combo
	st.set_lock(has, shut)
	if has:
		st.combo = combo
	_dirty = true
	_save_t = 0.0
	_msg(["lk", st.sid, has, shut])
	arena.on_lock_changed(st)

# ---------------------------------------------------------------- co-op messages

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_storage(m)

## The host's chests, all of them (the guest just came, or asked).
func send_all() -> void:
	if _is_host():
		_msg(["all", to_data(), _lids(), locks_data(false)])

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
				_own_locks = locks_data(true)
			_set_all(m[1])
			_set_locks(m[3] if m.size() > 3 else {})
			for st in list:
				st.open_there = (m[2] as Array).has(st.sid)
				arena.on_lock_changed(st)
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
		"try":
			var stt: VoxelStorage = by_id.get(String(m[1]))
			if host and stt and stt.locked and String(m[2]) == stt.combo:
				_lock_set(stt, true, false)
		"lock":
			var stl: VoxelStorage = by_id.get(String(m[1]))
			if host and stl and stl.has_lock and not stl.locked:
				stl.combo = String(m[2])
				_lock_set(stl, true, true)
			elif host and stl:
				_msg(["lk", stl.sid, stl.has_lock, stl.locked])      # (couldn't: put the guest's copy right)
		"lockoff":
			var sto: VoxelStorage = by_id.get(String(m[1]))
			if host and sto and sto.has_lock and not sto.locked:
				_lock_set(sto, false, false)
				_msg(["give", {"id": "padlock", "n": 1}, "inv"])
		"lockon":
			var stn: VoxelStorage = by_id.get(String(m[1]))
			if host and stn and not stn.has_lock:
				_lock_set(stn, true, false)
			elif host:
				_msg(["give", {"id": "padlock", "n": 1}, "inv"])      # (it has one already: theirs back)
		"lk":
			var stk: VoxelStorage = by_id.get(String(m[1]))
			if _is_guest() and stk:
				stk.set_lock(bool(m[2]), bool(m[3]))
				arena.on_lock_changed(stk)
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

## The padlocks: {id: [has one, shut, code]} (with_codes false: the code left out, for a guest).
func locks_data(with_codes: bool) -> Dictionary:
	var d := {}
	for st in list:
		d[st.sid] = [st.has_lock, st.locked, st.combo if with_codes else ""]
	return d

func _set_locks(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	for sid in d:
		var st: VoxelStorage = by_id.get(String(sid))
		var e = d[sid]
		if st and typeof(e) == TYPE_ARRAY and (e as Array).size() == 3:
			st.set_lock(bool(e[0]), bool(e[1]))
			st.combo = String(e[2])
			if st.locked and st.combo.length() != 4 and not _is_guest():
				st.set_lock(true, false)      # (a lock saved shut with no code could never open: left open)

## The backpack and the chests written out (a guest in someone's game: its own chests as they were).
func save() -> void:
	_dirty = false
	_save_t = 0.0
	if save_path == "":
		return
	var d := {"v": 1, "inv": arena.inv.to_data(), "storage": _own_chests if _own_chests != null else to_data(),
		"locks": _own_locks if _own_locks != null else locks_data(true), "tools": {"shovel": arena.shovel_tier, "upg": arena.me.upg if arena.me else arena._upg},
		"cash": arena.cash, "waiting": arena.waiting}
	if arena.yard:
		d["yard"] = arena.yard.save_data()
		d["farm"] = arena.yard.farm.save_data()
		d["chickens"] = arena.yard.chickens.save_data()
		d["shredder"] = arena.yard.shredder.save_data()
	if arena.get("mine"):
		d["mine"] = arena.mine.save_data()
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
	_set_locks(d.get("locks"))
	if typeof(d.get("tools")) == TYPE_DICTIONARY:
		arena.set_shovel_tier(int(d.tools.get("shovel", 0)))
		arena.set_upgrades(d.tools.get("upg", {}))
	if arena.yard and d.has("yard"):
		arena.yard.load_data(d.yard)
	if arena.yard and d.has("farm"):
		arena.yard.farm.from_data(d.farm)
	if arena.yard and d.has("chickens"):
		arena.yard.chickens.from_data(d.chickens)
	if arena.yard and d.has("shredder"):
		arena.yard.shredder.from_data(d.shredder)
	arena.cash = maxi(0, int(d.get("cash", 0)))
	if arena.get("mine") and d.has("mine"):
		arena.mine.load_data(d.mine)
	arena.waiting = []
	if typeof(d.get("waiting")) == TYPE_ARRAY:
		for w in d.waiting:
			if typeof(w) == TYPE_DICTIONARY and VoxelItems.has(String(w.get("id", ""))) and int(w.get("n", 0)) > 0:
				arena.waiting.append({"id": String(w.id), "n": int(w.n)})
	_dirty = false
