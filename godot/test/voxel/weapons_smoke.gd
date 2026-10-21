extends SceneTree
## Every weapon in the arena in turn on a crowd (left held, a second left click, right held, R), then the frame times
## each one cost and any script error: ~/godot/godot --headless --fixed-fps 60 --path godot -s res://test/voxel/weapons_smoke.gd -- --enemies=10 --godmode
## Prints "SMOKE <weapon> avg .. worst .." for each and "SMOKE done". Owned by the voxel session.

var arena: Node
var t := 0.0
var ids := []
var k := -1
var wt := 0.0
var worst := {}
var sum := {}
var n := {}
var _last := 0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if ids.is_empty():
		for s in arena.loadout.slots:
			ids.append(String(s.id))
	var id: String = ids[k] if k >= 0 else ""
	if k < 0 or wt > 4.0:
		if k >= 0 and arena.melee.has(id):
			arena.melee[id].release(MOUSE_BUTTON_LEFT)
			arena.melee[id].release(MOUSE_BUTTON_RIGHT)
		k += 1
		wt = 0.0
		if k >= ids.size():
			for i2 in ids:
				print("SMOKE %-12s avg %5.2f ms  worst %6.2f ms" % [i2, sum.get(i2, 0.0) / maxf(1, n.get(i2, 1)), worst.get(i2, 0.0)])
			print("SMOKE done: %d bodies, %d alive" % [arena.bodies.size(), arena.bodies.filter(func(b): return b.alive).size()])
			return true
		id = ids[k]
		arena.loadout.select(k)
		arena.loadout.switch_t = 0.0
		if arena.melee.has(id):
			arena.melee[id].on_select()
		if arena.bodies.filter(func(b): return b.alive).size() < 6:
			arena._next_wave()
	wt += dt
	# look at the nearest one standing
	var best: VoxelBody = null
	for b in arena.bodies:
		if b.alive and (best == null or b.global_position.distance_to(arena.player.global_position) < best.global_position.distance_to(arena.player.global_position)):
			best = b
	if best:
		var to: Vector3 = best.global_position + Vector3(0, 1.1, 0) - arena.cam.global_position
		arena.look_yaw = atan2(-to.x, -to.z)
		arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var w = arena.melee.get(id)
	if w:
		var once := dt * 1.5
		if wt < once:
			w.press(MOUSE_BUTTON_LEFT)
		elif wt < 0.8:
			w.hold(MOUSE_BUTTON_LEFT, dt)
		elif wt < 0.8 + once:
			w.release(MOUSE_BUTTON_LEFT)
		elif wt > 1.2 and wt < 1.2 + once:
			w.press(MOUSE_BUTTON_LEFT)
			w.release(MOUSE_BUTTON_LEFT)
		elif wt > 2.0 and wt < 2.0 + once:
			w.press(MOUSE_BUTTON_RIGHT)
		elif wt > 2.0 and wt < 2.8:
			w.hold(MOUSE_BUTTON_RIGHT, dt)
		elif wt > 2.8 and wt < 2.8 + once:
			w.release(MOUSE_BUTTON_RIGHT)
		elif wt > 3.3 and wt < 3.3 + once:
			w.reload_key()
	var now := Time.get_ticks_usec()
	var fms: float = (now - _last) / 1000.0 if _last > 0 else 0.0
	_last = now
	worst[id] = maxf(worst.get(id, 0.0), fms)
	sum[id] = sum.get(id, 0.0) + fms
	n[id] = n.get(id, 0) + 1
	return false
