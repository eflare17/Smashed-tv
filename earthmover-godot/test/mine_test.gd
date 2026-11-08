extends SceneTree
## Checks the mine, with no drawing. Run: godot --headless --path . -s test/mine_test.gd
## The pit, ramp and roads are where they should be; the haul truck takes a full load up the ramp; the big dozer climbs it too; and
## the big excavator can tip a bucket into the haul truck's tray from beside it.

const DT := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	ground_test()
	ramp_test("Haul truck")
	ramp_test("Big dozer")
	load_test()
	DirtSim.set_world(32.0)
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

func _world() -> Array:
	DirtSim.set_world(48.0)
	var ground := GroundData.new(Rect2(), Rect2(), Rect2(), false, true)
	var s := DirtSim.new()
	ground.fill_sim(s)
	return [ground, s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture())]

func ground_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	for spot: Array in [[Vector2(10.0, 6.0), -5.0, "the pit floor"], [Vector2(-7.0, 10.0), -2.5, "the first bench"], [Vector2(-32.0, 0.0), 0.0, "the haul road"], [Vector2(-30.0, -33.0), 0.0, "the parking area"], [Vector2(-17.0, -10.0), GroundData.mine_ramp_level(-17.0), "part way up the ramp"]]:
		var h := s.height_at(spot[0])
		check(absf(h - float(spot[1])) < 0.25, "%s is at %.2f m (%.2f wanted)" % [spot[2], h, spot[1]])
	var windrow := DirtSim.to_m3(s.soil[s.cell_of(Vector2(-23.7, 10.0)).y * DirtSim.CELLS + s.cell_of(Vector2(-23.7, 10.0)).x]) / (DirtSim.CELL_M * DirtSim.CELL_M)
	check(windrow > 0.7, "the road has a windrow of loose dirt along it (%.2f m deep)" % windrow)
	var rim := s.height_at(Vector2(GroundData.MINE_BUND_AT, 0.0))
	check(rim > 1.2, "a bund runs round the edge (%.1f m high)" % rim)

## From the bottom of the ramp to the top, held to the middle of it.
func ramp_test(which: String) -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var m: Machine
	if which == "Haul truck":
		var t := Truck.new()
		t.haul = true
		m = t
	else:
		m = Dozer.new()
		m.make_big(1.9)
	root.add_child(m)
	m.setup(s, w[2], StandardMaterial3D.new(), Vector2(13.0, GroundData.MINE_RAMP_Z), Vector2(-1.0, 0.0))
	var total := s.total()
	if m is Truck:
		var t := m as Truck
		t.tray_mm = t.capacity
		s.held += t.capacity
		total = s.total()
	m.throttle = 1.0
	var lowest_speed := INF
	var start_y := m.position.y
	var stuck_for := 0.0
	for k in int(40.0 / DT):
		var off := m.spot.y - GroundData.MINE_RAMP_Z
		var turned := wrapf(m.angle - PI, -PI, PI)
		m.steer = clampf(off * 0.35 + turned * 2.5, -1.0, 1.0)
		m.step(DT)
		s.step(DT, 1000000)
		if k > 300:
			lowest_speed = minf(lowest_speed, absf(m.speed))
			stuck_for = stuck_for + DT if absf(m.speed) < 0.3 else 0.0
		if m.spot.x < -30.0 or stuck_for > 3.0:
			break
	print("      %s: got to x %.1f, z %.1f, climbed %.1f m, slowest %.1f m/s" % [m.machine_name, m.spot.x, m.spot.y, m.position.y - start_y, lowest_speed])
	check(m.spot.x < -27.0, "%s gets to the top of the ramp%s" % [which, " full" if m is Truck else ""])
	check(m.position.y - start_y > 4.0, "%s climbs the 5 m out of the pit" % which)
	check(absf(m.spot.y - GroundData.MINE_RAMP_Z) < 3.0, "%s stays on the ramp" % which)
	check(s.total() == total, "%s: no soil lost" % which)
	m.queue_free()

## A full bucket swung out over the haul truck's tray and tipped: it lands in the tray.
func load_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var e := Excavator.new()
	e.make_big(1.9)
	root.add_child(e)
	e.setup(s, w[2], StandardMaterial3D.new(), Vector2(10.0, 4.0), Vector2(1.0, 0.0))
	var t := Truck.new()
	t.haul = true
	root.add_child(t)
	# Parked alongside, the tray's middle 11 m off to the excavator's left.
	t.setup(s, w[2], StandardMaterial3D.new(), Vector2(10.0 + 1.35, 15.0), Vector2(1.0, 0.0))
	e.bucket_mm = e.capacity()
	s.held += e.bucket_mm
	var total := s.total()
	e.swing = -PI * 0.5
	e.wrist = Vector2(11.0 / 1.9, 4.8)
	e.curl = Excavator.CURL_MAX
	for k in 30:
		e.step(DT)
		t.step(DT)
		s.step(DT, 1000000)
	var rim := t.tray_rim()
	print("      bucket's teeth at %.1f m up, the tray's rim at %.1f m, over the tray: %s" % [e.teeth.y, rim, t.over_tray(e.teeth)])
	check(e.teeth.y > rim, "the big excavator's bucket clears the haul truck's rim")
	var had := e.bucket_mm
	e.curl_cmd = -1.0
	for k in int(5.0 / DT):
		e.step(DT)
		t.step(DT)
		s.step(DT, 1000000)
	e.curl_cmd = 0.0
	for k in int(3.0 / DT):
		e.step(DT)
		t.step(DT)
		s.step(DT, 1000000)
	print("      tipped %.2f m3, the tray has %.2f m3, %.2f m3 on the ground" % [DirtSim.to_m3(had - e.bucket_mm), DirtSim.to_m3(t.tray_mm), DirtSim.to_m3(s.loose_total())])
	check(t.tray_mm > had * 0.9, "a bucket tipped over the tray lands in it (%.1f of %.1f m3)" % [DirtSim.to_m3(t.tray_mm), DirtSim.to_m3(had)])
	check(s.total() == total, "loading: no soil lost")
	check(float(t.capacity) / had >= 2.3 and float(t.capacity) / had <= 3.5, "it takes about three full buckets to fill (%.1f)" % (float(t.capacity) / had))
