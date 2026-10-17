extends Node
## Drives one side of a two-game online test (both games load it with --netdrive=res://test/net/drive.gd, or
## ?netdrive=... on the web): walking, a character change, the farm, both in bed, a fight with both shooting, a
## restart. Prints "CHECK <name> ok" / "CHECK <name> FAIL ..." and "DRIVE DONE".
## Owned by the Online task.

var t := -1.0
var step := 0
var net: Net
var start_them := Vector3.ZERO
var saw_enemies := 0
var fails := 0
var restarted := false
var steps_done := {}
var day0 := 0

func _ready() -> void:
	net = get_parent()

func check(name: String, ok: bool, detail: String = "") -> void:
	print("CHECK %s %s %s" % [name, "ok" if ok else "FAIL", detail])
	if not ok:
		fails += 1

func at(sec: float, key: String) -> bool:
	if t >= sec and not steps_done.has(key):
		steps_done[key] = true
		return true
	return false

func _process(dt: float) -> void:
	if not net.live or net.fight == null or not is_instance_valid(net.fight) or net.p2 == null or not is_instance_valid(net.p2):
		return
	if t < 0.0:
		t = 0.0
		print("DRIVE live as ", net.role)
	t += dt
	var host := net.role == "host"
	var fight := net.fight
	var me: Player = net.player
	if fight.sim.started:
		saw_enemies = maxi(saw_enemies, fight.sim.enemies.size())
	if at(1.0, "walk"):
		start_them = net.p2.html_pos()
		Input.action_press("move_down" if host else "move_right")
	if at(2.0, "walk_end"):
		Input.action_release("move_down")
		Input.action_release("move_right")
	if at(3.5, "walk_check"):
		var d := net.p2.html_pos() - start_them
		if host:
			check("host sees the guest walk right", d.x > 40.0, "moved %s" % d)
		else:
			check("guest sees the host walk down", d.y > 40.0, "moved %s" % d)
	if at(4.0, "char") and not host:
		me.char_id = "goth"
	if at(5.5, "char_check") and host:
		check("host sees the guest's character", net.p2.char_id == "goth", net.p2.char_id)
	if at(6.0, "farm") and not host:
		var fm := Farm.instance
		fm.buy_seed(1, 0, 1)
		fm.pick_seed(1, 0)
		var spot: Node = null
		for n in get_tree().get_nodes_in_group("interactable"):
			if n is FarmSpot and n.kind == "plot" and fm.spot_label(n, me).begins_with("PLANT"):
				spot = n
				break
		check("guest has a plot to plant", spot != null)
		if spot:
			fm.spot_act(spot, me)
			print("DRIVE planted plot ", spot.idx)
	if at(8.0, "farm_check"):
		var planted := 0
		for p in Farm.instance.state.plots:
			if int(p.s) >= 0:
				planted += 1
		check(("host" if host else "guest") + " sees the planted plot", planted >= 1, "planted=%d" % planted)
	if at(8.5, "bed"):
		day0 = get_node("/root/GameClock").day
		var bed = LobbyLife.current.things["bed"]
		bed.lie_down(me, 1 if host else 2)
	if at(13.0, "bed_check"):
		var gc := get_node("/root/GameClock")
		check(("host" if host else "guest") + " slept to the next morning", gc.day == day0 + 1 and gc.hour < 8.0, "day %d -> %d hour=%.2f" % [day0, gc.day, gc.hour])
		LobbyLife.current.things["bed"].get_up(me)
	if at(14.0, "run") and host:
		fight.start_run()
	if at(15.0, "run_check"):
		check(("host" if host else "guest") + " is in the run", fight.sim.started)
		fight.debug["auto"] = true
	if at(26.0, "fight_check"):
		fight.debug.erase("auto")
		check(("host" if host else "guest") + " saw enemies", saw_enemies > 0, "max=%d wave=%d" % [saw_enemies, fight.sim.wave])
		check(("host" if host else "guest") + " fired", fight.f.shots > 0, "shots=%d" % fight.f.shots)
		check(("host" if host else "guest") + " sees the other fire", fight.f2.shots > 0, "shots=%d" % fight.f2.shots)
		var kills := fight.f.kills + fight.f2.kills
		check(("host" if host else "guest") + " kills", kills > 0, "kills=%d+%d" % [fight.f.kills, fight.f2.kills])
	if at(27.0, "restart") and not host:
		net._on_request("restart")
	if at(30.0, "restart_check"):
		check(("host" if host else "guest") + " back in the lobby, still together", not fight.sim.started and net.live, "started=%s" % fight.sim.started)
		print("DRIVE DONE fails=%d" % fails)
