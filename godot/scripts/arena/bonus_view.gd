class_name BonusView
extends FightGfx
## Draws the secret bonus room (godot/specs/gore_loot.md 14.5): during the intro the suction from the cabinet (a cyan
## cone, notes spiralling in; the players are dragged in by Fight), then inside the machine its art over the floor,
## four cogs turning in the corners, twelve chasing lamps along the top, and the skull stamps with their warning rings
## and countdowns. Texts are FightHud's.

var sim: FightSim
var _floor: MeshInstance3D
var _floor_mat: StandardMaterial3D

func _ready() -> void:
	name = "BonusView"
	_floor = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(FightSim.AW * U, FightSim.AH * U)
	_floor.mesh = pm
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var mp = GameData.manifest.get("MACHINE_ART.src")
	if mp is String and ResourceLoader.exists("res://" + mp):
		_floor_mat.albedo_texture = GameData.tex(mp)
	else:
		_floor_mat.albedo_color = Color("#202936")
	_floor.material_override = _floor_mat
	_floor.position = Vector3(FightSim.AW / 2.0 * U, 0.004, FightSim.AH / 2.0 * U)
	_floor.visible = false
	add_child(_floor)

func _process(_d: float) -> void:
	begin(get_viewport().get_camera_3d())
	var sec := sim.secret if sim else null
	_floor.visible = sec != null and sec.room
	if sec and sec.phase != "done" and cam:
		if sec.phase == "intro":
			_intro(sec)
		if sec.room:
			_room(sec)
	finish()

func _intro(sec: FT.Secret) -> void:
	var s := sim
	var t := sec.t
	var b := batch(null, true, false, 2)
	var hx := s.slot.x
	var hy := s.slot.y + 4.0
	var power := clampf((t - 0.5) / 1.0, 0.0, 1.0)
	if power > 0.0 and t < 5.6:
		var mouth := p3(hx, hy, 30.0)
		for i in 12:
			var a0 := -0.55 + i / 12.0 * 1.1
			var a1 := -0.55 + (i + 1) / 12.0 * 1.1
			tri(b, mouth, p3(hx + sin(a0) * 260.0, hy + cos(a0) * 300.0, 0.5), p3(hx + sin(a1) * 260.0, hy + cos(a1) * 300.0, 0.5),
				Color(0.39, 0.97, 1.0, power * 0.2))
		var mb := batch(null, true, true, 3)
		quad(mb, p3(hx, hy, 30.0), cam_right * (13.0 * U), stand_up * (4.5 * U), Color("#46e7f4"))
		quad(mb, p3(hx, hy, 30.0) + to_cam * 0.01, cam_right * (8.0 * U), stand_up * (2.0 * U), Color("#e0ffff"))
	if t > 1.0 and t < 4.6:
		for i in 15:
			var f := fposmod((t - 1.0) * 0.65 + i / 15.0, 1.0)
			var a := 2.4 * i
			var x := hx + cos(a) * (1.0 - f) * 175.0
			var y := hy + 40.0 + (1.0 - f) * 200.0
			floor_quad(b, x, y, 12.0, 6.0, a + t, Color("#58b37a"), 10.0 + 20.0 * f)

func _room(sec: FT.Secret) -> void:
	var s := sim
	var b := batch(null, true, false, 1)
	var bf := batch(null, true, false, -1)
	var cogp = GameData.manifest.get("COG_ART.src")
	var cog: Texture2D = GameData.tex(cogp) if cogp is String and ResourceLoader.exists("res://" + cogp) else null
	if cog:
		for c in [[0, 0, 1, 0], [860, 0, -1, 0.2], [0, 520, -1, 0.4], [860, 520, 1, 0.6]]:
			floor_quad(batch(cog, false, false, -1), c[0], c[1], 200.0, 200.0, s.t * 0.12 * c[2] + c[3], Color.WHITE, 3.0)
	for i in 12:
		var on := (int(floor(s.t * 7.0)) + i) % 4 == 0
		floor_quad(bf, 82.0 + 62.0 * i, 109.0, 9.0, 3.0, 0.0, Color("#d9ffff") if on else Color("#235e72"), 0.5)
	for h: FT.Hazard in sec.hazards:
		if h.hp <= 0.0:
			continue
		var warn := h.t < 1.25
		floor_ellipse(bf, h.x, h.y, 38.0, 22.0, Color(0.95, 0.37, 0.24, 0.12) if warn else Color(1.0, 0.58, 0.4, 0.35), 0.6, 24)
		floor_ring(bf, h.x, h.y, 38.0, 22.0, 2.0, Color("#fa965f") if warn else Color("#ffdad1"), 0.7, 32)
		if warn:
			var segs := int(30 * h.t / 1.25)
			var prev := p3(h.x, h.y - 23.0, 0.8)
			for k in range(1, segs + 1):
				var a := -PI / 2.0 + float(k) / 30.0 * TAU
				var pp := p3(h.x + cos(a) * 23.0, h.y + sin(a) * 23.0, 0.8)
				line3(bf, prev, pp, 2.0, Color("#fa965f"))
				prev = pp
		# the skull block: up over its mark while it warns, stamped down after
		var z := 35.0 if warn else 13.0
		var col := Color("#c1ced2") if warn else Color("#ee9774")
		var c := p3(h.x, h.y, z)
		quad(b, c, cam_right * (16.0 * U), stand_up * (12.5 * U), col)
		quad(b, c - stand_up * (14.5 * U), cam_right * (10.0 * U), stand_up * (3.5 * U), col)
		quad(b, c + cam_right * (-7.0 * U) + stand_up * (4.0 * U) + to_cam * 0.01, cam_right * (4.0 * U), stand_up * (4.0 * U), Color("#202735"))
		quad(b, c + cam_right * (7.0 * U) + stand_up * (4.0 * U) + to_cam * 0.01, cam_right * (4.0 * U), stand_up * (4.0 * U), Color("#202735"))
		for i in 3:
			bar(batch(null, true, true, 4), h.x - 12.0 + 9.0 * i, h.y, z + 18.0, 6.0, 3.0, Color("#66e5ed") if i < int(h.hp) else Color("#343f50"))
