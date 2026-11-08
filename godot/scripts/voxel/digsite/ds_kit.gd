class_name DsKit
extends RefCounted
## (The digger game's MeshKit, copied for the Dig Site's machines.) Builds faceted, solid-colour meshes in code: every face has its own flat normal and one colour from the palette. All
## the shapes are convex, so each face is turned to point away from its shape's middle.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var xf := Transform3D.IDENTITY

func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot's front faces wind clockwise seen from the front.
	verts.append_array(PackedVector3Array([a, b, c]))
	norms.append_array(PackedVector3Array([n, n, n]))
	cols.append_array(PackedColorArray([col, col, col]))

## A flat convex polygon facing away from `middle`.
func face(pts: Array, middle: Vector3, col: Color) -> void:
	var w := []
	for p in pts:
		w.append(xf * (p as Vector3))
	var m: Vector3 = xf * middle
	var n: Vector3 = ((w[1] - w[0]) as Vector3).cross(w[2] - w[0]).normalized()
	var at := Vector3.ZERO
	for p in w:
		at += p
	at /= w.size()
	var flip := n.dot(at - m) < 0.0
	if flip:
		n = -n
	for i in range(1, w.size() - 1):
		# Clockwise from outside: with n = (b - a) x (c - a) pointing out, a, c, b is the clockwise order.
		if flip:
			_tri(w[0], w[i], w[i + 1], n, col)
		else:
			_tri(w[0], w[i + 1], w[i], n, col)

func box(c: Vector3, s: Vector3, col: Color, tilt := Basis.IDENTITY) -> void:
	var h := s * 0.5
	var p := []
	for z in [-1, 1]:
		for y in [-1, 1]:
			for x in [-1, 1]:
				p.append(c + tilt * Vector3(h.x * x, h.y * y, h.z * z))
	for f in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		face([p[f[0]], p[f[1]], p[f[2]], p[f[3]]], c, col)

## A convex side profile (x along, y up) extruded across z.
func prism(profile: Array, z0: float, z1: float, col: Color, cap := Color.TRANSPARENT) -> void:
	var middle := Vector3(0, 0, (z0 + z1) * 0.5)
	for p in profile:
		middle += Vector3(p.x, p.y, 0) / float(profile.size())
	var end_col: Color = col if cap.a == 0.0 else cap
	var a := []
	var b := []
	for p in profile:
		a.append(Vector3(p.x, p.y, z0))
		b.append(Vector3(p.x, p.y, z1))
	face(a, middle, end_col)
	face(b, middle, end_col)
	var count: int = profile.size()
	for i in count:
		var j: int = (i + 1) % count
		face([a[i], a[j], b[j], b[i]], middle, col)

## A faceted tapering cylinder from a to b. `wobble` nudges each corner for a hand-cut look.
func cone(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, wobble := 0.0, rng: RandomNumberGenerator = null, cap := true) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3(0.3, 0.1, 1.0)).normalized()
	var v := axis.cross(u)
	var lo := []
	var hi := []
	var turn := rng.randf() * TAU if rng else 0.0
	for i in sides:
		var t := turn + TAU * i / sides
		var w: float = 1.0 + (rng.randf_range(-wobble, wobble) if rng else 0.0)
		var d := (u * cos(t) + v * sin(t)) * w
		lo.append(a + d * r0)
		hi.append(b + d * r1)
	var middle := (a + b) * 0.5
	for i in sides:
		var j := (i + 1) % sides
		if r1 < 0.001:
			face([lo[i], lo[j], b], middle, col)
		else:
			face([lo[i], lo[j], hi[j], hi[i]], middle, col)
	if cap:
		face(lo, middle, col)
		if r1 >= 0.001:
			face(hi, middle, col)

func mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
