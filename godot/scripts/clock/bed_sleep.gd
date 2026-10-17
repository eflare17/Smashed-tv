class_name BedSleep
extends Interactable
## Lying in the bed skips to 7 am on the next day (1.4). Owned by the Lighting session.
##
## A stand-in until the Lobby session's bed (which lets you lie down and has a sleep_requested signal) arrives:
## LightingInstall puts one of these on the bed (game_data.json's BED) and takes it away again as soon as an
## interactable with a sleep_requested signal turns up, connecting that signal to sleep() instead.
## Online (later): sleeping needs both players in bed; the host's sleep() moves the shared clock.

signal slept(day: int)

var hud: ClockHud
## Something sleeping now (no second sleep till it's done).
var busy: bool = false

func label_for(_player: Node) -> String:
	return "" if busy else "SLEEP"

func act(player: Node) -> void:
	sleep(player)

## Fade out, move the clock to 7 am tomorrow, fade back in (the player can't move meanwhile).
func sleep(player: Node = null) -> void:
	if busy:
		return
	busy = true
	var c := get_node_or_null("/root/GameClock")
	if player and "controls_enabled" in player:
		player.controls_enabled = false
	var mid := func():
		if c:
			c.sleep_to_morning()
	var text := func() -> String: return ("Day %d" % c.day) if c else "Morning"
	if hud:
		await hud.sleep_fade(mid, text)
	else:
		mid.call()
	if player and is_instance_valid(player) and "controls_enabled" in player:
		player.controls_enabled = true
	busy = false
	slept.emit(c.day if c else 0)
