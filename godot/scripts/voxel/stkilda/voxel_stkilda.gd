class_name VoxelStKilda
extends Node3D
## St Kilda (the owner, 27 Oct: St Kilda as a map in the voxel game, step 1): a slice of the St Kilda game's map,
## Luna Park and the 50 m round it (its wall, Mr Moon's face entrance and forecourt, a bit of the Esplanade), to
## walk round. No fighting there yet. You get there and back on the phone (P: VoxelPhone's Travel).
##
## It's the St Kilda game's own code (scripts/voxel/stkilda/map, copied across by tools/stkilda_sync.sh, every class
## with "Sk" in front), built the first time you go, OFFSET m away from the arena in the same world: the same
## player, view (V) and keys. While you're there the arena waits for you (its enemies stood still, no new waves,
## your weapons put away), and the St Kilda sky and sun take over. Where you are isn't saved: start the game again
## and you're home.

const OFFSET := Vector3(0.0, 0.0, -3000.0)   # where the slice's middle goes (far past the arena's sky line)
const START_BACK := 18.0                     # you arrive this far out from Mr Moon's face, facing his mouth
const WALL_H := 6.0                          # the slice's edge: an invisible wall this tall

var arena: VoxelArena
var active := false
var built := false
var town: SkTownBuilder
var env: Environment                         # St Kilda's sky (swapped in for the arena's while you're here)
var sun: DirectionalLight3D
var _home_at := Vector3.ZERO                 # where you were in the arena, and which way you looked
var _home_yaw := 0.0
var _home_pitch := 0.0
var _was_frozen := false
var _arena_env: Environment
var _we: WorldEnvironment                    # the arena's
var _help_text := ""

func setup(a: VoxelArena) -> void:
	arena = a
	name = "StKilda"
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED     # (the rides only turn while you're here)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # (the rides turn by the frame, not the physics tick)
	for n in a.get_children():
		if n is WorldEnvironment:
			_we = n

## Build the slice (the first time: about half a second; the screen's black then).
func build() -> void:
	if built:
		return
	var t0 := Time.get_ticks_msec()
	town = SkTownBuilder.new()
	var luna := SkLunaPark.xf(town)
	var park = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/luna.json"))
	if park != null:
		town.skip = SkScenicRailway.in_the_way(town, luna, park.elements)
		for id in SkLunaRides.skip_ids() + SkLunaRides.stray_blocks(town, park.elements):
			town.skip[id] = true
	var slice: Array = town.data.get("slice", [])
	var box := Rect2(Vector2(slice[0], slice[1]), Vector2(slice[2] - slice[0], slice[3] - slice[1]))
	position = OFFSET - Vector3(box.get_center().x, 0.0, box.get_center().y)
	town.build(self, [[luna, SkLunaPark.CLEAR]])
	SkLunaPark.build(self, town)
	# the St Kilda sky: kept for when you're here (one WorldEnvironment in the world: the arena's, its sky swapped)
	env = town.environment
	sun = town.sun
	for n in town.root.get_children():
		if n is WorldEnvironment:
			n.queue_free()
	# the slice's edge
	var edge := StaticBody3D.new()
	edge.name = "SliceEdge"
	edge.collision_mask = 0
	add_child(edge)
	var c := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		SkTownBuilder._wall(edge, c[i], c[(i + 1) % 4], WALL_H)
	built = true
	print("VoxelStKilda: built in ", Time.get_ticks_msec() - t0, " ms")

## Where you arrive: on Luna Park's forecourt, facing Mr Moon's mouth. [where (world), yaw]
func arrive_spot() -> Array:
	var face := SkLunaPark.xf(town)               # (its front looks along its +z: you look the other way, at it)
	return [global_transform * (face * Vector3(0.0, 0.05, START_BACK)), face.basis.get_euler().y]

## Off to St Kilda: the arena waits.
func go() -> void:
	if active:
		return
	build()
	_home_at = arena.player.global_position
	_home_yaw = arena.look_yaw
	_home_pitch = arena.look_pitch
	_was_frozen = arena.frozen
	arena.frozen = true
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_arena_env = _we.environment
	_we.environment = env
	arena.sun.visible = false
	arena.bar.visible = false                  # (no weapons here yet)
	sun.visible = true
	_help_text = arena.help.text
	arena.help.text = "P phone (travel home)   WASD walk   mouse look   Shift run   Space jump   V view   Esc mouse"
	var s := arrive_spot()
	_put(s[0], s[1], 0.0)

## Home to the arena, where you were.
func home() -> void:
	if not active:
		return
	active = false
	arena.frozen = _was_frozen
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_we.environment = _arena_env
	arena.sun.visible = true
	arena.bar.visible = true
	arena.help.text = _help_text
	_put(_home_at, _home_yaw, _home_pitch)

func _put(at: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = at
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

## (Tests, pictures: --stkilda=dx,dz,yaw) stand dx m right and dz m back from where you arrive (Mr Moon's face your
## front), turned yaw degrees left from facing him.
func stand(arg: String) -> void:
	var v := arg.split_floats(",")
	var s := arrive_spot()
	var b := Basis(Vector3.UP, s[1])
	_put(s[0] + b * Vector3(v[0] if v.size() > 0 else 0.0, 0.0, v[1] if v.size() > 1 else 0.0),
			s[1] + deg_to_rad(v[2] if v.size() > 2 else 0.0), 0.0)
