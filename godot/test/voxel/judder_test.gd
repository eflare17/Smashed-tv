extends SceneTree
## The view's steadiness -- the third thing behind the phone's stutter (the owner, 25 Nov, on the build with the
## shader pre-warm and the touch fold already in it: "it's getting close to 60 frames, but it still kind of looks a
## bit shuddery when I'm moving both sticks"). The frame rate was right and the movement still was not, so it is
## pacing, not throughput.
##
## Godot's physics interpolation is on for the whole game, and with it on a Node3D is drawn at lerp(where it was at
## the last physics tick, where it is now, the frame's physics fraction). That is right for a node the physics moves
## and wrong for one placed fresh every frame in _process, because then "where it was at the last tick" is last
## frame's value and the fraction -- which wanders as the frame time moves -- smears the two together. The game's
## camera is placed and aimed every frame by VoxelArena._camera, and it is the one node whose wobble the player sees
## as the whole world wobbling.
##
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/judder_test.gd -- --nosave
##   ... and WITHOUT --fixed-fps for the mechanism check, which a pinned frame time cannot see (it says so if it
##   could not look)
##
## What it checks:
##   - the mechanism, on bare nodes: fed a perfectly even step every frame at ~60 fps with a browser's few ms of
##     frame-time jitter, a node in the interpolation draws an uneven step and one out of it draws an even one. This
##     is the part a --fixed-fps run can never show, because fixed frames pin the physics fraction and the smear
##     becomes exactly one frame of lag instead of a wobble -- which is why nothing caught this before. It runs on
##     its own real-time loop for that reason.
##   - the game's per-frame nodes are out of it: the camera, your own Jared, and (in co-op) your mate's body, view
##     and Jared. Your own Jared matters doubly now the camera is out: while both were in they smeared together and
##     stayed still relative to each other, so taking only the camera out would have started him sliding.
##   - the two switches the owner uses to compare, both ways: SET's "Steady view" row (set_steady_view) and
##     "Combine thumb moves" (VoxelTouch.fold), and ?steady=0 / ?fold=0 on the page.
## Prints PASS / FAIL lines and "JUDDER: X passed, Y failed". Owned by the voxel phone-performance session.

var arena: VoxelArena
var passed := 0
var failed := 0
var step := 0
# the mechanism check's own loop
var _in: Node3D
var _out: Node3D
var _f := 0
var _p_in := 0.0
var _p_out := 0.0
var _d_in: Array[float] = []
var _d_out: Array[float] = []
var _fr: Array[float] = []

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

func _initialize() -> void:
	seed(20261125)
	_in = Node3D.new()
	root.add_child(_in)
	_out = Node3D.new()
	_out.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_out)

## The spread of a series over its average, as a percentage: 0% is perfectly even.
static func _wobble(a: Array[float]) -> float:
	if a.size() < 2:
		return 0.0
	var mu := 0.0
	for v in a:
		mu += v
	mu /= float(a.size())
	var sq := 0.0
	for v in a:
		sq += (v - mu) * (v - mu)
	return sqrt(sq / float(a.size())) / maxf(0.000001, absf(mu)) * 100.0

static func _lo(a: Array[float]) -> float:
	var r := INF
	for v in a:
		r = minf(r, v)
	return r

static func _hi(a: Array[float]) -> float:
	var r := -INF
	for v in a:
		r = maxf(r, v)
	return r

func _process(_dt: float) -> bool:
	# ---- part one: the mechanism, on its own real-time loop with a browser's worth of frame-time jitter
	if step == 0:
		_f += 1
		OS.delay_msec(14 + randi() % 6)         # ~60 fps, give or take 3 ms: a browser, not --fixed-fps
		_in.position.x = float(_f)               # the same step every frame: a perfectly even input
		_out.position.x = float(_f)
		var a: float = _in.get_global_transform_interpolated().origin.x
		var b: float = _out.get_global_transform_interpolated().origin.x
		if _f > 10:                              # (the first frames: the interpolation settling)
			_d_in.append(a - _p_in)
			_d_out.append(b - _p_out)
			_fr.append(Engine.get_physics_interpolation_fraction())
		_p_in = a
		_p_out = b
		if _f >= 190:
			step = 1
			_mechanism()
			arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
			root.add_child(arena)
		return false
	if step == 1 and arena.phone != null:
		step = 2
		_game()
	return false

func _mechanism() -> void:
	var w_in := _wobble(_d_in)
	var w_out := _wobble(_d_out)
	print("  even input of 1.000 a frame, %d frames at ~60 fps with jitter; physics fraction ran %.3f to %.3f" % [
		_d_in.size(), _lo(_fr), _hi(_fr)])
	print("  in the interpolation:  steps %.3f to %.3f a frame, wobble %.1f%%" % [_lo(_d_in), _hi(_d_in), w_in])
	print("  out of it:             steps %.3f to %.3f a frame, wobble %.1f%%" % [_lo(_d_out), _hi(_d_out), w_out])
	# out of the interpolation the drawn step is the step it was given, to the float's precision
	_check(w_out < 0.5 and absf(_lo(_d_out) - 1.0) < 0.01 and absf(_hi(_d_out) - 1.0) < 0.01,
		"out of the interpolation, an even input draws an even step (wobble %.1f%%)" % w_out)
	# In it, the same even input comes out uneven -- this is the shudder. It needs a varying frame time to show: under
	# --fixed-fps the frame time is pinned, the physics fraction never moves, and the smear becomes exactly one frame
	# of lag instead of a wobble. That is why no test here ever caught this, so rather than pass or fail on a run that
	# cannot see it, the check says it could not look. Run without --fixed-fps for the real thing.
	if _hi(_fr) - _lo(_fr) < 0.1:
		print("NOTE the physics fraction never moved (%.3f to %.3f): a pinned frame time hides this entirely." % [
			_lo(_fr), _hi(_fr)])
		print("NOTE     run without --fixed-fps to see the wobble the browser sees.")
		return
	_check(w_in > 5.0 and w_in > w_out * 5.0,
		"in the interpolation, the same even input draws an uneven one (wobble %.1f%% against %.1f%%)" % [w_in, w_out])

func _game() -> void:
	var OFF := Node.PHYSICS_INTERPOLATION_MODE_OFF
	# ---- the game's per-frame nodes are out of the interpolation
	_check(arena.steady_view, "the view is steady by default")
	_check(arena.cam.physics_interpolation_mode == OFF, "the camera is out of the physics interpolation")
	_check(arena.avatar.physics_interpolation_mode == OFF, "your own Jared is out of it too (top-down, the mirror)")
	# your mate's body, view and Jared: placed every frame in VoxelNet._other_frame
	arena.net._make_other()
	_check(arena.net._o_body.physics_interpolation_mode == OFF
		and arena.net._o_cam.physics_interpolation_mode == OFF
		and arena.net.other_avatar.physics_interpolation_mode == OFF,
		"in co-op, your mate's body, view and Jared are out of it")
	arena.net._drop_other()
	# the 2D fight's block enemies ("Characters: blocks", VoxelEnemies): each enemy's root is placed fresh every
	# frame from _process (_pose), the same shape as the camera, your own Jared and the gravity gun, and it was the
	# one left in the interpolation
	var en: Node3D = load("res://scripts/voxel/voxel_enemies.gd").new()
	root.add_child(en)
	await process_frame             # (added from _process, so its own _ready runs on the next frame)
	_check(en.physics_interpolation_mode == OFF,
		"the 2D fight's block enemies are out of it as well (their roots are its children and inherit it)")
	root.remove_child(en)
	en.free()
	# ---- the switch, both ways: the owner compares in one session, not against a memory of an hour ago
	arena.set_steady_view(false)
	_check(not arena.steady_view and arena.cam.physics_interpolation_mode != OFF,
		"Steady view off: the camera goes back into the interpolation")
	arena.set_steady_view(true)
	_check(arena.steady_view and arena.cam.physics_interpolation_mode == OFF, "Steady view on again: back out")
	# ---- both switches are real settings with SET rows, and the page's options reach them
	for key in ["steady", "fold"]:
		_check(VoxelSettings.CHOICES.has(key) and VoxelSettings.PERSONAL.has(key)
			and bool(VoxelSettings.PERSONAL[key]), "\"%s\" is a SET row and starts on" % VoxelSettings.CHOICES[key][0])
	var s := VoxelSettings.new()
	s.file = ""
	s.set_value("steady", false)
	s.set_value("fold", false)
	s.apply(arena)
	_check(not arena.steady_view and arena.cam.physics_interpolation_mode != OFF and not VoxelTouch.fold,
		"the two SET rows turned off: both fixes off")
	s.set_value("steady", true)
	s.set_value("fold", true)
	s.apply(arena)
	_check(arena.steady_view and arena.cam.physics_interpolation_mode == OFF and VoxelTouch.fold,
		"the two SET rows turned on: both fixes on")
	# the page's ?steady=0 / ?fold=0 read into the settings themselves, so the SET rows tell the truth and can still
	# be flipped back mid-game -- which is the whole point of them
	var m := VoxelSettingsMenu.new()
	arena.add_child(m)
	var keep: Dictionary = arena._opts.duplicate()
	arena._opts["steady"] = "0"
	arena._opts["fold"] = "0"
	m.setup(arena, false)
	_check(not m.s.v.steady and not m.s.v.fold and not arena.steady_view and not VoxelTouch.fold,
		"?steady=0&fold=0 start with both off, and the SET rows say so")
	arena._opts = keep
	m.queue_free()
	# ---- and with a saved settings file in the way they still have to win. The four are read into the settings
	# before the file is loaded, and load_file() reads back every key the file holds -- which on any machine that
	# has run the game once is all of them -- so the file simply overwrote them and ?smooth=1 / ?steady=0 only ever
	# worked on a brand-new install. They must not be saved back either: a comparison asked for in a link is not a
	# choice the owner made in the SET rows.
	var f := "user://judder_opts_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var w := VoxelSettings.new()
	w.file = f
	w.set_value("smooth", false)            # the file says Off ...
	w.set_value("steady", true)
	w.save_file()
	var m2 := VoxelSettingsMenu.new()
	arena.add_child(m2)
	m2.s.file = f
	keep = arena._opts.duplicate()
	arena._opts["smooth"] = "1"             # ... and the page says On
	arena._opts.erase("steady")
	arena._opts.erase("fold")
	m2.setup(arena, true)
	_check(bool(m2.s.v.get("smooth", false)) and VoxelTouch.smooth,
		"?smooth=1 beats a saved file that says Off (the file used to win)")
	var cf := ConfigFile.new()
	_check(cf.load(f) == OK and not bool(cf.get_value("settings", "smooth", false)),
		"... and it isn't written back into the file as if it had been chosen")
	arena._opts = keep
	m2.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	VoxelTouch.smooth = false
	# ---- put it back as the game ships, so nothing after this runs on the old path
	VoxelTouch.fold = true
	arena.set_steady_view(true)
	print("JUDDER: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
