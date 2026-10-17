extends Node
## Headless test of the install inside the real game (scenes/look/install_test.tscn):
##   godot --headless --path godot res://scenes/look/install_test.tscn
## Prints PASS/FAIL lines, then quits with the number of failures.

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var li := LightingInstall.install(main)
	await frames(2)
	var clock := get_node_or_null("/root/GameClock")
	check(clock != null, "the GameClock is at /root/GameClock")
	check(li.get_parent() == main and li.day_night and li.look and li.clock_hud and li.bed, "installed under main: DayNight, LookPass, ClockHud, BedSleep")

	# the world's materials are lit ones; the characters lit and casting
	var unlit := 0
	for mi in main.world.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(i)
			if m == null:
				m = mi.material_override if mi.material_override else mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				unlit += 1
	check(unlit == 0, "no unshaded StandardMaterial3D left in the World (%d)" % unlit)
	check(main.player.sprite.get_node_or_null("SunShadow") != null, "the player has a sun shadow caster")
	check(main.gothica.sprite.get_node_or_null("SunShadow") != null, "Gothica has a sun shadow caster")
	check(main.world.find_children("HouseShadow", "", true, false).size() == 1, "the house's shadow caster (no roof)")

	# the cycle
	clock.load_state({"day": 1, "hour": 12.0})
	await frames(1)
	var dn: DayNight = li.day_night
	var sun: DirectionalLight3D = main.sun
	check(sun.visible and sun.light_energy > 0.3, "noon: the sun is out (%.2f)" % sun.light_energy)
	check((sun.global_basis.z).y > 0.6 and sun.global_basis.z.z < 0.0, "noon: the sun is high in the north")
	var lit_lamps := dn.lamps.filter(func(l): return l.light.visible).size()
	check(lit_lamps == 0, "noon: the lamps are off")
	clock.load_state({"day": 1, "hour": 6.6})
	await frames(1)
	check(sun.global_basis.z.x > 0.3, "morning: the sun's in the east")
	clock.load_state({"day": 1, "hour": 18.5})
	await frames(1)
	check(sun.global_basis.z.x < -0.3, "evening: the sun's in the west")
	clock.load_state({"day": 1, "hour": 23.0})
	await frames(1)
	lit_lamps = dn.lamps.filter(func(l): return l.light.visible).size()
	check(lit_lamps >= 6, "11 pm: the lamps are on (%d)" % lit_lamps)
	check(clock.is_night() and dn.look.stars > 0.9, "11 pm: night, stars out")
	check(sun.light_energy < 0.3 and sun.light_color.b > sun.light_color.r, "11 pm: the light is the moon's, dim and blue")
	var env: Environment = main.world.environment
	check(env.ambient_light_color.v < 0.4, "11 pm: dark ambient (%.2f)" % env.ambient_light_color.v)
	check(not dn.look_for(23.0).is_empty() and dn.look_for(19.0).lamps > 0.3, "the lamps come on at dusk")

	# the quality switch
	li.look.set_quality("low")
	await frames(1)
	check(not sun.shadow_enabled and dn.lamps.filter(func(l): return l.light.visible).size() == 0, "low: no shadows, no real lamps")
	li.look.set_quality("high")
	await frames(1)
	check(sun.shadow_enabled, "high: shadows")

	# the bed: stand beside it, E says SLEEP, sleeping goes to 7 am tomorrow
	clock.load_state({"day": 1, "hour": 22.0})
	main.player.place(380, 700)
	await frames(5)
	check(main.player.focus_label == "SLEEP", "beside the bed E says SLEEP (got '%s')" % main.player.focus_label)
	var days := []
	clock.day_started.connect(func(d): days.append(d))
	await li.bed.sleep(main.player)
	check(clock.day == 2 and clock.hour >= 7.0 and clock.hour < 7.1, "slept: 7 am day 2 (it ticks on during the fade back in) (%d %s)" % [clock.day, clock.time_text()])
	check(days == [2], "day_started(2) fired once")
	check(main.player.controls_enabled, "the player can move again")
	# the save
	var f := FileAccess.open(LightingInstall.SAVE_PATH, FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text()) if f else null
	check(v is Dictionary and int(v.day) == 2, "the save has day 2")
	# the lobby's bed: a sleep_requested signal takes over
	var lobby_bed := _FakeBed.new()
	main.add_child(lobby_bed)
	await frames(1)
	lobby_bed.sleep_requested.emit(main.player)
	await get_tree().create_timer(3.5).timeout
	check(clock.day == 3, "the lobby bed's sleep_requested sleeps too (day %d)" % clock.day)
	check(not li.bed.is_in_group("interactable"), "and the stand-in bed steps aside")
	print("install_test: %d failed" % fails)
	get_tree().quit(fails)

class _FakeBed extends Interactable:
	signal sleep_requested(player: Node)
