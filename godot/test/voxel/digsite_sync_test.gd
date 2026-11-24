extends SceneTree
## The Dig Site's co-op sync self-test (stage 5): two copies, --host=CODE first, then --join=CODE (both with --nosave;
## add --lag=150 --loss=10 for a bad line). The host's Travel takes both; the guest gets the host's ground; each one's
## digging shows in the other's game (the guest's own at once, the host's within moments); a heap of loose dirt the
## host drops slumps there and the guest sees it settle; a section the guest's copy gets wrong is found by the
## checksums and fixed; at the end both grounds match; home again, the guest's own site is back.
## Then the clods in co-op (integration/dirt_physics_plan.md, stage 8), before going home: the host levels the yard's
## patch and pushes across it with the bulldozer for 20 s twice, back to back: first with no clods (the baseline for
## its frames), then with them. The guest counts the clods it's shown against how many the host says it has, each
## second after the first; nothing a guest has weighs anything; when the last clod's settled the guest's sections'
## checksums are the host's within 4 s; the clods' packets are 6 kB a second at the most; the host's mass is exact,
## its clods' step and frames within stage 5's budgets. Then a stick's worth blown up: the guest throws the same
## clods itself from the host's random number. Writes integration/dirt_shots/sync_<role>.txt (--out=dir).
##   .../digsite_sync_test.gd -- --nosave --host=YARD1 --via=enet --lag=150 --loss=10
##   .../digsite_sync_test.gd -- --nosave --join=127.0.0.1 --via=enet --lag=150 --loss=10
## Owned by the voxel session.

var arena: Node
var role := ""
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}
const Yard := preload("res://test/voxel/digsite_yard.gd")
const SECS := 20.0
const LIFT := -0.1
const BLAST := Vector3(-8.0, 0.0, -9.0)   # where the host's blast is (from the site's middle: on the patch, clear of the push)
const DIG2 := Vector3(-16.0, 0.0, 9.0)    # the guest's dig while it's shown clods (off the patch)
var y := Yard.new()
var out := "res://integration/dirt_shots"
var lines := PackedStringArray()
var both := PackedFloat32Array()
var steps := PackedFloat32Array()
var res := []                   # the host's two pushes
var cur := {}
var inbox := []                 # the test's own messages from the other game ("t8")
var _paced := 0
var work_ms := 0.0
var frames := PackedFloat32Array()
var samples := []               # (the guest's) [second, shown, the host's]

const A := Vector3(5.0, 0.0, 5.0)        # where the host digs (from the site's middle)
const B := Vector3(-5.0, 0.0, 5.0)       # the guest
const C := Vector3(0.0, 0.0, -8.0)       # the host's heap

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
		elif a.begins_with("--join="):
			role = "guest"
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		say("ok   " + role + ": " + what)
	else:
		failed += 1
		say("FAIL " + role + ": " + what)

func say(s: String) -> void:
	lines.append("DSSYNC " + s)
	print("DSSYNC ", s)

func _done() -> bool:
	var ds: DigSite = arena.digsite
	say("%s stats %s" % [role, str(ds.net.stats)])
	say("done %d passed, %d failed" % [passed, failed])
	if out != "":
		var dir := ProjectSettings.globalize_path(out)
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("sync_%s.txt" % role), FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _w(local: Vector3) -> Vector3:
	var tr: DsTerrain = arena.digsite.terrain
	var p := DigSite.AT + local
	return Vector3(p.x, tr.top_at(p.x, p.z), p.z)

func _process(dt: float) -> bool:
	# (both games kept to the clock, a frame every 1/60 s at the least: headless, --fixed-fps runs a light game's
	# frames faster than a busy one's, and the two games' seconds would be different lengths. work_ms: the frame's
	# own time, without the wait)
	var now := Time.get_ticks_usec()
	if _paced > 0:
		work_ms = (now - _paced) / 1000.0
		if now - _paced < 16667:
			OS.delay_usec(16667 - (now - _paced))
	_paced = Time.get_ticks_usec()
	t += dt
	if t > 400.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var n = arena.net
	var ds: DigSite = arena.digsite
	match step:
		0:
			if n != null and n.linked and (role == "host" or n._got_world) and t > 2.0:
				_next(1)
		1:
			if t - mark > 1.0:
				if role == "host":
					arena.phone.travel("digsite")
				_next(2)
		2:
			var ok: bool = ds.active and not arena.phone._going and (role == "host" or ds.net.synced)
			if (ok and t - mark > 1.0) or t - mark > 30.0:
				check(ok, "at the Dig Site%s" % (" with the host's ground (%d bytes packed)" % ds.net.stats.world_bytes if role == "guest" else ""))
				v.top_a = _w(A).y
				v.top_b = _w(B).y
				if role == "host":
					pass                    # (the host digs once the guest's surely looked: step 3)
				else:
					var before := _w(B).y
					ds.tools.dig_at(_w(B) + Vector3(0, 0.1, 0), 0.6, 4)
					check(_w(B).y < before - 0.2, "the guest's dig shows at once (%.2f -> %.2f)" % [before, _w(B).y])
				_next(3)
		3:
			if role == "host" and not v.has("dug") and t - mark > 6.0:
				v.dug = true
				var y0 := _w(A).y
				var got := ds.tools.dig_at(_w(A) + Vector3(0, 0.1, 0), 0.6, 4)
				print("DSSYNC   host dug at A: %d blocks, top %.2f -> %.2f" % [got.n, y0, _w(A).y])
			var a_dug: bool = _w(A).y < float(v.top_a) - 0.2 or role == "host"
			var b_dug: bool = _w(B).y < float(v.top_b) - 0.2
			var settled: bool = role == "host" or ds.net._pending.is_empty()
			if (a_dug and b_dug and settled and t - mark > 7.0) or t - mark > 25.0:
				if role == "host":
					check(b_dug, "the guest's dig done in the host's ground")
					var g: DigSiteGrid = ds.terrain.grid
					var c := ds.terrain.cell_of(_w(C))
					v.c0 = c
					ds.net.act("drop", [c.x, c.z, DsMats.DIRT, 30])
					check(g.get_cell(c.x, g.column_top(c.x, c.z), c.z) & DsMats.LOOSE != 0, "the host drops a heap of loose dirt")
				else:
					check(a_dug, "the host's dig shows in the guest's game (top %.2f, was %.2f)" % [_w(A).y, v.top_a])
					check(settled, "the guest's dig confirmed by the host (nothing pending)")
				_next(4)
		4:
			if t - mark > 6.0:
				var tr: DsTerrain = ds.terrain
				var g: DigSiteGrid = tr.grid
				var c := tr.cell_of(_w(C))
				# (loose dirt on a column's top: a loose block, or 3 cm or more of the loose layer, since 9 Nov)
				var spread := 0
				for k in range(1, 12):
					var x := c.x + k
					var lay := g.get_layer(x, c.z)
					if g.get_cell(x, g.column_top(x, c.z), c.z) & DsMats.LOOSE != 0 or ((lay & 255) >= 30 and (lay >> 8) & 0x80 == 0):
						spread = k
				var loose: int = g.loose_mm() / DsTerrain.MM
				check(spread >= 2 and loose >= 20, "%s: the heap slumped out to a pile (%d cells out, %d blocks' worth loose)" % ["the host's" if role == "host" else "the guest sees it", spread, loose])
				if role == "guest":
					# the guest's copy goes wrong somewhere (as if a message were lost)
					var p := tr.cell_of(DigSite.AT + Vector3(-20, 0, -20))
					g.set_cell(p.x, g.column_top(p.x, p.z), p.z, 0)
					v.fixes = int(ds.net.stats.fixes)
				_next(5)
		5:
			var fixed: bool = role == "host" or (int(ds.net.stats.fixes) > int(v.fixes) and ds.net.last_match)
			if (fixed and t - mark > 1.0) or t - mark > 20.0:
				if role == "guest":
					check(int(ds.net.stats.fixes) > int(v.fixes), "a section gone wrong found by the checksums and fixed (%d fixes)" % ds.net.stats.fixes)
					check(ds.net.last_match, "both grounds match now")
				arena.godmode = true
				y.arena = arena
				y.tree = self
				ds.net.register_event("t8", func(a: Array): inbox.append(a))
				_next(10 if role == "host" else 20)
		6:
			if (not ds.active and not arena.phone._going and t - mark > 1.0) or t - mark > 60.0:
				check(not ds.active, "home again")
				if role == "guest":
					var g: DigSiteGrid = ds.terrain.grid
					check(g.get_seed() == DigSite.SEED and g.modified_chunks().is_empty(), "the guest's own site back as it was (%d chunks changed)" % g.modified_chunks().size())
				else:
					check(ds.net.stats.ch > 3, "the host sent %d updates (%d bytes)" % [ds.net.stats.ch, ds.net.stats.ch_bytes])
				_next(7)
		7:
			if t - mark > 2.0:
				return _done()
		_:
			return _clods(dt)
	return false

# ---------------------------------------------------------------- the clods in co-op (stage 8)

func _msg(kind: String) -> Array:
	for i in inbox.size():
		if String(inbox[i][0]) == kind:
			return inbox.pop_at(i)
	return []

func _clods(_dt: float) -> bool:
	var ds: DigSite = arena.digsite
	var d: DsDirt = ds.dirt
	if role == "guest":
		return _guest(ds, d)
	var dz := y.dozer()
	match step:
		10:
			if t - mark > 2.0:
				y.level()
				_next(11)
		11:
			if t - mark > 1.5:
				y.park_dozer()
				if res.is_empty():
					y.mount(dz)
					d.cap_us = 0
				dz.clod_share = 0.0 if res.is_empty() else DsDozer.CLOD_SHARE
				dz._clod_due = 0.0
				dz.clods_made = 0
				cur = {"mass0": y.mass(), "drift": 0, "sec": 0, "awake_most": 0, "at": dz.global_position, "ns": []}
				_next(12)
		12:
			if t - mark > 2.0:
				frames.clear()
				both.clear()
				steps.clear()
				if not res.is_empty():
					ds.net.stats.clod_most = 0
					ds.net.event("t8", ["go"])
				_next(13)
		13:
			var tr: DsTerrain = ds.terrain
			frames.append(work_ms)
			both.append(float(tr.layer_us + tr.show_us))
			if d.n > 0:
				steps.append(float(d.step_us))
			cur.awake_most = maxi(int(cur.awake_most), d.n)
			y.drive_dozer(dz, 1.0, LIFT)
			if int(t - mark) > int(cur.sec):
				cur.sec = int(t - mark)
				cur.drift = maxi(int(cur.drift), absi(int(y.mass().total) - int((cur.mass0 as Dictionary).total)))
				(cur.ns as Array).append(d.n)
			if t - mark >= SECS:
				dz.throttle = 0.0
				cur.frame = Yard.FrameTimer.of(frames)
				cur.both = Yard.FrameTimer.of(both)
				cur.step = Yard.FrameTimer.of(steps)
				cur.metres = dz.global_position.distance_to(cur.at)
				cur.made = dz.clods_made
				_next(14)
		14:
			y.drive_dozer(dz, 0.0, LIFT)
			if d.n == 0 or t - mark > 15.0:
				cur.rest_s = t - mark
				cur.left = d.n
				cur.drift = maxi(int(cur.drift), absi(int(y.mass().total) - int((cur.mass0 as Dictionary).total)))
				res.append(cur)
				if res.size() == 1:
					_next(10)
				else:
					cur.hn = 0
					cur.ht = -1.0
					_next(15)
		15:
			# (its sections' checksums, as the last clod's settled and every half second for 6 s: the guest's are to
			# be the same within 4 s)
			if t - mark >= float(cur.ht) + 0.5:
				cur.ht = t - mark
				ds.net.event("t8", ["h", int(cur.hn), ds.terrain.grid.section_hashes()])
				cur.hn = int(cur.hn) + 1
			if t - mark > 6.2:
				var a: Dictionary = res[0]
				var b: Dictionary = res[1]
				say("host: baseline (no clods) %.2f m, frames mean %.2f p95 %.2f worst %.2f ms, layer_us + show_us mean %.0f p95 %.0f" % [a.metres, a.frame.mean, a.frame.p95, a.frame.worst, a.both.mean, a.both.p95])
				say("host: with clods %.2f m, frames mean %.2f p95 %.2f worst %.2f ms, layer_us + show_us mean %.0f p95 %.0f; %d clods let go, %d awake at the most, each second %s; at rest %.2f s after the push" % [b.metres, b.frame.mean, b.frame.p95, b.frame.worst, b.both.mean, b.both.p95, b.made, b.awake_most, str(b.ns), b.rest_s])
				check(int(a.made) == 0 and int(b.made) > 200, "the host dozes %.0f s with a guest watching: over 200 clods let go (%d; the baseline %d)" % [SECS, b.made, a.made])
				check(int(a.drift) == 0 and int(b.drift) == 0 and int(b.left) == 0, "not a mm made or lost at any second, nor with every clod settled (%d mm; the baseline %d; %d clods left)" % [b.drift, a.drift, b.left])
				check(int(ds.net.stats.clod_most) <= 6000 and int(ds.net.stats.clod_n) > 100, "the clods' packets <= 6 kB a second (%d bytes in the busiest second; %d packets, %d bytes in all: %.0f a second of the push and the rest after)" % [ds.net.stats.clod_most, ds.net.stats.clod_n, ds.net.stats.clod_bytes, float(ds.net.stats.clod_bytes) / (SECS + float(b.rest_s))])
				check(float(b.step.mean) <= 2000.0, "the clods' step <= 2.0 ms on average (%.0f us with any awake; p95 %.0f, worst %.0f)" % [b.step.mean, b.step.p95, b.step.worst])
				check(float(b.frame.p95) <= float(a.frame.p95) + 3.0, "frame p95 <= the baseline's + 3.0 ms (%.2f against %.2f: %+.2f; means %.2f against %.2f)" % [b.frame.p95, a.frame.p95, float(b.frame.p95) - float(a.frame.p95), b.frame.mean, a.frame.mean])
				check(float(b.both.mean) <= 1.2 * float(a.both.mean), "layer_us + show_us within 20%% of the baseline's (mean %.0f us against %.0f: %+.0f%%)" % [b.both.mean, a.both.mean, 100.0 * (float(b.both.mean) / float(a.both.mean) - 1.0)])
				_next(16)
		16:
			# the blast (the guest's dug meanwhile, off the patch: its dirt's in its backpack, not the host's sum)
			if t - mark > 5.0:
				var at := _w(BLAST) + Vector3(0, 0.02, 0)
				v.g0 = ds.terrain.grid.ground_mm()
				var n0 := d.n
				ds.blasts._blow(at)
				v.thrown = d.n - n0
				v.blown = int(ds.blasts.last.n)
				ds.net.event("t8", ["blast", v.thrown])
				check(v.thrown > 100 and ds.terrain.grid.ground_mm() + d.mass_mm() + d.owed_mm() == int(v.g0), "the host's blast: %d blocks blown out as %d clods, all of it there" % [v.blown, v.thrown])
				_next(17)
		17:
			if (d.awake() == 0 and t - mark > 1.0) or t - mark > 15.0:      # (awake(): none left, and none's dirt still melting in: stage 9)
				check(d.awake() == 0 and ds.terrain.grid.ground_mm() + d.owed_mm() == int(v.g0), "its clods at rest %.1f s on, not a mm lost" % (t - mark))
				ds.net.event("t8", ["bdone"])
				ds.machines.get_off()
				_next(6)
	return false

func _guest(ds: DigSite, d: DsDirt) -> bool:
	# (nothing a guest has ever weighs anything)
	v.heavy = maxi(int(v.get("heavy", 0)), d.mass_mm() + d.owed_mm())
	match step:
		20:
			if not _msg("go").is_empty():
				v.sec = 0
				v.bad = 0
				v.worst = 0.0
				v.most = 0
				v.pk0 = int(ds.net.stats.clod_n)
				_next(21)
			elif t - mark > 120.0:
				check(false, "the host's push never began")
				_next(27)
		21:
			# each second after the first, for the 20 s of the push: the clods shown here against the host's own count
			# (as its last packet said)
			if int(t - mark) > int(v.sec):
				v.sec = int(t - mark)
				if int(v.sec) >= 2 and int(v.sec) <= int(SECS):
					var mine := d.shown()
					var theirs := d.host_n
					samples.append([v.sec, mine, theirs])
					v.most = maxi(int(v.most), mine)
					var off := absf(float(mine - theirs)) / maxf(1.0, float(theirs))
					v.worst = maxf(float(v.worst), off)
					if off > 0.15:
						v.bad = int(v.bad) + 1
			var h := _msg("h")
			if not h.is_empty():
				var line := ""
				for sm in samples:
					line += "%d:%d/%d " % [sm[0], sm[1], sm[2]]
				say("guest: second: shown / the host's   " + line)
				check(samples.size() >= 18 and int(v.bad) == 0 and int(v.most) > 20, "the guest's clod count within 15%% of the host's each second after the first (%d seconds, %d out; the furthest off %.1f%%; %d shown at the most; %d packets)" % [samples.size(), v.bad, 100.0 * float(v.worst), v.most, int(ds.net.stats.clod_n) - int(v.pk0)])
				v.theirs = h[2]
				v.same_at = -1.0
				v.last_h = 0
				_next(22)
			elif t - mark > 60.0:
				check(false, "the host never said its clods had settled")
				_next(27)
		22:
			var h := _msg("h")
			while not h.is_empty():
				v.theirs = h[2]
				v.last_h = int(h[1])
				h = _msg("h")
			var same: bool = ds.terrain.grid.section_hashes() == (v.theirs as PackedInt32Array)
			if same and float(v.same_at) < 0.0:
				v.same_at = t - mark
			if t - mark > 8.0 or int(v.last_h) >= 12:
				check(float(v.same_at) >= 0.0 and float(v.same_at) <= 4.0 and same, "the sections' checksums equal within 4 s of the last clod settling (%.2f s after the guest heard; still equal %.1f s on: %s; %d of the host's clods still shown)" % [v.same_at, t - mark, str(same), d.qn])
				# (a dig of its own while it's a guest: the dirt's its backpack's; nothing flies off that weighs anything)
				var before := _w(DIG2).y
				var fl: int = ds.tools.flicked
				ds.tools.dig_at(_w(DIG2) + Vector3(0, 0.1, 0), 0.6, 4)
				check(_w(DIG2).y < before - 0.2 and d.n == 0 and ds.tools.flicked == fl, "the guest digs: no clods of its own (%d, %d flicked)" % [d.n, ds.tools.flicked - fl])
				_next(23)
		23:
			var b := _msg("blast")
			if not b.is_empty():
				v.thrown = int(b[1])
				v.own_most = 0
				_next(24)
			elif t - mark > 40.0:
				check(false, "the host's blast never came")
				_next(27)
		24:
			v.own_most = maxi(int(v.own_most), d.n)
			if not _msg("bdone").is_empty() or t - mark > 30.0:
				var off := absf(float(int(v.own_most) - int(v.thrown))) / maxf(1.0, float(v.thrown))
				check(int(v.own_most) > 100 and off <= 0.15, "the host's blast thrown here too from its random number: %d clods of the guest's own to watch, the host's %d (%.1f%% off)" % [v.own_most, v.thrown, 100.0 * off])
				v.m0 = int(ds.net.stats.match)
				_next(25)
		25:
			# (its own pictures roll to rest on its copy of the ground and shrink away; and the checksums go on matching)
			if (d.n == 0 and int(ds.net.stats.match) > int(v.m0) and t - mark > 1.0) or t - mark > 20.0:
				check(d.n == 0 and d.qn == 0 and int(ds.net.stats.match) > int(v.m0) and ds.net.last_match, "the guest's pictures gone %.1f s after the host's clods, and both grounds match (%d left, %d of the host's)" % [t - mark, d.n, d.qn])
				check(int(v.heavy) == 0, "nothing the guest had weighed anything at any frame (%d mm at the most)" % int(v.heavy))
				_next(27)
		27:
			arena.phone.travel("home")
			_next(6)
	return false
