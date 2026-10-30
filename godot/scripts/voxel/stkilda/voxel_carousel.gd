class_name VoxelCarousel
extends RefCounted
## The Carousel's new horses (the owner, 31 Oct: "way less horses", like their photo): RING of them, the owner's
## carousel horse model (assets/models/carousel_horse/horse.res, made by tools/carousel_horse.gd), each on a long
## twisted gold pole from the floor to the canopy, riding up and down it as the ride turns, people on about half.
## Done here, over what SkLunaRides built (that's copied from the St Kilda game: not changed here): its sixty box horses,
## their riders and their poles (baked into the platform) taken off first.

const RING := 12
const R := 4.9                      # (between the mirrored drum, 2 m, and the platform's edge, 7.5 m)
const RISE := 0.35                  # how far up and down they ride (as the old ones)
const FLOOR := 0.67                 # the platform's top
const CEILING := 4.2                # the canopy's underside
const POLE_R := 0.045
const GOLD := Color("#e2b443")
const HIPS := Vector3(-0.2, 1.3, 0)  # where a rider sits on one (the seat's just behind the pole)

static func dress(carousel: Node3D) -> void:
	if carousel == null:
		return
	var spin := carousel.get_node_or_null("Ride") as SkLunaRides.Spinner
	if spin == null:
		return
	for c in spin.get_children():
		if c.name.begins_with("Horses") or c.name == "Riders":
			spin.remove_child(c)
			c.free()
	_unpole(spin.get_node_or_null("Platform") as MeshInstance3D)
	var poles := Node3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = load("res://assets/models/carousel_horse/horse.res")
	mm.instance_count = RING
	var horses := MultiMeshInstance3D.new()
	horses.name = "Horses"
	horses.multimesh = mm
	horses.material_override = SkModels.baked_material()
	horses.visibility_range_end = 500.0
	spin.add_child(horses)
	var list := []
	var seats := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1913
	for k in RING:
		var a := TAU * k / RING
		var at := Vector3(cos(a), 0, sin(a)) * R
		_pole(poles, at)
		# (facing round the way it turns, as the old ones: anticlockwise from above)
		var xf := Transform3D(Basis(Vector3.UP, -a), at + Vector3(0, FLOOR, 0))
		mm.set_instance_transform(k, xf)
		list.append([horses, k, xf, RISE, float(k) * 1.7])
		if rng.randf() < 0.5:
			seats.append([mm, k, SkLunaRides._seat(HIPS, -PI / 2.0, 0.85)])
	var pm := MeshInstance3D.new()
	pm.name = "Poles"
	pm.mesh = SkModels.bake(poles)
	pm.material_override = SkModels.baked_material()
	poles.free()
	spin.add_child(pm)
	spin.horses = list
	spin.riders = SkLunaRides._riders(spin, seats, 0.0, 0.8, 0.15)

## A twisted gold pole, floor to canopy: a rod with a ridge wound round it, a collar at each end.
static func _pole(holder: Node3D, at: Vector3) -> void:
	SkModels.cyl(holder, POLE_R, CEILING - FLOOR, at + Vector3(0, (CEILING + FLOOR) / 2.0, 0), GOLD, true, 8)
	var steps := 40
	for s in steps:
		var t := float(s) / steps
		var y := lerpf(FLOOR + 0.1, CEILING - 0.1, t)
		var a := t * TAU * 9.0
		var b := SkModels.box(holder, Vector3(0.035, 0.11, 0.035), at + Vector3(cos(a) * POLE_R, y, sin(a) * POLE_R), GOLD.darkened(0.12))
		b.rotation = Vector3(0, -a, 0.5)
	for y in [FLOOR + 0.05, CEILING - 0.06]:
		SkModels.cyl(holder, POLE_R * 1.9, 0.1, at + Vector3(0, y, 0), GOLD.lightened(0.1), true, 8)

## The old poles out of the platform's mesh (they're baked in with it): what's within a hand of where one stood,
## between the floor and the canopy.
static func _unpole(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var at := []
	var count := 0
	for row in SkLunaRides.ROWS:
		var many: int = row[1]
		for k in many:
			var a := TAU * (k + 0.5 * (count % 2)) / many
			at.append(Vector2(cos(a), sin(a)) * float(row[0]))
		count += 1
	var m := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
			var off := false
			if c.y > FLOOR + 0.02 and c.y < CEILING - 0.01:
				for p in at:
					if Vector2(c.x, c.z).distance_to(p) < 0.12:
						off = true
						break
			if not off:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = out
