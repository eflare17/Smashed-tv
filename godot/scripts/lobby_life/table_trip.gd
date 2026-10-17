class_name LobbyTableTrip
extends Node
## The bong trip (specs/table.md section 5, Smashed.html startTrip 5019, TRIP_T 5005, drawTrip 12764, the music
## 5019-5088). Owned by the Lobby life session; part of LobbyTable. Two hits in a row (3 to 30 s apart) start it, on
## this screen only: the screen goes black, a robed praying mantis flickers up out of the dark growing from far away
## to filling the screen (a heartbeat under it, a drone and a whine over it), then it shrieks and the dark lifts.
## 13.8 s in all. Play carries on underneath (nothing is blocked).
##
## It draws in screen space over everything (LobbyUI's fx_root is above the HUD). The HTML game's 860 x 520 screen
## is scaled to the window's height and centred.

const T_DARK := 1.5
const T_SHOW := 3.0
const T_FADE := 11.0
const T_BACK := 12.2
const T_END := 13.8
const RATE := 8000
const MUSIC_SECONDS := 13.0

var table: LobbyTable
var active: bool = false
var t: float = 0.0
## [[start, end, side], ...] when the mantis shows (generated once a trip).
var segs: Array = []

var _screen: Control
var _mantis: Array = []
var _rng := RandomNumberGenerator.new()
var _beat: float = 0.0
var _whoosh: bool = false
var _shriek: bool = false
var _seg_i: int = -1
var _blink: bool = false
var _music: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _music_bytes: PackedByteArray
var _music_i: int = 0
var _music_state: Dictionary = {}
var _building: bool = false

func _ready() -> void:
	_rng.randomize()
	for i in 4:
		_mantis.append(LobbyPic.art("table/trip_mantis_%d.png" % i))
	_screen = _Screen.new()
	_screen.trip = self
	_screen.name = "TripScreen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.visible = false
	table.ll.ui.fx_root.add_child(_screen)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)

static func ease_(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## How black the screen is (the overlay's alpha).
func black() -> float:
	if t < T_DARK:
		return ease_(t / T_DARK)
	if t < T_BACK:
		return 1.0
	return 1.0 - ease_((t - T_BACK) / 1.6)

## The mantis now: {a (alpha), side, k (scale), cx, feet} or an empty dictionary when it isn't showing.
func mantis_now() -> Dictionary:
	if t <= T_SHOW or t >= T_FADE:
		return {}
	var seg := -1
	for i in segs.size():
		if t >= segs[i][0] and t < segs[i][1]:
			seg = i
	if seg < 0:
		return {}
	var a := 1.0
	if seg == 0:
		a = ease_((t - segs[0][0]) / 0.8)
	if _blink:
		a *= 0.2
	var pr := pow((t - T_SHOW) / 8.0, 1.6)
	var k := 0.22 * pow(2.6 / 0.22, pr)
	var side: float = segs[seg][2]
	return {"a": a, "side": side, "k": k, "pr": pr, "cx": 430.0 + side * 60.0 * (1.0 - pr),
		"feet": 270.0 + 390.0 * pr * pr + sin(t * 1.7) * 6.0 * k, "seg": seg}

## startTrip (5019).
func start() -> void:
	active = true
	t = 0.0
	_beat = 0.0
	_whoosh = false
	_shriek = false
	_seg_i = -1
	segs.clear()
	var s := T_SHOW
	while s < T_FADE:
		var on := 0.45 + _rng.randf() * 0.7
		var off := 0.12 + _rng.randf() * 0.4
		segs.append([s, s + on, (_rng.randf() - 0.5) * 2.0])
		s += on + off
	_screen.visible = true
	if _music_stream:
		_music.stream = _music_stream
		_music.volume_db = -7.0
		_music.play()

func stop() -> void:
	active = false
	_screen.visible = false
	_music.stop()

func _process(delta: float) -> void:
	_build_music_step()
	if not active:
		return
	var dt := minf(delta, 0.1)
	t += dt
	_blink = _rng.randf() < dt * 4.0
	var sfx := table.ll.sfx
	# a crackle as each new segment (not the first) starts
	var seg := -1
	for i in segs.size():
		if t >= segs[i][0] and t < segs[i][1]:
			seg = i
	if seg >= 0 and seg != _seg_i:
		if seg > 0:
			sfx.noise(0.12, 0.2, 0.9)
		_seg_i = seg
	if t > 2.4 and not _whoosh:
		_whoosh = true
		sfx.noise(2.0, 0.28, 0.18)
		sfx.tone(250, 2.0, "sine", 0.1, 2600)
	if t >= T_SHOW and t < T_FADE:
		_beat -= dt
		if _beat <= 0.0:
			_beat = 1.15
			sfx.tone(130, 0.16, "sine", 0.35, 60)
			sfx.noise(0.07, 0.15, 0.15)
			sfx.tone(170, 0.14, "sine", 0.22, 70, 0.17)
	if t > T_FADE and not _shriek:
		_shriek = true
		sfx.tone(1400, 0.9, "saw", 0.22, 90)
		sfx.noise(0.5, 0.2, 0.8)
	if t >= T_END:
		stop()
		return
	_screen.queue_redraw()

# ------------------------------------------------------------------ the music (startTrip 5019-5046)

## Starts rendering the drone (a little each frame, so no hitch); called when the bong is taken, well before a trip.
func prepare() -> void:
	if _music_stream != null or _building or DisplayServer.get_name() == "headless":
		return
	_building = true
	_music_i = 0
	_music_bytes = PackedByteArray()
	_music_bytes.resize(int(MUSIC_SECONDS * RATE) * 2)
	_music_state = {"ph": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "lfo": 0.0, "y1": 0.0, "y2": 0.0,
		"delay": PackedFloat32Array(), "di": 0, "vib": 0.0}
	var d: PackedFloat32Array = _music_state.delay
	d.resize(int(0.37 * RATE))
	_music_state.delay = d

func music_ready() -> bool:
	return _music_stream != null

func _build_music_step() -> void:
	if not _building:
		return
	var total := int(MUSIC_SECONDS * RATE)
	var stop_at := mini(total, _music_i + 3000)
	var ph: Array = _music_state.ph
	var d: PackedFloat32Array = _music_state.delay
	var dn := d.size()
	var di: int = _music_state.di
	var y1: float = _music_state.y1
	var y2: float = _music_state.y2
	var lfo: float = _music_state.lfo
	var vib: float = _music_state.vib
	var saws := [110.0, 116.5, 155.6]
	var sg := [0.16, 0.15, 0.1]
	for i in range(_music_i, stop_at):
		var tt := float(i) / RATE
		var x := 0.0
		for k in 3:
			ph[k] = fmod(ph[k] + saws[k] / RATE, 1.0)
			x += (ph[k] * 2.0 - 1.0) * sg[k]
		ph[3] = fmod(ph[3] + 55.0 / RATE, 1.0)
		x += (4.0 * absf(ph[3] - 0.5) - 1.0) * 0.2
		lfo += 0.18 / RATE
		var fc := 650.0 + 420.0 * sin(lfo * TAU)
		var a := 1.0 - exp(-TAU * fc / RATE)
		y1 += a * (x - y1)
		y2 += a * (y1 - y2)
		# the whine: two sines gliding down to 0.94, with a shaky vibrato, through a feedback echo
		vib += 5.3 / RATE
		var glide := 1.0 - 0.06 * minf(tt / 12.0, 1.0)
		var vb := sin(vib * TAU) * 9.0
		ph[4] = fmod(ph[4] + (1244.5 * glide + vb) / RATE, 1.0)
		ph[5] = fmod(ph[5] + (1318.5 * glide + vb) / RATE, 1.0)
		var w := (sin(ph[4] * TAU) + sin(ph[5] * TAU)) * 0.06
		var echo := d[di]
		d[di] = w + echo * 0.5
		di = (di + 1) % dn
		var fader: float
		if tt < 2.5:
			fader = 0.0001 * pow(10000.0, tt / 2.5)
		elif tt < 11.0:
			fader = 1.0
		elif tt < 12.6:
			fader = pow(0.0001, (tt - 11.0) / 1.6)
		else:
			fader = 0.0
		var s := (y2 * 1.5 + w + echo) * 0.7 * fader
		_music_bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	_music_state.di = di
	_music_state.y1 = y1
	_music_state.y2 = y2
	_music_state.lfo = lfo
	_music_state.vib = vib
	_music_i = stop_at
	if stop_at >= total:
		_building = false
		var w2 := AudioStreamWAV.new()
		w2.format = AudioStreamWAV.FORMAT_16_BITS
		w2.mix_rate = RATE
		w2.stereo = false
		w2.data = _music_bytes
		_music_stream = w2
		if active and not _music.playing:
			_music.stream = w2
			_music.volume_db = -7.0
			_music.play(t)

# ------------------------------------------------------------------ drawing (drawTrip 12764)

class _Screen extends Control:
	var trip: LobbyTableTrip
	var _rng := RandomNumberGenerator.new()

	func _draw() -> void:
		if trip == null or not trip.active:
			return
		var vp := size
		var s := vp.y / 520.0
		var ox := (vp.x - 860.0 * s) / 2.0
		var b := trip.black()
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, b))
		var m := trip.mantis_now()
		if not m.is_empty():
			var k: float = m.k
			var a: float = m.a
			var tex: Texture2D = trip._mantis[int(floor(trip.t * 5.0)) % 4]
			if tex:
				var w := 169.0 * k
				var h := 240.0 * k
				var cx: float = m.cx
				var feet: float = m.feet
				# the shadow under it
				var pts := PackedVector2Array()
				for i in 28:
					var an := TAU * i / 28.0
					pts.append(Vector2(ox + (cx + cos(an) * 46.0 * k) * s, (feet + 22.0 * k + sin(an) * 9.0 * k) * s))
				draw_colored_polygon(pts, Color(0x1a / 255.0, 0x1a / 255.0, 0x22 / 255.0, a * 0.5))
				var rect := Rect2(ox + round(cx - w * 0.45) * s, round(feet - h) * s, w * s, h * s)
				draw_texture_rect(tex, rect, false, Color(1, 1, 1, a))
		if b > 0.2:
			_rng.seed = int(trip.t * 60.0) + 7
			for i in 90:
				draw_rect(Rect2(_rng.randf() * vp.x, _rng.randf() * vp.y, 2.0, 2.0), Color(1, 1, 1, 0.05 * b))
