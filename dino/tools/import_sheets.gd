extends SceneTree
## Turns the generated sprite sheets (art/raw/<creature>_sheet.jpg: pieces laid out on magenta, drawn as big
## blocky "pixels") into clean small PNGs the game loads (art/<creature>_<part>.png), one per piece, at the
## sheet's real pixel grid. From the dino folder:
##   godot --headless --path . --script res://tools/import_sheets.gd
## For each sheet: key out the magenta (with slack for JPEG smudge), find the separate pieces (connected blobs),
## work out the grid cell size from the run lengths of the outline, sample one pixel per cell, snap colours to a
## small palette, name the pieces by shape (body is the biggest; a leg is tall; a jaw is a flat wide sliver; a
## wing is the wide one on a flyer sheet; what's left is the head), and save them.

const SHEETS := {
	"raptor": 4, "hatchling": 4, "allosaur": 4, "tyrant": 4,
	"grazer": 2, "runner": 2, "charger": 2, "flyer": 2,
	# the owner's first Dino Maker sheets (25 Oct): body and one leg each, nothing in the game yet
	"ankylosaurus": 2, "stegosaurus": 2, "corythosaurus": 2, "iguanodon": 2, "pachycephalosaurus": 2,
	"carnotaurus": 2, "dimetrodon": 2,
}

func _initialize() -> void:
	for creature: String in SHEETS:
		_import(creature, SHEETS[creature])
	quit()

func _keyed(c: Color) -> bool:
	# magenta, allowing for JPEG: strong red and blue, little green
	return c.r > 0.6 and c.b > 0.6 and c.g < 0.45

func _import(creature: String, pieces_wanted: int) -> void:
	var path := "res://art/raw/%s_sheet.jpg" % creature
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		print("%s: no sheet" % creature)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# 1. mask: which pixels are not background
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 0 if _keyed(img.get_pixel(x, y)) else 1
	# a little erosion then dilation to drop JPEG fringe specks
	solid = _open(solid, w, h)
	# 2. connected blobs
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var blobs: Array = []
	for y in h:
		for x in w:
			var i := y * w + x
			if solid[i] == 1 and label[i] < 0:
				var b := _flood(solid, label, w, h, i, blobs.size())
				if b.count > 400:
					blobs.append(b)
	blobs.sort_custom(func(a, b): return a.count > b.count)
	blobs = blobs.slice(0, pieces_wanted)
	# 3. grid cell size: the most common short run length of one colour inside the biggest blob
	var cell := _cell_size(img, blobs[0])
	print("%s: %d pieces, cell %d px" % [creature, blobs.size(), cell])
	for b: Dictionary in blobs:
		print("   blob %d px at %d,%d-%d,%d" % [b.count, b.x0, b.y0, b.x1, b.y1])
	# 4. name the pieces
	var names := _name_pieces(creature, blobs, pieces_wanted)
	# 5. sample each piece on the grid and save
	for k in blobs.size():
		var b: Dictionary = blobs[k]
		var out := _sample(img, solid, label, w, b.id, b, cell)
		var file := "res://art/%s_%s.png" % [creature, names[k]]
		out.save_png(ProjectSettings.globalize_path(file))
		print("   %s: %dx%d" % [names[k], out.get_width(), out.get_height()])

func _open(solid: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var er := PackedByteArray()
	er.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			er[i] = 1 if (solid[i] == 1 and solid[i - 1] == 1 and solid[i + 1] == 1 and solid[i - w] == 1 and solid[i + w] == 1) else 0
	var di := PackedByteArray()
	di.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			di[i] = 1 if (er[i] == 1 or er[i - 1] == 1 or er[i + 1] == 1 or er[i - w] == 1 or er[i + w] == 1) else 0
	return di

func _flood(solid: PackedByteArray, label: PackedInt32Array, w: int, h: int, start: int, id: int) -> Dictionary:
	var stack := PackedInt32Array([start])
	label[start] = id
	var x0 := w
	var y0 := h
	var x1 := 0
	var y1 := 0
	var n := 0
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		n += 1
		var x := i % w
		var y := i / w
		x0 = mini(x0, x)
		x1 = maxi(x1, x)
		y0 = mini(y0, y)
		y1 = maxi(y1, y)
		# 8-way, so thin diagonal outlines stay joined
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if solid[j] == 1 and label[j] < 0:
					label[j] = id
					stack.append(j)
	return {"id": id, "count": n, "x0": x0, "y0": y0, "x1": x1, "y1": y1}

## The sheet's pixel grid. For each candidate cell size, lay a grid over the biggest piece and score how uniform
## the cells are (how many of a cell's pixels match its centre colour). The true size scores high; so do its
## multiples, so the answer is the smallest candidate within a whisker of the best.
func _cell_size(img: Image, b: Dictionary) -> int:
	# where the colour changes along the rows: on a blocky picture those sit on the grid lines
	var edges := PackedInt32Array()
	for y in range(b.y0, b.y1 + 1, 4):
		var prev := _q(img.get_pixel(b.x0, y))
		for x in range(b.x0 + 1, b.x1 + 1):
			var c := _q(img.get_pixel(x, y))
			if c != prev:
				edges.append(x)
				prev = c
	# for each cell size, the share of edges within a pixel of some grid phase, less what chance would give
	var best_cell := 16
	var best_score := -1.0
	for cell in range(8, 41):
		var counts := PackedInt32Array()
		counts.resize(cell)
		for x in edges:
			counts[x % cell] += 1
		var top := 0
		for ph in cell:
			var n := counts[ph] + counts[(ph + 1) % cell] + counts[(ph + cell - 1) % cell]
			top = maxi(top, n)
		var score := float(top) / maxi(1, edges.size()) - 3.0 / cell
		if score > best_score:
			best_score = score
			best_cell = cell
	return best_cell

func _q(c: Color) -> int:
	return int(c.r * 7.99) * 64 + int(c.g * 7.99) * 8 + int(c.b * 7.99)

## One pixel per cell: the most common colour in the cell's middle, keyed cells left clear.
func _sample(img: Image, solid: PackedByteArray, label: PackedInt32Array, w: int, id: int, b: Dictionary, cell: int) -> Image:
	# align the grid to the piece's left/top edge, then widen to catch the edge cells
	var cols := int(ceil(float(b.x1 - b.x0 + 1) / cell))
	var rows := int(ceil(float(b.y1 - b.y0 + 1) / cell))
	var out := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	for r in rows:
		for c in cols:
			var cx: int = b.x0 + c * cell
			var cy: int = b.y0 + r * cell
			var votes := {}
			var hits := 0
			var tot := 0
			for sy in range(cy + cell / 4, cy + cell - cell / 4):
				for sx in range(cx + cell / 4, cx + cell - cell / 4):
					if sx >= w or sy >= img.get_height():
						continue
					tot += 1
					var i := sy * w + sx
					if solid[i] == 1 and label[i] == id:
						hits += 1
						var q := _q(img.get_pixel(sx, sy))
						votes[q] = votes.get(q, 0) + 1
			if tot == 0 or hits * 2 < tot:
				continue
			var best := -1
			var best_n := 0
			for q: int in votes:
				if votes[q] > best_n:
					best_n = votes[q]
					best = q
			# the mean of that quantised colour's samples, so the palette keeps its real shades
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for sy in range(cy + cell / 4, cy + cell - cell / 4):
				for sx in range(cx + cell / 4, cx + cell - cell / 4):
					if sx < w and sy < img.get_height() and _q(img.get_pixel(sx, sy)) == best and label[sy * w + sx] == id:
						sum += img.get_pixel(sx, sy)
						n += 1
			var col := sum / n
			col.a = 1.0
			out.set_pixel(c, r, col)
	return _trim(out)

func _trim(img: Image) -> Image:
	var r := img.get_used_rect()
	return img.get_region(r) if r.size.x > 0 else img

## Body: the biggest. On a 4-piece sheet: leg = the tallest of the rest (taller than wide), jaw = the flattest
## (much wider than tall, and small), head = the other. On a 2-piece sheet: the other is the leg (or the wing).
func _name_pieces(creature: String, blobs: Array, wanted: int) -> Array:
	var names: Array = []
	names.resize(blobs.size())
	names[0] = "body"
	if wanted == 2:
		for k in range(1, blobs.size()):
			names[k] = "leg"
		# a spread wing is bigger than the pterodactyl's body: the biggest piece is the wing
		if creature == "flyer":
			names[0] = "wing"
			for k in range(1, blobs.size()):
				names[k] = "body"
		return names
	var rest := range(1, blobs.size())
	var leg := -1
	var best_aspect := 0.0
	for k in rest:
		var b: Dictionary = blobs[k]
		var aspect := float(b.y1 - b.y0) / maxf(1.0, b.x1 - b.x0)
		if aspect > best_aspect:
			best_aspect = aspect
			leg = k
	names[leg] = "leg"
	rest.erase(leg)
	var jaw := -1
	var flattest := 0.0
	for k in rest:
		var b: Dictionary = blobs[k]
		var flat := float(b.x1 - b.x0) / maxf(1.0, b.y1 - b.y0)
		if flat > flattest:
			flattest = flat
			jaw = k
	names[jaw] = "jaw"
	rest.erase(jaw)
	for k in rest:
		names[k] = "head"
	return names
