class_name DsSupports
extends Node3D
## Supports at the Dig Site (stage 8): the hammer's right click puts a post (2 x 2 blocks, 25 cm square) from the
## floor up to the roof where you aim, out of your backpack: a wooden prop (cheap: the site office sells them) or a
## concrete support (made there from stone, sand and gravel). They're solid blocks of the ground (DsMats.WOOD,
## DsMats.CONCRETE), so a roof's span is measured to them too: a post halves a room's span (stage 7's cave-ins).
## Deeper down there's more weight on them: a wooden prop holds to WOOD_OK metres under the ground; past that it
## groans, and past WOOD_MAX it cracks too, and before long it gives way (its blocks drop loose; the roof it held may
## follow). Concrete holds to CONCRETE_MAX (the whole site). The game that runs the ground keeps the list and does the
## weight; a guest's posts go to the host as actions ("post"), and it hears the creaks ("sup" events). Owned by the
## voxel session.

const POST := 2                 # cells a side
const MOST_UP := 32             # cells: the tallest post (4 m)
const WOOD_OK := 5.0            # metres under the ground's top a wooden prop holds for good ...
const WOOD_MAX := 9.0           # ... past this, quickly gives way
const WOOD_LIFE := 40.0         # s a wooden prop lasts just past WOOD_OK (less, deeper: WOOD_MAX and past, 8 s)
const CONCRETE_MAX := 30.0
const CHECK_T := 0.5

var site: Node3D                # DigSite
var posts := []                 # {x, z, y0, y1, m, stress (0 .. 1), groan_t}
var stress_k := 1.0             # (the tests: weight comes on this many times as fast)
var broke := 0                  # (the tests')
var heard := 0
var added := 0
var _t := 0.0

func setup(s: Node3D) -> void:
	site = s
	name = "Supports"
	site.net.register_op("post", _post_op)
	site.net.register_event("sup", func(a: Array): _sound(String(a[0]), a[1]))

func _grid() -> DigSiteGrid:
	return site.terrain.grid

## What the hammer's right click would put up where it hit (p, normal n): [x, z, y0, y1] in cells, or a reason why not
func plan(p: Vector3, n: Vector3):
	var tr: DsTerrain = site.terrain
	var g := _grid()
	var c := tr.cell_of(p - n * 0.06)          # (the block it hit)
	var x := c.x - (1 if fposmod(p.x - tr.origin.x, DsTerrain.CELL) < DsTerrain.CELL * 0.5 else 0)
	var z := c.z - (1 if fposmod(p.z - tr.origin.z, DsTerrain.CELL) < DsTerrain.CELL * 0.5 else 0)
	var y0 := 0
	var y1 := 0
	if n.y > 0.5:
		y0 = c.y + 1                            # (the floor: up from it to the roof)
		y1 = y0
		while y1 < y0 + MOST_UP and _air_box(g, x, y1, z):
			y1 += 1
		if y1 >= y0 + MOST_UP or y1 >= g.get_h():
			return "Nothing over it to hold up"
	elif n.y < -0.5:
		y1 = c.y                                # (the roof: down from it to the floor)
		y0 = y1 - 1
		while y0 > y1 - MOST_UP and _air_box(g, x, y0, z):
			y0 -= 1
		y0 += 1
		if y0 <= y1 - MOST_UP:
			return "Too far down to the floor"
	else:
		return "Aim at the floor or the roof"
	if y1 - y0 < 4:
		return "Too low for a post"
	for yy in range(y0, y1):
		if not _air_box(g, x, yy, z):
			return "Something's in the way"
	return [x, z, y0, y1]

func _air_box(g: DigSiteGrid, x: int, y: int, z: int) -> bool:
	for dz in POST:
		for dx in POST:
			if g.get_cell(x + dx, y, z + dz) & DsMats.MASK != 0:
				return false
	return true

## (the hammer) a post put up where it hit, out of the backpack: true if it went up
func place(p: Vector3, n: Vector3) -> bool:
	var a = site.arena
	var concrete: bool = a.inv.count("prop_concrete") > 0 and (a.inv.count("prop_wood") == 0 or _depth_at(p) > WOOD_OK)
	var item := "prop_concrete" if concrete else "prop_wood"
	if a.inv.count(item) <= 0:
		a.say("No props in your backpack: the site office sells them", 2.0)
		return false
	var pl = plan(p, n)
	if pl is String:
		a.say(pl, 1.5)
		return false
	a.inv.remove(item, 1)
	site.net.act("post", [pl[0], pl[1], pl[2], pl[3], DsMats.CONCRETE if concrete else DsMats.WOOD])
	a.sound.play("hammer_thud_0", p, -2.0, 1.1)
	site.net.event("sup", ["hammer_thud_0", p])
	if not concrete and _depth_at(p) > WOOD_OK:
		a.say("A wooden prop this deep won't hold for long: concrete down here", 2.5)
	return true

## The ground over a point: how far under the ground's top (m)
func _depth_at(p: Vector3) -> float:
	return site.terrain.top_at(p.x, p.z) - p.y

# the action (both games; the host keeps it in its list)
func _post_op(a: Array, again: bool) -> int:
	var g := _grid()
	var x := int(a[0])
	var z := int(a[1])
	var y0 := int(a[2])
	var y1 := int(a[3])
	var m := int(a[4])
	var n := 0
	for y in range(y0, y1):
		for dz in POST:
			for dx in POST:
				if g.get_cell(x + dx, y, z + dz) & DsMats.MASK == 0:
					g.set_cell(x + dx, y, z + dz, m)
					n += 1
	if not again and site.net.runs():
		posts.append({"x": x, "z": z, "y0": y0, "y1": y1, "m": m, "stress": 0.0, "groan_t": 0.0})
		added += 1
	return n

## A post's top in the world, and how deep it is (the ground over it from the top of the site's column)
func _post_top(pp: Dictionary) -> Vector3:
	var tr: DsTerrain = site.terrain
	return tr.centre_of(Vector3i(int(pp.x) + 1, int(pp.y1), int(pp.z) + 1)) - Vector3(0.0625, 0.0625, 0.0625)

func depth_of(pp: Dictionary) -> float:
	var g := _grid()
	return float(g.column_top(int(pp.x), int(pp.z)) - int(pp.y1)) * DsTerrain.CELL

func _process(dt: float) -> void:
	if not site.active or not site.net.runs() or posts.is_empty():
		return
	_t += dt
	if _t < CHECK_T:
		return
	var step := _t
	_t = 0.0
	var g := _grid()
	for i in range(posts.size() - 1, -1, -1):
		var pp: Dictionary = posts[i]
		# gone (dug out, fallen): off the list
		if g.get_cell(int(pp.x), int(pp.y0), int(pp.z)) & DsMats.MASK != int(pp.m):
			posts.remove_at(i)
			continue
		var d := depth_of(pp)
		var at := _post_top(pp)
		if int(pp.m) == DsMats.CONCRETE:
			if d <= CONCRETE_MAX:
				continue
		elif d <= WOOD_OK:
			continue
		# too much weight: it groans, cracks, gives way
		var k := clampf((d - WOOD_OK) / (WOOD_MAX - WOOD_OK), 0.0, 1.0)
		var life := lerpf(WOOD_LIFE, 8.0, k)
		pp.stress = float(pp.stress) + step * stress_k / life
		pp.groan_t = float(pp.groan_t) - step
		if float(pp.groan_t) <= 0.0:
			pp.groan_t = randf_range(2.0, 4.0) * (1.0 - 0.6 * float(pp.stress))
			var snd := "gate_creak" if float(pp.stress) < 0.6 else "mine_groan"
			_sound(snd, at)
			site.net.event("sup", [snd, at])
			if float(pp.stress) > 0.6 and site.arena.player.global_position.distance_to(at) < 10.0:
				site.arena.say("The prop's cracking! Too much weight this deep: concrete", 2.0)
		if float(pp.stress) >= 1.0:
			_break(pp)
			posts.remove_at(i)

# a post giving way: its blocks drop loose (splinters and rubble), the roof it held on its own again
func _break(pp: Dictionary) -> void:
	var g := _grid()
	for y in range(int(pp.y0), int(pp.y1)):
		for dz in POST:
			for dx in POST:
				var c := g.get_cell(int(pp.x) + dx, y, int(pp.z) + dz)
				if c & DsMats.MASK == int(pp.m):
					g.set_cell(int(pp.x) + dx, y, int(pp.z) + dz, c | DsMats.LOOSE)
	broke += 1
	var at := _post_top(pp)
	_sound("hammer_thud_1", at)
	_sound("mine_crumble", at)
	site.net.event("sup", ["mine_crumble", at])
	if site.arena.player.global_position.distance_to(at) < 12.0:
		site.arena.say("A prop gave way!", 2.0)

func _sound(snd: String, at: Vector3) -> void:
	heard += 1
	if site.active:
		site.arena.sound.play(snd, at, -2.0, randf_range(0.85, 1.1))

func save_data() -> Array:
	return posts.duplicate(true)

func load_data(d) -> void:
	posts = d.duplicate(true) if typeof(d) == TYPE_ARRAY else []
