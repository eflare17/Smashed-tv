extends Node
## Draw calls and objects per frame in the lounge (not part of the game). Run in a window (xvfb-run):
## godot --path . res://test/main/perf.tscn   [-- touch]   (touch: with the touch controls showing)
var main: Node
func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.rig.capture_mouse = false
	main.player.face_mouse = false
	if "touch" in OS.get_cmdline_user_args():
		main.hud.touch._set_active(true)
	for k in 30:
		await get_tree().process_frame
	for label in ["with HUD", "HUD hidden"]:
		if label == "HUD hidden":
			main.hud.visible = false
			for c in main.hud.get_children():
				c.visible = false
		for k in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		print("TEST draw calls (%s): %d, objects %d, fps %d" % [label,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			Engine.get_frames_per_second()])
	get_tree().quit()
