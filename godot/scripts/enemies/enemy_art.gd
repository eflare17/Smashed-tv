class_name EnemyArt
extends RefCounted
## The enemies' pictures (manifest ENEMY_SPRITES, JANITOR_SPRITES) and the gore cutting (godot/specs/gore_loot.md 7,
## b288): each picture is labelled once, pixel by pixel, into head, arms, legs and torso along its own outline, and
## the corpse's body and its flying parts are cut out of it, with a red stump where each cut was.

static var _labels: Dictionary = {}       # texture path -> {w, h, img, lab}
static var _cuts: Dictionary = {}         # path|key -> {tex, w, h, x, y} or {}

static func sprites(key: String) -> Dictionary:
	var es = GameData.manifest.get("ENEMY_SPRITES", {})
	return es.get(key, {}) if es is Dictionary else {}

## A picture of an enemy: pose ("front", "side", "diag", "back", "idle", "swing") and frame (batter arrays).
static func tex(key: String, pose: String, frame: int = 0) -> Texture2D:
	var s := sprites(key)
	var p = s.get(pose)
	if p == null:
		# the batter's are numbered files
		var paths := []
		for k in s.keys():
			if String(k).begins_with(pose + "_"):
				paths.append(k)
		if paths.is_empty():
			return null
		paths.sort_custom(func(a, b): return int(String(a).get_slice("_", 1)) < int(String(b).get_slice("_", 1)))
		p = s[paths[clampi(frame, 0, paths.size() - 1)]]
	elif p is Array:
		p = p[clampi(frame, 0, p.size() - 1)]
	return GameData.tex(String(p))

static func frame_count(key: String, pose: String) -> int:
	var s := sprites(key)
	if s.has(pose):
		return s[pose].size() if s[pose] is Array else 1
	var n := 0
	for k in s.keys():
		if String(k).begins_with(pose + "_"):
			n += 1
	return n

static func janitor_tex(frame: String) -> Texture2D:
	var j = GameData.manifest.get("JANITOR_SPRITES", {})
	if j is Dictionary and j.has(frame):
		return GameData.tex(String(j[frame]))
	return null

## The corpse picture: the front frame (the batter's by its odometer, a frame per 10 units).
static func corpse_tex(key: String, odo: float) -> Texture2D:
	var n := frame_count(key, "front")
	if n > 1:
		return tex(key, "front", int(floor(odo / 10.0)) % n)
	var t := tex(key, "front")
	return t if t else tex(key, "idle")

# ---------------------------------------------------------------- gore cutting

static func _jit(n: int) -> int:
	return ((((n * 73856093) & 0xFFFFFFFF) ^ ((n * 19349663) & 0xFFFFFFFF)) % 3) - 1

static func _label(t: Texture2D) -> Dictionary:
	var key := t.resource_path if t.resource_path != "" else str(t.get_instance_id())
	if _labels.has(key):
		return _labels[key]
	var img := t.get_image()
	if img == null:
		_labels[key] = {}
		return {}
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var op := func(x: int, y: int) -> bool: return data[(y * w + x) * 4 + 3] > 40
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] > 40:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		_labels[key] = {}
		return {}
	var H := y1 - y0 + 1
	var run := func(y: int) -> Array:
		var best := [0, (x0 + x1) / 2.0]
		var s := -1
		for x in range(x0, x1 + 2):
			var o: bool = x <= x1 and op.call(x, y)
			if o and s < 0:
				s = x
			if not o and s >= 0:
				if x - s > best[0]:
					best = [x - s, (s + x - 1) / 2.0]
				s = -1
		return best
	var y_head := y0 + int(round(H * 0.23))
	var y_leg := y0 + int(round(H * 0.62))
	var cr: Array = run.call(y0 + int(round(H * 0.45)))
	var chest: float = cr[0]
	var cx: float = cr[1]
	var t_half := maxf(2.0, chest * 0.37)
	var h_half: float = run.call(y0 + int(round(H * 0.12)))[0] / 2.0 + 1.0
	var leg_half := chest * 0.44
	var lab := PackedInt32Array()
	lab.resize(w * h)
	lab.fill(-1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var o := (y * w + x) * 4
			if data[o + 3] <= 40:
				continue
			var r := data[o]
			var g := data[o + 1]
			var b := data[o + 2]
			if y > y1 - 3 and maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < 16 and absf(x - cx) > chest * 0.3:
				continue
			var dx := x - cx
			var side := 1 if dx < 0 else 2
			var ax := absf(dx)
			var yh := y_head + _jit(x)
			var yl := y_leg + _jit(x + 7)
			var th := t_half + _jit(y) + maxf(0.0, y_head + H * 0.08 - y) * 0.5
			var l: int
			if y < yh:
				l = 0 if ax <= h_half + _jit(y + 3) else side
			elif y >= yl:
				l = side if ax > leg_half else (3 if dx + _jit(y + 11) < 0 else 4)
			else:
				l = 5 if ax <= th else side
			lab[y * w + x] = l
	# thin slivers of hip back to the body
	for y in range(y_head, y1 + 1):
		var x := x0
		while x <= x1:
			var l := lab[y * w + x]
			if l == 1 or l == 2:
				var e := x
				while e + 1 <= x1 and lab[y * w + e + 1] == l:
					e += 1
				var lft := lab[y * w + x - 1] if x > 0 else -1
				var rgt := lab[y * w + e + 1] if e < w - 1 else -1
				var nb := lft if (lft >= 0 and lft != l) else (rgt if (rgt >= 0 and rgt != l) else -1)
				if nb >= 0 and e - x + 1 <= 2 and y > y0 + H * 0.4:
					for k in range(x, e + 1):
						lab[y * w + k] = nb
				x = e
			x += 1
	# each arm and the head is one piece: stray bits go back to the body
	for part in [0, 1, 2]:
		var seen := PackedByteArray()
		seen.resize(w * h)
		var comps := []
		for i in w * h:
			if lab[i] != part or seen[i]:
				continue
			var comp := PackedInt32Array()
			var stack := [i]
			seen[i] = 1
			while not stack.is_empty():
				var j: int = stack.pop_back()
				comp.append(j)
				var jx := j % w
				var jy := j / w
				for nn in [[jx - 1, jy], [jx + 1, jy], [jx, jy - 1], [jx, jy + 1]]:
					if nn[0] < 0 or nn[0] >= w or nn[1] < 0 or nn[1] >= h:
						continue
					var k: int = nn[1] * w + nn[0]
					if lab[k] == part and not seen[k]:
						seen[k] = 1
						stack.append(k)
			comps.append(comp)
		comps.sort_custom(func(a, b): return a.size() > b.size())
		for ci in range(1, comps.size()):
			for j in comps[ci]:
				lab[j] = (3 if (j % w) < cx else 4) if (j / w) >= y_leg else 5
	var res := {"w": w, "h": h, "data": data, "lab": lab}
	_labels[key] = res
	return res

static func _cut(t: Texture2D, key: String, keep: Callable) -> Dictionary:
	var ck := (t.resource_path if t.resource_path != "" else str(t.get_instance_id())) + "|" + key
	if _cuts.has(ck):
		return _cuts[ck]
	var L := _label(t)
	if L.is_empty():
		_cuts[ck] = {}
		return {}
	var w: int = L.w
	var h: int = L.h
	var lab: PackedInt32Array = L.lab
	var data: PackedByteArray = L.data
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	for y in h:
		for x in w:
			var l := lab[y * w + x]
			if l >= 0 and keep.call(l):
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		_cuts[ck] = {}
		return {}
	var cut := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= w or y >= h:
			return false
		var l := lab[y * w + x]
		return l >= 0 and not keep.call(l)
	var cw := x1 - x0 + 1
	var chh := y1 - y0 + 1
	var out := Image.create(cw, chh, false, Image.FORMAT_RGBA8)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var l := lab[y * w + x]
			if l < 0 or not keep.call(l):
				continue
			var o := (y * w + x) * 4
			var r := data[o] / 255.0
			var g := data[o + 1] / 255.0
			var b := data[o + 2] / 255.0
			if cut.call(x - 1, y) or cut.call(x + 1, y) or cut.call(x, y - 1) or cut.call(x, y + 1):
				r = 196 / 255.0
				g = 26 / 255.0
				b = 44 / 255.0
			elif cut.call(x - 2, y) or cut.call(x + 2, y) or cut.call(x, y - 2) or cut.call(x, y + 2):
				r = r * 0.45 + 120 / 255.0 * 0.55
				g = g * 0.45 + 10 / 255.0 * 0.55
				b = b * 0.45 + 24 / 255.0 * 0.55
			out.set_pixel(x - x0, y - y0, Color(r, g, b, data[o + 3] / 255.0))
	var res := {"tex": ImageTexture.create_from_image(out), "w": cw, "h": chh, "x": x0, "y": y0}
	_cuts[ck] = res
	return res

## The body with the lost parts cut away (mask: bits of parts 0 head, 1/2 arms, 3/4 legs), or {} for none.
static func gore_body(t: Texture2D, mask: int) -> Dictionary:
	if mask == 0:
		return {}
	return _cut(t, "b%d" % mask, func(l: int) -> bool: return not (mask & (1 << l)))

## One piece (0 head, 1 left arm, 2 right arm, 3 left leg, 4 right leg), or {} if the picture has none.
static func gore_part(t: Texture2D, part: int) -> Dictionary:
	return _cut(t, "p%d" % part, func(l: int) -> bool: return l == part)
