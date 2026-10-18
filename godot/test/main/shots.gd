extends Node
## Screenshots of the real game (main.tscn) with the player put at given spots (not part of the game).
## User args: --out DIR  name,x,y,mode,zoom[,look_ang[,look_y[,dz]]] ...   (mode 0 top-down, 1 first person;
## zoom 0 = 1x, 1 = 1.5x, 2 = 2x; dz > 0 puts him on the trampoline that high over the ground).
## Run in a window (xvfb-run) so it draws: godot --path . res://test/main/shots.tscn -- --out /tmp/x a,380,260,0,2
var main: Node
var shots: Array = []
var out := "."
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i] == "--out":
			out = a[i + 1]; i += 2; continue
		if not a[i].begins_with("--"):          # (--look=low, --hour=13: the lighting reads those)
			shots.append(a[i].split(","))
		i += 1
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.rig.capture_mouse = false
	main.gothica.process_mode = Node.PROCESS_MODE_DISABLED
	main.player.face_mouse = false
	await get_tree().process_frame
	for s in shots:
		main.player.place(float(s[1]), float(s[2]))
		main.player.facing = Vector2(0, 1)
		main.rig.set_zoom(int(s[4]))
		main.rig.set_mode(int(s[3]))
		if s.size() > 5:
			main.player.look_ang = float(s[5])
			main.player.look_y = float(s[6]) if s.size() > 6 else 0.0
		if s.size() > 7 and float(s[7]) > 0.0:
			main.trampoline.climb_on(main.player)
			main.player.place(float(s[1]), float(s[2]))
			main.player.process_mode = Node.PROCESS_MODE_DISABLED
			main.trampoline.process_mode = Node.PROCESS_MODE_DISABLED
			main.player.dz = float(s[7])
			main.player.global_position.y = float(s[7]) * GameData.UNIT
			main.player.reset_physics_interpolation()
		main.rig.snap()
		for k in 12:
			await get_tree().process_frame
		main.rig.snap()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/" + s[0] + ".png")
		print("shot ", s[0])
	get_tree().quit()
