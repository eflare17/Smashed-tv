extends RefCounted
## The pool: the ladder, the board, the dive, swimming, climbing out, the splash, the ducks. Both views.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var pool: LobbyPool = ll.things["pool"]
	var p: Player = ll.player
	var g := pool.tower_geo()
	# --- the numbers
	t.check(absf(g.ladderX - 602.125) < 0.01 and absf(g.deckH - 93.1) < 0.01 and absf(g.boardH - 100.6) < 0.01, "towerGeo as the HTML game")
	t.check(absf(g.tipX - 682.75) < 0.01 and absf(g.baseY - 200.8) < 0.01 and absf(g.boardX0 - 622.75) < 0.01, "towerGeo tip, base, board start")
	t.check(LobbyPool.in_water(700, 150) and not LobbyPool.in_water(629, 150) and not LobbyPool.in_water(700, 240), "in_water")
	t.check(LobbyPool.water_rect() == Rect2(630, 96, 179, 137), "water_rect")
	# --- you cannot walk into the pool
	t.place(660, 250, Vector2(0, -1))
	await t.hold("move_up", 1.5)
	t.check(not LobbyPool.in_water(p.html_pos().x, p.html_pos().y), "the pool is a solid: he can't walk in (y=%.1f)" % p.html_pos().y)
	# --- the foot of the ladder: the prompt, then climbing with up
	t.place(g.ladderX, 214.0)
	await t.wait(0.1)
	t.check(t.label() == "CLIMB", "at the ladder foot E says CLIMB (%s)" % t.label())
	t.check(pool._tip.visible and pool._tip.text.ends_with("climb"), "the climb tip shows over his head (%s %s %s)" % [pool._tip.visible, pool._tip.text, pool._tip.position])
	t.place(g.ladderX + 40.0, 214.0)
	t.check(t.label() != "CLIMB", "not at the ladder when 40 to the side")
	t.place(g.ladderX, 214.0)
	Input.action_press("move_up")
	await t.wait(0.4)
	t.check(ll.busy.get(p) == pool, "push up at the foot: on the ladder")
	t.check(pool.dive_of(p) == LobbyPool.Dive.CLIMB, "climbing")
	t.check(absf(p.html_pos().x - g.ladderX) < 0.1, "snapped to the ladder x")
	t.check(p.dz > 0.0, "off the ground (dz %.1f)" % p.dz)
	await t.wait(1.0)
	Input.action_release("move_up")
	t.check(pool.dive_of(p) == LobbyPool.Dive.BOARD, "top of the ladder: on the board")
	t.check(absf(pool.height_of(p) - g.deckH) < 0.5, "at deck height (%.1f)" % pool.height_of(p))
	t.check(t.label() == "DIVE", "on the board E says DIVE (%s)" % t.label())
	# --- along the board
	await t.hold("move_right", 0.25)
	var x1 := p.html_pos().x
	t.check(x1 > g.ladderX + 20.0 and x1 < g.ladderX + 40.0, "walks along the board at 120 a second (x %.1f)" % x1)
	await t.hold("move_right", 0.3)
	t.check(p.html_pos().x > 640.0 and absf(pool.height_of(p) - g.boardH) < 0.5, "along the board, board height (%.1f %.1f)" % [p.html_pos().x, pool.height_of(p)])
	# --- walk off the end: the dive (a push at the tip after 0.15 s)
	Input.action_press("move_right")
	await t.wait(0.2)
	Input.action_release("move_right")
	t.check(pool.dive_of(p) in [LobbyPool.Dive.FALL, LobbyPool.Dive.SWIM], "walking off the tip dives")
	await t.wait(1.0)
	t.check(pool.swimming(p), "lands in the water and swims")
	var sp := p.html_pos()
	t.check(LobbyPool.in_water(sp.x, sp.y), "landed in the water (%.0f, %.0f)" % [sp.x, sp.y])
	t.check(pool.fx.foams.size() > 0 or pool.fx.ripples.size() > 0, "a splash and rings")
	t.check(p.sprite._mat.get_shader_parameter("sink") > 0.5 and p.sprite._mat.get_shader_parameter("cut") < 0.6, "sunk to the shoulders")
	# --- swimming around
	await t.hold("move_left", 0.5)
	t.check(p.html_pos().x < sp.x - 15.0, "swims left (%.0f -> %.0f)" % [sp.x, p.html_pos().x])
	# --- out over the left edge after the half second
	await t.hold("move_left", 2.0)
	t.check(not pool.swimming(p) and not ll.busy.has(p), "pushing into the edge hauls him out")
	t.check(p.html_pos().x < 630.0, "out on the tiles (x %.1f)" % p.html_pos().x)
	t.check(p.sprite._mat.get_shader_parameter("sink") == 0.0 and not p.frozen, "back to normal after the swim")
	# --- off the bottom rung
	t.place(g.ladderX, 214.0)
	await t.hold("move_up", 0.5)
	t.check(pool.dive_of(p) == LobbyPool.Dive.CLIMB, "up again")
	await t.hold("move_down", 0.7)
	t.check(not ll.busy.has(p) and p.html_pos().y > g.baseY - 1.0, "down the ladder and off the bottom rung (y %.1f)" % p.html_pos().y)
	# --- E at the foot, the roll button from the board
	t.place(g.ladderX, 214.0)
	t.press_e()
	t.check(pool.dive_of(p) == LobbyPool.Dive.CLIMB, "E at the foot climbs on")
	await t.hold("move_up", 1.2)
	t.check(pool.dive_of(p) == LobbyPool.Dive.BOARD, "up to the board")
	t.press_e()
	await t.wait(0.3)
	t.check(pool.dive_of(p) == LobbyPool.Dive.FALL or pool.swimming(p), "E dives off the board")
	await t.wait(1.0)
	t.check(pool.swimming(p), "swimming")
	# --- the collision exceptions are on while diving and off afterwards
	var sol = ll.world.solids
	t.check(p.get_collision_exceptions().has(sol["pool"]) and p.get_collision_exceptions().has(sol["tower"]), "passes through Solid_pool and Solid_tower while swimming")
	await t.hold("move_down", 2.5)
	t.check(not ll.busy.has(p), "out over the bottom edge")
	t.check(not p.get_collision_exceptions().has(sol["pool"]), "the exceptions are off again")
	t.check(p.html_pos().y > 240.0, "on the tiles below the pool (y %.1f)" % p.html_pos().y)
	# --- a miss: roll off the board when it would land short does not happen here, but a splash helper does work
	var nf := pool.fx.foams.size()
	pool.splash(700, 150, false)
	t.check(pool.fx.foams.size() == nf + 1, "small splash adds foam")
	# --- the ducks stay in the water and get shoved
	var d0: Dictionary = pool.fx.ducks[0]
	var before := Vector2(d0.x, d0.y)
	pool.shove_ducks(d0.x - 10.0, d0.y, 1.6)
	await t.wait(0.6)
	t.check(Vector2(d0.x, d0.y).distance_to(before) > 3.0, "a splash shoves a duck")
	for d in pool.fx.ducks:
		t.check(LobbyPoolFx.duck_bounds().grow(0.5).has_point(Vector2(d.x, d.y)), "duck stays in the water")
	# --- first person: slow climb with W, view locked, tower hidden
	t.place(g.ladderX, 214.0, Vector2(0, -1))
	ll.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	await t.wait(0.1)
	Input.action_press("move_up")
	await t.wait(0.5)
	t.check(pool.dive_of(p) == LobbyPool.Dive.CLIMB, "first person: facing the ladder and W climbs")
	await t.wait(1.0)
	var hz1 := pool.height_of(p)
	t.check(hz1 > 10.0 and hz1 < 40.0, "first person climbs slowly (%.1f)" % hz1)
	Input.action_release("move_up")
	t.check(absf(p.dz - hz1) < 0.1, "first person dz is the true height")
	t.check(not ll.world.props["tower"].visible, "the flat tower is hidden while you are on it in first person")
	Input.action_press("move_down")
	await t.wait(8.0)
	Input.action_release("move_down")
	t.check(not ll.busy.has(p), "first person: S back down and off")
	t.check(ll.world.props["tower"].visible, "the tower is back")
