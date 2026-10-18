extends RefCounted
## The barbecue and the esky.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var b: LobbyBbq = ll.things["bbq"]
	var p := ll.player
	await t.wait(0.3)
	t.place(510, 690)
	await t.wait(0.2)
	t.check(t.label() == "GRAB SNAG", "esky: GRAB SNAG (%s)" % t.label())
	t.press_e()
	t.check(b.food_of(p) == 1, "holding a raw snag")
	t.check(t.label() == "PUT BACK", "PUT BACK")
	t.place(560, 660)
	await t.wait(0.2)
	t.check(t.label() == "COOK", "bbq with a raw snag: COOK (%s)" % t.label())
	t.press_e()
	t.check(b.food_of(p) == 0 and float(b.s[0]) == 0.0, "snag on the plate")
	t.check(t.label() == "LIGHT", "then LIGHT (%s)" % t.label())
	t.press_e()
	t.check(b.heat == 1 and t.label() == "TURN UP", "heat 1")
	t.press_e()
	t.press_e()
	t.check(b.heat == 3 and t.label() == "TURN OFF", "heat 3")
	await t.wait(6.2)
	t.check(float(b.s[0]) >= 1.0, "cooked in about 6 s on high (%f)" % float(b.s[0]))
	t.check(t.label() == "TAKE SNAG", "TAKE SNAG (%s)" % t.label())
	t.press_e()
	t.check(b.food_of(p) == 2 and float(b.s[0]) == -1.0, "holding a cooked snag")
	t.check(t.label() == "EAT", "EAT (%s)" % t.label())
	t.place(300, 300)
	await t.wait(0.2)
	t.check(t.label() == "EAT", "EAT works anywhere (%s)" % t.label())
	t.press_e()
	t.check(b.food_of(p) == 0, "eaten")
	# burnt
	b.s[2] = 1.8
	b.set_food(p, 0)
	t.place(560, 660)
	await t.wait(0.2)
	t.press_e()
	t.check(b.food_of(p) == 3, "an overdone snag is burnt")
	t.check(t.label() == "EAT IT?", "EAT IT?")
	t.press_e()
	b.heat = 0
