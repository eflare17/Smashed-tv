class_name ArtLoader
extends RefCounted
## Builds a creature's rig from the imported sprites (art/<creature>_<part>.png, made by tools/import_sheets.gd):
## the same part dictionaries DinoArt's placeholders make, so Dino.build takes either. The sprites keep their own
## pixel size (finer than the placeholders, so bites look better) and the rig is scaled by `k` to the size the
## game wants. Where things sit (hips, the neck, the jaw hinge, the teeth, the beak) is found from the pictures
## by simple rules, and the zones (head, neck, body, tail, legs, wing) are painted by position. All of that is a
## first guess to be tuned by eye, per creature, in SPECS.

const DinoArt := preload("dino_art.gd")

## Per creature: the body width the game wants (game px, before the form's own size for the player's forms:
## those come out at 26, 52, 68 and 104 after Player.STAGES' sizes), which legs (two or four), and the zone splits as
## fractions of the body picture: tail = left of `tail`, neck = right of `neck` (and above `neck_y`), head =
## right of `head` (and above `head_y`) for bodies that include the head.
const SPECS := {
	"hatchling": {"width": 52.0, "legs": 2, "tail": 0.32, "neck": 0.8},
	"raptor": {"width": 65.0, "legs": 2, "tail": 0.3, "neck": 0.78},
	"allosaur": {"width": 52.0, "legs": 2, "tail": 0.3, "neck": 0.8},
	"tyrant": {"width": 52.0, "legs": 2, "tail": 0.28, "neck": 0.78},
	"grazer": {"stand": 54.0, "legs": 4, "hips": [0.42, 0.72], "hip_y": 0.86, "tail": 0.36, "neck": 0.76, "neck_y": 0.62, "head": 0.86, "head_y": 0.3},
	"runner": {"width": 36.0, "legs": 2, "tail": 0.42, "neck": 0.78, "head": 0.88, "head_y": 0.6},
	"charger": {"width": 96.0, "legs": 4, "tail": 0.2, "head": 0.66, "head_y": 1.0},
	"flyer": {"width": 44.0, "legs": 0, "tail": 0.25, "neck": 0.55, "head": 0.68, "head_y": 1.0},
}

## Which creatures use their imported sprites. Off by default: each is switched on once its rig has been checked
## by eye (hinges, sizes, which piece is which); until then the code-drawn placeholder is used.
const ENABLED := {
	"hatchling": false, "raptor": false, "allosaur": false, "tyrant": false,
	"grazer": true, "runner": true, "charger": false, "flyer": false,
}

static var _cache := {}

static func has(creature: String) -> bool:
	return ResourceLoader.exists("res://art/%s_body.png" % creature) or FileAccess.file_exists("res://art/%s_body.png" % creature)

static func _load(creature: String, part: String) -> Image:
	var key := creature + "_" + part
	if _cache.has(key):
		return _cache[key]
	var path := "res://art/%s_%s.png" % [creature, part]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	_cache[key] = img
	return img

## The rig for `creature`, or {} if its sprites aren't there. `tint` recolours it (the hunter is a red raptor).
static func rig(creature: String, tint: Color = Color.WHITE) -> Dictionary:
	if not ENABLED.get(creature, false):
		return {}
	var spec: Dictionary = SPECS[creature]
	var body := _load(creature, "body")
	if body == null:
		return {}
	if tint != Color.WHITE:
		body = _tinted(body, tint)
	var bw := body.get_width()
	var bh := body.get_height()
	var k: float = spec.get("width", 50.0) / bw
	var parts: Array = []
	var legs: int = spec.legs
	var leg := _load(creature, "leg")
	var leg_len := 0
	if leg and legs > 0:
		if tint != Color.WHITE:
			leg = _tinted(leg, tint)
		leg_len = leg.get_height() - 2
	# the hips: where the legs hang from the body picture
	var hip_y := int(bh * spec.get("hip_y", 0.74 if legs == 2 else 0.8))
	var hips: Array = []
	for hx: float in spec.get("hips", [0.56] if legs == 2 else [0.24, 0.7]):
		hips.append(int(bw * hx))
	# sized by how tall it stands (feet to back), when the spec says so, else by its width
	if spec.has("stand"):
		k = spec.stand / float(leg_len + hip_y)
	# the origin (between the feet) sits under the middle of the hips
	var pivot := Vector2(hips[0] if legs == 2 else (hips[0] + hips[1]) * 0.5, hip_y)
	var body_zones := _body_zones(body, spec)
	# what holds the body together is its bulk, around the middle of its mass (never the head or the tail, or a
	# bite through the neck would send the body flying off instead of the head)
	var deep := _deepest(body)
	parts.append({"name": "body", "image": body, "zones": body_zones, "pivot": pivot,
			"pos": Vector2(0, -leg_len), "anchors": _core(body, int(deep.x), int(deep.y), maxi(2, mini(int(bh * 0.2), int(deep.z) - 1))),
			"z": 0, "parent": "", "front": _rightmost(body)})
	# legs: one picture, the far ones darker and behind
	if leg and legs > 0:
		var far: Image = leg.duplicate()
		_darken(far, 0.3)
		var lz := _leg_zones(leg)
		var lp := Vector2(leg.get_width() * 0.5, 2)
		var la := _rows(leg, 0, 2)
		if legs == 2:
			parts.append({"name": "leg", "image": far, "zones": lz, "pivot": lp, "pos": Vector2(2, -leg_len),
					"anchors": la, "z": -1, "parent": "", "leg": PI})
			parts.append({"name": "leg", "image": leg, "zones": lz, "pivot": lp, "pos": Vector2(-2, -leg_len),
					"anchors": la, "z": 1, "parent": "", "leg": 0.0})
		else:
			var mid := pivot.x
			for spec_leg in [[far, hips[0] - mid - 2, -1, 0.0], [far, hips[1] - mid + 2, -1, PI],
					[leg, hips[0] - mid + 2, 1, PI], [leg, hips[1] - mid - 2, 1, 0.0]]:
				parts.append({"name": "leg", "image": spec_leg[0], "zones": lz, "pivot": lp,
						"pos": Vector2(spec_leg[1], -leg_len), "anchors": la, "z": spec_leg[2], "parent": "", "leg": spec_leg[3]})
	# a separate head and jaw (the meat-eaters)
	var head := _load(creature, "head")
	if head:
		if tint != Color.WHITE:
			head = _tinted(head, tint)
		var neck_y := _left_middle(head)
		var hp := Vector2(2, neck_y)
		var neck_end := _neck_end(body, spec)
		parts.append({"name": "head", "image": head, "zones": _fill_zones(head, DinoArt.HEAD), "pivot": hp,
				"pos": neck_end - pivot + Vector2(-3, 1), "anchors": _core(head, int(_deepest(head).x), int(_deepest(head).y), 4), "z": 2, "parent": "body",
				"tip": _tip(head)})
		var jaw := _load(creature, "jaw")
		if jaw:
			if tint != Color.WHITE:
				jaw = _tinted(jaw, tint)
			var hinge := Vector2(head.get_width() * 0.22, head.get_height() * 0.72)
			parts.append({"name": "jaw", "image": jaw, "zones": _fill_zones(jaw, DinoArt.HEAD), "pivot": Vector2(1, 1),
					"pos": hinge - hp, "anchors": _core(jaw, 3, 2, 3), "z": -1, "parent": "head"})
	# wings (the flyer): one picture, far wing darker and behind
	var wing := _load(creature, "wing")
	if wing:
		var far_w: Image = wing.duplicate()
		_darken(far_w, 0.3)
		var wz := _fill_zones(wing, DinoArt.WING)
		var wp := Vector2(wing.get_width() * 0.3, 2)
		var wa := _rows(wing, 0, 3)
		var at := Vector2(bw * 0.42, bh * 0.35) - pivot
		parts.append({"name": "wing", "image": far_w, "zones": wz, "pivot": wp, "pos": at + Vector2(-2, 0),
				"anchors": wa, "z": -1, "parent": "", "wing": true})
		parts.append({"name": "wing", "image": wing, "zones": wz, "pivot": wp, "pos": at,
				"anchors": wa, "z": 1, "parent": "", "wing": true})
	var height := (leg_len + hip_y) * k if legs > 0 else bh * k
	# how far the body drops when it dies: most of the leg (in the rig's own pixels: the rig is scaled by k)
	return {"parts": parts, "height": height, "k": k, "half_w": bw * k * 0.3, "foot": (bh * 0.5 * k) if legs == 0 else 0.0,
			"drop": leg_len * 0.8}

# --- picture rules -----------------------------------------------------------------------------------------

static func _solid(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5

## Zones for a body picture, by position (see SPECS).
static func _body_zones(img: Image, spec: Dictionary) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var z := PackedByteArray()
	z.resize(w * h)
	for y in h:
		for x in w:
			if not _solid(img, x, y):
				continue
			var fx := float(x) / w
			var fy := float(y) / h
			var zone := DinoArt.BODY
			if fx < spec.tail:
				zone = DinoArt.TAIL
			if spec.has("neck") and fx > spec.neck and fy < spec.get("neck_y", 1.0):
				zone = DinoArt.NECK
			if spec.has("head") and fx > spec.head and fy < spec.get("head_y", 1.0):
				zone = DinoArt.HEAD
			z[y * w + x] = zone
	return z

static func _leg_zones(img: Image) -> PackedByteArray:
	return _fill_zones(img, DinoArt.LEGS)

static func _fill_zones(img: Image, zone: int) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var z := PackedByteArray()
	z.resize(w * h)
	for y in h:
		for x in w:
			if _solid(img, x, y):
				z[y * w + x] = zone
	return z

## Solid pixels within `r` of (cx, cy).
static func _core(img: Image, cx: int, cy: int, r: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var w := img.get_width()
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if _solid(img, x, y) and Vector2(x - cx, y - cy).length() <= r:
				out.append(y * w + x)
	if out.is_empty():
		# nothing solid there: take whatever is nearest the middle instead
		for y in img.get_height():
			for x in w:
				if _solid(img, x, y):
					out.append(y * w + x)
					if out.size() > 20:
						return out
	return out

## The solid pixel furthest from any edge (the thickest part of the picture): (x, y, that distance). A bite near
## an edge can't cut this off from the rest, so it's what holds the part together.
static func _deepest(img: Image) -> Vector3:
	var w := img.get_width()
	var h := img.get_height()
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue := PackedInt32Array()
	# every non-solid pixel (and the picture's border) is distance 0
	for y in h:
		for x in w:
			if not _solid(img, x, y) or x == 0 or y == 0 or x == w - 1 or y == h - 1:
				dist[y * w + x] = 0
				queue.append(y * w + x)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if dist[j] < 0:
				dist[j] = dist[i] + 1
				queue.append(j)
	var best := Vector3(w * 0.5, h * 0.5, 1)
	for i in w * h:
		if dist[i] > best.z:
			best = Vector3(i % w, i / w, dist[i])
	return best

## The solid pixel nearest the picture's centre of mass.
static func _mass_centre(img: Image) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if _solid(img, x, y):
				sum += Vector2(x, y)
				n += 1
	var c := sum / maxi(1, n)
	var best := c
	var bd := INF
	for y in img.get_height():
		for x in img.get_width():
			if _solid(img, x, y):
				var d := Vector2(x, y).distance_squared_to(c)
				if d < bd:
					bd = d
					best = Vector2(x, y)
	return best

## Solid pixels in rows y0..y1.
static func _rows(img: Image, y0: int, y1: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var w := img.get_width()
	for y in range(y0, y1 + 1):
		for x in w:
			if _solid(img, x, y):
				out.append(y * w + x)
	return out

## The middle of the leftmost solid column (where a head joins its neck).
static func _left_middle(img: Image) -> int:
	for x in img.get_width():
		var ys: Array = []
		for y in img.get_height():
			if _solid(img, x, y):
				ys.append(y)
		if ys.size() > 0:
			return int((ys[0] + ys[ys.size() - 1]) * 0.5)
	return img.get_height() / 2

## The top of the body's neck: the topmost solid pixel in the right part of the picture.
static func _neck_end(img: Image, spec: Dictionary) -> Vector2:
	var w := img.get_width()
	var x0 := int(w * spec.get("neck", 0.75))
	for y in img.get_height():
		for x in range(w - 1, x0, -1):
			if _solid(img, x, y):
				return Vector2(x, y)
	return Vector2(w - 2, 2)

## Where the teeth meet: the rightmost solid pixel in the lower half of a head.
static func _tip(img: Image) -> Vector2:
	var h := img.get_height()
	for x in range(img.get_width() - 1, -1, -1):
		for y in range(h - 1, h / 3, -1):
			if _solid(img, x, y):
				return Vector2(x, y)
	return Vector2(img.get_width() - 1, h * 0.6)

## The front of a body picture (a beak, horns).
static func _rightmost(img: Image) -> Vector2:
	for x in range(img.get_width() - 1, -1, -1):
		for y in img.get_height():
			if _solid(img, x, y):
				return Vector2(x, y)
	return Vector2(img.get_width() - 1, img.get_height() * 0.5)

static func _darken(img: Image, k: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				img.set_pixel(x, y, c.darkened(k))

## A copy with every colour pulled toward `tint` (keeping its lightness).
static func _tinted(img: Image, tint: Color) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.5:
				var v := c.v
				var s := c.s
				var nc := Color.from_hsv(tint.h, clampf(s * 0.5 + tint.s * 0.6, 0.0, 1.0), v)
				out.set_pixel(x, y, nc)
	return out
