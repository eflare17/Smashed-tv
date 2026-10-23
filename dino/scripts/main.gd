extends Node2D
## Dino. A run: you roam a long procedurally generated area (Area), biting prey (Prey) and the hunters (Hunter)
## that come for you. Aim with the mouse, click to bite: the chunk comes out of exactly that spot
## (PixelPart.carve), flies or lands in your mouth, and pieces bitten clean through fall off (Gore). Kills and
## eating give XP; each level you pick an upgrade (bite size, speed, attack speed). The higher your level, the more
## hunters come, so the less time you get to eat. Eat a body down to nothing and you grow. The sign at the far end
## leads to the next area (harder). Die and the run is over; the next run is a new map.
##
## Each frame: input -> player (its snap calls player_bite) -> every creature -> the spawners -> gore; hit-stop
## freezes all of that for a few hundredths of a second after a bite lands, the camera shake keeps going.
## Keys: A/D or arrows move, W / Space / Up jump, left mouse bite, 1 / 2 / 3 pick a level-up, F3 show the zones,
## R new run. Command line (after --): --demo (a bot plays), --seed=<n> (that run), --shots=<folder> (saves 12
## screenshots, then quits; implies --demo), --shot-every=<frames> (75 by default), --shot-from=<frame>.

const DinoArt := preload("dino_art.gd")

const VIEW := Vector2(480, 270)
const GROUND_Y := 226.0
const MAX_CORPSES := 4
## A dead body with less than this much of itself left counts as eaten; eating one grows you by GROW.
const FINISHED := 0.05
const GROW := 0.1
## PLACEHOLDER numbers: XP and health for each thing, and XP to the next level.
const XP_KILL_PREY := 10
const XP_KILL_HUNTER := 25
const XP_EAT_BITE := 2
const XP_EAT_ALL := 15
const HEAL_EAT_BITE := 3.0
const HEAL_EAT_ALL := 15.0
## [name, what it does] for the three level-up choices, in order.
const UPGRADES := [["BITE SIZE", "bigger chunks"], ["SPEED", "run faster"], ["ATTACK SPEED", "bite more often"]]

enum { PLAY, CHOOSE, OVER }
## How heavy a bite lands (player_bite).
enum { SNAP, GRAB, TEAR, RIP }

var player: Player
## Everything you can bite: prey and hunters, alive and dead.
var creatures: Array[Prey] = []
var gore: Gore
var sfx: Sfx
var cam: Camera2D
var hud: Hud
var area: Area
var world_w := 2400
var obstacles: Array[Rect2] = []
var rng := RandomNumberGenerator.new()

var state := PLAY
var run_seed := 0
var area_n := 1
var level := 1
var xp := 0
var kills := 0
var chunks := 0
var eaten := 0
var show_zones := false
var demo := false

var _stop := 0.0
var _shake := 0.0
var _hunt_t := 0.0
var _herd_t := 0.0
var _choices := 0
var _over_t := 0.0
var _overlay: Node2D
var _popups: Array = []   # [text, world pos, seconds left, colour]
var _bot_t := 0.0
var _bot_point := Vector2.ZERO
var _bot_charge := 0.0
var _fixed_seed := -1
var _shots_dir := ""
var _shot_every := 75
var _shot_from := 0
var _frame := 0

func _ready() -> void:
	rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			demo = true
		elif a.begins_with("--seed="):
			_fixed_seed = int(a.substr(7))
		elif a.begins_with("--shot-from="):
			_shot_from = int(a.substr(12))
		elif a.begins_with("--shot-every="):
			_shot_every = int(a.substr(13))
		elif a.begins_with("--shots="):
			_shots_dir = a.substr(8)
			demo = true
	_add_inputs()
	sfx = Sfx.new()
	add_child(sfx)
	_overlay = Node2D.new()
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	cam = Camera2D.new()
	cam.limit_top = 0
	cam.limit_bottom = int(VIEW.y)
	add_child(cam)
	hud = Hud.new()
	hud.picked.connect(_pick)
	add_child(hud)
	hud.hint.text = "A/D MOVE   W JUMP   LEFT CLICK BITE   HOLD RIGHT CLICK BIG BITE   R NEW RUN"
	start_run()

# --- runs and areas ---------------------------------------------------------------------------------------

func start_run() -> void:
	run_seed = _fixed_seed if _fixed_seed >= 0 else rng.randi() % 100000
	if player:
		player.queue_free()
	player = Player.new()
	player.game = self
	add_child(player)
	level = 1
	xp = 0
	kills = 0
	chunks = 0
	eaten = 0
	_choices = 0
	state = PLAY
	hud.hide_over()
	hud.hide_choice()
	_mouse()
	enter_area(1)

func enter_area(n: int) -> void:
	area_n = n
	if area:
		area.queue_free()
	for c in creatures:
		c.queue_free()
	creatures.clear()
	_popups.clear()
	area = Area.new()
	area.generate(n, run_seed, GROUND_Y)
	world_w = area.width
	obstacles = area.obstacles
	add_child(area)
	move_child(area, 0)
	area.build(VIEW, GROUND_Y)
	gore = Gore.new()
	gore.z_index = 5
	area.add_child(gore)
	gore.setup(GROUND_Y, world_w, area.stains)
	cam.limit_left = 0
	cam.limit_right = world_w
	player.position = Vector2(40, GROUND_Y)
	player.vel = Vector2.ZERO
	for h: Array in area.herds:
		for k in h[1]:
			spawn_prey(h[0] + k * 50.0)
	_hunt_t = _hunt_gap() + 4.0
	_herd_t = 6.0
	hud.show_banner("AREA %d: %s" % [n, Area.NAMES[(n - 1) % Area.NAMES.size()]], 2.5)

func spawn_prey(x: float) -> Prey:
	return _add(Prey.new(), x)

func spawn_hunter(x: float) -> Hunter:
	return _add(Hunter.new(), x) as Hunter

func _add(c: Prey, x: float) -> Prey:
	c.game = self
	c.position = Vector2(clampf(x, 20.0, world_w - 20.0), GROUND_Y)
	area.add_child(c)
	c.set_facing(-1.0 if x > player.position.x else 1.0)
	if show_zones:
		c.set_show_zones(true)
	creatures.append(c)
	return c

## Off screen, on one side of you (inside the area): where newcomers walk in from.
func _offscreen_x() -> float:
	var sides := [-1.0, 1.0]
	sides.shuffle()
	for s: float in sides:
		var x: float = cam.get_screen_center_position().x + s * (VIEW.x * 0.5 + 24.0)
		if x > 20.0 and x < world_w - 20.0:
			return x
	return world_w - 20.0

## Seconds between hunters: shorter the higher your level and the further the area. PLACEHOLDER curve.
func _hunt_gap() -> float:
	return maxf(3.0, 16.0 - level * 1.5 - (area_n - 1) * 2.0)

func _hunt_cap() -> int:
	return mini(1 + (level - 1) / 2 + (area_n - 1), 6)

func _spawners(delta: float) -> void:
	_hunt_t -= delta
	if _hunt_t <= 0.0:
		_hunt_t = _hunt_gap()
		var live := creatures.filter(func(c): return c is Hunter and not c.dead).size()
		if live < _hunt_cap():
			spawn_hunter(_offscreen_x())
	# keep something to eat around
	_herd_t -= delta
	if _herd_t <= 0.0:
		_herd_t = 5.0
		var live := creatures.filter(func(c): return not (c is Hunter) and not c.dead).size()
		if live < 2 + area_n:
			spawn_prey(_offscreen_x())

# --- input ------------------------------------------------------------------------------------------------

func _add_inputs() -> void:
	var keys := {
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "jump": [KEY_W, KEY_SPACE, KEY_UP],
		"zones": [KEY_F3], "restart": [KEY_R], "pick1": [KEY_1], "pick2": [KEY_2], "pick3": [KEY_3],
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
	if not InputMap.has_action("big"):
		InputMap.add_action("big")
		var rb := InputEventMouseButton.new()
		rb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("big", rb)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zones"):
		show_zones = not show_zones
		for c in creatures:
			c.set_show_zones(show_zones)
	elif event.is_action_pressed("restart"):
		start_run()
	elif state == CHOOSE:
		for i in 3:
			if event.is_action_pressed("pick%d" % (i + 1)):
				_pick(i)
	elif state == OVER and _over_t <= 0.0 and event.is_action_pressed("bite"):
		start_run()

func _mouse() -> void:
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if state != PLAY else Input.MOUSE_MODE_HIDDEN

# --- frame -------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_frame += 1
	hud.tick(delta)
	var sim := delta
	if _stop > 0.0:
		_stop -= delta
		sim = 0.0
	if state == PLAY and sim > 0.0:
		_step(sim)
	elif state == OVER:
		_over_t -= delta
		if demo and _over_t < -2.0:
			start_run()
	elif state == CHOOSE and demo:
		_pick(rng.randi() % 3)
	_shake *= exp(-9.0 * delta)
	cam.position = Vector2(clampf(player.position.x, VIEW.x * 0.5, world_w - VIEW.x * 0.5), VIEW.y * 0.5)
	cam.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _shake * 5.0
	for pu in _popups:
		pu[2] -= delta
		pu[1].y -= delta * 14.0
	_popups = _popups.filter(func(pu): return pu[2] > 0.0)
	hud.set_bars(player.hp / player.max_hp, float(xp) / xp_needed(), level)
	hud.stats.text = "KILLS %d   EATEN %d   SIZE x%.1f" % [kills, eaten, player.size]
	hud.area_label.text = "AREA %d   RUN %d" % [area_n, run_seed]
	_overlay.queue_redraw()
	if _shots_dir != "" and _frame > _shot_from and (_frame - _shot_from) % _shot_every == 0:
		_save_shot()

func _step(delta: float) -> void:
	var move_x := 0.0
	var jump := false
	var bite := false
	var big := false
	var aim := get_global_mouse_position()
	if demo:
		var b := _bot(delta)
		move_x = b[0]
		jump = b[1]
		bite = b[2]
		aim = b[3]
		big = b[4]
	else:
		move_x = Input.get_axis("left", "right")
		jump = Input.is_action_just_pressed("jump")
		bite = Input.is_action_just_pressed("bite")
		big = Input.is_action_pressed("big")
	player.step(delta, move_x, jump, bite, aim, big)
	for c in creatures.duplicate():
		c.step(delta, player.global_position, rng)
	_spawners(delta)
	gore.step(delta)
	if player.position.x >= area.exit_x and state == PLAY:
		enter_area(area_n + 1)

# --- levels -----------------------------------------------------------------------------------------------

func xp_needed() -> int:
	return 30 + (level - 1) * 20

func add_xp(n: int, at: Vector2) -> void:
	xp += n
	_popups.append(["+%d XP" % n, at + Vector2(0, -14), 0.9, Color(0.5, 0.85, 1.0)])
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		_choices += 1
	if _choices > 0 and state == PLAY:
		_offer()

func _offer() -> void:
	state = CHOOSE
	var cards: Array = []
	cards.append([UPGRADES[0][0], "%s\n%.1f -> %.1f" % [UPGRADES[0][1], player.bite_radius, player.bite_radius + 1.0]])
	cards.append([UPGRADES[1][0], "%s\n%d -> %d" % [UPGRADES[1][1], player.walk_speed, player.walk_speed * 1.12]])
	cards.append([UPGRADES[2][0], "%s\n%.2fs -> %.2fs" % [UPGRADES[2][1], player.bite_cooldown, player.bite_cooldown * 0.85]])
	hud.show_choice(cards)
	sfx.play("gulp", 0.0, 2.0)
	_mouse()

func _pick(i: int) -> void:
	if state != CHOOSE:
		return
	match i:
		0:
			player.bite_radius += 1.0
		1:
			player.walk_speed *= 1.12
		2:
			player.bite_cooldown *= 0.85
	_choices -= 1
	hud.hide_choice()
	state = PLAY
	_popups.append(["LEVEL %d: %s" % [level - _choices, UPGRADES[i][0]], player.global_position + Vector2(0, -50), 1.6, Color(1, 0.85, 0.35)])
	if _choices > 0:
		_offer()
	_mouse()

# --- biting -----------------------------------------------------------------------------------------------

## The live (or dead) creature with a pixel under `world`, top-most first, or null.
func prey_at(world: Vector2) -> Prey:
	for i in range(creatures.size() - 1, -1, -1):
		if creatures[i].zone_at(world) != 0:
			return creatures[i]
	return null

## The player's jaws snapped shut at `p`: carve everything there, then the gore, XP, sounds, shake and hit-stop.
## `radius` is the bite's size; `mode` how heavy it lands: SNAP (a quick bite), GRAB (the big bite clamping on),
## TEAR (a little tear while shaking: no freeze, fewer words), RIP (the big rip at the end of a shake).
## Returns the creature bitten (the first), or null.
func player_bite(who: Player, p: Vector2, radius: float, mode := SNAP) -> Prey:
	var dir := Vector2(who.facing, 0.0)
	var got: Array = []
	var any := false
	var first: Prey = null
	var light := mode == TEAR
	for pr: Prey in creatures.duplicate():
		if pr.global_position.distance_to(p) > 160.0:
			continue
		var zone := pr.zone_at(p)
		var r := pr.bite(p, radius, rng)
		var off := 0
		for isl: Dictionary in r.islands:
			off += isl.pixels
		if r.removed.is_empty() and off == 0:
			continue
		any = true
		if first == null:
			first = pr
		chunks += 1
		got.append_array(r.removed)
		# tearing while you shake throws most of it about; a rip throws it hard
		gore.spray(r.removed, Vector2(rng.randf_range(-1.0, 1.0), -0.5) if light else dir, 0.8 if light else 0.35)
		gore.blood(p, dir, (4 + r.removed.size() / 3) if light else (8 + r.removed.size() / 2), 150.0 if mode == RIP else 110.0)
		for isl: Dictionary in r.islands:
			var fling := 1.6 if mode == RIP else 1.0
			gore.piece(isl, Vector2(dir.x * rng.randf_range(40.0, 100.0), -rng.randf_range(70.0, 150.0)) * fling)
			gore.blood(isl.center, Vector2.UP, 14, 90.0)
			sfx.play("rip", 0.08)
			_shake = minf(_shake + 0.5, 1.2)
		if zone == 0:
			zone = _main_zone(r.zones)
		if not light:
			_popups.append([DinoArt.ZONE_NAMES[zone], p + Vector2(0, -6), 0.7, Color(1, 0.9, 0.5)])
		var was_dead := pr.dead
		if was_dead:
			# eating: a little health and XP for every mouthful
			who.heal(HEAL_EAT_BITE)
			add_xp(XP_EAT_BITE, p)
		if pr.hurt(who.global_position) and not was_dead:
			kills += 1
			_popups.append(["KILL!", pr.global_position + Vector2(0, -50), 1.2, Color(1, 0.4, 0.3)])
			add_xp(XP_KILL_HUNTER if pr is Hunter else XP_KILL_PREY, pr.global_position + Vector2(0, -40))
			_trim_corpses()
		elif not pr.dead and (not light or rng.randf() < 0.25):
			sfx.play("cry", 0.1, -3.0 if not (pr is Hunter) else -8.0)
		if pr.dead and pr.mass_fraction() < FINISHED:
			got.append_array(_finish(who, pr))
	# pieces lying about (or still flying) go down whole
	if not light:
		var bits := gore.eat_pieces(p, radius + 1.0)
		if not bits.is_empty():
			any = true
			got.append_array(bits)
			gore.blood(p, dir, 6, 80.0)
			who.heal(HEAL_EAT_BITE)
			add_xp(XP_EAT_BITE, p)
	if not any:
		if not light:
			sfx.play("snap", 0.1, -2.0)
		return null
	match mode:
		TEAR:
			sfx.play("tear", 0.15, -6.0)
			_shake = minf(_shake + 0.12, 0.6)
		RIP:
			sfx.play("crunch", 0.1, 3.0)
			sfx.play("rip", 0.05, 2.0)
			_stop = 0.11
			_shake = 1.2
			who.hold(_mouthful(who, got, p))
		_:
			sfx.play("crunch", 0.1)
			sfx.play("tear", 0.1, -4.0)
			_stop = (0.07 if mode == GRAB else 0.045) + minf(0.05, got.size() * 0.0008)
			_shake = minf(_shake + (0.6 if mode == GRAB else 0.35), 1.2)
			if mode == SNAP:
				who.hold(_mouthful(who, got, p))
	return first

## The big bite landing at `p` with `charge` (0..1): a first bite as the jaws clamp on. Returns what you've got
## hold of (alive or dead), or null (missed).
func big_bite(who: Player, p: Vector2, charge: float) -> Prey:
	var got := player_bite(who, p, who.bite_radius * (1.0 + charge * 0.4), GRAB)
	if got:
		_popups.append(["GOT IT!", p + Vector2(0, -16), 0.8, Color(1, 0.55, 0.3)])
	return got

## Seconds into a `length`-second shake before `prey` breaks free: never if it's dead or no bigger than you, the
## bigger it is next to you the sooner. PLACEHOLDER rule.
func break_free_time(who: Player, prey: Prey, length: float) -> float:
	if prey.dead:
		return INF
	var mass := 0
	for part in prey.parts:
		mass += part.pixels_left()
	var ratio := mass / who.mass()
	return INF if ratio <= 1.0 else length / (ratio * ratio)

func grab_tear(who: Player, prey: Prey, p: Vector2, radius: float) -> void:
	player_bite(who, p, radius, TEAR)

func grab_rip(who: Player, prey: Prey, p: Vector2, radius: float) -> void:
	player_bite(who, p, radius, RIP)
	if is_instance_valid(prey) and creatures.has(prey) and not prey.dead:
		prey.vel.x += who.facing * 120.0
	_popups.append(["RIP!", p + Vector2(0, -16), 0.9, Color(1, 0.3, 0.2)])

func broke_free(who: Player, prey: Prey) -> void:
	_popups.append(["BROKE FREE!", prey.global_position + Vector2(0, -prey.height - 14), 1.0, Color(1, 1, 1)])
	sfx.play("cry", 0.05, 0.0)
	sfx.play("thud", 0.1, -6.0)
	prey.vel.x += who.facing * 80.0
	_shake = minf(_shake + 0.4, 1.2)

## A hunter's teeth reached you.
func hunter_bit(h: Hunter) -> void:
	if state != PLAY or not player.hurt(Hunter.DAMAGE, h.global_position):
		return
	hud.hurt()
	sfx.play("crunch", 0.1, 2.0)
	sfx.play("cry", 0.1, -2.0)
	_shake = 1.0
	_stop = 0.06
	var at := player.global_position + Vector2(0, -16.0 * player.size)
	gore.blood(at, Vector2(signf(player.position.x - h.position.x), -0.3), 18, 120.0)
	if player.hp <= 0.0:
		_game_over()

func _game_over() -> void:
	state = OVER
	_over_t = 1.0
	player.die_look()
	sfx.play("thud", 0.0)
	hud.show_over("LEVEL %d     AREA %d\nKILLS %d     EATEN %d     SIZE x%.1f\n\nRUN %d\n\n\nCLICK OR PRESS R FOR A NEW RUN" % [
		level, area_n, kills, eaten, player.size, run_seed])
	_mouse()

## A dead body eaten down to scraps: the scraps go down in one gulp, the body is gone, and you grow.
## Returns the scraps' pixels (for the mouthful).
func _finish(who: Player, pr: Prey) -> Array:
	var scraps: Array = []
	for part in pr.parts:
		for i in part.w * part.h:
			if part.alive[i] == 1:
				scraps.append([part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)), part.skin.get_pixel(i % part.w, i / part.w)])
	creatures.erase(pr)
	pr.queue_free()
	eaten += 1
	var was := who.size
	who.grow(GROW)
	who.heal(HEAL_EAT_ALL)
	_popups.append(["EATEN!" if who.size == was else "GROWING!", who.global_position + Vector2(0, -who.height * who.size - 10), 1.4, Color(1, 0.9, 0.5)])
	add_xp(XP_EAT_ALL, who.global_position + Vector2(0, -who.height * who.size))
	sfx.play("gulp", 0.05, 3.0)
	sfx.play("thud", 0.05, -6.0)
	return scraps

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
	var dead := creatures.filter(func(c): return c.dead)
	while dead.size() > MAX_CORPSES:
		var old: Prey = dead.pop_front()
		creatures.erase(old)
		old.queue_free()

# --- the demo bot -----------------------------------------------------------------------------------------

## Fights the nearest hunter, else eats the nearest body, else hunts the nearest prey, else heads for the exit;
## bites a different spot each time (now and then a charged big bite), jumps what's in the way.
## [move, jump, bite, aim, big held]
func _bot(delta: float) -> Array:
	# a big bite: hold right click for a while, then let go
	if player.charging:
		return [0.0, false, false, _bot_point, player.charge < _bot_charge]
	_bot_t -= delta
	var me := player.position
	var target: Prey = null
	for pass_n in 3:
		for c in creatures:
			var ok: bool = [c is Hunter and not c.dead, c.dead, not c.dead][pass_n]
			if ok and absf(c.position.x - me.x) < (140.0 if pass_n == 0 else 400.0) \
					and (target == null or absf(c.position.x - me.x) < absf(target.position.x - me.x)):
				target = c
		if target:
			break
	var jump := player.blocked != 0
	if target == null:
		return [1.0, jump, false, me + Vector2(60, -20), false]
	if _bot_t <= 0.0 or target.zone_at(_bot_point) == 0:
		_bot_t = 1.0
		var zones := [DinoArt.NECK, DinoArt.TAIL, DinoArt.LEGS, DinoArt.BODY, DinoArt.HEAD]
		zones.shuffle()
		var pt: Variant = null
		for z in zones:
			if pt == null:
				pt = _zone_point(target, z)
		_bot_point = pt if pt != null else target.global_position + Vector2(0, -20)
	var d := _bot_point - player.neck()
	var in_range := player.predict_bite(_bot_point).distance_to(_bot_point) < 1.0
	var move_x := 0.0 if in_range and absf(d.x) < player.head_len() * 1.5 else signf(d.x)
	var can_bite := in_range and player.cool <= 0.0 and player.bite_t < 0.0 and player.grab.is_empty()
	var big := can_bite and rng.randf() < 0.3
	if big:
		_bot_charge = rng.randf_range(0.3, 1.0)
	var bite := can_bite and not big
	return [move_x, jump, bite, _bot_point, big]

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
	var n := (_frame - _shot_from) / _shot_every
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
	# health: a little bar over each live creature (red for prey, orange for hunters)
	for c in creatures:
		if c.dead:
			continue
		var top := c.global_position + Vector2(-12, -c.height - 6)
		var f := clampf((c.mass_fraction() - Prey.DIE_MASS) / (1.0 - Prey.DIE_MASS), 0.0, 1.0)
		_overlay.draw_rect(Rect2(top, Vector2(24, 3)), Color(0, 0, 0, 0.7))
		_overlay.draw_rect(Rect2(top + Vector2(1, 1), Vector2(22 * f, 1)), Color(1.0, 0.55, 0.1) if c is Hunter else Color(0.9, 0.15, 0.1))
	for pu in _popups:
		var a := clampf(pu[2] * 2.0, 0.0, 1.0)
		var col: Color = pu[3]
		_text(font, pu[0], pu[1], Color(col, a))
	if demo or state != PLAY:
		return
	# the aim: red on a bitable spot in range (reach plus the lunge), white in range, grey past it (with a dot where
	# the bite would land instead)
	var m := get_global_mouse_position()
	var reach := player.predict_bite(m, Player.BIG if player.charging else Player.QUICK)
	var in_reach := reach.distance_to(m) < 1.0
	var target := prey_at(m)
	var c := Color(0.6, 0.6, 0.6)
	if in_reach:
		c = Color(1, 0.2, 0.15) if target else Color.WHITE
	var mp := m.floor() + Vector2(0.5, 0.5)
	for s: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_overlay.draw_line(mp + s * 2.0, mp + s * 4.0, c)
	if not in_reach:
		_overlay.draw_rect(Rect2(reach.floor(), Vector2.ONE), Color(1, 1, 1, 0.6))
	# charging a big bite: a ring the size of the rip, filling up as it charges
	if player.charging:
		var r := player.bite_radius * lerpf(Player.RIP[0], Player.RIP[1], player.charge) * player.size
		_overlay.draw_arc(mp, r, 0.0, TAU, 24, Color(c, 0.35), 1.0)
		_overlay.draw_arc(mp, r, -PI * 0.5, -PI * 0.5 + TAU * player.charge, 24, Color(1, 0.55, 0.2), 1.0)
	if target:
		_text(font, DinoArt.ZONE_NAMES[target.zone_at(m)], m + Vector2(0, -8), c)

func _text(font: Font, text: String, at: Vector2, c: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var p := (at + Vector2(-w * 0.5, 0)).floor()
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_overlay.draw_string(font, p + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0, 0, 0, c.a))
	_overlay.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
