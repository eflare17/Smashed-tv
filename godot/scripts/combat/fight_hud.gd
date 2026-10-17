class_name FightHud
extends CanvasLayer
## The fight's screen layer (godot/specs/modes_hud.md 3-4, 7; weapons.md 11.6, 12, 13.3): the weapon bar (1-6,
## click or tap, drag one slot onto another to swap, saved), the wallet and ammo, the run's top line ("wave N   M
## left   K killed"), the wave banner in the breathers, the big gold banner, the game-over screen, the mode picker
## and Start button in the lobby, the floating words ($3, SPLAT!, +2), Gothica's and Gary's speech, "need a spud",
## the machines' prompts; in first person the blasters in your hands with their kick, flash and tracers, the
## full-view flash for other guns, your own pips and a red pulse while you can't be hurt; on a phone the twin
## sticks (left: walk, right: aim and fire; a second finger on a held side rolls), tap to throw / tap to fire,
## and FIRE in first person.
##
## Laid out in the HTML game's 860 x 520 canvas units, scaled to the screen's height (things on the left stay
## left, on the right stay right, centred stay centred).

const GOLD := Color("#f6d17a")
const INK := Color(20 / 255.0, 22 / 255.0, 28 / 255.0)
const STICK_MAX := 52.0
## Pixels the run line and wallets sit below the HTML's spot: the farm's day line is up there now.
const TOP_PAD := 22.0

var fight: Fight
var _draw_c: _Draw
var _bar: _Hotbar
var _picker: HBoxContainer
var _mode_lbl: Label
var _start: Button
var _banner := ""
var _banner_until := 0
var _flash_slot := -1
var _flash_until := 0
var _hands: Texture2D
var _tracers: Array = []          # [side, t0 ms]
var _muzzle_seen := 0.0
var _walk_ph := 0.0
var _move_k := 0.0
var _last_odo := 0.0
var _launcher_hint_t := -1.0
var _fp_hint_t := 0.0
# touch
var sticks := {"move": {"on": false, "id": -1, "o": Vector2.ZERO, "d": Vector2.ZERO, "t0": 0, "moved": 0.0},
	"aim": {"on": false, "id": -1, "o": Vector2.ZERO, "d": Vector2.ZERO, "t0": 0, "moved": 0.0}}
var _fire_id := -1
## The fight's own twin sticks and FIRE: off now that milestone 1's TouchControls drive the actions (its aim stick
## sets Player.aim_override, its FIRE presses "fire"); the launcher's tap-to-fire and first-person look in a run
## (the shared layer only turns the view while the Player's controls are on) stay here.
var own_sticks := false
var help_on := false
var _help_auto := -1.0             ## seconds of the help shown by itself the first time a pad is used
var _pad_seen := false
const HELP_KEYS := [["W A S D", "Move"], ["Mouse", "Aim  (first person: look)"], ["Click (hold)", "Fire"],
	["Shift", "Dive roll"], ["E", "Use: pick up, sit, eat, play, pull, throw"], ["1 – 6", "Change weapon"],
	["Enter", "Start the run"], ["R", "Restart"], ["V", "First person"], ["Z", "Zoom"], ["Tab", "Show / hide this list"],
	["P", "Add a player 2 on this keyboard (arrows + space)"]]
const HELP_PAD := [["Left stick", "Move"], ["Right stick", "Aim  (first person: look)"], ["RT", "Fire"],
	["B  /  RB  /  LT", "Dive roll"], ["A", "Use: pick up, sit, eat, play, pull, throw"],
	["LB  /  Y,  d-pad left / right", "Change weapon"], ["Menu", "Start the run  (restart when it's over)"],
	["View", "First person"], ["D-pad up", "Zoom"], ["D-pad down", "Show / hide this list"]]
var _touch_driving := false

func _ready() -> void:
	layer = 9
	_draw_c = _Draw.new()
	_draw_c.hud = self
	_draw_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw_c)
	_bar = _Hotbar.new()
	_bar.hud = self
	add_child(_bar)
	# the mode picker and Start (the HTML's buttons over the canvas)
	_picker = HBoxContainer.new()
	_picker.add_theme_constant_override("separation", 4)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_picker.position = Vector2(0, 10)
	add_child(_picker)
	var prev := _btn("<", func(): fight.step_mode(-1))
	_mode_lbl = Label.new()
	_mode_lbl.custom_minimum_size = Vector2(130, 0)
	_mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_lbl.add_theme_color_override("font_color", GOLD)
	_mode_lbl.add_theme_font_size_override("font_size", 15)
	_picker.add_child(prev)
	_picker.add_child(_mode_lbl)
	_picker.add_child(_btn(">", func(): fight.step_mode(1)))
	_start = _btn("Start (Enter)", func(): fight.start_run())
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#e0473f")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_start.add_theme_stylebox_override("normal", sb)
	_start.add_theme_stylebox_override("hover", sb)
	_start.add_theme_stylebox_override("pressed", sb)
	_picker.add_child(_start)
	var hp = GameData.manifest.get("FP_BLASTER.img.src")
	if hp is String and ResourceLoader.exists("res://" + hp):
		_hands = GameData.tex(hp)

func fp_hint_on() -> bool:
	return fight.is_fp() and fight.touch_seen

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	return b

func show_banner(text: String, secs: float) -> void:
	_banner = text
	_banner_until = Time.get_ticks_msec() + int(secs * 1000.0)

func flash_slot(i: int) -> void:
	_flash_slot = i
	_flash_until = Time.get_ticks_msec() + 350

## The HTML canvas's scale on this screen (860 x 520 units, fitted to the height).
func sc() -> float:
	return _draw_c.size.y / 520.0

## An HTML canvas x on this screen: left things stay left, right things stay right, the middle stays centred.
func hx(x: float) -> float:
	var s := sc()
	var w := _draw_c.size.x
	if x < 300.0:
		return x * s
	if x > 560.0:
		return w - (860.0 - x) * s
	return w / 2.0 + (x - 430.0) * s

func _process(delta: float) -> void:
	if fight == null:
		return
	var s := fight.sim
	_picker.visible = not s.started
	_mode_lbl.text = Fight.mode_name(fight.mode)
	_picker.position.x = (_draw_c.size.x - _picker.size.x) / 2.0
	_picker.position.y = 10.0
	var f := fight.f
	# first-person hands: the walk bob and new shots' tracers
	var od := f.odo if s.started else fight.player.odo
	_walk_ph += absf(od - _last_odo) / 30.0 * PI
	_last_odo = od
	var mv := f.moving if s.started else fight.player.moving
	_move_k += ((1.0 if mv else 0.0) - _move_k) * minf(1.0, delta * 8.0)
	if f.muzzle > _muzzle_seen + 0.0001 and f.weapon == "blaster":
		_tracers.append([0 if f.last_gun == 0 else 1, Time.get_ticks_msec()])
	_muzzle_seen = f.muzzle
	if f.weapon == "launcher" and f.rockets == int(s.tv("launcherRounds", 3)) and fight.touch_seen:
		if _launcher_hint_t < 0.0:
			_launcher_hint_t = 0.0
		_launcher_hint_t += delta
	else:
		_launcher_hint_t = -1.0
	if fight.is_fp() and fight.touch_seen:
		_fp_hint_t += delta
	if _help_auto > 0.0:
		_help_auto -= delta
	_bar.visible = not s.over and not (s.secret and s.secret.room)
	# with the pointer held (first person) a click is always a shot, never a button (b307)
	var held := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE if held else Control.MOUSE_FILTER_STOP
	for b in _picker.get_children():
		if b is Control:
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE if held else Control.MOUSE_FILTER_STOP
	var bs := 54.0 * sc()
	_bar.size = Vector2(bs * 6.0 + 8.0 * sc() * 5.0, bs)
	_bar.position = Vector2((_draw_c.size.x - _bar.size.x) / 2.0, 440.0 * sc())
	_bar.queue_redraw()
	_draw_c.queue_redraw()
	_apply_touch_move()

# ---------------------------------------------------------------- touch (modes_hud.md 7)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help") and not event.is_echo():
		help_on = not help_on
		_help_auto = -1.0
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if fight == null:
		return
	if (event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)) and not _pad_seen:
		_pad_seen = true
		_help_auto = 7.0
	if event is InputEventScreenTouch:
		fight.touch_seen = true
		var p: Vector2 = event.position
		if not own_sticks:
			_shared_touch(event)
			return
		if event.pressed:
			_touch_down(event.index, p)
		else:
			_touch_up(event.index, p)
	elif event is InputEventScreenDrag and not own_sticks:
		if fight.is_fp() and fight.sim.started and event.position.x > _draw_c.size.x * 0.45 and fight.player:
			var kk := 720.0 / maxf(1.0, _draw_c.size.y)
			fight.player.look_ang = wrapf(fight.player.look_ang + event.screen_relative.x * 0.0075 * kk, -PI, PI)
			fight.player.look_y = clampf(fight.player.look_y + event.screen_relative.y * 0.006 * kk, -0.6, 0.6)
		var td: Dictionary = _taps.get(event.index, {})
		if not td.is_empty():
			td.moved = maxf(td.moved, (event.position - td.at).length())
	elif event is InputEventScreenDrag:
		for k in sticks:
			var st: Dictionary = sticks[k]
			if st.on and st.id == event.index:
				var d: Vector2 = event.position - st.o
				st.moved = maxf(st.moved, d.length())
				var lim := STICK_MAX * sc()
				if d.length() > lim:
					d = d.normalized() * lim
				st.d = d / lim
				if k == "aim":
					fight.touch_aim = st.d
		if fight.is_fp() and event.index != sticks.move.id and event.index != _fire_id and fight.player:
			fight.player.look_ang = wrapf(fight.player.look_ang + event.relative.x * 0.0075, -PI, PI)
			fight.player.look_y = clampf(fight.player.look_y + event.relative.y * 0.004, -0.6, 0.6)

var _taps: Dictionary = {}

# With the shared touch layer: a quick tap (< 300 ms, moved < 12) fires the launcher at that spot; a quick tap with
# the potato throws it there (weapons 6, modes 7.2); a tap on the game-over words restarts.
func _shared_touch(event: InputEventScreenTouch) -> void:
	var s := fight.sim
	var p := event.position
	if event.pressed:
		if s.over:
			if absf(p.x - _draw_c.size.x / 2.0) < 220.0 * sc() and absf(p.y - 260.0 * sc()) < 60.0 * sc():
				fight.restart()
			return
		_taps[event.index] = {"at": p, "t0": Time.get_ticks_msec(), "moved": 0.0}
		return
	var td: Dictionary = _taps.get(event.index, {})
	_taps.erase(event.index)
	if td.is_empty() or _on_ui(p):
		return
	if Time.get_ticks_msec() - int(td.t0) < 300 and float(td.moved) < 12.0 and not fight.is_fp():
		var g = fight.screen_to_ground(p)
		if g == null:
			return
		if fight.f.weapon == "launcher":
			fight.touch_tap_id += 1
			fight.touch_tap_spot = Vector2(g.x, g.y)
		elif fight.f.weapon == "lob":
			fight.touch_tap_spot = Vector2(g.x, g.y)
			get_tree().create_timer(0.13).timeout.connect(func(): fight.touch_tap_spot = null)

func _on_ui(p: Vector2) -> bool:
	if _bar.visible and _bar.get_global_rect().grow(4).has_point(p):
		return true
	if _picker.visible and _picker.get_global_rect().has_point(p):
		return true
	var vp := _draw_c.size
	# the milestone 1 round E button (bottom right) and the character buttons (top left)
	if p.distance_to(Vector2(vp.x - 86, vp.y - 190)) < 56:
		return true
	if p.y < 48 and p.x < 420:
		return true
	return false

func _touch_down(id: int, p: Vector2) -> void:
	var s := fight.sim
	if s.over:
		if absf(p.x - _draw_c.size.x / 2.0) < 220.0 * sc() and absf(p.y - 260.0 * sc()) < 60.0 * sc():
			fight.restart()
		return
	if _on_ui(p):
		return
	var w := _draw_c.size.x
	if fight.is_fp() and p.distance_to(Vector2(hx(705), 405 * sc())) < 50.0 * sc():
		_fire_id = id
		fight.touch_fire = true
		return
	var side := "move" if p.x < w / 2.0 else "aim"
	var st: Dictionary = sticks[side]
	if st.on or (sticks.move.on and sticks.aim.on):
		fight._roll_tap = true                # a second finger on a held side: roll
		if not s.started:
			Input.action_press("roll")
			get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("roll"))
		return
	if fight.is_fp() and side == "aim":
		return                                # first person: the right half looks round
	st.on = true
	st.id = id
	st.o = p
	st.d = Vector2.ZERO
	st.t0 = Time.get_ticks_msec()
	st.moved = 0.0
	if side == "aim":
		fight.touch_aim_on = fight.f.weapon != "launcher" and fight.f.weapon != "lob"
		fight.touch_aim = Vector2.ZERO
		if fight.f.weapon == "lob":
			var g = fight.screen_to_ground(p)
			if g != null:
				fight.touch_tap_spot = Vector2(g.x, g.y)

func _touch_up(id: int, p: Vector2) -> void:
	if id == _fire_id:
		_fire_id = -1
		fight.touch_fire = false
		return
	for k in sticks:
		var st: Dictionary = sticks[k]
		if st.on and st.id == id:
			var quick: bool = Time.get_ticks_msec() - int(st.t0) < 300 and float(st.moved) < 12.0
			st.on = false
			st.id = -1
			st.d = Vector2.ZERO
			if k == "aim":
				fight.touch_aim_on = false
				fight.touch_aim = Vector2.ZERO
				if fight.f.weapon == "lob":
					fight.touch_tap_spot = null
			if quick and fight.f.weapon == "launcher":
				var g = fight.screen_to_ground(p)
				if g != null:
					fight.touch_tap_id += 1
					fight.touch_tap_spot = Vector2(g.x, g.y)

func _apply_touch_move() -> void:
	var st: Dictionary = sticks.move
	var d: Vector2 = st.d if st.on and st.d.length() > 0.12 else Vector2.ZERO
	if d == Vector2.ZERO:
		if _touch_driving:
			for a in ["move_left", "move_right", "move_up", "move_down"]:
				Input.action_release(a)
			_touch_driving = false
		return
	_touch_driving = true
	for a in [["move_left", -d.x], ["move_right", d.x], ["move_up", -d.y], ["move_down", d.y]]:
		if a[1] > 0.0:
			Input.action_press(a[0], a[1])
		else:
			Input.action_release(a[0])

# ---------------------------------------------------------------- drawing

class _Draw extends Control:
	var hud: FightHud

	func _draw() -> void:
		if hud and hud.fight:
			hud.draw_all(self)

## A leading ● ○ ☢ ∞ drawn as shapes (the default font hasn't got them), then the text after it.
static func glyph(c: CanvasItem, pos: Vector2, txt: String, fs: int, col: Color, font: Font) -> String:
	if txt.is_empty():
		return txt
	var g := txt[0]
	if not g in ["●", "○", "☢", "∞"]:
		return txt
	var r := fs * 0.32
	var ctr := pos + Vector2(r, -fs * 0.33)
	match g:
		"●":
			c.draw_circle(ctr, r, col)
		"○":
			c.draw_arc(ctr, r * 0.85, 0, TAU, 20, col, maxf(1.0, fs * 0.1), true)
		"☢":
			c.draw_circle(ctr, r * 1.05, col)
			for i in 3:
				var a0 := -PI / 2.0 + i * TAU / 3.0 + PI / 3.0
				var pts := PackedVector2Array([ctr])
				for k in 7:
					pts.append(ctr + Vector2.from_angle(a0 + k * (PI / 3.0) / 6.0) * r * 0.9)
				c.draw_colored_polygon(pts, Color(0.08, 0.08, 0.1, col.a))
			c.draw_circle(ctr, r * 0.22, col)
		"∞":
			c.draw_arc(ctr - Vector2(r * 0.55, 0), r * 0.55, 0, TAU, 16, col, maxf(1.0, fs * 0.1), true)
			c.draw_arc(ctr + Vector2(r * 0.55, 0), r * 0.55, 0, TAU, 16, col, maxf(1.0, fs * 0.1), true)
	return "    " + txt.substr(1).strip_edges(true, false) if txt.length() > 1 else ""

func _text(c: Control, x: float, y: float, txt: String, size: int, col: Color, align := 0, outline := 0, ocol := Color(0, 0, 0, 0.6)) -> void:
	var font := c.get_theme_default_font()
	var fs := int(size * sc())
	if txt.length() > 0 and txt[0] in ["●", "○", "☢", "∞"]:
		txt = glyph(c, Vector2(x, y), txt, fs, col, font)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var px := x - (w / 2.0 if align == 1 else (w if align == 2 else 0.0))
	if outline > 0:
		c.draw_string_outline(font, Vector2(px, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(outline * sc()), ocol)
	else:
		c.draw_string(font, Vector2(px + 1, y + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * col.a))
	c.draw_string(font, Vector2(px, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## A world point (HTML x, y, z) on the screen, or null if it's behind the camera.
func to_screen(x: float, y: float, z: float):
	var cam := fight.get_viewport().get_camera_3d()
	if cam == null:
		return null
	var p := GameData.world_to_3d(x, y, z)
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)

func draw_all(c: Control) -> void:
	var s := fight.sim
	var f := fight.f
	var k := sc()
	var vp := c.size
	var fp := fight.is_fp()
	if s.secret and s.secret.phase != "done":
		_draw_secret(c, s.secret)
		return
	if fp:
		_draw_fp(c)
	# the run's top line (26, 38) and the wallet (26, 64) + ammo (88, 64)
	if s.started:
		var killed := 0
		for p: FT.Fighter in s.players:
			killed += p.kills
		_text(c, 26 * k, 38 * k + 20 + TOP_PAD, "wave %d   %d left   %d killed" % [s.wave, s.enemies.size(), killed], 12, Color("#a3aabb"), 0, 4, Color(0, 0, 0, 0.6))
	var y0 := 64 * k + 20 + TOP_PAD
	for p: FT.Fighter in s.players:
		var pc: Color = FightSim.P_COLOURS[p.id % 2]
		_text(c, 26 * k, y0, "$%d" % p.coins, 17, pc, 0, 4, Color(0, 0, 0, 0.55))
		var ax := 26 * k + c.get_theme_default_font().get_string_size("$%d" % p.coins, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * k)).x + 14 * k
		ax = maxf(ax, 88 * k)
		if p.weapon == "launcher":
			_text(c, ax, y0, "☢ %d" % p.rockets, 17, GOLD if p.rockets > 0 else Color("#e0473f"), 0, 4, Color(0, 0, 0, 0.55))
		elif WeaponDefs.uses_ammo(p.weapon):
			if p.ammo > 0:
				_text(c, ax, y0, "● %d" % p.ammo, 17, Color("#d8b878"), 0, 4, Color(0, 0, 0, 0.55))
			else:
				_text(c, ax, y0, "○ 0", 17, Color("#e0473f"), 0, 4, Color(0, 0, 0, 0.55))
		y0 += 22 * k
	# floaters, bubbles, words over heads (world space)
	for fl: FT.Floater in s.floaters:
		var sp = to_screen(fl.x, fl.y, 40.0 + fl.t * 30.0) if fp else to_screen(fl.x, fl.y, 30.0)
		if sp == null:
			continue
		var a := 1.0 if fl.t < 0.6 else 1.0 - (fl.t - 0.6) / 0.3
		_text(c, sp.x, sp.y, fl.text, 14, Color(fl.col, a), 1)
	if f.alive and f.dry_hint > 0.0 and WeaponDefs.uses_ammo(f.weapon) and f.ammo <= 0 and not fp:
		var sp2 = to_screen(f.x, f.y, 100.0)
		if sp2 != null:
			_text(c, sp2.x, sp2.y, "need a spud", 12, Color("#d8b878", minf(1.0, f.dry_hint * 2.0)), 1)
	elif f.alive and f.dry_hint > 0.0 and fp and WeaponDefs.uses_ammo(f.weapon) and f.ammo <= 0:
		_text(c, vp.x / 2.0, vp.y / 2.0 + 60 * k, "need a spud", 14, Color("#d8b878", minf(1.0, f.dry_hint * 2.0)), 1)
	if s.goth and s.goth.bubble != "":
		_bubble(c, s.goth.x, s.goth.y, 92.0, s.goth.bubble, clampf(minf((s.goth.bubble_dur - s.goth.bubble_t) / 0.4, s.goth.bubble_t / 0.12), 0.0, 1.0), Color("#fffdf6"))
	if s.goth and s.goth.hp > 0 and s.goth.carrier < 0 and ProtectSim.can_carry(s, f) and not fp:
		var sp3 = to_screen(s.goth.x, s.goth.y, 110.0)
		if sp3 != null:
			_text(c, sp3.x, sp3.y, ("A" if _pad_last() else "E") + ": pick up", 11, Color.WHITE, 1)
	var j := s.janitor
	if s.started and j.phase == "gripe":
		_bubble(c, j.x, j.y, 88.0, "HEY! I'M JUST TRYING TO DO MY JOB!", 1.0, Color("#f2efe6"))
	elif s.started and j.phase == "giveup" and j.t > 0.3:
		var sp4 = to_screen(j.x, j.y, 70.0)
		if sp4 != null:
			_text(c, sp4.x, sp4.y, "...", 13, Color("#8b93a4"), 1)
	_machine_prompts(c)
	# the wave banner in the breathers
	if s.started and not s.over and s.breather > 0.0:
		_text(c, vp.x / 2.0, 250 * k, "WAVE %d" % (s.wave + 1), 26, Color("#cfd4de"), 1, 5, Color(0, 0, 0, 0.5))
		_text(c, vp.x / 2.0, 276 * k, EnemySim.incoming_text(s, s.wave + 1), 14, Color("#9aa1b2"), 1)
		if s.goth and s.wave == 0:
			var line := "keep Gothica alive  ·  potatoes heal her"
			if f.ch in ProtectSim.CARRIERS:
				line += "  ·  E picks her up"
			_text(c, vp.x / 2.0, 298 * k, line, 14, Color("#f7a8ff"), 1)
	if _launcher_hint_t >= 0.0 and _launcher_hint_t < 4.0:
		var a2 := minf(1.0, _launcher_hint_t / 0.25) * minf(1.0, (4.0 - _launcher_hint_t) / 0.5)
		_text(c, vp.x / 2.0, 124 * k, "TAP WHERE YOU WANT IT TO LAND", 22, Color(GOLD, a2), 1, 5, Color(INK, 0.9 * a2))
	if fp and fight.touch_seen and _fp_hint_t < 6.0:
		var a3 := minf(1.0, (6.0 - _fp_hint_t) / 1.5)
		_text(c, vp.x * 0.25, 156 * k, "thumb here to walk", 14, Color(GOLD, a3), 1)
		_text(c, vp.x * 0.75, 156 * k, "drag here to look", 14, Color(GOLD, a3), 1)
	# the nuke's white-out
	if s.nuke and s.nuke.boom:
		var nf := minf(0.999, s.nuke.t / s.tv("nukeBoom", 0.85))
		if nf < 0.22:
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 0.965, 0.88, 0.85 * (1.0 - nf / 0.22)))
	# touch sticks
	for key in sticks:
		var st: Dictionary = sticks[key]
		if st.on:
			c.draw_arc(st.o, STICK_MAX * k, 0, TAU, 40, Color("#4b5468"), 2.0, true)
			c.draw_circle(st.o + st.d * STICK_MAX * k, 20 * k, Color(0.88, 0.28, 0.25, 0.55) if key == "move" else Color(0.96, 0.82, 0.48, 0.55))
	if fp and fight.touch_seen and own_sticks:
		var fc := Vector2(hx(705), 405 * k)
		var held := fight.touch_fire
		c.draw_circle(fc, 40 * k, Color(0.88, 0.28, 0.25, 0.6) if held else Color(14 / 255.0, 16 / 255.0, 22 / 255.0, 0.5))
		c.draw_arc(fc, 40 * k, 0, TAU, 40, Color("#ffd0c8") if held else Color("#e0473f"), 2.5, true)
		_text(c, fc.x, fc.y + 5 * k, "FIRE", 11, Color.WHITE if held else Color("#ffb3a8"), 1)
	if help_on or _help_auto > 0.0:
		_draw_help(c, minf(1.0, _help_auto / 0.6) if (not help_on and _help_auto > 0.0) else 1.0)
	# the big banner
	if Time.get_ticks_msec() < _banner_until:
		_text(c, vp.x / 2.0, 90 * k + 12 * k, _banner, 34, GOLD, 1, 5, Color(INK, 0.9))
	if s.over:
		_game_over(c)

# The bonus room's words (gore_loot 14.5): bold monospace with a dark outline.
func _stext(c: Control, y: float, txt: String, size: int, col := Color("#d9f9ff")) -> void:
	_text(c, c.size.x / 2.0, y * sc(), txt, size, col, 1, 4, Color("#111620"))

func _draw_secret(c: Control, sec: FT.Secret) -> void:
	var s := fight.sim
	var t := sec.t
	var vp := c.size
	var k := sc()
	match sec.phase:
		"intro":
			var sp = to_screen(s.slot.x, s.slot.y + 120.0, 0.0)
			if sp != null:
				if t > 3.6 and t < 4.15:
					_text(c, sp.x, sp.y, "...", 18, Color("#d9f9ff"), 1, 4, Color("#111620"))
				if t > 4.15 and t < 4.55:
					_text(c, sp.x, sp.y - 60 * k, "POP!", 24, Color("#c5ffff"), 1, 4, Color("#111620"))
			if t > 5.6:
				c.draw_rect(Rect2(Vector2.ZERO, vp), Color(5 / 255.0, 9 / 255.0, 18 / 255.0, minf(1.0, (t - 5.6) / 0.5)))
		"landing":
			var f := minf(1.0, t / 0.85)
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(8 / 255.0, 15 / 255.0, 24 / 255.0, (1.0 - f) * 0.7))
			_stext(c, 208, "YOU ARE THE PRIZE", 22, Color("#e7d387"))
		"payout":
			_stext(c, 320, "THANK YOU FOR YOUR CUSTOM" if sec.survived else "FAULT DETECTED — EJECTING", 20)
			if t > 1.05:
				c.draw_rect(Rect2(Vector2.ZERO, vp), Color(190 / 255.0, 250 / 255.0, 1.0, minf(1.0, (t - 1.05) / 0.55)))
		"return":
			_stext(c, 350, "PLEASE CHECK THE PAYOUT TRAY", 18, GOLD)
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(190 / 255.0, 250 / 255.0, 1.0, maxf(0.0, 1.0 - 3.0 * t)))
	if sec.room:
		var top := Rect2(vp.x / 2.0 - 147 * k, 87 * k, 294 * k, 27 * k)
		c.draw_rect(top, Color(8 / 255.0, 15 / 255.0, 24 / 255.0, 0.92))
		var head := "INSIDE THE MACHINE"
		if sec.phase == "bonus":
			head = "HOUSE MONEY  %ds" % int(ceil(maxf(0.0, 20.0 - t)))
		elif sec.phase == "payout":
			head = "PAYOUT"
		_stext(c, 107, head, 17)
		var bot := Rect2(vp.x / 2.0 - 250 * k, 482 * k, 500 * k, 33 * k)
		c.draw_rect(bot, Color(8 / 255.0, 15 / 255.0, 24 / 255.0, 0.9))
		_stext(c, 496, "BANKED $%d" % sec.earned + ("  + $10 EACH" if sec.phase == "payout" and sec.survived else ""), 13, Color("#b1efb7"))
		_stext(c, 509, "COLLECT CASH  /  SHOOT SKULLS  /  DODGE STAMPS", 10, Color("#9db7c3"))
		for fl: FT.Floater in s.floaters:
			var p = to_screen(fl.x, fl.y, 30.0)
			if p != null:
				_text(c, p.x, p.y, fl.text, 14, fl.col, 1)

# The controls help (drawControlsHelp): a panel of keys and what they do, for the device last used.
func _draw_help(c: Control, alpha: float) -> void:
	var k := sc()
	var pad := _pad_last()
	var rows: Array = HELP_PAD if pad else HELP_KEYS
	var w := 470.0 * k
	var h := (54.0 + rows.size() * 22.0) * k
	var r := Rect2((c.size.x - w) / 2.0, maxf(8.0, (c.size.y - h) / 2.0), w, h)
	c.draw_rect(r, Color(12 / 255.0, 14 / 255.0, 20 / 255.0, 0.9 * alpha))
	c.draw_rect(r, Color(247 / 255.0, 168 / 255.0, 1.0, 0.6 * alpha), false, 2.0)
	_text(c, r.get_center().x, r.position.y + 24 * k, "CONTROLLER" if pad else "KEYBOARD AND MOUSE", 15, Color(Color("#f7a8ff"), alpha), 1)
	for i in rows.size():
		var y := r.position.y + (50.0 + i * 22.0) * k
		_text(c, r.position.x + 170 * k, y, rows[i][0], 13, Color(Color("#ffd36b"), alpha), 2)
		_text(c, r.position.x + 186 * k, y, rows[i][1], 13, Color(Color("#e6e8ee"), alpha))

func _pad_last() -> bool:
	var h = fight.main.get("hud") if fight.main else null
	return h != null and h.get("pad_last") == true

func _bubble(c: Control, x: float, y: float, up: float, txt: String, alpha: float, fill: Color) -> void:
	var sp = to_screen(x, y, up)
	if sp == null or alpha <= 0.0:
		return
	var k := sc()
	var font := c.get_theme_default_font()
	var fs := int(11 * k)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(sp.x - tw / 2.0 - 7 * k, sp.y - 20 * k, tw + 14 * k, 20 * k)
	r.position.x = clampf(r.position.x, 4.0, c.size.x - r.size.x - 4.0)
	var ink := Color(0.11, 0.1, 0.13, alpha)
	c.draw_colored_polygon(PackedVector2Array([Vector2(sp.x - 5 * k, r.end.y - 1), Vector2(sp.x + 5 * k, r.end.y - 1), Vector2(sp.x, r.end.y + 7 * k)]), Color(fill, alpha))
	c.draw_rect(r, Color(fill, alpha))
	c.draw_rect(r, ink, false, 2.0)
	c.draw_string(font, Vector2(r.position.x + 7 * k, r.end.y - 6 * k), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

func _machine_prompts(c: Control) -> void:
	var s := fight.sim
	var f := fight.f
	if not s.started or s.over or not f.alive:
		return
	var vp := s.vend_pos()
	if Vector2(f.x - vp.x, f.y - vp.y).length() <= s.tv("vendRadius", 56):
		var sp = to_screen(vp.x, vp.y + 28.0, 0.0)
		if sp != null:
			var price := int(s.tv("vendPrice", 2500))
			if s.vend_sold:
				_text(c, sp.x, sp.y, "SOLD OUT — back next wave", 13, Color("#e0473f"), 1)
			else:
				_text(c, sp.x, sp.y, "NUKE LAUNCHER — $%d" % price, 13, GOLD, 1)
				var sub := "stand still to buy"
				var sc2 := Color("#9be29b")
				if f.weapon == "launcher":
					sub = "you've already got one"
					sc2 = Color("#8b93a4")
				elif f.coins < price:
					sub = "you're $%d short" % (price - f.coins)
					sc2 = Color("#8b93a4")
				_text(c, sp.x, sp.y + 16 * sc(), sub, 12, sc2, 1)
	if Vector2(f.x - s.slot.x, f.y - s.slot.y).length() <= s.tv("slotRadius", 46) and f.spin <= 0.0:
		var sp2 = to_screen(s.slot.x, s.slot.y + 28.0, 0.0)
		if sp2 != null:
			var txt := "$%d PLAY — stand still" % int(s.tv("spinCost", 5))
			var col := GOLD
			if s.slot.broken:
				txt = "OUT OF ORDER"
				col = Color("#8b93a4")
			elif s.slot.cool > 0.0:
				txt = "recharging — %.1fs" % s.slot.cool
				col = Color("#8b93a4")
			elif f.coins < int(s.tv("spinCost", 5)):
				txt = "need $%d" % int(s.tv("spinCost", 5))
				col = Color("#8b93a4")
			_text(c, sp2.x, sp2.y, txt, 13, col, 1)

func _game_over(c: Control) -> void:
	var s := fight.sim
	var k := sc()
	var vp := c.size
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(INK, 0.78))
	var killed := 0
	for p: FT.Fighter in s.players:
		killed += p.kills
	if s.goth:
		_text(c, vp.x / 2.0, 238 * k, "GOTHICA'S DOWN", 40, Color("#e0473f"), 1)
		_text(c, vp.x / 2.0, 268 * k, "you kept her safe to wave %d — best: wave %d" % [s.wave, maxi(ProtectSim.get_best(), s.wave)], 16, Color("#cfd4de"), 1)
	else:
		_text(c, vp.x / 2.0, 238 * k, "DOWN", 40, Color("#e0473f"), 1)
		_text(c, vp.x / 2.0, 268 * k, "made it to wave %d — %d killed" % [s.wave, killed], 16, Color("#cfd4de"), 1)
	_text(c, vp.x / 2.0, 294 * k, ("press Menu" if _pad_last() else "press R") + ", or tap here to restart", 13, Color("#8b93a4"), 1)

# First person: the hands (blasters), the kick and flash, the tracers, the full-view flash for other guns, your
# own pips (you can't see your head), a red pulse while you can't be hurt.
func _draw_fp(c: Control) -> void:
	var s := fight.sim
	var f := fight.f
	var vp := c.size
	var k := sc()
	if not f.alive:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.4, 0, 0, 0.35))
		return
	var hands := f.weapon == "blaster" and _hands != null and f.launch <= 0.0
	if hands:
		var h := vp.y * 0.44
		var w := h * _hands.get_width() / float(_hands.get_height())
		var fired := 0 if f.last_gun == 0 else 1
		for side in 2:
			var sw := _walk_ph + (PI if side == 1 else 0.0)
			var x := (vp.x * 0.335 - w) if side == 0 else vp.x * 0.665
			var y := vp.y - h + 0.05 * vp.y
			x += sin(sw) * 0.008 * vp.x * _move_k
			y += absf(cos(sw)) * 0.022 * vp.y * _move_k
			var kick := 0.0
			if side == fired and f.muzzle > 0.0:
				kick = minf(1.0, f.muzzle / 0.055)
				x += (-1.0 if side == 0 else 1.0) * 0.006 * vp.x * kick
				y += 0.045 * vp.y * kick
			var mx := 171.0 / 172.0 * w
			var my := 15.0 / 177.0 * h
			if side == 0:
				c.draw_texture_rect(_hands, Rect2(x, y, w, h), false)
			else:
				c.draw_texture_rect(_hands, Rect2(x + w, y, -w, h), false)
				mx = w - mx
			if kick > 0.0:
				var mp := Vector2(x + mx, y + my)
				var rr := 0.15 * vp.y * (0.6 + 0.4 * kick)
				c.draw_texture_rect(_glow(), Rect2(mp - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1, 1, 1, 0.95 * kick))
		# tracers: a glow from the gun to the crosshair over 110 ms
		var now := Time.get_ticks_msec()
		var keep := []
		for tr in _tracers:
			var e := (now - int(tr[1])) / 110.0
			if e >= 1.0:
				continue
			keep.append(tr)
			var q := 1.0 - (1.0 - e) * (1.0 - e)
			var from := Vector2(vp.x * (0.335 - 0.02) if tr[0] == 0 else vp.x * (0.665 + 0.02), vp.y * 0.62)
			var at := from.lerp(vp / 2.0, q)
			var rad := vp.y * (0.035 - 0.026 * q) * 2.2
			c.draw_texture_rect(_glow(), Rect2(at - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false)
		_tracers = keep
	elif f.muzzle > 0.0:
		var cc := Vector2(vp.x * 0.5, vp.y * 0.86)
		var rr2 := 0.3 * vp.y
		c.draw_texture_rect(_glow(), Rect2(cc - Vector2(rr2, rr2), Vector2(rr2, rr2) * 2.0), false, Color(1, 1, 1, 0.9 * minf(1.0, f.muzzle / 0.05)))
	if f.iframe > 0.0 and f.grace <= 0.0:
		var a := 0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0))
		for i in 4:
			var w2 := (4 - i) * 14.0 * k
			c.draw_rect(Rect2(0, 0, vp.x, w2), Color(0.85, 0.1, 0.1, a * 0.25))
			c.draw_rect(Rect2(0, vp.y - w2, vp.x, w2), Color(0.85, 0.1, 0.1, a * 0.25))
			c.draw_rect(Rect2(0, 0, w2, vp.y), Color(0.85, 0.1, 0.1, a * 0.25))
			c.draw_rect(Rect2(vp.x - w2, 0, w2, vp.y), Color(0.85, 0.1, 0.1, a * 0.25))
	# your pips under the wallet line
	var shown := maxi(int(s.tv("playerHp", 5)), int(ceil(f.hp)))
	for i in shown:
		var col := Color(1, 1, 1, 0.15)
		if i < int(ceil(f.hp)):
			col = GOLD if i >= int(s.tv("playerHp", 5)) else FightSim.P_COLOURS[0]
		c.draw_rect(Rect2(26 * k + i * 14 * k, 72 * k + 22 * s.players.size() * k + TOP_PAD, 10 * k, 10 * k), col)
	# landing ring hint text in first person isn't needed: the ring is drawn on the floor
	if s.goth and s.goth.hp > 0.0:
		var x0 := 26 * k
		var y1 := 72 * k + 22 * s.players.size() * k + 18 * k + TOP_PAD
		_text(c, x0, y1 + 10 * k, "Gothica", 11, Color("#f7a8ff"))
		c.draw_rect(Rect2(x0 + 52 * k, y1 + 2 * k, 80 * k, 8 * k), Color(0, 0, 0, 0.65))
		c.draw_rect(Rect2(x0 + 52 * k, y1 + 2 * k, 80 * k * clampf(s.goth.hp / s.goth.max_hp, 0, 1), 8 * k), Color("#f7a8ff"))

var _glow_tex: Texture2D

## The muzzle glow (a radial gradient: white, then gold, then clear).
func _glow() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 0.98, 0.86, 0.95))
		g.set_color(1, Color(1, 0.6, 0.2, 0.0))
		g.add_point(0.4, Color(1, 0.84, 0.43, 0.7))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex

# ---------------------------------------------------------------- the weapon bar

class _Hotbar extends Control:
	var hud: FightHud
	var _drag := -1
	var _drag_at := Vector2.ZERO
	var _drag_moved := 0.0
	var _drag_from := Vector2.ZERO
	var _icons: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _slot_at(p: Vector2) -> int:
		var k := hud.sc()
		var step := 62.0 * k
		var i := int(floor(p.x / step))
		if i < 0 or i > 5 or p.x - i * step > 58.0 * k:
			return -1
		return i

	func _gui_input(event: InputEvent) -> void:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag = _slot_at(event.position)
				_drag_from = event.position
				_drag_at = event.position
				_drag_moved = 0.0
			elif _drag >= 0:
				var to := _slot_at(event.position)
				if _drag_moved < 8.0:
					hud.fight.select_slot(_drag)
				elif to >= 0 and to != _drag:
					var o := Fight.hotbar_order
					var tmp := o[_drag]
					o[_drag] = o[to]
					o[to] = tmp
					hud.fight.save_hotbar()
				_drag = -1
			accept_event()
		elif event is InputEventMouseMotion and _drag >= 0:
			_drag_at = event.position
			_drag_moved = maxf(_drag_moved, (event.position - _drag_from).length())
			accept_event()

	func _icon(id: String) -> Array:
		if _icons.has(id):
			return _icons[id]
		var r := []
		match id:
			"blaster": r = [CharFrames.path("juicy", "side_run", 0), Rect2(76, 34, 54, 46)]
			"shotgun": r = [CharFrames.path("juicy_shotgun", "side_a", 0), Rect2(42, 31, 36, 17)]
			"launcher": r = [CharFrames.path("juicy_launcher", "side_a", 0), Rect2(72, 36, 52, 36)]
			"spud": r = [CharFrames.path("juicy_spud", "side_run", 0), Rect2(74, 28, 42, 28)]
			"lob":
				var l = GameData.manifest.get("SPUD_SPRITES")
				r = [l[4] if l is Array else "", Rect2()]
		if r.size() == 2 and String(r[0]) != "" and ResourceLoader.exists("res://" + String(r[0])):
			var t := GameData.tex(String(r[0]))
			if r[1] == Rect2():
				r[1] = Rect2(Vector2.ZERO, t.get_size())
			r = [t, r[1]]
		else:
			r = []
		_icons[id] = r
		return r

	func _draw() -> void:
		var f := hud.fight.f
		var s := hud.fight.sim
		var k := hud.sc()
		var sz := 54.0 * k
		var now := Time.get_ticks_msec()
		var font := get_theme_default_font()
		for i in 6:
			var id: String = Fight.hotbar_order[i]
			var r := Rect2(i * 62.0 * k, 0, sz, sz)
			var own := WeaponDefs.has_weapon(f, id)
			draw_rect(r, Color(14 / 255.0, 16 / 255.0, 22 / 255.0, 0.78))
			var bc := Color("#8b93a4") if own else Color("#3a4050")
			var bw := 1.0
			if f.weapon == id:
				bc = FightHud.GOLD
				bw = 2.0
			if hud._flash_slot == i and now < hud._flash_until:
				bc = Color("#e0473f")
				bw = 2.0
			draw_rect(r, bc, false, bw * maxf(1.0, k * 0.8))
			draw_string(font, r.position + Vector2(4, 11) * k, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * k), Color("#6b7385"))
			if i == _drag and _drag_moved >= 8.0:
				continue
			_draw_icon(id, Rect2(r.position + Vector2(10, 6) * k * 54.0 / 40.0, Vector2(34, 20) * k * 54.0 / 40.0), own)
			var lbl := ""
			var lc := Color("#9aa3b5")
			match id:
				"fists": lbl = "POW"
				"lob":
					lbl = "× %d" % (f.ammo / 10)
					lc = Color("#d8b878") if f.ammo >= 10 else Color("#e0473f")
				"spud":
					lbl = ("● %d" % f.ammo) if f.ammo > 0 else "○ 0"
					lc = Color("#d8b878") if f.ammo > 0 else Color("#e0473f")
				"blaster":
					lbl = "∞" if own else "—"
					lc = Color("#9aa3b5") if own else Color("#3a4050")
				"launcher":
					lbl = ("☢ %d" % f.rockets) if own else "—"
					lc = FightHud.GOLD if own else Color("#3a4050")
				"shotgun":
					if own:
						var br := Rect2(r.position + Vector2(6, 28) * k * 54.0 / 40.0, Vector2(28, 4) * k * 54.0 / 40.0)
						draw_rect(br, Color("#2a2f3b"))
						var red := s.started and f.w_time < 3.0 and int(floor(f.w_time * 6.0)) % 2 == 0
						draw_rect(Rect2(br.position, Vector2(br.size.x * f.w_time / s.tv("shotgunTime", 12), br.size.y)), Color("#e0473f") if red else FightHud.GOLD)
					else:
						lbl = "—"
						lc = Color("#3a4050")
			if lbl != "":
				var fs := int(9 * k * 54.0 / 40.0)
				var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var lp := r.position + Vector2(sz / 2.0 - tw / 2.0, 34 * k * 54.0 / 40.0 + 4)
				var rest := FightHud.glyph(self, lp, lbl, fs, lc, font)
				draw_string(font, lp, rest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
		if _drag >= 0 and _drag_moved >= 8.0:
			var dr := Rect2(_drag_at - Vector2(sz, sz) / 2.0, Vector2(sz, sz))
			draw_rect(dr, Color(14 / 255.0, 16 / 255.0, 22 / 255.0, 0.92))
			draw_rect(dr, FightHud.GOLD, false, 2.0)
			_draw_icon(Fight.hotbar_order[_drag], Rect2(dr.position + Vector2(10, 15) * k, Vector2(34, 24) * k), true)

	func _draw_icon(id: String, box: Rect2, own: bool) -> void:
		var ic := _icon(id)
		var mod := Color.WHITE if own else Color(0.6, 0.6, 0.6, 0.35)
		if ic.is_empty():
			var font := get_theme_default_font()
			var t: String = "FISTS" if id == "fists" else WeaponDefs.LABEL.get(id, id)
			var fs := int(box.size.y * 0.45)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, box.position + Vector2(box.size.x / 2.0 - tw / 2.0, box.size.y * 0.7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#cfd4de") * mod)
			return
		var src: Rect2 = ic[1]
		var fit := minf(box.size.x / src.size.x, box.size.y / src.size.y)
		var dsz := src.size * fit
		draw_texture_rect_region(ic[0], Rect2(box.get_center() - dsz / 2.0, dsz), src, mod)
