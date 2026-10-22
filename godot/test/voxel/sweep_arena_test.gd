extends SceneTree
## The bug sweep's arena and settings fixes, each checked (headless): no frame times kept outside a test run; a guest
## joined mid-fire stops the burn loop; corpses past the cap go in the order they died; top-down, a click on ONLINE or
## SETTINGS doesn't fire the gun too; arena.fire doesn't kick the view (the gun's shot_fx does); settings opened on the
## couch (or the online menu) gets you up; the benchmark from bed gets you up and fights on the arena's floor; no
## benchmark while down; the benchmark's kills pay nothing; ONLINE doesn't open over the settings screen or the
## benchmark; the Arc cards guessed High; shadows Off turns off the bedroom's ceiling light's too; a room code picked out
## of "Code: K7QD" and "... K7QD.".
## (The mouse kept free under the backpack after a menu closes can't be seen headless: the mouse mode isn't kept.)
## Prints "SWA ok/FAIL ..." and "SWA done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var started := false
var done := false
var passed := 0
var failed := 0

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("SWA %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t >= 1.0 and not started:
		started = true
		_run()
	return done

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _body(key: String, at: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(key, arena._cube_m(key), arena.chunk, arena._mat)
	b.position = at
	arena.bodies.append(b)
	b.hp = 1e9
	return b

func _kill(b: VoxelBody) -> void:
	b.hp = 10.0
	b.hurt(500.0)

# a real left click (through Input, so its button state is seen too) at a point on the game's view (put into the
# window's own coordinates: the headless window is small, the view stretched over it)
func _click(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = root.get_final_transform() * at
	e.global_position = e.position
	Input.parse_input_event(e)

# held down a few frames: did the weapon out get pressed?
func _held_while_down() -> bool:
	var held := false
	for i in 4:
		await process_frame
		held = held or bool(arena._held.get(MOUSE_BUTTON_LEFT, false))
	return held

# top-down: a click elsewhere fires (pressed and held), a click on the button doesn't and opens its menu
func _click_button(btn: Button) -> Array:
	var mid: Vector2 = arena.get_viewport().get_visible_rect().size * 0.5 + Vector2(120, 90)
	_click(mid, true)
	var fired_elsewhere: bool = await _held_while_down()
	_click(mid, false)
	await _wait(3)
	var at := btn.get_global_rect().get_center()
	_click(at, true)
	var fired_on_btn: bool = await _held_while_down()
	_click(at, false)
	await _wait(2)
	return [fired_elsewhere, fired_on_btn]

func _run() -> void:
	var m: VoxelSettingsMenu = arena.settings_menu
	var nm: VoxelNetMenu = arena.net_menu

	# _frames: only a test run's summary reads them
	check(arena._frames.is_empty(), "no frame times kept in a game that isn't a test run (%d)" % arena._frames.size())

	# arena.fire: no kick (the other player's copies fire through it); the gun's own shot_fx still kicks this view
	arena._kick = 0.0
	arena.fire(Vector3(0, 1.6, 6), Vector3(0, 0, -1), 1, 0.0, 1.0)
	var fire_kick: float = arena._kick
	arena.melee["pistol"].shot_fx(Vector3(0, 1.5, 6), 0.8, 0)
	check(fire_kick == 0.0 and arena._kick > 0.4, "arena.fire doesn't kick the view (%.2f), the local gun's shot_fx does (%.2f)" % [fire_kick, arena._kick])

	# a guest joined while something burned here: the burn loop stops
	arena.sound.loop("burning", "burn_loop", null, -8.0)
	arena.net.role = "guest"
	arena.net.linked = true
	await _wait(2)
	check(not arena.sound.playing("burning"), "joined as a guest mid-fire: the burn loop stops")
	arena.net.role = ""
	arena.net.linked = false
	await _wait(1)

	# past MAX_DEAD the first to die goes, not the first in the list
	for b in arena.bodies.duplicate():
		if not b.alive:
			arena.bodies.erase(b)
			b.queue_free()
	var md := VoxelArena.MAX_DEAD
	VoxelArena.MAX_DEAD = 2
	var a := _body("grunt", Vector3(-14, 0, -14))
	var b2 := _body("grunt", Vector3(-12, 0, -14))
	var c := _body("grunt", Vector3(-10, 0, -14))
	_kill(b2)
	await _wait(2)
	_kill(c)
	await _wait(2)
	_kill(a)
	await _wait(2)
	check(is_instance_valid(a) and not a.alive and arena.bodies.has(a) and is_instance_valid(c) and arena.bodies.has(c)
		and (not is_instance_valid(b2) or not arena.bodies.has(b2)), "past the corpse cap the first to die goes (not the one spawned first, killed last)")
	VoxelArena.MAX_DEAD = md

	# top-down: clicking ONLINE (O) or SETTINGS (F10) doesn't fire the gun on the way
	arena.top_down = true
	var r: Array = await _click_button(nm._btn)
	check(r[0] and not r[1] and nm.is_open(), "top-down: a click fires, a click on ONLINE doesn't (it opens the menu) %s" % str(r))
	nm.close()
	await _wait(2)
	r = await _click_button(m._btn)
	check(r[0] and not r[1] and m.is_open(), "top-down: a click on SETTINGS doesn't fire either (it opens the screen) %s" % str(r))
	m.close()
	arena.top_down = false
	await _wait(2)

	# ONLINE doesn't open over the settings screen (or its benchmark: no co-op started mid-run)
	m.open()
	nm.toggle()
	check(m.is_open() and not nm.is_open(), "ONLINE pressed with the settings screen up: not opened over it")
	m.close()

	# settings opened on the couch: up off it, so the menu's keys don't play the console's game
	arena.games.sit(1)
	m.open()
	check(m.is_open() and arena.games.seated == 0 and arena.games.tv.player_port == -1, "settings opened on the couch: up off it, no buttons to the game")
	m.close()
	arena.games.sit(2)
	nm.open()
	check(nm.is_open() and arena.games.seated == 0 and arena.games.tv.player_port == -1, "the online menu opened on the couch (its button): up off it too")
	nm.close()

	# no benchmark while down
	arena.down_t = 3.0
	arena.player_hp = 0.0
	m.open()
	m.bench_start()
	check(m._bench.is_empty() and m._result.text.contains("down"), "no benchmark while down (\"%s\")" % m._result.text)
	m.close()
	arena.down_t = 0.0
	arena.player_hp = VoxelArena.HP_MAX

	# the benchmark from bed: up first, the fight on the arena's floor; ONLINE can't open mid-run; its kills pay nothing
	var g := _body("grunt", Vector3(14, 0, -14))
	g.died.connect(arena._on_died)
	var c0: int = arena.cash
	var k0: int = arena.kills
	_kill(g)
	check(arena.cash == c0 + 1 and arena.kills == k0 + 1, "a kill outside the benchmark pays (control)")
	arena.lie_down(1)
	m.bench_warm = 30.0
	m.bench_measure = 0.2
	m.target_ms = 10000.0
	c0 = arena.cash
	k0 = arena.kills
	m.bench_start()
	var y_set: float = arena.player.global_position.y
	await _wait(3)
	var pp: Vector3 = arena.player.global_position
	check(not m._bench.is_empty() and arena.lying == 0 and absf(float(m._bench.at.y)) < 0.1 and not VoxelBedroom.in_house(pp)
		and Vector2(pp.x, pp.z).distance_to(Vector2(0, 9)) < 1.0, "the benchmark from bed: up first, the fight seen from the arena (%s)" % str(pp))
	nm.toggle()
	check(not nm.is_open(), "ONLINE pressed mid-benchmark: not opened")
	var g2 := _body("grunt", Vector3(14, 0, -12))
	g2.died.connect(arena._on_died)
	_kill(g2)
	await _wait(20)
	check(arena.cash == c0 and arena.kills == k0, "the benchmark's kills pay nothing (cash %d -> %d, kills %d -> %d)" % [c0, arena.cash, k0, arena.kills])
	m.bench_stop()
	m.close()
	check(absf(y_set - 0.05) < 0.001, "the benchmark's fight starts on the floor (%.2f)" % y_set)
	await _wait(2)
	# ... and from up on something (a step, the yard's mound): on the floor all the same
	arena.player.global_position = Vector3(2, 0.7, 4)
	m.bench_start()
	y_set = arena.player.global_position.y
	m.bench_stop()
	m.close()
	check(absf(y_set - 0.05) < 0.001, "from higher up too, the fight's on the arena's floor (%.2f)" % y_set)
	# ... and from the couch
	arena.games.sit(2)
	m.bench_start()
	check(arena.games.seated == 0, "the benchmark from the couch: up first")
	m.bench_stop()
	m.close()
	m.bench_warm = 1.5
	m.bench_measure = 4.0
	m.target_ms = 1000.0 / 60.0
	await _wait(2)

	# the graphics card's guess: Intel Arc by its real names
	check(VoxelSettings.guess("Intel(R) Arc(TM) A770 Graphics") == "high" and VoxelSettings.guess("Intel(R) Arc(TM) B580 Graphics") == "high"
		and VoxelSettings.guess("Intel(R) Arc(tm) A770 Graphics (DG2)") == "high", "Arc A7xx / B5xx guessed High by their real names")
	check(VoxelSettings.guess("Intel(R) UHD Graphics 620") == "low" and VoxelSettings.guess("AMD Radeon(TM) Graphics") == "low"
		and VoxelSettings.guess("AMD Radeon Graphics (radeonsi, renoir)") == "low" and VoxelSettings.guess("NVIDIA GeForce RTX 4070") == "ultra"
		and VoxelSettings.guess("AMD Radeon RX 6700 XT") == "high" and VoxelSettings.guess("NVIDIA GeForce GTX 1060 6GB") == "medium"
		and VoxelSettings.guess("llvmpipe (LLVM 15.0.7, 256 bits)") == "low" and VoxelSettings.guess("") == "low"
		and VoxelSettings.ORDER.has(VoxelSettings.guess()), "the other guesses as they were (and this PC's card read with none given)")

	# shadows Off: the bedroom's ceiling light casts none either (its lamps never did)
	var s := VoxelSettings.new()
	s.file = ""
	s.set_value("shadows", 0)
	s.apply(arena)
	var all_lights: Array = arena.house.find_children("*", "OmniLight3D", true, false)
	var shadowed := all_lights.filter(func(l): return l.shadow_enabled)
	s.set_value("shadows", 2)
	s.apply(arena)
	var shadowed2 := all_lights.filter(func(l): return l.shadow_enabled)
	check(shadowed.is_empty() and shadowed2.size() == 1, "shadows Off: the bedroom's ceiling light none (%d), on again: it alone (%d of %d)" % [shadowed.size(), shadowed2.size(), all_lights.size()])

	# a room code out of a pasted message, an address only when it's one
	check(VoxelNetMenu.code_in("join me, code K7QD.") == "K7QD" and VoxelNetMenu.code_in("Code: K7QD") == "K7QD"
		and VoxelNetMenu.code_in("code:k7qd") == "K7QD" and VoxelNetMenu.code_in("meet at 10:30, code PXR2") == "PXR2",
		"a room code out of \"Code: K7QD\", \"join me, code K7QD.\" (\"%s\", \"%s\")" % [VoxelNetMenu.code_in("Code: K7QD"), VoxelNetMenu.code_in("join me, code K7QD.")])
	check(VoxelNetMenu.code_in("192.168.1.20") == "192.168.1.20" and VoxelNetMenu.code_in("my address: 192.168.1.20.") == "192.168.1.20"
		and VoxelNetMenu.code_in(" 192.168.1.20:24643 ") == "192.168.1.20:24643" and VoxelNetMenu.code_in("localhost:24643") == "localhost:24643"
		and VoxelNetMenu.code_in("join me, the code's k7qd!") == "K7QD" and VoxelNetMenu.code_in("hello") == "", "an address still picked out (with its port), the rest as it was")
	# IPv6 (bare or "[v6]:port") and a dotted name stay addresses, not a room code made of their letters; "ip:1.2.3.4" whole
	var cases := {"fe80::1c2a:3bff:fe4d:5e6f": "fe80::1c2a:3bff:fe4d:5e6f", "[fe80::1]:24643": "[fe80::1]:24643", "[::1]:24643": "[::1]:24643",
		"2001:db8::1": "2001:db8::1", "::1": "::1", "1:2:3:4:5:6:7:8": "1:2:3:4:5:6:7:8", "mypc.local": "mypc.local", "mypc.local:24643": "mypc.local:24643",
		"my pc: mypc.local.": "mypc.local", "ip:192.168.1.20": "192.168.1.20", "(192.168.1.20)": "192.168.1.20", "join me\n192.168.1.20": "192.168.1.20",
		"code [K7QD]": "K7QD", "e.g. code K7QD": "K7QD", "at 10:30:00 code PXR2": "PXR2", "dead:beef code PXR2": "PXR2"}
	var wrong := []
	for k in cases:
		if VoxelNetMenu.code_in(k) != cases[k]:
			wrong.append("%s -> %s" % [k.c_escape(), VoxelNetMenu.code_in(k)])
	check(wrong.is_empty(), "IPv6, \"[v6]:port\" and \"mypc.local\" kept as addresses; \"e.g.\", \"10:30:00\", \"[K7QD]\" not (%s)" % ", ".join(wrong))

	print("SWA done %d passed, %d failed" % [passed, failed])
	done = true
