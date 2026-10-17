extends RefCounted
## The vending machine.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var v: LobbyVend = ll.things["vend"]
	await t.wait(0.3)
	t.place(235, 205)
	await t.wait(0.2)
	t.check(t.label() == "BUY $2500", "label BUY $2500 (%s)" % t.label())
	var got := []
	v.prize.connect(func(_p, k): got.append(k))
	t.press_e()
	await t.wait(0.3)
	t.check(ll.busy.has(ll.player) and v.buy > 0.0, "E starts the hold")
	await t.hold("move_left", 0.2)
	await t.wait(0.3)
	t.check(not ll.busy.has(ll.player) and got.is_empty(), "moving cancels it")
	t.place(235, 205)
	await t.wait(0.2)
	var c0 := ll.cash(ll.player)
	t.press_e()
	await t.wait(1.1)
	t.check(got == ["launcher"] and ll.cash(ll.player) == c0 - 2500, "0.8 s later he owns the launcher")
	t.check(ll.player.get_meta("rockets", 0) == 3, "with 3 rockets")
	t.check(t.label() == "SOLD OUT", "sold out (%s)" % t.label())
	v.restock_t = 0.05
	await t.wait(0.3)
	t.check(not v.sold, "restocks")
	ll.pay(ll.player, ll.cash(ll.player) - 100)
	await t.wait(0.1)
	t.check(t.label() == "NEED $2500", "too poor (%s)" % t.label())
