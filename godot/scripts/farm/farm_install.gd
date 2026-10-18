class_name FarmInstall
extends RefCounted
## The farm's one entry point: FarmInstall.install(main) adds the farm to the running game (PARALLEL.md, "Hook in
## from outside"). Call it at the end of main._ready(). It adds:
## - /root/GameClock (the stand-in, game_clock_standin.gd) and /root/Wallet (farm_wallet_standin.gd) if nothing's
##   there yet, so it runs before the Lighting session's clock and the shared wallet are merged;
## - main/Farm (the Farm: state, clock, saving, hooks), main/FarmWorld (plots, props, the land stages, the E
##   spots) and main/FarmUI (status strip, hints, toasts, the panel).
## Returns the Farm.

const D := preload("res://scripts/farm/farm_data.gd")
const ClockStandin := preload("res://scripts/farm/game_clock_standin.gd")
const WalletStandin := preload("res://scripts/farm/farm_wallet_standin.gd")

static func install(main: Node) -> Farm:
	var existing := main.get_node_or_null("Farm")
	if existing is Farm:
		return existing   # main.gd already installed it (the test scene calls this again)
	var root := main.get_tree().root
	var clock := root.get_node_or_null("GameClock")
	if clock == null:
		clock = ClockStandin.new()
		clock.name = "GameClock"
		root.add_child.call_deferred(clock)
	var wallet: Node = Wallet.ensure(main.get_tree())   # the game's one wallet (scripts/ui/wallet.gd)
	var farm := Farm.new()
	farm.name = "Farm"
	farm.main = main
	farm.clock = clock
	farm.wallet = wallet
	main.add_child(farm)
	var world := FarmWorld.new()
	main.add_child(world)
	world.build(farm)
	var ui := FarmUI.new()
	ui.name = "FarmUI"
	main.add_child(ui)
	ui.setup(farm, world, main.get("player"), main.get("rig"))
	var follow := FarmBounds.new()
	follow.name = "FarmBounds"
	follow.main = main
	main.add_child(follow)
	print("Farm: installed (%s clock, %s wallet)" % ["stand-in" if clock.get("STANDIN") == true else "game", "stand-in" if wallet.get("STANDIN") == true else "game"])
	return farm

## Out on the bought land (past the yard's fences) the top-down view may follow you beyond the yard (main keeps
## the camera inside worldW x worldH): widen the rig's bounds to the whole farm while you're out there.
class FarmBounds extends Node:
	var main: Node
	var _orig = null

	func _process(_dt: float) -> void:
		var rig = main.get("rig") if main else null
		var pl = main.get("player") if main else null
		if rig == null or pl == null:
			return
		if _orig == null:
			_orig = rig.bounds
		var h: Vector3 = GameData.from_3d(pl.global_position)
		var r: Rect2 = _orig
		var out: bool = r.size != Vector2.ZERO and (h.x > r.end.x - 300.0 or h.y > r.end.y - 300.0)
		rig.bounds = Rect2(0, 0, D.LAND_W, D.LAND_H) if out else r
