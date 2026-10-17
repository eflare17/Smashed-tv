class_name LobbyShroom
extends LobbyThing
## The mushroom on the lounge floor and its trip (Smashed.html: SHROOM_* @3539, shroomTryEat @3551, endShroom, the
## fade and the colours in drawShroom @4267, shroomMusic @3649, drawShroomPickup @3632). Owned by the Lobby life
## session.
##
## A mushroom grows at (52, 424), bobbing under a rainbow glow. E next to it ("EAT", within 26): the view goes to first
## person (the game's own, with its mouse look and walking) and for T 30 s everything melts: the screen spirals in over
## 2.2 s, then the world wobbles and sways, ghosts double, the hues turn and the picture pulses with the beat (0.21
## s); a rainbow bar along the top runs down with the time; a drone and an arpeggio play. The last 2.5 s spiral back
## out, the view goes back to what it was, and the mushroom regrows 20 s later. While it's on, only that. E on the
## tower does the same trip clock hold (it doesn't run out while he's up the dive tower: pool.on_tower).
##
## Port decisions: one screen-texture shader does the colour and wobble in place of the HTML game's software
## raycaster (its melting walls, rainbow floor and ceiling and its trails and clouds aren't redone: the real
## world just goes psychedelic); the spiral crossfades through the same shader's alpha; the sky/cloud/dive extras
## aren't ported; the drone is a looping sound made in code.

const SPOT := Vector2(52.0, 424.0)
const TIME := 30.0
const IN := 2.2
const OUT := 2.5
const REGROW := 20.0
const BEAT := 0.21

var on: bool = false
var t: float = 0.0                 # the trip's clock (holds on the tower)
var clock: float = 0.0             # always runs: colours, beat, music
var gone_until: float = 0.0
var amp: float = 0.0
var fade: float = 0.0
var hue: float = 0.0

var _pic: LobbyPic
var _glow: Sprite3D
var _layer: CanvasLayer
var _rect: ColorRect
var _bar: ColorRect
var _mat: ShaderMaterial
var _music: AudioStreamPlayer
var _prev_mode: int = 0
var _beat: int = -1
var _now: float = 0.0
var _arp := [0, 3, 5, 7, 10, 12, 15, 17]

func _ready() -> void:
	reach = 60.0
	global_position = GameData.world_to_3d(SPOT.x, SPOT.y, 0.0)
	await get_tree().process_frame
	_pic = LobbyPic.make(LobbyPic.art("machines/shroom_pickup.png"), 1.0, 2.0)
	_pic.top_level = true
	add_child(_pic)
	_glow = Sprite3D.new()
	_glow.texture = _glow_tex()
	_glow.pixel_size = 1.0 * GameData.UNIT
	_glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glow.shaded = false
	_glow.transparent = true
	_glow.top_level = true
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_build_layer()

func _glow_tex() -> Texture2D:
	var n := 44
	var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
			im.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) * 0.8))
	return ImageTexture.create_from_image(im)

func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	_layer.add_child(_rect)
	_bar = ColorRect.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = BAR_SHADER
	bm.shader = bs
	_bar.material = bm
	_bar.visible = false
	_layer.add_child(_bar)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -80.0
	add_child(_music)

# ------------------------------------------------------------------ E

func here() -> bool:
	return not on and _now >= gone_until

func near(p: Node) -> bool:
	return ppos(p).distance_to(SPOT) < 26.0

func label_for(p: Node) -> String:
	if here() and can_start(p) and near(p):
		return "EAT"
	return ""

func act(p: Node) -> void:
	if here() and can_start(p) and near(p):
		eat(p as Player)

## shroomTryEat: the trip begins.
func eat(p: Player) -> void:
	on = true
	t = 0.0
	clock = 0.0
	hue = 0.0
	_beat = -1
	gone_until = INF
	_prev_mode = ll.rig.mode
	ll.rig.capture_mouse = ll.rig.capture_mouse
	ll.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	p.look_ang = atan2(p.facing.y, p.facing.x)
	_rect.visible = true
	_bar.visible = true
	ll.sfx.noise(1.8, 0.3, 0.6)
	_start_music()
	ll.ui.info("", 0.0)

## endShroom: back to the lobby; the mushroom grows back in 20 s.
func end_trip() -> void:
	on = false
	gone_until = _now + REGROW
	_rect.visible = false
	_bar.visible = false
	amp = 0.0
	fade = 0.0
	ll.rig.set_mode(_prev_mode)
	_stop_music()
	ll.sfx.noise(1.6, 0.25, 0.3)

# ------------------------------------------------------------------ every frame

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	_now += dt
	_show_pickup()
	if not on:
		return
	clock += dt
	var p := ll.player
	# the trip clock holds up the dive tower (and so does not run out while falling)
	var up := false
	var pool = ll.things.get("pool")
	if pool and pool.has_method("on_tower"):
		up = bool(pool.on_tower(p))
	if not (up and t >= TIME - OUT - 0.2):
		t += dt
	if t >= TIME:
		end_trip()
		return
	var f := t / IN
	if t < IN:
		fade = _ease(f)
	elif t > TIME - OUT - 0.0:
		fade = _ease((TIME - t) / OUT)
	else:
		fade = 1.0
	amp = 0.4 + 0.6 * fade
	hue += dt * 45.0
	var pulse := pow(1.0 - fmod(clock, BEAT) / BEAT, 3.0)
	_mat.set_shader_parameter("amp", amp)
	_mat.set_shader_parameter("t", clock)
	_mat.set_shader_parameter("hue", deg_to_rad(fmod(hue, 360.0)))
	_mat.set_shader_parameter("fade", fade)
	_mat.set_shader_parameter("pulse", pulse)
	var vs := get_viewport().get_visible_rect().size
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(vs.x * (1.0 - t / TIME), 4.0)
	_bar.material.set_shader_parameter("t", clock)
	var b := int(clock / BEAT)
	if b != _beat:
		_beat = b
		if fade > 0.2:
			var n: int = _arp[(b * 3 + (b >> 3)) % 8]
			ll.sfx.tone(196.0 * pow(2.0, n / 12.0), 0.3, "triangle" if b % 4 != 0 else "square", 0.045 * fade * 4.0, 196.0 * pow(2.0, n / 12.0) * 1.004)
	_music.volume_db = lerpf(-30.0, -10.0, fade)

static func _ease(f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)

## drawShroomPickup: the mushroom bobbing under a glow that turns through the colours.
func _show_pickup() -> void:
	var v := here()
	if _pic:
		_pic.visible = v
		_glow.visible = v
		if v:
			var bob := roundf(sin(_now * 2.2))
			_pic.global_position = GameData.world_to_3d(SPOT.x, SPOT.y, bob)
			_glow.global_position = GameData.world_to_3d(SPOT.x, SPOT.y, 12.0)
			var h := fmod(_now * 90.0, 360.0) / 360.0
			_glow.modulate = Color.from_hsv(h, 0.6, 1.0, 0.35 + 0.15 * sin(3.0 * _now))

# ------------------------------------------------------------------ the music

func _start_music() -> void:
	if _music.stream == null:
		_music.stream = _drone()
	_music.volume_db = -40.0
	_music.play()

func _stop_music() -> void:
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -70.0, 2.0)
	tw.tween_callback(_music.stop)

## shroomMusic's drone: saw 98 and 98.9, triangle 147, sine 196.4, a slow wobble; 10 s so every pitch loops cleanly.
func _drone() -> AudioStreamWAV:
	var rate := 11025
	var secs := 10
	var n := rate * secs
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		var s := 0.0
		s += (fposmod(tt * 98.0, 1.0) * 2.0 - 1.0) * 0.09
		s += (fposmod(tt * 98.9, 1.0) * 2.0 - 1.0) * 0.09
		s += (absf(fposmod(tt * 147.0, 1.0) * 4.0 - 2.0) - 1.0) * 0.08
		s += sin(TAU * 196.4 * tt + sin(TAU * 0.5 * tt) * 0.4) * 0.06
		var cut := 0.12 + 0.07 * sin(TAU * 0.3 * tt)
		lp += (s - lp) * cut
		var v := int(clampf(lp * 3.0, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(55.0, 440.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	tl.later(0.8, func(): tl.use())
	tl.later(0.9, func(): t = 8.0)

const SHADER := """
shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear, repeat_disable;
uniform float amp = 0.5;
uniform float t = 0.0;
uniform float hue = 0.0;
uniform float fade = 1.0;
uniform float pulse = 0.0;

vec3 hue_rot(vec3 c, float a) {
	float cs = cos(a);
	float sn = sin(a);
	return vec3(
		dot(c, vec3(0.213 + cs * 0.787 - sn * 0.213, 0.715 - cs * 0.715 - sn * 0.715, 0.072 - cs * 0.072 + sn * 0.928)),
		dot(c, vec3(0.213 - cs * 0.213 + sn * 0.143, 0.715 + cs * 0.285 + sn * 0.140, 0.072 - cs * 0.072 - sn * 0.283)),
		dot(c, vec3(0.213 - cs * 0.213 - sn * 0.787, 0.715 - cs * 0.715 + sn * 0.715, 0.072 + cs * 0.928 + sn * 0.072)));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float sp = 1.0 - fade;
	float ang = sp * 1.4;
	c = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * c / (1.0 + sp * 1.2);
	uv = c + 0.5;
	uv.x += (sin(uv.y * 14.0 + t * 2.1) * 0.010 + sin(uv.y * 5.0 - t * 1.1) * 0.008) * amp;
	uv.y += sin(uv.x * 11.0 + t * 1.7) * 0.008 * amp;
	vec3 col = texture(scr, uv).rgb;
	vec3 g = texture(scr, uv + vec2(0.012 * amp, 0.0)).rgb + texture(scr, uv - vec2(0.012 * amp, 0.0)).rgb;
	col = mix(col, max(col, g * 0.5), 0.5 * amp);
	col = hue_rot(col, hue);
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(l), col, 1.3 + 0.5 * amp);
	vec3 rb = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + t * 0.2 + uv.x * 0.6 + uv.y * 0.4));
	col = mix(col, col * rb * 1.7, (0.25 + 0.15 * sin(1.3 * t)) * amp);
	col *= 0.85 + 0.3 * pulse;
	COLOR = vec4(col, fade);
}
"""

const BAR_SHADER := """
shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	float h = fract(UV.x * 1.0 + t * 0.33);
	vec3 c = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	COLOR = vec4(mix(vec3(1.0), c, 0.8) * 0.9, 1.0);
}
"""
