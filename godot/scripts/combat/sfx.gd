class_name Sfx
extends Node
## The HTML game's sounds (Smashed.html L11152-11382: sNoise, sTone, sClip, vary, startWhistle, SFX.*), baked.
##
## Web Audio filter sweeps don't map onto Godot's bus effects, so each recipe is synthesised into an
## AudioStreamWAV the first time it's asked for (mono 16-bit, 22050 Hz) and cached: an oscillator with the
## exponential frequency ramp, white noise through an RBJ biquad (Web Audio's lowpass/bandpass) with the
## exponential cutoff sweep, an exponential gain envelope to 0.0008. vary() is done by baking a few variants and
## picking one. Played on a pool of AudioStreamPlayers, master gain 0.5 like audioInit.
##
## The three recordings (pistol x6, nuke, whistle) are in assets/sounds.
## One instance (Sfx.me) is made by the fighting install; Sfx.play("hit") from anywhere.

static var me: Sfx

const RATE := 22050
const VOICES := 20
const MASTER := 0.5

var muted: bool = false
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}          # recipe key -> AudioStreamWAV
var _noise: PackedFloat32Array
var _clips: Dictionary = {}          # name -> Array[AudioStream]
var _clip_i: Dictionary = {}
var _whistle: AudioStreamPlayer
var _last: Dictionary = {}           # name -> msec last played (to stop a frame's ten hits stacking)

func _enter_tree() -> void:
	me = self

func _exit_tree() -> void:
	if me == self:
		me = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_noise.resize(int(RATE * 1.2))
	for i in _noise.size():
		_noise[i] = rng.randf() * 2.0 - 1.0
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = linear_to_db(MASTER)
		add_child(p)
		_players.append(p)
	_whistle = AudioStreamPlayer.new()
	_whistle.volume_db = linear_to_db(MASTER * 0.9)
	add_child(_whistle)
	for n in ["pistol_0", "pistol_1", "pistol_2", "pistol_3", "pistol_4", "pistol_5"]:
		_add_clip("pistol", "res://assets/sounds/%s.mp3" % n)
	_add_clip("nuke", "res://assets/sounds/nuke.mp3")
	_add_clip("whistle", "res://assets/sounds/whistle.mp3")

func _add_clip(name: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var s = load(path)
	if s is AudioStream:
		if not _clips.has(name):
			_clips[name] = []
		_clips[name].append(s)

## Bake the common sounds now (a little each frame would be nicer; they're small).
func prewarm() -> void:
	for n in ["hit", "kill", "kill_big", "hurt", "down", "shot", "pop", "jab", "cash", "click", "switch",
			"pickup", "throw", "swing", "punch", "rocket", "blast", "splat", "shotgun"]:
		_recipe(n, 0)

# ---------------------------------------------------------------- the recipes (SFX.*, and the one-offs)

## Play a named sound (the HTML game's SFX names and the other recipes in the specs). arg: a power (throw) etc.
static func play(name: String, arg: float = 0.0) -> void:
	if me:
		me._play(name, arg)

func _play(name: String, arg: float) -> void:
	if muted:
		return
	var now := Time.get_ticks_msec()
	if _last.get(name, -1000) > now - 25 and name in ["hit", "kill", "kill_big", "hurt", "cash", "thud"]:
		return
	_last[name] = now
	match name:
		"shot":
			if not _clip("pistol", 0.85, 1.0):
				_voice(_recipe("shot", randi() % 4))
		"shotgun":
			_clip("pistol", 1.0, 0.62)
			_voice(_recipe("shotgun", randi() % 3))
		"blast":
			if not _clip("nuke", 0.75, 1.25):
				_voice(_recipe("blast", 0))
		"nuke_boom":
			if not _clip("nuke", 1.0, 1.0):
				_voice(_recipe("nuke_boom", 0))
		"throw_whole":
			_voice(_recipe("throw", 0))
			_voice(_bake_key("tw%d" % int(arg * 4.0), func(): return _mix([_tone(0.12, 300 + 300 * arg, 700 + 400 * arg, 0.12, "triangle")])))
		_:
			var n := 4 if name in ["hit", "kill", "kill_big", "pop", "jab", "cash", "shot"] else 1
			_voice(_recipe(name, randi() % n))

func _clip(name: String, gain: float, rate: float) -> bool:
	if not _clips.has(name) or _clips[name].is_empty():
		return false
	var list: Array = _clips[name]
	var i: int = _clip_i.get(name, 0)
	_clip_i[name] = (i + 1) % list.size()
	var p := _take()
	p.stream = list[i]
	p.pitch_scale = rate * (0.96 + 0.08 * randf())
	p.volume_db = linear_to_db(MASTER * gain)
	p.play()
	return true

func _voice(s: AudioStream) -> void:
	if s == null:
		return
	var p := _take()
	p.stream = s
	p.pitch_scale = 1.0
	p.volume_db = linear_to_db(MASTER)
	p.play()

func _take() -> AudioStreamPlayer:
	for i in VOICES:
		var p := _players[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	var q := _players[_next]
	_next = (_next + 1) % VOICES
	return q

## The falling-bomb whistle (startWhistle): the clip sped up to end when the bomb lands.
static func whistle(dur: float) -> void:
	if me == null or me.muted:
		return
	me._whistle.stop()
	if me._clips.has("whistle"):
		me._whistle.stream = me._clips["whistle"][0]
		me._whistle.pitch_scale = 2.87 / maxf(0.2, dur)
		me._whistle.play()

static func stop_whistle() -> void:
	if me:
		me._whistle.stop()

func _recipe(name: String, variant: int) -> AudioStream:
	return _bake_key(name + str(variant), func(): return _make(name))

func _bake_key(key: String, make: Callable) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var buf: PackedFloat32Array = make.call()
	var s := _to_wav(buf)
	_cache[key] = s
	return s

static func vary(n: float, amt: float = 0.12) -> float:
	return n * (1.0 + (randf() - 0.5) * amt)

func _make(name: String) -> PackedFloat32Array:
	match name:
		"hit":      # SFX.hit: a wet thud on an enemy
			return _mix([_noise_s(0.075, vary(900), 1.6, 0.24, "lowpass", 240), _tone(0.05, vary(190), 80, 0.10, "triangle")])
		"kill":
			return _mix([_noise_s(0.22, vary(1100), 1.1, 0.36, "lowpass", 130), _tone(0.18, vary(160), 38, 0.22, "sawtooth")])
		"kill_big":
			return _mix([_noise_s(0.34, vary(1100), 1.1, 0.5, "lowpass", 130), _tone(0.26, vary(160), 38, 0.32, "sawtooth")])
		"hurt":
			return _mix([_tone(0.30, 420, 120, 0.34, "sawtooth"), _noise_s(0.16, 1600, 1.4, 0.20, "bandpass", 300)])
		"down":
			return _mix([_tone(0.75, 300, 55, 0.40, "sawtooth"), _noise_s(0.5, 700, 1.0, 0.26, "lowpass", 90)])
		"shot":     # the blaster's fallback (the pistol clip is tried first)
			return _mix([_noise_s(0.07, vary(2600), 1.2, 0.30, "bandpass", 700), _tone(0.06, vary(320), 90, 0.16, "square")])
		"shotgun":
			return _mix([_noise_s(0.26, vary(1500, 0.08), 0.8, 0.55, "lowpass", 180), _noise_s(0.10, vary(3800), 1.0, 0.22, "bandpass", 900),
				_tone(0.20, vary(120), 42, 0.34, "square")])
		"pop":      # the spud gun: a hollow cork pop
			return _mix([_noise_s(0.045, vary(1400, 0.15), 2.2, 0.32, "bandpass", 500), _tone(0.06, vary(520), 180, 0.22, "sine")])
		"jab":      # the stab: a wet crunch
			return _mix([_noise_s(0.10, vary(2400, 0.2), 1.6, 0.55, "bandpass", 380), _noise_s(0.18, vary(700), 0.9, 0.45, "lowpass", 160),
				_tone(0.08, vary(160), 90, 0.24, "triangle")])
		"throw":
			return _mix([_noise_s(0.08, 900, 1.4, 0.16, "bandpass", 300)])
		"pickup":   # shunk
			return _mix([_noise_s(0.12, 600, 1.2, 0.3, "lowpass", 120), _tone(0.08, 220, 160, 0.14, "triangle")])
		"click":
			return _mix([_tone(0.03, 900, 500, 0.12, "square")])
		"splat":
			return _mix([_noise_s(0.12, 500, 1.3, 0.3, "lowpass", 500), _tone(0.06, 140, 60, 0.2, "sine")])
		"swing":    # a punch thrown
			return _mix([_noise_s(0.07, 400, 1.2, 0.12, "bandpass", 120)])
		"punch":    # a punch lands
			return _mix([_noise_s(0.06, 250, 1.6, 0.25, "lowpass", 400), _tone(0.05, 110, 60, 0.18, "sine")])
		"switch":
			return _mix([_tone(0.04, 520, 880, 0.08, "square")])
		"rocket":   # THUNK-whoosh
			return _mix([_tone(0.12, 140, 60, 0.35, "square"), _noise_s(0.55, 1800, 0.8, 0.3, "bandpass", 500)])
		"blast":
			return _mix([_noise_s(0.8, 700, 0.7, 0.8, "lowpass", 60), _tone(0.6, 110, 30, 0.45, "sawtooth")])
		"nuke_boom":
			return _mix([_noise_s(1.1, 700, 0.7, 0.85, "lowpass", 60), _tone(0.9, 90, 26, 0.5, "sawtooth")])
		"empty":
			return _mix([_tone(0.05, 700, 300, 0.15, "square")])
		"bought":
			return _mix([_tone(0.08, 500, 900, 0.2, "square"), _tone(0.25, 90, 60, 0.3, "square")])
		"cash":
			return _mix([_tone(0.07, vary(1180, 0.16), 0, 0.11, "triangle"), _tone(0.09, vary(1760, 0.16), 0, 0.07, "sine")])
		"thud":     # a falling potato lands
			return _mix([_noise_s(0.05, 300, 1.4, 0.14, "lowpass", 300)])
		"jan_down":
			return _mix([_tone(0.2, 300, 120, 0.2, "square")])
		"clank":
			return _mix([_noise_s(0.07, 2200, 3, 0.24, "bandpass", 700), _tone(0.05, 340, 130, 0.12, "square")])
		"whack":
			return _mix([_noise_s(0.22, 900, 1.2, 0.5, "lowpass", 140), _tone(0.18, 150, 50, 0.3, "square")])
		"bounce":   # a launched player hits a wall
			return _mix([_noise_s(0.14, 500, 1.1, 0.34, "lowpass", 90), _tone(0.12, 120, 46, 0.2, "square")])
		"windup":   # new (first person): the batter's tell you can hear
			return _mix([_tone(0.38, 180, 520, 0.12, "sawtooth")])
	return PackedFloat32Array()

# ---------------------------------------------------------------- synthesis

# sTone(dur, f0, f1, gain, wave): f0 ramped exponentially to max(20, f1) over dur (none if f1 is 0); gain from
# `gain` exponentially to 0.0008; stops at dur + 0.02.
func _tone(dur: float, f0: float, f1: float, gain: float, wave: String) -> PackedFloat32Array:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var fe := maxf(20.0, f1) if f1 != 0.0 else f0
	for i in n:
		var t := float(i) / RATE
		var k := minf(1.0, t / dur)
		var f := f0 * pow(fe / f0, k)
		ph = fmod(ph + f / RATE, 1.0)
		var v := 0.0
		match wave:
			"square":
				v = 1.0 if ph < 0.5 else -1.0
			"triangle":
				v = 4.0 * absf(ph - 0.5) - 1.0
			"sawtooth":
				v = 2.0 * ph - 1.0
			_:
				v = sin(ph * TAU)
		out[i] = v * gain * pow(0.0008 / gain, k)
	return out

# sNoise(dur, freq, q, gain, type, sweepTo): looped noise -> biquad -> exponential gain.
func _noise_s(dur: float, freq: float, q: float, gain: float, type: String, sweep: float) -> PackedFloat32Array:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var fe := maxf(40.0, sweep) if sweep > 0.0 else freq
	for i in n:
		var t := float(i) / RATE
		var k := minf(1.0, t / dur)
		if i % 32 == 0:
			var f := clampf(freq * pow(fe / freq, k), 20.0, RATE * 0.45)
			var w0 := TAU * f / RATE
			var cw := cos(w0)
			var sw := sin(w0)
			var alpha: float
			var a0: float
			if type == "bandpass":
				alpha = sw / (2.0 * maxf(0.0001, q))
				b0 = alpha
				b1 = 0.0
				b2 = -alpha
			else:
				# Web Audio's lowpass Q is a resonance in dB
				var qq := pow(10.0, q / 20.0)
				alpha = sw / (2.0 * qq)
				b0 = (1.0 - cw) / 2.0
				b1 = 1.0 - cw
				b2 = (1.0 - cw) / 2.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw / a0
			a2 = (1.0 - alpha) / a0
			b0 /= a0
			b1 /= a0
			b2 /= a0
		var x := _noise[i % _noise.size()]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y * gain * pow(0.0008 / gain, k)
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out

func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
