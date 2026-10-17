extends Node
## The arcade's test bed: the real game (scenes/main.tscn) with Arcade.install called on it, the way main.gd
## will. Run as the main scene of a test copy (scenes/arcade/arcade_test.tscn).
##
## User arguments (after --), or the web build's address (?open=miner&at=1 ...):
##   --logic          run the logic tests headless, print "ARCADE TEST ..." lines and quit (exit code 1 on a fail)
##   --open=<game>    walk up to the cabinet and open: miner, bricks (the Mega Drive menu), snake or bricksgame
##   --play           and start the game, steering about a bit (for screenshots of a game going)
##   --fp             first person
##   --at             stand at the miner cabinet (for the E prompt)
##   --touch          pretend the last device was a finger (the on-screen buttons)

var main: Node
var arcade: Arcade
var _args: PackedStringArray
var _fails := 0
var _t := 0.0
var _play := false

func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for part in q.substr(1).split("&"):
				_args.append("--" + part)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	arcade = Arcade.install(main)
	await get_tree().process_frame
	if _arg("logic") != null:
		await _logic()
		print("ARCADE TEST done: %d failed" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	if _arg("fp") != null:
		main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
		main.player.look_ang = -PI / 2.0
	if _arg("at") != null or _arg("open") != null:
		var c: Dictionary = GameData.data.CABINETS[0]
		main.player.place(float(c.x), float(_arg("at")) if _arg("at") != null and _arg("at") != "" else 140.0)
		main.player.facing = Vector2(0, -1)
	var o = _arg("open")
	if o != null:
		await get_tree().create_timer(0.5).timeout
		match String(o):
			"bricks":
				arcade.use_cabinet(arcade.cabinets[1])
			"snake", "bricksgame":
				arcade.overlay.open(GameData.data.CABINETS[1], "snake" if o == "snake" else "bricks")
			_:
				arcade.use_cabinet(arcade.cabinets[0])
		if _arg("touch") != null:
			arcade.overlay.device = "touch"
		_play = _arg("play") != null
	print("ARCADE ready")

func _arg(name: String):
	for a in _args:
		if a == "--" + name:
			return ""
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return null

var _state_t := 0.0

func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	if _arg("astate") != null and _state_t > 0.5:
		_state_t = 0.0
		var g := arcade.overlay.game
		print("ASTATE open=%s md=%s game=%s live=%s over=%s score=%d device=%s label=%s ctl=%s drags=%d next=%s" % [arcade.overlay.is_open(), arcade.md.is_open(),
			arcade.overlay.game_id if g else "", g.live if g else false, g.over if g else false, g.score if g else 0,
			arcade.overlay.device, main.player.focus_label, main.player.controls_enabled, arcade.overlay.touch_events, str(g.next) if g is SnakeGame else ""])
	if _play and arcade.overlay.is_open():
		var g := arcade.overlay.game
		if not g.live:
			g.live = true
		if g is SandMinerGame:
			# walk right, dig down in front of him now and then
			var st := {"x": 1.0 if fmod(_t, 4.0) < 1.2 else 0.0, "y": 0.0, "held": {}, "pressed": {},
				"ptr": Vector2(250, 200), "ptr_in": true, "ptr_down": fmod(_t, 4.0) > 1.4, "aim": Vector2.ZERO}
			g.step(delta, st)

func check(name: String, ok: bool, info: String = "") -> void:
	if ok:
		print("ARCADE TEST ok   ", name, ("  (" + info + ")") if info != "" else "")
	else:
		_fails += 1
		print("ARCADE TEST FAIL ", name, ("  (" + info + ")") if info != "" else "")

func _logic() -> void:
	arcade.sfx.enabled = false
	# ---- phone stick shaping (touch_controls.gd)
	check("stick: inside the dead zone is nothing", TouchControls.shape(Vector2(0.2, 0), 0.22, 1.5) == Vector2.ZERO)
	check("stick: a full push is full", absf(TouchControls.shape(Vector2(1, 0), 0.22, 1.5).x - 1.0) < 0.001)
	check("stick: a half push walks slowly (curve)", TouchControls.shape(Vector2(0.5, 0), 0.22, 1.5).x < 0.3)
	# ---- Snake
	var s := SnakeGame.new()
	s.live = true
	var head := s.body[0]
	s.food = Vector2i(head.x + 1, head.y)
	s.step(0.131, {"x": 0.0, "y": 0.0})
	check("snake eats the potato in front", s.score == 1 and s.body.size() == 4, "score %d len %d" % [s.score, s.body.size()])
	check("snake speeds up 3%", absf(s.speed - 0.13 * 0.97) < 1e-6)
	s.step(0.01, {"x": -1.0, "y": 0.0})
	check("snake can't turn back on itself", s.next == Vector2i(1, 0))
	s.step(0.01, {"x": 0.0, "y": 1.0})
	check("snake turns", s.next == Vector2i(0, 1))
	var n := 0
	while not s.over and n < 200:
		s.step(0.2, {"x": 0.0, "y": 0.0})
		n += 1
	check("snake dies at the wall", s.over and s.wait > 0.0)
	# ---- Bricks
	var b := BricksGame.new()
	b.live = true
	check("bricks: a wall of 40", b.bricks.size() == 40)
	b.step(0.016, {"x": 0.0, "y": 0.0, "fire": true})
	check("bricks: fire launches", not b.stuck and b.vy < 0.0)
	n = 0
	while b.score == 0 and n < 600:
		b.step(0.016, {"x": 0.0, "y": 0.0, "paddle": b.bx})
		n += 1
	check("bricks: the ball breaks bricks", b.score > 0, "score %d after %d steps" % [b.score, n])
	var lives := b.lives
	b.stuck = false
	b.by = 335.0
	b.vy = 100.0
	b.step(0.016, {"x": 0.0, "y": 0.0})
	check("bricks: a missed ball costs a life", b.lives == lives - 1 and b.stuck)
	b.lives = 1
	b.stuck = false
	b.by = 335.0
	b.step(0.016, {"x": 0.0, "y": 0.0})
	check("bricks: out of lives is game over", b.over)
	var b2 := BricksGame.new()
	b2.step(0.016, {"paddle": 400.0})
	check("bricks: the mouse or a finger puts the paddle there", b2.px == 400.0 and b2.bx == 400.0)
	b2.level = 3
	b2.wall()
	check("bricks: level 3 has two rows of two-hit bricks", b2.bricks[15].hp == 2 and b2.bricks[16].hp == 1)
	# ---- Sand Miner
	var t0 := Time.get_ticks_usec()
	var m := SandMinerGame.new(1234)
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check("miner: the world's made", m.grid.size() == 384 * 256, "%.0f ms" % gen_ms)
	m.live = true
	t0 = Time.get_ticks_usec()
	for i in 120:
		m.tick()
	var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 120.0
	check("miner: he lands on the ground", m.pl.ground, "y %.1f" % m.pl.y)
	print("ARCADE TEST info miner tick %.2f ms, awake chunks %d" % [tick_ms, m.awake_chunks()])
	t0 = Time.get_ticks_usec()
	m.refresh_picture()
	print("ARCADE TEST info miner first picture %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in 30:
		m.tick()
		m.refresh_picture()
	print("ARCADE TEST info miner tick+picture %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / 30.0))
	for i in 600:
		m.tick()
	check("miner: the sand and water settle (few chunks awake)", m.awake_chunks() < 60, "%d of %d" % [m.awake_chunks(), SandMinerGame.CCX * SandMinerGame.CCY])
	# dig straight down under him
	var cx: float = m.pl.x + SandMinerGame.PW / 2.0
	var st := {"x": 0.0, "y": 0.0, "held": {}, "pressed": {}, "ptr": null, "aim": Vector2(0, 1), "ptr_alt": false}
	st.held["dig"] = true
	var dirt0 := m.inv[SandMinerGame.DIRT] + m.inv[SandMinerGame.CLAY]
	for i in 40:
		m.step(1.0 / 60.0, st)
	check("miner: the shovel digs dirt", m.inv[SandMinerGame.DIRT] + m.inv[SandMinerGame.CLAY] > dirt0, "dirt %d clay %d" % [m.inv[SandMinerGame.DIRT], m.inv[SandMinerGame.CLAY]])
	# ore: put a lump of gold where he digs, dig it, and the nuggets come to him
	var y0 := int(m.pl.y) + SandMinerGame.PH + 2
	for yy in range(y0, y0 + 4):
		for xx in range(int(cx) - 2, int(cx) + 3):
			m.set_cell(yy * SandMinerGame.W + xx, SandMinerGame.GOLD)
	var score0 := m.score
	for i in 240:
		m.step(1.0 / 60.0, st)
	check("miner: gold dug pops out as nuggets and scores", m.score > score0, "score %d nuggets %d gold %d" % [m.score, m.nuggets.size(), m.inv[SandMinerGame.GOLD]])
	# launch some dirt
	m.inv[SandMinerGame.DIRT] = 50
	var shots0 := m.inv[SandMinerGame.DIRT]
	var st2 := {"x": 0.0, "y": 0.0, "held": {"launch": true}, "pressed": {}, "ptr": null, "aim": Vector2(1, -1)}
	for i in 30:
		m.step(1.0 / 60.0, st2)
	check("miner: the launcher throws dirt", m.inv[SandMinerGame.DIRT] < shots0 and m.shots.size() > 0, "left %d shots %d" % [m.inv[SandMinerGame.DIRT], m.shots.size()])
	m.step(1.0 / 60.0, {"pressed": {"q": true}, "held": {}})
	check("miner: Q picks the next ammo", m.ammo == SandMinerGame.CLAY)
	m.inv[SandMinerGame.COAL] = 5
	m.step(1.0 / 60.0, {"pressed": {"u": true}, "held": {}})
	check("miner: U upgrades the launcher with 5 coal", m.launch_lvl == 2 and m.inv[SandMinerGame.COAL] == 0)
	# ---- the cabinets in the game
	var p: Player = main.player
	var c0: Dictionary = GameData.data.CABINETS[0]
	p.place(float(c0.x), 135.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check("cabinet: E says PLAY in front of Sand Miner", p.focus_label == "PLAY", "label '%s'" % p.focus_label)
	p.place(float(c0.x) + 100.0, 300.0)
	await get_tree().process_frame
	check("cabinet: nothing from across the room", p.focus_label != "PLAY", "label '%s'" % p.focus_label)
	p.place(float(c0.x), 135.0)
	await get_tree().process_frame
	p.use()
	check("cabinet: E opens Sand Miner", arcade.overlay.is_open() and arcade.overlay.game_id == "miner")
	check("cabinet: he stands still while playing", not p.controls_enabled and Arcade.is_open())
	await get_tree().create_timer(0.4).timeout
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	check("cabinet: Esc walks away", not arcade.overlay.is_open() and p.controls_enabled)
	await get_tree().process_frame
	p.use()
	print("ARCADE TEST info reopened: ", arcade.overlay.is_open(), " focus ", p.focus_label)
	await get_tree().create_timer(0.4).timeout
	_key(KEY_E)
	await get_tree().process_frame
	check("cabinet: E walks away too", not arcade.overlay.is_open())
	var c1: Dictionary = GameData.data.CABINETS[1]
	p.place(float(c1.x), 135.0)
	await get_tree().process_frame
	await get_tree().process_frame
	p.use()
	check("cabinet: Bricks opens the Mega Drive menu", arcade.md.is_open() and not p.controls_enabled)
	arcade.md._btn_snake.pressed.emit()
	await get_tree().process_frame
	check("menu: Play Snake plays Snake on the Bricks cabinet", arcade.overlay.is_open() and arcade.overlay.game_id == "snake" and not arcade.md.is_open())
	# a go: start, die, the high score is kept
	var ov := arcade.overlay
	await get_tree().create_timer(0.35).timeout
	ov.test_step(0.016, {"go": true})
	check("overlay: PUSH TO START starts it", ov.game.live)
	ov.game.score = 7
	ov.game.over = true
	ov.test_step(0.016, {})
	ov.close()
	check("overlay: the best score is kept", int(arcade.hi.get("snake", 0)) >= 7, str(arcade.hi))
	check("overlay: closing gives him back", p.controls_enabled and not Arcade.is_open())
	# he faces the cabinet again (the lobby's vending machine stands just behind him: facing away buys from it)
	p.facing = Vector2(0, -1)
	await get_tree().process_frame
	p.use()
	await get_tree().process_frame
	arcade.md._btn_bricks.pressed.emit()
	await get_tree().process_frame
	check("menu: Play Bricks plays Bricks", ov.is_open() and ov.game_id == "bricks")
	Arcade.close_all()
	check("Arcade.close_all shuts it all", not Arcade.is_open() and p.controls_enabled)
	# first person: E still works and the pointer comes back
	main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	p.place(float(c0.x), 135.0)
	p.look_ang = -PI / 2.0
	await get_tree().process_frame
	await get_tree().process_frame
	check("first person: E says PLAY", p.focus_label == "PLAY", "label '%s'" % p.focus_label)
	p.use()
	check("first person: E opens it", ov.is_open())
	Arcade.close_all()
	main.rig.set_mode(CameraRig.Mode.TOP_DOWN)
	# touch: a swipe steers Snake
	ov.open(GameData.data.CABINETS[1], "snake")
	await get_tree().create_timer(0.4).timeout
	var mid := ov.stage_to_view(ArcadeOverlay.SCR.get_center())
	_touch(true, mid)
	for i in 6:
		_drag(mid + Vector2(0, -10 * (i + 1)))
		await get_tree().process_frame
	await get_tree().process_frame
	check("touch: a swipe up starts Snake and turns it up", ov.game.live and ov.game.next == Vector2i(0, -1), "next %s drag %s" % [ov.game.next, ov._drag])
	_touch(false, mid + Vector2(0, -60))
	await get_tree().process_frame
	check("touch: lifting the finger lets go", ov._drag == Vector2.ZERO and ov.device == "touch")
	Arcade.close_all()
	# a pad: X is ammo in Sand Miner, B walks away
	p.place(float(c0.x), 135.0)
	await get_tree().process_frame
	await get_tree().process_frame
	p.use()
	await get_tree().create_timer(0.4).timeout
	ov.game.live = true
	_pad(JOY_BUTTON_X)
	await get_tree().process_frame
	await get_tree().process_frame
	check("pad: X picks the next ammo in Sand Miner", ov.game.ammo == SandMinerGame.CLAY and ov.device == "pad")
	_pad(JOY_BUTTON_B)
	await get_tree().process_frame
	check("pad: B walks away", not ov.is_open() and p.controls_enabled)
	# the friend's offer and messages (milestone 4 hooks)
	var sent: Array = []
	arcade.md.friend_send = func(msg): sent.append(msg)
	var mine := arcade.md.on_friend_message({"t": "md", "on": 1, "name": "Sonic", "who": "Tornado Tyson", "sys": "md"})
	check("friend: an offer is the Mega Drive's message", mine and arcade.md.offer != null and arcade.md._ask.visible)
	check("friend: other messages aren't", not arcade.md.on_friend_message({"t": "snap"}))
	arcade.md.on_friend_message({"t": "md", "on": 0})
	check("friend: stopped clears the offer", arcade.md.offer == null and not arcade.md._ask.visible)

func _pad(b: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)

func _touch(down: bool, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = down
	e.position = at
	Input.parse_input_event(e)

func _drag(at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	Input.parse_input_event(e)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
