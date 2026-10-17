class_name BonusRoom
extends RefCounted
## The secret inside the slot machine (godot/specs/gore_loot.md 14, modes_hud.md 6): after Gary has fixed the
## machine, shoot him once as he walks out; he trudges back, and his first swing at the cabinet sucks everyone in.
## 20 seconds of HOUSE MONEY: notes raining, skull stamps to shoot or dodge; then the run comes back exactly as it was
## (the paused wave, its enemies), each player keeping the better of their cash and +$10 for surviving.
## Once per world (a restart makes it available again).

const BOUNDS := Rect2(90, 135, 680, 332)       # BONUS_BOUNDS: left 90, right 770, top 135, bottom 467
const INTRO := 6.1
const LANDING := 0.85
const BONUS := 20.0
const PAYOUT := 1.6
const RETURN := 1.15

static func active(s: FightSim) -> bool:
	return s.secret != null and s.secret.phase != "done"

static func in_room(s: FightSim) -> bool:
	return s.secret != null and s.secret.room

## beginSlotSecret: save the run, start the cinematic.
static func begin(s: FightSim) -> void:
	if s.secret_used or s.over:
		return
	s.secret_used = true
	var sec := FT.Secret.new()
	sec.saved = _save(s)
	for p: FT.Fighter in s.players:
		sec.origins.append(Vector2(p.x, p.y))
		p.vx = 0.0
		p.vy = 0.0
		p.spin = 0.0
		p.muzzle = 0.0
		p.iframe = 0.0
	s.secret = sec
	s.freeze = 0.0
	s.shake = 0.0
	s.slot.flash = 0.0
	s.slot.busy = -1
	s.slot.broken = false
	s.banners.append(["", 0.0])

static func step(s: FightSim, inputs: Array, dt: float) -> void:
	var sec := s.secret
	sec.t += dt
	s.t += dt
	match sec.phase:
		"intro":
			if sec.t >= INTRO:
				_enter(s)
		"landing":
			if sec.t >= LANDING:
				sec.phase = "bonus"
				sec.t = 0.0
		"bonus":
			s.over = false
			if s.freeze > 0.0:
				s.freeze -= dt
			else:
				s.step_world(inputs, dt, true)
			s.over = false
			_rules(s, dt)
		"payout":
			if sec.t >= PAYOUT:
				_restore(s)
		"return":
			if sec.t >= RETURN:
				sec.phase = "done"
				sec.t = 0.0
				s.banner("GARY KEEPS THE CHANGE", 1.8)

static func _enter(s: FightSim) -> void:
	var sec := s.secret
	sec.phase = "landing"
	sec.t = 0.0
	sec.room = true
	sec.hazards = []
	sec.next_drop = 0.5
	sec.next_cash = 0.0
	s.enemies = []
	s.bullets = []
	s.shards = []
	s.coins = []
	s.bits = []
	s.blood = []
	s.splats = []
	s.corpses = []
	s.floaters = []
	s.plants = []
	s.husks = []
	s.rockets = []
	s.blasts = []
	s.rain = []
	s.nuke = null
	s.breather = 0.0
	s.pending = 0
	s.queue = []
	s.over = false
	s.janitor.phase = "done"
	s.sign = "gone"
	s.slot.broken = true
	s.slot.cool = 0.0
	s.slot.busy = -1
	for p: FT.Fighter in s.players:
		p.alive = true
		p.hp = s.tv("playerHp", 5)
		p.iframe = 0.0
		p.grace = 1.0
		p.x = FightSim.AW / 2.0 + (-55.0 if p.id == 0 else 55.0)
		p.y = 350.0
		p.vx = 0.0
		p.vy = 0.0
		p.roll = 0.0
		p.roll_cd = 0.0
		p.launch = 0.0
		p.spin = 0.0
		p.reload = 0.0
		p.pickup = 0.0
		p.throw = 0.0
		p.muzzle = 0.0
		p.cooldown = 0.0
		p.weapon = "blaster"
		p.w_time = 0.0
		p.blasters = 1
		p.speed = 0.0
		p.magnet = 0.0
		p.fx = 0.0
		p.fy = -1.0
		p.moving = false
		p.firing = false
		p.charging = false

# The room's rules each step (14.3).
static func _rules(s: FightSim, dt: float) -> void:
	var sec := s.secret
	for p: FT.Fighter in s.players:
		p.x = clampf(p.x, BOUNDS.position.x, BOUNDS.end.x)
		p.y = clampf(p.y, BOUNDS.position.y, BOUNDS.end.y)
	sec.next_cash -= dt
	sec.next_drop -= dt
	if sec.next_cash <= 0.0:
		sec.next_cash += 0.23
		var c := s._coin(105.0 + s.rnd() * 650.0, 160.0 + s.rnd() * 290.0, 0, 0, 5.0, 0.25)
		c.spin = 5.0
	if sec.next_drop <= 0.0:
		sec.next_drop = maxf(0.48, 1.05 - sec.t * 0.025)
		var alive := []
		for p: FT.Fighter in s.players:
			if p.alive:
				alive.append(p)
		var tx := 430.0
		var ty := 330.0
		if not alive.is_empty():
			var tp: FT.Fighter = alive[int(floor(s.rnd() * alive.size())) % alive.size()]
			tx = tp.x
			ty = tp.y
		var h := FT.Hazard.new()
		h.x = clampf(tx + (s.rnd() - 0.5) * 220.0, 95.0, 765.0)
		h.y = clampf(ty + (s.rnd() - 0.5) * 180.0, 165.0, 440.0)
		sec.hazards.append(h)
	for h: FT.Hazard in sec.hazards:
		h.t += dt
		if h.t < 1.25 and h.hp > 0.0:
			for b: FT.Bullet in s.bullets.duplicate():
				if Vector2(b.x - h.x, b.y - (h.y - 35.0)).length() <= 29.0:
					s.bullets.erase(b)
					h.hp -= b.dmg
					s.fx(FightSim.FX_HIT, h.x, h.y - 35.0)
		if h.hp <= 0.0 and not h.hit:
			h.hit = true
			h.t = 1.65
			s.fx(FightSim.FX_KILL, h.x, h.y)
			for i in 3:
				var c := s._coin(h.x + (i - 1) * 12.0, h.y, (i - 1) * 40.0, -20.0, 4.0, 0.2)
				c.rot = 0.0
				c.spin = 4.0
				c.phase = 0.0
		if h.t >= 1.25 and not h.hit:
			h.hit = true
			s.shake = 6.0
			s.fx(FightSim.FX_WALL, h.x, h.y)
			s.snd("stamp")
			for p: FT.Fighter in s.players:
				if not s.can_hurt(p):
					continue
				if Vector2(p.x - h.x, p.y - h.y).length() <= 40.0:
					p.hp -= 1.0
					p.iframe = 1.0
					s.fx(FightSim.FX_HURT, p.x, p.y)
					if p.hp <= 0.0:
						p.alive = false
						s.fx(FightSim.FX_DOWN, p.x, p.y)
	var keep := []
	for h: FT.Hazard in sec.hazards:
		if h.t < 1.85:
			keep.append(h)
	sec.hazards = keep
	sec.earned = _earned(s)
	var any := false
	for p: FT.Fighter in s.players:
		if p.alive:
			any = true
	if not any:
		_finish(s, false)
	elif sec.t >= BONUS:
		_finish(s, true)

static func _earned(s: FightSim) -> int:
	var n := 0
	var saved: Array = s.secret.saved.get("players", [])
	for i in s.players.size():
		var was: int = saved[i].get("coins", 0) if i < saved.size() else 0
		n += maxi(0, s.players[i].coins - was)
	return n

static func _finish(s: FightSim, survived: bool) -> void:
	var sec := s.secret
	sec.earned = _earned(s)
	sec.survived = survived
	sec.phase = "payout"
	sec.t = 0.0
	s.over = false
	s.freeze = 0.0
	s.shake = 0.0

# restoreFromMachine: the run comes back as it was.
static func _restore(s: FightSim) -> void:
	var sec := s.secret
	var cash := []
	for p: FT.Fighter in s.players:
		cash.append(p.coins)
	_load(s, sec.saved)
	sec.phase = "return"
	sec.t = 0.0
	sec.room = false
	s.over = false
	s.freeze = 0.0
	s.shake = 0.0
	s.events.clear()
	for i in s.players.size():
		var p: FT.Fighter = s.players[i]
		p.coins = maxi(p.coins, cash[i]) + (10 if sec.survived else 0)
		p.x = s.slot.x + (-55.0 if p.id == 0 else 55.0)
		p.y = s.slot.y + 125.0
		p.vx = 0.0
		p.vy = 0.0
		p.spin = 0.0
		p.roll = 0.0
		p.launch = 0.0
		p.muzzle = 0.0
		p.grace = 2.0
		p.iframe = 0.0
	for e: FT.Enemy in s.enemies:
		for p: FT.Fighter in s.players:
			if Vector2(p.x - e.x, p.y - e.y).length() < 120.0:
				e.y = maxf(FightSim.WALL + 30.0, e.y - 145.0)
				e.stun = 1.5
				break

# Saving the run: the lists are kept as they are (the room gets new ones), the players and the scalars are copied.
const LISTS := ["enemies", "bullets", "shards", "coins", "bits", "blood", "splats", "corpses", "floaters", "plants",
	"husks", "rockets", "blasts", "rain", "queue"]
const SCALARS := ["wave", "pending", "spawn_timer", "breather", "sign", "vend_sold", "plant_timer", "goth_down"]

static func _save(s: FightSim) -> Dictionary:
	var d := {}
	for k in LISTS:
		d[k] = s.get(k)
	for k in SCALARS:
		d[k] = s.get(k)
	d["nuke"] = s.nuke
	d["janitor"] = _props(s.janitor)
	d["janitor"]["phase"] = "done"
	d["janitor"]["secret_return"] = false
	d["slot"] = _props(s.slot)
	d["slot"]["broken"] = false
	d["slot"]["busy"] = -1
	d["goth"] = _props(s.goth) if s.goth else {}
	var ps := []
	for p: FT.Fighter in s.players:
		ps.append(_props(p))
	d["players"] = ps
	return d

static func _load(s: FightSim, d: Dictionary) -> void:
	for k in LISTS:
		s.set(k, d[k])
	for k in SCALARS:
		s.set(k, d[k])
	s.nuke = d["nuke"]
	_apply(s.janitor, d["janitor"])
	_apply(s.slot, d["slot"])
	if s.goth and not d["goth"].is_empty():
		_apply(s.goth, d["goth"])
	for i in s.players.size():
		if i < d["players"].size():
			var keep_node = s.players[i].node
			_apply(s.players[i], d["players"][i])
			s.players[i].node = keep_node

static func _props(o: Object) -> Dictionary:
	var d := {}
	for pr in o.get_property_list():
		if pr.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = o.get(pr.name)
			d[pr.name] = v.duplicate() if v is Array else v
	return d

static func _apply(o: Object, d: Dictionary) -> void:
	for k in d:
		o.set(k, d[k])
