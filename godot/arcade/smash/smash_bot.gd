extends RefCounted
## Smash arcade's computer player: plays the attract demo, and the balance bench's test runs (autopilot).
## Backs away from the enemies near it (the boss and mines most of all) and off the walls, sidesteps incoming
## bullets and barrels, drifts to prizes and power-ups, walks out of the exit when it opens, shoots the nearest
## enemy (a mine only from a safe distance), and sets off the smart bomb when it's swamped. It reads the game, it
## doesn't change it: think() returns what a player's input would give: [move, aim, fire, bomb].

const SCAN := 600
const MINE_SAFE := 3.4

static func think(game) -> Array:
	var p: Vector2 = game.player_pos
	var flee := Vector2.ZERO
	var near := Vector2.ZERO
	var nd := INF
	var crowd := 0
	var horde = game.horde
	# enough grunts for the decision, not all of a stress test's thousands
	for i in mini(horde.count, SCAN):
		var d: Vector2 = horde.pos[i] - p
		var l2 := d.length_squared()
		if l2 < nd:
			nd = l2
			near = horde.pos[i]
		if l2 < 30.0:
			flee -= d / maxf(l2, 0.2)
		if l2 < 9.0:
			crowd += 1
	for pool_weight in [[game.brutes, 3.0, 40.0], [game.snipers, 1.5, 25.0]]:
		var pool = pool_weight[0]
		for i in pool.count:
			var d: Vector2 = pool.pos[i] - p
			var l2 := d.length_squared()
			if l2 < nd:
				nd = l2
				near = pool.pos[i]
			if l2 < pool_weight[2]:
				flee -= d * pool_weight[1] / maxf(l2, 0.2)
	var mines = game.mines
	for i in mines.count:
		var d: Vector2 = mines.pos[i] - p
		var l2 := d.length_squared()
		if l2 < 20.0:
			flee -= d * (8.0 if mines.fuse[i] >= 0.0 else 4.0) / maxf(l2, 0.2)
		if l2 > MINE_SAFE * MINE_SAFE and l2 < nd:
			nd = l2
			near = mines.pos[i]
	var boss = game.boss
	if boss.count > 0:
		var d: Vector2 = boss.pos - p
		var l2 := d.length_squared()
		if l2 < 64.0:
			flee -= d * 12.0 / maxf(l2, 0.5)
		if l2 < nd or l2 < 120.0:
			nd = l2
			near = boss.pos
		if l2 < 9.0:
			crowd += 20
	var es = game.eshots
	for i in es.count:
		var rel: Vector2 = p - es.pos[i]
		var along: float = rel.dot(es.dir[i])
		if along > 0.0 and rel.length_squared() < 25.0:
			var side: Vector2 = rel - es.dir[i] * along
			flee += side.normalized() * 3.0 / maxf(side.length(), 0.3) if side.length_squared() > 0.0001 else Vector2(es.dir[i].y, -es.dir[i].x) * 3.0
	# keep off the walls, except when heading out of the open exit (the push would hold it in front of the door)
	var lim: float = game.HALF - 2.0 if game.exit_door < 0 else INF
	if absf(p.x) > lim:
		flee.x -= signf(p.x) * (absf(p.x) - lim) * 2.0
	if absf(p.y) > lim:
		flee.y -= signf(p.y) * (absf(p.y) - lim) * 2.0

	var goal := Vector2.ZERO
	var pull := 0.0
	if game.exit_door >= 0:
		goal = -Vector2(game.DOOR_N[game.exit_door]) * (game.HALF + 2.0)
		pull = 2.0
	else:
		var prizes = game.prizes
		var best := INF
		for i in prizes.count:
			var q := Vector2(prizes.pos[i].x, prizes.pos[i].z)
			var l2 := (q - p).length_squared()
			if l2 < 49.0 and l2 < best:
				best = l2
				goal = q
				pull = 0.8
		var k: int = game.pickups.nearest(p)
		if pull == 0.0 and k >= 0:
			goal = game.pickups.pos[k]
			pull = 0.6
	var move := flee
	if pull > 0.0:
		move += (goal - p).normalized() * pull
	elif flee.length() < 0.2:
		move += -p * 0.05
	if move.length() > 1.0:
		move = move.normalized()
	var aim := Vector2.ZERO
	if nd < INF:
		aim = (near - p).normalized()
	var bomb: bool = game.bombs > 0 and crowd >= 14
	return [move, aim, nd < 200.0, bomb]
