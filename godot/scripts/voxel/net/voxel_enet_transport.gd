class_name VoxelEnetTransport
extends NetTransport
## The voxel arena's co-op over a plain address (LAN, a forwarded port, Tailscale; and the headless two-game tests):
## ENet over UDP, channel 0 reliable and in order, channel 1 unreliable (positions). The host listens on PORT; the
## guest's code is the host's address ("192.168.1.20", "203.0.113.5:24643"), or anything else for this machine.
## Owned by the voxel session.

const PORT := 24643
const RETRY := 3.0              # seconds a guest's try waits for an answer before starting again (a fresh socket)

var port := PORT
var _enet: ENetConnection
var _peer: ENetPacketPeer
var _role := ""
var _open := false
var _addr := ""
var _port := PORT
var _tries := 0
var _try_t := 0.0
var _clock := 0.0

func kind() -> String:
	return "Direct"

func host(code: String) -> void:
	close()
	_role = "host"
	_enet = ENetConnection.new()
	if _enet.create_host_bound("*", port, 1, 2) != OK:
		status.emit("can't open port %d (another copy hosting?)" % port, "bad")
		_enet = null
		return
	status.emit("hosting on port %d — waiting for player 2" % port, "live")
	opened.emit(code)

func join(code: String) -> void:
	close()
	_role = "guest"
	var addr := "127.0.0.1"
	var p := port
	if code.is_valid_ip_address() or code.contains(".") or code.contains(":"):
		var hp := code.rsplit(":", true, 1)
		addr = hp[0]
		if hp.size() > 1 and hp[1].is_valid_int():
			p = int(hp[1])
	_addr = addr
	_port = p
	_tries = 0
	_try()
	opened.emit(code)

# one go at reaching the host, on a fresh socket (tried again every RETRY seconds till it answers: F8 pressed before
# the host was up just waits)
func _try() -> void:
	if _enet:
		_enet.destroy()
	_peer = null
	_tries += 1
	_try_t = 0.0
	_enet = ENetConnection.new()
	_enet.create_host(1, 2)
	_peer = _enet.connect_to_host(_addr, _port, 2)
	status.emit("connecting to %s:%d…%s" % [_addr, _port, "" if _tries == 1 else " (try %d)" % _tries], "")

func is_open() -> bool:
	return _open

func send(data: PackedByteArray) -> void:
	if _open and _peer:
		_peer.send(0, data, ENetPacketPeer.FLAG_RELIABLE)

func send_fast(data: PackedByteArray) -> void:
	if _open and _peer:
		_peer.send(1, data, ENetPacketPeer.FLAG_UNSEQUENCED)

func poll() -> void:
	if _enet == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - _clock, 0.0, 0.5) if _clock > 0.0 else 0.0
	_clock = now
	if _role == "guest" and not _open:
		_try_t += dt
		if _try_t > RETRY:
			_try()
	while true:
		var ev := _enet.service()
		var type: int = ev[0]
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var p: ENetPacketPeer = ev[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				if _role == "host" and _open:
					p.peer_disconnect_now()       # (one guest at a time)
					continue
				_peer = p
				_open = true
				status.emit("player 2 connected" if _role == "host" else "connected — you are player 2", "live")
				connected.emit()
			ENetConnection.EVENT_DISCONNECT:
				if p == _peer:
					_open = false
					_peer = null
					status.emit("player 2 left" if _role == "host" else "lost the connection", "bad")
					disconnected.emit()
			ENetConnection.EVENT_RECEIVE:
				var data := p.get_packet()
				if p == _peer:
					received.emit(data)

func drop_peer() -> void:
	if _peer:
		_peer.peer_disconnect_now()
	_peer = null
	_open = false

func close() -> void:
	if _peer:
		_peer.peer_disconnect_now()
	_peer = null
	if _enet:
		_enet.flush()
		_enet.destroy()
	_enet = null
	_open = false
	_role = ""
