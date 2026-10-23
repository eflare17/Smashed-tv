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

var number := 1
var seed_value := 0
var width := 2400
var palette: Array
## Rect2s: each obstacle's box, standing on the ground (what dinosaurs bump into and stand on).
var obstacles: Array[Rect2] = []
## Where herds start: [x, how many].
var herds: Array = []
var exit_x := 0.0
var stains: Sprite2D

var _rng := RandomNumberGenerator.new()

## Lays the area out (no nodes yet): its length, obstacles, herds.
func generate(n: int, run_seed: int, ground_y: float) -> void:
	number = n
	seed_value = hash([run_seed, n])
	_rng.seed = seed_value
	palette = PALETTES[(n - 1) % PALETTES.size()]
	width = 2200 + n * 400 + _rng.randi_range(0, 600)
	exit_x = width - 24.0
	obstacles.clear()
	herds.clear()
	var x := 360.0
	while x < width - 260.0:
		if _rng.randf() < 0.65:
			if _rng.randf() < 0.55:
				var w := _rng.randi_range(16, 30)
				var h := _rng.randi_range(12, 22)
				obstacles.append(Rect2(x, ground_y - h, w, h))
			else:
				var w := _rng.randi_range(30, 48)
				var h := _rng.randi_range(8, 11)
				obstacles.append(Rect2(x, ground_y - h, w, h))
		else:
			herds.append([x + _rng.randf_range(-40.0, 40.0), _rng.randi_range(1, 2 + mini(n, 2))])
		x += _rng.randf_range(170.0, 380.0)
	# always something to eat near the start
	herds.push_front([300.0, 1])

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

	var ground := Image.create(width, int(view.y - ground_y) + 4, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.08
	var light: Color = palette[5]
	var dark: Color = palette[6]
	var grass: Color = palette[7]
	for y in ground.get_height():
		for x in width:
			var c := light.lerp(dark, clampf(n.get_noise_2d(x, y * 2.0) + 0.5, 0.0, 1.0))
			if y < 3:
				c = grass if (y < 2 or (x * 7 + y) % 5 != 0) else c
				if y == 0 and n.get_noise_1d(x * 3.0) > 0.2:
					c = grass.lightened(0.15)
			ground.set_pixel(x, y, c)
	var g := Sprite2D.new()
	g.texture = ImageTexture.create_from_image(ground)
	g.centered = false
	g.position = Vector2(0, ground_y - 3)
	g.z_index = -6
	add_child(g)

	stains = Sprite2D.new()
	stains.z_index = -5
	add_child(stains)

	for o in obstacles:
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
