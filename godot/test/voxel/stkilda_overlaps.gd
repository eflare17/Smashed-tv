extends SceneTree
## St Kilda (scripts/voxel/stkilda): where the copied map's buildings and Luna Park's rides overlap, which shows as
## flickering walls (two faces in the same place: the owner found Cafe Luna through the Ghost Train, 29 Oct). Builds
## the slice on its own, then lists each overlap (the map's buildings by OpenStreetMap id, the rides by name) with
## how much they share, biggest first, and (under a display, -- --out=dir) a picture of each from outside. The fixes
## belong in the St Kilda game (stkilda-godot), where the map and the rides are made; this only finds them.

const MIN_AREA := 0.5            # m² shared before it counts
const ROOFS_TOO := ["Town", "SliceEdge", "SkCrowd", "SkParkFlags", "SkDayNight", "ParkWall", "ParkPaving", "LunaParkLamps",
		"RideSpill", "NightPools", "SkScenicRailway"]    # (and the coaster: it winds round the buildings, SkScenicRailway.in_the_way
		# clears what it runs through)    # (not rides: the map itself, the edge, the people, the lights)

var sk: VoxelStKilda
var out := ""
var found: Array = []            # [area, name a, name b, middle (x, z)]
var shot := -1
var cam: Camera3D

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	sk = VoxelStKilda.new()
	sk.process_mode = Node.PROCESS_MODE_DISABLED     # (no arena here: its walking about stays off)
	root.add_child(sk)
	sk.build()
	await process_frame                       # (where everything is, once it's all in)
	var shapes: Array = []       # [name, outline (world x, z)]
	for b in sk.town.data.buildings:
		if sk.town.skip.has(b.get("id", "")):
			continue
		shapes.append(["%s %s (%s)" % [b.get("id", ""), b.get("n", ""), b.get("k", "")], _inset(SkTownBuilder._pts(b.p))])
	# the map's outlines the rides are built on (their own shapes follow them closely: a ride's box would be rough)
	for b in sk.town.data.buildings:
		if sk.town.skip.has(b.get("id", "")) and b.get("n", "") != "":
			shapes.append(["ride on %s %s" % [b.get("id", ""), b.get("n", "")], _inset(SkTownBuilder._pts(b.p))])
	for c in sk.get_children():
		if c is Node3D and not (String(c.name) in ROOFS_TOO) and not String(c.name).begins_with("@"):
			var o := _outline(c)
			if not o.is_empty():
				shapes.append([String(c.name), o])
	for i in shapes.size():
		for j in range(i + 1, shapes.size()):
			if not String(shapes[i][0]).begins_with("w") and not String(shapes[j][0]).begins_with("w"):
				continue                # (ride with ride: their boxes are rough, and the St Kilda game lays them out)
			var area := 0.0
			var mid := Vector2.ZERO
			for p in Geometry2D.intersect_polygons(shapes[i][1], shapes[j][1]):
				var a := _area(p)
				area += a
				mid += _middle(p) * a
			if area >= MIN_AREA:
				found.append([area, shapes[i][0], shapes[j][0], mid / area])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("overlaps (", found.size(), "):")
	for f in found:
		print("  %6.1f m²  %s  /  %s  at (%.0f, %.0f)" % [f[0], f[1], f[2], f[3].x, f[3].y])
	if out == "" or DisplayServer.get_name() == "headless":
		quit()
		return
	var we := WorldEnvironment.new()
	we.environment = sk.env
	root.add_child(we)
	sk.visible = true
	sk.sun.visible = true
	cam = Camera3D.new()
	cam.near = VoxelStKilda.NEAR
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	shot = 0

var _wait := 0
func _process(_dt: float) -> bool:
	if shot < 0:
		return false
	if shot >= found.size():
		quit()
		return false
	if _wait == 0:
		var m: Vector2 = found[shot][3]
		var at := Vector3(m.x, 0, m.y)
		# from the side with the most open ground (of four), 14 m back, a little above
		var best := Vector3.BACK
		var space := sk.get_world_3d().direct_space_state
		var far := 0.0
		for d in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.6, 0) + d * 4.0, at + Vector3(0, 1.6, 0) + d * 30.0)
			var hit := space.intersect_ray(q)
			var free := 30.0 if hit.is_empty() else (hit.position as Vector3).distance_to(at)
			if free > far:
				far = free
				best = d
		cam.global_position = at + best * minf(14.0, far - 1.0) + Vector3(0, 2.5, 0)
		cam.look_at(at + Vector3(0, 2.5, 0))
	_wait += 1
	if _wait == 30:
		root.get_texture().get_image().save_png("%s/overlap_%02d.png" % [out, shot + 1])
		_wait = 0
		shot += 1
	return false

## A node's footprint: the box round its meshes in its own frame, turned into the world (x, z).
func _outline(n: Node3D) -> PackedVector2Array:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := inv * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.x * box.size.z < 1.0:
		return PackedVector2Array()
	var o := PackedVector2Array()
	for c in [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z),
			Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z)]:
		var w := n.global_transform * (c as Vector3)
		o.append(Vector2(w.x, w.z))
	return o

## An outline brought in 0.2 m all round (neighbours that only touch don't count, ones that share a wall do: their
## faces are in the same place).
static func _inset(p: PackedVector2Array) -> PackedVector2Array:
	var r := Geometry2D.offset_polygon(p, -0.2)
	return r[0] if not r.is_empty() else p

static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return absf(a) * 0.5

static func _middle(p: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for v in p:
		s += v
	return s / p.size()
