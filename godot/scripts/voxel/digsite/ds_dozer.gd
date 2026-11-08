class_name DsDozer
extends DsMachine
## The bulldozer (the owner, 8 Nov: "put a bulldozer in there"), the digger game's Dozer: its model (DsProps.bulldozer,
## dozer_blade, its tracks), its numbers. R/F raise and lower the blade. Driving on, its cutting edge cuts everything
## standing above it (DsTerrain.blade): the loose soil at once, firm ground a bit at a time, and banks it up against
## the blade, the rest rolling off its ends; the heap goes with it, picked up again as it drives on, so you push dirt
## about. What's banked against the blade pushes back: the more of it, the slower it goes, and the tracks bog. It
## won't cut rock (stone and harder): it stops dead. In co-op the host's game runs it. Owned by the voxel session.

# (the digger game's: dozer.gd)
const EDGE_X := 2.85            # the blade's cutting edge, ahead of the middle
const HALF_WIDTH := 2.15
const ARM_PIVOT := Vector3(0.85, 0.78, 0.0)
const LIFT_MIN := -0.3          # the edge this far under the tracks' bottoms (m) ...
const LIFT_MAX := 1.15          # ... up to this
const LIFT_SPEED := 0.55
const START_LIFT := 0.35
const HEAP := 1.6               # m over the edge it banks soil up against the blade
const MOUTH := 1.7              # m over the edge the blade reaches
const FIRM := 2                 # firm blocks it cuts off a column each tick
const HARDEST := 2              # soil and clay: stone stops it
const BOG := 3500.0             # loose blocks banked ahead that bring it nearly to a stop

var lift := START_LIFT
var lift_cmd := 0.0
var push_load := 0              # loose blocks banked against the blade
var moved := 0                  # (tests: blocks it's moved)
var _look: Node3D
var _pivot: MeshInstance3D
var _tracks: DsTrackRig
var _was := Vector3.INF

func _init() -> void:
	kind = "bulldozer"
	length = 4.0
	width = 2.9
	max_speed = 3.2
	accel = 1.4
	turn_rate = 0.8
	max_climb = deg_to_rad(30.0)
	step_up = 0.4
	seat = Vector3(0, 1.15, 0.8)

func _build() -> void:
	super()
	(_body.get_child(0) as CollisionShape3D).position.y = 0.7
	_look = Node3D.new()
	_look.rotation.y = PI * 0.5
	add_child(_look)
	var frame := DsKit.new()
	DsProps.track_frames(frame, 1.15, 0.3, 1.8, 2.3, 1.95, false)
	_mesh(_look, frame)
	var body := DsKit.new()
	DsProps.bulldozer(body, false)
	_mesh(_look, body)
	var bk := DsKit.new()
	DsProps.dozer_blade(bk, false)
	_pivot = _mesh(_look, bk)
	_tracks = DsTrackRig.new()
	_look.add_child(_tracks)
	_tracks.setup(DsExcavator.mat(), DsProps.track_path(1.8, 2.33, 1.97), 1.15, 0.62, 1.47, DsProps.dozer_wheels())

func _mesh(parent: Node3D, kit: DsKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsExcavator.mat()
	parent.add_child(m)
	return m

func _pose_tool() -> void:
	if _pivot == null:
		return
	var swing := asin(clampf(lift / (EDGE_X - ARM_PIVOT.x), -0.9, 0.9))
	var turn := Basis(Vector3.BACK, swing)
	_pivot.transform = Transform3D(turn, ARM_PIVOT - turn * ARM_PIVOT)

## The blade's cutting edge, its two ends, in the world
func edge_ends() -> Array:
	var t := _look.global_transform * _pivot.transform
	return [t * Vector3(EDGE_X, 0.0, -HALF_WIDTH), t * Vector3(EDGE_X, 0.0, HALF_WIDTH)]

func edge() -> Vector3:
	var e: Array = edge_ends()
	return ((e[0] as Vector3) + (e[1] as Vector3)) * 0.5

func read_input() -> void:
	super()
	lift_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))

func stop_cmds() -> void:
	super()
	lift_cmd = 0.0

func keys() -> String:
	return "W/S drive   A/D turn   R/F blade up/down (lower it into the ground to cut, push the heap)\nV view   wheel zoom   E get off"

func status() -> String:
	var e := edge()
	var gap := e.y - ground_y(e.x, e.z)
	var word := "Blade %+.2f m" % gap
	if push_load > 0:
		word += "   pushing %.1f t" % (push_load * 0.0031)
	return word + ("   " + blocked if blocked != "" else "")

func _drive(dt: float) -> void:
	# the push_load pushes back: slower with more banked against the blade
	var k := 1.0 - 0.75 * clampf(float(push_load) / BOG, 0.0, 1.0)
	var top := max_speed
	max_speed = top * k
	super(dt)
	max_speed = top

func _tool(dt: float) -> void:
	lift = clampf(lift + lift_cmd * LIFT_SPEED * dt, LIFT_MIN, LIFT_MAX)
	_pose_tool()
	_tracks.update(speed + steer * 0.8, speed - steer * 0.8, dt)
	var tr: DsTerrain = site.terrain
	var e: Array = edge_ends()
	var a: Vector3 = e[0]
	var b: Vector3 = e[1]
	var f := forward()
	# working only going forward (or trying to): a parked blade doesn't dig
	if speed > 0.02 or (throttle > 0.05 and speed > -0.05):
		var r: Dictionary = tr.blade(a, b, f, 2, MOUTH, FIRM, HARDEST, 0, HEAP)
		moved += int(r.moved)
		if bool(r.rock) and int(r.moved) == 0:
			speed = minf(speed, 0.0)
			blocked = "Rock: the blade won't cut it (dynamite, or the excavator)"
	push_load = tr.load_ahead(a, b, f, HEAP + 0.3)

func _follow(dt: float) -> void:
	super(dt)
	_tracks.update(speed, speed, dt)

func net_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift, float(push_load)])

func net_take_more(f: PackedFloat32Array) -> void:
	if f.size() >= 2:
		lift = lerpf(lift, f[0], 0.5)
		push_load = int(f[1])

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift_cmd])

func _take_cmds_more(f: PackedFloat32Array) -> void:
	if f.size() >= 1:
		lift_cmd = clampf(f[0], -1.0, 1.0)
