extends RefCounted
## The World's pictures made in code: the HTML game's first-person materials (fpMaterial in Smashed.html: walls,
## fences, the garage, the shed, the ute, the barbecue...), each as a small texture to wrap round a solid, and the
## yard picture with each solid's spread-out art painted over (fpPaintOut), since in 3D those stand up instead.
## One texel is one HTML unit. Used by world_builder.gd.

## JS's fpHash: a repeatable 0..1 from an integer.
static func fhash(n: int) -> float:
	n = n & 0xFFFFFFFF
	n = ((n ^ (n >> 15)) * 0x2c1b3c6d) & 0xFFFFFFFF
	n = ((n ^ (n >> 12)) * 0x297a2d39) & 0xFFFFFFFF
	return float((n ^ (n >> 15)) & 0xFFFFFFFF) / 4294967296.0

static func rep(u: float, n: float) -> float:
	return fposmod(u, n)

## The colour of a solid's side at u across its face and z up it (fpMaterial). s: the solid's data (h, m, x0.. and
## for the ute its part), face: "N", "E", "S", "W" (the way it looks). Returns r, g, b in 0..255 and a in 0..1.
## (m and H: the solid's material and height, when the caller has them already: it's called for every texel.)
static func material(s: Dictionary, face: String, u: float, z: float, m: String = "", H: float = -1.0) -> Color:
	if H < 0:
		H = float(s.get("h", 150))
	if m == "":
		m = String(s.get("m", ""))
	var r := 150.0
	var g := 150.0
	var b := 150.0
	var a := 1.0
	match m:
		"in":
			r = 168; g = 150; b = 128
			if z < 10.5:
				r *= 0.6; g *= 0.6; b *= 0.6
		"house":
			if z < 7:
				r = 74; g = 74; b = 76
			else:
				r = 160; g = 154; b = 132
				if fmod(z - 7, 9) < 1.4:
					r = 112; g = 108; b = 92
		"fence":
			if rep(u, 11) < 1.3:
				r = 58; g = 46; b = 32
			else:
				var k := 0.88 + 0.22 * fhash(int(floor(u / 11)) + 977)
				r = 124 * k; g = 102 * k; b = 74 * k
				if z > H - 5:
					r *= 0.82; g *= 0.82; b *= 0.82
				elif z < 4:
					r = 80; g = 64; b = 46
		"garage":
			if face == "S" and u > 952 and u < 1208 and z < 84:
				if z > 80:
					r = 58; g = 54; b = 50
				else:
					var k := 0.7 if fmod(z, 7) < 1.2 else 1.0
					r = 118 * k; g = 114 * k; b = 106 * k
			else:
				var k := 1.0 if rep(u, 6) < 3 else 0.84
				if fhash(int(floor(u / 6)) + 31) < 0.3:
					r = 126 * k; g = 84 * k; b = 60 * k
				else:
					r = 136 * k; g = 124 * k; b = 110 * k
				if z > H - 7:
					r *= 0.78; g *= 0.78; b *= 0.78
		"shed":
			if face == "S" and u > 230 and u < 292 and z < 66:
				r = 66; g = 60; b = 54
			else:
				var k := 1.0 if rep(u, 5) < 2.5 else 0.85
				var rust := fhash(int(floor(u / 5)) + 7) < 0.22 and fhash(int(floor(u / 5)) * 61 + int(floor(z / 10))) < 0.75
				if rust:
					r = 130 * k; g = 88 * k; b = 62 * k
				else:
					r = 152 * k; g = 152 * k; b = 150 * k
				if z > H - 5:
					r *= 0.78; g *= 0.78; b *= 0.78
		"car":
			var p := String(s.get("part", ""))
			var side_on := face == "E" or face == "W"
			var v: float = (u - s.y0) / (s.y1 - s.y0) if side_on else (u - s.x0) / (s.x1 - s.x0)
			if z < 13:
				var wheel := side_on and ((p == "tray" and v > 0.25 and v < 0.7) or (p == "bonnet" and v > 0.3 and v < 0.78))
				r = 22 if wheel else 42; g = r; b = r
			else:
				r = 138; g = 134; b = 112
				if p == "tray":
					if face == "N" and z > 27 and z < 39 and (v < 0.1 or v > 0.9):
						r = 196; g = 42; b = 36
					elif z > 40:
						r = 104; g = 100; b = 84
				elif p == "cab":
					if z > 44 and z < 63 and v > 0.07 and v < 0.93:
						r = 40; g = 54; b = 66
					elif side_on and z < 44 and absf(v - 0.5) < 0.012:
						r = 92; g = 88; b = 74
				elif face == "S":
					if z < 19:
						r = 72; g = 72; b = 74
					elif z < 32:
						if v < 0.15 or v > 0.85:
							r = 236; g = 230; b = 196
						else:
							r = 34; g = 36; b = 38
		"bbq":
			if z < 24:
				var row := int(floor(z / 6))
				var uu := u + (row & 1) * 6
				if fmod(z, 6) < 1 or rep(uu, 12) < 1:
					r = 176; g = 166; b = 152
				else:
					var k := 0.9 + 0.2 * fhash(row * 131 + int(floor(uu / 12)))
					r = 124 * k; g = 64 * k; b = 50 * k
			elif z < 27:
				r = 86; g = 86; b = 88
			else:
				r = 166; g = 168; b = 174
				if absf(z - 31) < 0.8:
					r = 90; g = 92; b = 96
		"wood":
			r = 126; g = 88; b = 56
			if fmod(z, 7) < 1:
				r *= 0.78; g *= 0.78; b *= 0.78
		"bush":
			if z > H - 10 * fhash(int(floor(u / 4)) + 5):
				a = 0
			else:
				var k := 0.7 + 0.55 * fhash(int(floor(u / 3)) * 977 + int(floor(z / 3)))
				r = 50 * k; g = 104 * k; b = 42 * k
		"tramp":
			var tr: Dictionary = s.get("tramp", {})
			var circ := TAU * float(tr.get("r", 122))
			var mat := float(tr.get("mat", 32))
			if z < 22:
				if rep(u, circ / 6) < 5:
					r = 50; g = 52; b = 56
				else:
					a = 0
			elif z < 26:
				var k := 0.78 if rep(u, 3) < 1 else 1.0
				r = 132 * k; g = 136 * k; b = 142 * k
			elif z <= mat:
				if z > mat - 1.2:
					r = 80; g = 120; b = 208
				else:
					r = 44; g = 84; b = 172
			elif z > H - 2.5 or rep(u, circ / 8) < 3:
				r = 58; g = 60; b = 66
			else:
				r = 12; g = 12; b = 16
				a = 0.42 if (rep(u, 4) < 0.7 or rep(z, 4) < 0.7) else 0.1
		"junk":
			if rep(u, 22) < 11:
				r = 134; g = 66; b = 48
			else:
				r = 152; g = 112; b = 64
			if fmod(z, 6) < 1:
				r *= 0.75; g *= 0.75; b *= 0.75
		"bed":
			r = 108; g = 76; b = 46
			if z > H - 2:
				r = 132; g = 98; b = 62
			elif fmod(z, 8) < 1:
				r = 78; g = 54; b = 32
		"tank":
			var k := 1.0 if fmod(z, 6) < 3 else 0.84
			r = 170 * k; g = 176 * k; b = 178 * k
			if z > H - 3:
				r = 192; g = 198; b = 200
			elif z < 2:
				r = 92; g = 94; b = 94
		"esky":
			if z > H - 6:
				r = 230; g = 234; b = 238
			elif z < 2:
				r = 30; g = 40; b = 60
			else:
				r = 48; g = 110; b = 190
		"compost":
			r = 58; g = 86; b = 50
			if z > H - 4:
				r = 44; g = 64; b = 38
			elif fmod(z, 9) < 1:
				r = 40; g = 60; b = 34
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

## A texture of a solid's side: w texels across (u from u0) and zh up (z from 0 at the bottom row), one per unit.
## Rows: the top row is z = zh. Mipmapped (it's seen at a slant).
static func side_texture(s: Dictionary, face: String, u0: float, w: int, zh: int) -> ImageTexture:
	w = maxi(1, w)
	zh = maxi(1, zh)
	var data := PackedByteArray()
	data.resize(w * zh * 4)
	var i := 0
	var m := String(s.get("m", ""))
	var H := float(s.get("h", 150))
	for j in zh:
		var z := zh - j - 0.5
		for x in w:
			var c := material(s, face, u0 + x + 0.5, z, m, H)
			data[i] = int(clampf(c.r, 0, 1) * 255.0)
			data[i + 1] = int(clampf(c.g, 0, 1) * 255.0)
			data[i + 2] = int(clampf(c.b, 0, 1) * 255.0)
			data[i + 3] = int(c.a * 255.0)
			i += 4
	var img := Image.create_from_data(w, zh, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## A corrugated-iron roof slope (the HTML game's roofRows): ribs every 6 (garage) or 5 (shed) units running down
## the slope, some rusty. One row of texels along the slope's length; it's stretched up the slope.
static func roof_texture(m: String, length: int) -> ImageTexture:
	length = maxi(1, length)
	var img := Image.create(length, 4, true, Image.FORMAT_RGBA8)
	for x in length:
		var along := x + 0.5
		var c: Color
		if m == "garage":
			var kk := 1.0 if rep(along, 6) < 3 else 0.82
			c = Color8(int(132 * kk), int(86 * kk), int(60 * kk)) if fhash(int(floor(along / 6)) + 31) < 0.35 else Color8(int(140 * kk), int(128 * kk), int(114 * kk))
		else:
			var kk := 1.0 if rep(along, 5) < 2.5 else 0.82
			c = Color8(int(134 * kk), int(90 * kk), int(64 * kk)) if fhash(int(floor(along / 5)) + 7) < 0.2 else Color8(int(156 * kk), int(156 * kk), int(154 * kk))
		for y in 4:
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The trampoline's mat, springs and pad seen from above (n texels across its whole width, 2r).
static func tramp_top_texture(tr: Dictionary, n: int) -> ImageTexture:
	var R := float(tr.get("r", 122))
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var wx := (x + 0.5) / n * 2.0 * R - R
			var wy := (y + 0.5) / n * 2.0 * R - R
			var rr := sqrt(wx * wx + wy * wy)
			var c := Color(0, 0, 0, 0)
			if rr < R - 18:
				var kk := 1.4 if (rep(wx + wy, 14) < 1 or rep(wx - wy, 14) < 1) else 1.0
				c = Color8(int(24 * kk), int(24 * kk), int(28 * kk))
			elif rr < R - 15:
				c = Color8(120, 124, 130)
			elif rr < R:
				var seam := 0.8 if rep((atan2(wy, wx) + PI) * R, 26) < 1.2 else 1.0
				c = Color8(int(46 * seam), int(88 * seam), int(178 * seam))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The water tank from above: its rim, and the water in it.
static func tank_top_texture(r: float, n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var wx := (x + 0.5) / n * 2.0 * r - r
			var wy := (y + 0.5) / n * 2.0 * r - r
			var d := sqrt(wx * wx + wy * wy)
			var c := Color(0, 0, 0, 0)
			if d > r - 7 and d <= r:
				c = Color8(196, 200, 204)
			elif d <= r - 7:
				var kk := 1.15 if rep(wx * 0.7 + wy, 18) < 1.2 else 1.0
				c = Color8(int(78 * kk), int(128 * kk), int(176 * kk))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## fpPaintOut: one solid's picture, where it spreads past the ground the solid stands on, filled with the colour
## round it (the median of a ring just outside its art), a little grain, and darker under the trampoline (its
## shadow). img: the yard picture (RGB8 or RGBA8), its top-left corner at world (ox, oy).
static func paint_out(img: Image, s: Dictionary, ox: int, oy: int) -> void:
	var art: Array = s["art"]
	var W := img.get_width()
	var Hh := img.get_height()
	var ch := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
	var ax0 := int(art[0]) - ox
	var ay0 := int(art[1]) - oy
	var ax1 := int(art[2]) - ox
	var ay1 := int(art[3]) - oy
	var x0 := maxi(0, ax0 - 3)
	var y0 := maxi(0, ay0 - 3)
	var x1 := mini(W, ax1 + 3)
	var y1 := mini(Hh, ay1 + 3)
	var data := img.get_data()
	var ring := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for y in range(y0, y1):
		for x in range(x0, x1):
			if x >= ax0 and x < ax1 and y >= ay0 and y < ay1:
				continue
			var o := (y * W + x) * ch
			ring[0].append(data[o]); ring[1].append(data[o + 1]); ring[2].append(data[o + 2])
	var med := [0, 0, 0]
	for c in 3:
		var v: PackedInt32Array = ring[c]
		v.sort()
		med[c] = v[v.size() >> 1] if v.size() > 0 else 0
	var is_round := s.has("r")
	var tramp := String(s.get("m", "")) == "tramp"
	var from_above := String(s.get("m", "")) == "fence"
	for y in range(maxi(0, ay0), mini(Hh, ay1)):
		for x in range(maxi(0, ax0), mini(W, ax1)):
			var wx := x + ox + 0.5
			var wy := y + oy + 0.5
			var inside: bool
			if is_round:
				inside = Vector2(wx - float(s.cx), wy - float(s.cy)).length() < float(s.r)
			else:
				inside = wx > float(s.x0) and wx < float(s.x1) and wy > float(s.y0) and wy < float(s.y1)
			if inside and not tramp:
				continue
			var k := (0.985 + 0.03 * fhash(((int(wx) * 7919) ^ (int(wy) * 104729)))) * (0.55 if inside else 1.0)
			var o := (y * W + x) * ch
			if from_above:
				# a fence: drawn standing up the picture over what's behind it; carry on what's above it instead
				var oa := (maxi(0, ay0 - 2) * W + x) * ch
				data[o] = clampi(int(data[oa] * k), 0, 255)
				data[o + 1] = clampi(int(data[oa + 1] * k), 0, 255)
				data[o + 2] = clampi(int(data[oa + 2] * k), 0, 255)
				continue
			data[o] = clampi(int(med[0] * k), 0, 255)
			data[o + 1] = clampi(int(med[1] * k), 0, 255)
			data[o + 2] = clampi(int(med[2] * k), 0, 255)
	img.set_data(W, Hh, false, img.get_format(), data)
