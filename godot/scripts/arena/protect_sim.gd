class_name ProtectSim
extends RefCounted
## Protect Gothica (godot/specs/modes_hud.md 2): she's in the arena with a health bar. Calm, she wanders, and heads
## for a ripe potato when she's hurt (eating one heals her); an enemy close by sends her running; Juicy Jared can
## carry her (E): she can't be hurt up there, but he's slow and can't shoot or roll, and she wriggles down after a
## few seconds. Enemies go for whichever is closer, her or a player. Players come back after a few seconds; if she
## goes down, that's the run.

const SAY_PANIC := ["Help!", "Eek!", "Get away!", "Nooo!"]
const SAY_HURT := ["Ow!", "Ouch!", "Hey!"]
const SAY_EAT := ["Mmm", "Yum!"]
const SAY_FREE := ["Put me down!", "I can walk!"]
const CARRIERS := ["juicy", "jared"]

static var best_wave: int = -1

static func prot(key: String, fallback: float) -> float:
	var p: Dictionary = GameData.data.get("PROT", {})
	return float(p.get(key, fallback))

static func carry_slow() -> float:
	return prot("carrySlow", 0.7)

static func top(s: FightSim) -> float:
	return maxf(FightSim.WALL + 14.0, s.slot.y + 40.0)

static func new_goth(s: FightSim) -> FT.Goth:
	var g := FT.Goth.new()
	var npc: Dictionary = GameData.data.get("calls", {}).get("npcGoth", {})
	var m := FightSim.WALL + prot("margin", 70)
	g.x = clampf(float(npc.get("x", 430)), m, FightSim.AW - m)
	g.y = clampf(float(npc.get("y", 260)), top(s) + 30.0, FightSim.AH - m)
	g.tx = g.x
	g.ty = g.y
	g.hp = prot("hp", 10)
	g.max_hp = g.hp
	return g

static func say(g: FT.Goth, list: Array, dur: float) -> void:
	g.bubble = String(list[randi() % list.size()])
	g.bubble_t = 0.0
	g.bubble_dur = dur

## protTarget: Gothica instead of the nearest player when she's nearer (and on the ground). (x, y, distance), or
## x = -1e9 for "keep the player".
static func target_for(s: FightSim, e: FT.Enemy, best: float) -> Vector3:
	var g := s.goth
	if g == null or g.hp <= 0.0 or g.carrier >= 0:
		return Vector3(-1e9, 0, 0)
	var d := Vector2(g.x - e.x, g.y - e.y).length()
	if d < best:
		return Vector3(g.x, g.y, d)
	return Vector3(-1e9, 0, 0)

static func can_carry(s: FightSim, p: FT.Fighter) -> bool:
	var g := s.goth
	return g != null and s.started and not s.over and g.hp > 0.0 and g.carrier < 0 and g.carry_cd <= 0.0 \
		and p.alive and p.ch in CARRIERS and Vector2(p.x - g.x, p.y - g.y).length() < s.tv("carryRange", 46)

## E in a Protect run: pick her up or put her down.
static func carry_toggle(s: FightSim, p: FT.Fighter) -> void:
	var g := s.goth
	if g == null or s.over:
		return
	if g.carrier == p.id:
		set_down(s, 0.3)
		return
	if can_carry(s, p):
		g.carrier = p.id
		g.carry_t = 0.0
		g.face = p.fx < 0.0
		g.moving = false
		g.bubble = ""

static func set_down(s: FightSim, cool: float) -> void:
	var g := s.goth
	var p: FT.Fighter = s.players[g.carrier] if g.carrier >= 0 and g.carrier < s.players.size() else null
	g.carrier = -1
	g.carry_t = 0.0
	g.carry_cd = cool
	if p:
		g.x = p.x + (20.0 if g.face else -20.0)
		g.y = p.y + 4.0
	g.x = clampf(g.x, 32.0, 828.0)
	g.y = clampf(g.y, top(s), 488.0)
	g.moving = false
	g.wait = 0.4
	g.fx = 0.0
	g.fy = 1.0

## protHurt: returns true if the hit landed.
static func hurt(s: FightSim, dmg: float, nx: float, ny: float) -> bool:
	var g := s.goth
	if g == null or g.hurt > 0.0 or g.hp <= 0.0 or g.carrier >= 0:
		return false
	g.hp = maxf(0.0, g.hp - dmg)
	g.hurt = prot("hurtFor", 0.9)
	g.vx += nx * s.tv("contactPush", 320) * 0.8
	g.vy += ny * s.tv("contactPush", 320) * 0.8
	s.fx(FightSim.FX_HURT, g.x, g.y)
	if g.hp <= 0.0:
		g.moving = false
		g.bubble = "Ugh..."
		g.bubble_t = 0.0
		g.bubble_dur = 3.0
		s.fx(FightSim.FX_DOWN, g.x, g.y)
		s.over = true
		s.goth_down = true
		note_best(s.wave)
	elif g.say_cd <= 0.0:
		say(g, SAY_HURT, 1.1)
		g.say_cd = 1.2
	return true

## The batter's swing reaching her (L7600).
static func swing_hits(s: FightSim, e: FT.Enemy, dmg: float) -> void:
	var g := s.goth
	var dx := g.x - e.x
	var dy := g.y - e.y
	var d := sqrt(dx * dx + dy * dy)
	if d > s.tv("batReach", 46) + 12.0:
		return
	if d > 0.001 and (dx * e.sdx + dy * e.sdy) / d < 0.25:
		return
	hurt(s, dmg, e.sdx, e.sdy)

static func note_best(w: int) -> void:
	if best_wave < 0:
		best_wave = 0
		var cf := ConfigFile.new()
		if cf.load("user://smashed.cfg") == OK:
			best_wave = int(cf.get_value("protect", "best", 0))
	if w > best_wave:
		best_wave = w
		var cf2 := ConfigFile.new()
		cf2.load("user://smashed.cfg")
		cf2.set_value("protect", "best", w)
		cf2.save("user://smashed.cfg")

static func get_best() -> int:
	if best_wave < 0:
		note_best(0)
	return best_wave

## stepGoth (2.6).
static func step(s: FightSim, dt: float) -> void:
	var g := s.goth
	if g == null or not s.started or s.over:
		return
	g.hurt = maxf(0.0, g.hurt - dt)
	g.carry_cd = maxf(0.0, g.carry_cd - dt)
	g.say_cd = maxf(0.0, g.say_cd - dt)
	if g.bubble != "":
		g.bubble_t += dt
		if g.bubble_t > g.bubble_dur:
			g.bubble = ""
	# players who went down come back after a while, next to her
	for p: FT.Fighter in s.players:
		if p.alive:
			p.down_t = 0.0
			continue
		p.down_t += dt
		if p.down_t < prot("respawn", 4):
			continue
		p.alive = true
		p.down_t = 0.0
		p.hp = s.tv("playerHp", 5)
		p.grace = 1.5
		p.iframe = 0.0
		p.x = clampf(g.x + (40.0 if p.id else -40.0), 32.0, 828.0)
		p.y = clampf(g.y + 10.0, 32.0, 488.0)
		p.vx = 0.0
		p.vy = 0.0
		p.roll = 0.0
		p.roll_cd = 0.0
	# in someone's arms
	if g.carrier >= 0:
		var c: FT.Fighter = s.players[g.carrier] if g.carrier < s.players.size() else null
		if c == null or not c.alive:
			set_down(s, 0.5)
			return
		g.x = c.x
		g.y = c.y
		g.moving = false
		g.vx = 0.0
		g.vy = 0.0
		if c.moving and absf(c.ix) > 0.2:
			g.face = c.ix < 0.0
		g.carry_t += dt
		if g.carry_t >= prot("carryFor", 4):
			set_down(s, prot("carryCool", 1.5))
			say(g, SAY_FREE, 1.4)
		return
	var kick := Vector2(g.vx, g.vy).length()
	var mx := 0.0
	var my := 0.0
	var spd := 0.0
	var ax := 0.0
	var ay := 0.0
	var near := INF
	for e: FT.Enemy in s.enemies:
		if e.spawn > 0.0:
			continue
		var d := Vector2(g.x - e.x, g.y - e.y).length()
		if d < 0.001:
			d = 1.0
		near = minf(near, d)
		if d < prot("panicR", 130):
			ax += (g.x - e.x) / d * (1.0 / d)
			ay += (g.y - e.y) / d * (1.0 / d)
	if near < prot("panicR", 130):
		if g.panic <= 0.0 and g.say_cd <= 0.0:
			say(g, SAY_PANIC, 1.2)
			g.say_cd = 2.5
		g.panic = 0.8
		g.run_x = ax
		g.run_y = ay
	var food: FT.Plant = null
	if g.panic > 0.0:
		g.panic -= dt
		var rx := g.run_x
		var ry := g.run_y
		if g.x < 48.0 and rx < 0.0: rx = 0.0
		if g.x > 812.0 and rx > 0.0: rx = 0.0
		if g.y < top(s) + 16.0 and ry < 0.0: ry = 0.0
		if g.y > 472.0 and ry > 0.0: ry = 0.0
		var rl := Vector2(rx, ry).length()
		if rl > 1e-6:
			mx = rx / rl
			my = ry / rl
			spd = prot("run", 110)
		g.wait = 0.6
		g.tx = g.x
		g.ty = g.y
	else:
		var fd := prot("eatR", 280)
		if g.hp < g.max_hp:
			for pl: FT.Plant in s.plants:
				if pl.t < s.tv("spudGrow", 9):
					continue
				var d := Vector2(pl.x - g.x, pl.y - g.y).length()
				if d < fd:
					fd = d
					food = pl
		if food:
			g.wait = 0.0
			g.tx = food.x
			g.ty = food.y
			if fd < 14.0:
				s.plants.erase(food)
				g.hp = minf(g.max_hp, g.hp + prot("heal", 2))
				say(g, SAY_EAT, 1.2)
				s.floater(g.x, g.y - 46.0, "+%d" % int(prot("heal", 2)), Color("#7dff9a"))
				s.fx(FightSim.FX_WALL, food.x, food.y)
				g.wait = 0.8
				g.tx = g.x
				g.ty = g.y
				food = null
		elif g.wait > 0.0:
			g.wait -= dt
			if g.wait <= 0.0:
				var m := 88.0
				var tp := maxf(88.0, top(s) + 20.0)
				g.tx = m + randf() * (FightSim.AW - 2.0 * m)
				g.ty = tp + randf() * (FightSim.AH - m - tp)
		elif Vector2(g.tx - g.x, g.ty - g.y).length() < 4.0:
			g.wait = 1.2 + randf() * 2.2
			g.fx = 0.0
			g.fy = 1.0
		if g.wait <= 0.0:
			var dv := Vector2(g.tx - g.x, g.ty - g.y)
			if dv.length() > 2.0:
				mx = dv.x / dv.length()
				my = dv.y / dv.length()
				spd = prot("walk", 38) * (1.8 if food else 1.0)
	if spd > 0.0:
		g.ix = mx
		g.iy = my
		g.fx = mx
		g.fy = my
		g.x += mx * spd * dt
		g.y += my * spd * dt
		g.odo += spd * dt
		g.moving = true
	else:
		g.moving = false
	if kick > 1.0:
		g.x += g.vx * dt
		g.y += g.vy * dt
		var f := pow(0.002, dt)
		g.vx *= f
		g.vy *= f
	else:
		g.vx = 0.0
		g.vy = 0.0
	g.x = clampf(g.x, 32.0, 828.0)
	g.y = clampf(g.y, top(s), 488.0)
	for e: FT.Enemy in s.enemies:
		if e.spawn > 0.0 or s.e_melee[e.t]:
			continue
		var dx := g.x - e.x
		var dy := g.y - e.y
		var d := sqrt(dx * dx + dy * dy)
		if d > s.e_rad(e.t) + 12.0:
			continue
		if d < 0.001:
			dx = 0.0
			dy = 1.0
			d = 1.0
		if hurt(s, s.tv("contactDmg", 1) * s.e_dmg[e.t], dx / d, dy / d):
			var mass: float = s.e_mass[e.t]
			e.vx -= dx / d * s.tv("contactPush", 320) * 0.6 / mass
			e.vy -= dy / d * s.tv("contactPush", 320) * 0.6 / mass
