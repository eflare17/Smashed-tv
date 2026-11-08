extends SceneTree
## The Dig Site hand tools' self-test (stage 3; headless: --fixed-fps 60 -s test/voxel/digsite_tools_test.gd -- --nosave):
## the shovel digs the soil into the backpack and fills it back; it can't break rock, the pick can; the hammer chips;
## gems need a steel pick, made at the site office out of what the ground gives; the tiers are saved. Owned by the
## voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSTOOLS ok   ", what)
	else:
		failed += 1
		print("DSTOOLS FAIL ", what)

func _done() -> bool:
	print("DSTOOLS done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _ds() -> DigSite:
	return arena.digsite

func _count_solid(tr: DsTerrain) -> int:
	return tr.grid.count_box(0, 0, 0, 512, 192, 512, -1)

# the player at a spot on the site, looking straight down
func _stand(local: Vector3) -> void:
	var tr := _ds().terrain
	var top := tr.top_at(DigSite.AT.x + local.x, DigSite.AT.z + local.z)
	_ds()._put(Vector3(DigSite.AT.x + local.x, top + 0.1, DigSite.AT.z + local.z), 0.0, -1.4)

func _swing(id: String, button := MOUSE_BUTTON_LEFT) -> void:
	var w = arena.melee[id]
	w._cd = 0.0
	w._t = -1.0
	w.press(button)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if t > 90.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var ds := _ds()
	match step:
		0:
			check(arena.melee.has("hammer_ds") and arena.loadout.index_of("hammer_ds") >= 0, "the hammer's in the tools (group 6)")
			check(VoxelItems.has("coal") and VoxelItems.has("iron_ore") and VoxelItems.has("gem") and VoxelItems.has("sand"), "the backpack knows coal, iron ore, gems, sand")
			arena.phone.travel("digsite")
			_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				_stand(Vector3(6, 0, 6))
				v.dirt = arena.inv.count("dirt")
				v.solid = _count_solid(ds.terrain)
				_next(2)
		2:
			if t - mark > 0.6:
				_swing("shovel")
				_next(3)
		3:
			if t - mark > 0.6:
				var got: int = arena.inv.count("dirt") - int(v.dirt)
				var gone: int = int(v.solid) - _count_solid(ds.terrain)
				check(got > 0 and got == gone, "the shovel: a scoop of soil into the backpack (%d dirt, %d blocks gone)" % [got, gone])
				v.dirt = arena.inv.count("dirt")
				v.solid = _count_solid(ds.terrain)
				_swing("shovel", MOUSE_BUTTON_RIGHT)
				_next(4)
		4:
			if t - mark > 0.6:
				var put: int = int(v.dirt) - arena.inv.count("dirt")
				var back: int = _count_solid(ds.terrain) - int(v.solid)
				check(put > 0 and put == back, "its right click: dirt back in the hole (%d out of the backpack, %d blocks back)" % [put, back])
				# a shaft down to the stone (as if dug), the player at its bottom
				var tr := ds.terrain
				tr.paused = true              # (the shaft's dirt walls would cave in: stage 4's dirt, not what's tested here)
				var c := DigSite.AT + Vector3(-6, 0, -6)
				var top := tr.top_at(c.x, c.z)
				var y := top
				while y > top - 7.6:
					tr.dig(Vector3(c.x, y, c.z), 0.9, 6)
					y -= 0.5
				tr.build_now(500.0)
				_stand(Vector3(-6, 0, -6))
				v.depth = top - arena.player.global_position.y
				v.under = DsMats.name_of(tr.cell_at(arena.player.global_position + Vector3(0, -0.2, 0)))
				v.solid = _count_solid(tr)
				_next(5)
		5:
			if t - mark > 1.0:
				print("DSTOOLS   at the shaft's bottom: %.1f m down, on %s" % [v.depth, v.under])
				v.solid = _count_solid(ds.terrain)
				_swing("shovel")
				_next(6)
		6:
			if t - mark > 0.6:
				check(_count_solid(ds.terrain) == int(v.solid), "the shovel can't break the rock")
				v.stone = arena.inv.count("stone") + arena.inv.count("coal") + arena.inv.count("iron_ore")
				_swing("pick")
				_next(7)
		7:
			if t - mark > 0.7:
				var got: int = arena.inv.count("stone") + arena.inv.count("coal") + arena.inv.count("iron_ore") - int(v.stone)
				check(got > 0 and _count_solid(ds.terrain) < int(v.solid), "the pick breaks it: %d bits of rock in the backpack" % got)
				v.solid = _count_solid(ds.terrain)
				_swing("hammer_ds")
				_next(8)
		8:
			if t - mark > 0.7:
				var chipped: int = int(v.solid) - _count_solid(ds.terrain)
				check(chipped > 0 and chipped < 20, "the hammer chips a little out (%d blocks)" % chipped)
				_office_checks(ds)
				return _done()
	return false

func _office_checks(ds: DigSite) -> void:
	var tl := ds.tools
	check(int(tl.stats("pick")[1]) == 4, "the pick breaks hardness 4 (not gems)")
	# at the office counter: what it makes
	ds._put(DigSite.AT + DigSite.OFFICE_WINDOW + Vector3(1.2, -1.1, 0), -PI * 0.5, 0.0)
	ds._process(0.016)
	check(ds.near_office and tl.office_line().begins_with("Site office: a Steel pick needs"), "the site office: '%s'" % tl.office_line())
	check(not tl.office_make() and tl.pick_tier == 0, "not enough: nothing made")
	arena.inv.add("iron_ore", 20)
	arena.inv.add("coal", 20)
	arena.inv.add("stone", 60)
	var iron: int = arena.inv.count("iron_ore")
	check(tl.office_line().begins_with("E  make a Steel pick"), "with the ore: '%s'" % tl.office_line())
	check(tl.office_make() and tl.pick_tier == 1 and arena.inv.count("iron_ore") == iron - 20, "made: a steel pick (the ore spent)")
	check(int(tl.stats("pick")[1]) == 5 and arena.melee["pick"].tier == 1, "the steel pick breaks gems (hardness 5)")
	check(tl.offer().name == "Diamond pick", "next: a diamond pick")
	var d := tl.save_data()
	tl.set_tiers(0, 0)
	tl.load_data(d)
	check(tl.pick_tier == 1 and tl.hammer_tier == 0, "the tiers saved and loaded")
