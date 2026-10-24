class_name Area
extends Node2D
## One area of a run, generated from a seed: its length, the look (a palette per area, cycling), the scenery, the
## ground, the obstacles (rocks to jump, logs) and where the first herds stand, plus the sign at the far end that
## leads to the next area. Every run has its own seed, so every run's areas are different; the same seed always
## builds the same area. Everything in an area is a child of this node, so the next area just replaces it.
## PLACEHOLDER: the look, the obstacle kinds and all the numbers here are first guesses.

const DinoArt := preload("dino_art.gd")

## [sky top, sky low, far hills, near hills, jungle, ground light, ground dark, grass]
const PALETTES := [
	[Color(0.36, 0.55, 0.72), Color(0.93, 0.74, 0.5), Color(0.45, 0.47, 0.55), Color(0.24, 0.36, 0.28),
			Color(0.16, 0.3, 0.18), Color(0.42, 0.3, 0.2), Color(0.33, 0.23, 0.15), Color(0.36, 0.52, 0.22)],
	[Color(0.55, 0.62, 0.75), Color(0.98, 0.85, 0.6), Color(0.62, 0.5, 0.42), Color(0.55, 0.4, 0.28),
			Color(0.38, 0.4, 0.2), Color(0.66, 0.5, 0.32), Color(0.55, 0.4, 0.25), Color(0.6, 0.55, 0.3)],
	[Color(0.3, 0.4, 0.42), Color(0.62, 0.7, 0.6), Color(0.3, 0.38, 0.36), Color(0.2, 0.3, 0.24),
			Color(0.12, 0.22, 0.16), Color(0.3, 0.28, 0.2), Color(0.22, 0.2, 0.14), Color(0.28, 0.4, 0.22)],
	[Color(0.25, 0.12, 0.14), Color(0.85, 0.4, 0.2), Color(0.3, 0.18, 0.18), Color(0.2, 0.12, 0.12),
			Color(0.15, 0.1, 0.08), Color(0.32, 0.22, 0.2), Color(0.22, 0.14, 0.12), Color(0.4, 0.3, 0.18)],
]
const NAMES := ["JUNGLE", "BADLANDS", "SWAMP", "VOLCANO"]
## What a herd is made of.
enum { HERD_GRAZER, HERD_RUNNER, HERD_CHARGER }

var number := 1
var seed_value := 0
var width := 2400
var palette: Array
## Rect2s: each obstacle's box, standing on the ground (what dinosaurs bump into and stand on).
var obstacles: Array[Rect2] = []
## Rock shelves in the air (one-way: jump up through, stand on), and the raised-ground slabs (drawn as ground).
var platforms: Array[Rect2] = []
var ground: Array[Rect2] = []
var ground_y_ := 226.0
## Where herds start: [x, how many, which kind (HERD_*)].
var herds: Array = []
var exit_x := 0.0
var stains: Sprite2D

var _rng := RandomNumberGenerator.new()

## Lays the area out (no nodes yet): its length, obstacles, herds.
func generate(n: int, run_seed: int, ground_y: float) -> void:
	number = n
	ground_y_ = ground_y
	seed_value = hash([run_seed, n])
	_rng.seed = seed_value
	palette = PALETTES[(n - 1) % PALETTES.size()]
	width = 2200 + n * 400 + _rng.randi_range(0, 600)
	exit_x = width - 24.0
	obstacles.clear()
	platforms.clear()
	ground.clear()
	herds.clear()
	var x := 360.0
	while x < width - 260.0:
		var roll := _rng.randf()
		if roll < 0.3:
			# a rock to jump or a log to hop
			if _rng.randf() < 0.55:
				var w := _rng.randi_range(16, 30)
				var h := _rng.randi_range(12, 22)
				obstacles.append(Rect2(x, ground_y - h, w, h))
			else:
				var w := _rng.randi_range(30, 48)
				var h := _rng.randi_range(8, 11)
				obstacles.append(Rect2(x, ground_y - h, w, h))
		elif roll < 0.55:
			# raised ground: a rise you walk up in steps (low) or a plateau you have to jump onto (high), sometimes
			# with a herd grazing on top
			var w := _rng.randi_range(120, 260)
			var high := _rng.randf() < 0.4
			var h := _rng.randi_range(26, 36) if high else _rng.randi_range(10, 12)
			var top := Rect2(x, ground_y - h, w, h)
			obstacles.append(top)
			ground.append(top)
			if not high:
				# a step up and down either side
				for side: Array in [[x - 14.0, 1], [x + w, 1]]:
					var st := Rect2(side[0], ground_y - h * 0.5, 14, h * 0.5)
					obstacles.append(st)
					ground.append(st)
			if _rng.randf() < 0.6:
				var kind := herd_kind(_rng)
				herds.append([x + w * 0.5, 1 if kind == HERD_CHARGER else _rng.randi_range(1, 2), kind])
			x += w
		elif roll < 0.7:
			# a rock shelf in the air: jump up through it and stand on it
			var w := _rng.randi_range(40, 72)
			platforms.append(Rect2(x, ground_y - _rng.randi_range(28, 36), w, 6))
		else:
			var kind := herd_kind(_rng)
			herds.append([x + _rng.randf_range(-40.0, 40.0), 1 if kind == HERD_CHARGER else _rng.randi_range(1, 2 + mini(n, 2)), kind])
		x += _rng.randf_range(170.0, 380.0)
	# always something to eat near the start
	herds.push_front([300.0, 2, HERD_RUNNER])

## Where the feet go at `x`: the ground, or the top of raised ground there.
func floor_at(x: float) -> float:
	var y := ground_y_
	for slab in ground:
		if x >= slab.position.x and x <= slab.end.x:
			y = minf(y, slab.position.y)
	return y

## Builds the nodes: sky, parallax hills and jungle, the ground, the obstacles, the stain layer, the exit sign.
func build(view: Vector2, ground_y: float) -> void:
	var sky := Image.create(1, int(view.y), false, Image.FORMAT_RGBA8)
	for y in int(view.y):
		var k := floorf(float(y) / view.y * 9.0) / 8.0
		sky.set_pixel(0, y, (palette[0] as Color).lerp(palette[1], k))
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	var sky_rect := TextureRect.new()
	sky_rect.texture = ImageTexture.create_from_image(sky)
	sky_rect.stretch_mode = TextureRect.STRETCH_SCALE
	sky_rect.size = view
	sky_layer.add_child(sky_rect)
	_add_layer(_ridge(960, 120, 70.0, 0.012, palette[2]), 0.15, ground_y - 120)
	_add_layer(_ridge(960, 90, 40.0, 0.03, palette[3]), 0.4, ground_y - 88)
	_add_layer(_jungle(960, 70, palette[4]), 0.7, ground_y - 66)

	var ground_img := Image.create(width, int(view.y - ground_y) + 4, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.08
	var light: Color = palette[5]
	var dark: Color = palette[6]
	var grass: Color = palette[7]
	for y in ground_img.get_height():
		for x in width:
			var c := light.lerp(dark, clampf(n.get_noise_2d(x, y * 2.0) + 0.5, 0.0, 1.0))
			if y < 3:
				c = grass if (y < 2 or (x * 7 + y) % 5 != 0) else c
				if y == 0 and n.get_noise_1d(x * 3.0) > 0.2:
					c = grass.lightened(0.15)
			ground_img.set_pixel(x, y, c)
	var g := Sprite2D.new()
	g.texture = ImageTexture.create_from_image(ground_img)
	g.centered = false
	g.position = Vector2(0, ground_y - 3)
	g.z_index = -6
	add_child(g)

	stains = Sprite2D.new()
	stains.z_index = -5
	add_child(stains)

	for slab in ground:
		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(_slab(int(slab.size.x), int(slab.size.y), light, dark, grass))
		s.centered = false
		s.position = slab.position
		s.z_index = -4
		add_child(s)
	for pf in platforms:
		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(_shelf(int(pf.size.x), int(pf.size.y) + 4))
		s.centered = false
		s.position = pf.position
		s.z_index = -3
		add_child(s)
	for o in obstacles:
		if ground.has(o):
			continue
		var img: Image
		if o.size.y > 11.5:
			img = DinoArt.rock(int(o.size.x), int(o.size.y), _rng)
		else:
			img = DinoArt.log_image(int(o.size.x), int(o.size.y))
		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(img)
		s.centered = false
		s.position = o.position
		s.z_index = -2
		add_child(s)

	var post := Sprite2D.new()
	post.texture = ImageTexture.create_from_image(DinoArt.sign_image())
	post.centered = false
	post.position = Vector2(exit_x - 18.0, ground_y - 30.0)
	post.z_index = -3
	add_child(post)

func _add_layer(img: Image, scroll: float, y: float) -> void:
	var par := Parallax2D.new()
	par.scroll_scale = Vector2(scroll, 1.0)
	par.repeat_size = Vector2(img.get_width(), 0)
	par.repeat_times = 3
	par.z_index = -20
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.position = Vector2(-img.get_width(), y)
	par.add_child(s)
	add_child(par)

func _ridge(w: int, h: int, amp: float, freq: float, c: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = _rng.randi()
	n.frequency = freq
	for x in w:
		# wraps: blend the noise with itself one width along
		var k := float(x) / w
		var v := lerpf(n.get_noise_1d(x), n.get_noise_1d(x - w), k)
		var top := int(h - amp * (0.55 + v * 0.8))
		for y in range(clampi(top, 0, h), h):
			img.set_pixel(x, y, c.lightened(0.08) if y == top else c)
	return img

func _jungle(w: int, h: int, leaf: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var trunk := leaf.darkened(0.25).lerp(Color(0.2, 0.2, 0.16), 0.5)
	var x := 10
	while x < w - 20:
		var th := _rng.randi_range(30, 60)
		for y in range(h - th, h):
			img.set_pixel(x, y, trunk)
			img.set_pixel(x + 1, y, trunk)
		# palm fronds: lines drooping out from the top
		for f in 6:
			var a := -PI * 0.5 + (f - 2.5) * 0.55
			var p := Vector2(x, h - th)
			for s in 14:
				p += Vector2(cos(a), sin(a) + s * 0.07)
				var px := int(p.x)
				var py := int(p.y)
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, leaf)
					if py + 1 < h:
						img.set_pixel(px, py + 1, leaf.darkened(0.2))
		x += _rng.randi_range(40, 90)
	for y in range(h - 10, h):
		for xx in w:
			if _rng.randf() < 0.7 - (h - y) * 0.06:
				img.set_pixel(xx, y, leaf.darkened(0.1))
	return img

## A slab of raised ground: dirt with a grass top and darker edges.
func _slab(w: int, h: int, light: Color, dark: Color, grass: Color) -> Image:
	var img := Image.create(w, h + 3, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = _rng.randi()
	n.frequency = 0.1
	for y in h + 3:
		for x in w:
			var c := light.lerp(dark, clampf(n.get_noise_2d(x, y * 2.0) + 0.5, 0.0, 1.0))
			if y < 3:
				c = grass if (y < 2 or (x * 7 + y) % 5 != 0) else c
			if x == 0 or x == w - 1:
				c = c.darkened(0.3)
			img.set_pixel(x, y, c)
	return img

## A rock shelf: a grey slab, lighter on top, with a few lumps underneath.
func _shelf(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var grey := Color(0.48, 0.47, 0.45)
	for y in h:
		for x in w:
			var edge := x < 2 or x >= w - 2
			if y >= h - 2 and (edge or (x * 5 + y) % 7 < 3):
				continue
			var c := grey.lightened(0.15) if y == 0 else (grey.darkened(0.25) if y >= h - 3 or edge else grey)
			img.set_pixel(x, y, c)
	return img

## A random kind of herd: small runners most often, then the big grazers, now and then a charger. PLACEHOLDER mix.
func herd_kind(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	return HERD_RUNNER if r < 0.45 else (HERD_GRAZER if r < 0.85 else HERD_CHARGER)
