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
	# ---- both thumbs down: a frame's worth of drags is applied once (the owner, 25 Nov: "it only seems to stutter
	# when I'm using both sticks" -- with two fingers the browser's drags stop being folded for us, so the layer
	# folds them itself)
	yaw0 = arena.look_yaw
	var folds0: int = touch.folds_sec
	var keys0: int = touch.key_sec
	for n in 20:                    # one frame, forty drags: the stick's thumb jittering, the look's thumb sweeping
		_drag(0, s0 + Vector2(0, -60 + (1 if n % 2 == 0 else -1)), Vector2(0, 1.0 if n % 2 == 0 else -1.0))
		_drag(1, l0 + Vector2(40 + n * 2, 0), Vector2(2, 0))
	await _wait(0.05)
	_check(touch.folds_sec - folds0 == 1, "both thumbs: a frame of 40 drags is applied once, not forty times (%d)" % (touch.folds_sec - folds0))
	_check(arena.look_yaw < yaw0 - 0.05, "... and the view turns by the lot of them, not by the last one (%.3f rad)" % (arena.look_yaw - yaw0))
	_check(touch.key_sec - keys0 == 0, "... and a jittering thumb sends the game no keys (%d)" % (touch.key_sec - keys0))
	yaw0 = arena.look_yaw
	_drag(1, l0 + Vector2(1040, 0), Vector2(1000, 0))
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.6, "a finger's huge jump is capped: the view doesn't spin (%.3f rad)" % (arena.look_yaw - yaw0))
	# ---- the snap (the owner, 25 Nov: "view jumps or snaps" -- sudden jerks to a different angle). Godot's web
	# build measures a drag's `relative` from whichever finger was in the same place in the browser's changed-touch
	# list last time, so with two thumbs down it keeps handing us one thumb's move measured from the OTHER thumb's
	# position -- hundreds of pixels. Proved in the real browser build on 25 Nov: wrong on every one of 40 drags
	# when the thumbs alternate, by up to 1245 px. The layer works each finger's movement out itself now, so a
	# `relative` about the wrong finger changes nothing at all.
	_drag(1, l0 + Vector2(1040, 0), Vector2.ZERO)       # (settle: the finger is where it says it is)
	await _wait(0.1)
	yaw0 = arena.look_yaw
	var pitch0 := arena.look_pitch
	var bad0: int = touch.rel_bad_sec
	for n in 6:                     # the look thumb creeping 3 px a sample, each `relative` the gap to the stick thumb
		var at := l0 + Vector2(1040 + n * 3, 0)
		_drag(1, at, at - s0)       # the engine's figure: measured from the stick's thumb, not this one
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.1 and absf(arena.look_pitch - pitch0) < 0.1,
		"a `relative` about the other thumb is ignored: 18 px of thumb turns the view 18 px worth (%.3f rad, %.3f up)" % [
			arena.look_yaw - yaw0, arena.look_pitch - pitch0])
	_check(touch.rel_bad_sec > bad0 and touch.rel_bad_worst > 200.0,
		"... and it is counted and reported as the engine getting it wrong (%d drags, worst %.0f px out)" % [
			touch.rel_bad_sec - bad0, touch.rel_bad_worst])
	# ---- a thumb rolling or briefly lifting: the re-press must contribute nothing, however far it lands from
	# where the finger was. Both ways round: a proper lift and press, and a press the browser never said was lifted.
	yaw0 = arena.look_yaw
	_touch(1, l0 + Vector2(1058, 0), false)
	await _wait(0.05)
	_touch(1, Vector2(vs.x * 0.95, vs.y * 0.9), true)   # down again, most of the screen away
	await _wait(0.05)
	_drag(1, Vector2(vs.x * 0.95, vs.y * 0.9) + Vector2(4, 0), Vector2(4, 0))
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.05, "a thumb lifted and put down elsewhere starts from there (%.3f rad)" % (arena.look_yaw - yaw0))
	yaw0 = arena.look_yaw
	_touch(1, Vector2(vs.x * 0.55, vs.y * 0.15), true)  # pressed again with no lift: the layer lets the old one go
	await _wait(0.05)
	_drag(1, Vector2(vs.x * 0.55, vs.y * 0.15) + Vector2(4, 0), Vector2(4, 0))
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.05, "a thumb the browser never said was lifted, pressed again: no jump (%.3f rad)" % (arena.look_yaw - yaw0))
	# ---- a finger the browser gives a big identifier to (Godot's web build passes the DOM's own number through):
	# it gets a slot of ours, and its first drag is measured from where it landed
	yaw0 = arena.look_yaw
	var big := Vector2(vs.x * 0.75, vs.y * 0.3)
	_touch(37, big, true)
	await _wait(0.05)
	_drag(37, big + Vector2(5, 0), big - s0)            # again the engine's cross-finger figure
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.05, "a finger with identifier 37: a slot of ours, and no jump on its first drag (%.3f rad)" % (arena.look_yaw - yaw0))
	_touch(37, big + Vector2(5, 0), false)
	await _wait(0.05)
	# ---- and a frame's worth of samples can't add up to a jerk, however many arrive (LOOK_FRAME_CAP)
	yaw0 = arena.look_yaw
	var capped0: int = touch.frame_capped_sec
	var ff := Vector2(vs.x * 0.55, vs.y * 0.15)
	# ten samples each worth a whole LOOK_CAP, all in the one frame, with the stick's thumb in between so Godot
	# doesn't fold them into one: capped one at a time that is 900 px, and LOOK_FRAME_CAP holds it to 150
	for n in 10:
		ff += Vector2(300, 0)
		_drag(1, ff, Vector2(300, 0))
		_drag(0, s0 + Vector2(0, -60), Vector2.ZERO)
	await _wait(0.1)
	_check(absf(arena.look_yaw - yaw0) < 0.6 and touch.frame_capped_sec > capped0,
		"ten capped samples in one frame add up to a cap, not a spin (%.3f rad, %d frames capped)" % [
			arena.look_yaw - yaw0, touch.frame_capped_sec - capped0])
	_touch(1, ff, false)
	await _wait(0.05)
	_touch(1, l0, true)             # (the look thumb back where the rest of the test expects it)
	await _wait(0.05)
	# ---- "Even out the view": off unless it's asked for, and when it is on it must only move the surplus of a
	# bursty frame to the next frame -- not lose any of the thumb's movement, which would be a slower view
	_check(not T.smooth, "evening the view out is off unless it's asked for")
	var burst := func(where: Vector2) -> Vector2:
		var a := where
		for n in 4:               # four even frames first, so there's an average for a burst to stand out from
			a += Vector2(10, 0)
			_drag(1, a, Vector2(10, 0))
			await _wait(0.02)
		var y := arena.look_yaw
		for n in 6:               # then six samples in the one frame: the clump
			a += Vector2(10, 0)
			_drag(1, a, Vector2(10, 0))
			_drag(0, s0 + Vector2(0, -60), Vector2.ZERO)    # (between them, so Godot doesn't fold them into one)
		await _wait(0.1)          # (two frames: the frame itself and the one the surplus goes out on)
		return Vector2(arena.look_yaw - y, a.x)
	var plain: Vector2 = await burst.call(l0)
	var held0: int = touch.smooth_held_sec
	T.smooth = true
	var evened: Vector2 = await burst.call(Vector2(plain.y + 20.0, l0.y))
	T.smooth = false
	_check(touch.smooth_held_sec > held0, "evened out: a bursty frame's surplus is held for the next frame (%d frames)" % (touch.smooth_held_sec - held0))
	_check(absf(evened.x - plain.x) < absf(plain.x) * 0.05,
		"... and none of the thumb's movement is lost on the way (%.4f rad vs %.4f)" % [evened.x, plain.x])
	# ... and the surplus has to land on a LATER frame than the burst, which is the whole of what this setting does.
	# flush() runs four times a rendered frame (VoxelArena._physics_process at 120 Hz, so twice, VoxelArena._process,
	# and this layer's own _process) and it used to let the held part straight back out on the second call, because
	# the "have I just held something" flag it tested is still true for the rest of that frame. So the camera got the
	# whole unsmoothed burst before the frame was drawn and the row did nothing at all; the two checks above cannot
	# see that, because they only ever compare the total, which the bug preserves. flush() is driven directly here:
	# a drag cannot choose which of a frame's four calls it arrives between.
	T.smooth = true
	touch._look_held = Vector2.ZERO
	touch._held_last = false
	touch._held_frame = -1
	touch._spread_frame = -1
	touch._look_avg = 10.0          # (a steady 10 px a frame: 120 px in one frame is a burst against that)
	touch._pend_look = Vector2(120, 0)
	touch._pend_look_any = true
	yaw0 = arena.look_yaw
	touch.flush()
	var one := arena.look_yaw - yaw0
	touch.flush()
	touch.flush()
	var same := arena.look_yaw - yaw0
	_check(absf(same - one) < 0.00001 and touch._look_held != Vector2.ZERO,
		"evened out: the surplus stays put when flush() runs again in the same frame (%.4f rad, then %.4f)" % [one, same])
	await _wait(0.06)
	var whole := arena.look_yaw - yaw0
	_check(absf(whole) > absf(one) * 1.5 and absf(whole - one * 2.0) < absf(one) * 0.1 and touch._look_held == Vector2.ZERO,
		"... and it goes out whole on a later frame (%.4f rad of the burst's frame, %.4f in all)" % [one, whole])
	T.smooth = false
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
	# ---- two thumbs on the one button: the press lasts until the LAST of them lifts. A second finger put on a
	# button that is already down was not written down anywhere, so when IT lifted the button was let go with the
	# first thumb still pressing it -- FIRE held, a second thumb brushed it, and the gun stopped firing.
	_touch(0, _btn(T.B_FIRE), true)
	await _wait(0.1)
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "FIRE held by one thumb")
	_touch(1, _btn(T.B_FIRE) + Vector2(8, 8), true)
	await _wait(0.1)
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "a second thumb down on it: still held, and not pressed twice")
	_touch(1, _btn(T.B_FIRE) + Vector2(8, 8), false)
	await _wait(0.1)
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		"the second thumb lifted: the first thumb's press is still on (it used to stop here)")
	_touch(0, _btn(T.B_FIRE), false)
	await _wait(0.1)
	_check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "the last thumb off it: now the button's up")
	# and the same for a key button (R), the other way round: the FIRST of the two lifts first
	_touch(0, _btn(T.B_JUMP), true)
	_touch(1, _btn(T.B_JUMP) + Vector2(6, 6), true)
	await _wait(0.1)
	_touch(0, _btn(T.B_JUMP), false)
	await _wait(0.1)
	_check(Input.is_physical_key_pressed(KEY_SPACE), "JUMP under two thumbs: the first lifting doesn't let it go")
	_touch(1, _btn(T.B_JUMP) + Vector2(6, 6), false)
	await _wait(0.1)
	_check(not Input.is_physical_key_pressed(KEY_SPACE), "... the second lifting does")
	await _wait(0.6)
	# ---- a menu opened and closed with a thumb still on the glass: it goes on working without being lifted. On the
	# owner's phone the stick went dead after any menu, because letting go of what was HELD also threw away the
	# browser's finger-id -> slot map, and every drag from a finger whose id was gone was dropped until it lifted.
	arena.player.global_position = Vector3(0, 0.05, 6)
	arena.look_yaw = 0.0
	await _wait(0.3)
	_touch(0, s0, true)
	await _wait(0.05)
	_drag(0, s0 + Vector2(0, -60), Vector2(0, -60))
	await _wait(0.3)
	_check(touch.stick_on and touch.move.y < -0.4, "a thumb on the stick, pushed up (%.2f)" % touch.move.y)
	arena.settings_menu.toggle()
	await _wait(0.3)
	_check(arena.settings_menu.is_open() and not touch.stick_on and touch.move == Vector2.ZERO
		and not Input.is_physical_key_pressed(KEY_W),
		"the settings up: the stick is let go and no key is left down")
	_check(touch._slot.has(0), "... but the thumb that never left the glass is still one the layer knows")
	arena.settings_menu.toggle()
	await _wait(0.3)
	_drag(0, s0 + Vector2(0, -70), Vector2(0, -10))     # (its first drag back: it takes the stick under itself)
	await _wait(0.05)
	p0 = arena.player.global_position
	_drag(0, s0 + Vector2(0, -130), Vector2(0, -60))
	await _wait(0.5)
	_check(touch.stick_on and touch.move.y < -0.4,
		"the menu closed and the same thumb dragged on: the stick is back under it, nothing lifted (%.2f)" % touch.move.y)
	_check(arena.player.global_position.z < p0.z - 0.5,
		"... and it walks you again (%.2f m)" % (p0.z - arena.player.global_position.z))
	_touch(0, s0 + Vector2(0, -130), false)
	await _wait(0.2)
	# a thumb left sitting on FIRE when the menu closed: it turns the view, and it does NOT fire on its own -- the
	# finger this happens to is usually the one that tapped the menu open or X shut, resting over the cluster
	_touch(1, _btn(T.B_FIRE), true)
	await _wait(0.15)
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "a thumb on FIRE")
	arena.settings_menu.toggle()
	await _wait(0.3)
	_check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "the settings up: FIRE is let go")
	arena.settings_menu.toggle()
	await _wait(0.3)
	var fb := _btn(T.B_FIRE)
	_drag(1, fb + Vector2(-20, 0), Vector2(-20, 0))
	await _wait(0.05)
	yaw0 = arena.look_yaw
	_drag(1, fb + Vector2(-70, 0), Vector2(-50, 0))
	await _wait(0.2)
	_check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and absf(arena.look_yaw - yaw0) > 0.02,
		"the thumb left on FIRE turns the view when it moves, and never fires by itself (%.3f rad)" % (arena.look_yaw - yaw0))
	_touch(1, fb + Vector2(-70, 0), false)
	await _wait(0.3)
	_check(not touch.stick_on and not touch._slot.has(0) and not touch._slot.has(1)
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		"both thumbs lifted: nothing held, and their slots are given back")
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
