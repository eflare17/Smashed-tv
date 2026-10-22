extends RefCounted
## Smash arcade wave director: decides what each wave sends and spawns it, in bursts from one door at a time.
## All the difficulty numbers are here (the balance pass tunes them; see README):
##  - grunts per wave grow with the room; their speed with the room too, capped;
##  - brutes from room 2, snipers from room 3, mines from room 4, more of each in later rooms;
##  - every BOSS_EVERY rooms is a boss room: one wave, Big Tony, a sniper and a trickle of grunts.
## Specials (brutes, snipers, mines) are shuffled into a queue and lead a burst now and then.

const BOSS_EVERY := 5
enum { BRUTE, SNIPER, MINE }

var game
var grunts_left := 0
var specials: Array[int] = []
var boss_pending := false

var _room := 1
var _wave := 1
var _spawn_t := 0.0
var _burst_left := 0
var _burst_door := 0
var _boss_t := 0.0

static func is_boss_room(room: int) -> bool:
	return room % BOSS_EVERY == 0

static func waves_in_room(room: int) -> int:
	return 1 if is_boss_room(room) else 2

## Big Tony's HP: more each time he comes back.
static func boss_hp(room: int) -> int:
	return 160 + (room / BOSS_EVERY - 1) * 100

## Plans wave `wave` (1 or 2) of `room`.
func start(room: int, wave: int) -> void:
	_room = room
	_wave = wave
	var boss := is_boss_room(room)
	specials.clear()
	if boss:
		grunts_left = 8 + room * 2
		specials.append(SNIPER)
	else:
		# from room 6 the curve steepens: that's where it should start to get hard
		var late := maxi(0, room - 5)
		grunts_left = 10 + room * 9 + wave * 6 + late * 4
		for i in (room - 1 + wave - 1 + room / 4 + mini(late, 1) if room >= 2 else 0):
			specials.append(BRUTE)
		for i in (1 + (room - 3) * 2 / 3 + wave - 1 + mini(late, 1) if room >= 3 else 0):
			specials.append(SNIPER)
		for i in (2 + room - 4 + wave if room >= 4 else 0):
			specials.append(MINE)
	specials.shuffle()
	boss_pending = boss
	_boss_t = 2.5
	_spawn_t = 1.5
	_burst_left = 0
	game.snipers.gap = maxf(0.8, 2.2 - room * 0.14)

func done_spawning() -> bool:
	return grunts_left == 0 and specials.is_empty() and not boss_pending

func grunt_speed() -> float:
	return minf(2.3 + _room * 0.22 + maxi(0, _room - 5) * 0.08 + _wave * 0.08, 5.0) * randf_range(0.85, 1.15)

func brute_speed() -> float:
	return minf(1.6 + _room * 0.08, 2.5) * randf_range(0.9, 1.1)

func update(delta: float) -> void:
	if boss_pending:
		_boss_t -= delta
		if _boss_t <= 0.0:
			boss_pending = false
			game.spawn_boss(game.spawn_door(), boss_hp(_room))
	if grunts_left == 0 and specials.is_empty():
		return
	_spawn_t -= delta
	while _spawn_t <= 0.0 and (grunts_left > 0 or not specials.is_empty()):
		if _burst_left <= 0:
			_burst_door = game.spawn_door()
			_burst_left = randi_range(4, 6 + _room * 3 / 2)
			if not specials.is_empty() and (randf() < 0.4 or grunts_left == 0):
				_spawn_special(specials.pop_back(), _burst_door)
		if grunts_left > 0:
			game.horde.spawn(_burst_door, randf_range(0.5, 2.0), grunt_speed())
			grunts_left -= 1
		_burst_left -= 1
		_spawn_t += 0.12 if _burst_left > 0 else randf_range(0.5, 1.1) / (1.0 + _room * 0.18)

func _spawn_special(kind: int, door: int) -> void:
	match kind:
		BRUTE:
			game.brutes.spawn(door, randf_range(0.8, 2.0), brute_speed())
		SNIPER:
			game.snipers.spawn(door, randf_range(0.5, 1.5))
		MINE:
			game.mines.spawn(door, randf_range(0.5, 1.5))
