class_name Dino
extends Node2D
## A side-on pixel dinosaur: PixelParts on a rig (flipped to face left or right), legs that swing as it walks,
## and bites that tear pixels out of whichever parts they land on. Player and Prey extend this with their own
## brains; the scene root steps them (step) so hit-stop can freeze everything at once.

const DinoArt := preload("dino_art.gd")

const GRAVITY := 520.0

var game: Node
var rig := Node2D.new()
var parts: Array[PixelPart] = []
var body: PixelPart
var head: PixelPart
var jaw: PixelPart
## [part, swing phase offset]
var legs: Array = []
var facing := 1.0
var vel := Vector2.ZERO
var on_ground := true
var walk_phase := 0.0
var dead := false
var height := 30.0
## Seconds of white hit-flash left.
var flash := 0.0
var _named := {}

func build(art: Dictionary) -> void:
	add_child(rig)
	height = art.height
	for p: Dictionary in art.parts:
		var part := PixelPart.new()
		part.setup(p.image, p.zones, p.pivot, p.anchors)
		part.name = p.name
		part.position = p.pos
		part.z_index = p.z
		var parent: Node = rig if p.parent == "" else _named[p.parent]
		parent.add_child(part)
		parts.append(part)
		if not _named.has(p.name):
			_named[p.name] = part
		if p.has("leg"):
			legs.append([part, p.leg])
		if p.has("tip"):
			part.set_meta("tip", p.tip)
	body = _named.get("body")
	head = _named.get("head")
	jaw = _named.get("jaw")
	body.set_meta("y0", body.position.y)
	# the hit flash: every part draws with the rig's material
	var mat := ShaderMaterial.new()
	mat.shader = _flash_shader()
	rig.material = mat
	for part in parts:
		part.use_parent_material = true

static var _shader: Shader

static func _flash_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = "shader_type canvas_item;\nuniform float flash = 0.0;\n" \
				+ "void fragment() { vec4 c = texture(TEXTURE, UV) * COLOR; c.rgb = mix(c.rgb, vec3(1.0), flash); COLOR = c; }"
	return _shader

func set_facing(f: float) -> void:
	facing = signf(f) if f != 0.0 else facing
	rig.scale.x = facing

## Legs swing with `walk_phase`; standing still they ease back to straight.
func animate(delta: float, moving: bool, stride: float) -> void:
	if moving:
		walk_phase += delta * stride
	else:
		walk_phase = lerpf(walk_phase, roundf(walk_phase / PI) * PI, minf(1.0, delta * 10.0))
	for l in legs:
		var part: PixelPart = l[0]
		part.rotation = sin(walk_phase + l[1]) * 0.55 if on_ground else (0.5 if l[1] == 0.0 else -0.3)
	body.position.y = body.get_meta("y0") - absf(sin(walk_phase)) * 1.0
	(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.85 if flash > 0.0 else 0.0)
	flash -= delta

## The zone under `world` (top-most part first), or 0.
func zone_at(world: Vector2) -> int:
	var best := 0
	var best_z := -1000
	for part in parts:
		if not part.carvable:
			continue
		var z := part.zone_at(world)
		if z != 0 and part.z_index > best_z:
			best = z
			best_z = part.z_index
	return best

## Bites at `world`: every part under the bite loses its pixels. Returns the merged carve results.
func bite(world: Vector2, radius: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"removed": [], "islands": [], "zones": PackedInt32Array()}
	out.zones.resize(DinoArt.ZONE_NAMES.size())
	for part in parts:
		var r := part.carve(world, radius, rng)
		out.removed.append_array(r.removed)
		out.islands.append_array(r.islands)
		for z in r.zones.size():
			out.zones[z] += r.zones[z]
	return out

func zone_fraction(z: int) -> float:
	var total := 0
	var left := 0
	for part in parts:
		total += part.zone_total[z]
		left += part.zone_left[z]
	return float(left) / maxf(1.0, total)

func mass_fraction() -> float:
	var total := 0
	var left := 0
	for part in parts:
		total += part.pixels_total()
		left += part.pixels_left()
	return float(left) / maxf(1.0, total)

## A random wound's world position on any part, or null.
func random_wound(rng: RandomNumberGenerator) -> Variant:
	var part: PixelPart = parts[rng.randi() % parts.size()]
	return part.random_wound(rng)

func wound_count() -> int:
	var n := 0
	for part in parts:
		n += part.wounds.size()
	return n

func set_show_zones(on: bool) -> void:
	for part in parts:
		part.show_zones = on
		part.rebuild()

## Falls, lands, stays inside the world.
func move(delta: float, ground: float, lo: float, hi: float) -> void:
	vel.y += GRAVITY * delta
	position += vel * delta
	position.x = clampf(position.x, lo, hi)
	on_ground = position.y >= ground
	if on_ground:
		position.y = ground
		vel.y = 0.0
