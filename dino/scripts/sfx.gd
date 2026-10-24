class_name Sfx
extends Node
## Every sound, synthesised at start-up (no sound files): the bite's crunch, the wet tear, the snap at air, the
## prey's cry, the swallow, the jump, the whoosh of the lunge, a body hitting the ground. Played through a small
## pool of players, with a little random pitch so repeats don't sound identical.

const RATE := 22050
const VOICES := 10

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_rng.seed = 11
	_sounds["crunch"] = _make(0.2, _crunch)
	_sounds["tear"] = _make(0.3, _tear)
	_sounds["snap"] = _make(0.09, _snap)
	_sounds["cry"] = _make(0.42, _cry)
	_sounds["gulp"] = _make(0.16, _gulp)
	_sounds["jump"] = _make(0.12, _jump)
	_sounds["whoosh"] = _make(0.12, _whoosh)
	_sounds["thud"] = _make(0.35, _thud)
	_sounds["rip"] = _make(0.45, _rip)
	_sounds["roar"] = _make(0.7, _roar)

func play(sound: String, pitch_jitter := 0.06, db := 0.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sounds[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = db
	p.play()

func _make(secs: float, fn: Callable) -> AudioStreamWAV:
	var n := int(secs * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := clampf(fn.call(t, t / secs), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

# each takes (seconds, 0..1 through the sound)
func _crunch(t: float, k: float) -> float:
	# crackling bone: noise in random bursts, a low thump under it
	var crack := _noise() * (1.0 if _rng.randf() < 0.35 else 0.25)
	return crack * pow(1.0 - k, 2.0) * 0.9 + sin(TAU * 70.0 * t) * exp(-t * 25.0) * 0.8

func _tear(t: float, k: float) -> float:
	# wet: noise wobbling in volume
	return _noise() * (0.5 + 0.5 * sin(TAU * 38.0 * t)) * pow(1.0 - k, 1.5) * 0.55

func _snap(t: float, k: float) -> float:
	return (_noise() * 0.6 + sin(TAU * 900.0 * t) * 0.4) * exp(-t * 60.0)

func _cry(t: float, k: float) -> float:
	# a falling squawk with vibrato, buzzy
	var f := lerpf(820.0, 360.0, k) * (1.0 + sin(TAU * 18.0 * t) * 0.05)
	var ph := fmod(t * f, 1.0)
	return (ph * 2.0 - 1.0) * 0.45 * sin(PI * k) + _noise() * 0.08 * (1.0 - k)

func _gulp(t: float, k: float) -> float:
	return sin(TAU * lerpf(240.0, 80.0, k) * t) * sin(PI * k) * 0.8

func _jump(t: float, k: float) -> float:
	return _noise() * 0.3 * (1.0 - k)

func _whoosh(t: float, k: float) -> float:
	return _noise() * sin(PI * k) * 0.35

func _thud(t: float, k: float) -> float:
	return sin(TAU * lerpf(70.0, 40.0, k) * t) * exp(-t * 9.0) * 0.9 + _noise() * exp(-t * 30.0) * 0.4

## A low roar: a growling buzz that rises then falls, with a rough rasp over it.
func _roar(t: float, k: float) -> float:
	var f := 55.0 + sin(PI * k) * 40.0 + sin(TAU * 7.0 * t) * 4.0
	var ph := fmod(t * f, 1.0)
	var buzz := (ph * 2.0 - 1.0) * 0.5 + sin(TAU * f * 2.0 * t) * 0.25
	var rasp := _noise() * 0.2 * (0.5 + 0.5 * sin(TAU * 31.0 * t))
	return (buzz + rasp) * sin(PI * k) * 0.9

func _rip(t: float, k: float) -> float:
	# something big coming off: a long ragged tear with cracks in it
	var crack := _noise() * (1.0 if _rng.randf() < 0.2 else 0.4)
	return crack * (1.0 - k) * (0.6 + 0.4 * sin(TAU * 23.0 * t)) * 0.8
