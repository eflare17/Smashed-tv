class_name FightSim
extends RefCounted
## The fighting world, a pure simulation in HTML units stepped at 1/120 s like Smashed.html's stepBase
## (L7160-8296): players' weapons (and, in a run, their movement), bullets, thrown potatoes, rockets and blasts,
## the nuke, potato plants and falling potatoes, the wave director and enemies (EnemySim), the janitor
## (JanitorSim), Gothica in Protect mode (ProtectSim), the kill sequence with its gore (sparks, blood, stains,
## corpses and flying parts), hit-stop and shake, money (kill pay, loose notes, the magnet), the vending machine
## and the run's slot machine, floaters, the lobby target dummies.
##
## Views only read it. Sounds and banners are queued (sounds, banners) and the Fight node plays/shows them.
## One RNG (rnd(), the HTML LCG), one event list (events, for milestone 4), one step order (step()).
## Specs: godot/specs/weapons.md, enemies_waves.md, gore_loot.md, modes_hud.md (sections are cited as w3.1 etc.).

const DT := 1.0 / 120.0
const AW := 860.0                # ARENA.w
const AH := 520.0                # ARENA.h
const WALL := 18.0               # ARENA.wall
const SHOT_Z := 45.0             # the height bullets fly at in 3D (the HTML first person draws them at 40-50)

const FX_HIT := 0
const FX_KILL := 1
const FX_WALL := 2
const FX_HURT := 3
const FX_DOWN := 4
const FX_BOOM := 5
const FX_LAUNCH := 6
const FX_BLAST := 7
const FX_SPLASH := 8
const FX_DIVE := 9
## FX_LOOK: [count, colour, speed]
const FX_LOOK := [[4, "#f6d17a", 180], [14, "#6fd3a0", 260], [3, "#5a6274", 120], [10, "#e0473f", 220],
	[24, "#e0473f", 300], [36, "#ff9a6a", 420], [8, "#c9c9c9", 140], [40, "#ffb347", 520], [10, "#e6f7ff", 200],
	[16, "#ffffff", 260]]
const P_COLOURS := [Color("#e0473f"), Color("#4f9fe8")]
const PRIZES := [
	{"key": "blasters", "label": "REAL GUNS!", "weight": 3, "sym": 1},
	{"key": "shotgun", "label": "SHOTGUN!", "weight": 3, "sym": 1},
	{"key": "health", "label": "+2 HEALTH", "weight": 3, "sym": 0},
	{"key": "speed", "label": "SPEED BOOST", "weight": 2, "sym": 3},
	{"key": "clear", "label": "SCREEN CLEAR", "weight": 1, "sym": 4},
	{"key": "cash", "label": "JACKPOT!", "weight": 2, "sym": 2},
	{"key": "magnet", "label": "CASH MAGNET!", "weight": 2, "sym": 2},
	{"key": "bust", "label": "BUST!", "weight": 2, "sym": 5}]

var T: Dictionary = {}
var seed: int = 1
var t := 0.0
var freeze := 0.0
var shake := 0.0
var events: Array = []           ## [kind, x, y] since the last time the view took them
var sounds: Array = []           ## sound names to play (the Fight node drains it)
var banners: Array = []          ## [text, seconds]
var started := false
var over := false
var mode := "classic"
var wave := 0
var pending := 0
var queue: Array = []
var spawn_timer := 0.0
var breather := 1.2
var players: Array = []          ## FT.Fighter
var enemies: Array = []          ## FT.Enemy
var shards: Array = []           ## FT.Shard
var janitor := FT.Janitor.new()
var sign := "stand"
var slot := FT.Slot.new()
var vend_sold := false
var nuke: FT.Nuke = null
var bullets: Array = []
var husks: Array = []
var rockets: Array = []
var blasts: Array = []
var blast_id := 0
var plants: Array = []
var plant_timer := 0.0
var rain: Array = []
var bits: Array = []
var blood: Array = []
var splats: Array = []
var corpses: Array = []
var coins: Array = []
var floaters: Array = []
var dummies: Array = []
var goth: FT.Goth = null
var goth_down := false
var lobby_areas: Array = []      ## Rect2s: in the lobby a bullet is stopped outside all of them
var world_w := 2003.0
var world_h := 1998.0
var enemy_uid := 0
var secret: FT.Secret = null     ## the bonus room inside the slot machine, while it runs
var secret_used := false
var thud_cd := 0.0

# ETYPE as arrays (index t)
var e_key: Array[String] = []
var e_speed: Array[float] = []
var e_hp: Array[float] = []
var e_r: Array[float] = []
var e_dmg: Array[float] = []
var e_mass: Array[float] = []
var e_coins: Array[int] = []
var e_melee: Array[bool] = []
var e_col: Array[Color] = []

func _init() -> void:
	T = GameData.data.get("T", {})
	for e in GameData.data.get("ETYPE", []):
		e_key.append(String(e.get("key", "grunt")))
		e_speed.append(float(e.get("speed", 1)))
		e_hp.append(float(e.get("hp", 1)))
		e_r.append(float(e.get("r", 1)))
		e_dmg.append(float(e.get("dmg", 1)))
		e_mass.append(float(e.get("mass", 1)))
		e_coins.append(int(e.get("coins", 1)))
		e_melee.append(bool(e.get("melee", false)))
		e_col.append(Color(String(e.get("colour", "#6fd3a0"))))
	var calls: Dictionary = GameData.data.get("calls", {})
	for a in calls.get("lobbyAreas", []):
		lobby_areas.append(Rect2(float(a.x0), float(a.y0), float(a.x1) - float(a.x0), float(a.y1) - float(a.y0)))
	world_w = float(calls.get("worldW", 2003))
	world_h = float(calls.get("worldH", 1998))
	for d in calls.get("dummies", []):
		var dm := FT.Dummy.new()
		dm.x = float(d.x)
		dm.y = float(d.y)
		dm.hp = tv("dummyHp", 6)
		dummies.append(dm)
	slot.x = tv("loungeSlotX", 90)
	slot.y = WALL + 54.0 + tv("slotDrop", 38)

## A T value.
func tv(key: String, fallback: float = 0.0) -> float:
	return float(T.get(key, fallback))

## The world's RNG (rnd, L6060).
func rnd() -> float:
	seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(seed) / 4294967296.0

func e_rad(et: int) -> float:
	return tv("enemyRadius", 15) * e_r[et]

func e_max_hp(et: int) -> float:
	return maxf(1.0, round(tv("enemyHp", 3) * e_hp[et]))

## The lobby is the tall house (lounge, bedroom, yard); a run is the plain arena.
func lobby() -> bool:
	return not started

func ww() -> float:
	return world_w if lobby() else AW

func wh() -> float:
	return world_h if lobby() else AH

func add_player(node: Node3D, ch: String) -> FT.Fighter:
	var f := FT.Fighter.new()
	f.id = players.size()
	f.node = node
	f.ch = ch
	f.hp = tv("playerHp", 5)
	players.append(f)
	return f

## fillLobby: the lobby's blasters, 20 pellets and cash (only the players already here, weapons.md 3.3).
func fill_lobby() -> void:
	for f: FT.Fighter in players:
		f.weapon = "blaster"
		f.blasters = 1
		f.rockets = 0
		f.dump = 0.0
		f.ammo = int(tv("spudPellets", 10) * 2)
		f.coins = maxi(f.coins, int(maxf(tv("lobbyCash", 40), tv("testCash", 2500))))

# ---------------------------------------------------------------- effects (gore_loot.md 5)

func snd(name: String) -> void:
	sounds.append(name)

func banner(text: String, secs: float) -> void:
	banners.append([text, secs])

func fx(kind: int, x: float, y: float) -> void:
	var lk: Array = FX_LOOK[kind]
	burst(x, y, lk[0], Color(String(lk[1])), lk[2])
	if events.size() < 40:
		events.append([kind, round(x), round(y)])

func burst(x: float, y: float, n: int, col: Color, speed: float) -> void:
	for i in n:
		var a := rnd() * TAU
		var sp := speed * (0.3 + rnd() * 0.7)
		var b := FT.Bit.new()
		b.x = x
		b.y = y
		b.vx = cos(a) * sp
		b.vy = sin(a) * sp
		b.life = 0.25 + rnd() * 0.35
		b.col = col
		bits.append(b)
	if bits.size() > 600:
		bits = bits.slice(bits.size() - 600)

func spray(x: float, y: float, dx: float, dy: float, big: bool) -> void:
	var s := FT.Blood.new()
	s.x = x
	s.y = y
	s.a = atan2(dy, dx)
	s.big = big
	s.scale = (0.78 + rnd() * 0.42) * (tv("shotgunBlood", 1.5) * 0.8 if big else 1.0)
	blood.append(s)
	if blood.size() > 48:
		blood.pop_front()

func splat(x: float, y: float) -> void:
	if tv("splatMax", 140) <= 0:
		return
	var s := FT.Splat.new()
	s.x = x
	s.y = y
	s.k = int(floor(rnd() * 6))
	s.life = tv("splatLife", 45)
	s.a = rnd() * TAU
	s.scale = 0.7 + rnd() * 0.5
	splats.append(s)
	while splats.size() > int(tv("splatMax", 140)):
		splats.pop_front()

func floater(x: float, y: float, text: String, col: Color) -> void:
	var f := FT.Floater.new()
	f.x = x
	f.y = y
	f.text = text
	f.col = col
	floaters.append(f)

## killBurst (5.5): the body shoves what it falls into, five death sprays fan out, the hit-stop.
func kill_burst(x: float, y: float, dx: float, dy: float, big: bool) -> void:
	var base := atan2(dy, dx)
	for e: FT.Enemy in enemies:
		var ex: float = e.x - x
		var ey: float = e.y - y
		var d := sqrt(ex * ex + ey * ey)
		if d > 46.0 or d < 0.001:
			continue
		var push := (1.0 - d / 46.0) * 130.0 / e_mass[e.t]
		e.vx += ex / d * push
		e.vy += ey / d * push
		e.stun = maxf(e.stun, tv("stagger", 0.13) * 0.6)
	var n := maxi(1, int(round(tv("deathSpray", 5))))
	var mul := tv("shotgunBlood", 1.5) if big else 1.0
	for i in n:
		var tt := 0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * 2.0
		var a := base + tt * 0.38 + (rnd() - 0.5) * 0.22
		var far := rnd() < 0.3
		var d := (8.0 + rnd() * 10.0 if far else 2.0 + rnd() * 5.0) * tv("bloodReach", 0.68)
		var s := FT.Blood.new()
		s.x = x + cos(a) * d
		s.y = y + sin(a) * d
		s.a = a
		s.t = -i * 0.018
		s.big = true
		s.scale = tv("deathSize", 1.42) * mul * (0.9 if far else 0.8 + rnd() * 0.4)
		blood.append(s)
	while blood.size() > 48:
		blood.pop_front()
	freeze = maxf(freeze, tv("hitStop", 0.022) * (tv("hitStopBig", 2.2) if big else 1.0))

## makeCorpse (8.1): the body thrown, plus an arm and a leg (everything on a big kill).
func make_corpse(e: FT.Enemy, dx: float, dy: float, big: bool) -> void:
	var d := sqrt(dx * dx + dy * dy)
	if d < 0.0001:
		d = 1.0
	var angle := atan2(dy, dx)
	var sp := (170.0 + rnd() * 130.0) * tv("corpseFly", 1.35) * (1.7 if big else 1.0) / e_mass[e.t]
	var parts := [0, 1, 2, 3, 4] if big else [1 + int(floor(rnd() * 2)), 3 + int(floor(rnd() * 2))]
	var mask := 0
	for p in parts:
		mask |= 1 << p
	var body := _corpse_base(e, dx)
	body.vx = dx / d * sp
	body.vy = dy / d * sp
	body.spin = (rnd() - 0.5) * tv("corpseSpin", 7)
	body.part = -1
	body.mask = mask
	corpses.append(body)
	for p in parts:
		var a := angle + (rnd() - 0.5) * 2.5
		var speed := sp * (0.65 + rnd() * 0.9)
		var c := _corpse_base(e, dx)
		c.part = p
		c.z = 8.0
		c.vz = 100.0 + rnd() * 100.0
		c.vx = cos(a) * speed
		c.vy = sin(a) * speed
		c.spin = (rnd() - 0.5) * 18.0
		c.rot = rnd() * 6.0
		corpses.append(c)
	while corpses.size() > 90:
		corpses.pop_front()

func _corpse_base(e: FT.Enemy, dx: float) -> FT.Corpse:
	var c := FT.Corpse.new()
	c.x = e.x
	c.y = e.y
	c.t = e.t
	c.odo = e.odo
	c.flip = (e.vx if e.vx != 0.0 else dx) < 0.0
	c.life = tv("corpseLife", 7)
	c.max_life = c.life
	return c

## payKill (11.1): straight to the killer's wallet with a floater; split between the living if nobody owns it.
func pay_kill(x: float, y: float, et: int, owner: int) -> void:
	var n := int(round(e_coins[et] * tv("coinMult", 1)))
	if n <= 0:
		return
	var killer: FT.Fighter = players[owner] if owner >= 0 and owner < players.size() else null
	if tv("magnetBonus", 1) > 0 and killer and killer.alive and killer.magnet > 0.0:
		for i in int(tv("magnetBonus", 1)):
			var a := rnd() * TAU
			var sp := tv("coinPop", 150) * (0.5 + rnd() * 0.8)
			var c := _coin(x, y, cos(a) * sp, sin(a) * sp, tv("coinLife", 6), 0.18)
			c.owner = owner
			c.spin = (rnd() - 0.5) * 9.0
	if killer and killer.alive:
		killer.coins += n
		floater(x, y - 10.0, "$%d" % n, P_COLOURS[killer.id % 2])
	else:
		var alive := []
		for p: FT.Fighter in players:
			if p.alive:
				alive.append(p)
		if alive.is_empty():
			return
		var each := maxi(1, int(round(float(n) / alive.size())))
		for p in alive:
			p.coins += each
		floater(x, y - 10.0, "$%d" % n, Color("#7fd89a"))
	while floaters.size() > 30:
		floaters.pop_front()

func _coin(x: float, y: float, vx: float, vy: float, life: float, arm: float) -> FT.Coin:
	var c := FT.Coin.new()
	c.x = x
	c.y = y
	c.vx = vx
	c.vy = vy
	c.life = life
	c.arm = arm
	c.rot = rnd() * 6.28
	c.spin = (rnd() - 0.5) * 9.0
	c.phase = rnd() * 6.28
	coins.append(c)
	return c

## burstShrapnel: the brute goes off like a grenade.
func burst_shrapnel(x: float, y: float) -> void:
	fx(FX_BOOM, x, y)
	var n := int(round(tv("shrapCount", 8)))
	if n <= 0:
		return
	var r0 := rnd() * TAU
	for i in n:
		var a := r0 + float(i) / n * TAU
		var s := FT.Shard.new()
		s.x = x
		s.y = y
		s.vx = cos(a) * tv("shrapSpeed", 270)
		s.vy = sin(a) * tv("shrapSpeed", 270)
		s.life = tv("shrapLife", 1.1)
		shards.append(s)

## The kill sequence (gore 5.4), the same everywhere. shake_mul < 0: no kill shake (rockets, the nuke).
func kill_enemy(e: FT.Enemy, dx: float, dy: float, big: bool, owner: int, shake_mul: float, count: bool,
		shrapnel: bool = true) -> void:
	if e.t == 2 and shrapnel:
		burst_shrapnel(e.x, e.y)
	else:
		fx(FX_KILL, e.x, e.y)
	make_corpse(e, dx, dy, big)
	if shake_mul >= 0.0:
		shake = maxf(shake, tv("killShake", 5) * shake_mul)
	kill_burst(e.x, e.y, dx, dy, big)
	splat(e.x, e.y)
	pay_kill(e.x, e.y, e.t, owner)
	enemies.erase(e)
	if count and owner >= 0 and owner < players.size():
		players[owner].kills += 1

## A player hurt (contact, the swing, shrapnel, a stamp): hp, iframes, push, HURT or DOWN.
func hurt_player(p: FT.Fighter, dmg: float, nx: float, ny: float, push: float) -> void:
	p.hp -= dmg
	p.iframe = tv("iframes", 0.9)
	p.vx += nx * push
	p.vy += ny * push
	fx(FX_HURT, p.x, p.y)
	if p.hp <= 0.0:
		p.alive = false
		p.launch = 0.0
		if slot.busy == p.id:
			slot.busy = -1
			p.spin = 0.0
		fx(FX_DOWN, p.x, p.y)
		if goth == null:
			var any := false
			for q: FT.Fighter in players:
				if q.alive:
					any = true
			if not any:
				over = true

func can_hurt(p: FT.Fighter) -> bool:
	return p.alive and p.iframe <= 0.0 and p.grace <= 0.0

# ---------------------------------------------------------------- weapons (weapons.md 4)

func give_weapon(p: FT.Fighter, id: String) -> void:
	p.weapon = id
	p.w_time = tv("shotgunTime", 12) if id == "shotgun" else 0.0
	if id == "launcher":
		p.rockets = int(tv("launcherRounds", 3))
	if id == "blaster":
		p.blasters = 1
	if id != "spud":
		banner(String(WeaponDefs.w(id).get("name", id)).to_upper() + "!", 1.4)

func fallback_weapon(p: FT.Fighter) -> void:
	p.weapon = "blaster" if p.blasters > 0 else "spud"

## A slot machine prize (award, L6278): the run's machine uses it, and the lobby's can call it too.
func award(p: FT.Fighter, prize: int) -> void:
	var pr: Dictionary = PRIZES[clampi(prize, 0, PRIZES.size() - 1)]
	banner(pr.label, 1.6)
	slot.flash = 1.0
	match String(pr.key):
		"blasters":
			if p.blasters > 0:
				p.ammo = mini(int(tv("spudMaxAmmo", 200)), p.ammo + int(tv("spudPellets", 10) * 2))
			else:
				give_weapon(p, "blaster")
		"shotgun":
			give_weapon(p, "shotgun")
		"health":
			p.hp = minf(tv("playerHp", 5) + tv("overheal", 6), p.hp + 2.0)
		"speed":
			p.speed = tv("speedTime", 10)
		"magnet":
			p.magnet = tv("magnetTime", 14)
		"clear":
			drop_nuke()
		"cash":
			for i in 18:
				var a := float(i) / 18.0 * TAU + rnd() * 0.3
				var sp := 420.0 + rnd() * 340.0
				var c := _coin(slot.x, slot.y, cos(a) * sp, sin(a) * sp, tv("coinLife", 6) + 4.0, 0.85)
				c.spin = (rnd() - 0.5) * 16.0
		"bust":
			var a := rnd() * TAU
			var e := new_enemy(2, p.x + cos(a) * 90.0, p.y + sin(a) * 90.0)
			e.spawn = 0.6

func pick_prize() -> int:
	var r := rnd() * 18.0
	for i in PRIZES.size():
		r -= float(PRIZES[i].weight)
		if r <= 0.0:
			return i
	return 0

func drop_nuke() -> void:
	nuke = FT.Nuke.new()
	nuke.x = AW / 2.0
	nuke.y = AH / 2.0
	snd("whistle")

func new_enemy(et: int, x: float, y: float) -> FT.Enemy:
	var e := FT.Enemy.new()
	e.x = x
	e.y = y
	e.t = et
	e.hp = e_max_hp(et)
	enemy_uid += 1
	e.uid = enemy_uid
	enemies.append(e)
	return e

## The muzzle where shots start in the simulation (weapons.md 18.4): ahead of him by muzzleFwd, to the side for
## the blasters (gun 0 = his left hand, like the first-person view).
func muzzle_point(p: FT.Fighter, ax: float, ay: float, gun: int, two_handed: bool) -> Vector2:
	var fwd := tv("muzzleFwd", 30)
	var side := 0.0 if two_handed else (-1.0 if gun == 0 else 1.0) * tv("muzzleSide", 7)
	return Vector2(p.x + ax * fwd - ay * side, p.y + ay * fwd + ax * side)

## firePlayer (L6889).
func fire_player(p: FT.Fighter, ax: float, ay: float) -> void:
	var g := WeaponDefs.w(p.weapon)
	if g.get("fists", false):
		p.punch = tv("punchTime", 0.24)
		p.punched = false
		p.vx += ax * tv("punchLunge", 170)
		p.vy += ay * tv("punchLunge", 170)
		p.fx = ax
		p.fy = ay
		p.shots += 1
		snd("swing")
		return
	if g.get("lob", false):
		if p.ammo < int(tv("spudPellets", 10)):
			return
		p.ammo -= int(tv("spudPellets", 10))
		p.throw = tv("spudThrow", 0.5)
		p.threw = false
		p.throw_whole = true
		p.throw_pow = p.lob_pow if p.lob_pow > 0.0 else 0.5
		p.throw_dx = ax
		p.throw_dy = ay
		p.throw_dist = p.lob_dist if p.lob_dist > 0.0 else tv("lobNear", 110)
		p.throw_tx = p.tx
		p.throw_ty = p.ty
		p.fx = ax
		p.fy = ay
		p.shots += 1
		return
	if g.get("rocket", false):
		if p.rockets <= 0:
			return
		var mo := WeaponDefs.barrel(WeaponDefs.barrel_key(p.ch, p.weapon), WeaponDefs.oct_of(ax, ay), 0)
		var m := muzzle_point(p, ax, ay, 0, true)
		var dist := Vector2(p.tx - p.x, p.ty - p.y).length()
		var r := FT.Rocket.new()
		r.owner = p.id
		r.sx = m.x
		r.sy = m.y
		r.h0 = maxf(0.0, 12.6 - mo.y)
		r.tx = p.tx
		r.ty = p.ty
		r.big_h = tv("lobHeight", 110) * (0.35 + 0.65 * minf(1.0, dist / tv("lobMax", 420)))
		blast_id += 1
		r.id = blast_id
		rockets.append(r)
		p.rockets -= 1
		if p.rockets <= 0:
			p.dump = 0.7
		p.vx -= ax * tv("launcherRecoil", 320)
		p.vy -= ay * tv("launcherRecoil", 320)
		shake = maxf(shake, 6.0)
		fx(FX_LAUNCH, m.x - ax * 10.0, m.y - ay * 10.0)
		p.muzzle = float(g.get("flashTime", 0.12))
		p.mdx = ax
		p.mdy = ay
		p.last_gun = 0
		p.shots += 1
		return
	# bullets: blasters, shotgun, spud gun (8.2)
	var base := atan2(ay, ax)
	var spread := deg_to_rad(float(g.get("spread", tv("spread", 4))))
	var speed := float(g.get("speed", tv("bulletSpeed", 620)))
	var life := float(g.get("life", tv("bulletLife", 1.4)))
	var pellets := int(g.get("pellets", 1))
	var gun := 0 if pellets > 1 else (p.gun if tv("dualGuns", 1) > 0.0 else 0)
	p.last_gun = gun
	if pellets == 1:
		p.gun = 0 if p.gun == 1 else 1
	var jab := bool(g.get("jab", false))
	var m := muzzle_point(p, ax, ay, gun, pellets > 1 or jab)
	for i in pellets:
		var tt := 0.0 if pellets == 1 else (float(i) / (pellets - 1) - 0.5) * 2.0
		var a := base + tt * spread * 0.5 + (rnd() - 0.5) * spread * 0.35
		var b := FT.Bullet.new()
		b.owner = p.id
		b.x = m.x
		b.y = m.y
		b.x0 = p.x
		b.y0 = p.y
		b.vx = cos(a) * speed * (0.9 + rnd() * 0.2)
		b.vy = sin(a) * speed * (0.9 + rnd() * 0.2)
		b.life = life
		b.kb = float(g.get("knockMul", 1))
		b.size = float(g.get("size", tv("bulletSize", 4)))
		b.dmg = maxf(0.1, tv("enemyHp", 3) * float(g.dmgFrac)) if g.has("dmgFrac") else float(g.get("dmg", 1))
		b.spud = jab
		b.rot = rnd() * 6.28
		bullets.append(b)
	if g.get("ammo", false):
		p.ammo = maxi(0, p.ammo - 1)
	if jab:
		var per := int(tv("spudPellets", 10))
		if p.ammo > 0 and p.ammo % per == 0:
			p.throw = tv("spudThrow", 0.5)
			p.threw = false
			p.throw_whole = false
		elif p.ammo == 0:
			p.throw = tv("spudThrow", 0.5)
			p.threw = false
			p.throw_whole = false
		else:
			p.reload = tv("spudReload", 0.42)
	var rc := float(g.get("recoil", tv("recoil", 60)))
	p.vx -= ax * rc
	p.vy -= ay * rc
	snd("pop" if jab else ("shotgun" if pellets > 1 else "shot"))
	p.muzzle = float(g.get("flashTime", 0.055)) if float(g.get("flashTime", 0)) > 0.0 else 0.055
	p.mdx = ax
	p.mdy = ay
	p.shots += 1

## punchLand (L7010).
func punch_land(p: FT.Fighter) -> void:
	var f := Vector2(p.fx, p.fy)
	f = f.normalized() if f.length() > 0.001 else Vector2(0, 1)
	var h := Vector2(p.x, p.y) + f * tv("punchReach", 40) * 0.6
	var any := false
	for e: FT.Enemy in enemies.duplicate():
		if e.spawn > 0.0:
			continue
		var r := e_rad(e.t)
		if Vector2(e.x, e.y).distance_to(h) > tv("punchReach", 40) * 0.7 + r:
			continue
		any = true
		var mass: float = e_mass[e.t]
		e.hp -= maxf(0.1, tv("enemyHp", 3) * tv("punchDmg", 0.7))
		e.flash = 0.08
		e.stun = maxf(e.stun, tv("stagger", 0.13) * 1.5 / (mass if tv("staggerMass", 1) > 0.0 else 1.0))
		e.vx += f.x * tv("knockback", 170) * tv("punchKnock", 2.8) / mass
		e.vy += f.y * tv("knockback", 170) * tv("punchKnock", 2.8) / mass
		fx(FX_HIT, e.x - f.x * r * 0.5, e.y - f.y * r * 0.5)
		if e.hp <= 0.0:
			kill_enemy(e, f.x * 200.0, f.y * 200.0, false, p.id, 1.0, false)
	if lobby():
		for d: FT.Dummy in dummies:
			if d.down > 0.0:
				continue
			if Vector2(d.x, d.y).distance_to(h) <= tv("punchReach", 40) * 0.7 + 14.0:
				any = true
				d.hp -= 1.0
				d.flash = 0.1
				d.wob = 1.0
				fx(FX_HIT, d.x, d.y - 14.0)
	if any:
		shake = maxf(shake, 3.0)
		snd("punch")

## potatoSplat (L6972): a full-power potato bursts.
func potato_splat(x: float, y: float, owner: int) -> void:
	var R := tv("splatRadius", 72)
	burst(x, y, 16, Color("#e9c98f"), 280)
	burst(x, y, 10, Color("#8a5a2b"), 200)
	fx(FX_HIT, x, y)
	shake = maxf(shake, 5.0)
	floater(x, y - 30.0, "SPLAT!", Color("#e9c98f"))
	snd("splat")
	for e: FT.Enemy in enemies.duplicate():
		if e.spawn > 0.0:
			continue
		var dx: float = e.x - x
		var dy: float = e.y - y
		var d := sqrt(dx * dx + dy * dy)
		if d > R + e_rad(e.t):
			continue
		var f := minf(1.0, d / R)
		var u := Vector2(dx, dy) / d if d > 0.001 else Vector2(0, -1)
		var mass: float = e_mass[e.t]
		e.hp -= maxf(0.1, tv("enemyHp", 3) * tv("splatDmg", 0.9) * (1.0 - 0.7 * f))
		e.flash = 0.08
		e.stun = maxf(e.stun, tv("stagger", 0.13))
		var k := tv("knockback", 170) * tv("splatKnock", 1.8) * (1.0 - 0.5 * f) / mass
		e.vx += u.x * k
		e.vy += u.y * k
		if e.hp <= 0.0:
			kill_enemy(e, u.x * 200.0, u.y * 200.0, false, owner, 1.0, false)
	if lobby():
		for dm: FT.Dummy in dummies:
			if dm.down <= 0.0 and Vector2(dm.x, dm.y).distance_to(Vector2(x, y)) <= R + 14.0:
				dm.hp -= 1.0
				dm.flash = 0.1
				dm.wob = 1.0
				fx(FX_HIT, dm.x, dm.y - 14.0)

## rocketAt (L7052): where a rocket is t seconds in: ground point, height, heading on screen.
func rocket_at(r: FT.Rocket, tt: float) -> Dictionary:
	var D := maxf(0.05, tv("lobTime", 0.75))
	var s := clampf(tt / D, 0.0, 1.0)
	var gx := r.sx + (r.tx - r.sx) * s
	var gy := r.sy + (r.ty - r.sy) * s
	var h := r.h0 * (1.0 - s) + 4.0 * r.big_h * s * (1.0 - s)
	var dh := (-r.h0 + 4.0 * r.big_h * (1.0 - 2.0 * s)) / D
	return {"x": gx, "y": gy, "h": h, "vx": (r.tx - r.sx) / D, "vy": (r.ty - r.sy) / D, "vh": dh, "s": s}

## detonate (L7080).
func detonate(x: float, y: float, owner: int, dx: float, dy: float) -> void:
	var R := tv("blastRadius", 110)
	var b := FT.Blast.new()
	b.x = x
	b.y = y
	blast_id += 1
	b.id = blast_id
	blasts.append(b)
	shake = maxf(shake, tv("blastShake", 18))
	freeze = maxf(freeze, 0.06)
	fx(FX_BLAST, x, y)
	for e: FT.Enemy in enemies.duplicate():
		if e.spawn > 0.0:
			continue
		var ex: float = e.x - x
		var ey: float = e.y - y
		var d := sqrt(ex * ex + ey * ey)
		if d > R + e_rad(e.t):
			continue
		var f := minf(1.0, d / R)
		e.hp -= tv("enemyHp", 3) * tv("blastDmg", 4) * (1.0 - f * (1.0 - tv("blastEdge", 0.35)))
		e.flash = 0.1
		var u := Vector2(ex, ey) / d if d > 0.001 else Vector2(dx, dy).normalized()
		if e.hp <= 0.0:
			kill_enemy(e, ex if ex != 0.0 else dx, ey if ey != 0.0 else dy, true, owner, -1.0, true)
		else:
			var k := tv("blastPush", 520) * (1.0 - 0.5 * f) / e_mass[e.t]
			e.vx += u.x * k
			e.vy += u.y * k
			e.stun = maxf(e.stun, 0.6)
	if lobby():
		for dm: FT.Dummy in dummies:
			if dm.down <= 0.0 and Vector2(dm.x, dm.y).distance_to(Vector2(x, y)) <= R + 16.0:
				dm.hp = 0.0
				dm.down = tv("dummyRespawn", 2.5)
				kill_burst(dm.x, dm.y - 14.0, dm.x - x, dm.y - y, true)
				splat(dm.x, dm.y + 8.0)
	var reach := R * tv("blastSelf", 1.4)
	for p: FT.Fighter in players:
		if not p.alive:
			continue
		var px: float = p.x - x
		var py: float = p.y - y
		var d := sqrt(px * px + py * py)
		if d > reach:
			continue
		var k := 1.0 - d / reach
		var u := Vector2(px, py) / d if d > 0.001 else -Vector2(dx, dy).normalized()
		var v := u * tv("blastYeet", 620) * (0.4 + 0.6 * k)
		p.vx = v.x
		p.vy = v.y
		p.roll = 0.0
		p.launch = maxf(p.launch, 0.25 + 0.5 * k)
		p.iframe = maxf(p.iframe, 0.6)

## plantSpud (L5979).
func plant_spud(progress: float) -> void:
	if plants.size() >= int(tv("spudMax", 6)):
		return
	var m := WALL + 40.0
	var x := 0.0
	var y := 0.0
	for tries in 12:
		x = m + rnd() * (AW - 2.0 * m)
		y = m + 60.0 + rnd() * (AH - 2.0 * m - 60.0)
		var ok := true
		if Vector2(x, y).distance_to(Vector2(slot.x, slot.y)) < 90.0:
			ok = false
		if ok and started and Vector2(x, y).distance_to(vend_pos()) < 90.0:
			ok = false
		if ok:
			for pl: FT.Plant in plants:
				if Vector2(x, y).distance_to(Vector2(pl.x, pl.y)) < 70.0:
					ok = false
					break
		if ok:
			for p: FT.Fighter in players:
				if Vector2(x, y).distance_to(Vector2(p.x, p.y)) < 60.0:
					ok = false
					break
		if ok:
			break
	var pl := FT.Plant.new()
	pl.x = x
	pl.y = y
	pl.t = progress * tv("spudGrow", 9)
	plants.append(pl)

func vend_pos() -> Vector2:
	return Vector2(AW * tv("vendX", 0.82), WALL + 54.0 + tv("vendDrop", 82))

## Potatoes from the gym's bell rope (pullRope, L9997): for the lobby's rope to call.
func rope_rain() -> void:
	for i in int(tv("ropeCount", 10)):
		var r := FT.Rain.new()
		r.x = 318.0 + rnd() * 262.0
		r.y = 126.0 + rnd() * 108.0
		r.dz = 380.0 + rnd() * 160.0
		r.delay = 0.35 + i * 0.12 + rnd() * 0.08
		r.spin = (rnd() - 0.5) * 10.0
		rain.append(r)
	floater(tv("ropeX", 345), tv("ropeY", 152) - 30.0, "POTATOES!", Color("#d8b878"))

# ---------------------------------------------------------------- the run (enemies_waves.md 3)

## startGame (L13549), with the README's fix: what's left over from the lobby is cleared and everyone revived.
func start_run(run_mode: String) -> void:
	if started:
		return
	started = true
	over = false
	mode = run_mode
	goth_down = false
	breather = tv("intermission", 2.2)
	dummies.clear()
	enemies.clear()
	bullets.clear()
	shards.clear()
	husks.clear()
	rockets.clear()
	blasts.clear()
	nuke = null
	rain.clear()
	for p: FT.Fighter in players:
		p.coins = int(tv("testCash", 2500))
		p.rockets = 0
		p.dump = 0.0
		p.buy = 0.0
		p.hp = tv("playerHp", 5)
		p.alive = true
		p.launch = 0.0
		p.iframe = 0.0
		p.spin = 0.0
		p.weapon = "spud"
		p.blasters = 0
		p.ammo = maxi(p.ammo, int(tv("spudPellets", 10) * tv("spudStart", 0)))
		p.reload = 0.0
		p.w_time = 0.0
		p.speed = 0.0
		p.magnet = 0.0
		p.roll = 0.0
		p.roll_cd = 0.0
		p.vx = 0.0
		p.vy = 0.0
		if p.y > AH + 40.0 or p.x > AW:
			# in the yard (or the bedroom): back in the lounge at the back door
			p.x = clampf(645.0, WALL + 14.0, AW - WALL - 14.0)
			p.y = AH - WALL - tv("radius", 14) - 6.0
		p.x = clampf(p.x, WALL + tv("radius", 14), AW - WALL - tv("radius", 14))
		p.y = clampf(p.y, WALL + tv("radius", 14), AH - WALL - tv("radius", 14))
	coins.clear()
	plants.clear()
	plant_timer = 1.5
	slot.x = AW * 0.5
	slot.y = WALL + 54.0 + tv("slotDrop", 38)
	plant_spud(0.3)
	plant_spud(0.6)
	plant_spud(0.9)
	corpses.clear()
	blood.clear()
	splats.clear()
	slot.cool = 0.0
	slot.busy = -1
	slot.broken = true
	sign = "stand"
	janitor = FT.Janitor.new()
	goth = ProtectSim.new_goth(self) if run_mode == "protect" else null

func start_wave() -> void:
	wave += 1
	vend_sold = false
	queue = EnemySim.wave_mix(self, wave)
	pending = queue.size()
	spawn_timer = 0.0
	for p: FT.Fighter in players:
		if not p.alive:
			p.alive = true
			p.x = 430.0
			p.y = 260.0
			p.vx = 0.0
			p.vy = 0.0
			p.roll = 0.0
			p.roll_cd = 0.0
		p.hp = maxf(p.hp, tv("playerHp", 5))
		p.grace = 1.0

# ---------------------------------------------------------------- the step (stepBase)

## One fixed step. inputs: an FT.Inp per player. drive: the sim moves the players (the run); in the lobby the
## Player nodes move themselves and the sim only reads their positions and adds its pushes to their velocity.
func step(inputs: Array, dt: float = DT) -> void:
	if secret and secret.phase != "done":
		BonusRoom.step(self, inputs, dt)
		return
	if over:
		shake = maxf(0.0, shake - 90.0 * dt)          # (the HTML's shake froze at game over: let it settle)
		return
	if freeze > 0.0:
		freeze -= dt
		return
	t += dt
	step_world(inputs, dt, false)

## The world's step (stepBase). room: inside the slot machine (no waves, no Gary, no growing potatoes, no Gothica).
func step_world(inputs: Array, dt: float, room: bool) -> void:
	thud_cd = maxf(0.0, thud_cd - dt)
	for i in players.size():
		var inp: FT.Inp = inputs[i] if i < inputs.size() and inputs[i] != null else FT.Inp.new()
		_step_player(players[i], inp, dt)
	if started and not over and not room:
		EnemySim.step_director(self, dt)
	EnemySim.step_enemies(self, dt)
	_step_bullets(dt)
	EnemySim.step_shards(self, dt)
	if started and not room:
		JanitorSim.step(self, dt)
		if secret and secret.phase == "intro":
			return
	_step_nuke(dt)
	_step_rockets(dt)
	shake = maxf(0.0, shake - 90.0 * dt)
	if not room:
		_step_plants(dt)
	if goth and not room:
		ProtectSim.step(self, dt)
	_step_rain(dt)
	_step_husks(dt)
	_step_timers(dt)
	if lobby():
		for d: FT.Dummy in dummies:
			d.flash = maxf(0.0, d.flash - dt)
			d.wob *= pow(0.02, dt)
			if d.down > 0.0:
				d.down -= dt
				if d.down <= 0.0:
					d.hp = tv("dummyHp", 6)
					d.wob = 0.0
	slot.flash = maxf(0.0, slot.flash - dt)
	for f: FT.Floater in floaters.duplicate():
		f.t += dt
		f.y -= 34.0 * dt
		if f.t > 0.9:
			floaters.erase(f)
	_step_corpses(dt)
	for s: FT.Blood in blood.duplicate():
		s.t += dt
		if s.t > tv("bloodTime", 0.34):
			blood.erase(s)
	for s: FT.Splat in splats.duplicate():
		s.life -= dt
		if s.life <= 0.0:
			splats.erase(s)
	slot.cool = maxf(0.0, slot.cool - dt)
	_step_coins(dt)
	var drag := pow(0.9, dt * 60.0)
	var keep := []
	for b: FT.Bit in bits:
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.vx *= drag
		b.vy *= drag
		b.life -= dt
		if b.life > 0.0:
			keep.append(b)
	bits = keep

func _carrying(p: FT.Fighter) -> bool:
	return goth != null and goth.carrier == p.id

# The players block (L7169-7525). In the lobby the Player node moves him; the sim does the rest.
func _step_player(p: FT.Fighter, inp: FT.Inp, dt: float) -> void:
	var drive := started or p.driven
	if _carrying(p):
		inp.shoot = false
		inp.roll = false
	if goth and inp.use:
		ProtectSim.carry_toggle(self, p)
	# weapon switch
	if inp.wsel != "" and inp.wsel != p.weapon and WeaponDefs.has_weapon(p, inp.wsel) and p.dump <= 0.0 and p.spin <= 0.0:
		p.weapon = inp.wsel
		p.lob_held = false
		p.aim_on = false
		p.charging = false          # (w17.2: switching away mid wind-up drops the wind-up)
		p.charge = 0.0
		snd("switch")
	p.iframe = maxf(0.0, p.iframe - dt)
	p.muzzle = maxf(0.0, p.muzzle - dt)
	p.cooldown = maxf(p.cooldown - dt, -dt)
	if not p.alive:
		return
	if drive:
		p.roll = maxf(0.0, p.roll - dt)
		p.roll_cd = maxf(0.0, p.roll_cd - dt)
	p.grace = maxf(0.0, p.grace - dt)
	if started:
		p.speed = maxf(0.0, p.speed - dt)
		p.magnet = maxf(0.0, p.magnet - dt)
		if p.w_time > 0.0:
			p.w_time -= dt
			if p.w_time <= 0.0:
				p.w_time = 0.0
				if p.weapon == "shotgun":
					fallback_weapon(p)
	# pulling the slot machine: rooted
	if p.spin > 0.0:
		p.spin -= dt
		var k := pow(0.001, dt)
		p.vx *= k
		p.vy *= k
		if drive:
			p.x += p.vx * dt
			p.y += p.vy * dt
		if p.spin <= 0.0:
			p.spin = 0.0
			slot.cool = tv("spinCool", 8)
			slot.busy = -1
			award(p, slot.prize if slot.prize >= 0 else pick_prize())
		return
	if p.dump > 0.0:
		p.dump -= dt
		if p.dump <= 0.0:
			p.dump = 0.0
			if p.weapon == "launcher":
				fallback_weapon(p)
			banner("EMPTY!", 1.0)
			snd("empty")
	var still := absf(inp.mx) < 0.001 and absf(inp.my) < 0.001
	# buying the launcher (run only)
	var vp := vend_pos()
	if started and not over and not vend_sold and p.weapon != "launcher" and p.coins >= int(tv("vendPrice", 2500)) \
			and still and not inp.shoot and Vector2(p.x, p.y).distance_to(vp) <= tv("vendRadius", 56):
		p.buy += dt
		if p.buy >= tv("vendHold", 0.8):
			p.buy = 0.0
			p.coins -= int(tv("vendPrice", 2500))
			vend_sold = true
			give_weapon(p, "launcher")
			p.cooldown = 0.35
			floater(vp.x, vp.y - 40.0, "-$%d" % int(tv("vendPrice", 2500)), Color("#e0473f"))
			snd("bought")
	else:
		p.buy = 0.0
	# starting a pull (the run's machine, once the janitor's fixed it)
	if started and not over and not slot.broken and slot.cool <= 0.0 and slot.busy < 0 and still \
			and p.coins >= int(tv("spinCost", 5)) and Vector2(p.x, p.y).distance_to(Vector2(slot.x, slot.y)) <= tv("slotRadius", 46):
		p.coins -= int(tv("spinCost", 5))
		p.spin = tv("spinTime", 1.6)
		slot.busy = p.id
		slot.prize = pick_prize()
		slot.decoy = [int(floor(rnd() * 6)), int(floor(rnd() * 6))]
		return
	# movement (the run; the lobby's Player moves himself)
	var mv := Vector2(inp.mx, inp.my)
	var mlen := mv.length()
	p.moving = mlen > 0.001
	if p.moving:
		p.ix = mv.x / maxf(mlen, 1.0)
		p.iy = mv.y / maxf(mlen, 1.0)
	if drive:
		if inp.roll and p.roll <= 0.0 and p.roll_cd <= 0.0:
			var d := mv.normalized() if mlen > 0.001 else Vector2(p.fx, p.fy).normalized()
			if d.length() < 0.001:
				d = Vector2(0, 1)
			p.roll = tv("rollTime", 0.42)
			p.roll_cd = tv("rollTime", 0.42) + tv("rollCooldown", 0.55)
			p.rdx = d.x
			p.rdy = d.y
			p.vx = d.x * tv("rollSpeed", 620)
			p.vy = d.y * tv("rollSpeed", 620)
			p.iframe = maxf(p.iframe, tv("rollInvuln", 0.3))
		if p.launch > 0.0:
			# blown away: no control, no cap, drag, bounces off the walls
			p.launch -= dt
			var k := pow(tv("launchDrag", 0.25), dt)
			p.vx *= k
			p.vy *= k
			p.x += p.vx * dt
			p.y += p.vy * dt
			var r := tv("radius", 14)
			var lo := WALL + r
			var bounced := 0.0
			if p.x < lo:
				p.x = lo
				bounced = absf(p.vx)
				p.vx = absf(p.vx) * tv("playerBounce", 0.55)
			elif p.x > AW - lo:
				p.x = AW - lo
				bounced = absf(p.vx)
				p.vx = -absf(p.vx) * tv("playerBounce", 0.55)
			if p.y < lo:
				p.y = lo
				bounced = maxf(bounced, absf(p.vy))
				p.vy = absf(p.vy) * tv("playerBounce", 0.55)
			elif p.y > AH - lo:
				p.y = AH - lo
				bounced = maxf(bounced, absf(p.vy))
				p.vy = -absf(p.vy) * tv("playerBounce", 0.55)
			if bounced > 120.0:
				shake = maxf(shake, 14.0)
				fx(FX_WALL, p.x, p.y)
				snd("bounce")
			if p.launch <= 0.0:
				p.launch = 0.0
				p.vx *= 0.3
				p.vy *= 0.3
			return
		if p.roll > 0.0:
			var frac := clampf(1.0 - p.roll / maxf(0.05, tv("rollTime", 0.42)), 0.0, 0.9999)
			var fr := CharFrames.ROLL_FRAMES
			var acc := 0.0
			var idx := fr.size() - 1
			var tt := 1.0
			for n in fr.size():
				var dd: float = fr[n]["dur"]
				if frac < acc + dd:
					idx = n
					tt = (frac - acc) / dd
					break
				acc += dd
			var s0: float = fr[idx]["speed"]
			var s1: float = fr[mini(fr.size() - 1, idx + 1)]["speed"]
			var spd := (s0 + (s1 - s0) * tt) * tv("rollSpeed", 620)
			p.vx = p.rdx * spd
			p.vy = p.rdy * spd
			p.fx = p.rdx
			p.fy = p.rdy
			_integrate(p, dt)
			return
		if p.moving:
			var n := mv / mlen if mlen > 1.0 else mv
			p.vx += n.x * tv("accel", 2200) * dt
			p.vy += n.y * tv("accel", 2200) * dt
			p.fx = p.ix
			p.fy = p.iy
		else:
			var sp := Vector2(p.vx, p.vy).length()
			if sp > 0.0:
				var drop := minf(sp, tv("friction", 1900) * dt)
				p.vx -= p.vx / sp * drop
				p.vy -= p.vy / sp * drop
	else:
		# the lobby: rolling or thrown, no shooting (the Player node runs the roll)
		if p.roll > 0.0:
			return
		if p.moving:
			p.fx = p.ix
			p.fy = p.iy
	# aim and fire
	var ax := inp.ax
	var ay := inp.ay
	var alen := sqrt(ax * ax + ay * ay)
	p.firing = inp.shoot
	if alen > 0.001:
		p.fx = ax / alen
		p.fy = ay / alen
	if p.weapon == "launcher":
		_launcher_block(p, inp, ax, ay, alen)
	else:
		p.aim_on = false
		p.lob_held = false
	if p.weapon == "lob":
		_lob_block(p, inp, ax, ay, alen, dt)
	elif inp.shoot and p.weapon != "launcher":
		if alen > 0.001:
			ax /= alen
			ay /= alen
		else:
			var fv := Vector2(p.fx, p.fy).normalized()
			if fv.length() < 0.001:
				fv = Vector2(0, 1)
			ax = fv.x
			ay = fv.y
		p.fx = ax
		p.fy = ay
		p.adx = ax
		p.ady = ay
		if p.cooldown <= 0.0:
			if p.reload > 0.0 or p.pickup > 0.0 or p.throw > 0.0 or p.dump > 0.0:
				pass
			elif WeaponDefs.uses_ammo(p.weapon) and p.ammo < 1:
				p.dry_hint = 1.2
				p.click -= tv("spudEmpty", 0.18)          # (w17.1: a click every spudEmpty)
				if p.click <= 0.0:
					p.click = tv("spudEmpty", 0.18)
					snd("click")
				p.cooldown += tv("spudEmpty", 0.18)
			else:
				fire_player(p, ax, ay)
				p.cooldown += 1.0 / WeaponDefs.fire_rate(p.weapon)
	elif p.cooldown < 0.0:
		p.cooldown = 0.0
	if drive:
		var cap := tv("maxSpeed", 260) * (tv("speedMul", 1.55) if p.speed > 0.0 else 1.0) * (ProtectSim.carry_slow() if _carrying(p) else 1.0)
		var sp2 := Vector2(p.vx, p.vy).length()
		if sp2 > cap:
			p.vx = p.vx / sp2 * cap
			p.vy = p.vy / sp2 * cap
		_integrate(p, dt)

func _integrate(p: FT.Fighter, dt: float) -> void:
	if not started:
		# the lobby: the Fight node moves his body with these velocities, sliding along the house's walls
		p.odo += Vector2(p.vx, p.vy).length() * dt
		return
	p.x += p.vx * dt
	p.y += p.vy * dt
	p.odo += Vector2(p.vx, p.vy).length() * dt
	var r := tv("radius", 14)
	if p.x < WALL + r:
		p.x = WALL + r
		p.vx = maxf(0.0, p.vx)
	elif p.x > AW - WALL - r:
		p.x = AW - WALL - r
		p.vx = minf(0.0, p.vx)
	if p.y < WALL + r:
		p.y = WALL + r
		p.vy = maxf(0.0, p.vy)
	elif p.y > AH - WALL - r:
		p.y = AH - WALL - r
		p.vy = minf(0.0, p.vy)

func _launcher_block(p: FT.Fighter, inp: FT.Inp, ax: float, ay: float, alen: float) -> void:
	var f0 := Vector2(p.fx, p.fy).length()
	if f0 < 0.001:
		f0 = 1.0
	var live := false
	var dir := Vector2(p.fx, p.fy) / f0
	var dist := tv("lobDefault", 220)
	if inp.st:
		live = alen > 0.25
		if live:
			dir = Vector2(ax, ay) / alen
		dist = tv("lobMin", 50) + (tv("lobMax", 420) - tv("lobMin", 50)) * clampf((alen - 0.15) / 0.8, 0.0, 1.0)
	elif alen > 0.0:
		live = true
		dir = Vector2(ax, ay) / alen
		dist = minf(alen, tv("lobMax", 420))
	else:
		live = not inp.tc
	var m := WALL + 6.0
	if inp.tap != 0 and inp.tap != p.last_tap:
		p.last_tap = inp.tap
		p.lob_held = false
		p.tx = clampf(inp.tx, m, ww() - m)
		p.ty = clampf(inp.ty, m, wh() - m)
		p.aim_on = true
		var dd := Vector2(p.tx - p.x, p.ty - p.y)
		if dd.length() > 1.0:
			dir = dd.normalized()
		p.tap_fire = true
	elif p.lob_held and not inp.st:
		dir = Vector2(p.adx, p.ady)
	else:
		p.tx = clampf(p.x + dir.x * dist, m, ww() - m)
		p.ty = clampf(p.y + dir.y * dist, m, wh() - m)
		p.aim_on = live
	p.fx = dir.x
	p.fy = dir.y
	p.adx = dir.x
	p.ady = dir.y
	var fire := false
	if inp.st and not p.tap_fire:
		if live:
			p.lob_held = true
			p.firing = true
		else:
			p.lob_held = false
	else:
		if p.tap_fire:
			fire = true
			p.tap_fire = false
		elif p.lob_held:
			fire = true
			p.lob_held = false
		elif inp.shoot:
			fire = true
		p.firing = inp.shoot
	if p.cooldown > 0.0:
		p.tap_fire = false
	elif fire and p.dump <= 0.0 and p.rockets > 0:
		p.firing = true
		fire_player(p, dir.x, dir.y)
		p.cooldown += 1.0 / tv("launcherRate", 1.1)
	elif p.cooldown < 0.0:
		p.cooldown = 0.0

func _lob_block(p: FT.Fighter, inp: FT.Inp, ax: float, ay: float, alen: float, dt: float) -> void:
	var busy := p.reload > 0.0 or p.pickup > 0.0 or p.throw > 0.0
	var dir := Vector2(ax, ay) / alen if alen > 0.001 else Vector2(p.fx, p.fy).normalized()
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	var dist: float
	if inp.st:
		dist = tv("lobNear", 110) + (tv("lobFar", 430) - tv("lobNear", 110)) * clampf((alen - 0.15) / 0.8, 0.0, 1.0)
	elif alen > 0.0:
		dist = minf(alen, tv("lobFar", 430))
	else:
		dist = tv("lobNear", 110)
	if inp.lt:
		var d := Vector2(inp.lx - p.x, inp.ly - p.y)
		if d.length() > 1.0:
			dir = d.normalized()
			dist = minf(d.length(), tv("lobFar", 430))
	var per := int(tv("spudPellets", 10))
	if inp.shoot and not busy and p.ammo >= per:
		p.charge = minf(1.0, p.charge + dt / tv("lobCharge", 0.3))
		p.charging = true
		p.fx = dir.x
		p.fy = dir.y
		p.adx = dir.x
		p.ady = dir.y
		p.firing = true
		var m := WALL + 6.0
		p.tx = clampf(p.x + dir.x * dist, m, ww() - m)
		p.ty = clampf(p.y + dir.y * dist, m, wh() - m)
		p.aim_on = true
	elif p.charging and not busy:
		p.charging = false
		p.lob_pow = 0.2 + 0.8 * p.charge
		p.charge = 0.0
		p.aim_on = false
		var tl := Vector2(p.tx - p.x, p.ty - p.y)
		if tl.length() > 1.0:
			dir = tl.normalized()
		p.lob_dist = maxf(20.0, tl.length())
		p.fx = dir.x
		p.fy = dir.y
		fire_player(p, dir.x, dir.y)
	elif inp.shoot and not busy and p.ammo < per:
		p.dry_hint = 1.2
		p.click -= dt
		if p.click <= 0.0:
			p.click = tv("spudEmpty", 0.18)
			snd("click")
	else:
		p.charging = false
		p.charge = 0.0
		p.aim_on = false

# ---------------------------------------------------------------- things in flight

## segmentHit (L7147): 0 if the start is inside, else the first t in [0, 1] where the segment meets the circle, or -1.
static func segment_hit(x0: float, y0: float, x1: float, y1: float, cx: float, cy: float, r: float) -> float:
	var dx := x1 - x0
	var dy := y1 - y0
	var fx0 := x0 - cx
	var fy0 := y0 - cy
	var c := fx0 * fx0 + fy0 * fy0 - r * r
	if c <= 0.0:
		return 0.0
	var a := dx * dx + dy * dy
	if a < 1e-9:
		return -1.0
	var b := 2.0 * (fx0 * dx + fy0 * dy)
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var tt := (-b - sqrt(disc)) / (2.0 * a)
	if tt < 0.0 or tt > 1.0:
		return -1.0
	return tt

func in_lobby_floor(x: float, y: float) -> bool:
	for r: Rect2 in lobby_areas:
		if r.has_point(Vector2(x, y)):
			return true
	return false

func _step_bullets(dt: float) -> void:
	var keep := []
	for i in range(bullets.size() - 1, -1, -1):
		var b: FT.Bullet = bullets[i]
		var ox := b.x
		var oy := b.y
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.travelled += Vector2(b.vx, b.vy).length() * dt
		b.life -= dt
		var gone := false
		# the janitor first
		if started and JanitorSim.shootable(self):
			var jt := segment_hit(ox, oy, b.x, b.y, janitor.x, janitor.y - 16.0, 20.0)
			if jt >= 0.0:
				fx(FX_HIT, b.x, b.y)
				JanitorSim.on_shot(self, b)
				continue
		# the nearest enemy along the shot
		var best: FT.Enemy = null
		var bt := 2.0
		var rr := tv("bulletSize", 4) / 2.0
		for e: FT.Enemy in enemies:
			if e.spawn > 0.0:
				continue
			var ht := segment_hit(ox, oy, b.x, b.y, e.x, e.y, e_rad(e.t) + rr)
			if ht >= 0.0 and ht < bt:
				bt = ht
				best = e
		if best:
			b.x = ox + (b.x - ox) * bt
			b.y = oy + (b.y - oy) * bt
			var mass: float = e_mass[best.t]
			best.hp -= b.dmg
			best.flash = 0.08
			best.stun = maxf(best.stun, tv("stagger", 0.13) / (mass if tv("staggerMass", 1) > 0.0 else 1.0))
			var sp := Vector2(b.vx, b.vy).length()
			if sp > 0.001:
				best.vx += b.vx / sp * tv("knockback", 170) * b.kb / mass
				best.vy += b.vy / sp * tv("knockback", 170) * b.kb / mass
			fx(FX_HIT, b.x, b.y)
			spray(b.x, b.y, b.vx, b.vy, b.kb > 1.5)
			if best.hp <= 0.0:
				var big := b.kb > 1.5
				kill_enemy(best, b.vx, b.vy, big, b.owner, tv("killShakeBig", 3.2) if big else 1.0, true)
			continue
		if lobby():
			var hit_d := false
			for d: FT.Dummy in dummies:
				if d.down > 0.0:
					continue
				if Vector2(b.x, b.y).distance_to(Vector2(d.x, d.y - 14.0)) <= 20.0:
					hit_d = true
					d.hp -= 1.0
					d.flash = 0.08
					d.wob = 0.5
					fx(FX_HIT, b.x, b.y)
					spray(b.x, b.y, b.vx, b.vy, b.kb > 1.5)
					if d.hp <= 0.0:
						d.down = tv("dummyRespawn", 2.5)
						kill_burst(d.x, d.y - 14.0, b.vx, b.vy, b.kb > 1.5)
						splat(d.x, d.y + 8.0)
						if b.owner >= 0 and b.owner < players.size():
							players[b.owner].coins += 3
							floater(d.x, d.y - 20.0, "$3", P_COLOURS[b.owner % 2])
					break
			if hit_d:
				continue
			if not in_lobby_floor(b.x, b.y):
				fx(FX_WALL, b.x, b.y)
				gone = true
		else:
			if b.x < WALL or b.x > AW - WALL or b.y < WALL or b.y > AH - WALL:
				fx(FX_WALL, clampf(b.x, WALL, AW - WALL), clampf(b.y, WALL, AH - WALL))
				gone = true
		if gone or b.life <= 0.0:
			continue
		keep.append(b)
	keep.reverse()
	bullets = keep

func _step_husks(dt: float) -> void:
	var keep := []
	for h: FT.Husk in husks:
		var ox: float = h.x
		var oy: float = h.y
		h.x += h.vx * dt
		h.y += h.vy * dt
		if h.whole:
			h.vz -= 1000.0 * dt
			h.dz += h.vz * dt
		else:
			var k := pow(0.5, dt)
			h.vx *= k
			h.vy *= k
		h.rot += h.spin * dt
		h.life -= dt
		var gone: bool = h.life <= 0.0
		if h.whole and h.dz <= 0.0:
			gone = true
			if _in_water(h.x, h.y):
				fx(FX_SPLASH, h.x, h.y)
			elif h.power >= 0.98:
				potato_splat(h.x, h.y, h.owner)
			else:
				var r := FT.Rain.new()
				r.x = h.x
				r.y = h.y
				r.vz = h.vz
				r.vx = h.vx * 0.3
				r.vy = h.vy * 0.3
				r.rot = h.rot
				r.spin = h.spin
				rain.append(r)
		var struck := false
		if not gone:
			for e: FT.Enemy in enemies.duplicate():
				if e.spawn > 0.0:
					continue
				var er := e_rad(e.t)
				if h.whole and h.dz > er * 1.6 + 10.0:
					continue
				if segment_hit(ox, oy, h.x, h.y, e.x, e.y, er + 6.0) < 0.0:
					continue
				var mass: float = e_mass[e.t]
				var dmg: float = h.dmg if h.dmg >= 0.0 else tv("enemyHp", 3) * tv("spudThrowFrac", 1) * (tv("lobWhole", 2.2) if h.whole else 1.0)
				e.hp -= maxf(0.1, dmg)
				e.flash = 0.08
				e.stun = maxf(e.stun, tv("stagger", 0.13))
				if h.whole:
					var dv := Vector2(h.vx, h.vy).normalized()
					e.vx += dv.x * tv("knockback", 170) * 1.5 / mass
					e.vy += dv.y * tv("knockback", 170) * 1.5 / mass
				fx(FX_HIT, h.x, h.y)
				if e.hp <= 0.0:
					kill_enemy(e, h.vx, h.vy, false, h.owner, 1.0, false)
				gone = true
				struck = true
				break
		if struck and h.whole and h.power >= 0.98:
			potato_splat(h.x, h.y, h.owner)
		if not gone:
			if lobby():
				if not in_lobby_floor(h.x, h.y):
					gone = true
			elif h.x < 24.0 or h.x > AW - 24.0 or h.y < 24.0 or h.y > AH - 24.0:
				gone = true
		if not gone:
			keep.append(h)
	husks = keep

func _in_water(x: float, y: float) -> bool:
	if started:
		return false
	var pool: Dictionary = GameData.data.get("POOL", {})
	if pool.is_empty():
		return false
	return x > float(pool.x0) and x < float(pool.x1) and y > float(pool.y0) and y < float(pool.y1)

func _step_nuke(dt: float) -> void:
	if nuke == null:
		return
	nuke.t += dt
	if not nuke.boom and nuke.t >= tv("nukeFall", 1.9):
		nuke.boom = true
		nuke.t = 0.0
		shake = tv("nukeShake", 26)
		freeze = maxf(freeze, 0.05)
		snd("stop_whistle")
		snd("nuke_boom")
		for e: FT.Enemy in enemies.duplicate():
			var dx: float = e.x - nuke.x
			var dy: float = e.y - nuke.y
			kill_enemy(e, dx, dy, true, -1, -1.0, false)
		enemies.clear()
		for p: FT.Fighter in players:
			if not p.alive:
				continue
			var d := Vector2(p.x - nuke.x, p.y - nuke.y)
			var push := maxf(0.0, 1.0 - d.length() / 420.0) * 520.0
			if d.length() > 0.001:
				p.vx += d.x / d.length() * push
				p.vy += d.y / d.length() * push
			p.iframe = maxf(p.iframe, 0.5)
	elif nuke.boom and nuke.t >= tv("nukeBoom", 0.85):
		nuke = null

func _step_rockets(dt: float) -> void:
	for r: FT.Rocket in rockets.duplicate():
		r.t += dt
		if r.t >= tv("lobTime", 0.75):
			rockets.erase(r)
			detonate(r.tx, r.ty, r.owner, r.tx - r.sx, r.ty - r.sy)
	for b: FT.Blast in blasts.duplicate():
		b.t += dt
		if b.t >= tv("blastTime", 0.6):
			blasts.erase(b)

func _step_plants(dt: float) -> void:
	if over:
		return
	if started:
		plant_timer -= dt
		if plant_timer <= 0.0:
			plant_spud(0.0)
			plant_timer = tv("spudRate", 5)
	for pl: FT.Plant in plants.duplicate():
		pl.t += dt
		pl.wob = maxf(0.0, pl.wob - dt)
		if pl.t < tv("spudGrow", 9):
			continue
		for p: FT.Fighter in players:
			if not p.alive or p.reload > 0.0 or p.pickup > 0.0 or p.throw > 0.0:
				continue
			if p.ammo >= int(tv("spudMaxAmmo", 200)):
				continue
			if Vector2(p.x, p.y).distance_to(Vector2(pl.x, pl.y)) > tv("radius", 14) + 14.0:
				continue
			p.ammo = mini(int(tv("spudMaxAmmo", 200)), p.ammo + int(tv("spudPellets", 10)))
			p.pickup = tv("spudPickup", 0.36)
			plants.erase(pl)
			fx(FX_WALL, pl.x, pl.y)
			snd("pickup")
			break

func _step_rain(dt: float) -> void:
	var hardest := 0.0
	for r: FT.Rain in rain.duplicate():
		if r.delay > 0.0:
			r.delay -= dt
			continue
		r.squash = maxf(0.0, r.squash - 9.0 * dt)
		r.vz -= 1500.0 * dt
		r.dz += r.vz * dt
		r.x += r.vx * dt
		r.y += r.vy * dt
		r.rot += r.spin * dt
		if r.dz > 0.0:
			continue
		r.dz = 0.0
		var hit: float = -r.vz
		var keepk: float = [0.45, 0.36, 0.28][mini(2, r.bounces)]
		r.bounces += 1
		hardest = maxf(hardest, hit)
		if hit > 110.0 and r.bounces <= 3:
			r.vz = hit * keepk
			r.vx = r.vx * 0.6 + (rnd() - 0.5) * hit * 0.08
			r.vy = r.vy * 0.6 + (rnd() - 0.5) * hit * 0.08
			r.spin *= 0.55
			r.squash = 1.0
			if hit > 300.0:
				burst(r.x, r.y + 4.0, 3, Color("#b9a58a"), 40)
			continue
		rain.erase(r)
		r.x = clampf(r.x, 30.0, (ww() if lobby() else AW) - 30.0)
		r.y = clampf(r.y, 30.0, (wh() if lobby() else AH) - 30.0)
		if _in_water(r.x, r.y):
			fx(FX_SPLASH, r.x, r.y)
			continue
		var pl := FT.Plant.new()
		pl.x = r.x
		pl.y = r.y
		pl.t = tv("spudGrow", 9)
		pl.wob = 0.3
		plants.append(pl)
	if hardest > 0.0 and thud_cd <= 0.0:
		thud_cd = 0.05
		snd("thud")

# The player action timers (L8094): punch lands, throw releases, the jab, the pickup.
func _step_timers(dt: float) -> void:
	for p: FT.Fighter in players:
		if p.punch > 0.0:
			var before := p.punch
			p.punch -= dt
			if before > tv("punchTime", 0.24) * 0.55 and p.punch <= tv("punchTime", 0.24) * 0.55 and not p.punched:
				p.punched = true
				if p.alive:
					punch_land(p)
			p.punch = maxf(0.0, p.punch)
		if p.throw > 0.0:
			p.throw -= dt
			if p.throw <= tv("spudThrow", 0.5) * (1.0 - 3.0 / 5.0) and not p.threw:
				p.threw = true
				_release_throw(p)
			if p.throw <= 0.0:
				p.throw = 0.0
				if p.ammo > 0 and WeaponDefs.w(p.weapon).get("jab", false):
					p.reload = tv("spudReload", 0.42)
		if p.reload > 0.0:
			var before2 := p.reload
			p.reload -= dt
			var stab := tv("spudReload", 0.42) * (1.0 - 2.5 / 6.0)
			if before2 > stab and p.reload <= stab:
				snd("jab")
			p.reload = maxf(0.0, p.reload)
		p.dry_hint = maxf(0.0, p.dry_hint - dt)
		if p.pickup > 0.0:
			p.pickup -= dt
			if p.pickup <= 0.0:
				p.pickup = 0.0
				if WeaponDefs.w(p.weapon).get("jab", false):
					p.reload = tv("spudReload", 0.42)

## Which way the body is drawn (facingVec, L9563): the aim while firing, else the way he's moving, else facing.
func facing_vec(p: FT.Fighter) -> Vector2:
	if p.firing and Vector2(p.adx, p.ady).length() > 0.001:
		return Vector2(p.adx, p.ady).normalized()
	if p.moving and Vector2(p.ix, p.iy).length() > 0.001:
		return Vector2(p.ix, p.iy).normalized()
	var f := Vector2(p.fx, p.fy)
	return f.normalized() if f.length() > 0.001 else Vector2(0, 1)

func _release_throw(p: FT.Fighter) -> void:
	var f := facing_vec(p)
	snd("throw")
	if not p.throw_whole:
		var h := FT.Husk.new()
		h.owner = p.id
		h.x = p.x + f.x * 14.0
		h.y = p.y + f.y * 8.0
		h.dz = 26.0
		h.vx = f.x * tv("spudThrowSpd", 520)
		h.vy = f.y * tv("spudThrowSpd", 520)
		h.rot = rnd() * 6.28
		h.spin = (rnd() - 0.5) * 22.0
		h.life = 1.2
		husks.append(h)
		return
	p.throw_whole = false
	var dist := p.throw_dist
	var dir := Vector2(p.throw_dx, p.throw_dy)
	if not is_nan(p.throw_tx):
		var d := Vector2(p.throw_tx - p.x, p.throw_ty - p.y)
		if d.length() > 8.0:
			dist = d.length()
			dir = d / d.length()
	var pw := p.throw_pow
	var tf := 0.78 - 0.33 * pw
	var G := 1000.0
	var h := FT.Husk.new()
	h.owner = p.id
	h.whole = true
	h.x = p.x + dir.x * 12.0
	h.y = p.y + dir.y * 6.0
	h.dz = 28.0
	h.vz = G * tf / 2.0 - 28.0 / tf
	h.vx = dir.x * (dist - 12.0) / tf
	h.vy = dir.y * (dist - 6.0) / tf
	h.dmg = tv("enemyHp", 3) * tv("spudThrowFrac", 1) * tv("lobWhole", 2.2) * (1.0 + (tv("lobPowDmg", 1.5) - 1.0) * pw)
	h.power = pw
	h.rot = rnd() * 6.28
	h.spin = (rnd() - 0.5) * (14.0 + 16.0 * pw)
	h.life = 3.0
	husks.append(h)
	sounds.append("throw_whole:%.2f" % pw)

func _step_corpses(dt: float) -> void:
	var keep := []
	for c: FT.Corpse in corpses:
		c.x += c.vx * dt
		c.y += c.vy * dt
		if c.z > 0.0 or c.vz > 0.0:
			c.vz -= 440.0 * dt
			c.z = maxf(0.0, c.z + c.vz * dt)
			if c.z == 0.0:
				if not c.landed:
					splat(c.x, c.y)
					if not splats.is_empty():
						splats[-1].scale *= 0.48
					c.landed = true
				c.vz = -c.vz * 0.23 if absf(c.vz) > 45.0 else 0.0
				c.vx *= 0.65
				c.vy *= 0.65
		var drag := pow(0.035, dt)
		c.vx *= drag
		c.vy *= drag
		c.rot += c.spin * dt
		c.spin *= pow(0.1, dt)
		if started:
			c.x = clampf(c.x, WALL + 8.0, AW - WALL - 8.0)
			c.y = clampf(c.y, WALL + 8.0, AH - WALL - 8.0)
		c.life -= dt
		if c.life > 0.0:
			keep.append(c)
	corpses = keep

func _step_coins(dt: float) -> void:
	var keep := []
	for c: FT.Coin in coins:
		c.x += c.vx * dt
		c.y += c.vy * dt
		var drag := pow(0.02, dt)
		c.vx *= drag
		c.vy *= drag
		var moving := Vector2(c.vx, c.vy).length()
		c.rot += c.spin * dt * (0.25 + minf(1.0, moving / 120.0))
		c.spin *= pow(0.25, dt)
		c.x = clampf(c.x, 24.0, ww() - 24.0)
		c.y = clampf(c.y, 24.0, wh() - 24.0)
		c.life -= dt
		if c.arm > 0.0:
			c.arm -= dt
			keep.append(c)
			continue
		var near: FT.Fighter = null
		var nd := INF
		var reach := tv("coinMagnet", 95)
		for p: FT.Fighter in players:
			if not p.alive:
				continue
			if c.owner >= 0 and c.owner != p.id:
				continue
			var r2 := maxf(tv("coinMagnet", 95), tv("magnetRange", 460)) if p.magnet > 0.0 else tv("coinMagnet", 95)
			var d := Vector2(p.x - c.x, p.y - c.y).length()
			if d - r2 < nd - reach:
				nd = d
				near = p
				reach = r2
		var taken := false
		if near:
			if nd < tv("coinGrab", 34):
				near.coins += 1
				taken = true
				if c.pull:
					burst(c.x, c.y, 3, Color("#7fd89a"), 90)
				snd("cash")
			elif nd < reach and nd > 0.001:
				var boost := 2.4 if near.magnet > 0.0 else 1.0
				c.pull = near.magnet > 0.0
				var k := tv("coinPull", 900) * boost * (1.0 - nd / reach) * dt / nd
				c.vx += (near.x - c.x) * k
				c.vy += (near.y - c.y) * k
				c.life = maxf(c.life, 1.5 if near.magnet > 0.0 else 0.6)
		if not taken and c.life > 0.0:
			keep.append(c)
	coins = keep

## Debug (M with ?debug in the HTML): the magnet and 14 notes round player 0.
func test_magnet() -> void:
	if players.is_empty():
		return
	var p: FT.Fighter = players[0]
	p.magnet = tv("magnetTime", 14)
	for i in 14:
		var a := float(i) / 14.0 * TAU + randf() * 0.4
		var d := 140.0 + randf() * 260.0
		var c := _coin(clampf(p.x + cos(a) * d, 28.0, ww() - 28.0), clampf(p.y + sin(a) * d, 28.0, wh() - 28.0), 0, 0, 10.0, 0.2)
		c.spin = 4.0
