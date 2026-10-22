extends SceneTree
## Stage 9, the settings and the benchmark (headless): a test's game is left as it was (High, nothing saved); each
## preset put on sets what it should (the cube size, the cubes' caps, pieces, corpses, the mirror, shadows, the
## picture's effects, the render scale, MSAA); one setting changed is Custom, changed back it's the preset again; saved
## and loaded the same; a guess and the PC's line; the screen opens on F10 (the game's keys and mouse its) and closes on
## Esc; a preset button; field of view; the benchmark runs each preset from Ultra down and stops at the first that holds
## 60 (with a lenient target: Ultra), or runs all four and recommends Low (an impossible one), the game put back as it
## was after (the settings, the enemies, god mode), APPLY RECOMMENDED; no benchmark in co-op. Prints "SETTINGS ok/FAIL
## ..." and "SETTINGS done N passed, M failed". Owned by the voxel session.

var arena: Node
var m: VoxelSettingsMenu
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v0 := {}

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("SETTINGS %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	root.push_input(e)
	var u := e.duplicate()
	u.pressed = false
	root.push_input(u)

func _alive() -> int:
	var n := 0
	for b in arena.bodies:
		if b.alive:
			n += 1
	return n

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	match step:
		0:
			m = arena.settings_menu
			var s := m.s
			check(s.preset == "high" and s.file == "" and arena.chunk == 1 and VoxelDebris.max_lie == 150000 and VoxelPieces.MAX_PIECES == 30 and VoxelArena.MAX_DEAD == 40,
				"a test's game: High, untouched, never saved")
			s.set_preset("low")
			s.apply(arena)
			var vp: Viewport = arena.get_viewport()
			check(arena.chunk == 2 and arena.debris.MAX == 3000 and arena.debris.MAX_LIE == 40000 and VoxelPieces.MAX_PIECES == 12 and VoxelArena.MAX_DEAD == 12,
				"Low: chunky cubes (2 pixels), 40k lying, 3k flying, 12 pieces, 12 corpses")
			check(not VoxelMirror.enabled and not arena.sun.shadow_enabled and not arena.world_env.ssao_enabled and not arena.world_env.glow_enabled and is_equal_approx(vp.scaling_3d_scale, 0.67),
				"Low: no mirror, shadows, ambient occlusion or glow; drawn at 67%")
			check(_alive() >= 1, "the cube size changed: the fight started over (%d enemies)" % _alive())
			s.set_value("glow", true)
			var custom := s.preset
			s.set_value("glow", false)
			check(custom == "custom" and s.preset == "low", "a setting changed by hand: Custom; changed back: Low again")
			s.set_preset("ultra")
			s.apply(arena)
			check(arena.chunk == 1 and arena.debris.MAX_LIE == 300000 and arena.debris.MAX == 12000 and VoxelPieces.MAX_PIECES == 45 and VoxelArena.MAX_DEAD == 60
				and vp.msaa_3d == Viewport.MSAA_4X and arena.sun.shadow_enabled and VoxelMirror.enabled,
				"Ultra: fine cubes, 300k lying, 12k flying, 45 pieces, 60 corpses, 4x MSAA, shadows, the mirror")
			var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
			check(arena.world_env.sdfgi_enabled == forward and arena.world_env.volumetric_fog_enabled == forward and vp.use_taa == forward,
				"Ultra's SDFGI, fog and TAA: on with Forward+ only (here: %s)" % RenderingServer.get_current_rendering_method())
			check(not arena.world_env.ssr_enabled and int(s.v.fx) == 0, "Ultra: no reflections, effects at Normal")
			s.set_preset("extreme")
			s.apply(arena)
			check(arena.debris.MAX_LIE == 600000 and arena.debris.MAX == 25000 and VoxelPieces.MAX_PIECES == 90 and VoxelArena.MAX_DEAD == 120
				and vp.msaa_3d == Viewport.MSAA_8X and is_equal_approx(vp.scaling_3d_scale, 1.5) and int(s.v.fx) == 1 and s.which_preset() == "extreme",
				"Extreme: 600k lying, 25k flying, 90 pieces, 120 corpses, 8x MSAA, drawn at 150%, effects at their best")
			check(arena.world_env.ssr_enabled == forward, "Extreme's reflections: on with Forward+ only")
			s.set_value("fx", 0)
			check(s.preset == "custom", "Extreme with the effects turned down: Custom")
			# saved and loaded
			s.set_preset("medium")
			s.set_value("fov", 95.0)
			s.set_value("pieces", 45)
			s.file = "user://settings_test.cfg"
			s.save_file()
			var s2 := VoxelSettings.new()
			s2.file = "user://settings_test.cfg"
			s2.load_file()
			check(s2.v == s.v and s2.preset == "custom" and not s2.first_run, "saved and loaded the same (Custom: Medium, 45 pieces, 95° view)")
			s.file = ""
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_test.cfg"))
			var s3 := VoxelSettings.new()
			s3.file = "user://settings_none.cfg"
			s3.load_file()
			check(s3.first_run and s3.preset in VoxelSettings.ORDER and VoxelSettings.hardware().length() > 10,
				"the first run: a preset guessed from the graphics card (%s); the PC: %s" % [s3.preset, VoxelSettings.hardware()])
			s.apply(arena)
			mark = t
			step = 1
		1:
			if t - mark > 0.3:
				check(is_equal_approx(arena.cam.fov, 95.0) and is_equal_approx(arena.base_fov, 95.0), "the field of view: 95°")
				_key(KEY_F10)
				mark = t
				step = 2
		2:
			if t - mark > 0.2:
				check(m.is_open() and m._panel.visible, "F10: the settings screen opens")
				var p0: Vector3 = arena.player.global_position
				Input.action_press("ui_up")         # (nothing: the screen has the keys)
				v0.p0 = p0
				m._on_preset("low")
				check(m.s.preset == "low" and arena.chunk == 2 and m._presets.low.button_pressed and not m._presets.high.button_pressed,
					"the LOW button: Low on, shown pressed")
				m._on_choice(1, "glow")
				check(m.s.preset == "custom" and arena.world_env.glow_enabled and m._now.text.contains("CUSTOM"), "a row changed: glow on, Custom")
				m._on_preset("high")
				_key(KEY_ESCAPE)
				mark = t
				step = 3
		3:
			if t - mark > 0.2:
				Input.action_release("ui_up")
				check(not m.is_open() and arena.chunk == 1, "Esc closes it (High back on)")
				# no benchmark in co-op
				arena.net.role = "host"
				m.bench_start()
				check(m._bench.is_empty(), "no benchmark in co-op")
				arena.net.role = ""
				# the benchmark, a lenient target: Ultra holds it
				arena.spawn(3)
				v0.alive = _alive()
				v0.saved = m.s.v.duplicate()
				v0.god = arena.godmode
				m.bench_warm = 0.3
				m.bench_measure = 0.6
				m.target_ms = 10000.0
				m.bench_start()
				check(m.is_open() and m._bench_lbl.visible and not m._panel.visible, "the benchmark: running, the screen out of the way")
				mark = t
				step = 4
		4:
			if m._bench.has("i") and m._bench.i == 0 and m._bench.get("phase") == "measure" and not v0.has("mid"):
				v0.mid = true
				check(arena.chunk == 1 and VoxelArena.MAX_DEAD == 120 and arena.godmode and _alive() >= VoxelSettingsMenu.BENCH_ENEMIES - 2,
					"Extreme put on to be measured first: 24 enemies (%d), god mode" % _alive())
			if m._bench.is_empty():
				var res: Dictionary = m.s.bench.get("results", {})
				check(m.recommended == "extreme" and res.size() == 1 and res.has("extreme"), "a fast PC: Extreme holds 60, recommended, nothing lower tried")
				check(m.s.v == v0.saved and arena.godmode == v0.god and _alive() == int(v0.alive) and arena.chunk == 1,
					"after: the settings, the enemies (%d), god mode as they were" % _alive())
				check(m._panel.visible and m._result.text.contains("Recommended for this PC: EXTREME") and not m._apply_b.disabled, "the results shown, APPLY RECOMMENDED ready")
				m.apply_recommended()
				check(m.s.preset == "extreme" and VoxelArena.MAX_DEAD == 120, "APPLY RECOMMENDED: Extreme on")
				m.s.set_preset("high")
				m.s.apply(arena)
				m.close()
				# an impossible target: nothing holds it, all five tried, Low recommended
				m.target_ms = 0.0001
				m.bench_start()
				mark = t
				step = 5
			elif t - mark > 20.0:
				check(false, "the benchmark never finished")
				step = 99
		5:
			if m._bench.has("i") and int(m._bench.i) == 4 and not v0.has("low_on"):
				v0.low_on = true
				check(arena.chunk == 2 and VoxelArena.MAX_DEAD == 12, "Low, tried last: chunky cubes")
			if m._bench.is_empty():
				var res: Dictionary = m.s.bench.get("results", {})
				check(m.recommended == "low" and res.size() == 5, "a slow PC: all five tried (%d), Low recommended" % res.size())
				check(m.bench_booms > 0, "the benchmark's grenades went off (%d)" % m.bench_booms)
				check(m.s.preset == "high" and arena.chunk == 1 and VoxelArena.MAX_DEAD == 40, "High back on after")
				# stopped part way: nothing changes
				m.close()
				v0.rec = m.recommended
				m.bench_start()
				mark = t
				step = 6
			elif t - mark > 30.0:
				check(false, "the benchmark (all five) never finished")
				step = 99
		6:
			if t - mark > 0.5:
				_key(KEY_ESCAPE)
				mark = t
				step = 7
		7:
			if t - mark > 0.3:
				check(m._bench.is_empty() and m.recommended == v0.rec and m._result.text.contains("stopped") and m.s.preset == "high",
					"Esc stops the benchmark: High kept, the last recommendation kept")
				step = 99
		99:
			print("SETTINGS done %d passed, %d failed" % [passed, failed])
			return true
	return false
