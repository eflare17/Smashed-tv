extends SceneTree
## Makes textures/clods.png, the lumps the ground draws on loose dirt. Run once: godot --headless --path . -s test/make_clods.gd
## It tiles. R and G are which way the surface leans at that spot, B is how far up a lump it is (0 down in a gap between lumps),
## and A is how light or dark that lump is. Baked ahead of time, as working it out on the phone for every pixel would cost far too much.

const SIDE := 512
const BIG := 15                 # lumps across
const SMALL := 44               # crumbs across

var rng := RandomNumberGenerator.new()

func _layer(count: int) -> Array:
	var cells := []
	cells.resize(count * count)
	for k in cells.size():
		# Where the lump sits in its square, how big it is, how it's squashed, and its shade.
		cells[k] = [Vector2(rng.randf(), rng.randf()), rng.randf_range(0.62, 1.0), rng.randf(), Vector2.from_angle(rng.randf() * TAU), rng.randf()]
	return cells

## The height of this layer at a spot, and the shade of the lump it's on.
func _height(layer: Array, count: int, p: Vector2) -> Vector2:
	var at := p * count
	var cell := Vector2i(floori(at.x), floori(at.y))
	var best := 0.0
	var shade := 0.0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var c := cell + Vector2i(di, dj)
			var d: Array = layer[posmod(c.y, count) * count + posmod(c.x, count)]
			var to: Vector2 = at - (Vector2(c) + (d[0] as Vector2))
			# Squashed one way, so they're lumps and not balls.
			var along: float = to.dot(d[3])
			var across: float = to.dot((d[3] as Vector2).orthogonal())
			var r: float = sqrt(along * along * (1.0 + float(d[2]) * 1.2) + across * across) / float(d[1])
			# Flattish on top and falling away at the edge, a bit like a rock, not a smooth dome.
			var h: float = clampf(1.0 - pow(r, 3.0), 0.0, 1.0) * float(d[1])
			if h > best:
				best = h
				shade = d[4]
	return Vector2(best, shade)

func _init() -> void:
	rng.seed = 73
	var big := _layer(BIG)
	var small := _layer(SMALL)
	var heights := PackedFloat32Array()
	heights.resize(SIDE * SIDE)
	var shades := PackedFloat32Array()
	shades.resize(SIDE * SIDE)
	for j in SIDE:
		for i in SIDE:
			var p := Vector2(i + 0.5, j + 0.5) / SIDE
			var a := _height(big, BIG, p)
			var b := _height(small, SMALL, p)
			heights[j * SIDE + i] = a.x + b.x * 0.22
			shades[j * SIDE + i] = a.y
	var img := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	for j in SIDE:
		for i in SIDE:
			var h := heights[j * SIDE + i]
			var dx := heights[j * SIDE + (i + 1) % SIDE] - heights[j * SIDE + (i + SIDE - 1) % SIDE]
			var dy := heights[(j + 1) % SIDE * SIDE + i] - heights[(j + SIDE - 1) % SIDE * SIDE + i]
			var lean := Vector2(-dx, -dy) * 3.2
			# Kept solid: a see-through pixel loses its colour when the picture is saved.
			img.set_pixel(i, j, Color(clampf(lean.x * 0.5 + 0.5, 0.0, 1.0), clampf(lean.y * 0.5 + 0.5, 0.0, 1.0), clampf(h, 0.0, 1.0), 0.5 + shades[j * SIDE + i] * 0.5))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://textures"))
	img.save_png("res://textures/clods.png")
	print("made textures/clods.png")
	quit()
