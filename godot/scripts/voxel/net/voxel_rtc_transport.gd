class_name VoxelRtcTransport
extends NetTransport
## The voxel arena's co-op connection over the internet (the owner, 21 Oct: "online with my mate", reusing the Smashed
## TV set-up): a native WebRTC connection (addons/webrtc, godotengine/webrtc-native) introduced through a PeerJS
## server, the room code as the host's peer id, with the HTML game's STUN servers and its metered.ca TURN relay, so
## two PCs behind home routers find each other with no port forwarding. The PeerJS server only passes the offer, the
## answer and the network candidates between the two (its own WebSocket protocol, spoken here directly); after that
## it's a direct (or relayed) WebRTC connection with two data channels: "rel" reliable and in order (events), "fast"
## unreliable and unordered (positions, many a second). Long reliable messages are cut into pieces and put back
## together. Another transport (GodotSteam) only needs the same few calls. Owned by the voxel session.
##
## server: the PeerJS server ("wss://0.peerjs.com/" by default; tests run `npx peerjs --port 9000` and pass
## "ws://127.0.0.1:9000/"). local_only: no STUN/TURN (two copies on one machine).

## Peer ids are this plus the room code (the main game's are "smashedgd-", the HTML game's "jucyjared-").
const PREFIX := "smashedvx-"
const DEFAULT_SERVER := "wss://0.peerjs.com/"
const KEY := "peerjs"
const HEARTBEAT := 5.0
const JOIN_TIMEOUT := 20.0
const PIECE := 15000            # bytes a reliable message is cut into at most
const ICE := [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
	{"urls": ["stun:stun.cloudflare.com:3478"]},
	{"urls": ["turn:global.relay.metered.ca:80"], "username": "717ffe96ec1375e0fb3f834b", "credential": "v/tattI18wAT8wvM"},
	{"urls": ["turn:global.relay.metered.ca:443"], "username": "717ffe96ec1375e0fb3f834b", "credential": "v/tattI18wAT8wvM"},
	{"urls": ["turn:global.relay.metered.ca:443?transport=tcp"], "username": "717ffe96ec1375e0fb3f834b", "credential": "v/tattI18wAT8wvM"},
	{"urls": ["turns:global.relay.metered.ca:443?transport=tcp"], "username": "717ffe96ec1375e0fb3f834b", "credential": "v/tattI18wAT8wvM"},
]

var server := DEFAULT_SERVER
var local_only := false
var _ws: WebSocketPeer
var _ws_up := false
var _role := ""
var _code := ""
var _me := ""                   # my peer id on the server
var _other := ""                # theirs
var _pc: WebRTCPeerConnection
var _rel: WebRTCDataChannel
var _fast: WebRTCDataChannel
var _open := false
var _beat := 0.0
var _wait := 0.0                # guest: seconds waiting for the host
var _pending_cands := []        # candidates that came before the offer/answer was set
var _have_remote := false
var _parts := {}                # piece id -> [count, got, Array of pieces]
var _part_id := 0
var _clock := 0.0

func kind() -> String:
	return "Internet"

func host(code: String) -> void:
	close()
	_role = "host"
	_code = code.to_upper()
	_me = PREFIX + _code
	_connect_server()
	status.emit("opening room %s…" % _code, "")

func join(code: String) -> void:
	close()
	_role = "guest"
	_code = code.to_upper()
	_me = PREFIX + "g-" + str(randi() % 100000000)
	_other = PREFIX + _code
	_connect_server()
	status.emit("looking for room %s…" % _code, "")

func _connect_server() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var base := server if server.ends_with("/") else server + "/"
	var url := "%speerjs?key=%s&id=%s&token=%s&version=1.5.4" % [base, KEY, _me.uri_encode(), str(randi())]
	var err := _ws.connect_to_url(url)
	if err != OK:
		status.emit("can't reach the matchmaking server (%s)" % server, "bad")
		_ws = null

func is_open() -> bool:
	return _open

func send(data: PackedByteArray) -> void:
	if not _open:
		return
	if data.size() <= PIECE:
		var b := PackedByteArray([0])
		b.append_array(data)
		_rel.put_packet(b)
		return
	# long: in pieces, [1, id(4), i(2), n(2), bytes...]
	_part_id += 1
	var n := ceili(float(data.size()) / PIECE)
	for i in n:
		var h := PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0, 0])
		h.encode_u32(1, _part_id)
		h.encode_u16(5, i)
		h.encode_u16(7, n)
		h.append_array(data.slice(i * PIECE, mini(data.size(), (i + 1) * PIECE)))
		_rel.put_packet(h)

## Unreliable, unordered: positions and the like (a lost one is replaced by the next).
func send_fast(data: PackedByteArray) -> void:
	if _open and _fast and _fast.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_fast.put_packet(data)

func poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - _clock, 0.0, 0.5) if _clock > 0.0 else 0.0
	_clock = now
	if _ws:
		_ws.poll()
		# (read whatever came, open or not: the server says "ID-TAKEN" and hangs up straight away)
		while _ws and _ws.get_available_packet_count() > 0:
			_on_server(_ws.get_packet().get_string_from_utf8())
		var st := _ws.get_ready_state() if _ws else WebSocketPeer.STATE_CLOSED
		if not _ws_up and _ws and _role != "":
			_wait += dt
			if _wait > 6.0:
				# (a room code already taken can come back as no answer at all)
				status.emit("no answer for room %s (taken? try another code)" % _code if _role == "host" else "no answer from the matchmaking server (%s)" % server, "bad")
				close()
				return
		if st == WebSocketPeer.STATE_OPEN:
			_beat += dt
			if _beat >= HEARTBEAT:
				_beat = 0.0
				_ws_send({"type": "HEARTBEAT"})
		elif st == WebSocketPeer.STATE_CLOSED and _ws:
			if not _open and _role != "":
				status.emit("lost the matchmaking server (%s)" % server, "bad")
			_ws = null
			_ws_up = false
	if _role == "guest" and not _open and _ws_up:
		_wait += dt
		if _wait > JOIN_TIMEOUT:
			status.emit("room %s not found (host first, then join)" % _code, "bad")
			_wait = -INF
	if _pc:
		_pc.poll()
		var was := _open
		_open = _rel != null and _rel.get_ready_state() == WebRTCDataChannel.STATE_OPEN
		if _open and not was:
			status.emit("player 2 connected" if _role == "host" else "connected — you are player 2", "live")
			connected.emit()
		elif was and not _open:
			_lost()
			return
		if _pc and _pc.get_connection_state() in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED] and was:
			_lost()
			return
		if _rel:
			while _rel.get_available_packet_count() > 0:
				_on_packet(_rel.get_packet())
		if _fast:
			while _fast.get_available_packet_count() > 0:
				received.emit(_fast.get_packet())

func _lost() -> void:
	_open = false
	_drop_pc()
	status.emit("player 2 left" if _role == "host" else "lost the connection", "bad")
	disconnected.emit()

func _on_packet(p: PackedByteArray) -> void:
	if p.is_empty():
		return
	if p[0] == 0:
		received.emit(p.slice(1))
		return
	var pid := p.decode_u32(1)
	var i := p.decode_u16(5)
	var n := p.decode_u16(7)
	var e: Array = _parts.get(pid, [n, 0, []])
	if (e[2] as Array).is_empty():
		(e[2] as Array).resize(n)
	if e[2][i] == null:
		e[2][i] = p.slice(9)
		e[1] = int(e[1]) + 1
	_parts[pid] = e
	if int(e[1]) == n:
		var whole := PackedByteArray()
		for piece in e[2]:
			whole.append_array(piece)
		_parts.erase(pid)
		received.emit(whole)

# ---------------------------------------------------------------- the PeerJS server's messages

func _ws_send(o: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(o))

func _on_server(text: String) -> void:
	var m = JSON.parse_string(text)
	if typeof(m) != TYPE_DICTIONARY:
		return
	var type := String(m.get("type", ""))
	match type:
		"OPEN":
			_ws_up = true
			_wait = 0.0
			if _role == "host":
				status.emit("room %s — waiting for player 2" % _code, "live")
				opened.emit(_code)
			else:
				opened.emit(_code)
				_make_pc()
				_pc.create_offer()
		"ID-TAKEN":
			status.emit("room %s is taken (someone's hosting it)" % _code if _role == "host" else "try again", "bad")
			close()
		"ERROR":
			status.emit("matchmaking error: %s" % str(m.get("payload", {}).get("msg", "")), "bad")
		"EXPIRE":
			if _role == "guest" and not _open:
				status.emit("room %s not found (host first, then join)" % _code, "bad")
		"OFFER":
			if _role != "host":
				return
			if _open:
				return                  # (one guest at a time)
			_other = String(m.get("src", ""))
			_drop_pc()
			_make_pc()
			var pl: Dictionary = m.get("payload", {})
			_pc.set_remote_description("offer", String(pl.get("sdp", "")))
			_have_remote = true
			_flush_cands()
		"ANSWER":
			if _role != "guest" or _pc == null:
				return
			var pl2: Dictionary = m.get("payload", {})
			_pc.set_remote_description("answer", String(pl2.get("sdp", "")))
			_have_remote = true
			_flush_cands()
		"CANDIDATE":
			if String(m.get("src", "")) != _other:
				return
			var c: Dictionary = m.get("payload", {}).get("candidate", {})
			if _have_remote and _pc:
				_pc.add_ice_candidate(String(c.get("sdpMid", "")), int(c.get("sdpMLineIndex", 0)), String(c.get("candidate", "")))
			else:
				_pending_cands.append(c)
		"LEAVE":
			if String(m.get("src", "")) == _other and _open:
				_lost()

func _flush_cands() -> void:
	for c in _pending_cands:
		_pc.add_ice_candidate(String(c.get("sdpMid", "")), int(c.get("sdpMLineIndex", 0)), String(c.get("candidate", "")))
	_pending_cands.clear()

func _make_pc() -> void:
	_pc = WebRTCPeerConnection.new()
	_pc.initialize({"iceServers": [] if local_only else ICE})
	_pc.session_description_created.connect(_on_sdp)
	_pc.ice_candidate_created.connect(_on_cand)
	_rel = _pc.create_data_channel("rel", {"negotiated": true, "id": 1})
	_fast = _pc.create_data_channel("fast", {"negotiated": true, "id": 2, "ordered": false, "maxRetransmits": 0})
	_have_remote = false
	_wait = 0.0

func _on_sdp(type: String, sdp: String) -> void:
	_pc.set_local_description(type, sdp)
	_ws_send({"type": "OFFER" if type == "offer" else "ANSWER", "dst": _other, "payload": {"sdp": sdp, "type": "data"}})

func _on_cand(media: String, index: int, cand: String) -> void:
	_ws_send({"type": "CANDIDATE", "dst": _other, "payload": {"candidate": {"candidate": cand, "sdpMid": media, "sdpMLineIndex": index}, "type": "data"}})

func _drop_pc() -> void:
	if _rel:
		_rel.close()
	if _fast:
		_fast.close()
	if _pc:
		_pc.close()
	_rel = null
	_fast = null
	_pc = null
	_have_remote = false
	_pending_cands.clear()
	_parts.clear()

func drop_peer() -> void:
	_open = false
	_drop_pc()

func close() -> void:
	if _ws:
		if _other != "":
			_ws_send({"type": "LEAVE", "dst": _other})
		_ws.close()
	_ws = null
	_ws_up = false
	_open = false
	_drop_pc()
	_role = ""
