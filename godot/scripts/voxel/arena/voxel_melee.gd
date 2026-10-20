class_name VoxelMelee
extends Node3D
## What every melee weapon in the voxel arena has in common (the owner, 20 Oct: five melee weapons, each doing something
## different). A weapon is a node the arena makes once (setup), then tells what the mouse buttons do while it's out:
## press(button) on the click, hold(button, dt) every frame it stays down, release(button) on letting go, step(dt)
## every frame out or not. It has a view (first person: on the camera, posed by the weapon, shown while it's out or
## busy), a mesh for Jared's right hand (top-down), the arm pose to hold it with, a drawing for the weapon bar, and
## checks() the logic test runs. Helpers here give the eye, the look, the swing's direction off the mouse, the bodies
## in reach, flying bits, pieces and the hit-stop. Owned by the voxel session.
##
## Subclasses: voxel_sword.gd (slices), voxel_melee_bat.gd, voxel_melee_hammer.gd, voxel_melee_chainsaw.gd,
## voxel_melee_spear.gd (VoxelArena.MELEE lists them; a missing file is just left out).

var arena: Node3D               # VoxelArena (untyped: the two scripts know each other)
var view: Node3D                # the first-person view: a child of the camera; the arena shows/hides it
var last := {}                  # what the last hit did (the self-tests print it)
static var _stop_n := 0

func setup(arena_: Node3D, cam: Camera3D) -> void:
	arena = arena_
	view = Node3D.new()
	cam.add_child(view)
	view.visible = false
	_build()

# ---------------------------------------------------------------- for subclasses to fill in

## Makes the view model (under view) and anything else the weapon needs.
func _build() -> void:
	pass

## A mouse button went down (MOUSE_BUTTON_LEFT / MOUSE_BUTTON_RIGHT) while this weapon is out and up.
func press(_button: int) -> void:
	pass

## Every frame a button stays down after its press.
func hold(_button: int, _dt: float) -> void:
	pass

## The button came up (also sent when the weapon is put away with a button down).
func release(_button: int) -> void:
	pass

## Every frame, out or not (animations, things in flight).
func step(_dt: float) -> void:
	pass

## Taken out / put away.
func on_select() -> void:
	pass

func on_deselect() -> void:
	pass

## Mid-move (the view stays shown, e.g. a quick sword slash with a gun out).
func busy() -> bool:
	return false

## How much of its cooldown is left, 1 to 0 (the weapon bar's slot edge).
func cooling() -> float:
	return 0.0

## Top-down: the weapon in Jared's right hand, in its own space (the grip at the origin, along +z away from the hand,
## its top toward +y), metres. Null: nothing shown.
func hand_mesh() -> Node3D:
	return null

## Top-down: the arm pose to hold it with (a VoxelAnim weapon: "", "spud", "shotgun", "fists" ...).
func hand_pose() -> String:
	return "spud"

## The weapon bar's little drawing of it, in r (left to right: grip to tip).
func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_rect(Rect2(r.position + r.size * Vector2(0.1, 0.4), r.size * Vector2(0.8, 0.2)), col)

## Headless checks for the logic test: [[ok: bool, what: String], ...]. host is a Node in the tree to add bodies to.
static func checks(_host: Node) -> Array:
	return []

# ---------------------------------------------------------------- helpers

func top_down() -> bool:
	return bool(arena.top_down)

## Where the weapon's reach is measured from: the eye (first person) or Jared's chest (top-down).
func eye() -> Vector3:
	if top_down():
		return arena.player.global_position + Vector3(0, 1.15, 0)
	return arena.cam.global_position

## Where it points: the view's middle (first person) or level toward the mouse (top-down).
func look() -> Vector3:
	if top_down():
		var pp: Vector3 = arena.player.global_position
		var at: Vector3 = arena._mouse_floor()
		if at != Vector3.INF:
			var f := Vector3(at.x - pp.x, 0, at.z - pp.z)
			if f.length() > 0.01:
				return f.normalized()
		return Vector3(-sin(arena.look_yaw), 0, -cos(arena.look_yaw))
	return -arena.cam.global_transform.basis.z

## The camera's basis (first person) or one facing look() level (top-down): x right, y up, -z forward.
func frame() -> Basis:
	if top_down():
		var f := look()
		return Basis(f.cross(Vector3.UP).normalized(), Vector3.UP, -f)
	return arena.cam.global_transform.basis

## Which way the mouse has been moving lately, on screen (x right, y down), unit; a still mouse goes back and forth.
func swing_dir() -> Vector2:
	var mv: Vector2 = arena._mouse_v
	if mv.length() > 30.0:
		return mv.normalized()
	arena._flip = -float(arena._flip)
	return Vector2(float(arena._flip), 0.0)

## The bodies whose middle is within r metres (level) of p, nearest first.
func bodies_near(p: Vector3, r: float, alive_only: bool = false) -> Array:
	var out := []
	for b in arena.bodies:
		if alive_only and not b.alive:
			continue
		var d := Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length()
		if d <= r:
			out.append([d, b])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out.map(func(x): return x[1])

## Flying bits from a slice / carve result, out along dir.
func spray(res: Dictionary, dir: Vector3, power: float = 2.2) -> void:
	arena.knocked += (res.bits as Array).size()
	arena.debris.burst(res.bits, dir, power)

## The pieces a slice / carve took off b, flung at vel, spinning at spin.
func fling(b: VoxelBody, res: Dictionary, vel: Vector3, spin: Vector3) -> void:
	if not (res.pieces as Array).is_empty():
		arena.pieces.spawn(b, res.pieces, vel, spin)

## The game all but stops for a blink as a blow lands (secs of real time, at scale speed).
func hit_stop(secs: float = 0.07, scale: float = 0.05) -> void:
	_stop_n += 1
	var me := _stop_n
	Engine.time_scale = scale
	arena._kick = maxf(float(arena._kick), 0.5)
	await get_tree().create_timer(secs, true, false, true).timeout
	if me == _stop_n:
		Engine.time_scale = 1.0

## A box part for a view or hand model.
static func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func mat(col: Color, metal: float = 0.0, rough: float = 0.8, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	return m

func _exit_tree() -> void:
	Engine.time_scale = 1.0
