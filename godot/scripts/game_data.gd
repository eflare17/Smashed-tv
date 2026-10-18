extends Node
## Everything measured from the HTML game (data/game_data.json) and the list of its pictures
## (assets/manifest.json). Positions in the data are the HTML game's: x across, y down the screen
## (which is north-south on the ground), z up. world_to_3d() turns them into Godot's 3D space.

## One HTML-game unit in metres. His eyes are 62 units up, about 1.55 m; a wall is 150 (3.75 m).
const UNIT := 0.025

## The physics layers (named in project.godot, layer_names/3d_physics), as bits for collision_layer / mask:
## 1 world (walls, solids, the trampoline), 2 players, 3 npcs (Gothica), 4 enemies, 5 projectiles, 6 pickups.
## Gameplay steps run in _physics_process (120 ticks a second, the HTML game's FIXED_DT, with physics
## interpolation on); only visuals and the cameras run in _process.
const LAYER_WORLD := 1 << 0
const LAYER_PLAYERS := 1 << 1
const LAYER_NPCS := 1 << 2
const LAYER_ENEMIES := 1 << 3
const LAYER_PROJECTILES := 1 << 4
const LAYER_PICKUPS := 1 << 5

var data: Dictionary = {}
var manifest: Dictionary = {}
var _tex_cache: Dictionary = {}

func _ready() -> void:
	data = _load_json("res://data/game_data.json")
	manifest = _load_json("res://assets/manifest.json")

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("can't open " + path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

## The HTML game's (x, y) on the ground, and z up, as a Godot position.
static func world_to_3d(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x * UNIT, z * UNIT, y * UNIT)

## And back: a Godot position as the HTML game's (x, y, z).
static func from_3d(p: Vector3) -> Vector3:
	return Vector3(p.x / UNIT, p.z / UNIT, p.y / UNIT)

## A picture from the manifest, by its path there ("assets/CHARS/goth/front_run_0.png"), as a texture.
## Pixel art: drawn with nearest filtering by whoever uses it.
func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = load("res://" + path)
	_tex_cache[path] = t
	return t
