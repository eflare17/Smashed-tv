extends RefCounted
## The slot machine.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var s: LobbySlot = ll.things["slot"]
	await t.wait(0.3)
	t.place(90, 150)
	await t.wait(0.2)
	t.check(t.label() == "SPIN $5", "label SPIN $5 (%s)" % t.label())
	var c0 := ll.cash(ll.player)
	var got := []
	s.prize.connect(func(_p, k): got.append(k))
	t.press_e()
	await t.wait(0.2)
	t.check(ll.cash(ll.player) == c0 - 5 and ll.busy.has(ll.player), "pulling pays $5 and roots him")
	await t.wait(1.6)
	t.check(not ll.busy.has(ll.player) and got.size() == 1, "after 1.6 s the prize arrives (%s)" % [got])
	t.check(s.cool > 7.0 and t.label().begins_with("WAIT"), "then it recharges (%s)" % t.label())
	# odds over many picks
	var counts := {}
	for i in 1800:
		var k: String = s.pick_prize().key
		counts[k] = int(counts.get(k, 0)) + 1
	t.check(int(counts.get("clear", 0)) > 40 and int(counts.get("clear", 0)) < 160, "SCREEN CLEAR is about 1 in 18 (%s)" % counts.get("clear", 0))
	t.check(int(counts.get("blasters", 0)) > 200 and int(counts.get("blasters", 0)) < 460, "REAL GUNS about 3 in 18 (%s)" % counts.get("blasters", 0))
	# jackpot notes
	var base := ll.cash(ll.player)
	s.award(ll.player, LobbySlot.PRIZES[5])
	t.check(s.notes.size() == 18, "JACKPOT throws 18 notes")
	await t.wait(3.0)
	t.check(ll.cash(ll.player) > base, "and walking about picks some up (%d)" % (ll.cash(ll.player) - base))
	# speed boost
	var ms := LobbyLife.T("maxSpeed")
	s.award(ll.player, LobbySlot.PRIZES[3])
	t.check(LobbyLife.T("maxSpeed") > ms * 1.5, "SPEED BOOST raises maxSpeed")
	s.speed_t = 0.05
	await t.wait(0.3)
	t.check(is_equal_approx(LobbyLife.T("maxSpeed"), ms), "and it wears off")
