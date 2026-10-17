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
## Saved (a second after a change, and when the window closes or loses focus) so a reload keeps the money and the
## farm's purchases stay paid for. Headless runs (the tests) neither load nor save it.
const SAVE_PATH := "user://smashed-wallet.json"

var cash: int = 0
var _save_pending := false

static func _persist() -> bool:
	return DisplayServer.get_name() != "headless"

static func _load_saved() -> int:
	if not _persist() or not FileAccess.file_exists(SAVE_PATH):
		return -1
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return -1
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary and d.has("cash"):
		return int(d.cash)
	return -1

func save() -> void:
	_save_pending = false
	if not _persist():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cash": cash}))

func _save_soon() -> void:
	if _save_pending or not is_inside_tree():
		return
	_save_pending = true
	get_tree().create_timer(1.0).timeout.connect(func(): if _save_pending: save())

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _save_pending:
			save()

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
	var saved := _load_saved()
	if saved >= 0:
		nw.cash = saved
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
	_save_soon()
	changed.emit(cash)
	cash_changed.emit(cash)

func add_cash(n: int, _why: String = "") -> void:
	set_cash(cash + n)

func spend_cash(n: int, _why: String = "") -> bool:
	if n > cash:
		return false
	set_cash(cash - n)
	return true
