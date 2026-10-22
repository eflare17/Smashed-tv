extends Node
## Smash's cabinet in the real game: runs scenes/main.tscn (which installs the Arcade, which makes the cabinet)
## and checks the cabinet is there, says PLAY in front of it, opens over the game with the player held still,
## takes the keys, walks away again, and sleeps when you're far off.
## godot --headless --path godot --fixed-fps 60 res://arcade/smash/smash_cabinet_test.tscn   (exit code 1 on a fail)
## With `-- --shots=<dir>` (and a display) it saves pictures: the lounge from above, first person, and playing.

var main: Node
var fails := 0
var shots := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(20)
	var arcade = Arcade.instance()
	var cab = arcade.smash_cab if arcade else null
	_check(cab != null, "the Arcade made Smash's cabinet")
	if cab == null:
		get_tree().quit(1)
		return
	var p = main.player
	p.place(cab.X, cab.cab_y + 24.0)
	p.facing = Vector2(0, -1)
	await _frames(30)
	_check(cab.label_for(p) == "PLAY", "PLAY in front of it (%s)" % cab.label_for(p))
	_check(arcade.cabinets.all(func(c): return c.label_for(p) == ""), "the other cabinets don't answer there")
	_check(cab._awake and cab.smash.state == cab.smash.State.ATTRACT, "its screen runs the demo")
	if shots != "":
		await _snap("lounge_top")
		main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
		p.place(cab.X - 30.0, cab.cab_y + 70.0)
		p.look_ang = -PI / 2.0 + 0.35
		await _frames(30)
		await _snap("lounge_fp")
		main.rig.set_mode(CameraRig.Mode.TOP_DOWN)
		p.place(cab.X, cab.cab_y + 24.0)
		await _frames(10)

	cab.act(p)
	await _frames(5)
	_check(cab.is_open() and Arcade.is_open(), "E opens it (Arcade.is_open too)")
	_check(not main.hud.visible and not p.controls_enabled, "the player is held and the HUD is off")
	await _frames(30)
	_key(KEY_ENTER)
	await _frames(10)
	_check(cab.smash.state == cab.smash.State.PLAY, "Enter starts a game on it")
	var before: Vector3 = p.global_position
	Input.action_press("arcade_smash_move_left")
	await _frames(30)
	Input.action_release("arcade_smash_move_left")
	_check(cab.smash.player_pos.x < -0.5 and p.global_position.distance_to(before) < 0.01,
			"moving moves Smash's player, not the game's (%.2f)" % cab.smash.player_pos.x)
	if shots != "":
		cab.smash.spawn_debug(40)
		Input.action_press("arcade_smash_fire")
		await _frames(150)
		Input.action_release("arcade_smash_fire")
		await _snap("playing")
	_key(KEY_ESCAPE)
	await _frames(5)
	_check(not cab.is_open() and not Arcade.is_open(), "Esc walks away")
	_check(main.hud.visible and p.controls_enabled, "the player and the HUD are back")
	_check(cab.smash.state == cab.smash.State.ATTRACT and not cab.smash.input_enabled, "the cabinet's back to its demo")

	cab.act(p)
	await _frames(5)
	Arcade.close_all()
	await _frames(2)
	_check(not cab.is_open(), "Arcade.close_all closes it too")

	p.place(700.0, 400.0)
	await _frames(10)
	_check(not cab._awake and cab._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "far away, its demo sleeps")
	print("SMASH CABINET TEST done: %d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(cond: bool, what: String) -> void:
	print("SMASH CABINET %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1

func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame

func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("cab_%s.png" % n))
