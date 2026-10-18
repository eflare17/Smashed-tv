extends Node
## Two games online, digging (both load it with --netdrive=res://test/dig/net_drive.gd): the guest digs and the
## host's ground follows (its op), the host ploughs and digs a shaft and the guest's follows (the ops passed on),
## each sees the other's tool, and the host drops down his shaft on both screens. Prints "CHECK <name> ok|FAIL" and
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
				dig.carve(Vector3(1100, 1300, -40), Vector3(1100, 1300, 40), 20.0, me)
				expect("keeps its own dig", func(): return g.vol.surface_height(1100, 1300) < -30.0, 10.0,
					func(): return "%.1f" % g.vol.surface_height(1100, 1300))
			else:
				expect("sees the guest's dig", func(): return g.vol.surface_height(1100, 1300) < -30.0, 20.0,
					func(): return "%.1f" % g.vol.surface_height(1100, 1300))
				expect("sees the guest's shovel", func(): return dig.tool_of(net.p2) == "shovel", 20.0)
		3:
			if host:
				dig.set_tool(me, "hoe")
				g.plough(1300, 1150, Vector2.RIGHT)
				dig.carve(Vector3(1250, 1350, -150), Vector3(1250, 1350, 30), 22.0, me)
				me.place(1250, 1350)
				expect("falls into its own shaft", func(): return me.global_position.y / U < -120.0, 10.0,
					func(): return "%.1f" % (me.global_position.y / U))
			else:
				expect("sees the host's ploughing", func(): return g.soil_at(1300, 1150) == 1, 20.0)
				expect("sees the host's shaft", func(): return g.vol.surface_height(1250, 1350) < -120.0, 20.0,
					func(): return "%.1f" % g.vol.surface_height(1250, 1350))
				expect("sees the host's hoe", func(): return dig.tool_of(net.p2) == "hoe", 20.0)
				expect("sees the host down in it", func(): return is_instance_valid(net.p2) and net.p2.global_position.y / U < -120.0, 20.0,
					func(): return "%.1f" % (net.p2.global_position.y / U) if is_instance_valid(net.p2) else "gone")
		4:
			done = true
			print("DRIVE DONE fails=%d" % fails)
			get_tree().create_timer(25.0 if host else 1.0).timeout.connect(func(): get_tree().quit(1 if fails > 0 else 0))
