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

## The trencher: a chain boom pointing down and forward from the pivot, along +x.
static func trencher(kit: MeshKit, length: float) -> void:
	kit.box(Vector3(length * 0.5, 0, 0), Vector3(length, 0.16, 0.08), CHARCOAL)
	for i in 10:
		var x := length * (i + 0.5) / 10.0
		kit.box(Vector3(x, 0.1, 0), Vector3(0.06, 0.05, 0.14), STEEL)
		kit.box(Vector3(x, -0.1, 0), Vector3(0.06, 0.05, 0.14), STEEL)
	kit.box(Vector3(0.05, 0.0, 0), Vector3(0.3, 0.3, 0.26), RED)

## The pipe layer on the Dingo's front: a frame with a drum of pipe on it.
static func pipe_spool(kit: MeshKit) -> void:
	for z: float in [-0.28, 0.28]:
		kit.box(Vector3(0.55, 0.78, z), Vector3(0.65, 0.07, 0.05), CHARCOAL)
	kit.cone(Vector3(0.75, 0.98, -0.27), Vector3(0.75, 0.98, 0.27), 0.34, 0.34, 10, c("#e9e6dc"))
	for z: float in [-0.28, 0.28]:
		kit.cone(Vector3(0.75, 0.98, z - 0.015), Vector3(0.75, 0.98, z + 0.015), 0.4, 0.4, 10, c("#3f7fbf"))

## The solid part of a pair of tracks. The cleats and wheels that run on it are TrackRig's.
static func track_frames(kit: MeshKit, z_mid: float, half_w: float, flat: float, nose: float, top: float) -> void:
	for side: float in [-1.0, 1.0]:
		kit.prism([Vector2(-nose, 0.42), Vector2(-flat, 0.0), Vector2(flat, 0.0), Vector2(nose, 0.42), Vector2(top, 0.88), Vector2(-top, 0.88)], side * (z_mid - half_w), side * (z_mid + half_w), CHARCOAL)
		var face_z := side * (z_mid + half_w + 0.02)
		var k := flat - 0.08
		kit.prism([Vector2(-k, 0.3), Vector2(-k + 0.27, 0.14), Vector2(k - 0.27, 0.14), Vector2(k, 0.3), Vector2(k - 0.17, 0.7), Vector2(-k + 0.17, 0.7)], face_z - side * 0.03, face_z, YELLOW_DARK)

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

## The turning part, in its own coordinates: forward is +x, the ground at y = 0. The cab is on the left, the boom right of middle.
static func excavator_house(kit: MeshKit) -> void:
	kit.box(Vector3(-0.55, 1.2, 0), Vector3(4.1, 0.34, 2.7), YELLOW_DARK)
	kit.box(Vector3(-1.5, 1.78, 0.0), Vector3(1.95, 0.84, 2.6), YELLOW)
	for i in 5:
		kit.box(Vector3(-2.1 + i * 0.3, 2.21, 0.45), Vector3(0.15, 0.02, 1.3), YELLOW_DARK)
	kit.box(Vector3(-2.72, 1.5, 0), Vector3(0.55, 1.12, 2.7), CHARCOAL)
	kit.box(Vector3(0.62, 1.6, 0.98), Vector3(1.5, 0.48, 0.72), YELLOW)
	kit.box(Vector3(0.62, 1.86, 0.98), Vector3(1.3, 0.03, 0.55), YELLOW_DARK)
	kit.cone(Vector3(-1.7, 2.18, 0.8), Vector3(-1.7, 2.95, 0.8), 0.07, 0.07, 6, BLACK)
	kit.cone(Vector3(-1.7, 2.95, 0.8), Vector3(-1.75, 3.05, 0.8), 0.09, 0.09, 6, BLACK)
	# The foot of the boom.
	kit.box(Vector3(0.95, 1.6, 0.25), Vector3(0.9, 0.75, 0.62), YELLOW_DARK)
	# The cab: dark glass in a yellow frame.
	var glass := c("#2c4656")
	kit.box(Vector3(0.45, 2.15, -0.8), Vector3(1.55, 1.56, 0.98), glass)
	kit.box(Vector3(0.45, 2.97, -0.8), Vector3(1.66, 0.1, 1.08), YELLOW)
	for x: float in [-0.32, 1.22]:
		for z: float in [-1.29, -0.31]:
			kit.box(Vector3(x, 2.15, z), Vector3(0.07, 1.6, 0.07), YELLOW)
	kit.box(Vector3(1.28, 2.98, -0.55), Vector3(0.1, 0.12, 0.16), LAMP)

## From the shoulder along +x to the elbow, `length` m away, with the bend upward. Banana-shaped, so in two pieces.
static func excavator_boom(kit: MeshKit, length: float) -> void:
	var m := length * 0.5
	kit.prism([Vector2(-0.22, -0.2), Vector2(m, 0.32), Vector2(m, 0.98), Vector2(-0.22, 0.24)], -0.23, 0.23, YELLOW, YELLOW_DARK)
	kit.prism([Vector2(m, 0.32), Vector2(length + 0.14, -0.14), Vector2(length + 0.14, 0.2), Vector2(m, 0.98)], -0.23, 0.23, YELLOW, YELLOW_DARK)

## From the elbow along +x to the bucket's pin, with a stub behind the elbow for the ram to push on.
static func excavator_stick(kit: MeshKit, length: float) -> void:
	kit.prism([Vector2(-0.62, 0.0), Vector2(length + 0.08, -0.1), Vector2(length + 0.08, 0.1), Vector2(-0.62, 0.42)], -0.17, 0.17, YELLOW, YELLOW_DARK)

## The bucket, from its pin along +x to the teeth; its open side is -y. Plates and curved floor, so it really is a hollow.
static func excavator_bucket(kit: MeshKit, length: float, half_w: float) -> void:
	var floor_line := [Vector2(-0.08, 0.1), Vector2(0.35, 0.5), Vector2(0.85, 0.52), Vector2(length - 0.12, 0.14), Vector2(length, -0.02)]
	for i in floor_line.size() - 1:
		var a: Vector2 = floor_line[i]
		var b: Vector2 = floor_line[i + 1]
		kit.prism([a, b, b + Vector2(0.0, 0.07), a + Vector2(0.0, 0.07)], -half_w, half_w, YELLOW_DARK, CHARCOAL)
	for z: float in [-half_w, half_w]:
		kit.prism([Vector2(-0.08, 0.1), Vector2(0.35, 0.5), Vector2(0.85, 0.52), Vector2(length, -0.02), Vector2(0.15, -0.28)], z - 0.03, z + 0.03, YELLOW)
	for k in 6:
		var z := lerpf(-half_w + 0.08, half_w - 0.08, k / 5.0)
		kit.prism([Vector2(length - 0.06, -0.05), Vector2(length + 0.2, -0.04), Vector2(length - 0.06, 0.07)], z - 0.055, z + 0.055, STEEL)
	# The lugs it hangs from.
	kit.box(Vector3(0.0, 0.12, 0.0), Vector3(0.36, 0.36, 0.34), YELLOW_DARK)

## The bulldozer: forward is +x, the ground at y = 0, about 4.5 m long without the blade. Its tracks are built apart from it.
static func bulldozer(kit: MeshKit) -> void:
	for side: float in [-1.0, 1.0]:
		# Canopy posts, and a work lamp up front.
		kit.box(Vector3(-0.1, 2.35, side * 0.78), Vector3(0.07, 1.4, 0.07), BLACK)
		kit.box(Vector3(-1.5, 2.35, side * 0.78), Vector3(0.07, 1.4, 0.07), BLACK)
		kit.box(Vector3(0.05, 3.0, side * 0.6), Vector3(0.1, 0.12, 0.16), LAMP)

	# The body: a deck over the tracks, the sloped engine hood and its grille, the back of the machine.
	kit.box(Vector3(-0.2, 1.0, 0), Vector3(4.0, 0.45, 2.1), YELLOW)
	kit.prism([Vector2(0.05, 1.2), Vector2(2.2, 1.2), Vector2(2.2, 1.72), Vector2(1.9, 1.85), Vector2(0.05, 2.08)], -0.62, 0.62, YELLOW)
	kit.box(Vector3(2.23, 1.46, 0), Vector3(0.08, 0.42, 1.0), BLACK)
	for i in 4:
		kit.box(Vector3(2.28, 1.3 + i * 0.105, 0), Vector3(0.04, 0.045, 1.0), STEEL)
	for i in 5:
		kit.box(Vector3(0.5 + i * 0.28, 1.89 - i * 0.03, 0), Vector3(0.14, 0.02, 0.9), YELLOW_DARK)
	kit.cone(Vector3(1.05, 1.95, 0.38), Vector3(1.05, 2.65, 0.38), 0.07, 0.07, 6, BLACK)
	kit.cone(Vector3(1.05, 2.65, 0.38), Vector3(1.0, 2.75, 0.38), 0.09, 0.09, 6, BLACK)
	kit.box(Vector3(-1.95, 1.45, 0), Vector3(0.5, 0.75, 1.85), YELLOW)
	kit.box(Vector3(-2.22, 1.45, 0), Vector3(0.05, 0.42, 1.0), BLACK)

	# The open cab: a floor, seat and levers under a canopy on four posts, so you can see out and see the machine.
	kit.box(Vector3(-0.8, 1.27, 0), Vector3(1.55, 0.08, 1.6), CHARCOAL)
	kit.box(Vector3(-0.95, 1.6, 0), Vector3(0.5, 0.58, 0.62), SEAT)
	kit.box(Vector3(-1.2, 2.05, 0), Vector3(0.14, 0.7, 0.58), SEAT)
	for z: float in [-0.42, 0.42]:
		kit.cone(Vector3(-0.3, 1.32, z), Vector3(-0.42, 1.95, z), 0.03, 0.03, 5, BLACK)
		kit.cone(Vector3(-0.42, 1.95, z), Vector3(-0.42, 2.02, z), 0.06, 0.06, 6, STEEL)
	kit.prism([Vector2(-1.72, 3.05), Vector2(0.14, 3.05), Vector2(0.14, 3.16), Vector2(-1.72, 3.2)], -1.02, 1.02, YELLOW)
	kit.box(Vector3(-0.8, 3.02, 0), Vector3(1.62, 0.05, 1.62), BLACK)

	# The ripper on the back.
	kit.box(Vector3(-2.55, 0.92, 0), Vector3(0.2, 0.2, 1.6), YELLOW_DARK)
	for z: float in [-0.6, 0.6]:
		kit.box(Vector3(-2.3, 0.95, z), Vector3(0.6, 0.14, 0.12), YELLOW_DARK)
		kit.prism([Vector2(-2.7, 1.0), Vector2(-2.5, 1.0), Vector2(-2.58, 0.05), Vector2(-2.72, 0.05)], z - 0.06, z + 0.06, CHARCOAL)

## The blade, its push arms and lift rams: separate from the body because it lifts. Same coordinates as the body.
static func dozer_blade(kit: MeshKit) -> void:
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(1.85, 0.72, side * 1.58), Vector3(2.0, 0.18, 0.16), YELLOW_DARK, Basis(Vector3.BACK, deg_to_rad(-6.0)))
		kit.cone(Vector3(0.9, 1.65, side * 0.72), Vector3(2.5, 1.0, side * 1.05), 0.075, 0.075, 6, STEEL)

	# Curved, in straight facets, with a dark steel cutting edge and end plates.
	var w := 2.15
	var profile := [Vector2(2.82, 0.14), Vector2(2.68, 0.55), Vector2(2.7, 1.1), Vector2(2.9, 1.62), Vector2(3.08, 1.72)]
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		kit.prism([a, b, b + Vector2(-0.18, 0.0), a + Vector2(-0.18, 0.0)], -w, w, YELLOW, YELLOW_DARK)
	kit.prism([Vector2(2.72, 0.0), Vector2(2.98, 0.0), Vector2(2.82, 0.16), Vector2(2.66, 0.16)], -w, w, STEEL)
	for z: float in [-w, w]:
		kit.prism([Vector2(2.5, 0.08), Vector2(2.9, 0.08), Vector2(2.72, 1.5), Vector2(2.5, 1.5)], z - 0.05, z + 0.05, YELLOW_DARK)
	kit.box(Vector3(2.48, 0.8, 0), Vector3(0.1, 1.0, 3.5), YELLOW_DARK)

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

## The scout ute, without its wheels: a white single cab with a steel tray, a bull bar, a hi-vis stripe and a bundle of pegs in the
## back. Forward is +x, ground at y = 0, about 5 m long.
static func ute_body(kit: MeshKit) -> void:
	var white := c("#f2f0ea")
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
