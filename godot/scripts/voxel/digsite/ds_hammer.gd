class_name DsHammer
extends VoxelTool
## The hammer (the Dig Site, stage 3: "Shovel, pick, hammer (hammer used later for supports)"), weapon id "hammer_ds",
## group 6 with the other tools (the arena's "hammer" is the sledgehammer). At the Dig Site its left click chips a block
## or two out where you look (DsTools.HAMMER: a framing hammer chips rock, a nail gun anything a steel pick does); stage
## 8 gives it supports to build. Anywhere else it just swings. Its tiers are made at the site office. Owned by the voxel
## session.

const HEAD := [Color8(120, 122, 128), Color8(70, 92, 140), Color8(230, 170, 40)]

func stats() -> Array:
	var ds = arena.get("digsite") if arena else null
	if ds != null and ds.tools != null:
		return ds.tools.stats("hammer_ds")
	return DsTools.HAMMER[0]

func is_shovel() -> bool:
	return false

func _paint(m: StandardMaterial3D) -> void:
	m.albedo_color = HEAD[clampi(tier, 0, 2)]
	m.metallic = 0.75
	m.roughness = 0.35

# a short wooden handle, a steel head across its end: a face one side, a claw the other (the nail gun: a yellow body)
func _model(parent: Node3D, s: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color8(170, 120, 70) if tier < 2 else Color8(40, 40, 44)
	wood.roughness = 0.8
	_paint(_blade_mat)
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.035, 0.03, 0.34) * s
	handle.mesh = hm
	handle.material_override = wood
	handle.position = Vector3(0, 0, -0.12 * s)
	parent.add_child(handle)
	var head := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.14, 0.045) * s if tier < 2 else Vector3(0.07, 0.12, 0.16) * s
	head.mesh = bm
	head.material_override = _blade_mat
	head.position = Vector3(0, 0.0, -0.3 * s)
	parent.add_child(head)
	var face := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.05, 0.04, 0.05) * s
	face.mesh = fm
	face.material_override = _blade_mat
	face.position = Vector3(0, 0.08 * s, -0.3 * s)
	parent.add_child(face)
	if tier < 2:
		var claw := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.03, 0.07, 0.03) * s
		claw.mesh = cm
		claw.material_override = _blade_mat
		claw.position = Vector3(0, -0.09 * s, -0.28 * s)
		claw.rotation.x = 0.5
		parent.add_child(claw)

func bar_text() -> String:
	return ["", "framing", "nailer"][clampi(tier, 0, 2)]

func _bite() -> void:
	var ds = arena.get("digsite")
	if ds == null or not ds.active:
		sfx("dig_scrape", eye() + look() * 1.0, -10.0, 1.4)
		if shooter == arena.me:
			arena.say("The hammer's for the Dig Site (the phone takes you there)", 1.5)
		return
	super()

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var y := r.position.y + r.size.y * 0.5
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.15, y - 2, r.size.x * 0.5, 4), Color(0.66, 0.47, 0.27, col.a))
	var hc: Color = HEAD[clampi(tier, 0, 2)]
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.62, y - r.size.y * 0.3, r.size.x * 0.14, r.size.y * 0.6), Color(hc.r, hc.g, hc.b, col.a))
