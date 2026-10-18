extends Node
## Screenshots of the zombies in the real game (main.tscn), not part of the game. Run in a window (xvfb-run):
## godot --path . res://test/zombie/zombie_shot.tscn -- --out DIR [--hour=23] [--look=low] name,x,y,mode,zoom[,look_ang[,look_y]] ...
## (mode 0 top-down, 1 first person; zoom 0..2). Around him: one shambling at him, one clawing, one screaming,
## one fallen. "arena" as the name starts a run (wave 5) and shoots it there.
var main: Node
var shots: Array = []
var out := "."
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i] == "--out":
			out = a[i + 1]; i += 2; continue
		if not a[i].begins_with("--"):
			shots.append(a[i].split(","))
		i += 1
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.rig.capture_mouse = false
	main.gothica.process_mode = Node.PROCESS_MODE_DISABLED
	main.player.face_mouse = false
	await get_tree().process_frame
	var zn: ZombieNight = main.get_node("ZombieNight")
	var fight: Fight = zn.fight
	zn.set_physics_process(false)          # (no zombies of its own: only the ones placed here)
	for s in shots:
		var s_sim := fight.sim
		var arena := String(s[0]).begins_with("arena")
		if arena and not s_sim.started:
			fight.start_run(true)
			await get_tree().process_frame
		s_sim = fight.sim
		s_sim.enemies.clear()
		s_sim.corpses.clear()
		var x := float(s[1])
		var y := float(s[2])
		if not arena:
			main.player.place(x, y)
		else:
			fight.f.x = x
			fight.f.y = y
		main.player.facing = Vector2(0, -1)
		main.rig.set_zoom(int(s[4]))
		main.rig.set_mode(int(s[3]))
		if s.size() > 5:
			main.player.look_ang = float(s[5])
			main.player.look_y = float(s[6]) if s.size() > 6 else 0.0
		if String(s[0]).begins_with("close"):
			# one just in front of him (south, nearer the camera) and one just behind: who's drawn over whom
			var fr := ZombieSim.spawn_at(s_sim, x + 6.0, y + 32.0)
			fr.st = ZombieSim.WANDER
			fr.zf = 1
			var bk := ZombieSim.spawn_at(s_sim, x - 30.0, y - 34.0)
			bk.st = ZombieSim.WANDER
			bk.zf = 1
			for k in 150:
				fight.f.iframe = 1.0
				await get_tree().physics_frame
			fight.set_meta("frozen", true)
			main.rig.snap()
			for k in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out + "/" + s[0] + ".png")
			fight.remove_meta("frozen")
			continue
		var walker := ZombieSim.spawn_at(s_sim, x - 40.0, y - 190.0)
		walker.st = ZombieSim.CHASE
		walker.zf = 1
		var claw := ZombieSim.spawn_at(s_sim, x + 70.0, y - 60.0)
		claw.st = ZombieSim.CHASE
		claw.zf = 1
		var scream := ZombieSim.spawn_at(s_sim, x - 150.0, y - 120.0)
		scream.st = ZombieSim.CHASE
		var dead := ZombieSim.spawn_at(s_sim, x + 130.0, y - 170.0)
		dead.st = ZombieSim.CHASE
		dead.zf = 1
		s_sim.kill_enemy(dead, 300.0, -100.0, false, 0, 0.0, false)
		for k in 150:
			fight.f.iframe = 1.0
			fight.f.hp = 5.0
			if claw.st == ZombieSim.CHASE and k > 20:
				claw.st = ZombieSim.WINDUP
				claw.st_t = ZombieSim.WINDUP_TIME * 0.15
				claw.sdx = -0.7
				claw.sdy = 0.7
			await get_tree().physics_frame
		fight.set_meta("frozen", true)
		main.rig.snap()
		for k in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/" + s[0] + ".png")
		fight.remove_meta("frozen")
		print("shot ", s[0], " zombies=", ZombieSim.count(s_sim), " fps=", Engine.get_frames_per_second())
	get_tree().quit()
