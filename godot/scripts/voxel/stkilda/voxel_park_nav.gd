class_name VoxelParkNav
extends NavigationRegion3D
## Where enemies can walk in St Kilda (the owner, 29 Oct: enemies in the park, for its game modes): a walking map
## (Godot's navigation mesh) made from everything solid in the slice (Luna Park's wall, the rides, the stalls, the
## coaster's legs, the buildings, the slice's edge), the first time it's wanted. It's made again (in the background) a
## moment after a building's been knocked through (VoxelBreakables), so they come through the hole. The arena's own
## enemies don't use it: VoxelArena moves one marked "park" (VoxelStKilda.spawn) along a path on it to whoever it's
## after, and keeps it on the map.

const REPATH := 0.45            # s between a body's new paths
const REBAKE := 1.2             # s after a wall's knocked through before it's made again

var sk: VoxelStKilda
var ready_ := false             # made at least once
var _baking := false
var _dirty_t := -1.0
var _paths := {}                # body id -> {p: PackedVector3Array, i, t, to}

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "ParkNav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = SkData.LAYER_WORLD
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.35
	nm.agent_max_slope = 30.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	var sl: Array = sk.town.data.slice
	nm.filter_baking_aabb = AABB(Vector3(sl[0], -1.0, sl[1]), Vector3(sl[2] - sl[0], 8.0, sl[3] - sl[1]))
	navigation_mesh = nm

## Made (again), in the background.
func bake() -> void:
	if _baking:
		_dirty_t = REBAKE
		return
	_baking = true
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, src, sk)
	NavigationServer3D.bake_from_source_geometry_data_async(navigation_mesh, src, _baked)

func _baked() -> void:
	_baking = false
	navigation_mesh = navigation_mesh         # (the region told it's changed)
	ready_ = true
	_paths.clear()

## A wall's been knocked through: made again soon.
func changed() -> void:
	_dirty_t = REBAKE

func _process(dt: float) -> void:
	if _dirty_t > 0.0:
		_dirty_t -= dt
		if _dirty_t <= 0.0:
			bake()

## Which way (level, length 1) a body at `from` goes to get to `to`; Vector3.ZERO if there (or no map yet: straight).
func way(id: int, from: Vector3, to: Vector3, dt: float) -> Vector3:
	if not ready_:
		var d := Vector3(to.x - from.x, 0, to.z - from.z)
		return d.normalized() if d.length() > 0.01 else Vector3.ZERO
	var map := get_world_3d().navigation_map
	var p: Dictionary = _paths.get(id, {})
	if p.is_empty() or float(p.t) <= 0.0 or (p.to as Vector3).distance_to(to) > 2.0:
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		p = {"p": path, "i": 1, "t": REPATH * randf_range(0.8, 1.2), "to": to}
		_paths[id] = p
	p.t = float(p.t) - dt
	var path: PackedVector3Array = p.p
	var i: int = p.i
	while i < path.size() and Vector2(path[i].x - from.x, path[i].z - from.z).length() < 0.5:
		i += 1
	p.i = i
	if i >= path.size():
		return Vector3.ZERO
	var d := Vector3(path[i].x - from.x, 0, path[i].z - from.z)
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO

## at, put back on the walking map if it's slipped off (into a wall, a ride); its height as it was.
func keep_on(at: Vector3) -> Vector3:
	if not ready_:
		return at
	var c := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, at)
	if Vector2(c.x - at.x, c.z - at.z).length() < 0.02:
		return at
	return Vector3(c.x, at.y, c.z)

## A spot on the walking map near `at` (where to stand one).
func spot_near(at: Vector3) -> Vector3:
	if not ready_:
		return at
	var c := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, at)
	return Vector3(c.x, 0.0, c.z)

func forget(id: int) -> void:
	_paths.erase(id)
