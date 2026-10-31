# (Copied from stkilda-godot scripts/world/sounds.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkSounds
extends RefCounted
## Little sounds made in code (no audio files needed): the desk phone's ring, the counter bell's ding, an ibis's squawk
## and the bat's whack.

const RATE := 22050

## An Aussie double ring (brring-brring ... pause), 3 s, looping: two tones a touch apart, warbling.
static func ring() -> AudioStreamWAV:
	var n := RATE * 3
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var on := (t < 0.4) or (t >= 0.6 and t < 1.0)
		if not on:
			continue
		var env := minf(1.0, minf(fmod(t, 0.6) / 0.01, 1.0))
		var warble := 0.5 + 0.5 * sin(TAU * 17.0 * t)
		s[i] = env * (0.35 * sin(TAU * 400.0 * t) + 0.35 * sin(TAU * 450.0 * t)) * (0.6 + 0.4 * warble)
	return _wav(s, true)

## A counter bell: a bright ping that rings out.
static func ding() -> AudioStreamWAV:
	var n := int(RATE * 1.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 4.0) * minf(1.0, t / 0.002)
		s[i] = env * (0.5 * sin(TAU * 2093.0 * t) + 0.25 * sin(TAU * 5230.0 * t) * exp(-t * 9.0) + 0.15 * sin(TAU * 1046.0 * t))
	return _wav(s, false)

## An ibis's squawk: a harsh, nasal honk that drops in pitch, twice (`pitch` lifts or lowers it; `hurt`: one long
## shriek, higher, for when the bat gets it).
static func squawk(pitch := 1.0, hurt := false) -> AudioStreamWAV:
	var length := 0.55 if hurt else 0.5
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / RATE
		var u := t if hurt else fmod(t, 0.25)            # (two honks, or one long one)
		var dur := length if hurt else 0.22
		if u > dur:
			continue
		var f := (520.0 if hurt else 330.0) * pitch * (1.0 - 0.35 * u / dur)
		ph += f / RATE
		var saw := 2.0 * fmod(ph, 1.0) - 1.0
		var env := minf(1.0, u / 0.01) * minf(1.0, (dur - u) / 0.04)
		var rasp := 0.6 + 0.4 * sin(TAU * 45.0 * t)      # (the rattle in it)
		s[i] = env * rasp * (0.32 * saw + 0.12 * sin(TAU * ph * 2.0) + 0.1 * rng.randf_range(-1.0, 1.0))
	return _wav(s, false)

## A bat hitting something soft: a thump with a woody knock on top.
static func whack() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / RATE
		var thump := sin(TAU * 95.0 * t * (1.0 - t)) * exp(-t * 18.0)
		var knock := sin(TAU * 820.0 * t) * exp(-t * 45.0)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0)
		s[i] = 0.6 * thump + 0.3 * knock + 0.35 * crack
	return _wav(s, false)

static func _wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w
