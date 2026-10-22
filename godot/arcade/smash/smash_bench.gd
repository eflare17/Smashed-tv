extends Node
## Smash arcade bench + smoke test. Runs the real smash.tscn with no input and the high-score file untouched:
##  1. smoke: shooting, gibs, the debug spawn, getting hit, first person, power-ups (spread, rockets and their
##     blast, shield, speed), the brute, the exit door and the next room, the host, the high-score table, the
##     attract demo, and game over into the initials entry;
##  2. stress: for each grunt count, fills the arena, lets them pile onto the player (the worst case for the
##     crowd push-apart) and prints the average / worst simulation time per frame.
## godot --headless --path godot --fixed-fps 60 res://arcade/smash/smash_bench.tscn   (exit code 1 on a fail)

const COUNTS := [100, 250, 500, 750, 1000, 1500, 2000, 3000, 4000]

var game
var ok := true

func _ready() -> void:
	game = load("res://arcade/smash/smash.tscn").instantiate()
	game.input_enabled = false
	game.save_scores = false
	add_child(game)
	if not game.has_method("start_game"):
		print("SMASH BENCH FAIL: the game script didn't load")
		get_tree().quit(1)
		return
	await _frames(2)
	await _smoke()
	await _stress()
	print("SMASH BENCH ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(cond: bool, what: String) -> void:
	print("SMASH CHECK %s %s" % ["ok  " if cond else "FAIL", what])
	ok = ok and cond

## A fresh run in PLAY with no waves, god mode, the player in the middle.
func _fresh() -> void:
	game.waves_enabled = false
	game.start_game()
	game.god = true
	await _frames(1)

func _smoke() -> void:
	# the attract demo plays itself: the bot should be killing grunts
	game.waves_enabled = false
	game.start_attract(false)
	for i in 12:
		game.horde.spawn_inside(Vector2(-6.0 + i, -7.0), 1.0)
	await _frames(240)
	_check(game.state == game.State.ATTRACT and game.horde.count < 12, "attract demo bot shoots (%d of 12 left)" % game.horde.count)

	await _fresh()
	_check(game.state == game.State.PLAY and game.room == 1, "start game")
	for i in 10:
		game.horde.spawn_inside(Vector2(-4.0 + i * 0.9, -6.0), 0.0)
	for i in 10:
		game.shots.fire(Vector2(-4.0 + i * 0.9, -1.0), Vector2(0, -1))
	await _frames(30)
	_check(game.horde.count == 0, "bullets killed all 10 grunts (left %d)" % game.horde.count)
	_check(game.score == 1000, "score 1000 (got %d)" % game.score)
	_check(game.gibs.chunks > 0 and game.gibs.splats == 10, "chunks %d, splats %d" % [game.gibs.chunks, game.gibs.splats])
	await _frames(int(60 * 6.5))
	_check(game.gibs.chunks == 0 and game.gibs.splats == 0, "chunks and splats faded out")
	game.spawn_debug(50)
	_check(game.horde.count == 50, "debug spawn +50")
	await _frames(60 * 6)
	var inside := 0
	for i in game.horde.count:
		inside += 1 if game.horde.door[i] == game.horde.INSIDE else 0
	_check(inside == 50, "all 50 came in through the doors (%d inside)" % inside)
	game.god = false
	game._invuln_t = 0.0
	await _frames(30)
	_check(game.lives == game.START_LIVES - 1, "touched: lives %d" % game.lives)
	game.set_first_person(true)
	await _frames(2)
	_check(game.fp_cam.current, "first person camera")
	game.set_first_person(false)

	# power-ups
	await _fresh()
	game.pickups.spawn(game.player_pos, game.SmashPickups.SPREAD)
	await _frames(2)
	_check(game.weapon == 1 and game.score == game.SCORE_PICKUP, "spread pickup (weapon %d)" % game.weapon)
	_check(game.hud.host.busy(), "host pops down on a pickup")
	# one volley through the player's own fire code, aimed by the demo bot at a lone grunt
	game.shots.clear()
	game.horde.spawn_inside(Vector2(0, -6), 0.0)
	game.state = game.State.ATTRACT
	game._fire_t = 0.0
	game._update_player(1.0 / 60.0)
	game.state = game.State.PLAY
	_check(game.shots.count == 5, "spread fires 5 (%d)" % game.shots.count)

	await _fresh()
	for i in 12:
		game.horde.spawn_inside(Vector2(randf_range(-1.2, 1.2), -6.0 + randf_range(-0.8, 0.8)), 0.0)
	game.brutes.spawn_inside(Vector2(0.0, -6.0), 0.0)
	game.shots.fire(Vector2(0, -2), Vector2(0, -1), game.SmashShots.ROCKET)
	await _frames(40)
	_check(game.horde.count == 0, "rocket blast cleared the grunts (left %d)" % game.horde.count)
	_check(game.brutes.count == 1 and game.brutes.hp[0] == game.SmashBrutes.HP - 4, "blast hurt the brute (hp %d)" % (game.brutes.hp[0] if game.brutes.count else -1))
	var s0: int = game.score
	for i in 2:
		game.shots.fire(Vector2(0, -3), Vector2(0, -1))
		await _frames(12)
	_check(game.brutes.count == 0 and game.score - s0 == game.SCORE_BRUTE, "brute killed by 2 more bullets (+%d)" % (game.score - s0))

	await _fresh()
	game.pickups.spawn(game.player_pos, game.SmashPickups.SHIELD)
	await _frames(2)
	game.god = false
	game._invuln_t = 0.0
	for i in 6:
		game.horde.spawn_inside(game.player_pos + Vector2(2.0 + i * 0.7, 0), 3.0)
	await _frames(90)
	_check(game.lives == game.START_LIVES and game.horde.count == 0, "shield pops grunts, no life lost (lives %d, left %d)" % [game.lives, game.horde.count])
	game.pickups.spawn(game.player_pos, game.SmashPickups.SPEED)
	await _frames(2)
	_check(game.speed_t > 0.0, "speed pickup")

	# room clear -> exit -> next room
	await _fresh()
	game.waves_enabled = true
	game._to_spawn = 0
	game._brutes_to_spawn = 0
	game.wave_in_room = game.WAVES_PER_ROOM
	await _frames(2)
	_check(game.exit_door >= 0, "room clear opens an exit (door %d)" % game.exit_door)
	var out: Vector2 = -game.DOOR_N[game.exit_door]
	var old_floor: Color = game._floor_mat.albedo_color
	game.player_pos = out * (game.HALF - 0.5)
	for i in 30:
		game.player_pos += out * 0.1
		game.player_pos = game._clamp_player(game.player_pos, game.player_pos - out * 0.1)
		await _frames(1)
	await _frames(80)
	_check(game.room == 2 and game.exit_door == -1, "walked out into room %d" % game.room)
	_check(game._floor_mat.albedo_color != old_floor, "room 2 is re-tinted")
	_check(game._brutes_to_spawn == 2, "room 2 sends brutes (%d)" % game._brutes_to_spawn)

	# high scores
	var sc = game.scores
	_check(sc.qualifies(60000) and not sc.qualifies(100), "high score qualifying")
	_check(sc.insert("ZZZ", 60000, 3) == 0 and sc.entries[0][0] == "ZZZ" and sc.entries.size() == 10, "high score insert at the top")

	# game over -> initials
	await _fresh()
	game.god = false
	game.lives = 1
	game.score = 99999
	game._invuln_t = 0.0
	game.waves_enabled = false
	game.horde.spawn_inside(game.player_pos + Vector2(0.4, 0), 0.0)
	await _frames(5)
	_check(game.game_over, "last life lost: game over")
	await _frames(60 * 3 + 10)
	_check(game.state == game.State.NAME, "game over with a high score asks for initials")
	game._name_done()
	_check(game.state == game.State.ATTRACT and game._rank == 0, "initials saved at rank %d" % game._rank)

func _stress() -> void:
	print("SMASH STRESS  grunts | avg sim ms | worst ms   (crowd piled on the player, 60 fps = 16.7 ms budget)")
	for n in COUNTS:
		await _fresh()
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
