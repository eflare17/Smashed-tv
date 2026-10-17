extends Node
## Headless logic tests for the fighting simulation (FightSim), checked against the numbers in godot/specs.
## Run: godot --headless --path godot res://test/combat/logic_test.tscn   (prints PASS/FAIL lines, exits 0/1)

var fails := 0
var passes := 0

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("PASS ", what)
	else:
		fails += 1
		print("FAIL ", what)

func near(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

func _ready() -> void:
	test_rng()
	test_wave_mix()
	test_blasters()
	test_spud()
	test_lob()
	test_fists()
	test_shotgun()
	test_launcher()
	test_run_waves()
	test_batter()
	test_brute_shrapnel()
	test_janitor()
	test_game_over()
	test_protect()
	test_coins()
	print("logic tests: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func sim_with_player(x := 430.0, y := 400.0) -> FightSim:
	var s := FightSim.new()
	var f := s.add_player(null, "juicy")
	f.x = x
	f.y = y
	s.fill_lobby()
	return s

func inp() -> FT.Inp:
	return FT.Inp.new()

func steps(s: FightSim, n: int, i: FT.Inp = null) -> void:
	for k in n:
		s.step([i if i else inp()])

func test_rng() -> void:
	var s := FightSim.new()
	var a := s.rnd()
	# seed 1: (1 * 1664525 + 1013904223) mod 2^32 = 1015568748
	ok(near(a, 1015568748.0 / 4294967296.0, 1e-12), "rnd matches the HTML LCG")

func test_wave_mix() -> void:
	var s := FightSim.new()
	var q := EnemySim.wave_mix(s, 1)
	ok(q.size() == 6 and q.count(3) == 6, "wave 1 is six batters")
	var q5 := EnemySim.wave_mix(s, 5)
	ok(q5.size() == 18 and q5.count(1) == 6 and q5.count(2) == 1 and q5.count(3) == 11, "wave 5: 11 batters, 6 swarmers, 1 brute")
	ok(EnemySim.incoming_text(s, 5) == "18 incoming — swarmers and brutes", "wave 5 banner text")
	ok(near(EnemySim.wave_speed(s, 2), 42.4, 0.001), "wave 2 speed 42.4")

func test_blasters() -> void:
	var s := sim_with_player()
	s.start_run("classic")
	var f: FT.Fighter = s.players[0]
	s.give_weapon(f, "blaster")
	s.breather = 999.0
	var e := s.new_enemy(0, 430, 200)
	e.spawn = 0.0
	var i := inp()
	i.shoot = true
	i.ax = 0
	i.ay = -1
	var shots0 := f.shots
	steps(s, 120, i)
	ok(f.shots - shots0 >= 9 and f.shots - shots0 <= 10, "blasters fire 9.5 a second (%d)" % (f.shots - shots0))
	ok(not s.enemies.has(e), "a grunt dies to blaster fire")
	ok(f.kills == 1, "a bullet kill counts")
	ok(f.coins == 2500 + 1, "the kill pays $1 to the wallet (%d)" % f.coins)

func test_spud() -> void:
	var s := sim_with_player()
	var f: FT.Fighter = s.players[0]
	f.weapon = "spud"
	f.ammo = 20
	var i := inp()
	i.shoot = true
	i.ax = 1
	i.ay = 0
	var t0 := 0
	var shots := 0
	var seen_throw := false
	for k in 120 * 12:
		s.step([i])
		if f.throw > 0.0:
			seen_throw = true
	ok(f.ammo == 0, "the spud gun empties 20 pellets (%d left)" % f.ammo)
	ok(seen_throw, "a husk is thrown after a potato's worth")
	ok(f.dry_hint > 0.0, "need a spud when empty")
	# jab timing: 0.42 s between shots
	var s2 := sim_with_player()
	var g: FT.Fighter = s2.players[0]
	g.weapon = "spud"
	g.ammo = 20
	steps(s2, 120, i)
	ok(g.shots >= 2 and g.shots <= 3, "the jab sets the spud gun's rate (%d shots in 1 s)" % g.shots)
	# pickup: a ripe plant adds 10
	var s3 := sim_with_player(200, 200)
	var h: FT.Fighter = s3.players[0]
	h.ammo = 0
	var pl := FT.Plant.new()
	pl.x = 205
	pl.y = 200
	pl.t = 9.0
	s3.plants.append(pl)
	steps(s3, 2)
	ok(h.ammo == 10 and h.pickup > 0.0, "a ripe potato adds 10 pellets and bends him over")

func test_lob() -> void:
	var s := sim_with_player(400, 300)
	var f: FT.Fighter = s.players[0]
	f.weapon = "lob"
	f.ammo = 20
	var i := inp()
	i.shoot = true
	i.ax = 300
	i.ay = 0
	steps(s, 40, i)            # full wind-up (0.3 s)
	ok(f.charge >= 1.0 and f.aim_on, "the throw winds up fully in 0.3 s with the ring on")
	ok(near(f.tx, 700, 0.5), "the ring is on the cursor")
	steps(s, 1, inp())          # let go
	ok(f.ammo == 10 and f.throw > 0.0, "letting go throws a whole potato")
	var landed := false
	var splatted := false
	for k in 200:
		s.step([inp()])
		for fl in s.floaters:
			if fl.text == "SPLAT!":
				splatted = true
	ok(splatted, "a full-power potato bursts (SPLAT!)")
	# a tap: no burst, it lands and lies there as a ripe potato
	var s2 := sim_with_player(400, 300)
	var g: FT.Fighter = s2.players[0]
	g.weapon = "lob"
	g.ammo = 10
	steps(s2, 1, i)
	steps(s2, 1, inp())
	steps(s2, 300)
	ok(s2.plants.size() >= 1, "a tapped potato bounces and becomes a pickup (%d plants)" % s2.plants.size())

func test_fists() -> void:
	var s := sim_with_player(400, 300)
	s.start_run("classic")
	s.breather = 999.0
	var f: FT.Fighter = s.players[0]
	f.weapon = "fists"
	var e := s.new_enemy(0, 430, 300)
	e.spawn = 0.0
	var i := inp()
	i.shoot = true
	i.ax = 1
	i.ay = 0
	steps(s, 1, i)
	ok(f.punch > 0.0 and e.hp == 3.0, "a punch is thrown, not landed yet")
	steps(s, 14, inp())
	ok(e.hp < 3.0 or not s.enemies.has(e), "the punch lands 0.108 s in")

func test_shotgun() -> void:
	var s := sim_with_player()
	s.start_run("classic")
	var f: FT.Fighter = s.players[0]
	s.give_weapon(f, "shotgun")
	s.breather = 999.0
	var i := inp()
	i.shoot = true
	i.ax = 1
	i.ay = 0
	steps(s, 1, i)
	ok(s.bullets.size() == 5, "the shotgun fires five pellets")
	steps(s, 120 * 13)
	ok(f.weapon == "spud", "the shotgun runs out after 12 s in a run (back to %s)" % f.weapon)

func test_launcher() -> void:
	var s := sim_with_player(300, 300)
	s.start_run("classic")
	s.breather = 999.0
	var f: FT.Fighter = s.players[0]
	s.give_weapon(f, "launcher")
	var e := s.new_enemy(2, 500, 300)
	e.spawn = 0.0
	var i := inp()
	i.shoot = true
	i.ax = 200
	i.ay = 0
	steps(s, 1, i)
	ok(s.rockets.size() == 1 and f.rockets == 2, "a rocket is fired")
	steps(s, 100)
	ok(not s.enemies.has(e), "the blast kills a brute on the ring")
	ok(f.kills == 1, "a rocket kill counts")
	steps(s, 120 * 3, i)
	ok(f.rockets == 0, "three rockets")
	steps(s, 120)
	ok(f.weapon != "launcher", "the empty launcher is put away")

func test_run_waves() -> void:
	var s := sim_with_player()
	s.start_run("classic")
	ok(s.plants.size() == 3, "three potatoes growing at the start")
	steps(s, int(2.2 * 120) + 2)
	ok(s.wave == 1, "wave 1 starts after the 2.2 s breather")
	steps(s, int(0.45 * 120 * 6) + 10)
	ok(s.enemies.size() == 6 and s.pending == 0, "six enemies spawned 0.45 s apart (%d)" % s.enemies.size())

func test_batter() -> void:
	var s := sim_with_player(430, 300)
	s.start_run("classic")
	s.breather = 999.0
	var f: FT.Fighter = s.players[0]
	f.grace = 0.0
	var e := s.new_enemy(3, 470, 300)
	e.spawn = 0.0
	var hp0 := f.hp
	var wound_up := false
	for k in 120:
		s.step([inp()])
		if e.st == EnemySim.WINDUP:
			wound_up = true
	ok(wound_up, "the batter winds up close by")
	ok(f.hp == hp0 - 2.0, "the swing takes two hearts (%s)" % f.hp)

func test_brute_shrapnel() -> void:
	var s := sim_with_player(100, 100)
	s.start_run("classic")
	s.breather = 999.0
	var e := s.new_enemy(2, 600, 300)
	e.spawn = 0.0
	s.kill_enemy(e, 1, 0, false, 0, 1.0, true)
	ok(s.shards.size() == 8, "a brute bursts into 8 shards")

func test_janitor() -> void:
	var s := sim_with_player(200, 400)
	s.start_run("classic")
	s.wave = 1
	s.breather = 2.0
	ok(s.slot.broken, "the machine starts broken in a run")
	var live := false
	for k in 120 * 20:
		s.step([inp()])
		if not s.slot.broken:
			live = true
			break
	ok(live, "Gary fixes the machine")
	ok(s.sign == "floor", "he threw the sign down")

func test_game_over() -> void:
	var s := sim_with_player(430, 300)
	s.start_run("classic")
	var f: FT.Fighter = s.players[0]
	s.hurt_player(f, 10, 0, 1, 0)
	ok(not f.alive and s.over, "everyone down: game over")

func test_protect() -> void:
	var s := sim_with_player(430, 300)
	s.players[0].ch = "juicy"
	s.start_run("protect")
	ok(s.goth != null and s.goth.hp == 10.0, "Protect: Gothica is in the run with 10 hp")
	var g := s.goth
	s.players[0].x = g.x + 10
	s.players[0].y = g.y
	var i := inp()
	i.use = true
	s.step([i])
	ok(g.carrier == 0, "E picks her up")
	steps(s, 120 * 5)
	ok(g.carrier == -1, "she wriggles down after 4 s")
	ProtectSim.hurt(s, 20, 0, 1)
	ok(s.over and s.goth_down, "her down ends the run")

func test_coins() -> void:
	var s := sim_with_player(430, 300)
	var f: FT.Fighter = s.players[0]
	var c0 := f.coins
	s._coin(470, 300, 0, 0, 6, 0)
	steps(s, 60)
	ok(f.coins == c0 + 1, "a note drifts in and is picked up")
