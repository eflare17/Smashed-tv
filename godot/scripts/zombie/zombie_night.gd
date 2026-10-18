class_name ZombieNight
extends Node
## The night zombies in the backyard, and the one entry point for the zombie work (main.gd:
## `ZombieInstall.install(self)`, after the Fight). Owns the ZombieView (the 3D models for every zombie, the yard's
## and the arena's) and the ZombieSfx.
##
## At night (GameClock: from NIGHT_FROM to DAWN) while someone is out in the yard, zombies climb out of the ground
## in the dark round the yard, away from you but not too far, one at a time, up to a few at once (more deep in the
## night, one more with a friend), and come at you. They're the fight's enemies (ZombieSim), so every weapon and
## your fists work on them, in both views and with every control. Indoors you're safe: they never come in, and
## mill about the yard. At dawn they sink back into the ground. Knocked down out there, you come to inside by the
## back door a few seconds later (no game over in the lobby), and you get your health back slowly indoors.
##
## Online the host runs all this: the zombies are in the fight's snapshot like any enemy, so the guest sees them,
## shoots them (the host's sim takes its shots) and is clawed by them, and its own player is brought back inside
## here when the host revives it.

const NIGHT_FROM := 21.25
const DAWN := 5.6
## Most at once: 2, 3 after 11 pm until 4 am, one more with two players.
const MAX_EARLY := 2
const MAX_DEEP := 3
## Seconds between climbing out (random in between), and before the first after you step out.
const GAP := Vector2(11.0, 20.0)
const FIRST := Vector2(3.0, 6.0)
## How far from every player they come up (HTML units): out of sight in the dark, not across the whole yard.
const NEAR := 330.0
const FAR := 820.0
## Down in the yard: seconds before you come to inside.
const DOWN_TIME := 3.5
## Health back indoors: a heart every this many seconds.
const HEAL_EVERY := 5.0
## Where you come to: inside the lounge by the back door.
const INSIDE := Vector2(640.0, 470.0)

var main: Node
var fight: Fight
var view: ZombieView
var sfx: ZombieSfx
var force_night := false           ## tests: always night
var _timer := -1.0
var _was_night := false
var _down: Dictionary = {}         # fighter id -> seconds down
var _heal: Dictionary = {}         # fighter id -> seconds indoors
var _dead_seen: Dictionary = {}    # this side's own players: were they down?
var _groan: Dictionary = {}        # zombie uid -> seconds to its next groan
var _corpses_seen := 0
var _rng := RandomNumberGenerator.new()

static var me: ZombieNight

func _enter_tree() -> void:
	me = self

func _ready() -> void:
	name = "ZombieNight"
	process_physics_priority = 51      # after the fight's step on the same tick
	_rng.randomize()
	fight = Fight.me
	if fight == null:
		push_warning("ZombieNight: no Fight")
		return
	view = ZombieView.new()
	view.sim = fight.sim
	view.main = main
	fight.add_child(view)
	sfx = ZombieSfx.new()
	sfx.sim = fight.sim
	fight.add_child(sfx)
	var dbg := _args()
	if dbg.has("zombie"):
		force_night = true

static func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zombie"):
			out["zombie"] = a.get_slice("=", 1) if "=" in a else ""
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.find("zombie") >= 0:
			out["zombie"] = ""
	return out

func sim() -> FightSim:
	return fight.sim if fight else null

## The hour now (the GameClock's), or noon.
func hour() -> float:
	var gc := get_node_or_null("/root/GameClock")
	return float(gc.get("hour")) if gc else 12.0

func is_night() -> bool:
	if force_night:
		return true
	var h := hour()
	return h >= NIGHT_FROM or h < DAWN

func _physics_process(dt: float) -> void:
	var s := sim()
	if s == null or fight.sim != s:
		return
	if fight.sim != view.sim:
		view.sim = fight.sim
		sfx.sim = fight.sim
	_bring_back_own()
	if s.started:
		return
	if Net.is_guest():
		return                      # (the host's game runs the night; its snapshot brings the zombies)
	var night := is_night()
	if _was_night and not night:
		ZombieSim.sink_all(s)
	_was_night = night
	_downed(s, dt)
	if s.over:
		return
	var out := []
	for p: FT.Fighter in s.players:
		if p.alive and ZombieSim.reachable(p):
			out.append(p)
	if not night or out.is_empty():
		_timer = -1.0
		return
	if _timer < 0.0:
		_timer = _rng.randf_range(FIRST.x, FIRST.y)
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(GAP.x, GAP.y)
	var h := hour()
	var cap := MAX_DEEP if (h >= 23.0 or h < 4.0) else MAX_EARLY
	if s.players.size() > 1:
		cap += 1
	var live := 0
	for e: FT.Enemy in s.enemies:
		if e.t == ZombieSim.T and e.st != ZombieSim.SINK:
			live += 1
	if live >= cap:
		return
	var at = _spot(s, out)
	if at != null:
		ZombieSim.spawn_at(s, at.x, at.y)

## Somewhere a zombie can climb out: in the yard, clear of things, NEAR..FAR from the nearest player out there.
func _spot(s: FightSim, out: Array):
	var r := s.e_rad(ZombieSim.T)
	for tries in 40:
		var p: FT.Fighter = out[_rng.randi_range(0, out.size() - 1)]
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(NEAR, FAR)
		var x := p.x + cos(a) * d
		var y := p.y + sin(a) * d
		if not ZombieSim.can_stand(x, y, r * 1.3):
			continue
		var ok := true
		for q: FT.Fighter in s.players:
			if q.alive and Vector2(q.x - x, q.y - y).length() < NEAR:
				ok = false
		for e: FT.Enemy in s.enemies:
			if Vector2(e.x - x, e.y - y).length() < 60.0:
				ok = false
		if ok:
			return Vector2(x, y)
	return null

## Down in the yard: back on your feet inside after a moment. Health back slowly indoors (and all of it at dawn).
func _downed(s: FightSim, dt: float) -> void:
	var full := s.tv("playerHp", 5)
	for p: FT.Fighter in s.players:
		if not p.alive:
			_down[p.id] = float(_down.get(p.id, 0.0)) + dt
			if float(_down[p.id]) >= DOWN_TIME:
				_down.erase(p.id)
				p.alive = true
				p.hp = full
				p.iframe = 2.5
				p.launch = 0.0
				p.vx = 0.0
				p.vy = 0.0
				p.x = INSIDE.x - 34.0 * p.id
				p.y = INSIDE.y
				s.banner("YOU CRAWLED BACK INSIDE", 2.0)
			continue
		if p.hp < full and not ZombieSim.in_yard(p.x, p.y):
			_heal[p.id] = float(_heal.get(p.id, 0.0)) + dt
			if float(_heal[p.id]) >= HEAL_EVERY:
				_heal[p.id] = 0.0
				p.hp = minf(full, p.hp + 1.0)
		elif not is_night() and p.hp < full:
			p.hp = full

## This side's own players (the one at the keyboard, and a second one on it): when one is back on its feet in
## the lobby after being down, stand its body inside and give it its controls back.
func _bring_back_own() -> void:
	var s := sim()
	var own := [[fight.player, fight.f]]
	if fight.p2 and fight.f2 and fight.f2.driven:
		own.append([fight.p2, fight.f2])
	for o in own:
		var pl: Player = o[0]
		var f: FT.Fighter = o[1]
		if pl == null or f == null:
			continue
		var key := pl.get_instance_id()
		var was := bool(_dead_seen.get(key, false))
		_dead_seen[key] = not f.alive
		if was and f.alive and not s.started:
			var at := Vector2(INSIDE.x - 34.0 * f.id, INSIDE.y)
			pl.place(at.x, at.y)
			pl.vel = Vector2.ZERO
			f.x = at.x
			f.y = at.y
			if pl == fight.player:
				pl.controls_enabled = true

func _process(dt: float) -> void:
	var s := sim()
	if s == null or view == null:
		return
	# groans now and then from each zombie, a grunt when hit, the death rattle
	for e: FT.Enemy in s.enemies:
		if e.t != ZombieSim.T or e.st == ZombieSim.RISE:
			continue
		var g := float(_groan.get(e.uid, _rng.randf_range(0.5, 4.0))) - dt
		if g <= 0.0:
			g = _rng.randf_range(3.5, 8.0)
			if e.st != ZombieSim.SCREAM:
				sfx.play_at("groan", GameData.world_to_3d(e.x, e.y, 60.0), -3.0)
		_groan[e.uid] = g
	var n := 0
	for c: FT.Corpse in s.corpses:
		if c.t == ZombieSim.T:
			n += 1
			if n > _corpses_seen and c.max_life - c.life < 0.5:
				sfx.play_at("death", GameData.world_to_3d(c.x, c.y, 40.0))
	_corpses_seen = n
	for ev in s.events:
		if int(ev[0]) == FightSim.FX_HIT:
			for e: FT.Enemy in s.enemies:
				if e.t == ZombieSim.T and absf(e.x - float(ev[1])) < 30.0 and absf(e.y - float(ev[2])) < 30.0 and _rng.randf() < 0.35:
					sfx.play_at("hurt", GameData.world_to_3d(e.x, e.y, 55.0), -2.0)
					break
	if _groan.size() > 64:
		_groan.clear()
