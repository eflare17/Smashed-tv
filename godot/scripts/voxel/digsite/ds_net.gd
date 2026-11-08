class_name DsNet
extends Node
## The Dig Site in co-op (stage 5): the host's game owns the ground and runs its dirt; the guest's shows it. Built as
## the layer the later stages plug into (machines, supports, dynamite, cave-ins), like the shared mine's MineNet:
## - Arriving, the guest asks for the host's ground ("hello"): the host's seed and every chunk changed since it was
##   made (DigSiteGrid.modified_chunks, zstd-packed, in parts). The guest's own site waits, put back when it goes home.
## - Then 15 times a second the host sends the chunks changed since the last time (DigSiteGrid.take_diff, packed),
##   with the number of the guest's last action it has done.
## - Actions (act): a change to the ground (a dig, a fill, a heap dropped) by a handler kind (register_op). Solo or the
##   host: done at once. The guest: done at once on its own copy too (it shows straight away, its backpack gets what
##   came up), and sent; until the host's chunks say it's done there (its number), the guest does it again on top of
##   each update, so a hole doesn't flicker shut.
## - Every HASH_T s the host sends its sections' checksums; the guest (with nothing of its own on the way) compares,
##   asks for any section that's drifted ("fix"), and gets its chunks back.
## - Events (event): one-off things the other game shows (dust and a sound where a tool bit; later booms, creaks), by
##   kind (register_event). Fast states (send_fast): the first byte FAST, then a machine's id byte (register_fast),
##   unreliable, for the machines' movement (stage 6 on).
## Owned by the voxel session.

const DIFF_HZ := 15.0
const HASH_T := 2.0
const PART := 48000
const FAST := 68                # (the fast messages' first byte: a Dig Site machine's state)
const MOST_CHUNKS := 240        # chunks a diff at most (the rest next time)

var site: Node3D                # DigSite
var stats := {"ch": 0, "ch_bytes": 0, "ops": 0, "fixes": 0, "hashes": 0, "match": 0, "world_bytes": 0}
# the host's
var guest_here := false
var _applied := 0               # the guest's last action done here
var _acked := 0                 # (the last number sent back)
var _diff_t := 0.0
var _hash_t := 0.0
# the guest's
var synced := false             # showing the host's ground
var _want := false
var _want_t := 0.0
var _parts := []
var _seq := 0
var _pending := []              # [[seq, kind, args]] not yet done by the host
var _outbox := []
var _out_t := 0.0
var _own := {}                  # its own site while it's at the host's: {seed, chunks}
var last_match := false         # (the tests') the last checksums compared all matched
# both
var _ops := {}                  # kind -> Callable(args: Array, again: bool) -> what it did
var _events := {}               # kind -> Callable(args: Array)
var _fast := {}                 # id -> Callable(d: PackedByteArray)

func setup(s: Node3D) -> void:
	site = s
	name = "Net"

func register_op(kind: String, fn: Callable) -> void:
	_ops[kind] = fn

func register_event(kind: String, fn: Callable) -> void:
	_events[kind] = fn

func register_fast(id: int, fn: Callable) -> void:
	_fast[id] = fn

func _net():
	var a = site.arena
	var n = a.get("net") if a else null
	return n if n != null and n.linked else null

func role() -> String:
	var n = _net()
	return String(n.role) if n else ""

## Whether this game runs the ground (solo, or the host): the dirt, the cave-ins, the machines
func runs() -> bool:
	return role() != "guest"

## Whether this player can change the ground yet (a guest: once it has the host's)
func can_change() -> bool:
	return role() != "guest" or synced

func _send(m: Array) -> void:
	var n = _net()
	if n:
		n.send_digsite(["n"] + m)

func _grid() -> DigSiteGrid:
	return site.terrain.grid

# ---------------------------------------------------------------- actions and events

## A change to the ground: done here now (-> what the handler gave back), and in co-op on the host's too
func act(kind: String, args: Array) -> Variant:
	var fn: Callable = _ops.get(kind, Callable())
	if not fn.is_valid():
		return null
	var out = fn.call(args, false)
	if role() == "guest" and synced:
		_seq += 1
		_pending.append([_seq, kind, args])
		_outbox.append([_seq, kind, args])
		stats.ops += 1
	return out

## Something the other game shows (a tool's dust, a boom): sent if there's another game there
func event(kind: String, args: Array) -> void:
	if (role() == "host" and guest_here) or (role() == "guest" and synced):
		_send(["ev", kind, args])

## A machine's state, fast (unreliable: the newest one counts): id 0 .. 255, then its bytes
func send_fast(id: int, body: PackedByteArray) -> void:
	var n = _net()
	if n == null or not ((role() == "host" and guest_here) or (role() == "guest" and synced)):
		return
	var d := PackedByteArray([FAST, id])
	d.append_array(body)
	n.send_digsite_fast(d)

func on_fast(d: PackedByteArray) -> void:
	if d.size() < 2:
		return
	var fn: Callable = _fast.get(int(d[1]), Callable())
	if fn.is_valid():
		fn.call(d.slice(2))

# ---------------------------------------------------------------- arriving and leaving

## Here (DigSite.go): a guest asks for the host's ground
func arrived() -> void:
	if role() == "guest":
		synced = false
		_want = true
		_want_t = 0.0
		_parts.clear()
		_send(["hello"])

## Gone home (DigSite.home): the guest's own site back; the host stops sending
func left() -> void:
	if role() == "guest" and (synced or _want):
		_send(["bye"])
	_drop_shared()
	guest_here = false

func _drop_shared() -> void:
	if synced and not _own.is_empty():
		var g := _grid()
		if g.get_seed() != int(_own.seed):
			g.generate(int(_own.seed))
		else:
			g.generate(g.get_seed())
		g.apply_chunks(_own.chunks)
		g.clear_touched()
		g.mark_all_dirty()
	_own = {}
	synced = false
	_want = false
	_pending.clear()
	_outbox.clear()

# ---------------------------------------------------------------- each frame

func _process(dt: float) -> void:
	if site == null or not site.active or site.terrain == null:
		return
	var r := role()
	if r == "":
		if synced:
			synced = false          # (the link's gone: what's here is this game's now)
			_own = {}
			_pending.clear()
		guest_here = false
		_want = false
		return
	if r == "guest":
		if _want and not synced:
			_want_t += dt
			if _want_t > 2.5:
				_want_t = 0.0
				_send(["hello"])    # (asked again: the first one lost, or the host still on its way)
		_out_t += dt
		if not _outbox.is_empty() and _out_t >= 1.0 / 30.0:
			_out_t = 0.0
			_send(["ops", _outbox])
			_outbox = []
		return
	# the host: what's changed to the guest, and now and then the checksums
	if not guest_here:
		return
	_diff_t += dt
	_hash_t += dt
	if _diff_t >= 1.0 / DIFF_HZ or _hash_t >= HASH_T:
		_diff_t = 0.0
		_send_diff()
	if _hash_t >= HASH_T:
		_hash_t = 0.0
		_send(["hash", _applied, _grid().section_hashes()])

func _send_diff() -> void:
	var d: PackedByteArray = _grid().take_diff(MOST_CHUNKS)
	if d.size() > 0:
		var z := d.compress(FileAccess.COMPRESSION_ZSTD)
		stats.ch += 1
		stats.ch_bytes += z.size()
		_send(["ch", _applied, d.size(), z])
		_acked = _applied
	elif _applied != _acked:
		_acked = _applied
		_send(["ack", _applied])

# ---------------------------------------------------------------- messages

func on_net(m: Array) -> void:
	if m.is_empty():
		return
	var r := role()
	match String(m[0]):
		"hello":
			# (the host's) the guest's here: the ground as it is, in parts
			if r != "host" or site.terrain == null:
				return
			var g := _grid()
			_send_diff()                                  # (anything changed meanwhile goes the usual way first)
			var all := g.pack_chunks(g.modified_chunks())
			var z := all.compress(FileAccess.COMPRESSION_ZSTD)
			g.clear_touched()
			_applied = 0
			_acked = 0
			guest_here = true
			stats.world_bytes = z.size()
			var n := maxi(1, ceili(float(z.size()) / PART))
			for i in n:
				_send(["world", g.get_seed(), i, n, all.size(), z.slice(i * PART, mini(z.size(), (i + 1) * PART))])
		"world":
			# (the guest's) a part of the host's ground; the last one in: it's shown
			if r != "guest" or not _want or m.size() < 6:
				return
			_parts.append(m[5])
			if _parts.size() < int(m[3]):
				return
			var z := PackedByteArray()
			for p in _parts:
				z.append_array(p)
			_parts.clear()
			var all := z.decompress(int(m[4]), FileAccess.COMPRESSION_ZSTD) if int(m[4]) > 0 else PackedByteArray()
			var g := _grid()
			_own = {"seed": g.get_seed(), "chunks": g.pack_chunks(g.modified_chunks())}
			if g.get_seed() != int(m[1]) or not g.modified_chunks().is_empty():
				g.generate(int(m[1]))
				g.mark_all_dirty()
			g.apply_chunks(all)
			g.clear_touched()
			synced = true
			_want = false
			_seq = 0
			_pending.clear()
			_outbox.clear()
			site.terrain.build_now(400.0)
		"bye":
			if r == "host":
				guest_here = false
		"ops":
			# (the host's) the guest's actions, done to the real ground
			if r != "host" or not guest_here:
				return
			for e in m[1]:
				if typeof(e) != TYPE_ARRAY or e.size() < 3:
					continue
				var fn: Callable = _ops.get(String(e[1]), Callable())
				if fn.is_valid():
					fn.call(e[2], false)
				_applied = maxi(_applied, int(e[0]))
		"ch":
			# (the guest's) the host's changed chunks; then its own actions not done there yet, again on top
			if r != "guest" or not synced or m.size() < 4:
				return
			var d: PackedByteArray = (m[3] as PackedByteArray).decompress(int(m[2]), FileAccess.COMPRESSION_ZSTD)
			_grid().apply_chunks(d)
			stats.ch += 1
			stats.ch_bytes += (m[3] as PackedByteArray).size()
			_done_upto(int(m[1]), true)
		"ack":
			if r == "guest" and synced:
				_done_upto(int(m[1]), false)
		"hash":
			if r != "guest" or not synced or m.size() < 3:
				return
			stats.hashes += 1
			if not _pending.is_empty() or not _outbox.is_empty() or int(m[1]) < _seq:
				return              # (its own on the way: they'd differ for now anyway)
			var theirs: PackedInt32Array = m[2]
			var mine := _grid().section_hashes()
			var bad := PackedInt32Array()
			for s in mini(theirs.size(), mine.size()):
				if theirs[s] != mine[s]:
					bad.append(s)
			last_match = bad.is_empty()
			if last_match:
				stats.match += 1
			else:
				_send(["fix", bad])
		"fix":
			# (the host's) sections the guest's got wrong: their chunks again
			if r != "host":
				return
			var g := _grid()
			var list := PackedInt32Array()
			for s in m[1]:
				list.append_array(g.section_chunks(int(s)))
			var all := g.pack_chunks(list)
			_send(["fixd", all.size(), all.compress(FileAccess.COMPRESSION_ZSTD)])
		"fixd":
			if r == "guest" and synced and m.size() >= 3:
				_grid().apply_chunks((m[2] as PackedByteArray).decompress(int(m[1]), FileAccess.COMPRESSION_ZSTD))
				stats.fixes += 1
				_redo_pending()
		"ev":
			if m.size() >= 3:
				var fn: Callable = _events.get(String(m[1]), Callable())
				if fn.is_valid():
					fn.call(m[2])

func _done_upto(seq: int, redo: bool) -> void:
	while not _pending.is_empty() and int(_pending[0][0]) <= seq:
		_pending.pop_front()
	if redo:
		_redo_pending()

func _redo_pending() -> void:
	for e in _pending:
		var fn: Callable = _ops.get(String(e[1]), Callable())
		if fn.is_valid():
			fn.call(e[2], true)
