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
	# desert: dunes, cycads, sand on top instead of grass
	[Color(0.6, 0.72, 0.84), Color(1.0, 0.9, 0.7), Color(0.86, 0.7, 0.48), Color(0.8, 0.62, 0.4),
			Color(0.34, 0.42, 0.2), Color(0.86, 0.72, 0.48), Color(0.74, 0.58, 0.36), Color(0.93, 0.8, 0.56)],
	[Color(0.3, 0.4, 0.42), Color(0.62, 0.7, 0.6), Color(0.3, 0.38, 0.36), Color(0.2, 0.3, 0.24),
			Color(0.12, 0.22, 0.16), Color(0.3, 0.28, 0.2), Color(0.22, 0.2, 0.14), Color(0.28, 0.4, 0.22)],
	# coast: a far headland, the sea (near hills), a few palms, a sand beach
	[Color(0.38, 0.6, 0.84), Color(0.86, 0.9, 0.94), Color(0.42, 0.5, 0.56), Color(0.16, 0.46, 0.6),
			Color(0.2, 0.42, 0.22), Color(0.88, 0.8, 0.6), Color(0.76, 0.66, 0.46), Color(0.94, 0.88, 0.7)],
	[Color(0.25, 0.12, 0.14), Color(0.85, 0.4, 0.2), Color(0.3, 0.18, 0.18), Color(0.2, 0.12, 0.12),
			Color(0.15, 0.1, 0.08), Color(0.32, 0.22, 0.2), Color(0.22, 0.14, 0.12), Color(0.4, 0.3, 0.18)],
	# night jungle: the jungle after dark (everything in it is dimmed blue too: see build)
	[Color(0.03, 0.04, 0.12), Color(0.12, 0.16, 0.32), Color(0.1, 0.12, 0.22), Color(0.07, 0.12, 0.13),
			Color(0.06, 0.14, 0.09), Color(0.2, 0.15, 0.13), Color(0.13, 0.1, 0.09), Color(0.12, 0.22, 0.12)],
]
const NAMES := ["JUNGLE", "BADLANDS", "DESERT", "SWAMP", "COAST", "VOLCANO", "NIGHT JUNGLE"]
## Patches of ground that change how you move (owner's picks, 26 Oct; all numbers PLACEHOLDERS): WATER in the
## swamp slows every creature wading through it, LAVA in the volcano scorches you and burns creatures' feet,
## SAND (quicksand) in the desert slows and sinks.
enum { WATER, LAVA, SAND }
const HAZARD_OF := {"SWAMP": WATER, "VOLCANO": LAVA, "DESERT": SAND}
## How fast anything moves through each (WATER, LAVA, SAND), and how deep it sinks into quicksand.
const HAZARD_SPEED := [0.5, 1.0, 0.45]
const SINK := 5.0
## What a herd is made of. LONE kinds come one at a time; every area has at least one of each GUARANTEED kind
## (the newer dinosaurs, so a normal run meets them).
enum { HERD_GRAZER, HERD_RUNNER, HERD_CHARGER, HERD_ANKYLO, HERD_COMPY, HERD_GALLI, HERD_CORYTHO }
const LONE := [HERD_CHARGER, HERD_ANKYLO]
const GUARANTEED := [HERD_ANKYLO, HERD_COMPY, HERD_GALLI, HERD_CORYTHO]

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
## This area's look (one of NAMES).
var look := "JUNGLE"
## Ground patches: [x0, x1, kind (WATER, LAVA, SAND)], on the flat ground only.
var hazards: Array = []
## The lava's sprites (they glow and dim).
var _lava: Array[Sprite2D] = []
var _t := 0.0

var _rng := RandomNumberGenerator.new()

## Lays the area out (no nodes yet): its length, obstacles, herds.
func generate(n: int, run_seed: int, ground_y: float) -> void:
	number = n
	ground_y_ = ground_y
	seed_value = hash([run_seed, n])
	_rng.seed = seed_value
	palette = PALETTES[(n - 1) % PALETTES.size()]
	look = NAMES[(n - 1) % NAMES.size()]
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
			# on the coast it's mostly driftwood
			if _rng.randf() < (0.2 if look == "COAST" else 0.55):
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
				herds.append([x + w * 0.5, _herd_size(kind, 2), kind])
			x += w
		elif roll < 0.7:
			# a rock shelf in the air: jump up through it and stand on it
			var w := _rng.randi_range(40, 72)
			platforms.append(Rect2(x, ground_y - _rng.randi_range(28, 36), w, 6))
		else:
			var kind := herd_kind(_rng)
			herds.append([x + _rng.randf_range(-40.0, 40.0), _herd_size(kind, 2 + mini(n, 2)), kind])
		x += _rng.randf_range(170.0, 380.0)
	# at least one of each newer kind, in the first half or so (one of the herds there becomes it)
	for kind: int in GUARANTEED:
		if herds.any(func(hd: Array) -> bool: return hd[2] == kind and hd[0] < width * 0.6):
			continue
		# turn an ordinary herd early on into this kind, or add one if there's none to spare
		var early := herds.filter(func(hd: Array) -> bool: return hd[0] < width * 0.6 and not GUARANTEED.has(hd[2]))
		if early.is_empty():
			herds.append([_rng.randf_range(width * 0.15, width * 0.6), _herd_size(kind, 2), kind])
		else:
			var hd: Array = early[_rng.randi() % early.size()]
			hd[1] = _herd_size(kind, 2)
			hd[2] = kind
	# always something to eat near the start
	herds.push_front([300.0, 2, HERD_RUNNER])
	_place_hazards()

## This look's ground patches, on flat open ground (clear of rocks, logs and raised ground, of each other, and of
## the start and the exit). Placed last, so the rest of the area is the same as without them.
func _place_hazards() -> void:
	hazards.clear()
	if not HAZARD_OF.has(look):
		return
	var kind: int = HAZARD_OF[look]
	# [how many, narrowest, widest] for WATER, LAVA, SAND
	var spec: Array = [[5, 60, 140], [8, 16, 36], [4, 40, 80]][kind]
	var want: int = spec[0] + number / 4
	for tries in want * 12:
		if hazards.size() >= want:
			break
		var w := float(_rng.randi_range(spec[1], spec[2]))
		var x0 := _rng.randf_range(420.0, width - 320.0 - w)
		var clear := true
		for o: Rect2 in obstacles:
			if x0 < o.end.x + 18.0 and x0 + w > o.position.x - 18.0:
				clear = false
		for hz: Array in hazards:
			if x0 < hz[1] + 40.0 and x0 + w > hz[0] - 40.0:
				clear = false
		if clear:
			hazards.append([x0, x0 + w, kind])

## The ground patch under feet at (`x`, `feet_y`), or -1. Only on the flat ground (not raised ground or rocks).
func hazard_at(x: float, feet_y: float) -> int:
	if feet_y < ground_y_ - 1.5:
		return -1
	for hz: Array in hazards:
		if x >= hz[0] and x <= hz[1]:
			return hz[2]
	return -1

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
	match look:
		"DESERT":
			# low smooth dunes that shimmer in the heat, and stubby cycads
			var shimmer := ShaderMaterial.new()
			shimmer.shader = _shimmer_shader()
			_add_layer(_ridge(960, 120, 46.0, 0.006, palette[2]), 0.15, ground_y - 120).material = shimmer
			_add_layer(_ridge(960, 90, 26.0, 0.014, palette[3]), 0.4, ground_y - 88).material = shimmer
			_add_layer(_cycads(960, 50, palette[4]), 0.7, ground_y - 46)
		"COAST":
			# a far headland, the sea with surf breaking along it, a few palms on the beach
			_add_layer(_ridge(960, 120, 50.0, 0.01, palette[2]), 0.15, ground_y - 120)
			_add_layer(_sea(960, 64, palette[3]), 0.4, ground_y - 62)
			_add_layer(_jungle(960, 70, palette[4], 120, 260, false), 0.7, ground_y - 66)
		"NIGHT JUNGLE":
			sky_layer.add_child(_night_sky(view))
			_add_layer(_ridge(960, 120, 70.0, 0.012, palette[2]), 0.15, ground_y - 120)
			_add_layer(_ridge(960, 90, 40.0, 0.03, palette[3]), 0.4, ground_y - 88)
			_add_layer(_jungle(960, 70, palette[4]), 0.7, ground_y - 66)
			# everything down here is in the dark too, the dinosaurs included; the fireflies glow through it
			var dark := CanvasModulate.new()
			dark.color = Color(0.5, 0.56, 0.82)
			add_child(dark)
			add_child(_fireflies(ground_y))
		_:
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

	for hz: Array in hazards:
		var w := int(hz[1] - hz[0])
		match hz[2]:
			WATER:
				# a dark muddy bed on the ground, and the water itself over the feet of whatever wades in
				_ground_patch(_mud(w), Vector2(hz[0], ground_y - 3), -4)
				_ground_patch(_water(w), Vector2(hz[0], ground_y - 7), 3)
			LAVA:
				_lava.append(_ground_patch(_lava_crack(w), Vector2(hz[0], ground_y - 3), -4))
			SAND:
				_ground_patch(_quicksand(w, light), Vector2(hz[0], ground_y - 3), -4)

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

func _add_layer(img: Image, scroll: float, y: float) -> Sprite2D:
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
	return s

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

## The lava glows brighter and dimmer.
func _process(delta: float) -> void:
	_t += delta
	for k in _lava.size():
		var v := 0.85 + 0.25 * sin(_t * 3.0 + k * 1.7)
		_lava[k].modulate = Color(v, v, v)

func _ground_patch(img: Image, at: Vector2, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.position = at
	s.z_index = z
	add_child(s)
	return s

## The swamp's muddy bottom (where the water is).
func _mud(w: int) -> Image:
	var img := Image.create(w, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in w:
			if (x < 3 or x >= w - 3) and y > x % 3 + 1:
				continue
			img.set_pixel(x, y, Color(0.16, 0.18, 0.12) if (x * 3 + y * 5) % 7 else Color(0.22, 0.24, 0.16))
	return img

## Swamp water, see-through, with a lighter rippled surface line: drawn over the wader's feet.
func _water(w: int) -> Image:
	var img := Image.create(w, 10, false, Image.FORMAT_RGBA8)
	for y in range(1, 10):
		for x in w:
			var edge := mini(x, w - 1 - x)
			if edge < 3 and y < 4 - edge:
				continue
			var c := Color(0.24, 0.42, 0.38, 0.55)
			if y == 1 or (y == 2 and (x / 3) % 4 == 0):
				c = Color(0.62, 0.8, 0.72, 0.85)
			img.set_pixel(x, y, c)
	return img

## A glowing crack in the volcano's ground: yellow-hot in the middle, orange, then dark red at the edges.
func _lava_crack(w: int) -> Image:
	var img := Image.create(w, 6, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = _rng.randi()
	n.frequency = 0.25
	for x in w:
		var taper := minf(1.0, minf(x, w - 1 - x) / 4.0)
		var half := (1.5 + n.get_noise_1d(x) * 1.5) * taper
		for y in 6:
			var d := absf(y - 2.5)
			if d > half + 1.0:
				continue
			var c := Color(0.45, 0.06, 0.04)
			if d <= half * 0.4:
				c = Color(1.0, 0.92, 0.45)
			elif d <= half:
				c = Color(1.0, 0.5, 0.1)
			img.set_pixel(x, y, c)
	return img

## Quicksand: dark wet sand swirling in rings, with a pale dry rim round it.
func _quicksand(w: int, sand: Color) -> Image:
	var img := Image.create(w, 6, false, Image.FORMAT_RGBA8)
	var mid := w * 0.5
	var wet := sand.darkened(0.3).lerp(Color(0.45, 0.33, 0.2), 0.3)
	for y in 6:
		for x in w:
			var edge := mini(x, w - 1 - x)
			if edge < 3 and y < 3 - edge:
				continue
			var c := wet
			if int(absf(x - mid) * 0.3 + y * 0.8) % 4 == 0:
				c = wet.lightened(0.2)
			if edge < 2 or y == 0:
				c = sand.lightened(0.15)
			img.set_pixel(x, y, c)
	return img

## Palms (`gap_lo`..`gap_hi` apart), with undergrowth along the bottom unless `bushes` is off (a beach).
func _jungle(w: int, h: int, leaf: Color, gap_lo := 40, gap_hi := 90, bushes := true) -> Image:
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
		x += _rng.randi_range(gap_lo, gap_hi)
	if bushes:
		for y in range(h - 10, h):
			for xx in w:
				if _rng.randf() < 0.7 - (h - y) * 0.06:
					img.set_pixel(xx, y, leaf.darkened(0.1))
	return img

## Cycads for the desert: a short thick scaly trunk with a crown of stiff fronds, now and then a low shrub.
func _cycads(w: int, h: int, leaf: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var trunk := Color(0.45, 0.35, 0.22)
	var x := 14
	while x < w - 20:
		var th := _rng.randi_range(8, 20)
		for y in range(h - th, h):
			for dx in range(-2, 3):
				img.set_pixel(x + dx, y, trunk.darkened(0.25) if (y + dx) % 3 == 0 else trunk)
		# stiff fronds fanning up and out
		for f in 7:
			var a := -PI * 0.5 + (f - 3) * 0.42
			var p := Vector2(x, h - th)
			for s in 10:
				p += Vector2(cos(a), sin(a) + s * 0.04)
				var px := int(p.x)
				var py := int(p.y)
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, leaf if s < 8 else leaf.lightened(0.15))
		# a low dry shrub between
		var sx := x + _rng.randi_range(30, 50)
		for k in 12:
			var px := sx + _rng.randi_range(-6, 6)
			var py := h - 1 - _rng.randi_range(0, 4)
			if px >= 0 and px < w:
				img.set_pixel(px, py, leaf.lerp(Color(0.6, 0.5, 0.3), 0.5))
		x += _rng.randi_range(70, 150)
	return img

## The sea seen from the beach: flat bands of water darkening to the horizon, light wave lines, and a white line
## of surf along the bottom where it breaks.
func _sea(w: int, h: int, water: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = _rng.randi()
	n.frequency = 0.05
	var top := 18
	for y in range(top, h):
		var k := float(y - top) / (h - top)
		var c := water.darkened(0.25).lerp(water.lightened(0.1), k)
		for x in w:
			var v := lerpf(n.get_noise_2d(x, y * 3.0), n.get_noise_2d(x - w, y * 3.0), float(x) / w)
			var px := c
			if v > 0.35:
				px = c.lightened(0.25)
			if y >= h - 4 and v > -0.3 - (y - (h - 4)) * 0.2:
				px = Color(0.95, 0.97, 1.0)
			img.set_pixel(x, y, px)
	return img

## Stars and a big moon, over the night sky.
func _night_sky(view: Vector2) -> TextureRect:
	var img := Image.create(int(view.x), int(view.y), false, Image.FORMAT_RGBA8)
	for k in 90:
		var x := _rng.randi_range(0, int(view.x) - 1)
		var y := _rng.randi_range(0, int(view.y * 0.55))
		img.set_pixel(x, y, Color(1, 1, 0.9, _rng.randf_range(0.4, 1.0)))
	var mc := Vector2(view.x * 0.78, view.y * 0.2)
	for y in range(int(mc.y) - 14, int(mc.y) + 15):
		for x in range(int(mc.x) - 14, int(mc.x) + 15):
			var d := Vector2(x, y).distance_to(mc)
			if d <= 13.0:
				var c := Color(0.95, 0.93, 0.8)
				# a few darker patches, and a soft shadow on one side
				if Vector2(x, y).distance_to(mc + Vector2(-4, -3)) < 3.0 or Vector2(x, y).distance_to(mc + Vector2(5, 4)) < 2.0:
					c = c.darkened(0.15)
				if x > mc.x + 6:
					c = c.darkened(0.1)
				img.set_pixel(x, y, c)
			elif d <= 18.0:
				img.set_pixel(x, y, Color(0.9, 0.9, 0.8, 0.12))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.size = view
	return tr

## Fireflies drifting over the undergrowth, all along the area, glowing through the dark.
func _fireflies(ground_y: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(40, width / 14)
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.position = Vector2(width * 0.5, ground_y - 40.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(width * 0.5, 34.0)
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.7, 2.0, 0.7, 0.0))
	ramp.set_color(1, Color(1.7, 2.0, 0.7, 0.0))
	ramp.add_point(0.3, Color(1.7, 2.0, 0.7, 1.0))
	ramp.add_point(0.7, Color(1.7, 2.0, 0.7, 1.0))
	p.color_ramp = ramp
	p.z_index = 2
	return p

## The heat shimmer on the desert's dunes: each row wobbles sideways a little.
func _shimmer_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\n" \
				+ "void fragment() { vec2 uv = UV; uv.x += sin(TIME * 2.5 + UV.y * 70.0) * 0.0012; COLOR = texture(TEXTURE, uv); }"
	return sh

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

## How many in a herd of `kind`: one for the LONE kinds, a little group of compys, a few gallimimus or
## corythosaurus, else 1 to `most`. PLACEHOLDER numbers.
func _herd_size(kind: int, most: int) -> int:
	match kind:
		HERD_COMPY:
			return _rng.randi_range(3, 5)
		HERD_GALLI:
			return _rng.randi_range(2, 4)
		HERD_CORYTHO:
			return _rng.randi_range(2, 3)
	return 1 if kind in LONE else _rng.randi_range(1, most)

## A random kind of herd. PLACEHOLDER mix (owner: "more variety", 26 Oct), in shares of 100: runners 18, compys 12,
## grazers 16, gallimimus 12, corythosaurus 12, chargers 12, ankylosaurus 18.
func herd_kind(rng: RandomNumberGenerator) -> int:
	var r := rng.randf() * 100.0
	for kind_share: Array in [[HERD_RUNNER, 18], [HERD_COMPY, 12], [HERD_GRAZER, 16], [HERD_GALLI, 12],
			[HERD_CORYTHO, 12], [HERD_CHARGER, 12]]:
		if r < kind_share[1]:
			return kind_share[0]
		r -= kind_share[1]
	return HERD_ANKYLO
