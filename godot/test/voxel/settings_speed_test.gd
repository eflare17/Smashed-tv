extends SceneTree
## Stage 10, the settings screen's speed (the owner, 25 Nov: he opened SET on his Galaxy S25's browser, tapped a row
## and the tab froze and never came back, so he reloaded). What froze it: the rows that change a cube size, and the
## preset buttons above them that change two, used to build every block character again inside the tap -- your own
## Jared is 655,000 cubes at Fine, which was one frame 13 s long here and 14.3 s in a desktop browser.
##
## So this walks the whole screen the way a thumb does -- every preset button, then every row and every value it
## offers, down the list and back up -- and holds each one to a budget: the tap itself must come back inside
## TAP_MS, and if it starts a rebuild, no frame of that rebuild may cost more than FRAME_MS and the whole of it
## must be over inside MAX_FRAMES. It also taps a row twice in a row and two rows in the same frame, which must
## fold into the one rebuild instead of stacking or deadlocking, and checks the characters actually come out at the
## size that was asked for.
##
## It starts the game on Low -- a phone's first run -- and then empties every character cache, so each size really
## is built from nothing the first time a row asks for it. Without that this test would pass with the bug still in:
## a test's game starts on High, which builds your own Jared at Fine during the loading screen, and the row that
## used to freeze a phone would find him already made and cost nothing. _cold() is the whole point of the test.
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/settings_speed_test.gd -- --nosave
## Prints PASS / FAIL lines and "SETTINGS SPEED: X passed, Y failed". Owned by the voxel session.

## The tap on a row itself: it may set a rebuild going, it may not do one. Measured worst here: 13 ms.
const TAP_MS := 60.0
## And any one frame of the rebuild that follows, with the game still being played underneath. VoxelArena.REBUILD_MS
## asks for 6 ms a frame and nearly every frame takes it; the budget is this wide because two steps inside a
## character can't be cut any finer than one part of it -- keeping the biggest lump of a part's cubes (one flood
## fill over the lot) and meshing it. Your own Jared's torso is 199,000 cubes, which is 203 ms for the first and
## 181 ms for the second on this PC: the two frames that reach for this budget. Everything else is inside 15 ms.
## A freeze, which is what this test is here to stop, was 13,194 ms in one frame.
const FRAME_MS := 300.0
const MAX_FRAMES := 900         # and the whole rebuild (15 s at 60: Jared at Fine is about 2.3 s of work)

var arena: VoxelArena
var m: VoxelSettingsMenu
var t := 0.0
var started := false
var passed := 0
var failed := 0
var plan := []                  # [what, key, index] to tap, in order
var i := 0
var waiting := ""               # the tap we're watching a rebuild for
var frames := 0
var worst_frame := 0.0
var worst_tap := 0.0
var worst_tap_what := ""
var worst_frame_what := ""
var last_us := 0

## The character caches put back to what a phone's game holds when SET is opened: the enemies and your own Jared
## built at the sizes Low asks for (the loading screen does that much), and nothing at all built at any other size.
func _cold() -> void:
	VoxelBody._flesh_cache.clear()
	VoxelBody._shared.clear()
	VoxelBody._bone0.clear()
	arena._warm_up()            # (the loading screen's "enemies" step, at the size they're being played at)
	arena.remake_avatar()       # ... and your own Jared at the size Low gives him: chunky
	arena._respawn_all()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

func _initialize() -> void:
	seed(20261125)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _rows() -> Array:
	var out := []
	for key in VoxelSettings.CHOICES:
		if (m._rows[key] as Control).visible:
			out.append(key)
	return out

func _plan() -> void:
	# the presets, Low last so what follows starts from a phone's own first run
	for name in ["medium", "high", "ultra", "extreme", "low"]:
		plan.append(["preset", name, 0])
	# every row, every value it offers, down and back
	for key in _rows():
		var n: int = (m._choice[key][0] as Array).size()
		for j in n:
			plan.append(["row", key, j])
		for j in range(n - 2, -1, -1):
			plan.append(["row", key, j])
	# tapped twice in a row, and two rows in the one frame: one rebuild, not two
	plan.append(["double", "jared", 0])
	plan.append(["both", "", 0])

func _tap(what: Array) -> float:
	var t0 := Time.get_ticks_usec()
	match String(what[0]):
		"preset":
			m._on_preset(String(what[1]))
		"row":
			(m._rows[String(what[1])] as OptionButton).item_selected.emit(int(what[2]))
		"double":
			# the same row twice inside one frame: chunky, then fine again before the first has finished
			var ob: OptionButton = m._rows.jared
			ob.item_selected.emit(1)
			ob.item_selected.emit(0)
		"both":
			(m._rows.jared as OptionButton).item_selected.emit(1)
			(m._rows.chunk as OptionButton).item_selected.emit(1)
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _name(what: Array) -> String:
	match String(what[0]):
		"preset": return "preset %s" % String(what[1]).to_upper()
		"row": return "%s -> %s" % [String(what[1]), String(m._choice[String(what[1])][1][int(what[2])])]
	return String(what[0])

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if not started:
		started = true
		m = arena.settings_menu
		m.s.set_preset("low")               # a phone's first run
		m.s.apply(arena)
		while arena.rebuilding():
			arena._rb_tick()
		m._refresh()
		_cold()                             # ... with nothing built at any other size, as a phone's game has it
		_plan()
		print("SETTINGS SPEED: %d taps planned" % plan.size())
		last_us = Time.get_ticks_usec()
		return false
	# a rebuild running: watch every frame of it
	if waiting != "":
		var ms := float(Time.get_ticks_usec() - last_us) / 1000.0
		last_us = Time.get_ticks_usec()
		frames += 1
		if ms > worst_frame:
			worst_frame = ms
			worst_frame_what = waiting
		if ms > FRAME_MS:
			_check(false, "%s: a frame of the rebuild took %.0f ms (budget %.0f)" % [waiting, ms, FRAME_MS])
		if frames > MAX_FRAMES:
			_check(false, "%s: the rebuild is still going after %d frames" % [waiting, frames])
			waiting = ""
		elif not arena.rebuilding():
			waiting = ""
		else:
			return false
	if i >= plan.size():
		return _done()
	var what: Array = plan[i]
	i += 1
	var ms2 := _tap(what)
	if ms2 > worst_tap:
		worst_tap = ms2
		worst_tap_what = _name(what)
	if ms2 > TAP_MS:
		_check(false, "%s: the tap itself took %.0f ms (budget %.0f)" % [_name(what), ms2, TAP_MS])
	if arena.rebuilding():
		waiting = _name(what)
		frames = 0
	last_us = Time.get_ticks_usec()
	return false

func _done() -> bool:
	_check(worst_tap <= TAP_MS, "every tap came back inside %.0f ms (worst %.0f ms, %s)" % [TAP_MS, worst_tap, worst_tap_what])
	_check(worst_frame <= FRAME_MS, "no frame of a rebuild went over %.0f ms (worst %.0f ms, %s)" % [FRAME_MS, worst_frame, worst_frame_what])
	# the last tap asked for chunky enemies and chunky Jared, and both must have arrived
	_check(arena.chunk == 2 and VoxelArena.jared_chunk == 2 and arena.avatar != null,
		"two rows tapped in the one frame: both took effect (enemies %d, Jared %d)" % [arena.chunk, VoxelArena.jared_chunk])
	_check(not arena.rebuilding(), "nothing left rebuilding at the end")
	# and back the other way, from nothing again: the one that froze the owner's tab, built cold, a slice a frame
	VoxelArena.jared_chunk = 2
	_cold()
	var t0 := Time.get_ticks_usec()
	(m._rows.jared as OptionButton).item_selected.emit(0)
	var tap := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(tap <= TAP_MS, "your own blocks -> Fine from nothing: the tap came back in %.0f ms" % tap)
	var n := 0
	while arena.rebuilding() and n < MAX_FRAMES:
		arena._rb_tick()
		n += 1
	_check(VoxelArena.jared_chunk == 1 and not arena.rebuilding() and n > 1 and n < MAX_FRAMES,
		"... and he was built over %d frames, not in the one tap" % n)
	print("SETTINGS SPEED: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true
