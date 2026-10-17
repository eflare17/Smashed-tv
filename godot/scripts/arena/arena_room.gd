class_name ArenaRoom
extends FightGfx
## The wave arena: what the lobby turns into at Start (godot/specs/enemies_waves.md 3.2, 12.6). The lounge's
## footprint (860 x 520) with a dark grid floor (#1b1e26, #232733 lines every 40 from the wall line), plain walls 18
## thick (#2b3040), the slot machine moved to the middle of the top wall (broken, the OUT OF ORDER sign taped on
## until Gary fixes it) and the vending machine top right. Built hidden; Fight shows it when a run starts.
## The machines are walk-through, as in the HTML.

const WALL_H := 150.0

var sim: FightSim
var _slot: Sprite3D
var _vend: Sprite3D
var _mats: Dictionary = {}

func _ready() -> void:
	name = "ArenaRoom"
	visible = false
	var AW := FightSim.AW
	var AH := FightSim.AH
	var W := FightSim.WALL
	# the floor: a 40-unit grid tile
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color("#1b1e26"))
	for i in 40:
		img.set_pixel(i, 0, Color("#232733"))
		img.set_pixel(0, i, Color("#232733"))
	var tile := ImageTexture.create_from_image(img)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(AW * U, AH * U)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = tile
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fm.texture_repeat = true
	fm.uv1_scale = Vector3(AW / 40.0, AH / 40.0, 1)
	fm.uv1_offset = Vector3(-W / 40.0, -W / 40.0, 0)
	fl.material_override = fm
	fl.position = p3(AW / 2.0, AH / 2.0, 0.05)
	add_child(fl)
	# the walls (and a dark surround past them, so first person doesn't look out at the lobby's sky)
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color("#2b3040")
	var top_m := StandardMaterial3D.new()
	top_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	top_m.albedo_color = Color("#3a4152")
	for r in [Rect2(0, 0, AW, W), Rect2(0, AH - W, AW, W), Rect2(0, 0, W, AH), Rect2(AW - W, 0, W, AH)]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x * U, WALL_H * U, r.size.y * U)
		b.mesh = bm
		b.material_override = wm
		b.position = p3(r.get_center().x, r.get_center().y, WALL_H / 2.0)
		add_child(b)
		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(r.size.x * U, 0.02, r.size.y * U)
		cap.mesh = cm
		cap.material_override = top_m
		cap.position = p3(r.get_center().x, r.get_center().y, WALL_H + 0.5)
		add_child(cap)
	# a ceiling, seen only from below (first person); from above it's culled away
	var ceil := MeshInstance3D.new()
	var cpm := PlaneMesh.new()
	cpm.size = Vector2(AW * U, AH * U)
	cpm.flip_faces = true
	ceil.mesh = cpm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color("#14161c")
	ceil.material_override = cmat
	ceil.position = p3(AW / 2.0, AH / 2.0, WALL_H)
	add_child(ceil)
	var out := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(AW * 6.0 * U, AH * 6.0 * U)
	out.mesh = om
	var omat := StandardMaterial3D.new()
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	omat.albedo_color = Color("#101218")
	out.material_override = omat
	out.position = p3(AW / 2.0, AH / 2.0, -0.6)
	add_child(out)
	_slot = _machine()
	_vend = _machine()

func _machine() -> Sprite3D:
	var s := Sprite3D.new()
	s.centered = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.double_sided = true
	var m := ShaderMaterial.new()
	m.shader = CharSprite._shader(false)
	m.set_shader_parameter("modulate", Color.WHITE)
	m.set_shader_parameter("recolour", false)
	s.material_override = m
	_mats[s] = m
	add_child(s)
	return s

func _put(s: Sprite3D, t: Texture2D, x: float, y: float, h: float, mod: Color) -> void:
	if t == null:
		s.visible = false
		return
	s.visible = true
	if s.texture != t:
		s.texture = t
		_mats[s].set_shader_parameter("tex", t)
	_mats[s].set_shader_parameter("modulate", mod)
	s.pixel_size = h / float(t.get_height()) * U
	s.offset = Vector2(0, t.get_height() / 2.0)
	s.position = p3(x, y, 0)

func _tex(group: String, key: String) -> Texture2D:
	var g = GameData.manifest.get(group, {})
	if g is Dictionary and g.has(key):
		return GameData.tex(String(g[key]))
	return null

func _process(_d: float) -> void:
	begin(get_viewport().get_camera_3d())
	if visible and sim and cam:
		_draw()
	finish()

func _draw() -> void:
	var s := sim
	var floor_c := batch(null, true, false, -2)
	var col := batch(null, false, false, 0)
	# the slot machine
	var spinning := false
	for p: FT.Fighter in s.players:
		if p.spin > 0.0:
			spinning = true
	var key := "win" if s.slot.flash > 0.001 else ("spin" if spinning else ("idle_b" if int(floor(s.t * 3.0)) % 2 else "idle_a"))
	var dim := s.slot.cool > 0.0 and not spinning and s.slot.flash <= 0.001
	var a := 0.38 if s.slot.broken else (0.55 if dim else 1.0)
	var h := 92.0 * s.tv("slotScale", 1.35)
	floor_ellipse(floor_c, s.slot.x, s.slot.y - 2.0, 34.5, 12.0, Color(0, 0, 0, 0.35))
	_put(_slot, _tex("SLOT_SPRITES", key), s.slot.x, s.slot.y - 4.0, h, Color(a, a, a) if s.slot.broken else Color(a, a, a))
	if s.slot.cool > 0.0:
		bar(batch(null, true, true, 4), s.slot.x - 28.0, s.slot.y + 14.0, 2.0, 56.0, 5.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.75))
		bar(batch(null, true, true, 4), s.slot.x - 28.0, s.slot.y + 14.0, 2.0, 56.0 * (1.0 - s.slot.cool / s.tv("spinCool", 8)), 5.0, Color("#5a6274"))
	if spinning or s.slot.flash > 0.001:
		_reels(h, spinning)
	# the OUT OF ORDER sign: on the cabinet, or thrown on the floor
	if s.sign == "stand":
		_card(p3(s.slot.x + 4.0, s.slot.y + 2.0, 60.0) + to_cam * 0.12, cam_right, stand_up, -0.06, col)
	elif s.sign == "floor":
		_card(p3(s.slot.x + 30.0, s.slot.y + 26.0, 1.2), Vector3(cos(0.5), 0, sin(0.5)), Vector3(sin(0.5), 0, -cos(0.5)) * 0.45, 0.0, col)
	# the vending machine
	var vp := s.vend_pos()
	var vk := "sold" if s.vend_sold else ("idle_b" if int(floor(s.t * 2.5)) % 2 else "idle_a")
	floor_ellipse(floor_c, vp.x, vp.y - 2.0, 39.6, 12.0, Color(0, 0, 0, 0.35))
	_put(_vend, _tex("VEND_SPRITES", vk), vp.x, vp.y - 4.0, s.tv("vendHeight", 150), Color.WHITE)
	for p: FT.Fighter in s.players:
		if p.buy > 0.0:
			var tb := batch(null, true, true, 4)
			bar(tb, vp.x - 35.0, vp.y + 20.0, 2.0, 70.0, 6.0, Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.8))
			bar(tb, vp.x - 35.0, vp.y + 20.0, 2.0, 70.0 * p.buy / s.tv("vendHold", 0.8), 6.0, Color("#9be29b"))

# The reels in the cabinet's window (13.5): the first two land on the decoys at 45% and 70% of the pull, the
# third keeps turning; when the prize is paid all three show its symbol.
func _reels(h: float, spinning: bool) -> void:
	var s := sim
	# drawn over the cabinet's picture (its depth is a standing figure's, nearer than its tipped-back top)
	var b := batch(null, false, true, 1)
	var dw := h * 89.0 / 128.0
	var rw := dw * 0.16 * 1.9
	var rh := h * 0.115 * 1.9
	var zc := h * 0.497 - 2.0
	var base := p3(s.slot.x, s.slot.y - 4.0, zc) + to_cam * 0.5
	var frac := 1.0
	for p: FT.Fighter in s.players:
		if p.spin > 0.0:
			frac = 1.0 - p.spin / maxf(0.05, s.tv("spinTime", 1.6))
	var cols := [-18.4, 2.1, 22.6]
	var stops := [0.45, 0.70, 1.0]
	quad(b, base, cam_right * ((cols[2] - cols[0] + rw) * 0.5 + rw * 0.22) * U, stand_up * (rh * 0.5 + rh * 0.3) * U,
		Color(12 / 255.0, 13 / 255.0, 18 / 255.0, 1.0))
	var prize_sym: int = FightSim.PRIZES[clampi(s.slot.prize, 0, 7)].sym
	for i in 3:
		var c: Vector3 = base + cam_right * (cols[i] * U) + to_cam * 0.01
		quad(b, c, cam_right * (rw * 0.5 * U), stand_up * (rh * 0.5 * U), Color("#f2efe6"))
		var sym: int
		if spinning and frac < stops[i]:
			sym = (i * 2 + int(floor(s.t * 9.0))) % 6
		else:
			sym = prize_sym if (i == 2 or s.slot.flash > 0.001) else int(s.slot.decoy[i])
		_sym(b, c + to_cam * 0.01, sym, rh * 0.8)
		if spinning and frac < stops[i]:
			quad(batch(null, true, true, 2), c + to_cam * 0.02, cam_right * (rw * 0.5 * U), stand_up * (rh * 0.5 * U), Color(0.95, 0.94, 0.9, 0.45))

# drawSym: heart, shotgun, coin, bolt, star, skull.
func _sym(b: Batch, c: Vector3, sym: int, size: float) -> void:
	var u := size / 10.0 * U
	var R := cam_right * u
	var Up := stand_up * u
	match sym:
		0:
			_disc(b, c - R * 2.0 + Up * 1.0, 2.4 * u, Color("#e0473f"))
			_disc(b, c + R * 2.0 + Up * 1.0, 2.4 * u, Color("#e0473f"))
			tri(b, c - R * 4.2, c + R * 4.2, c - Up * 4.4, Color("#e0473f"))
		1:
			quad(b, c - R * 0.5, R * 4.0, Up * 1.1, Color("#4a5260"))
			quad(b, c + R * 3.75, R * 1.25, Up * 1.6, Color("#8a5a33"))
		2:
			_disc(b, c, 3.6 * u, Color("#d9a520"))
			_disc(b, c + to_cam * 0.002, 2.4 * u, Color("#f6d17a"))
		3:
			var pts := [Vector2(1.5, -4), Vector2(-2.5, 0.6), Vector2(-0.2, 0.6), Vector2(-1.5, 4), Vector2(2.5, -0.6), Vector2(0.2, -0.6)]
			tri(b, c + R * pts[0].x - Up * pts[0].y, c + R * pts[1].x - Up * pts[1].y, c + R * pts[2].x - Up * pts[2].y, Color("#6fd3a0"))
			tri(b, c + R * pts[3].x - Up * pts[3].y, c + R * pts[4].x - Up * pts[4].y, c + R * pts[5].x - Up * pts[5].y, Color("#6fd3a0"))
			tri(b, c + R * pts[0].x - Up * pts[0].y, c + R * pts[2].x - Up * pts[2].y, c + R * pts[5].x - Up * pts[5].y, Color("#6fd3a0"))
			tri(b, c + R * pts[3].x - Up * pts[3].y, c + R * pts[5].x - Up * pts[5].y, c + R * pts[2].x - Up * pts[2].y, Color("#6fd3a0"))
		4:
			for k in 5:
				var a0 := -PI / 2.0 + k * TAU / 5.0
				var a1 := a0 + PI / 5.0
				var a2 := a0 - PI / 5.0
				tri(b, c, c + (R * cos(a0) - Up * sin(a0)) * 4.0, c + (R * cos(a1) - Up * sin(a1)) * 1.7, Color("#f6d17a"))
				tri(b, c, c + (R * cos(a0) - Up * sin(a0)) * 4.0, c + (R * cos(a2) - Up * sin(a2)) * 1.7, Color("#f6d17a"))
		_:
			_disc(b, c + Up * 0.6, 3.4 * u, Color("#cfd4de"))
			quad(b, c - Up * 2.5, R * 2.0, Up * 1.1, Color("#cfd4de"))
			quad(b, c - R * 1.2 + Up * 0.5 + to_cam * 0.002, R * 0.8, Up * 0.9, Color("#14161c"))
			quad(b, c + R * 1.2 + Up * 0.5 + to_cam * 0.002, R * 0.8, Up * 0.9, Color("#14161c"))

func _disc(b: Batch, c: Vector3, r: float, col: Color) -> void:
	var prev := c + cam_right * r
	for i in range(1, 15):
		var a := float(i) / 14.0 * TAU
		var p := c + cam_right * (cos(a) * r) + stand_up * (sin(a) * r)
		tri(b, c, prev, p, col)
		prev = p

# The cardboard sign (drawSign): a card with a strip, two bits of tape, and OUT OF / ORDER marks.
func _card(c: Vector3, r: Vector3, u: Vector3, rot: float, b: Batch) -> void:
	var rr := (r * cos(rot) - u * sin(rot)) * U
	var uu := (u * cos(rot) + r * sin(rot)) * U
	quad(b, c + uu * 0.0, rr * 23.0, uu * 15.0, Color(0, 0, 0, 1))
	quad(b, c + rr * 0.0 + uu * 0.2, rr * 22.0, uu * 14.0, Color("#c8a56b"))
	quad(b, c + uu * 12.5, rr * 22.0, uu * 1.5, Color("#a8854f"))
	quad(b, c + rr * -19.0 + uu * 14.0, rr * 5.0, uu * 2.5, Color("#ece3d0"))
	quad(b, c + rr * 19.0 - uu * 13.0, rr * 5.0, uu * 2.5, Color("#ece3d0"))
	# the words, as two dark bars of "type"
	quad(b, c + uu * 3.0, rr * 14.0, uu * 2.5, Color("#2b2118"))
	quad(b, c - uu * 6.0, rr * 12.0, uu * 2.5, Color("#2b2118"))
