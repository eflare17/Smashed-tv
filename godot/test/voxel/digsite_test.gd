extends SceneTree
## The Dig Site's self-test (headless: --fixed-fps 60 -s test/voxel/digsite_test.gd -- --nosave). Alone: the phone has
## the Dig Site; Travel takes you there (the arena waits, you stand on the site), the phone says you're here, Travel
## Home takes you back where you were. With --host=CODE / --join=CODE (two copies, the host first): the host's Travel
## takes both players to the Dig Site; the guest's Travel Home brings both back (asked of the host). Owned by the voxel
## session.

var arena: Node
var role := ""
var code := ""
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
			code = a.trim_prefix("--host=")
		elif a.begins_with("--join="):
			role = "guest"
			code = a.trim_prefix("--join=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DIGSITE ok   ", what)
	else:
		failed += 1
		print("DIGSITE FAIL ", what)

func _done() -> bool:
	print("DIGSITE done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _on_site() -> bool:
	return DigSite.on_site(arena.player.global_position)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if t > 120.0:
		check(false, "timed out at step %d" % step)
		return _done()
	return _solo() if role == "" else _coop()

func _solo() -> bool:
	var ds: DigSite = arena.digsite
	match step:
		0:
			check(ds != null and not ds.active, "the Dig Site's there, not gone to yet")
			check(arena.phone._buttons.has("digsite"), "the phone's Travel has the Dig Site")
			v.home = arena.player.global_position
			arena.phone.travel("digsite")
			_next(1)
		1:
			if t - mark > 2.0:
				check(ds.active and _on_site() and arena.elsewhere(), "Travel: at the Dig Site (%s), the arena waiting" % str(arena.player.global_position))
				check(ds.built and ds.get_child_count() > 5, "the site's built (%d things)" % ds.get_child_count())
				arena.phone.open()
				check(arena.phone._buttons.digsite.disabled and arena.phone._buttons.home.disabled == false, "the phone: you're here (Home to go back)")
				arena.phone.close()
				arena.phone.travel("home")
				_next(2)
		2:
			if t - mark > 2.0:
				check(not ds.active and not _on_site() and arena.player.global_position.distance_to(v.home) < 0.5, "Travel Home: back where you were")
				return _done()
	return false

func _coop() -> bool:
	var n = arena.net
	var ds: DigSite = arena.digsite
	if step == 0:
		if n == null or not n.linked or (role == "guest" and not n._got_world):
			return false
		_next(1)
	match step:
		1:
			if t - mark > 1.0:
				arena.phone.open()
				check((not arena.phone._buttons.digsite.disabled or ds.active) and arena.phone._buttons.stkilda.disabled, "co-op: the phone offers the Dig Site (or you're there: the host was quicker), not St Kilda yet")
				arena.phone.close()
				if role == "host":
					arena.phone.travel("digsite")
				_next(2)
		2:
			if (ds.active and not arena.phone._going and t - mark > 1.0) or t - mark > 25.0:
				check(ds.active and _on_site(), "co-op: %s at the Dig Site (the host's Travel took both)" % role)
				_next(3)
		3:
			if (DigSite.on_site(n._o_target) and t - mark > 0.5) or t - mark > 15.0:
				check(DigSite.on_site(n._o_target), "co-op: the other player's there too (%s)" % str(n._o_target))
				if role == "guest":
					arena.phone.travel("home")          # (asked of the host, who sends both)
				_next(4)
		4:
			if (not ds.active and not arena.phone._going and t - mark > 1.0) or t - mark > 25.0:
				check(not ds.active and not _on_site(), "co-op: %s home again (the guest's Travel Home brought both)" % role)
				_next(5)
		5:
			if t - mark > 2.0:
				return _done()
	return false
