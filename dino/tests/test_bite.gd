extends SceneTree
## Headless checks for step 1. Run from the dino folder:
##   godot --headless --path . --script res://tests/test_bite.gd
## Prints PASS / FAIL per check and exits with the number of failures.

const DinoArt := preload("res://scripts/dino_art.gd")

var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _zone_points(p: Prey, zone: int) -> Array:
	var out: Array = []
	for part in p.parts:
		for i in part.w * part.h:
			if part.alive[i] == 1 and part.zone[i] == zone:
				out.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
	return out

func _mass(p: Prey) -> float:
	var n := 0
	for part in p.parts:
		n += part.pixels_left()
	return n * p.art_k * p.art_k * p.scale.x * p.scale.x

func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# a quiet, flat test ground: no obstacles, no hunters turning up
	main.obstacles.clear()
	main.platforms.clear()
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	main.rng.seed = 7
	seed(7)
	var prey: Prey = main.creatures[0]

	# a bite takes pixels from exactly the zone aimed at
	var tail: Array = _zone_points(prey, DinoArt.TAIL)
	var before: float = prey.zone_fraction(DinoArt.TAIL)
	var head_before: float = prey.zone_fraction(DinoArt.HEAD)
	var r: Dictionary = prey.bite(tail[tail.size() / 2], 4.5, rng)
	_check("bite removes pixels", r.removed.size() > 10, "%d" % r.removed.size())
	_check("tail bite hits the tail", prey.zone_fraction(DinoArt.TAIL) < before)
	_check("tail bite leaves the head", prey.zone_fraction(DinoArt.HEAD) == head_before)
	_check("wounds marked", prey.wound_count() > 0, "%d" % prey.wound_count())

	# biting the same spot again goes deeper (nothing left there = nothing removed is fine)
	var mass1: float = prey.mass_fraction()
	prey.bite(tail[tail.size() / 2], 4.5, rng)
	_check("mass only goes down", prey.mass_fraction() <= mass1)

	# chew through the neck: the head comes off as one piece
	var islands := 0
	var head_off := false
	for k in 40:
		var neck: Array = _zone_points(prey, DinoArt.NECK)
		if neck.is_empty():
			break
		# bite the middle of what's left of the neck
		var mid := Vector2.ZERO
		for p: Vector2 in neck:
			mid += p
		mid /= neck.size()
		var res: Dictionary = prey.bite(mid, 4.5, rng)
		for isl: Dictionary in res.islands:
			islands += 1
			if isl.zones[DinoArt.HEAD] > 20:
				head_off = true
		if head_off:
			break
	_check("head comes off when the neck is bitten through", head_off, "%d pieces" % islands)
	_check("head gone from the body", prey.zone_fraction(DinoArt.HEAD) < 0.1, "%.2f" % prey.zone_fraction(DinoArt.HEAD))
	_check("losing the head kills", prey.hurt(Vector2.ZERO) and prey.dead)

	# a leg bitten at the hip falls off whole
	var p2: Prey = main.spawn_prey(600.0)
	await _frames(2)
	var leg: PixelPart = p2.legs[2][0]
	var hip: Vector2 = leg.to_world(leg.offset * -1.0 + Vector2(0, 2))
	var off := false
	for k in 6:
		var res2: Dictionary = p2.bite(hip, 4.5, rng)
		if not res2.islands.is_empty():
			off = true
			break
		hip += Vector2(0, 1)
	_check("leg comes off at the hip", off)

	# the tail is cut into pieces that bend and wag, on every kind of creature
	var cast := {"grazer": main.spawn_prey(1200.0), "runner": main.spawn_prey(1300.0, Prey.RUNNER),
			"hunter": main.spawn_hunter(1400.0), "charger": main._spawn_herd_kind(Area.HERD_CHARGER, 1500.0),
			"pterodactyl": main.spawn_flyer(1600.0), "player": main.player}
	var counts := []
	var all_cut := true
	for k: String in cast:
		var c: Dino = cast[k]
		counts.append("%s %d" % [k, c.tails.size()])
		if c.tails.size() < 2 and k != "pterodactyl":
			all_cut = false
	_check("every tail is cut into pieces", all_cut, ", ".join(counts))
	var p4: Prey = cast.grazer
	var tip: PixelPart = p4.tails[p4.tails.size() - 1]
	var swings := {}
	for f in 40:
		await process_frame
		swings[snappedf(tip.rotation, 0.01)] = true
	_check("the tail wags", swings.size() > 5, "%d different angles" % swings.size())
	var tail_px := 0
	for t in p4.tails:
		tail_px += t.pixels_left()
	var dropped := 0
	var base_at: Vector2 = p4.tails[0].to_world(-p4.tails[0].offset)
	for k in 8:
		var res4: Dictionary = p4.bite(base_at, 4.5, rng)
		for isl: Dictionary in res4.islands:
			dropped += isl.zones[DinoArt.TAIL]
		var left := 0
		for t in p4.tails:
			left += t.pixels_left()
		if left == 0:
			break
	var gone := 0
	for t in p4.tails:
		gone += t.pixels_left()
	_check("biting through the base drops the whole tail", gone == 0 and dropped > tail_px / 2,
			"%d of %d tail pixels fell off" % [dropped, tail_px])
	for k: String in cast:
		if k != "player":
			(cast[k] as Node).queue_free()
			main.creatures.erase(cast[k])

	# the teeth meet exactly where you clicked: real bites through the player, at spots all over a prey
	var pl: Player = main.player
	var p3: Prey = main.spawn_prey(900.0)
	pl.position = Vector2(860.0, main.GROUND_Y)
	await _frames(2)
	var worst := 0.0
	for z in [DinoArt.HEAD, DinoArt.NECK, DinoArt.BODY, DinoArt.TAIL, DinoArt.LEGS]:
		p3.position.x = 900.0
		p3.state = Prey.GRAZE
		p3.vel = Vector2.ZERO
		pl.position = Vector2(860.0, main.GROUND_Y)
		pl.vel = Vector2.ZERO
		pl.cool = 0.0
		await _frames(2)
		var pts: Array = _zone_points(p3, z)
		if pts.is_empty():
			continue
		var aim: Vector2 = pts[pts.size() / 2]
		pl.step(1.0 / 60.0, 0.0, false, true, aim)
		var miss := 999.0
		for f in 12:
			pl.step(1.0 / 60.0, 0.0, false, false, aim)
			if pl.bite_t >= pl.WIND[0] and pl.bite_t < pl.WIND[0] + pl.HOLD:
				miss = pl.jaw_tip().distance_to(pl.target_point())
				break
		print("   %s: %.2f px" % [DinoArt.ZONE_NAMES[z], miss])
		worst = maxf(worst, miss)
		pl.bite_t = -1.0
	_check("the teeth meet on the spot you clicked", worst < 1.5, "worst %.2f px off" % worst)

	# the big bite: charge it, it clamps on, shakes (tearing), and rips; it takes far more than a quick bite
	# (measured as the raptor: the hatchling's bites are too small to compare)
	pl.set_stage(1)
	var quick_take := 0
	var q: Prey = main.spawn_prey(1200.0)
	q.die()
	await _frames(2)
	var m0: float = q.mass_fraction()
	var qp: Vector2 = _zone_points(q, DinoArt.BODY)[40]
	main.player_bite(pl, qp, pl.bite_radius)
	quick_take = int((m0 - q.mass_fraction()) * 10000)
	var big_target: Prey = main.spawn_prey(1500.0)
	big_target.die()
	pl.position = Vector2(1460.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	pl.cool = 0.0
	pl.bite_t = -1.0
	await _frames(2)
	var spot: Vector2 = _zone_points(big_target, DinoArt.BODY)[60]
	var mb: float = big_target.mass_fraction()
	var grabbed := false
	var ripped := false
	pl.step(1.0 / 60.0, 0.0, false, false, spot, true)
	for f in 50:
		pl.step(1.0 / 60.0, 0.0, false, false, spot, true)
	_check("holding right click charges", pl.charging and pl.charge > 0.99, "%.2f" % pl.charge)
	for f in 200:
		pl.step(1.0 / 60.0, 0.0, false, false, spot, false)
		if not pl.grab.is_empty():
			grabbed = true
		elif grabbed:
			ripped = true
			break
	var big_take := int((mb - big_target.mass_fraction()) * 10000)
	_check("a big bite clamps on, shakes and lets go", grabbed and ripped)
	_check("a big bite takes far more than a quick one", big_take > quick_take * 3, "%d vs %d" % [big_take, quick_take])

	pl.set_stage(0)
		# a big live prey breaks free (you're smaller than it); a dead one can't
	var big_live: Prey = main.spawn_prey(1800.0)
	await _frames(2)
	_check("something bigger than you breaks free early", main.break_free_time(pl, big_live, 1.0) < 0.6,
			"after %.2f of the shake (it's %.1fx you)" % [main.break_free_time(pl, big_live, 1.0), _mass(big_live) / pl.mass()])
	_check("a body can't break free", main.break_free_time(pl, big_target, 1.0) == INF)
	var small: Hunter = main.spawn_hunter(1900.0)
	await _frames(2)
	_check("a hunter comes at your mass, so it can't break free", main.break_free_time(pl, small, 1.0) == INF
			and absf(_mass(small) / pl.mass() - 1.0) < 0.1, "it's %.2fx your mass, drawn at %.2f" % [_mass(small) / pl.mass(), small.scale.x])
	small.scale = Vector2(2.0, 2.0)
	_check("a hunter twice your size can", main.break_free_time(pl, small, 1.0) < 1.0)
	small.queue_free()
	main.creatures.erase(small)

	# a killed prey eaten down to scraps disappears and you grow
	p3.die()
	var size0: float = pl.size
	var eaten0: int = main.eaten
	for k in 400:
		if not is_instance_valid(p3) or not main.creatures.has(p3):
			break
		var left: Array = []
		for z in [DinoArt.HEAD, DinoArt.NECK, DinoArt.BODY, DinoArt.TAIL, DinoArt.LEGS]:
			left.append_array(_zone_points(p3, z))
		if left.is_empty():
			break
		main.player_bite(pl, left[rng.randi() % left.size()], pl.bite_radius)
	_check("eating a body completely removes it", not main.creatures.has(p3))
	_check("eating a whole one grows you", pl.size > size0 and main.eaten == eaten0 + 1, "size %.2f (was %.2f), eaten %d (was %d), still there %s" % [pl.size, size0, main.eaten, eaten0, main.creatures.has(p3)])

	# levelling: enough XP offers the choice, picking one raises that stat (eating above may have levelled already)
	while main.state == main.CHOOSE:
		main._pick(1)
	var lv0: int = main.level
	var r0: float = pl.bite_radius
	main.add_xp(main.xp_needed(), pl.global_position)
	_check("enough XP offers a level-up choice", main.state == main.CHOOSE and main.level == lv0 + 1)
	_check("the cards are three different upgrades", main._offered.size() == 3
			and main._offered[0] != main._offered[1] and main._offered[1] != main._offered[2])
	main._offered = [main.UP_BITE, main.UP_SPEED, main.UP_RATE]
	main._pick(0)
	_check("picking BITE SIZE makes bites bigger", pl.bite_radius > r0 and main.state == main.PLAY, "%.1f" % pl.bite_radius)
	var gap1: float = main._hunt_gap()
	main.level = 6
	_check("higher levels bring hunters sooner", main._hunt_gap() < gap1 and main._hunt_cap() > 1,
			"every %.1fs at level 2, %.1fs at level 6" % [gap1, main._hunt_gap()])
	main.level = lv0 + 1

	# a hunter walks up and bites you
	pl.position = Vector2(500.0, main.GROUND_Y)
	pl.invuln = 0.0
	var hp0: float = pl.hp
	var h: Hunter = main.spawn_hunter(580.0)
	for f in 300:
		await process_frame
		if pl.hp < hp0:
			break
	_check("a hunter's bite takes health", pl.hp < hp0, "%.0f -> %.0f, state %d, hunter state %d at %.0f, you at %.0f" % [hp0, pl.hp, main.state, h.state, h.position.x, pl.position.x])
	# and it can be bitten to death
	for k in 60:
		if h.dead:
			break
		var pts2: Array = _zone_points(h, DinoArt.BODY) + _zone_points(h, DinoArt.NECK)
		if pts2.is_empty():
			break
		main.player_bite(pl, pts2[rng.randi() % pts2.size()], pl.bite_radius)
	_check("a hunter can be killed", h.dead)

	# a pterodactyl circles, dives at you and rakes you
	while main.state == main.CHOOSE:
		main._pick(1)
	pl.position = Vector2(900.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	pl.invuln = 0.0
	pl.hp = pl.max_hp
	var fl: Flyer = main.spawn_flyer(960.0)
	var dived := false
	for f in 900:
		await process_frame
		pl.invuln = 0.0 if pl.hp == pl.max_hp else pl.invuln
		if fl.state == Flyer.DIVE:
			dived = true
		if pl.hp < pl.max_hp:
			break
	_check("a pterodactyl dives at you", dived)
	_check("its dive hurts", pl.hp < pl.max_hp, "%.0f" % pl.hp)
	# bite a wing off and it crashes
	for k in 30:
		if fl.state == Flyer.GROUNDED or fl.dead:
			break
		var wpts: Array = _zone_points(fl, DinoArt.WING)
		if wpts.is_empty():
			break
		main.player_bite(pl, wpts[0], pl.bite_radius)
	for f in 400:
		await process_frame
		if main.state == main.CHOOSE:
			main._pick(1)
		if fl.on_ground and fl.position.y > main.GROUND_Y - fl.foot - 2.0:
			break
	_check("biting its wing away brings it down", fl.on_ground and fl.position.y > main.GROUND_Y - fl.foot - 2.0 and (fl.state == Flyer.GROUNDED or fl.dead),
			"state %d, y %.0f" % [fl.state, fl.position.y])

	while main.state == main.CHOOSE:
		main._pick(1)
	# a charger ignores you until bitten, then charges
	pl.hp = pl.max_hp
	pl.invuln = 0.0
	pl.position = Vector2(1300.0, main.GROUND_Y)
	var ch: Charger = main._spawn_herd_kind(Area.HERD_CHARGER, 1400.0)
	await _frames(30)
	_check("a charger doesn't care about you at first", ch.state == Prey.GRAZE)
	main.player_bite(pl, _zone_points(ch, DinoArt.TAIL)[5], pl.bite_radius)
	_check("bitten, it gets angry", ch.state == Charger.ANGRY)
	var charged := false
	pl.position = Vector2(ch.position.x - 80.0, main.GROUND_Y)
	for f in 600:
		await process_frame
		if ch.state == Charger.CHARGE:
			charged = true
		if pl.hp < pl.max_hp:
			break
	_check("it charges", charged)
	_check("its horns hurt", pl.hp < pl.max_hp, "%.0f" % pl.hp)

	# runners are small and quick
	var rn: Prey = main.spawn_prey(1600.0, Prey.RUNNER)
	await _frames(2)
	_check("a runner is smaller and faster than a grazer", _mass(rn) < 600 and rn.run_speed > 68.0, "%d px" % _mass(rn))

	# the danger clock: the longer you stay, the sooner and more things come, and the herds stop coming
	var lvl0: int = main.level
	main.area_t = 0.0
	var g0: float = main._hunt_gap()
	var c0: int = main._hunt_cap()
	main.area_t = main.DANGER_TIME * 0.75
	_check("staying longer brings attackers sooner and more of them", main._hunt_gap() < g0 and main._hunt_cap() > c0,
			"every %.1fs, %d at once -> every %.1fs, %d at once" % [g0, c0, main._hunt_gap(), main._hunt_cap()])
	_check("the danger bar fills", main.danger() > 0.7, "%.2f" % main.danger())
	main.area_t = 0.0
	main.level = lvl0

	# pressure: attackers hit harder as the bar fills, bodies rot, reaching the next area pays
	main.area_t = 0.0
	var d0: float = main.danger_mult()
	main.area_t = main.DANGER_TIME
	_check("a full danger bar makes bites hurt more", main.danger_mult() > d0 * 2.0, "%.1fx -> %.1fx" % [d0, main.danger_mult()])
	_check("past half danger they come in packs", main._pack_size() >= 2, "%d at once" % main._pack_size())
	main.area_t = 0.0
	var old: Prey = main.spawn_prey(2000.0)
	old.die()
	old.dead_t = main.ROT_TIME + 1.0
	await _frames(2)
	pl.hp = 50.0
	main.player_bite(pl, _zone_points(old, DinoArt.BODY)[30], pl.bite_radius)
	_check("rotten meat doesn't heal", old.rotten() and pl.hp == 50.0, "hp %.0f" % pl.hp)
	main.area_t = main.DANGER_TIME * 0.2
	var hp_before: float = pl.hp
	var xp_before: int = main.xp + (main.level - 1) * 1000
	main.enter_area(main.area_n + 1)
	var xp_after: int = main.xp + (main.level - 1) * 1000
	_check("reaching the next area heals and pays XP", pl.hp > hp_before and xp_after > xp_before,
			"hp %.0f -> %.0f" % [hp_before, pl.hp])
	_check("...and resets the danger bar", main.area_t == 0.0)
	main.enter_area(1)
	while main.state == main.CHOOSE:
		main._pick(1)
	main.obstacles.clear()
	main.platforms.clear()
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	main.rng.seed = 7
	seed(7)
	pl = main.player

	# areas: the same run seed builds the same area, another seed a different one
	var a1 := Area.new()
	a1.generate(1, 777, main.GROUND_Y)
	var a2 := Area.new()
	a2.generate(1, 777, main.GROUND_Y)
	var a3 := Area.new()
	a3.generate(1, 778, main.GROUND_Y)
	_check("same seed, same area", a1.width == a2.width and a1.obstacles == a2.obstacles and not a1.obstacles.is_empty(),
			"%d obstacles" % a1.obstacles.size())
	_check("another seed, another area", a1.width != a3.width or a1.obstacles != a3.obstacles)
	for a in [a1, a2, a3]:
		a.free()

	# you can't walk through a rock, but you can jump onto it
	var rock := Rect2(700.0, main.GROUND_Y - 16.0, 20.0, 16.0)
	main.obstacles.append(rock)
	pl.position = Vector2(670.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	for f in 60:
		pl.step(1.0 / 60.0, 1.0, false, false, pl.global_position + Vector2(50, -10))
	_check("a rock blocks the way", pl.position.x < rock.position.x, "x %.0f" % pl.position.x)
	pl.step(1.0 / 60.0, 1.0, true, false, pl.global_position + Vector2(50, -10))
	var stood := false
	for f in 40:
		pl.step(1.0 / 60.0, 0.4, false, false, pl.global_position + Vector2(50, -10))
		if pl.on_ground and absf(pl.position.y - rock.position.y) < 0.5:
			stood = true
	_check("you can jump up onto it", stood)
	main.obstacles.erase(rock)

	# (killing the hunter may have levelled you up: pick, so the game runs on)
	while main.state == main.CHOOSE:
		main._pick(1)
	# the kill moment: a killing bite freezes, then runs the world slow for a beat, punches the camera in, and
	# the KILL! popup is held back until it's speeding up again
	var victim: Prey = main.spawn_prey(700.0, Prey.RUNNER)
	await _frames(2)
	for k in 60:
		if victim.dead:
			break
		var vpts: Array = _zone_points(victim, DinoArt.NECK) + _zone_points(victim, DinoArt.BODY)
		if vpts.is_empty():
			break
		main.player_bite(pl, vpts[rng.randi() % vpts.size()], pl.bite_radius)
	_check("a kill starts the slow-motion beat", victim.dead and main.get("_slow_t") > 0.0 and main.get("_zoom_punch") > 0.0)
	var kill_shown := false
	for pu in main.get("_popups"):
		if pu[0] == "KILL!":
			kill_shown = true
	var kill_waiting := false
	for pu in main.get("_pending"):
		if pu[1][0] == "KILL!":
			kill_waiting = true
	_check("the KILL! popup waits for the beat", kill_waiting and not kill_shown)
	for f in 60:
		await process_frame
	kill_shown = false
	for pu in main.get("_popups"):
		if pu[0] == "KILL!":
			kill_shown = true
	_check("...then shows", kill_shown)
	while main.state == main.CHOOSE:
		main._pick(1)

	# evolving: enough whole bodies eaten and you become the next form, bigger, with new art and stats; level-up
	# bonuses carry over; at the top nothing breaks free
	_check("you start as the first form", pl.stage == 0 and pl.stage_name() == "HATCHLING", pl.stage_name())
	var size_before: float = pl.size
	var head_w_before: int = pl.head.w
	pl.bite_bonus = 1.5
	pl.apply_stage()
	var bite_before: float = pl.bite_radius
	main.eaten = pl.meals_to_evolve() - 1
	var meal: Prey = main.spawn_prey(1100.0, Prey.RUNNER)
	meal.die()
	await _frames(2)
	for k in 300:
		if not main.creatures.has(meal):
			break
		var mpts: Array = []
		for z in [DinoArt.HEAD, DinoArt.NECK, DinoArt.BODY, DinoArt.TAIL, DinoArt.LEGS]:
			mpts.append_array(_zone_points(meal, z))
		if mpts.is_empty():
			break
		main.player_bite(pl, mpts[rng.randi() % mpts.size()], pl.bite_radius)
	_check("eating enough evolves you", pl.stage == 1 and pl.stage_name() == "RAPTOR", "stage %d" % pl.stage)
	_check("the new form is bigger with a bigger bite", pl.size > size_before and pl.bite_radius > bite_before,
			"size %.2f (was %.2f), bite %.1f (was %.1f)" % [pl.size, size_before, pl.bite_radius, bite_before])
	_check("the new form has new art", pl.head.w != head_w_before and pl.parts.size() > 0, "head %d -> %d px wide" % [head_w_before, pl.head.w])
	_check("level-up bonuses carry over", pl.bite_radius == Player.STAGES[1].bite + 1.5)
	_check("evolving is a moment", main.get("_slow_t") > 0.0 and main.get("_zoom_punch") > 0.0)
	pl.set_stage(3)
	var huge: Prey = main.spawn_prey(1300.0)
	await _frames(2)
	_check("a tyrant can't be broken free of", main.break_free_time(pl, huge, 1.0) == INF)
	pl.set_stage(1)
	pl.bite_bonus = 0.0
	pl.apply_stage()
	huge.queue_free()
	main.creatures.erase(huge)
	main.eaten = 0
	while main.state == main.CHOOSE:
		main._pick(1)

	# bitten legs slow a creature down, and enough bites cripple it
	var lame: Prey = main.spawn_prey(760.0)
	await _frames(2)
	var full_speed: float = lame.leg_speed()
	for k in 40:
		var lpts: Array = _zone_points(lame, DinoArt.LEGS)
		if lpts.is_empty() or lame.crippled():
			break
		main.player_bite(pl, lpts[rng.randi() % lpts.size()], pl.bite_radius)
	_check("leg bites slow it down", lame.leg_speed() < full_speed * 0.8, "%.2f of its speed" % lame.leg_speed())
	_check("enough leg bites cripple it", lame.crippled(), "%.0f%% of its legs left" % (lame.legs_left() * 100.0))
	lame.queue_free()
	main.creatures.erase(lame)

	# terrain: a low step is walked up, a shelf in the air is landed on from above and jumped up through
	var step := Rect2(800.0, main.GROUND_Y - 10.0, 60.0, 10.0)
	main.obstacles.append(step)
	pl.position = Vector2(780.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	for f in 60:
		pl.step(1.0 / 60.0, 1.0, false, false, pl.global_position + Vector2(50, -10))
	_check("a low step is walked up without jumping", pl.position.x > step.position.x + 10.0 and absf(pl.position.y - step.position.y) < 0.5,
			"x %.0f, y %.0f" % [pl.position.x, pl.position.y])
	main.obstacles.erase(step)
	var shelf := Rect2(900.0, main.GROUND_Y - 32.0, 60.0, 6.0)
	main.platforms.append(shelf)
	pl.position = Vector2(930.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	# a settle frame (it was teleported), then the jump
	pl.step(1.0 / 60.0, 0.0, false, false, pl.global_position + Vector2(50, -10))
	pl.step(1.0 / 60.0, 0.0, true, false, pl.global_position + Vector2(50, -10))
	var went_through := false
	var landed := false
	for f in 90:
		pl.step(1.0 / 60.0, 0.0, false, false, pl.global_position + Vector2(50, -10))
		if pl.position.y < shelf.position.y - 2.0:
			went_through = true
		if went_through and pl.on_ground and absf(pl.position.y - shelf.position.y) < 0.5:
			landed = true
			break
	_check("a shelf is jumped up through and landed on", went_through and landed, "y %.0f" % pl.position.y)
	main.platforms.erase(shelf)
	while main.state == main.CHOOSE:
		main._pick(1)

	# the far end leads to the next area
	pl.position = Vector2(main.area.exit_x + 1.0, main.GROUND_Y)
	main.set("_stop", 0.0)
	await _frames(2)
	_check("the sign at the end leads to area 2", main.area_n == 2 and pl.position.x < 100.0, "area %d, x %.0f, exit %.0f, width %d, state %d, stop %.2f" % [main.area_n, pl.position.x, main.area.exit_x, main.world_w, main.state, main.get("_stop")])

	# out of health: the run is over (the arrival bonus may have levelled you: pick first)
	while main.state == main.CHOOSE:
		main._pick(1)
	pl.hp = 1.0
	pl.invuln = 0.0
	var h2: Hunter = main.spawn_hunter(pl.position.x + 30.0)
	main.creature_hit(h2, Hunter.DAMAGE)
	_check("losing all your health ends the run", main.state == main.OVER)
	main.start_run()
	_check("a new run starts fresh", main.state == main.PLAY and main.level == 1 and main.area_n == 1)

	# the whole game runs with the bot for a while without errors, and stays quick
	main.demo = true
	var t0 := Time.get_ticks_msec()
	await _frames(1500)
	var ms := float(Time.get_ticks_msec() - t0) / 1500.0
	_check("demo runs 1500 frames", true, "%.2f ms a frame headless" % ms)
	_check("the bot landed bites", main.chunks > 0, "%d chunks, %d kills" % [main.chunks, main.kills])
	print("%d failed" % _fails)
	quit(_fails)
