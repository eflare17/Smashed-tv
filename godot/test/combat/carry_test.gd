extends Node
## Protect mode in the real game: stand Jared next to Gothica, check the E prompt says PICK UP, press E (an input
## event, as the keyboard would send it), check she's in his arms, then E again puts her down.
## godot --headless --path godot res://test/combat/carry_test.tscn

var main: Node
var step := 0
var t := 0.0
var fails := 0

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	FightInstall.install(main)

func _press_e() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.keycode = KEY_E
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventKey.new()
	r.physical_keycode = KEY_E
	r.keycode = KEY_E
	r.pressed = false
	Input.call_deferred("parse_input_event", r)

func check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1

func _process(delta: float) -> void:
	t += delta
	var fg := Fight.me
	if fg == null:
		return
	match step:
		0:
			if t > 1.0:
				fg.mode = "protect"
				fg.start_run()
				step = 1
		1:
			if t > 1.5:
				var g := fg.sim.goth
				fg.f.x = g.x + 20.0
				fg.f.y = g.y
				g.wait = 99.0
				step = 2
		2:
			if t > 1.8:
				check(main.player.focus_label == "PICK UP", "E prompt says PICK UP (%s)" % main.player.focus_label)
				_press_e()
				step = 3
		3:
			if t > 2.1:
				check(fg.sim.goth.carrier == 0, "E picked her up")
				check(main.player.focus_label == "PUT DOWN", "E prompt says PUT DOWN (%s)" % main.player.focus_label)
				_press_e()
				step = 4
		4:
			if t > 2.4:
				check(fg.sim.goth.carrier == -1, "E put her down")
				print("carry test: %s" % ("ok" if fails == 0 else "%d failed" % fails))
				get_tree().quit(1 if fails else 0)
