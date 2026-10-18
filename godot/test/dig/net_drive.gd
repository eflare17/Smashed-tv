extends Node
## Two games online, digging (both load it with --netdrive=res://test/dig/net_drive.gd): the guest digs and the
## host's ground follows (its op), the host ploughs and digs and the guest's follows (the snapshot), each sees
## the other's tool, and the other player stands in a hole on both screens. Prints "CHECK <name> ok|FAIL" and
## "DRIVE DONE fails=N". Run (in a work copy):
##   godot --headless --path $W --fixed-fps 60 -- --host=TEST --netdrive=res://test/dig/net_drive.gd &
##   godot --headless --path $W --fixed-fps 60 -- --join=127.0.0.1 --netdrive=res://test/dig/net_drive.gd

const U := 0.025

var net: Net
var fails := 0
var phase := 0
var phase_t := 0.0
var waiting: Array = []
var host := false
var done := false

func _ready() -> void:
	net = get_parent()

func check(name: String, ok: bool, detail: String = "") -> void:
	print("CHECK %s %s %s" % [name, "ok" if ok else "FAIL", detail])
	if not ok:
		fails += 1

func expect(name: String, cond: Callable, secs: float, detail: Callable = Callable()) -> void:
	waiting.append([("host " if host else "guest ") + name, cond, secs, detail])

func _process(dt: float) -> void:
	if done:
		return
	for w in waiting.duplicate():
		if w[1].call():
			check(w[0], true, w[3].call() if w[3].is_valid() else "")
			waiting.erase(w)
		else:
			w[2] -= dt
			if w[2] <= 0.0:
				check(w[0], false, w[3].call() if w[3].is_valid() else "")
				waiting.erase(w)
	# (the host waits a while before quitting, so the guest's last checks see it)
	if not net.live or net.p2 == null or not is_instance_valid(net.p2) or Dig.instance == null:
		return
	host = net.role == "host"
	var dig := Dig.instance
	var g := dig.grid
	phase_t += dt
	if not waiting.is_empty() or phase_t < 1.5:
		return
	phase_t = 0.0
	phase += 1
	var me: Player = net.player
	match phase:
		1:
			print("DRIVE live as ", net.role)
			g.clear()
		2:
			if not host:
				dig.set_tool(me, "shovel")
				dig.dig_at(me, Vector2(1100, 1300))
				dig.dig_at(me, Vector2(1100, 1300))
				expect("keeps its own dig", func(): return absf(g.depth_at(1100, 1300) - 18.0) < 0.01, 10.0,
					func(): return "%.1f" % g.depth_at(1100, 1300))
			else:
				expect("sees the guest's dig", func(): return absf(g.depth_at(1100, 1300) - 18.0) < 0.01, 20.0,
					func(): return "%.1f" % g.depth_at(1100, 1300))
				expect("sees the guest's shovel", func(): return dig.tool_of(net.p2) == "shovel", 20.0)
		3:
			if host:
				dig.set_tool(me, "hoe")
				g.plough(1300, 1150, Vector2.RIGHT)
				for i in 4:
					dig.dig_at(me, Vector2(1250, 1350))
				me.place(1250, 1350)
				expect("stands in its own hole", func(): return absf(me.global_position.y / U + 36.0) < 0.6, 10.0,
					func(): return "%.1f" % (me.global_position.y / U))
			else:
				expect("sees the host's ploughing", func(): return g.soil_at(1300, 1150) == 1, 20.0)
				expect("sees the host's hole", func(): return absf(g.depth_at(1250, 1350) - 36.0) < 0.01, 20.0,
					func(): return "%.1f" % g.depth_at(1250, 1350))
				expect("sees the host's hoe", func(): return dig.tool_of(net.p2) == "hoe", 20.0)
				expect("sees the host standing in it", func(): return is_instance_valid(net.p2) and absf(net.p2.global_position.y / U + 36.0) < 1.0, 20.0,
					func(): return "%.1f" % (net.p2.global_position.y / U) if is_instance_valid(net.p2) else "gone")
		4:
			done = true
			print("DRIVE DONE fails=%d" % fails)
			get_tree().create_timer(25.0 if host else 1.0).timeout.connect(func(): get_tree().quit(1 if fails > 0 else 0))
