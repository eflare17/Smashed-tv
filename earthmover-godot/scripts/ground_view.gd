class_name GroundView
extends RefCounted
## Keeps the ground's two textures in step with the simulation, redoing only the chunks that changed. The ground and grass
## shaders read those textures, so this is all it takes for holes to open and grass to vanish.

var CELLS := DirtSim.CELLS
const CHUNK := DirtSim.CHUNK
var CHUNKS := DirtSim.CHUNKS
const UPLOAD_EVERY := 1.0 / 30.0
const RINGS := [[3, 0.45], [8, 1.2], [18, 2.4]]

var sim: DirtSim
var height_tex: ImageTexture
var data_tex: ImageTexture
## How much each cell looks like cracker dust, 0 to 255.
const LOOSE_FROM := 4           # steps of that before a chunk counts as having any
const DEEP_STEP := 4            # mm of loose stuff to a step of the lumps' texture: up to about a metre
var dust_tex: ImageTexture
var dust_data := PackedByteArray()
var _dust_changed := false
## Which chunks have loose stuff lying on them, so the lumps need only be drawn there.
var loose_here := PackedByteArray()

var heights := PackedFloat32Array()
var data := PackedByteArray()
# How each cell looks with no loose soil on it: its soil, rock and packed paint, and the firm ground's first height.
var base_r := PackedByteArray()
var base_g := PackedByteArray()
var base_b := PackedByteArray()
var first_bed := PackedInt32Array()
## Where a track or tyre has pressed loose soil flat, the height it left it at; NOT_PRESSED elsewhere. The lumps there are
## crushed, so a print shows as a smooth packed band through lumpy dirt, until dirt is pushed onto it or dug off it.
const NOT_PRESSED := -1000000
const PRESS_KEEP := 30          # mm the ground there can change by and still look pressed
var pressed_at := PackedInt32Array()

var _shade_queue: Dictionary = {}
var _heights_changed := false
var _data_changed := false
var _since_upload := 0.0
## Online, on the host: the chunks changed and not yet sent.
var net_watch := false
var changed: Dictionary = {}

func _init(ground: GroundData, s: DirtSim, h_tex: ImageTexture, d_tex: ImageTexture) -> void:
	sim = s
	height_tex = h_tex
	data_tex = d_tex
	heights = ground.heights.duplicate()
	data = ground.data.duplicate()
	first_bed = s.bed.duplicate()
	pressed_at.resize(CELLS * CELLS)
	pressed_at.fill(NOT_PRESSED)
	# Two to a cell: how the dust looks, and how deep the loose stuff lies, which is what makes it look lumpy.
	dust_data.resize(CELLS * CELLS * 2)
	for n in CELLS * CELLS:
		dust_data[n * 2 + 1] = mini((s.soil[n] + s.dust[n]) / DEEP_STEP, 255)
	dust_tex = ImageTexture.create_from_image(Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RG8, dust_data))
	loose_here.resize(CHUNKS * CHUNKS)
	for n in CELLS * CELLS:
		if dust_data[n * 2 + 1] >= LOOSE_FROM:
			loose_here[((n / CELLS) >> 4) * CHUNKS + ((n % CELLS) >> 4)] = 1
	var count := CELLS * CELLS
	base_r.resize(count)
	base_g.resize(count)
	base_b.resize(count)
	for n in count:
		base_r[n] = data[n * 4]
		base_g[n] = data[n * 4 + 1]
		base_b[n] = data[n * 4 + 2]

## A machine's track has worn this cell bare.
func wear(i: int, j: int) -> void:
	if i < 0 or j < 0 or i >= CELLS or j >= CELLS:
		return
	var n := j * CELLS + i
	if base_r[n] + base_b[n] >= 255 or base_g[n] > 128:
		return
	base_b[n] = 255 - base_r[n]
	sim.dirty[(j >> 4) * CHUNKS + (i >> 4)] = true

## A track or tyre has just pressed this cell's loose soil flat.
func press(i: int, j: int) -> void:
	if i < 0 or j < 0 or i >= CELLS or j >= CELLS:
		return
	var n := j * CELLS + i
	pressed_at[n] = sim.bed[n] + sim.soil[n]
	sim.dirty[(j >> 4) * CHUNKS + (i >> 4)] = true

## Whether this cell shows as pressed flat by a track.
func pressed(n: int) -> bool:
	return pressed_at[n] != NOT_PRESSED

func sync(delta: float, budget_usec := 2500) -> void:
	var t0 := Time.get_ticks_usec()
	for c: int in sim.dirty:
		_redo_chunk(c % CHUNKS, c / CHUNKS)
		_shade_queue[c] = true
		if net_watch:
			changed[c] = true
	sim.dirty.clear()
	# Shading looks further than one chunk, so it's the part that waits if time runs out.
	for c: int in _shade_queue.keys():
		if Time.get_ticks_usec() - t0 > budget_usec:
			break
		_shade_chunk(c % CHUNKS, c / CHUNKS)
		_shade_queue.erase(c)
	_since_upload += delta
	if _since_upload >= UPLOAD_EVERY and (_heights_changed or _data_changed or _dust_changed):
		_since_upload = 0.0
		if _heights_changed:
			height_tex.update(Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RF, heights.to_byte_array()))
			_heights_changed = false
		if _dust_changed:
			dust_tex.update(Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RG8, dust_data))
			_dust_changed = false
		if _data_changed:
			data_tex.update(Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RGBA8, data))
			_data_changed = false

func _redo_chunk(ci: int, cj: int) -> void:
	var bed := sim.bed
	var soil := sim.soil
	var i1 := mini((ci + 1) * CHUNK, CELLS)
	var j1 := mini((cj + 1) * CHUNK, CELLS)
	var any_loose := 0
	for j in range(cj * CHUNK, j1):
		for i in range(ci * CHUNK, i1):
			var n := j * CELLS + i
			var s := soil[n]
			var b := bed[n]
			var d := sim.dust[n]
			heights[n] = (b + s) * 0.001
			# Solid once there's enough to count as covering the ground, patchy under that, and mixed with dirt it shows as much as it is.
			var looks := mini(d, Mission.COVERED_MM) * d * 255 / (Mission.COVERED_MM * maxi(s, 1)) if d > 0 else 0
			var deep := mini((s + d) / DEEP_STEP, 255)
			# A track print stays pressed till dirt's pushed onto it or dug off it.
			var flat := false
			if pressed_at[n] != NOT_PRESSED:
				flat = s >= 40 and absi(b + s - pressed_at[n]) <= PRESS_KEEP
				if not flat:
					pressed_at[n] = NOT_PRESSED
			if flat:
				deep = 0
			if deep >= LOOSE_FROM:
				any_loose = 1
			if dust_data[n * 2] != looks or dust_data[n * 2 + 1] != deep:
				dust_data[n * 2] = looks
				dust_data[n * 2 + 1] = deep
				_dust_changed = true
			# Loose soil on top hides what's under it; cut-away ground shows bare, wherever it was grass.
			var cover := 255 if (s >= 40 or d >= 10 or b < first_bed[n] - 30) else 0
			var o := n * 4
			var r := maxi(base_r[n], cover)
			data[o] = r
			data[o + 1] = 0 if (s >= 40 or d >= 10) else base_g[n]
			data[o + 2] = mini(base_b[n], 255 - r)
			if flat:
				# Packed down: it looks like worked ground, not loose lumps.
				data[o] = 0
				data[o + 2] = 255
	loose_here[cj * CHUNKS + ci] = any_loose
	_heights_changed = true
	_data_changed = true

func _shade_chunk(ci: int, cj: int) -> void:
	var i1 := mini((ci + 1) * CHUNK, CELLS)
	var j1 := mini((cj + 1) * CHUNK, CELLS)
	var last := CELLS - 1
	for j in range(cj * CHUNK, j1):
		for i in range(ci * CHUNK, i1):
			var here := heights[j * CELLS + i]
			var dark := 0.0
			for ring in RINGS:
				var r: int = ring[0]
				var d: int = r * 7 / 10
				var x0 := maxi(i - r, 0)
				var x1 := mini(i + r, last)
				var y0 := maxi(j - r, 0)
				var y1 := mini(j + r, last)
				var u0 := maxi(i - d, 0)
				var u1 := mini(i + d, last)
				var v0 := maxi(j - d, 0)
				var v1 := mini(j + d, last)
				var total := heights[j * CELLS + x0] + heights[j * CELLS + x1] + heights[y0 * CELLS + i] + heights[y1 * CELLS + i]
				total += heights[v0 * CELLS + u0] + heights[v0 * CELLS + u1] + heights[v1 * CELLS + u0] + heights[v1 * CELLS + u1]
				dark = maxf(dark, (total / 8.0 - here) / float(ring[1]))
			data[(j * CELLS + i) * 4 + 3] = int((1.0 - clampf(dark, 0.0, 1.0) * 0.62) * 255.0)
	_data_changed = true
