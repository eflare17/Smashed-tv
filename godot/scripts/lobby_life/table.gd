class_name LobbyTable
extends LobbyThing
## The lounge table with its two chairs, sitting, the bong and its trip, and blackjack with Gothica dealing
## (specs/table.md, following Smashed.html: chairNear 3435, drawTable 3444, lobbyAction 10152, drawSitArt 5136,
## drawSitIdle 5189, bongHit 5009). Owned by the Lobby life session; split in three:
##   table.gd        this file: the chairs, sitting, the bong, the hit (Jared's sit art frame by frame), the table's
##                   look. Every picture standing on the table is drawn in the table picture's own coordinates.
##   table_cards.gd  LobbyTableCards: blackjack (the rules, Gothica dealing, the panel and buttons, cards on the table).
##   table_trip.gd   LobbyTableTrip: the screen the second hit in a row opens (the mantis, the dark, the music).
##
## E next to a chair: SIT. Seated: E takes the bong (BONG), then every E is a hit (HIT, about 6 s). Walking off (the
## stick or keys; Shift, RB or LT; not pad B) stands him up and cancels the hit. Two hits finished 3 to 30 s apart
## are a trip (on this screen only). B / pad X calls Gothica and deals, H / pad Y hits, T / pad B stands (the HTML
## game's keys); the panel's buttons do the same for the mouse and touch.
##
## Both views. Top-down it is the HTML picture. First person: he sits at the chair with his eyes lower (dz -18)
## looking across the table (the HTML game steps first person aside while seated; here you can look round).
## Jared's sit art (tyson too, in his colours) is a picture of him, so in first person you just see the room.
## Other characters (Gothica) stay as they are, put on the chair; the hit still runs, only without the art.

const TX := 165.0
const TY := 300.0
## Where the table's picture stands (the bottom of its rect), and the line the little pictures on it stand on.
const FEET_Y := 323.0
const U := 0.025
const SIT_T := {"heat": 0.25, "click": 2.1, "pull": 2.4, "blow": 3.8, "done": 5.9, "end": 6.2}
## Art px (x, y from the picture's top left) of the stem tip per sit frame, in world px (SIT_STEM, 3525).
const SIT_STEM: Array = [Vector2(29.25, 24), Vector2(29.75, 23.5), Vector2(29.5, 24.5), Vector2(28, 23.5)]
## The vape in the bong's stem (STEM_PIX 5110): one char is one art pixel.
const STEM_PIX: Array = [
	"...KKKKKK.", "...KHHHHK.", "...KLSSDK.", "...KLSSDK.", "...KLSSDK.", "KWWPKLSSDK",
	"KwwPKLSSDK", "...KEEEEK.", "...KWWWwK.", "...KWWWwK.", "...KWWwwK.", "...KKKKKK."]
const STEM_COL := {"K": "#1c1a22", "L": "#e6e8ec", "S": "#b4b8c0", "D": "#7a7e88", "E": "#5a5e68",
	"W": "#9a5a32", "w": "#6e3c1e", "P": "#c9ccd2"}
const SIT_FRAMES := ["sit_bong_0_hold", "sit_bong_1_torch", "sit_bong_2_pull", "sit_bong_3_blow"]
const SIT_W := 90.0
const SIT_H := 118.0

## Fired when a hit finishes (the player; counted for the trip only if it is the local player's).
signal hit_done(player: Node)
signal sat(player: Node, chair: int)
signal stood(player: Node, chair: int)

var cards: LobbyTableCards
var trip: LobbyTableTrip
## Who sits where: player -> {chair, bong (taken), vape (seconds into a hit, -1 none), pic, ...}.
var sitters: Dictionary = {}

## The BONG_HITS counter (5008): the row of hits and when the last one finished (seconds of game time).
var hit_row: int = 0
var hit_at: float = 0.0
## Seconds of play (game time, not the wall clock).
var clock: float = 0.0

var _bong_pic: LobbyPic
var _prop_tex: Dictionary = {}          # "<hide1><hide2>" -> Texture2D
var _prop_shown: String = ""
var _base_imgs: Dictionary = {}         # frame name -> Image
var _baked: Dictionary = {}             # cache key -> Texture2D
var _rng := RandomNumberGenerator.new()
var _world: Node
var _panel: Control
var _panel_btns: Array = []

func _ready() -> void:
	ll = get_parent() as LobbyLife
	reach = 150.0
	_rng.randomize()
	LobbyLife.ensure_action("table_deal", [KEY_B], [JOY_BUTTON_X])
	LobbyLife.ensure_action("table_hit", [KEY_H], [JOY_BUTTON_Y])
	LobbyLife.ensure_action("table_stand", [KEY_T], [JOY_BUTTON_B])
	global_position = GameData.world_to_3d(TX, TY, 0.0)
	_make_prop_variants()
	_bong_pic = LobbyPic.make(LobbyPic.art("table/bong_stem.png"), 0.5, 2.0)
	_bong_pic.name = "Bong"
	add_child(_bong_pic)
	# at (156, 281) the bong's middle, on the table: its bottom is 13 above that
	_bong_pic.global_position = GameData.world_to_3d(TX - 9.0, FEET_Y + 0.4, 0.0)
	_bong_pic.lift = FEET_Y - (281.0 + 13.0)
	cards = LobbyTableCards.new()
	cards.name = "Cards"
	cards.table = self
	add_child(cards)
	trip = LobbyTableTrip.new()
	trip.name = "Trip"
	trip.table = self
	add_child(trip)
	_build_panel()

# ------------------------------------------------------------------ geometry

## chairPos (3434): chair 1 left of the table, 2 right.
static func chair_pos(i: int) -> Vector2:
	return Vector2(TX + (-44.0 if i == 1 else 44.0), TY + 2.0)

## tableBox (3432): the solid lump of table and chairs (the World already has it as a solid).
static func box() -> Rect2:
	return Rect2(TX - 52.0, TY - 16.0, 104.0, 32.0)

## The seated player's side: +1 (chair 1 faces right) or -1.
static func dir_of(chair: int) -> float:
	return 1.0 if chair == 1 else -1.0

## chairNear (3435): 1, 2 or 0 (a free chair within 44 across and down of its seat).
func chair_near(p: Node3D) -> int:
	if p == null or not is_instance_valid(p) or bool(p.get_meta("carrying_goth", false)):
		return 0
	var o := ppos(p)
	for i in [1, 2]:
		if chair_taken(i, p):
			continue
		var c := chair_pos(i)
		if absf(o.x - c.x) < 44.0 and absf(o.y - c.y) < 44.0:
			return i
	return 0

func chair_taken(i: int, except: Node = null) -> bool:
	for q in sitters:
		if q != except and sitters[q].chair == i:
			return true
	return false

func sitter_at(chair: int) -> Node:
	for q in sitters:
		if sitters[q].chair == chair:
			return q
	return null

func is_seated(p: Node) -> bool:
	return sitters.has(p)

func chair_of(p: Node) -> int:
	return sitters[p].chair if sitters.has(p) else 0

func has_bong(p: Node) -> bool:
	return sitters.has(p) and sitters[p].bong

func hitting(p: Node) -> bool:
	return sitters.has(p) and sitters[p].vape >= 0.0

## bongHeld (5532): somebody has it in hand (so it is not on the table).
func bong_held() -> bool:
	for q in sitters:
		if sitters[q].bong:
			return true
	return false

# ------------------------------------------------------------------ E

func label_for(p: Node) -> String:
	if not can_start(p) or chair_near(p) == 0:
		return ""
	return "SIT"

func act(p: Node) -> void:
	var ch := chair_near(p)
	if ch > 0 and can_start(p):
		sit(p as Player, ch)

func busy_label(p: Player) -> String:
	if not sitters.has(p):
		return ""
	var s: Dictionary = sitters[p]
	if not s.bong:
		return "BONG"
	return "" if s.vape >= 0.0 else "HIT"

func busy_act(p: Player) -> void:
	if not sitters.has(p):
		return
	var s: Dictionary = sitters[p]
	if not s.bong:
		take_bong(p)
	elif s.vape < 0.0:
		start_hit(p)

func busy_input(p: Player, event: InputEvent) -> bool:
	if not sitters.has(p) or event.is_echo():
		return false
	if event.is_action_pressed("table_deal"):
		cards.act(p, "deal")
		return true
	if event.is_action_pressed("table_hit"):
		cards.act(p, "hit")
		return true
	if event.is_action_pressed("table_stand"):
		cards.act(p, "stand")
		return true
	return false

func busy_end(p: Player) -> void:
	if sitters.has(p):
		_drop(p)

func hides_sprite(p: Player) -> bool:
	return sitters.has(p) and sitters[p].pic != null

# ------------------------------------------------------------------ sitting

## Sit p in chair ch (sitDown 5473): on the seat point, facing the table.
func sit(p: Player, ch: int) -> void:
	if sitters.has(p) or chair_taken(ch):
		return
	ll.hold(p, self)
	var s := {"chair": ch, "bong": false, "vape": -1.0, "pic": null, "clicked": false, "coughed": false,
		"hiss": 0.0, "bub": 0.0, "frame": "", "t_idle": 0.0}
	sitters[p] = s
	p.facing = Vector2(dir_of(ch), 0.0)
	p.look_ang = 0.0 if ch == 1 else PI
	p.look_y = 0.1
	if LobbyLife.is_jared(p):
		var pic := LobbyPic.make(null, 0.5, 0.0)
		pic.name = "SitPic"
		pic.recolour_for = p.char_id if p.char_id != "juicy" else ""
		pic.flip = ch == 2
		pic.shift_x = 12.0 * dir_of(ch)
		pic.position = Vector3(0.0, 0.0, 18.0 * U)
		s.pic = pic
		ll.set_pose(p, pic)
		_set_frame(p, s)
	_place(p, s)
	cards.on_sit(p, ch)
	sat.emit(p, ch)

## Take him off the chair (stand up): outside the table's box so he doesn't stick in it.
func stand(p: Player) -> void:
	if not sitters.has(p):
		return
	var ch: int = sitters[p].chair
	_drop(p)
	ll.release(p)
	p.dz = 0.0
	p.place(98.0 if ch == 1 else 232.0, TY + 2.0)
	p.facing = Vector2(-dir_of(ch), 0.0)
	stood.emit(p, ch)

func _drop(p: Node) -> void:
	var ch: int = sitters[p].chair
	sitters.erase(p)
	cards.on_stand(p, ch)

func take_bong(p: Node) -> void:
	if sitters.has(p) and not sitters[p].bong:
		sitters[p].bong = true
		trip.prepare()

## Start a hit (p.vape = {t: 0}).
func start_hit(p: Node) -> void:
	if not sitters.has(p):
		return
	var s: Dictionary = sitters[p]
	if not s.bong:
		take_bong(p)
	if s.vape < 0.0:
		s.vape = 0.0
		s.clicked = false
		s.coughed = false

func _place(p: Player, s: Dictionary) -> void:
	var c := chair_pos(s.chair)
	put(p, c.x, c.y, -18.0 if p.is_first_person() else 0.0)
	p.facing = Vector2(dir_of(s.chair), 0.0)

## Standing up: the move keys or stick past 0.3, or the roll (Shift, RB, LT; pad B is "stand" at the cards).
func _wants_up(p: Player) -> bool:
	if p.read_steer().length() > 0.3:
		return true
	if Input.is_physical_key_pressed(KEY_SHIFT):
		return true
	if Input.is_action_pressed("roll") and not _pad_b():
		return true
	return false

func _pad_b() -> bool:
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_B):
			return true
	return false

func busy_step(p: Player, dt: float) -> void:
	if not sitters.has(p):
		return
	if _wants_up(p):
		stand(p)
		return
	var s: Dictionary = sitters[p]
	_place(p, s)
	_step_hit(p, s, minf(dt, 0.1))
	_set_frame(p, s)

# ------------------------------------------------------------------ the hit (drawSitArt 5136)

func _step_hit(p: Player, s: Dictionary, dt: float) -> void:
	if s.vape < 0.0:
		return
	var before: float = s.vape
	s.vape += dt
	var t: float = s.vape
	var d := dir_of(s.chair)
	var f := hit_frame(t)
	if before < SIT_T.click and t >= SIT_T.click and not s.clicked:
		s.clicked = true
		ll.sfx.tone(2400, 0.02, "square", 0.12, 2200)
		ll.sfx.tone(2600, 0.02, "square", 0.1, 2400, 0.07)
	if f == 1:
		s.hiss -= dt
		if s.hiss <= 0.0:
			s.hiss = 1.0 / 6.0
			ll.sfx.noise(0.18, 0.06, 0.9)
	if f == 2:
		if _rng.randf() < dt * 8.0:
			var at := art_spot(p, s, 29.2, -34.5)
			ll.smoke.puff(at.x, at.y, at.z, d * 3.0, 0.0, 12.0, 1.0, 4.0, 0.9, 0.45)
		s.bub -= dt
		if s.bub <= 0.0:
			s.bub = 1.0 / 9.0
			ll.sfx.tone(_rng.randf_range(180, 300), 0.05, "sine", 0.06, 120)
	if t >= SIT_T.blow and t < 5.2 and _rng.randf() < dt * 30.0:
		var k := 1.0 - (t - SIT_T.blow) / 1.4
		var m := art_spot(p, s, 21.0, -46.5)
		ll.smoke.puff(m.x + d * 2.0, m.y, m.z, d * (30.0 + _rng.randf() * 30.0) * (0.4 + k), 0.0,
			8.0 + _rng.randf() * 12.0, 1.5 + _rng.randf() * 1.5, 9.0 + _rng.randf() * 8.0, 2.0 + _rng.randf(), 0.7)
	if before < 5.4 and t >= 5.4 and not s.coughed:
		s.coughed = true
		if _rng.randf() < 0.35:
			var m2 := art_spot(p, s, 21.0, -46.5)
			ll.ui.float_text(m2.x, m2.y, m2.z + 18.0, "*cough*", Color("#e8e2d2"), 0.9, 15)
			ll.sfx.play("cough")
	if t >= SIT_T.end:
		s.vape = -1.0
		_bong_hit(p)

## drawSitArt's frame: 0 hold, 1 torch, 2 pull, 3 blow (the idle frame 0 before the heat).
static func hit_frame(t: float) -> int:
	if t < 0.0 or t < SIT_T.heat:
		return 0
	if t < SIT_T.pull:
		return 1
	if t < SIT_T.blow:
		return 2
	if t < SIT_T.done:
		return 3
	return 0

## The vape's heat (drawSitArt): rises while the torch burns, falls as he pulls and blows.
static func hit_heat(t: float) -> float:
	if t < 0.0 or t < SIT_T.heat:
		return 0.0
	if t < SIT_T.pull:
		return minf(1.0, (t - SIT_T.heat) / 1.6)
	return maxf(0.0, 1.0 - (t - SIT_T.pull) / 2.4)

## bongHit (5009): only the local player's own hit counts; two within 30 s (the second 3 s or more after the
## first) open the trip.
func _bong_hit(p: Node) -> void:
	hit_done.emit(p)
	if p != ll.player:
		return
	var now := clock
	if now - hit_at < 3.0 and hit_at > 0.0:
		return
	var seated := sitters.has(p)
	hit_row = hit_row + 1 if (seated and hit_at > 0.0 and now - hit_at < 30.0) else 1
	hit_at = now
	if hit_row >= 2 and not trip.active:
		hit_row = 0
		trip.start()

# ------------------------------------------------------------------ pictures

## Where a point of the sit art is, in HTML units (x, y on the ground, z up) such that the picture's pixel shows
## there in the current view: ox, oy are world px from the art's left edge and from its bottom (up is negative),
## as the HTML game's W(ox, oy).
func art_spot(p: Node3D, s: Dictionary, ox: float, oy: float) -> Vector3:
	var o := ppos(p)
	var d := dir_of(s.chair)
	return standing_spot(o.x + d * (ox - 10.5), o.y + 18.0, -oy)

## A point h up a picture that stands at (x, y): where it shows now (LobbyPic tips back to lie flat from above).
func standing_spot(x: float, y: float, h: float) -> Vector3:
	var base := GameData.world_to_3d(x, y, 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(x, y, h)
	var cb := cam.global_transform.basis.z
	var cu := cam.global_transform.basis.y
	var tip := smoothstep(0.55, 0.9, clampf(cb.y, 0.0, 1.0))
	var up := Vector3.UP.lerp(cu, tip).normalized()
	var w := base + up * (h * U)
	return GameData.from_3d(w)

func _art(n: String) -> Texture2D:
	return LobbyPic.art("table/%s.png" % n)

func _base_image(n: String) -> Image:
	if not _base_imgs.has(n):
		var tex := _art(n)
		var im: Image = tex.get_image() if tex else Image.create(90, 118, false, Image.FORMAT_RGBA8)
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		_base_imgs[n] = im
	return _base_imgs[n]

## The sit art picture now: idle (hands on his knees) or with the bong, the vape in its stem glowing.
func _set_frame(p: Player, s: Dictionary) -> void:
	var pic: LobbyPic = s.pic
	if pic == null:
		return
	if not s.bong:
		var n := "sit_idle_3_look" if fmod(clock, 9.0) > 7.6 else "sit_idle_0_relaxed"
		if s.frame != n:
			s.frame = n
			pic.texture = _art(n)
		return
	var t: float = maxf(s.vape, 0.0) if s.vape >= 0.0 else -1.0
	var f := hit_frame(t) if s.vape >= 0.0 else 0
	var heat := hit_heat(t) if s.vape >= 0.0 else 0.0
	var flame := 0
	if f == 1:
		var a := 0.35 + 0.3 * sin(clock * 47.0) * sin(clock * 13.0)
		flame = 1 if a > 0.5 else 0
	var cap := 0 if heat <= 0.0 else (1 if heat < 0.35 else (2 if heat < 0.7 else 3))
	var glow := int(round(heat * 5.0)) if heat > 0.35 else 0
	var key := "%d|%d|%d|%d" % [f, cap, glow, flame]
	if s.frame == key:
		return
	s.frame = key
	pic.texture = _bake(key, f, cap, glow, flame)

func _bake(key: String, f: int, cap: int, glow: int, flame: int) -> Texture2D:
	if _baked.has(key):
		return _baked[key]
	var im: Image = _base_image(SIT_FRAMES[f]).duplicate()
	var tip: Vector2 = SIT_STEM[f]
	var x0 := int(floor(tip.x * 2.0 - 6.0 + 0.5))
	var y0 := int(floor(tip.y * 2.0 - 1.5 + 0.5))
	var caps := ["#d7d9de", "#e8a07a", "#ff6a2a", "#ff3a1e"]
	if glow > 0:
		_blend(im, Rect2i(x0 + 2, y0 - 1, 6, 4), Color("#ff8a2a"), 0.3 * glow / 5.0)
	for r in STEM_PIX.size():
		var row: String = STEM_PIX[r]
		for c in row.length():
			var ch := row[c]
			if ch == ".":
				continue
			var col := Color(caps[cap]) if ch == "H" else Color(STEM_COL[ch])
			var x := x0 + c - r / 4
			var y := y0 + r
			if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
				im.set_pixel(x, y, col)
	if flame > 0:
		var fc := Vector2(33.3 * 2.0, SIT_H - 39.0 * 2.0)
		for y in range(int(fc.y) - 5, int(fc.y) + 6):
			for x in range(int(fc.x) - 5, int(fc.x) + 6):
				if Vector2(x + 0.5, y + 0.5).distance_to(fc) <= 4.4 and x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
					im.set_pixel(x, y, Color("#9fe8ff"))
	if _baked.size() > 80:
		_baked.clear()
	var tex := ImageTexture.create_from_image(im)
	_baked[key] = tex
	return tex

static func _blend(im: Image, r: Rect2i, col: Color, a: float) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height():
				continue
			var o := im.get_pixel(x, y)
			if o.a > 0.0:
				im.set_pixel(x, y, Color(lerpf(o.r, col.r, a), lerpf(o.g, col.g, a), lerpf(o.b, col.b, a), o.a))

## The World's table picture, four ways: with both chairs, or without the one a seated Jared brings his own stool for.
func _make_prop_variants() -> void:
	var tex := LobbyPic.art("table/prop_nobong.png")
	if tex == null:
		return
	var im: Image = tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	for h1 in [false, true]:
		for h2 in [false, true]:
			var v: Image = im.duplicate()
			if h1:
				v.fill_rect(Rect2i(0, 0, 48, v.get_height()), Color(0, 0, 0, 0))
			if h2:
				v.fill_rect(Rect2i(176, 0, 48, v.get_height()), Color(0, 0, 0, 0))
			_prop_tex["%d%d" % [int(h1), int(h2)]] = ImageTexture.create_from_image(v)

func _find_prop() -> MeshInstance3D:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world_builder")
	if _world == null:
		return null
	var pr = _world.get("props")
	if pr is Dictionary:
		return pr.get("table", null)
	return null

func _process(dt: float) -> void:
	clock += dt
	# the table's picture: the chair a seated Jared brings his own stool for isn't drawn, and the bong is only
	# on the table while nobody holds it
	var h := [false, false]
	for q in sitters:
		if sitters[q].pic != null:
			h[sitters[q].chair - 1] = true
	var key := "%d%d" % [int(h[0]), int(h[1])]
	if key != _prop_shown and _prop_tex.has(key):
		var mi := _find_prop()
		if mi and mi.material_override is ShaderMaterial:
			(mi.material_override as ShaderMaterial).set_shader_parameter("tex", _prop_tex[key])
			_prop_shown = key
	if _bong_pic:
		_bong_pic.visible = not bong_held()
	_update_panel()

# ------------------------------------------------------------------ the sit panel (sitMenu 5434)

func _build_panel() -> void:
	if ll == null or ll.ui == null:
		return
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.9)
	sb.border_color = LobbyUI.PINK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.offset_right = -66
	pc.offset_top = 52
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pc.add_child(box)
	var title := Label.new()
	title.text = "Take a seat. What'll it be?"
	title.add_theme_font_size_override("font_size", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var b1 := _btn("BONG (E)", Color("#3a2150"), 150, func(): _panel_bong())
	var b2 := _btn("CALL GOTHICA (B)", Color("#1f5a36"), 190, func(): _panel_call())
	row.add_child(b1)
	row.add_child(b2)
	_panel_btns = [b1, b2]
	pc.visible = false
	ll.ui.root.add_child(pc)
	_panel = pc

static func _btn(text: String, col: Color, w: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 38)
	b.add_theme_font_size_override("font_size", 16)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.15) if st == "hover" or st == "pressed" else col
		sb.border_color = LobbyUI.PINK
		sb.set_border_width_all(2 if st != "focus" else 3)
		sb.set_corner_radius_all(7)
		b.add_theme_stylebox_override(st, sb)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _panel_bong() -> void:
	if ll.player and sitters.has(ll.player):
		take_bong(ll.player)

func _panel_call() -> void:
	if ll.player and sitters.has(ll.player):
		cards.act(ll.player, "call")

func _update_panel() -> void:
	if _panel == null:
		return
	var p := ll.player
	_panel.visible = p != null and sitters.has(p) and not sitters[p].bong and not cards.active() and not trip.active

# ------------------------------------------------------------------ test scene

## ?lobby=table[,fp][,bong][,trip][,mantis,secs][,cards]: sit him down (top-down or first person) and, for bong, take the bong and
## hit; for trip, two hits in a row; for cards, call Gothica and deal.
func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(98.0, 302.0, Vector2(1, 0))
	tl.later(0.5, func(): tl.use())
	if parts.has("cards"):
		tl.later(1.0, func(): cards.act(ll.player, "call"))
		tl.later(9.0, func(): cards.act(ll.player, "deal"))
	elif parts.has("mantis"):
		# straight into the trip, some way in (the third part is the seconds in: ?lobby=table,mantis,8)
		var at := 7.0
		for q in parts:
			if q.is_valid_float():
				at = float(q)
		tl.later(1.0, func():
			trip.start()
			trip.t = at)
	elif parts.has("trip"):
		tl.later(1.0, func(): tl.use())
		tl.later(1.4, func(): tl.use())
		tl.later(7.8, func(): tl.use())
	elif parts.has("bong"):
		tl.later(1.0, func(): tl.use())
		tl.later(1.4, func(): tl.use())
