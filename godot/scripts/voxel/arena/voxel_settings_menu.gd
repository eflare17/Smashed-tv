class_name VoxelSettingsMenu
extends CanvasLayer
## The settings screen (Stage 9): a SETTINGS (F10) button under ONLINE (O) opens it. Your PC in a line (the processor,
## its threads, the memory, the graphics card); the presets LOW MEDIUM HIGH ULTRA EXTREME; every setting on its own below them
## (changing one makes it Custom); field of view, mouse speed, volume. Everything takes effect straight away and is
## saved. RUN BENCHMARK (on your own, not in co-op): each preset from Extreme down gets a fight to draw (24 enemies, shot
## at, set on fire and blown up by a grenade every couple of seconds, so the cubes flying and lying about and the cut-off
## pieces fill toward the preset's limits: the gore at full load; as fast as the PC can go: no frame cap, no vsync), and the highest one that holds 60 frames a
## second (19 frames in 20 inside 16.7 ms) is the one recommended; APPLY RECOMMENDED puts it on. The fight you were
## in is put back after. Esc stops the benchmark, or closes the screen. Owned by the voxel session.

const PINK := Color("#f7a8ff")
const GOLD := Color("#f6d17a")
const GOOD := Color("#7fd89a")
const BAD := Color("#ff7a7a")
const NAMES := {"low": "LOW", "medium": "MEDIUM", "high": "HIGH", "ultra": "ULTRA", "extreme": "EXTREME", "custom": "CUSTOM"}
const BENCH_BLAST := 2.0        # seconds between the benchmark's grenades
const BENCH_ENEMIES := 24

var arena: Node3D
var s := VoxelSettings.new()
var bench_warm := 1.5           # seconds settling in (shaders, meshes) before each preset's measured
var bench_measure := 4.0        # seconds measured
var target_ms := 1000.0 / 60.0
var recommended := ""
var bench_booms := 0            # the benchmark's grenades gone off (all runs)
var _btn: Button
var _panel: PanelContainer
var _hw: Label
var _now: Label
var _presets := {}              # name: Button
var _rows := {}                 # key: OptionButton / HSlider
var _vals := {}                 # slider key: its value's Label
var _bench_b: Button
var _apply_b: Button
var _result: Label
var _bench_lbl: Label
var _open := false
var _quiet := false             # (the rows being filled in: no change from that)
var _bench := {}                # running: {order, i, phase, t0, times, last_us, results, saved...}

## use_file: the saved settings put into effect (the real game; the tests keep the game as it was, High, untouched).
func setup(arena_: Node3D, use_file: bool) -> void:
	arena = arena_
	layer = 31
	if not use_file:
		s.file = ""
	else:
		s.load_file()
		var p := String(arena._opts.get("preset", ""))
		if p != "":
			s.set_preset(p)
		s.apply(arena)
		if s.first_run:
			s.save_file()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_btn = Button.new()
	_btn.text = "SETTINGS (F10)"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 14)
	_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_btn.offset_left = -12
	_btn.offset_right = -12
	_btn.offset_top = 48
	_btn.offset_bottom = 80
	_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_btn.pressed.connect(toggle)
	_btn.button_down.connect(func(): arena._ignore[MOUSE_BUTTON_LEFT] = true)     # (top-down: the click on it doesn't fire too)
	root.add_child(_btn)

	_bench_lbl = Label.new()
	_bench_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bench_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bench_lbl.offset_left = -360
	_bench_lbl.offset_right = 360
	_bench_lbl.offset_top = 70
	_bench_lbl.offset_bottom = 140
	_bench_lbl.add_theme_font_size_override("font_size", 26)
	_bench_lbl.add_theme_color_override("font_color", GOLD)
	_bench_lbl.add_theme_constant_override("outline_size", 6)
	_bench_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_bench_lbl.visible = false
	root.add_child(_bench_lbl)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.1, 0.95)
	sb.border_color = PINK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(780, 0)
	_panel.visible = false
	root.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", PINK)
	v.add_child(title)
	_hw = Label.new()
	_hw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hw.custom_minimum_size = Vector2(740, 0)
	_hw.add_theme_font_size_override("font_size", 13)
	_hw.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_hw.text = VoxelSettings.hardware()
	v.add_child(_hw)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	v.add_child(prow)
	for name in VoxelSettings.ORDER:
		var b := _button(prow, NAMES[name], _on_preset.bind(name))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		_presets[name] = b
	_now = Label.new()
	_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_now.add_theme_font_size_override("font_size", 14)
	_now.add_theme_color_override("font_color", GOLD)
	v.add_child(_now)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(748, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for key in VoxelSettings.CHOICES:
		var c: Array = VoxelSettings.CHOICES[key]
		_label(grid, c[0])
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(170, 32)
		ob.add_theme_font_size_override("font_size", 14)
		for t in c[2]:
			ob.add_item(t)
		ob.item_selected.connect(_on_choice.bind(key))
		grid.add_child(ob)
		_rows[key] = ob
	for sl in [["fov", "Field of view", 60.0, 110.0, 1.0], ["sens", "Mouse speed", 0.2, 3.0, 0.05], ["volume", "Volume", 0.0, 1.0, 0.05]]:
		_label(grid, sl[1])
		var h := HBoxContainer.new()
		var hs := HSlider.new()
		hs.min_value = sl[2]
		hs.max_value = sl[3]
		hs.step = sl[4]
		hs.custom_minimum_size = Vector2(120, 32)
		hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hs.value_changed.connect(_on_slider.bind(sl[0]))
		h.add_child(hs)
		var vl := Label.new()
		vl.custom_minimum_size = Vector2(46, 0)
		vl.add_theme_font_size_override("font_size", 14)
		h.add_child(vl)
		grid.add_child(h)
		_rows[sl[0]] = hs
		_vals[sl[0]] = vl

	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(740, 0)
	_result.add_theme_font_size_override("font_size", 14)
	v.add_child(_result)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	v.add_child(brow)
	_bench_b = _button(brow, "RUN BENCHMARK", bench_start)
	_bench_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_b = _button(brow, "APPLY RECOMMENDED", apply_recommended)
	_apply_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_b := _button(brow, "CLOSE", close)
	close_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not s.bench.is_empty():
		recommended = String(s.bench.get("pick", ""))
		_result.text = _bench_text(s.bench.get("results", {}), recommended)
	_refresh()

func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(190, 0)
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)

func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## The rows shown as the settings are.
func _refresh() -> void:
	_quiet = true
	for name in _presets:
		_presets[name].button_pressed = s.preset == name
	_now.text = "Now: %s%s" % [NAMES.get(s.preset, "CUSTOM"), ("   (recommended for this PC: %s)" % NAMES[recommended]) if recommended != "" else ""]
	for key in VoxelSettings.CHOICES:
		var vals: Array = VoxelSettings.CHOICES[key][1]
		var i := vals.find(s.v[key])
		if i < 0:                   # (a value between the menu's: the nearest)
			var bd := INF
			for j in vals.size():
				var d := absf(float(vals[j]) - float(s.v[key]))
				if d < bd:
					bd = d
					i = j
		(_rows[key] as OptionButton).select(i)
	for key in _vals:
		(_rows[key] as HSlider).value = float(s.v[key])
		_vals[key].text = _slider_text(key)
	var solo: bool = arena.net == null or arena.net.role == ""
	_bench_b.disabled = not solo or not _bench.is_empty()
	_bench_b.tooltip_text = "" if solo else "not in co-op (leave the game first)"
	_apply_b.disabled = recommended == "" or recommended == s.preset
	_quiet = false

func _slider_text(key: String) -> String:
	match key:
		"fov": return "%d°" % int(s.v.fov)
		"sens": return "%.2fx" % float(s.v.sens)
	return "%d%%" % int(round(float(s.v.volume) * 100.0))

func _changed() -> void:
	s.apply(arena)
	s.save_file()
	_refresh()

func _on_preset(name: String) -> void:
	if _quiet:
		return
	s.set_preset(name)
	_changed()

func _on_choice(i: int, key: String) -> void:
	if _quiet:
		return
	s.set_value(key, VoxelSettings.CHOICES[key][1][i])
	_changed()

func _on_slider(value: float, key: String) -> void:
	if _quiet:
		return
	s.set_value(key, value)
	s.apply(arena)
	_vals[key].text = _slider_text(key)
	s.save_file()

func apply_recommended() -> void:
	if recommended == "":
		return
	s.set_preset(recommended)
	_changed()

func is_open() -> bool:
	return _open or not _bench.is_empty()

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	if _open or not _bench.is_empty():
		return
	if arena.net_menu and arena.net_menu.is_open():
		arena.net_menu.close()
	if arena.games.seated > 0:
		arena.games.get_up()        # (on the couch the keys are the console's: up, so the menu's keys don't play the game)
	_open = true
	_panel.visible = true
	arena._let_go()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hw.text = VoxelSettings.hardware()
	_refresh()
	(_presets[s.preset] if _presets.has(s.preset) else _bench_b).grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	var fo := get_viewport().gui_get_focus_owner()
	if fo:
		fo.release_focus()
	if not arena.top_down and not arena._opts.has("auto") and not arena.inv_ui.is_open() and not arena.lock_view.is_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED     # (the backpack or a padlock still up underneath: the mouse stays theirs)

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.physical_keycode == KEY_ESCAPE and not _bench.is_empty():
		bench_stop()
		get_viewport().set_input_as_handled()
	elif e.physical_keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()
	elif e.physical_keycode == KEY_F10:
		toggle()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- the benchmark

## Each preset from Ultra down, till one holds 60 frames a second: that one recommended.
func bench_start() -> void:
	if not _bench.is_empty() or (arena.net and arena.net.role != ""):
		return
	if arena.mine and arena.mine.active:
		_result.text = "Not down the mine: come back up to the yard first."      # (the arena isn't drawn down there)
		return
	if arena.down_t > 0.0:
		_result.text = "Not while you're down: get up first."      # (the count would run out mid-run, the HP put back at 0)
		return
	if arena.lying > 0:
		arena.get_up()              # (from bed or the couch: up first, or the run measures the bedroom wall)
	if arena.games.seated > 0:
		arena.games.get_up()
	var alive := 0
	for b in arena.bodies:
		if b.alive:
			alive += 1
	_bench = {"order": VoxelSettings.ORDER.duplicate(), "i": -1, "results": {}, "saved": s.v.duplicate(),
		"saved_preset": s.preset, "alive": alive, "kinds": arena.living_kinds(), "godmode": arena.godmode, "frozen": arena.frozen,
		"at": arena.player.global_position, "yaw": arena.look_yaw, "pitch": arena.look_pitch,
		"top": arena.top_down, "hp": arena.player_hp}
	_bench.order.reverse()
	_open = false
	_panel.visible = false
	arena.godmode = true
	arena.frozen = false
	arena.top_down = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_bench_lbl.visible = true
	_next_preset()

func _next_preset() -> void:
	_bench.i += 1
	if _bench.i >= _bench.order.size():
		_bench_done()
		return
	var name: String = _bench.order[_bench.i]
	s.set_preset(name)
	s.v.fps = 0
	s.v.vsync = false
	s.apply(arena)
	arena._respawn_all(BENCH_ENEMIES)
	arena.player.global_position = Vector3(0, 0.05, 9)     # (on the arena's floor, wherever you were: a pit in the yard too)
	arena.player.velocity = Vector3.ZERO
	_bench.phase = "warm"
	_bench.t0 = Time.get_ticks_msec()
	_bench.times = PackedFloat32Array()
	_bench.last_us = Time.get_ticks_usec()
	_bench.fire_t = 0.0
	_bench.sg_t = 0.0
	_bench.burn_t = 0.0
	_bench.boom_t = 0.5

func bench_stop() -> void:
	if _bench.is_empty():
		return
	_bench.stopped = true
	_bench_done()

func _bench_done() -> void:
	var res: Dictionary = _bench.results
	var stopped := _bench.has("stopped")
	if not stopped:
		recommended = "low"         # (nothing held 60: the lowest)
		for name in VoxelSettings.ORDER:
			if res.has(name) and float(res[name][1]) <= target_ms:
				recommended = name      # (the highest that passed: ORDER runs low to extreme)
	# the game as it was
	s.v = (_bench.saved as Dictionary).duplicate()
	s.preset = s.which_preset()
	s.apply(arena)
	arena.pieces.trim()             # (Extreme's 90 pieces down to the cap put back)
	arena._respawn_all(-1 if not (_bench.kinds as Array).is_empty() else 1, _bench.kinds)
	arena.godmode = _bench.godmode
	arena.frozen = _bench.frozen
	arena.top_down = _bench.top
	arena.player.global_position = _bench.at
	arena.player.velocity = Vector3.ZERO
	arena.look_yaw = _bench.yaw
	arena.look_pitch = _bench.pitch
	arena.player_hp = _bench.hp
	if not stopped:
		s.bench = {"results": res, "pick": recommended, "hw": VoxelSettings.hardware()}
		s.save_file()
	_result.text = _bench_text(res, recommended) if not stopped else "Benchmark stopped."
	_bench = {}
	_bench_lbl.visible = false
	open()

func _bench_text(res: Dictionary, pick: String) -> String:
	var lines := []
	var order := VoxelSettings.ORDER.duplicate()
	order.reverse()             # (as it ran: Extreme first)
	for name in order:
		if res.has(name):
			var r: Array = res[name]
			lines.append("%s: %d fps average, %d fps at its slowest 5%% — %s" % [NAMES[name], int(r[0]), int(1000.0 / maxf(0.001, float(r[1]))),
				"smooth" if float(r[1]) <= target_ms else "too slow"])
	if pick != "":
		lines.append("Recommended for this PC: %s" % NAMES[pick])
	return "\n".join(lines)

func _process(_dt: float) -> void:
	if _bench.is_empty():
		return
	var now_us := Time.get_ticks_usec()
	var frame_ms := float(now_us - int(_bench.last_us)) / 1000.0
	_bench.last_us = now_us
	var name: String = _bench.order[_bench.i]
	var secs := float(Time.get_ticks_msec() - int(_bench.t0)) / 1000.0
	_fight(minf(frame_ms / 1000.0, 0.1))
	if _bench.phase == "warm":
		_bench_lbl.text = "BENCHMARK  %s (%d of %d)  getting ready...\nEsc stops" % [NAMES[name], _bench.i + 1, _bench.order.size()]
		if secs >= bench_warm:
			_bench.phase = "measure"
			_bench.t0 = Time.get_ticks_msec()
		return
	_bench.times.append(frame_ms)
	var fps := 1000.0 / maxf(0.001, frame_ms)
	_bench_lbl.text = "BENCHMARK  %s (%d of %d)  %d fps\nEsc stops" % [NAMES[name], _bench.i + 1, _bench.order.size(), int(fps)]
	if secs >= bench_measure:
		var t: PackedFloat32Array = _bench.times
		var total := 0.0
		for x in t:
			total += x
		var sorted := t.duplicate()
		sorted.sort()
		var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if sorted.size() > 0 else 1000.0
		var avg := 1000.0 * t.size() / maxf(1.0, total)
		_bench.results[name] = [avg, p95]
		print("VoxelSettings: benchmark %s: %.0f fps average, slowest 5%% %.1f ms" % [name, avg, p95])
		if p95 <= target_ms:
			_bench_done()           # (the highest that holds 60: no need to try lower)
		else:
			_next_preset()

func _fight(dt: float) -> void:
	VoxelBody.hit_k = 1.0           # (the same fight for everyone: the weapon bench's DAMAGE kept out)
	_fight_x(dt)
	VoxelBody.hit_k = arena.me.upg_k("damage")

# the fight to draw: the enemies kept at 24, the nearest shot at (a gun and a shotgun), now and then one set alight, and
# a grenade at the nearest one's feet every BENCH_BLAST seconds (the craters, torn limbs and cubes thrown up: the gore)
func _fight_x(dt: float) -> void:
	var alive := 0
	var best: VoxelBody = null
	var bd := INF
	var pp: Vector3 = arena.cam.global_position
	for b in arena.bodies:
		if b.alive:
			alive += 1
			var d: float = b.global_position.distance_to(pp)
			if d < bd:
				bd = d
				best = b
	if alive < BENCH_ENEMIES:
		arena.spawn(BENCH_ENEMIES - alive)
	arena.player_hp = VoxelArena.HP_MAX
	if best == null:
		return
	var target := best.global_position + Vector3(0, best.height * (0.62 if randf() < 0.7 else 0.9), 0)
	var to := target - pp
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var dir := to.normalized()
	_bench.fire_t -= dt
	_bench.sg_t -= dt
	_bench.burn_t -= dt
	if _bench.fire_t <= 0.0:
		_bench.fire_t = 0.1
		arena.fire(pp, dir, 1, 0.6, 1.9)
	if _bench.sg_t <= 0.0:
		_bench.sg_t = 1.2
		arena.fire(pp, dir, 9, 4.5, 1.4)
	if _bench.burn_t <= 0.0:
		_bench.burn_t = 0.5
		var h: Dictionary = best.trace(pp, dir, 30.0)
		if not h.is_empty():
			best.ignite(h.point, 0.085)
	_bench.boom_t -= dt
	if _bench.boom_t <= 0.0 and arena.melee.has("grenades"):
		_bench.boom_t = BENCH_BLAST
		var at := best.global_position + Vector3(randf_range(-0.4, 0.4), 0.3, randf_range(-0.4, 0.4))
		arena.melee.grenades.explode(at, "bench")
		bench_booms += 1
