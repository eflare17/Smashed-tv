class_name VoxelRetroTV
extends Node3D
## The games room's TV and the console under it (Stage 7: "built-in emulator for Mega Drive games, Smash TV etc."):
## a game runs in a libretro core through the voxel_retro GDExtension (RetroCore: Genesis Plus GX for the Mega Drive,
## Master System and Game Gear; Snes9x for the Super Nintendo), at the console's own frame rate, its picture on the TV's
## screen (a CRT look: scanlines, a glow) and its sound coming out of the TV. Sitting on the couch, your keys and pad
## are its controller (player 1; in co-op the guest's are player 2's, whichever seat). Stopped (ejected, or you leave the
## room with it running a while), it saves where you were and carries on from there next time. Owned by the voxel session.

## The systems: the core that plays them, the extensions their game files have.
const SYSTEMS := {
	"md": {"name": "Mega Drive", "core": "genesis_plus_gx_libretro", "ext": ["md", "bin", "gen", "smd"]},
	"snes": {"name": "Super Nintendo", "core": "snes9x_libretro", "ext": ["sfc", "smc"]},
	"sms": {"name": "Master System", "core": "genesis_plus_gx_libretro", "ext": ["sms", "sg"]},
	"gg": {"name": "Game Gear", "core": "genesis_plus_gx_libretro", "ext": ["gg"]},
}
## libretro's joypad buttons
enum { B, Y, SELECT, START, UP, DOWN, LEFT, RIGHT, A, X, L, R }
## The keyboard: arrows or WASD the d-pad; J K L (A B C on a Mega Drive pad; Y B A on a Super Nintendo's), U I O
## (X Y Z; L X R), Enter start, Tab mode / select.
const KEYS := {KEY_UP: UP, KEY_W: UP, KEY_DOWN: DOWN, KEY_S: DOWN, KEY_LEFT: LEFT, KEY_A: LEFT, KEY_RIGHT: RIGHT, KEY_D: RIGHT,
	KEY_J: Y, KEY_K: B, KEY_L: A, KEY_U: L, KEY_I: X, KEY_O: R, KEY_ENTER: START, KEY_KP_ENTER: START, KEY_TAB: SELECT, KEY_SPACE: B}
const PAD := {JOY_BUTTON_A: B, JOY_BUTTON_B: A, JOY_BUTTON_X: Y, JOY_BUTTON_Y: X, JOY_BUTTON_BACK: SELECT, JOY_BUTTON_START: START,
	JOY_BUTTON_LEFT_SHOULDER: L, JOY_BUTTON_RIGHT_SHOULDER: R, JOY_BUTTON_DPAD_UP: UP, JOY_BUTTON_DPAD_DOWN: DOWN,
	JOY_BUTTON_DPAD_LEFT: LEFT, JOY_BUTTON_DPAD_RIGHT: RIGHT}
const SAVES := "user://retro_saves"

var arena: Node3D
var core = null                 # RetroCore (null: the GDExtension isn't there)
var core_file := ""             # the core loaded
var game := {}                  # what's playing: {path, name, sys}, {} nothing
var player_port := -1           # the controller this player holds (sitting on the couch), -1: none
var remote_buttons := 0         # (co-op) the other player's buttons, on port 1
var screen: MeshInstance3D
var _tex: ImageTexture
var _mat: ShaderMaterial
var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _acc := 0.0
var _serial := -1
var _glow: OmniLight3D
var _glow_t := 0.0
var frames_run := 0             # (tests)
var last_frame: Image

static func available() -> bool:
	return ClassDB.class_exists("RetroCore")

## Where a core's library is: beside the exe in a build, in the addon's folder otherwise.
static func core_path(name: String) -> String:
	var ext := ".dll" if OS.get_name() == "Windows" else ".so"
	var beside := OS.get_executable_path().get_base_dir().path_join(name + ext)
	if not OS.has_feature("editor") and FileAccess.file_exists(beside):
		return beside
	var dev := ProjectSettings.globalize_path("res://addons/voxel_retro/bin/cores/" + name + ext)
	return dev if FileAccess.file_exists(dev) else beside

static func system_of(path: String) -> String:
	var e := path.get_extension().to_lower()
	for s in SYSTEMS:
		if e in SYSTEMS[s].ext:
			return s
	return ""

## The TV: screen_size the picture's size (metres), facing -z (the room).
func setup(arena_: Node3D, screen_size: Vector2) -> void:
	arena = arena_
	screen = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = screen_size
	screen.mesh = qm
	screen.rotation.y = PI          # (a quad faces +z: turned to face the room)
	add_child(screen)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D tex : filter_linear;
uniform float on = 0.0;
uniform float lines = 224.0;
void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	uv = 0.5 + c * (1.0 + dot(c, c) * 0.08);              // a little curve, like a tube
	vec3 col = texture(tex, uv).rgb;
	float scan = 0.78 + 0.22 * sin(uv.y * lines * 3.14159);
	float vig = 1.0 - dot(c, c) * 0.9;
	vec3 off = vec3(0.025, 0.03, 0.035) + 0.04 * (1.0 - dot(c, c) * 2.0);
	ALBEDO = mix(off, col * scan * vig * 1.15, on);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) ALBEDO = vec3(0.0);
}
"""
	_mat.shader = sh
	screen.material_override = _mat
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 8.0
	_audio.max_distance = 30.0
	_audio.volume_db = -4.0
	add_child(_audio)
	_glow = OmniLight3D.new()
	_glow.position = Vector3(0, 0, -0.8)
	_glow.omni_range = 4.5
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	add_child(_glow)
	if available():
		core = ClassDB.instantiate("RetroCore")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVES))
		core.set_dirs(ProjectSettings.globalize_path(SAVES), ProjectSettings.globalize_path(SAVES))

func playing() -> bool:
	return not game.is_empty()

## (co-op, a guest) the host's TV picture shown here; null: the host's TV is off.
func show_remote(img: Image) -> void:
	if img == null:
		_mat.set_shader_parameter("on", 0.0)
		_glow.light_energy = 0.0
		last_frame = null
		return
	last_frame = img
	if _tex == null or _tex.get_width() != img.get_width() or _tex.get_height() != img.get_height():
		_tex = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter("tex", _tex)
		_mat.set_shader_parameter("lines", 224.0)
	else:
		_tex.update(img)
	_mat.set_shader_parameter("on", 1.0)

## A game (from the library: {path, name, sys}) put in and switched on. "" or why not.
func play(entry: Dictionary) -> String:
	stop()
	if core == null:
		return "the console plugin isn't there (voxel_retro)"
	var sys := String(entry.get("sys", ""))
	if not SYSTEMS.has(sys):
		return "not a game this TV knows"
	var cf: String = core_path(SYSTEMS[sys].core)
	if cf != core_file:
		if not core.load_core(cf):
			core_file = ""
			return String(core.get_last_error())
		core_file = cf
	if not core.load_game(String(entry.path)):
		return String(core.get_last_error())
	game = entry.duplicate()
	var st := _state_file()
	if FileAccess.file_exists(st):
		core.load_state(FileAccess.get_file_as_bytes(st))       # (carry on where you were)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = core.get_sample_rate()
	gen.buffer_length = 0.12
	_audio.stream = gen
	_audio.play()
	_playback = _audio.get_stream_playback()
	_acc = 0.0
	_serial = -1
	core.take_audio()
	return ""

## Switched off and taken out: where you were saved first.
func stop() -> void:
	if game.is_empty():
		return
	var data: PackedByteArray = core.save_state()
	if not data.is_empty():
		var f := FileAccess.open(_state_file(), FileAccess.WRITE)
		if f:
			f.store_buffer(data)
	core.unload()
	game = {}
	_audio.stop()
	_playback = null
	_mat.set_shader_parameter("on", 0.0)
	_glow.light_energy = 0.0
	last_frame = null               # (or the glow lights up again in its colour)
	player_port = -1

func reset() -> void:
	if playing():
		core.reset()

func _state_file() -> String:
	var n := String(game.get("path", "x")).get_file().md5_text()
	return ProjectSettings.globalize_path(SAVES).path_join(n + ".state")

func _exit_tree() -> void:
	stop()

func _process(dt: float) -> void:
	if game.is_empty():
		_glow_light(dt)
		return
	_buttons()
	var step: float = 1.0 / maxf(30.0, core.get_fps())
	_acc = minf(_acc + dt, step * 4.0)
	var n := 0
	while _acc >= step and n < 3:
		_acc -= step
		core.run()
		frames_run += 1
		n += 1
	if core.get_frame_serial() != _serial:
		_serial = core.get_frame_serial()
		var img: Image = core.get_frame()
		if img:
			last_frame = img
			if _tex == null or _tex.get_width() != img.get_width() or _tex.get_height() != img.get_height():
				_tex = ImageTexture.create_from_image(img)
				_mat.set_shader_parameter("tex", _tex)
				_mat.set_shader_parameter("lines", float(img.get_height()))
			else:
				_tex.update(img)
			_mat.set_shader_parameter("on", 1.0)
	# its sound, out of the TV
	var frames: PackedVector2Array = core.take_audio()
	if _playback and not frames.is_empty():
		var room := _playback.get_frames_available()
		if frames.size() > room:
			frames = frames.slice(frames.size() - room)
		_playback.push_buffer(frames)
	_glow_light(dt)

# the room lit by the picture (its average colour, a few times a second)
func _glow_light(dt: float) -> void:
	_glow_t -= dt
	if _glow_t <= 0.0 and last_frame:
		_glow_t = 0.25
		var small := last_frame.duplicate() as Image
		small.resize(1, 1, Image.INTERPOLATE_LANCZOS)       # (all of it: bilinear only looks at the middle few pixels)
		var c := small.get_pixel(0, 0)
		_glow.light_color = c.lerp(Color.WHITE, 0.2)
		_glow.light_energy = 0.4 + c.get_luminance() * 1.2

# the controller(s): this player's keys and pad when they're holding one, the other player's from the network
func _buttons() -> void:
	core.clear_buttons()
	if player_port >= 0:
		for k in KEYS:
			if Input.is_physical_key_pressed(k):
				core.set_button(player_port, KEYS[k], true)
		for dev in Input.get_connected_joypads():
			for jb in PAD:
				if Input.is_joy_button_pressed(dev, jb):
					core.set_button(player_port, PAD[jb], true)
			var lx := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
			var ly := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
			if lx < -0.5: core.set_button(player_port, LEFT, true)
			if lx > 0.5: core.set_button(player_port, RIGHT, true)
			if ly < -0.5: core.set_button(player_port, UP, true)
			if ly > 0.5: core.set_button(player_port, DOWN, true)
	if remote_buttons != 0:
		for i in 12:
			if (remote_buttons >> i) & 1:
				core.set_button(1, i, true)

## This player's buttons as bits (co-op: sent to the host for player 2).
func my_buttons() -> int:
	var bits := 0
	for k in KEYS:
		if Input.is_physical_key_pressed(k):
			bits |= 1 << int(KEYS[k])
	for dev in Input.get_connected_joypads():
		for jb in PAD:
			if Input.is_joy_button_pressed(dev, jb):
				bits |= 1 << int(PAD[jb])
		var lx := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)      # (the left stick the d-pad, as on player 1's)
		var ly := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
		if lx < -0.5: bits |= 1 << LEFT
		if lx > 0.5: bits |= 1 << RIGHT
		if ly < -0.5: bits |= 1 << UP
		if ly > 0.5: bits |= 1 << DOWN
	return bits
