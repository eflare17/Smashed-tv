extends Node
## A stand-in for the shared wallet (PLAN.md: "One wallet for wave cash and trading money"), so the farm can buy
## and sell before the real one exists. FarmInstall adds it at /root/Wallet only when nothing's there. The farm
## talks to whatever wallet it has through these three functions (duck typed), so the real one needs only these:
##   get_cash() -> int, add_cash(n: int, why: String) -> void, spend_cash(n: int, why: String) -> bool
## and ideally `signal cash_changed(cash: int)`.

signal cash_changed(cash: int)

const STANDIN := true             # (the farm saves the stand-in's cash with the farm)

var cash: int = 0

func get_cash() -> int:
	return cash

func add_cash(n: int, _why: String = "") -> void:
	cash += n
	cash_changed.emit(cash)

func spend_cash(n: int, _why: String = "") -> bool:
	if n > cash:
		return false
	cash -= n
	cash_changed.emit(cash)
	return true
