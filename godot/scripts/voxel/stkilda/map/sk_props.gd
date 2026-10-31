# (Copied from stkilda-godot scripts/world/props.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkProps
extends RefCounted
## Small things people hold: a spanner, a phone, a set of keys. Built at true size; they go on a person's "Hand"
## point (SkPeople.hold), which is inside the person's scale, so they're sized up by 1 / SkPeople.SCALE.

static func _up(n: Node3D) -> Node3D:
	n.scale = Vector3.ONE / SkPeople.SCALE
	return n

static func spanner() -> Node3D:
	var s := Node3D.new()
	s.name = "Spanner"
	var steel := SkData.C_STEEL_LIGHT
	SkModels.box(s, Vector3(0.03, 0.26, 0.015), Vector3(0, -0.08, 0), steel, 0.3)
	SkModels.box(s, Vector3(0.07, 0.035, 0.016), Vector3(0, -0.225, 0), steel, 0.3)
	for sx in [-1.0, 1.0]:
		SkModels.box(s, Vector3(0.018, 0.05, 0.016), Vector3(sx * 0.028, -0.26, 0), steel, 0.3)
	SkModels.box(s, Vector3(0.05, 0.05, 0.02), Vector3(0, 0.06, 0), steel, 0.3)
	return _up(s)

## A phone, screen toward -z... it's held flat out in front, so the screen faces up its local +y.
static func phone(case_col := Color("#1d1f26")) -> Node3D:
	var p := Node3D.new()
	p.name = "Phone"
	SkModels.box(p, Vector3(0.075, 0.009, 0.155), Vector3.ZERO, case_col, 0.3)
	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.066, 0.142)
	screen.mesh = qm
	screen.name = "Screen"
	screen.rotation.x = -PI / 2.0
	screen.position.y = 0.0055
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color("#9fd9ff")
	screen.material_override = sm
	p.add_child(screen)
	# camera bump on the back
	SkModels.box(p, Vector3(0.025, 0.004, 0.025), Vector3(-0.02, -0.006, -0.055), Color("#3a3d46"), 0.3)
	return _up(p)

## SkCar keys with a mint M&M tag.
static func keys() -> Node3D:
	var k := Node3D.new()
	k.name = "Keys"
	SkModels.box(k, Vector3(0.03, 0.05, 0.015), Vector3(0, -0.02, 0), SkData.C_INK, 0.4)
	SkModels.box(k, Vector3(0.008, 0.045, 0.004), Vector3(0, -0.065, 0), SkData.C_STEEL_LIGHT, 0.3)
	SkModels.box(k, Vector3(0.045, 0.06, 0.006), Vector3(0.03, 0.02, 0), SkData.C_MINT, 0.6)
	return _up(k)

## The front desk's phone, true size, sitting on a desk at y = 0. The caller's side (keypad, display) faces -z;
## the handset ("Handset", lift and jiggle it) lies in its cradle along the back; "Lamp" is the red ring light.
static func desk_phone() -> Node3D:
	var p := Node3D.new()
	p.name = "DeskPhone"
	var body := Color("#2b2d33")
	SkModels.box(p, Vector3(0.2, 0.05, 0.18), Vector3(0, 0.025, 0), body, 0.5)
	var plate := SkModels.box(p, Vector3(0.18, 0.012, 0.1), Vector3(0, 0.058, -0.035), Color("#34363d"), 0.5)
	plate.rotation.x = -0.25
	for r in 4:
		for c in 3:
			var k := SkModels.box(p, Vector3(0.026, 0.008, 0.016), Vector3(-0.04 + c * 0.04, 0.066 + r * 0.005, -0.07 + r * 0.02), Color("#c9ced4"), 0.4)
			k.rotation.x = -0.25
	SkModels.box(p, Vector3(0.09, 0.004, 0.025), Vector3(0.0, 0.074, 0.004), Color("#9fe0c8"), 0.3)      # display
	SkModels.box(p, Vector3(0.2, 0.03, 0.06), Vector3(0, 0.065, 0.06), body, 0.5)                        # cradle
	var lamp := SkModels.box(p, Vector3(0.014, 0.006, 0.014), Vector3(0.08, 0.06, -0.075), Color("#ff3b30"), 0.3)
	lamp.name = "Lamp"
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#ff3b30")
	lm.emission_enabled = true
	lm.emission = Color("#ff3b30")
	lm.emission_energy_multiplier = 3.0
	lamp.material_override = lm
	lamp.visible = false
	var h := Node3D.new()
	h.name = "Handset"
	h.position = Vector3(0, 0.095, 0.06)
	p.add_child(h)
	SkModels.box(h, Vector3(0.16, 0.03, 0.045), Vector3.ZERO, body.lightened(0.05), 0.45)
	for sx in [-1.0, 1.0]:
		SkModels.box(h, Vector3(0.05, 0.04, 0.055), Vector3(sx * 0.085, -0.005, 0), body.lightened(0.05), 0.45)
	SkModels.cyl(p, 0.008, 0.07, Vector3(-0.105, 0.05, 0.06), Color("#1b1c20"), true, 6)               # the curly cord
	return p
