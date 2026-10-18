class_name ZombieView
extends Node3D
## Draws the FightSim's zombies (enemy type 4) as the 3D model, in the yard and in the arena, in both views: one
## pooled ZombieModel per living zombie (by its uid) and per fallen one (its corpse), turned the way it faces,
## standing on the dug yard's ground, playing the move its state says (ZombieAnim): climbing out of the ground,
## idling, shambling or charging with the stride matched to how far it has walked, the claw swipe, the scream, a
## flinch when hit, the fall when killed, then fading into the ground. Lit by the game's look (quality from the
## LookPass), its scratches glowing at night. It only reads the sim, so a guest sees the host's zombies the same.

const DEATH_TIME := 1.5          ## seconds of the fall
const FADE_TIME := 1.6           ## a corpse's last seconds, sinking and dithering away
const WALK_CYCLE := 54.0         ## HTML units walked per full stride (both feet), shambling
const RUN_CYCLE := 84.0
const TURN := 7.0                ## radians a second it turns to face where it goes
const HIT_TIME := 0.45

var sim: FightSim
var main: Node
var _live: Dictionary = {}       # uid -> {m: ZombieModel, yaw, hp, hit, t}
var _dead: Array = []            # ZombieModels for corpses, in order
var _spare: Array = []
var _look: Node
var _dn: Node
var _quality := "high"
var _t := 0.0

func _ready() -> void:
	name = "ZombieView"
	process_priority = 60          # after the sim's step this frame (physics), with the fight's views

func _find_look() -> void:
	if main and (_look == null or not is_instance_valid(_look)):
		_look = main.find_child("LookPass", true, false)
		_dn = main.find_child("DayNight", true, false)

func _process(dt: float) -> void:
	if sim == null:
		return
	_t += dt
	_find_look()
	if _look:
		_quality = String(_look.get("quality"))
	var glow := 0.0
	if not sim.started and _dn:
		glow = float(_dn.get("lamp_level"))
	elif sim.started:
		glow = 0.5
	var seen := {}
	var hidden: bool = sim.secret != null and sim.secret.phase != "done"
	for e: FT.Enemy in sim.enemies:
		if e.t != ZombieSim.T or hidden:
			continue
		seen[e.uid] = true
		var z: Dictionary = _live.get(e.uid, {})
		if z.is_empty():
			z = {"m": _take(e.uid), "yaw": atan2(e.sdx, e.sdy), "hp": e.hp, "hit": -1.0, "seed": _seed(e.uid)}
			_live[e.uid] = z
		_pose_live(e, z, dt, glow)
	for uid in _live.keys():
		if not seen.has(uid):
			_give(_live[uid].m)
			_live.erase(uid)
	var i := 0
	if not hidden:
		for c: FT.Corpse in sim.corpses:
			if c.t != ZombieSim.T:
				continue
			while _dead.size() <= i:
				_dead.append(_take(i + 1000))
			_pose_dead(c, _dead[i], dt, glow)
			i += 1
	while _dead.size() > i:
		_give(_dead.pop_back())

static func _seed(uid: int) -> float:
	return fposmod(float(uid) * 0.6180339887, 1.0)

func _take(uid: int) -> ZombieModel:
	var m: ZombieModel
	if _spare.is_empty():
		m = ZombieModel.new(_seed(uid))
		add_child(m)
	else:
		m = _spare.pop_back()
		m.anim.seed = _seed(uid)
		m.anim.move = ""
		m.visible = true
	m.set_quality(_quality)
	m.set_fade(1.0)
	m.set_flash(0.0)
	return m

func _give(m: ZombieModel) -> void:
	m.visible = false
	_spare.append(m)

## The ground under (x, y) in metres (the yard's dug heightmap, flat elsewhere).
func _ground(x: float, y: float) -> float:
	if sim.started:
		return 0.0
	var dg = Dig.instance if ResourceLoader.exists("res://scripts/dig/dig.gd") else null
	if dg and is_instance_valid(dg) and dg.grid:
		return dg.grid.height_at(x, y) * GameData.UNIT
	return 0.0

func _pose_live(e: FT.Enemy, z: Dictionary, dt: float, glow: float) -> void:
	var m: ZombieModel = z.m
	m.set_quality(_quality)
	m.set_glow(glow)
	# the way it faces: where it goes, or at you while it screams, rises or claws
	var sp := Vector2(e.vx, e.vy).length()
	var want: float = z.yaw
	if e.st in [ZombieSim.WINDUP, ZombieSim.SWING, ZombieSim.RECOVER, ZombieSim.SCREAM, ZombieSim.RISE]:
		if e.sdx != 0.0 or e.sdy != 0.0:
			want = atan2(e.sdx, e.sdy)
	elif sp > 8.0:
		want = atan2(e.vx, e.vy)
	z.yaw = rotate_toward(float(z.yaw), want, TURN * dt)
	# hit: a flinch when its hp drops
	if e.hp < float(z.hp) - 0.001:
		z.hit = 0.0
	z.hp = e.hp
	var hit := -1.0
	if float(z.hit) >= 0.0:
		z.hit = float(z.hit) + dt / ZombieAnim.length("hit", HIT_TIME)
		if float(z.hit) >= 1.0:
			z.hit = -1.0
		else:
			hit = z.hit
	var move := "idle"
	var u := fposmod(_t / 3.2 + float(z.seed), 1.0)
	var y := _ground(e.x, e.y)
	match e.st:
		ZombieSim.RISE:
			move = "rise"
			u = 1.0 - e.st_t / ZombieSim.RISE_TIME
			y -= ZombieAnim.rise_depth(u)
			hit = -1.0
		ZombieSim.SINK:
			move = "rise"
			u = e.st_t / ZombieSim.SINK_TIME
			y -= ZombieAnim.rise_depth(u)
			hit = -1.0
		ZombieSim.SCREAM:
			move = "scream"
			u = 1.0 - e.st_t / ZombieSim.SCREAM_TIME
		ZombieSim.WINDUP:
			move = "attack"
			u = 0.45 * (1.0 - e.st_t / ZombieSim.WINDUP_TIME)
		ZombieSim.SWING:
			move = "attack"
			u = 0.45 + 0.17 * (1.0 - e.st_t / ZombieSim.SWING_TIME)
		ZombieSim.RECOVER:
			move = "attack"
			u = 0.62 + 0.38 * (1.0 - e.st_t / ZombieSim.RECOVER_TIME)
		_:
			if sp > 6.0:
				if e.zt > 0.0:
					move = "run"
					u = fposmod(e.odo / RUN_CYCLE, 1.0)
				else:
					move = "walk"
					u = fposmod(e.odo / WALK_CYCLE + float(z.seed), 1.0)
	m.position = GameData.world_to_3d(e.x, e.y, 0.0) + Vector3(0, y, 0)
	m.rotation = Vector3(0, float(z.yaw), 0)
	m.anim.apply(move, u, dt, hit)
	m.set_flash(clampf(e.flash / 0.08, 0.0, 1.0))
	m.set_fade(1.0)

func _pose_dead(c: FT.Corpse, m: ZombieModel, dt: float, glow: float) -> void:
	m.set_quality(_quality)
	m.set_glow(glow * clampf(c.life / c.max_life, 0.0, 1.0))
	m.set_flash(0.0)
	var age := c.max_life - c.life
	# it falls away from the blow: backwards, so it faces where the blow came from
	var fx := -cos(c.rot)
	var fy := -sin(c.rot)
	m.rotation = Vector3(0, atan2(fx, fy), 0)
	var y := _ground(c.x, c.y)
	var f := clampf(c.life / FADE_TIME, 0.0, 1.0)
	y -= (1.0 - f) * 0.35
	m.position = GameData.world_to_3d(c.x, c.y, 0.0) + Vector3(0, y, 0)
	m.anim.apply("death", clampf(age / ZombieAnim.length("death", DEATH_TIME), 0.0, 1.0), dt)
	m.set_fade(f)

## How many models are showing (tests).
func shown() -> int:
	var n := 0
	for ch in get_children():
		if ch is ZombieModel and ch.visible:
			n += 1
	return n
