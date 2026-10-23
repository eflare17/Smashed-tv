extends SceneTree
## Gothica's self-test (headless: --fixed-fps 60 -s test/voxel/gothica_test.gd -- --nosave): her sculpted model, her
## wandering, following you round the house (and waiting in the doorway when you go out to the fight), staying put, and
## her soft parts: a hop sets them going, standing still they settle, Jiggle Off keeps them still. Owned by the voxel
## session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var g: VoxelGothica
var seen := {}
var passed := 0
var failed := 0
var peak := 0.0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("GOTH ok   ", what)
	else:
		failed += 1
		print("GOTH FAIL ", what)

func _amp() -> float:
	return maxf((g.jig.sides[0].p as Vector3).length(), (g.jig.sides[1].p as Vector3).length())

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if g:
		seen[g.at_node] = true
	match step:
		0:
			g = arena.gothica
			arena.waves.queue.clear()
			arena.godmode = true
			arena.frozen = true
			var plain := VoxelModel.get_model("goth")
			var her := VoxelModel.get_model("gothica")
			var a: Vector3i = plain.grid("torso").size
			var b: Vector3i = her.grid("torso").size
			check(g != null and g.body.key == "gothica", "she's in the house: %s at %s" % [g.body.key if g else "-", g.body.global_position if g else "-"])
			check(b.z > a.z and b.x == a.x, "her torso sculpted out in front: %s (was %s)" % [b, a])
			check(VoxelGothica.in_house(g.body.global_position), "she starts in the house")
			arena.player.global_position = Vector3(10, 0, 10)
			g.idle_t = 0.0
			mark = t
			step = 1
		1:
			if t - mark > 45.0:
				check(seen.size() >= 3, "wandering: %d places (%s)" % [seen.size(), seen.keys()])
				check(VoxelGothica.in_house(g.body.global_position), "still in the house after wandering")
				# E at her: she follows; you go to the games room
				arena.player.global_position = g.body.global_position + Vector3(0, 0, -1.0)
				g.interact()
				check(g.following and g.hop_t >= 0.0 and g._say.visible, "E: a hop, a word (%s), she follows" % g._say.text)
				mark = t
				step = 2
		2:
			if t - mark > 1.0 and t - mark < 1.1:
				arena.player.global_position = Vector3(-12.6, 0, 27.5)
			if t - mark > 25.0:
				var d := g.body.global_position.distance_to(arena.player.global_position)
				check(d < 2.5, "she came after you into the games room (%.1f m off, at %s)" % [d, g.body.global_position])
				check(peak > 0.008, "running after you shook her up: %.1f mm" % (peak * 1000.0))
				arena.player.global_position = Vector3(0, 0, 0)
				mark = t
				step = 3
			peak = maxf(peak, _amp())
		3:
			if t - mark > 25.0:
				var dd := Vector2(g.body.global_position.x, g.body.global_position.z).distance_to(VoxelGothica.NODES.b_door[0])
				check(dd < 0.6 and g.speed < 0.05, "you went out to the fight: she waits in the bedroom doorway (%.2f m off it)" % dd)
				# standing still she settles; a hop sets her going; then still again
				mark = t
				step = 4
		4:
			if t - mark > 4.0:
				var a0 := _amp()
				check(a0 < 0.004, "standing still, settled: %.1f mm" % (a0 * 1000.0))
				g.hop_t = 0.0
				peak = 0.0
				mark = t
				step = 5
		5:
			peak = maxf(peak, _amp())
			if t - mark > 5.0:
				var a1 := _amp()
				check(peak > 0.02, "a hop throws them about: %.1f mm" % (peak * 1000.0))
				check(a1 < 0.005, "and they settle again: %.1f mm after 5 s" % (a1 * 1000.0))
				arena.player.global_position = g.body.global_position + Vector3(0, 0, -1.0)
				g.interact()
				check(not g.following, "E again: she stays")
				VoxelJiggle.level = 0
				g.hop_t = 0.0
				peak = 0.0
				mark = t
				step = 6
		6:
			peak = maxf(peak, _amp())
			if t - mark > 2.0:
				check(peak == 0.0, "Jiggle Off: still")
				VoxelJiggle.level = 3
				print("GOTH done %d passed, %d failed" % [passed, failed])
				return true
	return false
