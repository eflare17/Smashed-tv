class_name MineOreBox
extends Node3D
## The ORE box up top (the owner, 24 Oct: "I want it to like squirt into a box ... rather than, you know, just shop and
## sell it"): a big steel hopper with a funnel, between the fuel station and the trader. Fly over it (or park by it)
## and press E: the ship runs its hose out of its back and squirts its cargo out, a nugget at a time, each arcing over
## into the funnel; each one clunks in, the counter on the box rolls up and the cash with it, ka-ching when the last
## one's in. Drawn in pixel art like the ship (MineShipArt's grid). The mine (VoxelMine) asks it whether the ship's in
## reach and starts it; it pays through the mine. Owned by the voxel session.

const X := 14.0                 # the box's middle (metres along the ground)
const REACH := 3.4              # how far from it the hose reaches
const SCALE := 1.4              # (its pixels: the ship's, a bit bigger)
const EVERY := 0.11             # a nugget squirted out this often
const FLIGHT := 0.55            # seconds a nugget takes to arc over
const GRAV := 12.0

var mine: Node                  # VoxelMine
var unloading := false
var hose := 0.0                 # how far it has the ship's hose run out (0 .. 1)
var counter := 0                # what the box's counter shows (this unload's takings)
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _shown := -1
var _queue: Array[String] = []  # what's still to squirt out
var _flying := []               # {n, p, v, id, price}
var _hose_t := 0.0
var _emit_t := 0.0
var _total := 0
var _ore_mat := {}              # cargo id -> its tile (for the nugget's colours)

func setup(m: Node) -> void:
	mine = m
	_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	var px := MineShipArt.PX * SCALE
	q.size = Vector2(MineShipArt.W, MineShipArt.H) * px
	_quad.mesh = q
	var sh := Shader.new()
	sh.code = MineShip.SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("self_lit", 0.2)
	_quad.material_override = _mat
	# the box's foot on the ground at X (its art: middle at canvas x 30, feet's bottom at canvas y 42)
	_quad.position = Vector3(X + (MineShipArt.W * 0.5 - 30.0) * px, (42.0 - MineShipArt.H * 0.5) * px, 0.25)
	add_child(_quad)
	for t in MineTiles.INFO:
		var id := String(MineTiles.INFO[t].get("cargo", ""))
		if id != "" and not _ore_mat.has(id):
			_ore_mat[id] = t
	_redraw()

## The funnel's mouth (metres)
static func mouth() -> Vector2:
	return Vector2(X, (42.0 - 4.0) * MineShipArt.PX * SCALE)

## Whether the ship at p is close enough to unload
static func in_reach(p: Vector2) -> bool:
	return absf(p.x - X) < REACH and p.y > 0.0 and p.y < 4.0

## Start squirting the cargo out (cargo: id -> how many)
func start(cargo: Dictionary) -> void:
	if unloading:
		return
	_queue.clear()
	for id in MineShop.CARGO_ORDER:
		for i in int(cargo.get(id, 0)):
			_queue.append(id)
	if _queue.is_empty():
		return
	_queue.shuffle()
	unloading = true
	counter = 0
	_total = 0
	_hose_t = 0.0
	_emit_t = 0.0
	_redraw()

func _process(dt: float) -> void:
	if mine == null:
		return
	var ship: MineShip = mine.ship
	if unloading:
		_hose_t += dt
		hose = minf(1.0, _hose_t / 0.3)
		if not in_reach(ship.p):
			_queue.clear()              # (flew off: the rest stays in the hold)
		if hose >= 1.0 and not _queue.is_empty():
			_emit_t -= dt
			if _emit_t <= 0.0:
				_emit_t = EVERY
				_squirt(_queue.pop_back(), ship)
		if _queue.is_empty() and _flying.is_empty():
			unloading = false
			if _total > 0:
				mine.unloaded(_total)
	else:
		hose = maxf(0.0, hose - dt * 3.0)
	_step(dt)
	if counter != _shown:
		_redraw()

## One nugget out of the nozzle, thrown so it lands in the funnel FLIGHT seconds on
func _squirt(id: String, ship: MineShip) -> void:
	var from := ship.nozzle_at()
	var to := mouth() + Vector2(randf_range(-0.12, 0.12), 0.05)
	var vel := (to - from) / FLIGHT + Vector2(0, 0.5 * GRAV * FLIGHT)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.16)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	var sh := MineTiles.shades(int(_ore_mat.get(id, MineTiles.COAL)))
	mat.albedo_color = sh[6]
	mat.emission_enabled = true
	mat.emission = sh[7]
	mat.emission_energy_multiplier = 1.3
	mi.material_override = mat
	mi.position = Vector3(from.x, from.y, 0.45)
	add_child(mi)
	_flying.append({"n": mi, "p": from, "v": vel, "t": 0.0, "id": id})
	mine.cargo[id] = maxi(0, int(mine.cargo.get(id, 0)) - 1)
	if int(mine.cargo[id]) == 0:
		mine.cargo.erase(id)
	mine.sound.play("mine_squirt", Vector3.INF, -9.0, randf_range(0.9, 1.15))

func _step(dt: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var f: Dictionary = _flying[i]
		f.t += dt
		f.v.y -= GRAV * dt
		f.p += f.v * dt
		var n: MeshInstance3D = f.n
		n.position = Vector3(f.p.x, f.p.y, 0.45)
		n.rotation += Vector3(dt * 6.0, dt * 9.0, 0)
		if f.t >= FLIGHT:
			# in: a clunk (brighter for the rarer), the counter and the cash up
			var price := MineShop.price(String(f.id), mine.day)
			counter += price
			_total += price
			mine.pay_quiet(price)
			mine.sound.play("mine_clunk", Vector3.INF, -6.0, 0.8 + MineShop.CARGO_ORDER.find(String(f.id)) * 0.06)
			if String(f.id) in VoxelMine.NUG_RARE:
				mine.spark(mouth() + Vector2(0, 0.1), Color8(255, 230, 140), 6)
			n.queue_free()
			_flying.remove_at(i)

## Done at once (leaving the mine mid-unload): what's in the air lands, the rest stays in the hold.
func finish_now() -> void:
	for f in _flying:
		var price := MineShop.price(String(f.id), mine.day)
		_total += price
		mine.pay_quiet(price)
		f.n.queue_free()
	_flying.clear()
	_queue.clear()
	if unloading and _total > 0:
		mine.unloaded(_total)
	unloading = false
	hose = 0.0

func _redraw() -> void:
	_shown = counter
	_mat.set_shader_parameter("tex", art(counter))

## The box: a steel hopper with a funnel on top, ORE on a green sign, a hazard stripe, the counter (value: what it
## shows, up to 9999).
static func art(value: int) -> ImageTexture:
	var g := MineShipArt.Grid.new(MineShipArt.BASE.merged({"H": Color8(120, 124, 132), "h": Color8(84, 88, 96),
		"L": Color8(170, 174, 182), "j": Color8(56, 58, 66), "Y": Color8(255, 230, 110), "y": Color8(240, 190, 30),
		"E": Color8(110, 255, 120)}, true))
	var ox := -8
	var oy := -4
	for y in range(0, 8):
		for x in range(2 + y, 44 - y):
			g.put(ox + x, oy + y, "L" if y < 2 else ("H" if x < 23 else "h"))
	for x in range(4, 42):
		g.put(ox + x, oy + 1, "j")
	for y in range(8, 38):
		for x in range(8, 38):
			g.put(ox + x, oy + y, "j" if (y - 8) % 6 == 0 else ("H" if x < 30 else "h"))
	for x in range(8, 38):
		g.put(ox + x, oy + 10, "y" if (x / 2) % 2 else "K")
	for y in range(14, 24):
		for x in range(11, 35):
			g.put(ox + x, oy + y, "N" if (x >= 12 and x <= 33 and y >= 15 and y <= 22) else "n")
	var font := {"O": ["YYY", "Y.Y", "Y.Y", "Y.Y", "YYY"], "R": ["YY.", "Y.Y", "YY.", "Y.Y", "Y.Y"], "E": ["YYY", "Y..", "YY.", "Y..", "YYY"],
		"0": ["EEE", "E.E", "E.E", "E.E", "EEE"], "1": [".E.", "EE.", ".E.", ".E.", "EEE"], "2": ["EE.", "..E", ".E.", "E..", "EEE"],
		"3": ["EE.", "..E", ".E.", "..E", "EE."], "4": ["E.E", "E.E", "EEE", "..E", "..E"], "5": ["EEE", "E..", "EE.", "..E", "EE."],
		"6": [".EE", "E..", "EEE", "E.E", "EEE"], "7": ["EEE", "..E", ".E.", ".E.", ".E."], "8": ["EEE", "E.E", "EEE", "E.E", "EEE"],
		"9": ["EEE", "E.E", "EEE", "..E", "EE."]}
	for i in 3:
		g.rows(ox + 15 + i * 5, oy + 16, font["ORE"[i]])
	for y in range(27, 33):
		for x in range(13, 33):
			g.put(ox + x, oy + y, "T")
	var s := str(clampi(value, 0, 9999))
	var x0 := 31 - s.length() * 4
	for i in s.length():
		g.rows(ox + x0 + i * 4, oy + 28, font[s[i]])
	g.rows(ox + 9, oy + 38, ["jjj"])
	g.rows(ox + 34, oy + 38, ["jjj"])
	return ImageTexture.create_from_image(g.outline().image())
