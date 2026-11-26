extends Node
## Smash arcade bench + smoke test. Runs the real smash.tscn with no input and the high-score file untouched:
##  1. smoke (EXPECTED checks): shooting, gibs, getting hit, first person, power-ups, brutes, snipers, mines,
##     barrels and chain blasts, Big Tony, prizes, the smart bomb, the wave plans, room bonus and exit, the host,
##     high scores, the attract demo, game over into the initials;
##  2. stress: for each grunt count, fills the arena, lets them pile onto the player (the worst case for the
##     crowd push-apart) and prints the average / worst simulation time per frame.
## godot --headless --path godot --fixed-fps 60 res://arcade/smash/smash_bench.tscn   (exit code 1 on a fail)
## With `-- --balance[=N]` it instead lets the bot play N whole games (autopilot, lives and all; default 4) and
## prints how far each got: the numbers the balance pass in smash_waves.gd was tuned on.

const COUNTS := [100, 250, 500, 750, 1000, 1500, 2000, 3000, 4000]
const EXPECTED := 48
const BALANCE_CAP := 60.0 * 20.0
## The balance runs' bot is handicapped to play more like a person: a reaction time and a bit of aim error.
const BOT_REACTION := 0.2
const BOT_AIM_ERROR := 0.15

var game
var ok := true
var checks := 0

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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--balance"):
			await _balance(int(a.get_slice("=", 1)) if "=" in a else 4)
			get_tree().quit(0)
			return
	await _smoke()
	_check(checks == EXPECTED - 1, "all %d checks ran (%d)" % [EXPECTED, checks + 1])
	await _stress()
	print("SMASH BENCH ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(cond: bool, what: String) -> void:
	checks += 1
	print("SMASH CHECK %s %s" % ["ok  " if cond else "FAIL", what])
	ok = ok and cond

## A fresh run in PLAY with no waves, god mode, the player in the middle.
func _fresh() -> void:
	game.waves_enabled = false
	game.autopilot = false
	game.start_game()
	game.god = true
	await _frames(1)

func _vulnerable() -> void:
	game.god = false
	game._invuln_t = 0.0

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
	_check(game.score >= 1000, "score at least 1000 (got %d)" % game.score)
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
	_vulnerable()
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
	# fired from close by, before the cluster has time to spread out
	game.shots.fire(Vector2(0, -4.3), Vector2(0, -1), game.SmashShots.ROCKET)
	await _frames(40)
	_check(game.horde.count == 0, "rocket blast cleared the grunts (left %d)" % game.horde.count)
	_check(game.brutes.count == 1 and game.brutes.hp[0] == game.SmashBrutes.HP - 4, "blast hurt the brute (hp %d)" % (game.brutes.hp[0] if game.brutes.count else -1))
	var s0: int = game.score
	for i in 2:
		game.shots.fire(Vector2(0, -3), Vector2(0, -1))
		await _frames(12)
	_check(game.brutes.count == 0 and game.score - s0 >= game.SCORE_BRUTE, "brute killed by 2 more bullets (+%d)" % (game.score - s0))

	await _fresh()
	game.pickups.spawn(game.player_pos, game.SmashPickups.SHIELD)
	await _frames(2)
	_vulnerable()
	for i in 6:
		game.horde.spawn_inside(game.player_pos + Vector2(2.0 + i * 0.7, 0), 3.0)
	await _frames(150)
	_check(game.lives == game.START_LIVES and game.horde.count == 0, "shield pops grunts, no life lost (lives %d, left %d)" % [game.lives, game.horde.count])
	game.pickups.spawn(game.player_pos, game.SmashPickups.SPEED)
	await _frames(2)
	_check(game.speed_t > 0.0, "speed pickup")
	game.pickups.spawn(game.player_pos, game.SmashPickups.BOMB)
	await _frames(2)
	_check(game.bombs == game.START_BOMBS + 1, "bomb pickup (bombs %d)" % game.bombs)

	# snipers
	await _fresh()
	game.snipers.spawn_inside(Vector2(0, -7))
	game.snipers.cool[0] = 0.2
	_vulnerable()
	await _frames(100)
	_check(game.lives == game.START_LIVES - 1, "sniper's bullet costs a life (lives %d)" % game.lives)
	await _fresh()
	game.snipers.spawn_inside(Vector2(0, -6))
	game.snipers.cool[0] = 99.0
	for i in 2:
		game.shots.fire(Vector2(0, -2), Vector2(0, -1))
		await _frames(15)
	_check(game.snipers.count == 0 and game.score == game.SCORE_SNIPER, "sniper dies in 2 hits (+%d)" % game.score)
	await _fresh()
	game.snipers.spawn(0, 1.0)
	await _frames(150)
	_check(game.snipers.count == 1 and game.snipers.door[0] == game.SmashSnipers.INSIDE, "sniper walks in and takes a post")

	# mines
	await _fresh()
	game.mines.spawn_inside(Vector2(1.2, 0))
	for i in 5:
		game.horde.spawn_inside(Vector2(-1.0 + i * 0.4, 1.0), 0.0)
	_vulnerable()
	await _frames(70)
	_check(game.mines.count == 0 and game.lives == game.START_LIVES - 1, "mine arms near you and blows (lives %d)" % game.lives)
	await _fresh()
	game.mines.spawn_inside(Vector2(0, -6))
	game.mines.spawn_inside(Vector2(1.5, -6.5))
	game.horde.spawn_inside(Vector2(-1.0, -6.0), 0.0)
	game.shots.fire(Vector2(0, -2), Vector2(0, -1))
	await _frames(25)
	_check(game.mines.count == 0 and game.horde.count == 0, "shot mine chain-sets off the other and kills the grunt")
	_check(game.lives == game.START_LIVES, "a blast far away doesn't hurt you")

	# barrels
	await _fresh()
	game.eshots.fire(Vector2(4, -3), Vector2(0, -1), game.SmashEShots.BARREL)
	game.horde.spawn_inside(Vector2(4.5, -9.0), 0.0)
	await _frames(100)
	_check(game.eshots.count == 0 and game.horde.count == 0, "barrel rolls to the wall and blows up (grunt %d)" % game.horde.count)
	await _fresh()
	game.eshots.fire(Vector2(0, -6), Vector2(0, -1), game.SmashEShots.BARREL)
	game.shots.fire(Vector2(0, -2), Vector2(0, -1))
	await _frames(20)
	_check(game.eshots.count == 0 and game.gibs.booms > 0, "shooting a barrel sets it off")

	# Big Tony
	await _fresh()
	game.spawn_boss(0, 40)
	await _frames(60 * 9)
	_check(game.boss.active and game.boss.state != game.SmashBoss.ENTER, "boss walks in")
	_check(game.boss.attacks > 0, "boss attacks (%d)" % game.boss.attacks)
	game.boss.pos = Vector2(0, -6)
	var before_score: int = game.score
	for i in 60:
		game.shots.fire(game.boss.pos + Vector2(0, 3), Vector2(0, -1))
		game.boss.pos = Vector2(0, -6)
		await _frames(2)
	await _frames(150)
	_check(not game.boss.active and game.score - before_score >= game.SCORE_BOSS, "boss beaten (+%d)" % (game.score - before_score))
	var cars := 0
	for i in game.prizes.count:
		cars += 1 if game.prizes.kind[i] == game.SmashPrizes.CAR else 0
	_check(cars == 1 and game.prizes.count >= 10, "boss drops a car and loot (%d prizes)" % game.prizes.count)

	# prizes
	await _fresh()
	game.prizes.spawn(game.player_pos, game.SmashPrizes.TOASTER)
	await _frames(90)
	_check(game.prize_counts[game.SmashPrizes.TOASTER] == 1 and game.score == 5000, "toaster collected (+%d)" % game.score)
	_check(game._summary_text().contains("TOASTER x1"), "prize summary lists it")

	# smart bomb
	await _fresh()
	for i in 300:
		game.horde.spawn_inside(Vector2(randf_range(-9, 9), randf_range(-9, 9)), 2.0)
	game.brutes.spawn_inside(Vector2(5, 5), 1.0)
	game.snipers.spawn_inside(Vector2(-5, 5))
	game.mines.spawn_inside(Vector2(-5, -5))
	game.eshots.fire(Vector2(3, 3), Vector2(1, 0), game.SmashEShots.SHOT)
	game.smart_bomb()
	await _frames(2)
	_check(game.enemies_left() == 0 and game.eshots.count == 0 and game.bombs == 0, "smart bomb clears the screen (left %d)" % game.enemies_left())

	# wave plans
	var w = game.waves
	w.start(1, 1)
	_check(w.specials.is_empty() and w.grunts_left > 0 and not w.boss_pending, "room 1: grunts only")
	w.start(4, 2)
	_check(w.specials.has(w.BRUTE) and w.specials.has(w.SNIPER) and w.specials.has(w.MINE), "room 4: brutes, snipers, mines")
	w.start(5, 1)
	_check(w.boss_pending and game.SmashWaves.waves_in_room(5) == 1, "room 5: the boss room")

	# room clear -> bonus -> exit -> next room
	await _fresh()
	game.waves_enabled = true
	game.waves.grunts_left = 0
	game.waves.specials.clear()
	game.waves.boss_pending = false
	game.wave_in_room = game.SmashWaves.waves_in_room(game.room)
	var sc0: int = game.score
	await _frames(2)
	_check(game.exit_door >= 0, "room clear opens an exit (door %d)" % game.exit_door)
	_check(game.score - sc0 >= game.NO_DEATH_BONUS + 5000, "time and no-death bonus (+%d)" % (game.score - sc0))
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
	game.debug_next_room()
	_check(game.room == 3, "debug next room")

	# high scores
	var sc = game.scores
	_check(sc.qualifies(60000) and not sc.qualifies(100), "high score qualifying")
	_check(sc.insert("ZZZ", 60000, 3) == 0 and sc.entries[0][0] == "ZZZ" and sc.entries.size() == 10, "high score insert at the top")

	# game over -> initials
	await _fresh()
	game.lives = 1
	game.score = 99999
	_vulnerable()
	game.horde.spawn_inside(game.player_pos + Vector2(0.4, 0), 0.0)
	await _frames(5)
	_check(game.game_over, "last life lost: game over")
	await _frames(60 * 4 + 10)
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

func _balance(runs: int) -> void:
	print("SMASH BALANCE  run | room | wave | score | minutes | kills | prizes $   (bot on autopilot, %d lives, %.2f s reaction, %.2f rad aim error)" % [game.START_LIVES, BOT_REACTION, BOT_AIM_ERROR])
	for r in runs:
		game.start_game()
		game.waves_enabled = true
		game.autopilot = true
		game.bot_reaction = BOT_REACTION
		game.bot_aim_error = BOT_AIM_ERROR
		game.sfx.enabled = false
		var frames := 0
		while not game.game_over and frames < BALANCE_CAP * 60.0:
			await get_tree().process_frame
			frames += 1
		print("SMASH BALANCE  %3d | %4d | %4d | %6d | %7.1f | %5d | %d%s" % [r + 1, game.room, game.wave, game.score,
				frames / 3600.0, game.kills, game.prize_total, "" if game.game_over else "  (time cap)"])
	game.autopilot = false
