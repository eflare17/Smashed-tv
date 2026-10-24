class_name Dino
extends Node2D
## A side-on pixel dinosaur: PixelParts on a rig (flipped to face left or right), legs that swing as it walks,
## and bites that tear pixels out of whichever parts they land on. Player and Prey extend this with their own
## brains; the scene root steps them (step) so hit-stop can freeze everything at once.

const DinoArt := preload("dino_art.gd")

const GRAVITY := 520.0
## Legs bitten away slow a creature down to this fraction of its speed; under CRIPPLED_UNDER of its legs it can't
## jump or charge. PLACEHOLDER numbers.
const LEG_MIN_SPEED := 0.3
const CRIPPLED_UNDER := 0.5
## A step this high or lower is walked up, not bumped into.
const STEP := 12.0

var game: Node
var rig := Node2D.new()
var parts: Array[PixelPart] = []
var body: PixelPart
var head: PixelPart
var jaw: PixelPart
## Wings (flyers), flapped by their owner.
var wings: Array[PixelPart] = []
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
## Half its width for bumping into obstacles (before scaling).
var half_w := 8.0
## How high its origin sits above the ground when it stands (a flyer's origin is its body).
var foot := 0.0
## Set by move(): the side it bumped into an obstacle this frame (-1 left, 1 right), else 0.
var blocked := 0
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
		if p.has("wing"):
			wings.append(part)
		if p.has("leg"):
			legs.append([part, p.leg])
		if p.has("tip"):
			part.set_meta("tip", p.tip)
		# where it hangs on its parent (the body for legs and the head, the head for the jaw), in the parent's pixels
		if p.name != "body":
			var host: Dictionary = {}
			for q: Dictionary in art.parts:
				if q.name == (p.parent if p.parent != "" else "body"):
					host = q
					break
			var at: Vector2 = p.pos if p.parent != "" else p.pos - (host.pos as Vector2)
			part.set_meta("attach", [host.name, (host.pivot as Vector2) + at])
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

## Takes the rig apart (for a rebuild with new art: evolving).
func clear_rig() -> void:
	for c in rig.get_children():
		rig.remove_child(c)
		c.queue_free()
	if rig.get_parent() == self:
		remove_child(rig)
	parts.clear()
	legs.clear()
	wings.clear()
	_named.clear()
	body = null
	head = null
	jaw = null

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
	# bitten legs: the stride shortens into a limp, and the body dips on each step
	var limp := 1.0 - legs_left()
	for l in legs:
		var part: PixelPart = l[0]
		var swing := 0.55 - limp * 0.35
		part.rotation = sin(walk_phase + l[1]) * swing if on_ground else (0.5 if l[1] == 0.0 else -0.3)
	body.position.y = body.get_meta("y0") - absf(sin(walk_phase)) * 1.0 + limp * 3.0 + (maxf(0.0, sin(walk_phase)) * limp * 2.0)
	(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.85 if flash > 0.0 else 0.0)
	flash -= delta

## How much of its legs it still has, 0..1.
func legs_left() -> float:
	return zone_fraction(DinoArt.LEGS)

## How fast it can go with the legs it has left: full speed with them whole, down to LEG_MIN_SPEED with them gone.
func leg_speed() -> float:
	return lerpf(LEG_MIN_SPEED, 1.0, legs_left())

## Legs too bitten to jump or charge.
func crippled() -> bool:
	return legs_left() < CRIPPLED_UNDER

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
	# a part whose hold on its parent was bitten away comes off whole (a head off the neck, a leg off the hip)
	for part in parts:
		if not part.has_meta("attach") or part.pixels_left() == 0:
			continue
		var at: Array = part.get_meta("attach")
		var host: PixelPart = _named[at[0]]
		if not host.holds(at[1], 2) or host.pixels_left() == 0:
			for p: PixelPart in [part] + _children(part):
				var isl := p.detach()
				if not isl.is_empty():
					out.islands.append(isl)
					for z in isl.zones.size():
						out.zones[z] += isl.zones[z]
	return out

func _children(part: PixelPart) -> Array:
	var out: Array = []
	for c in part.get_children():
		if c is PixelPart:
			out.append(c)
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

## Walks into obstacles (blocked: -1 / 1, the side it bumped, else 0), stands on their tops, falls, lands, stays
## inside the world. Obstacles are the area's Rect2s (top-left, size), standing on the ground.
func move(delta: float) -> void:
	var prev := position
	var hw := half_w * absf(scale.x)
	vel.y += GRAVITY * delta
	position.x = clampf(position.x + vel.x * delta, hw, game.world_w - hw)
	blocked = 0
	for o: Rect2 in game.obstacles:
		if position.x + hw > o.position.x and position.x - hw < o.end.x and position.y > o.position.y + 1.0:
			# a low step is walked up; anything higher is a wall
			if on_ground and position.y - o.position.y <= STEP + 0.5:
				position.y = o.position.y
				prev.y = o.position.y
				continue
			if prev.x <= o.get_center().x:
				position.x = o.position.x - hw
				blocked = 1
			else:
				position.x = o.end.x + hw
				blocked = -1
	position.y += vel.y * delta
	var floor_y: float = game.GROUND_Y - foot
	for o: Rect2 in game.obstacles:
		if position.x + hw > o.position.x and position.x - hw < o.end.x and prev.y <= o.position.y + 1.0:
			floor_y = minf(floor_y, o.position.y - foot)
	# shelves in the air are one-way: jump up through them, land on them from above
	if vel.y >= 0.0:
		for o: Rect2 in game.platforms:
			if position.x + hw > o.position.x and position.x - hw < o.end.x and prev.y <= o.position.y + 1.0 \
					and position.y >= o.position.y - 0.5:
				floor_y = minf(floor_y, o.position.y - foot)
	on_ground = position.y >= floor_y
	if on_ground:
		position.y = floor_y
		vel.y = 0.0
