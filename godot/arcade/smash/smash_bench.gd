extends Node
## Smash arcade bench + smoke test. Runs the real smash.tscn with no input, god mode on and the waves off:
##  1. smoke: shoots at a few grunts and checks they die, score, gib and splat; checks a debug +50 spawn;
##  2. stress: for each grunt count, fills the arena, lets them pile onto the player (the worst case for the
##     crowd push-apart) and prints the average / worst simulation time per frame.
## godot --headless --path godot --fixed-fps 60 res://arcade/smash/smash_bench.tscn   (exit code 1 on a fail)

const COUNTS := [100, 250, 500, 750, 1000, 1500, 2000, 3000, 4000]

var game

func _ready() -> void:
	game = load("res://arcade/smash/smash.tscn").instantiate()
	game.waves_enabled = false
	game.input_enabled = false
	add_child(game)
	await _frames(2)
	var ok := await _smoke()
	await _stress()
	print("SMASH BENCH ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(cond: bool, what: String) -> bool:
	print("SMASH CHECK %s %s" % ["ok  " if cond else "FAIL", what])
	return cond

func _smoke() -> bool:
	var ok := true
	game.reset_game()
	game.god = true
	for i in 10:
		game.horde.spawn_inside(Vector2(-4.0 + i * 0.9, -6.0), 0.0)
	for i in 10:
		game.shots.fire(Vector2(-4.0 + i * 0.9, -1.0), Vector2(0, -1))
	await _frames(30)
	ok = _check(game.horde.count == 0, "bullets killed all 10 grunts (left %d)" % game.horde.count) and ok
	ok = _check(game.score == 1000, "score 1000 (got %d)" % game.score) and ok
	ok = _check(game.gibs.chunks > 0 and game.gibs.splats == 10,
			"chunks %d, splats %d" % [game.gibs.chunks, game.gibs.splats]) and ok
	await _frames(int(60 * 6.5))
	ok = _check(game.gibs.chunks == 0 and game.gibs.splats == 0, "chunks and splats faded out") and ok
	game.spawn_debug(50)
	ok = _check(game.horde.count == 50, "debug spawn +50") and ok
	await _frames(60 * 6)
	var inside := 0
	for i in game.horde.count:
		inside += 1 if game.horde.door[i] == game.horde.INSIDE else 0
	ok = _check(inside == 50, "all 50 came in through the doors (%d inside)" % inside) and ok
	# not god: a grunt touching the player costs a life
	game.god = false
	game._invuln_t = 0.0
	await _frames(30)
	ok = _check(game.lives == game.START_LIVES - 1, "touched: lives %d" % game.lives) and ok
	game.set_first_person(true)
	await _frames(2)
	ok = _check(game.fp_cam.current, "first person camera") and ok
	game.set_first_person(false)
	return ok

func _stress() -> void:
	print("SMASH STRESS  grunts | avg sim ms | worst ms   (crowd piled on the player, 60 fps = 16.7 ms budget)")
	for n in COUNTS:
		game.reset_game()
		game.god = true
		for i in n:
			game.horde.spawn_inside(Vector2(randf_range(-game.HALF, game.HALF), randf_range(-game.HALF, game.HALF)) * 0.95, randf_range(2.5, 3.5))
		await _frames(60 * 4)
		var total := 0
		var worst := 0
		for i in 120:
			await get_tree().process_frame
			total += game.sim_usec
			worst = maxi(worst, game.sim_usec)
		print("SMASH STRESS  %6d | %10.2f | %8.2f" % [n, total / 120.0 / 1000.0, worst / 1000.0])
