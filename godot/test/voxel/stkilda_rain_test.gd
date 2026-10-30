extends SceneTree
## St Kilda's rain (VoxelRain): K starts it (as you'd press it); after it's eased in it's falling and splashing, the
## sky's grey, the ground's wet, there are puddles about (filled at once here, not over a minute) and the screen's
## reflections are on; by night too; K again and it eases off. -- --out=dir for pictures (under a display, Forward+).
## Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var out := ""
var fails := []
var day_top := Color.BLACK

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 and step == 0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			var s := sk.arrive_spot()
			sk._put(s[0], float(s[1]), 0.05)
			step = 1
			t = 0.0
		1:
			if t > 1.0:
				_shot("rain_0_dry")
				day_top = ((sk.env.sky.sky_material as ProceduralSkyMaterial).sky_top_color)
				_key(KEY_K)
				step = 2
				t = 0.0
		2:
			if t > VoxelRain.EASE_T + 1.0:
				var r := sk.rain
				_check(r.raining and is_equal_approx(r.w, 1.0), "K: raining, eased right in")
				_check(r._drops.emitting and r._splash.emitting, "falling and splashing")
				_check(r.puddles() >= 30, "puddles put about (%d)" % r.puddles())
				var top := (sk.env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
				_check(top.s < day_top.s * 0.6, "the sky's gone grey")
				_check(SkModels.baked_material().roughness < 0.5, "the ground's wet (glossy)")
				_check(sk.env.ssr_enabled, "the screen's reflections on")
				r.fill = 1.0              # (full now, not in a minute)
				step = 3
				t = 0.0
		3:
			if t > 1.5:
				_shot("rain_1_day")
				# looking down the forecourt at the puddles
				var s := sk.arrive_spot()
				sk._put(s[0], float(s[1]) + PI, -0.12)
				step = 4
				t = 0.0
		4:
			if t > 1.0:
				_shot("rain_2_puddles")
				_key(KEY_N)
				step = 5
				t = 0.0
		5:
			if t > 3.5:
				_shot("rain_3_night")
				# stood behind a puddle out on the forecourt, Mr Moon across it
				var s := sk.arrive_spot()
				var yaw := float(s[1])
				var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
				var mm := sk.rain._puddles.multimesh
				var best := INF
				var at: Vector3 = s[0]
				for i in mm.visible_instance_count:
					var p := mm.get_instance_transform(i).origin
					var ahead := (p - (s[0] as Vector3)).dot(fwd)
					var aside := ((p - (s[0] as Vector3)) - fwd * ahead).length()
					if ahead > -20.0 and ahead < 25.0 and aside + absf(ahead) * 0.1 < best:
						best = aside + absf(ahead) * 0.1
						at = p
				sk._put(Vector3(at.x, 0.05, at.z) - fwd * 5.0, yaw, -0.08)
				step = 6
				t = 0.0
		6:
			if t > 1.0:
				_shot("rain_4_night_moon")
				_key(KEY_K)
				step = 7
				t = 0.0
		7:
			if t > VoxelRain.EASE_T + 0.5:
				var r := sk.rain
				_check(not r.raining and r.w == 0.0, "K again: stopped")
				_check(not r._drops.emitting, "nothing falling")
				_check(SkModels.baked_material().roughness > 0.7, "drying (the gloss gone with the rain)")
				_check(r.fill > 0.5, "the puddles still there, drying slowly")
				r.dry()
				_check(not sk.env.ssr_enabled and sk.env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED, "dry: reflections off again")
				step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
