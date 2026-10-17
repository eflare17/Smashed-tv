extends RefCounted
## The gym: zones and prompts, plates (take, rack, load, unload, leg press horns), the bench and leg press reps.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var g: LobbyGym = ll.things["gym"]
	var p: Player = ll.player
	# the tree
	t.place(528, 130)
	t.check(t.label() == "TAKE", "TAKE at the tree (%s)" % t.label())
	t.press_e()
	t.check(g.holding_plate(p) == "L", "the biggest plate first (%s)" % g.holding_plate(p))
	t.check(g.pegs[2].is_empty() and g.pegs[5].is_empty() == false, "off the front L peg (the top one), back peg stays")
	t.check(t.label() == "RACK IT", "RACK IT with a plate in hand (%s)" % t.label())
	t.press_e()
	t.check(g.holding_plate(p) == "" and g.pegs[2].size() == 1, "racked back on its home peg")
	# load the bar
	t.place(528, 130)
	t.press_e()   # take L
	t.place(373, 140)
	t.check(t.label() == "LOAD", "LOAD at the bar's left end (%s)" % t.label())
	t.press_e()
	t.check(not g.anim.is_empty() and g.holding_plate(p) == "", "the load animation starts, hands empty")
	t.check(t.label() == "", "nothing else during it")
	await t.wait(1.0)
	t.check(g.bar.L == ["L"] and g.anim.is_empty(), "the plate is on the left side")
	# the bench with uneven sides
	t.place(420, 150)
	t.check(t.label() == "BENCH", "BENCH at the front (%s)" % t.label())
	t.press_e()
	t.check(not g.lifting(p), "uneven bar: no lift (LOAD IT EVEN)")
	# even it up: take a plate, load right
	t.place(528, 130)
	t.press_e()
	t.place(469, 140)
	t.press_e()
	await t.wait(1.0)
	t.check(g.bar.R.size() == 1 and g.bench_kg() == 20 + side(g.bar.L) + side(g.bar.R), "right side loaded, %d kg" % g.bench_kg())
	t.place(373, 140)
	t.check(t.label() == "UNLOAD", "UNLOAD at a loaded end (%s)" % t.label())
	t.place(420, 150)
	t.press_e()
	t.check(g.lifting(p) and g.machine_of(p) == "bench", "lying on the bench")
	var o := LobbyLife.hpos(p)
	t.check(o.distance_to(Vector2(420, 148)) < 0.5, "pinned at the bench (%s)" % str(o))
	t.check(t.label() == "GET UP", "GET UP")
	var rep_len: float = g.lifts[p].rep
	t.check(absf(rep_len - (1.3 + g.bench_kg() * 0.012)) < 0.001, "rep length %.2f s" % rep_len)
	var got := [0]
	g.rep.connect(func(_p, m, n): got[0] = n)
	await t.wait(rep_len * 2.0 + 0.2)
	t.check(g.reps(p) == 2 and got[0] == 2, "two reps counted, signal fired (%d)" % g.reps(p))
	t.press_e()
	t.check(not g.lifting(p) and not p.frozen, "E gets him up")
	# leg press
	t.place(454, 250)
	t.check(t.label() == "LEG PRESS", "LEG PRESS (%s)" % t.label())
	t.press_e()
	t.check(g.machine_of(p) == "leg", "on the leg press")
	var l := LobbyLife.hpos(p)
	t.check(l.distance_to(Vector2(454, 242)) < 0.5, "pinned in the seat (%s)" % str(l))
	await t.hold("move_down", 0.3)
	t.check(not g.lifting(p), "walking gets him off the leg press")
	t.check(LobbyLife.hpos(p).y > 250, "put in front of it")
	# leg horns
	t.place(528, 130)
	t.press_e()
	t.place(515, 200)
	t.check(t.label() == "LOAD", "LOAD at the horns' end (%s)" % t.label())
	t.press_e()
	t.check(g.horn.L.size() + g.horn.R.size() == 1, "a plate on a horn")
	t.check(t.label() == "UNLOAD", "UNLOAD")
	t.press_e()
	t.check(g.holding_plate(p) != "" and g.horn.L.is_empty() and g.horn.R.is_empty(), "taken back off")
	g.drop_plate(p)
	t.check(g.holding_plate(p) == "", "drop_plate racks it")
	t.check(LobbyGym.watch_spot("bench") == Vector2(478, 154) and LobbyGym.watch_spot("leg") == Vector2(390, 262), "watch spots")
	# zones don't reach far
	t.place(300, 400)
	t.check(t.label() == "", "nothing far away")

func side(a: Array) -> int:
	return LobbyGym.side_kg(a)
