extends RefCounted
## PLACEHOLDER dinosaur art, drawn in code until the real sprites exist. Each dinosaur is a few parts (body, legs,
## and for the player a head and lower jaw that move), each a small image plus a zone map (which pixel is head,
## neck, body, tail or leg). All art faces right (+X); the dinosaur's origin is between its feet, on the ground.
##
## A part is a Dictionary: name, image, zones, pivot (the pixel the part turns about), pos (where the pivot sits
## in its parent), anchors (pixels that hold it on), z (draw order), parent ("" = the rig), and for legs "leg".

const NONE := 0
const HEAD := 1
const NECK := 2
const BODY := 3
const TAIL := 4
const LEGS := 5
const WING := 6
const ZONE_NAMES := ["", "HEAD", "NECK", "BODY", "TAIL", "LEGS", "WING"]

## Draws shapes into a zone map, then paints it: skin, a lighter belly, a light top edge, back stripes, outline.
class Canvas:
	var w: int
	var h: int
	var zones := PackedByteArray()
	var marks := {}

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		zones.resize(w * h)

	func ellipse(cx: float, cy: float, rx: float, ry: float, z: int) -> void:
		for y in range(floori(cy - ry), ceili(cy + ry) + 1):
			for x in range(floori(cx - rx), ceili(cx + rx) + 1):
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0:
					zones[y * w + x] = z

	func poly(points: PackedVector2Array, z: int) -> void:
		var lo := points[0]
		var hi := points[0]
		for p in points:
			lo = lo.min(p)
			hi = hi.max(p)
		for y in range(maxi(0, floori(lo.y)), mini(h - 1, ceili(hi.y)) + 1):
			for x in range(maxi(0, floori(lo.x)), mini(w - 1, ceili(hi.x)) + 1):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
					zones[y * w + x] = z

	func rect(x0: int, y0: int, x1: int, y1: int, z: int) -> void:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x >= 0 and y >= 0 and x < w and y < h:
					zones[y * w + x] = z

	## A fixed colour on one pixel (eyes, teeth, claws), painted over everything else. The pixel must be solid.
	func mark(x: int, y: int, c: Color) -> void:
		marks[y * w + x] = c

	func solid(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and zones[y * w + x] != NONE

	func paint(skin: Color, belly: Color, stripe: Color) -> Image:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in h:
			for x in w:
				if not solid(x, y):
					continue
				var c := skin
				# belly: within 2 pixels of the underside (not on the tail tip or the legs)
				if not solid(x, y + 3) and solid(x, y - 2) and zones[y * w + x] != LEGS:
					c = belly
				# stripes across the back
				elif not solid(x, y - 3) and (x + y / 2) % 7 < 2:
					c = stripe
				if not solid(x, y - 1):
					c = c.lightened(0.18)
				if not solid(x - 1, y) or not solid(x + 1, y) or not solid(x, y - 1) or not solid(x, y + 1):
					c = c.darkened(0.55)
				img.set_pixel(x, y, c)
		for i: int in marks:
			if zones[i] != NONE:
				img.set_pixel(i % w, i / w, marks[i])
		return img

	## Every solid pixel of zone `z` (for anchors).
	func pixels_of(z: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		for i in w * h:
			if zones[i] == z:
				out.append(i)
		return out

const EYE := Color(0.95, 0.85, 0.2)
const PUPIL := Color(0.05, 0.03, 0.02)
const TOOTH := Color(0.96, 0.94, 0.86)
const MOUTH := Color(0.25, 0.04, 0.05)
const PLAYER_SKIN := Color(0.32, 0.5, 0.3)

## A leg: thigh, shin, foot pointing forward. Pivot (the hip) near the top. `len` is hip to sole.
static func _leg(width: int, length: int, skin: Color, claw: bool) -> Dictionary:
	var c := Canvas.new(width + 4, length + 4)
	var mid := width * 0.5 + 1.0
	c.ellipse(mid, 4.0, width * 0.5, 5.0, LEGS)
	c.rect(int(mid) - 1, 6, int(mid) + 1, length, LEGS)
	c.rect(int(mid) - 2, length + 1, int(mid) + 4, length + 2, LEGS)
	if claw:
		c.mark(int(mid) + 4, length + 2, TOOTH)
	var img := c.paint(skin, skin, skin)
	var anchors := PackedInt32Array()
	for y in 3:
		for x in c.w:
			if c.solid(x, y + 1):
				anchors.append((y + 1) * c.w + x)
	return {"image": img, "zones": c.zones, "pivot": Vector2(mid, 3.0), "anchors": anchors, "length": length - 1}

## The prey: a long-necked plant-eater shape on four legs. PLACEHOLDER (which dinosaurs are prey isn't decided).
static func prey() -> Dictionary:
	var skin := Color(0.6, 0.6, 0.36)
	var belly := Color(0.85, 0.8, 0.58)
	var stripe := Color(0.42, 0.38, 0.22)
	var c := Canvas.new(98, 42)
	c.poly(PackedVector2Array([Vector2(32, 20), Vector2(6, 25), Vector2(1, 28), Vector2(6, 30), Vector2(32, 34)]), TAIL)
	c.ellipse(48, 27, 20, 11, BODY)
	c.poly(PackedVector2Array([Vector2(60, 22), Vector2(77, 6), Vector2(84, 10), Vector2(69, 31)]), NECK)
	c.ellipse(84, 8, 7, 5, HEAD)
	c.ellipse(91, 10, 5, 3, HEAD)
	c.mark(85, 6, EYE)
	c.mark(86, 6, PUPIL)
	for x in range(89, 96):
		c.mark(x, 11, MOUTH)
	var body := {"name": "body", "image": c.paint(skin, belly, stripe), "zones": c.zones, "pivot": Vector2(48, 33),
			"pos": Vector2(0, -15), "anchors": _core(c, 48, 27, 6), "z": 0, "parent": ""}
	var parts := [body]
	var leg := _leg(7, 15, skin, false)
	var far := _leg(7, 15, skin.darkened(0.3), false)
	# far legs behind the body (darker), near legs in front; back pair at the hips, front pair at the shoulders
	for spec in [[far, -10, -1, 0.0], [far, 14, -1, PI], [leg, -14, 1, PI], [leg, 10, 1, 0.0]]:
		var l: Dictionary = spec[0]
		parts.append({"name": "leg", "image": l.image, "zones": l.zones, "pivot": l.pivot,
				"pos": Vector2(spec[1], -16), "anchors": l.anchors, "z": spec[2], "parent": "", "leg": spec[3]})
	return {"parts": parts, "height": 44}

## A small fast plant-eater on two legs: long tail, little head. PLACEHOLDER.
static func runner() -> Dictionary:
	var skin := Color(0.62, 0.5, 0.3)
	var belly := Color(0.88, 0.8, 0.6)
	var stripe := Color(0.4, 0.3, 0.16)
	var c := Canvas.new(36, 18)
	c.poly(PackedVector2Array([Vector2(13, 7), Vector2(0, 5), Vector2(0, 7), Vector2(13, 12)]), TAIL)
	c.ellipse(17, 10, 7, 4.5, BODY)
	c.poly(PackedVector2Array([Vector2(21, 8), Vector2(27, 3), Vector2(29, 5), Vector2(23, 12)]), NECK)
	c.ellipse(30, 4, 3.5, 2.5, HEAD)
	c.ellipse(33, 5, 2.5, 1.5, HEAD)
	c.mark(30, 3, PUPIL)
	var body := {"name": "body", "image": c.paint(skin, belly, stripe), "zones": c.zones, "pivot": Vector2(17, 12),
			"pos": Vector2(0, -11), "anchors": _core(c, 17, 10, 3), "z": 0, "parent": ""}
	var parts := [body]
	var leg := _leg(5, 10, skin, false)
	var far := _leg(5, 10, skin.darkened(0.3), false)
	parts.append({"name": "leg", "image": far.image, "zones": far.zones, "pivot": far.pivot, "pos": Vector2(1, -11),
			"anchors": far.anchors, "z": -1, "parent": "", "leg": PI})
	parts.append({"name": "leg", "image": leg.image, "zones": leg.zones, "pivot": leg.pivot, "pos": Vector2(-1, -11),
			"anchors": leg.anchors, "z": 1, "parent": "", "leg": 0.0})
	return {"parts": parts, "height": 22}

## A big horned plant-eater on four legs that fights back: a bony frill and two horns on a big low head.
## PLACEHOLDER.
static func charger() -> Dictionary:
	var skin := Color(0.45, 0.5, 0.52)
	var belly := Color(0.7, 0.68, 0.6)
	var stripe := Color(0.3, 0.33, 0.36)
	var c := Canvas.new(96, 40)
	c.poly(PackedVector2Array([Vector2(24, 18), Vector2(2, 24), Vector2(0, 27), Vector2(24, 30)]), TAIL)
	c.ellipse(44, 24, 22, 13, BODY)
	c.poly(PackedVector2Array([Vector2(60, 16), Vector2(70, 14), Vector2(72, 30), Vector2(62, 32)]), NECK)
	# the frill, the head, the beak, the horns
	c.ellipse(72, 14, 7, 11, HEAD)
	c.ellipse(80, 22, 9, 7, HEAD)
	c.poly(PackedVector2Array([Vector2(86, 19), Vector2(93, 22), Vector2(87, 27)]), HEAD)
	c.poly(PackedVector2Array([Vector2(78, 16), Vector2(92, 9), Vector2(80, 19)]), HEAD)
	c.poly(PackedVector2Array([Vector2(86, 21), Vector2(90, 15), Vector2(88, 22)]), HEAD)
	c.mark(81, 19, EYE)
	c.mark(82, 19, PUPIL)
	var img := c.paint(skin, belly, stripe)
	# the frill's rim and the horns in bone
	for y in c.h:
		for x in c.w:
			var i := y * c.w + x
			if c.zones[i] == HEAD and ((x > 84 and y < 18) or (x >= 88 and y < 21)):
				img.set_pixel(x, y, TOOTH.darkened(0.15))
	var body := {"name": "body", "image": img, "zones": c.zones, "pivot": Vector2(44, 34),
			"pos": Vector2(0, -15), "anchors": _core(c, 44, 24, 7), "z": 0, "parent": ""}
	var parts := [body]
	var leg := _leg(9, 15, skin, false)
	var far := _leg(9, 15, skin.darkened(0.3), false)
	for spec in [[far, -12, -1, 0.0], [far, 16, -1, PI], [leg, -16, 1, PI], [leg, 12, 1, 0.0]]:
		var l: Dictionary = spec[0]
		parts.append({"name": "leg", "image": l.image, "zones": l.zones, "pivot": l.pivot,
				"pos": Vector2(spec[1], -16), "anchors": l.anchors, "z": spec[2], "parent": "", "leg": spec[3]})
	return {"parts": parts, "height": 42}

## A pterodactyl: a small body, a long beak and a crest, and two wings that flap (separate parts, WING zone).
## Its origin is its body (it flies). PLACEHOLDER.
static func flyer() -> Dictionary:
	var skin := Color(0.55, 0.42, 0.45)
	var belly := Color(0.82, 0.7, 0.66)
	var stripe := Color(0.36, 0.24, 0.28)
	var c := Canvas.new(44, 16)
	c.poly(PackedVector2Array([Vector2(10, 8), Vector2(1, 7), Vector2(1, 9), Vector2(10, 10)]), TAIL)
	c.ellipse(16, 9, 7, 4, BODY)
	c.poly(PackedVector2Array([Vector2(20, 7), Vector2(26, 4), Vector2(28, 7), Vector2(22, 11)]), NECK)
	c.ellipse(30, 5, 3.5, 3, HEAD)
	c.poly(PackedVector2Array([Vector2(31, 4), Vector2(43, 7), Vector2(31, 7)]), HEAD)
	c.poly(PackedVector2Array([Vector2(28, 3), Vector2(21, 0), Vector2(30, 2)]), HEAD)
	c.mark(30, 4, EYE)
	c.rect(14, 12, 15, 14, BODY)
	c.rect(18, 12, 19, 14, BODY)
	var body := {"name": "body", "image": c.paint(skin, belly, stripe), "zones": c.zones, "pivot": Vector2(16, 9),
			"pos": Vector2.ZERO, "anchors": _core(c, 16, 9, 3), "z": 0, "parent": ""}
	var parts := [body]
	for spec in [[skin.darkened(0.35), -1], [skin, 1]]:
		var wc := Canvas.new(34, 11)
		wc.poly(PackedVector2Array([Vector2(0, 9), Vector2(4, 6), Vector2(30, 0), Vector2(33, 1), Vector2(12, 10)]), WING)
		var wimg := wc.paint(spec[0], (spec[0] as Color).lightened(0.15), spec[0])
		var anchors := PackedInt32Array()
		for y in range(6, 11):
			for x in range(0, 5):
				if wc.solid(x, y):
					anchors.append(y * wc.w + x)
		parts.append({"name": "wing", "image": wimg, "zones": wc.zones, "pivot": Vector2(2, 8),
				"pos": Vector2(-1, -2), "anchors": anchors, "z": spec[1], "parent": "", "wing": true})
	return {"parts": parts, "height": 16}

## The hunter that comes after you: the player's shape in reds. PLACEHOLDER (which dinosaurs hunt you isn't decided).
static func hunter() -> Dictionary:
	return player(Color(0.56, 0.27, 0.2), Color(0.86, 0.66, 0.46), Color(0.26, 0.1, 0.08))

## The player: a raptor-ish shape on two legs with a head and jaw that move. PLACEHOLDER (which dinosaur you start
## as isn't decided).
static func player(skin := PLAYER_SKIN, belly := Color(0.78, 0.74, 0.52), stripe := Color(0.18, 0.26, 0.14)) -> Dictionary:
	var c := Canvas.new(52, 26)
	c.poly(PackedVector2Array([Vector2(18, 9), Vector2(1, 5), Vector2(0, 8), Vector2(18, 18)]), TAIL)
	c.ellipse(26, 14, 11, 7, BODY)
	c.poly(PackedVector2Array([Vector2(31, 10), Vector2(40, 2), Vector2(46, 6), Vector2(36, 18)]), NECK)
	c.rect(35, 15, 37, 16, BODY)
	c.rect(37, 16, 38, 18, BODY)
	var body := {"name": "body", "image": c.paint(skin, belly, stripe), "zones": c.zones, "pivot": Vector2(26, 17),
			"pos": Vector2(0, -17), "anchors": _core(c, 26, 14, 5), "z": 0, "parent": ""}

	var hd := Canvas.new(27, 13)
	hd.ellipse(7, 6, 6, 5, HEAD)
	hd.poly(PackedVector2Array([Vector2(6, 2), Vector2(25, 5), Vector2(26, 8), Vector2(6, 10)]), HEAD)
	hd.mark(7, 4, EYE)
	hd.mark(8, 4, PUPIL)
	for x in range(10, 25, 2):
		hd.mark(x, 8, TOOTH)
	var head := {"name": "head", "image": hd.paint(skin, skin, stripe), "zones": hd.zones, "pivot": Vector2(3, 7),
			"pos": Vector2(43 - 26, 5 - 17), "anchors": _core(hd, 6, 6, 3), "z": 2, "parent": "body", "tip": Vector2(25, 9)}

	var jw := Canvas.new(20, 5)
	jw.poly(PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 2), Vector2(0, 5)]), HEAD)
	for x in range(5, 19, 2):
		jw.mark(x, 0, TOOTH)
	var jaw := {"name": "jaw", "image": jw.paint(belly, belly, belly), "zones": jw.zones, "pivot": Vector2(1, 1),
			"pos": Vector2(5 - 3, 9 - 7), "anchors": _core(jw, 2, 2, 2), "z": -1, "parent": "head"}

	var parts := [body, head, jaw]
	var leg := _leg(9, 16, skin, true)
	var far := _leg(9, 16, skin.darkened(0.3), true)
	parts.append({"name": "leg", "image": far.image, "zones": far.zones, "pivot": far.pivot, "pos": Vector2(1, -16),
			"anchors": far.anchors, "z": -1, "parent": "", "leg": PI})
	parts.append({"name": "leg", "image": leg.image, "zones": leg.zones, "pivot": leg.pivot, "pos": Vector2(-1, -16),
			"anchors": leg.anchors, "z": 1, "parent": "", "leg": 0.0})
	return {"parts": parts, "height": 30}

## PLACEHOLDER obstacles. A rock: a lumpy grey boulder, `w` x `h`.
static func rock(w: int, h: int, rng: RandomNumberGenerator) -> Image:
	var c := Canvas.new(w, h)
	c.ellipse(w * 0.5, h * 0.62, w * 0.5, h * 0.62, BODY)
	for k in 3:
		c.ellipse(rng.randf_range(w * 0.25, w * 0.75), rng.randf_range(h * 0.3, h * 0.6), w * 0.28, h * 0.4, BODY)
	c.rect(0, h - 2, w - 1, h - 1, BODY)
	var grey := Color(0.5, 0.49, 0.47).darkened(rng.randf_range(0.0, 0.2))
	var img := c.paint(grey, grey.darkened(0.15), grey.darkened(0.1))
	for k in w * h / 14:
		var x := rng.randi() % w
		var y := rng.randi() % h
		if img.get_pixel(x, y).a > 0.0:
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12))
	return img

## A fallen log lying across the path, `w` long, `h` thick, with its cut ends showing rings.
static func log_image(w: int, h: int) -> Image:
	var c := Canvas.new(w, h)
	c.rect(0, 0, w - 1, h - 1, BODY)
	var bark := Color(0.4, 0.27, 0.16)
	var img := c.paint(bark, bark.darkened(0.2), bark.darkened(0.25))
	for y in range(1, h - 1):
		for x in [1, w - 2]:
			img.set_pixel(x, y, Color(0.78, 0.62, 0.4) if (y + x) % 3 != 0 else Color(0.6, 0.45, 0.28))
	return img

## The way on, at the far end of an area: a post with an arrow board.
static func sign_image() -> Image:
	var img := Image.create(24, 30, false, Image.FORMAT_RGBA8)
	var wood := Color(0.55, 0.38, 0.22)
	for y in range(8, 30):
		img.set_pixel(10, y, wood.darkened(0.3))
		img.set_pixel(11, y, wood)
	for y in range(1, 10):
		for x in range(0, 18 + mini(y, 10 - y)):
			if x < 18 or x - 18 < mini(y, 10 - y):
				img.set_pixel(x, y, wood.lightened(0.1) if y > 1 else wood.lightened(0.3))
	for x in range(3, 15):
		img.set_pixel(x, 5, Color(0.2, 0.1, 0.05))
	for k in 3:
		img.set_pixel(14 - k, 5 - k, Color(0.2, 0.1, 0.05))
		img.set_pixel(14 - k, 5 + k, Color(0.2, 0.1, 0.05))
	return img

## Solid pixels within `r` of (cx, cy): what holds a part together.
static func _core(c: Canvas, cx: int, cy: int, r: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if c.solid(x, y) and Vector2(x - cx, y - cy).length() <= r:
				out.append(y * c.w + x)
	return out
