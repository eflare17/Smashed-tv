extends SceneTree
## Checks cracker dust and the driveway jobs, with no drawing. Run: godot --headless --path . -s test/mission_test.gd
## A bot does each job with a player's controls. That says the job can be finished, not that it's any fun.

const DT := 1.0 / 60.0
const Bot := preload("res://test/spread_bot.gd")
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	dust_tests()
	drag_tests()
	spread_button_tests()
	save_tests()
	for job: Dictionary in Mission.LIST:
		job_test(job)
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

## Against a file of its own, not the real save.
func save_tests() -> void:
	Mission.save_path = "user://test_progress.cfg"
	DirAccess.remove_absolute(Mission.save_path)
	var second: Dictionary = Mission.LIST[1]
	check(Mission.open(Mission.LIST[0]), "the first job is open from the start")
	check(not Mission.open(second), "the next is shut")
	Mission.mark_done("driveway")
	check(Mission.is_done("driveway") and Mission.open(second), "finishing the first opens it")
	check(Mission.after(Mission.LIST[0]) == second, "and it's the one offered next")
	DirAccess.remove_absolute(Mission.save_path)

func dust_ok(s: DirtSim) -> bool:
	for n in s.dust.size():
		if s.dust[n] > s.soil[n] or s.dust[n] < 0:
			return false
	return true

func dust_tests() -> void:
	var s := DirtSim.new()
	var put_down := s.add_dust_pile(Vector2.ZERO, 1.5)
	print("      pile: asked 1.50 m3, got %.2f m3" % DirtSim.to_m3(put_down))
	check(absf(DirtSim.to_m3(put_down) - 1.5) < 0.15, "a pile is about the size asked for")
	check(s.dust_total() == put_down, "all of it is dust")
	var mid := DirtSim.cell_of(Vector2.ZERO)
	var height := s.soil[mid.y * DirtSim.CELLS + mid.x]
	for k in 300:
		s.step(DT, 1000000)
	print("      top %d mm, then %d mm once settled" % [height, s.soil[mid.y * DirtSim.CELLS + mid.x]])
	check(s.dust_total() == put_down, "slumping keeps every mm of dust")
	check(dust_ok(s), "and no cell has more dust than soil")
	# Dirt on top of a dust pile mixes, moves with it, and none is lost.
	s.put(mid.x, mid.y, 3000)
	for k in 600:
		s.step(DT, 1000000)
	check(s.dust_total() == put_down and dust_ok(s), "dirt slumping through it keeps the dust too")
	# A blade pushes it along as dust.
	var r: Array = s.blade(Vector2(-2, -1), Vector2(2, -1), Vector2(0, 1), 50, 0)
	check(r[0] > 0 and s.dust_total() == put_down and dust_ok(s), "a blade pushes it, and it's still dust")
	# Falling chunks.
	s.launch(Vector3(4, 3, 4), Vector3.ZERO, 500, 500)
	check(s.dust_total() == put_down + 500, "a falling chunk counts as dust")
	for k in 120:
		s.step(DT, 1000000)
	check(s.dust[DirtSim.cell_of(Vector2(4, 4)).y * DirtSim.CELLS + DirtSim.cell_of(Vector2(4, 4)).x] > 0, "and lands as dust")
	check(s.dust_total() == put_down + 500 and dust_ok(s), "with nothing lost")

func drag_tests() -> void:
	# Back-dragging a heap leaves an even layer, and never cuts the firm ground.
	var s := DirtSim.new()
	var ground := GroundData.new()
	var heap := DirtSim.cell_of(Vector2(0, -6))
	for j in range(heap.y - 2, heap.y + 3):
		for i in range(heap.x - 3, heap.x + 4):
			s.put(i, j, 150, 150)
	var total := s.total()
	var dust_was := s.dust_total()
	var l := Loader.new()
	root.add_child(l)
	l.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), Vector2(0, -8.0), Vector2(0, -1), Loader.DINGO)
	check(not l.bucket_low(), "the bucket starts up, so driving doesn't spread by accident")
	# Lower, then back up across it, and on past where it ends.
	l.lift_cmd = -1.0
	for k in 60:
		l.step(DT)
		s.step(DT, 1000000)
	l.lift_cmd = 0.0
	check(l.bucket_low(), "lowered, it's ready to spread")
	print("      word: %s" % l.gauge_word()[0])
	var spread_seen := false
	l.throttle = -1.0
	for k in 480:
		l.step(DT)
		s.step(DT, 1000000)
		spread_seen = spread_seen or l.spreading
	check(spread_seen, "backing up with it low spreads")
	check(s.total() == total, "total unchanged")
	check(s.dust_total() == dust_was and dust_ok(s), "and it's all still dust")
	var depths := {}
	for j in range(heap.y + 3, DirtSim.cell_of(l.spot).y):
		var d: int = s.dust[j * DirtSim.CELLS + heap.x]
		depths[d] = depths.get(d, 0) + 1
	print("      depths behind the bucket, down the middle (mm: cells): %s; machine at %s, bed change %d" % [depths, l.spot, s.bed[heap.y * DirtSim.CELLS + heap.x]])
	var firm_same := true
	for n in s.bed.size():
		if s.bed[n] != 0:
			firm_same = false
			break
	check(firm_same, "the firm ground isn't touched")
	l.queue_free()

## A load tipped from a raised bucket stands as a heap, and the SPREAD button flattens it driving forward, with no scooping.
func spread_button_tests() -> void:
	for which: String in [Loader.DINGO, Loader.BOBCAT]:
		var s := DirtSim.new()
		var ground := GroundData.new()
		var l := Loader.new()
		root.add_child(l)
		l.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), Vector2(0, -8.0), Vector2(0, -1), which)
		l.bucket_mm = l.capacity
		l.bucket_dust = l.capacity
		s.held += l.capacity
		var total := s.total()
		l.lift_cmd = 1.0
		for k in 90:
			l.step(DT)
			s.step(DT, 1000000)
		l.lift_cmd = 0.0
		l.curl_cmd = -1.0
		for k in 180:
			l.step(DT)
			s.step(DT, 1000000)
		l.curl_cmd = 0.0
		for k in 240:
			l.step(DT)
			s.step(DT, 1000000)
		var top := 0
		var n_top := 0
		for n in s.dust.size():
			if s.dust[n] > top:
				top = s.dust[n]
				n_top = n
		print("      %s: a full bucket (%.2f m3) tipped stands %d mm high" % [which, DirtSim.to_m3(l.capacity), top])
		check(l.bucket_mm == 0, "%s tipped it all out" % which)
		check(top >= (300 if which == Loader.DINGO else 500), "%s: it lands as a real heap" % which)
		l.toggle_spread()
		for k in 240:
			l.step(DT)
			s.step(DT, 1000000)
		check(l.arm <= l.arm_low + 0.01, "SPREAD lowers the bucket by itself")
		var firm_was := s.bed.duplicate()
		l.throttle = 0.6
		var start := l.spot
		var seen := false
		for k in 300:
			l.step(DT)
			s.step(DT, 1000000)
			seen = seen or l.spreading
		l.throttle = 0.0
		var tallest := 0
		for n in s.dust.size():
			tallest = maxi(tallest, s.dust[n])
		print("      drove %.1f m with SPREAD on: tallest now %d mm" % [l.spot.distance_to(start), tallest])
		check(seen and tallest < top, "driving forward flattens it")
		check(l.bucket_mm == 0, "and none goes in the bucket")
		check(s.bed == firm_was, "and the firm ground isn't cut")
		l.throttle = -0.6
		for k in 300:
			l.step(DT)
			s.step(DT, 1000000)
		l.throttle = 0.0
		check(s.total() == total, "total unchanged")
		check(dust_ok(s), "no cell has more dust than soil")
		l.lift_cmd = 1.0
		l.step(DT)
		check(not l.spread_on, "RAISE turns SPREAD off")
		l.queue_free()

func job_test(job: Dictionary) -> void:
	print("--- %s" % job["title"])
	var ground := GroundData.new(Mission.site(job), job["rect"], Mission.road(job))
	var s := DirtSim.new()
	ground.fill_sim(s)
	var had := s.add_dust_pile(job["pile"], job["pile_m3"])
	var total := s.total()
	var r: Rect2 = job["rect"]
	var a := DirtSim.cell_of(r.position)
	var flat := true
	for j in range(a.y, DirtSim.cell_of(r.end).y):
		for i in range(a.x, DirtSim.cell_of(r.end).x):
			if absi(s.bed[j * DirtSim.CELLS + i]) > 20:
				flat = false
	check(flat, "the driveway is flat")
	var road_at := DirtSim.cell_of(Vector2(0.0, 12.0))
	check(s.rock[road_at.y * DirtSim.CELLS + road_at.x] == 1, "the road can't be dug")
	check(is_zero_approx(Mission.coverage(s, job)), "nothing's done to start with")
	var l := Loader.new()
	root.add_child(l)
	l.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), job["start"], job["dir"], job["machine"])
	l.reposition(job["start"], job["dir"])
	var bot := Bot.new(l, s, job)
	var t := 0.0
	var finished_at := -1.0
	var same := true
	var last_print := 0.0
	while t < 1500.0 and bot.trip < bot.want_trips * 3:
		t += DT
		bot.tick(DT)
		l.step(DT)
		s.step(DT, 1000000)
		var cover := Mission.coverage(s, job) if int(t * 60.0) % 30 == 0 else -1.0
		if cover >= Mission.PASS and finished_at < 0.0:
			finished_at = t
			break
		if bot.state == "back_up" and absf(l.speed) < 0.01 and bot.clock > 3.0 and int(t * 60.0) % 600 == 0:
			print("      STUCK %.0f: thr %.2f drive %.2f speed %.3f back %.2f cap %.2f rock %s slip %s pitch %.2f y %.2f at %s teeth %s" % [t, l.throttle, l.drive, l.speed, l.back_speed, l._speed_cap, l.on_rock, l.slipping, l.transform.basis.x.y, l.y_smooth, l.spot, l.teeth])
		if t - last_print > 60.0:
			last_print = t
			print("      %.0f s: trip %d of %d, covered %.0f%%, state %s, at %s, bucket %.2f m3" % [t, bot.trip, bot.want_trips, Mission.coverage(s, job) * 100.0, bot.state, l.spot, DirtSim.to_m3(l.bucket_mm)])
	if s.total() != total:
		same = false
	var cover_now := Mission.coverage(s, job)
	var least := 99999
	var most := 0
	var sum := 0
	var cells := 0
	for j in range(a.y, DirtSim.cell_of(r.end).y):
		for i in range(a.x, DirtSim.cell_of(r.end).x):
			var d := s.dust[j * DirtSim.CELLS + i]
			least = mini(least, d)
			most = maxi(most, d)
			sum += d
			cells += 1
	var carrying := l.bucket_dust + l._pour_dust
	print("      finished at %.0f s after %d trips: covered %.1f%%. On the driveway least %d mm, average %d mm, most %d mm. Dust left off it %.2f m3" % [finished_at, bot.trip, cover_now * 100.0, least, sum / cells, most, DirtSim.to_m3(had - sum * 1)])
	check(finished_at > 0.0, "%s can be finished with %s" % [job["title"], job["machine"]])
	check(same, "the total never changes")
	check(s.dust_total() + carrying == had, "no dust is lost (%d of %d)" % [s.dust_total() + carrying, had])
	check(dust_ok(s), "and no cell has more dust than soil")
	l.queue_free()
