extends SceneTree
## The kill announcer's self-test (headless: --fixed-fps 60 -s test/voxel/announcer_test.gd -- --nosave): FIRST
## BLOOD, a chain of kills up through DOUBLE KILL .. HOLY SHIT with their bonuses, KILLING SPREE at five, the chain
## running out after a pause, a HEADSHOT (a real one: the head blown open), a kill that wasn't yours counting for
## nothing, going down ending the spree, Off saying nothing, and a recording in user://voices played for its line.
## Owned by the voxel session.

var arena: Node
var a: VoxelAnnouncer
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("ANN ok   ", what)
	else:
		failed += 1
		print("ANN FAIL ", what)

func next(s: int) -> void:
	step = s
	mark = t

## A fresh grunt killed by this player (its health taken: VoxelBody.hurt, as a blow does).
func kill_one() -> VoxelBody:
	var b: VoxelBody = arena.spawn_kind("grunt", Vector3(randf_range(-8, 8), 0, randf_range(-8, 4)))
	b.hurt(9999.0)
	return b

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var e := t - mark
	match step:
		0:
			a = arena.announcer
			arena.waves.queue.clear()
			arena.godmode = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			VoxelAnnouncer.level = 1
			arena.cash = 0
			check(a != null, "the announcer's there")
			var b := kill_one()
			check(not b.alive and a.last == ["FIRST BLOOD"], "first kill: %s" % [a.last])
			var want := ["DOUBLE KILL", "MULTI KILL", "MEGA KILL", "ULTRA KILL", "M O N S T E R   K I L L", "LUDICROUS KILL", "HOLY SHIT"]
			var got := []
			var spree_seen := false
			for i in 7:
				kill_one()
				got.append(a.last[0])
				if a.last.has("KILLING SPREE"):
					spree_seen = true
			check(got == want, "the chain: %s" % [got])
			check(spree_seen, "KILLING SPREE at five")
			var bonus := 2 + 4 + 7 + 10 + 15 + 25 + 40 + 10
			check(arena.cash >= bonus, "bonuses paid: $%d (the callouts' $%d, and the kills' own)" % [arena.cash, bonus])
			kill_one()
			check(a.last[0] == "HOLY SHIT", "past eight it's still HOLY SHIT")
			next(1)
		1:
			if e > 3.5:
				kill_one()
				check(a.chain == 1 and a.spree == 10 and a.last.has("RAMPAGE"), "a pause ends the chain (%d), the spree goes on: %d %s" % [a.chain, a.spree, a.last])
				# a headshot, for real: the head blown open
				var b: VoxelBody = arena.spawn_kind("grunt", Vector3(0, 0, -6))
				v.b = b
				next(2)
		2:
			if e > 0.5 and not v.has("shot"):
				v.shot = true
				var b: VoxelBody = v.b
				var hb := b.skeleton.find_bone("head")
				var hp := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(hb).origin
				for k in 6:
					if b.alive:
						b.carve(hp + Vector3(0, 0.12, 0), hp + Vector3(0, 0.12, 0), 0.16)
				check(not b.alive and b.head_gone, "the head blown open: dead %s, head gone %s" % [not b.alive, b.head_gone])
				check(a.last.has("HEADSHOT"), "HEADSHOT: %s" % [a.last])
				# someone else's kill (not hit by this player): nothing
				var c: VoxelBody = arena.spawn_kind("grunt", Vector3(3, 0, -6))
				var before := a.spree
				c.alive = false
				c.died.emit(c)
				check(a.spree == before, "a kill that wasn't yours: nothing (%d)" % a.spree)
				# down: the spree's over
				arena.godmode = false
				arena.player_hp = 1.0
				arena.down_t = 3.0
				next(3)
		3:
			if e > 0.3:
				check(a.spree == 0, "going down ends the spree")
				arena.down_t = 0.0
				arena.godmode = true
				VoxelAnnouncer.level = 0
				a.last = []
				kill_one()
				check(a.last.is_empty(), "Off: nothing said")
				# a recording for a line
				VoxelAnnouncer.level = 2
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://voices"))
				var src := ProjectSettings.globalize_path("res://assets/voxel/sound/announce_head.wav")
				DirAccess.copy_absolute(src, ProjectSettings.globalize_path("user://voices/double_kill.wav"))
				a._voices.clear()
				var s = a._voice_for("double_kill")
				check(s != null and s is AudioStream, "a recording in user://voices is picked up for its line")
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://voices/double_kill.wav"))
				a._voices.clear()
				check(a._voice_for("rampage") == null, "no recording: the stinger")
				print("ANN done %d passed, %d failed" % [passed, failed])
				quit(1 if failed > 0 else 0)
				return true
	return false
