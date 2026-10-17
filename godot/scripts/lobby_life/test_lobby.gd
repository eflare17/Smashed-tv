extends Node
## Lobby life inside the real game: makes scenes/main.tscn, installs LobbyLife on it (as main.gd will) and, for
## screenshots, sets a scene up: ?lobby=<name> in the web build's address (or --lobby=<name> after -- on the
## command line). Owned by the Lobby life session.
##
## Scenes: pool, tower, board, swim, bench, lift, legpress, rope, table, bong, trip, cards, mirror, wardrobe,
## bed, shroom, slot, vend, bbq, carry, fp (first person at the bench), goth.

var main: Node
var ll: LobbyLife
var scene_name: String = ""
var t: float = 0.0
var _steps: Array = []          # [[time, Callable], ...] to run once each

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	ll = LobbyLife.install(main)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lobby="):
			scene_name = a.substr(8)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			var i: int = q.find("lobby=")
			if i >= 0:
				scene_name = q.substr(i + 6).split("&")[0]
	if scene_name != "":
		print("LOBBY scene ", scene_name)
		_setup.call_deferred(scene_name)

func _process(delta: float) -> void:
	t += delta
	while _steps.size() > 0 and t >= _steps[0][0]:
		var s: Array = _steps.pop_front()
		(s[1] as Callable).call()

func later(at_t: float, f: Callable) -> void:
	_steps.append([at_t, f])
	_steps.sort_custom(func(a, b): return a[0] < b[0])

func go(x: float, y: float, face: Vector2 = Vector2(0, -1)) -> void:
	var p := ll.player
	p.place(x, y)
	p.facing = face
	p.look_ang = atan2(face.y, face.x)
	p.look_y = 0.0
	ll.rig.snap()

func fp(on: bool = true) -> void:
	ll.rig.capture_mouse = false
	ll.rig.set_mode(CameraRig.Mode.FIRST_PERSON if on else CameraRig.Mode.TOP_DOWN)

func use() -> void:
	var p := ll.player
	if ll.busy.has(p):
		ll.busy_act(p)
	else:
		p._update_focus()
		p.use()

func _setup(n: String) -> void:
	var parts := n.split(",")
	var name_ := parts[0]
	var view_fp := parts.has("fp")
	if view_fp:
		fp(true)
	var th: Dictionary = ll.things
	match name_:
		_:
			if th.has(name_) and th[name_].has_method("test_scene"):
				th[name_].test_scene(self, parts)
	print("LOBBY ready ", n)
