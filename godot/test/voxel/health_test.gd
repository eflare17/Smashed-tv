extends SceneTree
## The player's health in the arena (headless): a grunt's swings hurt; at nothing you're down (no moving) and get up
## again; health comes back after a while unhurt; a blast hurts by how near. With --join=CODE / --host=CODE (two
## copies, the host first) it checks co-op instead: the host's enemies hurt the guest, the guest goes down and the
## host standing by gets them up. Prints "HEALTH ok/FAIL ..." lines and "HEALTH done N passed, M failed".
## Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var hp0 := 0.0
var v_hurt_start := false
var mark_ms := 0

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("HEALTH %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _grunt_at(p: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = p
	b.speed = 1.5
	b.died.connect(arena._on_died)
	arena.bodies.append(b)
	return b

func _clear() -> void:
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	match step:
		0:
			_clear()
			arena.player.global_position = Vector3(0, 0, 6)
			_grunt_at(Vector3(0, 0, 4.9))
			hp0 = arena.player_hp
			mark = t
			step = 1
		1:
			if t - mark > 3.0:
				check(arena.player_hp < hp0 - 5.0, "a grunt's swings hurt (%d -> %d in 3 s)" % [hp0, arena.player_hp])
				_clear()
				arena.frozen = true          # (the next wave stands still: nothing else hurts from here)
				arena.hurt_player(500.0)
				check(arena.down_t > 0.0 and arena.player_hp == 0.0, "at nothing: down")
				mark = t
				arena.player.global_position = Vector3(0, 0, 6)
				Input.action_press("ui_up")
				step = 2
		2:
			if t - mark > 1.0 and t - mark < 1.1:
				check(arena.player.global_position.distance_to(Vector3(0, 0, 6)) < 0.05, "down: not moving")
			if t - mark > VoxelArena.DOWN_SOLO + 0.3:
				check(arena.down_t <= 0.0 and arena.player_hp == VoxelArena.HP_MAX, "up again after %d s with full health" % VoxelArena.DOWN_SOLO)
				arena.hurt_player(30.0)
				hp0 = arena.player_hp
				mark = t
				step = 3
		3:
			if t - mark > 2.0 and t - mark < 2.1:
				check(absf(arena.player_hp - hp0) < 0.01, "no health back straight away")
			if t - mark > VoxelArena.REGEN_WAIT + 2.0:
				check(arena.player_hp > hp0 + 3.0, "health comes back after a while unhurt (%d -> %d)" % [hp0, arena.player_hp])
				hp0 = arena.player_hp
				arena.hurt_players_near(arena.player.global_position + Vector3(0, 0.9, 1.0), 2.8, 50.0)
				var near_hit: float = hp0 - arena.player_hp
				hp0 = arena.player_hp
				arena.hurt_players_near(arena.player.global_position + Vector3(0, 0.9, 2.4), 2.8, 50.0)
				var far_hit: float = hp0 - arena.player_hp
				check(near_hit > far_hit and far_hit > 0.0, "a blast hurts by how near (1 m: %d, 2.4 m: %d)" % [near_hit, far_hit])
				step = 4
		4:
			print("HEALTH done %d passed, %d failed" % [passed, failed])
			return true
	return false

func _coop() -> bool:
	var n = arena.net
	if step > 0 and not n.linked:
		step = 9                         # (the other one finished and went)
	elif not n.linked or (role == "guest" and not n._got_world):
		if Time.get_ticks_msec() > 60000:          # (real time: --fixed-fps runs faster than that)
			print("HEALTH FAIL never linked")
			print("HEALTH done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	match step:
		0:
			# the host's grunt next to the guest, the host far off
			if role == "host":
				_clear()
				arena.godmode = true             # (the host stands by its grunt to get the guest up: it mustn't go down itself)
				arena.player.global_position = Vector3(-8, 0, 0)
				mark = t
				step = 1
			else:
				arena.player.global_position = Vector3(6, 0, 6)
				hp0 = arena.player_hp
				mark = t
				step = 1
		1:
			if role == "host":
				if t - mark > 1.0 and arena.bodies.is_empty():
					_grunt_at(Vector3(6, 0, 4.8))
				if n.other_down:
					arena.player.global_position = Vector3(5.6, 0, 6.6)      # walk over to the guest, down
				if not n.linked or t - mark > 600.0:
					step = 9          # (till the guest's done and gone)
			else:
				# (the host's grunt comes and swings: waited for, by real time; the two games' clocks don't keep step)
				if step == 1 and not v_hurt_start:
					v_hurt_start = true
					mark_ms = Time.get_ticks_msec()
				if step == 1 and (arena.player_hp < hp0 - 5.0 or Time.get_ticks_msec() - mark_ms > 20000):
					check(arena.player_hp < hp0 - 5.0, "co-op: the host's grunt hurts the guest (%d -> %d)" % [hp0, arena.player_hp])
					arena.hurt_player(500.0)
					check(arena.down_t > 0.0, "co-op: guest down")
					mark = t
					step = 2
		2:
			if role == "guest" and arena.down_t <= 0.0:
				check(arena.player_hp == VoxelArena.HP_MAX * 0.5 and t - mark < VoxelArena.DOWN_COOP, "co-op: the host standing by got the guest up (%.1f s, %d health)" % [t - mark, arena.player_hp])
				step = 9
			elif role == "guest" and t - mark > 12.0:
				check(false, "co-op: never got up by the host")
				step = 9
		9:
			print("HEALTH done %d passed, %d failed" % [passed, failed])
			return true
	return false
