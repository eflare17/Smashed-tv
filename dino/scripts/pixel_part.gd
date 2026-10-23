class_name PixelPart
extends Sprite2D
## One carvable piece of a dinosaur (its body, a leg, a head, a jaw): a small pixel image where every pixel is
## alive or bitten off. A bite (carve) removes a jagged circle of pixels, colours the new edge as a wound (dark
## red rim, flesh behind it, the odd bit of bone), and anything no longer joined to the part's anchor pixels falls
## off as an "island" (the caller turns those into falling pieces). Every pixel also has a zone (DinoArt.HEAD...)
## so the game knows what was bitten. The image is rebuilt and re-uploaded after each change (they're small).

const DinoArt := preload("dino_art.gd")

const RIM := 1
const FLESH := 2
const BONE := 3
## Islands smaller than this just turn into flying pixels.
const MIN_ISLAND := 6

const RIM_COLOR := Color(0.45, 0.02, 0.04)
const FLESH_COLOR := Color(0.78, 0.13, 0.13)
const BONE_COLOR := Color(0.93, 0.89, 0.78)
const ZONE_COLORS := [Color(0, 0, 0, 0), Color(1.0, 0.3, 0.3), Color(1.0, 0.8, 0.2), Color(0.3, 0.75, 1.0),
		Color(0.7, 0.4, 1.0), Color(0.35, 1.0, 0.45)]

var w := 0
var h := 0
## The part's own colours, before any bites.
var skin: Image
var zone := PackedByteArray()
var alive := PackedByteArray()
var wound := PackedByteArray()
## Pixels the part counts as "attached here" (a leg's hip, the body's middle).
var anchor := PackedInt32Array()
var zone_total := PackedInt32Array()
var zone_left := PackedInt32Array()
## Wound pixel indices (for bleeding); may hold a few stale ones, checked when picked.
var wounds := PackedInt32Array()
## Debug: draw each zone in its own colour.
var show_zones := false
## False: bites pass through (the player's own parts).
var carvable := true

var _img: Image
var _tex: ImageTexture

## `pivot` is the pixel that sits on the node's position (and that it turns about).
func setup(image: Image, zones: PackedByteArray, pivot: Vector2, anchors: PackedInt32Array) -> void:
	skin = image
	w = image.get_width()
	h = image.get_height()
	zone = zones
	anchor = anchors
	alive.resize(w * h)
	wound.resize(w * h)
	zone_total.resize(DinoArt.ZONE_NAMES.size())
	zone_left.resize(DinoArt.ZONE_NAMES.size())
	for i in w * h:
		if skin.get_pixel(i % w, i / w).a > 0.0:
			alive[i] = 1
			zone_total[zone[i]] += 1
	zone_left = zone_total.duplicate()
	centered = false
	offset = -pivot
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	texture = _tex
	rebuild()

func pixels_left() -> int:
	var n := 0
	for z in zone_left:
		n += z
	return n

func pixels_total() -> int:
	var n := 0
	for z in zone_total:
		n += z
	return n

## World point -> pixel coordinates in this part's image.
func to_pixel(world: Vector2) -> Vector2:
	return to_local(world) - offset

func to_world(px: Vector2) -> Vector2:
	return to_global(px + offset)

## The zone of the live pixel under `world`, or 0.
func zone_at(world: Vector2) -> int:
	var p := to_pixel(world)
	var x := floori(p.x)
	var y := floori(p.y)
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0
	var i := y * w + x
	return zone[i] if alive[i] == 1 else 0

## Bites a jagged circle of `radius` (world pixels) out at `world`. Returns {removed: [[world pos, colour]...],
## islands: [{image, center, rotation, scale, zones}...], zones: counts per zone of what came off (bitten and fallen)}.
func carve(world: Vector2, radius: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"removed": [], "islands": [], "zones": PackedInt32Array()}
	out.zones.resize(DinoArt.ZONE_NAMES.size())
	if not carvable:
		return out
	var s := absf(global_scale.x)
	var r := radius / s
	var c := to_pixel(world)
	if c.x < -r - 2 or c.y < -r - 2 or c.x > w + r + 2 or c.y > h + r + 2:
		return out
	var x0 := maxi(0, floori(c.x - r - 2))
	var x1 := mini(w - 1, ceili(c.x + r + 2))
	var y0 := maxi(0, floori(c.y - r - 2))
	var y1 := mini(h - 1, ceili(c.y + r + 2))
	var bitten := false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * w + x
			if alive[i] == 0:
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			# a ragged edge, not a clean circle
			if d < r + rng.randf_range(-0.8, 0.5):
				_take(i, out)
				bitten = true
	if not bitten:
		return out
	# tooth notches just past the edge
	for k in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * (r + rng.randf_range(0.5, 1.5))
		var x := floori(p.x)
		var y := floori(p.y)
		if x >= 0 and y >= 0 and x < w and y < h and alive[y * w + x] == 1:
			_take(y * w + x, out)
	_mark_wounds(x0, y0, x1, y1, rng)
	_split(out)
	rebuild()
	return out

func _take(i: int, out: Dictionary) -> void:
	out.removed.append([to_world(Vector2(i % w + 0.5, i / w + 0.5)), _color(i)])
	out.zones[zone[i]] += 1
	alive[i] = 0
	zone_left[zone[i]] -= 1

func _is_hole(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var i := y * w + x
	return alive[i] == 0 and skin.get_pixel(x, y).a > 0.0

## Live pixels next to a bitten-out one become the wound's rim (sometimes bone); the ones behind those, flesh.
func _mark_wounds(x0: int, y0: int, x1: int, y1: int, rng: RandomNumberGenerator) -> void:
	x0 = maxi(0, x0 - 2)
	y0 = maxi(0, y0 - 2)
	x1 = mini(w - 1, x1 + 2)
	y1 = mini(h - 1, y1 + 2)
	var rim := PackedInt32Array()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * w + x
			if alive[i] == 0 or wound[i] == RIM or wound[i] == BONE:
				continue
			var edge := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if _is_hole(x + dx, y + dy):
						edge = true
			if edge:
				rim.append(i)
	for i in rim:
		var bony := zone[i] != DinoArt.HEAD and rng.randf() < 0.12
		wound[i] = BONE if bony else RIM
		wounds.append(i)
	for i in rim:
		var x := i % w
		var y := i / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if alive[j] == 1 and wound[j] == 0 and rng.randf() < 0.7:
					wound[j] = FLESH

## Whatever isn't joined (4-way) to the anchor any more comes off.
func _split(out: Dictionary) -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var root := -1
	for a in anchor:
		if alive[a] == 1:
			root = a
			break
	var comps: Array = []
	if root < 0:
		# the anchor is gone: keep the biggest piece
		for i in w * h:
			if alive[i] == 1 and seen[i] == 0:
				comps.append(_fill(i, seen))
		var best := 0
		for k in comps.size():
			if comps[k].size() > comps[best].size():
				best = k
		if comps.is_empty():
			return
		comps.remove_at(best)
	else:
		_fill(root, seen)
		for i in w * h:
			if alive[i] == 1 and seen[i] == 0:
				comps.append(_fill(i, seen))
	for comp: PackedInt32Array in comps:
		if comp.size() < MIN_ISLAND:
			for i in comp:
				_take(i, out)
			continue
		out.islands.append(_island(comp, out))

func _fill(start: int, seen: PackedByteArray) -> PackedInt32Array:
	var comp := PackedInt32Array()
	var stack := PackedInt32Array([start])
	seen[start] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		comp.append(i)
		var x := i % w
		var y := i / w
		for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
			if n >= 0 and alive[n] == 1 and seen[n] == 0:
				seen[n] = 1
				stack.append(n)
	return comp

func _island(comp: PackedInt32Array, out: Dictionary) -> Dictionary:
	var bx0 := w
	var by0 := h
	var bx1 := 0
	var by1 := 0
	for i in comp:
		bx0 = mini(bx0, i % w)
		bx1 = maxi(bx1, i % w)
		by0 = mini(by0, i / w)
		by1 = maxi(by1, i / w)
	var img := Image.create(bx1 - bx0 + 1, by1 - by0 + 1, false, Image.FORMAT_RGBA8)
	var zones := PackedInt32Array()
	zones.resize(DinoArt.ZONE_NAMES.size())
	for i in comp:
		img.set_pixel(i % w - bx0, i / w - by0, _color(i))
		zones[zone[i]] += 1
		out.zones[zone[i]] += 1
		alive[i] = 0
		zone_left[zone[i]] -= 1
	var mid := Vector2(bx0 + bx1 + 1, by0 + by1 + 1) * 0.5
	return {"image": img, "center": to_world(mid), "rotation": global_rotation, "scale": global_scale,
			"zones": zones, "pixels": comp.size()}

## The whole part comes off (what held it on was bitten away). Returns it as one island ({} if nothing's left).
func detach() -> Dictionary:
	var comp := PackedInt32Array()
	for i in w * h:
		if alive[i] == 1:
			comp.append(i)
	if comp.is_empty():
		return {}
	var out := {"removed": [], "islands": [], "zones": PackedInt32Array()}
	out.zones.resize(DinoArt.ZONE_NAMES.size())
	var isl := _island(comp, out)
	rebuild()
	return isl

## True if any live pixel is within `r` pixels of `px` (what a child part hangs on).
func holds(px: Vector2, r: int) -> bool:
	for y in range(int(px.y) - r, int(px.y) + r + 1):
		for x in range(int(px.x) - r, int(px.x) + r + 1):
			if x >= 0 and y >= 0 and x < w and y < h and alive[y * w + x] == 1:
				return true
	return false

## A random wound pixel's world position, or null if it has none.
func random_wound(rng: RandomNumberGenerator) -> Variant:
	for tries in 4:
		if wounds.is_empty():
			return null
		var k := rng.randi() % wounds.size()
		var i := wounds[k]
		if alive[i] == 1:
			return to_world(Vector2(i % w + 0.5, i / w + 0.5))
		wounds.remove_at(k)
	return null

func _color(i: int) -> Color:
	if show_zones:
		return ZONE_COLORS[zone[i]]
	match wound[i]:
		RIM:
			return RIM_COLOR
		FLESH:
			return FLESH_COLOR
		BONE:
			return BONE_COLOR
	return skin.get_pixel(i % w, i / w)

func rebuild() -> void:
	for i in w * h:
		_img.set_pixel(i % w, i / w, _color(i) if alive[i] == 1 else Color(0, 0, 0, 0))
	_tex.update(_img)
