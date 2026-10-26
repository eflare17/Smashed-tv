extends SceneTree
## A MOCK-UP video of the evolve zoom-out (the owner's idea, not in the game yet): you start as a hatchling with
## the camera in tight; each evolve freezes the world, you grow over two seconds while the camera pulls back, then
## the roar and the banner. The camera makes up most of the growth (zoom ~ size^-0.75), so you get only a little
## bigger on screen while the world shrinks round you. Record with Godot's movie maker:
##   godot --path . --write-movie evolve.avi --fixed-fps 30 --script res://tests/video_evolve.gd

const TIGHT := 2.6   # the camera zoom on a hatchling (the game's is 1.5 for every form)
const GROW_TIME := 2.0

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		while main.state == main.CHOOSE:
			main._pick(0)

## The camera zoom for a dinosaur of `size`.
func _zoom_for(size: float) -> float:
	return TIGHT * pow(0.5 / size, 0.75)

func _clear() -> void:
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	_clear()
	var pl: Player = main.player
	pl.position = Vector2(120, main.GROUND_Y)
	main.zoom_mult = _zoom_for(pl.size) / main.ZOOM
	# what's about at each size: a couple of compys, then gallimimus, then corythosaurus, then a big grazer herd
	var scenes := [[Prey.COMPY, 3, 16.0], [Prey.GALLIMIMUS, 3, 40.0], [Prey.CORYTHO, 3, 60.0], [Prey.GRAZER, 4, 70.0]]
	for s in scenes.size():
		var sc: Array = scenes[s]
		for k in sc[1]:
			var c: Prey = main.spawn_prey(pl.position.x + 150.0 + k * sc[2], sc[0])
			c.set_facing(1.0)
		await _frames(2)
		Input.action_press("right")
		await _frames(55)
		Input.action_release("right")
		await _frames(15)
		if s == scenes.size() - 1:
			break
		# evolve: freeze, grow while the camera pulls back, then the roar
		var from_size: float = pl.size
		var from_zoom: float = main.zoom_mult
		main.sfx.play("whoosh", 0.0, 4.0)
		main.hud.flash(Color(1, 1, 1), 0.5)
		pl.set_stage(pl.stage + 1)
		var to_size: float = pl.size
		var to_zoom: float = _zoom_for(to_size) / main.ZOOM
		var frames := int(GROW_TIME * 30.0)
		for f in frames + 1:
			main.set("_stop", 0.2)
			var k := float(f) / frames
			var e := k * k * (3.0 - 2.0 * k)
			pl.size = lerpf(from_size, to_size, e)
			pl.scale = Vector2(pl.size, pl.size)
			main.zoom_mult = lerpf(from_zoom, to_zoom, e)
			await process_frame
		main.set("_stop", 0.0)
		main.set("_shake", 1.2)
		main.sfx.play("roar", 0.0, 4.0)
		main.sfx.play("thud", 0.0, 2.0)
		main.hud.show_banner("YOU ARE NOW A %s" % pl.stage_name(), 2.5)
		await _frames(25)
		_clear()
	main.queue_free()
	quit()
