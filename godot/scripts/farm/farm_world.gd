class_name FarmWorld
extends Node3D
## The farm in the world: every plot's look (FarmPlotView) and its E spot (FarmSpot), the seed crate and its
## SEEDS sign against the shed, the spots at the water tank, the garage's roller door and the compost bin, and
## the two land stages past the fences (FARM.md): the neighbour's block (its house, the grow house; 24 plots, the
## sprinkler, the breeding table; a FOR SALE sign and a gate in the east fence) and the paddock out the back (12
## long rows, the tractor shed and the tractor, a silo and a tank, a dirt track; a FOR SALE sign and the farm gate
## in the bottom fence). Built from FarmData's positions (HTML units), with collision for what's solid.

const D := preload("res://scripts/farm/farm_data.gd")
const GD := preload("res://scripts/game_data.gd")
const U := 0.025

var farm: Farm
var views: Array = []                 # FarmPlotView per plot (index = plot index)
var spots: Array = []                 # every FarmSpot
var _field_spots: Dictionary = {}      # plot index -> its FarmSpot, for the plots on ploughed soil
var _for_sale := {}                   # land -> the sign's node
var _owned_only := {}                 # land -> nodes shown once it's bought
var _tractor: Node3D
var _sprinkler: Node3D
var _lights: Node3D
var _compost_bin: Node3D
var _body: StaticBody3D
var _mats := {}

static func P(x: float, y: float, z: float = 0.0) -> Vector3:
	return GD.world_to_3d(x, y, z)

func build(f: Farm) -> void:
	farm = f
	name = "FarmWorld"
	_body = StaticBody3D.new()
	_body.name = "FarmSolids"
	add_child(_body)
	_owned_only = {"neighbour": [], "paddock": []}
	_build_yard()
	_build_neighbour()
	_build_paddock()
	_build_fences()
	for i in farm.state.plots.size():
		var p: Dictionary = farm.state.plots[i]
		var v := FarmPlotView.new()
		v.name = "Plot%d" % i
		v.position = P(p.x, p.y)
		add_child(v)
		views.append(v)
		if p.zone != "paddock":
			var s := _spot("plot", i, Vector2(p.x, p.y), D.HOLE_REACH)
			s.name = "PlotSpot%d" % i
			if p.zone == "field":
				_field_spots[i] = s
	for r in D.P_ROWS:
		var y := D.P_ROW_Y0 + r * D.P_ROW_DY
		var x1 := D.P_ROW_X0 + (D.P_ROW_PLANTS - 1) * D.P_ROW_DX
		_spot("row", r, Vector2(D.P_ROW_X0, y), 30.0, Rect2(D.P_ROW_X0 - 40, y - 26, x1 - D.P_ROW_X0 + 80, 40))
	farm.changed.connect(refresh)
	refresh()

func _spot(kind: String, idx: int, at: Vector2, reach: float, rect: Rect2 = Rect2()) -> FarmSpot:
	var s := FarmSpot.new()
	s.farm = farm
	s.kind = kind
	s.idx = idx
	s.reach = reach
	s.rect = rect
	s.position = P(at.x, at.y)
	add_child(s)
	spots.append(s)
	return s

## Bring every plot's look and the land's signs up to date.
func refresh() -> void:
	var st := farm.state
	for i in views.size():
		var p: Dictionary = st.plots[i]
		if _field_spots.has(i):
			# (plots on ploughed soil move to wherever they're planted: scripts/dig)
			var at := P(p.x, p.y)
			if views[i].position != at:
				views[i].position = at
				_field_spots[i].position = at
		views[i].show_plot(p, st.stage(i), st.look(i), st.watered(i), st.plot_open(i))
	for k in _for_sale:
		_for_sale[k].visible = not st.land[k]
	for k in _owned_only:
		for n in _owned_only[k]:
			n.visible = st.land[k]
	if _tractor:
		_tractor.visible = st.upgrades.tractor
	if _sprinkler:
		_sprinkler.visible = st.upgrades.sprinkler
	if _lights:
		_lights.visible = st.upgrades.lights and st.land.neighbour
	if _compost_bin:
		_compost_bin.visible = st.upgrades.compost

## ---------------------------------------------------------------- the backyard

func _build_yard() -> void:
	var c := D.CRATE
	# the seed crate (the HTML game's drawSeedCrate): rim, two bins of packets, front boards, and the sign behind
	var crate := Node3D.new()
	crate.name = "SeedCrate"
	add_child(crate)
	_box(crate, c.x0, c.y0, c.x1, c.y1, 0, 22, _col(Color8(122, 84, 52)), _col(Color8(167, 120, 74)))
	_box(crate, c.x0 + 3, c.y0 + 3, (c.x0 + c.x1) / 2.0 - 1.5, c.y1 - 6, 22, 22.6, _col(Color8(58, 40, 26)), _col(Color8(58, 40, 26)))
	_box(crate, (c.x0 + c.x1) / 2.0 + 1.5, c.y0 + 3, c.x1 - 3, c.y1 - 6, 22, 22.6, _col(Color8(58, 40, 26)), _col(Color8(58, 40, 26)))
	for k in 3:
		_box(crate, c.x0 + 6 + k * 10, c.y0 + 8, c.x0 + 14 + k * 10, c.y0 + 18, 22, 30, _col(Color8(63, 143, 58)), _col(Color8(239, 228, 198)))
		_box(crate, (c.x0 + c.x1) / 2.0 + 4 + k * 10, c.y0 + 8, (c.x0 + c.x1) / 2.0 + 12 + k * 10, c.y0 + 18, 22, 30, _col(Color8(196, 191, 54)), _col(Color8(239, 228, 198)))
	_solid(c.x0, c.y0, c.x1, c.y1, 22)
	_sign(Vector2(c.x1 - 12, c.y0 - 6), "SEEDS\nFERTILISER", Color8(210, 174, 116), Color8(47, 90, 36), 26)
	_spot("crate", 0, Vector2((c.x0 + c.x1) / 2.0, (c.y0 + c.y1) / 2.0), 34.0, Rect2(c.x0, c.y0, c.x1 - c.x0, c.y1 - c.y0 + 6))
	# the tank, the garage door, the compost bin (they're in the world already: just their spots)
	_spot("tank", 0, Vector2(D.TANK.cx, D.TANK.cy), D.TANK.d)
	var sl := D.SELL
	_spot("sell", 0, Vector2((sl.x0 + sl.x1) / 2.0, (sl.y0 + sl.y1) / 2.0), 1.0, Rect2(sl.x0, sl.y0, sl.x1 - sl.x0, sl.y1 - sl.y0))
	var cp := D.COMPOST
	_spot("compost", 0, Vector2((cp.x0 + cp.x1) / 2.0, (cp.y0 + cp.y1) / 2.0), 30.0, Rect2(cp.x0, cp.y0, cp.x1 - cp.x0, cp.y1 - cp.y0))
	_compost_bin = _sign(Vector2(cp.x1 - 20, cp.y1 + 4), "COMPOST", Color8(90, 64, 40), Color8(230, 220, 190), 18)
	# a sign on the roller door: what it buys
	_sign(Vector2(sl.x1 - 30, sl.y0 - 8), "BUDS\nBOUGHT", Color8(240, 220, 160), Color8(110, 40, 30), 20)

## ---------------------------------------------------------------- the neighbour's block (stage 2)

func _build_neighbour() -> void:
	var b := D.N_BLOCK
	var root := Node3D.new()
	root.name = "NeighbourBlock"
	add_child(root)
	# their lawn: a slightly different green, so the block reads as its own; a dirt bed for the 24 plots
	_flat(root, b.x0, b.y0, b.x1, b.y1, 0.002, _col(Color8(92, 142, 58)))
	var o := D.N_PLOT_ORIGIN
	var bed := _flat(root, o.x - 70, o.y - 80, o.x + (D.N_PLOT_COLS - 1) * D.N_PLOT_STEP.x + 70,
		o.y + (D.N_PLOT_ROWS - 1) * D.N_PLOT_STEP.y + 60, 0.004, _col(Color8(104, 72, 46)))
	_owned_only.neighbour.append(bed)
	# their house: the grow house once it's yours
	var g := D.GROW_HOUSE
	_box(root, g.x0, g.y0, g.x1, g.y1, 0, g.h, _col(Color8(196, 186, 160)), _col(Color8(84, 88, 96)))
	_box(root, (g.x0 + g.x1) / 2.0 - 30, g.y1 - 2, (g.x0 + g.x1) / 2.0 + 30, g.y1 + 1, 0, 70, _col(Color8(110, 74, 46)), _col(Color8(110, 74, 46)))
	_solid(g.x0, g.y0, g.x1, g.y1, g.h)
	var gh := _label(root, Vector2((g.x0 + g.x1) / 2.0, g.y1 + 4), g.h + 30, "GROW HOUSE", Color8(160, 255, 140), 40)
	_owned_only.neighbour.append(gh)
	_lights = _label(root, Vector2((g.x0 + g.x1) / 2.0, g.y1 + 4), g.h + 60, "GROW LIGHTS ON", Color8(255, 120, 255), 26)
	# the breeding table, in front of it
	var t := D.BREED_TABLE
	var table := Node3D.new()
	root.add_child(table)
	_box(table, t.x - 40, t.y - 18, t.x + 40, t.y + 18, 0, 30, _col(Color8(120, 90, 60)), _col(Color8(170, 140, 100)))
	_label(table, Vector2(t.x, t.y), 52, "BREEDING", Color8(255, 220, 140), 22)
	_owned_only.neighbour.append(table)
	_solid(t.x - 40, t.y - 18, t.x + 40, t.y + 18, 30)
	_spot("breed", 0, Vector2(t.x, t.y), 64.0)
	# the sprinkler, in the middle of the plots
	_sprinkler = Node3D.new()
	root.add_child(_sprinkler)
	var sp := D.SPRINKLER
	_box(_sprinkler, sp.x - 4, sp.y - 4, sp.x + 4, sp.y + 4, 0, 40, _col(Color8(150, 156, 164)), _col(Color8(90, 200, 255)))
	_label(_sprinkler, Vector2(sp.x, sp.y), 56, "SPRINKLER", Color8(140, 210, 255), 18)
	# FOR SALE sign in the yard, by the fence, and the gate
	_for_sale["neighbour"] = _sign(Vector2(D.N_SIGN.x, D.N_SIGN.y), "FOR SALE\nNEIGHBOUR'S\n$%d" % D.LAND_PRICES.neighbour, Color8(230, 60, 50), Color8(255, 255, 255), 30)
	_spot("sign_neighbour", 0, Vector2(D.N_SIGN.x, D.N_SIGN.y), 70.0)
	var gate := _gate(Vector2(D.N_GATE.x, D.N_GATE.y), true)
	_owned_only.neighbour.append(gate)
	var gs := _spot("gate_neighbour", 0, Vector2(D.N_GATE.x, D.N_GATE.y), 60.0)
	gs.gate_pos = Vector2(D.N_GATE.x, D.N_GATE.y)

## ---------------------------------------------------------------- the paddock (stage 3)

func _build_paddock() -> void:
	var pk := D.PADDOCK
	var root := Node3D.new()
	root.name = "Paddock"
	add_child(root)
	_flat(root, pk.x0, pk.y0, pk.x1, pk.y1, 0.002, _col(Color8(150, 160, 70)))
	# the rows, ploughed
	for r in D.P_ROWS:
		var y := D.P_ROW_Y0 + r * D.P_ROW_DY
		var x1 := D.P_ROW_X0 + (D.P_ROW_PLANTS - 1) * D.P_ROW_DX
		_flat(root, D.P_ROW_X0 - 40, y - 16, x1 + 40, y + 14, 0.004, _col(Color8(112, 78, 50)))
		_label(root, Vector2(D.P_ROW_X0 - 70, y), 10, "%d" % (r + 1), Color8(255, 240, 200), 20)
	# the dirt track from the gate down past the shed
	_flat(root, D.P_GATE.x - 40, pk.y0, D.P_GATE.x + 40, D.P_ROW_Y0 - 40, 0.003, _col(Color8(176, 150, 100)))
	_flat(root, 380, D.P_ROW_Y0 - 70, D.P_GATE.x + 40, D.P_ROW_Y0 - 40, 0.003, _col(Color8(176, 150, 100)))
	# the tractor shed, the silo, the tank
	var ts := D.TRACTOR_SHED
	_box(root, ts.x0, ts.y0, ts.x1, ts.y1, 0, ts.h, _col(Color8(150, 70, 50)), _col(Color8(170, 176, 180)))
	_solid(ts.x0, ts.y0, ts.x1, ts.y1, ts.h)
	_label(root, Vector2((ts.x0 + ts.x1) / 2.0, ts.y1), ts.h + 24, "TRACTOR SHED", Color8(255, 230, 190), 28)
	_spot("shed", 0, Vector2((ts.x0 + ts.x1) / 2.0, ts.y1), 20.0, Rect2(ts.x0, ts.y1, ts.x1 - ts.x0, 30))
	for c in [D.SILO, D.P_TANK]:
		var m := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = c.r * U
		cy.bottom_radius = c.r * U
		cy.height = c.h * U
		m.mesh = cy
		m.material_override = _col(Color8(190, 196, 200) if c == D.SILO else Color8(160, 168, 172))
		m.position = P(c.cx, c.cy, c.h / 2.0)
		root.add_child(m)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = (c.r - 7) * U
		sh.height = c.h * U
		cs.shape = sh
		cs.position = m.position
		_body.add_child(cs)
	_label(root, Vector2(D.SILO.cx, D.SILO.cy), D.SILO.h + 20, "SILO", Color8(255, 255, 255), 26)
	# the tractor, out front of its shed
	_tractor = Node3D.new()
	_tractor.name = "Tractor"
	root.add_child(_tractor)
	var tx: float = ts.x1 + 40
	var ty: float = ts.y1 - 120
	_box(_tractor, tx, ty, tx + 70, ty + 110, 8, 40, _col(Color8(40, 140, 60)), _col(Color8(60, 170, 80)))
	_box(_tractor, tx + 10, ty + 50, tx + 60, ty + 100, 40, 80, _col(Color8(40, 140, 60)), _col(Color8(30, 30, 30)))
	for w in [[tx - 10, ty + 60, tx + 4, ty + 104], [tx + 66, ty + 60, tx + 80, ty + 104], [tx - 6, ty + 6, tx + 4, ty + 34], [tx + 66, ty + 6, tx + 76, ty + 34]]:
		_box(_tractor, w[0], w[1], w[2], w[3], 0, 30, _col(Color8(30, 30, 30)), _col(Color8(50, 50, 50)))
	# FOR SALE sign by the farm gate in the bottom fence, and the gate
	_for_sale["paddock"] = _sign(Vector2(D.P_SIGN.x, D.P_SIGN.y), "FOR SALE\nPADDOCK\n$%d" % D.LAND_PRICES.paddock, Color8(230, 60, 50), Color8(255, 255, 255), 30)
	_spot("sign_paddock", 0, Vector2(D.P_SIGN.x, D.P_SIGN.y), 70.0)
	var gate := _gate(Vector2(D.P_GATE.x, D.P_GATE.y), false)
	_owned_only.paddock.append(gate)
	var gs := _spot("gate_paddock", 0, Vector2(D.P_GATE.x, D.P_GATE.y), 60.0)
	gs.gate_pos = Vector2(D.P_GATE.x, D.P_GATE.y)

## The fences round the new land (the yard's own are the world's): the neighbour's block's north and east, the
## paddock's west, south and east, and between the block and the paddock, so each is reached by its gate.
func _build_fences() -> void:
	var W := D.LAND_W
	var H := D.LAND_H
	var fh := float(GameData.data.get("FENCE_H", 58)) if Engine.get_main_loop() else 58.0
	var wood := _col(Color8(122, 96, 66))
	var rail := _col(Color8(58, 46, 32))
	for r in [[1706, 36, W, 40], [W, 36, W + 4, H], [-4, H, W + 4, H + 4], [-4, 1880, 0, H], [1710, 1900, W, 1904]]:
		_box(self, r[0], r[1], r[2], r[3], 0, fh, wood, rail)
		_solid(r[0] - 2, r[1] - 2, r[2] + 2, r[3] + 2, fh)

## ---------------------------------------------------------------- pieces

func _col(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	_mats[k] = m
	return m

## A box from (x0, y0) to (x1, y1) on the ground, z0 to z1 up: sides in one colour, its top in another.
func _box(parent: Node3D, x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, side: Material, top: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x1 - x0, z1 - z0, y1 - y0) * U
	m.mesh = bm
	m.material_override = side
	m.position = P((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	parent.add_child(m)
	var t := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(x1 - x0, y1 - y0) * U
	t.mesh = q
	t.material_override = top
	t.position = Vector3(0, (z1 - z0) / 2.0 * U + 0.002, 0)
	m.add_child(t)
	return m

func _flat(parent: Node3D, x0: float, y0: float, x1: float, y1: float, lift: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(x1 - x0, y1 - y0) * U
	m.mesh = q
	m.material_override = mat
	m.position = P((x0 + x1) / 2.0, (y0 + y1) / 2.0) + Vector3(0, lift, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

func _solid(x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(x1 - x0, h, y1 - y0) * U
	cs.shape = b
	cs.position = P((x0 + x1) / 2.0, (y0 + y1) / 2.0, h / 2.0)
	_body.add_child(cs)

## Words on a board, facing the camera (both views).
func _label(parent: Node3D, at: Vector2, z: float, text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.32 * U
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	l.position = P(at.x, at.y, z)
	parent.add_child(l)
	return l

## A sign on a stake: a board of colour bg with the words in fg.
func _sign(at: Vector2, text: String, bg: Color, fg: Color, size: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_box(n, at.x - 2, at.y - 2, at.x + 2, at.y + 2, 0, 40, _col(Color8(94, 63, 38)), _col(Color8(94, 63, 38)))
	var l := _label(n, at, 52, text, fg, size)
	l.outline_modulate = bg
	l.outline_size = 22
	return n

## A gate in a fence (open, two posts and a swung-back leaf), east (across x) or south (across y).
func _gate(at: Vector2, east: bool) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var post := _col(Color8(80, 60, 40))
	var leaf := _col(Color8(200, 190, 120))
	if east:
		_box(n, at.x - 4, at.y - 44, at.x + 4, at.y - 36, 0, 64, post, post)
		_box(n, at.x - 4, at.y + 36, at.x + 4, at.y + 44, 0, 64, post, post)
		_box(n, at.x + 4, at.y - 44, at.x + 70, at.y - 40, 10, 50, leaf, leaf)
	else:
		_box(n, at.x - 44, at.y - 4, at.x - 36, at.y + 4, 0, 64, post, post)
		_box(n, at.x + 36, at.y - 4, at.x + 44, at.y + 4, 0, 64, post, post)
		_box(n, at.x - 44, at.y + 4, at.x - 40, at.y + 70, 10, 50, leaf, leaf)
	_label(n, at, 76, "GATE", Color8(255, 240, 180), 20)
	return n
