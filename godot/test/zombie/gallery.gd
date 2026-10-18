extends Node3D
## The zombie's moves side by side, saved as a picture (not part of the game).
## xvfb-run godot --path . res://test/zombie/gallery.tscn -- --out DIR [--low] [--night] [--side]
var out := "."
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out":
			out = a[i + 1]
	var low := "--low" in a
	var night := "--night" in a
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.07, 0.12) if night else Color(0.55, 0.7, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#3c4470") if night else Color("#acaeb6")
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.22 if night else 0.9
	sun.light_color = Color("#8ca6ff") if night else Color("#fff6e6")
	sun.shadow_enabled = true
	add_child(sun)
	if night:
		var o := OmniLight3D.new()
		o.position = Vector3(2.5, 2.6, 2.0)
		o.omni_range = 7.0
		o.light_energy = 2.0
		o.light_color = Color(1.0, 0.8, 0.6)
		add_child(o)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gm
	add_child(ground)
	LookPass.register_globals()
	var tint := Vector3(0.45, 0.5, 0.75) if night else Vector3(1.0, 1.0, 1.0)
	RenderingServer.global_shader_parameter_set("look_tint", tint)
	var moves := [["idle", 0.2], ["walk", 0.1], ["walk", 0.35], ["walk", 0.6], ["run", 0.3], ["attack", 0.3], ["attack", 0.55], ["hit", 0.2], ["scream", 0.5], ["rise", 0.45], ["death", 0.3], ["death", 1.0]]
	for x in a:
		if x.begins_with("--only="):
			var keep := []
			for k in x.trim_prefix("--only=").split(","):
				keep.append(moves[int(k)])
			moves = keep
	var zs := []
	for i in moves.size():
		var z := ZombieModel.new(0.2 + 0.6 * float(i % 2))
		z.position = Vector3((i - moves.size() / 2.0) * 1.25, 0, 0)
		if "--side" in a:
			z.rotation_degrees.y = 70
		add_child(z)
		z.set_quality("low" if low else "high")
		z.set_glow(1.0 if night else 0.0)
		zs.append(z)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 1.6 + moves.size() * 1.05)
	cam.rotation_degrees.x = -4
	cam.fov = 60
	add_child(cam)
	cam.current = true
	for f in 3:
		for i in moves.size():
			var m: String = moves[i][0]
			var u: float = moves[i][1]
			if m == "hit":
				zs[i].anim.apply("walk", 0.3, 1.0, u)
			else:
				zs[i].anim.apply(m, u, 1.0)
			if m == "rise":
				zs[i].position.y = -ZombieAnim.rise_depth(u)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/gallery.png")
	print("saved")
	get_tree().quit()
