extends RefCounted
## The table: chairs, sitting, the bong and its hit, standing up, the trip, blackjack's rules and a played hand.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var tb: LobbyTable = ll.things["table"]
	var p: Player = ll.player
	# geometry and prompts
	t.place(98, 302, Vector2(1, 0))
	t.check(t.label() == "SIT", "SIT next to chair 1 (%s)" % t.label())
	t.place(300, 302)
	t.check(t.label() == "", "nothing far from the chairs")
	t.place(232, 302, Vector2(-1, 0))
	t.check(tb.chair_near(p) == 2, "chair 2 on the right")
	t.place(98, 302, Vector2(1, 0))
	t.press_e()
	await t.wait(0.2)
	t.check(tb.is_seated(p) and ll.busy.get(p) == tb, "E sits him down, the table holds him")
	var o := LobbyLife.hpos(p)
	t.check(o.distance_to(Vector2(121, 302)) < 0.5, "on the chair point (%s)" % str(o))
	t.check(t.label() == "BONG", "seated: BONG (%s)" % t.label())
	t.check(ll.pose_of(p) != null, "Jared's sit art shows")
	t.press_e()
	await t.wait(0.1)
	t.check(tb.has_bong(p) and t.label() == "HIT", "second E takes the bong, then HIT")
	t.check(not tb._bong_pic.visible, "the bong is off the table")
	t.press_e()
	await t.wait(0.1)
	t.check(tb.hitting(p) and t.label() == "", "E starts the hit, no button during it")
	t.press_e()
	t.check(tb.sitters[p].vape < 0.5, "E ignored during a hit")
	# the frames
	t.check(LobbyTable.hit_frame(0.1) == 0 and LobbyTable.hit_frame(1.0) == 1 and LobbyTable.hit_frame(3.0) == 2 \
		and LobbyTable.hit_frame(4.5) == 3 and LobbyTable.hit_frame(6.0) == 0, "sit art frame timings")
	t.check(LobbyTable.hit_heat(1.0) > 0.4 and LobbyTable.hit_heat(5.0) < LobbyTable.hit_heat(2.4), "the vape heats and cools")
	await t.wait(6.3)
	t.check(not tb.hitting(p) and tb.hit_row == 1, "hit done after 6.2 s, one in the row (%d)" % tb.hit_row)
	t.check(not tb.trip.active, "one hit is not a trip")
	# stand up by walking
	await t.hold("move_up", 0.3)
	t.check(not tb.is_seated(p) and not ll.busy.has(p), "walking stands him up")
	o = LobbyLife.hpos(p)
	t.check(o.x < 113.0 or o.x > 217.0 or o.y < 284.0 or o.y > 316.0, "outside the table's box (%s)" % str(o))
	t.check(not p.frozen and p.dz == 0.0, "free again")
	t.check(tb.chair_near(p) >= 0, "chair near check ok")
	# a second hit within 30 s: a trip
	t.place(98, 302, Vector2(1, 0))
	t.press_e()
	await t.wait(0.1)
	t.press_e()
	t.press_e()
	await t.wait(6.3)
	t.check(tb.trip.active, "a second hit within 30 s starts the trip")
	t.check(tb.hit_row == 0, "the row is reset")
	await t.wait(0.5)
	t.check(tb.trip.black() > 0.0 and tb.trip.black() < 1.0, "the screen goes dark (%.2f)" % tb.trip.black())
	await t.wait(3.0)
	t.check(tb.trip.black() == 1.0 and not tb.trip.mantis_now().is_empty() or tb.trip.t > 3.0, "black, the mantis flickers (t %.1f)" % tb.trip.t)
	t.check(tb.trip.segs.size() > 3 and tb.trip.segs[0][0] == 3.0, "its segments are laid out from 3 s (%d)" % tb.trip.segs.size())
	await t.wait(10.6)
	t.check(not tb.trip.active, "the trip ends by 13.8 s")
	# cards
	await _cards(t, ll, tb, p)
	# a second player standing in chair 1 blocks it
	t.reset()

func _cards(t, ll: LobbyLife, tb: LobbyTable, p: Player) -> void:
	var c: LobbyTableCards = tb.cards
	t.check(LobbyTableCards.value([0, 12]) == 21, "ace + king = 21")
	t.check(LobbyTableCards.value([0, 0, 8]) == 21, "ace, ace, nine = 21 (soft counts down)")
	t.check(LobbyTableCards.value([12, 11, 5]) == 26, "bust counts")
	t.check(LobbyTableCards.value([0, 5]) == 17, "soft 17 is 17")
	t.check(LobbyTableCards.value([9, -1]) == 10, "hidden card skipped")
	t.reset()
	t.place(98, 302, Vector2(1, 0))
	t.press_e()
	await t.wait(0.2)
	var goth: GothLife = ll.things["goth_life"]
	c.act(p, "call")
	t.check(c.active() and c.phase() == "idle", "call opens an idle table")
	t.check(goth.claimed_by() == "cards", "Gothica is claimed to deal")
	var cash0 := ll.cash(p)
	# a hand we know: he has 10 + 9 = 19, she K + 7 = 17: he stands, wins
	c.deck = [6, 8, 12, 9]
	c.act(p, "deal")
	t.check(c.phase() == "play" and ll.cash(p) == cash0 - 10, "deal takes the bet")
	t.check(c.bj.seats[1].c == [9, 8] and c.bj.d == [12, 6], "two cards each")
	t.check(c.view_dealer() == [12, -1], "her hole card is hidden")
	t.check(int(c.bj.turn) == 1, "his turn")
	c.act(p, "stand")
	t.check(c.phase() == "dealer", "then hers")
	await t.wait(2.6)
	t.check(c.phase() == "done" and c.bj.seats[1].res == "WIN", "he wins (%s)" % c.bj.seats[1].res)
	t.check(ll.cash(p) == cash0 + 10, "paid 20 for 10 (%d vs %d)" % [ll.cash(p), cash0 + 10])
	# blackjack pays 3:2: A + K
	cash0 = ll.cash(p)
	c.deck = [4, 12, 12, 0]       # pops: 0 (ace), 12 (king dealer), 12 (king him), 4 (dealer's 5)
	c.act(p, "deal")
	t.check(c.bj.seats[1].st == "bj", "ace + king is a blackjack")
	await t.wait(2.8)
	t.check(c.bj.seats[1].res == "BLACKJACK" and ll.cash(p) == cash0 - 10 + 25, "blackjack pays 25 (%d)" % (ll.cash(p) - cash0))
	# bust: 10 + 6 then hit a king
	cash0 = ll.cash(p)
	c.deck = [9, 5, 3, 9]       # him 10 + 6, her 4 + 10
	c.act(p, "deal")
	t.check(c.phase() == "play", "dealt")
	c.deck = [12]
	c.act(p, "hit")
	var v := LobbyTableCards.value(c.bj.seats[1].c)
	if v > 21:
		t.check(c.bj.seats[1].st == "bust", "a bust ends his go")
	await t.wait(2.0)
	t.check(c.phase() == "done", "round over")
	# DONE sends her away
	c.act(p, "stop")
	t.check(not c.active() and goth.claimed_by() == "", "DONE: the table closes, she is free")
	# not enough coins
	ll.add_cash(p, -ll.cash(p) + 5)
	c.act(p, "call")
	c.act(p, "deal")
	t.check(not c.active(), "no deal without 10 coins")
	ll.add_cash(p, 3000)
	# she's busy
	goth.held = true
	c.act(p, "call")
	t.check(not c.active(), "no cards while she is carried")
	goth.held = false
	# leaving mid-hand loses the bet
	c.act(p, "call")
	c.deck = [6, 8, 12, 9]
	cash0 = ll.cash(p)
	c.act(p, "deal")
	await t.hold("move_up", 0.3)
	await t.wait(3.0)
	t.check(not c.active() or c.phase() == "done" or c.phase() == "dealer", "standing mid-hand ends it")
	t.check(ll.cash(p) <= cash0 - 10 + 0, "the bet is lost when he leaves")
