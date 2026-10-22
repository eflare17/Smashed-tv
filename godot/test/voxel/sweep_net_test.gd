extends SceneTree
## The bug sweep's co-op fixes, each checked (headless): a guest's copies of the host's pieces fall and settle on the
## floor when the link goes (not hang in the air); a guest never culls the host's piece copies by its own cap; the
## vacuum brush's message carries only the time it sucked (not the idle time before); a direct join takes an IPv6
## address whole; the TV's picture goes in unreliable pieces over ENet; an internet guest that lost the connection
## isn't told "room not found" later; the guest's clock follows the host's snapshots back into step; a fix ("G") goes
## after the events already pending; a piece settled while no one was there doesn't stop the world going to the next
## guest. Prints "SWN ok/FAIL ..." and "SWN done N passed, M failed". Owned by the voxel session.

const TV_PORT := 24698

class FakeTr extends NetTransport:
	var sent := []
	func send(d: PackedByteArray) -> void:
		sent.append(d)

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v0 := {}
var tv_host: VoxelEnetTransport
var tv_cl: ENetConnection
var tv_up := false
var tv_sent := false
var tv_got := {}

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("SWN %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _body(key: String, at: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(key, arena._cube_m(key), 1, arena._mat)
	b.position = at
	arena.bodies.append(b)
	b.hp = 1e9
	return b

# a forearm's worth of piece (as the host announces one)
func _piece_list(b: VoxelBody) -> Array:
	return b.as_pieces().filter(func(e): return String(e.part) == "forearm_l")

# the reliable messages a fake line was given, decoded
static func _msgs(tr: FakeTr) -> Array:
	var out := []
	for d in tr.sent:
		if (d as PackedByteArray)[0] == 82:
			out.append(bytes_to_var((d as PackedByteArray).slice(1)))
	return out

func _clear_pieces() -> void:
	for pc in arena.pieces._pieces:
		if is_instance_valid(pc.rb):
			pc.rb.queue_free()
	arena.pieces._pieces.clear()

# ---------------------------------------------------------------- the checks done at once

func _at_once() -> void:
	var net: VoxelNet = arena.net
	var src := _body("grunt", Vector3(0, 0, -12))
	var list := _piece_list(src)
	# a guest doesn't cull the host's copies by its own cap (the host's "q" takes them)
	var cap0 := VoxelPieces.MAX_PIECES
	VoxelPieces.MAX_PIECES = 3
	_clear_pieces()
	arena.pieces.puppet = true
	var copies := []
	for i in 5:
		copies.append(arena.pieces.spawn_copy(src.key, src.chunk_n, src.vm, list, Transform3D(Basis(), Vector3(i * 0.6 - 1.2, 2.0, -8))))
	var kept := 0
	for rb in copies:
		if is_instance_valid(rb) and not (rb as Node).is_queued_for_deletion():
			kept += 1
	check(kept == 5 and arena.pieces.count() == 5, "a guest on a lower cap (3) keeps all 5 of the host's piece copies (%d kept)" % kept)
	arena.pieces.puppet = false
	arena.pieces.spawn(src, list, Vector3.ZERO, Vector3.ZERO)
	check(arena.pieces.count() == 3, "alone again: the next piece trims to the cap (%d)" % arena.pieces.count())
	VoxelPieces.MAX_PIECES = cap0
	_clear_pieces()

	# the vacuum brush: the message carries the time it sucked, not the idle time before
	var ft := FakeTr.new()
	net.tr = ft
	net.role = "host"
	net.linked = true
	var st: VoxelStorages = arena.stash
	var pdt := root.get_process_delta_time()
	st._vb_t = 3.0                     # (three seconds idle)
	st._vb = Vector3.INF
	st._vb_s = 0.0
	ft.sent.clear()
	st.vac_brush(Vector3(1, 0.4, 1), 0.8)
	st._process(1.0 / 60.0)
	var vbs := _msgs(ft).filter(func(m): return m.size() > 1 and String(m[0]) == "S" and String(m[1]) == "vb")
	check(vbs.size() == 1 and float(vbs[0][4]) <= pdt + 0.001,
		"a tap of the vacuum after 3 s idle: the other game clears a frame's worth (%.3f s, not 3 s)" % (float(vbs[0][4]) if vbs.size() > 0 else -1.0))
	ft.sent.clear()
	for i in 12:
		st.vac_brush(Vector3(1, 0.4, 1), 0.8)
		st._process(1.0 / 60.0)
	var sum := 0.0
	vbs = _msgs(ft).filter(func(m): return m.size() > 1 and String(m[0]) == "S" and String(m[1]) == "vb")
	for m in vbs:
		sum += float(m[4])
	check(vbs.size() >= 1 and absf(sum + st._vb_s - 12.0 * pdt) < 0.002,
		"sucking 12 frames: the messages carry the 12 frames' time (%.3f + %.3f waiting)" % [sum, st._vb_s])
	net.linked = false
	st.vac_brush(Vector3(1, 0.4, 1), 0.8)
	st._process(1.0 / 60.0)
	net.linked = true
	ft.sent.clear()
	st._vb_t = 1.0
	st._process(1.0 / 60.0)
	vbs = _msgs(ft).filter(func(m): return m.size() > 1 and String(m[0]) == "S" and String(m[1]) == "vb")
	check(vbs.is_empty(), "a brush from playing alone isn't sent when linked")

	# a fix ("G") goes after this frame's pending events (they're in it: replayed after, they'd be done twice)
	var fnet := VoxelNet.new()
	fnet.setup(arena)
	var ft2 := FakeTr.new()
	fnet.tr = ft2
	fnet.role = "host"
	fnet.linked = true
	var fb := _body("grunt", Vector3(2, 0, -12))
	fb.net_id = 77
	fnet._bodies[77] = fb
	fnet._out.append(["m", 77, "hurt", [5.0], []])
	fnet._message(["F", [77]])
	var kinds := []
	for m in _msgs(ft2):
		kinds.append(String(m[0]))
	check(kinds == ["E", "G"] and fnet._out.is_empty(), "a fix asked for: the pending events go first, then the fix (%s)" % str(kinds))

	# a piece settled while no one was linked: the world still goes to the next guest
	ft2.sent.clear()
	var gone := RigidBody3D.new()
	arena.add_child(gone)
	fnet._pieces[999] = gone
	gone.free()
	fnet._send_world()
	kinds = []
	for m in _msgs(ft2):
		kinds.append(String(m[0]))
	check(kinds.has("W"), "a stale piece left from the last guest: the world ('W') is still sent (%s)" % str(kinds))
	fnet.free()

	# the guest's clock: set while the line was slow (0.3 s off), the snapshots bring it back in step
	var hn := VoxelNet.new()
	hn.setup(arena)
	var gn := VoxelNet.new()
	gn.setup(arena)
	gn.role = "guest"
	hn._clock = 100.0
	gn._read_snapshot(hn._snapshot())
	var set0 := gn._clock
	gn._clock -= 0.3
	for i in 80:
		hn._clock += 0.05
		gn._clock += 0.05
		gn._read_snapshot(hn._snapshot())
	check(is_equal_approx(set0, 100.0) and absf(gn._clock - hn._clock) < 0.03,
		"the guest's clock 0.3 s off the host's: four seconds of snapshots bring it in step (%.3f off)" % absf(gn._clock - hn._clock))
	hn.free()
	gn.free()

	net.tr = null
	net.linked = false
	net.role = ""

	# a direct join: an IPv6 address taken whole (its last group isn't a port)
	var et := VoxelEnetTransport.new()
	var cases := [["FD7A:115C:A1E0::5", "FD7A:115C:A1E0::5", VoxelEnetTransport.PORT], ["::1", "::1", VoxelEnetTransport.PORT],
		["[fd7a::5]:5000", "fd7a::5", 5000], ["192.168.1.20:3000", "192.168.1.20", 3000], ["203.0.113.5", "203.0.113.5", VoxelEnetTransport.PORT],
		["somewhere", "127.0.0.1", VoxelEnetTransport.PORT]]
	var bad := []
	for c in cases:
		et.join(String(c[0]))
		if et._addr != String(c[1]) or et._port != int(c[2]):
			bad.append("%s -> %s:%d" % [c[0], et._addr, et._port])
		et._peer = null              # (nothing sent to these made-up addresses on closing)
		et._enet = null
	et.close()
	check(bad.is_empty(), "a direct join's address: IPv6 whole, [v6]:port, v4:port, v4 (%s)" % str(bad))

	# an internet guest that lost the connection isn't told "room not found" twenty seconds on
	var rt := VoxelRtcTransport.new()
	rt._role = "guest"
	rt._code = "K7QD"
	rt._ws_up = true
	rt._open = true
	rt._wait = 2.0
	var said := []
	rt.status.connect(func(tx, _k): said.append(String(tx)))
	rt._lost()
	for i in 60:
		rt._clock = Time.get_ticks_msec() / 1000.0 - 0.5
		rt.poll()
	check(said.has("lost the connection") and not said.any(func(s): return String(s).contains("not found")),
		"an internet guest's connection lost: no 'room not found' 30 s later (%s)" % str(said))

	# the TV's picture over ENet: a long fast message arrives in unreliable pieces
	tv_host = VoxelEnetTransport.new()
	tv_host.port = TV_PORT
	tv_host.host("TV")
	tv_cl = ENetConnection.new()
	tv_cl.create_host(1, 2)
	tv_cl.connect_to_host("127.0.0.1", TV_PORT, 2)

	# a guest's copy of the host's piece, in the air (the link goes in a moment)
	var cp: RigidBody3D
	arena.pieces.puppet = true
	net.role = "guest"
	net.linked = true
	cp = arena.pieces.spawn_copy(src.key, src.chunk_n, src.vm, list, Transform3D(Basis(), Vector3(0, 3.0, -8)))
	v0.cp = cp
	v0.y0 = cp.global_position.y
	v0.bodies = arena.bodies.duplicate()

func _tv_poll() -> void:
	if tv_host == null:
		return
	tv_host.poll()
	while true:
		var ev := tv_cl.service()
		var type: int = ev[0]
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var p: ENetPacketPeer = ev[1]
		if type == ENetConnection.EVENT_CONNECT:
			tv_up = true
		elif type == ENetConnection.EVENT_RECEIVE:
			var flags := p.get_packet_flags()
			var d := p.get_packet()
			if d.size() == 6000:
				tv_got = {"flags": flags, "size": d.size()}
	if tv_up and tv_host.is_open() and not tv_sent:
		var big := PackedByteArray()
		big.resize(6000)
		big.fill(7)
		tv_host.send_fast(big)
		tv_sent = true

func _process(dt: float) -> bool:
	t += dt
	_tv_poll()
	if t < 1.0:
		return false
	match step:
		0:
			arena.frozen = true
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			_at_once()
			mark = t
			step = 1
		1:
			if t - mark < 0.2:
				return false
			var cp: RigidBody3D = v0.cp
			check(is_instance_valid(cp) and cp.freeze and absf(cp.global_position.y - float(v0.y0)) < 0.01,
				"linked: the guest's copy stays where the host's positions put it (frozen)")
			arena.net._on_disconnected()          # (the host gone)
			arena.net.role = ""
			check(is_instance_valid(cp) and not cp.freeze and not arena.pieces.puppet, "the link gone: the guest's copies are real pieces again (not frozen)")
			mark = t
			step = 2
		2:
			if t - mark < 0.5:
				return false
			var cp2 = v0.cp
			check(not is_instance_valid(cp2) or (cp2 as RigidBody3D).global_position.y < float(v0.y0) - 0.6,
				"half a second on: the copy has fallen (%.2f m from 3.00)" % ((cp2 as RigidBody3D).global_position.y if is_instance_valid(cp2) else -1.0))
			mark = t
			step = 3
		3:
			if t - mark < 3.0 and is_instance_valid(v0.cp):
				return false
			# settled: a fragment on the floor, not one hanging where the copy was
			var hi := -INF
			var made := 0
			for b in arena.bodies:
				if b in v0.bodies or not is_instance_valid(b) or not b.fragment:
					continue
				made += 1
				for nm in b.parts:
					var p: Dictionary = b.parts[nm]
					if not p.gone and (p.mesh as MeshInstance3D).mesh:
						var mi: MeshInstance3D = p.mesh
						hi = maxf(hi, (mi.global_transform * mi.mesh.get_aabb().get_center()).y)
			check(not is_instance_valid(v0.cp) and made >= 1 and hi < 1.0,
				"it settled as a fragment lying on the floor (%d made, highest part at %.2f m)" % [made, hi])
			check(tv_got.size() > 0 and int(tv_got.flags) & ENetPacketPeer.FLAG_RELIABLE == 0,
				"the TV picture (6 KB) over ENet: arrived, in unreliable pieces (flags %s)" % str(tv_got.get("flags", "none")))
			tv_host.close()
			tv_cl.destroy()
			tv_host = null
			step = 99
		99:
			print("SWN done %d passed, %d failed" % [passed, failed])
			return true
	return false
