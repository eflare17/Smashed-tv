class_name VoxelLoadout
extends RefCounted
## The arena's weapons (the owner, 20 Oct): in groups on the number keys, as in Half-Life (1 melee, 2 guns, 3 special,
## 4 explosives, 5 the vacuum): a key takes out the one last used in its group, again steps to the next in it. Each
## uses both mouse buttons; the wheel cycles through them all, Q swaps back to the last one. A switch takes a moment (the old one goes down, the new one comes
## up) and nothing fires till it's up. Cooldowns are kept per weapon, so the weapon bar can show them. No nodes: the
## arena reads it, the logic test drives it. Owned by the voxel session.

## Every weapon, group by group, in key order. slots is the ones this arena has (a weapon whose script isn't there
## is left out; see keep_only).
const ALL := [
	{"id": "sword", "group": 1, "name": "Sword", "left": "slash the way the mouse moves", "right": "chop down"},
	{"id": "bat", "group": 1, "name": "Bat", "left": "swing: knocks them flying", "right": "hold to charge a home run, let go"},
	{"id": "hammer", "group": 1, "name": "Sledgehammer", "left": "swing the way the mouse moves (still: overhead smash)", "right": "ground slam: knocks everyone near down"},
	{"id": "chainsaw", "group": 1, "name": "Chainsaw", "left": "hold: saw through", "right": "lunge forward"},
	{"id": "spear", "group": 1, "name": "Spear", "left": "thrust: skewers in a line", "right": "throw (again: call it back)"},
	{"id": "pistol", "group": 2, "name": "Pistol", "left": "fire", "right": "aim in"},
	{"id": "shotgun", "group": 2, "name": "Shotgun", "left": "fire (pump)", "right": "both barrels: blow a chunk out"},
	{"id": "laser", "group": 2, "name": "Laser cutter", "left": "hold: a thin beam that cuts where you drag it", "right": "hold: overcharge, a fat beam through everything"},
	{"id": "flamethrower", "group": 3, "name": "Flamethrower", "left": "hold: spray fire (it spreads, they burn to ash)", "right": "a burst of fire on the floor that burns a while"},
	{"id": "freezeray", "group": 3, "name": "Freeze ray", "left": "hold: freeze them solid", "right": "ice shot: shatters what's frozen"},
	{"id": "harpoon", "group": 3, "name": "Harpoon gun", "left": "harpoon them, drag them to you", "right": "harpoon a limb, yank it off"},
	{"id": "gravity", "group": 3, "name": "Gravity gun", "left": "grab a body or bit, click again: launch it", "right": "black hole: pulls everything in and crushes it"},
	{"id": "grenades", "group": 4, "name": "Grenade launcher", "left": "bouncing grenade", "right": "sticky bomb (R: set them off)"},
	{"id": "vacuum", "group": 5, "name": "Vacuum", "left": "suck up (hold)", "right": "hold + wheel: brush size"},
]
const GROUPS := {1: "Melee", 2: "Guns", 3: "Special", 4: "Explosives", 5: "Vacuum"}
const SWITCH_T := 0.25          # seconds a switch takes

var slots: Array = ALL.duplicate()
var current := 0
var last := 0
var _group_last := {}           # group -> the weapon id last out in it
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
	_group_last[int(slots[i].group)] = String(slots[i].id)
	return true

## A group's key: the one last used in it (or its first); if one of its own is out already, the next one in it.
## False if the group has none.
func select_group(g: int) -> bool:
	var mine := []
	for i in slots.size():
		if int(slots[i].group) == g:
			mine.append(i)
	if mine.is_empty():
		return false
	var at := mine.find(current)
	if at >= 0:
		return select(mine[(at + 1) % mine.size()])
	var want := index_of(String(_group_last.get(g, "")))
	return select(want if mine.has(want) else int(mine[0]))

## The group of the one out.
func group() -> int:
	return int(slots[current].group)

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
