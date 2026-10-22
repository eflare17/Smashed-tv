extends Node3D
## Smash arcade power-up pickups: a few fixed slots (built once, shown and hidden, never created during play),
## each a spinning tinted crate with its name floating over it. They last LIFE seconds and blink before going.

const SmashVox := preload("smash_vox.gd")

const SLOTS := 4
const LIFE := 9.0
const REACH := 0.9
const SPREAD := 0
const ROCKETS := 1
const SHIELD := 2
const SPEED := 3
const NAMES := ["SPREAD", "ROCKETS", "SHIELD", "SPEED"]
const COLORS := [Color(1.0, 0.85, 0.2), Color(1.0, 0.35, 0.25), Color(0.35, 0.9, 1.0), Color(0.45, 1.0, 0.45)]

var active := PackedByteArray()
var type := PackedByteArray()
var pos := PackedVector2Array()
var age := PackedFloat32Array()

var _nodes: Array[Node3D] = []
var _crates: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _mats: Array[StandardMaterial3D] = []
var _spin := 0.0

func _init() -> void:
	name = "SmashPickups"
	active.resize(SLOTS)
	type.resize(SLOTS)
	pos.resize(SLOTS)
	age.resize(SLOTS)
	var mesh := SmashVox.crate_mesh()
	for i in SLOTS:
		var n := Node3D.new()
		n.visible = false
		var crate := MeshInstance3D.new()
		crate.mesh = mesh
		var mat := SmashVox.flat_material()
		crate.material_override = mat
		crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(crate)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 64
		label.outline_size = 14
		label.pixel_size = 0.012
		label.position = Vector3(0, 1.0, 0.75)
		n.add_child(label)
		add_child(n)
		_nodes.append(n)
		_crates.append(crate)
		_labels.append(label)
		_mats.append(mat)

func set_label_size(pixel: float) -> void:
	for l in _labels:
		l.pixel_size = pixel

func clear() -> void:
	for i in SLOTS:
		active[i] = 0
		_nodes[i].visible = false

func free_slots() -> int:
	var n := 0
	for i in SLOTS:
		n += 1 - active[i]
	return n

func spawn(p: Vector2, t: int) -> bool:
	for i in SLOTS:
		if active[i] == 0:
			active[i] = 1
			type[i] = t
			pos[i] = p
			age[i] = 0.0
			_mats[i].albedo_color = COLORS[t]
			_labels[i].text = NAMES[t]
			_labels[i].modulate = COLORS[t]
			_nodes[i].visible = true
			return true
	return false

func step(delta: float) -> void:
	_spin += delta * 2.5
	for i in SLOTS:
		if active[i] == 0:
			continue
		age[i] += delta
		if age[i] >= LIFE:
			active[i] = 0
			_nodes[i].visible = false
			continue
		var p := pos[i]
		_nodes[i].position = Vector3(p.x, 0.25 + absf(sin(_spin + i)) * 0.25, p.y)
		_crates[i].rotation.y = _spin + i
		# blink for the last two seconds
		_nodes[i].visible = age[i] < LIFE - 2.0 or int(age[i] * 8.0) % 2 == 0

## The type of a pickup within reach of `p` (and takes it), or -1.
func collect(p: Vector2) -> int:
	for i in SLOTS:
		if active[i] == 1 and (pos[i] - p).length_squared() < REACH * REACH:
			active[i] = 0
			_nodes[i].visible = false
			return type[i]
	return -1

func nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in SLOTS:
		if active[i] == 1:
			var d := (pos[i] - p).length_squared()
			if d < bd:
				bd = d
				best = i
	return best
