class_name Props
extends RefCounted
## The look test's bulldozer and pine trees, in the palette's solid swatches. Colours are given as they look on screen and
## turned into the linear values the shader wants.

static func c(hex: String) -> Color:
	# The web graphics mode already takes a mesh's colours as they look on screen, and would darken them a second time.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return Color(hex)
	return Color(hex).srgb_to_linear()

static var _dust_mat: ShaderMaterial

## What cracker dust looks like off the ground: in a bucket or a tray, or falling.
static func dust_mat() -> ShaderMaterial:
	if _dust_mat == null:
		_dust_mat = ShaderMaterial.new()
		_dust_mat.shader = preload("res://shaders/dust_prop.gdshader")
	return _dust_mat

static var YELLOW := c("#f6b40e")
static var YELLOW_DARK := c("#d18f06")
static var CHARCOAL := c("#34363a")
static var BLACK := c("#1c1d20")
static var STEEL := c("#7d8287")
static var SEAT := c("#4a3226")
static var LAMP := c("#fff3b8")
static var TRUNK := c("#6e4a2d")
static var PINE_A := c("#2f8a43")
static var PINE_B := c("#3fa24d")
static var PINE_C := c("#25733a")

static var GLASS := c("#2c4656")
static var WHITE_PAINT := c("#efe8d8")
static var RED := c("#c9402c")
static var HI_VIS := c("#ff7a1a")
# The mine's big machines: fleet white, grey for the shaded parts, safety yellow for what you hold on to.
static var MINE_WHITE := c("#dcd8cd")
static var MINE_GREY := c("#b9bbb7")
static var SAFETY := c("#ffd21f")
# Dirt off the ground: in a bucket or tray, or flying. Red on the mine.
static var DIRT := c("#7d4329")
static var DIRT_DARK := c("#6a3722")
static var DIRT_LIGHT := c("#8a4c30")

## The mine's red dirt or the usual brown, for what's built next. These outlive a scene, so every scene sets them.
static func set_dirt(mine: bool) -> void:
	DIRT = c("#9c4a30") if mine else c("#7d4329")
	DIRT_DARK = c("#7e3b26") if mine else c("#6a3722")
	DIRT_LIGHT = c("#ad5a3c") if mine else c("#8a4c30")
static var SKIN := c("#d9a06f")
static var DENIM := c("#37506e")

## A wheel of radius 1 (scaled when placed), `width` m across, with spokes on both faces so it can be seen turning.
static func wheel(kit: MeshKit, width: float) -> void:
	kit.cone(Vector3(0, 0, -width * 0.5), Vector3(0, 0, width * 0.5), 1.0, 1.0, 10, BLACK)
	for k in 3:
		kit.box(Vector3.ZERO, Vector3(1.25, 0.2, width + 0.05), STEEL, Basis(Vector3.BACK, k * PI / 3.0))

## The dump truck, without its wheels and tray: forward is +x, ground at y = 0, about 8 m long. A chassis and a square cab up front.
static func truck_body(kit: MeshKit) -> void:
	kit.box(Vector3(-0.5, 0.95, 0), Vector3(6.6, 0.32, 1.1), CHARCOAL)
	for x: float in [-2.6, -1.5, 2.3]:
		kit.box(Vector3(x, 0.62, 0), Vector3(0.2, 0.2, 2.0), BLACK)
	# Cab.
	kit.box(Vector3(2.45, 1.95, 0), Vector3(1.6, 1.7, 2.4), RED)
	kit.box(Vector3(3.25, 1.3, 0), Vector3(0.1, 0.5, 2.1), BLACK)
	for i in 4:
		kit.box(Vector3(3.31, 1.12 + i * 0.12, 0), Vector3(0.04, 0.05, 2.0), STEEL)
	kit.box(Vector3(3.3, 2.3, 0), Vector3(0.1, 0.8, 2.2), GLASS)
	for z: float in [-1.21, 1.21]:
		kit.box(Vector3(2.6, 2.3, z), Vector3(1.0, 0.75, 0.04), GLASS)
		kit.box(Vector3(3.3, 1.0, z * 0.82), Vector3(0.14, 0.2, 0.36), LAMP)
		kit.box(Vector3(1.75, 2.25, z * 1.1), Vector3(0.06, 0.32, 0.18), BLACK)
	kit.box(Vector3(2.45, 2.85, 0), Vector3(1.7, 0.1, 2.5), RED)
	kit.box(Vector3(3.4, 0.82, 0), Vector3(0.18, 0.26, 2.5), CHARCOAL)
	# Mudguards over each set of wheels.
	for z: float in [-1.08, 1.08]:
		kit.box(Vector3(2.3, 1.3, z), Vector3(1.5, 0.08, 0.62), RED)
		kit.box(Vector3(-2.05, 1.26, z), Vector3(2.5, 0.08, 0.62), CHARCOAL)
	kit.cone(Vector3(1.6, 1.3, -1.1), Vector3(1.6, 3.1, -1.1), 0.07, 0.07, 6, STEEL)
	kit.box(Vector3(1.6, 0.95, 1.2), Vector3(0.8, 0.3, 0.4), CHARCOAL)

## The tray, from its hinge at the back along +x. Hollow, so soil in it shows.
static func truck_tray(kit: MeshKit, length: float, half: float, high: float) -> void:
	kit.box(Vector3(length * 0.5, 0.04, 0), Vector3(length, 0.08, half * 2.0), RED)
	for z: float in [-half, half]:
		kit.prism([Vector2(0.0, 0.04), Vector2(length, 0.04), Vector2(length, high), Vector2(0.25, high * 0.8)], z - 0.05, z + 0.05, RED)
		for x: float in [1.0, 2.2, 3.4]:
			kit.box(Vector3(x, high * 0.45, z * 1.04), Vector3(0.09, high * 0.8, 0.05), CHARCOAL)
	kit.box(Vector3(length, high * 0.55, 0), Vector3(0.1, high * 1.1, half * 2.0), RED)
	kit.box(Vector3(length + 0.35, high + 0.05, 0), Vector3(0.8, 0.07, half * 2.0), RED)
	kit.box(Vector3(0.0, high * 0.35, 0), Vector3(0.08, high * 0.6, half * 2.0), CHARCOAL)
	kit.box(Vector3(length * 0.5, -0.1, 0), Vector3(length, 0.14, 1.0), CHARCOAL)

## A loader's bucket, from its pin along +x to the cutting edge. Floor along x, open at the top, steel edge.
static func loader_bucket(kit: MeshKit, length: float, half: float, high: float) -> void:
	kit.box(Vector3(length * 0.5, 0.0, 0), Vector3(length, high * 0.1, half * 2.0), YELLOW_DARK)
	kit.prism([Vector2(-0.02, 0.0), Vector2(high * 0.1, 0.0), Vector2(high * 0.1, high), Vector2(-0.02, high)], -half, half, YELLOW_DARK, CHARCOAL)
	for z: float in [-half, half]:
		kit.prism([Vector2(0.0, 0.0), Vector2(length, 0.0), Vector2(0.0, high)], z - 0.025, z + 0.025, YELLOW)
	kit.box(Vector3(length, 0.0, 0), Vector3(high * 0.16, high * 0.1, half * 2.0), STEEL)

## The two arms a loader lifts with, along +x from the pivot to the pin.
static func loader_arms(kit: MeshKit, length: float, z: float, thick: float) -> void:
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(length * 0.5, 0, side * z), Vector3(length + thick, thick, thick * 0.6), YELLOW_DARK)
	kit.box(Vector3(length * 0.72, 0, 0), Vector3(thick * 0.8, thick * 0.8, z * 2.0), YELLOW_DARK)

## The Bobcat, without wheels, arms or bucket. About 2.8 m long and 1.8 m wide, a caged cab on a low body.
static func bobcat_body(kit: MeshKit) -> void:
	kit.box(Vector3(-0.1, 0.62, 0), Vector3(2.2, 0.5, 1.15), CHARCOAL)
	kit.box(Vector3(-0.72, 1.12, 0), Vector3(1.1, 0.72, 1.3), WHITE_PAINT)
	kit.box(Vector3(-1.22, 1.12, 0), Vector3(0.1, 0.55, 1.1), BLACK)
	for i in 3:
		kit.box(Vector3(-0.72, 1.5, -0.3 + i * 0.3), Vector3(0.9, 0.02, 0.14), CHARCOAL)
	# The cage: open at the front, bars down the sides.
	kit.box(Vector3(0.12, 2.17, 0), Vector3(1.28, 0.1, 1.25), WHITE_PAINT)
	for z: float in [-0.6, 0.6]:
		kit.box(Vector3(0.7, 1.45, z), Vector3(0.07, 1.4, 0.07), BLACK)
		kit.box(Vector3(-0.45, 1.65, z), Vector3(0.07, 1.0, 0.07), BLACK)
		for y: float in [1.3, 1.6, 1.9]:
			kit.box(Vector3(0.12, y, z), Vector3(1.15, 0.03, 0.03), BLACK)
	kit.box(Vector3(0.05, 0.98, 0), Vector3(0.5, 0.25, 0.55), SEAT)
	kit.box(Vector3(-0.2, 1.35, 0), Vector3(0.12, 0.55, 0.5), SEAT)
	for z: float in [-0.92, 0.92]:
		kit.box(Vector3(0.0, 0.95, z), Vector3(1.9, 0.08, 0.5), WHITE_PAINT)
	# The arms' uprights at the back.
	for z: float in [-0.72, 0.72]:
		kit.box(Vector3(-0.85, 1.3, z), Vector3(0.28, 0.9, 0.12), YELLOW_DARK)

## The Dingo, without its tracks, arms or bucket: a tiny low machine, with a platform at the back and its driver standing on it.
static func dingo_body(kit: MeshKit) -> void:
	kit.box(Vector3(0.0, 0.4, 0), Vector3(1.05, 0.26, 0.5), CHARCOAL)
	kit.box(Vector3(-0.08, 0.68, 0), Vector3(0.8, 0.34, 0.66), RED)
	kit.box(Vector3(-0.08, 0.86, 0), Vector3(0.6, 0.03, 0.5), CHARCOAL)
	kit.cone(Vector3(-0.35, 0.86, 0.2), Vector3(-0.35, 1.05, 0.2), 0.025, 0.025, 5, BLACK)
	# Uprights for the arms.
	for z: float in [-0.3, 0.3]:
		kit.box(Vector3(-0.28, 0.9, z), Vector3(0.14, 0.44, 0.06), YELLOW_DARK)
	# The control tower, and the plate the driver stands on.
	kit.box(Vector3(-0.55, 0.8, 0), Vector3(0.1, 0.72, 0.42), CHARCOAL)
	kit.box(Vector3(-0.5, 1.16, 0), Vector3(0.24, 0.05, 0.52), BLACK)
	for z: float in [-0.15, 0.0, 0.15]:
		kit.cone(Vector3(-0.5, 1.18, z), Vector3(-0.56, 1.28, z), 0.012, 0.012, 4, STEEL)
	kit.box(Vector3(-0.92, 0.2, 0), Vector3(0.62, 0.05, 0.58), STEEL)
	for z: float in [-0.25, 0.25]:
		kit.box(Vector3(-0.68, 0.3, z), Vector3(0.28, 0.14, 0.05), CHARCOAL)

## The Dingo's driver, standing on its back plate, hands on the controls. Apart from the body, so he can step off.
static func dingo_driver(kit: MeshKit) -> void:
	for z: float in [-0.1, 0.1]:
		kit.box(Vector3(-0.92, 0.26, z), Vector3(0.26, 0.08, 0.1), BLACK)
		kit.box(Vector3(-0.94, 0.6, z), Vector3(0.14, 0.66, 0.13), DENIM)
	kit.box(Vector3(-0.94, 1.17, 0), Vector3(0.22, 0.54, 0.38), HI_VIS)
	kit.box(Vector3(-0.94, 1.17, 0), Vector3(0.23, 0.04, 0.39), LAMP)
	for z: float in [-0.23, 0.23]:
		kit.box(Vector3(-0.76, 1.22, z), Vector3(0.34, 0.09, 0.09), HI_VIS)
	kit.box(Vector3(-0.94, 1.54, 0), Vector3(0.2, 0.2, 0.19), SKIN)
	kit.box(Vector3(-0.94, 1.67, 0), Vector3(0.28, 0.09, 0.26), YELLOW)

## The trencher: a chain boom pointing down and forward from the pivot, along +x. `wide` scales it across, for the Bobcat's
## bigger one.
static func trencher(kit: MeshKit, length: float, wide := 1.0) -> void:
	var deep := sqrt(wide)
	kit.box(Vector3(length * 0.5, 0, 0), Vector3(length, 0.16 * deep, 0.08 * wide), CHARCOAL)
	var teeth := int(round(length / 0.115))
	for i in teeth:
		var x := length * (i + 0.5) / teeth
		kit.box(Vector3(x, 0.1 * deep, 0), Vector3(0.06, 0.05, 0.14 * wide), STEEL)
		kit.box(Vector3(x, -0.1 * deep, 0), Vector3(0.06, 0.05, 0.14 * wide), STEEL)
	kit.box(Vector3(0.05, 0.0, 0), Vector3(0.3, 0.3, 0.26) * deep, RED)

## The pipe layer on the Dingo's front: a frame with a drum of pipe on it.
static func pipe_spool(kit: MeshKit) -> void:
	for z: float in [-0.28, 0.28]:
		kit.box(Vector3(0.55, 0.78, z), Vector3(0.65, 0.07, 0.05), CHARCOAL)
	kit.cone(Vector3(0.75, 0.98, -0.27), Vector3(0.75, 0.98, 0.27), 0.34, 0.34, 10, c("#e9e6dc"))
	for z: float in [-0.28, 0.28]:
		kit.cone(Vector3(0.75, 0.98, z - 0.015), Vector3(0.75, 0.98, z + 0.015), 0.4, 0.4, 10, c("#3f7fbf"))

## The solid part of a pair of tracks. The cleats and wheels that run on it are TrackRig's.
static func track_frames(kit: MeshKit, z_mid: float, half_w: float, flat: float, nose: float, top: float, mine := false) -> void:
	for side: float in [-1.0, 1.0]:
		kit.prism([Vector2(-nose, 0.42), Vector2(-flat, 0.0), Vector2(flat, 0.0), Vector2(nose, 0.42), Vector2(top, 0.88), Vector2(-top, 0.88)], side * (z_mid - half_w), side * (z_mid + half_w), CHARCOAL)
		var face_z := side * (z_mid + half_w + 0.02)
		var k := flat - 0.08
		kit.prism([Vector2(-k, 0.3), Vector2(-k + 0.27, 0.14), Vector2(k - 0.27, 0.14), Vector2(k, 0.3), Vector2(k - 0.17, 0.7), Vector2(-k + 0.17, 0.7)], face_z - side * 0.03, face_z, MINE_GREY if mine else YELLOW_DARK)

## The way round a track that its cleats run, starting along the bottom going back.
static func track_path(flat: float, nose: float, top: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(flat, 0.03), Vector2(-flat, 0.03), Vector2(-nose, 0.42), Vector2(-top, 0.91), Vector2(top, 0.91), Vector2(nose, 0.42)])

## x, y, radius of each wheel on a track.
static func dozer_wheels() -> Array[Vector3]:
	var w: Array[Vector3] = [Vector3(-1.95, 0.5, 0.3), Vector3(1.95, 0.5, 0.26)]
	for i in 5:
		w.append(Vector3(-1.2 + i * 0.6, 0.34, 0.17))
	return w

static func excavator_wheels() -> Array[Vector3]:
	var w: Array[Vector3] = [Vector3(-2.05, 0.5, 0.32), Vector3(2.05, 0.5, 0.3)]
	for i in 6:
		w.append(Vector3(-1.4 + i * 0.56, 0.32, 0.16))
	return w

## The excavator's frame between its tracks and the ring the house turns on.
static func excavator_carriage(kit: MeshKit) -> void:
	kit.box(Vector3(0, 0.68, 0), Vector3(3.0, 0.42, 2.0), CHARCOAL)
	kit.cone(Vector3(0, 0.85, 0), Vector3(0, 1.02, 0), 1.05, 1.05, 12, BLACK)

## How far up a mine excavator's cab sits on its riser, above where the small one's is.
const MINE_CAB_UP := 0.55

## The turning part, in its own coordinates: forward is +x, the ground at y = 0. The cab is on the left, the boom right of middle.
## The mine's one is fleet white, its cab up on a riser with a ladder to it, rails round the engine deck and stripes on the back.
static func excavator_house(kit: MeshKit, mine := false) -> void:
	var body := MINE_WHITE if mine else YELLOW
	var dark := MINE_GREY if mine else YELLOW_DARK
	kit.box(Vector3(-0.55, 1.2, 0), Vector3(4.1, 0.34, 2.7), dark)
	kit.box(Vector3(-1.5, 1.78, 0.0), Vector3(1.95, 0.84, 2.6), body)
	for i in 5:
		kit.box(Vector3(-2.1 + i * 0.3, 2.21, 0.45), Vector3(0.15, 0.02, 1.3), dark)
	kit.box(Vector3(-2.72, 1.5, 0), Vector3(0.55, 1.12, 2.7), body if mine else CHARCOAL)
	kit.box(Vector3(0.62, 1.6, 0.98), Vector3(1.5, 0.48, 0.72), body)
	kit.box(Vector3(0.62, 1.86, 0.98), Vector3(1.3, 0.03, 0.55), dark)
	kit.cone(Vector3(-1.7, 2.18, 0.8), Vector3(-1.7, 2.95, 0.8), 0.07, 0.07, 6, BLACK)
	kit.cone(Vector3(-1.7, 2.95, 0.8), Vector3(-1.75, 3.05, 0.8), 0.09, 0.09, 6, BLACK)
	# The foot of the boom.
	kit.box(Vector3(0.95, 1.6, 0.25), Vector3(0.9, 0.75, 0.62), dark)
	# The cab: dark glass in a frame.
	var up := MINE_CAB_UP if mine else 0.0
	kit.box(Vector3(0.45, 2.15 + up, -0.8), Vector3(1.55, 1.56, 0.98), GLASS)
	kit.box(Vector3(0.45, 2.97 + up, -0.8), Vector3(1.66, 0.1, 1.08), body)
	for x: float in [-0.32, 1.22]:
		for z: float in [-1.29, -0.31]:
			kit.box(Vector3(x, 2.15 + up, z), Vector3(0.07, 1.6, 0.07), body)
	kit.box(Vector3(1.28, 2.98 + up, -0.55), Vector3(0.1, 0.12, 0.16), LAMP)
	if not mine:
		return
	# Up on its riser, with a ladder from the deck's edge to the door.
	kit.box(Vector3(0.45, 1.37 + up * 0.5, -0.8), Vector3(1.5, up, 0.95), dark)
	kit.box(Vector3(-0.32, 3.0 + up, -0.8), Vector3(0.1, 0.12, 0.16), LAMP)
	for x: float in [-0.58, -0.24]:
		kit.box(Vector3(x, 1.62, -1.42), Vector3(0.045, 1.34, 0.045), SAFETY)
	for k in 6:
		kit.box(Vector3(-0.41, 1.03 + k * 0.17, -1.42), Vector3(0.34, 0.035, 0.05), STEEL)
	# Rails round the engine deck.
	for z: float in [-1.28, 1.28]:
		for x: float in [-2.4, -1.5, -0.6]:
			kit.box(Vector3(x, 2.47, z), Vector3(0.045, 0.54, 0.045), SAFETY)
		kit.box(Vector3(-1.5, 2.74, z), Vector3(1.85, 0.045, 0.045), SAFETY)
		kit.box(Vector3(-1.5, 2.5, z), Vector3(1.85, 0.035, 0.035), SAFETY)
	# Hi-vis chevrons across the back of the counterweight, and a band along each side.
	for k in 4:
		kit.box(Vector3(-3.005, 1.5, -0.98 + k * 0.65), Vector3(0.02, 0.95, 0.16), HI_VIS, Basis(Vector3.RIGHT, 0.6))
	for z: float in [-1.352, 1.352]:
		kit.box(Vector3(-1.95, 1.27, z), Vector3(2.9, 0.08, 0.012), HI_VIS)
	stencil(kit, "EX-01", Vector3(-1.5, 1.74, 1.3), Vector3.RIGHT, Vector3.BACK, 0.075, BLACK)
	stencil(kit, "EX-01", Vector3(-1.5, 1.74, -1.3), Vector3.LEFT, Vector3.FORWARD, 0.075, BLACK)

## From the shoulder along +x to the elbow, `length` m away, with the bend upward. Banana-shaped, so in two pieces.
static func excavator_boom(kit: MeshKit, length: float, mine := false) -> void:
	var body := MINE_WHITE if mine else YELLOW
	var dark := MINE_GREY if mine else YELLOW_DARK
	var m := length * 0.5
	kit.prism([Vector2(-0.22, -0.2), Vector2(m, 0.32), Vector2(m, 0.98), Vector2(-0.22, 0.24)], -0.23, 0.23, body, dark)
	kit.prism([Vector2(m, 0.32), Vector2(length + 0.14, -0.14), Vector2(length + 0.14, 0.2), Vector2(m, 0.98)], -0.23, 0.23, body, dark)

## From the elbow along +x to the bucket's pin, with a stub behind the elbow for the ram to push on.
static func excavator_stick(kit: MeshKit, length: float, mine := false) -> void:
	kit.prism([Vector2(-0.62, 0.0), Vector2(length + 0.08, -0.1), Vector2(length + 0.08, 0.1), Vector2(-0.62, 0.42)], -0.17, 0.17, MINE_WHITE if mine else YELLOW, MINE_GREY if mine else YELLOW_DARK)

## The bucket, from its pin along +x to the teeth; its open side is -y. Plates and curved floor, so it really is a hollow.
## The mine's is a rock bucket: worn grey, a heavy steel lip, five big teeth and a cutter at each corner.
static func excavator_bucket(kit: MeshKit, length: float, half_w: float, mine := false) -> void:
	var floor_line := [Vector2(-0.08, 0.1), Vector2(0.35, 0.5), Vector2(0.85, 0.52), Vector2(length - 0.12, 0.14), Vector2(length, -0.02)]
	for i in floor_line.size() - 1:
		var a: Vector2 = floor_line[i]
		var b: Vector2 = floor_line[i + 1]
		kit.prism([a, b, b + Vector2(0.0, 0.07), a + Vector2(0.0, 0.07)], -half_w, half_w, CHARCOAL if mine else YELLOW_DARK, CHARCOAL)
	for z: float in [-half_w, half_w]:
		kit.prism([Vector2(-0.08, 0.1), Vector2(0.35, 0.5), Vector2(0.85, 0.52), Vector2(length, -0.02), Vector2(0.15, -0.28)], z - 0.03, z + 0.03, MINE_GREY if mine else YELLOW)
	var count := 5 if mine else 6
	var reach := 0.36 if mine else 0.2
	var thick := 0.085 if mine else 0.055
	for k in count:
		var z := lerpf(-half_w + 0.08, half_w - 0.08, k / float(count - 1))
		kit.prism([Vector2(length - 0.06, -0.06), Vector2(length + reach, -0.04), Vector2(length - 0.06, 0.09)], z - thick, z + thick, STEEL)
	if mine:
		kit.box(Vector3(length - 0.04, 0.0, 0.0), Vector3(0.16, 0.1, half_w * 2.0), STEEL)
		for z: float in [-half_w, half_w]:
			kit.box(Vector3(length - 0.25, -0.02, z), Vector3(0.5, 0.14, 0.09), STEEL)
		for x: float in [0.45, 0.8]:
			kit.box(Vector3(x, 0.58, 0.0), Vector3(0.12, 0.04, half_w * 1.9), STEEL)
	# The lugs it hangs from.
	kit.box(Vector3(0.0, 0.12, 0.0), Vector3(0.36, 0.36, 0.34), CHARCOAL if mine else YELLOW_DARK)

## The bulldozer: forward is +x, the ground at y = 0, about 4.5 m long without the blade. Its tracks are built apart from it.
## The mine's one is fleet white, with a closed cab, rails and a ladder up to walkways over the tracks, and one big ripper.
static func bulldozer(kit: MeshKit, mine := false) -> void:
	var body := MINE_WHITE if mine else YELLOW
	var dark := MINE_GREY if mine else YELLOW_DARK
	# The body: a deck over the tracks, the sloped engine hood and its grille, the back of the machine.
	kit.box(Vector3(-0.2, 1.0, 0), Vector3(4.0, 0.45, 2.1), body)
	kit.prism([Vector2(0.05, 1.2), Vector2(2.2, 1.2), Vector2(2.2, 1.72), Vector2(1.9, 1.85), Vector2(0.05, 2.08)], -0.62, 0.62, body)
	kit.box(Vector3(2.23, 1.46, 0), Vector3(0.08, 0.42, 1.0), BLACK)
	for i in 4:
		kit.box(Vector3(2.28, 1.3 + i * 0.105, 0), Vector3(0.04, 0.045, 1.0), STEEL)
	for i in 5:
		kit.box(Vector3(0.5 + i * 0.28, 1.89 - i * 0.03, 0), Vector3(0.14, 0.02, 0.9), dark)
	kit.cone(Vector3(1.05, 1.95, 0.38), Vector3(1.05, 2.65, 0.38), 0.07, 0.07, 6, BLACK)
	kit.cone(Vector3(1.05, 2.65, 0.38), Vector3(1.0, 2.75, 0.38), 0.09, 0.09, 6, BLACK)
	kit.box(Vector3(-1.95, 1.45, 0), Vector3(0.5, 0.75, 1.85), body)
	kit.box(Vector3(-2.22, 1.45, 0), Vector3(0.05, 0.42, 1.0), BLACK)

	# A floor, seat and levers: under an open canopy on the small one, shut in a cab on the mine's.
	kit.box(Vector3(-0.8, 1.27, 0), Vector3(1.55, 0.08, 1.6), CHARCOAL)
	kit.box(Vector3(-0.95, 1.6, 0), Vector3(0.5, 0.58, 0.62), SEAT)
	kit.box(Vector3(-1.2, 2.05, 0), Vector3(0.14, 0.7, 0.58), SEAT)
	for z: float in [-0.42, 0.42]:
		kit.cone(Vector3(-0.3, 1.32, z), Vector3(-0.42, 1.95, z), 0.03, 0.03, 5, BLACK)
		kit.cone(Vector3(-0.42, 1.95, z), Vector3(-0.42, 2.02, z), 0.06, 0.06, 6, STEEL)
	if not mine:
		for side: float in [-1.0, 1.0]:
			# Canopy posts, and a work lamp up front.
			kit.box(Vector3(-0.1, 2.35, side * 0.78), Vector3(0.07, 1.4, 0.07), BLACK)
			kit.box(Vector3(-1.5, 2.35, side * 0.78), Vector3(0.07, 1.4, 0.07), BLACK)
			kit.box(Vector3(0.05, 3.0, side * 0.6), Vector3(0.1, 0.12, 0.16), LAMP)
		kit.prism([Vector2(-1.72, 3.05), Vector2(0.14, 3.05), Vector2(0.14, 3.16), Vector2(-1.72, 3.2)], -1.02, 1.02, body)
		kit.box(Vector3(-0.8, 3.02, 0), Vector3(1.62, 0.05, 1.62), BLACK)
		# The ripper on the back.
		kit.box(Vector3(-2.55, 0.92, 0), Vector3(0.2, 0.2, 1.6), dark)
		for z: float in [-0.6, 0.6]:
			kit.box(Vector3(-2.3, 0.95, z), Vector3(0.6, 0.14, 0.12), dark)
			kit.prism([Vector2(-2.7, 1.0), Vector2(-2.5, 1.0), Vector2(-2.58, 0.05), Vector2(-2.72, 0.05)], z - 0.06, z + 0.06, CHARCOAL)
		return

	# The cab: solid walls to the waist, then one block of glass, which drops out of sight from the seat.
	for x: float in [0.1, -1.7]:
		kit.box(Vector3(x, 1.54, 0), Vector3(0.06, 0.48, 1.66), body)
	for z: float in [-0.83, 0.83]:
		kit.box(Vector3(-0.8, 1.54, z), Vector3(1.86, 0.48, 0.06), body)
	kit.box(Vector3(-0.8, 2.37, 0), Vector3(1.78, 1.18, 1.6), GLASS)
	for x: float in [0.1, -0.75, -1.7]:
		for z: float in [-0.82, 0.82]:
			kit.box(Vector3(x, 2.37, z), Vector3(0.09, 1.2, 0.09), body)
	kit.box(Vector3(-0.8, 3.02, 0), Vector3(1.98, 0.12, 1.82), body)
	kit.box(Vector3(-1.25, 3.2, 0), Vector3(0.7, 0.24, 1.0), dark)
	for x: float in [0.13, -1.73]:
		for z: float in [-0.6, 0.6]:
			kit.box(Vector3(x, 2.97, z), Vector3(0.1, 0.12, 0.18), LAMP)
	# Walkways over the tracks, with rails, and a ladder up the outside of the left track frame.
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(-0.65, 0.93, side * 1.26), Vector3(2.5, 0.05, 0.42), dark)
		for x: float in [-1.85, -0.65, 0.55]:
			kit.box(Vector3(x, 1.24, side * 1.45), Vector3(0.04, 0.62, 0.04), SAFETY)
		kit.box(Vector3(-0.65, 1.55, side * 1.45), Vector3(2.44, 0.04, 0.04), SAFETY)
		kit.box(Vector3(-0.65, 1.26, side * 1.45), Vector3(2.44, 0.03, 0.03), SAFETY)
		kit.box(Vector3(-0.2, 1.12, side * 1.056), Vector3(3.95, 0.08, 0.012), HI_VIS)
	for x: float in [-1.75, -1.45]:
		kit.box(Vector3(x, 0.62, -1.56), Vector3(0.04, 0.84, 0.04), SAFETY)
	for k in 4:
		kit.box(Vector3(-1.6, 0.3 + k * 0.17, -1.56), Vector3(0.3, 0.03, 0.05), STEEL)
	# One big ripper tooth on a heavy frame.
	kit.box(Vector3(-2.6, 0.95, 0), Vector3(0.28, 0.3, 1.1), dark)
	for z: float in [-0.45, 0.45]:
		kit.box(Vector3(-2.35, 0.98, z), Vector3(0.55, 0.16, 0.14), dark)
	kit.cone(Vector3(-2.1, 1.75, 0.0), Vector3(-2.6, 1.08, 0.0), 0.07, 0.07, 6, STEEL)
	kit.prism([Vector2(-2.84, 1.3), Vector2(-2.5, 1.3), Vector2(-2.64, 0.2), Vector2(-2.78, 0.06), Vector2(-2.9, 0.22)], -0.09, 0.09, CHARCOAL)
	kit.prism([Vector2(-2.92, 0.02), Vector2(-2.74, 0.04), Vector2(-2.66, 0.24), Vector2(-2.9, 0.24)], -0.07, 0.07, STEEL)
	stencil(kit, "DZ-01", Vector3(1.12, 1.47, 0.62), Vector3.RIGHT, Vector3.BACK, 0.075, BLACK)
	stencil(kit, "DZ-01", Vector3(1.12, 1.47, -0.62), Vector3.LEFT, Vector3.FORWARD, 0.075, BLACK)

## The blade, its push arms and lift rams: separate from the body because it lifts. Same coordinates as the body. The mine's has
## wings on its ends, the way a big U-blade does.
static func dozer_blade(kit: MeshKit, mine := false) -> void:
	var body := MINE_WHITE if mine else YELLOW
	var dark := MINE_GREY if mine else YELLOW_DARK
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(1.85, 0.72, side * 1.58), Vector3(2.0, 0.18, 0.16), dark, Basis(Vector3.BACK, deg_to_rad(-6.0)))
		kit.cone(Vector3(0.9, 1.65, side * 0.72), Vector3(2.5, 1.0, side * 1.05), 0.075, 0.075, 6, STEEL)

	# Curved, in straight facets, with a dark steel cutting edge and end plates.
	var w := 2.15
	var profile := [Vector2(2.82, 0.14), Vector2(2.68, 0.55), Vector2(2.7, 1.1), Vector2(2.9, 1.62), Vector2(3.08, 1.72)]
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		kit.prism([a, b, b + Vector2(-0.18, 0.0), a + Vector2(-0.18, 0.0)], -w, w, body, dark)
	kit.prism([Vector2(2.72, 0.0), Vector2(2.98, 0.0), Vector2(2.82, 0.16), Vector2(2.66, 0.16)], -w, w, STEEL)
	for z: float in [-w, w]:
		kit.prism([Vector2(2.5, 0.08), Vector2(2.9, 0.08), Vector2(2.72, 1.5), Vector2(2.5, 1.5)], z - 0.05, z + 0.05, dark)
	kit.box(Vector3(2.48, 0.8, 0), Vector3(0.1, 1.0, 3.5), dark)
	if mine:
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(2.98, 0.86, side * (w - 0.1)), Vector3(0.62, 1.55, 0.09), body, Basis(Vector3.UP, side * 0.46))
			kit.box(Vector3(3.0, 0.05, side * (w - 0.1)), Vector3(0.64, 0.1, 0.11), STEEL, Basis(Vector3.UP, side * 0.46))

## Block letters a fleet number is painted in, three wide and five high, read across then down.
const GLYPHS := {
	"D": "110101101101110", "Z": "111001010100111", "E": "111100110100111", "X": "101101010101101",
	"H": "101101111101101", "T": "111010010010010", "-": "000000111000000", "0": "111101101101111",
	"1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "L": "100100100100111",
	"V": "101101101101010",
}

## A fleet number painted on a machine's side: `along` is the way it reads, `out` the way the side faces, `px` one block's size.
static func stencil(kit: MeshKit, text: String, middle: Vector3, along: Vector3, out: Vector3, px: float, col: Color) -> void:
	var wide := text.length() * 4 - 1
	var start := middle - along * (wide * px * 0.5)
	var size := along.abs() * px + Vector3(0.0, px, 0.0) + out.abs() * 0.012
	for k in text.length():
		var g: String = GLYPHS.get(text[k], "")
		for n in g.length():
			if g[n] != "1":
				continue
			var at := start + along * ((k * 4 + n % 3 + 0.5) * px) + Vector3.UP * ((2 - n / 3) * px) + out * 0.006
			kit.box(at, size, col)

## A pine: a trunk and stacked faceted cones, a bit uneven, in two or three greens.
static func pine(kit: MeshKit, at: Vector3, high: float, rng: RandomNumberGenerator, tiers := 3, sides := 7) -> void:
	var r := high * 0.22
	var trunk_h := high * 0.22
	kit.cone(at, at + Vector3(0, trunk_h + 0.3, 0), high * 0.045, high * 0.03, 6, TRUNK, 0.0, null, false)
	var greens := [PINE_C, PINE_A, PINE_B]
	var y := trunk_h
	var step := (high - trunk_h) / (tiers + 0.5)
	for i in tiers:
		var k := 1.0 - float(i) / tiers
		var bottom := at + Vector3(0, y, 0)
		var tip := at + Vector3(rng.randf_range(-0.05, 0.05), y + step * 1.75, rng.randf_range(-0.05, 0.05))
		kit.cone(bottom, tip, r * (0.45 + 0.55 * k), 0.0, sides, greens[i % 3], 0.1, rng)
		y += step

## The driver on foot, in three kinds of part so he can swing his arms and legs as he walks. Facing +x, feet at 0, in the same
## gear as the Dingo's driver: hard hat, hi-vis, jeans, boots.
static func worker_body(kit: MeshKit) -> void:
	kit.box(Vector3(0.0, 0.95, 0), Vector3(0.22, 0.54, 0.38), HI_VIS)
	kit.box(Vector3(0.0, 0.95, 0), Vector3(0.23, 0.04, 0.39), LAMP)
	kit.box(Vector3(0.0, 1.32, 0), Vector3(0.2, 0.2, 0.19), SKIN)
	kit.box(Vector3(0.0, 1.45, 0), Vector3(0.28, 0.09, 0.26), YELLOW)
	kit.box(Vector3(0.06, 1.42, 0), Vector3(0.22, 0.03, 0.27), YELLOW_DARK)

## One leg, hanging from the hip at 0: jeans down to a boot.
static func worker_leg(kit: MeshKit) -> void:
	kit.box(Vector3(0.0, -0.33, 0), Vector3(0.14, 0.66, 0.13), DENIM)
	kit.box(Vector3(0.04, -0.68, 0), Vector3(0.26, 0.08, 0.12), BLACK)

## One arm, hanging from the shoulder at 0: a hi-vis sleeve and a hand.
static func worker_arm(kit: MeshKit) -> void:
	kit.box(Vector3(0.0, -0.2, 0), Vector3(0.09, 0.4, 0.09), HI_VIS)
	kit.box(Vector3(0.0, -0.44, 0), Vector3(0.08, 0.08, 0.08), SKIN)

## A wheelbarrow facing +x, its wheel's axle at `pivot`, built round that axle so the whole thing tips up over the wheel.
static func barrow(kit: MeshKit, pivot: Vector3) -> void:
	var o := -pivot
	var tub := c("#c9402c")
	var tub_dark := c("#a5321f")
	var side := [Vector2(-0.2, 0.36), Vector2(0.5, 0.36), Vector2(0.66, 0.68), Vector2(-0.32, 0.68)]
	var moved: Array[Vector2] = []
	for p: Vector2 in side:
		moved.append(p + Vector2(o.x, o.y))
	for z: float in [-0.34, 0.3]:
		kit.prism(moved, z, z + 0.04, tub, tub_dark)
	kit.box(Vector3(0.15, 0.375, 0.0) + o, Vector3(0.72, 0.03, 0.64), tub_dark)
	for wall: Array in [[Vector2(-0.2, 0.36), Vector2(-0.16, 0.36), Vector2(-0.28, 0.68), Vector2(-0.32, 0.68)], [Vector2(0.46, 0.36), Vector2(0.5, 0.36), Vector2(0.66, 0.68), Vector2(0.62, 0.68)]]:
		var w: Array[Vector2] = []
		for p: Vector2 in wall:
			w.append(p + Vector2(o.x, o.y))
		kit.prism(w, -0.32, 0.32, tub, tub_dark)
	for z: float in [-0.25, 0.25]:
		# Handles from the wheel back past the tub, with grips; legs under the back of the tub; the fork down to the axle.
		kit.cone(Vector3(0.78, 0.2, z * 0.4) + o, Vector3(-1.05, 0.55, z) + o, 0.022, 0.022, 5, STEEL)
		kit.cone(Vector3(-0.85, 0.51, z) + o, Vector3(-1.08, 0.555, z) + o, 0.035, 0.035, 6, BLACK)
		kit.cone(Vector3(-0.22, 0.36, z) + o, Vector3(-0.28, 0.0, z * 1.1) + o, 0.02, 0.02, 5, STEEL)
		kit.box(Vector3(-0.28, 0.015, z * 1.1) + o, Vector3(0.08, 0.03, 0.05), BLACK)

## A long-handled shovel held in the right hand, the hand at 0, the blade down and ahead.
static func shovel(kit: MeshKit) -> void:
	kit.cone(Vector3(-0.35, 0.3, 0.0), Vector3(0.45, -0.5, 0.0), 0.02, 0.02, 5, c("#b88a55"))
	kit.box(Vector3(0.53, -0.6, 0.0), Vector3(0.05, 0.24, 0.22), STEEL, Basis(Vector3.BACK, deg_to_rad(40.0)))

## A garden rake, its head out ahead on the ground.
static func rake(kit: MeshKit) -> void:
	kit.cone(Vector3(-0.3, 0.25, 0.0), Vector3(0.95, -0.75, 0.0), 0.018, 0.018, 5, c("#b88a55"))
	kit.box(Vector3(0.97, -0.77, 0.0), Vector3(0.05, 0.05, 0.62), STEEL)
	for k in 9:
		kit.box(Vector3(1.0, -0.82, -0.28 + k * 0.07), Vector3(0.02, 0.08, 0.015), STEEL)

## A survey peg: a pale stake with a pink ribbon tied near the top.
static func survey_peg(kit: MeshKit, at: Vector3) -> void:
	kit.box(at + Vector3(0.0, 0.45, 0.0), Vector3(0.06, 0.9, 0.06), c("#efe8d8"))
	kit.box(at + Vector3(0.0, 0.82, 0.0), Vector3(0.075, 0.08, 0.075), c("#ff4fa3"))
	kit.box(at + Vector3(0.06, 0.74, 0.0), Vector3(0.12, 0.16, 0.012), c("#ff4fa3"))

## A stake as tall as a jump's to be built here, its top marked pink like a survey peg's.
static func height_stake(kit: MeshKit, at: Vector3, high: float) -> void:
	kit.box(at + Vector3(0.0, high * 0.5, 0.0), Vector3(0.07, high, 0.07), c("#efe8d8"))
	kit.box(at + Vector3(0.0, high - 0.06, 0.0), Vector3(0.085, 0.12, 0.085), c("#ff4fa3"))

## The scout ute, without its wheels: a white single cab with a steel tray, a bull bar, a hi-vis stripe and a bundle of pegs in the
## back. Forward is +x, ground at y = 0, about 5 m long.
## The dirt bike without its wheels, swingarm or fork legs: forward is +x, ground at y = 0 sitting on its springs, the axles at
## x -0.74 and 0.71. Site yellow plastics on a black frame.
static func bike_body(kit: MeshKit) -> void:
	# Engine and frame.
	kit.box(Vector3(0.02, 0.47, 0), Vector3(0.42, 0.32, 0.24), CHARCOAL)
	kit.box(Vector3(0.12, 0.68, 0), Vector3(0.2, 0.2, 0.2), STEEL, Basis(Vector3.BACK, deg_to_rad(-15.0)))
	kit.box(Vector3(-0.02, 0.3, 0), Vector3(0.3, 0.06, 0.16), BLACK)
	for z: float in [-0.08, 0.08]:
		kit.cone(Vector3(0.48, 1.03, z), Vector3(0.2, 0.42, z), 0.025, 0.025, 4, BLACK)
		kit.cone(Vector3(0.46, 1.0, z), Vector3(-0.08, 0.84, z), 0.025, 0.025, 4, BLACK)
		kit.cone(Vector3(-0.08, 0.84, z), Vector3(-0.05, 0.4, z), 0.025, 0.025, 4, BLACK)
		kit.cone(Vector3(-0.08, 0.84, z), Vector3(-0.62, 0.92, z), 0.02, 0.02, 4, BLACK)
	# Tank and radiator shrouds.
	kit.prism([Vector2(0.48, 1.05), Vector2(0.05, 1.0), Vector2(0.02, 0.86), Vector2(0.3, 0.74), Vector2(0.5, 0.88)], -0.15, 0.15, YELLOW)
	kit.prism([Vector2(0.44, 1.0), Vector2(0.2, 0.95), Vector2(0.16, 0.7), Vector2(0.36, 0.66), Vector2(0.48, 0.82)], -0.21, 0.21, YELLOW_DARK)
	kit.box(Vector3(0.3, 0.72, 0), Vector3(0.12, 0.26, 0.36), CHARCOAL)
	# Seat, side panels and the back mudguard sweeping up.
	kit.box(Vector3(-0.2, 0.99, 0), Vector3(0.74, 0.08, 0.24), BLACK, Basis(Vector3.BACK, deg_to_rad(-3.0)))
	kit.prism([Vector2(-0.05, 0.94), Vector2(-0.55, 0.96), Vector2(-0.5, 0.78), Vector2(-0.1, 0.74)], -0.15, 0.15, YELLOW)
	kit.prism([Vector2(-0.45, 0.97), Vector2(-1.02, 1.07), Vector2(-1.02, 1.03), Vector2(-0.45, 0.9)], -0.11, 0.11, YELLOW)
	# The front mudguard, high up clear of the wheel, the plate on the front and its lamp.
	kit.prism([Vector2(0.4, 0.98), Vector2(0.98, 0.93), Vector2(1.02, 0.89), Vector2(0.42, 0.93)], -0.08, 0.08, YELLOW)
	kit.box(Vector3(0.6, 1.08, 0), Vector3(0.04, 0.26, 0.3), WHITE_PAINT, Basis(Vector3.BACK, deg_to_rad(18.0)))
	kit.box(Vector3(0.62, 1.04, 0), Vector3(0.04, 0.06, 0.1), LAMP, Basis(Vector3.BACK, deg_to_rad(18.0)))
	# The top of the forks, the clamps and the bars.
	for z: float in [-0.09, 0.09]:
		kit.cone(Vector3(0.48, 1.1, z), Vector3(0.62, 0.66, z), 0.035, 0.035, 6, STEEL)
	kit.box(Vector3(0.48, 1.1, 0), Vector3(0.1, 0.05, 0.28), CHARCOAL)
	kit.cone(Vector3(0.44, 1.18, -0.38), Vector3(0.44, 1.18, 0.38), 0.016, 0.016, 5, BLACK)
	kit.cone(Vector3(0.47, 1.12, 0), Vector3(0.44, 1.18, 0), 0.02, 0.02, 4, BLACK)
	for z: float in [-0.33, 0.33]:
		kit.cone(Vector3(0.44, 1.18, z * 0.85), Vector3(0.44, 1.18, z * 1.15), 0.024, 0.024, 6, CHARCOAL)
	# Foot pegs and the pipe out to the right, back to the silencer under the mudguard.
	for z: float in [-0.21, 0.21]:
		kit.box(Vector3(0.02, 0.44, z), Vector3(0.08, 0.03, 0.1), STEEL)
	kit.cone(Vector3(0.22, 0.62, 0.12), Vector3(0.05, 0.5, 0.17), 0.03, 0.03, 5, STEEL)
	kit.cone(Vector3(0.05, 0.5, 0.17), Vector3(-0.35, 0.82, 0.17), 0.03, 0.03, 5, STEEL)
	kit.cone(Vector3(-0.3, 0.84, 0.17), Vector3(-0.78, 0.94, 0.17), 0.055, 0.045, 7, STEEL)
	# Number boards on the side panels.
	for z: float in [-0.155, 0.155]:
		kit.box(Vector3(-0.32, 0.86, z), Vector3(0.3, 0.13, 0.01), WHITE_PAINT)

## The swingarm from its pivot back along -x, 1 m long: stretched to reach the back axle as the spring moves.
static func bike_swingarm(kit: MeshKit) -> void:
	for z: float in [-0.08, 0.08]:
		kit.box(Vector3(-0.5, 0.0, z), Vector3(1.0, 0.07, 0.035), CHARCOAL)
	kit.box(Vector3(-0.15, 0.0, 0), Vector3(0.06, 0.06, 0.16), CHARCOAL)

## The bottoms of the forks, from the front axle at 0 up along the forks' rake.
static func bike_fork_legs(kit: MeshKit) -> void:
	for z: float in [-0.09, 0.09]:
		kit.cone(Vector3(0.0, 0.0, z), Vector3(-0.13, 0.38, z), 0.045, 0.045, 6, CHARCOAL)

## The rider, up on the pegs ready for the bumps: boots on the pegs, hands on the bars, in the site's hi-vis and a white helmet.
## Apart from the bike, so he can come off it.
static func bike_rider(kit: MeshKit) -> void:
	for z: float in [-1.0, 1.0]:
		rider_shin(kit, z)
		rider_thigh(kit, z)
		rider_upper_arm(kit, z)
		rider_forearm(kit, z)
	rider_body(kit)

## Where the rider's joints are, sitting on the bike: forward is +x. `z` is -1 for one side, 1 for the other.
static func rider_joint(part: String, z := 0.0) -> Vector3:
	match part:
		"head": return Vector3(0.18, 1.67, 0.0)
		"shoulder": return Vector3(0.12, 1.47, 0.19 * z)
		"elbow": return Vector3(0.24, 1.3, 0.33 * z)
		"hand": return Vector3(0.44, 1.2, 0.34 * z)
		"hip": return Vector3(-0.12, 1.06, 0.11 * z)
		"knee": return Vector3(0.22, 0.84, 0.19 * z)
		_: return Vector3(0.04, 0.48, 0.21 * z)     # the boot

static func rider_shin(kit: MeshKit, z: float) -> void:
	var boot := rider_joint("boot", z)
	kit.box(boot, Vector3(0.28, 0.1, 0.12), BLACK)
	kit.cone(boot + Vector3(0.0, 0.04, 0.0), rider_joint("knee", z), 0.07, 0.065, 5, DENIM)

static func rider_thigh(kit: MeshKit, z: float) -> void:
	kit.cone(rider_joint("knee", z), rider_joint("hip", z), 0.075, 0.08, 5, DENIM)

static func rider_upper_arm(kit: MeshKit, z: float) -> void:
	kit.cone(rider_joint("shoulder", z), rider_joint("elbow", z), 0.055, 0.05, 5, HI_VIS)

static func rider_forearm(kit: MeshKit, z: float) -> void:
	var hand := rider_joint("hand", z)
	kit.cone(rider_joint("elbow", z), hand, 0.05, 0.045, 5, HI_VIS)
	kit.box(hand, Vector3(0.08, 0.08, 0.08), BLACK)

## His body and helmet.
static func rider_body(kit: MeshKit) -> void:
	rider_pelvis(kit)
	rider_chest(kit)
	rider_head(kit)

## His body's in two halves, so he can fold at the waist coming off: leaning forward over the tank, sitting on it.
static func rider_chest(kit: MeshKit) -> void:
	var lean := Basis(Vector3.BACK, deg_to_rad(-28.0))
	kit.box(Vector3(0.0, 1.27, 0) + lean * Vector3(0.0, 0.13, 0.0), Vector3(0.24, 0.26, 0.38), HI_VIS, lean)
	kit.box(Vector3(0.0, 1.27, 0) + lean * Vector3(0.0, 0.04, 0.0), Vector3(0.25, 0.04, 0.39), LAMP, lean)

static func rider_pelvis(kit: MeshKit) -> void:
	var lean := Basis(Vector3.BACK, deg_to_rad(-28.0))
	kit.box(Vector3(0.0, 1.27, 0) + lean * Vector3(0.0, -0.13, 0.0), Vector3(0.23, 0.26, 0.37), HI_VIS, lean)
	# A roll across his waist, that fills the gap as he folds.
	kit.cone(Vector3(0.0, 1.27, -0.18), Vector3(0.0, 1.27, 0.18), 0.118, 0.118, 8, HI_VIS)

static func rider_head(kit: MeshKit) -> void:
	# His neck.
	kit.box(Vector3(0.15, 1.54, 0), Vector3(0.13, 0.16, 0.15), CHARCOAL, Basis(Vector3.BACK, deg_to_rad(-17.0)))
	# Helmet with its peak and goggles.
	kit.box(Vector3(0.18, 1.67, 0), Vector3(0.3, 0.28, 0.27), WHITE_PAINT)
	kit.box(Vector3(0.3, 1.78, 0), Vector3(0.16, 0.03, 0.25), YELLOW, Basis(Vector3.BACK, deg_to_rad(-12.0)))
	kit.box(Vector3(0.33, 1.68, 0), Vector3(0.03, 0.09, 0.22), GLASS)
	kit.box(Vector3(0.34, 1.57, 0), Vector3(0.1, 0.1, 0.14), CHARCOAL)

static func ute_body(kit: MeshKit) -> void:
	var white := c("#e2ded4")
	kit.box(Vector3(0.0, 0.58, 0), Vector3(4.9, 0.24, 1.4), CHARCOAL)
	kit.box(Vector3(0.95, 0.95, 0), Vector3(2.9, 0.62, 1.8), white)
	kit.box(Vector3(1.9, 1.3, 0), Vector3(1.1, 0.12, 1.74), white)
	kit.box(Vector3(0.15, 1.6, 0), Vector3(1.45, 0.72, 1.72), white)
	kit.box(Vector3(0.15, 1.97, 0), Vector3(1.5, 0.06, 1.76), white)
	kit.box(Vector3(0.93, 1.6, 0), Vector3(0.07, 0.62, 1.6), GLASS, Basis(Vector3.BACK, deg_to_rad(-28.0)))
	kit.box(Vector3(-0.58, 1.62, 0), Vector3(0.05, 0.5, 1.5), GLASS)
	for z: float in [-0.87, 0.87]:
		kit.box(Vector3(0.2, 1.62, z), Vector3(1.1, 0.48, 0.03), GLASS)
		kit.box(Vector3(0.4, 0.98, z * 1.04), Vector3(3.9, 0.1, 0.03), HI_VIS)
		# Wheel arches.
		for x: float in [1.55, -1.55]:
			kit.box(Vector3(x, 0.98, z * 1.03), Vector3(1.0, 0.12, 0.12), BLACK)
		kit.box(Vector3(2.42, 1.0, z * 0.78), Vector3(0.06, 0.14, 0.3), LAMP)
		kit.box(Vector3(-2.47, 1.0, z * 0.8), Vector3(0.06, 0.16, 0.22), RED)
		# The tray's sides.
		kit.box(Vector3(-1.58, 1.18, z * 1.0), Vector3(1.85, 0.32, 0.05), STEEL)
	kit.box(Vector3(-1.58, 1.0, 0), Vector3(1.85, 0.06, 1.78), STEEL)
	kit.box(Vector3(-2.48, 1.18, 0), Vector3(0.05, 0.32, 1.78), STEEL)
	kit.box(Vector3(-0.66, 1.3, 0), Vector3(0.06, 0.56, 1.78), STEEL)
	kit.box(Vector3(-1.0, 1.24, 0), Vector3(0.5, 0.42, 1.7), CHARCOAL)
	# A bundle of survey pegs in the back.
	for k in 5:
		kit.box(Vector3(-1.9, 1.1 + (k % 2) * 0.06, -0.3 + k * 0.12), Vector3(1.0, 0.05, 0.05), c("#efe8d8"))
	kit.box(Vector3(-1.5, 1.17, 0.0), Vector3(0.06, 0.07, 0.62), c("#ff4fa3"))
	# Bull bar.
	kit.box(Vector3(2.5, 0.88, 0), Vector3(0.1, 0.12, 1.7), BLACK)
	for z: float in [-0.55, 0.55]:
		kit.box(Vector3(2.5, 1.05, z), Vector3(0.1, 0.5, 0.08), BLACK)
	kit.box(Vector3(2.5, 1.28, 0), Vector3(0.1, 0.08, 1.2), BLACK)

## The mine's haul truck, without its wheels or tray: forward is +x, ground at y = 0, about 11 m long and 7 wide. Fleet white, the
## cab up on a deck over the front wheels on the left, a big grille, and a stair up across the front to get there.
static func haul_body(kit: MeshKit) -> void:
	# Chassis, axle housings, the tanks between the wheels, tail lights.
	kit.box(Vector3(-0.2, 1.75, 0), Vector3(9.4, 0.9, 1.7), CHARCOAL)
	kit.box(Vector3(-3.2, 1.5, 0), Vector3(1.4, 1.1, 2.6), BLACK)
	kit.box(Vector3(3.0, 1.5, 0), Vector3(0.8, 0.6, 3.6), BLACK)
	kit.box(Vector3(-0.1, 2.1, -1.6), Vector3(2.6, 1.2, 1.1), MINE_WHITE)
	kit.box(Vector3(-0.1, 2.1, 1.6), Vector3(2.6, 1.2, 1.1), MINE_GREY)
	for z: float in [-0.6, 0.6]:
		kit.box(Vector3(-4.92, 1.85, z), Vector3(0.06, 0.2, 0.3), RED)
	# The engine and its grille, and a heavy bumper.
	kit.box(Vector3(3.7, 2.65, 0), Vector3(3.0, 2.3, 2.4), MINE_WHITE)
	kit.box(Vector3(5.22, 2.6, 0), Vector3(0.08, 1.8, 2.1), BLACK)
	for i in 6:
		kit.box(Vector3(5.27, 1.85 + i * 0.3, 0), Vector3(0.04, 0.1, 2.0), STEEL)
	kit.box(Vector3(5.35, 1.2, 0), Vector3(0.5, 0.6, 3.2), CHARCOAL)
	for z: float in [-1.3, 1.3]:
		kit.box(Vector3(5.62, 1.3, z), Vector3(0.06, 0.2, 0.36), LAMP)
	# The deck over the front wheels.
	kit.box(Vector3(3.8, 3.9, 0), Vector3(3.6, 0.16, 6.8), MINE_GREY)
	for z: float in [-3.41, 3.41]:
		kit.box(Vector3(3.8, 3.86, z), Vector3(3.6, 0.1, 0.02), HI_VIS)
	for z: float in [-2.7, 2.7]:
		kit.box(Vector3(5.62, 4.02, z), Vector3(0.06, 0.16, 0.4), LAMP)
	# The cab on the left: solid to the dash, then glass, and the air conditioner on the roof.
	kit.box(Vector3(3.65, 4.26, -2.05), Vector3(2.5, 0.56, 1.9), MINE_WHITE)
	kit.box(Vector3(3.65, 5.2, -2.05), Vector3(2.44, 1.3, 1.84), GLASS)
	for x: float in [2.42, 4.88]:
		for z: float in [-2.98, -1.12]:
			kit.box(Vector3(x, 5.2, z), Vector3(0.1, 1.32, 0.1), MINE_WHITE)
	kit.box(Vector3(3.65, 5.92, -2.05), Vector3(2.7, 0.14, 2.05), MINE_WHITE)
	kit.box(Vector3(3.2, 6.1, -2.05), Vector3(0.9, 0.24, 1.1), MINE_GREY)
	# The air cleaners and a cabinet on the right of the deck.
	kit.box(Vector3(3.6, 4.45, 2.1), Vector3(2.2, 1.1, 1.7), MINE_WHITE)
	for x: float in [3.0, 4.2]:
		kit.cone(Vector3(x, 5.0, 2.1), Vector3(x, 5.5, 2.1), 0.32, 0.32, 8, MINE_GREY)
	# Rails round the deck's front and sides.
	for z: float in [-3.35, -1.7, 0.0, 1.7, 3.35]:
		kit.box(Vector3(5.55, 4.45, z), Vector3(0.06, 0.95, 0.06), SAFETY)
	kit.box(Vector3(5.55, 4.92, 0.0), Vector3(0.06, 0.06, 6.76), SAFETY)
	kit.box(Vector3(5.55, 4.45, 0.0), Vector3(0.05, 0.05, 6.76), SAFETY)
	for z: float in [-3.35, 3.35]:
		for x: float in [2.05, 3.8]:
			kit.box(Vector3(x, 4.45, z), Vector3(0.06, 0.95, 0.06), SAFETY)
		kit.box(Vector3(3.8, 4.92, z), Vector3(3.5, 0.06, 0.06), SAFETY)
	# The stair up across the front, from beside the bumper to the deck, and the rungs below it.
	var low := Vector3(6.0, 1.0, 2.95)
	var high := Vector3(6.0, 3.9, 0.35)
	var mid := (low + high) * 0.5
	var run := (high - low).length()
	var lean := Basis(Vector3.RIGHT, atan2(high.z - low.z, high.y - low.y))
	for x: float in [5.66, 6.34]:
		kit.box(Vector3(x, mid.y, mid.z), Vector3(0.06, run, 0.14), SAFETY, lean)
	kit.box(Vector3(6.36, mid.y + 0.95, mid.z), Vector3(0.05, run, 0.05), SAFETY, lean)
	for k in 9:
		var at := low.lerp(high, (k + 0.5) / 9.0)
		kit.box(at, Vector3(0.68, 0.05, 0.28), STEEL)
	for x: float in [5.75, 6.25]:
		kit.box(Vector3(x, 0.65, 2.95), Vector3(0.05, 0.75, 0.05), SAFETY)
	for k in 3:
		kit.box(Vector3(6.0, 0.4 + k * 0.22, 2.95), Vector3(0.5, 0.04, 0.06), STEEL)

## The haul truck's body, from its hinge at the back along +x: a deep steel box with a canopy reaching forward over the cab, so it
## all tips as one. Its fleet number is painted big on each side.
static func haul_tray(kit: MeshKit, length: float, half: float, high: float) -> void:
	kit.box(Vector3(length * 0.5, 0.06, 0), Vector3(length, 0.12, half * 2.0), MINE_GREY)
	for z: float in [-half, half]:
		kit.prism([Vector2(0.0, 0.06), Vector2(length, 0.06), Vector2(length, high), Vector2(0.8, high), Vector2(0.0, high * 0.6)], z - 0.08, z + 0.08, MINE_WHITE)
		for x: float in [1.4, 2.8, 4.2, 5.6]:
			kit.box(Vector3(x, high * 0.5, z * 1.03), Vector3(0.14, high * 0.9, 0.1), MINE_GREY)
		kit.box(Vector3(length * 0.5 + 0.4, high, z * 1.02), Vector3(length - 0.8, 0.16, 0.24), MINE_WHITE)
		kit.box(Vector3(length * 0.5 + 0.3, high - 0.3, z * 1.04), Vector3(length - 1.4, 0.14, 0.02), HI_VIS)
	stencil(kit, "HT-01", Vector3(length * 0.5, high * 0.42, half + 0.09), Vector3.RIGHT, Vector3.BACK, 0.17, BLACK)
	stencil(kit, "HT-01", Vector3(length * 0.5, high * 0.42, -half - 0.09), Vector3.LEFT, Vector3.FORWARD, 0.17, BLACK)
	# A low lip at the back, the front wall up to the canopy, and the canopy out over the cab.
	kit.box(Vector3(0.1, 0.25, 0), Vector3(0.24, 0.4, half * 2.0), MINE_GREY)
	kit.box(Vector3(length, 1.6, 0), Vector3(0.16, 3.1, half * 2.0), MINE_WHITE)
	kit.box(Vector3(length + 1.85, 3.15, 0), Vector3(3.9, 0.16, half * 2.0 + 0.2), MINE_WHITE)
	for z: float in [-half * 0.6, 0.0, half * 0.6]:
		kit.box(Vector3(length + 1.85, 3.0, z), Vector3(3.9, 0.16, 0.12), MINE_GREY)
	for z: float in [-0.9, 0.9]:
		kit.box(Vector3(length * 0.5, -0.12, z), Vector3(length, 0.24, 0.3), CHARCOAL)

## A lighting tower on its trailer, the lamps facing `face` radians round from +x.
static func light_tower(kit: MeshKit, at: Vector3, face: float) -> void:
	var b := Basis(Vector3.UP, face)
	kit.box(at + b * Vector3(0.0, 0.95, 0.0), Vector3(2.2, 1.1, 1.4), MINE_WHITE, b)
	kit.box(at + b * Vector3(0.0, 1.53, 0.0), Vector3(2.26, 0.06, 1.46), SAFETY, b)
	kit.box(at + b * Vector3(1.65, 0.5, 0.0), Vector3(1.2, 0.09, 0.09), CHARCOAL, b)
	for z: float in [-0.8, 0.8]:
		kit.cone(at + b * Vector3(-0.2, 0.36, z - 0.13), at + b * Vector3(-0.2, 0.36, z + 0.13), 0.36, 0.36, 10, BLACK)
	for z: float in [-1.15, 1.15]:
		kit.box(at + b * Vector3(0.0, 0.55, z), Vector3(0.12, 0.1, 0.5), SAFETY, b)
		kit.box(at + b * Vector3(0.0, 0.28, z * 1.15), Vector3(0.1, 0.56, 0.1), SAFETY, b)
	kit.box(at + b * Vector3(-0.6, 4.9, 0.0), Vector3(0.16, 7.6, 0.16), STEEL, b)
	kit.box(at + b * Vector3(-0.55, 8.6, 0.0), Vector3(0.12, 0.12, 1.9), CHARCOAL, b)
	for z: float in [-0.66, -0.22, 0.22, 0.66]:
		kit.box(at + b * Vector3(-0.42, 8.6 + (0.22 if absf(z) < 0.3 else -0.02), z), Vector3(0.18, 0.36, 0.34), LAMP, b)

## A site hut: a transportable building up on blocks, long along x, its door, windows and steps on the +z side.
static func donga(kit: MeshKit, at: Vector3) -> void:
	kit.box(at + Vector3(0.0, 1.85, 0.0), Vector3(12.0, 2.7, 3.3), c("#ece6d4"))
	kit.box(at + Vector3(0.0, 3.27, 0.0), Vector3(12.3, 0.14, 3.6), c("#c9cdd0"))
	for x: float in [-5.5, -2.0, 1.5, 5.0]:
		for z: float in [-1.3, 1.3]:
			kit.box(at + Vector3(x, 0.25, z), Vector3(0.5, 0.5, 0.5), CHARCOAL)
	for x: float in [-4.2, -1.6, 3.6]:
		kit.box(at + Vector3(x, 2.1, 1.66), Vector3(1.4, 0.9, 0.06), GLASS)
	kit.box(at + Vector3(1.0, 1.55, 1.66), Vector3(0.9, 2.0, 0.06), c("#8a8f94"))
	kit.box(at + Vector3(1.0, 0.25, 2.2), Vector3(1.4, 0.5, 1.0), STEEL)
	for x: float in [0.3, 1.7]:
		kit.box(at + Vector3(x, 0.8, 2.2), Vector3(0.05, 0.9, 0.9), SAFETY)
	kit.box(at + Vector3(6.15, 2.2, 0.6), Vector3(0.3, 0.6, 0.8), c("#d6d6cf"))
	kit.box(at + Vector3(0.0, 0.62, 1.66), Vector3(12.0, 0.1, 0.03), HI_VIS)

## A flat-topped red hill on the horizon, its cap a darker band of rock.
static func mesa(kit: MeshKit, at: Vector3, r: float, high: float, rng: RandomNumberGenerator) -> void:
	kit.cone(at, at + Vector3(0.0, high * 0.8, 0.0), r, r * 0.74, 9, c("#b9653d"), 0.12, rng)
	kit.cone(at + Vector3(0.0, high * 0.8, 0.0), at + Vector3(0.0, high, 0.0), r * 0.74, r * 0.7, 9, c("#8f4a2d"), 0.08, rng)

## A clump of spinifex, the dry yellow-green tussock out round the mine.
static func spinifex(kit: MeshKit, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	kit.cone(at, at + Vector3(0.0, r * 0.75, 0.0), r, r * 0.25, 6, c("#b8a65c") if rng.randf() < 0.6 else c("#9f9a55"), 0.25, rng)

## A white-trunked gum, thin and scraggly, as they grow out in the red country.
static func gum(kit: MeshKit, at: Vector3, high: float, rng: RandomNumberGenerator) -> void:
	kit.cone(at, at + Vector3(rng.randf_range(-0.6, 0.6), high * 0.7, rng.randf_range(-0.6, 0.6)), high * 0.035, high * 0.02, 6, c("#efe9dc"), 0.0, null, false)
	for k in 3:
		var c_at := at + Vector3(rng.randf_range(-high * 0.18, high * 0.18), high * rng.randf_range(0.62, 0.85), rng.randf_range(-high * 0.18, high * 0.18))
		kit.cone(c_at, c_at + Vector3(0.0, high * 0.22, 0.0), high * rng.randf_range(0.14, 0.2), high * 0.06, 7, c("#7f9a62") if k % 2 == 0 else c("#6c8a55"), 0.2, rng)
