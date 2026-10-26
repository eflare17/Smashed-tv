extends SceneTree
## A short video of the runners family: you walk up on a group of compys (they scatter), a gallimimus herd
## (it stampedes) and a corythosaurus herd (one honks, they all bolt). Record with Godot's movie maker:
##   godot --path . --write-movie runners.avi --fixed-fps 30 --script res://tests/video_runners.gd

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		while main.state == main.CHOOSE:
			main._pick(0)

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	var pl: Player = main.player
	for scene: Array in [[Prey.COMPY, 5, 14.0], [Prey.GALLIMIMUS, 3, 40.0], [Prey.CORYTHO, 3, 55.0]]:
		pl.position = Vector2(140.0, main.GROUND_Y)
		var herd: Array = []
		for k in scene[1]:
			herd.append(main.spawn_prey(260.0 + k * scene[2], scene[0]))
		await _frames(20)
		Input.action_press("right")
		await _frames(70)
		Input.action_release("right")
		# a bite at the nearest, if it's still in reach
		var near: Prey = herd[0]
		if near.global_position.distance_to(pl.global_position) < 60.0:
			main.player_bite(pl, near.global_position + Vector2(0, -near.height * 0.4), pl.bite_radius)
		await _frames(60)
		for c in herd:
			c.queue_free()
			main.creatures.erase(c)
	main.queue_free()
	quit()
