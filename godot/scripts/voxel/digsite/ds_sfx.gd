class_name DsSfx
extends Node3D
## A machine's sound (the owner, 11 Nov: the machines were silent), the digger game's sfx.gd brought over: all made
## here in code, no sound files: a diesel that revs and labours, a hydraulic whine while its rams work, its tracks
## clattering, soil scraping where it cuts and falling where it pours, a beeper backing up. One of these on each
## machine, heard from where it stands, so a mate's machine is heard too; driven by what both games know of it
## (DsMachine: speed, driver, effort_now, cut_now, its load going down). Owned by the voxel session.

const RATE := 22050
const GAIN := 7.0              # dB over the digger game's levels: heard from where the machine stands, they came out quiet

static var _streams := {}

var engine: AudioStreamPlayer3D
var whine: AudioStreamPlayer3D
var clank: AudioStreamPlayer3D
var scrape: AudioStreamPlayer3D
var pour: AudioStreamPlayer3D
var beep: AudioStreamPlayer3D
var _eng := 0.0
var _hyd := 0.0
var _clk := 0.0
var _scr := 0.0
var _pour := 0.0
var _beep_t := 0.0

func setup(size_k: float) -> void:
	_make()
	engine = _player("diesel", 0.78 / clampf(size_k, 0.6, 1.3))    # (a small machine's motor sits higher)
	whine = _player("hydraulic", 1.0)
	clank = _player("clatter", 1.0)
	scrape = _player("scrape", 1.0)
	pour = _player("pour", 1.0)
	beep = _player("beep", 1.0)

func _player(what: String, pitch: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[what]
	p.volume_db = -60.0
	p.pitch_scale = pitch
	p.unit_size = 9.0
	p.max_distance = 70.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.set_meta("pitch", pitch)
	add_child(p)
	return p

func _level(p: AudioStreamPlayer3D, level: float, db: float) -> void:
	# (playing only while it's heard: six machines' loops aren't all mixed in silence)
	if level > 0.004:
		p.volume_db = linear_to_db(level) + db + GAIN
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()

## Each frame: m as it is now
func update(dt: float, m: DsMachine, tracked: bool, pouring: bool) -> void:
	var on := m.driver != 0
	var go := clampf(absf(m.speed) / m.max_speed, 0.0, 1.0)
	var work := clampf(m.effort_now + m.cut_now * 0.6, 0.0, 1.0)
	_eng = lerpf(_eng, 1.0 if on else 0.0, minf(dt * 3.0, 1.0))
	var base: float = engine.get_meta("pitch")
	engine.pitch_scale = lerpf(engine.pitch_scale, base * (0.8 + 0.3 * go + 0.25 * work - 0.12 * m.cut_now), minf(dt * 5.0, 1.0))
	_level(engine, _eng * db_to_linear(-15.0 + 5.0 * maxf(go, work)), 0.0)
	_hyd = lerpf(_hyd, m.effort_now if on else 0.0, minf(dt * 9.0, 1.0))
	whine.pitch_scale = 0.9 + 0.25 * _hyd
	_level(whine, _hyd, -17.0)
	_clk = lerpf(_clk, go if tracked else 0.0, minf(dt * 6.0, 1.0))
	clank.pitch_scale = 0.6 + 0.5 * go
	_level(clank, _clk, -11.0)
	_scr = lerpf(_scr, clampf(m.cut_now, 0.0, 1.0), minf(dt * 7.0, 1.0))
	scrape.pitch_scale = 0.8 + 0.35 * go
	_level(scrape, _scr, -5.0)
	_pour = lerpf(_pour, 1.0 if pouring else 0.0, minf(dt * 8.0, 1.0))
	_level(pour, _pour, -7.0)
	# backing up: a beep twice a second
	if on and m.speed < -0.15:
		_beep_t -= dt
		if _beep_t <= 0.0:
			_beep_t = 0.55
			beep.volume_db = -14.0 + GAIN
			beep.play()
	else:
		_beep_t = 0.0

# ---------------------------------------------------------------- the sounds (the digger game's, made once)

static func _make() -> void:
	if not _streams.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_streams["diesel"] = _wav(_diesel(rng), true)
	_streams["hydraulic"] = _wav(_hydraulic(), true)
	_streams["clatter"] = _wav(_clatter(rng), true)
	_streams["scrape"] = _wav(_noise(rng, 0.18, 700, 1.6), true)
	_streams["pour"] = _wav(_noise(rng, 0.3, 500, 2.2), true)
	_streams["beep"] = _wav(_beep(), false)

static func _wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

# one second that loops cleanly: everything in it repeats a whole number of times a second
static func _diesel(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RATE)
	var phases: Array[float] = []
	for k in 10:
		phases.append(rng.randf() * TAU)
	for i in RATE:
		var t := float(i) / RATE
		var v := 0.0
		for k in 10:
			v += sin(TAU * 32.0 * (k + 1) * t + phases[k]) / (k + 1.0)
		v *= 0.65 + 0.35 * sin(TAU * 8.0 * t)       # (the chug of the cylinders)
		out[i] = v * 0.36
	return out

static func _hydraulic() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 240.0 * t) * 0.34 + sin(TAU * 481.0 * t) * 0.24 + sin(TAU * 722.0 * t) * 0.12) * (0.85 + 0.15 * sin(TAU * 31.0 * t))
	return out

# a tin-can clatter 8 times a second: track plates over the wheels
static func _clatter(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RATE)
	var low := 0.0
	for i in RATE:
		var t := float(i) / RATE
		var into := fmod(t * 8.0, 1.0) / 8.0
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.4)
		out[i] = (low * 1.1 + sin(TAU * 310.0 * t) * 0.45) * exp(-into * 55.0)
	return out

# rough low noise with slow lumps in it, its ends blended so the loop doesn't click: soil scraped, soil falling
static func _noise(rng: RandomNumberGenerator, cut: float, lump_every: int, gain: float) -> PackedFloat32Array:
	var n := int(RATE * 1.5)
	var blend := int(RATE * 0.2)
	var raw := PackedFloat32Array()
	raw.resize(n + blend)
	var low := 0.0
	var slow := 0.5
	var slow_to := 0.5
	for i in raw.size():
		low = lerpf(low, rng.randf_range(-1.0, 1.0), cut)
		if i % lump_every == 0:
			slow_to = rng.randf_range(0.4, 1.0)
		slow = lerpf(slow, slow_to, 0.004)
		raw[i] = low * gain * slow
	var out := raw.slice(0, n)
	for i in blend:
		out[i] = lerpf(raw[n + i], raw[i], float(i) / blend)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.95:
		for i in out.size():
			out[i] *= 0.95 / peak
	return out

static func _beep() -> PackedFloat32Array:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 200.0) * minf(1.0, (0.22 - t) * 200.0)
		out[i] = sin(TAU * 1250.0 * t) * 0.5 * env
	return out
