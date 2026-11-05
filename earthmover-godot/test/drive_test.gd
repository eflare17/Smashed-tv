extends SceneTree
## Checks the bulldozer against the dirt, with no drawing. Run: godot --headless --path . -s test/drive_test.gd
## These test how it behaves, not whether it feels good: only driving it can tell that.

const DT := 1.0 / 60.0
var fails := 0
var ground := GroundData.new()

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func new_dozer(s: DirtSim, at: Vector2, dir: Vector2) -> Dozer:
	var view := GroundView.new(ground, s, ground.height_texture(), ground.data_texture())
	var d := Dozer.new()
	root.add_child(d)
	d.setup(s, view, StandardMaterial3D.new(), at, dir)
	return d

func run(s: DirtSim, d: Dozer, seconds: float, throttle: float, steer := 0.0, lift_cmd := 0.0) -> bool:
	d.throttle = throttle
	d.steer = steer
	d.lift_cmd = lift_cmd
	var start := s.total()
	var same := true
	for t in int(seconds / DT):
		d.step(DT)
		s.step(DT, 1000000)
		if s.total() != start:
			same = false
	return same

func _init() -> void:
	# Flat firm ground, blade up: it just drives, at its top speed, and moves nothing.
	var a := DirtSim.new()
	var d := new_dozer(a, Vector2(-20, 0), Vector2(1, 0))
	run(a, d, 0.5, 0.0, 0.0, 1.0)
	run(a, d, 6.0, 1.0)
	check(d.speed > Dozer.TOP_SPEED * 0.9, "blade up on flat ground, it reaches top speed (%.1f m/s)" % d.speed)
	check(d.moved_m3 == 0.0, "and moves no soil")
	var x := d.spot.x
	check(x > -7.0, "it covered the ground (from -20 to %.1f)" % x)
	run(a, d, 3.0, -1.0)
	check(d.spot.x < x, "it reverses")
	var turned := d.angle
	run(a, d, 2.0, 0.0, 1.0)
	check(absf(d.angle - turned) > 1.0, "it turns on the spot (%.1f rad)" % absf(d.angle - turned))

	# A layer of loose soil: it pushes along a growing load, leaves scraped ground, and slows as the load builds.
	var b := DirtSim.new()
	for j in range(100, 158):
		for i in range(30, 230):
			b.soil[j * DirtSim.CELLS + i] = 220
	var e := new_dozer(b, Vector2(-22, 0), Vector2(1, 0))
	e.lift = -0.14
	run(b, e, 0.6, 1.0)
	var quick := e.speed
	var same := run(b, e, 10.0, 1.0)
	check(same, "pushing through 0.22 m of soil for 10 s: the total never changes")
	check(e.moved_m3 > 3.0, "it moved soil (%.0f m3 handled)" % e.moved_m3)
	check(e.load_t > 2.0, "a load builds against the blade (%.1f t)" % e.load_t)
	# On average along the cleared stretch: the machine's nose bobs under load, so the scraped ground is rippled.
	var behind := 0.0
	var samples := 0
	var along_x := -19.0
	while along_x < e.spot.x - 2.0:
		behind += b.height_at(Vector2(along_x, 0.0))
		samples += 1
		along_x += 0.25
	behind /= maxi(samples, 1)
	check(samples > 4 and behind < 0.15, "it scrapes the 0.22 m layer down as it goes (%.2f m left on average)" % behind)
	check(e.spot.x > -19.0, "it made headway (at %.1f after 10.6 s, was going %.1f m/s early on)" % [e.spot.x, quick])
	print("      speed %.2f m/s under %.1f t" % [e.speed, e.load_t])

	# A wall of soil too big to shift: it stops, the tracks slip, and it can back away.
	var c := DirtSim.new()
	for j in range(90, 168):
		for i in range(150, 200):
			c.soil[j * DirtSim.CELLS + i] = 3200
	var f := new_dozer(c, Vector2(0, 0), Vector2(1, 0))
	f.lift = 0.0
	var same_c := run(c, f, 12.0, 1.0)
	check(same_c, "shoving a huge wall of soil: the total never changes")
	check(f.speed < 0.5, "a load too big stops it (%.2f m/s under %.1f t)" % [f.speed, f.load_t])
	check(f.slipping, "and the tracks slip")
	var stuck_x := f.spot.x
	run(c, f, 3.0, -1.0)
	check(f.spot.x < stuck_x - 1.0, "it can back away (%.1f to %.1f)" % [stuck_x, f.spot.x])

	# Rock stops the blade dead, but not with it raised.
	var g := DirtSim.new()
	for j in 257:
		for i in range(140, 200):
			g.bed[j * DirtSim.CELLS + i] = 400
			g.rock[j * DirtSim.CELLS + i] = 1
	var h := new_dozer(g, Vector2(-6, 0), Vector2(1, 0))
	h.lift = 0.0
	run(g, h, 6.0, 1.0)
	check(h.on_rock and h.speed < 0.3, "a rock ledge stops the blade (%.2f m/s at x %.1f)" % [h.speed, h.spot.x])

	# The very first thing a player does: push the stick, touching nothing else. It has to go, and even a timid push counts.
	var first := DirtSim.new()
	ground.fill_sim(first)
	var n := new_dozer(first, GroundData.dozer_spot(), GroundData.dozer_dir())
	run(first, n, 4.0, 1.0)
	check(n.spot.distance_to(GroundData.dozer_spot()) > 10.0, "the first push of the stick drives it: 4 s went %.1f m" % n.spot.distance_to(GroundData.dozer_spot()))
	var timid := DirtSim.new()
	ground.fill_sim(timid)
	var o := new_dozer(timid, GroundData.dozer_spot(), GroundData.dozer_dir())
	run(timid, o, 4.0, 0.25)
	check(o.spot.distance_to(GroundData.dozer_spot()) > 4.0, "so does a quarter push: 4 s went %.1f m" % o.spot.distance_to(GroundData.dozer_spot()))

	# The real scene: blade lowered, straight on at full throttle to the pile.
	var real := DirtSim.new()
	ground.fill_sim(real)
	var m := new_dozer(real, GroundData.dozer_spot(), GroundData.dozer_dir())
	var from := m.spot
	m.lift = 0.0
	var same_real := run(real, m, 8.0, 1.0)
	print("      real scene after 8 s: went %.1f m, %.2f m/s, load %.1f t, slipping %s, moved %.0f m3" % [m.spot.distance_to(from), m.speed, m.load_t, m.slipping, m.moved_m3])
	check(same_real, "the real scene: the total never changes")
	check(m.spot.distance_to(from) > 1.5, "it gets moving in the real scene (%.1f m)" % m.spot.distance_to(from))
	var reach := m.spot.distance_to(GroundData.PILE)
	run(real, m, 8.0, 1.0)
	var to_pile := m.spot.distance_to(GroundData.PILE)
	print("      after 16 s: %.1f m from the pile middle, %.2f m/s, load %.1f t, slipping %s, moved %.0f m3" % [to_pile, m.speed, m.load_t, m.slipping, m.moved_m3])
	check((m.spot - GroundData.PILE).dot(GroundData.dozer_dir()) < 0.0, "it can't just drive through the big pile: 16 s of full throttle and it hasn't passed the middle")
	check(reach >= 0.0 and m.moved_m3 > 3.0, "it shoved soil getting there (%.0f m3)" % m.moved_m3)
	# Stuck against it, raising the blade should let it ride up and get moving again.
	var stuck_at := m.spot
	run(real, m, 2.5, 1.0, 0.0, 1.0)
	run(real, m, 4.0, 1.0)
	print("      blade raised: went %.1f m further, %.2f m/s, lift %.2f, load %.1f t" % [m.spot.distance_to(stuck_at), m.speed, m.lift, m.load_t])
	check(m.spot.distance_to(stuck_at) > 0.5, "raising the blade frees it")
	var before_back := m.spot
	run(real, m, 3.0, -1.0)
	check(m.spot.distance_to(before_back) > 2.0, "and it can always back off (%.1f m)" % m.spot.distance_to(before_back))


	# LEVEL: full throttle at the big pile, there and back, several times. It should hardly ever stop, and bring the top down.
	var lv := DirtSim.new()
	ground.fill_sim(lv)
	var q := new_dozer(lv, GroundData.dozer_spot(), GroundData.dozer_dir())
	var lv_total := lv.total()
	var top0 := lv.height_at(GroundData.PILE)
	q.set_level(true)
	var q_dir := GroundData.dozer_dir()
	var worst_stop := 0
	for trip in 3:
		q.throttle = 1.0
		var ticks := 0
		var stop_run := 0
		while ticks < 2400 and (q.spot - GroundData.PILE).dot(q_dir) < 9.0:
			q.step(DT)
			lv.step(DT, 1000000)
			ticks += 1
			stop_run = stop_run + 1 if q.speed < 0.1 else 0
			worst_stop = maxi(worst_stop, stop_run)
		q.throttle = -1.0
		for back in 540:
			q.step(DT)
			lv.step(DT, 1000000)
	check(worst_stop * DT < 2.0, "LEVEL keeps it moving over the pile (longest stop %.1f s)" % (worst_stop * DT))
	check(lv.height_at(GroundData.PILE) < top0 - 0.5, "LEVEL brings the pile down (%.1f to %.1f m)" % [top0, lv.height_at(GroundData.PILE)])
	check(lv.total() == lv_total, "LEVEL: the total never changes")

	# The glitch from the owner's screenshot: full throttle into the edge of the site. It must stop, and soil must stay off the rim.
	var ed := DirtSim.new()
	ground.fill_sim(ed)
	var ee := new_dozer(ed, Vector2(10.0, 20.0), Vector2(0.0, 1.0))
	ee.lift = -0.1
	var ed_total := ed.total()
	var ed_moved := 0.0
	for tick_no in 900:
		ee.throttle = 1.0
		ee.step(DT)
		ed.step(DT, 1000000)
		if tick_no == 600:
			ed_moved = ee.moved_m3
	check(ee.at_edge and absf(ee.speed) < 0.01, "at the edge of the site it stops (%.2f m/s)" % ee.speed)
	check(ee.moved_m3 - ed_moved < 1.0, "and stops moving soil there (%.1f m3 in the last 5 s)" % (ee.moved_m3 - ed_moved))
	var rim_soil := 0
	for j in DirtSim.CELLS:
		for i in DirtSim.CELLS:
			if i < DirtSim.RIM or j < DirtSim.RIM or i >= DirtSim.CELLS - DirtSim.RIM or j >= DirtSim.CELLS - DirtSim.RIM:
				rim_soil += ed.soil[j * DirtSim.CELLS + i]
	check(rim_soil == 0, "no soil reaches the rim (%d mm)" % rim_soil)
	check(ed.total() == ed_total, "the edge: the total never changes")

	# Trees: drive at one and it goes over, slowly then down, the machine feels it, and the blade shoves it afterwards.
	var ts := DirtSim.new()
	var td := new_dozer(ts, Vector2(-20.0, 0.0), Vector2(1.0, 0.0))
	td.lift = 0.5
	var tr := Trees.new()
	root.add_child(tr)
	var spots: Array[Vector2] = [Vector2(-10.0, 0.5), Vector2(-20.0, 15.0)]
	var trng := RandomNumberGenerator.new()
	trng.seed = 1
	tr.setup(ts, StandardMaterial3D.new(), spots, trng)
	var knocks := [0, 0]
	tr.knocked.connect(func(_at: Vector3) -> void: knocks[0] += 1)
	tr.landed.connect(func(_at: Vector3) -> void: knocks[1] += 1)
	var felled: Trees.Pine = tr.list[0]
	var base_was := felled.base
	var fall_ticks := 0
	var slowed := false
	td.throttle = 1.0
	for tick_no in 900:
		var before := td.speed
		td.step(DT)
		tr.update(DT, td)
		if felled.state != Trees.STANDING and fall_ticks == 0:
			slowed = td.speed < before
		if felled.state == Trees.FALLING:
			fall_ticks += 1
		if tick_no == 100:
			check(felled.state == Trees.STANDING, "a tree stands until it's reached")
	check(knocks[0] == 1 and knocks[1] == 1, "it hits one tree: knocked %d, landed %d" % knocks)
	check(felled.state == Trees.DOWN and tr.down == 1, "it ends up lying down (%d down)" % tr.down)
	check(fall_ticks * DT > 0.7 and fall_ticks * DT < 4.0, "it takes a believable time to fall (%.1f s)" % (fall_ticks * DT))
	check(slowed, "the machine feels the hit")
	check(felled.base.distance_to(base_was) > 2.0, "the blade shoves the tree along (%.1f m)" % felled.base.distance_to(base_was))
	check(tr.list[1].state == Trees.STANDING, "the tree it never touched still stands")

	# The sounds are made in code: they have to exist, have something in them, and not clip.
	var sx := Sfx.new()
	for pair: Array in [["diesel", sx.diesel()], ["scraping", sx.scraping()], ["crack", sx.crack_sound()], ["thud", sx.thud_sound()], ["rustle", sx.rustle_sound()]]:
		var peak := 0.0
		for v: float in pair[1]:
			peak = maxf(peak, absf(v))
		check(peak > 0.1 and peak <= 1.05, "sound %s has a sensible level (peak %.2f)" % [pair[0], peak])
	sx.free()

	# The owner's screenshot: the machine sinking out of sight in a pile. At every moment of driving over it, with and without
	# LEVEL, its tracks must stay close to the surface under them.
	for use_level: bool in [false, true]:
		var sk := DirtSim.new()
		ground.fill_sim(sk)
		var sd := new_dozer(sk, GroundData.dozer_spot(), GroundData.dozer_dir())
		sd.set_level(use_level)
		sd.throttle = 1.0
		var deepest := 0.0
		var highest := -9.0
		for tick_no in 1500:
			sd.step(DT)
			sk.step(DT, 1000000)
			deepest = maxf(deepest, sk.height_at(sd.spot) - sd.y_smooth)
			highest = maxf(highest, sd.y_smooth)
		check(deepest < 0.45, "LEVEL %s: it never sinks into the pile (deepest %.2f m, got up to %.2f m)" % [use_level, deepest, highest])

	# What LEVEL is for: three runs along one line. Each goes straight through. The pile's sides slump into the cut, so it takes a few, and then the line is stripped down to the firm ground.
	var fl := DirtSim.new()
	ground.fill_sim(fl)
	var fd := new_dozer(fl, GroundData.dozer_spot(), GroundData.dozer_dir())
	var fl_total := fl.total()
	fd.set_level(true)
	var fl_stop := 0
	var fl_worst := 0
	for fl_run in 3:
		fd.throttle = 1.0
		fd.at_edge = false
		var fl_run_ticks := 0
		while fl_run_ticks < 1500 and not fd.at_edge:
			fd.step(DT)
			fl.step(DT, 1000000)
			fl_run_ticks += 1
			fl_stop = fl_stop + 1 if fd.speed < 0.1 and not fd.at_edge else 0
			fl_worst = maxi(fl_worst, fl_stop)
		fd.spot = GroundData.dozer_spot()
		fd.angle = atan2(-GroundData.dozer_dir().y, GroundData.dozer_dir().x)
		fd.speed = 0.0
	for settle in 300:
		fl.step(DT, 1000000)
	check(fl_worst * DT < 0.5, "a LEVEL run goes through the pile without stopping (longest stop %.1f s)" % (fl_worst * DT))
	var fl_dir := GroundData.dozer_dir()
	var left_on_path := 0.0
	var fl_samples := 0
	for k in range(-6, 7):
		var at := GroundData.PILE + fl_dir * float(k)
		left_on_path += fl.height_at(at) - fl.firm_at(at)
		fl_samples += 1
	check(left_on_path / fl_samples < 0.4, "three runs take its path most of the way down: the sides slump back in, so it needs runs beside it too (%.2f m of soil left on average)" % (left_on_path / fl_samples))
	check(fl.total() == fl_total, "the LEVEL run: the total never changes")

	# The owner's screenshot: soil stacking into a tower ahead of the blade (it had reached 9.75 m). Through the pile it must never
	# stand higher than the pile did, and after that the windrows should stay low.
	var tw := DirtSim.new()
	ground.fill_sim(tw)
	var pile_top := tw.height_at(GroundData.PILE) - tw.firm_at(GroundData.PILE)
	var tw_d := new_dozer(tw, GroundData.dozer_spot(), GroundData.dozer_dir())
	var tw_total := tw.total()
	tw_d.set_level(true)
	tw_d.throttle = 1.0
	var tw_tallest := 0.0
	var tw_ticks := 0
	while tw_ticks < 1500 and not tw_d.at_edge:
		tw_d.step(DT)
		tw.step(DT, 4000)
		tw_ticks += 1
		var tw_mid := (tw_d.blade_a + tw_d.blade_b) * 0.5
		for tw_reach: float in [0.3, 0.6, 1.0, 1.5, 2.0]:
			var tw_at := tw_mid + tw_d.forward() * tw_reach
			tw_tallest = maxf(tw_tallest, tw.height_at(tw_at) - tw.firm_at(tw_at))
	check(tw_tallest < pile_top + 0.3, "no tower ahead of the blade (tallest %.2f m, the pile was %.2f m)" % [tw_tallest, pile_top])
	check(tw.total() == tw_total, "spilling off the blade: the total never changes")
	print("\n%s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
