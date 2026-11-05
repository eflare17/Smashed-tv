class_name Sfx
extends Node
## All the sound, made here in code so the game needs no sound files: a diesel, soil scraping, and tree cracks and thuds.

const RATE := 22050

var engine: AudioStreamPlayer
var scrape: AudioStreamPlayer
var crack: AudioStreamPlayer
var thud: AudioStreamPlayer
var rustle: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var roll: AudioStreamPlayer
var clank: AudioStreamPlayer
var whine: AudioStreamPlayer
var pour: AudioStreamPlayer
var clunk: AudioStreamPlayer
var _scrape_level := 0.0
var _roll_level := 0.0
var _clank_level := 0.0
var _hyd_level := 0.0
var _pour_level := 0.0

func _ready() -> void:
	_rng.seed = 11
	engine = _player(_wav(diesel(), true), -14.0)
	scrape = _player(_wav(scraping(), true), -60.0)
	crack = _player(_wav(crack_sound()), -2.0)
	thud = _player(_wav(thud_sound()), 0.0)
	rustle = _player(_wav(rustle_sound()), -6.0)
	roll = _player(_wav(lumps(0.06, 900)), -60.0)
	clank = _player(_wav(clatter(), true), -60.0)
	whine = _player(_wav(hydraulic(), true), -60.0)
	pour = _player(_wav(lumps(0.3, 500)), -60.0)
	clunk = _player(_wav(clunk_sound()), -4.0)
	for looped: AudioStreamPlayer in [roll, pour]:
		var w: AudioStreamWAV = looped.stream
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = w.data.size() / 2
	engine.play()
	scrape.play()
	roll.play()
	clank.play()
	whine.play()
	pour.play()

func _player(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p

func _wav(samples: PackedFloat32Array, looped := false) -> AudioStreamWAV:
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

## One second that loops cleanly: everything in it repeats a whole number of times a second.
func diesel() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RATE)
	var phases: Array[float] = []
	for k in 10:
		phases.append(_rng.randf() * TAU)
	for i in RATE:
		var t := float(i) / RATE
		var v := 0.0
		for k in 10:
			v += sin(TAU * 32.0 * (k + 1) * t + phases[k]) / (k + 1.0)
		# The chug of the cylinders.
		v *= 0.65 + 0.35 * sin(TAU * 8.0 * t)
		out[i] = v * 0.36
	return out

## Rough low noise, with its ends blended so the loop doesn't click.
func scraping() -> PackedFloat32Array:
	var n := int(RATE * 1.5)
	var blend := int(RATE * 0.2)
	var raw := PackedFloat32Array()
	raw.resize(n + blend)
	var low := 0.0
	var slow := 0.5
	for i in raw.size():
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.18)
		if i % 700 == 0:
			slow = _rng.randf_range(0.55, 1.0)
		raw[i] = low * 1.6 * slow
	var out := raw.slice(0, n)
	for i in blend:
		var k := float(i) / blend
		out[i] = lerpf(raw[n + i], raw[i], k)
	return out

func crack_sound() -> PackedFloat32Array:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.5)
		# A few sharp snaps close together, as wood goes.
		var snaps := exp(-t * 26.0)
		if t > 0.07:
			snaps += 0.7 * exp(-(t - 0.07) * 34.0)
		if t > 0.16:
			snaps += 0.45 * exp(-(t - 0.16) * 40.0)
		out[i] = low * snaps * 0.95
	return out

func thud_sound() -> PackedFloat32Array:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.06)
		out[i] = (sin(TAU * (68.0 - 30.0 * t) * t) * 0.72 + low * 1.0) * exp(-t * 7.0)
	return out

func rustle_sound() -> PackedFloat32Array:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := _rng.randf_range(-1.0, 1.0)
		var airy := white - last
		last = white
		out[i] = airy * 0.3 * smoothstep(0.0, 0.08, t) * exp(-t * 4.0)
	return out

## Each tick: the engine labours with what the machine is doing, and soil is heard while it's moving.
func update(dt: float, d: Machine) -> void:
	var push := d.effort()
	var rev := 0.8 + 0.3 * push + 0.3 * absf(d.speed) / d.top_speed
	var labour := clampf(d.load_t / 18.0, 0.0, 1.0) * push
	engine.pitch_scale = lerpf(engine.pitch_scale, rev - labour * 0.14, minf(dt * 5.0, 1.0))
	engine.volume_db = lerpf(engine.volume_db, -17.0 + 6.0 * push + 3.0 * labour, minf(dt * 5.0, 1.0))
	var want := 0.0
	if d.moved_tick > 0 and (absf(d.speed) > 0.1 or d.hyd > 0.05):
		want = clampf(0.25 + d.load_t / 14.0, 0.0, 1.0)
	_scrape_level = lerpf(_scrape_level, want, minf(dt * 7.0, 1.0))
	scrape.volume_db = linear_to_db(maxf(_scrape_level, 0.001)) - 4.0
	scrape.pitch_scale = 0.8 + 0.35 * clampf(absf(d.speed) / d.top_speed, 0.0, 1.0)
	# Deep soil tumbling off a blade under load: a low rumble under the scrape.
	var tumble := clampf(d.load_t / 12.0, 0.0, 1.0) if d.moved_tick > 0 and d.speed > 0.1 else 0.0
	_roll_level = lerpf(_roll_level, tumble, minf(dt * 4.0, 1.0))
	roll.volume_db = linear_to_db(maxf(_roll_level, 0.001)) - 7.0
	# The tracks clatter with speed, and faster still when they're spinning.
	var belt := absf(d.speed) if not d.slipping else absf(d.drive) * d.top_speed * 0.8
	var moving := clampf(belt / 1.5, 0.0, 1.0) if d.tracks else 0.0
	_clank_level = lerpf(_clank_level, moving, minf(dt * 6.0, 1.0))
	clank.volume_db = linear_to_db(maxf(_clank_level, 0.001)) - 11.0
	clank.pitch_scale = 0.6 + 0.5 * clampf(belt / d.top_speed, 0.0, 1.0)
	_hyd_level = lerpf(_hyd_level, d.hyd, minf(dt * 9.0, 1.0))
	whine.volume_db = linear_to_db(maxf(_hyd_level, 0.001)) - 19.0
	whine.pitch_scale = 0.9 + 0.25 * _hyd_level - 0.12 * clampf(d.load_t / 3.0, 0.0, 1.0)

## Soil falling out of the bucket, 0 to 1.
func pouring(dt: float, amount: float) -> void:
	_pour_level = lerpf(_pour_level, amount, minf(dt * 8.0, 1.0))
	pour.volume_db = linear_to_db(maxf(_pour_level, 0.001)) - 7.0

## Steel meeting something: the blade touching down, a bucket reaching the end of its travel.
func clunked(weight := 1.0) -> void:
	clunk.volume_db = linear_to_db(clampf(weight, 0.05, 1.0)) - 4.0
	clunk.pitch_scale = _rng.randf_range(0.9, 1.15)
	clunk.play()

## A tin-can clatter that repeats 8 times a second: track plates over the wheels.
func clatter() -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var into := fmod(t * 8.0, 1.0) / 8.0
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.4)
		out[i] = (low * 1.1 + sin(TAU * 310.0 * t) * 0.45) * exp(-into * 55.0)
	return out

## A hydraulic pump's whine: whole numbers of cycles a second, so it loops, with a slight flutter.
func hydraulic() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 240.0 * t) * 0.34 + sin(TAU * 481.0 * t) * 0.24 + sin(TAU * 722.0 * t) * 0.12) * (0.85 + 0.15 * sin(TAU * 31.0 * t))
	return out

## A deep thump with a ring of steel in it.
func clunk_sound() -> PackedFloat32Array:
	var n := int(RATE * 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.25)
		out[i] = sin(TAU * 92.0 * t) * 0.8 * exp(-t * 20.0) + sin(TAU * 610.0 * t) * 0.14 * exp(-t * 30.0) + low * 0.5 * exp(-t * 32.0)
	return out

## Noise with slow lumps in it and its ends blended, a bit rougher as `grain` goes down. For soil falling and tumbling.
func lumps(cut: float, lump_every: int) -> PackedFloat32Array:
	var n := int(RATE * 1.5)
	var blend := int(RATE * 0.2)
	var raw := PackedFloat32Array()
	raw.resize(n + blend)
	var low := 0.0
	var slow := 0.5
	var slow_to := 0.5
	for i in raw.size():
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), cut)
		if i % lump_every == 0:
			slow_to = _rng.randf_range(0.3, 1.0)
		slow = lerpf(slow, slow_to, 0.002)
		raw[i] = low * 2.2 * slow
	var out := raw.slice(0, n)
	for i in blend:
		out[i] = lerpf(raw[n + i], raw[i], float(i) / blend)
	return out

func tree_knocked() -> void:
	crack.pitch_scale = _rng.randf_range(0.85, 1.2)
	crack.play()
	rustle.pitch_scale = _rng.randf_range(0.85, 1.15)
	rustle.play()

func tree_landed() -> void:
	thud.pitch_scale = _rng.randf_range(0.85, 1.1)
	thud.play()
