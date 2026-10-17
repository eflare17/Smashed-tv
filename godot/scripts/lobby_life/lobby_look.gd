class_name LobbyLook
extends RefCounted
## Jared's hair style and the picture printed on his singlet, baked onto his frames (Smashed.html: BEARDS, HAIR_ART,
## HAIR_FIT, hairPaint @1505, shirtLogoBox @1207, shirtSkin @1371, applyShirtArt @1652). Owned by the Lobby life session.
##
## The HTML game replaces every frame in place with a haired and printed copy. Here the frames stay as they are and
## LobbyLook.baked(path, texture, flip) hands back a copy of one (same size) with the head redone and the picture
## on the shirt; whoever draws a juicy frame swaps it in (LobbyMirror does it for every CharSprite it knows of).
##
## Port decisions: baked at the frame's own size (the HTML game prints at 2x or 3x for the photo look), the strap
## over the shoulder isn't specially treated, and the shirt is found as the green singlet's pixels with each row
## filled between its edges (the HTML game flood-fills holes).

const DATA := "res://scripts/lobby_life/art/bedroom/hair_data.json"
const SAVE := "user://lobby_look.cfg"

## The style now (an index of BEARDS) and its print; all static: there is one Jared look per screen, as in the HTML game.
static var style: int = 0
static var art_front: Image
static var art_back: Image
## {x, y, w, h} in 0..1 of the shirt's box (may leave it).
static var place_front := Rect2(0, 0, 1, 1)
static var place_back := Rect2(0, 0, 1, 1)
static var smooth: bool = true
## Bumped whenever the look changes, so cached frames know.
static var rev: int = 0

static var _data: Dictionary = {}
static var _cache: Dictionary = {}      # "path|flip|rev" -> Texture2D
static var _hair: Dictionary = {}       # "style_view" -> Image
static var _anchors: Dictionary = {}    # view -> Vector2i (the sunglasses in the run frame 0), or (-1,-1)
static var _loaded: bool = false

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_data = j
	return _data

static func beards() -> Array:
	return data().get("BEARDS", [])

static func style_label(i: int = -1) -> String:
	var b := beards()
	if b.is_empty():
		return ""
	return String(b[posmod(style if i < 0 else i, b.size())].label)

static func set_style(i: int) -> void:
	var n := maxi(1, beards().size())
	style = posmod(i, n)
	rev += 1
	save()

static func load_saved() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	style = clampi(int(cf.get_value("look", "hair", 0)), 0, maxi(0, beards().size() - 1))
	smooth = bool(cf.get_value("look", "smooth", true))
	var pf = cf.get_value("look", "place", null)
	if pf is Rect2:
		place_front = pf
	var pb = cf.get_value("look", "place_back", null)
	if pb is Rect2:
		place_back = pb
	for side in ["front", "back"]:
		var fn := "user://shirt_%s.png" % side
		if FileAccess.file_exists(fn):
			var im := Image.load_from_file(fn)
			if im and not im.is_empty():
				if side == "front":
					art_front = im
				else:
					art_back = im
	rev += 1

static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("look", "hair", style)
	cf.set_value("look", "smooth", smooth)
	cf.set_value("look", "place", place_front)
	cf.set_value("look", "place_back", place_back)
	cf.save(SAVE)
	for side in ["front", "back"]:
		var im: Image = art_front if side == "front" else art_back
		var fn := "user://shirt_%s.png" % side
		if im and not im.is_empty():
			im.save_png(fn)
		elif FileAccess.file_exists(fn):
			DirAccess.remove_absolute(fn)

## loadShirtArt: trim blank edges, no bigger than 512 px, set as the front (or back) picture.
static func set_art(im: Image, back: bool) -> void:
	if im == null or im.is_empty():
		return
	im = im.duplicate()
	im.convert(Image.FORMAT_RGBA8)
	var w := im.get_width()
	var h := im.get_height()
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			var blank := c.a < 30.0 / 255.0 or (c.r > 244.0 / 255.0 and c.g > 244.0 / 255.0 and c.b > 244.0 / 255.0)
			if not blank:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < x0:
		return
	im = im.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	var k := minf(1.0, 512.0 / float(maxi(im.get_width(), im.get_height())))
	if k < 1.0:
		im.resize(maxi(1, int(im.get_width() * k)), maxi(1, int(im.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	if back:
		art_back = im
	else:
		art_front = im
	rev += 1

static func clear_art() -> void:
	art_front = null
	art_back = null
	place_front = Rect2(0, 0, 1, 1)
	place_back = Rect2(0, 0, 1, 1)
	rev += 1
	save()

## shirtFitPlace: contain ("fit") or cover ("fill") the shirt's box, centred.
static func fit_place(im: Image, box: Vector2, mode: String) -> Rect2:
	if im == null or box.x <= 0 or box.y <= 0:
		return Rect2(0, 0, 1, 1)
	var ar := float(im.get_width()) / float(im.get_height())
	var br := box.x / box.y
	var w := 1.0
	var h := 1.0
	if (mode == "fit") == (ar > br):
		h = br / ar
	else:
		w = ar / br
	return Rect2((1.0 - w) / 2.0, (1.0 - h) / 2.0, w, h)

# ------------------------------------------------------------------ which frames

## "assets/CHARS/juicy_spud/sprites/throw_front_3.png" -> ["juicy_spud", "throw_front", 3]
static func parse(path: String) -> Array:
	var parts := path.split("/")
	if parts.size() < 4 or parts[1] != "CHARS":
		return []
	var sheet := parts[2]
	var base := parts[parts.size() - 1].get_basename()
	var idx := 0
	var key := base
	var us := base.rfind("_")
	if us > 0 and base.substr(us + 1).is_valid_int():
		key = base.substr(0, us)
		idx = int(base.substr(us + 1))
	else:
		key = base
	return [sheet, key, idx]

## hairView: which of front, diag, side, back, bdiag the frame shows ("" for none).
static func view_of(key: String) -> String:
	if key.begins_with("roll"):
		return ""
	for v in ["bdiag", "diag", "front", "side", "back"]:
		if key.begins_with(v):
			return v
	if key.ends_with("side"):
		return "side"
	if key.ends_with("front") or key == "reload" or key == "pickup":
		return "front"
	return ""

# ------------------------------------------------------------------ baking

## The frame with the style's hair and the shirt picture, or tex itself if neither applies.
static func baked(path: String, tex: Texture2D, flip: bool = false) -> Texture2D:
	if tex == null or (style == 0 and art_front == null and art_back == null):
		return tex
	var ck := "%s|%d|%d" % [path, int(flip), rev]
	if _cache.has(ck):
		return _cache[ck]
	var pk := parse(path)
	var out: Texture2D = tex
	if pk.size() == 3 and String(pk[0]).begins_with("juicy"):
		var fit_key := "%s.%s.%d" % [pk[0], pk[1], pk[2]]
		var fits: Dictionary = data().get("HAIR_FIT", {})
		var view := view_of(String(pk[1]))
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var changed := false
			if style > 0 and view != "" and fits.has(fit_key):
				var f: Array = fits[fit_key]
				var s := float(f[0])
				var ox := float(f[1])
				var oy := float(f[2])
				if absf(s - 1.0) < 0.05:
					s = 1.0
					ox = roundf(ox)
					oy = roundf(oy)
				_paint_hair(img, view, s, ox, oy)
				changed = true
			if (art_front != null or art_back != null) and String(pk[1]) != "" and view != "":
				var is_back := view == "back" or view == "bdiag"
				if _print(img, is_back, flip):
					changed = true
			if changed:
				out = ImageTexture.create_from_image(img)
	if _cache.size() > 600:
		_cache.clear()
	_cache[ck] = out
	return out

static func _hair_img(st: String, view: String) -> Image:
	var k := st + "_" + view
	if not _hair.has(k):
		var p := "res://scripts/lobby_life/art/bedroom/hair/%s.png" % k
		var im: Image = null
		if ResourceLoader.exists(p):
			var t = load(p)
			if t is Texture2D:
				im = t.get_image()
				if im.is_compressed():
					im.decompress()
				im.convert(Image.FORMAT_RGBA8)
		_hair[k] = im
	return _hair[k]

static func _blue(c: Color) -> bool:
	var r := int(c.r8)
	var g := int(c.g8)
	var b := int(c.b8)
	return c.a8 > 200 and b > 150 and r < 110 and b > g + 10

## hairAnchor: where the sunglasses are (the top-left of their blob) in an image, or (-1, -1).
static func _anchor(img: Image) -> Vector2i:
	var w := img.get_width()
	var h := img.get_height()
	var start := Vector2i(-1, -1)
	for y in int(h * 0.6):
		for x in w:
			if _blue(img.get_pixel(x, y)):
				start = Vector2i(x, y)
				break
		if start.x >= 0:
			break
	if start.x < 0:
		return start
	var seen := {}
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	var minx := w
	var miny := h
	var n := 0
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		n += 1
		minx = mini(minx, p.x)
		miny = mini(miny, p.y)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q := Vector2i(p.x + dx, p.y + dy)
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen.has(q):
					continue
				if _blue(img.get_pixel(q.x, q.y)):
					seen[q] = true
					stack.append(q)
	return Vector2i(minx, miny) if n >= 4 else Vector2i(-1, -1)

static func _view_anchor(view: String) -> Vector2i:
	if not _anchors.has(view):
		var t := GameData.tex("assets/CHARS/juicy/sprites/%s_run_0.png" % view)
		var a := Vector2i(-1, -1)
		if t:
			var im := t.get_image()
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			a = _anchor(im)
		_anchors[view] = a
	return _anchors[view]

## hairPaint: erase the old hair round the head, stamp the new style's art on it. img is changed.
static func _paint_hair(img: Image, view: String, s: float, ox: float, oy: float) -> void:
	var beard: Dictionary = beards()[style]
	var st := String(beard.key)
	var face := bool(beard.get("face", false))
	var arts: Dictionary = data().get("HAIR_ART", {})
	if not arts.has(st):
		return
	var av := view
	if not arts[st].has(av):
		av = "back" if view == "bdiag" else view
	var L := _hair_img(st, av)
	if L == null:
		return
	var at: Array = arts[st][av].at
	var head: Array = data().HAIR_HEAD[view]
	var hx := float(head[0])
	var t0 := float(head[1])
	var t1 := float(head[2])
	var hw := float(head[3])
	var hy := (t0 + t1) / 2.0
	var orig := img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var y1 := int(oy + (t1 + 18.0) * s)
	var dx := ox + float(at[0]) * s
	var dy := oy + float(at[1]) * s
	var dw := int(round(L.get_width() * s))
	var dh := int(round(L.get_height() * s))
	var ref := Vector2i(-1, -1)
	if face and view != "back" and view != "bdiag":
		ref = _view_anchor(view)
	var face_top := 1000000
	if ref.x >= 0:
		face_top = int((oy + (ref.y - 1) * s))
	var ys := int(oy + (t0 - 3.0) * s)
	var ye := mini(mini(y1, int(oy + (t1 + 1.0) * s)), face_top)
	var xs := int(ox + (hx - hw - 5.0) * s)
	var xe := int(ox + (hx + hw + 5.0) * s)
	var Ls := L
	if dw != L.get_width() or dh != L.get_height():
		Ls = L.duplicate()
		Ls.resize(maxi(1, dw), maxi(1, dh), Image.INTERPOLATE_NEAREST if s >= 0.8 else Image.INTERPOLATE_BILINEAR)
	var ix := int(round(dx))
	var iy := int(round(dy))
	for y in range(maxi(0, ys), mini(h, ye)):
		for x in range(maxi(0, xs), mini(w, xe)):
			var o: Color = orig.get_pixel(x, y)
			var ry := ((y + 0.5) - oy) / s - hy
			var rx := ((x + 0.5) - ox) / s - hx
			var grow := 2.5 if ry < 0.0 else 1.0
			var u := rx / (hw + grow)
			var v := ry / ((t1 - t0) / 2.0 + grow)
			var mx := maxi(o.r8, maxi(o.g8, o.b8))
			var hair_like: bool = o.a8 > 200 and mx < 125 and o.r8 >= o.b8 - 4 and o.g8 < o.r8 + 25
			var skin: bool = o.a8 > 100 and o.r8 > 120 and o.r8 > o.g8 + 25
			if u * u + v * v <= 1.0 and (hair_like or (ry < 0.0 and o.a8 < 200) or (mx < 125 and o.g8 < o.r8 + 10)):
				if not (ref.x >= 0 and skin):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif ref.x < 0 and v < (0.85 if view == "back" or view == "bdiag" else 0.3) and (skin or (o.a8 > 0 and mx < 125 and o.g8 < o.r8 + 10)):
				var lx := x - ix
				var ly := y - iy
				var covered := lx >= 0 and ly >= 0 and lx < Ls.get_width() and ly < Ls.get_height() and Ls.get_pixel(lx, ly).a8 > 0
				if not covered and (rx / (hw + 5.0)) * (rx / (hw + 5.0)) + v * v <= 1.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	# the new hair on top
	img.blend_rect(Ls, Rect2i(0, 0, Ls.get_width(), Ls.get_height()), Vector2i(ix, iy))
	if ref.x >= 0:
		# his sunglasses stay on top of any style that keeps his face
		for y in range(maxi(0, ys), mini(h, int(oy + (t1 + 6.0) * s))):
			for x in range(maxi(0, xs), mini(w, xe)):
				var o: Color = orig.get_pixel(x, y)
				if o.a8 > 200 and o.b8 > 140 and o.b8 > o.r8 + 40:
					img.set_pixel(x, y, o)

# ------------------------------------------------------------------ the shirt picture

static func _is_shirt(c: Color) -> bool:
	if c.a8 <= 200:
		return false
	var r := int(c.r8)
	var g := int(c.g8)
	var b := int(c.b8)
	return (g > 1.2 * r and g > 1.2 * b and g > 80) or (r < 60 and g >= 70 and b <= 1.2 * g) or (r < 30 and g >= 45 and g > 2 * r and b <= 1.4 * g)

## shirtSkin: the picture on the shirt's pixels, folds darkening it. Returns false if this frame has no shirt.
static func _print(img: Image, is_back: bool, flip: bool) -> bool:
	var a: Image = art_back if (is_back and art_back != null) else art_front
	if a == null:
		return false
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	var count := 0
	for y in h:
		var lo := w
		var hi := -1
		for x in w:
			if _is_shirt(img.get_pixel(x, y)):
				mask[y * w + x] = 1
				count += 1
				lo = mini(lo, x)
				hi = maxi(hi, x)
		if hi >= 0:
			y0 = mini(y0, y)
			y1 = maxi(y1, y)
			x0 = mini(x0, lo)
			x1 = maxi(x1, hi)
	if count < 60:
		return false
	# fill between the edges of each row: lettering and folds on the shirt count as shirt, skin and glass don't
	for y in range(y0, y1 + 1):
		var lo := -1
		var hi := -1
		for x in range(x0, x1 + 1):
			if mask[y * w + x] == 1:
				if lo < 0:
					lo = x
				hi = x
		if lo >= 0 and hi - lo < 90:
			for x in range(lo, hi + 1):
				if mask[y * w + x] == 0:
					var c: Color = img.get_pixel(x, y)
					var skin := c.r8 > 110 and c.r8 > 1.15 * c.g8 and c.r8 > 1.3 * c.b8
					if c.a8 > 200 and not skin:
						mask[y * w + x] = 2
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	var pl: Rect2 = place_back if (is_back and art_back != null) else place_front
	var pic := a
	if flip:
		pic = a.duplicate()
		pic.flip_x()
	var pw := maxi(1, int(round(pl.size.x * bw)))
	var ph := maxi(1, int(round(pl.size.y * bh)))
	var scaled := pic.duplicate()
	scaled.resize(pw, ph, Image.INTERPOLATE_BILINEAR if smooth else Image.INTERPOLATE_NEAREST)
	var plx := (1.0 - pl.position.x - pl.size.x) if flip else pl.position.x
	var px0 := x0 + int(round(plx * bw))
	var py0 := y0 + int(round(pl.position.y * bh))
	# the average brightness of the green, for the folds
	var lum_sum := 0.0
	var lum_n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if mask[y * w + x] == 1:
				var c: Color = img.get_pixel(x, y)
				lum_sum += 0.3 * c.r8 + 0.59 * c.g8 + 0.11 * c.b8
				lum_n += 1
	var avg := maxf(1.0, lum_sum / maxf(1.0, lum_n))
	var amt := (0.3 if smooth else 0.5) if is_back else 0.75
	var orig := img.duplicate()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if mask[y * w + x] == 0:
				continue
			var sx := x - px0
			var sy := y - py0
			if sx < 0 or sy < 0 or sx >= pw or sy >= ph:
				continue
			var pc: Color = scaled.get_pixel(sx, sy)
			if pc.a < 0.02:
				continue
			var oc: Color = orig.get_pixel(x, y)
			var shade := 1.0
			if mask[y * w + x] == 1:
				var lum: float = 0.3 * oc.r8 + 0.59 * oc.g8 + 0.11 * oc.b8
				var v := clampf(roundf(255.0 * lum / avg), 60.0, 255.0) / 255.0
				shade = 1.0 - amt + amt * v
			var col := Color(pc.r * shade, pc.g * shade, pc.b * shade, 1.0)
			img.set_pixel(x, y, oc.lerp(col, pc.a) if pc.a < 1.0 else col)
			img.set_pixel(x, y, Color(img.get_pixel(x, y), oc.a))
	return true

## The shirt's box in a frame (for the editor): Rect2i, or an empty one.
static func shirt_box(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	var n := 0
	for y in h:
		for x in w:
			if _is_shirt(img.get_pixel(x, y)):
				n += 1
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if n < 60:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## The frame with the picture at a trial place (the editor's preview), whatever is saved.
static func preview(img: Image, back: bool, place: Rect2, art: Image, smooth_: bool) -> Image:
	var keep := [art_front, art_back, place_front, place_back, smooth]
	if back:
		art_back = art
		place_back = place
	else:
		art_front = art
		place_front = place
	smooth = smooth_
	var out := img.duplicate()
	_print(out, back, false)
	art_front = keep[0]
	art_back = keep[1]
	place_front = keep[2]
	place_back = keep[3]
	smooth = keep[4]
	return out

# ------------------------------------------------------------------ picking a picture (pickShirtArt)

static var _pick_cb: JavaScriptObject
static var _dialog: FileDialog

## Ask for a picture file and hand the Image to on_image. In the web build the browser's own file chooser opens
## (an <input type=file>, as the HTML game does); elsewhere the system's file dialog.
static func pick_picture(parent: Node, on_image: Callable) -> void:
	if OS.has_feature("web"):
		var win := JavaScriptBridge.get_interface("window")
		_pick_cb = JavaScriptBridge.create_callback(func(args: Array) -> void:
			var im := _image_from_data_url(String(args[0]))
			if im:
				on_image.call(im))
		win.__lobbyPick = _pick_cb
		JavaScriptBridge.eval("(function(){var i=document.createElement('input');i.type='file';i.accept='image/*';i.onchange=function(){var f=i.files[0];if(!f)return;var r=new FileReader();r.onload=function(){window.__lobbyPick(r.result);};r.readAsDataURL(f);};i.click();})()")
		return
	var load_file := func(path: String) -> void:
		var im := Image.load_from_file(path)
		if im and not im.is_empty():
			on_image.call(im)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Pick a picture", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp;Pictures"]),
			func(ok: bool, paths: PackedStringArray, _f: int) -> void:
				if ok and paths.size() > 0:
					load_file.call(paths[0]))
		return
	if _dialog == null or not is_instance_valid(_dialog):
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = false
		_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
		_dialog.size = Vector2i(720, 460)
		parent.add_child(_dialog)
	for c in _dialog.file_selected.get_connections():
		_dialog.file_selected.disconnect(c.callable)
	_dialog.file_selected.connect(func(p: String) -> void: load_file.call(p))
	_dialog.popup_centered()

static func _image_from_data_url(url: String) -> Image:
	var comma := url.find(",")
	if comma < 0:
		return null
	var head := url.substr(0, comma)
	var buf := Marshalls.base64_to_raw(url.substr(comma + 1))
	var im := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if head.contains("png"):
		err = im.load_png_from_buffer(buf)
	elif head.contains("webp"):
		err = im.load_webp_from_buffer(buf)
	elif head.contains("jpeg") or head.contains("jpg"):
		err = im.load_jpg_from_buffer(buf)
	else:
		err = im.load_png_from_buffer(buf)
		if err != OK:
			err = im.load_jpg_from_buffer(buf)
		if err != OK:
			err = im.load_webp_from_buffer(buf)
	return im if err == OK else null
