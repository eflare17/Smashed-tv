class_name ZombieSfx
extends Node3D
## The zombie's voice, made in code like the rest of the game's sounds (lobby_sfx.gd): a rough voice (a jittery
## pulse train) through vowel formants (band-pass filters) with breath noise, for the groans, the scream, the
## snarl of a swipe, the grunt when hit and the death rattle; brown noise crumbling for climbing out of the
## ground. Each is rendered once into an AudioStreamWAV (a few a frame, ahead of the first night) and played where
## the zombie is (AudioStreamPlayer3D: it comes from its side in first person). The Master bus mute (Hud's sound
## button, F9) silences it with everything else.
##
## Sim events (ZombieSim.EV_*) are heard here, before the Fight drains them each frame.

const RATE := 22050
const GROANS := 5
var sim: FightSim
var volume_db := -4.0
var _cache: Dictionary = {}
var _todo: Array = []
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "ZombieSfx"
	process_priority = 40          # before the Fight drains the sim's events
	_rng.seed = 7
	for i in 6:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 14.0
		a.max_db = 3.0
		a.attenuation_filter_cutoff_hz = 9000.0
		a.panning_strength = 0.7
		add_child(a)
		_players.append(a)
	for i in GROANS:
		_todo.append("groan%d" % i)
	_todo.append_array(["scream", "swipe", "hurt", "death", "rise"])

func _process(_dt: float) -> void:
	# bake ahead, one sound a frame (none in a headless test)
	if not _todo.is_empty() and DisplayServer.get_name() != "headless":
		var k: String = _todo.pop_front()
		if not _cache.has(k):
			_cache[k] = _make(k)
	if sim == null:
		return
	for e in sim.events:
		var p := GameData.world_to_3d(float(e[1]), float(e[2]), 50.0)
		match int(e[0]):
			ZombieSim.EV_SCREAM: play_at("scream", p)
			ZombieSim.EV_SWIPE: play_at("swipe", p)
			ZombieSim.EV_RISE: play_at("rise", p)
			ZombieSim.EV_SINK: play_at("rise", p, -6.0)

## Plays a named sound at a 3D point.
func play_at(k: String, pos: Vector3, db := 0.0) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if k == "groan":
		k = "groan%d" % _rng.randi_range(0, GROANS - 1)
	var s: AudioStreamWAV = _cache.get(k)
	if s == null:
		s = _make(k)
		_cache[k] = s
	var a := _players[_next]
	_next = (_next + 1) % _players.size()
	a.stream = s
	a.volume_db = volume_db + db
	a.pitch_scale = _rng.randf_range(0.92, 1.08)
	a.global_position = pos
	a.play()

# ---------------------------------------------------------------- the recipes

func _make(k: String) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = hash(k)
	var out: PackedFloat32Array
	if k.begins_with("groan"):
		var v := int(k.trim_prefix("groan"))
		var dur := 1.1 + 0.25 * v
		var f0 := 74.0 + 9.0 * v
		out = _voice(dur, f0, f0 * 0.8, [480.0 + 40 * v, 850.0, 2300.0], 0.5, 0.35, r)
		out = _env(out, 0.25, 0.5)
	else:
		match k:
			"scream":
				out = _voice(1.6, 190.0, 150.0, [820.0, 1250.0, 2800.0], 0.9, 0.6, r, 300.0)
				out = _drive(out, 3.0)
				out = _env(out, 0.12, 0.35)
			"swipe":
				var w := _band(_noise(0.32, r), 900.0, 2.0)
				w = _env(w, 0.4, 0.5)
				var g := _env(_voice(0.42, 120.0, 95.0, [600.0, 1000.0, 2500.0], 0.7, 0.5, r), 0.05, 0.6)
				out = _add(_gain(w, 1.4), g)
			"hurt":
				out = _env(_voice(0.32, 105.0, 80.0, [550.0, 950.0, 2400.0], 0.8, 0.4, r), 0.02, 0.7)
				out = _drive(out, 1.8)
			"death":
				var gr := _env(_voice(1.5, 110.0, 52.0, [520.0, 820.0, 2200.0], 0.75, 0.5, r), 0.05, 0.75)
				var thud := _thud(0.5, r)
				out = _add(gr, _delay(thud, 0.95))
			"rise":
				var dirt := _band(_brown(1.6, r), 300.0, 0.7)
				for i in 26:
					var at := int(r.randf() * dirt.size() * 0.9)
					for j in 300:
						if at + j < dirt.size():
							dirt[at + j] += (r.randf() * 2.0 - 1.0) * 0.5 * exp(-j / 60.0)
				dirt = _env(dirt, 0.2, 0.4)
				var low := _env(_voice(1.4, 68.0, 60.0, [420.0, 760.0, 2100.0], 0.35, 0.3, r), 0.5, 0.4)
				out = _add(_gain(dirt, 0.9), _delay(low, 0.3))
			_:
				out = _env(_voice(0.6, 90.0, 80.0, [500.0, 900.0, 2300.0], 0.5, 0.3, r), 0.1, 0.5)
	return _wav(_norm(out, 0.8))

## A rough voice: a pulse train sliding f0 -> f1 with jitter and a slow wobble, through three formants, plus
## breath noise through the same. rough: jitter amount; breath: noise level; vib: wobble depth in Hz.
func _voice(dur: float, f0: float, f1: float, formants: Array, rough: float, breath: float, r: RandomNumberGenerator,
		vib := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var src := PackedFloat32Array()
	src.resize(n)
	var ph := 0.0
	var jit := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t * t) * (1.0 + sin(i / float(RATE) * TAU * 4.5) * 0.04)
		if vib > 0.0:
			f += sin(i / float(RATE) * TAU * 7.0) * vib * sin(t * PI)
		if i % 64 == 0:
			jit = (r.randf() * 2.0 - 1.0) * rough * 0.18
		ph += f * (1.0 + jit) / RATE
		if ph >= 1.0:
			ph -= 1.0
		# a glottal-ish pulse: a sharp rise and a slow fall
		var g := pow(1.0 - ph, 3.0) - 0.25
		src[i] = g + (r.randf() * 2.0 - 1.0) * breath
	var out := PackedFloat32Array()
	out.resize(n)
	var gains := [1.0, 0.6, 0.3]
	for k in formants.size():
		var b := _band(src, float(formants[k]), 4.0 + k * 2.0)
		for i in n:
			out[i] += b[i] * gains[k]
	return out

## A band-pass biquad (RBJ, constant peak gain) at f Hz with Q q.
func _band(x: PackedFloat32Array, f: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * f / RATE
	var al := sin(w0) / (2.0 * q)
	var a0 := 1.0 + al
	var b0 := al / a0
	var b2 := -al / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - al) / a0
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var v := b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = v
		y[i] = v
	return y

func _noise(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(int(dur * RATE))
	for i in o.size():
		o[i] = r.randf() * 2.0 - 1.0
	return o

func _brown(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(int(dur * RATE))
	var v := 0.0
	for i in o.size():
		v = clampf(v + (r.randf() * 2.0 - 1.0) * 0.08, -1.0, 1.0) * 0.998
		o[i] = v
	return o

func _thud(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(int(dur * RATE))
	for i in o.size():
		var t := float(i) / RATE
		o[i] = (sin(TAU * (70.0 - 30.0 * t / dur) * t) * 1.2 + (r.randf() * 2.0 - 1.0) * 0.4 * exp(-t * 30.0)) * exp(-t * 9.0)
	return o

## A swell in (seconds share of attack) and a fade out (share of release).
func _env(x: PackedFloat32Array, att: float, rel: float) -> PackedFloat32Array:
	var n := x.size()
	for i in n:
		var t := float(i) / n
		var g := minf(1.0, t / maxf(0.001, att)) * minf(1.0, (1.0 - t) / maxf(0.001, rel))
		x[i] *= g * g * (3.0 - 2.0 * g)
	return x

func _drive(x: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var m := 0.0
	for v in x:
		m = maxf(m, absf(v))
	m = maxf(m, 0.0001)
	for i in x.size():
		var v := x[i] / m * k
		x[i] = v / (1.0 + absf(v))
	return x

func _gain(x: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in x.size():
		x[i] *= g
	return x

func _delay(x: PackedFloat32Array, secs: float) -> PackedFloat32Array:
	var pad := PackedFloat32Array()
	pad.resize(int(secs * RATE))
	pad.append_array(x)
	return pad

func _add(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(maxi(a.size(), b.size()))
	for i in o.size():
		o[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return o

func _norm(x: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in x:
		m = maxf(m, absf(v))
	if m > 0.0001:
		for i in x.size():
			x[i] *= peak / m
	return x

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = b
	return w

## The baked sound as samples (tests write it to a file to listen to).
func samples_of(k: String) -> AudioStreamWAV:
	return _make(k)
