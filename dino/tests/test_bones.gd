extends SceneTree
## Headless checks for the bones (what carries over between runs): earning them by dying, the death screen's shop
## (mouse and touch), saving, and the ranks going onto the next run. From the dino folder:
##   godot --headless --path . --script res://tests/test_bones.gd
## Prints PASS / FAIL per check and exits with the number of failures. Uses its own save file, never yours.

const SAVE := "user://test_bones.cfg"

var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _fresh() -> Bones:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var b := Bones.new()
	b.path = SAVE
	b.load_save()
	return b

func _tap(main: Node, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.position = at
		e.pressed = pressed
		main.touch.active = true
		main.touch.handle(e)

func _click(at: Vector2, device: int) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = pressed
		e.device = device
		root.push_input(e)

func _run() -> void:
	# earning: every source pays, and nothing pays nothing
	_check("a run with nothing in it pays nothing", Bones.earned(0, 0, 0, 0) == 0)
	_check("kills, eating, areas and evolving all pay", Bones.earned(1, 0, 0, 0) > 0 and Bones.earned(0, 1, 0, 0) > 0
			and Bones.earned(0, 0, 1, 0) > 0 and Bones.earned(0, 0, 0, 1) > 0)

	# buying
	var b := _fresh()
	_check("a fresh save has no bones and no ranks", b.bones == 0 and b.ranks.max() == 0 and not b.raptor)
	_check("you can't buy without bones", not b.buy(0) and b.ranks[0] == 0)
	b.add(1000)
	var p1 := b.price(0)
	_check("buying a rank costs its price", b.buy(0) and b.ranks[0] == 1 and b.bones == 1000 - p1)
	_check("each rank costs more than the last", b.price(0) > p1)
	for k in 10:
		b.buy(0)
	_check("ranks stop at the max", b.ranks[0] == Bones.MAX_RANK and b.price(0) == -1 and not b.buy(0))
	var before := b.bones
	_check("the Raptor can be bought once", b.buy(Bones.RAPTOR) and b.raptor and not b.buy(Bones.RAPTOR)
			and b.bones == before - Bones.RAPTOR_PRICE)
	b.buy(3)
	b.buy(3)

	# saving: a new start reads back the same
	var again := Bones.new()
	again.path = SAVE
	again.load_save()
	_check("bones and ranks are saved", again.bones == b.bones and again.ranks == b.ranks and again.raptor,
			"%d %s" % [again.bones, again.ranks])

	# the game: a fresh save makes a normal hatchling
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	_check("the tests never use your real save", main.bones.path == "")
	var pl: Player = main.player
	_check("with nothing bought you start as a plain hatchling", pl.stage == 0
			and is_equal_approx(pl.bite_radius, Player.STAGES[0].bite) and is_equal_approx(pl.max_hp, Player.STAGES[0].hp))

	# dying pays the run's bones
	var mb := _fresh()
	main.bones = mb
	main.kills = 7
	main.eaten = 3
	main.area_n = 2
	main.evolves = 1
	main.call("_game_over")
	var paid := Bones.earned(7, 3, 1, 1)
	_check("dying pays for the run", mb.bones == paid, "%d" % mb.bones)
	_check("the death screen says how many", ("+%d BONES" % paid) in main.hud.get("_over_text").text)
	var card0: Vector2 = main.hud.get("_shop")[1].get_global_rect().get_center()
	_tap(main, card0)
	_check("a tap before the screen settles buys nothing", mb.ranks[1] == 0)
	main.set("_over_t", 0.0)
	mb.bones = 100
	var price := mb.price(1)
	_tap(main, card0)
	_check("tapping a card buys one rank", mb.ranks[1] == 1 and mb.bones == 100 - price)
	# the click a phone makes from that same tap mustn't buy a second one
	_click(card0, InputEvent.DEVICE_ID_EMULATION)
	await _frames(2)
	_check("...and the phone's copy of the tap as a click doesn't buy again", mb.ranks[1] == 1)
	_click(card0, 0)
	await _frames(2)
	_check("clicking a card with the mouse buys one rank", mb.ranks[1] == 2, "%d" % mb.ranks[1])
	_check("the card shows the new rank", main.hud.get("_shop_items")[1][2] == 2)
	mb.bones = 0
	_tap(main, card0)
	_check("without the bones a tap buys nothing", mb.ranks[1] == 2)
	_check("...and the card is dimmed", not main.hud.get("_shop_items")[1][4])

	# the next run starts with what you bought
	mb.bones = 1000
	for k in 3:
		mb.buy(0)
	mb.buy(Bones.RAPTOR)
	var next: Vector2 = main.hud.get("_next").get_global_rect().get_center()
	_click(next, 0)
	await _frames(2)
	_check("NEXT RUN starts the next run", main.playing())
	pl = main.player
	_check("bought bite ranks are on the new run", is_equal_approx(pl.bite_radius,
			Player.STAGES[1].bite + 3 * Bones.RANK_BITE), "%.2f" % pl.bite_radius)
	_check("bought speed ranks are on the new run", is_equal_approx(pl.walk_speed,
			Player.STAGES[1].speed * pow(Bones.RANK_SPEED, 2)), "%.1f" % pl.walk_speed)
	_check("with the Raptor bought you start as a Raptor", pl.stage == 1 and pl.stage_name() == "RAPTOR")
	_check("...at full health", is_equal_approx(pl.hp, pl.max_hp))
	_check("...and starting as one isn't an evolve", main.evolves == 0)
	main.call("_evolve")
	_check("evolving is counted for the bones", main.evolves == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d failed" % _fails)
	quit(_fails)
