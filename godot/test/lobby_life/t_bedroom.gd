extends RefCounted
## Wardrobe and bed.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var w: LobbyWardrobe = ll.things["wardrobe"]
	var b: LobbyBed = ll.things["bed"]
	await t.wait(0.3)
	t.place(180, 640)
	await t.wait(0.2)
	t.check(t.label() == "OPEN", "wardrobe says OPEN (%s)" % t.label())
	t.press_e()
	await t.wait(0.4)
	t.check(w.open and w.k >= 1.0, "E opens it")
	t.check(ll.ui.menu_open(), "and the menu shows")
	await t.wait(0.1)
	t.check(t.label() == "CLOSE", "label is CLOSE")
	ll.ui.close_menu()
	# change clothes
	w.clothes()
	var bt: Array = ll.ui.menu_buttons()
	t.check(bt.size() == 4, "clothes menu has 3 characters and BACK (%d)" % bt.size())
	bt[1].pressed.emit()
	t.check(ll.player.char_id == "tyson2", "changing clothes changes the character")
	ll.player.char_id = "juicy"
	t.press_e()
	await t.wait(0.5)
	t.check(not w.open and w.k <= 0.0, "E closes it")
	# the shirt editor
	var im := Image.create(60, 40, false, Image.FORMAT_RGBA8)
	im.fill(Color.RED)
	w.editor.take_picture(im)
	t.check(w.editor.is_open() and LobbyLook.art_front != null, "a picture opens the editor")
	t.check(w.editor.place.size.x > 0.3, "and is fitted to the shirt")
	w.editor._fit("fill")
	w.editor._on_done()
	t.check(not w.editor.is_open() and LobbyLook.place_front.size.x > 0.5, "DONE keeps the place")
	var tex = GameData.tex("assets/CHARS/juicy/sprites/front_run_0.png")
	var bk = LobbyLook.baked("assets/CHARS/juicy/sprites/front_run_0.png", tex, false)
	t.check(bk != tex, "the singlet frame is printed")
	LobbyLook.clear_art()
	# the bed
	t.place(360, 700)
	await t.wait(0.2)
	t.check(t.label() == "LIE DOWN", "bed says LIE DOWN (%s)" % t.label())
	var slept := [0]
	var woke := [0]
	ll.sleep_requested.connect(func(_p): slept[0] += 1)
	ll.woke.connect(func(_p): woke[0] += 1)
	t.press_e()
	await t.wait(0.3)
	t.check(ll.busy.has(ll.player) and b.sides.get(ll.player) == 1, "E lies him down on the left half")
	t.check(slept[0] == 1, "sleep_requested fired")
	t.check(t.label() == "GET UP", "label GET UP")
	var o := LobbyLife.hpos(ll.player)
	t.check(absf(o.x - 350.0) < 1.0 and absf(o.y - 590.0) < 1.0, "he's at bedSpot (%s)" % o)
	t.press_e()
	await t.wait(0.3)
	t.check(not ll.busy.has(ll.player) and woke[0] == 1, "E gets up, woke fired")
	o = LobbyLife.hpos(ll.player)
	t.check(o.y > 680.0, "at the foot of the bed (%s)" % o)
	t.press_e()
	await t.wait(0.2)
	await t.hold("move_up", 0.3)
	t.check(not ll.busy.has(ll.player), "a move key gets him up")
