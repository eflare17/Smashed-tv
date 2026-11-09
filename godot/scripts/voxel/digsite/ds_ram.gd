class_name DsRam
extends Node3D
## A hydraulic ram (the owner, 9 Nov: "so you can actually see the hydraulics", then "do all three": every machine's):
## a painted barrel pinned at one end, a chrome rod pinned at the other, sliding in and out of it as the pins move
## apart. A tip truck's has stages, each sliding out of the one before. aim(a, b) each pose, in its parent's space (it
## sits at its parent's origin). Owned by the voxel session.

var stage_len := 0.6            # each tube's length (the barrel's; stages' too)
var _tubes: Array[MeshInstance3D] = []
var _rod: MeshInstance3D

## A ram with tubes of stage_len (stages of them, the barrel first: 1 for a plain ram), radius r (the barrel's; each
## stage a little thinner), a chrome rod of rod_r, the barrel in col, hoses along it or not
static func make(parent: Node3D, length: float, r: float, rod_r: float, col: Color, stages := 1, hoses := true) -> DsRam:
	var ram := DsRam.new()
	ram.stage_len = length
	parent.add_child(ram)
	for k in stages:
		var kit := DsKit.new()
		var rk := r - (r - rod_r) * float(k) / float(stages)
		if k == 0:
			kit.box(Vector3.ZERO, Vector3(r * 1.6, r * 1.3, r * 1.1), DsProps.CHARCOAL)
			kit.cone(Vector3(r * 0.5, 0.0, 0.0), Vector3(length, 0.0, 0.0), r, r, 10, col)
			kit.cone(Vector3(r * 0.5, 0.0, 0.0), Vector3(r * 1.1, 0.0, 0.0), r * 1.12, r * 1.12, 10, DsProps.YELLOW_DARK if col != DsProps.CHARCOAL else DsProps.BLACK)
			if hoses:
				var h := r + 0.02
				kit.cone(Vector3(r * 1.4, h, 0.0), Vector3(length - r * 1.0, h, 0.0), 0.022, 0.022, 5, DsProps.BLACK)
				kit.cone(Vector3(length - r * 1.0, h, 0.0), Vector3(length - r * 1.0, r * 0.6, 0.0), 0.03, 0.03, 6, DsProps.STEEL)
				kit.cone(Vector3(r * 1.4, h, 0.0), Vector3(r * 1.4, r * 0.6, 0.0), 0.03, 0.03, 6, DsProps.STEEL)
				kit.cone(Vector3(r * 0.8, r * 0.8, 0.0), Vector3(-r * 1.2, r * 2.2, 0.0), 0.022, 0.022, 5, DsProps.BLACK)
		else:
			kit.cone(Vector3.ZERO, Vector3(length, 0.0, 0.0), rk, rk, 10, DsProps.CHROME)
		# the gland it comes out of
		kit.cone(Vector3(length - 0.06, 0.0, 0.0), Vector3(length, 0.0, 0.0), rk * 1.12, rk * 0.9, 10, DsProps.STEEL if k > 0 else DsProps.YELLOW_DARK if col != DsProps.CHARCOAL else DsProps.BLACK)
		ram._tubes.append(ram._mesh(kit))
	var rod := DsKit.new()
	rod.cone(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), rod_r, rod_r, 8, DsProps.CHROME)
	ram._rod = ram._mesh(rod)
	return ram

func _mesh(kit: DsKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsLook.prop_mat()
	add_child(m)
	return m

## The barrel's pin at a, the rod's at b (its parent's space; side: the way its hoses don't face, roughly)
func aim(a: Vector3, b: Vector3, side := Vector3.BACK) -> void:
	var d := a.distance_to(b)
	var x := (b - a) / maxf(d, 0.001)
	var z := side - x * x.dot(side)
	z = z.normalized() if z.length_squared() > 0.0001 else x.cross(Vector3.UP).normalized()
	var bas := Basis(x, z.cross(x), z)
	# (pins close together: the tubes are kept short of the rod's pin)
	var l := minf(stage_len, d - 0.12)
	var fit := Basis.from_scale(Vector3(maxf(l, 0.05) / stage_len, 1.0, 1.0))
	var n := _tubes.size()
	# each stage out of the one before by the same, keeping 8 cm in it
	var step := 0.0 if n < 2 else clampf((d - l) / float(n), 0.0, l - 0.08)
	for k in n:
		_tubes[k].transform = Transform3D(bas * fit, a + x * (step * k))
	var back := step * (n - 1) + l - 0.1
	var rod := maxf(0.05, d - back)
	_rod.transform = Transform3D(Basis(-x, z.cross(x), -z) * Basis.from_scale(Vector3(rod, 1.0, 1.0)), b)
