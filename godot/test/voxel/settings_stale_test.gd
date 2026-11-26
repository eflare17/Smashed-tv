extends SceneTree
## The two things the owner hit on the native Android build, 26 Nov: "When i went into the setting in the apk ot
## froze. Also the enemies looked more blockybthen the website version".
##
## A saved settings file keeps every setting VERBATIM, so a DEFAULT that moves after a phone has written one never
## reaches that phone. The first APK (164b770) was built before cc0b076, when Low's "chunk" was 2 -- an eighth of
## the blocks -- and before 1a52b30, when a native phone started drawing at the screen's own pixels. So the owner's
## phone carries chunk: 2, scale: 0.67, scenery: 60.0 and no "jared" key at all, and every APK since has read it
## straight back: blocky enemies and a 67% picture on the phone, Fine and full size in the browser, where no
## pre-fix file was ever written.
##
## So this writes a file in the first APK's exact shape and checks:
##  - it comes up Fine, with Low's chunky Jared and the native build's own starting picture (VoxelSettings.VERSION
##    and _migrate: the version stamp is how the next default change does the same);
##  - a Chunky the player chose is left alone -- a stamped file, or an unstamped one that isn't Low;
##  - a file already up to date isn't touched, and once saved the step never runs again;
##  - and then the screen itself: the arena started on the native path WITH that file (--settings --touch, with
##    VoxelSettings.pretend_native and VoxelTouch.pretend_phone standing in for the APK's feature tags), the
##    settings screen opened, and every frame of it inside a budget. No frame may reach FREEZE_MS, nothing may be
##    left rebuilding characters, and opening the screen must not start a rebuild at all;
##  - and that a change the renderer really does chew on still says so: the MEDIUM button turns the shadows on and
##    builds your own Jared again at once, and the shadows' warning has to stay on screen through it rather than be
##    replaced by the rebuild's count (VoxelArena.say_held).
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/settings_stale_test.gd -- --nosave --settings --touch
## Prints PASS / FAIL lines and "SETTINGS STALE: X passed, Y failed". Owned by the voxel session.
##
## NOTE this is the one voxel test that reads and writes the real user://voxel_settings.cfg, because that is the
## path the bug lives on; it writes the file before the arena is built and removes it at the end.

## A frame of the settings screen. Opening it builds no blocks, so this is generous: the worst honest frame
## measured here was 30 ms (the first draw of the rows). FREEZE_MS is the failure -- the browser's freeze this
## family of bugs is named for was one frame 13,194 ms long.
const FRAME_MS := 300.0
const FREEZE_MS := 2000.0
const WATCH_FRAMES := 180       # three seconds of the screen being up

## Every setting the first Android APK (164b770) saved, with the values its Low preset gave a first launch, and
## nothing else: no "jared", no "steady"/"fold"/"own"/"smooth", and no version stamp.
const FIRST_APK := {
	"scale": 0.67, "msaa": 0, "taa": false, "shadows": 0, "ssao": false, "ssil": false, "glow": false,
	"sdfgi": false, "fog": false, "mirror": false, "chunk": 2, "lying": 40000, "flying": 3000, "pieces": 12,
	"corpses": 12, "gore": 0, "jiggle": 3, "scenery": 60.0, "fx": 0,
	"fov": 80.0, "sens": 1.0, "volume": 1.0, "fullscreen": false, "fps": 0, "vsync": true,
	"mine_sewers": true, "mine_cops": true, "mine_rivals": true, "announcer": 2,
}

var arena: VoxelArena
var m: VoxelSettingsMenu
var t := 0.0
var step := 0
var passed := 0
var failed := 0
var frames := 0
var worst := 0.0
var worst_what := ""
var last_us := 0
var open_ms := 0.0
var rebuilt := false
var said := ""                  # the longest line seen while MEDIUM's change was going through

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		passed += 1
	else:
		failed += 1

## A settings file written with exactly these values and nothing else (`version`: left out for an unstamped one).
func _write(path: String, vals: Dictionary, version := -1) -> void:
	var cf := ConfigFile.new()
	for k in vals:
		cf.set_value("settings", k, vals[k])
	if version >= 0:
		cf.set_value("settings", "version", version)
	cf.save(path)

func _load(path: String) -> VoxelSettings:
	var s := VoxelSettings.new()
	s.file = path
	s.load_file()
	return s

func _initialize() -> void:
	# the APK, as far as a headless PC can be it: the phone branches and the native caps both on, before the arena
	# reads its options (VoxelTouch.detect) or decides to stage its start-up
	VoxelTouch.pretend_phone = true
	VoxelSettings.pretend_native = true
	_write(VoxelSettings.FILE, FIRST_APK)       # the owner's phone, as it is now: the arena's own menu will read it
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

# ---------------------------------------------------------------- the file itself

func _file_checks() -> void:
	var tmp := "user://settings_stale_tmp.cfg"

	# 1. the owner's phone, on the native build
	_write(tmp, FIRST_APK)
	var s := _load(tmp)
	_check(int(s.v.chunk) == 1, "the first APK's file, native: the enemies come up Fine (chunk %d)" % int(s.v.chunk))
	_check(int(s.v.jared) == 2, "... your own Jared stays chunky, as Low has him (jared %d)" % int(s.v.jared))
	_check(is_equal_approx(float(s.v.scale), 1.0) and is_equal_approx(float(s.v.scenery), 110.0),
		"... and the native start it never got: the screen's own pixels, scenery to 110 m (%d%%, %d m)" % [
		int(float(s.v.scale) * 100.0), int(float(s.v.scenery))])
	_check(s.migrated and bool(s.v.steady) and bool(s.v.fold) and bool(s.v.own) and not bool(s.v.smooth),
		"... the three view fixes on and the smoothing off, as a fresh install has them")
	# saved back with its stamp, and then left alone for ever
	s.save_file()
	var s2 := _load(tmp)
	_check(not s2.migrated and int(s2.v.chunk) == 1, "saved with the stamp: the step doesn't run a second time")

	# 2. the same file in a phone's browser: Low as Low is now, and no native start
	VoxelSettings.pretend_native = false
	_write(tmp, FIRST_APK)
	var b := _load(tmp)
	_check(int(b.v.chunk) == 1 and int(b.v.jared) == 2 and is_equal_approx(float(b.v.scale), 0.67)
		and is_equal_approx(float(b.v.scenery), 60.0) and b.preset == "low",
		"the same file in a phone's browser: Fine enemies, and Low's own picture kept (%s)" % b.preset)
	VoxelSettings.pretend_native = true

	# 3. Chunky chosen on purpose, and stamped: the player's choice is the player's
	var mine := FIRST_APK.duplicate()
	mine.chunk = 2
	mine.jared = 2
	_write(tmp, mine, VoxelSettings.VERSION)
	var c := _load(tmp)
	_check(int(c.v.chunk) == 2 and not c.migrated, "Chunky chosen since the stamp: left alone (chunk %d)" % int(c.v.chunk))

	# 4. Chunky on an unstamped file that is NOT Low: the rest of it says it was chosen by hand, so it stays
	var hi := FIRST_APK.duplicate()
	hi.merge({"scale": 1.0, "msaa": 2, "shadows": 2, "ssao": true, "glow": true, "mirror": true, "lying": 150000,
		"flying": 8000, "pieces": 30, "corpses": 40, "gore": 1, "scenery": 180.0}, true)
	hi.chunk = 2
	_write(tmp, hi)
	var h := _load(tmp)
	_check(int(h.v.chunk) == 2, "Chunky on an unstamped High file: chosen by hand, so it stays (chunk %d)" % int(h.v.chunk))

	# 5. a file that is already today's Low: nothing moves
	var now := FIRST_APK.duplicate()
	now.chunk = 1
	now.jared = 2
	_write(tmp, now)
	var n := _load(tmp)
	_check(int(n.v.chunk) == 1 and is_equal_approx(float(n.v.scale), 0.67) and n.preset == "low",
		"a file already at today's Low: nothing moved (%s)" % n.preset)

	# 6. and a first run still comes up where it should on native
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	var f := _load(tmp)
	_check(f.first_run and int(f.v.chunk) == 1 and int(f.v.jared) == 2 and is_equal_approx(float(f.v.scale), 1.0)
		and is_equal_approx(float(f.v.scenery), 110.0),
		"a fresh native install, for comparison: Fine, chunky Jared, full size, 110 m")

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			_file_checks()
			m = arena.settings_menu
			# what the arena's own menu made of the real file at start-up (the APK's path, start to finish)
			_check(m.s.file == VoxelSettings.FILE, "the arena read the real settings file (%s)" % m.s.file)
			_check(int(m.s.v.chunk) == 1 and arena.chunk_wanted() == 1 and arena.chunk == 1,
				"the arena started with Fine enemies off that file (chunk %d, built %d)" % [int(m.s.v.chunk), arena.chunk])
			_check(int(m.s.v.jared) == 2 and VoxelArena.jared_chunk == 2,
				"... and your own Jared chunky, so the loading screen didn't build 650,000 cubes (jared %d)" % VoxelArena.jared_chunk)
			_check(not arena.rebuilding(), "... with nothing left rebuilding after the start-up")
			var cf := ConfigFile.new()
			cf.load(VoxelSettings.FILE)
			_check(int(cf.get_value("settings", "version", 0)) == VoxelSettings.VERSION,
				"... and the file written back with its stamp (version %d)" % int(cf.get_value("settings", "version", 0)))
			# the screen opened, the way the owner opened it
			var t0 := Time.get_ticks_usec()
			m.open()
			open_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			_check(m.is_open() and m._panel.visible, "the settings screen opens on the native path")
			_check(open_ms < FRAME_MS, "opening it came back in %.1f ms (budget %.0f)" % [open_ms, FRAME_MS])
			rebuilt = arena.rebuilding()
			_check(not rebuilt, "opening it started no character rebuild")
			last_us = Time.get_ticks_usec()
			step = 1
		1:
			var ms := float(Time.get_ticks_usec() - last_us) / 1000.0
			last_us = Time.get_ticks_usec()
			frames += 1
			if ms > worst:
				worst = ms
				worst_what = "frame %d" % frames
			if arena.rebuilding():
				rebuilt = true
			if frames >= WATCH_FRAMES:
				step = 2
		2:
			_check(worst < FREEZE_MS, "no frame with the screen up froze the game (worst %.1f ms over %d frames, %s)" % [
				worst, frames, worst_what])
			if worst > FRAME_MS:
				print("NOTE  the worst frame with the screen up was %.1f ms, over the %.0f ms budget" % [worst, FRAME_MS])
			_check(worst <= FRAME_MS, "every frame with the screen up stayed inside %.0f ms (worst %.1f ms)" % [FRAME_MS, worst])
			_check(not rebuilt, "the screen being up started no rebuild of its own")
			# MEDIUM: the shadows come on (seconds in one frame, on a phone's driver) and your own Jared is built
			# again. The warning has to stay up through the rebuild, not be replaced by its count.
			m._on_preset("medium")
			frames = 0
			step = 3
		3:
			frames += 1
			var line: String = arena._rb_label.text if arena._rb_label else ""
			if line.length() > said.length():
				said = line
			if frames > 400 or (frames > 8 and not arena.rebuilding() and arena.say_held == ""):
				step = 4
		4:
			_check(said.contains("Turning the shadows on"),
				"MEDIUM: the shadows' warning stayed up through the rebuild (\"%s\")" % said.replace("\n", " / "))
			_check(said.contains("Rebuilding the blocks"), "... with the rebuild's count under it, not over it")
			_check(arena.say_held == "" and int(m.s.v.chunk) == 1, "... and the line was taken away after")
			m.close()
			step = 99
		99:
			print("SETTINGS STALE: opening the screen took %.1f ms, the worst frame after it %.1f ms" % [open_ms, worst])
			print("SETTINGS STALE: %d passed, %d failed" % [passed, failed])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(VoxelSettings.FILE))
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_stale_tmp.cfg"))
			quit(1 if failed > 0 else 0)
			return true
	return false
