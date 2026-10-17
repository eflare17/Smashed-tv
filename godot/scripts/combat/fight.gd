class_name Fight
extends Node3D
## Milestone 2, the fighting, in the running game. FightInstall.install(main) adds one of these.
##
## It owns the FightSim (the HTML game's world for the fight, stepped at 1/120 s with an accumulator) and its views
## (FightView, EnemyView, ArenaRoom, FightHud), reads the local player's input the HTML game's way (localInput0 and,
## in first person, shroomInput: mouse aim on the floor, the pad's right stick and RT, the touch sticks, the
## weapon keys), and plays the sounds and banners the sim queues.
##
## In the lobby the Player node walks himself (milestone 1) and the sim only reads where he is, shoots for him and
## adds its pushes (recoil, the punch lunge) to his velocity. In a run (Enter, the Start button, the pad's Menu)
## the lobby turns into the wave arena and the sim moves him itself, the HTML game's player step (rolls, being
## thrown, the arena walls), with his own movement switched off. R (or the pad's Menu when it's over) restarts:
## a fresh lobby, keeping the character and the mode.
##
## Debug (?fight=... in the web build's address, or --fight=... after -- on the command line): run, protect,
## auto (aims at the nearest enemy and fires), fp (first person), wave=N, weapon=ID, god (can't be hurt), nuke.

static var me: Fight
static var saved_char: String = ""
static var saved_mode: String = "classic"
static var hotbar_order: Array[String] = []
static var saved_two: bool = false

var main: Node
var player: Player
var rig: CameraRig
var sim: FightSim
var f: FT.Fighter                       ## the local player's fight record
var p2: Player                          ## a second player on the same keyboard (P), or null
var f2: FT.Fighter
var view: FightView
var eview: EnemyView
var room: ArenaRoom
var hud: FightHud
var sfx: Sfx
var mode := "classic"
var debug: Dictionary = {}
var touch_seen := false
## Touch: the aim stick (-1..1 each) while a finger holds it, the FIRE button (first person), a roll tap.
var touch_aim := Vector2.ZERO
var touch_aim_on := false
var touch_fire := false
var touch_tap_spot = null              ## a world point tapped (launcher / potato), Vector2 or null
var touch_tap_id := 0
var goth_carry: Interactable

var _acc := 0.0
var _fire_mouse := false
var _wsel := ""
var _use := false
var _roll_tap := false
var _pad_aim := Vector2(0, 1)
var _mouse_moved_ms := 0
var _shake_node: Node
var _was_alive := true
var _hp_seen := 5.0
var _last_spin := false
var _log_t := 0.0
var _coins_synced: int = -2147483648
var _sec_state: Dictionary = {}        # player id -> [scale, hidden, tumble] in the bonus room's cinematics
var _sectors: Dictionary = {}          # player id -> the picture's last sector (kept over the sheet swap)
var _view_before := -1
var _secret_beat := ""
var _zoom_before := -1
## Online (milestone 4, scripts/net/): player 2's input from the network instead of the second keyboard/pad; the
## step itself (the guest loads the host's fight instead of stepping its own); and a hook for Enter, R and P
## (start, restart, add_player), which returns true when the network took it.
var net_input2: Callable
var net_step: Callable
var net_request: Callable

func _enter_tree() -> void:
	me = self

func _exit_tree() -> void:
	if me == self:
		me = null

func setup(m: Node) -> void:
	main = m
	player = m.get("player")
	rig = m.get("rig")

func _ready() -> void:
	name = "Fight"
	process_priority = 50                # after the Player's picture, before the camera follows him
	process_physics_priority = 50        # after the Player's own step on the same tick
	_read_debug()
	sim = FightSim.new()
	if saved_char != "" and player:
		player.char_id = saved_char
	f = sim.add_player(player, player.char_id if player else "juicy")
	f.shared_wallet = true
	if player:
		var hp := player.html_pos()
		f.x = hp.x
		f.y = hp.y
	sim.fill_lobby()
	mode = saved_mode
	if hotbar_order.is_empty():
		_load_hotbar()
	sfx = Sfx.new()
	add_child(sfx)
	room = ArenaRoom.new()
	room.sim = sim
	add_child(room)
	view = FightView.new()
	view.sim = sim
	view.fight = self
	add_child(view)
	eview = EnemyView.new()
	eview.sim = sim
	add_child(eview)
	var bview := BonusView.new()
	bview.sim = sim
	add_child(bview)
	for v in [room, view, eview, bview]:
		v.process_priority = 60          # after the sim's step this frame, before the camera (100)
	hud = FightHud.new()
	hud.fight = self
	add_child(hud)
	goth_carry = GothCarry.new()
	goth_carry.fight = self
	add_child(goth_carry)
	_shake_node = _ShakeNode.new()
	_shake_node.fight = self
	add_child(_shake_node)
	if main and main.get("hud"):
		main.hud.number_keys_pick = false
		var tc = main.hud.get("touch")
		if tc:
			tc.fire_enabled = true          # its FIRE button presses the "fire" action
	if debug.has("run") or debug.has("protect"):
		if debug.has("protect"):
			mode = "protect"
		call_deferred("start_run")
	if debug.has("fp") and rig:
		rig.call_deferred("set_mode", CameraRig.Mode.FIRST_PERSON)
	if debug.has("weapon"):
		call_deferred("_debug_weapon")
	if debug.has("gallery"):
		call_deferred("_gallery")
	if debug.has("secret"):
		call_deferred("_debug_secret")
	if saved_two or debug.has("p2"):
		call_deferred("add_player2")
	if debug.has("at") and player:
		var xy: PackedStringArray = String(debug["at"]).split(":")
		if xy.size() == 2:
			player.call_deferred("place", float(xy[0]), float(xy[1]))

func _read_debug() -> void:
	var q := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fight="):
			q = a.substr(8)
	if OS.has_feature("web"):
		var s = JavaScriptBridge.eval("window.location.search", true)
		if s is String:
			var i := String(s).find("fight=")
			if i >= 0:
				q = String(s).substr(i + 6).split("&")[0]
	for part in q.split(",", false):
		var kv := part.split("=")
		debug[kv[0]] = kv[1] if kv.size() > 1 else "1"

func _debug_weapon() -> void:
	var w: String = debug.get("weapon", "")
	if w == "spud" or w == "lob":
		f.ammo = maxi(f.ammo, 60)
	if w != "":
		sim.give_weapon(f, w)
	if w == "spud" or w == "fists" or w == "lob":
		f.weapon = w

## Debug: a staged moment with one of everything, the sim paused a beat in (for screenshots).
func _gallery() -> void:
	mode = "protect" if debug.get("gallery") == "protect" else "classic"
	start_run()
	sim.breather = 999.0
	f.x = 430
	f.y = 330
	sim.give_weapon(f, "launcher")
	f.tx = 560
	f.ty = 250
	f.aim_on = true
	f.muzzle = 0.1
	f.mdx = 1
	f.mdy = -0.5
	f.adx = 1
	f.ady = -0.5
	f.firing = true
	for et in 4:
		var e := sim.new_enemy(et, 200 + et * 70, 200 + (et % 2) * 60)
		e.spawn = 0.0
		e.vx = 30
		e.vy = 20
		e.odo = et * 7.0
	var b := sim.new_enemy(3, 470, 400)
	b.spawn = 0.0
	b.st = EnemySim.WINDUP
	b.st_t = 0.2
	b.sdx = -0.5
	b.sdy = -0.8
	var sp := sim.new_enemy(1, 640, 420)
	sp.spawn = 0.2
	for et in 4:
		var dead := sim.new_enemy(et, 150 + et * 50, 420)
		sim.kill_enemy(dead, 1, 0.3, et == 2, 0, 1.0, true)
	var r := FT.Rocket.new()
	r.sx = 450
	r.sy = 330
	r.h0 = 30
	r.tx = 700
	r.ty = 300
	r.t = 0.35
	r.big_h = 90
	r.id = 99
	sim.rockets.append(r)
	var bl := FT.Blast.new()
	bl.x = 700
	bl.y = 420
	bl.t = 0.12
	sim.blasts.append(bl)
	var h := FT.Husk.new()
	h.whole = true
	h.x = 330
	h.y = 300
	h.dz = 40
	sim.husks.append(h)
	for i in 5:
		sim._coin(520 + i * 14, 470, 0, 0, 6, 0)
	sim.burst_shrapnel(600, 200)
	for sh: FT.Shard in sim.shards:
		sh.x += sh.vx * 0.15
		sh.y += sh.vy * 0.15
	sim.floater(430, 300, "$3", Color("#e0473f"))
	sim.janitor.phase = "gripe"
	sim.janitor.x = 520
	sim.janitor.y = 160
	sim.sign = "floor"
	sim.slot.broken = false
	if debug.get("gallery") == "slot":
		f.x = sim.slot.x
		f.y = sim.slot.y + 30.0
		f.spin = 0.5
		sim.slot.busy = 0
		sim.slot.prize = 4
		sim.slot.decoy = [2, 5]
		sim.janitor.phase = "done"
	set_meta("frozen", true)

## Debug (the HTML's "secret preview"): a run at wave 1 with Gary swinging at the live machine, straight in.
func _debug_secret() -> void:
	start_run()
	sim.wave = 1
	sim.breather = 999.0
	sim.slot.broken = false
	sim.janitor.phase = "swing"
	BonusRoom.begin(sim)
	if debug.get("secret") == "room":
		sim.secret.t = BonusRoom.INTRO

func _load_hotbar() -> void:
	hotbar_order.assign(WeaponDefs.ORDER)
	var cf := ConfigFile.new()
	if cf.load("user://smashed.cfg") == OK:
		var o = cf.get_value("hotbar", "order", [])
		if o is Array and o.size() == 6:
			var ok := true
			for id in WeaponDefs.ORDER:
				if not o.has(id):
					ok = false
			if ok:
				hotbar_order.assign(o)

## Hides a lobby part for the run: its drawn nodes go invisible and it stops processing.
func _hide_for_run(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is Node3D or n is CanvasItem:
		n.visible = false
		return
	for c in n.get_children():
		_hide_for_run(c)

func save_hotbar() -> void:
	var cf := ConfigFile.new()
	cf.load("user://smashed.cfg")
	cf.set_value("hotbar", "order", hotbar_order)
	cf.save("user://smashed.cfg")

# ---------------------------------------------------------------- the run

## forced: the network says so (the host started); otherwise online, the guest asks the host instead.
func start_run(forced: bool = false) -> void:
	if sim.started or player == null:
		return
	if not forced and net_request.is_valid() and net_request.call("start"):
		return
	_sync_from_player()
	saved_mode = mode
	sim.start_run(mode)
	room.visible = true
	if main:
		for n in ["world", "trampoline", "gothica"]:
			var node = main.get(n)
			if node is Node3D:
				node.visible = false
				if n != "world":
					node.process_mode = Node.PROCESS_MODE_DISABLED
				if node is CollisionObject3D:
					node.collision_layer = 0
	# parts that live in the lobby (lobby life, the arcade) hide for the run
	for n in get_tree().get_nodes_in_group("lobby_only"):
		_hide_for_run(n)
	# the lobby's E things aren't in the arena
	for n in get_tree().get_nodes_in_group("interactable"):
		if n != goth_carry:
			n.remove_from_group("interactable")
	if rig:
		rig.bounds = Rect2(0, 0, FightSim.AW, FightSim.AH)
		rig.in_run = true
	player.on_tramp = false
	player.dz = 0.0
	player.frozen = false
	player.controls_enabled = false
	player.collision_mask = 0
	player.halt()
	_place_player()
	player.reset_physics_interpolation()
	if rig:
		rig.snap()

## P: a second player on the same keyboard (addPlayer, L6065): arrows move, Space fires the way he faces, Ctrl rolls,
## or the second pad. He gets the lobby's cash but not its blasters; mid-run he joins with nothing.
func add_player2() -> void:
	if p2 != null or main == null or BonusRoom.active(sim):
		return
	p2 = Player.new()
	p2.name = "Player2"
	main.add_child(p2)
	p2.char_id = "juicy" if player and player.char_id == "tyson2" else "tyson2"
	p2.controls_enabled = false
	p2.face_mouse = false
	p2.place(480, 260)
	f2 = sim.add_player(p2, p2.char_id)
	f2.driven = true
	f2.x = 480
	f2.y = 260
	f2.coins = 0 if sim.started else int(maxf(sim.tv("lobbyCash", 40), sim.tv("testCash", 2500)))
	if sim.started:
		p2.collision_mask = 0
	saved_two = true

## forced: the network says so (the host restarted); otherwise online, the guest asks the host instead.
func restart(forced: bool = false) -> void:
	if not forced and net_request.is_valid() and net_request.call("restart"):
		return
	if player:
		saved_char = player.char_id
	saved_mode = mode
	Sfx.stop_whistle()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for a in ["move_left", "move_right", "move_up", "move_down", "roll"]:
		Input.action_release(a)
	get_tree().call_deferred("reload_current_scene")

func step_mode(d: int) -> void:
	if sim.started:
		return
	var modes := ["classic", "protect"]
	mode = modes[posmod(modes.find(mode) + d, modes.size())]
	saved_mode = mode

static func mode_name(m: String) -> String:
	return "Protect Gothica" if m == "protect" else "Classic"

## A slot machine prize for a player node (the lobby's machine can call this): blasters, shotgun, health, speed,
## clear, cash, magnet, bust.
func award(node: Node, key: String) -> void:
	for p: FT.Fighter in sim.players:
		if p.node == node:
			for i in FightSim.PRIZES.size():
				if FightSim.PRIZES[i].key == key:
					sim.award(p, i)

# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		touch_seen = true
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_moved_ms = Time.get_ticks_msec()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if sim.over:
			# a click on the game-over words restarts (|x - 430| < 220, |y - 260| < 60 on the HTML canvas)
			var k := get_viewport().get_visible_rect().size.y / 520.0
			var c := get_viewport().get_visible_rect().size / 2.0
			if absf(event.position.x - c.x) < 220.0 * k and absf(event.position.y - 260.0 * k) < 60.0 * k:
				restart()
			return
		_fire_mouse = true
	if event is InputEventAction and event.action == "fire":
		_fire_mouse = event.pressed          # the touch layer's FIRE button
		touch_fire = event.pressed and is_fp()
	if event.is_action_pressed("start_run") and not event.is_echo():
		if sim.over:
			restart()
		elif not sim.started:
			start_run()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("add_player") and not event.is_echo():
		if not (net_request.is_valid() and net_request.call("add_player")):
			add_player2()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart") and not event.is_echo():
		restart()
		get_viewport().set_input_as_handled()
		return
	for i in 6:
		if event.is_action_pressed("weapon_%d" % (i + 1)) and not event.is_echo():
			select_slot(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("weapon_next") and not event.is_echo():
		cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev") and not event.is_echo():
		cycle_weapon(-1)
	if sim.started and event.is_action_pressed("interact") and not event.is_echo():
		# (the Player's own E is off while the run moves him)
		if player and player.focus:
			player.use()
		get_viewport().set_input_as_handled()
	if sim.started and event.is_action_pressed("roll") and not event.is_echo():
		_roll_tap = true
	if debug.has("keys"):
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_G:
					sim.give_weapon(f, "shotgun")
				KEY_N:
					if sim.started and sim.nuke == null:
						sim.drop_nuke()
				KEY_M:
					sim.test_magnet()
				KEY_J:
					if sim.started:
						sim.slot.broken = true
						sim.sign = "stand"
						sim.janitor = FT.Janitor.new()
						sim.wave = maxi(sim.wave, 1)
						sim.breather = 5.2

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_fire_mouse = false

## Keys 1-6 and the bar: pick that slot's weapon if he has it (selectSlot), else the slot flashes red.
func select_slot(i: int) -> void:
	var id: String = hotbar_order[i]
	if WeaponDefs.has_weapon(f, id):
		_wsel = id
	elif hud:
		hud.flash_slot(i)

## The pad's LB / Y: the previous / next weapon he has, in bar order.
func cycle_weapon(d: int) -> void:
	var i := hotbar_order.find(f.weapon)
	for k in range(1, 7):
		var j := posmod(i + d * k, 6)
		if WeaponDefs.has_weapon(f, hotbar_order[j]):
			_wsel = hotbar_order[j]
			return

func request_use() -> void:
	_use = true

func pad_rt() -> bool:
	var pads := Input.get_connected_joypads()
	return not pads.is_empty() and Input.get_joy_axis(pads[0], JOY_AXIS_TRIGGER_RIGHT) > 0.5

func is_fp(id: int = 0) -> bool:
	return id == 0 and rig != null and rig.mode == CameraRig.Mode.FIRST_PERSON

func _steer() -> Vector2:
	var mx := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var my := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	if not is_fp() and p2 == null and Player.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() < 0.01:
		# top-down the look actions (the arrows) move him too, as milestone 1's Player does
		mx += Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
		my += Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	var m := Vector2(clampf(mx, -1, 1), clampf(my, -1, 1))
	if is_fp():
		var fw := Vector2(cos(player.look_ang), sin(player.look_ang))
		var rt := Vector2(-fw.y, fw.x)
		m = fw * -m.y + rt * m.x
	return m

func _mouse_ground():
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return null
	var k := -o.y / d.y
	if k < 0.0:
		return null
	return GameData.from_3d(o + d * k)

func screen_to_ground(sp: Vector2):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return null
	var k := -o.y / d.y
	return GameData.from_3d(o + d * k) if k > 0.0 else null

## localInput0 / shroomInput: the local player's input for this frame.
func _build_input() -> FT.Inp:
	var inp := FT.Inp.new()
	inp.tc = touch_seen
	if sim.over or player == null:
		return inp
	var m := _steer()
	inp.mx = m.x
	inp.my = m.y
	inp.roll = Input.is_action_pressed("roll") or _roll_tap
	inp.wsel = _wsel
	inp.use = _use
	var rt := pad_rt()
	if is_fp():
		var fw := Vector2(cos(player.look_ang), sin(player.look_ang))
		var reach := maxf(60.0, minf(sim.tv("lobFar", 430), sim.tv("lobDefault", 220) * (1.0 - 1.4 * player.look_y)))
		inp.ax = fw.x * reach
		inp.ay = fw.y * reach
		inp.shoot = touch_fire or (not touch_aim_on and ((_fire_mouse and (rig.mouse_captured() or touch_seen)) or rt))
		return inp
	var stick := Player.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.22)
	if touch_tap_spot != null and f.weapon == "launcher":
		inp.tap = touch_tap_id
		inp.tx = touch_tap_spot.x
		inp.ty = touch_tap_spot.y
	if touch_tap_spot != null and f.weapon == "lob":
		inp.lt = true
		inp.lx = touch_tap_spot.x
		inp.ly = touch_tap_spot.y
		inp.shoot = true
	if player.aim_override.length() > 0.0:
		touch_aim_on = true
		touch_aim = player.aim_override
	elif touch_aim_on and hud and not hud.own_sticks:
		touch_aim_on = false
	if touch_aim_on:
		inp.shoot = true
		inp.st = true
		inp.ax = touch_aim.x if touch_aim.length() >= 0.06 else 0.0
		inp.ay = touch_aim.y if touch_aim.length() >= 0.06 else 0.0
	elif stick.length() > 0.0:
		inp.st = true
		inp.ax = stick.x
		inp.ay = stick.y
		inp.shoot = rt
		_pad_aim = stick
	elif rt and Time.get_ticks_msec() - _mouse_moved_ms > 1500:
		inp.shoot = true
		inp.st = true
		inp.ax = _pad_aim.x
		inp.ay = _pad_aim.y
	else:
		var at = _mouse_ground()
		if at != null:
			inp.ax = at.x - f.x
			inp.ay = at.y - f.y
		inp.shoot = inp.shoot or _fire_mouse or rt
	return inp

## localInput1: arrows, Space, Ctrl; or the second pad (left stick, right stick aims, RT fires, B/RB/LT roll).
func _build_input2() -> FT.Inp:
	if net_input2.is_valid():
		return net_input2.call()
	var inp := FT.Inp.new()
	if sim.over:
		return inp
	var mx := 0.0
	var my := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT): mx -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): mx += 1.0
	if Input.is_physical_key_pressed(KEY_UP): my -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): my += 1.0
	inp.shoot = Input.is_physical_key_pressed(KEY_SPACE)
	inp.roll = Input.is_physical_key_pressed(KEY_KP_0) or Input.is_physical_key_pressed(KEY_SLASH) \
		or (Input.is_physical_key_pressed(KEY_CTRL) and not OS.has_feature("web"))
	var pads := Input.get_connected_joypads()
	if pads.size() > 1:
		var d: int = pads[1]
		var ls := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if ls.length() > 0.2:
			mx = ls.x
			my = ls.y
		var rs := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.22:
			inp.st = true
			inp.ax = rs.x
			inp.ay = rs.y
		var rt := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		inp.shoot = inp.shoot or rt
		inp.roll = inp.roll or Input.is_joy_button_pressed(d, JOY_BUTTON_B) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) \
			or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.5
	inp.mx = clampf(mx, -1, 1)
	inp.my = clampf(my, -1, 1)
	return inp

# Player 2's body in the lobby: slid along the house's walls with the sim's velocity (like the Player's own step).
func _move_p2_lobby(dt: float) -> void:
	p2.vel = Vector2.ZERO
	p2.collision_mask = 1
	p2.velocity = Vector3(f2.vx, 0.0, f2.vy) * GameData.UNIT
	p2.move_and_slide()
	for i in p2.get_slide_collision_count():
		var n3 := p2.get_slide_collision(i).get_normal()
		var n := Vector2(n3.x, n3.z)
		if n.length() < 0.2:
			continue
		n = n.normalized()
		var into := Vector2(f2.vx, f2.vy).dot(n)
		if into < 0.0:
			f2.vx -= n.x * into
			f2.vy -= n.y * into
	p2.velocity = Vector3.ZERO
	var hp := p2.html_pos()
	f2.x = hp.x
	f2.y = hp.y

# ---------------------------------------------------------------- the frame

func _sync_from_player() -> void:
	if player == null:
		return
	var hp := player.html_pos()
	f.x = hp.x
	f.y = hp.y
	f.vx = player.vel.x
	f.vy = player.vel.y
	f.roll = player.roll
	f.odo = player.odo
	f.ch = player.char_id

# One tick of the shared 120 Hz physics clock = one step of the fight (the HTML game's FIXED_DT).
func _physics_process(delta: float) -> void:
	if player == null:
		return
	var dt := minf(delta, 0.1)
	var lobby := not sim.started
	if not lobby and is_fp() and not sim.over:
		# first-person look in a run (the rig turns only while the Player's own controls are on): the look actions
		var lx := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
		var ly := Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
		if p2 != null and not net_input2.is_valid() and Player.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() < 0.01:
			lx = 0.0                     # the arrows are player 2's
			ly = 0.0
		var turn := 2.8 if Player.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() > 0.01 else 2.4
		player.look_ang = wrapf(player.look_ang + lx * turn * dt, -PI, PI)
		player.look_y = clampf(player.look_y + ly * 1.6 * dt, -0.6, 0.6)
	if lobby:
		_sync_from_player()
	f.ch = player.char_id
	if p2:
		f2.ch = p2.char_id
	var vel0 := Vector2(f.vx, f.vy)
	var wallet := Wallet.get_wallet(get_tree())
	if wallet:
		if _coins_synced != -2147483648 and f.coins != _coins_synced:
			wallet.add_cash(f.coins - _coins_synced, "fight")     # changed between ticks (a prize, a test)
		f.coins = wallet.cash
	var coins0 := f.coins
	if not has_meta("frozen"):
		var inp := _build_input()
		if debug.has("god"):
			f.iframe = maxf(f.iframe, 0.1)
		if debug.has("auto"):
			_autopilot(inp)
		var inputs := [inp, _build_input2()] if f2 else [inp]
		if net_step.is_valid():
			net_step.call(inputs, dt)
		else:
			sim.step(inputs, dt)
		_wsel = ""
		_use = false
		_roll_tap = false
		if touch_tap_spot != null and f.weapon != "lob":
			touch_tap_spot = null
	if wallet:
		if f.coins != coins0:
			wallet.add_cash(f.coins - coins0, "fight")
		_coins_synced = f.coins
	if p2 and lobby and f2.alive and f2.driven:
		_move_p2_lobby(dt)
	if lobby:
		if Vector2(f.vx, f.vy) != vel0:
			player.vel += Vector2(f.vx, f.vy) - vel0
		if not f.alive:
			player.controls_enabled = false
	else:
		_place_player()
		if p2:
			p2.collision_mask = 0
			p2.vel = Vector2.ZERO
			p2.global_position = GameData.world_to_3d(f2.x, f2.y, 0.0)
			p2.facing = sim.facing_vec(f2)
			if sim.secret and sim.secret.phase != "done":
				_sec_state[1] = _secret_place(sim.secret, p2, f2)
	goth_carry.update_pos()
	if debug.has("wave") and sim.started and sim.wave == 0 and sim.breather > 0.0:
		sim.wave = int(debug["wave"]) - 1
		debug.erase("wave")

func _process(delta: float) -> void:
	if player == null:
		return
	_drain()
	if sim.over and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE      # let the pointer go for the game-over screen
	_update_sprite()
	if p2:
		_update_sprite_of(p2, f2)
	_secret_frame()
	if debug.has("log"):
		_log_t += delta
		if _log_t >= 1.0:
			_log_t = 0.0
			print("FIGHT started=%s wave=%d enemies=%d hp=%.0f alive=%s kills=%d coins=%d weapon=%s ammo=%d over=%s x=%.0f y=%.0f shots=%d fps=%d" % [
				sim.started, sim.wave, sim.enemies.size(), f.hp, f.alive, f.kills, f.coins, f.weapon, f.ammo, sim.over, f.x, f.y, f.shots, Engine.get_frames_per_second()])

func _place_player() -> void:
	player.vel = Vector2.ZERO
	player.velocity = Vector3.ZERO
	player.global_position = GameData.world_to_3d(f.x, f.y, 0.0)
	_sec_state.clear()
	var sec := sim.secret
	if sec and sec.phase != "done":
		_sec_state[0] = _secret_place(sec, player, f)
	player.facing = sim.facing_vec(f)
	player.moving = f.moving
	player.odo = f.odo
	player.roll = f.roll

func _drain() -> void:
	for s in sim.sounds:
		var name: String = s
		if name == "whistle":
			Sfx.whistle(sim.tv("nukeFall", 1.9))
		elif name == "stop_whistle":
			Sfx.stop_whistle()
		elif name.begins_with("throw_whole:"):
			Sfx.play("throw_whole", float(name.get_slice(":", 1)))
		else:
			Sfx.play(name)
	sim.sounds.clear()
	for e in sim.events:
		match int(e[0]):
			FightSim.FX_HIT: Sfx.play("hit")
			FightSim.FX_KILL: Sfx.play("kill")
			FightSim.FX_HURT: Sfx.play("hurt")
			FightSim.FX_DOWN: Sfx.play("down")
			FightSim.FX_BOOM: Sfx.play("kill_big")
			FightSim.FX_LAUNCH: Sfx.play("rocket")
			FightSim.FX_BLAST: Sfx.play("blast")
			100:
				if is_fp():
					Sfx.play("windup")
	sim.events.clear()
	for b in sim.banners:
		hud.show_banner(b[0], b[1])
	sim.banners.clear()
	# the pad rumbles when you're hurt (3.9)
	if f.hp < _hp_seen and Input.get_connected_joypads().size() > 0:
		var last := f.hp <= 0.0
		Input.start_joy_vibration(Input.get_connected_joypads()[0], 0.35, 1.0 if last else 0.6, 0.42 if last else 0.14)
	_hp_seen = f.hp

## The picture: the weapon's sheet, facing the shot while firing, the weapon actions (reload, pickup, throw,
## wind-up), tumbling when thrown, blinking in iframes, gone when down.
func _update_sprite() -> void:
	_update_sprite_of(player, f)

func _update_sprite_of(pl: Player, f: FT.Fighter) -> void:
	var spr: CharSprite = pl.sprite
	if spr == null:
		return
	var fp := is_fp(f.id)
	if not f.alive:
		spr.visible = false
		return
	var blink := f.iframe > 0.0 and int(floor(f.iframe * 20.0)) % 2 == 0
	var ss: Array = _sec_state.get(f.id, [1.0, false, false])
	spr.scale = Vector3.ONE * float(ss[0])
	if ss[1]:
		spr.visible = false
		return
	var carried := sim.goth != null and sim.goth.carrier == f.id
	spr.visible = not fp and not blink
	# lobby life shows a picture of its own for him (lying in bed, lifting, sitting...): leave his sprite hidden
	var ll := LobbyLife.current
	if not sim.started and ll and (ll.pose_of(pl) != null or (ll.busy.has(pl) and bool(ll.busy[pl].hides_sprite(pl)))):
		spr.visible = false
		return
	if fp:
		return
	var skin := WeaponDefs.skin_for(pl.char_id, f.weapon)
	if not CharFrames.has(skin, "front_a") and not CharFrames.has(skin, "front_run"):
		skin = pl.char_id
	spr.char_id = skin
	var fv := sim.facing_vec(f)
	spr.facing = fv
	var own := sim.started or f.driven
	spr.moving = f.moving if own else pl.moving
	spr.odo = f.odo if own else pl.odo
	var roll := f.roll if own else pl.roll
	if f.launch > 0.0 or ss[2]:
		spr.action = "tumble"
		spr.odo = Time.get_ticks_msec() / 1000.0 * 120.0
	elif roll > 0.0:
		spr.action = "roll"
		spr.roll_t = clampf(1.0 - roll / maxf(0.05, sim.tv("rollTime", 0.42)), 0.0, 0.9999)
	else:
		spr.action = ""
	var cam := get_viewport().get_camera_3d()
	if _sectors.has(f.id):
		spr._sector = _sectors[f.id]       # (the Player sets its own sheet back each frame, which forgets it)
	spr.update_view(cam)
	_sectors[f.id] = spr._sector
	if f.launch > 0.0 or roll > 0.0:
		return
	# weapon actions (drawJared's checks, weapons 11.1)
	var vf := spr.facing_for_view(cam)
	var sideways := absf(vf.x) > absf(vf.y) * 0.9
	var key := ""
	var idx := 0
	var flip := false
	if f.charging and CharFrames.has(skin, "throw_side"):
		key = "throw_side" if sideways else "throw_front"
		flip = sideways and vf.x < 0.0
	elif f.throw > 0.0 and CharFrames.has(skin, "throw_side"):
		key = "throw_side" if sideways else "throw_front"
		flip = sideways and vf.x < 0.0
		var nn := CharFrames.frame_count(skin, key)
		idx = mini(nn - 1, int(floor((1.0 - f.throw / sim.tv("spudThrow", 0.5)) * nn)))
	elif f.pickup > 0.0:
		var ps := skin if CharFrames.has(skin, "pickup") else WeaponDefs.skin_for(pl.char_id, "spud")
		if CharFrames.has(ps, "pickup"):
			skin = ps
			key = "pickup"
			idx = mini(CharFrames.frame_count(ps, "pickup") - 1, int(floor((1.0 - f.pickup / sim.tv("spudPickup", 0.36)) * 4.0)))
	elif f.reload > 0.0 and CharFrames.has(skin, "reload"):
		key = "reload_side" if sideways and CharFrames.has(skin, "reload_side") else "reload"
		flip = key == "reload_side" and vf.x < 0.0
		var nn2 := CharFrames.frame_count(skin, key)
		idx = mini(nn2 - 1, int(floor((1.0 - f.reload / sim.tv("spudReload", 0.42)) * nn2)))
	if key != "":
		spr.char_id = skin
		spr._show(skin, key, idx, flip, 0.0)
		spr.current_key = key
	if carried:
		spr.visible = not blink

# The bonus room's cinematics (gore_loot 14.5): dragged feet first into the cabinet and shrinking into it, then
# tumbling in from the bottom of the room, and back out of the machine at the end.
func _secret_place(sec: FT.Secret, pl: Player, ff: FT.Fighter) -> Array:
	var t := sec.t
	var side := -1.0 if ff.id == 0 else 1.0
	var hx := sim.slot.x
	var hy := sim.slot.y + 4.0
	var scale := 1.0
	var hidden := false
	var tumble := false
	match sec.phase:
		"intro":
			var o: Vector2 = sec.origins[ff.id] if ff.id < sec.origins.size() else Vector2(ff.x, ff.y)
			if t < 1.5:
				pl.global_position = GameData.world_to_3d(o.x, o.y, 0.0)
			elif t < 4.15:
				var k := minf(1.0, (t - 1.5) / 2.1)
				k = k * k * (3.0 - 2.0 * k)
				var at := o.lerp(Vector2(hx + side * 11.0, hy + 12.0), k)
				at.x += sin(t * 30.0) * 2.0 * k
				pl.global_position = GameData.world_to_3d(at.x, at.y, 0.0)
				scale = 1.0 - 0.18 * k
				tumble = k > 0.3
			elif t < 4.43:
				var k2 := (t - 4.15) / 0.28
				pl.global_position = GameData.world_to_3d(hx + side * 11.0, hy + 12.0, 0.0)
				scale = 0.82 * (1.0 - k2)
				tumble = true
			else:
				hidden = true
		"landing", "return":
			var dur := 0.85 if sec.phase == "landing" else 1.15
			var k3 := minf(1.0, t / dur)
			k3 = 1.0 - (1.0 - k3) * (1.0 - k3)
			var from := Vector2(430, 505) if sec.phase == "landing" else Vector2(hx, hy)
			var at2 := from.lerp(Vector2(ff.x, ff.y), k3)
			pl.global_position = GameData.world_to_3d(at2.x, at2.y, 45.0 * 4.0 * k3 * (1.0 - k3))
			tumble = k3 < 1.0
	return [scale, hidden, tumble]

func _secret_frame() -> void:
	var sec := sim.secret
	var beat := ""
	if sec and sec.phase != "done":
		if sec.phase == "intro":
			beat = "s_hammer" if sec.t < 0.5 else ("s_reels" if sec.t < 1.5 else ("s_suction" if sec.t < 4.15 else ("s_pop" if sec.t < 4.6 else "quiet")))
		else:
			beat = sec.phase
	if beat != _secret_beat:
		_secret_beat = beat
		match beat:
			"s_hammer", "s_reels", "s_suction", "s_pop":
				Sfx.play(beat)
			"landing":
				Sfx.play("s_landing")
			"payout":
				Sfx.play("s_payout")
	var on := sec != null and sec.phase != "done"
	if rig:
		if on and _view_before < 0:
			_view_before = rig.mode
			rig.set_mode(CameraRig.Mode.TOP_DOWN)
		elif not on and _view_before >= 0:
			rig.set_mode(_view_before)
			_view_before = -1
	var mh = main.get("hud") if main else null
	if mh and mh.get("_picker") is Control:
		mh._picker.visible = not on
	# the camera shows the whole room inside the machine
	var inside := sec != null and sec.room
	if rig:
		if inside and _zoom_before < 0:
			_zoom_before = rig.zoom_level
			rig.set_zoom(0)
		elif not inside and _zoom_before >= 0:
			rig.set_zoom(_zoom_before)
			_zoom_before = -1

## Where a player's gun is in 3D: the barrel map's point for the frame his picture shows (weapons 18.4), or near
## the camera in first person. INF if unknown.
func visual_muzzle(owner: int) -> Vector3:
	var pl: Player = player if owner == 0 else p2
	var ff: FT.Fighter = f if owner == 0 else f2
	if pl == null or ff == null:
		return Vector3.INF
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	if is_fp(owner):
		var b := cam.global_transform.basis
		var side := -1.0 if ff.last_gun == 0 else 1.0
		return cam.global_position - b.z * 0.5 - b.y * 0.25 + b.x * 0.18 * side
	var spr: CharSprite = pl.sprite
	var key := WeaponDefs.barrel_key(pl.char_id, ff.weapon)
	var o := WeaponDefs.barrel(key, spr.current_sector if spr else 2, ff.last_gun)
	return pl.get_global_transform_interpolated().origin + view.cam_right * (o.x * GameData.UNIT) + view.stand_up * ((12.6 - o.y) * GameData.UNIT) + view.to_cam * 0.05

## First person: your own shots aren't drawn until they're 70 out (they'd seem to come from the middle of the
## screen; the tracers cover the gap).
func hide_own_shot(b: FT.Bullet) -> bool:
	return is_fp() and b.owner == 0 and b.travelled < 70.0

func _autopilot(inp: FT.Inp) -> void:
	var best: FT.Enemy = null
	var bd := INF
	for e: FT.Enemy in sim.enemies:
		if e.spawn > 0.0:
			continue
		var d := Vector2(e.x - f.x, e.y - f.y).length()
		if d < bd:
			bd = d
			best = e
	if best == null and sim.lobby():
		for d: FT.Dummy in sim.dummies:
			if d.down <= 0.0:
				inp.ax = d.x - f.x
				inp.ay = d.y - 14.0 - f.y
				inp.shoot = true
				return
	if best:
		inp.ax = best.x - f.x
		inp.ay = best.y - f.y
		if is_fp():
			player.look_ang = atan2(inp.ay, inp.ax)
			player.look_y = 0.12
		inp.shoot = true
		inp.st = false
		# keep some distance
		if bd < 120.0:
			inp.mx = -inp.ax / bd
			inp.my = -inp.ay / bd
		else:
			inp.mx = 0.0
			inp.my = 0.0
	else:
		inp.shoot = false

## Screen shake on the camera after it has followed him (gore_loot 10.2; first person: a small turn).
class _ShakeNode extends Node:
	var fight: Fight
	func _ready() -> void:
		process_priority = 200
	func _process(_d: float) -> void:
		if fight == null or fight.rig == null:
			return
		var amt := minf(40.0, fight.sim.shake)
		if amt <= 0.0:
			return
		var cam := fight.rig.camera()
		if cam == null:
			return
		if fight.is_fp():
			cam.rotate_object_local(Vector3.FORWARD, deg_to_rad((randf() - 0.5) * amt * 0.15))
			cam.rotate_object_local(Vector3.RIGHT, deg_to_rad((randf() - 0.5) * amt * 0.08))
		else:
			var z := fight.rig.zoom_wanted()
			var b := cam.global_transform.basis
			cam.global_position += (b.x * (randf() - 0.5) + b.y * (randf() - 0.5)) * amt / z * GameData.UNIT
