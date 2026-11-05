extends SceneTree
## Checks the side-on bucket picture tells the truth, with no drawing. Run: godot --headless --path . -s test/bucket_view_test.gd

var fails := 0

## Lines up on a truck by doing what the picture's words say, with the real controls, then tips the load and looks in the tray.
func truck_tests(s: DirtSim, view: GroundView, mat: Material) -> void:
	var d := Excavator.new()
	root.add_child(d)
	d.setup(s, view, mat, Vector2(-10.0, -12.0), Vector2(1.0, 0.0))
	var t := Truck.new()
	root.add_child(t)
	t.setup(s, view, mat, d.spot + Vector2(5.5, 4.5), Vector2(1.0, 0.0))
	var b := BucketView.new()
	b.machine = d
	b.truck = t
	root.add_child(b)
	var word := func() -> String:
		return b._truck_word(d.side_view()).get("word", "")
	t.step(1.0 / 60.0)
	d.step(1.0 / 60.0)
	d.swing = 0.0
	d._solve(Vector2(6.0, 4.6))
	d.curl = 2.9
	d._pose()
	print("      to start: " + word.call())
	check(String(word.call()).begins_with("SWING RIGHT"), "the truck's on the right of the arm: it says swing right")
	# Thumb to the right, as a player would, for as long as it says swing.
	var ticks := 0
	while String(word.call()).begins_with("SWING") and ticks < 900:
		d.swing_cmd = 1.0 if String(word.call()).contains("RIGHT") else -1.0
		t.step(1.0 / 60.0)
		d.step(1.0 / 60.0)
		ticks += 1
	d.swing_cmd = 0.0
	print("      after swinging for %.1f s: %s" % [ticks / 60.0, word.call()])
	check(not String(word.call()).begins_with("SWING"), "swinging the way it says gets the arm lined up")
	ticks = 0
	while not String(word.call()).begins_with("OVER") and ticks < 600:
		d.reach_cmd = 1.0 if String(word.call()).begins_with("REACH OUT") else (-1.0 if String(word.call()).begins_with("REACH IN") else 0.0)
		d.swing_cmd = 0.0
		d.step(1.0 / 60.0)
		ticks += 1
	d.reach_cmd = 0.0
	print("      after reaching: " + word.call())
	check(String(word.call()).begins_with("OVER THE TRUCK"), "reaching the way it says gets it over the tray")
	d.raise_cmd = 1.0
	while String(word.call()).ends_with("RAISE") and ticks < 1200:
		d.step(1.0 / 60.0)
		ticks += 1
	d.raise_cmd = 0.0
	d.bucket_mm = 9000
	s.held += 9000
	check(word.call() == "OVER THE TRUCK: DUMP", "with a load, it says to dump")
	var total := s.total()
	d.curl_cmd = -1.0
	ticks = 0
	while d.bucket_mm > 0 and ticks < 300:
		d.step(1.0 / 60.0)
		s.step(1.0 / 60.0)
		ticks += 1
	d.curl_cmd = 0.0
	for k in 180:
		s.step(1.0 / 60.0)
	print("      dumped: %.2f m3 of %.2f in the tray" % [DirtSim.to_m3(t.tray_mm), DirtSim.to_m3(9000)])
	check(t.tray_mm >= 8000, "and the load lands in the tray")
	check(s.total() == total, "total unchanged")
	t.spot = d.spot + Vector2(40.0, 0.0)
	check(word.call() == "", "a truck far off isn't mentioned")

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var s := DirtSim.new()
	var ground := GroundData.new()
	var view := GroundView.new(ground, s, ground.height_texture(), ground.data_texture())
	var mat := StandardMaterial3D.new()

	var d := Excavator.new()
	root.add_child(d)
	d.setup(s, view, mat, Vector2.ZERO, Vector2(1.0, 0.0))
	d.swing = 0.7
	d.curl = 1.4
	var v := d.side_view()
	var tip: Vector2 = v["pin"] + Vector2(v["reach"], 0.0).rotated(v["turn"])
	var real: Vector3 = d._teeth_local()
	check(tip.distance_to(Vector2(real.x, real.y)) < 0.001, "excavator: the picture's teeth are where the real teeth are")
	check(absf(float(v["angle"]) - rad_to_deg(1.4)) < 0.01, "excavator: the angle is its real curl")
	var at: Vector3 = d._teeth_now()
	check(absf(float(v["down"]) - (s.height_at(Vector2(at.x, at.z)) - at.y)) < 0.001, "excavator: how far up is measured from the ground under the teeth")
	d.bucket_mm = Excavator.CAPACITY
	d.curl = Excavator.CURL_MAX
	check(not d.side_view()["pours"], "excavator: curled in, full, it holds")
	d.curl = Excavator.CURL_EMPTY
	check(d.side_view()["pours"], "excavator: tipped out, full, it pours")
	d.bucket_mm = 0
	check(not d.side_view()["pours"], "excavator: empty, nothing pours")

	for which: String in [Loader.BOBCAT, Loader.DINGO]:
		var m := Loader.new()
		root.add_child(m)
		m.setup(s, view, mat, Vector2.ZERO, Vector2(1.0, 0.0), which)
		m.arm = 0.3
		m.curl = 0.4
		var lv := m.side_view()
		var edge: Vector2 = lv["pin"] + Vector2(lv["reach"], 0.0).rotated(lv["turn"])
		var true_edge := m._edge_local()
		check(edge.distance_to(Vector2(true_edge.x, true_edge.y)) < 0.001, which + ": the picture's edge is where the real edge is")
		m.bucket_mm = m.capacity
		check(not m.side_view()["pours"], which + ": tipped back, full, it holds")
		m.curl = Loader.POUR_ALL
		check(m.side_view()["pours"], which + ": tipped forward, full, it pours")
		if which == Loader.DINGO:
			m.bucket_mm = 0
			m.curl = 0.25
			m.toggle_attachment()
			check(m.side_view().is_empty(), "Dingo: with the trencher on there's no bucket to show")

	var z := Dozer.new()
	root.add_child(z)
	z.setup(s, view, mat, Vector2.ZERO, Vector2(1.0, 0.0))
	var made := z.side_view()
	z.lift = 0.8
	z.step(1.0 / 60.0)
	check(not made.is_empty() and z.side_view()["down"] < -0.1, "the dozer's picture: raised, the blade reads as up")
	check(absf(float(z.side_view()["down"]) + z.edge_gap) < 0.001, "the dozer's picture: its height is the blade gauge's")
	z.lift_cmd = 0.0
	z.queue_free()
	truck_tests(s, view, mat)
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
