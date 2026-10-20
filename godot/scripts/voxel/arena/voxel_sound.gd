class_name VoxelSound
extends Node
## The arena's sounds (the owner, 20 Oct): play(name) for a one-off, at a place in the world (heard from where the
## camera is) or flat (your own weapon); loop(key, name) for something that keeps going (a chainsaw's engine, the
## vacuum's hum) till stop(key). Names are files in assets/voxel/sound/ (made by assets/voxel/tools/sfx.py), or
## "game:<name>" for the game's own assets/sounds/<name>.mp3; a name with numbered files (pistol_0, pistol_1 ...) picks
## one at random each time. A small pool of players is reused (the oldest one cut off when all are busy), and the same
## sound can't pile up more than a few times in a blink. Owned by the voxel session.

const DIR := "res://assets/voxel/sound/"
const GAME_DIR := "res://assets/sounds/"
const POOL_3D := 24
const POOL_FLAT := 8
const SAME_MAX := 4             # the same sound at most this many times ...
const SAME_T := 0.08            # ... in this many seconds

var _streams := {}              # name -> Array[AudioStream] (its variants)
var _3d: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _n3 := 0
var _nf := 0
var _loops := {}                # key -> AudioStreamPlayer / AudioStreamPlayer3D
var _recent := {}               # name -> [times played lately]
var _clock := 0.0
var volume_db := 0.0

func _ready() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 60.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_3d.append(p)
	for i in POOL_FLAT:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat.append(p)

func _process(dt: float) -> void:
	_clock += dt

## The streams for name (its numbered variants, or the one file); empty if there are none.
func streams(name: String) -> Array:
	if _streams.has(name):
		return _streams[name]
	var out := []
	var base := DIR + name
	var ext := ".wav"
	if name.begins_with("game:"):
		base = GAME_DIR + name.trim_prefix("game:")
		ext = ".mp3"
	if ResourceLoader.exists(base + ext):
		out.append(load(base + ext))
	else:
		for i in 16:
			if not ResourceLoader.exists("%s_%d%s" % [base, i, ext]):
				break
			out.append(load("%s_%d%s" % [base, i, ext]))
	_streams[name] = out
	return out

func _pick(name: String) -> AudioStream:
	var s := streams(name)
	if s.is_empty():
		return null
	return s[randi() % s.size()]

## One sound: at a place (Vector3.INF: flat, your own), louder or quieter by db, its pitch varied a little each time.
func play(name: String, at: Vector3 = Vector3.INF, db: float = 0.0, pitch: float = 1.0, vary: float = 0.06) -> void:
	var st := _pick(name)
	if st == null:
		return
	# the same sound piling up (a shotgun's nine holes at once): only the first few
	var times: Array = _recent.get(name, [])
	times = times.filter(func(x): return _clock - float(x) < SAME_T)
	if times.size() >= SAME_MAX:
		return
	times.append(_clock)
	_recent[name] = times
	var pit := pitch * randf_range(1.0 - vary, 1.0 + vary)
	if at == Vector3.INF:
		var p := _flat[_nf]
		_nf = (_nf + 1) % _flat.size()
		p.stream = st
		p.volume_db = db + volume_db
		p.pitch_scale = pit
		p.play()
	else:
		var p3 := _3d[_n3]
		_n3 = (_n3 + 1) % _3d.size()
		p3.stream = st
		p3.global_position = at
		p3.volume_db = db + volume_db
		p3.pitch_scale = pit
		p3.play()

## A sound that keeps going under key (started if it isn't, or changed to name if it's another): at a node (it
## follows it) or flat; db and pitch can be changed every frame by calling again.
func loop(key: String, name: String, follow: Node3D = null, db: float = 0.0, pitch: float = 1.0) -> void:
	var p: Node = _loops.get(key)
	if p == null or not is_instance_valid(p):
		if follow:
			p = AudioStreamPlayer3D.new()
			(p as AudioStreamPlayer3D).unit_size = 6.0
			follow.add_child(p)
		else:
			p = AudioStreamPlayer.new()
			add_child(p)
		_loops[key] = p
	var want := _pick(name)
	if want == null:
		return
	if want is AudioStreamWAV:
		var w := want as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)    # (frames; whatever it was imported as)
	if p.get("stream") != want:
		p.set("stream", want)
		p.call("play")
	elif not p.get("playing"):
		p.call("play")
	p.set("volume_db", db + volume_db)
	p.set("pitch_scale", pitch)

func stop(key: String) -> void:
	var p: Node = _loops.get(key)
	if p and is_instance_valid(p):
		p.queue_free()
	_loops.erase(key)

func playing(key: String) -> bool:
	var p: Node = _loops.get(key)
	return p != null and is_instance_valid(p)
