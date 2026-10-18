extends RefCounted
## The bell rope: PULL, ten potatoes that fall, bounce and settle, the cooldown, and picking them up as ammo.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var r: LobbyRope = ll.things["rope"]
	var p: Player = ll.player
	p.remove_meta("spud_ammo") if p.has_meta("spud_ammo") else null
	t.place(300, 175)
	t.check(t.label() == "", "nothing away from the rope")
	t.place(350, 175)
	t.check(t.label() == "PULL", "PULL at the rope (%s)" % t.label())
	t.place(371.5, 175)
	t.check(t.label() == "", "x 371.5 is out of reach")
	t.place(350, 175)
	t.press_e()
	t.check(r.cool > 19.9 and r.rain.size() == 10, "pulled: cooling, ten potatoes in the air")
	t.check(t.label() == "", "cooling: no prompt")
	await t.wait(0.5)
	t.check(r.pull_t == 0.0, "the pull is over in 0.45 s")
	# keep the player away from them while they settle
	t.place(120, 420)
	await t.wait(6.0)
	t.check(r.rain.is_empty(), "all potatoes have settled (%d left)" % r.rain.size())
	t.check(r.spuds.size() == 10, "ten potatoes on the floor (%d)" % r.spuds.size())
	var ok := true
	for s in r.spuds:
		if s.x < 30 or s.x > 830 or s.y < 30 or s.y > 490:
			ok = false
		for b in LobbyLife.calls("lobbySolidBoxes", []):
			if s.x > b.x0 and s.x < b.x1 and s.y > b.y0 and s.y < b.y1:
				ok = false
	t.check(ok, "settled inside the room and not inside furniture")
	# pick one up
	var s0: Dictionary = r.spuds[0]
	t.place(s0.x, s0.y)
	await t.wait(0.2)
	t.check(LobbyRope.ammo(p) >= 10 and LobbyRope.ammo(p) % 10 == 0, "picked up: ammo in tens (%d)" % LobbyRope.ammo(p))
	t.check(r.spuds.size() == 10 - LobbyRope.ammo(p) / 10, "they are gone from the floor")
	# the cap
	p.set_meta("spud_ammo", 195)
	var s1: Dictionary = r.spuds[0]
	t.place(s1.x, s1.y)
	await t.wait(0.2)
	t.check(LobbyRope.ammo(p) == 200, "capped at 200")
	p.set_meta("spud_ammo", 200)
	var n_before := r.spuds.size()
	var s2: Dictionary = r.spuds[0]
	t.place(s2.x, s2.y)
	await t.wait(0.2)
	t.check(r.spuds.size() == n_before, "full of ammo: leaves it")
	# cooldown
	t.place(350, 175)
	t.check(t.label() == "", "still cooling")
	r.cool = 0.0
	t.check(t.label() == "PULL", "ready again after the cooldown")
