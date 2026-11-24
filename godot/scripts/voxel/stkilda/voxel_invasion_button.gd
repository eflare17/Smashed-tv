class_name VoxelInvasionButton
extends Node3D
## The invasion's start button (the owner, 24 Nov: "I want to make it to be a way to start with enemies there. Not just
## there when you spawn in ... A button to start it"). A post just inside Luna Park's entrance, to one side of the path
## past Mr Moon's mouth: a big red mushroom button under a yellow-and-black striped hood, an "INVASION" sign over it
## (lit at night) and a red lamp on top. Looking at it within REACH m: "E  start the invasion". Pressed: the button
## goes down with a clunk, a siren winds up (made in code: siren()), the lamp flashes, the screen washes red a moment
## and VoxelParkInvasion.start(true) is called (you're inside the park: nobody pops up beside you). While it's on:
## "E  call off the invasion", E held CALL_OFF s: stopped, the park as it was. Owned by the St Kilda session.

const REACH := 2.8               # m (level) from the post
const LOOKING := 0.8             # (first person) how near your look is to the button: the cosine of the angle
const CALL_OFF := 1.0            # s E's held to call it off
const INSIDE := 8.0              # m past Mr Moon's face (into the park) ...
const SIDE := 3.1                # ... and this far to the side of the path (the mouth's 2 m either side of the middle)
const BUTTON_Y := 1.3
const BUTTON_OUT := 0.2          # the button's rest, out from the post's middle; pressed, PRESS further in
const PRESS := 0.07
const YELLOW := Color("#f2c230")
const BLACK := Color("#17181a")
const RED := Color("#ee2a22")
const STEEL := Color("#5c646b")
const RATE := 22050

var sk: VoxelStKilda
var button: MeshInstance3D
var lamp: MeshInstance3D
var lamp_light: OmniLight3D
var sign_light: OmniLight3D
var sign: Label3D
var prompt := ""                 # what it's showing (tests)
var presses := 0
var _lamp_mat: StandardMaterial3D
var _siren: AudioStreamPlayer3D
var _flash: ColorRect
var _flash_t := 0.0
var _e_down := false
var _hold := 0.0
var _armed := true               # (E let go since the press that started it: the same hold doesn't call it off)
var _t := 0.0

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "InvasionButton"
	var face := SkLunaPark.xf(sk.town)
	var at: Vector3 = sk.global_transform * (face * Vector3(SIDE, 0.0, -INSIDE))
	var front: Vector3 = (sk.global_transform.basis * face.basis) * Vector3(-0.45, 0.0, 1.0)      # (toward you coming in, turned to the path)
	_build()
	global_transform = Transform3D(Basis(Vector3.UP, atan2(front.x, front.z)), Vector3(at.x, 0.0, at.z))
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.08, 0.05, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	sk.arena._hud_layer.add_child(_flash)

# the post (its front along +z): a concrete foot, a steel post, the yellow box with the button on its front, the
# striped hood over it, the sign on a taller pole behind, the lamp on top
func _build() -> void:
	var h := Node3D.new()
	SkModels.box(h, Vector3(0.7, 0.12, 0.6), Vector3(0, 0.06, 0), Color("#9a9a94"))
	SkModels.box(h, Vector3(0.18, 1.0, 0.18), Vector3(0, 0.6, 0), STEEL)
	SkModels.box(h, Vector3(0.12, 2.5, 0.1), Vector3(0, 1.3, -0.2), STEEL.darkened(0.15))               # the sign's pole
	SkModels.box(h, Vector3(0.66, 0.6, 0.3), Vector3(0, BUTTON_Y, 0), YELLOW)                             # the box
	SkModels.box(h, Vector3(0.5, 0.44, 0.02), Vector3(0, BUTTON_Y, 0.155), BLACK)                         # its face plate
	# the hood: a roof and two cheeks, in stripes
	for k in 8:
		var c := YELLOW if k % 2 == 0 else BLACK
		SkModels.box(h, Vector3(0.105, 0.06, 0.62), Vector3(-0.3675 + k * 0.105, BUTTON_Y + 0.36, 0.14), c)
	for k in 8:                               # (its front edge, striped the other way round: seen as you walk up)
		var c := BLACK if k % 2 == 0 else YELLOW
		SkModels.box(h, Vector3(0.105, 0.12, 0.03), Vector3(-0.3675 + k * 0.105, BUTTON_Y + 0.33, 0.455), c)
	for s in [-1.0, 1.0]:
		for k in 5:
			var c := BLACK if k % 2 == 0 else YELLOW
			SkModels.box(h, Vector3(0.05, 0.66, 0.124), Vector3(s * 0.395, BUTTON_Y + 0.03, -0.108 + k * 0.124), c)
	# the sign: a red board in a striped frame
	SkModels.box(h, Vector3(1.5, 0.5, 0.06), Vector3(0, 2.25, -0.2), RED.darkened(0.25))
	for k in 12:
		var c := YELLOW if k % 2 == 0 else BLACK
		for y in [2.25 + 0.28, 2.25 - 0.28]:
			SkModels.box(h, Vector3(0.13, 0.07, 0.08), Vector3(-0.715 + k * 0.13, y, -0.2), c)
	for s in [-1.0, 1.0]:
		SkModels.box(h, Vector3(0.07, 0.63, 0.08), Vector3(s * 0.785, 2.25, -0.2), BLACK)
	SkModels.box(h, Vector3(0.2, 0.08, 0.2), Vector3(0, 2.62, -0.2), BLACK)                               # the lamp's foot
	var mi := MeshInstance3D.new()
	mi.name = "Post"
	mi.mesh = SkModels.bake(h)
	mi.material_override = SkModels.baked_material()
	h.free()
	add_child(mi)
	# the button: a red mushroom on a dark collar, moved in and out
	var collar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 0.1
	collar.mesh = cm
	collar.rotation.x = PI / 2.0
	collar.position = Vector3(0, BUTTON_Y, 0.17)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#2b2d30")
	collar.material_override = dark
	add_child(collar)
	button = MeshInstance3D.new()
	button.name = "Button"
	var dome := SphereMesh.new()
	dome.radius = 0.21
	dome.height = 0.2
	dome.is_hemisphere = true
	button.mesh = dome
	button.rotation.x = PI / 2.0              # (its round top toward you)
	button.position = Vector3(0, BUTTON_Y, BUTTON_OUT)
	var red := StandardMaterial3D.new()
	red.albedo_color = RED
	red.roughness = 0.35
	red.emission_enabled = true
	red.emission = RED
	red.emission_energy_multiplier = 0.7
	button.material_override = red
	add_child(button)
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "INVASION"
		l.font_size = 96
		l.pixel_size = 0.0026
		l.outline_size = 14
		l.modulate = Color("#fff3c4")
		l.outline_modulate = Color("#2a0705")
		l.position = Vector3(0, 2.25, -0.2 + side * 0.035)
		l.rotation.y = 0.0 if side > 0.0 else PI
		add_child(l)
		if side > 0.0:
			sign = l
	lamp = MeshInstance3D.new()
	lamp.name = "Lamp"
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	lamp.mesh = sm
	lamp.position = Vector3(0, 2.76, -0.2)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color("#5a1512")
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color("#ff2a1a")
	_lamp_mat.emission_energy_multiplier = 0.0
	lamp.material_override = _lamp_mat
	add_child(lamp)
	lamp_light = OmniLight3D.new()
	lamp_light.light_color = Color("#ff3a24")
	lamp_light.omni_range = 9.0
	lamp_light.light_energy = 0.0
	lamp_light.visible = false
	lamp_light.position = Vector3(0, 2.8, 0.1)
	add_child(lamp_light)
	sign_light = OmniLight3D.new()            # (night: the sign and the button lit)
	sign_light.light_color = Color("#ffe2a8")
	sign_light.omni_range = 4.5
	sign_light.light_energy = 0.0
	sign_light.visible = false
	sign_light.position = Vector3(0, 1.9, 0.9)
	add_child(sign_light)
	var body := StaticBody3D.new()
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 2.6, 0.5)
	cs.shape = bs
	cs.position = Vector3(0, 1.3, -0.05)
	body.add_child(cs)
	add_child(body)
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = siren()
	_siren.unit_size = 14.0
	_siren.max_distance = 140.0
	_siren.position = Vector3(0, 2.7, 0)
	add_child(_siren)

## An air-raid siren winding up (made in code, as SkSounds'): its note climbing over 3 s, held wavering, dying away.
static func siren() -> AudioStreamWAV:
	var length := 6.0
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var up := 1.0 - exp(-t * 1.1)
		var f := 170.0 + 520.0 * up + 14.0 * sin(TAU * 0.9 * t) * up
		if t > 4.6:
			f *= 1.0 - 0.3 * (t - 4.6) / 1.4          # (running down)
		ph += f / RATE
		var x := fmod(ph, 1.0)
		var tone := 0.55 * sin(TAU * x) + 0.22 * sin(TAU * 2.0 * x) + 0.12 * sin(TAU * 3.0 * x) + 0.1 * (2.0 * x - 1.0)
		var env := minf(1.0, t / 0.25) * minf(1.0, (length - t) / 1.3)
		s[i] = tone * env * 0.7
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

## Where the button is (the world).
func button_at() -> Vector3:
	return global_transform * Vector3(0, BUTTON_Y, BUTTON_OUT)

func on() -> bool:
	return sk.invasion != null and sk.invasion.running

## You can reach it and you're looking at it (top-down: just by it).
func looked_at() -> bool:
	var a := sk.arena
	if not sk.active or a.down_t > 0.0 or sk.riding() or sk.near_ride or (a.phone and a.phone.is_open()):
		return false
	if sk.hack and (sk.hack._open or (sk.hack._cam and sk.hack._cam.current)):
		return false
	var pp := a.player.global_position
	var at := button_at()
	if Vector2(at.x - pp.x, at.z - pp.z).length() > REACH:
		return false
	if a.top_down:
		return true
	var eye: Vector3 = a.cam.global_position if a.cam.current else pp + Vector3(0, 1.6, 0)
	var look := Vector3(-sin(a.look_yaw) * cos(a.look_pitch), sin(a.look_pitch), -cos(a.look_yaw) * cos(a.look_pitch))
	var best := 0.0
	for y in [0.0, 0.95]:                      # (the button, or the sign over it)
		best = maxf(best, look.dot((at + Vector3(0, y, 0) - eye).normalized()))
	return best > LOOKING

## The button pushed: the invasion starts round you.
func press() -> void:
	if on():
		return
	presses += 1
	_armed = not _e_down
	_hold = 0.0
	var a := sk.arena
	a.sound.play("slam", button_at(), -3.0, 1.5)
	a.sound.play("switch", button_at(), 0.0, 0.7)
	_siren.volume_db = a.sound.volume_db + 2.0
	_siren.play()
	_flash_t = 1.0
	sk.invasion.start(true)
	a.say("INVASION!", 2.5)

## Called off: its enemies gone, the park as it was.
func call_off() -> void:
	_hold = 0.0
	if not on():
		return
	sk.invasion.stop()
	_siren.stop()
	sk.arena.sound.play("switch", button_at(), 0.0, 1.2)
	sk.arena.say("Invasion called off", 2.0)

## Leaving St Kilda: quiet, nothing on screen.
func reset() -> void:
	_siren.stop()
	_flash_t = 0.0
	_flash.visible = false
	_hold = 0.0
	prompt = ""

func _process(dt: float) -> void:
	_t += dt
	var running := on()
	# the button down while it's on, the lamp flashing; the sign lit at night
	var want := BUTTON_OUT - (PRESS if running else 0.0)
	button.position.z = move_toward(button.position.z, want, dt * (1.2 if running else 0.25))
	var blink := 0.0
	if running:
		blink = 1.0 if fmod(_t, 0.5) < 0.25 else 0.12
	_lamp_mat.emission_energy_multiplier = blink * 4.0
	lamp_light.visible = running
	lamp_light.light_energy = blink * 3.0
	var night: float = sk.day_night.t if sk.day_night else 0.0
	sign_light.visible = night > 0.02
	sign_light.light_energy = night * 1.6
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - dt / 0.9)
		_flash.visible = _flash_t > 0.0
		_flash.color.a = 0.42 * _flash_t * _flash_t
	if not running and _siren.playing:
		_siren.stop()                         # (stopped some other way: the phone)
	prompt = ""
	if not looked_at():
		_hold = 0.0
		return
	if not running:
		prompt = "E  start the invasion"
	elif _e_down and _armed:
		_hold += dt
		if _hold >= CALL_OFF:
			call_off()
			_armed = false                    # (let go of E before the next press counts)
			prompt = "E  start the invasion"
		else:
			var bar := int(_hold / CALL_OFF * 10.0)
			prompt = "E  call off the invasion  [%s%s]" % ["#".repeat(bar), "-".repeat(10 - bar)]
	else:
		_hold = 0.0
		prompt = "E  call off the invasion (hold)"
	sk.arena._use_label.text = prompt

func _input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_E and not e.echo:
		_e_down = e.pressed
		if not e.pressed:
			_armed = true
			_hold = 0.0

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_E):
		return
	if not looked_at():
		return
	if not on():
		press()
	get_viewport().set_input_as_handled()
