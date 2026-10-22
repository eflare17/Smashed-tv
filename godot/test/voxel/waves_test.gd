extends SceneTree
## The waves and the boss (Stage 12, VoxelWaves; headless, -- --waves): the waves grow and the kinds come in as they
## go; a wave's enemies walk in a few at a time; all down, a rest, then the next, its number shown; every fifth wave
## THE BUTCHER first (twice the size, tough, his bar at the top); his slam hurts and throws whoever's near; his roar
## calls swarmers; his limbs take more hits to come off; down, he pays and says so; F12 back to one at a time.
## Prints "WAVES ok/FAIL ..." lines and "WAVES done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}
var boss: VoxelBody

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("WAVES %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _alive() -> int:
	var n := 0
	for b in arena.bodies:
		if b.alive:
			n += 1
	return n

func _kill_all() -> void:
	for b in arena.bodies:
		if b.alive and b.key != "boss":
			b.hurt(1e6)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var w: VoxelWaves = arena.waves
	match step:
		0:
			check(w.on and arena.wave == 1 and w._banner.visible and w._banner.text.contains("WAVE 1"), "the waves on (--waves): wave 1, its number shown")
			var sizes := []
			for i in [1, 2, 3, 4, 6, 9, 29]:
				sizes.append(VoxelWaves.plan(i).size())
			check(sizes[0] < sizes[1] and sizes[1] < sizes[2] and sizes[3] < sizes[5] and sizes[6] <= 34, "each wave bigger (%s), up to 34" % str(sizes))
			var p1 := VoxelWaves.plan(1)
			var p9 := VoxelWaves.plan(9) + VoxelWaves.plan(11) + VoxelWaves.plan(12)
			check(not p1.has("brute") and not p1.has("shielder") and not p1.has("charger"), "wave 1: grunts and swarmers only %s" % str(p1))
			check(p9.has("shielder") and p9.has("thrower") and p9.has("charger"), "later waves: the new kinds in the mix")
			check(VoxelWaves.plan(5)[0] == "boss" and VoxelWaves.plan(10)[0] == "boss" and not VoxelWaves.plan(4).has("boss"), "every fifth wave: the boss first")
			v.max_alive = 0
			mark = t
			step = 1
		1:
			# wave 2 (4): they walk in a few at a time
			if arena.wave == 1 and w.queue.is_empty():
				_kill_all()
			if arena.wave == 2:
				v.max_alive = maxi(int(v.max_alive), _alive())
				if w.queue.is_empty():
					check(_alive() == VoxelWaves.plan(2).size(), "wave 1 down, a rest, wave 2: %d enemies in" % _alive())
					check(t - mark > VoxelWaves.REST, "... after the rest")
					arena.wave = 4               # (to the boss: wave 5 next)
					_kill_all()
					mark = t
					step = 2
			elif t - mark > 15.0:
				check(false, "wave 2 never came (wave %d, queue %d, alive %d)" % [arena.wave, w.queue.size(), _alive()])
				step = 99
		2:
			if arena.wave == 4:
				_kill_all()
			if arena.wave == 5 and boss == null:
				for b in arena.bodies:
					if b.key == "boss":
						boss = b
				if boss:
					v.boss_t = t
					check(w._banner.text.contains(VoxelWaves.BOSS_NAME), "wave 5: %s's wave" % VoxelWaves.BOSS_NAME)
					check(boss.height > 4.0 and is_equal_approx(boss.tough, 3.0) and is_equal_approx(boss.hp, VoxelKinds.BOSS_HP * 3.0),
						"he's %.1f m tall, three times as tough (%d health)" % [boss.height, int(boss.hp)])
			if boss and t - float(v.get("boss_t", t)) > 0.2:
				check(w._bar_back.visible, "his health bar up")
				# near him: the slam
				arena.godmode = false
				arena.player_hp = VoxelArena.HP_MAX
				_kill_all()
				for b in arena.bodies:
					if b != boss:
						b.queue_free()
				arena.bodies = arena.bodies.filter(func(x): return x == boss)
				w.queue.clear()
				boss.position = Vector3(0, 0, 0)
				boss.set_meta("roar_t", 99.0)
				boss.act_cool = 0.0
				arena.player.global_position = Vector3(0, 0, 2.6)
				v.hp0 = arena.player_hp
				v.saw_up = false
				mark = t
				step = 3
			elif t - mark > 20.0:
				check(false, "the boss never came (wave %d)" % arena.wave)
				step = 99
		3:
			arena.player.global_position = Vector3(0, 0, 2.6)
			if boss.act == VoxelBody.ACT_SLAM_UP:
				v.saw_up = true
			if arena.player_hp < float(v.hp0) - 5.0:
				check(v.saw_up, "close to him: his fists up first")
				check(float(v.hp0) - arena.player_hp >= VoxelKinds.SLAM_HURT * 0.35, "... the slam: %.0f health" % (float(v.hp0) - arena.player_hp))
				arena.player_hp = VoxelArena.HP_MAX
				arena.player.global_position = Vector3(0, 0, 12)
				boss.set_meta("roar_t", 0.0)
				boss.act_cool = 0.0
				v.n0 = arena.bodies.size()
				mark = t
				step = 4
			elif t - mark > 8.0:
				check(false, "no slam (act %d)" % boss.act)
				step = 99
		4:
			if arena.bodies.size() >= int(v.n0) + 2:
				var sw := 0
				for b in arena.bodies:
					if b.key == "swarmer":
						sw += 1
				check(sw >= 2, "his roar: two swarmers come running")
				# his limbs: three times the hits
				arena.frozen = true
				var fa: Dictionary = boss.parts.forearm_r
				for i in 2:
					boss._damage_x({"part": "forearm_r", "cell": Vector3i((fa.grid.size as Vector3i) / 2)}, 1.0)
				check(not fa.gone, "two hits on his forearm (a brute's loses it at two): still on")
				arena.frozen = false
				var cash0: int = arena.cash
				boss.hp = 1.0
				boss.hurt(5.0)
				check(not boss.alive and arena.cash - cash0 == int(VoxelFarm.KILL_CASH.boss), "down: +$%d" % (arena.cash - cash0))
				check(w._banner.visible and w._banner.text.contains("IS DOWN"), "... and it says so")
				mark = t
				step = 5
			elif t - mark > 6.0:
				check(false, "no roar")
				step = 99
		5:
			if t - mark > 0.3:
				var ev := InputEventKey.new()
				ev.pressed = true
				ev.keycode = KEY_F12
				ev.physical_keycode = KEY_F12
				arena._unhandled_input(ev)
				check(not w.on, "F12: one at a time again")
				step = 99
		99:
			print("WAVES done %d passed, %d failed" % [passed, failed])
			return true
	return false
