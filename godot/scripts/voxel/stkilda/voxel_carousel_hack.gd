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
## - Stopped dead from flat out (THROW_FROM), a rider goes flying across the park at Luna Palace, the view going with
##   them, and is caught by a foot on a window sill, left hanging upside down (the owner, 31 Oct). VoxelCarouselTumble.
## Put back as it was the next time you come (reset). Owned by the St Kilda session.

const SPEEDS := [0.0, 0.45, 1.2, 2.2, 3.4]   # rad/s the ride turns at each speed (1: its own)
const SPEED_UP := 0.5           # rad/s a second it speeds up or slows down
const DEAD_STOP := 0.15         # s the brake takes, from any speed
const LOOSEN := 3.0             # s to loosen a bolt, holding E
const NEAR_BOX := 1.8           # m from the box to use it
const AWAY := 9.0               # m from the box and the gadget's put away
const NEAR_HORSE := 1.7         # m (level) from a horse's pole to get at its bolt
const ACTS := ["faster", "slower", "brake", "lights"]
const THROW_FROM := 3.0         # rad/s (flat out): stopped dead faster than this and a rider goes flying (VoxelCarouselTumble)
const THROW_MAX := 9.0          # m/s they fly off at, at most
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
var tumbles: Array = []         # the riders thrown off (VoxelCarouselTumble)
var _gone_seats: Array = []     # [seat, where they sat] of those
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
	for tb in tumbles:
		if is_instance_valid(tb):
			(tb as Node).queue_free()
	tumbles.clear()
	if _cam and _cam.current:
		_cam.current = false
		sk.arena.cam.current = true
	_cam_tb = null
	if bin:
		bin.rotation.x = 0.0
		bin.set_meta("wobble", 0.0)
	for g in _gone_seats:
		(g[0] as Array)[2] = g[1]
	_gone_seats.clear()
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
				if w > THROW_FROM:
					_throw()
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
	if bin == null and _bin_tries < 30 and SkLunaRides._near(spin):
		_bin_tries += 1                         # (the window found by looking across at Luna Palace: once its walls are there to hit)
		if _palace_wall() and _sill != Vector3.INF:
			_make_bin()
	_follow_step(dt)
	if _open:
		_refresh()
		if sk.arena.player.global_position.distance_to(box.global_position) > AWAY:
			_show(false)
	_prompt(dt)

# what E does here: the box, a horse's bolt (held)
func _prompt(dt: float) -> void:
	if _cam and _cam.current:
		sk.arena._use_label.text = "Mouse: swing the view round   Wheel: nearer / further"
		return
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
	if _cam and _cam.current:
		if e is InputEventMouseMotion:
			var rel := (e as InputEventMouseMotion).relative
			orbit.x -= rel.x * ORBIT_SENS
			orbit.y = clampf(orbit.y - rel.y * ORBIT_SENS, -1.2, 1.2)
			get_viewport().set_input_as_handled()
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			var b := (e as InputEventMouseButton).button_index
			if b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clampf(zoom * (0.88 if b == MOUSE_BUTTON_WHEEL_UP else 1.14), 0.35, 3.0)
				get_viewport().set_input_as_handled()
				return
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


# ---------------------------------------------------------------- a rider thrown off (stopped dead from speed)
#
# (The owner, 31 Oct: "flung off really far hitting the castle, the camera follows them".) Thrown at Luna Palace: the
# rider going the way most toward it is the one, and they fly in an arc FLY_SPEED m/s across at the upstairs window
# nearest the Carousel: they hit the wall above it, slide down it and a foot catches on its sill (the owner: "his leg
# gets caught on the window sill and he gets stuck hanging upside down"): left hanging there till you come again. (Its front facing away, no window to
# aim at: into its wall FLY_H m up, down, up and off back toward the ride.) The view goes with them (FollowCam) and
# comes back to you once they're hanging (or walking). No Luna Palace (or something between): the old short throw,
# into whatever's nearest.

const FLY_H := 6.0              # m up Luna Palace's wall they hit
const FLY_SPEED := 26.0         # m/s across

var _wall_at := Vector3.INF     # where on Luna Palace's wall (and its normal): found the first time
var _wall_n := Vector3.ZERO
var _sill := Vector3.INF        # the window sill they catch on: its top, at its front edge (INF: none facing the ride)
var _sill_out := Vector3.ZERO
var bin: Node3D                 # the wheelie bin under that window (the owner: "fall into a bin")
var _bin_tries := 0
var _cam: Camera3D
var _cam_tb: VoxelCarouselTumble
var _cam_dir := Vector3.FORWARD
var orbit := Vector2.ZERO       # (the owner, 31 Oct: "choose the angle of the camera during flight") the mouse swinging the
var zoom := 1.0                 # view round them: how far round (rad), how far up or down; the wheel, how near
const ORBIT_SENS := 0.006

# where they'd hit Luna Palace's wall, looking across from the Carousel at FLY_H
func _palace_wall() -> bool:
	if _wall_at != Vector3.INF:
		return true
	var palace := sk.get_node_or_null("LunaPalace") as Node3D
	if palace == null:
		return false
	var a := spin.global_position + Vector3(0, FLY_H, 0)
	var b := palace.global_position
	b.y = FLY_H
	var q := PhysicsRayQueryParameters3D.create(a, a + (b - a) * 1.2, SkData.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit.position as Vector3).distance_to(b) > (a.distance_to(b)) * 0.6:
		return false                    # (something else in the way, nearer the Carousel)
	_wall_at = hit.position
	_wall_n = hit.normal
	_window(palace)
	return true

## The rider thrown off: at Luna Palace if it's there to hit, else into whatever's nearest the way they're going.
func _throw() -> void:
	if spin.riders == null:
		return
	var mid := spin.global_position
	var far := _palace_wall()
	var space := get_world_3d().direct_space_state
	var best := -1
	var best_d := INF
	var best_xf := Transform3D()
	var best_v := Vector3.ZERO
	var seats: Array = spin.riders.seats
	for i in seats.size():
		var s: Array = seats[i]
		if (s[2] as Transform3D).basis.get_scale().x < 0.01:
			continue                         # (thrown off already)
		var on := Transform3D()
		for h in spin.horses:
			if int(h[1]) == int(s[1]):
				on = h[2]
		var xf := spin.global_transform * on * (s[2] as Transform3D)
		var r := xf.origin - mid
		r.y = 0.0
		var v := Vector3.UP.cross(r) * w
		var d := 0.0
		if far:
			var to := _wall_at - xf.origin
			to.y = 0.0
			d = 1.0 - v.normalized().dot(to.normalized())        # (going most toward Luna Palace)
		else:
			var from := xf.origin + Vector3(0, 1.0, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + v.normalized() * 15.0, SkData.LAYER_WORLD)
			var hit := space.intersect_ray(q)
			d = from.distance_to(hit.position) if not hit.is_empty() else 50.0
			if d <= 1.0:
				continue
		if d < best_d:
			best = i
			best_d = d
			best_xf = xf
			best_v = v
	if best < 0:
		return
	var seat: Array = seats[best]
	_gone_seats.append([seat, seat[2]])
	var custom := spin.riders.multimesh.get_instance_custom_data(best)
	seat[2] = Transform3D(Basis().scaled(Vector3.ONE * 0.001), (seat[2] as Transform3D).origin)
	var tb := VoxelCarouselTumble.new()
	tb.name = "Tumble"
	add_child(tb)
	var start := best_xf.origin
	var fly := Vector3(best_v.x, 0, best_v.z)
	var lift := 2.2
	if far:
		# an arc that comes down on the wall a little in front of it (the body's middle about 1.1 m up off their feet)
		var aim := _wall_at + _wall_n * 0.3
		if _sill != Vector3.INF:
			aim = _sill + _sill_out * 0.4 + Vector3(0, 0.6, 0)        # (where VoxelCarouselTumble catches them on it)
			tb.hang_at = _sill
			tb.hang_out = _sill_out
			if bin:
				tb.bin_at = bin.global_position
				tb.bin = bin
		var across := Vector3(aim.x - start.x, 0, aim.z - start.z)
		var t := across.length() / FLY_SPEED
		fly = across / t
		lift = (aim.y - (start.y + 1.1) + 0.5 * 9.8 * t * t) / t
		tb.walk_back = true
	else:
		fly = fly.normalized() * minf(fly.length(), THROW_MAX)
	var face := Basis(Vector3.UP, atan2(-fly.x, -fly.z))
	tb.start(Transform3D(face.scaled(Vector3.ONE * best_xf.basis.get_scale().x), start), custom, fly, mid, lift, 4.0 if far else 6.0)
	tumbles.append(tb)
	sk.arena.sound.play("swoosh_heavy", start, 0.0, 0.8)
	if far:
		_follow(tb, fly.normalized())

# ---------------------------------------------------------------- the view going with them

func _follow(tb: VoxelCarouselTumble, dir: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "FollowCam"
		_cam.fov = 65.0
		add_child(_cam)
	_cam_tb = tb
	_cam_dir = dir
	orbit = Vector2.ZERO
	zoom = 1.0
	var p := _where(tb)
	# (off to their side, outside the ride: straight behind them is in under its roof)
	_cam.global_position = _clear_of_ride(p + dir.cross(Vector3.UP) * 5.0 - dir * 1.5 + Vector3(0, 1.8, 0))
	_cam.look_at(p, Vector3.UP)
	_cam.current = true

# the Carousel's canopy, as a round tower: (its middle, how far out, how high its top), found the first time
var _roof := Vector3.INF
const ROOF_MARGIN := 0.8

## Where the view can be, kept out of the Carousel (the owner, 31 Oct: "the camera clips through the carousel"): from
## the ground to just over its roof it's pushed out past the edge of its canopy.
func _clear_of_ride(at: Vector3) -> Vector3:
	if _roof == Vector3.INF:
		var roof := carousel.find_child("Roof", true, false) as MeshInstance3D
		var box := roof.global_transform * roof.get_aabb() if roof else AABB(carousel.global_position, Vector3(14, 6, 14))
		_roof = Vector3(maxf(box.size.x, box.size.z) * 0.5, box.end.y, 0.0)
	var c := carousel.global_position
	var out := Vector3(at.x - c.x, 0, at.z - c.z)
	var r := _roof.x + ROOF_MARGIN
	if at.y > _roof.y + ROOF_MARGIN or out.length() >= r:
		return at
	if out.length() < 0.01:
		out = _cam_dir
	return Vector3(c.x, at.y, c.z) + out.normalized() * r

# where the thrown one is now: the ragdoll's middle, or them stood up
static func _where(tb: VoxelCarouselTumble) -> Vector3:
	if tb.stage == "hang":
		return tb.hang_at + Vector3(0, -0.9, 0)
	if tb.stage in ["flying", "splat", "slide", "fall", "binned"] and tb.hang_at != Vector3.INF:
		return tb.mid_now
	if tb._rag != null and is_instance_valid(tb._rag):
		var b := tb._rag._parts.get("body") as RigidBody3D
		if b:
			return b.global_position
	return tb.at + Vector3(0, 0.9, 0)

func _follow_step(dt: float) -> void:
	if _cam == null or not _cam.current:
		return
	if _cam_tb == null or not is_instance_valid(_cam_tb) or _cam_tb.stage == "done" or (_cam_tb.stage == "walk" and _cam_tb._t > 3.5) or (_cam_tb.stage == "hang" and _cam_tb.bin_at == Vector3.INF and _cam_tb._t > 6.0) or (_cam_tb.stage == "binned" and _cam_tb._t > 3.0):
		_cam.current = false
		sk.arena.cam.current = true          # (back to you)
		_cam_tb = null
		return
	var p := _where(_cam_tb)
	var side := _cam_dir.cross(Vector3.UP)
	var want: Vector3
	if _cam_tb.stage == "flying" and p.distance_to(_wall_at) > 6.0:
		want = p - _cam_dir * 6.0 + Vector3(0, 2.0, 0)                    # (behind them, flying)
	elif _cam_tb.stage in ["hang", "splat", "slide", "fall", "binned"]:
		want = p + _cam_tb.hang_out * 4.2 + side * 1.3 + Vector3(0, -0.5, 0)    # (out in front of the wall, looking at them)
	else:
		want = p - _cam_dir * 7.0 + side * 4.5 + Vector3(0, 2.2, 0)     # (stood off to the side: the wall, the drop, up again)
		want.y = maxf(want.y, 1.5)
	# swung round them as the mouse has, nearer or further as the wheel has (never under the ground)
	var off := Basis(Vector3.UP, orbit.x) * (want - p)
	var tilt := off.cross(Vector3.UP).normalized()
	if tilt.length() > 0.5:
		off = Basis(tilt, orbit.y) * off
	want = p + off * zoom
	want.y = maxf(want.y, 0.4)
	_cam.global_position = _clear_of_ride(_cam.global_position.lerp(_clear_of_ride(want), minf(1.0, dt * 4.0)))
	_cam.look_at(p, Vector3.UP)

# the upstairs window of Luna Palace nearest the Carousel, if its front's toward the ride (SkLunaRides' Luna Palace:
# windows along its front between the round tower and the far end, sills 4.78 m up standing out from the wall; its
# size from where the tower's flag is)
func _window(palace: Node3D) -> void:
	if not palace.has_meta("flag_tops"):
		return
	var xf := palace.global_transform
	var out := xf.basis.z.normalized()
	var to := spin.global_position - palace.global_position
	to.y = 0.0
	if out.dot(to.normalized()) < 0.3:
		return
	var tower: Vector3 = (palace.get_meta("flag_tops") as PackedVector3Array)[0]
	var hw := 3.0 - tower.x
	var hd := tower.z + 3.0
	var span := hw * 2.0 - 8.0
	var many := maxi(2, int(span / 4.5))
	var near := xf.affine_inverse() * spin.global_position
	var best := INF
	for k in many:
		var x := -hw + 7.0 + (k + 0.5) * span / many
		if absf(x - near.x) < best:
			best = absf(x - near.x)
			_sill = xf * Vector3(x, 4.78 + 0.09, hd + 0.05 + 0.12 + 0.175)
	_sill_out = out
	_wall_at = _sill

## A wheelie bin on the path under the window (a council one: dark green, its red lid flung open back against the
## wall), its open top up; you bump into it. VoxelCarouselTumble drops the one hanging there into it.
func _make_bin() -> void:
	var h := Node3D.new()
	var green := Color("#2d5a34")
	var inside := Color("#16241a")
	var w := 0.58
	var d := 0.72
	var tall := 1.0
	SkModels.box(h, Vector3(w, 0.06, d), Vector3(0, 0.1, 0), inside)                                    # its floor, inside
	SkModels.box(h, Vector3(w, tall, 0.04), Vector3(0, tall / 2.0, d / 2.0 - 0.02), green)               # front
	SkModels.box(h, Vector3(w, tall, 0.04), Vector3(0, tall / 2.0, -d / 2.0 + 0.02), green.darkened(0.1))  # back
	for s in [-1.0, 1.0]:
		SkModels.box(h, Vector3(0.04, tall, d), Vector3(s * (w / 2.0 - 0.02), tall / 2.0, 0), green.darkened(0.05))
		SkModels.box(h, Vector3(0.05, 0.22, 0.22), Vector3(s * (w / 2.0 + 0.03), 0.11, -d / 2.0 + 0.1), Color("#1a1a1a"))  # wheels
	SkModels.box(h, Vector3(w - 0.08, 0.02, d - 0.08), Vector3(0, tall - 0.25, 0), inside)               # (dark in it)
	SkModels.box(h, Vector3(w + 0.04, 0.05, d + 0.04), Vector3(0, tall, 0), green.lightened(0.05))       # the rim
	SkModels.box(h, Vector3(0.36, 0.04, 0.06), Vector3(0, tall - 0.05, -d / 2.0 - 0.05), Color("#222222"))  # the handle
	var lid := SkModels.box(h, Vector3(w + 0.06, d + 0.06, 0.04), Vector3(0, tall + (d + 0.06) / 2.0 - 0.02, -d / 2.0 - 0.05), Color("#c23a2e"))
	lid.rotation.x = -0.25                                                                                # (open, leant back)
	bin = Node3D.new()
	bin.name = "WheelieBin"
	var mi := MeshInstance3D.new()
	mi.mesh = SkModels.bake(h)
	mi.material_override = SkModels.baked_material()
	h.free()
	bin.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, tall, d)
	cs.shape = bs
	cs.position = Vector3(0, tall / 2.0, 0)
	body.add_child(cs)
	bin.add_child(body)
	add_child(bin)
	var at := _sill + _sill_out * 0.45
	bin.global_transform = Transform3D(Basis(Vector3.UP, atan2(_sill_out.x, _sill_out.z)), Vector3(at.x, 0.0, at.z))
