class_name DsDynamite
extends VoxelTool
## Dynamite (the Dig Site, stage 9), weapon id "dynamite_ds", group 4 with the explosives. Left click at the Dig Site:
## a stick put down where you aim (or at your feet), lit: run (DsBlasts: FUSE seconds). It takes a stick from your
## backpack (the site office sells them). Anywhere else it does nothing. Owned by the voxel session.

func stats() -> Array:
	return [0.0, 0, 0.8, "Dynamite"]

func is_shovel() -> bool:
	return false

func _paint(m: StandardMaterial3D) -> void:
	m.albedo_color = Color8(200, 30, 30)
	m.roughness = 0.7

# a red stick, a fuse out of its end
func _model(parent: Node3D, s: float) -> void:
	_paint(_blade_mat)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03 * s
	cm.bottom_radius = 0.03 * s
	cm.height = 0.24 * s
	stick.mesh = cm
	stick.material_override = _blade_mat
	stick.rotation.x = PI * 0.5
	stick.position = Vector3(0, 0, -0.1 * s)
	parent.add_child(stick)
	var fuse := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.008, 0.008, 0.08) * s
	fuse.mesh = fm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color8(230, 220, 200)
	fuse.material_override = wm
	fuse.position = Vector3(0, 0.0, -0.26 * s)
	parent.add_child(fuse)

func bar_text() -> String:
	return "%d" % arena.inv.count("dynamite") if arena and arena.inv else ""

func press(button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or _cd > 0.0 or _t >= 0.0:
		return
	var ds = arena.get("digsite")
	_cd = 0.8
	_t = 0.0
	_bit = true
	if shooter != arena.me:
		return
	if ds == null or not ds.active:
		arena.say("Dynamite's for the Dig Site (the phone takes you there)", 1.5)
		return
	var ad := _aim_digsite()
	var at: Vector3 = ad[0] if not ad.is_empty() else shooter.player.global_position
	ds.blasts.light(at)

func _bite() -> void:
	pass

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var y := r.position.y + r.size.y * 0.5
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.2, y - r.size.y * 0.15, r.size.x * 0.5, r.size.y * 0.3), Color(0.8, 0.12, 0.12, col.a))
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.7, y - 1, r.size.x * 0.15, 2), Color(0.9, 0.86, 0.78, col.a))
