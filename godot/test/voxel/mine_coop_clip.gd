extends SceneTree
## A short film of the shared mine: two copies linked (the host first: -s test/voxel/mine_coop_clip.gd -- --host=CODE
## --via=enet --nosave --write-movie host.avi, then --join=CODE ... guest.avi), each filming its own screen, put side by
## side after. Both Moles start up top a few metres apart (the host's yellow, the guest's blue), drill down, tunnel
## towards each other and meet; the guest's dynamite blows a room out between them; both fly up out of it. Owned by
## the voxel session.

var arena: Node
var m: VoxelMine
var role := ""
var t := 0.0
var t0 := -1.0                  # when both are down there (the film's start)
var v := {}

const HX := 28.5                # where the host's Mole starts ...
const GX := 34.5                # ... and the guest's
const DEEP := 4.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
		elif a.begins_with("--join="):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _quiet() -> void:
	m.tips_done = {}
	for k in VoxelMine.TIPS:
		m.tips_done[k] = true
	m.hull = 9999.0
	m.fuel = m.tank_max()

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	m = arena.mine
	var n = arena.net
	if not v.has("prep"):
		v.prep = true
		arena.frozen = true
		arena.godmode = true
		arena.waves.queue.clear()
	if t > 120.0:
		print("MCLIP gave up")
		quit()
		return true
	if n == null or not n.linked or (role == "guest" and not n._got_world):
		return false
	if t0 < 0.0:
		if role == "host" and not m.active:
			m.enter()
			_quiet()
			v.hpos = true
		if role == "host" and v.has("hpos") and m.active and m._going == 0 and not v.has("placed"):
			v.placed = true
			# (the route: soft dirt between the two, a stone floor under it)
			var g := m.ground
			g.set_box(Vector2((HX + GX) * 0.5, -DEEP * 0.5), Vector2(5.5, DEEP * 0.5 + 0.5), MineTiles.DIRT)
			g.set_box(Vector2((HX + GX) * 0.5, -DEEP - 0.6), Vector2(5.5, 0.12), MineTiles.STONE)
			m.ship.place(Vector2(HX, 1.0))
		if role == "guest" and not m.active and not v.has("asked"):
			v.asked = true
			m.enter()
		var ready: bool = m.active and m._going == 0 and m.net.other_on and (role == "host" or m.net.shared)
		if role == "guest" and m.active and not v.has("gpos"):
			v.gpos = true
			_quiet()
			m.ship.place(Vector2(GX, 1.0))
		if ready:
			t0 = t
		return false
	m.hull = 9999.0
	m.fuel = m.tank_max()
	var s := t - t0
	var me := HX if role == "host" else GX
	var toward := 1.0 if role == "host" else -1.0
	if s < 1.5:
		m.auto = {}
	elif s < 6.0:
		m.auto = {"down": true} if -m.ship.p.y - MineShip.HALF < DEEP - 0.1 else {}
	elif s < 11.0:
		var meet := (HX + GX) * 0.5 - toward * 0.75
		m.auto = {"x": toward} if absf(m.ship.p.x - meet) > 0.1 else {}
	elif s < 12.5:
		m.auto = {}
		m.ship.face = int(toward)
	elif s < 13.0:
		if role == "guest" and not v.has("boom"):
			v.boom = true
			m.explode(Vector2((HX + GX) * 0.5, -DEEP + 1.6), 1.6, true)
	elif s < 15.0:
		m.auto = {}
	elif s < 19.5:
		m.auto = {"up": true, "x": -toward * 0.3 if s < 16.0 else 0.0}
	else:
		print("MCLIP done (%s): %.1f s" % [role, s])
		quit()
		return true
	return false
