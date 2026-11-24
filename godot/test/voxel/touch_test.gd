extends SceneTree
## Touch controls (VoxelTouch, the browser's game on a phone): with touch off there's no layer and the keyboard walks
## you; the first real touch turns touch mode on (as --touch / ?touch does from the start); the left stick walks the
## player, a drag on the right turns the view (capped: one huge jump of a finger doesn't spin it), FIRE fires the
## weapon out, > and a tap on the weapon bar change weapon, E uses what's in front (a chest), PHONE gets the phone out
## and a tap on a row travels, SET opens the settings and a tap on LOW changes the preset; a phone's first run starts
## on Low; the Forward+-only rows hide.
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/touch_test.gd -- --nosave
## Prints PASS / FAIL lines and "TOUCH: X passed, Y failed". Owned by the voxel-web-touch session.

const T := preload("res://scripts/voxel/arena/voxel_touch.gd")

var arena: VoxelArena
var touch: VoxelTouch
var t := 0.0
var step := 0
var passed := 0
var failed := 0
var p0 := Vector3.ZERO
var yaw0 := 0.0
var clip0 := 0
var slot0 := 0
var mid := Vector2.ZERO

func _initialize() -> void:
	seed(20261124)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = root.get_final_transform() * at      # (the window's pixels: the screen's stretch is taken off on the way in)
	e.pressed = down
	Input.parse_input_event(e)

func _drag(i: int, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = root.get_final_transform() * at
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)

func _tap(at: Vector2) -> void:
	_touch(0, at, true)
	await create_timer(0.1).timeout
	_touch(0, at, false)

func _btn(b: int) -> Vector2:
	return touch.button_pos(b)

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _process(_dt: float) -> bool:
	if step == 0 and arena.phone != null:
		step = 1
		_run()
	return false

func _run() -> void:
	await _wait(0.5)
	VoxelBody.immortal = true
	arena.godmode = true
	arena.frozen = true
	mid = root.get_visible_rect().size * 0.5
	# ---- touch off: no layer, the keyboard as ever
	_check(not VoxelTouch.active and arena.touch == null, "touch off: no touch layer (active %s)" % VoxelTouch.active)
	_check(arena.help.visible, "touch off: the keyboard's line along the bottom is there")
	_check(not VoxelTouch.detect({"notouch": "1"}) and not VoxelTouch.allowed, "?notouch: never")
	_check(VoxelTouch.detect({"touch": "1"}), "?touch / --touch: touch mode forced on")
	_check(not VoxelTouch.detect({}) and VoxelTouch.allowed, "no option, not a phone: off (a touch may still turn it on)")
	arena.player.global_position = Vector3(0, 0.05, 6)
	arena.look_yaw = 0.0
	p0 = arena.player.global_position
	_key(KEY_W, true)
	await _wait(0.5)
	_key(KEY_W, false)
	_check(arena.player.global_position.z < p0.z - 1.0, "touch off: W walks you forward (%.2f m)" % (p0.z - arena.player.global_position.z))
	# ---- the first real touch: touch mode
	_touch(5, Vector2(mid.x * 1.2, mid.y * 0.6), true)
	await _wait(0.1)
	_touch(5, Vector2(mid.x * 1.2, mid.y * 0.6), false)
	await _wait(0.1)
	touch = arena.touch
	_check(touch != null and VoxelTouch.active, "the first touch turns touch mode on: the layer's built")
	if touch == null:
		_done()
		return
	_check(not arena.help.visible, "touch mode: the keyboard's long line is hidden")
	_check(not arena.settings_menu._btn.visible and not arena.guide._btn.visible and not arena.net_menu._btn.visible,
		"touch mode: the mouse's small SETTINGS / HELP / ONLINE buttons are put away")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and VoxelTouch.grabbed(), "touch mode: no pointer lock, the game plays on")
	var all_on := true
	for b in [T.B_FIRE, T.B_AIM, T.B_USE, T.B_RELOAD, T.B_PREV, T.B_NEXT, T.B_JUMP, T.B_MORE, T.B_PHONE, T.B_BAG, T.B_VIEW, T.B_HELP, T.B_SET, T.B_ONLINE]:
		all_on = all_on and touch.button_shown(b)
	_check(all_on, "FIRE, AIM, E, R, < >, JUMP, ... and PHONE BAG VIEW HELP SET ONLINE are on screen")
	var vs := root.get_visible_rect().size
	var apart := true
	var inside := true
	for a in T.B_COUNT:
		if not touch.button_shown(a):
			continue
		var ra := Rect2(touch._at[a] - touch._half[a], touch._half[a] * 2.0)
		inside = inside and Rect2(Vector2.ZERO, vs).encloses(ra)
		for b in range(a + 1, T.B_COUNT):
			if touch.button_shown(b) and ra.intersects(Rect2(touch._at[b] - touch._half[b], touch._half[b] * 2.0).grow(-8.0)) \
					and touch._at[a].distance_to(touch._at[b]) < touch._half[a].x + touch._half[b].x:
				apart = false
				print("  overlap ", T.DEFS[a][0], " ", T.DEFS[b][0])
	_check(apart and inside, "no button over another, none off the screen (%dx%d)" % [int(vs.x), int(vs.y)])
	# ---- the stick walks
	arena.player.global_position = Vector3(0, 0.05, 6)
	arena.look_yaw = 0.0
	p0 = arena.player.global_position
	var s0 := Vector2(vs.x * 0.2, vs.y * 0.55)
	_touch(0, s0, true)
	await _wait(0.05)
	_drag(0, s0 + Vector2(0, -60), Vector2(0, -60))
	await _wait(0.5)
	_check(touch.stick_on and touch.move.y < -0.4, "a thumb on the left: the stick (pushed up: %.2f)" % touch.move.y)
	_check(arena.player.global_position.z < p0.z - 0.8, "the stick pushed up walks you forward (%.2f m)" % (p0.z - arena.player.global_position.z))
	# ---- a second finger looks while the first walks
	yaw0 = arena.look_yaw
	var l0 := Vector2(vs.x * 0.62, vs.y * 0.4)
	_touch(1, l0, true)
	await _wait(0.05)
	_drag(1, l0 + Vector2(40, 0), Vector2(40, 0))
	await _wait(0.1)
	_check(arena.look_yaw < yaw0 - 0.05 and touch.stick_on, "a second finger dragged on the right turns the view (%.3f rad) while the stick's held" % (arena.look_yaw - yaw0))
	yaw0 = arena.look_yaw
	_drag(1, l0 + Vector2(1040, 0), Vector2(1000, 0))
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.6, "a finger's huge jump is capped: the view doesn't spin (%.3f rad)" % (arena.look_yaw - yaw0))
	# ---- a third finger fires (the pistol's out) while those two stay down
	clip0 = int(arena.melee.pistol.clip)
	_touch(2, _btn(T.B_FIRE), true)
	await _wait(0.15)
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "FIRE held is the left mouse button held")
	yaw0 = arena.look_yaw
	_drag(2, _btn(T.B_FIRE) + Vector2(-30, 0), Vector2(-30, 0))
	await _wait(0.1)
	_check(arena.look_yaw > yaw0 + 0.03, "a drag from FIRE turns the view too (aim while you fire)")
	_touch(2, _btn(T.B_FIRE) + Vector2(-30, 0), false)
	await _wait(0.15)
	_check(int(arena.melee.pistol.clip) < clip0, "FIRE fired the weapon out (the pistol: %d -> %d rounds)" % [clip0, int(arena.melee.pistol.clip)])
	_check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "FIRE let go: the button's up")
	_touch(1, l0, false)
	_touch(0, s0, false)
	await _wait(0.2)
	_check(not touch.stick_on and touch.move == Vector2.ZERO and not Input.is_physical_key_pressed(KEY_W), "the thumb lifted: the stick's back, nothing held")
	p0 = arena.player.global_position
	await _wait(0.3)
	_check(arena.player.global_position.distance_to(p0) < 0.05, "... and you stand still")
	# ---- weapons: > the next one, a tap on the bar's slot that one
	slot0 = arena.loadout.current
	await _tap(_btn(T.B_NEXT))
	await _wait(0.4)
	_check(arena.loadout.current == posmod(slot0 + 1, arena.loadout.slots.size()), "> takes out the next weapon (%s)" % arena.loadout.id())
	await _tap(_btn(T.B_PREV))
	await _wait(0.4)
	_check(arena.loadout.current == slot0, "< the one before (%s)" % arena.loadout.id())
	var bar: VoxelWeaponBar = arena.bar
	var want := arena.loadout.index_of("shotgun")
	var at := Vector2.INF
	for x in range(0, int(bar.size.x), 8):
		if bar.slot_at(Vector2(x, bar.size.y - 20.0)) == want:
			at = bar.global_position + Vector2(x + 16.0, bar.size.y - 20.0)
			break
	await _tap(at)
	await _wait(0.4)
	_check(arena.loadout.id() == "shotgun", "a tap on the weapon bar's shotgun takes the shotgun out (%s)" % arena.loadout.id())
	# ---- JUMP
	arena.player.global_position = Vector3(0, 0.05, 6)
	await _wait(0.2)
	_touch(0, _btn(T.B_JUMP), true)
	await _wait(0.2)
	_touch(0, _btn(T.B_JUMP), false)
	_check(arena.player.global_position.y > 0.3, "JUMP jumps (%.2f m up)" % arena.player.global_position.y)
	await _wait(0.8)
	# ---- E on something: a chest (its line shown by the button), X closes it
	var st: VoxelStorage = arena.stash.by_id["chest_a"]
	arena.player.global_position = st.front() + Vector3(0, 0, 0.9)
	arena.player.velocity = Vector3.ZERO
	arena.look_yaw = 0.0
	arena.look_pitch = -0.7
	await _wait(0.4)
	_check(arena._near_st == st and touch._use_cap != "", "stood at a chest: E's caption is the game's own line (\"%s\")" % touch._use_cap)
	await _tap(_btn(T.B_USE))
	await _wait(0.3)
	_check(arena.inv_ui.is_open() and arena.inv_ui.storage == st, "E opens the chest")
	_check(touch.button_shown(T.B_CLOSE) and not touch.button_shown(T.B_FIRE), "a menu up: X is there, the game's buttons aren't")
	# a tap is a click: the backpack's first stack picked up, put down in the next slot
	arena.inv.add("egg", 3)
	await _wait(0.1)
	var ui: VoxelInventoryUI = arena.inv_ui
	var bp: Dictionary = ui._panels[ui._panels.size() - 1]
	var from_i := -1
	for i in arena.inv.size():
		if not arena.inv.is_empty_at(i):
			from_i = i
			break
	var xf := ui.get_global_transform()
	await _tap(xf * ui._slot_rect(bp, from_i).get_center())
	await _wait(0.2)
	_check(not ui.cursor.is_empty(), "the backpack by touch: a tap on a stack picks it up")
	var to_i := arena.inv.size() - 1
	await _tap(xf * ui._slot_rect(bp, to_i).get_center())
	await _wait(0.2)
	_check(ui.cursor.is_empty() and not arena.inv.is_empty_at(to_i), "... a tap on another slot puts it down there")
	await _tap(_btn(T.B_CLOSE))
	await _wait(0.3)
	_check(not arena.inv_ui.is_open() and touch.button_shown(T.B_FIRE), "X closes it: the game's buttons are back")
	# ---- BAG: the backpack; HELP: the page
	await _tap(_btn(T.B_BAG))
	await _wait(0.3)
	_check(arena.inv_ui.is_open() and arena.inv_ui.storage == null, "BAG opens the backpack")
	await _tap(_btn(T.B_CLOSE))
	await _wait(0.3)
	await _tap(_btn(T.B_HELP))
	await _wait(0.3)
	_check(arena.guide.is_open(), "HELP opens the help page")
	await _tap(_btn(T.B_CLOSE))
	await _wait(0.3)
	_check(not arena.guide.is_open(), "X closes the help page")
	await _tap(_btn(T.B_ONLINE))
	await _wait(0.3)
	_check(arena.net_menu.is_open(), "ONLINE opens the online menu")
	await _tap(_btn(T.B_CLOSE))
	await _wait(0.3)
	_check(not arena.net_menu.is_open(), "X closes the online menu")
	# ---- VIEW: top-down; the right thumb aims
	await _tap(_btn(T.B_VIEW))
	await _wait(0.3)
	_check(arena.top_down, "VIEW: top-down")
	arena.player.global_position = Vector3(0, 0.05, 6)
	await _wait(0.2)
	_touch(1, l0, true)
	await _wait(0.05)
	_drag(1, l0 + Vector2(80, 0), Vector2(80, 0))
	await _wait(0.2)
	var aim: Array = arena._aim()
	_check(aim.size() == 2 and (aim[1] as Vector3).x > 0.5, "top-down: the right thumb pushed right aims Jared right (%s)" % [aim[1] if aim.size() == 2 else "-"])
	_touch(1, l0 + Vector2(80, 0), false)
	await _tap(_btn(T.B_VIEW))
	await _wait(0.3)
	_check(not arena.top_down, "VIEW again: first person")
	# ---- SET: the settings, a preset by a tap
	arena.settings_menu.s.set_preset("high")
	await _tap(_btn(T.B_SET))
	await _wait(0.4)
	_check(arena.settings_menu.is_open(), "SET opens the settings")
	var lowb: Button = arena.settings_menu._presets.low
	_check(lowb.size.y >= 60.0, "touch mode: the preset buttons are a thumb's size (%d px)" % int(lowb.size.y))
	await _tap(lowb.get_global_rect().get_center())
	await _wait(0.4)
	_check(arena.settings_menu.s.preset == "low", "a tap on LOW: the Low preset (%s)" % arena.settings_menu.s.preset)
	await _tap((arena.settings_menu._presets.medium as Button).get_global_rect().get_center())
	await _wait(0.4)
	_check(arena.settings_menu.s.preset == "medium", "a tap on MEDIUM raises it (%s)" % arena.settings_menu.s.preset)
	arena.settings_menu.show_supported(false)
	await _wait(0.1)
	_check(not arena.settings_menu._rows.sdfgi.visible and not arena.settings_menu._rows.taa.visible and not arena.settings_menu._rows.fog.visible
		and arena.settings_menu._rows.shadows.visible and arena.settings_menu._rows.scale.visible,
		"Compatibility: the Forward+-only rows (TAA, SDFGI, fog ...) aren't shown; shadows, render scale are")
	arena.settings_menu.show_supported(true)
	await _tap(_btn(T.B_CLOSE))
	await _wait(0.3)
	_check(not arena.settings_menu.is_open(), "X closes the settings")
	# ---- a phone's first run: Low (no guessing from the graphics card), and what's picked after is kept
	var f := "user://touch_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var s := VoxelSettings.new()
	s.file = f
	s.load_file()
	_check(s.first_run and s.preset == "low", "a phone's first run starts on Low (%s)" % s.preset)
	s.set_preset("high")
	s.save_file()
	var s2 := VoxelSettings.new()
	s2.file = f
	s2.load_file()
	_check(not s2.first_run and s2.preset == "high", "the preset picked is kept for next time (%s)" % s2.preset)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	# ---- PHONE: out, a row tapped: there
	await _tap(_btn(T.B_PHONE))
	await _wait(0.4)
	_check(arena.phone.is_open(), "PHONE gets the phone out")
	var row: Button = arena.phone._buttons["range"]
	await _tap(row.get_global_rect().get_center())
	await _wait(2.5)
	_check(arena.gun_range.active and not arena.phone.is_open(), "a tap on the phone's Gun range row: you're at the gun range")
	_check(touch.button_shown(T.B_LANE_NEXT), "at the gun range: LANE < > buttons (the [ ] keys)")
	var lane0: int = arena.gun_range.lane
	await _tap(_btn(T.B_LANE_NEXT))
	await _wait(0.3)
	_check(arena.gun_range.lane != lane0, "LANE > moves you a lane on")
	_done()

func _done() -> void:
	print("TOUCH: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
