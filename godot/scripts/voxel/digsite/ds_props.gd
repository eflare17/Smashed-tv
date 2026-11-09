class_name DsProps
extends RefCounted
## The digger game's machines (earthmover-godot/scripts/props.gd, copied for the Dig Site, the owner, 8 Nov: "the
## excavator looks trash compared to the other one"): their bodies, booms, buckets, trays, tracks, in its colours. Forward
## is +x, the ground at y = 0 (DsMachine turns them to face -z). Owned by the voxel session.

## A colour as it looks on screen (the material takes vertex colours as sRGB: DsMachine.prop_mat)
static func c(hex: String) -> Color:
	return Color(hex)

static var YELLOW := c("#f6b40e")
static var YELLOW_DARK := c("#d18f06")
static var CHARCOAL := c("#34363a")
static var BLACK := c("#1c1d20")
static var STEEL := c("#7d8287")
static var CHROME := c("#d6dade")
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
static var MINE_WHITE := c("#eeece6")
static var MINE_GREY := c("#b9bbb7")
static var SAFETY := c("#ffd21f")
# Dirt off the ground: in a bucket or tray, or flying. Red on the mine.
static var DIRT := c("#7d4329")
static var DIRT_DARK := c("#6a3722")
static var DIRT_LIGHT := c("#8a4c30")

static var SKIN := c("#d9a06f")
static var DENIM := c("#37506e")

## A wheel of radius 1 (scaled when placed), `width` m across, with spokes on both faces so it can be seen turning.
static func wheel(kit: DsKit, width: float) -> void:
	kit.cone(Vector3(0, 0, -width * 0.5), Vector3(0, 0, width * 0.5), 1.0, 1.0, 10, BLACK)
	for k in 3:
		kit.box(Vector3.ZERO, Vector3(1.25, 0.2, width + 0.05), STEEL, Basis(Vector3.BACK, k * PI / 3.0))

## The dump truck, without its wheels and tray: forward is +x, ground at y = 0, about 8 m long. A chassis and a square cab up front.
static func truck_body(kit: DsKit) -> void:
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
static func truck_tray(kit: DsKit, length: float, half: float, high: float) -> void:
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
static func loader_bucket(kit: DsKit, length: float, half: float, high: float) -> void:
	kit.box(Vector3(length * 0.5, 0.0, 0), Vector3(length, high * 0.1, half * 2.0), YELLOW_DARK)
	kit.prism([Vector2(-0.02, 0.0), Vector2(high * 0.1, 0.0), Vector2(high * 0.1, high), Vector2(-0.02, high)], -half, half, YELLOW_DARK, CHARCOAL)
	for z: float in [-half, half]:
		kit.prism([Vector2(0.0, 0.0), Vector2(length, 0.0), Vector2(0.0, high)], z - 0.025, z + 0.025, YELLOW)
	kit.box(Vector3(length, 0.0, 0), Vector3(high * 0.16, high * 0.1, half * 2.0), STEEL)

## The two arms a loader lifts with, along +x from the pivot to the pin.
static func loader_arms(kit: DsKit, length: float, z: float, thick: float) -> void:
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(length * 0.5, 0, side * z), Vector3(length + thick, thick, thick * 0.6), YELLOW_DARK)
	kit.box(Vector3(length * 0.72, 0, 0), Vector3(thick * 0.8, thick * 0.8, z * 2.0), YELLOW_DARK)

## The Bobcat, without wheels, arms or bucket. About 2.8 m long and 1.8 m wide, a caged cab on a low body.
static func bobcat_body(kit: DsKit) -> void:
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
static func dingo_body(kit: DsKit) -> void:
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
static func dingo_driver(kit: DsKit) -> void:
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
static func trencher(kit: DsKit, length: float) -> void:
	kit.box(Vector3(length * 0.5, 0, 0), Vector3(length, 0.16, 0.08), CHARCOAL)
	for i in 10:
		var x := length * (i + 0.5) / 10.0
		kit.box(Vector3(x, 0.1, 0), Vector3(0.06, 0.05, 0.14), STEEL)
		kit.box(Vector3(x, -0.1, 0), Vector3(0.06, 0.05, 0.14), STEEL)
	kit.box(Vector3(0.05, 0.0, 0), Vector3(0.3, 0.3, 0.26), RED)

## The pipe layer on the Dingo's front: a frame with a drum of pipe on it.
static func pipe_spool(kit: DsKit) -> void:
	for z: float in [-0.28, 0.28]:
		kit.box(Vector3(0.55, 0.78, z), Vector3(0.65, 0.07, 0.05), CHARCOAL)
	kit.cone(Vector3(0.75, 0.98, -0.27), Vector3(0.75, 0.98, 0.27), 0.34, 0.34, 10, c("#e9e6dc"))
	for z: float in [-0.28, 0.28]:
		kit.cone(Vector3(0.75, 0.98, z - 0.015), Vector3(0.75, 0.98, z + 0.015), 0.4, 0.4, 10, c("#3f7fbf"))

## The solid part of a pair of tracks. The cleats and wheels that run on it are TrackRig's.
static func track_frames(kit: DsKit, z_mid: float, half_w: float, flat: float, nose: float, top: float, mine := false) -> void:
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
static func excavator_carriage(kit: DsKit) -> void:
	kit.box(Vector3(0, 0.68, 0), Vector3(3.0, 0.42, 2.0), CHARCOAL)
	kit.cone(Vector3(0, 0.85, 0), Vector3(0, 1.02, 0), 1.05, 1.05, 12, BLACK)

## How far up a mine excavator's cab sits on its riser, above where the small one's is.
const MINE_CAB_UP := 0.55

## The turning part, in its own coordinates: forward is +x, the ground at y = 0. The cab is on the left, the boom right of middle.
## The mine's one is fleet white, its cab up on a riser with a ladder to it, rails round the engine deck and stripes on the back.
static func excavator_house(kit: DsKit, mine := false) -> void:
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

## From the shoulder along +x to the elbow, `length` m away, with the bend upward. Banana-shaped, so in two pieces.
static func excavator_boom(kit: DsKit, length: float, mine := false) -> void:
	var body := MINE_WHITE if mine else YELLOW
	var dark := MINE_GREY if mine else YELLOW_DARK
	var m := length * 0.5
	kit.prism([Vector2(-0.22, -0.2), Vector2(m, 0.32), Vector2(m, 0.98), Vector2(-0.22, 0.24)], -0.23, 0.23, body, dark)
	kit.prism([Vector2(m, 0.32), Vector2(length + 0.14, -0.14), Vector2(length + 0.14, 0.2), Vector2(m, 0.98)], -0.23, 0.23, body, dark)

## From the elbow along +x to the bucket's pin, with a stub behind the elbow for the ram to push on.
static func excavator_stick(kit: DsKit, length: float, mine := false) -> void:
	kit.prism([Vector2(-0.62, 0.0), Vector2(length + 0.08, -0.1), Vector2(length + 0.08, 0.1), Vector2(-0.62, 0.42)], -0.17, 0.17, MINE_WHITE if mine else YELLOW, MINE_GREY if mine else YELLOW_DARK)

## The bucket, from its pin along +x to the teeth; its open side is -y. Plates and curved floor, so it really is a hollow.
## The mine's is a rock bucket: worn grey, a heavy steel lip, five big teeth and a cutter at each corner.
static func excavator_bucket(kit: DsKit, length: float, half_w: float, mine := false) -> void:
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

## The bulldozer (the digger game's): forward is +x, the ground at y = 0, about 4.5 m long without the blade. Its tracks are
## built apart from it.
static func bulldozer(kit: DsKit, mine := false) -> void:
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
	# The lift cylinders' brackets on the hood's sides, their pins (the cylinders: DsDozer, they move with the blade)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(1.2, 1.74, side * 0.68), Vector3(0.26, 0.3, 0.14), dark)
		kit.cone(Vector3(1.2, 1.78, side * 0.6), Vector3(1.2, 1.78, side * 0.9), 0.035, 0.035, 6, STEEL)
		kit.cone(Vector3(1.05, 1.62, side * 0.63), Vector3(1.05, 1.3, side * 0.63), 0.025, 0.025, 5, BLACK)

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

## The blade, its push arms and the lift rods' brackets: separate from the body because it lifts. Same coordinates as the body. The mine's has
## wings on its ends, the way a big U-blade does.
static func dozer_blade(kit: DsKit, mine := false) -> void:
	var body := MINE_WHITE if mine else YELLOW
	var dark := MINE_GREY if mine else YELLOW_DARK
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(1.85, 0.72, side * 1.58), Vector3(2.0, 0.18, 0.16), dark, Basis(Vector3.BACK, deg_to_rad(-6.0)))
		# the lift cylinders' rods' brackets on its back, and their pins (DsDozer.LIFT_AT)
		for dz: float in [-0.085, 0.085]:
			kit.box(Vector3(2.33, 1.15, side * 0.84 + dz), Vector3(0.22, 0.26, 0.04), dark)
		kit.cone(Vector3(2.36, 1.15, side * 0.72), Vector3(2.36, 1.15, side * 0.96), 0.035, 0.035, 6, STEEL)
		kit.box(Vector3(2.36, 1.15, side * 0.84), Vector3(0.12, 0.12, 0.11), STEEL)

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

## A pine (the digger game's): a trunk and tiers of faceted cones, nudged for a hand-cut look. At `at`, `high` m tall.
static func pine(kit: DsKit, at: Vector3, high: float, rng: RandomNumberGenerator, tiers := 3, sides := 7) -> void:
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
