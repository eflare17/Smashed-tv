extends Node
## Clock checks on the real game (not part of it). Run headless:
##   godot --headless --fixed-fps N res://test/main/clock_test.tscn -- roll      one roll from rest at N fps: how
##       long and how far (the HTML game: 0.42 s, about 135 units), then the stopping distance from full speed
##   godot --headless --max-fps 144 res://test/main/clock_test.tscn -- judder   frames where Gothica (walking) or
##       the player (bouncing) are drawn where they were the frame before
var main: Node
var mode := "roll"
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		mode = a[0]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.rig.capture_mouse = false
	main.player.face_mouse = false
	await get_tree().process_frame
	if mode == "roll":
		await _roll()
	else:
		await _judder()
	get_tree().quit()

func _roll() -> void:
	var p: Player = main.player
	p.place(1000, 1200)                       # open yard
	p.facing = Vector2(1, 0)
	for k in 5:
		await get_tree().process_frame
	var x0 := p.html_pos().x
	var t0 := Time.get_ticks_usec()
	var frames := 0
	Input.action_press("roll")
	await get_tree().process_frame
	Input.action_release("roll")
	var started := false
	var sim_t := 0.0
	while frames < 400:
		await get_tree().physics_frame
		sim_t += get_physics_process_delta_time()
		frames += 1
		if p.roll > 0.0:
			started = true
		if started and p.roll <= 0.0 and p.vel.length() < 0.01:
			break
		if started and p.roll <= 0.0:
			break
	print("TEST roll fps=%d: %.3f s, %.1f units (roll_t left %.3f)" % [Engine.max_fps if Engine.max_fps > 0 else 0, sim_t, p.html_pos().x - x0, p.roll])
	# full speed then let go: stopping distance
	p.place(1000, 1200)
	p.halt()
	await get_tree().physics_frame
	Input.action_press("move_right")
	var tt := 0.0
	while tt < 1.0:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
	Input.action_release("move_right")
	var xs := p.html_pos().x
	var ts := 0.0
	while p.vel.length() > 0.01 and ts < 2.0:
		await get_tree().physics_frame
		ts += get_physics_process_delta_time()
	print("TEST stop: %.3f s, %.1f units (speed was capped at maxSpeed)" % [ts, p.html_pos().x - xs])

func _judder() -> void:
	var g: Gothica = main.gothica
	var p: Player = main.player
	# Gothica walking: count drawn frames where she hasn't moved while moving
	g.place(200, 360)
	g.wait = 0.0
	g.target = Vector2(560, 380)
	var frozen := 0
	var walking := 0
	var last := g.get_global_transform_interpolated().origin
	for k in 500:
		await get_tree().process_frame
		var now := g.get_global_transform_interpolated().origin
		if g.moving:
			walking += 1
			if now.distance_to(last) < 1e-6:
				frozen += 1
		last = now
	print("TEST judder gothica: frozen %d of %d walking frames, fps %d" % [frozen, walking, Engine.get_frames_per_second()])
	# the player bouncing
	main.trampoline.climb_on(p)
	frozen = 0
	var n := 0
	var lz := p.visual_pos().z
	for k in 500:
		await get_tree().process_frame
		var z := p.visual_pos().z
		n += 1
		if absf(z - lz) < 1e-6:
			frozen += 1
		lz = z
	print("TEST judder bounce: dz frozen %d of %d frames" % [frozen, n])
