class_name EnemySim
extends RefCounted
## The wave director and the enemies (godot/specs/enemies_waves.md 4): spawning round the walls, chasing with the
## HTML game's sluggish steering, the batter's wind-up and swing, separation, the arena clamp, contact damage, and
## brute shrapnel. Static functions on the FightSim (one world, one RNG).

const CHASE := 0
const WINDUP := 1
const SWING := 2
const RECOVER := 3

static func wave_size(s: FightSim, n: int) -> int:
	return int(s.tv("waveBase", 6) + (n - 1) * s.tv("waveGrowth", 3))

static func wave_speed(s: FightSim, n: int) -> float:
	return s.tv("enemySpeed", 40) * (1.0 + (n - 1) * s.tv("waveSpeedUp", 6) / 100.0)

## waveMix (L6526): the filler type, swarmers from swarmWave, brutes from bruteWave, shuffled with the world RNG.
static func wave_mix(s: FightSim, n: int) -> Array:
	var total := wave_size(s, n)
	var bw := int(s.tv("bruteWave", 5))
	var sw := int(s.tv("swarmWave", 3))
	var batw := int(s.tv("batWave", 4))
	var brutes := (n - bw) / 2 + 1 if n >= bw else 0
	var swarmers := (n - sw + 1) * 2 if n >= sw else 0
	var base := 3 if int(s.tv("baseEnemy", 3)) == 3 else 0
	var batters := (n - batw) / 2 + 1 if (base != 3 and n >= batw) else 0
	var zw := int(s.tv("zombieWave", 3))
	var zombies := (n - zw) / 2 + 1 if n >= zw else 0
	brutes = mini(brutes, total / 4)
	batters = mini(batters, total / 4)
	swarmers = mini(swarmers, total / 2)
	zombies = mini(zombies, total / 4)
	var fillers := maxi(0, total - brutes - swarmers - batters - zombies)
	var q := []
	for i in fillers:
		q.append(base)
	for i in swarmers:
		q.append(1)
	for i in brutes:
		q.append(2)
	for i in batters:
		q.append(3)
	for i in zombies:
		q.append(ZombieSim.T)
	for i in range(q.size() - 1, 0, -1):
		var j := int(floor(s.rnd() * (i + 1)))
		var tmp = q[i]
		q[i] = q[j]
		q[j] = tmp
	return q

## The text under "WAVE n" (8): "18 incoming — swarmers and brutes".
static func incoming_text(s: FightSim, n: int) -> String:
	var txt := "%d incoming" % wave_size(s, n)
	var list := []
	if n >= int(s.tv("swarmWave", 3)):
		list.append("swarmers")
	if int(s.tv("baseEnemy", 3)) != 3 and n >= int(s.tv("batWave", 4)):
		list.append("batters")
	if n >= int(s.tv("bruteWave", 5)):
		list.append("brutes")
	if n >= int(s.tv("zombieWave", 3)):
		list.append("zombies")
	if not list.is_empty():
		txt += " — " + " and ".join(list)
	return txt

## The wave director (4.1).
static func step_director(s: FightSim, dt: float) -> void:
	if s.breather > 0.0:
		s.breather -= dt
		if s.breather <= 0.0:
			s.start_wave()
	elif s.pending > 0:
		s.spawn_timer -= dt
		if s.spawn_timer <= 0.0:
			spawn(s, int(s.queue.pop_front()) if not s.queue.is_empty() else 0)
			s.pending -= 1
			s.spawn_timer = s.tv("spawnGap", 0.45)
	elif s.enemies.is_empty():
		s.breather = s.tv("intermission", 2.2)
		s.waves_cleared += 1

## spawnEnemy (4.4): a random side, away from the players if it can.
static func spawn(s: FightSim, et: int) -> FT.Enemy:
	if et == ZombieSim.T:
		return ZombieSim.spawn_arena(s)          # (up through the floor, not in from a wall)
	var m := FightSim.WALL + s.tv("enemyRadius", 15) * s.e_r[et] + 2.0
	var x := 0.0
	var y := 0.0
	for tries in 12:
		var side := int(floor(s.rnd() * 4))
		match side:
			0:
				x = m + s.rnd() * (FightSim.AW - 2.0 * m)
				y = m
			1:
				x = FightSim.AW - m
				y = m + s.rnd() * (FightSim.AH - 2.0 * m)
			2:
				x = m + s.rnd() * (FightSim.AW - 2.0 * m)
				y = FightSim.AH - m
			_:
				x = m
				y = m + s.rnd() * (FightSim.AH - 2.0 * m)
		var near := false
		for p: FT.Fighter in s.players:
			if p.alive and Vector2(p.x - x, p.y - y).length() < 150.0:
				near = true
		if not near:
			break
	var e := s.new_enemy(et, x, y)
	e.spawn = 0.35
	return e

## The enemies' step, separation, the clamp and contact damage (4.5-4.8).
static func step_enemies(s: FightSim, dt: float) -> void:
	if s.enemies.is_empty():
		return
	var wspeed := wave_speed(s, s.wave) * s.bfv("enemy_speed_mult")
	for e: FT.Enemy in s.enemies.duplicate():
		e.flash = maxf(0.0, e.flash - dt)
		e.spawn = maxf(0.0, e.spawn - dt)
		if e.spawn > 0.0:
			continue
		var target = null           # Vector2 of what it chases
		var best := INF
		for p: FT.Fighter in s.players:
			if not p.alive:
				continue
			var d := Vector2(p.x - e.x, p.y - e.y).length()
			if d < best:
				best = d
				target = Vector2(p.x, p.y)
		if s.goth:
			var g := ProtectSim.target_for(s, e, best)
			if g.x > -1e8:
				target = Vector2(g.x, g.y)
				best = g.z
		if e.t == ZombieSim.T:
			ZombieSim.step(s, e, wspeed, dt)
			continue
		e.stun = maxf(0.0, e.stun - dt)
		var espeed: float = wspeed * s.e_speed[e.t] * (0.0 if e.stun > 0.0 else 1.0)
		if e.t == 3:
			if _batter(s, e, target, best, espeed, dt):
				continue
		if target != null:
			var dv: Vector2 = target - Vector2(e.x, e.y)
			var d := dv.length()
			if d < 0.0001:
				d = 1.0
			e.vx += dv.x / d * espeed * 6.0 * dt
			e.vy += dv.y / d * espeed * 6.0 * dt
		var sp := Vector2(e.vx, e.vy).length()
		if sp > 0.0:
			var drop := minf(sp, espeed * 5.0 * dt)
			e.vx -= e.vx / sp * drop
			e.vy -= e.vy / sp * drop
		var cap := espeed * 2.2
		sp = Vector2(e.vx, e.vy).length()
		if sp > cap:
			if sp > 0.0:
				e.vx = e.vx / sp * cap
				e.vy = e.vy / sp * cap
		e.x += e.vx * dt
		e.y += e.vy * dt
		e.odo += Vector2(e.vx, e.vy).length() * dt
	# separation: the heavier shoves the lighter
	var zpos := {}
	if s.lobby():
		for e: FT.Enemy in s.enemies:
			if e.t == ZombieSim.T:
				zpos[e] = Vector2(e.x, e.y)
	var n := s.enemies.size()
	for i in n:
		var a: FT.Enemy = s.enemies[i]
		var ra := s.e_rad(a.t)
		var ma: float = s.e_mass[a.t]
		for j in range(i + 1, n):
			var b: FT.Enemy = s.enemies[j]
			var want := ra + s.e_rad(b.t)
			var dx := b.x - a.x
			var dy := b.y - a.y
			if absf(dx) >= want or absf(dy) >= want:
				continue
			var d := sqrt(dx * dx + dy * dy)
			if d > 0.0 and d < want:
				var push := want - d
				var nx := dx / d
				var ny := dy / d
				var mb: float = s.e_mass[b.t]
				a.x -= nx * push * mb / (ma + mb)
				a.y -= ny * push * mb / (ma + mb)
				b.x += nx * push * ma / (ma + mb)
				b.y += ny * push * ma / (ma + mb)
	# the arena clamp (always the ARENA rectangle, the lobby too: a BUST brute stays in the lounge)
	for e: FT.Enemy in s.enemies:
		if zpos.has(e):
			ZombieSim.keep_in_yard(s, e, zpos[e].x, zpos[e].y)      # (in the backyard at night)
			continue
		var r := s.e_rad(e.t)
		e.x = clampf(e.x, FightSim.WALL + r, FightSim.AW - FightSim.WALL - r)
		e.y = clampf(e.y, FightSim.WALL + r, FightSim.AH - FightSim.WALL - r)
	# contact damage (not the batter: he has to swing)
	for e: FT.Enemy in s.enemies:
		if e.spawn > 0.0 or s.e_melee[e.t]:
			continue
		var r := s.e_rad(e.t)
		for p: FT.Fighter in s.players:
			if not s.can_hurt(p):
				continue
			var dx: float = p.x - e.x
			var dy: float = p.y - e.y
			var d := sqrt(dx * dx + dy * dy)
			if d > r + s.tv("radius", 14):
				continue
			if d < 0.001:
				dx = 0.0
				dy = 1.0
				d = 1.0
			var nx := dx / d
			var ny := dy / d
			var mass: float = s.e_mass[e.t]
			e.vx -= nx * s.tv("contactPush", 320) * 0.6 / mass
			e.vy -= ny * s.tv("contactPush", 320) * 0.6 / mass
			s.hurt_player(p, s.tv("contactDmg", 1) * s.e_dmg[e.t], nx, ny, s.tv("contactPush", 320))

# The batter's states (4.6). Returns true when he's planted (no chase steering this step).
static func _batter(s: FightSim, e: FT.Enemy, target, best: float, espeed: float, dt: float) -> bool:
	e.st_t = maxf(0.0, e.st_t - dt)
	if e.st == CHASE and e.stun <= 0.0 and target != null and best < s.tv("batRange", 60):
		e.st = WINDUP
		e.st_t = s.tv("batWindup", 0.38)
		var dv: Vector2 = (target - Vector2(e.x, e.y))
		var d := maxf(0.0001, dv.length())
		e.sdx = dv.x / d
		e.sdy = dv.y / d
		s.events.append([100, round(e.x), round(e.y)])       # (a wind-up: the first-person whoosh)
	if e.st == CHASE:
		return false
	var k := pow(0.001, dt)
	e.vx *= k
	e.vy *= k
	e.x += e.vx * dt
	e.y += e.vy * dt
	if e.st == WINDUP and e.st_t <= 0.0:
		e.st = SWING
		e.st_t = 0.16
		e.hit = false
	if e.st == SWING and not e.hit and e.st_t <= 0.08:
		e.hit = true
		var dmg: float = s.tv("contactDmg", 1) * s.e_dmg[e.t]
		for p: FT.Fighter in s.players:
			if not s.can_hurt(p):
				continue
			var dx: float = p.x - e.x
			var dy: float = p.y - e.y
			var d := sqrt(dx * dx + dy * dy)
			if d > s.tv("batReach", 46) + s.tv("radius", 14):
				continue
			if d > 0.001 and (dx * e.sdx + dy * e.sdy) / d < 0.25:
				continue
			s.hurt_player(p, dmg, e.sdx, e.sdy, s.tv("contactPush", 320) * 1.4)
		if s.goth:
			ProtectSim.swing_hits(s, e, dmg)
		e.vx += e.sdx * espeed * 1.6
		e.vy += e.sdy * espeed * 1.6
	elif e.st == SWING and e.st_t <= 0.0:
		e.st = RECOVER
		e.st_t = s.tv("batRecover", 0.55)
	elif e.st == RECOVER and e.st_t <= 0.0:
		e.st = CHASE
	return true

## Shrapnel (4.10).
static func step_shards(s: FightSim, dt: float) -> void:
	if s.shards.is_empty():
		return
	var keep := []
	for sh: FT.Shard in s.shards:
		sh.x += sh.vx * dt
		sh.y += sh.vy * dt
		sh.life -= dt
		var gone: bool = sh.life <= 0.0 or sh.x < FightSim.WALL or sh.x > FightSim.AW - FightSim.WALL \
			or sh.y < FightSim.WALL or sh.y > FightSim.AH - FightSim.WALL
		var dir := Vector2(sh.vx, sh.vy).normalized()
		if not gone and s.goth and Vector2(s.goth.x - sh.x, s.goth.y - sh.y).length() < 16.0:
			if ProtectSim.hurt(s, s.tv("shrapDmg", 1), dir.x, dir.y):
				gone = true
		if not gone:
			for p: FT.Fighter in s.players:
				if not s.can_hurt(p):
					continue
				if Vector2(p.x - sh.x, p.y - sh.y).length() <= s.tv("radius", 14) + 4.0:
					s.hurt_player(p, s.tv("shrapDmg", 1), dir.x, dir.y, s.tv("contactPush", 320) * 0.8)
					gone = true
					break
		if not gone and s.tv("shrapFriendly", 1) > 0.0:
			for e: FT.Enemy in s.enemies.duplicate():
				if e.spawn > 0.0 or e.t == 2:
					continue
				if Vector2(e.x - sh.x, e.y - sh.y).length() <= s.e_rad(e.t):
					e.hp -= 1.0
					e.flash = 0.08
					s.fx(FightSim.FX_HIT, sh.x, sh.y)
					if e.hp <= 0.0:
						s.kill_enemy(e, sh.vx, sh.vy, false, -1, 1.0, false, false)
					gone = true
					break
		if not gone:
			keep.append(sh)
	s.shards = keep
