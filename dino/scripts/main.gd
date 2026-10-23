extends Node2D
## Dino, step 1: one bite that feels good. A side-on strip of ground, you (Player) and prey (Prey) that runs.
## Aim with the mouse, click to bite: the chunk comes out of exactly that spot (PixelPart.carve), flies or lands in
## your mouth, and pieces bitten clean through fall off (Gore). Everything is drawn in code at 480x270 and scaled
## up in whole pixels.
##
## Each frame: input -> player (its snap calls player_bite) -> prey -> gore; hit-stop freezes all of that for a
## few hundredths of a second after a bite lands, the camera shake keeps going.
## Keys: A/D or arrows move, W / Space / Up jump, left mouse bite, F3 show the zones, R start over.
## Command line (after --): --demo (a bot plays), --shots=<folder> (saves screenshots, then quits; implies --demo).

const DinoArt := preload("dino_art.gd")

const WORLD_W := 1280
const VIEW := Vector2(480, 270)
const GROUND_Y := 226.0
const MAX_CORPSES := 3
const RESPAWN := 2.5

var player: Player
var prey: Array[Prey] = []
var gore: Gore
var sfx: Sfx
var cam: Camera2D
var rng := RandomNumberGenerator.new()

var kills := 0
var chunks := 0
var show_zones := false
var demo := false

var _stop := 0.0
var _shake := 0.0
var _respawn_t := -1.0
var _overlay: Node2D
var _hud: Label
var _hint: Label
var _popups: Array = []   # [text, world pos, seconds left]
var _bot_t := 0.0
var _bot_zone := 0
var _bot_point := Vector2.ZERO
var _shots_dir := ""
var _frame := 0

func _ready() -> void:
	rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			demo = true
		elif a.begins_with("--shots="):
			_shots_dir = a.substr(8)
			demo = true
	_add_inputs()
	_build_scenery()
	var stains := Sprite2D.new()
	stains.z_index = -5
	add_child(stains)
	gore = Gore.new()
	gore.z_index = 5
	add_child(gore)
	gore.setup(GROUND_Y, WORLD_W, stains)
	sfx = Sfx.new()
	add_child(sfx)
	_overlay = Node2D.new()
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_right = WORLD_W
	cam.limit_top = 0
	cam.limit_bottom = int(VIEW.y)
	add_child(cam)
	_build_hud()
	start()
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func start() -> void:
	for p in prey:
		p.queue_free()
	prey.clear()
	if player:
		player.queue_free()
	gore.clear()
	kills = 0
	chunks = 0
	_popups.clear()
	player = Player.new()
	player.game = self
	player.position = Vector2(140, GROUND_Y)
	add_child(player)
	spawn_prey(360.0)
	_respawn_t = -1.0

func spawn_prey(x: float) -> Prey:
	var p := Prey.new()
	p.game = self
	p.position = Vector2(x, GROUND_Y)
	add_child(p)
	p.set_facing(-1.0 if x > player.position.x else 1.0)
	if show_zones:
		p.set_show_zones(true)
	prey.append(p)
	return p

func _add_inputs() -> void:
	var keys := {
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "jump": [KEY_W, KEY_SPACE, KEY_UP],
		"zones": [KEY_F3], "restart": [KEY_R],
	}
	for action: String in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("bite"):
		InputMap.add_action("bite")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("bite", mb)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zones"):
		show_zones = not show_zones
		for p in prey:
			p.set_show_zones(show_zones)
	elif event.is_action_pressed("restart"):
		start()

# --- frame -------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_frame += 1
	var sim := delta
	if _stop > 0.0:
		_stop -= delta
		sim = 0.0
	if sim > 0.0:
		_step(sim)
	_shake *= exp(-9.0 * delta)
	cam.position = Vector2(clampf(player.position.x, VIEW.x * 0.5, WORLD_W - VIEW.x * 0.5), VIEW.y * 0.5)
	cam.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _shake * 5.0
	for pu in _popups:
		pu[2] -= delta
		pu[1].y -= delta * 14.0
	_popups = _popups.filter(func(pu): return pu[2] > 0.0)
	_hud.text = "KILLS %d    CHUNKS %d" % [kills, chunks]
	_overlay.queue_redraw()
	if _shots_dir != "" and _frame % 75 == 0:
		_save_shot()

func _step(delta: float) -> void:
	var move_x := 0.0
	var jump := false
	var bite := false
	var aim := get_global_mouse_position()
	if demo:
		var b := _bot(delta)
		move_x = b[0]
		jump = b[1]
		bite = b[2]
		aim = b[3]
	else:
		move_x = Input.get_axis("left", "right")
		jump = Input.is_action_just_pressed("jump")
		bite = Input.is_action_just_pressed("bite")
	player.step(delta, move_x, jump, bite, aim)
	for p in prey:
		p.step(delta, player.global_position, rng)
	gore.step(delta)
	if _respawn_t >= 0.0:
		_respawn_t -= delta
		if _respawn_t < 0.0:
			# in from the far side of the screen from you
			var side := 1.0 if player.position.x < WORLD_W * 0.5 else -1.0
			spawn_prey(clampf(player.position.x + side * 260.0, 20.0, WORLD_W - 20.0))

## The live (or dead) prey with a pixel under `world`, top-most first, or null.
func prey_at(world: Vector2) -> Prey:
	for i in range(prey.size() - 1, -1, -1):
		if prey[i].zone_at(world) != 0:
			return prey[i]
	return null

## The player's jaws snapped shut at `p`: carve every prey there, then the gore, sounds, shake and hit-stop.
func player_bite(who: Player, p: Vector2) -> void:
	var dir := Vector2(who.facing, 0.0)
	var got: Array = []
	var any := false
	for pr: Prey in prey.duplicate():
		if pr.global_position.distance_to(p) > 120.0:
			continue
		var zone := pr.zone_at(p)
		var r := pr.bite(p, who.bite_radius, rng)
		var off := 0
		for isl: Dictionary in r.islands:
			off += isl.pixels
		if r.removed.is_empty() and off == 0:
			continue
		any = true
		chunks += 1
		got.append_array(r.removed)
		gore.spray(r.removed, dir, 0.35)
		gore.blood(p, dir, 8 + r.removed.size() / 2, 110.0)
		for isl: Dictionary in r.islands:
			gore.piece(isl, Vector2(dir.x * rng.randf_range(40.0, 100.0), -rng.randf_range(70.0, 150.0)))
			gore.blood(isl.center, Vector2.UP, 14, 90.0)
			sfx.play("rip", 0.08)
			_shake = minf(_shake + 0.5, 1.2)
		if zone == 0:
			zone = _main_zone(r.zones)
		_popups.append([DinoArt.ZONE_NAMES[zone], p + Vector2(0, -6), 0.7])
		var was_dead := pr.dead
		if pr.hurt(who.global_position) and not was_dead:
			kills += 1
			_popups.append(["KILL!", pr.global_position + Vector2(0, -50), 1.2])
			if _respawn_t < 0.0:
				_respawn_t = RESPAWN
			_trim_corpses()
		elif not pr.dead:
			sfx.play("cry", 0.1, -3.0)
	if any:
		sfx.play("crunch", 0.1)
		sfx.play("tear", 0.1, -4.0)
		_stop = 0.045 + minf(0.05, got.size() * 0.0008)
		_shake = minf(_shake + 0.35, 1.2)
		who.hold(_mouthful(who, got, p))
	else:
		sfx.play("snap", 0.1, -2.0)

func _main_zone(zones: PackedInt32Array) -> int:
	var best := 0
	for z in zones.size():
		if zones[z] > zones[best]:
			best = z
	return best

## The bitten-off pixels as one small picture, in the head's own frame (centred on the bite), for the mouth.
func _mouthful(who: Player, got: Array, at: Vector2) -> Image:
	if got.is_empty():
		return null
	var base := who.head.to_local(at)
	var lo := Vector2(INF, INF)
	var hi := -lo
	var pts: Array = []
	for r in got:
		var lp: Vector2 = (who.head.to_local(r[0]) - base).round()
		pts.append(lp)
		lo = lo.min(lp)
		hi = hi.max(lp)
	var img := Image.create(int(hi.x - lo.x) + 1, int(hi.y - lo.y) + 1, false, Image.FORMAT_RGBA8)
	for k in pts.size():
		var q: Vector2 = pts[k] - lo
		img.set_pixel(int(q.x), int(q.y), got[k][1])
	return img

func prey_landed(p: Prey) -> void:
	sfx.play("thud", 0.05)
	_shake = minf(_shake + 0.4, 1.2)
	gore.pool(p.global_position.x, 26.0, 160)

func _trim_corpses() -> void:
	var dead := prey.filter(func(p): return p.dead)
	while dead.size() > MAX_CORPSES:
		var old: Prey = dead.pop_front()
		prey.erase(old)
		old.queue_free()

# --- the demo bot -----------------------------------------------------------------------------------------

## Walks up to the nearest prey and bites a chosen zone, a different one each time. [move, jump, bite, aim]
func _bot(delta: float) -> Array:
	_bot_t -= delta
	var target: Prey = null
	for p in prey:
		if not p.dead and (target == null or absf(p.position.x - player.position.x) < absf(target.position.x - player.position.x)):
			target = p
	if target == null:
		for p in prey:
			if target == null or absf(p.position.x - player.position.x) < absf(target.position.x - player.position.x):
				target = p
	if target == null:
		return [0.0, false, false, player.position + Vector2(40, -20)]
	if _bot_t <= 0.0 or target.zone_at(_bot_point) == 0:
		_bot_t = 1.2
		var zones := [DinoArt.NECK, DinoArt.TAIL, DinoArt.LEGS, DinoArt.BODY, DinoArt.HEAD]
		_bot_zone = zones[rng.randi() % zones.size()]
		var pt: Variant = _zone_point(target, _bot_zone)
		_bot_point = pt if pt != null else target.global_position + Vector2(0, -20)
	var neck := player.neck()
	var d := _bot_point - neck
	var move_x := 0.0
	if absf(d.x) > player.reach * 0.6:
		move_x = signf(d.x)
	var bite := d.length() < player.reach * 0.95 and player.cool <= 0.0 and player.bite_t < 0.0
	return [move_x, false, bite, _bot_point]

## A random live pixel of `zone` on `p`, in the world, or null.
func _zone_point(p: Prey, zone: int) -> Variant:
	var cands: Array = []
	for part in p.parts:
		for i in part.w * part.h:
			if part.alive[i] == 1 and part.zone[i] == zone:
				cands.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
	if cands.is_empty():
		return null
	return cands[rng.randi() % cands.size()]

func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var n := _frame / 75
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%02d.png" % [_shots_dir, n])
	# and a close-up (3x) of the fight, to check the pixels
	var mid := player.get_global_transform_with_canvas().origin + Vector2(50, -20)
	var r := Rect2i(Vector2i(clampi(int(mid.x) - 80, 0, int(VIEW.x) - 160), clampi(int(mid.y) - 45, 0, int(VIEW.y) - 90)), Vector2i(160, 90))
	var zoom := img.get_region(r)
	zoom.resize(480, 270, Image.INTERPOLATE_NEAREST)
	zoom.save_png("%s/zoom_%02d.png" % [_shots_dir, n])
	if n >= 12:
		get_tree().quit()

# --- drawing ----------------------------------------------------------------------------------------------

func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	# prey health: a little bar over each live one
	for p in prey:
		if p.dead:
			continue
		var top := p.global_position + Vector2(-12, -p.height - 6)
		var f := clampf((p.mass_fraction() - Prey.DIE_MASS) / (1.0 - Prey.DIE_MASS), 0.0, 1.0)
		_overlay.draw_rect(Rect2(top, Vector2(24, 3)), Color(0, 0, 0, 0.7))
		_overlay.draw_rect(Rect2(top + Vector2(1, 1), Vector2(22 * f, 1)), Color(0.9, 0.15, 0.1))
	for pu in _popups:
		var a := clampf(pu[2] * 2.0, 0.0, 1.0)
		_text(font, pu[0], pu[1], Color(1, 0.9, 0.5, a))
	if demo:
		return
	# the aim: red on a bitable spot in reach, white in reach, grey past reach (with a dot where you'd bite)
	var m := get_global_mouse_position()
	var reach := player.clamp_reach(m)
	var in_reach := reach.distance_to(m) < 0.5
	var target := prey_at(m)
	var c := Color(0.6, 0.6, 0.6)
	if in_reach:
		c = Color(1, 0.2, 0.15) if target else Color.WHITE
	var mp := m.floor() + Vector2(0.5, 0.5)
	for s: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_overlay.draw_line(mp + s * 2.0, mp + s * 4.0, c)
	if not in_reach:
		_overlay.draw_rect(Rect2(reach.floor(), Vector2.ONE), Color(1, 1, 1, 0.6))
	if target:
		_text(font, DinoArt.ZONE_NAMES[target.zone_at(m)], m + Vector2(0, -8), c)

func _text(font: Font, text: String, at: Vector2, c: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var p := (at + Vector2(-w * 0.5, 0)).floor()
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_overlay.draw_string(font, p + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0, 0, 0, c.a))
	_overlay.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ls := LabelSettings.new()
	ls.font_size = 8
	ls.outline_size = 2
	ls.outline_color = Color.BLACK
	_hud = Label.new()
	_hud.label_settings = ls
	_hud.position = Vector2(6, 4)
	layer.add_child(_hud)
	_hint = Label.new()
	_hint.label_settings = ls
	_hint.text = "A/D MOVE   W JUMP   CLICK BITE   F3 ZONES   R RESTART"
	_hint.position = Vector2(6, VIEW.y - 14)
	_hint.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(_hint)

## PLACEHOLDER scenery: a banded sky, far hills, nearer jungle, and the ground strip.
func _build_scenery() -> void:
	var sky := Image.create(1, int(VIEW.y), false, Image.FORMAT_RGBA8)
	var top := Color(0.36, 0.55, 0.72)
	var low := Color(0.93, 0.74, 0.5)
	for y in int(VIEW.y):
		var k := floorf(float(y) / VIEW.y * 9.0) / 8.0
		sky.set_pixel(0, y, top.lerp(low, k))
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	var sky_rect := TextureRect.new()
	sky_rect.texture = ImageTexture.create_from_image(sky)
	sky_rect.stretch_mode = TextureRect.STRETCH_SCALE
	sky_rect.size = VIEW
	sky_layer.add_child(sky_rect)
	_add_layer(_ridge(960, 120, 70.0, 0.012, Color(0.45, 0.47, 0.55), 3), 0.15, GROUND_Y - 120)
	_add_layer(_ridge(960, 90, 40.0, 0.03, Color(0.24, 0.36, 0.28), 7), 0.4, GROUND_Y - 88)
	_add_layer(_jungle(960, 70), 0.7, GROUND_Y - 66)
	var ground := Image.create(WORLD_W, int(VIEW.y - GROUND_Y) + 4, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.08
	for y in ground.get_height():
		for x in WORLD_W:
			var v := n.get_noise_2d(x, y * 2.0)
			var c := Color(0.42, 0.3, 0.2).lerp(Color(0.33, 0.23, 0.15), clampf(v + 0.5, 0.0, 1.0))
			if y < 3:
				c = Color(0.36, 0.52, 0.22) if (y < 2 or (x * 7 + y) % 5 != 0) else c
				if y == 0 and n.get_noise_1d(x * 3.0) > 0.2:
					c = Color(0.45, 0.62, 0.27)
			ground.set_pixel(x, y, c)
	var g := Sprite2D.new()
	g.texture = ImageTexture.create_from_image(ground)
	g.centered = false
	g.position = Vector2(0, GROUND_Y - 3)
	g.z_index = -6
	add_child(g)

func _add_layer(img: Image, scroll: float, y: float) -> void:
	var par := Parallax2D.new()
	par.scroll_scale = Vector2(scroll, 1.0)
	par.repeat_size = Vector2(img.get_width(), 0)
	par.repeat_times = 3
	par.z_index = -20
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.position = Vector2(-img.get_width(), y)
	par.add_child(s)
	add_child(par)

func _ridge(w: int, h: int, amp: float, freq: float, c: Color, sd: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	for x in w:
		# wraps: blend the noise with itself one width along
		var k := float(x) / w
		var v := lerpf(n.get_noise_1d(x), n.get_noise_1d(x - w), k)
		var top := int(h - amp * (0.55 + v * 0.8))
		for y in range(clampi(top, 0, h), h):
			img.set_pixel(x, y, c.lightened(0.08) if y == top else c)
	return img

func _jungle(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var trunk := Color(0.2, 0.2, 0.16)
	var leaf := Color(0.16, 0.3, 0.18)
	var x := 10
	while x < w - 20:
		var th := r.randi_range(30, 60)
		for y in range(h - th, h):
			img.set_pixel(x, y, trunk)
			img.set_pixel(x + 1, y, trunk)
		# palm fronds: lines drooping out from the top
		for f in 6:
			var a := -PI * 0.5 + (f - 2.5) * 0.55
			var p := Vector2(x, h - th)
			for s in 14:
				p += Vector2(cos(a), sin(a) + s * 0.07)
				var px := int(p.x)
				var py := int(p.y)
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, leaf)
					if py + 1 < h:
						img.set_pixel(px, py + 1, leaf.darkened(0.2))
		x += r.randi_range(40, 90)
	for y in range(h - 10, h):
		for xx in w:
			if r.randf() < 0.7 - (h - y) * 0.06:
				img.set_pixel(xx, y, leaf.darkened(0.1))
	return img
