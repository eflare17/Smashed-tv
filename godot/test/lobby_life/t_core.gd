extends RefCounted
## The framework: installed, things made, money, the UI.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	t.check(ll != null and ll.get_parent() == t.main, "installed under main")
	t.check(ll.get_index() < t.main.hud.get_index(), "before the Hud in main's children")
	for k in ["pool", "gym", "rope", "table", "mirror", "wardrobe", "bed", "shroom", "slot", "vend", "bbq", "goth_life"]:
		t.check(ll.things.has(k), "thing " + k)
	var c := ll.cash(ll.player)
	t.check(c >= 40, "starts with money (%d)" % c)
	t.check(ll.pay(ll.player, 5) and ll.cash(ll.player) == c - 5, "pay")
	ll.add_cash(ll.player, 5)
	ll.ui.say(t.main.gothica, "hello", 1.0)
	t.check(ll.ui.saying(t.main.gothica) == "hello", "speech bubble")
	await t.wait(1.2)
	t.check(ll.ui.saying(t.main.gothica) == "", "bubble gone after its time")
