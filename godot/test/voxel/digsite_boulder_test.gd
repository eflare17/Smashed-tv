extends SceneTree
## The owner's "this big boulder flickers when I emptied the bucket" (24 Nov; integration/dirt_physics_plan.md, stage
## 9; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_boulder_test.gd -- --nosave
## ). The "boulder" is one of the big lumps drawn on loose dirt (DsClods: laid once at fixed spots, each drawn by its
## shader from the ground under it). The excavator where it's parked, on the grass, a full bucket of sand, dirt and
## clay put in it by the script, tipped out; every frame until the clods have come to rest, each big lump within 2 m
## of where the dirt lands is looked at as its shader draws it (DsClods.lump_drawn, the shader's own sums): the ground
## under it, how far it's turned, how big, what colour. Passes when
##   - nothing of the lumps' nodes changes while the clods land: the same nodes, meshes and instances' transforms,
##     and no patch that's shown is hidden again;
##   - from a second after the clods are at rest no big lump changes at all;
##   - no big lump turns more than TURN_MOST in a frame, nor jumps in size or colour (SIZE_MOST, COL_MOST), nor
##     shuffles more than a centimetre; the ground under one rises 30 mm in a frame at the most;
##   - as it was the fault's there to be fixed: the same bucket poured first with the clods' dirt laid the step they
##     settle (DsDirt.melt off) and the lumps worked out as the shader drew them then (its calm 0), then again, the
##     house swung a quarter turn onto fresh grass, as it is now;
##   - not a mm made or lost.
## Writes integration/dirt_shots/boulder.txt (--out=dir). Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const NEAR := 2.0               # m from where the dirt lands
const BIG := 0.25               # a lump this size (its instance's scale: about half a metre across) or more
const TURN_MOST := 0.12         # rad a frame (7 degrees)
const SIZE_MOST := 0.2          # of its full size, in a frame
const COL_MOST := 0.5           # of a plain change of soil (sand to dirt is 1.4 on this scale), in a frame

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := "res://integration/dirt_shots"
var lines := PackedStringArray()
var lumps := []                 # {root, size, patch, index, t: Transform3D}
var was := []                   # each one's lump_drawn last frame: [new, old]
var worst := [{}, {}]
var res := []                   # each pour's: {worst, most, seen, peak, rest, frames, n}
var pour := 0                   # 0: as it was (the clods' dirt laid the step they settle); 1: as it is
var before := {}
var frames := 0
var still_changed := 0
var hidden_again := 0
var shown := {}
var peak := 0
var at := Vector3.ZERO
var rest_at := -1.0
var moved := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_clear()
	y.boot(self)

func _clear() -> void:
	for k in 2:
		worst[k] = {"turn": 0.0, "size": 0.0, "col": 0.0, "shift": 0.0, "flips": 0, "rise": 0.0}
	lumps = []
	was = []
	frames = 0
	peak = 0
	rest_at = -1.0

func say(s: String) -> void:
	lines.append("DSBOULDER " + s)
	print("DSBOULDER ", s)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		say("ok   " + what)
	else:
		failed += 1
		say("FAIL " + what)

func _x() -> DsExcavator:
	return y.machine("excavator") as DsExcavator

func _find() -> void:
	var cl: DsClods = y.ds().clods
	for l: Dictionary in cl.laid_near(at, NEAR, BIG):
		var inst: MultiMeshInstance3D = cl._patches[l.patch]
		l.node = inst
		l.mm = inst.multimesh
		l.mesh = inst.multimesh.mesh
		l.count = inst.multimesh.instance_count
		l.at = inst.position
		l.total = [0.0, 0.0]
		l.seen = false
		lumps.append(l)

func _look() -> void:
	var tr: DsTerrain = y.ds().terrain
	var topo: PackedByteArray = tr.grid.show_topo_bytes()
	var off: PackedByteArray = tr.grid.show_offsets()
	var now := []
	for l: Dictionary in lumps:
		now.append([DsClods.lump_drawn(topo, off, tr.origin, l.root, l.size, 1.0), DsClods.lump_drawn(topo, off, tr.origin, l.root, l.size, 0.0)])
	if not was.is_empty():
		frames += 1
		for i in lumps.size():
			for k in 2:
				var a: Dictionary = was[i][k]
				var b: Dictionary = now[i][k]
				if float(a.keep) < 0.5 and float(b.keep) < 0.5:
					continue                    # (not a big lump yet: under half its size)
				lumps[i].seen = true
				var w: Dictionary = worst[k]
				var turn := absf(float(b.angle) - float(a.angle))
				var dh := absf(float(b.h) - float(a.h))
				var dcol := Vector3(b.col.r - a.col.r, b.col.g - a.col.g, b.col.b - a.col.b).length() / 0.5   # (sand to dirt is 0.69 apart; 0.5: a plain change of soil)
				var dsize := absf(float(b.keep) - float(a.keep))
				if rest_at >= 0.0 and t - rest_at > 1.0 and k == 0 and (turn > 0.0 or dsize > 0.0 or dcol > 0.0):
					still_changed += 1
				w.rise = maxf(w.rise, dh)
				w.turn = maxf(w.turn, turn)
				w.size = maxf(w.size, dsize)
				w.col = maxf(w.col, dcol)
				if dcol > COL_MOST:
					w.flips += 1
				w.shift = maxf(w.shift, (b.shift - a.shift).length())
				lumps[i].total[k] += turn
	was = now
	var cl: DsClods = y.ds().clods
	for p in cl._patches.size():
		var v: bool = cl._patches[p].visible
		if shown.get(p, false) and not v:
			hidden_again += 1
		shown[p] = v

func _process(dt: float) -> bool:
	t += dt
	var d: DsDirt = y.ds().dirt if y.ds() != null else null
	match step:
		0:
			if t > 1.5:
				y.travel()
				step = 1
				mark = t
		1:
			if y.arrived() and t - mark > 1.0:
				var x := _x()
				y.mount(x)
				x.wrist = Vector2(5.4, 2.4)
				x.curl = 2.7
				step = 2
				mark = t
		2:
			if t - mark > 0.8:
				var x := _x()
				var c := DsExcavator.CAPACITY
				x.bucket = {DsMats.SAND: c / 2, DsMats.DIRT: c / 4, DsMats.CLAY: c / 4}
				x.load_n = c
				before = y.mass()
				d.melt = pour == 1
				at = x.pour_point()
				_find()
				x.curl_cmd = -1.0
				step = 3
				mark = t
		3:
			_look()
			peak = maxi(peak, d.n)
			if _x().load_n == 0 and d.n == 0 and rest_at < 0.0:
				rest_at = t
			if rest_at >= 0.0 and t - rest_at > 2.0 or t - mark > 30.0:
				var seen := 0
				var most := [0.0, 0.0]
				for l: Dictionary in lumps:
					if l.seen:
						seen += 1
					for k in 2:
						most[k] = maxf(most[k], l.total[k])
				var cl: DsClods = y.ds().clods
				for l: Dictionary in lumps:
					var inst: MultiMeshInstance3D = cl._patches[l.patch]
					if inst != l.node or inst.multimesh != l.mm or inst.multimesh.mesh != l.mesh or inst.multimesh.instance_count != l.count or inst.position != l.at:
						moved += 1
				res.append({"worst": worst.duplicate(true), "most": most, "seen": seen, "peak": peak, "rest": rest_at - mark, "frames": frames, "n": lumps.size(), "at": at})
				if pour == 1:
					_report()
					return true
				# (again, as it is now, the house swung a quarter turn: fresh grass)
				pour = 1
				_clear()
				var x := _x()
				x.curl_cmd = 0.0
				x.curl = 2.7
				x.swing = wrapf(x.swing + PI * 0.5, -PI, PI)
				x._pour_p = Vector3.INF
				step = 2
				mark = t
	return false

func _report() -> void:
	var d: DsDirt = y.ds().dirt
	for k in 2:
		var r: Dictionary = res[k]
		say("%s: the excavator's %d mm (half sand, a quarter dirt, a quarter clay) tipped out on the grass: %d clods awake at the most, at rest %.1f s after; %d frames looked at; %d lumps of size %.2f or more within %.1f m, %d of them drawn at half their size or more" % ["as it was (a clod's dirt laid the step it settles)" if k == 0 else "as it is (melting in)", DsExcavator.CAPACITY, r.peak, r.rest, r.frames, r.n, BIG, NEAR, r.seen])
		for j in 2:
			var q: Dictionary = r.worst[j]
			say("     drawn %s: in a frame at the most a big lump turned %.3f rad (%.1f degrees), changed size %.3f, colour %.3f (%d times over %.2f), shuffled %.1f mm; the ground under one rose %.1f mm; %.2f rad turned in all" % ["as it is (calm 1)" if j == 0 else "as it was (calm 0)", q.turn, rad_to_deg(q.turn), q.size, q.col, q.flips, COL_MOST, q.shift * 1000.0, q.rise * 1000.0, r.most[j]])
	var o: Dictionary = res[0].worst[1]
	var w: Dictionary = res[1].worst[0]
	check(d.n == 0 and res[0].peak > 50 and res[1].peak > 50, "both buckets poured as clods, and they've come to rest (%d and %d awake at the most)" % [res[0].peak, res[1].peak])
	check(res[0].seen >= 3 and res[1].seen >= 3, "big lumps stand in both heaps (%d and %d)" % [res[0].seen, res[1].seen])
	check(moved == 0 and hidden_again == 0, "none of the lumps' nodes, multimeshes, meshes or places changed (their instances are laid once, at the start), and no patch shown was hidden again (%d changed, %d hidden)" % [moved, hidden_again])
	check(still_changed == 0, "from a second after the clods are at rest no big lump changes at all (%d frames one did)" % still_changed)
	check(o.turn > TURN_MOST * 2.0, "as it was, the fault's there: a big lump turned %.2f rad in a frame (%.0f degrees), %.1f rad in all; %d frames a lump changed soil (the most %.2f)" % [o.turn, rad_to_deg(o.turn), res[0].most[1], o.flips, o.col])
	check(w.turn <= TURN_MOST, "no big lump turns more than %.2f rad in a frame: %.3f (%.1f degrees; it was %.2f), %.2f rad in all at the most (it was %.1f)" % [TURN_MOST, w.turn, rad_to_deg(w.turn), o.turn, res[1].most[0], res[0].most[1]])
	check(w.rise <= 0.03, "the ground under a big lump rises 30 mm in a frame at the most: %.1f (it was %.1f)" % [w.rise * 1000.0, o.rise * 1000.0])
	check(w.size <= SIZE_MOST, "nor does one grow or shrink more than %.2f of its size in a frame: %.3f (it was %.3f)" % [SIZE_MOST, w.size, o.size])
	check(w.col <= COL_MOST, "nor change colour more than %.2f of a soil's in a frame: %.3f (it was %.2f, %d times)" % [COL_MOST, w.col, o.col, o.flips])
	check(w.shift <= 0.01, "nor shuffle more than 1 cm in a frame: %.1f mm (it was %.1f)" % [w.shift * 1000.0, o.shift * 1000.0])
	var after := y.mass()
	check(int(after.total) == int(before.total), "not a mm made or lost (%d mm)" % (int(after.total) - int(before.total)))
	say("done %d passed, %d failed" % [passed, failed])
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("boulder.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
