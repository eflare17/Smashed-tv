extends Node
## Drives one side of a two-game online test (both games load it with --netdrive=res://test/net/drive.gd, or
## ?netdrive=... on the web): walking, a character change, the farm, both in bed, a fight with both shooting, a
## restart. The two games run at their own speeds (two browser pages on a software renderer differ a lot), so
## each check waits for its condition up to a deadline. Prints "CHECK <name> ok|FAIL ...", "DRIVE DONE fails=N".
## Owned by the Online task.

var net: Net
var fails := 0
var phase := 0
var phase_t := 0.0
var waiting: Array = []          # [name, callable, deadline, detail callable]
var start_them := Vector3.ZERO
var saw_enemies := 0
var day0 := 0
var host := false
var done := false

func _ready() -> void:
	net = get_parent()

func check(name: String, ok: bool, detail: String = "") -> void:
	print("CHECK %s %s %s" % [name, "ok" if ok else "FAIL", detail])
	if not ok:
		fails += 1

## Wait for cond to be true (checked every frame), failing after secs.
func expect(name: String, cond: Callable, secs: float, detail: Callable = Callable()) -> void:
	waiting.append([("host " if host else "guest ") + name, cond, secs, detail])

func _who() -> String:
	return "host" if host else "guest"

func _process(dt: float) -> void:
	if done or not net.live or net.fight == null or not is_instance_valid(net.fight) or net.p2 == null or not is_instance_valid(net.p2):
		return
	host = net.role == "host"
	var fight := net.fight
	if fight.sim.started:
		saw_enemies = maxi(saw_enemies, fight.sim.enemies.size())
	# the checks waiting
	for w in waiting.duplicate():
		if w[1].call():
			check(w[0], true, w[3].call() if w[3].is_valid() else "")
			waiting.erase(w)
		else:
			w[2] -= dt
			if w[2] <= 0.0:
				check(w[0], false, w[3].call() if w[3].is_valid() else "")
				waiting.erase(w)
	phase_t += dt
	# the next phase starts when this one's checks are all in, and a moment has passed
	if not waiting.is_empty() or phase_t < 1.0:
		return
	phase_t = 0.0
	phase += 1
	var me: Player = net.player
	match phase:
		1:
			print("DRIVE live as ", net.role)
			start_them = net.p2.html_pos()
			Input.action_press("move_down" if host else "move_right")
			get_tree().create_timer(1.0).timeout.connect(func():
				Input.action_release("move_down")
				Input.action_release("move_right"))
			if host:
				expect("sees the guest walk right", func(): return net.p2.html_pos().x - start_them.x > 40.0, 30.0,
					func(): return str(net.p2.html_pos() - start_them))
			else:
				expect("sees the host walk down", func(): return net.p2.html_pos().y - start_them.y > 40.0, 30.0,
					func(): return str(net.p2.html_pos() - start_them))
		2:
			if not host:
				me.char_id = "goth"
			else:
				expect("sees the guest's character", func(): return net.p2.char_id == "goth", 30.0, func(): return net.p2.char_id)
		3:
			var fm := Farm.instance
			if not host:
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
			expect("sees the planted plot", func():
				for p in Farm.instance.state.plots:
					if int(p.s) >= 0:
						return true
				return false, 30.0)
		4:
			day0 = get_node("/root/GameClock").day
			LobbyLife.current.things["bed"].lie_down(me, 1 if host else 2)
			expect("sees the other in bed", func(): return bool(net.remote_av.get("bed", false)), 40.0)
			expect("slept to the next morning", func():
				var gc := get_node("/root/GameClock")
				return gc.day == day0 + 1 and gc.hour < 8.0, 60.0,
				func(): return "day %d -> %d" % [day0, get_node("/root/GameClock").day])
		5:
			LobbyLife.current.things["bed"].get_up(me)
			if host:
				get_tree().create_timer(3.0).timeout.connect(func(): fight.start_run())
			expect("is in the run", func(): return net.fight.sim.started, 60.0)
		6:
			fight.debug["auto"] = true
			expect("saw enemies", func(): return saw_enemies > 0, 60.0)
			expect("fired", func(): return net.fight.f.shots > 0, 60.0, func(): return "shots=%d" % net.fight.f.shots)
			expect("sees the other fire", func(): return net.fight.f2 != null and net.fight.f2.shots > 0, 90.0,
				func(): return "shots=%d" % (net.fight.f2.shots if net.fight.f2 else -1))
			expect("sees kills", func(): return net.fight.f.kills + (net.fight.f2.kills if net.fight.f2 else 0) > 0, 90.0)
		7:
			fight.debug.erase("auto")
			print("DRIVE fight: wave=%d kills=%d+%d hp=%.0f/%.0f" % [fight.sim.wave, fight.f.kills, fight.f2.kills, fight.f.hp, fight.f2.hp])
			if not host:
				get_tree().create_timer(4.0).timeout.connect(func(): net._on_request("restart"))
			var old_fight := fight.get_instance_id()
			expect("back in the lobby, still together", func():
				return net.fight != null and is_instance_valid(net.fight) and net.fight.get_instance_id() != old_fight and is_instance_valid(net.fight) and not net.fight.sim.started and net.live and net.p2 != null, 90.0)
		8:
			print("DRIVE DONE fails=%d" % fails)
			done = true
