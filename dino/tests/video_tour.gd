extends SceneTree
## A short scripted tour for a video: the ankylosaurus (CLANK on its plates, a bite out of its belly, its tail club),
## then a few seconds in each newer map walking through its patch. Record it with Godot's movie maker:
##   godot --path . --write-movie tour.avi --fixed-fps 30 --script res://tests/video_tour.gd

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		while main.state == main.CHOOSE:
			main._pick(0)

func _quiet() -> void:
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)

func _clear() -> void:
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	_quiet()
	_clear()
	var pl: Player = main.player
	# 1. the ankylosaurus: plates, belly, club
	pl.position = Vector2(200, main.GROUND_Y)
	var an: Ankylosaurus = main._spawn_herd_kind(Area.HERD_ANKYLO, 330.0)
	await _frames(2)
	an.set_facing(-1.0)
	an.state = 99
	Input.action_press("right")
	await _frames(40)
	Input.action_release("right")
	for k in 2:
		var top := -1
		var col := int(an.body.w * (0.45 + k * 0.15))
		for y in an.body.h:
			if an.body.alive[y * an.body.w + col] == 1:
				top = y
				break
		main.player_bite(pl, an.body.to_world(Vector2(col + 0.5, top + 3.5)), pl.bite_radius)
		await _frames(25)
	for k in 2:
		var col := int(an.body.w * 0.5)
		var bottom := 0
		for y in an.body.h:
			if an.body.alive[y * an.body.w + col] == 1:
				bottom = y
		main.player_bite(pl, an.body.to_world(Vector2(col + 0.5, bottom - 2.5)), pl.bite_radius)
		await _frames(25)
	# round the back of it: up comes the club
	an.state = Prey.GRAZE
	an.set_facing(1.0)
	pl.position = Vector2(an.position.x - an._reach() * 0.7, main.GROUND_Y)
	pl.set_facing(1.0)
	pl.invuln = 0.0
	await _frames(70)
	# 2. the newer maps, walking through each one's patch
	for n in [3, 4, 5, 6, 7]:
		main.enter_area(n)
		_quiet()
		_clear()
		await _frames(1)
		pl = main.player
		var area: Area = main.area
		var at: float = area.hazards[0][0] if not area.hazards.is_empty() else 500.0
		pl.position = Vector2(at - 70.0, main.GROUND_Y)
		pl.invuln = 0.0
		pl.hp = pl.max_hp
		# something grazing in the patch ahead
		var g: Prey = main.spawn_prey(at + 40.0)
		await _frames(1)
		g.state = 99
		Input.action_press("right")
		await _frames(75)
		Input.action_release("right")
	main.queue_free()
	quit()
