class_name PeerJsTransport
extends NetTransport
## The web build's connection: the HTML game's own PeerJS set-up (Smashed.html "NET": PEER_OPTS with its STUN and
## TURN servers, the room code as the host's peer id, a reliable data channel, the same status lines), run in the
## page through JavaScriptBridge as window.SmashedNet. PeerJS's broker only introduces the two browsers; then
## it's a direct WebRTC data channel, so it works from GitHub Pages with no server of ours.
## Owned by the Online task.
##
## The page's address can point it elsewhere (tests, or a broker of your own):
##   ?peerjs=<url of peerjs.min.js>   (default unpkg.com/peerjs@1.5.4, the HTML game's)
##   ?peer=<host>:<port>[/path]       a PeerJS server (e.g. `npx peer --port 9000`), plain ws unless ?peerssl
## Messages go as base64 strings; long ones are cut into pieces and put back together on the other side.

const LIB := "https://unpkg.com/peerjs@1.5.4/dist/peerjs.min.js"
## Peer ids are this plus the room code (the HTML game uses "jucyjared-": a different prefix keeps the two
## games' rooms apart, since they don't speak the same messages).
const PREFIX := "smashedgd-"

const JS := r"""
(function () {
if (window.SmashedNet) return;
const N = { q: [], peer: null, conn: null, role: '', code: '', parts: {}, server: null, lib: '', ready: false, otherId: '' };
window.SmashedNet = N;
const ev = o => N.q.push(o);
N.poll = function () { if (!N.q.length) return ''; const s = JSON.stringify(N.q); N.q = []; return s; };
N.status = (text, cls) => ev({ e: 'status', text: text, cls: cls || '' });
const ICE = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
  { urls: 'stun:stun.cloudflare.com:3478' },
  { urls: 'turn:global.relay.metered.ca:80', username: '717ffe96ec1375e0fb3f834b', credential: 'v/tattI18wAT8wvM' },
  { urls: 'turn:global.relay.metered.ca:443', username: '717ffe96ec1375e0fb3f834b', credential: 'v/tattI18wAT8wvM' },
  { urls: 'turn:global.relay.metered.ca:443?transport=tcp', username: '717ffe96ec1375e0fb3f834b', credential: 'v/tattI18wAT8wvM' },
  { urls: 'turns:global.relay.metered.ca:443?transport=tcp', username: '717ffe96ec1375e0fb3f834b', credential: 'v/tattI18wAT8wvM' }
];
N.opts = function () {
  const o = { debug: 1, secure: true, config: { iceServers: ICE } };
  if (N.server) { o.host = N.server.host; o.port = N.server.port; o.path = N.server.path || '/'; o.secure = !!N.server.secure; if (N.server.local) o.config = { iceServers: [] }; }
  return o;
};
N.setup = function (lib, server) {
  N.lib = lib; N.server = server ? JSON.parse(server) : null;
  if (window.Peer) { N.ready = true; return; }
  const s = document.createElement('script');
  s.src = lib;
  s.onload = () => { N.ready = true; ev({ e: 'loaded' }); };
  s.onerror = () => N.status('PeerJS did not load — need internet', 'bad');
  document.head.appendChild(s);
};
N.kill = function () {
  const c = N.conn, p = N.peer;
  N.conn = null; N.peer = null; N.parts = {};
  try { if (c) c.close(); } catch (_) {}
  try { if (p) p.destroy(); } catch (_) {}
};
// the Mega Drive cabinet's picture and sound come as a PeerJS media call (SmashedMD, scripts/arcade/md_bridge_js.gd)
function takeCalls(peer) {
  peer.on('call', call => { if (N.peer !== peer) return; if (window.SmashedMD) window.SmashedMD.answerCall(call); else call.close(); });
}
function wire(conn) {
  N.conn = conn;
  const timeout = setTimeout(() => {
    if (N.conn !== conn || conn.open) return;
    conn.close(); if (N.conn === conn) N.conn = null;
    N.status('Connection timed out. Check the room code.', 'bad');
  }, 15000);
  conn.on('open', () => {
    if (N.conn !== conn) { conn.close(); return; }
    clearTimeout(timeout);
    N.otherId = conn.peer;
    N.status(N.role === 'host' ? 'player 2 connected' : 'connected — you are player 2', 'live');
    ev({ e: 'open' });
  });
  conn.on('data', d => {
    if (N.conn !== conn || typeof d !== 'string') return;
    if (d.charCodeAt(0) === 126) {          // "~id|i|n|piece": one piece of a long message
      const a = d.indexOf('|'), b = d.indexOf('|', a + 1), c = d.indexOf('|', b + 1);
      const id = d.slice(1, a), i = +d.slice(a + 1, b), n = +d.slice(b + 1, c);
      const P = N.parts[id] || (N.parts[id] = { n: n, got: 0, s: [] });
      if (P.s[i] === undefined) { P.s[i] = d.slice(c + 1); P.got++; }
      if (P.got === P.n) { delete N.parts[id]; ev({ e: 'data', d: P.s.join('') }); }
      return;
    }
    ev({ e: 'data', d: d });
  });
  conn.on('close', () => {
    clearTimeout(timeout);
    if (N.conn !== conn) return;
    N.conn = null;
    N.status(N.role === 'host' ? 'Player 2 left. Room ' + N.code + ' is open.' : 'Disconnected. Join again or Leave.', 'bad');
    ev({ e: 'close' });
  });
  conn.on('error', e => { if (N.conn !== conn) return; conn.close(); N.status('connection error: ' + (e.type || e), 'bad'); });
}
N.host = function (code, id) {
  if (!window.Peer) { N.status('PeerJS did not load — need internet', 'bad'); return; }
  if (typeof RTCPeerConnection === 'undefined') { N.status('WebRTC is unavailable. Open this game in Chrome, Edge, Firefox or Safari.', 'bad'); return; }
  N.kill(); N.role = 'host'; N.code = code;
  N.status('opening room…');
  const peer = N.peer = new Peer(id, N.opts());
  takeCalls(peer);
  peer.on('open', () => { if (N.peer === peer) { N.status('room ' + code + ' — waiting for player 2', 'live'); ev({ e: 'room', code: code }); } });
  peer.on('connection', c => { if (N.peer !== peer || (N.conn && N.conn.open)) { c.close(); return; } wire(c); });
  peer.on('disconnected', () => { if (N.peer !== peer || peer.destroyed) return; N.status('signaling dropped — reconnecting…', 'bad'); try { peer.reconnect(); } catch (_) {} });
  peer.on('error', e => { if (N.peer !== peer) return; if (e.type === 'unavailable-id') ev({ e: 'taken' }); else N.status('host error: ' + e.type, 'bad'); });
};
N.join = function (code, id) {
  if (!window.Peer) { N.status('PeerJS did not load — need internet', 'bad'); return; }
  if (typeof RTCPeerConnection === 'undefined') { N.status('WebRTC is unavailable. Open this game in Chrome, Edge, Firefox or Safari.', 'bad'); return; }
  N.kill(); N.role = 'client'; N.code = code;
  N.status('connecting to ' + code + '…');
  const peer = N.peer = new Peer(N.opts());
  takeCalls(peer);
  peer.on('open', () => {
    if (N.peer !== peer) return;
    N.status('found broker — calling room ' + code + '…');
    const c = peer.connect(id, { reliable: true, serialization: 'json' });
    if (!c) { N.status('join failed to start', 'bad'); return; }
    wire(c);
    ev({ e: 'room', code: code });
    setTimeout(() => { if (N.peer === peer && (!N.conn || !N.conn.open)) N.status('no answer from ' + code + ' — is the host waiting, same build?', 'bad'); }, 8000);
  });
  peer.on('error', e => {
    if (N.peer !== peer) return;
    if (e.type === 'peer-unavailable') N.status('room ' + code + ' not found — host first, then join', 'bad');
    else if (e.type === 'network' || e.type === 'server-error') N.status('cannot reach PeerJS cloud (need internet / port 443)', 'bad');
    else N.status('join error: ' + e.type, 'bad');
  });
};
let seq = 0;
N.send = function (s) {
  const c = N.conn; if (!c || !c.open) return;
  const MAX = 15000;
  if (s.length <= MAX) { c.send(s); return; }
  const id = (++seq).toString(36), n = Math.ceil(s.length / MAX);
  for (let i = 0; i < n; i++) c.send('~' + id + '|' + i + '|' + n + '|' + s.slice(i * MAX, (i + 1) * MAX));
};
N.isOpen = () => !!(N.conn && N.conn.open);
N.drop = function () { const c = N.conn; N.conn = null; N.parts = {}; if (c) { try { c.close(); } catch (_) {} } };
})();
"""

var _js: JavaScriptObject
var _open := false
var _role := ""
var _code := ""
var _pending := ""          # host/join asked for before the library loaded: "host:CODE" / "join:CODE"

func _init() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(JS, true)
	_js = JavaScriptBridge.get_interface("SmashedNet")
	var args := _page_args()
	var lib: String = args.get("peerjs", LIB)
	var server := ""
	if args.has("peer"):
		var s: String = args["peer"]
		var path := "/"
		var slash := s.find("/")
		if slash >= 0:
			path = s.substr(slash)
			s = s.substr(0, slash)
		var hp := s.split(":")
		server = JSON.stringify({"host": hp[0], "port": int(hp[1]) if hp.size() > 1 else 9000, "path": path,
			"secure": args.has("peerssl"), "local": args.has("peerlocal") or hp[0] == "127.0.0.1" or hp[0] == "localhost"})
	_js.setup(lib, server)

static func available() -> bool:
	return OS.has_feature("web")

func kind() -> String:
	return "PeerJS"

func host(code: String) -> void:
	_role = "host"
	_code = code
	_open = false
	if _js == null:
		status.emit("online play needs the web build", "bad")
		return
	if not bool(_js.ready):
		_pending = "host:" + code
		status.emit("loading PeerJS…", "")
		return
	_js.host(code, PREFIX + code)

func join(code: String) -> void:
	_role = "client"
	_code = code
	_open = false
	if _js == null:
		status.emit("online play needs the web build", "bad")
		return
	if not bool(_js.ready):
		_pending = "join:" + code
		status.emit("loading PeerJS…", "")
		return
	_js.join(code, PREFIX + code)

func send(data: PackedByteArray) -> void:
	if _js and _open:
		_js.send(Marshalls.raw_to_base64(data))

func is_open() -> bool:
	return _open

func drop_peer() -> void:
	_open = false
	if _js:
		_js.drop()

func close() -> void:
	_open = false
	_pending = ""
	if _js:
		_js.kill()

## The other side's PeerJS peer and id (for the Mega Drive cabinet's video call).
func js_peer():
	return _js.peer if _js else null

func other_id() -> String:
	return String(_js.otherId) if _js else ""

func poll() -> void:
	if _js == null:
		return
	var s = _js.poll()
	if not (s is String) or s == "":
		return
	var list = JSON.parse_string(s)
	if not (list is Array):
		return
	for e in list:
		if not (e is Dictionary):
			continue
		match String(e.get("e", "")):
			"loaded":
				if _pending != "":
					var p := _pending
					_pending = ""
					if p.begins_with("host:"):
						host(p.substr(5))
					else:
						join(p.substr(5))
			"status":
				status.emit(String(e.get("text", "")), String(e.get("cls", "")))
			"room":
				opened.emit(String(e.get("code", _code)))
			"taken":
				# the code's in use: the HTML game picks another and tries again
				status.emit("code taken, retrying…", "")
				host(Net.make_code())
			"open":
				_open = true
				connected.emit()
			"data":
				if _open:
					received.emit(Marshalls.base64_to_raw(String(e.get("d", ""))))
			"close":
				var was := _open
				_open = false
				if was:
					disconnected.emit()

static func _page_args() -> Dictionary:
	var out := {}
	if not OS.has_feature("web"):
		return out
	var q = JavaScriptBridge.eval("window.location.search", true)
	if q is String:
		for p in q.trim_prefix("?").split("&", false):
			var kv: PackedStringArray = String(p).split("=", true, 1)
			out[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out
