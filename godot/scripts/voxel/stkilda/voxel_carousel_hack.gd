class_name VoxelCarouselHack
extends Node3D
## The Carousel sabotaged (the owner, 31 Oct, the first mission: "loosening 1 of the bolts and hacking the Mary go
## round ... You have to work out each control"). Takes over turning the ride from SkLunaRides' Spinner (the same
## turn and the horses' rise and fall, but at the speed the controls set).
## - The control box: a steel cabinet on the path just off the ride. E there and you hold up the gadget (made up,
##   not a real one): its screen has SIGNALS buttons, 1 to 4. Which does what is shuffled each time you come
##   (faster, slower, the brake, the lights): you find out by trying them, and the screen remembers what you've seen.
##   Faster goes up through the speeds (SPEEDS), slower down again; the brake stops it dead, the horses lurching;
##   the lights go off and on. E, or walking off, puts the gadget away.
## - A loose bolt: with the ride stood still, hold E by a horse nobody's on for LOOSEN s (a bar fills): its bolt's
##   loose. From then it rattles on its pole as the ride turns, the faster the worse, and when the ride stops dead
##   it's thrown over crooked on its pole and stays that way.
## Put back as it was the next time you come (reset). Owned by the St Kilda session.

const SPEEDS := [0.0, 0.45, 1.2, 2.2, 3.4]   # rad/s the ride turns at each speed (1: its own)
const SPEED_UP := 0.5           # rad/s a second it speeds up or slows down
const DEAD_STOP := 0.15         # s the brake takes, from any speed
const LOOSEN := 3.0             # s to loosen a bolt, holding E
const NEAR_BOX := 1.8           # m from the box to use it
const AWAY := 9.0               # m from the box and the gadget's put away
const NEAR_HORSE := 1.7         # m (level) from a horse's pole to get at its bolt
const ACTS := ["faster", "slower", "brake", "lights"]
const BOX_GREY := Color("#6f777d")

var sk: VoxelStKilda
var carousel: Node3D
var spin: SkLunaRides.Spinner
var box: Node3D
var level := 1                  # the speed it's set to (SPEEDS)
var w := 0.45                   # how fast it's turning now (rad/s)
var braking := 0.0              # s left of a dead stop
var lights_on := true
var keys: Array = []            # signal (0..3) -> what it does (ACTS)
var seen: Array = []            # signal -> found out yet
var loose := -1                 # the horse with the loose bolt (its number), -1: none yet
var thrown := 0.0               # how far over it's been thrown (0..1), stopping dead
var _empty: Array = []          # the horses nobody's on
var _t := 0.0
var _phase := 0.0              # where the horses are in their rise and fall (it goes as fast as the ride)
var _brake_from := 0.0         # how fast it was turning when the brake went on
var _hold := 0.0                # s E's been held at a horse
var _hold_horse := -1
var _open := false
var _e_down := false            # E held (from its key events: a held key, seen the same way in tests)
var _rattle := 0.0
var _hidden_lights: Array = []  # the Carousel's bulbs, and its share of the coloured light at night
var _spill_entry = null
var _ui: PanelContainer
var _rows: Array[Label] = []
var _state: Label

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "CarouselHack"
	carousel = sk.get_node_or_null("Carousel") as Node3D
	if carousel == null:
		return
	spin = carousel.get_node_or_null("Ride") as SkLunaRides.Spinner
	if spin == null:
		return
	spin.process_mode = Node.PROCESS_MODE_DISABLED       # (turned from here)
	var taken := {}
	if spin.riders:
		for st in spin.riders.seats:
			taken[int(st[1])] = true
	for k in spin.horses.size():
		if not taken.has(k):
			_empty.append(k)
	_box()
	_gadget()
	reset()

## Put back as it was: turning at its own speed, every bolt tight, the lights on, the signals shuffled again.
func reset() -> void:
	if spin == null:
		return
	level = 1
	w = SPEEDS[1]
	braking = 0.0
	loose = -1
	thrown = 0.0
	_hold = 0.0
	_set_lights(true)
	keys = ACTS.duplicate()
	keys.shuffle()
	seen = [false, false, false, false]
	_show(false)

# ---------------------------------------------------------------- the control box

# a steel cabinet on a concrete foot, its door, a warning sign, two lamps on top (green: running), a pipe to the ground,
# on the path just off the ride, toward the way into the park, facing out
func _box() -> void:
	var c := carousel.global_position
	var to: Vector3 = sk.arrive_spot()[0] - c
	to.y = 0.0
	var out := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var at := c + out * (VoxelCarousel.EDGE + 1.6)
	var h := Node3D.new()
	SkModels.box(h, Vector3(0.9, 0.12, 0.6), Vector3(0, 0.06, 0), Color("#9a9a94"))
	SkModels.box(h, Vector3(0.75, 1.3, 0.42), Vector3(0, 0.77, 0), BOX_GREY)
	SkModels.box(h, Vector3(0.68, 1.18, 0.03), Vector3(0, 0.77, 0.22), BOX_GREY.lightened(0.08))     # its door
	SkModels.box(h, Vector3(0.05, 0.16, 0.04), Vector3(0.27, 0.8, 0.245), Color("#2b2d30"))          # the handle
	SkModels.box(h, Vector3(0.22, 0.2, 0.01), Vector3(0, 1.08, 0.24), Color("#f2c230"))              # the warning sign
	SkModels.box(h, Vector3(0.05, 0.12, 0.012), Vector3(0, 1.08, 0.247), Color("#202020"))
	SkModels.box(h, Vector3(0.82, 0.05, 0.48), Vector3(0, 1.45, 0), BOX_GREY.darkened(0.2))
	SkModels.box(h, Vector3(0.1, 0.5, 0.1), Vector3(-0.25, 0.25, -0.26), Color("#3a3c40"))           # the pipe
	box = Node3D.new()
	box.name = "ControlBox"
	var mi := MeshInstance3D.new()
	mi.mesh = SkModels.bake(h)
	mi.material_override = SkModels.baked_material()
	h.free()
	box.add_child(mi)
	for k in 2:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.045
		sm.height = 0.09
		lamp.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#3ad35a") if k == 0 else Color("#e0342a")
		m.emission_enabled = true
		m.emission = m.albedo_color
		lamp.material_override = m
		lamp.position = Vector3(-0.15 + k * 0.3, 1.5, 0.1)
		lamp.name = "Lamp%d" % k
		box.add_child(lamp)
	var body := StaticBody3D.new()
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.8, 1.5, 0.45)
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0)
	body.add_child(cs)
	box.add_child(body)
	add_child(box)
	box.global_transform = Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), Vector3(at.x, 0.0, at.z))

# ---------------------------------------------------------------- the gadget's screen

func _gadget() -> void:
	_ui = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#14181c")
	sb.border_color = Color("#ef7d22")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	_ui.add_theme_stylebox_override("panel", sb)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_ui.offset_left = -430
	_ui.offset_right = -40
	_ui.offset_top = -150
	_ui.offset_bottom = 150
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_ui.add_child(v)
	var title := _label("CONTROL BOX: 4 SIGNALS FOUND", 22, Color("#ef7d22"))
	v.add_child(title)
	for k in 4:
		var l := _label("", 26, Color("#9fe08a"))
		v.add_child(l)
		_rows.append(l)
	_state = _label("", 20, Color("#cfd6dc"))
	v.add_child(_state)
	v.add_child(_label("1-4 send   E put away", 18, Color("#7d8790")))
	_ui.visible = false
	sk.arena._hud_layer.add_child(_ui)

static func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _show(on: bool) -> void:
	_open = on
	if _ui:
		_ui.visible = on
	if on:
		_refresh()

func _refresh() -> void:
	for k in 4:
		_rows[k].text = "%d   SIGNAL %s   %s" % [k + 1, "ABCD"[k], ("-> " + String(keys[k]).to_upper()) if seen[k] else "???"]
	var turning := "STOPPED" if w < 0.02 else "SPEED %d" % level
	_state.text = "RIDE: %s   LIGHTS: %s" % [turning, "ON" if lights_on else "OFF"]

## Send signal k (0..3) to the control box: whatever it's wired to happens.
func send(k: int) -> void:
	var act: String = keys[k]
	seen[k] = true
	sk.arena.sound.play("switch", box.global_position, -4.0, 1.4)
	match act:
		"faster":
			if braking <= 0.0:
				level = mini(level + 1, SPEEDS.size() - 1)
				sk.arena.sound.play("machine_start", carousel.global_position, -4.0, 0.8 + level * 0.12)
		"slower":
			level = maxi(level - 1, 0)
		"brake":
			if w > 0.05:
				braking = DEAD_STOP
				_brake_from = w
				sk.arena.sound.play("slam", carousel.global_position, 2.0, 0.7)
				sk.arena.sound.play("mine_groan", carousel.global_position, 0.0, 1.2)
			level = 0
		"lights":
			_set_lights(not lights_on)
	_refresh()

func _set_lights(on: bool) -> void:
	lights_on = on
	if carousel == null:
		return
	_hidden_lights.clear()
	for n in carousel.find_children("*", "", true, false):
		if n.name in ["Bulbs", "NightLights", "NightHalos"]:
			_hidden_lights.append(n)
	for n in _hidden_lights:
		(n as Node3D).visible = on
	# its share of the coloured light the rides throw at night
	var spill := sk.get_node_or_null("RideSpill")
	if spill == null:
		return
	if _spill_entry == null:
		for e in spill.lights:
			if (e[0] as Node3D).global_position.distance_to(carousel.global_position) < VoxelCarousel.EDGE + 3.0:
				_spill_entry = e
				break
	if _spill_entry == null:
		return
	if on and not spill.lights.has(_spill_entry):
		spill.lights.append(_spill_entry)
	elif not on:
		spill.lights.erase(_spill_entry)
		(_spill_entry[0] as OmniLight3D).visible = false

# ---------------------------------------------------------------- turning the ride

func _process(dt: float) -> void:
	if spin == null:
		return
	_t += dt
	var was := w
	if braking > 0.0:
		braking -= dt
		w = maxf(0.0, w - was / maxf(braking + dt, dt) * dt)
		if braking <= 0.0:
			w = 0.0
			if loose >= 0 and _brake_from > 1.0:
				thrown = 1.0
	else:
		w = move_toward(w, SPEEDS[level], SPEED_UP * dt)
	if SkLunaRides._near(spin) or w > 0.5:
		spin.rotation.y = fposmod(spin.rotation.y + dt * w, TAU)
		_rattle = minf(1.0, w / 3.4)
		_phase += dt * 2.2 * w / 0.45
		var jolt := clampf((was - w) / maxf(dt, 0.001) / 20.0, 0.0, 1.0)     # (stopping dead: everything lurches)
		for h in spin.horses:
			var k: int = h[1]
			var xf: Transform3D = h[2]
			var rise := (sin(_phase + float(h[4])) * 0.5 + 0.5) * float(h[3])
			xf.origin.y = 0.6 + rise
			if jolt > 0.0:
				xf.basis = xf.basis * Basis(Vector3.BACK, -0.25 * jolt)          # (nose down, forward)
			if k == loose:
				var shake := _rattle * (0.05 + 0.1 * _rattle)
				xf.basis = xf.basis * Basis(Vector3.RIGHT, sin(_t * 31.0) * shake) * Basis(Vector3.BACK, sin(_t * 23.0) * shake * 0.6)
				xf.origin.y += absf(sin(_t * 17.0)) * shake * 0.4
				if thrown > 0.0:
					xf.basis = xf.basis * Basis(Vector3.RIGHT, 0.75) * Basis(Vector3.BACK, -0.35)   # (thrown over on its pole)
					xf.origin.y = 0.35
			(h[0] as MultiMeshInstance3D).multimesh.set_instance_transform(k, xf)
		if spin.riders:
			spin.riders.follow()
	if box:
		(box.get_node("Lamp0") as Node3D).visible = w > 0.02
		(box.get_node("Lamp1") as Node3D).visible = w <= 0.02
	if _open:
		_refresh()
		if sk.arena.player.global_position.distance_to(box.global_position) > AWAY:
			_show(false)
	_prompt(dt)

# what E does here: the box, a horse's bolt (held)
func _prompt(dt: float) -> void:
	if sk.riding() or sk.near_ride or (sk.bushes and sk.bushes.dragging >= 0):
		return
	var pp := sk.arena.player.global_position
	if not _open and pp.distance_to(box.global_position) < NEAR_BOX:
		sk.arena._use_label.text = "E  hold the gadget up to the control box"
		return
	var k := _horse_near(pp)
	if k < 0:
		_hold = 0.0
		return
	if k == loose:
		sk.arena._use_label.text = "This horse's bolt is loose"
		return
	if w > 0.05:
		sk.arena._use_label.text = "(it's turning: stop the ride to get at a bolt)"
		return
	if _e_down and not _open:
		if _hold_horse != k:
			_hold = 0.0
			_hold_horse = k
		var before := int(_hold / 0.5)
		_hold += dt
		if int(_hold / 0.5) != before:
			sk.arena.sound.play("dial_click", pp, -6.0, randf_range(0.7, 0.9))
		if _hold >= LOOSEN:
			loose = k
			thrown = 0.0
			_hold = 0.0
			sk.arena.sound.play("lock_rattle", pp, -2.0, 0.7)
			sk.arena.say("The bolt's loose", 1.5)
		else:
			var bar := int(_hold / LOOSEN * 10.0)
			sk.arena._use_label.text = "Loosening the bolt  [%s%s]" % ["#".repeat(bar), "-".repeat(10 - bar)]
	else:
		_hold = 0.0
		sk.arena._use_label.text = "Hold E  loosen this horse's bolt"

# the empty horse you're by (its number), or -1
func _horse_near(p: Vector3) -> int:
	var best := -1
	var bd := NEAR_HORSE
	for h in spin.horses:
		var k: int = h[1]
		if not _empty.has(k):
			continue
		var at := spin.global_transform * (h[2] as Transform3D).origin
		var d := Vector2(at.x - p.x, at.z - p.z).length()
		if d < bd:
			bd = d
			best = k
	return best

func _input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_E and not e.echo:
		_e_down = e.pressed
	if not _open or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).physical_keycode
	if k >= KEY_1 and k <= KEY_4:
		send(k - KEY_1)
		get_viewport().set_input_as_handled()

func _unhandled_input(e: InputEvent) -> void:
	if not sk.active or sk.arena.phone.is_open() or sk.riding() or sk.near_ride:
		return
	if not (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_E):
		return
	if _open:
		_show(false)
	elif sk.arena.player.global_position.distance_to(box.global_position) < NEAR_BOX:
		_show(true)
		sk.arena.sound.play("dial_click", box.global_position, -2.0, 1.3)
	else:
		return
	get_viewport().set_input_as_handled()
