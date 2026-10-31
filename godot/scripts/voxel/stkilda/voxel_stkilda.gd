class_name VoxelStKilda
extends Node3D
## St Kilda (the owner, 27 Oct: St Kilda as a map in the voxel game, step 1): a slice of the St Kilda game's map,
## Luna Park and the 50 m round it (its wall, Mr Moon's face entrance and forecourt, a bit of the Esplanade), to
## walk round, its buildings to smash (VoxelBreakables, 29 Oct: your weapons work here). You get there and back on
## the phone (P: VoxelPhone's Travel).
##
## It's the St Kilda game's own code (scripts/voxel/stkilda/map, copied across by tools/stkilda_sync.sh, every class
## with "Sk" in front), built the first time you go, in the arena's own world but 3 km east of it (the copy's map is
## moved there: tools/stkilda_cut.gd), so it's the same player, view (V) and keys. Its looks come too: the old wood
## coaster, the ground, the soft shade, the crowd, the flags, and N for night. Not the St Kilda game's own play (its
## people, the ute, knocking the crowd over). While you're there the arena waits for you (its enemies stood still, no
## new waves), your weapons are put away while you ride the coaster, and the St Kilda sky and sun take over. Where
## you are isn't saved: start the game again and you're home.

const START_BACK := 18.0                     # you arrive this far out from Mr Moon's face, facing his mouth
const WALL_H := 6.0                          # the slice's edge: an invisible wall this tall
const NEAR := 0.15                           # the camera's nearest (m) here: as the St Kilda game's, so the fronts don't flicker

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
var _arena_near := 0.05
var day_night: SkDayNight
var rain: VoxelRain
var breaks: VoxelBreakables
var nav: VoxelParkNav
var game: VoxelParkGame                        # "Kill 1, 2 come" (the phone starts it)
var dirt: VoxelParkDirt                        # the dirt along Luna Park's wall you can dig (the break-in)
var bushes: VoxelParkBushes                    # the bushes in it: cut down, dragged over a hole, hidden in
var hack: VoxelCarouselHack                    # the Carousel's control box, the gadget, a loose bolt (the sabotage)
var _debris_bound := INF
# (what SkCrowd looks for on its parent, from the St Kilda game: no car here, and a stand-in walker that never moves,
# so nobody's knocked over)
var driving := false
var car: SkCar = null
var walker := SkWalker.new()
var fly := {"active": false}

func setup(a: VoxelArena) -> void:
	arena = a
	name = "StKilda"
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED     # (the rides only turn while you're here)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # (the rides turn by the frame, not the physics tick)
	for n in a.get_children():
		if n is WorldEnvironment:
			_we = n

## Build the slice (the first time: a second or two; the screen's black then).
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
	var picked := VoxelBreakables.pick(town, box)     # (the buildings you can smash: the town leaves them to us)
	town.build(self, [[luna, SkLunaPark.CLEAR]])
	SkLunaPark.build(self, town)
	VoxelCarousel.dress(get_node_or_null("Carousel"))     # (its new horses)
	breaks = VoxelBreakables.new()
	add_child(breaks)
	breaks.setup(self, picked)
	breaks.add_park()                         # (and Luna Park's own: the Ghost Train, Luna Palace, the shops)
	nav = VoxelParkNav.new()
	add_child(nav)
	nav.setup(self)
	game = VoxelParkGame.new()
	add_child(game)
	game.setup(self)
	# its looks, as the St Kilda game (town_main) adds them
	for nm in ["Carousel", "GhostTrain", "ArabianMerry", "MoonBalloons", "Spider", "SkyRider", "PowerSurge", "LunaPalace", "Supernova", "PharaohsCurse", "ConeyDrop", "SkLunaPark"]:
		var ride := get_node_or_null(nm) as Node3D
		if ride:
			SkContactShade.under_node(ride)
	SkContactShade.build(town.root)
	dirt = VoxelParkDirt.new()                # (after the shade along the wall: it's cut away over the dirt)
	add_child(dirt)
	dirt.setup(self)
	bushes = VoxelParkBushes.new()
	add_child(bushes)
	bushes.setup(self, dirt)
	SkRideLights.build(self)
	hack = VoxelCarouselHack.new()            # (after the lights: it turns the Carousel's off and on)
	add_child(hack)
	hack.setup(self)
	var crowd := SkCrowd.new()
	crowd.name = "SkCrowd"
	crowd.setup(town)
	add_child(crowd)
	var flags := SkParkFlags.new()
	flags.name = "SkParkFlags"
	add_child(flags)
	day_night = SkDayNight.new()
	day_night.name = "SkDayNight"
	day_night.setup(town, luna, null)
	add_child(day_night)
	rain = VoxelRain.new()                     # (K: rain, laid over the day or night)
	rain.setup(self)
	add_child(rain)
	# the St Kilda sky: kept for when you're here (one WorldEnvironment in the world: the arena's, its sky swapped)
	env = town.environment
	sun = town.sun
	# the St Kilda game's sharper shadows in the park (on a computer): its sun's shadows kept to the nearer 70 m. The
	# shadow map's size, and the smoothing (MSAA), are the voxel game's settings', and F1 (shadows on or off) works here too.
	sun.directional_shadow_max_distance = 70.0
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
	_arena_near = arena.cam.near
	_debris_bound = arena.debris.bound
	arena.debris.bound = INF                    # (the arena's walls don't stop the cubes here)
	arena.frozen = true
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_arena_env = _we.environment
	_we.environment = env
	arena.sun.visible = false
	arena.cam.near = NEAR
	sun.visible = true
	_help_text = arena.help.text
	arena.help.text = "P phone (travel home)   shoot the buildings   WASD walk   mouse look   Shift run   Space jump   V view   N night   K rain   1-5 weapons   Esc mouse"
	var s := arrive_spot()
	_put(s[0], s[1], 0.0)
	rain.arrived()
	VoxelBody.wall_at = breaks.solid           # (bodies knocked flying bounce off the buildings)

## Home to the arena, where you were.
func home() -> void:
	if ride_train:
		end_ride()
	if not active:
		return
	active = false
	game.stop()
	clear_park()
	arena.frozen = _was_frozen
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_we.environment = _arena_env
	arena.sun.visible = true
	arena.cam.near = _arena_near
	arena.debris.bound = _debris_bound
	arena.help.text = _help_text
	_put(_home_at, _home_yaw, _home_pitch)
	breaks.reset()                            # (smashed buildings built again for next time)
	dirt.reset()                              # (the holes filled in, the bushes grown back)
	bushes.reset()
	hack.reset()
	VoxelBody.wall_at = Callable()

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

# ================================================================ riding the Scenic Railway
#
# (The owner, 27 Oct: "make it so you can ride the coaster".) The yellow ring by its station (SkScenicRailway's
# "board" spot): E there and you're in the front seat of the next train, first person, the mouse turning your head.
# W / S faster or slower, V the view from behind the train (you, block Jared, in the front car), E gets off early.
# Round both laps and you're stood back on the ring. The other trains are stopped and hidden while you ride (the
# laps share the track by the station), as in the St Kilda game. The phone takes you off it first.

const RIDE_NEAR := 3.5                # this close to the ring (m) and E gets you on
const HEAD_TURN := 2.6                # how far you can turn your head each way on it (radians)
var ride_train: SkScenicRailway.Train = null
var near_ride := false
var _rider: VoxelBody                 # you in the front seat (seen from behind the train)
var _behind := false                  # V on the ride: the view from behind (kept for next time)
var _look_from := Vector2.ZERO        # where you looked when you got on (your head turns from there)
var _was_top := false

func riding() -> bool:
	return ride_train != null

func railway() -> Node3D:
	return get_node_or_null("SkScenicRailway")

func _process(dt: float) -> void:
	sun.shadow_enabled = arena.sun.shadow_enabled     # (the settings' Shadows, and F1, are on the arena's sun)
	if ride_train:
		var up := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) \
				- float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		if arena.phone.is_open():
			up = 0.0
		SkScenicRailway.speed = clampf(SkScenicRailway.speed + up * dt * 0.8, SkScenicRailway.SPEED_MIN, SkScenicRailway.SPEED_MAX)
		_head()
		_rider.animate(dt, false)
		arena.cross.visible = false
		arena._use_label.text = "SCENIC RAILWAY   speed ×%.1f\nW faster   S slower   V view   E get off" % SkScenicRailway.speed
		return
	var rail := railway()
	near_ride = false
	if rail and rail.has_meta("board") and arena.down_t <= 0.0:
		var b := global_transform * (rail.get_meta("board") as Vector3)
		var p := arena.player.global_position
		near_ride = Vector2(p.x - b.x, p.z - b.z).length() < RIDE_NEAR
	if near_ride:
		arena._use_label.text = "E  ride the Scenic Railway"

func _unhandled_input(e: InputEvent) -> void:
	if not active or arena.phone.is_open() or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).physical_keycode
	if k == KEY_K:                          # rain or dry
		rain.toggle()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_N:                          # day or night (as in the St Kilda game)
		day_night.toggle()
		get_viewport().set_input_as_handled()
		return
	if ride_train:
		if k == KEY_E:
			end_ride()
		elif k == KEY_V:
			_behind = not _behind
			ride_train.view_from_behind(_behind)
		else:
			return
		get_viewport().set_input_as_handled()
	elif near_ride and k == KEY_E:
		start_ride()
		get_viewport().set_input_as_handled()

func start_ride() -> void:
	var rail := railway()
	if rail == null:
		return
	ride_train = SkScenicRailway.next_train(rail)
	if ride_train == null:
		return
	_was_top = arena.top_down
	arena.top_down = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_look_from = Vector2(arena.look_yaw, arena.look_pitch)
	ride_train.board()
	var first := _rider == null
	if first:
		_rider = VoxelBody.new()
	ride_train.seat(_rider)
	if first:
		_rider.setup("jared_new", 0.0125, 1, arena._mat)
	_rider.yaw = PI                        # (facing the front of the car)
	ride_train.view_from_behind(_behind)
	SkScenicRailway.space_out(rail, ride_train)
	_others(false)
	ride_train.ride_over.connect(end_ride, CONNECT_ONE_SHOT)

## Off the ride: stood on the ring, facing into the park.
func end_ride() -> void:
	if ride_train == null:
		return
	if ride_train.ride_over.is_connected(end_ride):
		ride_train.ride_over.disconnect(end_ride)
	ride_train.leave()
	_others(true)
	ride_train = null
	SkScenicRailway.speed = 1.0            # (back to its real speed for the next ride)
	arena.cam.current = true
	arena.top_down = _was_top
	arena._use_label.text = ""
	var rail := railway()
	var into: Vector3 = rail.get_meta("board_into")
	_put(global_transform * (rail.get_meta("board") as Vector3) + Vector3(0, 0.05, 0), atan2(-into.x, -into.z), 0.0)

## The other trains: stopped and out of sight while you ride, back (spaced out round from yours) after.
func _others(on: bool) -> void:
	for c in railway().get_children():
		if c is SkScenicRailway.Train and c != ride_train:
			(c as Node3D).visible = on
			(c as Node).process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

## Your head on the ride: the mouse (the arena's look) turns it from where you looked when you got on; from behind,
## the camera swings round you, level, behind and above the front car.
func _head() -> void:
	if ride_train.rider_cam == null:
		return
	var turn := clampf(wrapf(arena.look_yaw - _look_from.x, -PI, PI), -HEAD_TURN, HEAD_TURN)
	var tilt := clampf(arena.look_pitch - _look_from.y, -1.1, 0.9)
	ride_train.rider_cam.rotation = Vector3(-0.12 + tilt, turn, 0)
	var behind := ride_train.chase_cam
	if behind and behind.current:
		var car := ride_train.front().global_transform
		var fwd := -car.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized().rotated(Vector3.UP, turn)
		var you := car.origin + Vector3(0, 1.1, 0)
		behind.top_level = true
		behind.global_position = you - fwd * 6.5 + Vector3(0, 2.8 - tilt * 4.0, 0)
		behind.look_at(you + fwd * 2.0, Vector3.UP)

func _exit_tree() -> void:
	walker.free()                          # (the crowd's stand-in: never in the scene)
	if _rider and not _rider.is_inside_tree():
		_rider.free()                      # (off the ride, the rider's out of the scene: freed by hand)

# ================================================================ enemies in the park

## An enemy of a kind standing at (or near: on the walking map) `at`, one of St Kilda's: it walks the park's paths
## (VoxelParkNav), not the arena's floor. The walking map's made the first time.
func spawn(key: String, at: Vector3) -> VoxelBody:
	if not nav.ready_:
		nav.bake()
	var b := arena.spawn_kind(key, nav.spot_near(at))
	b.set_meta("park", true)
	return b

## Every one of St Kilda's enemies gone (leaving, or a game over).
func clear_park() -> void:
	for b in arena.bodies.duplicate():
		if b.has_meta("park"):
			arena.bodies.erase(b)
			nav.forget(b.get_instance_id())
			b.queue_free()
