class_name LobbySlot
extends LobbyThing
## The slot machine (Smashed.html: PRIZES @624, pickPrize @6271, award @6278, the pull in stepPlayers @7275, the
## cabinet and reels @12052, drawSym @11862). Owned by the Lobby life session.
##
## It stands at calls.slot (90, 110) against the lounge's top wall, 124 units tall (SLOT_SPRITES art, 89 x 128 px
## at 0.97). Next to it with $5 (T.spinCost) E ("SPIN $5") puts the money in and roots him for T.spinTime 1.6 s while
## the three reels turn and stop one after another (at 0.45, 0.70 and 1.0 of the spin); then the prize (weights
## 3 3 3 2 1 2 2 2): the machine flashes and shows its symbol on all three reels, a banner names it, and it
## recharges for T.spinCool 8 s.
##
## What each prize does here: JACKPOT bursts 18 notes ($1 each, picked up by walking over them); CASH MAGNET (14 s)
## pulls notes in from afar; SPEED BOOST (T.speedTime 10 s, x T.speedMul on T.maxSpeed); +2 HEALTH raises player.hp
## if he has one (up to T.playerHp + T.overheal). The ones that need a fight (REAL GUNS, SHOTGUN, SCREEN CLEAR,
## BUST) are announced and handed on: signal prize(player, kind) with the HTML game's PRIZES keys, and the player's
## meta "slot_prize" holds the last kind.
##
## Port decisions: E starts a spin (the HTML game starts it when you stand still near the machine, which a pad or
## a touch player can't plan); the speed boost counts down in the lobby (the HTML game's only ticks in a run, so
## in the lobby it would last for ever); no sound of its own, like the HTML game, but the notes chime.

signal prize(player: Node, kind: String)

const SLOT := Vector2(90.0, 110.0)
const SCALE := 124.2 / 128.0
const PRIZES := [
	{"key": "blasters", "label": "REAL GUNS!", "w": 3, "sym": 1},
	{"key": "shotgun", "label": "SHOTGUN!", "w": 3, "sym": 1},
	{"key": "health", "label": "+2 HEALTH", "w": 3, "sym": 0},
	{"key": "speed", "label": "SPEED BOOST", "w": 2, "sym": 3},
	{"key": "clear", "label": "SCREEN CLEAR", "w": 1, "sym": 4},
	{"key": "cash", "label": "JACKPOT!", "w": 2, "sym": 2},
	{"key": "magnet", "label": "CASH MAGNET!", "w": 2, "sym": 2},
	{"key": "bust", "label": "BUST!", "w": 2, "sym": 5},
]
const STOPS := [0.45, 0.70, 1.0]

var cool: float = 0.0
var flash: float = 0.0
var spin_t: float = 0.0                  # seconds of spin left (> 0 while turning)
var the_prize: Dictionary = {}
var decoy: Array = [0, 0]
var spinner: Player
var speed_t: float = 0.0
var magnet_t: float = 0.0
var notes: Array = []                    # {spr, x, y, z, vx, vy, vz, arm, life}
var rng := RandomNumberGenerator.new()

var _pic: LobbyPic
var _tex: ImageTexture
var _imgs: Dictionary = {}
var _syms: Array = []
var _t: float = 0.0
var _base_speed: float = -1.0
var _coin_tex: Texture2D

func _ready() -> void:
	reach = 70.0
	rng.randomize()
	var s = LobbyLife.calls("slot", {"x": 90, "y": 110})
	global_position = GameData.world_to_3d(float(s.x), float(s.y), 0.0)
	for k in ["idle_a", "idle_b", "spin", "win"]:
		_imgs[k] = _load("machines/slot_%s.png" % k)
	for i in 6:
		_syms.append(_make_sym(i))
	await get_tree().process_frame
	_tex = ImageTexture.create_from_image(_imgs["idle_a"])
	_pic = LobbyPic.make(_tex, SCALE, 0.0)
	_pic.top_level = true
	add_child(_pic)
	_pic.global_position = GameData.world_to_3d(SLOT.x, SLOT.y + 6.0, 0.0)
	var w = ll.world if ll else null
	if w and w.get("props") is Dictionary:
		var m = w.props.get("slot")
		if m is Node3D:
			m.visible = false

func _load(rel: String) -> Image:
	var t := LobbyPic.art(rel)
	var im := t.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	return im

# ------------------------------------------------------------------ E

func near(p: Node) -> bool:
	return ppos(p).distance_to(SLOT) < LobbyLife.T("slotRadius", 46.0) + 10.0

func label_for(p: Node) -> String:
	if not can_start(p) or not near(p):
		return ""
	var cost := int(LobbyLife.T("spinCost", 5))
	if cool > 0.0:
		return "WAIT %ds" % int(ceil(cool))
	if ll.cash(p) < cost:
		return "NEED $%d" % cost
	return "SPIN $%d" % cost

func act(p: Node) -> void:
	var cost := int(LobbyLife.T("spinCost", 5))
	if not can_start(p) or not near(p) or cool > 0.0 or spin_t > 0.0 or not ll.pay(p, cost):
		return
	start_spin(p as Player)

## pickPrize: a weighted pick.
func pick_prize() -> Dictionary:
	var total := 0
	for pr in PRIZES:
		total += int(pr.w)
	var r := rng.randi_range(0, total - 1)
	for pr in PRIZES:
		r -= int(pr.w)
		if r < 0:
			return pr
	return PRIZES[0]

func start_spin(p: Player, forced: String = "") -> void:
	spinner = p
	spin_t = LobbyLife.T("spinTime", 1.6)
	the_prize = pick_prize()
	if forced != "":
		for pr in PRIZES:
			if pr.key == forced:
				the_prize = pr
	decoy = [rng.randi_range(0, 5), rng.randi_range(0, 5)]
	ll.hold(p, self)
	p.facing = Vector2(0, -1)

func busy_label(_p: Player) -> String:
	return "SPINNING"

func busy_step(p: Player, dt: float) -> void:
	p.halt()
	spin_t -= dt
	if spin_t <= 0.0:
		spin_t = 0.0
		cool = LobbyLife.T("spinCool", 8.0)
		spinner = null
		ll.release(p)
		award(p, the_prize)

func busy_end(_p: Player) -> void:
	spin_t = 0.0
	spinner = null

# ------------------------------------------------------------------ the prize

## award: the banner, the flash, and the effect.
func award(p: Player, pr: Dictionary) -> void:
	flash = 1.0
	ll.ui.info(String(pr.label), 1.6)
	p.set_meta("slot_prize", pr.key)
	match String(pr.key):
		"health":
			var hp = p.get("hp")
			if hp != null:
				p.set("hp", mini(int(LobbyLife.T("playerHp", 5)) + int(LobbyLife.T("overheal", 6)), int(hp) + 2))
		"speed":
			if _base_speed < 0.0:
				_base_speed = LobbyLife.T("maxSpeed", 260.0)
			speed_t = LobbyLife.T("speedTime", 10.0)
			GameData.data["T"]["maxSpeed"] = _base_speed * LobbyLife.T("speedMul", 1.55)
		"cash":
			burst(18)
		"magnet":
			magnet_t = LobbyLife.T("magnetTime", 14.0)
	if ll.sfx:
		ll.sfx.play("win" if String(pr.key) != "bust" else "lose")
	prize.emit(p, String(pr.key))

# ------------------------------------------------------------------ the notes

func _note_tex() -> Texture2D:
	if _coin_tex == null:
		var im := Image.create(10, 6, false, Image.FORMAT_RGBA8)
		im.fill(Color("#2f7a45"))
		im.fill_rect(Rect2i(0, 0, 10, 1), Color("#7fd89a"))
		im.fill_rect(Rect2i(3, 1, 4, 4), Color("#d8f0d8"))
		_coin_tex = ImageTexture.create_from_image(im)
	return _coin_tex

## The jackpot: n notes burst from the machine (angles round, speed 420..760, arm 0.85 s).
func burst(n: int) -> void:
	for i in n:
		var a := float(i) / n * TAU + rng.randf() * 0.3
		var sp := rng.randf_range(420.0, 760.0)
		add_note(SLOT.x, SLOT.y + 20.0, 60.0, cos(a) * sp, sin(a) * sp, rng.randf_range(160.0, 320.0), 0.85, 10.0)

func add_note(x: float, y: float, z: float, vx: float, vy: float, vz: float, arm: float, life: float) -> void:
	var s := Sprite3D.new()
	s.texture = _note_tex()
	s.pixel_size = 1.6 * GameData.UNIT
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.top_level = true
	add_child(s)
	notes.append({"spr": s, "x": x, "y": y, "z": z, "vx": vx, "vy": vy, "vz": vz, "arm": arm, "life": life})

func _step_notes(dt: float) -> void:
	var p := ll.player
	var pp := ppos(p)
	var grab := LobbyLife.T("coinGrab", 34.0)
	var reach_m := LobbyLife.T("coinMagnet", 95.0)
	if magnet_t > 0.0:
		reach_m = maxf(reach_m, LobbyLife.T("magnetRange", 460.0))
	for n in notes.duplicate():
		n.life -= dt
		n.arm = maxf(0.0, n.arm - dt)
		if n.life <= 0.0:
			n.spr.queue_free()
			notes.erase(n)
			continue
		var drag := pow(0.02, dt)
		n.vx *= drag
		n.vy *= drag
		n.x += n.vx * dt
		n.y += n.vy * dt
		n.vz -= 900.0 * dt
		n.z += n.vz * dt
		if n.z <= 2.0:
			n.z = 2.0
			n.vz = absf(n.vz) * 0.35 if absf(n.vz) > 60.0 else 0.0
		var d := Vector2(n.x, n.y).distance_to(pp)
		if n.arm <= 0.0:
			if d < reach_m:
				var boost := 2.4 if magnet_t > 0.0 else 1.0
				var pull := LobbyLife.T("coinPull", 900.0) * boost * (1.0 - d / reach_m) * dt
				var dir := (pp - Vector2(n.x, n.y)).normalized()
				n.x += dir.x * pull
				n.y += dir.y * pull
				n.life = maxf(n.life, 1.5 if magnet_t > 0.0 else 0.6)
			if d < grab:
				n.spr.queue_free()
				notes.erase(n)
				ll.add_cash(p, 1)
				ll.sfx.play("coin")
				ll.ui.float_text(pp.x, pp.y, 70.0, "$1", Color("#7fd89a"), 0.9, 14)
				continue
		n.spr.visible = n.life > 2.0 or int(n.life * 8.0) % 2 == 0
		n.spr.global_position = GameData.world_to_3d(n.x, n.y, n.z + 3.0)

# ------------------------------------------------------------------ every frame

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	_t += dt
	cool = maxf(0.0, cool - dt)
	flash = maxf(0.0, flash - dt)
	if speed_t > 0.0:
		speed_t -= dt
		if speed_t <= 0.0 and _base_speed > 0.0:
			GameData.data["T"]["maxSpeed"] = _base_speed
			_base_speed = -1.0
	magnet_t = maxf(0.0, magnet_t - dt)
	if ll and ll.player:
		_step_notes(dt)
	_draw_cabinet()

func _draw_cabinet() -> void:
	if _tex == null:
		return
	var spinning := spin_t > 0.0
	var key := "win" if flash > 0.001 else ("spin" if spinning else ("idle_b" if int(_t * 3.0) % 2 == 1 else "idle_a"))
	var im: Image = _imgs[key].duplicate()
	if spinning or flash > 0.001:
		_reels(im, spinning)
	_tex.set_image(im)
	_pic.modulate = Color(0.72, 0.72, 0.72) if (cool > 0.0 and not spinning and flash <= 0.001) else Color.WHITE

## The live reels over the cabinet's window (L12090-12153), in the picture's pixels.
func _reels(im: Image, spinning: bool) -> void:
	var rw := int(round(86.4 * 0.16 * 1.9 / SCALE))
	var rh := int(round(124.2 * 0.115 * 1.9 / SCALE))
	var cy := int(round(128.0 * 0.503))
	var cols := [25, 47, 68]
	var pad_x := int(round(rw * 0.22))
	var pad_y := int(round(rh * 0.3))
	var x0: int = cols[0] - rw / 2 - pad_x
	var x1: int = cols[2] + rw / 2 + pad_x
	var y0 := cy - rh / 2 - pad_y
	var y1 := cy + rh / 2 + pad_y
	var edge := Color("#f6d17a") if flash > 0.001 else Color("#4b5468")
	im.fill_rect(Rect2i(x0 - 2, y0 - 2, x1 - x0 + 4, y1 - y0 + 4), edge)
	im.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), Color(12 / 255.0, 13 / 255.0, 18 / 255.0, 1.0))
	var frac := 1.0 - spin_t / LobbyLife.T("spinTime", 1.6) if spinning else 1.0
	for i in 3:
		var win := Image.create(rw, rh, false, Image.FORMAT_RGBA8)
		win.fill(Color("#f2efe6"))
		var stopped := frac >= float(STOPS[i]) or not spinning
		if stopped:
			var sym: int = int(the_prize.get("sym", 0)) if (i == 2 or flash > 0.001) else int(decoy[i] if i < 2 else 0)
			var sm: Image = _syms[sym]
			win.blend_rect(sm, Rect2i(0, 0, 20, 20), Vector2i((rw - 20) / 2, (rh - 20) / 2))
		else:
			var off := int(fmod(_t * 420.0 / 0.97, float(rh)))
			for k in range(-1, 3):
				var sym := (k + 1 + i * 2 + int(_t * 9.0)) % 6
				var yy := (rh - 20) / 2 + k * rh - off + rh
				win.blend_rect(_syms[sym], Rect2i(0, 0, 20, 20), Vector2i((rw - 20) / 2, yy))
			var haze := Image.create(rw, rh, false, Image.FORMAT_RGBA8)
			haze.fill(Color(0.949, 0.937, 0.902, 0.55))
			win.blend_rect(haze, Rect2i(0, 0, rw, rh), Vector2i.ZERO)
		im.blit_rect(win, Rect2i(0, 0, rw, rh), Vector2i(cols[i] - rw / 2, cy - rh / 2))

## drawSym: a 20 x 20 picture of symbol i (0 heart, 1 shotgun, 2 coin, 3 bolt, 4 star, 5 skull).
func _make_sym(i: int) -> Image:
	var im := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	for y in 20:
		for x in 20:
			var c := Color(0, 0, 0, 0)
			var p := Vector2(x + 0.5, y + 0.5)
			match i:
				0:
					if p.distance_to(Vector2(6.5, 7.5)) < 5.0 or p.distance_to(Vector2(13.5, 7.5)) < 5.0 or (y >= 8 and y < 18 and absf(p.x - 10.0) < (18.5 - y) * 0.98):
						c = Color("#e0473f")
				1:
					if x >= 1 and x < 15 and y >= 7 and y < 12:
						c = Color("#4a5260")
					elif x >= 13 and x < 19 and y >= 6 and y < 14:
						c = Color("#8a5a33")
				2:
					var d := p.distance_to(Vector2(10, 10))
					if d < 7.2:
						c = Color("#f6d17a") if d < 4.8 else Color("#d9a520")
				3:
					if _in_poly(p, [Vector2(11, 1), Vector2(4, 11), Vector2(9, 11), Vector2(7, 19), Vector2(16, 8), Vector2(11, 8)]):
						c = Color("#6fd3a0")
				4:
					var pts: Array = []
					for k in 10:
						var a := -PI / 2.0 + k * PI / 5.0
						var r := 8.0 if k % 2 == 0 else 3.4
						pts.append(Vector2(10.0 + cos(a) * r, 10.5 + sin(a) * r))
					if _in_poly(p, pts):
						c = Color("#f6d17a")
				5:
					if p.distance_to(Vector2(10, 8.5)) < 6.8 or (x >= 6 and x < 14 and y >= 12 and y < 17):
						c = Color("#cfd4de")
					if p.distance_to(Vector2(7.5, 8.5)) < 1.8 or p.distance_to(Vector2(12.5, 8.5)) < 1.8:
						c = Color("#14161c")
			im.set_pixel(x, y, c)
	return im

static func _in_poly(p: Vector2, pts: Array) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(90.0, 150.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	if parts.has("mid"):
		tl.later(0.5, func(): GameData.data["T"]["spinTime"] = 1000.0)
		tl.later(0.9, func(): spin_t = 480.0)
	tl.later(0.8, func(): tl.use())
	if parts.has("jackpot"):
		tl.later(0.9, func():
			spin_t = 0.0
			ll.release(ll.player)
			the_prize = PRIZES[5]
			cool = 0.0)
		tl.later(1.0, func(): award(ll.player, PRIZES[5]))
