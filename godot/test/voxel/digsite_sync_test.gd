extends SceneTree
## The Dig Site's co-op sync self-test (stage 5): two copies, --host=CODE first, then --join=CODE (both with --nosave;
## add --lag=150 --loss=10 for a bad line). The host's Travel takes both; the guest gets the host's ground; each one's
## digging shows in the other's game (the guest's own at once, the host's within moments); a heap of loose dirt the
## host drops slumps there and the guest sees it settle; a section the guest's copy gets wrong is found by the
## checksums and fixed; at the end both grounds match; home again, the guest's own site is back. Owned by the voxel
## session.

var arena: Node
var role := ""
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

const A := Vector3(5.0, 0.0, 5.0)        # where the host digs (from the site's middle)
const B := Vector3(-5.0, 0.0, 5.0)       # the guest
const C := Vector3(0.0, 0.0, -8.0)       # the host's heap

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
		elif a.begins_with("--join="):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSSYNC ok   ", role, ": ", what)
	else:
		failed += 1
		print("DSSYNC FAIL ", role, ": ", what)

func _done() -> bool:
	var ds: DigSite = arena.digsite
	print("DSSYNC %s stats %s" % [role, str(ds.net.stats)])
	print("DSSYNC done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _w(local: Vector3) -> Vector3:
	var tr: DsTerrain = arena.digsite.terrain
	var p := DigSite.AT + local
	return Vector3(p.x, tr.top_at(p.x, p.z), p.z)

func _process(dt: float) -> bool:
	t += dt
	if t > 150.0:
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
					arena.phone.travel("home")
				_next(6)
		6:
			if (not ds.active and not arena.phone._going and t - mark > 1.0) or t - mark > 30.0:
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
	return false
