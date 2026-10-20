class_name VoxelLoadout
extends RefCounted
## The arena's weapons (the owner, 20 Oct): slots on the number keys, each using both mouse buttons; the wheel
## cycles through them, Q swaps back to the last one. A switch takes a moment (the old one goes down, the new one comes
## up) and nothing fires till it's up. Cooldowns are kept per weapon, so the weapon bar can show them. No nodes: the
## arena reads it, the logic test drives it. Owned by the voxel session.

## Every weapon, in key order: guns, the five melee weapons, the vacuum. slots is the ones this arena has (a melee
## weapon whose script isn't there is left out; see keep_only).
const ALL := [
	{"id": "blaster", "name": "Blaster", "left": "fire (hold)", "right": "aim"},
	{"id": "shotgun", "name": "Shotgun", "left": "fire", "right": "both barrels"},
	{"id": "sword", "name": "Sword", "left": "slash the way the mouse moves", "right": "chop down"},
	{"id": "bat", "name": "Bat", "left": "swing: knocks them flying", "right": "hold to charge a home run, let go"},
	{"id": "hammer", "name": "Sledgehammer", "left": "smash a crater", "right": "ground slam: knocks everyone near down"},
	{"id": "chainsaw", "name": "Chainsaw", "left": "hold: saw through", "right": "lunge forward"},
	{"id": "spear", "name": "Spear", "left": "thrust: skewers in a line", "right": "throw (again: call it back)"},
	{"id": "vacuum", "name": "Vacuum", "left": "suck up (hold)", "right": "hold + wheel: brush size"},
]
const SWITCH_T := 0.25          # seconds a switch takes

var slots: Array = ALL.duplicate()
var current := 0
var last := 0
var switch_t := 0.0             # seconds left of the switch (nothing fires till it's 0)
var _cool := {}                 # weapon id -> [seconds left, seconds it started at]

## Keeps only the weapons in ids (in ALL's order), the first one out.
func keep_only(ids: Array) -> void:
	slots = ALL.filter(func(sl): return ids.has(sl.id))
	current = 0
	last = 0

## Takes out slot i (0-based); false if there's no such slot or it's already out.
func select(i: int) -> bool:
	if i < 0 or i >= slots.size() or i == current:
		return false
	last = current
	current = i
	switch_t = SWITCH_T
	return true

## The next (dir 1) or previous (dir -1) slot, round the end.
func cycle(dir: int) -> void:
	select(posmod(current + dir, slots.size()))

## Back to the one out before.
func swap_last() -> void:
	select(last)

func id() -> String:
	return String(slots[current].id)

func slot() -> Dictionary:
	return slots[current]

func index_of(weapon: String) -> int:
	for i in slots.size():
		if slots[i].id == weapon:
			return i
	return -1

## Up and ready (the switch done).
func usable() -> bool:
	return switch_t <= 0.0

## 0 when the switch is done, 1 just started.
func switch_frac() -> float:
	return clampf(switch_t / SWITCH_T, 0.0, 1.0)

func step(dt: float) -> void:
	switch_t = maxf(0.0, switch_t - dt)
	for k in _cool:
		var c: Array = _cool[k]
		c[0] = maxf(0.0, float(c[0]) - dt)

## The weapon can't fire again for secs.
func cool(weapon: String, secs: float) -> void:
	_cool[weapon] = [secs, secs]

## Ready to fire again (its cooldown run out).
func ready_to(weapon: String) -> bool:
	return not _cool.has(weapon) or float(_cool[weapon][0]) <= 0.0

## How much of its cooldown is left, 1 (just fired) to 0 (ready).
func cooling(weapon: String) -> float:
	if not _cool.has(weapon) or float(_cool[weapon][1]) <= 0.0:
		return 0.0
	return clampf(float(_cool[weapon][0]) / float(_cool[weapon][1]), 0.0, 1.0)
