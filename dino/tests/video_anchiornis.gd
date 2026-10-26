extends SceneTree
## A short video of the real start of a run: you as the tiny Anchiornis, the camera in close, chewing up a compy,
## then evolving into the hatchling (the grow-and-zoom-out cutscene). Record with Godot's movie maker:
##   godot --path . --write-movie anchiornis.avi --fixed-fps 30 --script res://tests/video_anchiornis.gd

var main: Node
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		while main.state == main.CHOOSE:
			main._pick(0)

func _points(p: Prey) -> Array:
	var out: Array = []
	for part in p.parts:
		for i in part.w * part.h:
			if part.alive[i] == 1:
				out.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
	return out

func _run() -> void:
	rng.seed = 3
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	var pl: Player = main.player
	main.hud.show_banner("YOU ARE AN ANCHIORNIS", 2.0)
	var compy: Prey = main.spawn_prey(pl.position.x + 70.0, Prey.COMPY)
	await _frames(2)
	compy.state = 99
	Input.action_press("right")
	for f in 60:
		await _frames(1)
		if compy.global_position.x - pl.global_position.x < 16.0:
			break
	Input.action_release("right")
	# one meal to go: eat this compy down to nothing and you evolve
	main.eaten = pl.meals_to_evolve() - 1
	compy.die()
	for k in 60:
		if not is_instance_valid(compy) or not main.creatures.has(compy):
			break
		var pts := _points(compy)
		if pts.is_empty():
			break
		main.player_bite(pl, pts[rng.randi() % pts.size()], pl.bite_radius)
		await _frames(5)
	# the cutscene plays out, then a little walk as the hatchling
	await _frames(90)
	Input.action_press("right")
	await _frames(60)
	Input.action_release("right")
	await _frames(20)
	main.queue_free()
	quit()
