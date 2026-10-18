class_name ZombieSim
extends RefCounted
## The skeleton zombie in the fight simulation: enemy type 4 (after the HTML game's grunt, swarmer, brute and
## batter), the same FT.Enemy records, so bullets, fists, potatoes, rockets, the nuke, gore, kill pay and the
## online snapshot all take it as they are. Static functions on the FightSim (one world, one RNG), called from
## EnemySim's step for each zombie.
##
## It climbs out of the ground (RISE), screams when it first sees you (SCREAM) and then comes at you faster for a
## moment, shambles after you (CHASE), and claws: a wind-up with the arm raised (WINDUP), the swipe that lands
## halfway through (SWING, one heart, only in front of it), a pause (RECOVER). Hits stagger it but don't stop a
## swipe. In the backyard at night (ZombieNight) it keeps to the yard (never the house), goes for whoever is out
## there, mills about when nobody is, and at dawn sinks back into the ground (SINK). In the arena it rises from
## the floor among the waves.
##
## e.st is the state, e.st_t its timer; e.zf: 1 = has screamed, 2 = this swipe has landed; e.zt: the charge left
## after the scream (seconds); e.sdx, e.sdy: the swipe's direction (and where it heads while milling about).

const T := 4
const RISE := 0
const CHASE := 1
const WINDUP := 2
const SWING := 3
const RECOVER := 4
const SCREAM := 5
const SINK := 6
const WANDER := 7

const RISE_TIME := 2.2
const WINDUP_TIME := 0.55
const SWING_TIME := 0.22
const RECOVER_TIME := 0.7
const SCREAM_TIME := 1.7
const SINK_TIME := 2.4
## The claw's reach past the zombie's body (HTML units).
const REACH := 40.0
## How far it sees you from (it screams when it first does).
const SIGHT := 430.0
## Speed after the scream (a run), as a multiple of the shamble.
const CHARGE := 1.75
const CHARGE_TIME := 2.2

## The ETYPE record (the HTML game's form): a slow, tough, heavy one that claws.
const ETYPE := {"key": "zombie", "facesRight": true, "speed": 0.62, "hp": 2.7, "r": 1.15, "dmg": 1, "mass": 1.8,
	"colour": "#9fb28a", "coins": 4, "melee": true}

## Event kinds for the views and sounds (FightSim.events: [kind, x, y]).
const EV_SCREAM := 110
const EV_SWIPE := 111
const EV_RISE := 112
const EV_SINK := 113

# the yard: where a zombie may stand (lobby areas in the yard, minus its solids), worked out once
static var _yard_rects: Array = []
static var _solids: Array = []           # [Rect2] or [Vector3(cx, cy, r)]
static var _yard_ready := false

## Adds the zombie to the sim's ETYPE arrays (FightSim._init).
static func add_type(s: FightSim) -> void:
	if s.e_key.has("zombie"):
		return
	var e: Dictionary = ETYPE
	s.e_key.append(String(e.key))
	s.e_speed.append(float(e.speed))
	s.e_hp.append(float(e.hp))
	s.e_r.append(float(e.r))
	s.e_dmg.append(float(e.dmg))
	s.e_mass.append(float(e.mass))
	s.e_coins.append(int(e.coins))
	s.e_melee.append(bool(e.melee))
	s.e_col.append(Color(String(e.colour)))

## A zombie climbing out of the ground at (x, y).
static func spawn_at(s: FightSim, x: float, y: float) -> FT.Enemy:
	var e := s.new_enemy(T, x, y)
	e.spawn = 0.0
	e.st = RISE
	e.st_t = RISE_TIME
	e.sdx = 0.0
	e.sdy = 1.0
	s.events.append([EV_RISE, round(x), round(y)])
	return e

## The arena: up through the floor somewhere clear of the players (instead of in from a wall).
static func spawn_arena(s: FightSim) -> FT.Enemy:
	var m := FightSim.WALL + 40.0
	var x := FightSim.AW / 2.0
	var y := FightSim.AH / 2.0
	for tries in 16:
		x = m + s.rnd() * (FightSim.AW - 2.0 * m)
		y = m + s.rnd() * (FightSim.AH - 2.0 * m)
		var near := false
		for p: FT.Fighter in s.players:
			if p.alive and Vector2(p.x - x, p.y - y).length() < 190.0:
				near = true
		if s.goth and Vector2(s.goth.x - x, s.goth.y - y).length() < 150.0:
			near = true
		if not near:
			break
	var e := spawn_at(s, x, y)
	if s.rnd() < 0.5:
		e.zf |= 1                    # (half of them don't stop to scream in a run)
	return e

## Sends every zombie back into the ground (dawn).
static func sink_all(s: FightSim) -> void:
	for e: FT.Enemy in s.enemies:
		if e.t == T and e.st != SINK:
			e.st = SINK
			e.st_t = SINK_TIME
			s.events.append([EV_SINK, round(e.x), round(e.y)])

static func count(s: FightSim) -> int:
	var n := 0
	for e: FT.Enemy in s.enemies:
		if e.t == T:
			n += 1
	return n

# ---------------------------------------------------------------- the step

## Who it goes for: the nearest living player it may reach (in the lobby only those out in the yard and on the
## ground), or Gothica in Protect mode. Returns Vector3(x, y, distance) or z = INF.
static func target(s: FightSim, e: FT.Enemy) -> Vector3:
	var best := Vector3(0, 0, INF)
	for p: FT.Fighter in s.players:
		if not p.alive:
			continue
		if s.lobby() and not reachable(p):
			continue
		var d := Vector2(p.x - e.x, p.y - e.y).length()
		if d < best.z:
			best = Vector3(p.x, p.y, d)
	if s.goth:
		var g := ProtectSim.target_for(s, e, best.z)
		if g.x > -1e8:
			best = g
	return best

## A player it can get at in the yard: out there, and not up on the trampoline.
static func reachable(p: FT.Fighter) -> bool:
	if not in_yard(p.x, p.y):
		return false
	var n := p.node
	if n and is_instance_valid(n) and float(n.get("dz") if n.get("dz") != null else 0.0) > 24.0:
		return false
	return true

## main.gd's inYard: past the middle of the lounge's bottom or right wall, and not in the bedroom.
static func in_yard(x: float, y: float) -> bool:
	var d: Dictionary = GameData.data
	var a: Dictionary = d.get("ARENA", {"w": 860, "h": 520, "wall": 18})
	var b: Dictionary = d.get("BEDROOM", {"x1": 458})
	var half: float = float(a.wall) / 2.0
	var lobby_h := float(d.get("LOBBY_H", 880))
	return x > float(a.w) - half or (y > float(a.h) - half and (x > float(b.x1) + half or y > lobby_h - half))

## One zombie's step (instead of EnemySim's chase). wspeed: the wave's enemy speed.
static func step(s: FightSim, e: FT.Enemy, wspeed: float, dt: float) -> void:
	e.st_t = maxf(0.0, e.st_t - dt)
	e.stun = maxf(0.0, e.stun - dt)
	e.zt = maxf(0.0, e.zt - dt)
	var base: float = wspeed * s.e_speed[T]
	var tg := target(s, e)
	var has := tg.z < INF
	match e.st:
		RISE:
			e.vx = 0.0
			e.vy = 0.0
			if has:
				_face(e, tg)
			if e.st_t <= 0.0:
				e.st = CHASE
			return
		SINK:
			e.vx *= pow(0.01, dt)
			e.vy *= pow(0.01, dt)
			if e.st_t <= 0.0:
				s.enemies.erase(e)
			return
		SCREAM:
			e.vx *= pow(0.002, dt)
			e.vy *= pow(0.002, dt)
			if has:
				_face(e, tg)
			if e.st_t <= 0.0:
				e.st = CHASE
				e.zt = CHARGE_TIME
			return
		WINDUP, SWING, RECOVER:
			_claw(s, e, base, dt)
			return
	# CHASE or WANDER
	if has and not (e.zf & 1) and tg.z < SIGHT:
		e.zf |= 1
		e.st = SCREAM
		e.st_t = SCREAM_TIME
		e.vx = 0.0
		e.vy = 0.0
		_face(e, tg)
		s.events.append([EV_SCREAM, round(e.x), round(e.y)])
		return
	var r := s.e_rad(T)
	if has and e.stun <= 0.0 and tg.z < r + s.tv("radius", 14) + REACH * 0.75:
		e.st = WINDUP
		e.st_t = WINDUP_TIME
		e.zf &= ~2
		_face(e, tg)
		s.events.append([EV_SWIPE, round(e.x), round(e.y)])
		return
	var speed := base * (CHARGE if e.zt > 0.0 else 1.0) * (0.0 if e.stun > 0.0 else 1.0)
	var goal = null
	if has:
		e.st = CHASE
		goal = Vector2(tg.x, tg.y)
	else:
		# nobody to go for: mill about, ambling somewhere new now and then
		e.st = WANDER
		speed *= 0.45
		if e.st_t <= 0.0:
			e.st_t = 2.5 + s.rnd() * 4.0
			var a := s.rnd() * TAU
			e.sdx = cos(a)
			e.sdy = sin(a)
			if s.rnd() < 0.3:
				e.sdx = 0.0              # (a pause)
				e.sdy = 0.0
		goal = Vector2(e.x + e.sdx * 100.0, e.y + e.sdy * 100.0)
	if goal != null:
		var dv: Vector2 = goal - Vector2(e.x, e.y)
		var d := dv.length()
		if d > 0.5 and (e.sdx != 0.0 or e.sdy != 0.0 or has):
			e.vx += dv.x / d * speed * 6.0 * dt
			e.vy += dv.y / d * speed * 6.0 * dt
	var sp := Vector2(e.vx, e.vy).length()
	if sp > 0.0:
		var drop := minf(sp, maxf(speed, base * 0.3) * 5.0 * dt)
		e.vx -= e.vx / sp * drop
		e.vy -= e.vy / sp * drop
	var cap := speed * 2.2
	sp = Vector2(e.vx, e.vy).length()
	if sp > cap and sp > 0.0 and e.stun <= 0.0:
		e.vx = e.vx / sp * cap
		e.vy = e.vy / sp * cap
	move(s, e, dt)

static func _face(e: FT.Enemy, tg: Vector3) -> void:
	var dv := Vector2(tg.x - e.x, tg.y - e.y)
	if dv.length() > 0.001:
		dv = dv.normalized()
		e.sdx = dv.x
		e.sdy = dv.y

## The claw: wind-up, the swipe (lands halfway), recovery.
static func _claw(s: FightSim, e: FT.Enemy, base: float, dt: float) -> void:
	var k := pow(0.001, dt)
	e.vx *= k
	e.vy *= k
	if e.st == WINDUP:
		var tg := target(s, e)
		if tg.z < INF and e.st_t > WINDUP_TIME * 0.4:
			_face(e, tg)            # (it tracks you for the first part of the wind-up)
		if e.st_t <= 0.0:
			e.st = SWING
			e.st_t = SWING_TIME
	elif e.st == SWING:
		if not (e.zf & 2) and e.st_t <= SWING_TIME * 0.5:
			e.zf |= 2
			var dmg: float = s.tv("contactDmg", 1) * s.e_dmg[T]
			var r := s.e_rad(T)
			for p: FT.Fighter in s.players:
				if not s.can_hurt(p):
					continue
				if s.lobby() and not reachable(p):
					continue
				var dx: float = p.x - e.x
				var dy: float = p.y - e.y
				var d := sqrt(dx * dx + dy * dy)
				if d > r + REACH + s.tv("radius", 14):
					continue
				if d > 0.001 and (dx * e.sdx + dy * e.sdy) / d < 0.2:
					continue
				var over := s.over
				s.hurt_player(p, dmg, e.sdx, e.sdy, s.tv("contactPush", 320) * 1.2)
				if s.lobby():
					s.over = over       # (down in the yard isn't game over: ZombieNight drags you back inside)
			if s.goth:
				ProtectSim.swing_hits(s, e, dmg)
			e.vx += e.sdx * base * 2.0
			e.vy += e.sdy * base * 2.0
		if e.st_t <= 0.0:
			e.st = RECOVER
			e.st_t = RECOVER_TIME
	elif e.st == RECOVER and e.st_t <= 0.0:
		e.st = CHASE
	move(s, e, dt)

## Moves it by its velocity: in a run anywhere (EnemySim clamps it to the arena); in the yard only where it may
## stand, sliding along what's in the way.
static func move(s: FightSim, e: FT.Enemy, dt: float) -> void:
	var nx := e.x + e.vx * dt
	var ny := e.y + e.vy * dt
	if s.lobby():
		var r := s.e_rad(T) * 0.8
		if not can_stand(nx, ny, r):
			if can_stand(nx, e.y, r):
				ny = e.y
				e.vy = 0.0
			elif can_stand(e.x, ny, r):
				nx = e.x
				e.vx = 0.0
			else:
				nx = e.x
				ny = e.y
				e.vx = 0.0
				e.vy = 0.0
				if e.st == WANDER:
					e.st_t = 0.0            # (bumped into something: pick another way)
	e.odo += Vector2(nx - e.x, ny - e.y).length()
	e.x = nx
	e.y = ny

## After the separation shove: back where it may stand (the lobby's clamp for zombies).
static func keep_in_yard(s: FightSim, e: FT.Enemy, ox: float, oy: float) -> void:
	if can_stand(e.x, e.y, s.e_rad(T) * 0.8):
		return
	if can_stand(ox, oy, s.e_rad(T) * 0.8):
		e.x = ox
		e.y = oy

# ---------------------------------------------------------------- the yard

static func _yard() -> void:
	if _yard_ready:
		return
	_yard_ready = true
	var d: Dictionary = GameData.data
	for a in d.get("calls", {}).get("lobbyAreas", []):
		var r := Rect2(float(a.x0), float(a.y0), float(a.x1) - float(a.x0), float(a.y1) - float(a.y0))
		if in_yard(r.get_center().x, r.get_center().y) or in_yard(r.end.x - 4.0, r.end.y - 4.0):
			_yard_rects.append(r)
	for so in d.get("YARD_SOLIDS", []):
		if so.has("cx"):
			_solids.append(Vector3(float(so.cx), float(so.cy), float(so.r)))
		else:
			_solids.append(Rect2(float(so.x0), float(so.y0), float(so.x1) - float(so.x0), float(so.y1) - float(so.y0)))

## Whether a zombie of radius r may stand at (x, y) in the yard.
static func can_stand(x: float, y: float, r: float) -> bool:
	_yard()
	if not in_yard(x, y):
		return false
	var inside := false
	for a: Rect2 in _yard_rects:
		if x >= a.position.x + r and x <= a.end.x - r and y >= a.position.y + r and y <= a.end.y - r:
			inside = true
			break
	if not inside:
		return false
	for so in _solids:
		if so is Rect2:
			var q: Rect2 = so
			if x > q.position.x - r and x < q.end.x + r and y > q.position.y - r and y < q.end.y + r:
				return false
		else:
			var c: Vector3 = so
			if Vector2(x - c.x, y - c.y).length() < c.z + r:
				return false
	return true
