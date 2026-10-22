class_name VoxelNet
extends Node
## Co-op for the voxel arena (the owner, 21 Oct: two players online, co-op, the hits sent as events). One game hosts:
## it runs the enemies (their walking, fire, ice, deaths, waves) and BOTH players' weapons (a copy of every weapon for
## the other player, driven by their buttons and aim). Every change to a body is told to the guest as an event (what
## was done, a carve, a slice, a hole, a freeze, the fire's char and ash, with the pose the body was in), and the guest
## makes the same change to its copy of that body: the cubes come out the same, which a fingerprint of every body,
## compared every two seconds, checks (one that differs is sent whole). Pieces knocked off are announced and the guest's
## copies follow the host's; lying pieces made bodies again are announced with their cubes. The guest's own weapons run
## in its game for the look and the sound (its view, beams, flames, grenades), but can't change a body there: the host's
## copy does the cutting, a moment later. Each player's state (where they stand and look, the weapon out) goes to the
## other many times a second; enemies' positions and poses go from the host twenty times a second, the guest showing
## them a tenth of a second behind, smoothly. Owned by the voxel session.

const VERSION := 1
const P_HZ := 30.0              # player states a second
const S_HZ := 20.0              # enemy snapshots a second (host)
const Q_HZ := 15.0              # piece positions a second (host)
const CHECK_T := 2.0            # seconds between fingerprint checks (host)
const BEHIND := 0.1             # seconds behind the host the guest shows the enemies
const MAX_FLAMES := 6           # flame points a burning body sends a snapshot

signal changed                  # linked / unlinked / status (the arena's overlay)

var arena: Node3D
var tr: NetTransport
var role := ""                  # "host", "guest" or "" (alone)
var linked := false
var status_text := ""
var status_kind := ""           # "live", "bad" or "" (the menu colours the status by it)
var code := ""
var other: VoxelShooter         # the other player, as the weapons see them
var other_avatar: VoxelBody
var _o_cam: Camera3D
var _o_body: CharacterBody3D
var _o_weapons := {}            # weapon id -> the other player's copy
var _o_held := {}               # mouse button -> true: held by the other player
var _o_target := Vector3.ZERO   # where they are (the latest state); shown smoothed
var _o_prev := Vector3.ZERO
var _o_eye := Transform3D()
var _o_hand := ""
var _o_hands: Array = []
var other_hp := 100.0           # the other player's health ...
var other_down := false         # ... and down
var other_lying := 0            # ... and the bed they lie on (0: none)
var _next_nid := 1
var _bodies := {}               # nid -> VoxelBody
var _pieces := {}               # nid -> RigidBody3D
var _born := {}                 # host: body -> true (announced)
var _out := []                  # host: events this frame, in order
var _p_t := 0.0
var _s_t := 0.0
var _q_t := 0.0
var _check_t := 0.0
var _clock := 0.0
var _snaps := {}                # guest: nid -> [[time, state], ...] (the last few)
var _pq := {}                   # guest: piece nid -> [[time, pos, rot], ...]
var _got_world := false
var _own_immortal := false
var _last_us := 0               # (real time: the clock and the other's weapons)      # guest: its own F6 before linking (the host's rules while linked)
var debug := false              # (tests: what was done to a body found different)
var lag := 0.0                  # (tests: seconds every message from the other game is held back ...)
var loss := 0.0                 # (... and the share of the fast ones lost, like a bad line)
var _late := []                 # [[time due, bytes], ...]
var stats := {"sent": 0, "recv": 0, "events": 0, "fixes": 0, "checks": 0, "mismatch": 0}

func setup(arena_: Node3D) -> void:
	arena = arena_

# ---------------------------------------------------------------- starting and stopping

## Host a room: via "rtc" (a room code over the internet) or "enet" (a port); server: the PeerJS server (rtc).
func host(code_: String, via: String = "rtc", server: String = "", local_only := false) -> void:
	_start(via, server, local_only)
	role = "host"
	code = code_
	tr.host(code_)
	VoxelBody.net_rec = _rec_body
	arena.pieces.net_rec = _rec_piece
	arena.pieces.net_rec_frag = _rec_frag
	# (numbers past any a body already has: one that was a guest holds the old host's)
	for b in arena.bodies:
		if is_instance_valid(b):
			_next_nid = maxi(_next_nid, b.net_id + 1)
	for b in arena.bodies:
		_ensure(b)
	_out.clear()

func join(code_: String, via: String = "rtc", server: String = "", local_only := false) -> void:
	_start(via, server, local_only)
	role = "guest"
	code = code_
	tr.join(code_)

func _start(via: String, server: String, local_only: bool) -> void:
	leave()
	if via == "enet":
		tr = VoxelEnetTransport.new()
	else:
		var r := VoxelRtcTransport.new()
		if server != "":
			r.server = server
		r.local_only = local_only
		tr = r
	tr.status.connect(func(text, kind): status_text = text; status_kind = String(kind); changed.emit())
	tr.connected.connect(_on_connected)
	tr.disconnected.connect(_on_disconnected)
	tr.received.connect(_on_received)

## Back to playing alone.
func leave() -> void:
	if tr:
		tr.close()
	tr = null
	if linked:
		_on_disconnected()
	role = ""
	linked = false
	_bodies.clear()
	_born.clear()
	_pieces.clear()
	_snaps.clear()
	_pq.clear()
	VoxelBody.net_rec = Callable()
	VoxelBody.net_locked = false
	if arena and arena.pieces:
		arena.pieces.net_rec = Callable()
		arena.pieces.net_rec_frag = Callable()
		arena.pieces.puppet = false
	changed.emit()

func _exit_tree() -> void:
	leave()

func shooters() -> Array:
	return [arena.me, other] if other else [arena.me]

## Where the players stand who are up (the enemies go for the nearest): [this player's (or a placeholder if down),
## the other's]; empty if everyone is down. Index 0 is always this player, 1 the other.
func targets() -> Array:
	# (in the bedroom or the yard counts as out of reach: the enemies don't go for anyone in there)
	var me_up: bool = arena.down_t <= 0.0 and not VoxelArena.safe(arena.player.global_position)
	var them_up := linked and is_instance_valid(_o_body) and not other_down and not VoxelArena.safe(_o_body.global_position)
	if not me_up and not them_up:
		return []
	var out := [arena.player.global_position if me_up else Vector3(1e6, 0, 1e6)]
	if them_up:
		out.append(_o_body.global_position)
	return out

## The other player hurt (the host's enemies, blasts and fire): their game takes it.
func hurt_other(amount: float) -> void:
	if role == "host" and linked and amount > 0.0:
		_out.append(["ph", amount])

func _on_connected() -> void:
	linked = true
	_make_other()
	if role == "guest":
		_own_immortal = VoxelBody.immortal          # (the host's F6 from here on: its snapshots carry it)
		VoxelBody.net_locked = true
		arena.pieces.puppet = true
		arena.player.global_position += Vector3(2.0, 0.0, 0.0)     # (beside the host, not inside them)
		_send(["H", VERSION])
	changed.emit()

func _on_disconnected() -> void:
	linked = false
	_drop_other()
	if role == "guest":
		# alone again: this game's own bodies from here on
		VoxelBody.net_locked = false
		VoxelBody.immortal = _own_immortal
		arena.pieces.puppet = false
		_got_world = false
	changed.emit()

# ---------------------------------------------------------------- the other player

func _make_other() -> void:
	_drop_other()
	_o_body = CharacterBody3D.new()           # (no shape: only where they stand, and their RID for ray exclusions)
	_o_body.collision_layer = 0
	_o_body.collision_mask = 0
	arena.add_child(_o_body)
	_o_cam = Camera3D.new()
	arena.add_child(_o_cam)
	other_avatar = VoxelBody.new()
	arena.add_child(other_avatar)
	other_avatar.setup("jared", 0.0125 * 2.0, 2, arena._mat)
	other = VoxelShooter.new()
	other.arena = arena
	other.local = false
	other.pid = 1 if role == "host" else 0
	other.cam = _o_cam
	other.player = _o_body
	other.avatar = other_avatar
	for id in arena.MELEE:
		if ResourceLoader.exists(arena.MELEE[id]):
			var w: VoxelMelee = load(arena.MELEE[id]).new()
			arena.add_child(w)
			w.setup(arena, other, id)
			_o_weapons[id] = w
	_o_hand = ""

func _drop_other() -> void:
	for id in _o_weapons:
		var w: VoxelMelee = _o_weapons[id]
		if is_instance_valid(w):
			w.on_deselect()
			w.queue_free()
	_o_weapons.clear()
	_o_held.clear()
	for h in _o_hands:
		if is_instance_valid(h):
			h.queue_free()
	_o_hands.clear()
	for n in [_o_body, _o_cam, other_avatar]:
		if is_instance_valid(n):
			n.queue_free()
	_o_body = null
	_o_cam = null
	other_avatar = null
	other = null

# the other player's weapon out changed: the old one put away (buttons let go), the new one taken out
func _o_switch(id: String) -> void:
	if other == null or id == other.weapon:
		return
	var old: VoxelMelee = _o_weapons.get(other.weapon)
	if old:
		for btn in _o_held.keys():
			old.release(btn)
		old.on_deselect()
	_o_held.clear()
	other.weapon = id
	var nw: VoxelMelee = _o_weapons.get(id)
	if nw:
		nw.on_select()

# their Jared holding what they have out (as the arena does for this player's top-down)
func _o_hold(id: String) -> void:
	_o_hand = id
	for h in _o_hands:
		if is_instance_valid(h):
			h.queue_free()
	_o_hands.clear()
	var md: VoxelModel = other_avatar.model
	var g: Array = md.rig.get("grip_r", [-34.5, 56.0, 0.0])
	other_avatar.weapon = _o_weapons[id].hand_pose() if _o_weapons.has(id) else ("spud" if id == "vacuum" else "")
	var b := md.bone("hand_r")
	if b < 0:
		return
	var node: Node3D = null
	if id == "vacuum":
		node = Node3D.new()
		var vmod: Node3D = arena.vacuum._model()
		vmod.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 0.12))
		vmod.visible = true
		node.add_child(vmod)
	elif _o_weapons.has(id):
		node = _o_weapons[id].hand_mesh()
	if node == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = b
	other_avatar.skeleton.add_child(att)
	node.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), (Vector3(g[0], g[1], -2.0) - md.bone_pivot[b]) * md.voxel_m)
	att.add_child(node)
	_o_hands.append(att)

## A button of this player's: told to the other game (its copy of this player's weapon presses it too).
func local_input(kind: String, arg = null) -> void:
	if linked:
		_send(["I", kind, arg])

func _apply_input(kind: String, arg) -> void:
	if other == null:
		return
	var w: VoxelMelee = _o_weapons.get(other.weapon)
	match kind:
		"press":
			var btn := int(arg[0]) if arg is Array else int(arg)
			if arg is Array and arg.size() > 1:
				other.mouse_v = arg[1]          # (the mouse's move when it was pressed: the slash's way, the swing's side)
			if w:
				_o_held[btn] = true
				w.press(btn)
		"release":
			if w and _o_held.has(int(arg)):
				_o_held.erase(int(arg))
				w.release(int(arg))
		"reload":
			if w:
				w.reload_key()
		"quick":
			var sw: VoxelMelee = _o_weapons.get("sword")
			if arg is Array and arg.size() > 1:
				other.mouse_v = arg[1]
			if sw and sw.has_method("quick") and sw.ready_to_swing():
				sw.quick(bool(arg[0]) if arg is Array else bool(arg))
		"switch":
			_o_switch(String(arg))
		"spear":
			var sp = _o_weapons.get("spear")
			if sp and sp.has_method("remote"):
				sp.remote(String(arg))

# ---------------------------------------------------------------- every frame

func _process(dt: float) -> void:
	if tr == null:
		return
	tr.poll()
	if not _late.is_empty():
		# (tests: what's due of the held-back messages; the reliable ones stay in order)
		var now := Time.get_ticks_msec() / 1000.0
		var keep := []
		var rel_blocked := false
		for e in _late:
			var due := float(e[0]) <= now
			var rel: bool = (e[1] as PackedByteArray)[0] == 82
			if due and not (rel and rel_blocked):
				_got(e[1])
			else:
				keep.append(e)
				if rel:
					rel_blocked = true
		_late = keep
	if not linked or other == null:
		_last_us = 0
		return
	# (real time: a hit-stop slows this game's delta, not the line between the two games, nor the other's weapons)
	var now_us := Time.get_ticks_usec()
	var rdt := dt if _last_us == 0 else minf(float(now_us - _last_us) / 1000000.0, 0.25)
	_last_us = now_us
	_clock += rdt
	if role == "host":
		_host_frame(dt)
	else:
		_guest_frame(dt)
	_other_frame(dt, rdt)
	_p_t += dt
	if _p_t >= 1.0 / P_HZ:
		_p_t = 0.0
		_send_fast(_player_state())

func _other_frame(dt: float, rdt: float) -> void:
	# their place, smoothed between states
	_o_body.global_position = _o_body.global_position.lerp(_o_target, 1.0 - exp(-dt * 18.0))
	_o_cam.global_transform = Transform3D(_o_eye.basis, _o_eye.origin + (_o_body.global_position - _o_target))
	var spd := Vector2(_o_body.global_position.x - _o_prev.x, _o_body.global_position.z - _o_prev.z).length() / maxf(dt, 0.001)
	_o_prev = _o_body.global_position
	other_avatar.global_position = _o_body.global_position
	var f := -_o_cam.global_transform.basis.z
	if other.top_down and other.mouse_floor() != Vector3.INF:
		f = other.mouse_floor() - _o_body.global_position
	if Vector2(f.x, f.z).length() > 0.01:
		other_avatar.yaw = atan2(f.x, f.z)
	other_avatar.speed = spd
	other_avatar.odo += spd * dt
	other_avatar.attack = maxf(0.0, other_avatar.attack - dt * 2.5)
	other_avatar.down_t = 1.0 if (other_down or other_lying > 0) else 0.0      # (down: lying on the floor; or in bed)
	if other_lying > 0:
		other_avatar.yaw = 0.0
	other_avatar.recoil = maxf(0.0, other_avatar.recoil - dt * 6.0)
	other_avatar.animate(dt, spd > 0.2)
	other_avatar.visible = true
	if _o_hand != other.weapon:
		_o_hold(other.weapon)
	# their weapons: held buttons, then every weapon's step
	var w: VoxelMelee = _o_weapons.get(other.weapon)
	if w:
		for btn in _o_held:
			w.hold(btn, rdt)
	for id in _o_weapons:
		_o_weapons[id].step(rdt)
		_o_weapons[id].view.visible = false

func _player_state() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(80)    # P
	var cam: Camera3D = arena.cam
	var e := cam.global_transform
	for v in [e.origin.x, e.origin.y, e.origin.z]:
		b.put_float(v)
	var q := e.basis.get_rotation_quaternion()
	for v in [q.x, q.y, q.z, q.w]:
		b.put_float(v)
	var p: Vector3 = arena.player.global_position
	for v in [p.x, p.y, p.z]:
		b.put_float(v)
	b.put_u8(1 if arena.top_down else 0)
	b.put_utf8_string(arena.me.weapon)
	var mv: Vector2 = arena._mouse_v
	b.put_float(mv.x)
	b.put_float(mv.y)
	b.put_u8(1 if arena._aiming else 0)
	var fl: Vector3 = arena.me.mouse_floor() if arena.top_down else Vector3.INF
	b.put_u8(1 if fl != Vector3.INF else 0)
	if fl != Vector3.INF:
		for v in [fl.x, fl.y, fl.z]:
			b.put_float(v)
	var ray: Array = arena.me.mouse_ray() if arena.top_down else []
	b.put_u8(1 if not ray.is_empty() else 0)
	if not ray.is_empty():
		for v in [ray[0].x, ray[0].y, ray[0].z, ray[1].x, ray[1].y, ray[1].z]:
			b.put_float(v)
	b.put_float(arena.look_yaw)
	b.put_float(arena.player_hp)
	b.put_u8(1 if arena.down_t > 0.0 else 0)
	b.put_u8(arena.lying)
	return b.data_array

func _read_player(d: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = d
	b.get_u8()
	var o := Vector3(b.get_float(), b.get_float(), b.get_float())
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	_o_eye = Transform3D(Basis(q), o)
	var p := Vector3(b.get_float(), b.get_float(), b.get_float())
	if _o_target == Vector3.ZERO and _o_body:
		_o_body.global_position = p
	_o_target = p
	other.top_down = b.get_u8() == 1
	_o_switch(b.get_utf8_string())
	other.mouse_v = Vector2(b.get_float(), b.get_float())
	other.aiming = b.get_u8() == 1
	other._floor = Vector3(b.get_float(), b.get_float(), b.get_float()) if b.get_u8() == 1 else Vector3.INF
	other._ray = [Vector3(b.get_float(), b.get_float(), b.get_float()), Vector3(b.get_float(), b.get_float(), b.get_float())] if b.get_u8() == 1 else []
	other.look_yaw = b.get_float()
	other_hp = b.get_float()
	other_down = b.get_u8() == 1
	other_lying = b.get_u8() if b.get_available_bytes() > 0 else 0

# ---------------------------------------------------------------- the host

func _host_frame(dt: float) -> void:
	# every body has a number and the guest knows it; the ones gone are told
	for b in arena.bodies:
		_ensure(b)
	for nid in _bodies.keys():
		var bb = _bodies[nid]
		if not is_instance_valid(bb) or not arena.bodies.has(bb):
			_bodies.erase(nid)
			_out.append(["g", nid])
	for pnid in _pieces.keys():
		if not is_instance_valid(_pieces[pnid]):
			_pieces.erase(pnid)
			_out.append(["q", pnid])
	if not _out.is_empty():
		stats.events += _out.size()
		_send(["E", _out])
		_out = []
	_s_t += dt
	if _s_t >= 1.0 / S_HZ:
		_s_t = 0.0
		_send_fast(_snapshot())
	_q_t += dt
	if _q_t >= 1.0 / Q_HZ and not _pieces.is_empty():
		_q_t = 0.0
		_send_fast(_piece_state())
	_check_t += dt
	if _check_t >= CHECK_T:
		_check_t = 0.0
		var fps := []
		for nid in _bodies:
			var bb: VoxelBody = _bodies[nid]
			if bb.net_id > 0:
				fps.append([nid, bb.fingerprint()])
		_send(["C", fps])

# a body the guest doesn't know yet: given a number and announced (a fresh enemy by its kind; a lying piece made a
# body again with its cubes)
func _ensure(b: VoxelBody) -> void:
	if b.net_id > 0 and _born.has(b):
		return
	if b.net_id == 0:
		b.net_id = _next_nid
		_next_nid += 1
	_born[b] = true
	_bodies[b.net_id] = b
	_out.append(_birth(b, false))

func _birth(b: VoxelBody, whole: bool) -> Array:
	var frag = null
	if b.fragment or whole:
		frag = b.grids_out()
	var xf := []
	if b.fragment:
		for i in b.skeleton.get_bone_count():
			xf.append(b.skeleton.get_bone_global_pose(i))
	return ["b", b.net_id, b.key, b.chunk_n, b.vm, b.global_position, b.yaw, b.speed, b.fragment, frag, xf, b.alive, b.hp,
		b.skeleton.global_transform]

func _rec_body(b: VoxelBody, what: String, args: Array, p: Array) -> void:
	if not linked or b == other_avatar or not arena.bodies.has(b):
		return
	_ensure(b)
	_out.append(["m", b.net_id, what, args, p])

func _rec_piece(src: VoxelBody, list: Array, vel: Vector3, spin: Vector3, rb: RigidBody3D) -> void:
	if not linked:
		return
	var pnid := _next_nid
	_next_nid += 1
	_pieces[pnid] = rb
	rb.set_meta("nid", pnid)
	var entries := []
	for e in list:
		if int(e.count) <= 0:
			continue
		var raw := (e.grid.cells as PackedInt32Array).to_byte_array()
		entries.append([String(e.get("part", "")), e.grid.size, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size(), e.origin, e.xform,
			e.box_at, e.box, int(e.count), bool(e.get("seam", false)), bool(e.get("limb", false))])
	_out.append(["p", pnid, src.key, src.chunk_n, src.vm, entries, rb.global_transform])

func _rec_frag(rb: RigidBody3D, f: VoxelBody, _grids: Dictionary, _xforms: Dictionary) -> void:
	if not linked:
		return
	_ensure(f)          # (announced with its cubes and bones as it lies)

func _snapshot() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(83)    # S
	b.put_float(_clock)
	var list := []
	for nid in _bodies:
		var bb: VoxelBody = _bodies[nid]
		if not is_instance_valid(bb):
			continue
		# the still dead (lying, done) rarely change: every twentieth snapshot
		if not bb.alive and not bb.airborne and bb.since_air > 2.0 and bb.knock.length_squared() < 0.0001 and int(_clock * S_HZ) % 20 != nid % 20:
			continue
		list.append(bb)
	b.put_u16(list.size())
	for bb in list:
		b.put_u32(bb.net_id)
		var p: Vector3 = bb.position
		for v in [p.x, p.y, p.z, bb.yaw, bb.odo, bb.attack, bb.stagger, bb.flinch, bb.down_t, bb.up_t, bb.tumble, bb.dead_t,
				bb.since_air, bb.hp, bb.frost, bb.panic_t, bb.speed]:
			b.put_float(v)
		var flags := (1 if bb.alive else 0) | (2 if bb.airborne else 0) | (4 if bb.frozen() else 0) | (8 if bb.burning() else 0) | (16 if bb.flinch_head else 0) | (32 if VoxelBody.immortal else 0)   # (32: the host's F6, can't die)
		b.put_u8(flags)
		if bb.burning():
			var pts := _flame_points(bb)
			b.put_u8(pts.size())
			for q in pts:
				for v in [q.x, q.y, q.z]:
					b.put_float(v)
	return b.data_array

# a few cubes burning on a body, in its own space (the guest lights flames there)
func _flame_points(bb: VoxelBody) -> Array:
	var out := []
	var inv := bb.global_transform.affine_inverse()
	for nm in bb._burn:
		var bd: Dictionary = bb._burn[nm]
		if bd.is_empty():
			continue
		var p: Dictionary = bb.parts[nm]
		var s: Vector3i = p.grid.size
		var bi: int = p.bone
		var m: Transform3D = bb.skeleton.global_transform * bb.skeleton.get_bone_global_pose(bi) * Transform3D(Basis.IDENTITY, -bb.model.bone_pivot[bi] * bb.model.voxel_m)
		var keys := bd.keys()
		for k in mini(2, keys.size()):
			var i: int = keys[randi() % keys.size()]
			out.append(inv * (m * ((Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)) + Vector3(p.origin) + Vector3(0.5, 0.5, 0.5)) * bb.vm)))
			if out.size() >= MAX_FLAMES:
				return out
	return out

func _piece_state() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(81)    # Q
	b.put_float(_clock)
	var moving := []
	for pnid in _pieces:
		var rb: RigidBody3D = _pieces[pnid]
		if is_instance_valid(rb) and not rb.sleeping:
			moving.append(pnid)
	b.put_u16(moving.size())
	for pnid in moving:
		var rb: RigidBody3D = _pieces[pnid]
		b.put_u32(pnid)
		var t := rb.global_transform
		var q := t.basis.get_rotation_quaternion()
		for v in [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]:
			b.put_float(v)
	return b.data_array

# the guest has just come: everything there is, whole
func _send_world() -> void:
	var bodies := []
	for b in arena.bodies:
		_ensure(b)
		bodies.append(_birth(b, true))
	_out.clear()
	var pieces := []
	for pnid in _pieces:
		var rb: RigidBody3D = _pieces[pnid]
		if not is_instance_valid(rb):
			continue
		var pc := {}
		for e in arena.pieces._pieces:
			if e.rb == rb:
				pc = e
		if pc.is_empty():
			continue
		var entries := []
		for c in pc.cells:
			var raw := (c.grid.cells as PackedInt32Array).to_byte_array()
			entries.append([String(c.part), c.grid.size, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size(), c.origin,
				rb.global_transform * (c.local as Transform3D), Vector3.ZERO, Vector3.ONE * 0.1, 1])
		pieces.append([pnid, String(pc.key), int(pc.chunk), float(pc.vm), entries, rb.global_transform])
	_send(["W", bodies, pieces, int(arena.wave), arena.debris.lying_out()])

# ---------------------------------------------------------------- the guest

func _guest_frame(_dt: float) -> void:
	if not _got_world:
		return
	var at := _clock - BEHIND
	for nid in _snaps:
		var bv = _bodies.get(nid)
		if not is_instance_valid(bv):
			continue
		var b: VoxelBody = bv          # (typed only once it's known to be there: a freed one can't be assigned)
		var list: Array = _snaps[nid]
		if list.is_empty():
			continue
		# the two snapshots either side of a tenth of a second ago
		var a: Array = list[0]
		var c: Array = list[0]
		for i in list.size():
			if float(list[i][0]) <= at:
				a = list[i]
				c = list[mini(i + 1, list.size() - 1)]
		var k := 0.0
		if float(c[0]) > float(a[0]):
			k = clampf((at - float(a[0])) / (float(c[0]) - float(a[0])), 0.0, 1.0)
		var sa: Dictionary = a[1]
		var sc: Dictionary = c[1]
		b.position = (sa.pos as Vector3).lerp(sc.pos, k)
		b.yaw = lerp_angle(float(sa.yaw), float(sc.yaw), k)
		for f in ["odo", "attack", "stagger", "flinch", "down_t", "up_t", "tumble", "dead_t", "since_air", "frost", "panic_t", "speed"]:
			b.set(f, lerpf(float(sa[f]), float(sc[f]), k) if f in ["odo", "tumble"] else float(sc[f]))
		b.hp = float(sc.hp)
		b.airborne = bool(sc.air)
		b.flinch_head = bool(sc.fh)
		if b.alive and not bool(sc.alive):
			b.alive = false
			b.died.emit(b)
		if bool(sc.burn) and not (sc.fl as Array).is_empty() and randf() < 0.7:
			for q in sc.fl:
				arena.flames.emit(b.global_transform * (q as Vector3), 2, Vector3.ZERO, 2.6, 0.55)
	# the pieces, where the host has them
	for pnid in _pq:
		var rv = _pieces.get(pnid)
		if not is_instance_valid(rv):
			continue
		var rb: RigidBody3D = rv
		var list2: Array = _pq[pnid]
		var e: Array = list2[list2.size() - 1]
		for i in list2.size():
			if float(list2[i][0]) <= at:
				e = list2[i]
		rb.global_transform = rb.global_transform.interpolate_with(Transform3D(Basis(e[2] as Quaternion), e[1]), 0.5)

func _read_snapshot(d: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = d
	b.get_u8()
	var t := b.get_float()
	# the host's clock ahead of ours by however much (the first snapshot sets it)
	if _clock < t - 1.0 or _clock > t + 1.0:
		_clock = t
	var n := b.get_u16()
	for i in n:
		var nid := b.get_u32()
		var s := {}
		s.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
		for f in ["yaw", "odo", "attack", "stagger", "flinch", "down_t", "up_t", "tumble", "dead_t", "since_air", "hp", "frost", "panic_t", "speed"]:
			s[f] = b.get_float()
		var flags := b.get_u8()
		s.alive = flags & 1 != 0
		s.air = flags & 2 != 0
		s.frozen = flags & 4 != 0
		s.burn = flags & 8 != 0
		s.fh = flags & 16 != 0
		VoxelBody.immortal = flags & 32 != 0     # (the host's F6)
		s.fl = []
		if s.burn:
			for j in b.get_u8():
				(s.fl as Array).append(Vector3(b.get_float(), b.get_float(), b.get_float()))
		var list: Array = _snaps.get(nid, [])
		list.append([t, s])
		while list.size() > 4:
			list.pop_front()
		_snaps[nid] = list

func _read_pieces(d: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = d
	b.get_u8()
	var t := b.get_float()
	for i in b.get_u16():
		var pnid := b.get_u32()
		var p := Vector3(b.get_float(), b.get_float(), b.get_float())
		var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
		var list: Array = _pq.get(pnid, [])
		list.append([t, p, q])
		while list.size() > 4:
			list.pop_front()
		_pq[pnid] = list

func _world(bodies: Array, pieces: Array) -> void:
	# this game's own enemies, pieces and corpses go: the host's world in their place
	for b in arena.bodies:
		if is_instance_valid(b):
			b.queue_free()
	arena.bodies.clear()
	for pc in arena.pieces._pieces:
		if is_instance_valid(pc.rb):
			pc.rb.queue_free()
	arena.pieces._pieces.clear()
	_bodies.clear()
	_pieces.clear()
	_snaps.clear()
	_pq.clear()
	for e in bodies:
		_born_here(e)
	for e in pieces:
		_piece_here(e[0], e[1], e[2], e[3], e[4], e[5])
	_got_world = true

func _born_here(e: Array) -> void:
	var nid: int = e[1]
	if _bodies.has(nid) and is_instance_valid(_bodies[nid]):
		return
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(String(e[2]), float(e[4]), int(e[3]), arena._mat)
	b.net_id = nid
	b.position = e[5]
	b.yaw = float(e[6])
	b.speed = float(e[7])
	if bool(e[8]):
		# a lying piece made a body: its cubes and its bones as they lie
		var grids := {}
		var d: Dictionary = e[9]
		for nm in d:
			if String(nm).begins_with("~"):
				continue             # (not a part: the frost)
			var g: Array = d[nm]
			if not bool(g[3]):
				grids[nm] = {"cells": (g[1] as PackedByteArray).decompress(int(g[2]), FileAccess.COMPRESSION_ZSTD).to_int32_array(), "mesh": null}
		b.skeleton.global_transform = e[13]
		var xforms := {}
		var bones: Array = e[10]
		for nm in b.parts:
			var bi: int = b.parts[nm].bone
			if bi < bones.size():
				xforms[nm] = b.skeleton.global_transform * (bones[bi] as Transform3D)
		b.make_fragment(grids, xforms)
	elif e[9] != null:
		b.grids_in(e[9])
	b.alive = bool(e[11])
	b.hp = float(e[12])
	if not b.alive and not b.fragment:
		b.dead_t = 99.0
	b.died.connect(arena._on_died)
	arena.bodies.append(b)
	_bodies[nid] = b

func _piece_here(pnid: int, key: String, chunk: int, vm: float, entries: Array, xf: Transform3D) -> void:
	var list := []
	for en in entries:
		var cells := (en[2] as PackedByteArray).decompress(int(en[3]), FileAccess.COMPRESSION_ZSTD).to_int32_array()
		list.append({"part": en[0], "grid": {"size": en[1], "cells": cells}, "origin": en[4], "xform": en[5], "box_at": en[6],
			"box": en[7], "count": en[8], "seam": en.size() > 9 and bool(en[9]), "limb": en.size() > 10 and bool(en[10])})
	var rb: RigidBody3D = arena.pieces.spawn_copy(key, chunk, vm, list, xf)
	if rb:
		_pieces[pnid] = rb

func _events(list: Array) -> void:
	for ev in list:
		match String(ev[0]):
			"b":
				_born_here(ev)
			"g":
				var b = _bodies.get(int(ev[1]))
				if is_instance_valid(b):
					arena.bodies.erase(b)
					b.queue_free()
				_bodies.erase(int(ev[1]))
				_snaps.erase(int(ev[1]))
			"m":
				var bv2 = _bodies.get(int(ev[1]))
				if not is_instance_valid(bv2):
					continue
				var b2: VoxelBody = bv2
				var res := b2.net_apply(String(ev[2]), ev[3], ev[4])
				if debug:
					var tl: Array = b2.get_meta("net_log", [])
					tl.append("%s fp %d" % [String(ev[2]), b2.fingerprint()])
					while tl.size() > 8:
						tl.pop_front()
					b2.set_meta("net_log", tl)
				var bits: Array = res.get("bits", [])
				if not bits.is_empty():
					var dir: Vector3 = (b2.global_position + Vector3.UP - arena.cam.global_position).normalized()
					arena.debris.burst(bits, dir, 2.5)
					arena.knocked += bits.size()
					arena.sound.play("shatter" if res.get("shattered", false) else "hit_flesh", b2.global_position + Vector3.UP, -6.0)
			"p":
				_piece_here(int(ev[1]), String(ev[2]), int(ev[3]), float(ev[4]), ev[5], ev[6])
			"q":
				var rb = _pieces.get(int(ev[1]))
				if is_instance_valid(rb):
					rb.queue_free()
				_pieces.erase(int(ev[1]))
				_pq.erase(int(ev[1]))
			"hs":
				_hit_stop(float(ev[2]), float(ev[3]))
			"ph":
				arena.hurt_player(float(ev[1]))
			"ds":
				arena.dash(ev[2], float(ev[3]))

func _hit_stop(secs: float, scale: float) -> void:
	for id in arena.melee:
		arena.melee[id].hit_stop(secs, scale)
		return

func _check(fps: Array) -> void:
	stats.checks += 1
	var bad := []
	for e in fps:
		var bv = _bodies.get(int(e[0]))
		if not is_instance_valid(bv):
			continue
		var b: VoxelBody = bv
		if b.fingerprint() != int(e[1]):
			bad.append(int(e[0]))
			if debug:
				print("NETDBG body %d (%s%s) differs; last: %s" % [int(e[0]), b.key, " fragment" if b.fragment else "", str(b.get_meta("net_log", []))])
	if not bad.is_empty():
		stats.mismatch += bad.size()
		_send(["F", bad])

# ---------------------------------------------------------------- messages

func _send(msg: Array) -> void:
	if tr == null:
		return
	var d := PackedByteArray([82])    # R
	d.append_array(var_to_bytes(msg))
	stats.sent += d.size()
	tr.send(d)

func _send_fast(d: PackedByteArray) -> void:
	if tr == null:
		return
	stats.sent += d.size()
	if tr.has_method("send_fast"):
		tr.call("send_fast", d)
	else:
		tr.send(d)

func _on_received(d: PackedByteArray) -> void:
	if d.is_empty():
		return
	if lag > 0.0 or loss > 0.0:
		if d[0] != 82 and randf() < loss:
			return
		_late.append([Time.get_ticks_msec() / 1000.0 + lag * randf_range(0.85, 1.15) if d[0] != 82 else Time.get_ticks_msec() / 1000.0 + lag, d])
		return
	_got(d)

func _got(d: PackedByteArray) -> void:
	stats.recv += d.size()
	match d[0]:
		80:
			if other:
				_read_player(d)
		83:
			if role == "guest":
				_read_snapshot(d)
		81:
			if role == "guest":
				_read_pieces(d)
		84:
			if role == "guest":
				arena.games.on_tv_frame(d.slice(1))     # (the host's TV picture, a JPEG)
		82:
			var msg = bytes_to_var(d.slice(1))
			if typeof(msg) == TYPE_ARRAY:
				_message(msg)

func _message(m: Array) -> void:
	match String(m[0]):
		"H":
			if role == "host":
				_send_world()
				arena.stash.send_all()
				arena.yard.send_all()
				arena.yard.farm.send_all()
				arena.yard.chickens.send_all()
				arena.yard.shredder.send_all()
				arena.games.send_all()
		"W":
			_world(m[1], m[2])
			arena.wave = int(m[3])
			if m.size() > 4:
				arena.debris.lying_in(m[4])          # (the host's floor: the same lying cubes in both games)
		"E":
			if _got_world:
				_events(m[1])
		"I":
			_apply_input(String(m[1]), m[2])
		"C":
			if _got_world:
				_check(m[1])
		"F":
			if role == "host":
				for nid in m[1]:
					var bv = _bodies.get(int(nid))
					if is_instance_valid(bv):
						var b: VoxelBody = bv
						stats.fixes += 1
						_send(["G", int(nid), b.grids_out(), b.alive, b.hp])
		"G":
			var bv2 = _bodies.get(int(m[1]))
			if is_instance_valid(bv2):
				var b2: VoxelBody = bv2
				stats.fixes += 1
				b2.grids_in(m[2])
				b2.alive = bool(m[3])
				b2.hp = float(m[4])
		"V":
			if role == "host":
				arena.pieces.vacuum(m[1], float(m[2]), true)
		"S":
			arena.stash.on_net(m.slice(1))
		"Y":
			arena.yard.on_net(m.slice(1))
		"K":
			arena.yard.farm.on_net(m.slice(1))
		"B":
			arena.yard.chickens.on_net(m.slice(1))
		"M":
			arena.yard.shredder.on_net(m.slice(1))
		"R":
			arena.games.on_net(m.slice(1))
		"X":
			if role == "host":
				arena.spawn(clampi(int(m[1]), 1, 40))

## The other player's lunge (the host's copy of their chainsaw): their game throws them.
func send_dash(pid: int, vel: Vector3, secs: float) -> void:
	if role == "host" and linked:
		_out.append(["ds", pid, vel, secs])

## The other player's blow froze their game a blink (the host's copy of their weapon struck).
func send_hitstop(pid: int, secs: float, scale: float) -> void:
	if role == "host" and linked:
		_out.append(["hs", pid, secs, scale])

## A guest's F3 / F5: the host sends in n more.
func request_more(n: int) -> void:
	if role == "guest" and linked:
		_send(["X", n])

## The farm's (VoxelFarm), either way, reliable.
func send_farm(m: Array) -> void:
	if linked:
		_send(["K"] + m)        # (K: "F" is the fingerprints' fix)

## The games room's (VoxelGamesRoom), either way, reliable.
func send_games(m: Array) -> void:
	if linked:
		_send(["R"] + m)

## The host's TV picture (a JPEG) to the guest, unreliable (a lost one is replaced by the next).
func send_tv(jpg: PackedByteArray) -> void:
	if linked and role == "host":
		var d := PackedByteArray([84])    # T
		d.append_array(jpg)
		_send_fast(d)

## The shredder's (VoxelShredder), either way, reliable.
func send_shredder(m: Array) -> void:
	if linked:
		_send(["M"] + m)

## The chickens' (VoxelChickens), either way, reliable.
func send_chickens(m: Array) -> void:
	if linked:
		_send(["B"] + m)

## The yard's digs, fills and chunks (VoxelYard), either way, reliable.
func send_yard(m: Array) -> void:
	if linked:
		_send(["Y"] + m)

## The chests' and backpacks' messages (VoxelStorages), either way, reliable.
func send_storage(m: Array) -> void:
	if linked:
		_send(["S"] + m)

## A guest's vacuum on pieces and corpses: the host's vacuum takes them.
func send_vac(brush: Vector3, r: float) -> void:
	if role == "guest" and linked:
		_send(["V", brush, r])
