extends Node
## The skeleton zombie, tested in the fight's simulation and inside the real game (scenes/main.tscn).
## Run: godot --headless --fixed-fps 60 --path <copy> res://test/zombie/zombie_test.tscn
## Prints "PASS ..." / "FAIL ..." and "ZOMBIE TESTS: n passed, m failed" (exit code 1 if anything failed).

var main: Node
var passed := 0
var failed := 0

func ok(c: bool, what: String) -> void:
	if c:
		passed += 1
		print("PASS ", what)
	else:
		failed += 1
		print("FAIL ", what)

func _ready() -> void:
	_go.call_deferred()

func sim_with_player(x: float, y: float) -> FightSim:
	var s := FightSim.new()
	var f := s.add_player(null, "juicy")
	f.x = x
	f.y = y
	return s

func run(s: FightSim, secs: float, inputs := []) -> void:
	for i in int(secs * 120.0):
		s.step(inputs)

func _go() -> void:
	_t_type()
	_t_rise_scream_chase_claw()
	_t_front_only()
	_t_yard_rules()
	_t_kill()
	_t_lobby_down()
	_t_arena_waves()
	_t_net()
	_t_anim()
	await _t_game()
	print("ZOMBIE TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _t_type() -> void:
	var s := FightSim.new()
	ok(s.e_key.size() == 5 and s.e_key[ZombieSim.T] == "zombie", "the zombie is enemy type 4")
	ok(s.e_melee[ZombieSim.T] and s.e_max_hp(ZombieSim.T) == 8.0, "it claws (melee) and takes 8 hp")

func _t_rise_scream_chase_claw() -> void:
	var s := sim_with_player(1000, 1200)
	var e := ZombieSim.spawn_at(s, 1000, 1500)
	ok(e.st == ZombieSim.RISE and s.events.any(func(v): return v[0] == ZombieSim.EV_RISE), "it climbs out of the ground")
	s.events.clear()
	run(s, ZombieSim.RISE_TIME * 0.5)
	ok(e.st == ZombieSim.RISE and absf(e.y - 1500.0) < 0.01, "it doesn't move while rising")
	run(s, ZombieSim.RISE_TIME * 0.5 + 0.05)
	ok(e.st == ZombieSim.SCREAM and s.events.any(func(v): return v[0] == ZombieSim.EV_SCREAM), "it screams when it sees you")
	run(s, ZombieSim.SCREAM_TIME + 0.05)
	ok(e.st == ZombieSim.CHASE and e.zt > 0.0, "then it comes at you, faster for a moment")
	var y0 := e.y
	run(s, 2.0)
	ok(e.y < y0 - 80.0, "it closes in (%.0f units in 2 s)" % (y0 - e.y))
	var f: FT.Fighter = s.players[0]
	var hp0 := f.hp
	var swiped := false
	for i in 120 * 12:
		s.step([])
		if e.st == ZombieSim.WINDUP:
			swiped = true
		if f.hp < hp0:
			break
	ok(swiped and f.hp == hp0 - 1.0, "it winds up and claws you for a heart")

func _t_front_only() -> void:
	var s := sim_with_player(1000, 1200)
	var e := ZombieSim.spawn_at(s, 1000, 1240)
	e.st = ZombieSim.SWING
	e.st_t = ZombieSim.SWING_TIME
	e.sdx = 0.0
	e.sdy = 1.0                       # swiping away from him
	var f: FT.Fighter = s.players[0]
	run(s, 0.3)
	ok(f.hp == s.tv("playerHp", 5), "a swipe only lands in front of it")

func _t_yard_rules() -> void:
	ok(ZombieSim.can_stand(1000, 1200, 16) and not ZombieSim.can_stand(400, 300, 16), "it may stand in the yard, not in the lounge")
	ok(not ZombieSim.can_stand(707, 1340, 16) and not ZombieSim.can_stand(200, 1700, 16), "not on the trampoline or in the shed")
	# he waits inside by the back door; it can't follow
	var s := sim_with_player(640, 470)
	var e := ZombieSim.spawn_at(s, 640, 640)
	e.st = ZombieSim.CHASE
	e.zf = 1
	var inside := false
	for i in 120 * 8:
		s.step([])
		if not ZombieSim.in_yard(e.x, e.y):
			inside = true
	ok(not inside, "it never comes into the house")
	ok(e.st == ZombieSim.WANDER, "with nobody out there it mills about")
	# up on the trampoline you're out of reach
	var s2 := sim_with_player(1000, 1200)
	var p := Node3D.new()
	p.set_meta("x", 0)
	var holder := _Dz.new()
	holder.dz = 60.0
	s2.players[0].node = holder
	ok(not ZombieSim.reachable(s2.players[0]), "up on a bounce it can't reach you")
	holder.free()
	p.free()

class _Dz extends Node3D:
	var dz := 0.0

func _t_kill() -> void:
	var s := sim_with_player(1000, 1200)
	s.players[0].x = 200
	s.players[0].y = 260
	var e := ZombieSim.spawn_at(s, 500, 260)
	e.st = ZombieSim.CHASE
	e.zf = 1
	var c0: int = s.players[0].coins
	var hits := 0
	while s.enemies.has(e) and hits < 20:
		var b := FT.Bullet.new()
		b.owner = 0
		b.x = e.x - 30.0
		b.y = e.y
		b.vx = 900.0
		b.vy = 0.0
		b.dmg = 1.0
		s.bullets.append(b)
		hits += 1
		for i in 12:
			s.step([])
	ok(not s.enemies.has(e) and hits == 8, "eight blaster hits kill it (%d)" % hits)
	var zc := s.corpses.filter(func(c): return c.t == ZombieSim.T)
	ok(zc.size() == 1 and zc[0].part == -1, "it falls whole (one body, no cut parts)")
	ok(zc.size() == 1 and absf(cos(zc[0].rot) - 1.0) < 0.2, "falling away from the shots")
	ok(s.players[0].coins == c0 + 4, "and pays $4")
	# fists
	var s2 := sim_with_player(1000, 1200)
	var e2 := ZombieSim.spawn_at(s2, 1000, 1236)
	e2.st = ZombieSim.CHASE
	var f: FT.Fighter = s2.players[0]
	f.fx = 0.0
	f.fy = 1.0
	var hp0 := e2.hp
	s2.punch_land(f)
	ok(e2.hp < hp0 and e2.stun > 0.0, "a punch hurts and staggers it")

func _t_lobby_down() -> void:
	var s := sim_with_player(1000, 1200)
	var f: FT.Fighter = s.players[0]
	f.hp = 1.0
	var e := ZombieSim.spawn_at(s, 1000, 1240)
	e.st = ZombieSim.SWING
	e.st_t = ZombieSim.SWING_TIME
	e.sdx = 0.0
	e.sdy = -1.0
	run(s, 0.3)
	ok(not f.alive and not s.over, "down in the yard isn't game over")

func _t_arena_waves() -> void:
	var s := sim_with_player(430, 260)
	s.start_run("classic")
	s.wave = 4
	s.breather = 0.01
	var seen := false
	var rose_inside := true
	for i in 120 * 40:
		s.step([])
		for e: FT.Enemy in s.enemies:
			if e.t == ZombieSim.T:
				seen = true
				if e.st == ZombieSim.RISE and (e.x < 40 or e.x > 820 or e.y < 40 or e.y > 480):
					rose_inside = false
		s.players[0].hp = 5.0
		if seen:
			break
	ok(seen, "wave 5 brings zombies into the arena")
	ok(rose_inside, "they rise from the arena floor, not the walls")
	ok(EnemySim.incoming_text(s, 5).ends_with("zombies"), "the wave banner says zombies")

func _t_net() -> void:
	var s := sim_with_player(1000, 1200)
	var e := ZombieSim.spawn_at(s, 1100, 1300)
	e.st = ZombieSim.WINDUP
	e.st_t = 0.3
	e.zf = 3
	e.zt = 1.25
	var d := NetCodec.pack_sim(s)
	var g := sim_with_player(0, 0)
	NetCodec.unpack_sim(g, d, true)
	var ge: FT.Enemy = g.enemies[0] if g.enemies.size() > 0 else null
	ok(ge != null and ge.t == ZombieSim.T and ge.st == ZombieSim.WINDUP and ge.zf == 3 and absf(ge.zt - 1.25) < 0.001,
		"the snapshot carries a zombie and its state to the guest")

func _t_anim() -> void:
	var m := ZombieModel.new(0.3)
	add_child(m)
	var a := m.anim
	var bad := false
	var moved := true
	for mv in ZombieAnim.MOVES:
		for k in 5:
			a.apply(mv, k / 4.0, 1.0, 0.3 if mv == "hit" else -1.0)
			for q in a.cur:
				if not q.is_normalized():
					bad = true
	a.apply("walk", 0.25, 1.0)
	var la: int = a.idx["LeftArm"]
	moved = a.cur[la].angle_to(a.rest_l[la]) > 0.5
	ok(not bad, "every move gives sound bone rotations")
	ok(moved, "the arms come down out of the T-pose")
	ok(not ZombieAnim.has_clip("walk") or ZombieAnim.clip("walk").has("anim"), "a clip if there is one, else the code's move")
	m.queue_free()

# ---------------------------------------------------------------- in the game

func _t_game() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 4:
		await get_tree().physics_frame
	var zn: ZombieNight = main.get_node_or_null("ZombieNight")
	ok(zn != null and zn.view != null and zn.sfx != null, "installed: main/ZombieNight with its view and sounds")
	if zn == null:
		return
	main.rig.capture_mouse = false
	var gc := get_node("/root/GameClock")
	gc.hour = 23.5
	var s: FightSim = zn.sim()
	main.player.place(1000, 1200)
	var seen := 0
	for i in 120 * 14:
		await get_tree().physics_frame
		s.players[0].iframe = 1.0
		gc.hour = 23.5
		seen = maxi(seen, ZombieSim.count(s))
	ok(seen >= 1, "at night, out in the yard, zombies come (%d)" % seen)
	var all_yard := true
	for e: FT.Enemy in s.enemies:
		if e.t == ZombieSim.T and not ZombieSim.in_yard(e.x, e.y):
			all_yard = false
	ok(all_yard, "in the yard")
	ok(zn.view.shown() >= ZombieSim.count(s), "each one drawn as the model (%d)" % zn.view.shown())
	# knocked down out there: back inside after a moment
	s.players[0].iframe = 0.0
	s.hurt_player(s.players[0], 99.0, 0.0, 1.0, 0.0)
	s.over = false
	for i in 120 * 5:
		await get_tree().physics_frame
	var hp: Vector3 = main.player.html_pos()
	ok(s.players[0].alive and not ZombieSim.in_yard(hp.x, hp.y) and main.player.controls_enabled, "knocked down, you come to inside")
	# dawn: they go back into the ground
	gc.hour = 6.0
	for i in 120 * 4:
		await get_tree().physics_frame
		gc.hour = 6.0
	ok(ZombieSim.count(s) == 0, "gone by morning")
	# by day nobody comes
	main.player.place(1000, 1200)
	for i in 120 * 10:
		await get_tree().physics_frame
		gc.hour = 12.0
	ok(ZombieSim.count(s) == 0, "none by day")
