extends Node
## Drives one side of a two-game online test of the night zombies (both games: --netdrive=res://test/zombie/net_zombie.gd
## --zombie). The host's game runs the night; the guest must see its zombies (models too), see one it kills fall,
## be knocked down and come to inside, and see them gone at dawn. Prints "CHECK <name> ok|FAIL", "DRIVE DONE fails=N".
##   godot --headless --path $W --fixed-fps 60 -- --host=TEST --netdrive=res://test/zombie/net_zombie.gd --zombie &
##   godot --headless --path $W --fixed-fps 60 -- --join=127.0.0.1 --netdrive=res://test/zombie/net_zombie.gd --zombie

var net: Net
var fails := 0
var host := false
var step := 0
var t := 0.0
var deadline := 0.0
var done := false

func _ready() -> void:
	net = get_parent()

func check(name: String, ok: bool, detail := "") -> void:
	print("CHECK %s %s %s" % [("host " if host else "guest ") + name, "ok" if ok else "FAIL", detail])
	if not ok:
		fails += 1

func _sim() -> FightSim:
	return net.fight.sim

## Waits for cond up to secs, then checks it and moves on.
func wait(name: String, cond: bool, secs: float, detail := "") -> void:
	if cond or t > secs:
		check(name, cond, detail)
		step += 1
		t = 0.0

func _process(dt: float) -> void:
	if done or not net.live or net.fight == null or not is_instance_valid(net.fight) or net.p2 == null:
		return
	host = net.role == "host"
	t += dt
	var s := _sim()
	var me: Player = net.fight.player
	var gc := get_node("/root/GameClock")
	if host:
		gc.hour = 23.5 if step < 6 else 6.5
	match step:
		0:
			# both out in the yard
			me.place(1000.0 if host else 1080.0, 1200.0)
			step += 1
			t = 0.0
		1:
			s.players[0].iframe = 1.0
			if host:
				wait("zombies come at night", ZombieSim.count(s) >= 1, 40.0, "(%d)" % ZombieSim.count(s))
			else:
				wait("sees the host's zombies", ZombieSim.count(s) >= 1, 50.0, "(%d)" % ZombieSim.count(s))
		2:
			s.players[0].iframe = 1.0
			var zn: ZombieNight = net.main.get_node("ZombieNight")
			wait("draws them as the model", zn.view.shown() >= 1, 10.0, "(%d)" % zn.view.shown())
		3:
			# the host kills one: the guest sees it fall
			s.players[0].iframe = 1.0
			if host and t > 2.0 and s.corpses.filter(func(c): return c.t == ZombieSim.T).is_empty():
				for e: FT.Enemy in s.enemies:
					if e.t == ZombieSim.T:
						s.kill_enemy(e, 200.0, 0.0, false, 0, 1.0, true)
						break
			wait("a killed one falls", not s.corpses.filter(func(c): return c.t == ZombieSim.T).is_empty(), 20.0)
		4:
			# the guest is knocked down out there (by the host's sim) and comes to inside
			if host and t > 1.0 and t < 1.2 and s.players.size() > 1 and s.players[1].alive:
				s.players[1].iframe = 0.0
				var over := s.over
				s.hurt_player(s.players[1], 99.0, 0.0, 1.0, 0.0)
				s.over = over
			if host:
				s.players[0].iframe = 1.0
				wait("the guest goes down and comes back", t > 9.0, 10.0)
			else:
				var hp := me.html_pos()
				wait("knocked down, back on its feet inside", t > 3.0 and s.players[0].alive and not ZombieSim.in_yard(hp.x, hp.y) and me.controls_enabled, 25.0,
					"(alive %s at %.0f,%.0f)" % [s.players[0].alive, hp.x, hp.y])
		5:
			s.players[0].iframe = 1.0
			wait("night still on", true, 0.0)
		6:
			# dawn (the host's clock): gone on both sides
			wait("gone by morning", ZombieSim.count(s) == 0, 25.0, "(%d)" % ZombieSim.count(s))
		_:
			print("DRIVE DONE fails=%d" % fails)
			done = true
			await get_tree().create_timer(3.0).timeout
			get_tree().quit(1 if fails > 0 else 0)
