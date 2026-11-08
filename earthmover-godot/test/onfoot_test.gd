extends SceneTree
## Checks the on-screen buttons once he's out of the machine, in the whole game. Run: godot --headless --path . -s test/onfoot_test.gd
## Free play and the mine: Get out, and the SHOVEL and RAKE buttons are there; SHOVEL picks it up and DIG shows. In free play,
## PUSH BARROW takes hold of the barrow, the same button then says LET GO and lets go, and there's no motor heard meanwhile.

var fails := 0
var g: Node
var t := 0
var on_mine := false
var pushed_at := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	_start()

func _start() -> void:
	Engine.set_meta("free_play", true)
	if on_mine:
		Engine.set_meta("big_site", true)
	g = load("res://main.tscn").instantiate()
	root.add_child(g)
	t = 0

func _process(_d: float) -> bool:
	t += 1
	var where := "on the mine" if on_mine else "in free play"
	if t == 39:
		check(g.sfx.engine.volume_db > -25.0, "%s: the machine's engine is heard (%.0f dB)" % [where, g.sfx.engine.volume_db])
	elif t == 40:
		g._get_out()
	elif t == 50:
		check(g.active.machine_name == "On foot", "%s: Get out puts him on foot" % where)
		check(g.shovel_button.visible, "%s: the SHOVEL button shows" % where)
		check(g.rake_button.visible, "%s: the RAKE button shows" % where)
		check(not g.spade_button.visible, "%s: no DIG button with nothing in his hands" % where)
		g._on_tool("shovel")
	elif t == 60:
		check(g.workers[0].tool == "shovel", "%s: SHOVEL picks the shovel up" % where)
		check(g.spade_button.visible and g.spade_word.text == "DIG", "%s: then DIG shows" % where)
		if on_mine:
			_finish()
		else:
			g._on_tool("shovel")
			var b: Machine = g.barrow
			g.workers[0].step_off(b.spot - b.forward() * 1.3, b.angle)
	elif t == 70:
		check(g.get_in_button.visible and g.get_in_word.text == "PUSH\nBARROW", "by the barrow, PUSH BARROW shows")
		g._get_in_or_let_go()
		pushed_at = Engine.get_physics_frames()
	elif t > 70 and t < 1000 and Engine.get_physics_frames() - pushed_at >= 120:
		check(g.active is Barrow, "PUSH BARROW takes hold of it")
		check(g.get_in_button.visible and g.get_in_word.text == "LET GO\nBARROW", "pushing it, the same button says LET GO")
		check(g.buttons["out"].visible and g.buttons["out"].text == "Let go", "and the top bar's button says Let go")
		check(g.sfx.engine.volume_db < -50.0, "no motor heard while pushing it (%.0f dB)" % g.sfx.engine.volume_db)
		g._get_in_or_let_go()
		t = 1000
	elif t == 1010:
		check(g.active.machine_name == "On foot", "LET GO lets go of it")
		check(g.get_in_button.visible and g.get_in_word.text == "PUSH\nBARROW", "and PUSH BARROW is back, to take hold again")
		check(not g.buttons["out"].visible, "on foot, the top bar's Let go is gone")
		# Out of the tree first, as the game's own reload does: the mine's a bigger world, and the old one mustn't run another frame in it.
		root.remove_child(g)
		g.queue_free()
		on_mine = true
		_start()
	return false

func _finish() -> void:
	g.queue_free()
	Engine.remove_meta("big_site")
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
