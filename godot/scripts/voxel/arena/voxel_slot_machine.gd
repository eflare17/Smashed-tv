class_name VoxelSlotMachine
extends Node3D
## The slot machine (the owner, 23 Oct: "bringing the slot machine back ... an old school one that you have to pull the
## lever and the dials spin"; "a bit of a beat up looking machine, maybe some of the lights flicker"; "a spider in the
## machine that sometimes comes down or falls onto one of the spinning wheels and gets flung around"). Against the arena's
## north wall: a 1950s one-armed bandit in cubes, on its own stand, left there for years. Built here, not from a file:
## - the cabinet: candy-apple red faded to brick, chipped at every edge to grey metal, rust streaking down from the
##   screws, a dent and four bullet holes in its left side, old blood up it, flames painted up both sides; cream front
##   panels; a scuffed kick plate ("KICK HERE"); a missing foot, so it leans, a folded bit of cardboard under the corner;
## - dull, pitted chrome (the trim, one strip bent out at the top; the window frame; the coin slot, taped on; the payout
##   tray, a wad of gum in it; the lever's hub), a tarnished brass pay table hanging crooked;
## - the marquee: an arch, cracked, "LUCKY SPUD" lit in gold (the K and the U dead, now and then flickering back on),
##   a crowned potato half its crown peeled off; twenty bulbs round the arch, a third dead or gone, one loose and
##   always flickering; now and then the whole lot dims, cuts out, buzzes back;
## - three real drums behind cracked, smudged glass (cherries, bell, BAR, 7, spud, chicken, skull, THE BUTCHER), lit
##   from inside (the right one's light dying), a faded win line, a WIN lamp with "BROKE" on a bit of tape;
## - the lever: a bent chrome arm, a chipped red ball with tape round it; pulled, it swings down, springs back with a
##   wobble (sometimes sticks halfway, then clunks home);
## - a spider living in the top of the window: now and then it lets itself down on a thread over a reel, dangles, goes
##   back up; if the reels are going while it's down (or it just drops) it lands on a drum, rides round it and is
##   flung off, bounces about behind the glass, lies there a moment and climbs back up.
## E in front pulls it (the prizes and the price come next). Owned by the voxel session.

const VM := 0.025               # metres a cube
const AT := Vector3(7.0, 0.0, -21.15)   # where it stands (its back to the north wall, facing south, into the arena; right of the chests)
const SYMS := ["cherry", "bell", "bar", "seven", "spud", "chicken", "skull", "butcher"]
const REEL_R := 5.8 * VM        # the drums' radius ...
const REEL_W := 6.0 * VM        # ... and width
const REEL_X := [-8.0, 0.0, 8.0]   # their middles across (cubes)
const REEL_Y := 62.0            # ... up
const REEL_Z := 5.0             # ... in
const SPIN_V := 24.0            # radians a second at full spin
const STOPS := [1.0, 1.45, 1.9]     # seconds after the pull each reel starts stopping
const DEAD_BULBS := [2, 5, 9, 13, 16, 18]
const GONE_BULBS := [5, 13, 18]  # (no bulb at all: an empty socket)
const LOOSE_BULB := 11
const LETTERS := ["L", "U", "C", "K", "Y", "S", "P", "U", "D"]
const DEAD_LETTERS := [3, 7]    # K and the U in SPUD

var arena: Node3D
var _t := 0.0
var _root: Node3D               # everything that leans with it
var _reels: Array[Node3D] = []
var _reel_phi := [0.0, 0.0, 0.0]
var _reel_v := [0.0, 0.0, 0.0]
var _reel_stop := [{}, {}, {}]  # a stopping reel: {from, to, t}
var _result := [0, 0, 0]
var _mat_reel: Array[StandardMaterial3D] = []
var _tex_sharp: ImageTexture
var _tex_blur: ImageTexture
var _lever: Node3D
var _lever_t := -1.0            # seconds into a pull (-1: at rest)
var _lever_stick := false
var spinning := false
var _spin_t := 0.0
var _bulbs: Array[MeshInstance3D] = []
var _bulb_on: StandardMaterial3D
var _bulb_pink: StandardMaterial3D
var _bulb_off: StandardMaterial3D
var _bulb_red: StandardMaterial3D
var _sp_shake := false          # the pull's jolt: it drops onto a drum as they start
var _letters: Array[MeshInstance3D] = []
var _letter_on: StandardMaterial3D
var _letter_off: StandardMaterial3D
var _face_mat: StandardMaterial3D
var _win_mat: StandardMaterial3D
var _glow: OmniLight3D
var _chase := 0.0
var _flicker := 0.0             # seconds left of a flicker fit (the whole marquee)
var _flicker_next := 4.0
var _win_t := 0.0
var _bust_t := 0.0
var near := false               # someone stood at it (the bulbs chase faster)
var pulls := 0
# the spider
var _sp: Node3D
var _sp_thread: MeshInstance3D
var _sp_legs: Array[Node3D] = []
var _sp_state := "hide"
var _sp_t := 6.0
var _sp_p := Vector3.ZERO       # (machine space, metres)
var _sp_v := Vector3.ZERO
var _sp_reel := 1
var _sp_a := 0.0                # riding: its angle on the drum
var _sp_spin := Vector3.ZERO
var _sp_top := 0.0
var spider_rides := 0           # (tests) times it's been flung off a reel

func setup(arena_: Node3D) -> void:
	arena = arena_
	position = AT
	_root = Node3D.new()
	add_child(_root)
	_root.rotation = Vector3(0.0, 0.0, deg_to_rad(-1.3))     # (a foot missing: it leans)
	_build()

# ---------------------------------------------------------------- the grids

class G:
	var s: Vector3i
	var o: Vector3i             # (the lowest cube's place, in cubes)
	var c: PackedInt32Array
	func _init(size: Vector3i, origin: Vector3i) -> void:
		s = size
		o = origin
		c.resize(s.x * s.y * s.z)
	func i(x: int, y: int, z: int) -> int:
		var lx := x - o.x
		var ly := y - o.y
		var lz := z - o.z
		if lx < 0 or ly < 0 or lz < 0 or lx >= s.x or ly >= s.y or lz >= s.z:
			return -1
		return lx + s.x * (ly + s.y * lz)
	func put(x: int, y: int, z: int, col: Color) -> void:
		var k := i(x, y, z)
		if k >= 0:
			c[k] = ((col.r8 << 16) | (col.g8 << 8) | col.b8) + 1
	func clear(x: int, y: int, z: int) -> void:
		var k := i(x, y, z)
		if k >= 0:
			c[k] = 0
	func has(x: int, y: int, z: int) -> bool:
		var k := i(x, y, z)
		return k >= 0 and c[k] != 0
	func get_col(x: int, y: int, z: int) -> Color:
		var k := i(x, y, z)
		if k < 0 or c[k] == 0:
			return Color.BLACK
		var v := c[k] - 1
		return Color8((v >> 16) & 255, (v >> 8) & 255, v & 255)
	func box(a: Vector3i, b: Vector3i, col: Color) -> void:
		for z in range(a.z, b.z + 1):
			for y in range(a.y, b.y + 1):
				for x in range(a.x, b.x + 1):
					put(x, y, z, col)
	func cut(a: Vector3i, b: Vector3i) -> void:
		for z in range(a.z, b.z + 1):
			for y in range(a.y, b.y + 1):
				for x in range(a.x, b.x + 1):
					clear(x, y, z)
	func exposed(x: int, y: int, z: int) -> int:
		var n := 0
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if not has(x + d.x, y + d.y, z + d.z):
				n += 1
		return n
	func grid() -> Dictionary:
		return {"size": s, "cells": c}

var _rng := RandomNumberGenerator.new()

func _vary(c: Color, amt: float) -> Color:
	var v := _rng.randf_range(-amt, amt)
	return Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1))

func _mesh(g: G, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelBody.array_mesh(VoxMesher.mesh(g.grid(), Vector3(g.o), VM))
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _mat(rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m

func _emit(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

const RED := Color8(150, 44, 38)
const RED_KEPT := Color8(188, 40, 38)
const METAL := Color8(118, 118, 124)
const RUST := Color8(126, 66, 34)
const CREAM := Color8(214, 198, 160)
const BLACK := Color8(28, 28, 32)
const CHROME := Color8(176, 178, 184)
const BLOOD := Color8(88, 12, 14)

func _build() -> void:
	_rng.seed = 1950
	var body := G.new(Vector3i(34, 74, 30), Vector3i(-17, 0, -13))
	var chrome := G.new(Vector3i(40, 76, 34), Vector3i(-19, 0, -14))
	# the stand: black steel, a chrome foot ring (a foot missing at the front right)
	body.box(Vector3i(-10, 2, -8), Vector3i(10, 29, 8), BLACK)
	chrome.box(Vector3i(-12, 0, -10), Vector3i(12, 1, 10), CHROME)
	chrome.cut(Vector3i(9, 0, 7), Vector3i(12, 1, 10))
	# the kick plate on the stand's front: bare, dented metal
	body.box(Vector3i(-9, 3, 8), Vector3i(9, 9, 8), METAL)
	for k in 5:
		body.clear(_rng.randi_range(-8, 8), _rng.randi_range(4, 8), 8)
	# the cabinet
	body.box(Vector3i(-15, 30, -12), Vector3i(15, 71, 12), RED)
	# the reel window: a recess through the front, dark inside
	body.cut(Vector3i(-12, 56, -1), Vector3i(12, 68, 12))
	body.box(Vector3i(-12, 56, -2), Vector3i(12, 68, -2), Color8(20, 18, 18))
	# the cream front panel, the kept-red band under the trim
	body.box(Vector3i(-13, 34, 12), Vector3i(13, 53, 12), CREAM)
	body.box(Vector3i(-15, 69, -12), Vector3i(15, 71, 12), RED_KEPT)
	# the marquee: an arch on top, set back a little
	for x in range(-15, 16):
		var top := 72 + int(round(17.0 * sqrt(maxf(0.0, 1.0 - pow(x / 15.5, 2.0)))))
		for y in range(72, top + 1):
			for z in range(-10, 6):
				body.put(x, y, z, RED)
	# its face: the glowing panel (its own mesh), so the shell's front is cut back
	_paint_wear(body)
	for z in range(-2, 13):                      # (the window's inside: dark, not the outside's paint)
		for y in range(55, 70):
			for x in range(-13, 14):
				if body.has(x, y, z) and (x <= -12 or x >= 12 or y <= 56 or y >= 68 or z <= -1) and absi(x) <= 13 and y >= 55 and y <= 69 and z < 12:
					body.put(x, y, z, _vary(Color8(30, 26, 26), 0.02))
	_paint_flames(body)
	_side_damage(body)
	var wood := _mat(0.9)
	_mesh(body, wood, _root)
	# chrome: the band, the window frame and dividers, the coin slot plate, the tray, the lever's hub, the trim
	chrome.box(Vector3i(-16, 71, -13), Vector3i(16, 72, 13), CHROME)
	chrome.box(Vector3i(-13, 55, 12), Vector3i(13, 55, 13), CHROME)
	chrome.box(Vector3i(-13, 69, 12), Vector3i(13, 69, 13), CHROME)
	chrome.box(Vector3i(-13, 55, 12), Vector3i(-13, 69, 13), CHROME)
	chrome.box(Vector3i(13, 55, 12), Vector3i(13, 69, 13), CHROME)
	for dx in [-4, 4]:
		chrome.box(Vector3i(dx, 56, 12), Vector3i(dx, 68, 12), CHROME)
	chrome.box(Vector3i(6, 38, 13), Vector3i(10, 42, 13), CHROME)       # the coin slot plate
	chrome.box(Vector3i(-8, 30, 13), Vector3i(8, 30, 17), CHROME)       # the tray: its floor ...
	chrome.box(Vector3i(-8, 31, 17), Vector3i(8, 34, 17), CHROME)       # ... front lip
	chrome.box(Vector3i(-8, 31, 13), Vector3i(-8, 34, 17), CHROME)
	chrome.box(Vector3i(8, 31, 13), Vector3i(8, 34, 17), CHROME)
	for y in range(55, 62):                      # the lever's hub: a round boss
		for z in range(-3, 4):
			if Vector2(y - 58, z).length() <= 3.2:
				chrome.box(Vector3i(16, y, z), Vector3i(17, y, z), CHROME)
	chrome.box(Vector3i(-16, 30, 13), Vector3i(16, 30, 13), CHROME)      # the bottom trim
	# the top trim along the marquee's foot, its right end bent out
	for x in range(-15, 12):
		chrome.put(x, 73, 6, CHROME)
	for k in 4:
		chrome.put(12 + k, 73 + k / 2, 7 + k, CHROME)
	_paint_chrome(chrome)
	_mesh(chrome, _mat(0.42, 0.75), _root)
	_coin_slot()
	_tray_bits()
	_pay_plate()
	_marquee()
	_reels_build()
	_glass()
	_win_lamp()
	_lever_build()
	_labels()
	_floor_bits()
	_spider_build()
	# the light it throws (warm, flickering with the marquee) and a collision box
	_glow = OmniLight3D.new()
	_glow.position = Vector3(0, 2.35, 1.3)
	_glow.light_color = Color(1.0, 0.72, 0.5)
	_glow.light_energy = 0.9
	_glow.omni_range = 4.0
	_glow.shadow_enabled = false
	_root.add_child(_glow)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.8, 2.25, 0.7)
	cs.shape = bx
	cs.position = Vector3(0, 1.12, 0)
	sb.add_child(cs)
	add_child(sb)

# chips at the edges (grey metal, rust), rust streaks under the screws, grime
func _paint_wear(g: G) -> void:
	for z in range(g.o.z, g.o.z + g.s.z):
		for y in range(g.o.y, g.o.y + g.s.y):
			for x in range(g.o.x, g.o.x + g.s.x):
				if not g.has(x, y, z):
					continue
				var col := g.get_col(x, y, z)
				var e := g.exposed(x, y, z)
				if e == 0:
					continue
				if e >= 2 and _rng.randf() < 0.32:
					col = METAL if _rng.randf() < 0.55 else RUST
				elif _rng.randf() < 0.04:
					col = col.darkened(0.35)          # a scratch, a stain
				g.put(x, y, z, _vary(col, 0.035))
	# rust streaks running down the front from the screws by the window's corners and the marquee's foot
	for sx in [-14, 14, -12, 12]:
		var y := 69 if absi(sx) == 12 else 54
		var x: int = sx
		while y > 31:
			if g.has(x, y, 12) and _rng.randf() < 0.85:
				g.put(x, y, 12, RUST.lerp(g.get_col(x, y, 12), clampf((69 - y) / 40.0, 0.0, 0.8)))
			y -= 1
			if _rng.randf() < 0.15:
				x += _rng.randi_range(-1, 1)

# flames up both sides, red at the foot to gold at the tips (faded)
func _paint_flames(g: G) -> void:
	for side in [-15, 15]:
		for z in range(-12, 13):
			var tip := 13.0 + 9.0 * absf(sin(z * 0.42 + 0.7 * side)) + 3.0 * sin(z * 1.3)
			for y in range(30, 70):
				var h := float(y - 30)
				if h < tip and g.has(side, y, z):
					var k := h / tip
					var col := Color8(196, 60, 30).lerp(Color8(222, 170, 60), k)
					if _rng.randf() < 0.18:
						col = col.darkened(0.3)           # (scratched)
					g.put(side, y, z, _vary(col.lerp(Color8(150, 110, 90), 0.25), 0.03))

# the left side: a dent, four bullet holes, old blood (and on the stand)
func _side_damage(g: G) -> void:
	var dc := Vector2(50, 2)
	for z in range(-12, 13):
		for y in range(30, 72):
			var d := Vector2(y, z).distance_to(dc)
			if d < 6.0:
				g.clear(-15, y, z)
				if d < 3.2:
					g.clear(-14, y, z)
				var x := -13 if d < 3.2 else -14
				if g.has(x, y, z):
					g.put(x, y, z, METAL.darkened(0.2) if _rng.randf() < 0.6 else RUST)
	for h in [Vector2(40, -6), Vector2(44, 7), Vector2(60, -8), Vector2(36, 4)]:
		var y := int(h.x)
		var z := int(h.y)
		g.clear(-15, y, z)
		g.clear(-14, y, z)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if g.has(-15, y + d.x, z + d.y):
				g.put(-15, y + d.x, z + d.y, Color8(196, 196, 200))
	for k in 6:
		var y := _rng.randi_range(34, 62)
		var z := _rng.randi_range(-10, 10)
		for j in _rng.randi_range(4, 9):
			var yy := y + _rng.randi_range(-2, 2)
			var zz := z + _rng.randi_range(-2, 2)
			if g.has(-15, yy, zz):
				g.put(-15, yy, zz, _vary(BLOOD, 0.04))
		for drip in _rng.randi_range(3, 8):
			if g.has(-15, y - drip, z):
				g.put(-15, y - drip, z, BLOOD)
	for k in 4:
		var y := _rng.randi_range(6, 26)
		var x := _rng.randi_range(-10, -2)
		for j in 5:
			if g.has(x + _rng.randi_range(-1, 1), y + _rng.randi_range(-1, 1), 8):
				g.put(x + _rng.randi_range(-1, 1), y + _rng.randi_range(-1, 1), 8, BLOOD)

func _paint_chrome(g: G) -> void:
	for z in range(g.o.z, g.o.z + g.s.z):
		for y in range(g.o.y, g.o.y + g.s.y):
			for x in range(g.o.x, g.o.x + g.s.x):
				if not g.has(x, y, z):
					continue
				var col := CHROME
				var r := _rng.randf()
				if r < 0.08:
					col = RUST
				elif r < 0.22:
					col = CHROME.darkened(0.3)           # (pitted, cloudy)
				g.put(x, y, z, _vary(col, 0.04))

func _coin_slot() -> void:
	var g := G.new(Vector3i(12, 8, 3), Vector3i(4, 36, 13))
	g.box(Vector3i(7, 39, 14), Vector3i(9, 41, 14), BLACK)              # the slot
	g.box(Vector3i(4, 40, 14), Vector3i(11, 40, 14), Color8(150, 150, 146))   # a strip of duct tape across ...
	g.box(Vector3i(4, 41, 14), Vector3i(5, 41, 14), Color8(140, 140, 136))
	g.box(Vector3i(10, 41, 14), Vector3i(11, 41, 14), Color8(140, 140, 136))
	_mesh(g, _mat(0.9), _root)

func _tray_bits() -> void:
	var g := G.new(Vector3i(16, 3, 4), Vector3i(-7, 31, 13))
	var gold := Color8(214, 176, 70)
	for p in [Vector3i(-4, 31, 14), Vector3i(-3, 31, 15), Vector3i(3, 31, 14)]:
		g.put(p.x, p.y, p.z, gold)
		g.put(p.x + 1, p.y, p.z, gold.darkened(0.15))
	g.box(Vector3i(5, 31, 15), Vector3i(6, 31, 16), Color8(232, 120, 160))     # gum
	g.put(5, 32, 15, Color8(220, 110, 150))
	_mesh(g, _mat(0.5, 0.3), _root)

func _pay_plate() -> void:
	var g := G.new(Vector3i(21, 8, 1), Vector3i(-10, 0, 0))
	var brass := Color8(150, 120, 60)
	for y in 8:
		for x in range(-10, 11):
			var col := brass.lerp(Color8(80, 100, 70), _rng.randf() * 0.5)     # (tarnished green-brown)
			if (y == 2 or y == 4 or y == 6) and absi(x) < 8 and x % 3 != 0:
				col = col.darkened(0.45)          # the engraved rows of the pay table
			g.put(x, y, 0, col)
	var n := Node3D.new()
	n.position = Vector3(0, 44 * VM, 13 * VM)
	n.rotation = Vector3(0, 0, deg_to_rad(4.0))      # (a screw missing: it hangs crooked)
	_root.add_child(n)
	_mesh(g, _mat(0.5, 0.6), n)

# the marquee's face (glowing, cracked, the crowned potato) and its letters and bulbs
func _marquee() -> void:
	var g := G.new(Vector3i(30, 18, 1), Vector3i(-14, 73, 6))
	for x in range(-14, 15):
		var top := 73 + int(floor(16.0 * sqrt(maxf(0.0, 1.0 - pow(x / 14.5, 2.0)))))
		for y in range(73, top + 1):
			g.put(x, y, 6, _vary(Color8(226, 206, 150), 0.03))
	# the crack, top left to the middle
	var cx := -10.0
	for y in range(89, 73, -1):
		cx += _rng.randf_range(0.2, 1.1)
		if g.has(int(cx), y, 6):
			g.put(int(cx), y, 6, Color8(90, 80, 60))
	# the potato with its crown (the crown's left half peeled off)
	var pot := ["..YYYYY..", ".Y.Y.Y.Y.", "..BBBBB..", ".BBBBBBB.", "BBKBBBKBB", "BBBBBBBBB", ".BBKKKBB.", "..BBBBB.."]
	for r in pot.size():
		var row: String = pot[r]
		for k in row.length():
			var ch := row[k]
			var x := k - 4
			var y := 88 - r
			match ch:
				"Y":
					g.put(x, y, 6, Color8(214, 180, 60) if x >= 0 else Color8(196, 180, 140))
				"B":
					g.put(x, y, 6, Color8(156, 104, 58))
				"K":
					g.put(x, y, 6, Color8(40, 28, 20))
	_face_mat = _mat(0.8)
	_face_mat.emission_enabled = true
	_face_mat.emission = Color(1.0, 0.86, 0.6)
	_face_mat.emission_energy_multiplier = 0.16
	_mesh(g, _face_mat, _root)
	# the letters: LUCKY over SPUD, gold, each its own (two of them dead)
	_letter_on = _emit(Color(1.0, 0.62, 0.12), 2.2)
	_letter_off = _emit(Color(0.32, 0.25, 0.12), 0.05)
	var font := {"L": ["X..", "X..", "X..", "X..", "XXX"], "U": ["X.X", "X.X", "X.X", "X.X", "XXX"], "C": ["XXX", "X..", "X..", "X..", "XXX"],
		"K": ["X.X", "XX.", "X..", "XX.", "X.X"], "Y": ["X.X", "X.X", ".X.", ".X.", ".X."], "S": ["XXX", "X..", "XXX", "..X", "XXX"],
		"P": ["XXX", "X.X", "XXX", "X..", "X.."], "D": ["XX.", "X.X", "X.X", "X.X", "XX."]}
	for i in LETTERS.size():
		var line := 0 if i < 5 else 1
		var col_i := i if i < 5 else i - 5
		var x0 := (-9 + col_i * 4) if line == 0 else (-7 + col_i * 4)
		var y0 := 83 if line == 0 else 77
		var lg := G.new(Vector3i(3, 5, 1), Vector3i(x0, y0 - 4, 7))
		var rows: Array = font[LETTERS[i]]
		for r in 5:
			for k in 3:
				if String(rows[r])[k] == "X":
					lg.put(x0 + k, y0 - r, 7, Color.WHITE)
		var mi := _mesh(lg, _letter_off if i in DEAD_LETTERS else _letter_on, _root)
		_letters.append(mi)
	# the bulbs round the arch
	_bulb_on = _emit(Color(1.0, 0.7, 0.25), 3.5)
	_bulb_pink = _emit(Color(1.0, 0.45, 0.85), 3.5)
	_bulb_off = _emit(Color(0.5, 0.46, 0.4), 0.0)
	_bulb_red = _emit(Color(0.6, 0.06, 0.04), 1.2)
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 1.3, 1.0) * VM
	var socket := BoxMesh.new()
	socket.size = Vector3(0.9, 0.9, 0.5) * VM
	for i in 20:
		var a := PI * float(i) / 19.0
		var mi := MeshInstance3D.new()
		mi.mesh = socket if i in GONE_BULBS else bm
		mi.position = Vector3(15.6 * cos(a), 72.5 + 17.6 * sin(a), 6.7) * VM
		mi.material_override = _bulb_off
		_root.add_child(mi)
		_bulbs.append(mi)

# ---------------------------------------------------------------- the reels

func _sym_art(name: String) -> Array:
	# 14 x 14, a letter a colour: . cream, r red, g green, y gold, k black, w white, b brown, o orange, c crimson, p pink
	match name:
		"cherry":
			return ["..............", ".........gg...", "........g.....", ".......g......", "......g.g.....", ".....g...g....",
				"....g.....g...", "...rrr...rrr..", "..rrrrr.rrrrr.", "..rrwrr.rrwrr.", "..rrrrr.rrrrr.", "...rrr...rrr..", "..............", ".............."]
		"bell":
			return ["..............", "......yy......", ".....yyyy.....", "....yyyyyy....", "....ywyyyy....", "...yywyyyyy...",
				"...yyyyyyyy...", "...yyyyyyyy...", "..yyyyyyyyyy..", "..yyyyyyyyyy..", ".yyyyyyyyyyyy.", "......yy......", "..............", ".............."]
		"bar":
			return ["..............", "..............", "..............", ".kkkkkkkkkkkk.", ".kkkkkkkkkkkk.", ".kwwkkwkkwwkk.",
				".kwkwkwkwkwkk.", ".kwwkwwwkwwkk.", ".kwkwkwkwkwkk.", ".kwwkwkwkwkwk.", ".kkkkkkkkkkkk.", ".kkkkkkkkkkkk.", "..............", ".............."]
		"seven":
			return ["..............", "..yyyyyyyyyy..", "..yrrrrrrrry..", "..yrrrrrrrry..", "..yyyyyyrry...", ".......yrry...",
				"......yrry....", "......yrry....", ".....yrry.....", ".....yrry.....", "....yrry......", "....yyyy......", "..............", ".............."]
		"spud":
			return ["..............", "..............", "....bbbbb.....", "...bbbbbbbb...", "..bbbbbbbbbb..", "..bkbbbbkbbb..",
				".bbbbbbbbbbbb.", ".bbbbbbbbbbbb.", ".bbbkkkkbbbbb.", "..bbbbbbbbbb..", "...bbbbbbbb...", ".....bbbb.....", "..............", ".............."]
		"chicken":
			return ["..............", ".....rrr......", "....rrrr......", "....wwww......", "...wwwwww.....", "...wkwwwwoo...",
				"...wwwwwoooo..", "...wwwwwr.....", "....wwwwr.....", "....wwww......", ".....ww.......", "..............", "..............", ".............."]
		"skull":
			return ["..............", ".....wwww.....", "....wwwwww....", "...wwwwwwww...", "...wkkwwkkw...", "...wkkwwkkw...",
				"...wwwwwwww...", "....wwkkww....", "....wwwwww....", ".....wkwk.....", ".....wwww.....", "..............", "..............", ".............."]
		"butcher":
			return ["..............", "....cccccc....", "...cccccccc...", "...cwwcccwwc..", "...cwkcccwkc..", "...cccccccc...",
				"...ccppppcc...", "...cpkkkkpc...", "...cckkkkcc...", "....cccccc....", ".....cccc.....", "..............", "..............", ".............."]
	return []

func _strip_image(blur: bool) -> Image:
	var cols := {".": Color8(232, 220, 186), "r": Color8(200, 30, 36), "g": Color8(40, 140, 50), "y": Color8(230, 186, 50),
		"k": Color8(24, 22, 22), "w": Color8(246, 244, 236), "b": Color8(150, 100, 56), "o": Color8(232, 140, 30),
		"c": Color8(150, 26, 30), "p": Color8(220, 140, 140)}
	var img := Image.create(16 * SYMS.size(), 16, false, Image.FORMAT_RGB8)
	img.fill(cols["."])
	for s in SYMS.size():
		var art: Array = _sym_art(SYMS[s])
		for r in art.size():
			var row: String = art[r]
			for k in row.length():
				# (round the drum, u (x here) goes up the symbol; across it, v (y here) goes right to left)
				img.set_pixel(s * 16 + 14 - r, 14 - k, cols[row[k]])
		for y in 16:
			img.set_pixel(s * 16 + 15, y, Color8(200, 186, 150))     # a faint line between symbols
	if blur:
		var src := img.duplicate()
		for y in 16:
			for x in img.get_width():
				var acc := Color(0, 0, 0)
				for d in range(-6, 7):
					acc += src.get_pixel(posmod(x + d, img.get_width()), y)
				img.set_pixel(x, y, acc / 13.0)
	return img

# a faceted drum (its own mesh: angle 0 faces the front, u round it)
func _drum_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var hw := REEL_W * 0.5
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var p00 := Vector3(-hw, REEL_R * sin(a0), REEL_R * cos(a0))
		var p01 := Vector3(hw, REEL_R * sin(a0), REEL_R * cos(a0))
		var p10 := Vector3(-hw, REEL_R * sin(a1), REEL_R * cos(a1))
		var p11 := Vector3(hw, REEL_R * sin(a1), REEL_R * cos(a1))
		var nm := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		for v in [[p00, Vector2(u0, 1)], [p11, Vector2(u1, 0)], [p01, Vector2(u0, 0)], [p00, Vector2(u0, 1)], [p10, Vector2(u1, 1)], [p11, Vector2(u1, 0)]]:
			st.set_normal(nm)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	# the ends: flat, dark (a strip of the texture's line colour, so the one material does)
	for side in [-1.0, 1.0]:
		var c := Vector3(hw * side, 0, 0)
		for i in n:
			var a0 := TAU * float(i) / n
			var a1 := TAU * float(i + 1) / n
			var q0 := Vector3(hw * side, REEL_R * sin(a0), REEL_R * cos(a0))
			var q1 := Vector3(hw * side, REEL_R * sin(a1), REEL_R * cos(a1))
			var tri := [c, q0, q1] if side > 0.0 else [c, q1, q0]
			for q in tri:
				st.set_normal(Vector3(side, 0, 0))
				st.set_uv(Vector2(0.0, 0.5))
				st.add_vertex(q)
	st.generate_tangents()
	return st.commit()

func _reels_build() -> void:
	_tex_sharp = ImageTexture.create_from_image(_strip_image(false))
	_tex_blur = ImageTexture.create_from_image(_strip_image(true))
	var dm := _drum_mesh()
	for i in 3:
		var r := Node3D.new()
		r.position = Vector3(REEL_X[i], REEL_Y, REEL_Z) * VM
		_root.add_child(r)
		var mi := MeshInstance3D.new()
		mi.mesh = dm
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex_sharp
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 0.6
		m.emission_enabled = true
		m.emission_texture = _tex_sharp
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 0.12            # lit from inside
		mi.material_override = m
		r.add_child(mi)
		_mat_reel.append(m)
		_reels.append(r)
		_result[i] = [3, 0, 5][i]                # (a 7, cherries, a chicken: a near miss, as it was left)
		_reel_phi[i] = _sym_angle(_result[i])
		r.rotation.x = _reel_phi[i]

## The drum's turn that puts symbol k on the line.
static func _sym_angle(k: int) -> float:
	return TAU * (float(k) + 0.5) / float(SYMS.size())

func _glass() -> void:
	# the window's glass: faintly tinted, smudged, a spiderweb crack in the bottom left corner
	var img := Image.create(96, 52, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.85, 0.9, 0.06))
	for k in 40:
		var c := Vector2i(_rng.randi_range(0, 95), _rng.randi_range(0, 51))
		for j in 9:
			var p := c + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-2, 2))
			if p.x >= 0 and p.y >= 0 and p.x < 96 and p.y < 52:
				img.set_pixelv(p, Color(0.85, 0.85, 0.8, 0.16))        # smudges, fingerprints
	var hub := Vector2(10, 44)
	for ray in 7:
		var a := -PI * 0.5 + ray * 0.42 + _rng.randf_range(-0.1, 0.1)
		var p := hub
		for s in 26:
			p += Vector2(cos(a), sin(a)) * 1.0 + Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
			var q := Vector2i(p)
			if q.x >= 0 and q.y >= 0 and q.x < 96 and q.y < 52:
				img.set_pixelv(q, Color(1, 1, 1, 0.75))
	for ring in [5.0, 10.0]:
		for s in 30:
			var a := -PI * 0.5 + s * 0.1
			var q := Vector2i(hub + Vector2(cos(a), sin(a)) * ring)
			if q.x >= 0 and q.y >= 0 and q.x < 96 and q.y < 52:
				img.set_pixelv(q, Color(1, 1, 1, 0.55))
	var qm := QuadMesh.new()
	qm.size = Vector2(25 * VM, 13 * VM)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.metallic_specular = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mi.material_override = m
	mi.position = Vector3(0, 62 * VM, 12.4 * VM)
	_root.add_child(mi)
	# the win line, faded to orange, across the middle behind it
	var wl := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(24 * VM, 0.25 * VM, 0.2 * VM)
	wl.mesh = wb
	wl.material_override = _emit(Color(0.9, 0.42, 0.15), 0.7)
	wl.position = Vector3(0, 62 * VM, 11.6 * VM)
	_root.add_child(wl)

func _win_lamp() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(9 * VM, 2 * VM, 0.6 * VM)
	mi.mesh = bm
	_win_mat = _emit(Color(0.35, 0.08, 0.06), 0.1)
	mi.material_override = _win_mat
	mi.position = Vector3(0, 54 * VM, 13.35 * VM)
	_root.add_child(mi)
	var l := Label3D.new()
	l.text = "WIN"
	l.font_size = 22
	l.pixel_size = 0.0018
	l.modulate = Color(1, 0.85, 0.7)
	l.outline_size = 0
	l.position = Vector3(-0.05, 54 * VM, 13.7 * VM)
	_root.add_child(l)
	_tape(Vector3(0.05, 54.2 * VM, 13.75 * VM), Vector2(0.07, 0.03), "BROKE", Color(0.88, 0.86, 0.72), 4.0)

func _tape(at: Vector3, size: Vector2, text: String, col: Color, tilt: float, parent: Node3D = null, yaw := 0.0) -> void:
	var n := Node3D.new()
	n.position = at
	n.rotation = Vector3(0, yaw, deg_to_rad(tilt))
	(parent if parent else _root).add_child(n)
	var qm := QuadMesh.new()
	qm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mi.material_override = m
	n.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font_size = 24
	l.pixel_size = size.y / 40.0
	l.modulate = Color(0.12, 0.1, 0.1)
	l.outline_size = 0
	l.position = Vector3(0, 0, 0.002)
	n.add_child(l)

func _labels() -> void:
	_tape(Vector3(-0.17, 41 * VM, 13.2 * VM), Vector2(0.13, 0.04), "NO REFUNDS", Color(0.92, 0.9, 0.86), -3.0)
	_tape(Vector3(-0.16, 38.6 * VM, 13.3 * VM), Vector2(0.11, 0.035), "SERIOUSLY", Color(0.96, 0.9, 0.4), 6.0)
	var ins := Label3D.new()
	ins.text = "INSERT $5"
	ins.font_size = 20
	ins.pixel_size = 0.0016
	ins.modulate = Color(0.25, 0.2, 0.18)
	ins.outline_size = 0
	ins.position = Vector3(8 * VM, 43.6 * VM, 13.15 * VM)
	_root.add_child(ins)
	var kick := Label3D.new()
	kick.text = "KICK HERE"
	kick.font_size = 20
	kick.pixel_size = 0.0017
	kick.modulate = Color(0.75, 0.75, 0.78, 0.8)
	kick.outline_size = 0
	kick.position = Vector3(0, 6 * VM, 8.6 * VM)
	kick.rotation = Vector3(0, 0, deg_to_rad(-5))
	_root.add_child(kick)
	var pull := Label3D.new()
	pull.text = "PULL ↓"
	pull.font_size = 26
	pull.pixel_size = 0.002
	pull.modulate = Color(0.95, 0.85, 0.6, 0.55)
	pull.outline_size = 0
	pull.position = Vector3(15.6 * VM, 65 * VM, -2 * VM)
	pull.rotation = Vector3(0, PI * 0.5, 0)
	_root.add_child(pull)

func _lever_build() -> void:
	_lever = Node3D.new()
	_lever.position = Vector3(19.0, 58.0, 0.0) * VM
	_root.add_child(_lever)
	var g := G.new(Vector3i(8, 30, 8), Vector3i(-4, 0, -4))
	for y in range(0, 22):
		var bend := 1 if y > 14 else 0           # (bent a little near the top)
		for x in range(0, 2):
			for z in range(-1, 1):
				var col := CHROME if (y > 16 or _rng.randf() < 0.7) else CHROME.darkened(0.35)    # worn bright where it's held
				g.put(x + bend, y, z, _vary(col, 0.04))
	var ball := G.new(Vector3i(8, 8, 8), Vector3i(-3, 21, -4))
	for z in range(-4, 4):
		for y in range(21, 29):
			for x in range(-3, 5):
				var d := Vector3(x - 0.5, y - 24.5, z + 0.5).length()
				if d <= 3.5:
					var col := Color8(196, 30, 30)
					if y == 22 or y == 21:
						col = Color8(30, 30, 34)        # the tape round its foot
					elif x == 4 and y > 24 and _rng.randf() < 0.7:
						col = Color8(230, 200, 190)     # a chip off it
					elif x == 1 and y >= 24 and y <= 27:
						col = Color8(110, 16, 16)       # the crack
					ball.put(x, y, z, _vary(col, 0.03))
	_mesh(g, _mat(0.38, 0.75), _lever)
	_mesh(ball, _mat(0.25, 0.0), _lever)

func _floor_bits() -> void:
	var n := Node3D.new()                        # (on the floor, not leaning)
	add_child(n)
	for k in 5:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = 0.003
		cm.radial_segments = 8
		c.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color8(200, 160, 60)
		m.metallic = 0.8
		m.roughness = 0.35
		c.material_override = m
		c.position = Vector3(_rng.randf_range(-0.5, 0.5), 0.002, _rng.randf_range(0.3, 0.7))
		n.add_child(c)
	for k in 4:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.008, 0.008, 0.028)
		b.mesh = bm
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color(0.9, 0.88, 0.82) if k % 2 == 0 else Color(0.85, 0.55, 0.3)
		b.material_override = m2
		b.position = Vector3(_rng.randf_range(-0.6, 0.6), 0.004, _rng.randf_range(0.25, 0.8))
		b.rotation.y = _rng.randf() * TAU
		n.add_child(b)
	# the folded cardboard wedged under the corner with the missing foot
	var w := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.09, 0.012, 0.07)
	w.mesh = wm
	var cm2 := StandardMaterial3D.new()
	cm2.albedo_color = Color8(170, 130, 80)
	w.material_override = cm2
	w.position = Vector3(10.5 * VM, 0.006, 8.5 * VM)
	n.add_child(w)

# ---------------------------------------------------------------- the spider

func _spider_build() -> void:
	_sp = Node3D.new()
	_sp.scale = Vector3.ONE * 1.7               # (a big one: it's been living well in there)
	_root.add_child(_sp)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color8(26, 20, 18)
	dark.roughness = 0.6
	var ab := MeshInstance3D.new()
	var abm := BoxMesh.new()
	abm.size = Vector3(0.014, 0.012, 0.016)
	ab.mesh = abm
	ab.material_override = dark
	ab.position = Vector3(0, 0.002, -0.006)
	_sp.add_child(ab)
	var hd := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.009, 0.008, 0.009)
	hd.mesh = hm
	hd.material_override = dark
	hd.position = Vector3(0, 0.0, 0.006)
	_sp.add_child(hd)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color8(150, 30, 20)
	var dot := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.005, 0.002, 0.005)
	dot.mesh = dm
	dot.material_override = red
	dot.position = Vector3(0, 0.0085, -0.006)
	_sp.add_child(dot)
	var lm := BoxMesh.new()
	lm.size = Vector3(0.016, 0.0018, 0.0018)
	for i in 8:
		var side := -1.0 if i < 4 else 1.0
		var leg := Node3D.new()
		leg.position = Vector3(0.004 * side, 0.0, 0.004 - (i % 4) * 0.004)
		var seg := MeshInstance3D.new()
		seg.mesh = lm
		seg.material_override = dark
		seg.position = Vector3(0.008 * side, -0.003, 0)
		seg.rotation.z = -0.5 * side
		leg.add_child(seg)
		leg.rotation.y = side * ((i % 4) - 1.5) * 0.35
		_sp.add_child(leg)
		_sp_legs.append(leg)
	_sp_thread = MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.0007, 1.0, 0.0007)
	_sp_thread.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.9, 0.9, 0.95, 0.6)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sp_thread.material_override = tmat
	_root.add_child(_sp_thread)
	_sp_top = 68.4 * VM
	_sp_p = Vector3(REEL_X[1] * VM, _sp_top, 10.6 * VM)
	_sp.position = _sp_p
	_sp_thread.visible = false
	_sp.visible = false

const SP_Z := 10.6 * VM          # (between the drums' fronts and the glass)

func _spider_step(dt: float) -> void:
	var lo := Vector3(-12.2, 56.3, 6.0) * VM
	var hi := Vector3(12.2, 68.6, 11.8) * VM
	_sp_t -= dt
	var wiggle := 0.0
	match _sp_state:
		"hide":
			_sp.visible = false
			_sp_thread.visible = false
			if _sp_t <= 0.0:
				_sp_state = "down"
				_sp_reel = _rng.randi() % 3
				_sp_p = Vector3(REEL_X[_sp_reel] * VM + _rng.randf_range(-0.03, 0.03), _sp_top, SP_Z)
				_sp_t = _rng.randf_range(2.0, 4.5)
				_sp.rotation = Vector3(PI * 0.5, 0, 0)       # head down the thread
		"down", "dangle":
			_sp.visible = true
			_sp_thread.visible = true
			var floor_y := REEL_Y * VM + _rng.randf_range(-0.01, 0.01)
			if _sp_state == "down":
				_sp_p.y = maxf(floor_y + 0.02, _sp_p.y - 0.06 * dt)
				if _sp_p.y <= floor_y + 0.021:
					_sp_state = "dangle"
			_sp.position = _sp_p + Vector3(sin(_t * 2.1) * 0.002, sin(_t * 3.3) * 0.0015, 0)
			wiggle = 1.0
			if spinning and _rng.randf() < dt * 2.5:
				_sp_drop()                            # the drum's going: it's caught
			elif _sp_t <= 0.0:
				_sp_state = "up"
		"up":
			_sp_p.y = minf(_sp_top, _sp_p.y + 0.05 * dt)
			_sp.position = _sp_p
			wiggle = 0.5
			if _sp_p.y >= _sp_top - 0.001:
				_sp_state = "hide"
				_sp_t = _rng.randf_range(7.0, 16.0)
		"ride":
			# carried round on the drum, round and round, till it's flung off
			_sp_thread.visible = false
			var phi: float = _reels[_sp_reel].rotation.x
			var rel := _sp_a - phi
			var rr := REEL_R + 0.006
			_sp.position = Vector3(REEL_X[_sp_reel] * VM, REEL_Y * VM + rr * sin(rel), REEL_Z * VM + rr * cos(rel))
			_sp.rotation = Vector3(-rel, 0, 0)
			_sp.visible = cos(rel) > -0.2
			wiggle = 2.0
			if _sp_t <= 0.0 and cos(rel) > 0.3:
				# flung off along the drum's surface at its speed
				_sp_v = Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(0.7, 1.3), 0.4)
				_sp_p = _sp.position
				_sp_spin = Vector3(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
				_sp_state = "flung"
				_sp_t = 1.2
				spider_rides += 1
				if arena and arena.sound:
					arena.sound.play("peep_0", global_position + Vector3(0, 1.5, 0.3), -14.0, 2.2)
		"flung":
			# bouncing about behind the glass
			_sp.visible = true
			_sp_v.y -= 9.8 * dt
			_sp_p += _sp_v * dt
			for ax in 3:
				if _sp_p[ax] < lo[ax]:
					_sp_p[ax] = lo[ax]
					_sp_v[ax] = absf(_sp_v[ax]) * 0.45
				elif _sp_p[ax] > hi[ax]:
					_sp_p[ax] = hi[ax]
					_sp_v[ax] = -absf(_sp_v[ax]) * 0.45
			_sp.position = _sp_p
			_sp.rotation += _sp_spin * dt
			_sp_spin *= exp(-dt * 1.5)
			wiggle = 3.0
			if _sp_t <= 0.0 and _sp_p.y <= lo.y + 0.002:
				_sp_state = "dazed"
				_sp_t = 1.6
				_sp.rotation = Vector3(PI, 0, 0)          # on its back, legs up
		"dazed":
			_sp_p.y = lo.y + 0.004
			_sp.position = _sp_p
			wiggle = 0.6
			if _sp_t <= 0.0:
				_sp_state = "climb"
				_sp.rotation = Vector3(-PI * 0.5, 0, 0)
				_sp_p.x = hi.x - 0.004 if _sp_p.x > 0.0 else lo.x + 0.004
		"climb":
			_sp_p.y += 0.07 * dt
			_sp.position = _sp_p
			wiggle = 1.5
			if _sp_p.y >= _sp_top:
				_sp_state = "hide"
				_sp_t = _rng.randf_range(10.0, 18.0)
	# legs
	for i in _sp_legs.size():
		var leg := _sp_legs[i]
		leg.rotation.x = sin(_t * 18.0 * wiggle + i * 1.3) * 0.35 * minf(1.0, wiggle)
	# the thread from the top down to it
	if _sp_thread.visible:
		var len := maxf(0.001, _sp_top - _sp.position.y + 0.01)
		_sp_thread.scale = Vector3(1, len, 1)
		_sp_thread.position = Vector3(_sp.position.x, _sp.position.y + len * 0.5, _sp.position.z)

func _sp_drop() -> void:
	_sp_state = "ride"
	var phi: float = _reels[_sp_reel].rotation.x
	_sp_a = phi + 0.35                         # (just above the line, as it lands)
	_sp_t = _rng.randf_range(0.5, 1.0)

# ---------------------------------------------------------------- pulling, spinning

## The front's within reach of where you're looking.
func pick(eye: Vector3, dir: Vector3, reach := 2.2) -> bool:
	var box := AABB(global_position + Vector3(-0.5, 0.0, -0.4), Vector3(1.0, 2.3, 0.85))
	var hit = box.intersects_ray(eye, dir)
	return hit != null and (hit as Vector3).distance_to(eye) <= reach

func line() -> String:
	return "the reels are going..." if spinning else "E  pull the lever"

## The lever pulled: the reels spin (the outcome picked now; they land on it).
func pull() -> bool:
	if spinning or _lever_t >= 0.0:
		return false
	_lever_t = 0.0
	_lever_stick = _rng.randf() < 0.25
	pulls += 1
	for i in 3:
		_result[i] = _rng.randi() % SYMS.size()
	if _rng.randf() < 0.18:
		var k := _rng.randi() % SYMS.size()
		_result = [k, k, k]                    # (a win, now and then)
	if arena and arena.sound:
		arena.sound.play("gate_creak", global_position + Vector3(0.5, 1.5, 0.3), -4.0, 1.4)
	_sp_shake = _sp_state == "hide" and _rng.randf() < 0.5     # (the jolt may shake it down onto a drum)
	return true

func _start_spin() -> void:
	spinning = true
	_spin_t = 0.0
	for i in 3:
		_reel_v[i] = SPIN_V * _rng.randf_range(0.9, 1.1)
		_reel_stop[i] = {}
	if arena and arena.sound:
		arena.sound.play("machine_start", global_position + Vector3(0, 1.5, 0.3), -6.0, 1.5)
	if _sp_shake and _sp_state == "hide":
		_sp_shake = false
		_sp_reel = _rng.randi() % 3
		_sp_drop()

func _spin_step(dt: float) -> void:
	_spin_t += dt
	var all_stopped := true
	for i in 3:
		var r := _reels[i]
		var st: Dictionary = _reel_stop[i]
		var stop_at: float = STOPS[i] + (0.7 if i == 2 and _result[0] == _result[1] else 0.0)
		if st.is_empty() and _reel_v[i] > 0.0 and _spin_t >= stop_at:
			# to the symbol, a turn and a half on, then a little past it and back
			var to := _sym_angle(_result[i])
			var now: float = _reel_phi[i]
			var k := ceilf((now + PI * 1.5 - to) / TAU)
			_reel_stop[i] = {"from": now, "to": to + k * TAU, "t": 0.0}
			st = _reel_stop[i]
		if not st.is_empty():
			st.t = float(st.t) + dt
			var dur := 0.55
			var u := clampf(float(st.t) / dur, 0.0, 1.0)
			var c1 := 1.9
			var e := 1.0 + (c1 + 1.0) * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)     # ease out, a little past and back
			var was: float = _reel_phi[i]
			_reel_phi[i] = lerpf(float(st.from), float(st.to), e)
			_reel_v[i] = (_reel_phi[i] - was) / maxf(dt, 0.001)
			if u >= 1.0:
				_reel_phi[i] = fmod(float(st.to), TAU)
				_reel_v[i] = 0.0
				_reel_stop[i] = {}
				if arena and arena.sound:
					arena.sound.play("dial_click", global_position + Vector3(REEL_X[i] * VM, 1.55, 0.3), -2.0, 0.8)
					arena.sound.play("harpoon_clank", global_position + Vector3(REEL_X[i] * VM, 1.55, 0.3), -12.0, 0.7)
			else:
				all_stopped = false
		elif _reel_v[i] > 0.0:
			_reel_phi[i] += _reel_v[i] * dt
			all_stopped = false
		r.rotation.x = _reel_phi[i]
		var fast := absf(_reel_v[i]) > 9.0
		_mat_reel[i].albedo_texture = _tex_blur if fast else _tex_sharp
		_mat_reel[i].emission_texture = _mat_reel[i].albedo_texture
	if all_stopped and _spin_t > STOPS[0]:
		spinning = false
		if _result[0] == _result[1] and _result[1] == _result[2]:
			if SYMS[_result[0]] == "skull":
				_bust_t = 1.2
				if arena and arena.sound:
					arena.sound.play("laser_fizzle", global_position + Vector3(0, 1.9, 0.3), 0.0)
			else:
				_win_t = 3.0
				if arena and arena.sound:
					arena.sound.play("gold_find", global_position + Vector3(0, 1.6, 0.3), 2.0)

## What the reels show on the line now.
func showing() -> Array:
	var out := []
	for i in 3:
		var a := fposmod(_reel_phi[i], TAU)
		out.append(SYMS[int(floor(a / TAU * SYMS.size())) % SYMS.size()])
	return out

func _lever_step(dt: float) -> void:
	if _lever_t < 0.0:
		return
	_lever_t += dt
	var t := _lever_t
	var ang := 0.0
	if t < 0.32:
		ang = 1.75 * smoothstep(0.0, 1.0, t / 0.32)             # down and forward
	elif _lever_stick and t < 0.32 + 0.45:
		ang = 0.9 + 0.04 * sin(t * 40.0)                       # stuck halfway, juddering
	else:
		var t2 := t - (0.32 + (0.45 if _lever_stick else 0.0))
		ang = (1.75 if not _lever_stick else 0.9) * exp(-t2 * 7.0) * cos(t2 * 16.0)    # springs back, wobbling
		if t2 > 0.9:
			ang = 0.0
			_lever_t = -1.0
	if t >= 0.32 and t - dt < 0.32 and not spinning:
		_start_spin()
		if arena and arena.sound:
			arena.sound.play("hammer_thud_0", global_position + Vector3(0.5, 1.4, 0.3), -8.0, 1.6)
	_lever.rotation.x = ang

# ---------------------------------------------------------------- the lights

func _process(dt: float) -> void:
	_t += dt
	_lever_step(dt)
	if spinning:
		_spin_step(dt)
	_spider_step(dt)
	_lights(dt)

func _lights(dt: float) -> void:
	_win_t = maxf(0.0, _win_t - dt)
	_bust_t = maxf(0.0, _bust_t - dt)
	# a fit of flickering now and then: the marquee dims, cuts out, buzzes back
	_flicker_next -= dt
	if _flicker_next <= 0.0:
		_flicker = _rng.randf_range(0.25, 0.8)
		_flicker_next = _rng.randf_range(3.0, 8.0)
	_flicker = maxf(0.0, _flicker - dt)
	var power := 1.0
	if _flicker > 0.0:
		power = 0.0 if _rng.randf() < 0.5 else _rng.randf_range(0.2, 0.7)
	if _bust_t > 0.0:
		power = 0.0 if _bust_t > 0.6 or _rng.randf() < 0.5 else 0.3
	var rate := 6.0 if not near else 13.0
	if spinning:
		rate = 0.0
	_chase += dt * rate
	var lit := int(_chase) % 20
	for i in _bulbs.size():
		var on := false
		if i in DEAD_BULBS:
			on = false
		elif _win_t > 0.0:
			on = int(_t * 8.0) % 2 == 0
		elif spinning:
			on = (i + int(_t * 10.0)) % 2 == 0 and _rng.randf() > 0.15      # (some lag behind)
		else:
			on = (i - lit + 20) % 20 < 6 or (i - lit + 20) % 20 >= 17
		if i == LOOSE_BULB:
			on = _rng.randf() < 0.55
		var m := (_bulb_pink if i % 2 == 0 else _bulb_on) if on and power > 0.25 else _bulb_off
		if _bust_t > 0.0 and on and power > 0.0:
			m = _bulb_red                         # (bust: a dull red, flickering out)
		_bulbs[i].material_override = m
	# the letters: the dead two now and then flicker on (and blaze on a win)
	for i in _letters.size():
		var on := power > 0.3
		if i in DEAD_LETTERS:
			on = (_win_t > 0.0 and int(_t * 8.0) % 2 == 0) or (power > 0.3 and fmod(_t * 0.37 + i, 7.0) < 0.25 and _rng.randf() < 0.6)
		_letters[i].material_override = _letter_on if on else _letter_off
	_face_mat.emission_energy_multiplier = 0.16 * power * (2.0 if _win_t > 0.0 else 1.0)
	_glow.light_energy = 0.9 * power * (1.8 if _win_t > 0.0 else 1.0)
	_win_mat.emission_energy_multiplier = 3.0 if (_win_t > 0.0 and int(_t * 6.0) % 2 == 0) else 0.1
	_win_mat.emission = Color(1.0, 0.25, 0.1) if _win_t > 0.0 else Color(0.35, 0.08, 0.06)
	# the reels' inside lights; the right one's dying
	for i in 3:
		var e := 0.12 * power
		if i == 2:
			e *= 0.45 + 0.35 * (1.0 if _rng.randf() < 0.8 else 0.0) * (0.7 + 0.3 * sin(_t * 31.0))
		_mat_reel[i].emission_energy_multiplier = e
