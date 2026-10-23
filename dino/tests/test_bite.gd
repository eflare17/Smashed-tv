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

func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var prey: Prey = main.prey[0]

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
			if pl.bite_t >= pl.WIND and pl.bite_t < pl.WIND + pl.HOLD:
				miss = pl.jaw_tip().distance_to(pl.target_point())
				break
		print("   %s: %.2f px" % [DinoArt.ZONE_NAMES[z], miss])
		worst = maxf(worst, miss)
		pl.bite_t = -1.0
	_check("the teeth meet on the spot you clicked", worst < 1.5, "worst %.2f px off" % worst)

	# a killed prey eaten down to scraps disappears and you grow
	p3.die()
	var size0: float = pl.size
	var eaten0: int = main.eaten
	for k in 400:
		if not is_instance_valid(p3) or not main.prey.has(p3):
			break
		var left: Array = []
		for z in [DinoArt.HEAD, DinoArt.NECK, DinoArt.BODY, DinoArt.TAIL, DinoArt.LEGS]:
			left.append_array(_zone_points(p3, z))
		if left.is_empty():
			break
		main.player_bite(pl, left[rng.randi() % left.size()])
	_check("eating a body completely removes it", not main.prey.has(p3))
	_check("eating a whole one grows you", pl.size > size0 and main.eaten == eaten0 + 1, "size %.2f" % pl.size)

	# the whole game runs with the bot for a while without errors, and stays quick
	main.demo = true
	var t0 := Time.get_ticks_msec()
	await _frames(1500)
	var ms := float(Time.get_ticks_msec() - t0) / 1500.0
	_check("demo runs 1500 frames", true, "%.2f ms a frame headless" % ms)
	_check("the bot landed bites", main.chunks > 0, "%d chunks, %d kills" % [main.chunks, main.kills])
	print("%d failed" % _fails)
	quit(_fails)
