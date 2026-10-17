class_name LobbySfx
extends Node
## Lobby life's sounds, made in code like the HTML game's (it plays oscillator tones and noise bursts through
## WebAudio): each is rendered once into an AudioStreamWAV and played from a small pool of players.
## Owned by the Lobby life session. (When the shared Sfx autoload arrives, these recipes can move into it.)

const RATE := 22050
var volume_db: float = -8.0
var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next: int = 0

func _ready() -> void:
	for i in 8:
		var a := AudioStreamPlayer.new()
		a.volume_db = volume_db
		add_child(a)
		_players.append(a)

## A tone: type "sine" | "square" | "triangle" | "saw", from f0 to f1 Hz over dur seconds, volume 0..1.
func tone(f0: float, dur: float, type: String = "sine", vol: float = 0.25, f1: float = -1.0, delay: float = 0.0) -> void:
	var key := "t%s|%.1f|%.1f|%.3f|%.2f" % [type, f0, f1, dur, vol]
	_play(key, func() -> PackedFloat32Array: return _tone(f0, f1 if f1 > 0 else f0, dur, type, vol), delay)

## A burst of noise, low-passed (lp 0..1: 1 bright, 0.05 dull), volume 0..1.
func noise(dur: float, vol: float = 0.2, lp: float = 0.5, delay: float = 0.0) -> void:
	var key := "n|%.3f|%.2f|%.2f" % [dur, vol, lp]
	_play(key, func() -> PackedFloat32Array: return _noise(dur, vol, lp), delay)

## The named sounds lobby life uses.
func play(name_: String) -> void:
	match name_:
		"splash":
			noise(0.5, 0.35, 0.25)
			tone(220, 0.25, "sine", 0.12, 90)
		"boing":
			tone(180, 0.28, "triangle", 0.25, 420)
		"clank":
			tone(820, 0.09, "square", 0.12, 600)
			noise(0.06, 0.15, 0.8)
		"plate":
			tone(520, 0.12, "triangle", 0.2, 380)
			noise(0.05, 0.12, 0.9)
		"grunt":
			tone(140, 0.18, "saw", 0.12, 110)
		"bell":
			tone(880, 0.9, "sine", 0.22)
			tone(1320, 0.6, "sine", 0.1)
		"thud":
			tone(90, 0.14, "sine", 0.3, 50)
			noise(0.08, 0.12, 0.2)
		"click":
			tone(1500, 0.03, "square", 0.08)
		"flick":
			noise(0.06, 0.15, 0.9)
			tone(2400, 0.04, "square", 0.05)
		"bubble":
			for i in 5:
				tone(300 + i * 90, 0.07, "sine", 0.12, 520 + i * 90, i * 0.11)
		"cough":
			noise(0.18, 0.3, 0.35)
			noise(0.16, 0.25, 0.35, 0.26)
		"exhale":
			noise(1.1, 0.12, 0.15)
		"card":
			noise(0.05, 0.18, 0.7)
		"win":
			for i in 4:
				tone([523.0, 659.0, 784.0, 1047.0][i], 0.14, "square", 0.1, -1, i * 0.1)
		"lose":
			tone(330, 0.3, "square", 0.08, 160)
		"coin":
			tone(988, 0.07, "square", 0.1)
			tone(1319, 0.18, "square", 0.1, -1, 0.07)
		"spin":
			for i in 10:
				tone(600 + (i % 3) * 100, 0.04, "square", 0.06, -1, i * 0.12)
		"vend":
			tone(200, 0.5, "saw", 0.08, 150)
			tone(110, 0.15, "sine", 0.3, 60, 0.55)
		"sizzle":
			noise(0.7, 0.12, 0.95)
		"chomp":
			noise(0.07, 0.25, 0.4)
			noise(0.07, 0.25, 0.4, 0.16)
		"door":
			tone(160, 0.25, "triangle", 0.15, 120)
		"pop":
			tone(400, 0.08, "sine", 0.25, 900)
		"whoosh":
			noise(0.4, 0.16, 0.3)
		"quack":
			tone(520, 0.12, "saw", 0.1, 380)
			tone(500, 0.1, "saw", 0.08, 360, 0.15)
		"snore":
			noise(0.9, 0.08, 0.08)
		"munch":
			noise(0.08, 0.2, 0.5)
			noise(0.08, 0.2, 0.5, 0.15)
			noise(0.08, 0.2, 0.5, 0.3)
		_:
			tone(660, 0.08, "sine", 0.15)

func _play(key: String, make: Callable, delay: float) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): _play(key, make, 0.0))
		return
	var s: AudioStreamWAV = _cache.get(key, null)
	if s == null:
		s = _wav(make.call())
		_cache[key] = s
	var a := _players[_next]
	_next = (_next + 1) % _players.size()
	a.stream = s
	a.volume_db = volume_db
	a.play()

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

static func _env(i: int, n: int) -> float:
	# a quick attack and an exponential-ish fade, like the HTML game's gain ramps
	var t := float(i) / maxf(1.0, n)
	return minf(1.0, i / 120.0) * pow(1.0 - t, 1.6)

func _tone(f0: float, f1: float, dur: float, type: String, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var f := lerpf(f0, f1, float(i) / maxf(1.0, n))
		ph = fmod(ph + f / RATE, 1.0)
		var v: float
		match type:
			"square":
				v = 1.0 if ph < 0.5 else -1.0
			"triangle":
				v = 4.0 * absf(ph - 0.5) - 1.0
			"saw":
				v = ph * 2.0 - 1.0
			_:
				v = sin(ph * TAU)
		out[i] = v * vol * _env(i, n)
	return out

func _noise(dur: float, vol: float, lp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		y += (randf() * 2.0 - 1.0 - y) * clampf(lp, 0.01, 1.0)
		out[i] = y * vol * 2.0 * _env(i, n)
	return out
