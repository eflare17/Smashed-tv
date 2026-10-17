class_name Net
extends Node
## Playing together online (milestone 4): the HTML game's co-op (Smashed.html "NET": host and join by a short
## room code, the host runs the game and sends snapshots twenty times a second, the guest sends its input).
## Owned by the Online task.
##
## Who runs what (see integration/online.md, Decisions):
## - The fight is the host's: its FightSim runs both players (the guest is its player 2, moved by the guest's
##   input); the host packs the whole sim into the snapshot (NetCodec) and the guest draws that, stepping it
##   forward between snapshots so it doesn't move in 20 fps steps (its own player predicted from its own input).
## - The clock and the farm are the host's: the clock rides in the snapshot; the farm's state goes over whenever
##   it changes, from either side (whoever acted), and the host's copy every few seconds.
## - Gothica in the lobby is the host's: the guest sees her where she is on the host's screen.
## - In the lobby each player walks themselves and does their own E things on their own screen (the wardrobe,
##   the mirror, the bong and its trip, the gym, the pool...), and tells the other what they look like: where
##   they are, their character, hair and shirt print, and the pictures lobby life shows for them (NetMirror).
## - Sleeping needs both players in bed; then the host's clock goes to morning on both screens.
##
## This node lives at /root/Net so a restart (the scene reloading) keeps the connection; main.gd calls
## Net.install(self) on every start and it hooks into the new game.

const PROTO := 1
const SNAP_HZ := 20.0
const INPUT_HZ := 30.0
const AV_HZ := 20.0
const ABC := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"     # no O/0, no I/1 (makeCode)

static var me: Net

signal changed

var role := "local"              ## "local", "host" or "client" (the HTML's net.role)
var code := ""
var status_text := "Local game — host or join to play online"
var status_kind := ""
var live := false                ## the other player is connected
var ping_ms := 0
var transport: NetTransport
var print_state := false

var main: Node
var fight: Fight
var player: Player
var p2: Player                   ## the other player's body here (it is the Fight's player 2)
var mirror := NetMirror.new()
var pics_parent: Node3D

var remote_av: Dictionary = {}   ## the other player's last avatar packet
var remote_look: Dictionary = {}
var remote_hello := false
var bytes_in := 0
var bytes_out := 0
var snaps_in := 0
var last_snap_size := 0
var pack_ms := 0.0

var _remote_in := FT.Inp.new()   # host: the guest's latest input
var _edge_use := false
var _edge_wsel := ""
var _out_in: FT.Inp              # guest: input gathered since the last send
var _snap_t := 0.0
var _in_t := 0.0
var _av_t := 0.0
var _ping_t := 0.0
var _farm_t := 0.0
var _farm_dirty := false
var _farm_applying := false
var _farm_quiet := 0.0           # guest: ignore the host's farm for a moment after acting
var _look_rev := -999
var _look_seq := 0
var _remote_look_seq := 0
var _fx_out := {"sounds": [], "events": [], "banners": []}
var _snap_pending = null         # guest: the newest snapshot not yet loaded
var _fx_in := []                 # guest: [sounds, events, banners] to play after the next step
var _was_started := false
var in_bed := false
var _both_bed := false
var _bed_node: Node              # the Lighting's BedSleep (fade + clock)
var _late: Node
var _state_t := 0.0
var _goth_off := false
var _goth_saved := {}
var _host_goth_pics: Array = []
var _target := Vector3.ZERO      # where the other player is heading (smoothed)
var _have_target := false
var _menu: Node
var _reloading := false          # a restart is under way: the old game is going

## main.gd: Net.install(self) at the end of _ready (after the Fight, the farm and lobby life).
static func install(m: Node) -> Net:
	var tree := m.get_tree()
	var n: Net = tree.root.get_node_or_null("Net")
	if n == null:
		n = Net.new()
		n.name = "Net"
		tree.root.add_child.call_deferred(n)    # (the root is busy setting up main now)
	n.call_deferred("attach", m)
	return n

static func make_code() -> String:
	var s := ""
	for i in 4:
		s += ABC[randi() % ABC.length()]
	return s

static func is_online() -> bool:
	return me != null and me.live

static func is_guest() -> bool:
	return me != null and me.role == "client"

func _enter_tree() -> void:
	me = self

func _ready() -> void:
	process_priority = 40               # before the Fight (50) drains this frame's sounds
	process_physics_priority = 40       # after the Player's step, before the Fight's
	_late = _Late.new()
	_late.net = self
	_late.process_priority = 55         # after the Fight has drawn the other player
	add_child(_late)
	var args := _args()
	print_state = args.has("netstate")
	if args.has("netdrive"):
		# tests: a script that drives this game (test/net/drive.gd)
		var sc = load(String(args["netdrive"]))
		if sc:
			var d: Node = sc.new()
			d.name = "NetDrive"
			add_child(d)

## ---------------------------------------------------------------- hooking into a (new) game

func attach(m: Node) -> void:
	main = m
	_reloading = false
	player = m.get("player")
	fight = Fight.me
	p2 = null
	_have_target = false
	_was_started = false
	_both_bed = false
	in_bed = false
	_goth_off = false
	mirror.clear_all()
	if fight:
		fight.net_request = _on_request
	pics_parent = Node3D.new()
	pics_parent.name = "NetPics"
	m.add_child(pics_parent)
	_hook_sleep()
	_hook_farm()
	_hook_md()
	_menu = NetMenu.new()
	_menu.net = self
	m.add_child(_menu)
	if live:
		_game_live(true)
	var args := _args()
	if role == "local" and not get_meta("auto_done", false):
		set_meta("auto_done", true)
		if args.has("host"):
			call_deferred("host", String(args["host"]) if String(args["host"]) != "" else "")
		elif args.has("join") and String(args["join"]) != "":
			call_deferred("join", String(args["join"]))

func _hook_sleep() -> void:
	var ll = LobbyLife.current
	var lighting = main.get_node_or_null("Lighting")
	_bed_node = lighting.get("bed") if lighting else null
	if ll == null:
		return
	for c in ll.sleep_requested.get_connections():
		ll.sleep_requested.disconnect(c.callable)
	ll.sleep_requested.connect(_on_lie_down)
	ll.woke.connect(_on_get_up)

func _on_lie_down(p) -> void:
	if p != player:
		return
	in_bed = true
	if not live:
		_sleep_now()
	_send_av()

func _on_get_up(p) -> void:
	if p == player:
		in_bed = false
		_send_av()

func _sleep_now() -> void:
	if _bed_node and _bed_node.has_method("sleep"):
		_bed_node.sleep(null)
	else:
		var c := get_node_or_null("/root/GameClock")
		if c:
			c.sleep_to_morning()

func _farm() -> Farm:
	return Farm.instance

func _hook_farm() -> void:
	var fm := _farm()
	if fm == null:
		return
	if not fm.state.changed.is_connected(_on_farm_changed):
		fm.state.changed.connect(_on_farm_changed)

func _on_farm_changed() -> void:
	if live and not _farm_applying:
		_farm_dirty = true
		if role == "client":
			_farm_quiet = 1.5

## ---------------------------------------------------------------- host, join, leave

func _make_transport() -> NetTransport:
	var args := _args()
	if PeerJsTransport.available() and not args.has("lan"):
		return PeerJsTransport.new()
	var t := ENetTransport.new()
	if args.has("netport"):
		t.set_port(int(args["netport"]))
	return t

func _new_transport() -> void:
	if transport:
		transport.close()
	transport = _make_transport()
	transport.status.connect(_on_status)
	transport.opened.connect(func(c: String): code = c; changed.emit())
	transport.connected.connect(_on_connected)
	transport.disconnected.connect(_on_disconnected)
	transport.received.connect(_on_bytes)

func host(c: String = "") -> void:
	leave(true)
	role = "host"
	code = c if c != "" else make_code()
	_new_transport()
	transport.host(code)
	changed.emit()

func join(c: String) -> void:
	c = c.strip_edges().to_upper()
	var lan := not PeerJsTransport.available() or _args().has("lan")
	if not lan and not RegEx.create_from_string("^[A-Z0-9]{4,8}$").search(c):
		_on_status("enter a valid 4–8 character room code", "bad")
		return
	leave(true)
	role = "client"
	code = c
	_new_transport()
	transport.join(code)
	changed.emit()

func leave(quiet: bool = false) -> void:
	var was_guest_run := live and role == "client" and fight != null and fight.sim.started
	if live:
		_game_live(false)
	live = false
	if transport:
		transport.close()
	transport = null
	role = "local"
	code = ""
	remote_av = {}
	remote_hello = false
	if not quiet:
		_on_status("Local game — host or join to play online", "")
	changed.emit()
	if was_guest_run and fight:
		_restart()

func _on_status(text: String, kind: String) -> void:
	status_text = text
	status_kind = kind
	changed.emit()

func _on_connected() -> void:
	live = true
	remote_av = {}
	remote_look = {}
	_remote_look_seq = 0
	_look_rev = -999
	mirror.reset_local()
	mirror.reset_remote()
	_remote_in = FT.Inp.new()
	_out_in = null
	if role == "host" and fight and fight.sim.over:
		pass
	_game_live(true)
	_send({"t": "hello", "v": PROTO, "ch": player.char_id if player else "juicy"})
	_send_look()
	if role == "host":
		_send_farm()
		_send_snap()
	changed.emit()

func _on_disconnected() -> void:
	var a := Arcade.instance()
	if a and a.md:
		a.md.friend_gone()
	var guest_run := role == "client" and fight != null and fight.sim.started
	if live:
		_game_live(false)
	live = false
	remote_av = {}
	changed.emit()
	if guest_run and fight:
		_restart()

## Turn the game here into (or back out of) a game for two.
func _game_live(on: bool) -> void:
	if main == null or not is_instance_valid(main) or fight == null:
		return
	var gc := get_node_or_null("/root/GameClock")
	var fm := _farm()
	if on:
		if p2 == null or not is_instance_valid(p2):
			_spawn_p2()
		fight.net_input2 = _input2
		fight.net_step = _guest_step if role == "client" else Callable()
		if role == "client":
			if gc:
				gc.is_host = false
			if player:
				player.set_meta("farm_pid", 1)
			if fm:
				fm.persist = false
			_goth_guest(true)
	else:
		fight.net_input2 = Callable()
		fight.net_step = Callable()
		_remove_p2()
		mirror.clear_all()
		if gc:
			gc.is_host = true
		if player and player.has_meta("farm_pid"):
			player.remove_meta("farm_pid")
		if role == "client":
			if fm:
				fm.persist = true
				_farm_applying = true
				if not fm.load_save():
					fm.state.reset()
				_farm_applying = false
			_goth_guest(false)

func _spawn_p2() -> void:
	var ch: String = remote_av.get("ch", "tyson2" if player and player.char_id == "juicy" else "juicy")
	p2 = Player.new()
	p2.name = "NetPlayer2"
	main.add_child(p2)
	p2.remove_from_group("player")
	p2.char_id = ch
	p2.controls_enabled = false
	p2.face_mouse = false
	p2.frozen = true
	p2.collision_layer = 0
	p2.collision_mask = 0
	p2.set_meta("farm_pid", 0 if role == "client" else 1)
	p2.set_meta("net_remote", true)
	var at := Vector2(480, 260)
	if remote_av.has("x"):
		at = Vector2(float(remote_av.x), float(remote_av.y))
	p2.place(at.x, at.y)
	var f2 := fight.sim.add_player(p2, ch)
	f2.driven = false
	f2.x = at.x
	f2.y = at.y
	if fight.sim.started:
		f2.coins = 0
	else:
		# the lobby's blasters, pellets and cash, like player 1's (fillLobby)
		f2.weapon = "blaster"
		f2.blasters = 1
		f2.ammo = int(fight.sim.tv("spudPellets", 10) * 2)
		f2.coins = int(maxf(fight.sim.tv("lobbyCash", 40), fight.sim.tv("testCash", 2500)))
	fight.p2 = p2
	fight.f2 = f2
	if fight.sim.started and role == "host":
		p2.collision_mask = 0

func _remove_p2() -> void:
	if fight:
		if fight.f2 and fight.sim.players.has(fight.f2):
			fight.sim.players.erase(fight.f2)
		fight.p2 = null
		fight.f2 = null
	if p2 and is_instance_valid(p2):
		p2.queue_free()
	p2 = null

## The guest's Gothica is the host's: hers stops walking by herself and lobby life leaves her alone.
func _goth_guest(on: bool) -> void:
	var g: Node = main.get("gothica") if main else null
	var gl: Node = null
	if LobbyLife.current:
		gl = LobbyLife.current.things.get("goth_life")
	if on and not _goth_off:
		_goth_off = true
		if gl:
			gl.set_physics_process(false)
			_goth_saved["gl_inter"] = gl.is_in_group("interactable")
			gl.remove_from_group("interactable")
		if g:
			g.set("_enabled", false)
	elif not on and _goth_off:
		_goth_off = false
		if gl:
			gl.set_physics_process(true)
			if _goth_saved.get("gl_inter", false):
				gl.add_to_group("interactable")
		if g:
			g.set("_enabled", true)
		mirror.clear("goth")

## ---------------------------------------------------------------- Enter, R, P

func _on_request(what: String) -> bool:
	if not live:
		return false
	match what:
		"add_player":
			return true                        # player 2 is the friend
		"start", "restart":
			if role == "client":
				_send({"t": "req", "r": what})
				return true
			if what == "restart":
				_send({"t": "restart"})
				_reloading = true
				_snap_pending = null
			return false
	return false

## ---------------------------------------------------------------- the wire

func _send(d: Dictionary) -> void:
	if transport == null or not transport.is_open():
		return
	var raw := var_to_bytes(d)
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(z)
	bytes_out += out.size()
	transport.send(out)

func _on_bytes(b: PackedByteArray) -> void:
	bytes_in += b.size()
	if b.size() < 4:
		return
	var n := b.decode_u32(0)
	if n <= 0 or n > 64 * 1024 * 1024:
		return
	var raw := b.slice(4).decompress(n, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != n:
		return
	var d = bytes_to_var(raw)
	if d is Dictionary:
		if String(d.get("t", "")) == "snap":
			last_snap_size = b.size()
		_on_message(d)

func _on_message(d: Dictionary) -> void:
	var t := String(d.get("t", ""))
	if t.begins_with("md"):
		_md_message(d)
		return
	match t:
		"hello":
			remote_hello = true
			if int(d.get("v", 0)) != PROTO:
				_on_status("the other game is a different build — update both", "bad")
		"tex":
			for e in d.get("l", []):
				mirror.add_texture(e)
		"av":
			_on_av(d)
		"look":
			remote_look = d
			for k in [["fr", "_front"], ["bk", "_back"]]:
				var png: PackedByteArray = d.get(k[0], PackedByteArray())
				var img: Image = null
				if png.size() > 0:
					img = Image.new()
					if img.load_png_from_buffer(png) != OK:
						img = null
				remote_look[k[1]] = img
			_remote_look_seq += 1
		"in":
			if role == "host":
				var inp := NetCodec.unpack_inp(d.get("i"))
				_remote_in = inp
				if inp.use:
					_edge_use = true
				if inp.wsel != "":
					_edge_wsel = inp.wsel
		"req":
			if role == "host" and fight:
				var r := String(d.get("r", ""))
				print("Net: the guest asks to ", r)
				if r == "start" and not fight.sim.started:
					fight.start_run(true)
				elif r == "restart":
					_send({"t": "restart"})
					_restart()
		"restart":
			if role == "client" and fight:
				print("Net: the host restarted")
				_restart()
		"snap":
			if role == "client":
				snaps_in += 1
				_snap_pending = d.get("s", {})
				if fight == null or not fight.net_step.is_valid():
					_apply_snap_now()
		"farm":
			_on_farm(d)
		"sleep":
			if role == "client":
				_sleep_now()
		"ping":
			_send({"t": "pong", "a": d.get("a", 0)})
		"pong":
			ping_ms = Time.get_ticks_msec() - int(d.get("a", 0))

## ---------------------------------------------------------------- every frame

func _process(dt: float) -> void:
	if transport:
		transport.poll()
	if print_state:
		_print_state(dt)
	if not live or main == null or not is_instance_valid(main) or fight == null or _reloading:
		return
	if role == "host":
		_collect_fx()
	_av_t += dt
	if _av_t >= 1.0 / AV_HZ:
		_av_t = 0.0
		_send_av()
	if LobbyLook.rev != _look_rev:
		_send_look()
	_ping_t += dt
	if _ping_t >= 2.0:
		_ping_t = 0.0
		_send({"t": "ping", "a": Time.get_ticks_msec()})
	_farm_quiet = maxf(0.0, _farm_quiet - dt)
	_farm_t += dt
	if _farm_dirty and _farm_t >= 0.25:
		_farm_dirty = false
		_farm_t = 0.0
		_send_farm()
	elif role == "host" and _farm_t >= 4.0:
		_farm_t = 0.0
		_send_farm()
	if role == "host":
		_snap_t += dt
		if _snap_t >= 1.0 / SNAP_HZ:
			_snap_t = 0.0
			_send_snap()
		_check_beds()
	else:
		if _snap_pending != null and fight.has_meta("frozen"):
			_apply_snap_now()          # (the Fight isn't stepping: the bonus room's cinematics)
		_in_t += dt
		if _in_t >= 1.0 / INPUT_HZ and _out_in != null:
			_in_t = 0.0
			_send({"t": "in", "i": NetCodec.pack_inp(_out_in)})
			_out_in = null

func _physics_process(dt: float) -> void:
	if not live or p2 == null or not is_instance_valid(p2) or fight == null:
		return
	if fight.sim.started:
		_have_target = false
		return
	# the other player in the lobby: where their screen has them, smoothed (and a little ahead by their speed)
	if remote_av.has("x"):
		var tgt := GameData.world_to_3d(float(remote_av.x), float(remote_av.y), float(remote_av.get("dz", 0.0)))
		if not _have_target or p2.global_position.distance_to(tgt) > 3.0:
			p2.global_position = tgt
			p2.reset_physics_interpolation()
			_have_target = true
		else:
			p2.global_position = p2.global_position.lerp(tgt, 1.0 - pow(0.0001, dt))
		p2.facing = Vector2(float(remote_av.get("fx", 0.0)), float(remote_av.get("fy", 1.0)))
		p2.moving = bool(remote_av.get("mv", false))
		p2.odo = float(remote_av.get("odo", 0.0))
		p2.roll = float(remote_av.get("roll", 0.0))
		p2.dz = float(remote_av.get("dz", 0.0))
		p2.on_tramp = bool(remote_av.get("tr", false))
		var ch := String(remote_av.get("ch", p2.char_id))
		if ch != p2.char_id:
			p2.char_id = ch
		var f2 := fight.f2
		if f2:
			var hp := p2.html_pos()
			f2.x = hp.x
			f2.y = hp.y
			f2.ch = ch
			if role == "host":
				f2.fx = p2.facing.x
				f2.fy = p2.facing.y

## After the Fight has set the other player's picture: hide it while lobby life shows a pose of theirs, put
## their hair and shirt on it, and stand their pose pictures (and the host's Gothica's) here.
func late_process() -> void:
	if not live or p2 == null or not is_instance_valid(p2) or fight == null:
		return
	var lobby := not fight.sim.started
	var spr := p2.sprite
	if lobby and remote_av.has("x"):
		if spr and not bool(remote_av.get("sv", true)):
			spr.visible = false
		mirror.apply("p2", pics_parent, remote_av.get("pics", []))
	else:
		mirror.apply("p2", pics_parent, [])
	if spr and spr.visible and spr.char_id == "juicy" and spr.current_path != "":
		_wear_remote_look(spr)

func _wear_remote_look(s: CharSprite) -> void:
	if remote_look.is_empty():
		return
	var keep := [LobbyLook.style, LobbyLook.art_front, LobbyLook.art_back, LobbyLook.place_front,
		LobbyLook.place_back, LobbyLook.smooth, LobbyLook.rev]
	LobbyLook.style = int(remote_look.get("st", 0))
	LobbyLook.art_front = remote_look.get("_front")
	LobbyLook.art_back = remote_look.get("_back")
	LobbyLook.place_front = remote_look.get("pf", Rect2(0, 0, 1, 1))
	LobbyLook.place_back = remote_look.get("pb", Rect2(0, 0, 1, 1))
	LobbyLook.smooth = bool(remote_look.get("sm", true))
	LobbyLook.rev = 1000000 + _remote_look_seq
	var tex := LobbyLook.baked(s.current_path, GameData.tex(s.current_path), s.current_flip)
	LobbyLook.style = keep[0]
	LobbyLook.art_front = keep[1]
	LobbyLook.art_back = keep[2]
	LobbyLook.place_front = keep[3]
	LobbyLook.place_back = keep[4]
	LobbyLook.smooth = keep[5]
	LobbyLook.rev = keep[6]
	if s._mat and tex != s._mat.get_shader_parameter("tex"):
		s._mat.set_shader_parameter("tex", tex)

## ---------------------------------------------------------------- what I look like

func _send_av() -> void:
	if not live or player == null or not is_instance_valid(player):
		return
	var hp := player.html_pos()
	var fp := player.is_first_person()
	var ll = LobbyLife.current
	var pose = ll.pose_of(player) if ll else null
	var shown := true
	if fp:
		shown = pose == null and not (ll and ll.busy.has(player) and bool(ll.busy[player].hides_sprite(player)))
	elif player.sprite:
		shown = player.sprite.visible
	var also := [pose] if pose else []
	var pics := mirror.capture([player], also) if not fight.sim.started else []
	var tex := mirror.take_outgoing()
	if not tex.is_empty():
		_send({"t": "tex", "l": tex})
	_send({"t": "av", "x": hp.x, "y": hp.y, "dz": player.dz, "fx": player.facing.x, "fy": player.facing.y,
		"mv": player.moving, "odo": player.odo, "roll": player.roll, "ch": player.char_id, "tr": player.on_tramp,
		"sv": shown, "pics": pics, "bed": in_bed, "fp": fp})

func _on_av(d: Dictionary) -> void:
	remote_av = d
	if p2 and is_instance_valid(p2):
		var ch := String(d.get("ch", p2.char_id))
		if ch != p2.char_id:
			p2.char_id = ch

func _send_look() -> void:
	_look_rev = LobbyLook.rev
	var d := {"t": "look", "st": LobbyLook.style, "pf": LobbyLook.place_front, "pb": LobbyLook.place_back,
		"sm": LobbyLook.smooth, "fr": PackedByteArray(), "bk": PackedByteArray()}
	if LobbyLook.art_front:
		d["fr"] = LobbyLook.art_front.save_png_to_buffer()
	if LobbyLook.art_back:
		d["bk"] = LobbyLook.art_back.save_png_to_buffer()
	_send(d)

## ---------------------------------------------------------------- host: the snapshot

func _collect_fx() -> void:
	var s := fight.sim
	_fx_out.sounds.append_array(s.sounds)
	_fx_out.events.append_array(s.events)
	_fx_out.banners.append_array(s.banners)

func _send_snap() -> void:
	if fight == null:
		return
	var t0 := Time.get_ticks_usec()
	var s := {"fight": NetCodec.pack_sim(fight.sim), "fx": _fx_out, "mode": fight.mode}
	pack_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_fx_out = {"sounds": [], "events": [], "banners": []}
	var gc := get_node_or_null("/root/GameClock")
	if gc:
		s["clock"] = gc.save_state()
	s["goth"] = _goth_state()
	s["bed"] = in_bed
	var tex := mirror.take_outgoing()
	if not tex.is_empty():
		_send({"t": "tex", "l": tex})
	_send({"t": "snap", "s": s})

func _goth_state() -> Dictionary:
	var g: Gothica = main.get("gothica") if main else null
	if g == null or fight.sim.started:
		return {}
	var hp := g.html_pos2()
	var gl: Node = LobbyLife.current.things.get("goth_life") if LobbyLife.current else null
	var spr := g.sprite
	return {"x": hp.x, "y": hp.y, "z": GameData.from_3d(g.global_position).z, "fx": g.facing.x, "fy": g.facing.y,
		"mv": g.moving, "odo": g.odo, "vis": g.visible, "sv": spr.visible if spr else false,
		"pics": mirror.capture([gl] if gl else [])}

func _check_beds() -> void:
	var both := in_bed and bool(remote_av.get("bed", false))
	if both and not _both_bed:
		_send({"t": "sleep"})
		_sleep_now()
	_both_bed = both

## ---------------------------------------------------------------- host: the guest's input

func _input2() -> FT.Inp:
	if role == "client":
		# the guest's guess at the host's player between snapshots: still walking the way he was
		var inp := FT.Inp.new()
		var f2 := fight.f2
		if f2 and f2.moving:
			inp.mx = f2.ix
			inp.my = f2.iy
		return inp
	var r := _remote_in
	var inp := FT.Inp.new()
	inp.mx = r.mx
	inp.my = r.my
	inp.ax = r.ax
	inp.ay = r.ay
	inp.shoot = r.shoot
	inp.roll = r.roll
	inp.st = r.st
	inp.tc = r.tc
	inp.tap = r.tap
	inp.tx = r.tx
	inp.ty = r.ty
	inp.lt = r.lt
	inp.lx = r.lx
	inp.ly = r.ly
	inp.use = _edge_use
	inp.wsel = _edge_wsel
	_edge_use = false
	_edge_wsel = ""
	return inp

## ---------------------------------------------------------------- guest: the host's game

## The Fight's step on the guest: load the newest snapshot, then step it on by this tick with my own input (no
## shots: those come back from the host) so things move smoothly; the host's sounds play once each.
func _guest_step(inputs: Array, dt: float) -> void:
	var own: FT.Inp = inputs[0]
	_gather_input(own)
	if _snap_pending != null:
		_apply_snap_now()
		if fight == null or not is_instance_valid(fight):
			return
	var sim := fight.sim
	var pred := FT.Inp.new()
	pred.mx = own.mx
	pred.my = own.my
	pred.roll = own.roll
	pred.ax = own.ax
	pred.ay = own.ay
	pred.st = own.st
	pred.wsel = own.wsel
	var ins := [pred, inputs[1] if inputs.size() > 1 else FT.Inp.new()]
	# nobody gets hurt in the guess (the host says who's hit): the wave-start grace, put back after
	var grace := []
	for f: FT.Fighter in sim.players:
		grace.append(f.grace)
		f.grace = maxf(f.grace, 1.0)
	sim.step(ins, dt)
	for i in mini(grace.size(), sim.players.size()):
		sim.players[i].grace = maxf(0.0, grace[i] - dt) if grace[i] > 0.0 else 0.0
	sim.sounds.clear()
	sim.events.clear()
	sim.banners.clear()
	for e in _fx_in:
		sim.sounds.append_array(e[0])
		sim.events.append_array(e[1])
		sim.banners.append_array(e[2])
	_fx_in.clear()

func _gather_input(inp: FT.Inp) -> void:
	if _out_in == null:
		_out_in = inp
		return
	var keep_use := _out_in.use or inp.use
	var keep_wsel := inp.wsel if inp.wsel != "" else _out_in.wsel
	var keep_roll := _out_in.roll or inp.roll
	_out_in = inp
	_out_in.use = keep_use
	_out_in.wsel = keep_wsel
	_out_in.roll = keep_roll

func _apply_snap_now() -> void:
	var s = _snap_pending
	_snap_pending = null
	if not (s is Dictionary) or fight == null or _reloading:
		return
	var gc := get_node_or_null("/root/GameClock")
	if gc and s.has("clock"):
		gc.is_host = false
		gc.load_state(s.clock)
	var fd: Dictionary = s.get("fight", {})
	var started := bool(fd.get("started", false))
	if not started and fight.sim.started:
		print("Net: the host is back in the lobby")
		_restart()             # the host is back in the lobby (a restart): so are we
		return
	fight.mode = String(s.get("mode", fight.mode))
	if started and not fight.sim.started:
		fight.start_run(true)
	if fight.f2 == null:
		_spawn_p2()
	NetCodec.unpack_sim(fight.sim, fd, true)
	var fx: Dictionary = s.get("fx", {})
	_fx_in.append([fx.get("sounds", []), fx.get("events", []), fx.get("banners", [])])
	_apply_goth(s.get("goth", {}))

func _apply_goth(g: Dictionary) -> void:
	var gn: Gothica = main.get("gothica") if main else null
	if gn == null or g.is_empty() or fight.sim.started:
		mirror.apply("goth", pics_parent, [])
		return
	gn.set("_enabled", false)
	gn.global_position = GameData.world_to_3d(float(g.x), float(g.y), float(g.get("z", 0.0)))
	gn.facing = Vector2(float(g.fx), float(g.fy))
	gn.moving = bool(g.mv)
	gn.odo = float(g.odo)
	gn.visible = bool(g.get("vis", true))
	if gn.sprite:
		gn.sprite.facing = gn.facing
		gn.sprite.moving = gn.moving
		gn.sprite.odo = gn.odo
		gn.sprite.visible = bool(g.get("sv", true))
	mirror.apply("goth", pics_parent, g.get("pics", []))

## ---------------------------------------------------------------- the farm

func _send_farm() -> void:
	var fm := _farm()
	if fm == null:
		return
	var d := fm.state.to_dict()
	_send({"t": "farm", "d": d})

func _on_farm(d: Dictionary) -> void:
	var fm := _farm()
	if fm == null:
		return
	if role == "client" and _farm_quiet > 0.0:
		return
	_farm_applying = true
	fm.state.from_dict(d.get("d", {}))
	fm._clock_reset()
	_farm_applying = false
	if role == "host":
		fm._save_soon()

## ---------------------------------------------------------------- the Mega Drive cabinet (player 2)

## The arcade's friend hooks (integration/arcade.md): its messages go over this connection; when the friend asks
## to join, whoever is playing calls them with the emulator's picture and sound (a PeerJS media call).
func _hook_md() -> void:
	var a := Arcade.instance()
	if a == null or a.md == null:
		return
	a.md.friend_send = func(msg: Dictionary):
		if live:
			_send(msg)
	a.md.friend_name = _char_name(player.char_id if player else "juicy")
	if not a.md.friend_joined.is_connected(_on_md_join):
		a.md.friend_joined.connect(_on_md_join)

func _on_md_join() -> void:
	if OS.has_feature("web") and transport is PeerJsTransport:
		JavaScriptBridge.eval("try{SmashedMD.streamTo(SmashedNet.peer, SmashedNet.otherId)}catch(e){console.log('md stream', e)}", true)

func _restart() -> void:
	if _reloading or fight == null:
		return
	_reloading = true
	_snap_pending = null
	fight.restart(true)

static func _char_name(id: String) -> String:
	for c in Hud.CHARACTERS:
		if c[0] == id:
			return c[1]
	return "Your friend"

func _md_message(d: Dictionary) -> void:
	var a := Arcade.instance()
	if a and a.md and a.md.has_method("on_friend_message"):
		a.md.on_friend_message(d)

## ---------------------------------------------------------------- tests

func _print_state(dt: float) -> void:
	_state_t += dt
	if _state_t < 0.5:
		return
	_state_t = 0.0
	var me_s := ""
	if player and is_instance_valid(player):
		var hp := player.html_pos()
		me_s = "%.0f,%.0f" % [hp.x, hp.y]
	var them := ""
	if p2 and is_instance_valid(p2):
		var hp2 := p2.html_pos()
		them = "%.0f,%.0f ch=%s" % [hp2.x, hp2.y, p2.char_id]
	var fs := ""
	if fight:
		var s := fight.sim
		fs = "started=%s wave=%d enemies=%d bullets=%d players=%d hp=%.0f coins=%d" % [s.started, s.wave, s.enemies.size(),
			s.bullets.size(), s.players.size(), fight.f.hp if fight.f else -1.0, fight.f.coins if fight.f else -1]
		if fight.f2:
			fs += " p2hp=%.0f p2alive=%s p2shots=%d" % [fight.f2.hp, fight.f2.alive, fight.f2.shots]
	var gc := get_node_or_null("/root/GameClock")
	var clock := ("day=%d hour=%.2f" % [gc.day, gc.hour]) if gc else ""
	var fm := _farm()
	var farm := ""
	if fm:
		var planted := 0
		for p in fm.state.plots:
			if int(p.s) >= 0:
				planted += 1
		farm = "planted=%d" % planted
	print("NET role=%s live=%s code=%s status=\"%s\" me=%s them=%s bed=%s/%s ping=%d snap=%dB pack=%.1fms in=%d out=%d %s %s %s" % [
		role, live, code, status_text, me_s, them, in_bed, remote_av.get("bed", false), ping_ms, last_snap_size, pack_ms,
		bytes_in, bytes_out, fs, clock, farm])

static func _args() -> Dictionary:
	var out := {}
	var parts: PackedStringArray = []
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			parts = q.trim_prefix("?").split("&", false)
	for a in OS.get_cmdline_user_args():
		parts.append(a.trim_prefix("--"))
	for p in parts:
		var kv: PackedStringArray = String(p).split("=", true, 1)
		out[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out

class _Late extends Node:
	var net: Net
	func _process(_dt: float) -> void:
		net.late_process()
