# (Copied from stkilda-godot scripts/town/coaster_wood.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkCoasterWood
extends RefCounted
## The Scenic Railway's timber (the owner: bare old wood, and "proper cartoon unsafe"). Beams and planks with the
## grain running along them (a texture made here: grain lines, knots, the odd seam), each its own shade of old wood:
## mostly mid brown, some sun-bleached grey, some dark with damp, now and then a pale new repair board. All drawn into
## one mesh (its own SurfaceTool, with UVs) under one material, like the rest of the ride. Random but the same every
## time: everything picks from `rng`, seeded once, in the order the ride is built.

const BOARD := 0.3                       # how wide (m) the texture's height is across the grain
const RUN := 2.4                         # how long (m) along the grain it covers before it repeats
const BROWN := Color("#a8875f")
const BLEACHED := Color("#b3aa99")
const DAMP := Color("#6e5640")
const NEW := Color("#e2c391")
const IRON := Color("#3b3a38")
const RUST := Color("#8a4a24")

static var rng := RandomNumberGenerator.new()
static var _mat: StandardMaterial3D

## Start over (so the ride comes out the same each time it's built).
static func reset() -> void:
	rng.seed = 18910
	rng.state = 0

## An old timber's colour: mostly brown, some bleached, some damp, about 1 in 15 a new repair.
static func shade() -> Color:
	var r := rng.randf()
	var c := BROWN
	if r < 0.067:
		c = NEW
	elif r < 0.25:
		c = BLEACHED
	elif r < 0.42:
		c = DAMP
	# (and no two quite the same)
	return c.lerp(DAMP, rng.randf() * 0.15).lightened(rng.randf() * 0.08)

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.albedo_texture = _grain()
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mat.roughness = 0.9
	return _mat

## The grain: across the image's width is along the wood. Wavy dark lines close together (warped by noise so they
## swirl round knots), a few dark oval knots, a faint seam now and then where two boards butt together.
static func _grain() -> ImageTexture:
	var w := 512
	var h := 64
	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 0.02
	warp.seed = 5
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_VALUE
	fine.frequency = 0.6
	fine.seed = 9
	var knots := [Vector2(70, 20), Vector2(300, 44), Vector2(440, 12)]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var p := Vector2(x, y)
			var bend := 0.0
			for k in knots:
				var d := Vector2((x - k.x) / 3.0, y - k.y)
				bend += 9.0 * exp(-d.length_squared() / 60.0) * signf(y - k.y)
			var yy := float(y) + warp.get_noise_2d(x, y * 4.0) * 6.0 + bend
			var line := 0.5 + 0.5 * sin(yy * 1.6)
			var v := 0.82 + 0.1 * line - 0.14 * pow(line, 6.0) + fine.get_noise_2d(x * 0.2, y * 3.0) * 0.05
			for k in knots:
				var d := Vector2((x - k.x) / 2.2, y - k.y)
				var r := d.length()
				if r < 4.5:
					v *= 0.55 + 0.1 * (r / 4.5)
				elif r < 6.0:
					v *= 0.85
			if x % 256 < 2:
				v *= 0.6
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.93))
	# (seamless across: blend the last columns into the first)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## A square timber from a to b, w thick, the grain along it.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var f := d / len
	var u := f.cross(Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT).normalized() * (w / 2.0)
	var v := f.cross(u).normalized() * (w / 2.0)
	var start := rng.randf() * RUN            # (where along the texture this beam starts, so they don't all match)
	var across := rng.randf()
	var sides := [[u, v], [v, -u], [-u, -v], [-v, u]]
	for sd in sides:
		var p: Vector3 = sd[0]
		var q: Vector3 = sd[1]
		var n := p.normalized()
		var col := c.darkened(0.12 if n.y < -0.3 else 0.0)
		_quad(st, a + p + q, b + p + q, a + p - q, b + p - q, n, col, start, len, across, w)
		across += w / BOARD
	# the end grain: only the top end shows
	_quad(st, b + u + v, b - u + v, b + u - v, b - u - v, f, c.darkened(0.2), 0.0, w, 0.0, w)

## A flat board, a0 to b0 along the grain one edge and a1 to b1 the other, facing n.
static func plank(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, n: Vector3, c: Color) -> void:
	_quad(st, a0, b0, a1, b1, n, c, rng.randf() * RUN, a0.distance_to(b0), rng.randf(), a0.distance_to(a1))

static func _quad(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, n: Vector3, c: Color, start: float, len: float, across: float, wide: float) -> void:
	var u0 := start / RUN
	var u1 := (start + len) / RUN
	var v0 := across
	var v1 := across + wide / BOARD
	_tri(st, [a0, b0, b1], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)], n, c)
	_tri(st, [a0, b1, a1], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)], n, c)

static func _tri(st: SurfaceTool, p: Array, t: Array, n: Vector3, col: Color) -> void:
	var a: Vector3 = p[0]
	var real := ((p[1] as Vector3) - a).cross((p[2] as Vector3) - a)
	if real.length_squared() < 0.000001:
		return
	var nn := real.normalized()
	var order := [0, 2, 1]                  # (Godot draws the side where the corners go clockwise)
	if nn.dot(n) < 0.0:
		nn = -nn
		order = [0, 1, 2]
	st.set_normal(nn)
	st.set_color(col)
	for k in order:
		st.set_uv(t[k])
		st.add_vertex(p[k])

## An iron plate bolted on where timbers meet: a thin dark square on a face (at `at`, facing `out`, `up` its upright
## way), four bolt heads on it, and sometimes a rust streak running down the wood under it. Into `st` (the plain
## coloured mesh).
static func plate(st: SurfaceTool, at: Vector3, out: Vector3, up: Vector3, size: float) -> void:
	var side := out.cross(up).normalized() * (size / 2.0)
	var u := up.normalized() * (size / 2.0)
	var o := out.normalized()
	var face := at + o * 0.03
	SkScenicRailway._strip(st, face - side - u, face + side - u, face - side + u, face + side + u, o, IRON)
	for sx in [-0.6, 0.6]:
		for sy in [-0.6, 0.6]:
			var b: Vector3 = face + side * sx + u * sy + o * 0.03
			var s := side.normalized() * 0.04
			var t := u.normalized() * 0.04
			SkScenicRailway._strip(st, b - s - t, b + s - t, b - s + t, b + s + t, o, IRON.lightened(0.15))
	if rng.randf() < 0.5:
		var long := 0.5 + rng.randf() * 1.2
		var top := at + o * 0.012 - u
		var wide := side * (0.25 + rng.randf() * 0.3)
		var off := side * (rng.randf() - 0.5)
		SkScenicRailway._strip(st, top + off - wide, top + off + wide, top + off - wide * 0.3 - up.normalized() * long, top + off + wide * 0.3 - up.normalized() * long, o, RUST.lerp(DAMP, rng.randf() * 0.4))

# ---------------------------------------------------------------- the bodges

const CONCRETE := Color("#9b9890")
const BRICK := Color("#9c4a36")
const ROPE := Color("#c2a878")
const CRATES := [Color("#2f5fb3"), Color("#c8302c"), Color("#e0b12a")]

## What a post stands on, at `at` (on the ground): mostly a concrete block, some on a stack of loose bricks, some on
## wooden wedges, the odd one on a milk crate. Gives back how high its top is (the post starts there).
static func footing(st: SurfaceTool, wood: SurfaceTool, at: Vector3) -> float:
	SkContactShade.blob(Vector2(at.x, at.z), 0.8, 0.42)
	var r := rng.randf()
	var up := Vector3.UP
	if r < 0.04:
		# a milk crate, a bit skew, with a darker band round it
		var c: Color = CRATES[rng.randi() % CRATES.size()]
		var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
		SkScenicRailway._beam(st, at, at + up * 0.38 + lean, 0.5, c)
		SkScenicRailway._beam(st, at + up * 0.16 + lean * 0.4, at + up * 0.22 + lean * 0.6, 0.52, c.darkened(0.35))
		return 0.38
	if r < 0.22:
		# loose bricks, three high, none quite on the one under it
		for k in 3:
			var o := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
			SkScenicRailway._beam(st, at + o + up * (0.11 * k), at + o + up * (0.11 * k + 0.1), 0.4, BRICK.lightened(rng.randf() * 0.15))
		return 0.32
	if r < 0.36:
		# wooden wedges, hammered in from either side
		var d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var s := d.cross(up) * 0.12
		beam(wood, at - d * 0.4 + up * 0.04 + s, at + d * 0.1 + up * 0.14 + s, 0.12, shade())
		beam(wood, at + d * 0.4 + up * 0.04 - s, at - d * 0.1 + up * 0.14 - s, 0.12, shade())
		return 0.16
	SkScenicRailway._beam(st, at, at + up * 0.35, 0.62, CONCRETE.darkened(rng.randf() * 0.15))
	return 0.35

## Rope lashed round a post (w thick) at `at`: a few turns.
static func rope(st: SurfaceTool, at: Vector3, w: float) -> void:
	var s := w / 2.0 + 0.03
	for k in 3:
		var h := at + Vector3(0, 0.07 * k, 0)
		var c := [h + Vector3(-s, 0, -s), h + Vector3(s, 0.02, -s), h + Vector3(s, 0.03, s), h + Vector3(-s, 0.01, s)]
		for j in 4:
			SkScenicRailway._beam(st, c[j], c[(j + 1) % 4], 0.045, ROPE.darkened(rng.randf() * 0.2))

## A scrap board nailed across something: centred on `at`, flat against a face looking along `out`, at an angle.
static func patch(wood: SurfaceTool, at: Vector3, out: Vector3, long: float, wide: float) -> void:
	var o := out.normalized()
	var flat := o.cross(Vector3.UP).normalized()
	var ang := rng.randf_range(-0.7, 0.7)
	var along := (flat * cos(ang) + Vector3.UP * sin(ang)).normalized() * (long / 2.0)
	var across := o.cross(along).normalized() * (wide / 2.0)
	var c := at + o * 0.06
	plank(wood, c - along - across, c + along - across, c - along + across, c + along + across, o, NEW.lerp(BLEACHED, rng.randf()))
