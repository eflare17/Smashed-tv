class_name Gore
extends Node2D
## The mess: flying pixels (bitten-off flesh and blood drops) that fall and stain the ground for good, and the
## bigger pieces that come off whole (a tail, a leg, a head) and tumble, bounce and lie there. Stains are painted
## into one ground image, so they cost nothing to keep. Pieces are capped (the oldest goes).

const MAX_PIXELS := 5000
const MAX_PIECES := 40
const GRAVITY := 420.0
## The ground band stains land in (the strip in front of and behind the dinosaurs' feet).
const BAND := 14

var ground_y := 230.0
var world_w := 1280

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var col := PackedColorArray()
## The y each pixel lands at (somewhere in the ground band).
var floor_y := PackedFloat32Array()

var _stain_img: Image
var _stain_tex: ImageTexture
var _stain_dirty := false
var _pieces: Array = []   # [Sprite2D, vel, spin, resting]
var _rng := RandomNumberGenerator.new()

func setup(ground: float, width: int, stain_layer: Sprite2D) -> void:
	ground_y = ground
	world_w = width
	pos.resize(MAX_PIXELS)
	vel.resize(MAX_PIXELS)
	col.resize(MAX_PIXELS)
	floor_y.resize(MAX_PIXELS)
	_stain_img = Image.create(width, BAND + 4, false, Image.FORMAT_RGBA8)
	_stain_tex = ImageTexture.create_from_image(_stain_img)
	stain_layer.texture = _stain_tex
	stain_layer.centered = false
	stain_layer.position = Vector2(0, ground - 3)

func clear() -> void:
	count = 0
	for pc in _pieces:
		pc[0].queue_free()
	_pieces.clear()
	_stain_img.fill(Color(0, 0, 0, 0))
	_stain_dirty = true

func add(p: Vector2, v: Vector2, c: Color) -> void:
	var i := count
	if count >= MAX_PIXELS:
		# full: land the oldest-looking one now and reuse it
		i = _rng.randi() % MAX_PIXELS
		_stain(pos[i], col[i])
	else:
		count += 1
	pos[i] = p
	vel[i] = v
	col[i] = c
	floor_y[i] = ground_y - 2.0 + _rng.randf() * BAND

## Bitten-off pixels: some fly off away from the biter (`dir`), up and out.
func spray(removed: Array, dir: Vector2, share: float) -> void:
	for r in removed:
		if _rng.randf() < share:
			var v := (dir * _rng.randf_range(40.0, 140.0) + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-150, -50)))
			add(r[0], v, r[1])

## A spray of blood from `p`, mostly along `dir`.
func blood(p: Vector2, dir: Vector2, n: int, speed: float) -> void:
	for k in n:
		var v := dir.rotated(_rng.randf_range(-0.7, 0.7)) * speed * _rng.randf_range(0.3, 1.2)
		v.y -= _rng.randf_range(20.0, 90.0)
		add(p, v, _blood_color())

func drip(p: Vector2, v: Vector2) -> void:
	add(p, v + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(0, 15)), _blood_color())

## A pool spreading under a corpse: `n` stains around x.
func pool(x: float, half: float, n: int) -> void:
	for k in n:
		var p := Vector2(x + _rng.randf_range(-half, half) * _rng.randf(), ground_y - 1.0 + _rng.randf() * 6.0)
		_stain(p, _blood_color().darkened(_rng.randf_range(0.1, 0.4)))

func _blood_color() -> Color:
	return Color(_rng.randf_range(0.5, 0.75), 0.02, _rng.randf_range(0.02, 0.06))

## A piece that came off whole (PixelPart island), flung with `v`.
func piece(island: Dictionary, v: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(island.image)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.global_position = island.center
	s.rotation = island.rotation
	s.scale = island.scale
	s.z_index = 2
	add_child(s)
	_pieces.append([s, v, _rng.randf_range(-9.0, 9.0), false])
	if _pieces.size() > MAX_PIECES:
		_pieces[0][0].queue_free()
		_pieces.remove_at(0)

func step(delta: float) -> void:
	var i := 0
	while i < count:
		var v := vel[i]
		v.y += GRAVITY * delta
		var p := pos[i] + v * delta
		if p.y >= floor_y[i] and v.y > 0.0:
			_stain(Vector2(p.x, floor_y[i]), col[i])
			count -= 1
			pos[i] = pos[count]
			vel[i] = vel[count]
			col[i] = col[count]
			floor_y[i] = floor_y[count]
			continue
		pos[i] = p
		vel[i] = v
		i += 1
	for pc in _pieces:
		if pc[3]:
			continue
		var s: Sprite2D = pc[0]
		var v: Vector2 = pc[1]
		v.y += GRAVITY * delta
		s.position += v * delta
		s.rotation += pc[2] * delta
		var half := s.texture.get_size() * absf(s.scale.x) * 0.5
		var bottom := s.position.y + minf(half.x, half.y)
		if bottom > ground_y + 2.0 and v.y > 0.0:
			s.position.y -= bottom - (ground_y + 2.0)
			if v.y > 60.0:
				v = Vector2(v.x * 0.5, -v.y * 0.35)
				pc[2] *= 0.5
				blood(s.position, Vector2.UP, 4, 40.0)
			else:
				v = Vector2.ZERO
				pc[3] = true
				# lie flat-ish: snap to the nearest quarter turn
				s.rotation = roundf(s.rotation / (PI * 0.5)) * PI * 0.5
		elif _rng.randf() < delta * 20.0:
			drip(s.position, v * 0.3)
		s.position.x = clampf(s.position.x, 4.0, world_w - 4.0)
		pc[1] = v
	if _stain_dirty:
		_stain_tex.update(_stain_img)
		_stain_dirty = false
	queue_redraw()

func _stain(p: Vector2, c: Color) -> void:
	var x := int(p.x)
	var y := int(p.y - (ground_y - 3.0))
	if x < 0 or x >= world_w or y < 0 or y >= _stain_img.get_height():
		return
	var old := _stain_img.get_pixel(x, y)
	# wet blood darkens what's already there; new stains go on a little darker than they flew
	var nc := c.darkened(0.15)
	if old.a > 0.0:
		nc = old.lerp(nc, 0.6).darkened(0.05)
	nc.a = 1.0
	_stain_img.set_pixel(x, y, nc)
	_stain_dirty = true

func _draw() -> void:
	for i in count:
		draw_rect(Rect2(pos[i].floor(), Vector2.ONE), col[i])
