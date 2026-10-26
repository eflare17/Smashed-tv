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
	"hatchling": {"width": 52.0, "arm": [0.84, 0.66], "jaw_k": 0.6, "jaw_trim": 0.3, "leg_scale": 0.6, "tilt": 0.35, "legs": 2, "tail": 0.32, "neck": 0.8},
	"raptor": {"width": 48.0, "jaw_k": 0.6, "jaw_trim": 0.3, "legs": 2, "leg_scale": 0.6, "tilt": 0.45, "tail": 0.3, "neck": 0.78},
	"allosaur": {"width": 52.0, "jaw_k": 0.6, "jaw_trim": 0.4, "leg_scale": 0.8, "tilt": 0.2, "legs": 2, "tail": 0.3, "neck": 0.8},
	"tyrant": {"width": 52.0, "jaw_k": 0.6, "jaw_trim": 0.4, "leg_scale": 0.55, "tilt": 0.4, "legs": 2, "tail": 0.28, "neck": 0.78},
	"grazer": {"stand": 54.0, "legs": 4, "hips": [0.42, 0.72], "hip_y": 0.86, "tail": 0.36, "neck": 0.76, "neck_y": 0.62, "head": 0.86, "head_y": 0.3},
	"runner": {"width": 36.0, "legs": 2, "tail": 0.42, "neck": 0.78, "head": 0.88, "head_y": 0.6},
	"charger": {"stand": 46.0, "legs": 4, "hips": [0.34, 0.6], "hip_y": 0.6, "tail": 0.2, "head": 0.66, "head_y": 1.0},
	# the front hip sits over the stub of a front leg the sheet drew on the body, so the game's leg hides it
	"ankylosaurus": {"stand": 34.0, "legs": 4, "hips": [0.4, 0.7], "hip_y": 0.8, "leg_scale": 0.45, "tail": 0.3, "head": 0.8, "head_y": 1.0},
	# the runners family (26 Oct): first guesses, tuned by eye
	"compsognathus": {"width": 24.0, "legs": 2, "tail": 0.45, "neck": 0.78, "head": 0.86, "head_y": 0.6},
	"gallimimus": {"width": 46.0, "legs": 2, "tail": 0.45, "neck": 0.76, "head": 0.88, "head_y": 0.35},
	"corythosaurus": {"stand": 52.0, "legs": 2, "hips": [0.45], "tail": 0.32, "neck": 0.72, "neck_y": 0.6, "head": 0.8, "head_y": 0.45},
	"flyer": {"width": 38.0, "wing_scale": 0.75, "legs": 0, "hips": [0.4, 0.5], "hip_y": 0.6, "shoulder": [0.55, 0.5], "tail": 0.22, "head": 0.3, "head_y": 0.42},
}

## Which creatures use their imported sprites. Off by default: each is switched on once its rig has been checked
## by eye (hinges, sizes, which piece is which); until then the code-drawn placeholder is used.
const ENABLED := {
	"hatchling": true, "raptor": true, "allosaur": true, "tyrant": true,
	"grazer": true, "runner": true, "charger": true, "flyer": true, "ankylosaurus": true,
	"compsognathus": true, "gallimimus": true, "corythosaurus": true,
}

static var _cache := {}

static func has(creature: String) -> bool:
	return ResourceLoader.exists("res://art/%s_body.png" % creature) or FileAccess.file_exists("res://art/%s_body.png" % creature)

static func _load(creature: String, part: String) -> Image:
	var key := creature + "_" + part
	if _cache.has(key):
		return _cache[key]
	var path := "res://art/%s_%s.png" % [creature, part]
	# as Godot's imported texture (what a web build packs), not the PNG on disk
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
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
		# the legs can be drawn smaller than the sheet made them (leg_scale); leg_len is how far they reach down
		leg_len = int((leg.get_height() - 2) * spec.get("leg_scale", 1.0))
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
			"z": 0, "parent": "", "front": _rightmost(body), "rot": spec.get("tilt", 0.0)})
	# little arms at the chest, for a sheet that drew none (spec "arm": where the shoulder is, as fractions of
	# the body picture): drawn in the body's own colours, the far one darker and behind
	if spec.has("arm"):
		var arm := _arm(body)
		var far_arm: Image = arm.duplicate()
		_darken(far_arm, 0.3)
		var at := Vector2(bw * spec.arm[0], bh * spec.arm[1]) - pivot
		var az := _fill_zones(arm, DinoArt.BODY)
		parts.append({"name": "arm", "image": far_arm, "zones": az, "pivot": Vector2(2, 1), "pos": at + Vector2(-2, 0),
				"anchors": _core(arm, 2, 1, 2), "z": -1, "parent": "body"})
		parts.append({"name": "arm", "image": arm, "zones": az, "pivot": Vector2(2, 1), "pos": at,
				"anchors": _core(arm, 2, 1, 2), "z": 1, "parent": "body"})
	# legs: one picture, the far ones darker and behind
	if leg and legs > 0:
		var far: Image = leg.duplicate()
		_darken(far, 0.3)
		var lz := _leg_zones(leg)
		var lp := Vector2(leg.get_width() * 0.5, 2)
		var la := _rows(leg, 0, 2)
		if legs == 2:
			parts.append({"name": "leg", "image": far, "zones": lz, "pivot": lp, "pos": Vector2(2, -leg_len),
					"anchors": la, "z": -1, "parent": "", "leg": PI, "scale": spec.get("leg_scale", 1.0)})
			parts.append({"name": "leg", "image": leg, "zones": lz, "pivot": lp, "pos": Vector2(-2, -leg_len),
					"anchors": la, "z": 1, "parent": "", "leg": 0.0, "scale": spec.get("leg_scale", 1.0)})
		else:
			var mid := pivot.x
			for spec_leg in [[far, hips[0] - mid - 2, -1, 0.0], [far, hips[1] - mid + 2, -1, PI],
					[leg, hips[0] - mid + 2, 1, PI], [leg, hips[1] - mid - 2, 1, 0.0]]:
				parts.append({"name": "leg", "image": spec_leg[0], "zones": lz, "pivot": lp, "scale": spec.get("leg_scale", 1.0),
						"pos": Vector2(spec_leg[1], -leg_len), "anchors": la, "z": spec_leg[2], "parent": "", "leg": spec_leg[3]})
	# a separate head and jaw (the meat-eaters)
	var head := _load(creature, "head")
	if head:
		if tint != Color.WHITE:
			head = _tinted(head, tint)
		# the sheet's head has the chin drawn on; the separate jaw replaces it, so cut it off below the upper jaw's
		# edge (keeping the throat at the back, where the head meets the neck)
		head = head.duplicate()
		var edge := _bottom_in(head, int(head.get_width() * 0.8), head.get_width() - 2)
		# only as far back as the jaw reaches, so no gap shows under the eye
		var cut_from := int(head.get_width() * 0.22)
		var jaw_pic := _load(creature, "jaw")
		if jaw_pic:
			var jl := jaw_pic.get_width() - int(jaw_pic.get_width() * spec.get("jaw_trim", 0.0))
			cut_from = maxi(cut_from, head.get_width() - jl + 1)
		for y in range(edge + 1, head.get_height()):
			for x in range(cut_from, head.get_width()):
				head.set_pixel(x, y, Color(0, 0, 0, 0))
		# a row of teeth hanging from the upper jaw, from the snout tip back to where the jaw starts
		_teeth(head, cut_from + 2, head.get_width() - 3, true)
		var neck_y := _left_middle(head)
		var hp := Vector2(2, neck_y)
		var neck_end := _neck_end(body, spec)
		parts.append({"name": "head", "image": head, "zones": _fill_zones(head, DinoArt.HEAD), "pivot": hp,
				"pos": neck_end - pivot + Vector2(-3, 1), "anchors": _core(head, int(_deepest(head).x), int(_deepest(head).y), 4), "z": 2, "parent": "body",
				"tip": _tip(head), "jaw_k": spec.get("jaw_k", 1.0)})
		var jaw := _load(creature, "jaw")
		if jaw:
			if tint != Color.WHITE:
				jaw = _tinted(jaw, tint)
			# seat the jaw shut: its hinge at its back end, its top edge tucked up under the upper jaw's bottom edge
			# at the snout, its front tip in line with the head's
			# a long sheet jaw hinged at the very back of the skull swings out too far: trim its back end so it hinges
			# further forward, under the eye (jaw_trim: the share cut off)
			var trim := int(jaw.get_width() * spec.get("jaw_trim", 0.0))
			if trim > 0:
				jaw = jaw.get_region(Rect2i(trim, 0, jaw.get_width() - trim, jaw.get_height()))
			# and a row standing up along the lower jaw's top edge
			_teeth(jaw, 3, jaw.get_width() - 3, false)
			var hw := head.get_width()
			var jw := jaw.get_width()
			var jaw_piv := Vector2(1, _left_middle(jaw))
			var mouth_y := _bottom_in(head, int(hw * 0.8), hw - 2)
			var hinge := Vector2(hw - jw + jaw_piv.x - 2, mouth_y - 2 + jaw_piv.y - _top_in(jaw, int(jw * 0.6), jw - 2))
			parts.append({"name": "jaw", "image": jaw, "zones": _fill_zones(jaw, DinoArt.HEAD), "pivot": jaw_piv,
					"pos": hinge - hp, "anchors": _core(jaw, 3, int(jaw_piv.y), 3), "z": -1, "parent": "head"})
	# wings (the flyer): one picture, far wing darker and behind
	var wing := _load(creature, "wing")
	if wing:
		# the sheet draws the wing spread out to the right from its root on the left; side-on it trails back over
		# the body from the shoulder, so mirror it and hinge it at the root
		wing = wing.duplicate()
		wing.flip_x()
		var root := Vector2(wing.get_width() - 3, _root_middle(wing))
		var far_w: Image = wing.duplicate()
		_darken(far_w, 0.3)
		var wz := _fill_zones(wing, DinoArt.WING)
		var wp := root
		var wa := _core(wing, int(root.x), int(root.y), 4)
		var sh: Array = spec.get("shoulder", [0.42, 0.35])
		var at := Vector2(bw * sh[0], bh * sh[1]) - pivot
		parts.append({"name": "wing", "image": far_w, "zones": wz, "pivot": wp, "pos": at + Vector2(-2, 0),
				"anchors": wa, "z": -1, "parent": "", "wing": true, "scale": spec.get("wing_scale", 1.0)})
		parts.append({"name": "wing", "image": wing, "zones": wz, "pivot": wp, "pos": at,
				"anchors": wa, "z": 1, "parent": "", "wing": true, "scale": spec.get("wing_scale", 1.0)})
	var height := (leg_len + hip_y) * k if legs > 0 else bh * k
	# how far the body drops when it dies: most of the leg (in the rig's own pixels: the rig is scaled by k)
	return {"parts": parts, "height": height, "k": k, "half_w": bw * k * 0.3, "foot": (bh * 0.5 * k) if legs == 0 else 0.0,
			"drop": leg_len * 0.8, "wing_rest": -0.15}

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

## The middle of the rightmost few solid columns (where a mirrored wing joins the shoulder).
static func _root_middle(img: Image) -> int:
	var ys: Array = []
	for x in range(img.get_width() - 1, maxi(-1, img.get_width() - 7), -1):
		for y in img.get_height():
			if _solid(img, x, y):
				ys.append(y)
	if ys.is_empty():
		return img.get_height() / 2
	ys.sort()
	return ys[ys.size() / 2]

const TOOTH := Color(0.95, 0.92, 0.82)
const TOOTH_SHADE := Color(0.72, 0.68, 0.6)
const TOOTH_GAP := Color(0.12, 0.06, 0.05)

## Paints a row of teeth along a jaw's edge, columns x0..x1: on the bottom edge pointing down (`upper`), or on
## the top edge pointing up. Teeth 2 wide and 3 long with a shaded root, 2-wide dark gaps between, drawn over the edge
## pixels (so the picture keeps its size and the jaw still fits).
static func _teeth(img: Image, x0: int, x1: int, upper: bool) -> void:
	var h := img.get_height()
	var x := x0
	var k := 0
	while x <= x1:
		var edge := -1
		if upper:
			for y in range(h - 1, -1, -1):
				if _solid(img, x, y):
					edge = y
					break
		else:
			for y in h:
				if _solid(img, x, y):
					edge = y
					break
		if edge >= 0:
			var step := -1 if upper else 1
			if k % 4 < 2:
				# a tooth (2 wide, 3 long: the sprite is drawn at about half size): white, shaded at the root
				img.set_pixel(x, edge, TOOTH)
				if _solid(img, x, edge + step):
					img.set_pixel(x, edge + step, TOOTH)
				if _solid(img, x, edge + step * 2):
					img.set_pixel(x, edge + step * 2, TOOTH_SHADE)
			else:
				# the dark gap between teeth, so they read on a pale lip too
				img.set_pixel(x, edge, TOOTH_GAP)
		x += 1
		k += 1

## A small arm hanging down and forward from the shoulder (top-left): upper arm, forearm, two claws.
## o = outline, x = skin, s = shade, w = claw. Colours are taken from `body` (its commonest, darkest, lightest).
const ARM := [
	".ooo.....",
	"oxxso....",
	"oxxso....",
	".oxxso...",
	".oxxxooo.",
	"..oxxxxxo",
	"...oossxo",
	".....owow",
]

static func _arm(body: Image) -> Image:
	var counts := {}
	var dark := Color(0.1, 0.06, 0.05)
	var dv := 1.0
	for y in body.get_height():
		for x in body.get_width():
			var c := body.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if c.v < dv:
				dv = c.v
				dark = c
			var key := c.to_html(false)
			counts[key] = counts.get(key, 0) + 1
	var best := ""
	for k: String in counts:
		if best == "" or counts[k] > counts[best]:
			best = k
	var skin := Color.html(best) if best != "" else Color(0.85, 0.7, 0.45)
	var img := Image.create(ARM[0].length(), ARM.size(), false, Image.FORMAT_RGBA8)
	for y in ARM.size():
		for x in ARM[y].length():
			var ch: String = ARM[y][x]
			var c := Color(0, 0, 0, 0)
			match ch:
				"o":
					c = dark
				"x":
					c = skin
				"s":
					c = skin.darkened(0.25)
				"w":
					c = TOOTH
			img.set_pixel(x, y, c)
	return img

## The lowest solid row anywhere in columns x0..x1 (the bottom edge of an upper jaw at the snout).
static func _bottom_in(img: Image, x0: int, x1: int) -> int:
	var best := 0
	for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
		for y in range(img.get_height() - 1, -1, -1):
			if _solid(img, x, y):
				best = maxi(best, y)
				break
	return best

## The highest solid row in columns x0..x1 (the top of a lower jaw's teeth).
static func _top_in(img: Image, x0: int, x1: int) -> int:
	var best := img.get_height()
	for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
		for y in img.get_height():
			if _solid(img, x, y):
				best = mini(best, y)
				break
	return best

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
