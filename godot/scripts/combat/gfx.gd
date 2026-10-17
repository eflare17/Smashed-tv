class_name FightGfx
extends Node3D
## Draws the fight's many small things the way the HTML game's canvas does, but in 3D: each frame every quad is
## rebuilt into a few ImmediateMeshes (one per texture, plus plain colour ones), so hundreds of sparks, bullets,
## notes, rings and bars cost a handful of draw calls. Positions are HTML units (x, y on the ground, z up).
##
## Two kinds of quad: on the floor (flat, x/y in the ground plane, rotated) and standing (facing the camera like
## the characters: upright when the camera is level, tipped back to face it as it looks steeply down, the same
## rule as CharSprite, so things over the floor read the same as the people).

const U := GameData.UNIT

var cam: Camera3D
var cam_right := Vector3.RIGHT
var cam_up := Vector3.UP
var stand_up := Vector3.UP            ## "up" for standing pictures (tips toward the camera's up from above)
var to_cam := Vector3.BACK

class Batch:
	var mi: MeshInstance3D
	var mesh: ImmediateMesh
	var mat: StandardMaterial3D
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()

var _batches: Dictionary = {}          # key -> Batch

## A batch for this texture (null: plain colour). blend: alpha blended (else cut out); top: drawn over
## everything (no depth test); prio: draw order among blended things; add: additive.
func batch(tex: Texture2D, blend: bool = true, top: bool = false, prio: int = 0, add: bool = false) -> Batch:
	var key := "%s|%s|%s|%d|%s" % [tex.get_instance_id() if tex else 0, blend, top, prio, add]
	if _batches.has(key):
		return _batches[key]
	var b := Batch.new()
	b.mesh = ImmediateMesh.new()
	b.mi = MeshInstance3D.new()
	b.mi.mesh = b.mesh
	b.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.mi.extra_cull_margin = 16384.0
	b.mat = StandardMaterial3D.new()
	b.mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.mat.vertex_color_use_as_albedo = true
	b.mat.vertex_color_is_srgb = true
	b.mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if tex:
		b.mat.albedo_texture = tex
	if add:
		b.mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		b.mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		b.mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	elif blend:
		b.mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		b.mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	else:
		b.mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		b.mat.alpha_scissor_threshold = 0.5
	if top:
		b.mat.no_depth_test = true
		b.mat.render_priority = 20 + prio
	else:
		b.mat.render_priority = prio
	b.mi.material_override = b.mat
	add_child(b.mi)
	_batches[key] = b
	return b

func begin(camera: Camera3D) -> void:
	cam = camera
	for k in _batches:
		var b: Batch = _batches[k]
		b.verts.clear()
		b.cols.clear()
		b.uvs.clear()
	if cam == null:
		return
	var bs := cam.global_transform.basis
	cam_right = bs.x.normalized()
	cam_up = bs.y.normalized()
	to_cam = bs.z.normalized()
	var tip := smoothstep(0.55, 0.9, clampf(to_cam.y, 0.0, 1.0))
	var r := Vector3(cam_right.x, 0.0, cam_right.z)
	r = r.normalized() if r.length() > 0.0001 else Vector3.RIGHT
	cam_right = r
	stand_up = Vector3.UP.lerp(cam_up, tip).normalized()

func finish() -> void:
	for k in _batches:
		var b: Batch = _batches[k]
		b.mesh.clear_surfaces()
		if b.verts.is_empty():
			continue
		b.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in b.verts.size():
			b.mesh.surface_set_color(b.cols[i])
			b.mesh.surface_set_uv(b.uvs[i])
			b.mesh.surface_add_vertex(b.verts[i])
		b.mesh.surface_end()

## HTML (x, y, z) to Godot. Heights go along the standing pictures' "up" (straight up at eye level, tipped
## toward the camera's up from above), so things in the air line up with the people drawn there.
func p3(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * U, 0.0, y * U) + stand_up * (z * U)

## A quad: centre c (Godot), half-axes ax, ay (Godot), uv rect (u0, v0, u1, v1; v down the picture).
func quad(b: Batch, c: Vector3, ax: Vector3, ay: Vector3, col: Color, uv := Rect2(0, 0, 1, 1)) -> void:
	var a := c - ax + ay
	var bb := c + ax + ay
	var cc := c + ax - ay
	var d := c - ax - ay
	var u0 := uv.position.x
	var v0 := uv.position.y
	var u1 := uv.end.x
	var v1 := uv.end.y
	b.verts.append(a)
	b.verts.append(bb)
	b.verts.append(cc)
	b.verts.append(a)
	b.verts.append(cc)
	b.verts.append(d)
	b.uvs.append(Vector2(u0, v0))
	b.uvs.append(Vector2(u1, v0))
	b.uvs.append(Vector2(u1, v1))
	b.uvs.append(Vector2(u0, v0))
	b.uvs.append(Vector2(u1, v1))
	b.uvs.append(Vector2(u0, v1))
	for i in 6:
		b.cols.append(col)

func tri(b: Batch, p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	b.verts.append(p0)
	b.verts.append(p1)
	b.verts.append(p2)
	for i in 3:
		b.uvs.append(Vector2.ZERO)
		b.cols.append(col)

## A standing picture: bottom centre at HTML (x, y, z), w x h units, turned `rot` radians in the view plane about
## its centre, flipped across. anchor_y: 1 = the bottom is at the point, 0.5 = the middle.
func stand(b: Batch, x: float, y: float, z: float, w: float, h: float, col: Color, rot := 0.0, flip := false,
		anchor_y := 1.0, uv := Rect2(0, 0, 1, 1)) -> void:
	var r := cam_right * (w * 0.5 * U)
	var u := stand_up * (h * 0.5 * U)
	var c := p3(x, y, z) + stand_up * (h * (anchor_y - 0.5) * U)
	if rot != 0.0:
		var cs := cos(rot)
		var sn := sin(rot)
		var r2 := r * cs - u * sn * (w / maxf(h, 0.001))
		var u2 := u * cs + r * sn * (h / maxf(w, 0.001))
		r = r2
		u = u2
	if flip:
		r = -r
	quad(b, c, r, u, col, uv)

## A screen-facing square (sparks, the glints): centre at HTML (x, y, z), s units across.
func dot(b: Batch, x: float, y: float, z: float, s: float, col: Color) -> void:
	var r := cam_right * (s * 0.5 * U)
	var u := stand_up * (s * 0.5 * U)
	quad(b, p3(x, y, z), r, u, col)

## A flat quad on the floor at HTML (x, y), w along the rotation `rot`, h across it, lifted by z.
func floor_quad(b: Batch, x: float, y: float, w: float, h: float, rot: float, col: Color, z := 0.6, uv := Rect2(0, 0, 1, 1)) -> void:
	var ax := Vector3(cos(rot), 0.0, sin(rot)) * (w * 0.5 * U)
	var ay := Vector3(-sin(rot), 0.0, cos(rot)) * (h * 0.5 * U)
	quad(b, p3(x, y, z), ax, -ay, col, uv)

## A filled ellipse on the floor.
func floor_ellipse(b: Batch, x: float, y: float, rx: float, ry: float, col: Color, z := 0.5, segs := 20) -> void:
	var c := p3(x, y, z)
	var prev := c + Vector3(rx * U, 0, 0)
	for i in range(1, segs + 1):
		var a := float(i) / segs * TAU
		var p := c + Vector3(cos(a) * rx * U, 0, sin(a) * ry * U)
		tri(b, c, prev, p, col)
		prev = p

## A ring on the floor (outline), width in units; dashes: [on, off] lengths in units (empty = solid).
func floor_ring(b: Batch, x: float, y: float, rx: float, ry: float, width: float, col: Color, z := 0.7,
		segs := 40, dash_on := 0.0, dash_off := 0.0, dash_ofs := 0.0) -> void:
	var c := p3(x, y, z)
	var perim := PI * (rx + ry)
	for i in segs:
		var a0 := float(i) / segs * TAU
		var a1 := float(i + 1) / segs * TAU
		if dash_on > 0.0:
			var s := fposmod(float(i) / segs * perim + dash_ofs, dash_on + dash_off)
			if s > dash_on:
				continue
		var o0 := Vector3(cos(a0) * (rx + width / 2.0), 0, sin(a0) * (ry + width / 2.0)) * U
		var i0 := Vector3(cos(a0) * (rx - width / 2.0), 0, sin(a0) * (ry - width / 2.0)) * U
		var o1 := Vector3(cos(a1) * (rx + width / 2.0), 0, sin(a1) * (ry + width / 2.0)) * U
		var i1 := Vector3(cos(a1) * (rx - width / 2.0), 0, sin(a1) * (ry - width / 2.0)) * U
		tri(b, c + o0, c + o1, c + i1, col)
		tri(b, c + o0, c + i1, c + i0, col)

## A thick line in the air between two HTML points, facing the camera.
func line3(b: Batch, a: Vector3, c: Vector3, width: float, col: Color) -> void:
	var d := c - a
	if d.length() < 0.00001:
		return
	var side := d.cross(to_cam).normalized() * (width * 0.5 * U)
	quad(b, (a + c) * 0.5, d * 0.5, side, col)

## A bar facing the camera (hp bars, power bars): left edge x0 at HTML (x, y) lifted z, w x h units.
func bar(b: Batch, x0: float, y: float, z: float, w: float, h: float, col: Color) -> void:
	var c := p3(x0, y, z) + cam_right * (w * 0.5 * U)
	quad(b, c, cam_right * (w * 0.5 * U), stand_up * (h * 0.5 * U), col)
