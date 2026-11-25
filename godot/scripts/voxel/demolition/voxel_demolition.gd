class_name VoxelDemolition
extends Node3D
## "Demolition" (the owner, 24 Nov, of blowing a hole in Luna Palace: "i really like this, what do you think about
## making a little level with distructable building?"): a little town block, eight buildings of different kinds, and a
## timed run to flatten it. On the phone (Travel: Demolition), or ?demolition in the browser.
##
## The block sits at its own corner of the world (AT, 3 km east of the arena, as the gun range sits 3 km west), under
## the arena's own sky: flat ground, a road down the middle with kerbs and footpaths, buildings either side of it. They
## are VoxelBreakables buildings (add_plain), so everything the St Kilda buildings do they do: a bullet knocks a block
## out, a blast a round hole, the blocks break into bricks that fly and pile up, a block with no way down to the ground
## falls, a big piece comes away as a slab and tips over, and the roof falls in once less than ROOF_GOES of the walls
## stand. They are not all the same: a brick shop of two storeys, a glass-fronted office, a timber shed in big chunks,
## a water tower on four legs (knock the legs out and the tank comes down), a petrol station's canopy on posts, a
## five-storey tower block that pancakes, and two fillers.
##
## The run: RUN_T seconds to get TARGET of the block's blocks down. The HUD counts the share down, the clock and the
## score (blocks destroyed); hit the target and a banner shows the time, the score and the best, kept in
## user://demolition.cfg. Going down doesn't end it. R runs it again, the phone takes you home.
##
## The crane (VoxelWreckingCrane) is parked at the west end of the street: walk up to it and E drives it.
##
## Phase B put two things in the block. VoxelDemolitionMob stations enemies on the rooftops (roof_spots()) and in the
## windows of the upper storeys (window_spots()), with a few out in the street, and brings them down with whatever they
## were standing on -- the roof caving in, the sill blown out -- so they take the fall. VoxelDemolitionProps stands the
## chain-reaction props (prop_spots()): the petrol station's pumps, gas bottles against the walls and a fuel tanker in
## the road, each setting off the next within reach a beat later. The score is blocks down plus KILL_SCORE a kill, and
## the HUD counts the kills.

const AT := Vector3(3000.0, 0.0, 0.0)    # the street's middle (the road runs along x; the player arrives at its west end)
const RUN_T := 180.0             # s a run
const TARGET := 0.55             # of the block's blocks down: the goal
const CASH := 150                # $ for flattening it
const KILL_SCORE := 10           # what a kill is worth beside a block knocked down (the score)
const BEST_FILE := "user://demolition.cfg"
const START := Vector3(-30.0, 0.05, 0.0)     # where you arrive (from AT), looking east down the street
const CRANE_AT := Vector3(-19.0, 0.0, 1.2)   # where the crane is parked
# the rubble this level allows: well under St Kilda's, and lower again on the web and on a phone (the bricks are the
# dear part -- a brick a MultiMesh instance -- and a phone has neither the memory nor the fill rate for St Kilda's)
const CAP := {"fly": 2200, "lie": 60000, "fall": 350, "draw": 1600}
const CAP_WEB := {"fly": 900, "lie": 18000, "fall": 150, "draw": 700}

## The block: each building's name, its outline (x0, z0 to x1, z1, from AT), how tall, its colour, and how it breaks.
## glass: a glazed front. bw: how wide its blocks are along a wall (bigger: it comes apart in bigger chunks). legs:
## [rows left out at the bottom, blocks a corner leg] -- it stands on legs, and comes down when they go.
const TOWN := [
	{"name": "CornerShop", "title": "the corner shop", "a": Vector2(-26, -15), "b": Vector2(-16, -6), "h": 4.2, "col": "#b5804e"},
	{"name": "BrickShop", "title": "the brick shop", "a": Vector2(-12, -17), "b": Vector2(0, -6), "h": 7.0, "col": "#8c4a37"},
	{"name": "Office", "title": "the office", "a": Vector2(4, -19), "b": Vector2(18, -6), "h": 11.0, "col": "#7f8a93", "glass": true},
	{"name": "Shed", "title": "the timber shed", "a": Vector2(22, -12), "b": Vector2(30, -6), "h": 3.4, "col": "#7a5b38", "bw": 1.6},
	{"name": "TowerBlock", "title": "the tower block", "a": Vector2(-22, 7), "b": Vector2(-10, 19), "h": 16.0, "col": "#a9a39a"},
	{"name": "WaterTower", "title": "the water tower", "a": Vector2(-4, 8), "b": Vector2(2, 14), "h": 12.0, "col": "#5f7a6c", "legs": Vector2i(8, 1)},
	{"name": "Petrol", "title": "the petrol station", "a": Vector2(6, 7), "b": Vector2(18, 14), "h": 5.0, "col": "#dcd6c4", "legs": Vector2i(3, 2)},
	{"name": "LockUps", "title": "the lock-ups", "a": Vector2(22, 7), "b": Vector2(32, 13), "h": 3.6, "col": "#8e9aa5"},
]

var arena: VoxelArena
var breaks: VoxelBreakables
var crane: VoxelWreckingCrane
var mob: VoxelDemolitionMob        # the block's enemies (phase B)
var props: VoxelDemolitionProps    # the gas bottles, the pumps, the tanker (phase B)
var active := false
var built := false
var nav = null                   # (VoxelBreakables looks for St Kilda's walking map: there's none here)
var town = null                  # (nor a town map: these buildings are the level's own)

var running := false
var over := false                # the run's finished: the banner's up
var won := false
var time := 0.0                  # s into the run
var blocks0 := 0                 # blocks standing when it was built (the score's out of this)
var best_time := 0.0             # s to flatten it, the best so far (0: none)
var best_score := 0

var _home_at := Vector3.ZERO
var _home_yaw := 0.0
var _home_pitch := 0.0
var _was_frozen := false
var _debris_bound := INF
var _help_text := ""
var _hud: Label
var _end: Label

func setup(a: VoxelArena) -> void:
	arena = a
	name = "Demolition"
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	var cf := ConfigFile.new()
	if cf.load(BEST_FILE) == OK:
		best_time = float(cf.get_value("best", "time", 0.0))
		best_score = int(cf.get_value("best", "score", 0))
	_hud = _label(24, Color("#ffd54a"), 8)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -520
	_hud.offset_right = 520
	_hud.offset_top = 64
	_end = _label(30, Color.WHITE, 10)
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.offset_left = -440
	_end.offset_right = 440
	_end.offset_top = -250
	_end.offset_bottom = -40

func _label(size: int, c: Color, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.visible = false
	arena._hud_layer.add_child(l)
	return l

# ---------------------------------------------------------------- the block

## Small enough to build in a moment (eight buildings, no map behind them): the first trip doesn't stall.
func build() -> void:
	if built:
		return
	built = true
	var t0 := Time.get_ticks_msec()
	_ground()
	breaks = VoxelBreakables.new()
	var cap: Dictionary = CAP_WEB if OS.has_feature("web") or VoxelTouch.active else CAP
	breaks.fly_max = int(cap.fly)         # (before setup: the multimeshes are made this size)
	breaks.lie_max = int(cap.lie)
	breaks.fall_max = int(cap.fall)
	breaks.fall_draw = int(cap.draw)
	add_child(breaks)
	breaks.setup(self, [])
	for spec in TOWN:
		var legs: Vector2i = spec.get("legs", Vector2i.ZERO)
		breaks.add_plain(String(spec.name), _ring(spec), float(spec.h), Color(String(spec.col)),
				bool(spec.get("glass", false)), float(spec.get("bw", VoxelBreakables.BLOCK)), legs.x, maxi(1, legs.y))
	blocks0 = standing()
	crane = VoxelWreckingCrane.new()
	add_child(crane)
	crane.setup(self, AT + CRANE_AT, -PI / 2.0)
	props = VoxelDemolitionProps.new()
	add_child(props)
	props.setup(self)
	mob = VoxelDemolitionMob.new()
	add_child(mob)
	mob.setup(self)
	mob.build_posts()
	print("VoxelDemolition: %d buildings, %d blocks, %d posts, %d props, %d ms" % [breaks.list.size(), blocks0,
		mob.posts.size(), props.list.size(), Time.get_ticks_msec() - t0])

static func _ring(spec: Dictionary) -> PackedVector2Array:
	var a: Vector2 = spec.a + Vector2(AT.x, AT.z)
	var b: Vector2 = spec.b + Vector2(AT.x, AT.z)
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])

# the ground, the road, its kerbs and footpaths (flat, so it reads as a street; the bricks pile up on y = 0)
func _ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1 | SkData.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	_box(body, Vector3(140.0, 1.0, 90.0), AT + Vector3(6.0, -0.5, 0.0), Color("#5f6b45"))        # the dirt
	_box(null, Vector3(140.0, 0.06, 8.0), AT + Vector3(6.0, 0.03, 0.0), Color("#3a3b40"))        # the road
	for i in 17:
		_box(null, Vector3(2.2, 0.08, 0.26), AT + Vector3(-50.0 + i * 7.0, 0.05, 0.0), Color("#9a9478"))   # its middle line
	for s in [-1.0, 1.0]:
		_box(null, Vector3(140.0, 0.22, 3.0), AT + Vector3(6.0, 0.11, s * 5.6), Color("#6d6c66"))   # the footpath
		_box(null, Vector3(140.0, 0.3, 0.3), AT + Vector3(6.0, 0.15, s * 4.1), Color("#85837b"))    # the kerb

func _box(body: StaticBody3D, size: Vector3, at: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	mi.material_override = m
	mi.position = at
	add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = at
		body.add_child(cs)

# ---------------------------------------------------------------- the score

## Blocks of the block still standing.
func standing() -> int:
	var n := 0
	for b in breaks.list:
		n += b.standing
	return n

## Blocks destroyed -- yours, that is: the windows the enemies burst out of to take their posts don't count.
func down() -> int:
	return maxi(0, blocks0 - standing() - (mob.opened if mob else 0))

## Enemies of the block killed this run.
func kills() -> int:
	return mob.kills if mob else 0

## The score: every block down, and KILL_SCORE for every enemy killed.
func score() -> int:
	return down() + kills() * KILL_SCORE

## How much of the block is down, 0..1.
func share() -> float:
	return float(down()) / maxf(1.0, float(blocks0))

func left() -> float:
	return maxf(0.0, RUN_T - time)

# ---------------------------------------------------------------- coming and going

## Off to the block: the arena waits (as the gun range does).
func go() -> void:
	if active:
		return
	build()
	_home_at = arena.player.global_position
	_home_yaw = arena.look_yaw
	_home_pitch = arena.look_pitch
	_was_frozen = arena.frozen
	arena.frozen = true
	_debris_bound = arena.debris.bound
	arena.debris.bound = INF            # (the arena's walls don't stop the cubes out here)
	if arena.waves and arena.waves._banner:
		arena.waves._banner.visible = false
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_help_text = arena.help.text
	arena.help.text = "DEMOLITION   flatten the block   bring it down on the enemies   shoot the petrol station   E drive the crane   P phone (home)   R start again   WASD walk   mouse look   1-5 weapons"
	VoxelBody.wall_at = breaks.solid    # (bodies knocked flying bounce off the buildings: phase B's enemies)
	start()

## Home to the arena, where you were: everything built again for next time.
func home() -> void:
	if not active:
		return
	active = false
	stop()
	if crane:
		crane.leave()
		crane.place(AT + CRANE_AT, -PI / 2.0)      # (back in the street where it's parked)
	if mob:
		mob.clear()                     # (its enemies gone: they're the block's, not the arena's)
	if props:
		props.reset()
	breaks.reset()                      # (the buildings as new)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	arena.frozen = _was_frozen
	arena.debris.bound = _debris_bound
	arena.help.text = _help_text
	VoxelBody.wall_at = Callable()
	_put(_home_at, _home_yaw, _home_pitch)

func _put(at: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = at
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

## A run: the clock from zero, the block as new, you at the west end of the street.
func start() -> void:
	stop()
	if crane:
		crane.leave()
		crane.place(AT + CRANE_AT, -PI / 2.0)
	breaks.reset()
	if mob:
		mob.reset()                     # (after the buildings: its posts are their blocks and roof tiles)
	if props:
		props.reset()
	blocks0 = standing()
	running = true
	over = false
	won = false
	time = 0.0
	_hud.visible = true
	_end.visible = false
	_put(AT + START, -PI / 2.0, -0.02)

func stop() -> void:
	running = false
	over = false
	_hud.visible = false
	_end.visible = false

## Where you stand to look down the street (the pictures, the tests).
func street_spot() -> Vector3:
	return AT + START

# ---------------------------------------------------------------- where the block's enemies and props stand
#
# (Phase A left these three as seams; phase B's VoxelDemolitionMob and VoxelDemolitionProps are what stands on them.
# Each is a point in the world: an enemy's feet, a prop's middle.)

## On the roofs, a few tiles apart: the enemies stationed up there (VoxelDemolitionMob.ROOF).
func roof_spots() -> Array:
	return mob.spots(VoxelDemolitionMob.ROOF) if mob else []

## In the windows of the upper storeys, standing on the block under the glazed one (VoxelDemolitionMob.WINDOW).
func window_spots() -> Array:
	return mob.spots(VoxelDemolitionMob.WINDOW) if mob else []

## Out on the road and the footpaths, in front of every other building (VoxelDemolitionMob.STREET).
func street_spots() -> Array:
	return mob.spots(VoxelDemolitionMob.STREET) if mob else []

## The chain-reaction props: the petrol station's pumps, the gas bottles, the tanker.
func prop_spots() -> Array:
	return props.spots() if props else []

## A shot that hit the world out here (VoxelArena.fire): a prop it hit goes up. True if it was one of them.
func world_shot(collider: Object) -> bool:
	return props != null and active and props.world_shot(collider)

## A blast out here that wasn't a prop's (a grenade): the props in reach of it lit. How many.
func props_blast(p: Vector3, r: float) -> int:
	return props.blast_at(p, r) if (props != null and active) else 0

# ---------------------------------------------------------------- the run

func driving() -> bool:
	return crane != null and crane.driving

func _process(dt: float) -> void:
	if not active:
		return
	if crane:
		crane.step(dt)
		if props:
			props.ball_at(crane.ball, crane.ball_speed())    # (the ball through a gas bottle: up it goes)
	if mob:
		mob.step(dt)
	if props:
		props.step(dt)
	if running:
		time += dt
		if share() >= TARGET:
			_flattened()
		elif left() <= 0.0:
			_out_of_time()
	_hud_line()

func _hud_line() -> void:
	_hud.visible = running and not (arena.phone and arena.phone.is_open())
	if not _hud.visible:
		return
	var tail := ""
	if crane and crane.driving:
		# (on a phone the keys mean nothing: VoxelTouch's own buttons are what's under the thumbs there)
		tail = "     stick: drive and turn   BOOM < >   CABLE ^ v   OUT" if VoxelTouch.active \
			else "     W/S drive   A/D turn   left/right swing the boom   up/down the cable   E out"
	elif crane and crane.can_enter():
		tail = "     E: drive the crane"
	_hud.text = "Demolition: %d%% down (target %d%%), %s left, score %d, %s%s" % [roundi(share() * 100.0),
		roundi(TARGET * 100.0), VoxelParkGame._clock(ceilf(left())), score(), VoxelParkGame._n(kills()), tail]

func _flattened() -> void:
	running = false
	over = true
	won = true
	var new_best := best_time <= 0.0 or time < best_time
	if new_best:
		best_time = time
	best_score = maxi(best_score, score())
	var cf := ConfigFile.new()
	cf.set_value("best", "time", best_time)
	cf.set_value("best", "score", best_score)
	cf.save(BEST_FILE)
	arena.cash += CASH
	_hud.visible = false
	_end.text = "THE BLOCK'S DOWN\n%d%% of it in %s%s\nscore %d (%d blocks, %s)   +$%d\nbest %s, %d\nR: again   P: the phone (home)" % [
		roundi(share() * 100.0), VoxelParkGame._clock(time), "   NEW BEST!" if new_best else "", score(), down(), VoxelParkGame._n(kills()), CASH,
		VoxelParkGame._clock(best_time), best_score]
	_end.visible = true
	arena.sound.play("gold_find", Vector3.INF, 0.0, 0.8)

func _out_of_time() -> void:
	running = false
	over = true
	won = false
	best_score = maxi(best_score, score())
	var cf := ConfigFile.new()
	cf.set_value("best", "time", best_time)
	cf.set_value("best", "score", best_score)
	cf.save(BEST_FILE)
	_hud.visible = false
	_end.text = "TIME UP\n%d%% down of %d%%, score %d (%d blocks, %s)\nbest %d\nR: again   P: the phone (home)" % [
		roundi(share() * 100.0), roundi(TARGET * 100.0), score(), down(), VoxelParkGame._n(kills()), best_score]
	_end.visible = true

func _unhandled_input(e: InputEvent) -> void:
	if not active or (arena.phone and arena.phone.is_open()) or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).physical_keycode
	if k == KEY_E and crane:
		if crane.driving:
			crane.leave()
		elif crane.can_enter():
			crane.enter()
		else:
			return
		get_viewport().set_input_as_handled()
	elif k == KEY_R:
		start()
		get_viewport().set_input_as_handled()
