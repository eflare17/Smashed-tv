class_name LobbyRope
extends LobbyThing
## The bell rope in the gym and the potato rain (specs/gym.md section 6, Smashed.html ropeNear 9996, pullRope 9997,
## stepRain 10007, drawRope 10047, drawRain 10069, stepPlants 6000). Owned by the Lobby life session.
##
## PULL next to the rope (x 319..371, y 148..192) when it is ready: the bell rings and ropeCount (10) potatoes fall
## on the gym floor (x 318..580, y 126..234) one after another, bounce and settle; then the rope is cooling for
## ropeCool (20) seconds (dark). A settled potato is a pickup: walk within 28 of it and it is yours (+10 ammo, up to
## 200), kept on the player's meta "spud_ammo" until weapons exist. The rope is drawn procedurally like the HTML game
## (a swaying curve that dips when pulled, a knot) as a picture standing where the World's static rope stands, which
## is hidden. Falling potatoes are billboards with a shadow on the floor; settled ones stand on the floor.
##
## signal picked(player, ammo): a potato picked up.

signal pulled
signal picked(player: Node, ammo: int)

const ROPE_X := 345.0
const ROPE_Y := 152.0
const WALL := 18.0
const COUNT := 10
const COOL := 20.0
const SPUD_PELLETS := 10
const SPUD_MAX := 200
const SPUD_W := 30.0
const TEX_W := 80          # the rope picture, art pixels (2 per unit)
const TEX_H := 304
const TOP := 16.0           # world y of its top row (the World's rope prop rect starts here)

var cool: float = 0.0
var pull_t: float = 0.0
var rain: Array = []
## Landed potatoes lying about, ready to pick up: {x, y, spr (LobbyPic), t}.
var spuds: Array = []
var clock: float = 0.0

var _rng := RandomNumberGenerator.new()
var _world: Node
var _hid: bool = false
var _img: Image
var _tex: ImageTexture
var _pic: LobbyPic
var _spud_tex: Texture2D
var _shadow_tex: Texture2D
var _thud_gate: float = 0.0
var _solids: Array = []

func _ready() -> void:
	ll = get_parent() as LobbyLife
	_rng.randomize()
	global_position = GameData.world_to_3d(ROPE_X, 170.0, 0.0)
	reach = 60.0
	_spud_tex = GameData.tex("assets/SPUD_SPRITES_4.png")
	_img = Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_pic = LobbyPic.make(_tex, 0.5, 0.0)
	_pic.name = "Rope"
	ll.add_child.call_deferred(_pic)
	_pic.set_deferred("global_position", GameData.world_to_3d(ROPE_X, 168.0, 0.0))
	var sb = LobbyLife.calls("lobbySolidBoxes", [])
	if sb is Array:
		_solids = sb
	_make_shadow()

# ------------------------------------------------------------------ E

## ropeNear: x 319..371, y 148..192.
func rope_near(p: Node3D) -> bool:
	if p == null or not is_instance_valid(p) or bool(p.get_meta("carrying_goth", false)):
		return false
	var o := ppos(p)
	return absf(o.x - ROPE_X) < 26.0 and o.y > ROPE_Y - 4.0 and o.y < ROPE_Y + 40.0

func label_for(p: Node) -> String:
	return "PULL" if can_start(p) and cool <= 0.0 and rope_near(p) else ""

func act(p: Node) -> void:
	if can_start(p) and cool <= 0.0 and rope_near(p):
		pull()

## pullRope (9997): the bell, ten potatoes with their delays, the rope cools.
func pull() -> void:
	cool = COOL
	pull_t = 0.45
	for i in COUNT:
		rain.append({"x": 318.0 + _rng.randf() * 262.0, "y": 126.0 + _rng.randf() * 108.0, "dz": 380.0 + _rng.randf() * 160.0,
			"vz": 0.0, "vx": 0.0, "vy": 0.0, "squash": 0.0, "delay": 0.35 + i * 0.12 + _rng.randf() * 0.08,
			"bounces": 0, "rot": _rng.randf() * 6.28, "spin": (_rng.randf() - 0.5) * 10.0, "spr": null, "sh": null})
	ll.ui.float_text(ROPE_X, ROPE_Y, 30.0, "POTATOES!", Color("#d8b878"), 1.0, 18)
	ll.sfx.tone(1320, 0.5, "sine", 0.22, 1240)
	ll.sfx.tone(880, 0.7, "triangle", 0.18, 840)
	pulled.emit()

# ------------------------------------------------------------------ every frame

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	clock += dt
	_hide_world_prop()
	cool = maxf(0.0, cool - dt)
	pull_t = maxf(0.0, pull_t - dt)
	_step_rain(dt)
	_pickups()
	_draw_rope()

func _hide_world_prop() -> void:
	if _hid:
		return
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world_builder")
	if _world == null:
		return
	var pr = _world.get("props")
	if pr is Dictionary and pr.has("rope"):
		pr["rope"].visible = false
		_hid = true

## stepRain (10007).
func _step_rain(dt: float) -> void:
	var loudest := 0.0
	for r in rain.duplicate():
		if r.delay > 0.0:
			r.delay -= dt
			continue
		r.squash = maxf(0.0, r.squash - 9.0 * dt)
		r.vz -= 1500.0 * dt
		r.dz += r.vz * dt
		r.x += r.vx * dt
		r.y += r.vy * dt
		r.rot += r.spin * dt
		if r.dz <= 0.0:
			r.dz = 0.0
			var hit: float = -r.vz
			var keep: float = [0.45, 0.36, 0.28][mini(2, r.bounces)]
			r.bounces += 1
			if hit > 110.0 and r.bounces <= 3:
				r.vz = hit * keep
				var kick := hit * 0.08
				r.vx = r.vx * 0.6 + (_rng.randf() - 0.5) * kick
				r.vy = r.vy * 0.6 + (_rng.randf() - 0.5) * kick
				r.spin *= 0.55
				r.squash = 1.0
				if hit > 300.0:
					ll.smoke.puff(r.x, r.y + 4.0, 0.0, 0.0, 0.0, 6.0, 2.0, 6.0, 0.5, 0.5, Color("#b9a58a"))
				loudest = maxf(loudest, hit)
			else:
				_settle(r)
				continue
		_draw_potato(r)
	_thud_gate -= dt
	if loudest > 0.0 and _thud_gate <= 0.0:
		_thud_gate = 0.05
		ll.sfx.noise(0.05, minf(0.22, 0.06 + loudest / 3000.0), 0.12)

## A potato that stops: pushed out of the furniture, and now a ready potato on the floor (a plant at t = spudGrow).
func _settle(r: Dictionary) -> void:
	if r.spr and is_instance_valid(r.spr):
		r.spr.queue_free()
	if r.sh and is_instance_valid(r.sh):
		r.sh.queue_free()
	rain.erase(r)
	var pos := Vector2(clampf(r.x, WALL + 12.0, 860.0 - (WALL + 12.0)), clampf(r.y, WALL + 12.0, 520.0 - (WALL + 12.0)))
	if _in_pool(pos):
		ll.sfx.play("splash")
		return
	for b in _solids:
		pos = Trampoline.push_out_of_solid(pos, 10.0, b)
	add_spud(pos.x, pos.y)

func _in_pool(pos: Vector2) -> bool:
	var pl = LobbyLife.D("POOL", {})
	return pl is Dictionary and pl.has("x0") and pos.x > pl.x0 and pos.x < pl.x1 and pos.y > pl.y0 and pos.y < pl.y1

## A ready potato lying at (x, y).
func add_spud(x: float, y: float) -> void:
	var pic := LobbyPic.make(_spud_tex, SPUD_W / maxf(1.0, _spud_tex.get_width()), 0.0)
	ll.add_child(pic)
	pic.global_position = GameData.world_to_3d(x, y + 8.0, 0.0)
	var sh := _shadow(13.0, 5.0, 0.28)
	ll.add_child(sh)
	sh.global_position = GameData.world_to_3d(x, y + 6.0, 0.15)
	spuds.append({"x": x, "y": y, "spr": pic, "sh": sh, "t": _rng.randf() * 6.0})

func _draw_potato(r: Dictionary) -> void:
	if r.spr == null:
		var s := Sprite3D.new()
		s.texture = _spud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.pixel_size = SPUD_W / maxf(1.0, _spud_tex.get_width()) * GameData.UNIT
		ll.add_child(s)
		r.spr = s
		var sh := _shadow(13.0, 5.0, 0.28)
		ll.add_child(sh)
		r.sh = sh
	var spr: Sprite3D = r.spr
	# at (x, y - dz) on the HTML screen: up in the air by dz, centred
	spr.global_position = GameData.world_to_3d(r.x, r.y + 2.0, r.dz + 10.0)
	spr.scale = Vector3(1.0 + 0.3 * r.squash, 1.0 - 0.3 * r.squash, 1.0)
	var sf := maxf(0.3, 1.0 - r.dz / 300.0)
	var shd: Sprite3D = r.sh
	shd.global_position = GameData.world_to_3d(r.x, r.y + 6.0, 0.15)
	shd.pixel_size = 26.0 * sf / 32.0 * GameData.UNIT
	shd.modulate = Color(0, 0, 0, 0.28 * sf)

## stepPlants: a ready potato within radius + 14 of him is his, if he has room.
func _pickups() -> void:
	var p := ll.player
	if p == null:
		return
	var o := ppos(p)
	var reach_d := LobbyLife.T("radius", 14.0) + 14.0
	for s in spuds.duplicate():
		s.t += get_process_delta_time()
		var g := 0.5 + 0.5 * sin(5.0 * clock + s.x)
		# the glint the HTML game flashes over a ready potato: a gentle pulse
		s.spr.modulate = Color(1.0 + 0.12 * g, 1.0 + 0.1 * g, 1.0 + 0.05 * g)
		if Vector2(o.x, o.y).distance_to(Vector2(s.x, s.y)) < reach_d and ammo(p) < SPUD_MAX:
			var a := mini(SPUD_MAX, ammo(p) + SPUD_PELLETS)
			p.set_meta("spud_ammo", a)
			s.spr.queue_free()
			s.sh.queue_free()
			spuds.erase(s)
			ll.sfx.noise(0.12, 0.3, 0.2)
			ll.sfx.tone(220, 0.08, "triangle", 0.14, 160)
			picked.emit(p, a)

static func ammo(p: Node) -> int:
	return int(p.get_meta("spud_ammo", 0))

# ------------------------------------------------------------------ the rope's picture (drawRope 10047)

func _draw_rope() -> void:
	var ready := cool <= 0.0
	var sway := sin(clock * 1.6) * 3.0
	var bot := ROPE_Y + (sin(pull_t / 0.45 * PI) * 14.0 if pull_t > 0.0 else 0.0)
	_img.fill(Color(0, 0, 0, 0))
	var c0 := Vector2(ROPE_X, WALL)
	var c1 := Vector2(ROPE_X + sway * 0.5, (WALL + bot) / 2.0)
	var c2 := Vector2(ROPE_X + sway, bot)
	var rope_col := Color("#b08a52") if ready else Color("#6e5a3c")
	var hi_col := Color("#e2bd82") if ready else Color("#8a7454")
	var steps := 90
	for i in steps + 1:
		var u := float(i) / steps
		var pt := c0.lerp(c1, u).lerp(c1.lerp(c2, u), u)
		_stamp(pt, 2.0, rope_col)
	for i in steps + 1:
		var u := float(i) / steps
		var pt := c0.lerp(c1, u).lerp(c1.lerp(c2, u), u)
		_stamp(pt + Vector2(-1.0, 0.0), 0.75, hi_col)
	# the knot: an ellipse 6 x 9 with a thin dark outline
	var kc := Vector2(ROPE_X + sway, bot + 6.0)
	_ellipse(kc, 7.0, 10.0, Color(0, 0, 0, 0.35))
	_ellipse(kc, 6.0, 9.0, Color("#8a5a2b") if ready else Color("#5c4530"))
	_tex.update(_img)

## A filled disc of radius r (world units) at a world point, into the picture (2 pixels a unit).
func _stamp(w: Vector2, r: float, col: Color) -> void:
	_ellipse(w, r, r, col)

func _ellipse(w: Vector2, rx: float, ry: float, col: Color) -> void:
	var cx := (w.x - (ROPE_X - TEX_W / 4.0)) * 2.0
	var cy := (w.y - TOP) * 2.0
	for y in range(int(floor(cy - ry * 2.0)), int(ceil(cy + ry * 2.0)) + 1):
		for x in range(int(floor(cx - rx * 2.0)), int(ceil(cx + rx * 2.0)) + 1):
			if x < 0 or y < 0 or x >= TEX_W or y >= TEX_H:
				continue
			var dx := (x + 0.5 - cx) / (rx * 2.0)
			var dy := (y + 0.5 - cy) / (ry * 2.0)
			if dx * dx + dy * dy <= 1.0:
				_img.set_pixel(x, y, col)

# ------------------------------------------------------------------ shadows

func _make_shadow() -> void:
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x + 0.5 - 16, y + 0.5 - 16).length() / 16.0
			im.set_pixel(x, y, Color(1, 1, 1, 1.0 if d <= 1.0 else 0.0))
	_shadow_tex = ImageTexture.create_from_image(im)

## A flat dark ellipse on the floor (rx, ry in units).
func _shadow(rx: float, ry: float, a: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _shadow_tex
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.modulate = Color(0, 0, 0, a)
	s.transparent = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.pixel_size = rx * 2.0 / 32.0 * GameData.UNIT
	s.scale = Vector3(1.0, ry / rx, 1.0)
	return s

# ------------------------------------------------------------------ test scene

## ?lobby=rope[,fp]: stand at the rope and pull it.
func test_scene(tl: Node, _parts: PackedStringArray) -> void:
	tl.go(350.0, 175.0, Vector2(0, -1))
	tl.later(0.6, func(): tl.use())
