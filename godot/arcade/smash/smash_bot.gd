extends RefCounted
## Smash arcade attract-mode player: plays the demo while nobody's at the cabinet. Backs away from the enemies
## near it (and off the walls), drifts to pickups, walks out of the exit when it opens, and always shoots at the
## nearest enemy. It reads the game, it doesn't change it: think() returns the same move / aim / fire a player's
## input would give.

const SCAN := 600

static func think(game) -> Array:
	var p: Vector2 = game.player_pos
	var horde = game.horde
	var brutes = game.brutes
	var flee := Vector2.ZERO
	var near := Vector2.ZERO
	var nd := INF
	# enough grunts for the decision, not all of a stress test's thousands
	for i in mini(horde.count, SCAN):
		var d: Vector2 = horde.pos[i] - p
		var l2 := d.length_squared()
		if l2 < nd:
			nd = l2
			near = horde.pos[i]
		if l2 < 30.0:
			flee -= d / maxf(l2, 0.2)
	for i in brutes.count:
		var d: Vector2 = brutes.pos[i] - p
		var l2 := d.length_squared()
		if l2 < nd:
			nd = l2
			near = brutes.pos[i]
		if l2 < 40.0:
			flee -= d * 3.0 / maxf(l2, 0.2)
	var lim: float = game.HALF - 2.0
	if absf(p.x) > lim:
		flee.x -= signf(p.x) * (absf(p.x) - lim) * 2.0
	if absf(p.y) > lim:
		flee.y -= signf(p.y) * (absf(p.y) - lim) * 2.0

	var goal := Vector2.ZERO
	var has_goal := false
	if game.exit_door >= 0:
		goal = -Vector2(game.DOOR_N[game.exit_door]) * (game.HALF + 2.0)
		has_goal = true
	else:
		var k: int = game.pickups.nearest(p)
		if k >= 0:
			goal = game.pickups.pos[k]
			has_goal = true
	var move := flee
	if has_goal:
		move += (goal - p).normalized() * (2.0 if game.exit_door >= 0 else 0.6)
	elif flee.length() < 0.2:
		move += -p * 0.05
	if move.length() > 1.0:
		move = move.normalized()
	var aim := Vector2.ZERO
	if nd < INF:
		aim = (near - p).normalized()
	return [move, aim, nd < 200.0]
