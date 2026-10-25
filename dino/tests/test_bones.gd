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

	# names: everyone gets a random one and an id; NEW NAME rolls another, and both are saved
	_check("you get a random name", mb.name.split(" ").size() == 3 and mb.name.length() <= 24, mb.name)
	_check("...and an id the database takes", mb.player_id.length() == 36 and mb.player_id[14] == "4", mb.player_id)
	var old_name := mb.name
	mb.new_name()
	var reread := Bones.new()
	reread.path = SAVE
	reread.load_save()
	_check("NEW NAME gives a different name, saved", mb.name != old_name and reread.name == mb.name
			and reread.player_id == mb.player_id)

	# kilograms: a whole grazer is 30 kg of meat, and every mouthful counts
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	main.obstacles.clear()
	await _frames(2)
	pl = main.player
	pl.position = Vector2(200.0, main.GROUND_Y)
	var g: Prey = main.spawn_prey(230.0)
	var px := 0
	for part in g.parts:
		px += part.pixels_total()
	_check("a whole grazer is 30 kg of meat", is_equal_approx(main.call("_kg_px", g) * px, 30.0))
	_check("a run starts with no meat eaten", main.meat_kg == 0.0)
	main.player_bite(pl, g.global_position + Vector2(0, -g.height * 0.5), 6.0)
	_check("a bite of a live animal counts as meat", main.meat_kg > 0.0, "%.2f kg" % main.meat_kg)
	main.call("_game_over")
	_check("the death screen says how much meat", "KG OF MEAT" in main.hud.get("_over_text").text)

	# the leaderboard: off in the tests (nothing is sent), so its button is hidden
	_check("the tests never send to the leaderboard", not main.leaderboard.enabled())
	_check("...and its button is hidden", not main.hud.get("_board_btn").visible)
	main.set("_over_t", 0.0)
	main.hud.set_board_enabled(true)
	_tap(main, main.hud.get("_board_btn").get_global_rect().get_center())
	_check("tapping LEADERBOARD shows the board over the shop", main.hud.board_showing()
			and not main.hud.get("_shop")[0].is_visible_in_tree())
	main.hud.set_board_rows([[1, "BLOODY REX 4", 123.4, false], [2, "SNEAKY FANG 9", 50.0, true]])
	var rows: Array = main.hud.get("_rows")
	_check("the board lists names and kilograms", rows[0][1].text == "BLOODY REX 4" and rows[0][2].text == "123 KG"
			and rows[2][1].text == "", rows[0][2].text)
	_check("...with you in gold", rows[1][1].label_settings.font_color == Hud.GOLD)
	var tab: Button = main.hud.get("_tabs")[2]
	_tap(main, tab.get_global_rect().get_center())
	_check("a tab switches the period", main.get("_board_period") == "month")
	var was := mb.name
	var nn: Button = main.hud.get("_board").get_children().filter(func(b): return b is Button and b.text == "NEW NAME")[0]
	_tap(main, nn.get_global_rect().get_center())
	_check("NEW NAME on the board rolls a new name", mb.name != was and was not in main.hud.get("_board_name").text)
	var back: Button = main.hud.get("_board").get_children().filter(func(b): return b is Button and b.text == "BACK")[0]
	_tap(main, back.get_global_rect().get_center())
	_check("BACK goes back to the shop", not main.hud.board_showing() and main.hud.get("_shop")[0].is_visible_in_tree())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d failed" % _fails)
	quit(_fails)
