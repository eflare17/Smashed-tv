extends SceneTree
## The help page (headless: --fixed-fps 60 -s test/voxel/help_test.gd -- --save=user://help_x.json): the HELP button
## (0 of 14 tried), the ? key opens WHAT CAN I DO? with a card an activity, Esc closes it; E at the seed crate ticks
## Farming (a "Tried" note, the button's count up); the ticks saved with the backpack and back on load. Owned by the
## voxel session.

var arena: Node
var t := 0.0
var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("HELP ok   ", what)
	else:
		failed += 1
		print("HELP FAIL ", what)

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var h: VoxelHelp = arena.guide
	h.from_data([])
	check(h != null and h._btn.text.contains("0/%d" % VoxelHelp.CARDS.size()), "the HELP button: \"%s\"" % h._btn.text)
	h._unhandled_input(_ev(KEY_SLASH))
	check(h.is_open() and h._grid.get_child_count() == VoxelHelp.CARDS.size(), "? opens WHAT CAN I DO?: %d cards" % h._grid.get_child_count())
	h._unhandled_input(_ev(KEY_ESCAPE))
	check(not h.is_open(), "Esc closes it")
	# E at the seed crate: Farming tried
	arena._near_prop = "crate0"
	arena.cash = 50
	arena._unhandled_input(_ev(KEY_E))
	check(h.done.has("farm") and h._toast.visible and h._toast.text.contains("Farming") and h._btn.text.contains("1/"), "E at the seed crate: Farming ticked (\"%s\")" % h._toast.text)
	h.tried("farm")
	check(h.done.size() == 1, "tried twice: ticked once")
	h.tried("nonsense")
	check(h.done.size() == 1, "an unknown one: nothing")
	h.open()
	var ticked := 0
	for c in h._grid.get_children():
		for l in c.find_children("*", "Label", true, false):
			if (l as Label).text == "✔ tried":
				ticked += 1
	check(ticked == 1, "its card says tried (%d)" % ticked)
	h.close()
	# saved and loaded
	var st = arena.stash
	if st.save_path != "":
		st.save()
		h.from_data([])
		st.load_save()
		check(h.done.has("farm"), "saved with the backpack, back on load")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(st.save_path))
	print("HELP done %d passed, %d failed" % [passed, failed])
	return true

func _ev(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	return e
