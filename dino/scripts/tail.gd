extends RefCounted
## Cuts the tail off a body picture into a chain of short pieces, so the tail can bend and wag (Dino.animate).
## Works on any rig, the code-drawn placeholders and the imported sprites alike: the tail is whatever the body's
## zone map calls TAIL. The pieces follow the tail's own shape (by distance along it from where it joins the
## body), so a curled tail is cut across, not in upright strips. Each piece is a PixelPart hanging on the one
## before it (the first on the body), so bites tear it like anything else and biting through a joint drops the
## rest of the tail.

const DinoArt := preload("dino_art.gd")

## Tail pixels per piece (in the body picture's own pixels), and the most pieces a tail is cut into.
const PIECE_LEN := 7.0
const MAX_PIECES := 4
## Tails smaller than this stay part of the body.
const MIN_PIXELS := 20
## How many pixels of the piece in front each piece copies underneath itself.
const OVERLAP := 2.0

## `art` with its body's tail cut into pieces ("tail0", "tail1"... each with "tail": its place in the chain).
## The body picture and zones are copied first (the loader caches them), and `art` itself is left alone.
static func split(art: Dictionary) -> Dictionary:
	var b: Dictionary = {}
	for p: Dictionary in art.parts:
		if p.name == "body":
			b = p
	if b.is_empty():
		return art
	var src: Image = b.image
	var zsrc: PackedByteArray = b.zones
	var img: Image = src.duplicate()
	var zones: PackedByteArray = zsrc.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var solid := func(i: int) -> bool: return img.get_pixel(i % w, i / w).a > 0.0
	# where the tail joins the body: tail pixels touching something that isn't tail
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(-1.0)
	var queue := PackedInt32Array()
	var tail_n := 0
	var base := Vector2.ZERO
	for i in w * h:
		if zones[i] != DinoArt.TAIL or not solid.call(i):
			continue
		tail_n += 1
		for n in _around(i, w, h):
			if zones[n] != DinoArt.TAIL and solid.call(n):
				dist[i] = 0.0
				queue.append(i)
				base += Vector2(i % w, i / w)
				break
	if tail_n < MIN_PIXELS or queue.is_empty():
		return art
	base /= queue.size()
	# distance along the tail from there
	var head := 0
	var far := 0.0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for n in _around(i, w, h):
			if dist[n] < 0.0 and zones[n] == DinoArt.TAIL and solid.call(n):
				dist[n] = dist[i] + 1.0
				far = maxf(far, dist[n])
				queue.append(n)
	# the body's pixels round the tail's base (the first piece copies them underneath itself)
	var near_base := PackedByteArray()
	near_base.resize(w * h)
	var r := int(OVERLAP)
	for i in w * h:
		if dist[i] != 0.0:
			continue
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := i % w + dx
				var y := i / w + dy
				if x >= 0 and y >= 0 and x < w and y < h and zsrc[y * w + x] != DinoArt.TAIL and solid.call(y * w + x):
					near_base[y * w + x] = 1
	var count := clampi(roundi(far / PIECE_LEN), 1, MAX_PIECES)
	var step := (far + 1.0) / count
	var out: Array = []
	for p: Dictionary in art.parts:
		if p.name != "body":
			out.append(p)
	var body := b.duplicate()
	body.image = img
	body.zones = zones
	out.insert(0, body)
	var joint := base
	var host := "body"
	var host_joint: Vector2 = b.pivot
	for k in count:
		var lo := k * step
		var hi := (k + 1) * step
		var px := PackedInt32Array()
		# a copy of the last OVERLAP pixels of the piece before (or of the body round the tail's base), tucked
		# underneath it, so bending never opens a gap at the joint. Bites carve every part under them, so the copy
		# gets bitten along with the original.
		var under := PackedInt32Array()
		var ring := Vector2.ZERO
		var ring_n := 0
		var x0 := w
		var y0 := h
		var x1 := 0
		var y1 := 0
		for i in w * h:
			var own := dist[i] >= lo and dist[i] < hi
			var tucked := dist[i] >= lo - OVERLAP and dist[i] < lo if k > 0 else near_base[i] == 1
			if not own and not tucked:
				continue
			(px if own else under).append(i)
			x0 = mini(x0, i % w)
			x1 = maxi(x1, i % w)
			y0 = mini(y0, i / w)
			y1 = maxi(y1, i / w)
			if own and dist[i] < lo + 1.0:
				ring += Vector2(i % w, i / w)
				ring_n += 1
		if px.is_empty():
			break
		# each piece turns about the middle of its first row of pixels, where it meets the one before
		if k > 0 and ring_n > 0:
			joint = ring / ring_n
		var pw := x1 - x0 + 1
		var piece := Image.create(pw, y1 - y0 + 1, false, Image.FORMAT_RGBA8)
		var pz := PackedByteArray()
		pz.resize(pw * piece.get_height())
		var anchors := PackedInt32Array()
		for i in under:
			piece.set_pixel(i % w - x0, i / w - y0, src.get_pixel(i % w, i / w))
			pz[(i / w - y0) * pw + (i % w - x0)] = zsrc[i]
		for i in px:
			var j := (i / w - y0) * pw + (i % w - x0)
			piece.set_pixel(i % w - x0, i / w - y0, src.get_pixel(i % w, i / w))
			pz[j] = DinoArt.TAIL
			if dist[i] < lo + 2.0:
				anchors.append(j)
			img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
			zones[i] = DinoArt.NONE
		var pname := "tail%d" % k
		# drawn behind the piece it hangs on (Dino.build: show_behind_parent), so the tucked copy stays hidden
		out.append({"name": pname, "image": piece, "zones": pz, "pivot": joint - Vector2(x0, y0) + Vector2(0.5, 0.5),
				"pos": joint - host_joint + (Vector2(0.5, 0.5) if host == "body" else Vector2.ZERO), "anchors": anchors,
				"z": 0, "parent": host, "tail": k})
		host = pname
		host_joint = joint
	var copy := art.duplicate()
	copy.parts = out
	return copy

## The 8 pixels around `i` that are inside the picture.
static func _around(i: int, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := i % w
	var y := i / w
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and x + dx >= 0 and y + dy >= 0 and x + dx < w and y + dy < h:
				out.append((y + dy) * w + x + dx)
	return out
