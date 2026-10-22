class_name VoxelUpgrades
extends Node3D
## The weapon bench (Stage 13 of the overnight plan, 22 Oct: "kill and harvest money buys weapon upgrades (damage,
## clips, fuel) at a lobby bench"): in the back yard against the south wall, west of the buyer's crate (the safe side
## of the house: the bedroom and the games room stay as the HTML game has them). Three racks on it, each a track of
## three levels bought with cash (kills, buds, eggs), in order:
## - DAMAGE: every weapon's holes and cuts bigger and its blows harder (VoxelBody.hit_k: a player's weapons' hits
##   scaled as they're made; x1.2, x1.4, x1.65);
## - CLIPS: the pistol's clip, the shotgun's tube, the grenade launcher's drum (x1.5, x2, x2.5);
## - FUEL: the flamethrower's tank, the laser's heat, the freeze ray's charge last longer (x1.5, x2, x2.5).
## E at a rack buys its next level. Each player's own (VoxelShooter.upg), saved with the backpack and chests; in
## co-op each game tells the other its player's (net "U") so the host's copies of the guest's weapons hit as hard.
## Owned by the voxel session.

const AT := Vector3(6.55, 0, 22.92)     # the bench's middle (its back to the arena's south wall)
const TRACKS := ["damage", "clip", "fuel"]
const INFO := {
	"damage": {"name": "DAMAGE", "k": [1.0, 1.2, 1.4, 1.65], "cost": [25, 60, 120],
		"desc": "every weapon hits harder"},
	"clip": {"name": "CLIPS", "k": [1.0, 1.5, 2.0, 2.5], "cost": [20, 50, 100],
		"desc": "bigger clips, tube and drum"},
	"fuel": {"name": "FUEL", "k": [1.0, 1.5, 2.0, 2.5], "cost": [20, 50, 100],
		"desc": "fire, laser and ice last longer"},
}
const MAX_LEVEL := 3

var arena: Node3D
var _tags := {}                 # track -> its Label3D (the level and the next price)

## A track's multiplier at a level.
static func k(track: String, level: int) -> float:
	if not INFO.has(track):
		return 1.0
	var ks: Array = INFO[track].k
	return float(ks[clampi(level, 0, ks.size() - 1)])

## What the next level of a track costs from level (-1: it's at the top).
static func cost(track: String, level: int) -> int:
	if not INFO.has(track) or level >= MAX_LEVEL:
		return -1
	return int(INFO[track].cost[level])

## The levels from a save (or a message), cleaned.
static func clean(d) -> Dictionary:
	var out := {"damage": 0, "clip": 0, "fuel": 0}
	if d is Dictionary:
		for t in TRACKS:
			out[t] = clampi(int(d.get(t, 0)), 0, MAX_LEVEL)
	return out

func setup(arena_: Node3D) -> void:
	arena = arena_
	position = AT
	_build()
	refresh()

## Which rack the view's on within reach ("" none).
func pick(eye: Vector3, dir: Vector3, reach := 2.4) -> String:
	var box := AABB(AT + Vector3(-1.05, 0, -0.4), Vector3(2.1, 1.9, 0.8))
	var hit = box.intersects_ray(eye, dir)
	if hit == null or (hit as Vector3).distance_to(eye) > reach:
		return ""
	var x: float = (hit as Vector3).x - AT.x
	return TRACKS[clampi(int(floor((x + 1.05) / 0.7)), 0, 2)]

## What looking at a rack says.
func line(track: String, levels: Dictionary, cash: int) -> String:
	var lv := int(levels.get(track, 0))
	var nm: String = INFO[track].name
	var c := cost(track, lv)
	if c < 0:
		return "%s: level %d of %d, as good as it gets" % [nm, lv, MAX_LEVEL]
	var nxt := k(track, lv + 1)
	var s := "%s level %d (x%s): %s" % [nm, lv + 1, str(snappedf(nxt, 0.01)), INFO[track].desc]
	if cash >= c:
		return "E  buy %s for $%d   (you have $%d)" % [s, c, cash]
	return "%s: $%d, you have $%d" % [s, c, cash]

## The racks' tags showing each player's own levels (the local one's).
func refresh() -> void:
	if arena == null or arena.me == null:
		return
	for t in TRACKS:
		var lv := int(arena.me.upg.get(t, 0))
		var c := cost(t, lv)
		var l: Label3D = _tags[t]
		l.text = "%s\n%s\n%s" % [INFO[t].name, "●".repeat(lv) + "○".repeat(MAX_LEVEL - lv), ("$%d" % c) if c >= 0 else "MAX"]

func _mat(c: Color, rough := 0.85, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m

func _box(size: Vector3, at: Vector3, m: Material, solid := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.position = at
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		add_child(sb)

func _build() -> void:
	var steel := _mat(Color8(92, 96, 104), 0.45, 0.7)
	var dark := _mat(Color8(46, 48, 54), 0.6, 0.5)
	var top := _mat(Color8(120, 70, 40), 0.7)
	var red := _mat(Color8(170, 34, 30), 0.6)
	# a steel workbench with a wooden top
	_box(Vector3(2.1, 0.08, 0.7), Vector3(0, 0.92, 0), top, true)
	for lx in [-0.98, 0.98]:
		for lz in [-0.3, 0.3]:
			_box(Vector3(0.07, 0.88, 0.07), Vector3(lx, 0.44, lz), dark)
	_box(Vector3(2.0, 0.04, 0.62), Vector3(0, 0.3, 0), dark)
	# a steel back board split in three racks, each with what it upgrades hung on it
	_box(Vector3(2.1, 1.0, 0.04), Vector3(0, 1.5, -0.33), steel)
	for sx in [-0.35, 0.35]:
		_box(Vector3(0.03, 1.0, 0.05), Vector3(sx, 1.5, -0.3), red)
	# DAMAGE: a pistol and a blade
	_box(Vector3(0.22, 0.06, 0.04), Vector3(-0.78, 1.62, -0.29), dark)
	_box(Vector3(0.05, 0.12, 0.04), Vector3(-0.85, 1.55, -0.29), dark)
	_box(Vector3(0.05, 0.42, 0.02), Vector3(-0.52, 1.5, -0.29), _mat(Color8(200, 204, 210), 0.3, 0.9))
	# CLIPS: magazines and shells in a row
	for i in 4:
		_box(Vector3(0.05, 0.16, 0.04), Vector3(-0.15 + i * 0.1, 1.55, -0.29), _mat(Color8(60, 60, 66), 0.5, 0.6))
	for i in 5:
		_box(Vector3(0.03, 0.07, 0.03), Vector3(-0.16 + i * 0.08, 1.36, -0.29), _mat(Color8(200, 40, 34), 0.5))
	# FUEL: a red can and a cyan cell
	_box(Vector3(0.18, 0.26, 0.1), Vector3(0.58, 1.5, -0.27), red)
	_box(Vector3(0.08, 0.2, 0.08), Vector3(0.85, 1.48, -0.27), _mat(Color8(80, 220, 255), 0.2, 0.0, 1.5))
	# a lamp over it
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.2, 0.2)
	lamp.light_energy = 0.8
	lamp.omni_range = 3.0
	lamp.light_color = Color(1.0, 0.92, 0.8)
	add_child(lamp)
	var sign := Label3D.new()
	sign.text = "WEAPON BENCH"
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.outline_size = 8
	sign.position = Vector3(0, 2.15, -0.3)
	add_child(sign)
	for i in TRACKS.size():
		var l := Label3D.new()
		l.font_size = 32
		l.pixel_size = 0.0032
		l.outline_size = 6
		l.modulate = Color("#f6d17a")
		l.position = Vector3(-0.7 + i * 0.7, 1.13, 0.0)
		l.rotation = Vector3(-0.5, 0, 0)
		add_child(l)
		_tags[TRACKS[i]] = l
