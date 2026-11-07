extends SceneTree
## Checks the on-screen buttons once he's out of the machine, in the whole game. Run: godot --headless --path . -s test/onfoot_test.gd
## Free play and the mine: Get out, and the SHOVEL and RAKE buttons are there; SHOVEL picks it up and DIG shows.

var fails := 0
var g: Node
var t := 0
var on_mine := false

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
	if t == 40:
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
		g.queue_free()
		if on_mine:
			Engine.remove_meta("big_site")
			print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
			quit(fails)
		else:
			on_mine = true
			_start()
	return false
