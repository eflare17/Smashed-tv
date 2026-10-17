class_name Wallet
extends Node
## The one wallet (PLAN.md: "One wallet for wave cash and trading money"): player 1's money everywhere: kill pay
## and notes in the fight, the slot machine, the vending machine and the cards in the lobby, the farm's buying and
## selling. Lives at /root/Wallet (made by whichever install runs first, Wallet.ensure), so it outlasts a restart
## (R reloads the scene) like the farm and the clock do. Player 2 keeps his own cash in the fight.
##
## The farm talks to it by duck typing (get_cash / add_cash / spend_cash, signal cash_changed); everyone else can
## too, or listen to `changed`.

signal changed(cash: int)
signal cash_changed(cash: int)      ## (the farm's name for it)

const STANDIN := false

var cash: int = 0

## The wallet at /root/Wallet, made now if there isn't one (starting with the HTML game's lobby cash:
## max(lobbyCash, testCash), $2500 while testCash is on).
static func ensure(tree: SceneTree) -> Wallet:
	var w = tree.root.get_node_or_null("Wallet")
	if w is Wallet:
		return w
	var nw := Wallet.new()
	nw.name = "Wallet"
	var t: Dictionary = GameData.data.get("T", {})
	nw.cash = int(maxf(float(t.get("lobbyCash", 40)), float(t.get("testCash", 2500))))
	if w != null:
		# an older stand-in got there first: take its money over
		if w.has_method("get_cash"):
			nw.cash = int(w.get_cash())
		w.name = "WalletOld"
		w.queue_free()
	tree.root.add_child.call_deferred(nw)
	return nw

static func get_wallet(tree: SceneTree) -> Wallet:
	var w = tree.root.get_node_or_null("Wallet") if tree else null
	return w if w is Wallet else null

func get_cash() -> int:
	return cash

func set_cash(n: int) -> void:
	if n == cash:
		return
	cash = n
	changed.emit(cash)
	cash_changed.emit(cash)

func add_cash(n: int, _why: String = "") -> void:
	set_cash(cash + n)

func spend_cash(n: int, _why: String = "") -> bool:
	if n > cash:
		return false
	set_cash(cash - n)
	return true
