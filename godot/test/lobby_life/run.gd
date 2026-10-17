extends Node
## Headless logic tests for lobby life, inside the real game (scenes/main.tscn with LobbyLife installed).
## Run:  godot --headless --path <copy> res://test/lobby_life/run.tscn --fixed-fps 60 -- --test=<name>[,<name>...]
## (no --test: all of them). Each test is res://test/lobby_life/t_<name>.gd with `func run(t) -> void` (a
## coroutine: await t.wait(seconds)); t.check(cond, what) records a result. Prints "PASS <what>" / "FAIL <what>",
## then "LOBBY TESTS: n passed, m failed" and quits (exit code 1 if anything failed).

var main: Node
var ll: LobbyLife
var passed := 0
var failed := 0
var current := ""

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	ll = LobbyLife.install(main)
	ll.rig.capture_mouse = false
	_go.call_deferred()

func _go() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			names = Array(a.substr(7).split(","))
	if names.is_empty():
		for f in DirAccess.get_files_at("res://test/lobby_life/"):
			if f.begins_with("t_") and f.ends_with(".gd"):
				names.append(f.substr(2, f.length() - 5))
	for n in names:
		current = n
		var s = load("res://test/lobby_life/t_%s.gd" % n)
		if s == null:
			check(false, "load t_%s.gd" % n)
			continue
		var t = s.new()
		reset()
		await t.run(self)
	print("LOBBY TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("PASS [%s] %s" % [current, what])
	else:
		failed += 1
		print("FAIL [%s] %s" % [current, what])

func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0 / maxf(0.01, Engine.time_scale))
	var frames := int(ceil(sec * 60.0))
	for i in frames:
		await get_tree().process_frame

## Back to a clean state: the player let go of, standing where the lobby starts him, top-down.
func reset() -> void:
	var p := ll.player
	if ll.busy.has(p):
		var th = ll.busy[p]
		ll.release(p)
		th.busy_end(p)
	p.frozen = false
	p.dz = 0.0
	ll.rig.set_mode(CameraRig.Mode.TOP_DOWN)
	place(380, 260)

func place(x: float, y: float, face: Vector2 = Vector2(0, -1)) -> void:
	var p := ll.player
	p.place(x, y)
	p.facing = face
	p.halt()
	ll.rig.snap()

## Press E as the player would (the busy thing's E if he's held, else the nearest Interactable).
func press_e() -> void:
	var p := ll.player
	if ll.busy.has(p):
		ll.busy_act(p)
	else:
		p._update_focus()
		p.use()

## What E says now.
func label() -> String:
	var p := ll.player
	if ll.busy.has(p):
		return ll.busy[p].busy_label(p)
	p._update_focus()
	return p.focus_label

## Hold an action down for sec seconds (Input.action_press), e.g. "move_up".
func hold(action: String, sec: float) -> void:
	Input.action_press(action)
	await wait(sec)
	Input.action_release(action)

## Send an input event (as if pressed) through the viewport.
func key(keycode: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	e.pressed = true
	get_viewport().push_input(e)
	var r := e.duplicate()
	r.pressed = false
	get_viewport().push_input(r)
