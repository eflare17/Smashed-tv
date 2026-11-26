extends Node
## Smash arcade sounds, all synthesised once at start-up into short AudioStreamWAVs (no audio files): bleepy
## tones and filtered noise in the style of the other cabinets' ArcadeSfx, plus the TV host's "voice", a
## gibberish babble with one syllable per syllable of his line. Played on a small pool of players; the gun and
## the host have a player each so rapid fire and speech never steal each other's voice.

const RATE := 22050
const VOICES := 10

## Off: silent (the attract demo and the bench).
var enabled := true
var volume_db := -4.0

var _sounds := {}
var _lines := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _gun: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _last := {}

func _init() -> void:
	name = "SmashSfx"
	for i in VOICES:
		_players.append(_player())
	_gun = _player()
	_voice = _player()
	_sounds["shot"] = _mix([_tone(0.07, 1100, 400, 0.22, "square"), _noise(0.05, 0.5, 0.18)])
	_sounds["spread"] = _mix([_tone(0.09, 800, 300, 0.22, "square"), _noise(0.08, 0.4, 0.2)])
	_sounds["rocket"] = _mix([_noise(0.3, 0.12, 0.4), _tone(0.3, 180, 520, 0.12, "saw")])
	_sounds["boom"] = _mix([_noise(0.75, 0.07, 0.9), _tone(0.5, 90, 35, 0.7, "sine")])
	_sounds["splat"] = _mix([_noise(0.16, 0.25, 0.45), _tone(0.12, 160, 60, 0.4, "sine")])
	_sounds["thud"] = _wav(_tone(0.08, 180, 90, 0.35, "square"))
	_sounds["brute_die"] = _mix([_noise(0.45, 0.1, 0.6), _tone(0.4, 300, 50, 0.35, "square")])
	_sounds["die"] = _mix([_tone(0.8, 700, 60, 0.35, "square"), _noise(0.5, 0.2, 0.3)])
	_sounds["pickup"] = _notes([660, 880, 1100, 1320], 0.07, 0.25, "square")
	_sounds["wave"] = _notes([523, 659, 784, 1046], 0.11, 0.25, "square")
	_sounds["door"] = _notes([784, 1046, 784, 1046], 0.16, 0.35, "sine")
	_sounds["gameover"] = _notes([392, 330, 262, 196], 0.26, 0.3, "square")
	_sounds["blip"] = _wav(_tone(0.05, 900, 900, 0.2, "square"))
	_sounds["coin"] = _notes([988, 1318], 0.12, 0.28, "square")
	_sounds["bomb"] = _mix([_noise(1.4, 0.05, 0.7), _tone(1.2, 70, 25, 0.55, "sine"), _noise(0.4, 0.8, 0.25)])
	_sounds["roar"] = _mix([_tone(0.9, 110, 55, 0.5, "saw"), _tone(0.9, 82, 41, 0.4, "square"), _noise(0.9, 0.15, 0.35)])
	_sounds["charge"] = _mix([_tone(0.5, 120, 480, 0.35, "saw"), _noise(0.5, 0.3, 0.2)])
	_sounds["sniper"] = _mix([_tone(0.12, 1500, 700, 0.18, "square"), _noise(0.06, 0.7, 0.12)])
	_sounds["mine"] = _wav(_tone(0.06, 1700, 1700, 0.18, "square"))
	_sounds["throw"] = _mix([_noise(0.25, 0.2, 0.3), _tone(0.2, 300, 150, 0.15, "square")])
	_sounds["cash"] = _notes([1318, 1760], 0.06, 0.2, "square")
	_sounds["prize"] = _notes([784, 988, 1175, 1568], 0.08, 0.25, "square")
	_sounds["car"] = _notes([523, 659, 784, 659, 784, 1046], 0.13, 0.28, "square")

func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	return p

## Plays a named sound; `min_gap` seconds since its last play or it's skipped (so 30 kills aren't 30 splats).
func play(sound: String, min_gap := 0.0, db := 0.0) -> void:
	if not enabled or not _sounds.has(sound):
		return
	var now := Time.get_ticks_msec() * 0.001
	if min_gap > 0.0 and now - float(_last.get(sound, -100.0)) < min_gap:
		return
	_last[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sounds[sound]
	p.volume_db = volume_db + db
	p.play()

func gun(sound: String) -> void:
	if not enabled:
		return
	_gun.stream = _sounds[sound]
	_gun.volume_db = volume_db - 6.0
	_gun.play()

## The host's babble for `text` (made the first time it's needed). Returns its length in seconds.
func say(text: String) -> float:
	if not _lines.has(text):
		_lines[text] = _babble(text)
	var s: AudioStreamWAV = _lines[text]
	if enabled:
		_voice.stream = s
		_voice.volume_db = volume_db + 2.0
		_voice.play()
	return s.get_length()

func stop_voice() -> void:
	_voice.stop()

static func _env(t: float, dur: float, gain: float) -> float:
	# 3 ms attack, then an exponential fall to nothing at `dur`
	var a := minf(1.0, t / 0.003)
	return a * gain * pow(0.001, clampf(t / dur, 0.0, 1.0))

static func _tone(dur: float, f0: float, f1: float, gain: float, wave: String) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, t / dur)
		ph = fmod(ph + f / RATE, 1.0)
		var v := 0.0
		match wave:
			"square": v = 1.0 if ph < 0.5 else -1.0
			"saw": v = ph * 2.0 - 1.0
			_: v = sin(ph * TAU)
		out[i] = v * _env(t, dur, gain)
	return out

## White noise through a one-pole low-pass (`a` near 1 = bright, near 0 = dull).
static func _noise(dur: float, a: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		y += a * (randf_range(-1.0, 1.0) - y)
		out[i] = y * _env(float(i) / RATE, dur, gain) * 2.0
	return out

static func _notes(freqs: Array, each: float, gain: float, wave: String) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for k in freqs.size():
		# the last note rings longer
		out.append_array(_tone(each * (2.5 if k == freqs.size() - 1 else 1.0), freqs[k], freqs[k], gain, wave))
	return _wav(out)

static func _mix(parts: Array) -> AudioStreamWAV:
	var n := 0
	for p: PackedFloat32Array in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p: PackedFloat32Array in parts:
		for i in p.size():
			out[i] += p[i]
	return _wav(out)

## Gibberish speech: a buzzy pulse at a talking pitch, one blip per syllable, words split by short gaps, the
## pitch wandering per syllable and jumping up at the end of an exclamation.
static func _babble(text: String) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var words := text.split(" ", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text)
	var shout := text.ends_with("!")
	for w in words.size():
		var syl := _syllables(words[w])
		for s in syl:
			var last := w == words.size() - 1 and s == syl - 1
			var dur := 0.2 if last else rng.randf_range(0.09, 0.13)
			var f := 150.0 * rng.randf_range(0.85, 1.3) * (1.5 if last and shout else 1.0)
			var bright := rng.randf_range(0.12, 0.35)
			var n := int(dur * RATE)
			var ph := 0.0
			var y := 0.0
			for i in n:
				var t := float(i) / RATE
				ph = fmod(ph + f * (1.0 + 0.04 * sin(t * 40.0)) / RATE, 1.0)
				y += bright * ((1.0 if ph < 0.3 else -0.4) - y)
				var env := minf(1.0, t / 0.01) * minf(1.0, (dur - t) / 0.03)
				out.append(y * env * 0.5)
			out.append_array(_silence(0.025))
		out.append_array(_silence(0.07))
	return _wav(out)

static func _syllables(word: String) -> int:
	var n := 0
	var prev := false
	for c in word.to_lower():
		var v := c in "aeiouy"
		if v and not prev:
			n += 1
		prev = v
	return maxi(1, n)

static func _silence(secs: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(secs * RATE))
	return s

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
