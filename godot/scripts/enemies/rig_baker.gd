class_name RigBaker
extends RefCounted
## The enemies' walk rigs (godot/specs/enemies_waves.md 6.3, drawOtherEnemyRig): "every enemy walks with planted
## feet and bending knees". The picture is cut off at the waist and drawn over two procedural legs whose planted foot
## slides back exactly as fast as the body moves forward. Baked once per (type, view, phase) into a 128 x 112 picture
## with the feet at (64, 96), PHASES phases a cycle (the HTML caches 96; fewer keeps the web build's memory down).

const PHASES := 24
const RIGS := {
	"grunt": {"stride": 12.0, "lift": 9.0, "bob": 0.7, "width": 9.0, "base": "#247235", "light": "#4f9b55", "dark": "#174425",
		"boot": "#303631", "views": {"front": [29, 45], "back": [30, 46], "side": [32, 44], "diag": [33, 45]}},
	"swarmer": {"stride": 16.0, "lift": 13.0, "bob": 1.0, "width": 6.0, "base": "#cc9f16", "light": "#f4cc38", "dark": "#80621a",
		"boot": "#38352c", "views": {"front": [29, 46], "back": [30, 47], "side": [39, 45], "diag": [34, 47]}},
	"brute": {"stride": 8.0, "lift": 5.0, "bob": 0.45, "width": 12.0, "base": "#6b3aa6", "light": "#9b63d2", "dark": "#3d2361",
		"boot": "#2a1f3e", "views": {"front": [35, 53], "back": [29, 54], "side": [30, 53], "diag": [34, 53]}},
}

static var _frames: Dictionary = {}

static func has_rig(key: String, pose: String) -> bool:
	return RIGS.has(key) and RIGS[key].views.has(pose)

## Units of walking per cycle (travel) for a type drawn h units tall.
static func travel(key: String, h: float) -> float:
	var stride: float = RIGS[key].stride
	var es := float(GameData.data.get("T", {}).get("enemyStride", 10))
	return stride * 2.0 / 0.6 * (h / 80.0) * maxf(0.4, es / 10.0)

## The baked frame for this odometer (feet at pixel (64, 96) of 128 x 112; 80 px = the enemy's height).
static func frame(key: String, pose: String, odo: float, h: float) -> Texture2D:
	var tr := travel(key, h)
	var ph := fposmod(odo, tr) / tr
	var i := int(floor(ph * PHASES)) % PHASES
	var k := "%s|%s|%d" % [key, pose, i]
	if _frames.has(k):
		return _frames[k]
	var t := _bake(key, pose, float(i) / PHASES)
	_frames[k] = t
	return t

static func _foot(phase: float, cfg: Dictionary) -> Vector3:
	var p := fposmod(phase, 1.0)
	var stride: float = cfg.stride
	if p < 0.6:
		return Vector3(stride * (1.0 - 2.0 * p / 0.6), 0.0, 0.0)
	var t := (p - 0.6) / 0.4
	var ss := t * t * (3.0 - 2.0 * t)
	return Vector3(stride * (-1.0 + 2.0 * ss), float(cfg.lift) * sin(PI * t), 0.0)

static func knee(hip: Vector2, ankle: Vector2, length: float, bend: float) -> Vector2:
	var dv := ankle - hip
	var d := maxf(0.001, dv.length())
	var half := minf(length, d / 2.0)
	var out := sqrt(maxf(0.0, length * length - half * half))
	return (hip + ankle) / 2.0 + Vector2(dv.y / d, -dv.x / d) * out * bend

static func _bake(key: String, pose: String, p: float) -> Texture2D:
	var cfg: Dictionary = RIGS[key]
	var view := "side" if (key == "brute" and pose == "back") else pose
	var vw: Array = cfg.views[pose]
	var anchor := float(vw[0])
	var cut := int(vw[1])
	var img := Image.create(128, 112, false, Image.FORMAT_RGBA8)
	var o := Vector2(64, 96)
	var rise := -float(cfg.bob) * (1.0 - cos(p * 4.0 * PI))
	var spread := 2.0 if view == "side" else float(cfg.width) * 0.58
	_leg(img, o + Vector2(-spread, cut - 80 + rise), _foot(p + 0.5, cfg), view, cfg, false, cut, key == "brute")
	_leg(img, o + Vector2(spread, cut - 80 + rise), _foot(p, cfg), view, cfg, true, cut, key == "brute")
	var src := EnemyArt.tex(key, pose)
	if src:
		var si := src.get_image()
		if si.is_compressed():
			si.decompress()
		si.convert(Image.FORMAT_RGBA8)
		var dx := int(round(o.x - anchor))
		var dy := int(round(o.y - 80.0 + rise))
		for y in mini(cut + 3, si.get_height()):
			for x in si.get_width():
				var c := si.get_pixel(x, y)
				if c.a <= 0.02:
					continue
				var tx := x + dx
				var ty := y + dy
				if tx < 0 or ty < 0 or tx >= 128 or ty >= 112:
					continue
				img.set_pixel(tx, ty, c)
	return ImageTexture.create_from_image(img)

static func _leg(img: Image, hip: Vector2, foot: Vector3, view: String, cfg: Dictionary, near: bool, cut: int, armour: bool) -> void:
	var profile := view == "side"
	var diagonal := view == "diag"
	var ax := hip.x + (foot.x if profile else (foot.x * 0.65 if diagonal else foot.x * 0.06))
	var ay := 96.0 - 4.0 - foot.y + (0.0 if profile else foot.x * (0.13 if diagonal else 0.18))
	var ankle := Vector2(ax, ay)
	var length := (80.0 - cut - 4.0) * 0.58
	var bend := 1.0 if (profile or diagonal) else (1.0 if near else -1.0) * 0.3
	var kn := knee(hip, ankle, length, bend)
	var w: float = cfg.width
	var base := Color(String(cfg.base))
	var light := Color(String(cfg.light))
	var dark := Color(String(cfg.dark))
	_segment(img, hip, kn, w, near, base, light, dark, false, armour)
	_segment(img, kn, ankle, w * 0.78, near, base, light, dark, true, armour)
	# the boot (side and diagonal boots are longer, toe forward)
	var sd := profile or diagonal
	_rect(img, ankle + Vector2(-0.43 * w, -3), Vector2(0.85 * w + (5.0 if sd else 0.0), 7), Color("#171b1c"))
	_rect(img, ankle + Vector2(-0.33 * w, -2), Vector2(0.65 * w + (4.0 if sd else 0.0), 5), Color(String(cfg.boot)))
	_rect(img, ankle + Vector2(-0.33 * w, 2), Vector2(0.65 * w + (4.0 if sd else 0.0), 1), Color("#7b7b71") if near else Color("#51564f"))

static func _segment(img: Image, a: Vector2, b: Vector2, w: float, near: bool, base: Color, light: Color, dark: Color, shin: bool, armour: bool) -> void:
	_capsule(img, a, b, w + 2.0, Color("#17201d"))
	_capsule(img, a, b, w, base if near else dark)
	_capsule(img, a + Vector2(-1, 0), b + Vector2(-1, 0), 2.0, light if near else base)
	if armour:
		var m := (a + b) / 2.0
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var hl := 4.0 if shin else 5.0
		var hw := 0.4 * w
		var pts := PackedVector2Array([m - dir * hl - side * hw, m + dir * hl - side * hw, m + dir * hl + side * hw, m - dir * hl + side * hw])
		_poly(img, pts, dark)
		var inner := PackedVector2Array()
		for q in pts:
			inner.append(m + (q - m) * 0.8)
		_poly(img, inner, light if near else base)

static func _capsule(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var r := w / 2.0
	var x0 := maxi(0, int(floor(minf(a.x, b.x) - r)))
	var x1 := mini(127, int(ceil(maxf(a.x, b.x) + r)))
	var y0 := maxi(0, int(floor(minf(a.y, b.y) - r)))
	var y1 := mini(111, int(ceil(maxf(a.y, b.y) + r)))
	var ab := b - a
	var l2 := maxf(0.0001, ab.length_squared())
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var pp := Vector2(x + 0.5, y + 0.5)
			var t := clampf((pp - a).dot(ab) / l2, 0.0, 1.0)
			if pp.distance_squared_to(a + ab * t) <= r * r:
				img.set_pixel(x, y, col)

static func _rect(img: Image, at: Vector2, size: Vector2, col: Color) -> void:
	var r := Rect2i(Vector2i(int(round(at.x)), int(round(at.y))), Vector2i(int(round(size.x)), int(round(size.y))))
	r = r.intersection(Rect2i(0, 0, 128, 112))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, col)

static func _poly(img: Image, pts: PackedVector2Array, col: Color) -> void:
	var bb := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		bb = bb.expand(q)
	for y in range(maxi(0, int(bb.position.y)), mini(111, int(bb.end.y) + 1)):
		for x in range(maxi(0, int(bb.position.x)), mini(127, int(bb.end.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, col)
