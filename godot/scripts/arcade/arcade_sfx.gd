class_name ArcadeSfx
extends Node
## The arcade games' bleeps, made in code like the HTML game's sTone and sNoise (Smashed.html, the sound
## section): an oscillator sweeping exponentially from f0 to f1 while its volume falls away exponentially
## to nothing over dur seconds, into a master volume of 0.5. Each sound is rendered once into a short
## AudioStreamWAV and kept (the games ask for the same few over and over), and played on a small pool of
## players so they can overlap.

const RATE := 22050
const MASTER := 0.5
const VOICES := 8

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
## Off: silent (the tests turn it off).
var enabled: bool = true

func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

## sTone(dur, f0, f1, gain, wave): wave is "sine", "square", "triangle" or "sawtooth".
func tone(dur: float, f0: float, f1: float, gain: float, wave: String = "sine") -> void:
	if not enabled:
		return
	var key := "t%.3f_%d_%d_%.3f_%s" % [dur, int(f0), int(f1), gain, wave]
	if not _cache.has(key):
		_cache[key] = _render_tone(dur, f0, f1, gain, wave)
	_play(_cache[key])

## sNoise(dur, freq, q, gain, type): noise through a filter (lowpass, highpass or bandpass) at freq.
func noise(dur: float, freq: float, q: float, gain: float, type: String = "lowpass") -> void:
	if not enabled:
		return
	var key := "n%.3f_%d_%.2f_%.3f_%s" % [dur, int(freq), q, gain, type]
	if not _cache.has(key):
		_cache[key] = _render_noise(dur, freq, q, gain, type)
	_play(_cache[key])

func _play(s: AudioStreamWAV) -> void:
	if _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.play()

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

static func _env(t: float, dur: float, gain: float) -> float:
	# exponentialRampToValueAtTime(0.0008, dur) from gain
	return gain * pow(0.0008 / maxf(gain, 0.0001), clampf(t / dur, 0.0, 1.0))

static func _render_tone(dur: float, f0: float, f1: float, gain: float, wave: String) -> AudioStreamWAV:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var fe := maxf(20.0, f1) if f1 > 0.0 else f0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * pow(fe / f0, clampf(t / dur, 0.0, 1.0))
		ph = fmod(ph + f / RATE, 1.0)
		var v := 0.0
		match wave:
			"square": v = 1.0 if ph < 0.5 else -1.0
			"triangle": v = 4.0 * absf(ph - 0.5) - 1.0
			"sawtooth": v = 2.0 * ph - 1.0
			_: v = sin(ph * TAU)
		out[i] = v * _env(t, dur, gain) * MASTER
	return _wav(out)

static func _render_noise(dur: float, freq: float, q: float, gain: float, type: String) -> AudioStreamWAV:
	var n := int((dur + 0.02) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# a biquad (the Web Audio one) at freq and q
	var w0 := TAU * freq / RATE
	var alpha := sin(w0) / (2.0 * maxf(q, 0.001))
	var c := cos(w0)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	match type:
		"highpass":
			b0 = (1.0 + c) / 2.0; b1 = -(1.0 + c); b2 = (1.0 + c) / 2.0
		"bandpass":
			b0 = alpha; b1 = 0.0; b2 = -alpha
		_:
			b0 = (1.0 - c) / 2.0; b1 = 1.0 - c; b2 = (1.0 - c) / 2.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * c
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var x := rng.randf() * 2.0 - 1.0
		var y := (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1; x1 = x; y2 = y1; y1 = y
		out[i] = y * _env(float(i) / RATE, dur, gain) * MASTER
	return _wav(out)
