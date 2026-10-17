class_name LobbyBbq
extends LobbyThing
## The barbecue and the esky on the back deck (Smashed.html: BBQ @2041, ESKY, bbqLabel @2048, bbqAction @2058, bbqStep
## @2073, snagColour @2357, drawSnag, drawBbq @2369, bbqFx @2341, drawHeldSnag @2398). Owned by the Lobby life session.
##
## E at the esky (within 42 of 504, 701): GRAB SNAG (the esky is bottomless) or PUT BACK. At the barbecue (in the
## strip in front of it, x 522..626, y 634..692): LIGHT / TURN UP / TURN UP / TURN OFF cycle the heat 0..3; COOK
## lays the snag in a free place (four, in two columns); TAKE SNAG takes the most-cooked one that's done. The
## snags cook at 0.055 / 0.1 / 0.17 a second by heat (raw pink 0, cooked brown 1, burnt black from 1 to 1.6); burners
## glow, the plate sizzles and smokes (black smoke when anything's burning). With a cooked snag in hand E, anywhere,
## says EAT (+1 health if he has hp and isn't full, floater YUM!); a burnt one says EAT IT? (BLEH!).
##
## The live hotplate is a flat picture on the barbecue's top; the world's own barbecue box stays under it.
## The snag in hand is a little picture at his side (first person: one rotated in the corner of the view).

signal ate(player: Node, burnt: bool)

const BBQ := Rect2(522.0, 634.0, 104.0, 58.0)
const TOP := Rect2(520.0, 576.0, 66.0, 46.0)    # BBQ.fp: the hotplate's footprint on the top (36 up)
const TOP_Z := 36.2
const ESKY := Vector2(504.0, 701.0)
const RATE := [0.0, 0.055, 0.1, 0.17]

var heat: int = 0
var s: Array = [-1.0, -1.0, -1.0, -1.0]
## What each player is holding: 0 nothing, 1 raw, 2 cooked, 3 burnt (player meta "food" too).
var food: Dictionary = {}

var _plate: MeshInstance3D
var _plate_tex: ImageTexture
var _t: float = 0.0
var _draw_t: float = 0.0
var _sizzle_t: float = 0.0
var _held: Dictionary = {}          # player -> LobbyPic
var _fp_snag: ColorRect
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	reach = 100000.0                       # EAT works anywhere; the others check where he stands
	rng.randomize()
	global_position = GameData.world_to_3d(560.0, 660.0, 0.0)
	await get_tree().process_frame
	_build_plate()
	_fp_snag = ColorRect.new()
	_fp_snag.size = Vector2(120, 26)
	_fp_snag.visible = false
	_fp_snag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fp_snag.rotation = -0.18
	ll.ui.fx_root.add_child(_fp_snag)

# ------------------------------------------------------------------ where and what

func near_bbq(p: Node) -> bool:
	var o := ppos(p)
	return o.x > BBQ.position.x and o.x < BBQ.end.x and o.y > BBQ.position.y and o.y < BBQ.end.y

func near_esky(p: Node) -> bool:
	return ppos(p).distance_to(ESKY) < 42.0

func food_of(p: Node) -> int:
	return int(food.get(p, 0))

## bbqLabel.
func label_for(p: Node) -> String:
	if not (p is Player) or bool(p.get("frozen")) or float(p.get("dz")) > 0.5:
		return ""
	var f := food_of(p)
	if near_bbq(p):
		if f == 1:
			if s.has(-1.0):
				return "COOK"
		elif f == 0:
			for c in s:
				if float(c) >= 1.0:
					return "TAKE SNAG"
			return ["LIGHT", "TURN UP", "TURN UP", "TURN OFF"][heat]
	if near_esky(p):
		if f == 0:
			return "GRAB SNAG"
		if f == 1:
			return "PUT BACK"
	if f >= 2:
		return "EAT" if f == 2 else "EAT IT?"
	return ""

## bbqAction.
func act(p: Node) -> void:
	var l := label_for(p)
	var f := food_of(p)
	match l:
		"LIGHT", "TURN UP", "TURN OFF":
			set_heat((heat + 1) % 4)
		"COOK":
			var i := s.find(-1.0)
			if i >= 0:
				s[i] = 0.0
				set_food(p, 0)
		"TAKE SNAG":
			var best := -1
			for i in 4:
				if float(s[i]) >= 1.0 and (best < 0 or float(s[i]) > float(s[best])):
					best = i
			if best >= 0:
				set_food(p, 3 if float(s[best]) >= 1.6 else 2)
				s[best] = -1.0
		"GRAB SNAG":
			set_food(p, 1)
		"PUT BACK":
			set_food(p, 0)
		"EAT", "EAT IT?":
			set_food(p, 0)
			var o := ppos(p)
			if f == 2:
				ll.ui.float_text(o.x, o.y, 70.0, "YUM!", Color("#7fd89a"), 1.0, 18)
				var hp = p.get("hp")
				if hp != null and int(hp) < int(LobbyLife.T("playerHp", 5)):
					p.set("hp", int(hp) + 1)
				ll.sfx.play("munch")
			else:
				ll.ui.float_text(o.x, o.y, 70.0, "BLEH!", Color("#9aa0a8"), 1.0, 18)
				ll.sfx.play("cough")
			ate.emit(p, f == 3)
	_draw_plate()

func set_heat(h: int) -> void:
	var was := heat
	heat = h
	ll.sfx.tone(1800, 0.03, "square", 0.05, 1200)
	if was == 0 and h > 0:
		ll.sfx.noise(0.5, 0.25, 0.4)

func set_food(p: Node, f: int) -> void:
	food[p] = f
	p.set_meta("food", f)

# ------------------------------------------------------------------ cooking and the show

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	_t += dt
	if heat > 0:
		for i in 4:
			if float(s[i]) >= 0.0:
				s[i] = minf(2.0, float(s[i]) + RATE[heat] * dt)
	_fx(dt)
	_draw_t += dt
	if _draw_t > (0.08 if heat > 0 else 0.5):
		_draw_t = 0.0
		_draw_plate()
	_held_snags()

## bbqFx: sizzle and smoke.
func _fx(dt: float) -> void:
	if heat <= 0 or ll == null or ll.smoke == null:
		return
	var on := 0
	var burnt := false
	for c in s:
		if float(c) >= 0.0:
			on += 1
			if float(c) > 1.5:
				burnt = true
	var near := maxf(0.0, 1.0 - ppos(ll.player).distance_to(Vector2(553, 600)) / 700.0)
	if on > 0:
		_sizzle_t -= dt
		if _sizzle_t <= 0.0:
			_sizzle_t = rng.randf_range(0.05, 0.17)
			ll.sfx.noise(0.08, (0.012 + 0.01 * heat) * near * 6.0, 0.9)
		if rng.randf() < dt * (2.0 + 3.0 * heat + (8.0 if burnt else 0.0)):
			_puff(rng.randf_range(0.15, 0.85), rng.randf_range(0.2, 0.8), 3.0, 0.5 if burnt else 0.28, Color(0.24, 0.24, 0.24) if burnt else Color(0.82, 0.82, 0.82), 1.6)
	elif rng.randf() < dt * 0.8:
		_puff(rng.randf_range(0.2, 0.8), 0.5, 2.0, 0.12, Color(0.78, 0.78, 0.78), 1.2)

func _puff(u: float, v: float, r: float, a: float, col: Color, life: float) -> void:
	ll.smoke.puff(TOP.position.x + u * TOP.size.x, TOP.position.y + v * TOP.size.y, TOP_Z + 2.0,
		rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), 26.0, r * 1.4, 7.0, life, a, col)

## snagColour: raw (232, 150, 150) to cooked (150, 84, 44) to burnt (36, 28, 24).
static func snag_colour(c: float) -> Color:
	var k := minf(1.0, c)
	var b := clampf((c - 1.0) / 0.6, 0.0, 1.0)
	var r := 232.0 + (150.0 - 232.0) * k
	var g := 150.0 + (84.0 - 150.0) * k
	var bl := 150.0 + (44.0 - 150.0) * k
	return Color8(int(r + (36.0 - r) * b), int(g + (28.0 - g) * b), int(bl + (24.0 - bl) * b))

func _build_plate() -> void:
	_plate = MeshInstance3D.new()
	_plate.name = "Hotplate"
	var q := QuadMesh.new()
	q.size = TOP.size * GameData.UNIT
	q.orientation = PlaneMesh.FACE_Y
	_plate.mesh = q
	var im := Image.create(int(TOP.size.x), int(TOP.size.y), false, Image.FORMAT_RGBA8)
	_plate_tex = ImageTexture.create_from_image(im)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _plate_tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_plate.material_override = m
	_plate.top_level = true
	add_child(_plate)
	_plate.global_position = GameData.world_to_3d(TOP.position.x + TOP.size.x / 2.0, TOP.position.y + TOP.size.y / 2.0, TOP_Z)
	_draw_plate()

## bbqPlateRGB (the first-person hotplate): the plate, its bars, the glowing gaps and the snags.
func _draw_plate() -> void:
	if _plate_tex == null:
		return
	var w := int(TOP.size.x)
	var h := int(TOP.size.y)
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color8(38, 39, 43))
	for y in h:
		var v := float(y) / h
		var bar := fposmod(v * 34.0, 3.0) < 1.2
		for x in w:
			var u := float(x) / w
			var c := Color8(38, 39, 43)
			if bar:
				c = Color8(96, 99, 106)
			elif heat > 0:
				var f := (0.25 + 0.17 * heat) * (0.7 + 0.3 * sin(13.0 * _t + 60.0 * u))
				c = Color8(int(clampf(34.0 + 210.0 * f, 0, 255)), int(clampf(30.0 + 100.0 * f * f, 0, 255)), 28)
			im.set_pixel(x, y, c)
	for i in 4:
		var si := float(s[i])
		if si < 0.0:
			continue
		var su := 0.1 + (i % 2) * 0.47
		var sv := 0.18 + (i >> 1) * 0.42
		var col := snag_colour(si)
		for y in range(int(sv * h), int((sv + 0.22) * h)):
			for x in range(int(su * w), int((su + 0.33) * w)):
				var c := col
				if si > 0.45 and fposmod((float(x) / w - su) * 40.0, 3.3) < 0.5:
					c = c.darkened(0.5)
				im.set_pixel(x, y, c)
	# the knobs along the front
	var lit: int = [0, 1, 3, 5][heat]
	for k in 5:
		im.set_pixel(clampi(4 + k * 14, 0, w - 1), h - 3, Color("#ff5a2a") if k < lit else Color(0.2, 0.2, 0.22))
	_plate_tex.set_image(im)

## drawHeldSnag: a little snag beside him (first person: the one in the corner of the view).
func _held_snags() -> void:
	for p in food.keys():
		if not is_instance_valid(p):
			continue
		var f := int(food[p])
		var pic: LobbyPic = _held.get(p)
		if f <= 0 or p.is_first_person():
			if pic:
				pic.visible = false
		else:
			if pic == null:
				var img := Image.create(14, 5, false, Image.FORMAT_RGBA8)
				pic = LobbyPic.make(ImageTexture.create_from_image(img), 1.0, 0.0)
				p.add_child(pic)
				_held[p] = pic
			pic.visible = true
			var c := snag_colour([0.0, 0.0, 1.0, 1.8][f])
			var img2 := Image.create(14, 5, false, Image.FORMAT_RGBA8)
			img2.fill(c)
			img2.set_pixel(0, 0, Color(0, 0, 0, 0))
			img2.set_pixel(13, 0, Color(0, 0, 0, 0))
			img2.set_pixel(0, 4, Color(0, 0, 0, 0))
			img2.set_pixel(13, 4, Color(0, 0, 0, 0))
			img2.fill_rect(Rect2i(3, 1, 8, 1), c.lightened(0.35 if f < 3 else 0.1))
			(pic.texture as ImageTexture).set_image(img2)
			var fx := -18.0 if p.facing.x < 0.0 else 4.0
			pic.position = Vector3(fx * GameData.UNIT, 0.0, 0.0)
			pic.lift = 20.0
	if ll and ll.player:
		var pf := food_of(ll.player)
		_fp_snag.visible = pf > 0 and ll.player.is_first_person()
		if _fp_snag.visible:
			var vs := get_viewport().get_visible_rect().size
			_fp_snag.size = Vector2(vs.x * 0.17, vs.y * 0.065)
			_fp_snag.position = Vector2(vs.x * 0.5, vs.y * 0.7)
			_fp_snag.color = snag_colour([0.0, 0.0, 1.0, 1.8][pf])

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(560.0, 665.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	tl.later(0.5, func():
		set_food(ll.player, 1)
		s[0] = 0.4
		s[1] = 1.2
		s[3] = 1.7
		heat = 3)
