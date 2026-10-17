extends Node
## One wallet for the whole game: the farm, the lobby's machines and the fight all see and change the same cash.
## godot --headless --fixed-fps 60 --path godot res://test/combat/wallet_test.tscn

var main: Node
var t := 0.0
var step := 0
var fails := 0

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1

func _physics_process(delta: float) -> void:
	t += delta
	var w := Wallet.get_wallet(get_tree())
	var fg := Fight.me
	if w == null or fg == null:
		return
	match step:
		0:
			if t > 0.5:
				var farm = main.get_node_or_null("Farm")
				check(farm != null and farm.wallet == w, "the farm uses /root/Wallet")
				var ll = main.get_node_or_null("LobbyLife")
				check(ll != null and ll.cash(main.player) == w.cash, "the lobby reads it ($%d)" % w.cash)
				w.set_cash(1000)
				step = 1
		1:
			check(fg.f.coins == 1000, "the fight reads it (%d)" % fg.f.coins)
			fg.sim.pay_kill(400, 300, 3, 0)           # a batter's $3 to player 1
			step = 2
		2:
			check(w.cash == 1003, "fight pay lands in it (%d)" % w.cash)
			var ll = main.get_node_or_null("LobbyLife")
			if ll:
				ll.add_cash(main.player, -5)          # a slot pull
			step = 3
		3:
			check(w.cash == 998 and fg.f.coins == 998, "the lobby spends it, the fight sees it (%d / %d)" % [w.cash, fg.f.coins])
			fg.start_run()
			step = 4
		4:
			check(fg.f.coins == 998, "it carries into a run (%d)" % fg.f.coins)
			print("wallet test: %s" % ("ok" if fails == 0 else "%d failed" % fails))
			get_tree().quit(1 if fails else 0)
