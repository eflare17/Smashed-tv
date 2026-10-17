class_name ENetTransport
extends NetTransport
## A native connection (desktop builds, and the headless two-game tests): ENet over UDP, one reliable channel.
## The host listens on PORT; the guest's "code" is the host's address ("192.168.1.20", "127.0.0.1:24642"),
## or a room code, which means this machine (two copies of the game side by side).
## Owned by the Online task.

const PORT := 24642

var _enet: ENetConnection
var _peer: ENetPacketPeer
var _role := ""
var _code := ""
var _open := false
var _port := PORT

func kind() -> String:
	return "LAN"

func host(code: String) -> void:
	close()
	_role = "host"
	_code = code
	_enet = ENetConnection.new()
	var err := _enet.create_host_bound("*", _port, 1, 1)
	if err != OK:
		status.emit("can't open port %d (another copy hosting?)" % _port, "bad")
		_enet = null
		return
	status.emit("room %s — waiting for player 2 (LAN port %d)" % [code, _port], "live")
	opened.emit(code)

func join(code: String) -> void:
	close()
	_role = "client"
	_code = code
	var addr := "127.0.0.1"
	var port := _port
	if code.is_valid_ip_address() or code.contains(".") or code.contains(":"):
		var hp := code.rsplit(":", true, 1)
		addr = hp[0]
		if hp.size() > 1 and hp[1].is_valid_int():
			port = int(hp[1])
	_enet = ENetConnection.new()
	_enet.create_host(1, 1)
	_peer = _enet.connect_to_host(addr, port, 1)
	status.emit("connecting to %s…" % code, "")
	opened.emit(code)

func send(data: PackedByteArray) -> void:
	if _open and _peer:
		_peer.send(0, data, ENetPacketPeer.FLAG_RELIABLE)

func is_open() -> bool:
	return _open

func drop_peer() -> void:
	if _peer:
		_peer.peer_disconnect_now()
	_peer = null
	_open = false

func set_port(p: int) -> void:
	_port = p

func close() -> void:
	if _peer and _open:
		_peer.peer_disconnect_now()
	_open = false
	_peer = null
	if _enet:
		_enet.destroy()
	_enet = null

func poll() -> void:
	if _enet == null:
		return
	for _i in 64:
		var ev := _enet.service(0)
		var t: int = ev[0]
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		var p: ENetPacketPeer = ev[1]
		match t:
			ENetConnection.EVENT_CONNECT:
				if _role == "host" and _open:
					p.peer_disconnect_now()        # one guest only
					continue
				_peer = p
				_open = true
				status.emit("player 2 connected" if _role == "host" else "connected — you are player 2", "live")
				connected.emit()
			ENetConnection.EVENT_DISCONNECT:
				if p == _peer:
					_open = false
					_peer = null
					status.emit(("Player 2 left. Room %s is open." % _code) if _role == "host" else "Disconnected. Join again or Leave.", "bad")
					disconnected.emit()
			ENetConnection.EVENT_RECEIVE:
				var pkt := p.get_packet()
				if p == _peer:
					received.emit(pkt)
