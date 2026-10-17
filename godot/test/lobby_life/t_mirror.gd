extends RefCounted
## The mirror: label, look, turn, leave, hair styles baked onto the frames.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var m: LobbyMirror = ll.things["mirror"]
	await t.wait(0.2)
	t.place(246, 640)
	await t.wait(0.2)
	t.check(t.label() == "LOOK", "near the glass the button says LOOK (%s)" % t.label())
	t.place(380, 260)
	await t.wait(0.1)
	t.check(t.label() != "LOOK", "far away it doesn't")
	t.place(246, 640)
	await t.wait(0.1)
	t.press_e()
	await t.wait(0.3)
	t.check(m.looking and ll.busy.has(ll.player), "E looks in the mirror")
	t.check(t.label() == "BACK", "and says BACK")
	var a0 := m.turn
	m.spin(1)
	await t.wait(0.5)
	t.check(m.turn > a0 + 0.7, "the big arrow turns an eighth of a turn")
	var s0 := LobbyLook.style
	m.hair(1)
	t.check(LobbyLook.style == s0 + 1, "F changes the hair")
	LobbyLook.set_style(4)
	var tex = GameData.tex("assets/CHARS/juicy/sprites/front_run_0.png")
	var b = LobbyLook.baked("assets/CHARS/juicy/sprites/front_run_0.png", tex, false)
	t.check(b != tex and b.get_size() == tex.get_size(), "a styled frame is a new picture of the same size")
	LobbyLook.set_style(0)
	b = LobbyLook.baked("assets/CHARS/juicy/sprites/front_run_0.png", tex, false)
	t.check(b == tex, "style 0 leaves it alone")
	t.press_e()
	await t.wait(0.2)
	t.check(not m.looking and not ll.busy.has(ll.player), "E steps away")
	LobbyLook.set_style(0)
