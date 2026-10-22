extends SceneTree
## The weapon bench (Stage 13, VoxelUpgrades; headless): it's in the yard, its three racks picked by where you look;
## no cash, no sale; CLIPS makes the pistol's clip, the shotgun's tube and the launcher's drum bigger; DAMAGE makes
## the same hit knock out more; FUEL makes the tanks last; three levels and no more; saved and loaded. With
## --host=CODE / --join=CODE (two copies, the host first) it checks co-op: the guest's levels reach the host's copies
## of the guest's weapons. Prints "UPG ok/FAIL ..." and "UPG done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var save_path := ""

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("UPG %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
		elif a.begins_with("--save="):
			save_path = a.trim_prefix("--save=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _grunt(p: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = p
	b.yaw = 0.0
	arena.bodies.append(b)
	b.animate(0.016, false)
	return b

# cubes the same pistol-sized hit knocks out of a fresh grunt's chest now
func _hole() -> int:
	var b := _grunt(Vector3(0, 0, -3))
	var res: Dictionary = b.damage({"part": "torso", "cell": (b.parts.torso.grid.size as Vector3i) / 2}, 2.2)
	var n := (res.bits as Array).size()
	arena.bodies.erase(b)
	b.queue_free()
	return n

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role != "":
		return _coop()
	match step:
		0:
			var u: VoxelUpgrades = arena.upgrades
			check(u != null and VoxelYard.in_yard(VoxelUpgrades.AT + Vector3(0, 0, 0.6)), "the weapon bench: in the yard")
			var eye := VoxelUpgrades.AT + Vector3(0, 1.6, 1.4)
			var picks := []
			for x in [-0.7, 0.0, 0.7]:
				picks.append(u.pick(eye, (VoxelUpgrades.AT + Vector3(x, 1.2, 0) - eye).normalized()))
			check(picks == ["damage", "clip", "fuel"], "its racks by where you look: %s" % str(picks))
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			arena.cash = 10
			check(not arena.upgrade_buy("clip") and int(arena.me.upg.clip) == 0 and arena.cash == 10, "no cash, no sale")
			check(u.line("clip", arena.me.upg, arena.cash).contains("$20"), "... it says what it costs: " + u.line("clip", arena.me.upg, arena.cash))
			arena.cash = 1000
			var p0: int = arena.melee.pistol.clip_max
			check(arena.upgrade_buy("clip") and arena.cash == 980, "CLIPS level 1 bought ($20)")
			check(arena.melee.pistol.clip_max == roundi(p0 * 1.5) and arena.melee.shotgun.clip_max == 9 and arena.melee.grenades.clip_max == 9
				and arena.melee.pistol.clip == arena.melee.pistol.clip_max,
				"... the pistol's clip %d, the shotgun's tube %d, the launcher's drum %d, full" % [arena.melee.pistol.clip_max, arena.melee.shotgun.clip_max, arena.melee.grenades.clip_max])
			var n0 := _hole()
			arena.upgrade_buy("damage")
			arena.upgrade_buy("damage")
			var n2 := _hole()
			check(is_equal_approx(VoxelBody.hit_k, 1.4) and n2 > n0 * 1.5, "DAMAGE level 2: the same hit knocks out %d cubes, not %d" % [n2, n0])
			arena.upgrade_buy("fuel")
			check(is_equal_approx(arena.me.upg_k("fuel"), 1.5) and is_equal_approx(arena.melee.laser._fuel_k(), 1.5), "FUEL level 1: the tanks last half as long again")
			var ft: VoxelMelee = arena.melee.flamethrower
			check(is_equal_approx(VoxelWeaponFlamethrower.refuel(1.0, 1.0 / 1.5, true, 0.0), 1.0 - 1.0 / (VoxelWeaponFlamethrower.FUEL_S * 1.5)) and ft != null,
				"... the flamethrower's 8 s tank good for 12 s")
			arena.upgrade_buy("damage")
			var c0: int = arena.cash
			check(not arena.upgrade_buy("damage") and arena.cash == c0 and int(arena.me.upg.damage) == 3, "three levels and no more")
			check(u.line("damage", arena.me.upg, arena.cash).contains("as good as it gets"), "... it says so")
			# saved and loaded
			if save_path != "":
				arena.stash.save_path = save_path
				arena.stash.save()
				var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
				check(d is Dictionary and int(d.tools.upg.damage) == 3 and int(d.tools.upg.clip) == 1, "saved with the backpack: %s" % str(d.tools.upg if d is Dictionary else "-"))
				arena.set_upgrades({})
				check(int(arena.me.upg.damage) == 0 and is_equal_approx(VoxelBody.hit_k, 1.0), "(levels taken off)")
				arena.stash.load_save()
				check(int(arena.me.upg.damage) == 3 and int(arena.me.upg.fuel) == 1 and arena.melee.pistol.clip_max == roundi(p0 * 1.5), "loaded again: all back")
				DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
			step = 99
		99:
			print("UPG done %d passed, %d failed" % [passed, failed])
			return true
	return false

func _coop() -> bool:
	var net = arena.net
	match step:
		0:
			if net.linked and net.other and t > 3.0:
				mark = t
				step = 1
				if role == "guest":
					arena.cash = 1000
					arena.upgrade_buy("clip")
					arena.upgrade_buy("damage")
			elif t > 40.0:
				check(false, "never linked")
				step = 99
		1:
			if role == "host":
				var w: VoxelMelee = net._o_weapons.get("pistol")
				if int(net.other.upg.clip) == 1 and int(net.other.upg.damage) == 1:
					check(w != null and w.clip_max == 18, "the guest's levels came: the host's copy of their pistol holds %d" % (w.clip_max if w else -1))
					net._as_other(true)
					var k_them := VoxelBody.hit_k
					net._as_other(false)
					check(is_equal_approx(k_them, 1.2) and is_equal_approx(VoxelBody.hit_k, 1.0), "their weapons hit with their DAMAGE (x%.2f), this player's with theirs (x%.2f)" % [k_them, VoxelBody.hit_k])
					step = 2
				elif t - mark > 10.0:
					check(false, "the guest's levels never came (%s)" % str(net.other.upg))
					step = 99
			else:
				if t - mark > 6.0:
					check(int(arena.me.upg.clip) == 1 and arena.melee.pistol.clip_max == 18, "the guest's own: bought, the pistol holds 18")
					step = 99
		2:
			if t - mark > 3.0:
				step = 99
		99:
			print("UPG done %d passed, %d failed" % [passed, failed])
			return true
	return false
