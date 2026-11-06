extends Node3D
## The earthmover test: a patch of real dirt in the cel-shaded look. Three modes: Look (the camera only), Dirt (tap to drop or
## take soil and watch it slump) and Drive (the bulldozer). Buttons try the ink and grass, and a readout gives the speed and
## the soil total. There's no game round this yet: what it's for is still to be agreed.
##
## For checking: -- --shot=<png> [--mode=Look|Dirt|Drive] [--view=...] [--ink=...] [--grass=...] [--noui] [--wait=<frames>]
## [--demo=pour|dig|push|stall]

const MODES := ["Drive", "Dirt"]
const VIEWS := {"Look": ["Wide", "Pit", "Dozer", "Cab"], "Dirt": ["Wide", "Pit"], "Drive": ["Chase", "High", "Cab"]}
const INKS := {"Off": 0.0, "Thin": 1.0, "Medium": 1.5, "Thick": 2.2}
const INK_NAMES := ["Off", "Thin", "Medium", "Thick"]
## Blades a square metre, near the camera.
const GRASSES := {"Off": 0.0, "Low": 18.0, "Medium": 36.0, "High": 64.0}
const GRASS_NAMES := ["Off", "Low", "Medium", "High"]
const MAX_DENSITY := 64.0
const GRASS_CHUNK := 8.0
const CLODS_PER_M2 := 28.0
## For trying the game out: in the job list, a SKIP beside each job not done yet. Held down, it counts that job done, so the
## next one opens. A skipped job earns no stars. Set to false to lock it away.
const TEST_SKIP := true
const STEER_DEAD := 0.18         # of the stick's reach sideways that does no steering
const SKIP_HOLD_S := 1.5         # how long SKIP has to be held
const FADED := 0.22             # how solid something in the way is drawn
const RES_STEPS := [1.0, 0.85, 0.7]
const CHECK_TOTAL_EVERY := 5.0
## The web graphics mode lights things twice as hard as the phone mode. Measured against a phone-mode picture, half matches.
const SUN_WEB := 0.5

## A heap of cracker dust in free play, near where the Dingo starts.
const FREE_DUST := Vector2(21.0, -11.5)
const FREE_DUST_M3 := 2.0
## The soil the player starts with in hand, in the Dirt mode. A placeholder.
const START_STORE_M3 := 150.0
const POUR_CHUNKS := 5
const POUR_EACH := 320          # mm on one cell a chunk carries (0.02 m3)
const POUR_HIGH := 5.0
const SCOOP_RATE := 30          # mm a tick at the middle
const TOOL_R := 1.6
const GET_IN_GAP := 0.9           # m between him and a machine that's near enough to climb into
const ROOMY := 1.2               # m clear round him that's plenty, stepping off: past this, the usual side will do

var ground: GroundData
var sim := DirtSim.new()
var view_data: GroundView
var dozer: Dozer
var digger: Excavator
var truck: Truck
var bobcat: Loader
var dingo: Loader
var machines: Array[Machine] = []
var workers: Array[Worker] = []   # the drivers on foot, one for each player: hidden while they're in a machine
var _walk_from: Machine
var _walk_spot := Vector2.ZERO
var _fill_cells: Array[Vector2i] = []
var star_card: Control          # "1 STAR!" with FINISH and KEEP GOING, each time a new star's earned
var star_title: Label
var star_note: Label
var _star_up := false
var _stars_offered := 0          # the most stars the card's been shown for this go
var _fill_step := -1
var get_in_button: TouchScreenButton
var get_in_word: Label
var _hinted := {}                 # machines whose hint's been said once already
var pipes: Pipes
var tick_count := 0
var active: Machine
var start_machine := "Dozer"
var height_tex: ImageTexture
var data_tex: ImageTexture
var noise_tex: ImageTexture
var rng := RandomNumberGenerator.new()

var camera: Camera3D
var outline_mat: ShaderMaterial
var outline: MeshInstance3D
var grass_chunks: Array[MultiMeshInstance3D] = []
var clod_chunks: Array[MultiMeshInstance3D] = []
var _clod_wait := 0.0
var grass_density := 36.0
var air_mesh: MultiMeshInstance3D
var air_dust_mesh: MultiMeshInstance3D

var mode := "Drive"
var view := "Chase"
var ink := "Medium"
var grass := "Medium"
var tool_name := "Drop"
var res_i := 0

var yaw := 0.0
var pitch := 0.0
var dist := 40.0
var target := Vector3.ZERO
var look_off := 0.0
var chase_yaw := 0.0

var fingers: Dictionary = {}    # index -> position
var pinch := 0.0
var tool_finger := -1
var stick_finger := -1
var stick_from := Vector2.ZERO
var stick_at := Vector2.ZERO
var stick2_finger := -1
var stick2_from := Vector2.ZERO
var stick2_at := Vector2.ZERO
var stick_ui: Control
var left_button: TouchScreenButton
var left_word: Label
var attach_button: TouchScreenButton
var attach_word: Label
var spread_button: TouchScreenButton
var spread_word: Label
var _spread_shown := false
var hint_time := 0.0
var dig_buzz := 0.0
var alert: Label

var prop_mat: ShaderMaterial
var trees: Trees
var sfx: Sfx
var clods: CPUParticles3D
var dust: CPUParticles3D
var track_dust: CPUParticles3D
var exhaust: CPUParticles3D
var needles: CPUParticles3D
var slam: CPUParticles3D
var tumble: CPUParticles3D
var pour_dust: CPUParticles3D
var shake := 0.0
var push_buzz := 0.0
var slip_time := 0.0
var gauge: Control
var bucket_view: BucketView
var side_shown := true          # the player can put the picture away
var side_button: Node2D
var side_word: Label
const SETTINGS_PATH := "user://settings.cfg"
var gauge_ground := 0.0
var level_button: TouchScreenButton
var level_word: Label
var cut_button: TouchScreenButton
var cut_word: Label
var _cut_shown := false
var start_lift := NAN
var built_size := Vector2.ZERO

## The job being done, if any. Nothing in here is free play.
var mission: Dictionary = {}
var mission_done := false
var mission_clock := 0.0
var covered := 0.0
var banner: Label
var stars_got := 0
var _skip_held := -1.0          # seconds a SKIP has been held, or less than 0 when none is
var _skip_id := ""
var _skip_button: Button
## The roof water job: whether the pipe's joined up, the flood on the lawn and how much of it's left, and how much of the trench is filled in.
var pipe_joined := false
var water: MeshInstance3D
var water_left := 1.0
var filled := 0.0
var drain_puffs: CPUParticles3D
## A flood job: whether a pipe's joined at both ends (the water may still not get through), and the flag where it stops.
var pipe_connected := false
var stop_flag: Node3D
var water_y0 := 0.07
## The rings and words at each end of a pipe job, and whether a pipe's reached each.
var end_marks: Array = []
var end_reached := [false, false]
var pipe_laid := false
var stop_at := -1
var stop_dry := false
var _mark_t := 0.0
## The look round at the start of a pipe job: where the pipe starts, then where it ends. Less than 0 when it isn't running.
var _tour_t := -1.0
var _tour_from := Transform3D()
const TOUR_S := 5.6
## The backyard's floating outdoor set: each piece's node, where it is, how deep it floats, and its own sway.
var floaters: Array = []
var _float_t := 0.0
var online: Online
var online_arg := ""
var report_page := false
var join_code := ""
var join_word: Label
var join_status: Label
var _banner_clock := 0.0
var _guest_ui := ""
var house: MeshInstance3D
## Things that go see-through while they stand between the camera and the machine being driven.
var fadeables: Array[GeometryInstance3D] = []
var obstacles: Array = []       # solid things that aren't machines, as machine footprints are: [a, b, radius]
var menu: Control
var menu_kind := ""             # "start" or "done", or nothing with no menu up
var bot: RefCounted
var game_speed := 1.0

var ui: CanvasLayer
var stats: Label
var buttons: Dictionary = {}
var touch_buttons: Array[Node2D] = []
var top_bar_h := 0.0
var worst := 999.0
var worst_clock := 0.0
var shot_path := ""
var shot_wait := 60
var demo := ""
var demo_clock := 0.0
var start_total := 0
var last_total := 0
var total_clock := 0.0
var total_ok := true
var cost_physics := 0
var cost_sync := 0

func _ready() -> void:
	rng.seed = 77
	_read_args()
	_choose_mission()
	if mission.is_empty():
		ground = GroundData.new()
	else:
		ground = GroundData.new(Mission.site(mission), mission["rect"], Mission.road(mission))
	# A phone browser has far less to spare than the phone app, so it starts with less grass. The Grass button still works.
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		grass = "Low"
	var t0 := Time.get_ticks_msec()
	ground.fill_sim(sim)
	if mission.is_empty():
		sim.add_dust_pile(FREE_DUST, FREE_DUST_M3)
	else:
		Mission.lay_out(sim, mission)
	sim.store = int(START_STORE_M3 / (DirtSim.CELL_M * DirtSim.CELL_M) * DirtSim.MM)
	start_total = sim.total()
	sim.loose_total_cached = sim.loose_total()
	last_total = start_total
	height_tex = ground.height_texture()
	data_tex = ground.data_texture()
	view_data = GroundView.new(ground, sim, height_tex, data_tex)
	var fn := FastNoiseLite.new()
	fn.seed = 3
	fn.frequency = 0.02
	fn.fractal_octaves = 3
	noise_tex = ImageTexture.create_from_image(fn.get_seamless_image(256, 256))
	_add_actions()
	_build_world()
	_build_ground()
	_build_grass()
	_build_clods()
	_build_props()
	_build_air()
	_build_outline()
	_build_camera()
	_build_ui()
	_apply_all()
	built_size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(_on_screen_size)
	var carried: Online = Engine.get_meta("online_keep") if Engine.has_meta("online_keep") else null
	if carried:
		Engine.remove_meta("online_keep")
	online = carried if carried else Online.new()
	online.game = self
	online.report = report_page
	add_child(online)
	if carried:
		online.arrive(self)
		_online_bar()
	elif online_arg != "":
		_online_from_arg.call_deferred()
	print("built in %d ms" % (Time.get_ticks_msec() - t0))

func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--ink="):
			ink = a.substr(6)
		elif a.begins_with("--grass="):
			grass = a.substr(8)
		elif a.begins_with("--wait="):
			shot_wait = int(a.substr(7))
		elif a.begins_with("--lift="):
			start_lift = float(a.substr(7))
		elif a.begins_with("--machine="):
			start_machine = a.substr(10)
		elif a.begins_with("--demo="):
			demo = a.substr(7)
		elif a.begins_with("--mission=") and not Engine.has_meta("online_keep"):
			mission = Mission.find(a.substr(10))
		elif a.begins_with("--speed="):
			game_speed = float(a.substr(8))
		elif a.begins_with("--online="):
			online_arg = a.substr(9)
	# On the web the same checks come in the page's address.
	var page := PeerJsTransport._page_args()
	if page.has("online"):
		online_arg = page["online"]
	if page.has("report"):
		report_page = true
	if page.has("demo"):
		demo = page["demo"]
	if page.has("mission") and not Engine.has_meta("online_keep"):
		mission = Mission.find(page["mission"])

## What this start of the scene is: a job carried over from the menu, free play, or the menu itself. Checks never stop at the menu.
func _choose_mission() -> void:
	Engine.time_scale = game_speed
	if game_speed > 1.0:
		Engine.max_physics_steps_per_frame = int(game_speed * 4.0)
	if mission.is_empty() and Engine.has_meta("mission"):
		mission = Mission.find(Engine.get_meta("mission"))
	if not mission.is_empty():
		start_machine = mission["machine"]
		hint_time = 12.0
		return
	if online_arg == "" and (demo == "touchmenu" or (demo == "" and shot_path == "")) and not Engine.has_meta("free_play"):
		menu_kind = "start"

func _add_actions() -> void:
	for pair: Array in [["dz_forward", KEY_W], ["dz_back", KEY_S], ["dz_left", KEY_A], ["dz_right", KEY_D], ["blade_up", KEY_E], ["blade_down", KEY_Q], ["dig_up", KEY_UP], ["dig_down", KEY_DOWN], ["dig_in", KEY_LEFT], ["dig_out", KEY_RIGHT], ["dig_curl", KEY_U], ["dig_dump", KEY_O]]:
		# Reset reloads the scene, and the actions from last time are still there.
		if InputMap.has_action(pair[0]):
			continue
		InputMap.add_action(pair[0])
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], key)

## ---------------------------------------------------------------- the world

func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47.0, -38.0, 0.0)
	sun.light_color = Color("#fff1d2")
	sun.light_energy = 0.72 * SUN_WEB if _web_look() else 0.72
	sun.shadow_enabled = true
	sun.shadow_blur = 0.0
	sun.shadow_bias = 0.7
	sun.shadow_normal_bias = 3.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_split_1 = 0.22
	add_child(sun)

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", noise_tex)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a8b8d8")
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _web_look() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

func _ground_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ground.gdshader")
	m.set_shader_parameter("height_tex", height_tex)
	m.set_shader_parameter("data_tex", data_tex)
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("dust_tex", view_data.dust_tex)
	m.set_shader_parameter("clods_tex", preload("res://textures/clods.png"))
	return m

func _build_ground() -> void:
	var mat := _ground_material()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GroundData.HALF * 2.0
	plane.subdivide_width = GroundData.N - 1
	plane.subdivide_depth = GroundData.N - 1
	plane.material = mat
	var patch := MeshInstance3D.new()
	patch.mesh = plane
	patch.custom_aabb = AABB(Vector3(-32, -8, -32), Vector3(64, 18, 64))
	add_child(patch)
	# Flat grass round the patch, out to the horizon.
	mat = mat.duplicate()
	mat.set_shader_parameter("outside", true)
	const OUT := 600.0
	for r: Rect2 in [Rect2(-OUT, -OUT, OUT * 2.0, OUT - 32.0), Rect2(-OUT, 32.0, OUT * 2.0, OUT - 32.0), Rect2(-OUT, -32.0, OUT - 32.0, 64.0), Rect2(32.0, -32.0, OUT - 32.0, 64.0)]:
		var p := PlaneMesh.new()
		p.size = r.size
		p.material = mat
		var part := MeshInstance3D.new()
		part.mesh = p
		part.position = Vector3(r.position.x + r.size.x * 0.5, 0.0, r.position.y + r.size.y * 0.5)
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(part)

## A short, wide blade: five corners, three triangles.
func _blade() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.045, 0, 0), Vector3(0.045, 0, 0), Vector3(-0.03, 0.12, 0.012), Vector3(0.03, 0.12, 0.012), Vector3(0.008, 0.26, 0.05)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.46), Vector2(1, 0.46), Vector2(0.5, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3, 2, 3, 4])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Grass in 8 m chunks, each holding its most blades in a random order, so showing fewer is just drawing the first ones.
func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/grass.gdshader")
	mat.set_shader_parameter("height_tex", height_tex)
	mat.set_shader_parameter("data_tex", data_tex)
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.render_priority = 1
	var blade := _blade()
	var gr := RandomNumberGenerator.new()
	gr.seed = 11
	var per_chunk := int(MAX_DENSITY * GRASS_CHUNK * GRASS_CHUNK)
	var chunks_side := int(GroundData.HALF * 2.0 / GRASS_CHUNK)
	for cj in chunks_side:
		for ci in chunks_side:
			var x0 := -GroundData.HALF + ci * GRASS_CHUNK
			var z0 := -GroundData.HALF + cj * GRASS_CHUNK
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = blade
			mm.instance_count = per_chunk
			var buf := PackedFloat32Array()
			buf.resize(per_chunk * 12)
			for i in per_chunk:
				var turn := gr.randf() * TAU
				var s := gr.randf_range(0.72, 1.3)
				var tall := s * gr.randf_range(0.8, 1.25)
				var cs := cos(turn) * s
				var sn := sin(turn) * s
				var o := i * 12
				buf[o] = cs
				buf[o + 2] = sn
				buf[o + 3] = x0 + gr.randf() * GRASS_CHUNK
				buf[o + 5] = tall
				buf[o + 8] = -sn
				buf[o + 10] = cs
				buf[o + 11] = z0 + gr.randf() * GRASS_CHUNK
			mm.buffer = buf
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			inst.material_override = mat
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			inst.custom_aabb = AABB(Vector3(x0, -8.0, z0), Vector3(GRASS_CHUNK, 18.0, GRASS_CHUNK))
			inst.set_meta("middle", Vector3(x0 + GRASS_CHUNK * 0.5, 0.0, z0 + GRASS_CHUNK * 0.5))
			add_child(inst)
			grass_chunks.append(inst)

## A rough ball: 12 corners, 20 faces, each corner pushed about so no two faces match.
func _clod_mesh(gr: RandomNumberGenerator) -> ArrayMesh:
	const T := 1.618034
	var corners := [Vector3(-1, T, 0), Vector3(1, T, 0), Vector3(-1, -T, 0), Vector3(1, -T, 0), Vector3(0, -1, T), Vector3(0, 1, T), Vector3(0, -1, -T), Vector3(0, 1, -T), Vector3(T, 0, -1), Vector3(T, 0, 1), Vector3(-T, 0, -1), Vector3(-T, 0, 1)]
	var points := PackedVector3Array()
	for c: Vector3 in corners:
		points.append(c.normalized() * gr.randf_range(0.72, 1.12))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 5, 11, 0, 1, 5, 0, 7, 1, 0, 10, 7, 0, 11, 10, 1, 9, 5, 5, 4, 11, 11, 2, 10, 10, 6, 7, 7, 8, 1, 3, 4, 9, 3, 2, 4, 3, 6, 2, 3, 8, 6, 3, 9, 8, 4, 5, 9, 2, 11, 4, 6, 10, 2, 8, 7, 6, 9, 1, 8])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Real lumps lying on the loose dirt, in chunks the same way as the grass, each in a random order so showing fewer is just drawing the first ones.
func _build_clods() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/clod.gdshader")
	mat.set_shader_parameter("height_tex", height_tex)
	mat.set_shader_parameter("data_tex", data_tex)
	mat.set_shader_parameter("dust_tex", view_data.dust_tex)
	mat.render_priority = 1
	var gr := RandomNumberGenerator.new()
	gr.seed = 29
	var shapes: Array[ArrayMesh] = [_clod_mesh(gr), _clod_mesh(gr), _clod_mesh(gr)]
	var per_chunk := int(CLODS_PER_M2 * GRASS_CHUNK * GRASS_CHUNK)
	var chunks_side := int(GroundData.HALF * 2.0 / GRASS_CHUNK)
	for cj in chunks_side:
		for ci in chunks_side:
			var x0 := -GroundData.HALF + ci * GRASS_CHUNK
			var z0 := -GroundData.HALF + cj * GRASS_CHUNK
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = shapes[(ci + cj * 2) % shapes.size()]
			mm.instance_count = per_chunk
			for i in per_chunk:
				# Big enough to overlap and hide the ground under them, with some small ones to fill in.
				var size := lerpf(0.07, 0.34, pow(gr.randf(), 1.7))
				var b := Basis(Vector3(gr.randf_range(-1.0, 1.0), gr.randf_range(-1.0, 1.0), gr.randf_range(-1.0, 1.0)).normalized(), gr.randf() * TAU)
				b = b * Basis.from_scale(Vector3(size * gr.randf_range(0.85, 1.35), size, size * gr.randf_range(0.8, 1.25)))
				mm.set_instance_transform(i, Transform3D(b, Vector3(x0 + gr.randf() * GRASS_CHUNK, 0.0, z0 + gr.randf() * GRASS_CHUNK)))
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			inst.material_override = mat
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			inst.custom_aabb = AABB(Vector3(x0 - 1.0, -8.0, z0 - 1.0), Vector3(GRASS_CHUNK + 2.0, 18.0, GRASS_CHUNK + 2.0))
			inst.set_meta("middle", Vector3(x0 + GRASS_CHUNK * 0.5, 0.0, z0 + GRASS_CHUNK * 0.5))
			inst.set_meta("sim_chunk", Vector2i(ci * 2, cj * 2))
			inst.visible = false
			add_child(inst)
			clod_chunks.append(inst)

## Lumps only where there's loose dirt, and fewer further out, where the small ones can't be seen anyway.
func _update_clods() -> void:
	if camera == null:
		return
	var at := camera.global_position
	var loose := view_data.loose_here
	var per_chunk := int(CLODS_PER_M2 * GRASS_CHUNK * GRASS_CHUNK)
	var count := 0
	for inst in clod_chunks:
		var c: Vector2i = inst.get_meta("sim_chunk")
		var any := false
		for dj in 2:
			for di in 2:
				any = any or loose[(c.y + dj) * DirtSim.CHUNKS + c.x + di] != 0
		var d: float = at.distance_to(inst.get_meta("middle"))
		var share := 1.0 if d < 22.0 else (0.6 if d < 36.0 else 0.3)
		var n := int(per_chunk * share * clampf(grass_density / float(GRASSES["Medium"]), 0.4, 1.0)) if any else 0
		if inst.multimesh.visible_instance_count != n:
			inst.visible = n > 0
			inst.multimesh.visible_instance_count = n
		count += n
	set_meta("clods", count)

func _build_props() -> void:
	prop_mat = ShaderMaterial.new()
	prop_mat.shader = preload("res://shaders/prop.gdshader")

	dozer = Dozer.new()
	add_child(dozer)
	dozer.setup(sim, view_data, prop_mat, GroundData.dozer_spot(), GroundData.dozer_dir())
	if not is_nan(start_lift):
		dozer.lift = start_lift
	digger = Excavator.new()
	add_child(digger)
	digger.setup(sim, view_data, prop_mat, GroundData.digger_spot(), (GroundData.PILE - GroundData.digger_spot()).normalized())
	truck = Truck.new()
	add_child(truck)
	truck.setup(sim, view_data, prop_mat, GroundData.truck_spot(), Vector2(1.0, 0.0))
	bobcat = Loader.new()
	add_child(bobcat)
	bobcat.setup(sim, view_data, prop_mat, GroundData.bobcat_spot(), (GroundData.PILE - GroundData.bobcat_spot()).normalized(), Loader.BOBCAT)
	dingo = Loader.new()
	add_child(dingo)
	dingo.setup(sim, view_data, prop_mat, GroundData.dingo_spot(), Vector2(-1.0, 0.0), Loader.DINGO)
	pipes = Pipes.new()
	add_child(pipes)
	pipes.setup(prop_mat)
	dingo.pipes = pipes
	machines = [dozer, digger, truck, bobcat, dingo]
	active = dozer
	for m: Machine in machines:
		if m.machine_name == start_machine:
			active = m
	if not mission.is_empty():
		# Only the job's machine is on site. The others are kept, out of sight and doing nothing, as so much here speaks to them by name.
		sim.catchers.erase(truck)
		for m: Machine in machines:
			m.visible = m == active
		machines = [active]
		(active as Loader).reposition(mission["start"], mission["dir"])
		active.hint = mission["hint"]
		# Playing with a friend, the friend gets the same machine, parked on the side away from the driveway.
		if Engine.has_meta("online_keep") or online_arg != "":
			var second := Loader.new()
			add_child(second)
			second.setup(sim, view_data, prop_mat, mission.get("friend", mission["start"] + Vector2(-3.0, 0.0)), mission["dir"], active.machine_name)
			second.pipes = pipes
			second.hint = mission["hint"]
			machines.append(second)
	# One for each player, on foot. In the list last, so every machine keeps its number, and parked out of sight till wanted.
	for k in 2:
		var w := Worker.new()
		add_child(w)
		w.setup(sim, view_data, prop_mat, active.spot, active.forward())
		workers.append(w)
		machines.append(w)
	chase_yaw = _behind_yaw()

	var tr := RandomNumberGenerator.new()
	tr.seed = 5
	var kit := MeshKit.new()
	trees = Trees.new()
	add_child(trees)
	trees.setup(sim, prop_mat, _tree_spots(tr), tr)
	trees.knocked.connect(_on_tree_knocked)
	trees.landed.connect(_on_tree_landed)
	_add_fence(kit)
	if not mission.is_empty():
		_add_site(kit)
	# A treeline in the distance, plainer, so the horizon isn't empty.
	for i in 170:
		var a := tr.randf() * TAU
		var d := tr.randf_range(42.0, 150.0)
		if a > 0.2 and a < 1.25 and d < 95.0:
			d = 95.0 + tr.randf() * 30.0
		Props.pine(kit, Vector3(cos(a) * d, 0.0, sin(a) * d), tr.randf_range(8.0, 15.0), tr, 2, 6)
	var far := MeshInstance3D.new()
	far.mesh = kit.mesh()
	far.material_override = prop_mat
	add_child(far)
	_gather_fadeables()
	_build_fx()
	sfx = Sfx.new()
	add_child(sfx)

## Where the knockable trees stand: one in the first run so it's found at once, the rest scattered clear of the pit, the pile,
## the run between them and the start.
func _tree_spots(tr: RandomNumberGenerator) -> Array[Vector2]:
	if not mission.is_empty():
		return _job_tree_spots(tr)
	var start := GroundData.dozer_spot()
	var spots: Array[Vector2] = [start + GroundData.dozer_dir() * 8.0]
	var tries := 0
	while spots.size() < 20 and tries < 800:
		tries += 1
		var p := Vector2(tr.randf_range(-28.0, 28.0), tr.randf_range(-28.0, 28.0))
		if ((p - GroundData.PIT) / GroundData.PIT_R).length() < 1.15:
			continue
		if p.distance_to(GroundData.PILE) < GroundData.PILE_R + 1.5:
			continue
		if p.distance_to(FREE_DUST) < 5.0:
			continue
		if p.distance_to(GroundData.digger_spot()) < 5.0 or p.distance_to(GroundData.truck_spot()) < 6.0 or p.distance_to(GroundData.bobcat_spot()) < 4.0:
			continue
		# The Dingo needs a clear run for its first trench.
		if _near_line(p, GroundData.dingo_spot(), GroundData.dingo_spot() + Vector2(-14.0, 0.0), 3.0):
			continue
		if _near_line(p, GroundData.RUN_A, GroundData.RUN_B, GroundData.RUN_W + 1.5) or _near_line(p, start, GroundData.PILE, 3.5):
			continue
		var crowded := false
		for other: Vector2 in spots:
			if other.distance_to(p) < 6.0:
				crowded = true
				break
		if not crowded:
			spots.append(p)
	return spots

## A few trees round the block, clear of the job and the road.
func _job_tree_spots(tr: RandomNumberGenerator) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var keep := Mission.site(mission)
	var road := Mission.road(mission).grow(1.5)
	var tries := 0
	while spots.size() < 12 and tries < 400:
		tries += 1
		var p := Vector2(tr.randf_range(-28.0, 28.0), tr.randf_range(-28.0, 28.0))
		if keep.has_point(p) or road.has_point(p):
			continue
		var crowded := false
		for other: Vector2 in spots:
			if other.distance_to(p) < 6.0:
				crowded = true
				break
		if not crowded:
			spots.append(p)
	return spots

## The job's house at the top of the driveway, and the pegs and string down each side of it.
func _add_site(kit: MeshKit) -> void:
	var r: Rect2 = mission["rect"]
	var peg := Props.c("#efe8d8")
	var line := Props.c("#ff4fa3")
	var z := r.position.y
	while z <= r.end.y + 0.01:
		for x: float in [r.position.x - 0.1, r.end.x + 0.1]:
			kit.box(Vector3(x, 0.3, z), Vector3(0.07, 0.6, 0.07), peg)
		z += 2.0
	for x: float in [r.position.x - 0.1, r.end.x + 0.1]:
		kit.box(Vector3(x, 0.42, r.get_center().y), Vector3(0.025, 0.025, r.size.y), line)
	var front := Mission.house_front(mission)
	const WIDE := 14.0
	const DEEP := 9.0
	const WALL := 2.8
	var mid := front - DEEP * 0.5
	var hk := MeshKit.new()
	hk.box(Vector3(0.0, WALL * 0.5, mid), Vector3(WIDE, WALL, DEEP), Props.c("#e8d9b8"))
	var roof := [Vector2(-WIDE * 0.5 - 0.5, WALL), Vector2(WIDE * 0.5 + 0.5, WALL), Vector2(0.0, WALL + 2.4)]
	hk.prism(roof, front - DEEP - 0.5, front + 0.5, Props.c("#a8553a"))
	# The garage door faces straight down the driveway, as wide as it is.
	hk.box(Vector3(r.get_center().x, 1.1, front + 0.03), Vector3(r.size.x, 2.2, 0.08), Props.c("#8a8f94"))
	for side: float in [-1.0, 1.0]:
		hk.box(Vector3(side * 5.0, 1.6, front + 0.03), Vector3(2.0, 1.2, 0.08), Props.c("#5f8fb5"))
	if Mission.kind(mission) == "pipe":
		_add_downpipe(hk, front, WIDE, WALL)
	house = MeshInstance3D.new()
	house.mesh = hk.mesh()
	house.material_override = prop_mat
	add_child(house)
	obstacles.append([Vector2(-WIDE * 0.5 + DEEP * 0.5, mid), Vector2(WIDE * 0.5 - DEEP * 0.5, mid), DEEP * 0.5])
	if Mission.kind(mission) != "driveway":
		_add_drain(kit)
		_add_flood()
	if Mission.kind(mission) == "flood":
		_add_back_fence(kit)
		_add_backyard_things(kit)
	if Mission.kind(mission) != "driveway":
		_add_end_marks()
		for m: Machine in machines:
			if m is Loader:
				(m as Loader).grade_toward = mission["drain"]
				(m as Loader).plan = Mission.trench_plan(sim, mission)

## A gutter along the front of the roof and a downpipe down the wall to the ground, where the trench is to start.
func _add_downpipe(hk: MeshKit, front: float, wide: float, wall: float) -> void:
	var grey := Props.c("#d6d6cf")
	var at: Vector2 = mission["downpipe"]
	hk.box(Vector3(0.0, wall - 0.05, front + 0.45), Vector3(wide + 1.0, 0.16, 0.16), grey)
	hk.box(Vector3(at.x, wall * 0.5, at.y), Vector3(0.11, wall, 0.11), grey)
	# Its foot turns out from the wall, spilling onto the lawn: where the flood comes from.
	hk.box(Vector3(at.x, 0.1, at.y + 0.18), Vector3(0.11, 0.11, 0.36), grey)

## A paling fence along the back of the yard, with the drain pit in front of it.
func _add_back_fence(kit: MeshKit) -> void:
	var z: float = mission["fence_z"]
	var wood := Props.c("#9a7650")
	var x := -13.5
	while x < 13.6:
		kit.box(Vector3(x, 0.9, z), Vector3(0.12, 1.8, 0.12), wood)
		x += 2.25
	for y: float in [0.45, 1.35]:
		kit.box(Vector3(0.0, y, z + 0.08), Vector3(27.2, 0.1, 0.05), wood)
	x = -13.45
	while x < 13.5:
		kit.box(Vector3(x, 0.85, z + 0.12), Vector3(0.13, 1.6, 0.02), Props.c("#b08a5e") if int(x * 4.0) % 2 == 0 else Props.c("#a07b52"))
		x += 0.15

## A trampoline standing in the flood, and a plastic outdoor table and chairs floating about on it.
func _add_backyard_things(kit: MeshKit) -> void:
	var at: Vector2 = mission["trampoline"]
	var base := Vector3(at.x, sim.height_at(at), at.y)
	const R := 1.65
	for k in 6:
		var a := TAU * k / 6.0
		kit.box(base + Vector3(cos(a) * R, 0.42, sin(a) * R), Vector3(0.06, 0.84, 0.06), Props.c("#5d6166"))
	for k in 22:
		var a := TAU * (k + 0.5) / 22.0
		var turn := Basis(Vector3.UP, -(a + PI * 0.5))
		kit.box(base + Vector3(cos(a) * R, 0.84, sin(a) * R), Vector3(0.5, 0.07, 0.07), Props.c("#7d8288"), turn)
		kit.box(base + Vector3(cos(a) * (R - 0.16), 0.875, sin(a) * (R - 0.16)), Vector3(0.5, 0.05, 0.34), Props.c("#2f7fd6"), turn)
	kit.cone(base + Vector3(0.0, 0.85, 0.0), base + Vector3(0.0, 0.87, 0.0), R - 0.32, R - 0.32, 22, Props.c("#1d1f22"))
	obstacles.append([at, at, R + 0.15])
	var white := Props.c("#ecece4")
	for spec: Array in mission["floaters"]:
		var piece := MeshKit.new()
		var sink := 0.0
		if spec[0] == "table":
			piece.cone(Vector3(0.0, 0.72, 0.0), Vector3(0.0, 0.76, 0.0), 0.55, 0.55, 14, white)
			piece.cone(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.72, 0.0), 0.045, 0.045, 8, white)
			piece.cone(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.03, 0.0), 0.32, 0.3, 10, white)
			sink = 0.64
		else:
			piece.box(Vector3(0.0, 0.45, 0.0), Vector3(0.46, 0.04, 0.44), white)
			piece.box(Vector3(0.0, 0.72, -0.21), Vector3(0.46, 0.5, 0.04), white, Basis(Vector3.RIGHT, -0.15))
			for cx: float in [-0.2, 0.2]:
				for cz: float in [-0.19, 0.19]:
					piece.box(Vector3(cx, 0.22, cz), Vector3(0.04, 0.45, 0.04), white)
			sink = 0.36
		var node := MeshInstance3D.new()
		node.mesh = piece.mesh()
		node.material_override = prop_mat
		add_child(node)
		var home: Vector2 = spec[1]
		floaters.append({"node": node, "home": home, "at": home, "sink": sink, "turn": randf() * TAU, "phase": randf() * TAU})
	_update_floaters(0.0)

## The outdoor set bobs and wanders on the water, gets shoved aside by a machine driving into it, and once the water's gone it sits
## on the mud wherever it ended up.
func _update_floaters(delta: float) -> void:
	if floaters.is_empty():
		return
	_float_t += delta
	var level := water.position.y if water != null and water.visible else -99.0
	for f: Dictionary in floaters:
		var at: Vector2 = f["at"]
		var ground := sim.height_at(at)
		var afloat := level - float(f["sink"]) > ground
		var ph: float = f["phase"]
		if afloat:
			at += Vector2(sin(_float_t * 0.31 + ph), cos(_float_t * 0.23 + ph * 1.7)) * 0.12 * delta
			var home: Vector2 = f["home"]
			if at.distance_to(home) > 2.5:
				at = home + (at - home).limit_length(2.5)
			f["turn"] = float(f["turn"]) + sin(_float_t * 0.2 + ph) * 0.15 * delta
		for m: Machine in machines:
			var away := at - m.spot
			if away.length() < 1.3 and away.length() > 0.001:
				at += away.normalized() * (1.3 - away.length())
		f["at"] = at
		ground = sim.height_at(at)
		var y := maxf(level - float(f["sink"]) + sin(_float_t * 1.4 + ph) * 0.015, ground)
		var node: MeshInstance3D = f["node"]
		node.position = Vector3(at.x, y, at.y)
		var rock := 0.06 * sin(_float_t * 1.1 + ph) if afloat else 0.0
		node.rotation = Vector3(rock, f["turn"], rock * 0.6)

## A hoop over the ground at each end of the pipe, with words over it: where the pipe starts and where it ends. Yellow until a
## pipe's end is inside it, then green.
func _add_end_marks() -> void:
	var from: Array = Mission.source(mission)
	var spots: Array = [[from[0], "START THE PIPE HERE", float(from[1]) if float(from[1]) <= Mission.PIPE_REACH else 0.0],
		[mission["drain"], "END THE PIPE HERE", Mission.PIPE_REACH]]
	for spot: Array in spots:
		var at: Vector2 = spot[0]
		var mark := Node3D.new()
		mark.position = Vector3(at.x, sim.height_at(at), at.y)
		add_child(mark)
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.albedo_color = Color("#ffd23f")
		var reach: float = spot[2]
		if reach > 0.0:
			var hoop := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = reach - 0.07
			torus.outer_radius = reach
			torus.rings = 48
			torus.ring_segments = 6
			hoop.mesh = torus
			hoop.material_override = look
			hoop.position.y = 0.32
			hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mark.add_child(hoop)
		var word := Label3D.new()
		word.text = spot[1]
		word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		word.no_depth_test = true
		word.fixed_size = true
		word.font_size = 56
		word.outline_size = 14
		word.pixel_size = 0.0008
		word.modulate = Color("#ffd23f")
		word.position.y = 3.6
		mark.add_child(word)
		# A big arrow over it, bobbing and flashing, so it can be found from anywhere on the site.
		var arrow_kit := MeshKit.new()
		arrow_kit.cone(Vector3(0.0, 0.6, 0.0), Vector3(0.0, 0.0, 0.0), 0.45, 0.02, 12, Color("#ffd23f"))
		arrow_kit.box(Vector3(0.0, 1.0, 0.0), Vector3(0.24, 0.8, 0.24), Color("#ffd23f"))
		var arrow := MeshInstance3D.new()
		arrow.mesh = arrow_kit.mesh()
		var bright := StandardMaterial3D.new()
		bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bright.vertex_color_use_as_albedo = true
		arrow.material_override = bright
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arrow.position.y = 2.0
		mark.add_child(arrow)
		end_marks.append([mark, look, word, arrow])

## The arrows bob and flash, over the ends no pipe has reached yet.
func _wave_end_marks(delta: float) -> void:
	_mark_t += delta
	for k in end_marks.size():
		var arrow: MeshInstance3D = end_marks[k][3]
		arrow.position.y = 2.0 + sin(_mark_t * 4.0) * 0.25
		arrow.visible = not end_reached[k] and fmod(_mark_t, 0.8) < 0.56

## The look round: the camera goes to where the pipe starts, then to the drain, then back to the machine. Any tap ends it.
func _start_tour() -> void:
	if mission.is_empty() or Mission.kind(mission) == "driveway" or demo != "" or shot_path != "" or camera == null:
		return
	_tour_t = 0.0
	_tour_from = camera.global_transform

func _end_tour() -> void:
	_tour_t = -1.0
	_show_banner()
	_place_camera()

func _tour_step(delta: float) -> void:
	if _tour_t < 0.0:
		return
	_tour_t += delta
	if _tour_t >= TOUR_S:
		_end_tour()

## Where the camera is partway through the look round.
func _tour_camera() -> void:
	var from: Array = Mission.source(mission)
	var a: Vector2 = from[0]
	var b: Vector2 = mission["drain"]
	var at_a := Vector3(a.x, sim.height_at(a), a.y)
	var at_b := Vector3(b.x, sim.height_at(b), b.y)
	var off := Vector3(3.5, 6.0, 6.0)
	var look_at_now: Vector3
	var pos: Vector3
	var t := _tour_t
	if t < 0.8:
		var k := smoothstep(0.0, 0.8, t)
		pos = _tour_from.origin.lerp(at_a + off, k)
		look_at_now = (_tour_from.origin - _tour_from.basis.z * 8.0).lerp(at_a, k)
	elif t < 2.8:
		pos = at_a + off
		look_at_now = at_a
	elif t < 3.6:
		var k := smoothstep(2.8, 3.6, t)
		pos = (at_a + off).lerp(at_b + off, k)
		look_at_now = at_a.lerp(at_b, k)
	else:
		pos = at_b + off
		look_at_now = at_b
	camera.global_position = pos
	camera.look_at(look_at_now)

func _tour_words() -> String:
	return ("THE PIPE STARTS HERE" if _tour_t < 3.2 else "AND ENDS HERE, AT THE DRAIN") + "   (TAP TO SKIP)"

func _input(e: InputEvent) -> void:
	if _tour_t < 0.0:
		return
	var pressed: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and not e.echo)
	if pressed:
		_end_tour()
		get_viewport().set_input_as_handled()

## The hoops and words go green as a pipe reaches each end, and away once the water's running.
func _show_end_marks(reached: Array) -> void:
	for k in end_marks.size():
		var mark: Node3D = end_marks[k][0]
		mark.visible = not pipe_joined
		var colour := Color("#7ee06a") if reached[k] else Color("#ffd23f")
		(end_marks[k][1] as StandardMaterial3D).albedo_color = colour
		(end_marks[k][2] as Label3D).modulate = colour

## Once the water's running, short lengths join the pipe up: from the foot of the downpipe down into the trench, and from the
## trench into the drain, so it's plain it's all connected.
func _add_joins(run: PackedVector3Array) -> void:
	if run.is_empty():
		return
	var kit := MeshKit.new()
	var white := Props.c("#e9e6dc")
	var d: Vector2 = mission["drain"]
	kit.cone(run[run.size() - 1], Vector3(d.x, sim.height_at(d) - 0.25, d.y), Pipes.RADIUS, Pipes.RADIUS, 8, white)
	if Mission.kind(mission) == "pipe":
		var dp: Vector2 = mission["downpipe"]
		var foot := Vector3(dp.x, 0.1, dp.y + 0.36)
		kit.cone(foot, run[0], Pipes.RADIUS, Pipes.RADIUS, 8, white)
		kit.cone(foot + Vector3(0.0, 0.0, -0.36), foot, Pipes.RADIUS, Pipes.RADIUS, 8, white)
	var joins := MeshInstance3D.new()
	joins.mesh = kit.mesh()
	joins.material_override = prop_mat
	add_child(joins)

## The flag where the water stops in a pipe that goes uphill somewhere, so it's plain where to dig deeper.
func _show_stop_flag(at: Variant) -> void:
	if at == null:
		if stop_flag != null:
			stop_flag.visible = false
		return
	if stop_flag == null:
		stop_flag = Node3D.new()
		var kit := MeshKit.new()
		kit.box(Vector3(0.0, 1.0, 0.0), Vector3(0.06, 2.0, 0.06), Props.c("#f2f2ee"))
		kit.box(Vector3(0.22, 1.75, 0.0), Vector3(0.42, 0.28, 0.03), Props.c("#ff4fa3"))
		var post := MeshInstance3D.new()
		post.mesh = kit.mesh()
		post.material_override = prop_mat
		stop_flag.add_child(post)
		var word := Label3D.new()
		word.text = "WATER STOPS HERE\nDIG DEEPER FROM HERE\nTO THE DRAIN"
		word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		word.no_depth_test = true
		# The same size on screen however far off, so it can be read from the driving camera.
		word.fixed_size = true
		word.font_size = 64
		word.outline_size = 16
		word.pixel_size = 0.0006
		word.modulate = Color("#ffd23f")
		word.position = Vector3(0.0, 2.45, 0.0)
		stop_flag.add_child(word)
		add_child(stop_flag)
	var p: Vector3 = at
	stop_flag.position = p
	stop_flag.visible = true

## The drain at the edge of the street: a dark pit with a grate on it.
func _add_drain(kit: MeshKit) -> void:
	var at: Vector2 = mission["drain"]
	kit.box(Vector3(at.x, 0.03, at.y), Vector3(0.8, 0.06, 0.8), Props.c("#2f3134"))
	for k in 4:
		kit.box(Vector3(at.x - 0.27 + k * 0.18, 0.065, at.y), Vector3(0.05, 0.03, 0.72), Props.c("#7c8085"))
	kit.box(Vector3(at.x, 0.065, at.y - 0.38), Vector3(0.8, 0.03, 0.05), Props.c("#7c8085"))
	kit.box(Vector3(at.x, 0.065, at.y + 0.38), Vector3(0.8, 0.03, 0.05), Props.c("#7c8085"))

## The flooded lawn: a sheet of water lying round the foot of the downpipe. It's only for looks: the dirt knows nothing of it.
func _add_flood() -> void:
	var c: Vector2 = mission["flood"]
	var r: Vector2 = mission["flood_r"]
	const SIDES := 32
	# A flooded yard's sheet is bigger than the water: the ground round it stands higher, and that's its shore.
	var spread := 1.3 if Mission.kind(mission) == "flood" else 1.0
	var points := PackedVector3Array()
	for k in SIDES:
		var a := TAU * k / SIDES
		var wobble := (1.0 + 0.1 * sin(a * 3.0 + 0.7) + 0.06 * sin(a * 5.0 + 2.1)) * spread
		points.append(Vector3(cos(a) * r.x * wobble, 0.0, sin(a) * r.y * wobble))
	var at := PackedVector3Array()
	for k in SIDES:
		at.append(Vector3.ZERO)
		at.append(points[(k + 1) % SIDES])
		at.append(points[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = at
	var normals := PackedVector3Array()
	normals.resize(at.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.38, 0.6, 0.78, 0.82)
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.roughness = 0.12
	look.metallic_specular = 0.7
	water = MeshInstance3D.new()
	water.mesh = m
	water.material_override = look
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_y0 = Mission.water_y(mission)
	water.position = Vector3(c.x, water_y0, c.y)
	add_child(water)
	# Under the water the lawn's drowned to bare mud, so the grass doesn't stand up through it, and it stays muddy once it's drained.
	var a := DirtSim.cell_of(c - r * 1.4)
	var b := DirtSim.cell_of(c + r * 1.4)
	for j in range(a.y, b.y + 1):
		for i in range(a.x, b.x + 1):
			if Mission.kind(mission) == "flood":
				# Mud where it's more than a few centimetres deep; round the edge the grass stands up through it.
				if sim.start_ground[j * DirtSim.CELLS + i] < int((water_y0 - 0.04) * 1000.0):
					view_data.wear(i, j)
				continue
			var p := (Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M - c) / r
			if p.length() < 1.02:
				view_data.wear(i, j)

## Once the pipe's joined, the flood shrinks away and water spurts at the drain until it's gone.
func _drain_flood(delta: float) -> void:
	if water == null or not pipe_joined or water_left <= 0.0:
		return
	var yard := Mission.kind(mission) == "flood"
	water_left = maxf(water_left - delta / (Mission.DRAIN_S * (1.7 if yard else 1.0)), 0.0)
	if yard:
		# A whole yard drains by its level going down: the ground comes up out of it, the hollow last.
		water.position.y = lerpf(water_y0 - 0.5, water_y0, water_left)
	else:
		var k := lerpf(0.15, 1.0, water_left)
		water.scale = Vector3(k, 1.0, k)
		water.position.y = lerpf(water_y0 - 0.06, water_y0, water_left)
	water.visible = water_left > 0.0
	if drain_puffs == null:
		drain_puffs = _puffs(Color(0.55, 0.72, 0.85, 0.7), 18, 0.7)
		var d: Vector2 = mission["drain"]
		drain_puffs.position = Vector3(d.x, 0.1, d.y)
		drain_puffs.direction = Vector3(0.0, 1.0, 0.0)
		drain_puffs.spread = 30.0
		drain_puffs.initial_velocity_min = 0.6
		drain_puffs.initial_velocity_max = 1.4
		drain_puffs.scale_amount_min = 0.12
		drain_puffs.scale_amount_max = 0.28
		drain_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		drain_puffs.emission_box_extents = Vector3(0.3, 0.02, 0.3)
	drain_puffs.emitting = water_left > 0.0
	if water_left <= 0.0:
		_show_banner()

func _near_line(p: Vector2, a: Vector2, b: Vector2, within: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < within

## Posts and tape round the site, so the limit of the work can be seen, just past where the blade can reach.
func _add_fence(kit: MeshKit) -> void:
	const AT := 30.5
	var post := Color("#efe8d8")
	var tape := Color("#ff7a1a")
	var spacing := 6.1
	for i in 11:
		var k := -AT + spacing * i
		for spot2: Vector2 in [Vector2(k, -AT), Vector2(k, AT), Vector2(-AT, k), Vector2(AT, k)]:
			kit.box(Vector3(spot2.x, 0.65, spot2.y), Vector3(0.14, 1.3, 0.14), post)
	for side: float in [-AT, AT]:
		kit.box(Vector3(0.0, 1.12, side), Vector3(AT * 2.0, 0.09, 0.03), tape)
		kit.box(Vector3(side, 1.12, 0.0), Vector3(0.03, 0.09, AT * 2.0), tape)

## ---------------------------------------------------------------- what makes it feel good

func _puff_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = colour
	return m

func _puffs(colour: Color, amount: int, life: float) -> CPUParticles3D:
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 6
	ball.rings = 3
	var p := CPUParticles3D.new()
	p.mesh = ball
	p.material_override = _puff_material(colour)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	add_child(p)
	return p

func _chunks(colours: Array, size: float, amount: int) -> CPUParticles3D:
	var kit := MeshKit.new()
	for i in colours.size():
		kit.box(Vector3(0.0, i * 0.01, 0.0), Vector3(size, size * 0.75, size * 0.85), colours[i], Basis(Vector3(0.4, 1.0, 0.2).normalized(), 0.6))
	var p := CPUParticles3D.new()
	p.mesh = kit.mesh()
	p.material_override = prop_mat
	p.amount = amount
	p.lifetime = 0.9
	p.emitting = false
	p.gravity = Vector3(0.0, -13.0, 0.0)
	p.angular_velocity_min = -280.0
	p.angular_velocity_max = 280.0
	add_child(p)
	return p

## A lump for flying dirt, in place of a box: its own corners on every face, as the shared material lights it from its normals.
func _flying_lump(colours: Array, size: float) -> ArrayMesh:
	var gr := RandomNumberGenerator.new()
	gr.seed = 41
	var source := _clod_mesh(gr).surface_get_arrays(0)
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var order: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var at := PackedVector3Array()
	var normals := PackedVector3Array()
	var tints := PackedColorArray()
	for k in range(0, order.size(), 3):
		var a := points[order[k]] * size * 0.5
		var b := points[order[k + 1]] * size * 0.5
		var c := points[order[k + 2]] * size * 0.5
		var n := (c - a).cross(b - a).normalized()
		var tint: Color = colours[(k / 3) % colours.size()]
		for p: Vector3 in [a, b, c]:
			at.append(p)
			normals.append(n)
			tints.append(tint)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = at
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = tints
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _build_fx() -> void:
	clods = _chunks([Props.c("#7d4329")], 0.2, 26)
	clods.mesh = _flying_lump([Props.c("#7d4329"), Props.c("#6a3722")], 0.3)
	clods.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	clods.emission_box_extents = Vector3(0.2, 0.2, 2.0)
	clods.direction = Vector3(0.5, 1.0, 0.0)
	clods.spread = 42.0
	clods.initial_velocity_min = 1.8
	clods.initial_velocity_max = 4.2
	clods.scale_amount_min = 0.5
	clods.scale_amount_max = 1.3

	dust = _puffs(Color("#c9a77c"), 26, 1.3)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.5, 0.2, 2.2)
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 50.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.3
	dust.gravity = Vector3(0.0, 0.2, 0.0)
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 1.7

	track_dust = _puffs(Color("#d6bd98"), 18, 1.0)
	track_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	track_dust.emission_box_extents = Vector3(0.3, 0.1, 1.2)
	track_dust.direction = Vector3(0.0, 1.0, 0.0)
	track_dust.spread = 40.0
	track_dust.initial_velocity_min = 0.2
	track_dust.initial_velocity_max = 0.8
	track_dust.gravity = Vector3.ZERO
	track_dust.scale_amount_min = 0.5
	track_dust.scale_amount_max = 1.1

	exhaust = _puffs(Color("#2b2b2b"), 16, 1.1)
	exhaust.direction = Vector3(0.0, 1.0, 0.0)
	exhaust.spread = 14.0
	exhaust.initial_velocity_min = 1.4
	exhaust.initial_velocity_max = 2.4
	exhaust.gravity = Vector3(0.3, 0.3, 0.0)
	exhaust.scale_amount_min = 0.22
	exhaust.scale_amount_max = 0.5

	needles = _chunks([Props.PINE_A, Props.TRUNK, Props.PINE_C], 0.26, 34)
	needles.one_shot = true
	needles.explosiveness = 0.95
	needles.lifetime = 1.2
	needles.direction = Vector3(0.0, 1.0, 0.0)
	needles.spread = 75.0
	needles.initial_velocity_min = 2.5
	needles.initial_velocity_max = 7.0
	needles.gravity = Vector3(0.0, -9.0, 0.0)
	needles.scale_amount_min = 0.5
	needles.scale_amount_max = 1.4

	slam = _puffs(Color("#d8c6a4"), 26, 1.2)
	slam.one_shot = true
	slam.explosiveness = 0.95
	slam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	slam.emission_box_extents = Vector3(2.5, 0.2, 2.5)
	slam.direction = Vector3(0.0, 1.0, 0.0)
	slam.spread = 70.0
	slam.initial_velocity_min = 1.0
	slam.initial_velocity_max = 3.2
	slam.gravity = Vector3.ZERO
	slam.scale_amount_min = 1.0
	slam.scale_amount_max = 2.3

	# Lumps rolling down the front of the heap on the blade: the more it's carrying, the more of them.
	tumble = _chunks([Props.c("#7d4329")], 0.34, 40)
	tumble.mesh = _flying_lump([Props.c("#7d4329"), Props.c("#6a3722"), Props.c("#8a4c30")], 0.4)
	tumble.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	tumble.emission_box_extents = Vector3(0.15, 0.1, 1.9)
	tumble.direction = Vector3(1.0, 0.15, 0.0)
	tumble.spread = 16.0
	tumble.initial_velocity_min = 0.7
	tumble.initial_velocity_max = 1.6
	tumble.gravity = Vector3(0.0, -7.0, 0.0)
	tumble.lifetime = 0.7
	tumble.scale_amount_min = 0.45
	tumble.scale_amount_max = 1.25
	tumble.angular_velocity_min = -420.0
	tumble.angular_velocity_max = 420.0

	pour_dust = _puffs(Color("#c9a77c"), 22, 1.4)
	pour_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pour_dust.emission_box_extents = Vector3(0.9, 0.15, 0.9)
	pour_dust.direction = Vector3(0.0, 1.0, 0.0)
	pour_dust.spread = 60.0
	pour_dust.initial_velocity_min = 0.5
	pour_dust.initial_velocity_max = 1.6
	pour_dust.gravity = Vector3.ZERO
	pour_dust.scale_amount_min = 0.9
	pour_dust.scale_amount_max = 1.9

func _on_tree_knocked(at: Vector3) -> void:
	shake = maxf(shake, 0.45)
	needles.position = at + Vector3(0.0, 2.2, 0.0)
	needles.restart()
	sfx.tree_knocked()
	Input.vibrate_handheld(70)

func _on_tree_landed(at: Vector3) -> void:
	shake = maxf(shake, 0.8)
	slam.position = at + Vector3(0.0, 0.3, 0.0)
	slam.restart()
	sfx.tree_landed()
	Input.vibrate_handheld(160)

## Each tick: dirt flies while the blade's moving soil, the tracks raise dust, the stack smokes, and the work is felt.
func _update_fx(dt: float) -> void:
	sfx.update(dt, active)
	shake = maxf(shake - dt * 1.7, 0.0)
	# On foot there's no engine working, no tracks and nothing being dug.
	if active is Worker:
		for p: CPUParticles3D in [track_dust, exhaust, clods, dust, tumble, pour_dust]:
			p.emitting = false
		sfx.pouring(dt, 0.0)
		slip_time = 0.0
		return
	var turn := Basis(Vector3.UP, active.angle)
	track_dust.position = active.to_global(Vector3(-2.2, 0.15, 0.0))
	track_dust.rotation = turn.get_euler()
	track_dust.emitting = absf(active.speed) > 0.8 or active.slipping
	exhaust.position = active.exhaust_point()
	exhaust.emitting = active.effort() > 0.1
	if active == dozer:
		_update_blade_fx(dt, turn)
	else:
		_update_dig_fx(dt)
	if active.slipping:
		slip_time += dt
	else:
		slip_time = 0.0

func _update_blade_fx(dt: float, turn: Basis) -> void:
	var pushing := dozer.moved_tick > 0 and dozer.speed > 0.15
	var mid := (dozer.blade_a + dozer.blade_b) * 0.5
	var front := Vector3(mid.x, sim.height_at(mid) + 0.25, mid.y)
	clods.position = front
	clods.rotation = turn.get_euler()
	clods.emitting = pushing
	dust.position = front
	dust.rotation = turn.get_euler()
	dust.emitting = pushing
	# They start at the top of the heap in front of the blade and roll down its front.
	var f := dozer.forward()
	var top := mid + f * 0.45
	tumble.position = Vector3(top.x, sim.height_at(top) + 0.2, top.y)
	tumble.rotation = turn.get_euler()
	tumble.emitting = pushing and dozer.load_t > 0.6
	tumble.scale_amount_max = lerpf(0.8, 1.6, clampf(dozer.load_t / 10.0, 0.0, 1.0))
	pour_dust.emitting = false
	if dozer.bit_ground:
		shake = maxf(shake, 0.3)
		sfx.clunked(clampf(absf(dozer.speed) / 2.0 + 0.3, 0.0, 1.0))
		Input.vibrate_handheld(30)
	sfx.pouring(dt, 0.0)
	if pushing:
		push_buzz -= dt
		if push_buzz <= 0.0 and dozer.load_t > 3.0:
			push_buzz = 0.3
			Input.vibrate_handheld(18)

func _update_dig_fx(dt: float) -> void:
	tumble.emitting = false
	var cutting := active.moved_tick > 0
	# A trencher's point is down in the slot, but the dirt comes up at the ground.
	var at := active.teeth
	at.y = maxf(at.y, sim.height_at(Vector2(at.x, at.z)) + 0.05)
	var f := active.view_forward()
	clods.position = at
	clods.rotation = Vector3(0.0, atan2(f.x, f.y) + PI * 0.5, 0.0)
	clods.emitting = cutting
	dust.position = at
	dust.emitting = cutting
	var under := Vector2(active.pour_spot.x, active.pour_spot.z)
	pour_dust.position = Vector3(under.x, sim.height_at(under) + 0.2, under.y)
	pour_dust.emitting = active.pouring > 0.15
	sfx.pouring(dt, active.pouring)
	if active.hit_end > 0.0:
		sfx.clunked(active.hit_end)
		shake = maxf(shake, active.hit_end * 0.4)
		Input.vibrate_handheld(int(16.0 + 30.0 * active.hit_end))
	if active.digging:
		dig_buzz -= dt
		if dig_buzz <= 0.0:
			dig_buzz = 0.22
			Input.vibrate_handheld(int(10.0 + 14.0 * active.bog))

## Falling clods: one chunky faceted lump drawn up to the air's limit.
func _build_air() -> void:
	var kit := MeshKit.new()
	var soil := Props.c("#7d4329")
	kit.box(Vector3.ZERO, Vector3(0.22, 0.17, 0.2), soil, Basis(Vector3(0.4, 1.0, 0.2).normalized(), 0.6))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/prop.gdshader")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _flying_lump([soil, Props.c("#6a3722")], 0.27)
	mm.instance_count = DirtSim.AIR_MAX
	mm.visible_instance_count = 0
	air_mesh = MultiMeshInstance3D.new()
	air_mesh.multimesh = mm
	air_mesh.material_override = mat
	air_mesh.custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 40, 80))
	add_child(air_mesh)
	var dust_mm := MultiMesh.new()
	dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	dust_mm.mesh = mm.mesh
	dust_mm.instance_count = DirtSim.AIR_MAX
	dust_mm.visible_instance_count = 0
	air_dust_mesh = MultiMeshInstance3D.new()
	air_dust_mesh.multimesh = dust_mm
	air_dust_mesh.material_override = Props.dust_mat()
	air_dust_mesh.custom_aabb = air_mesh.custom_aabb
	add_child(air_dust_mesh)

func _draw_air() -> void:
	var mm := air_mesh.multimesh
	var dust_mm := air_dust_mesh.multimesh
	var soil_n := 0
	var dust_n := 0
	var spin_axis := Vector3(0.6, 0.5, 0.62).normalized()
	for k in sim.air_amt.size():
		# Each lump its own size for what it carries, tumbling as it falls.
		var size := pow(sim.air_amt[k] / 320.0, 0.34) * 1.3
		var at: Vector3 = sim.air_pos[k]
		var place := Transform3D(Basis(spin_axis, at.y * 2.5 + k).scaled(Vector3.ONE * size), at)
		if sim.air_dust[k] * 2 > sim.air_amt[k]:
			dust_mm.set_instance_transform(dust_n, place)
			dust_n += 1
		else:
			mm.set_instance_transform(soil_n, place)
			soil_n += 1
	mm.visible_instance_count = soil_n
	dust_mm.visible_instance_count = dust_n

func _build_outline() -> void:
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = preload("res://shaders/outline.gdshader")
	outline_mat.render_priority = 0
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.material = outline_mat
	outline = MeshInstance3D.new()
	outline.mesh = q
	outline.extra_cull_margin = 16384.0
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outline)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.near = 0.15
	camera.far = 1200.0
	add_child(camera)

## ---------------------------------------------------------------- the settings

## Phones can report their real screen size only after the game has started, which would strand the controls off screen.
func _on_screen_size() -> void:
	var now := get_viewport().get_visible_rect().size
	if now == built_size:
		return
	built_size = now
	stick_ui.draw.disconnect(_draw_stick)
	gauge.draw.disconnect(_draw_gauge)
	ui.queue_free()
	buttons.clear()
	touch_buttons.clear()
	fingers.clear()
	_build_ui()
	_apply_all()

func _apply_all() -> void:
	if online and online.is_online():
		_online_bar.call_deferred()
	_set_mode(mode, view)
	_set_ink(ink)
	_set_grass(grass)
	_set_res(res_i)
	_label("tool", "Tool: " + tool_name)
	if not mission.is_empty():
		for key: String in ["machine", "mode", "tool", "ink", "grass", "res"]:
			buttons[key].visible = false
		stats.visible = false

## Who the right-hand buttons belong to.
func _show_buttons() -> void:
	var who := active.machine_name
	for b in touch_buttons:
		b.visible = mode == "Drive" and menu == null and String(b.get_meta("for")).contains(who)
	gauge.visible = mode == "Drive" and menu == null and not active is Worker
	bucket_view.visible = gauge.visible and side_shown
	_label("machine", "Now: " + who)
	_show_get_in()

## Swaps which machine the player is in. The other stays parked where it is, and its work stays done.
func _swap_machine() -> void:
	if online.is_guest():
		online.ask("swap")
		return
	if online.is_host():
		online.swap_for(0)
		_take_machine(machines[online.drivers[0]])
		return
	var at := machines.find(active)
	for k in range(1, machines.size()):
		var next: Machine = machines[(at + k) % machines.size()]
		if not next is Worker:
			_take_machine(next)
			return

## The player climbs into this one.
func _take_machine(next: Machine) -> void:
	if next == active:
		return
	active.stop_commands()
	active = next
	stick_finger = -1
	stick2_finger = -1
	fingers.clear()
	slip_time = 0.0
	# Each machine's hint once: climbing back in shouldn't say it all again.
	hint_time = 7.0 if active.hint != "" and not _hinted.has(active) else 0.0
	_hinted[active] = true
	_show_buttons()
	_show_left()
	stick_ui.queue_redraw()
	chase_yaw = _behind_yaw()
	_set_view(view)

## ---------------------------------------------------------------- on foot

## Which machine each player's in, by its place in `machines`: player 0 first.
func _who_drives() -> Array[int]:
	if online and online.is_online() and not online.drivers.is_empty():
		return online.drivers
	var just_me: Array[int] = [machines.find(active)]
	return just_me

## Shows the drivers where they are: a worker on the ground only while his player's on foot, and the driver on a Dingo only while
## someone's in it. Every tick, so swaps and a friend coming or going are all caught.
func _sync_people() -> void:
	var d := _who_drives()
	for k in workers.size():
		var w := workers[k]
		var walking := k < d.size() and d[k] == machines.find(w)
		if online.is_guest():
			w.visible = walking
			w.on_foot = walking
		elif w.on_foot and not walking:
			w.climb_on()
	for m: Machine in machines:
		if not m is Worker:
			m.show_driver(d.has(machines.find(m)))

## The GET OUT button: off the machine and onto the ground beside it.
func _get_out() -> void:
	if online.is_guest():
		online.ask("out")
		return
	_get_out_for(0)

func _get_out_for(player: int) -> void:
	var d := _who_drives()
	if player >= d.size() or player >= workers.size():
		return
	var m: Machine = machines[d[player]]
	if m is Worker:
		return
	var w := workers[player]
	var f := m.forward()
	var side := Vector2(sin(m.angle), cos(m.angle))
	var mid := m.spot + f * (m.fp_front - m.fp_back) * 0.5
	# Down the side, as a driver would, unless the other side, behind or in front has more room. Not into a gap he'd be stuck in.
	var half := (m.fp_front + m.fp_back) * 0.5
	var tries: Array[Vector2] = []
	for out: float in [0.45, 1.3]:
		for k in 8:
			# Left side first, then round: right, behind, in front, and the corners.
			var a: float = [PI * 0.5, -PI * 0.5, PI, 0.0, PI * 0.75, -PI * 0.75, PI * 0.25, -PI * 0.25][k]
			tries.append(mid + f * cos(a) * (half + out) - side * sin(a) * (m.fp_r + out))
	var chosen := tries[0]
	var roomiest := -INF
	for p: Vector2 in tries:
		w.step_off(p, m.angle)
		if absf(p.x) >= Machine.AREA or absf(p.y) >= Machine.AREA:
			continue
		var room := minf(_machine_gap(w), ROOMY)
		if room > roomiest + 0.01:
			roomiest = room
			chosen = p
	m.stop_commands()
	w.step_off(chosen, m.angle)
	if online.is_host():
		online.drivers[player] = machines.find(w)
	if player == 0:
		_take_machine(w)
	_sync_people()

## The machine this worker is near enough to climb into, that nobody else is in, or null.
func _near_machine(w: Worker) -> Machine:
	if not w.on_foot:
		return null
	var d := _who_drives()
	var a: Array = w.footprint()
	var best: Machine = null
	var best_gap := GET_IN_GAP
	for m: Machine in machines:
		if m is Worker or d.has(machines.find(m)) or not m.visible:
			continue
		var b: Array = m.footprint()
		var near := Geometry2D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])
		var gap: float = near[0].distance_to(near[1]) - a[2] - b[2]
		if gap < best_gap:
			best_gap = gap
			best = m
	return best

## The GET IN button: into the machine he's standing by.
func _get_in() -> void:
	if online.is_guest():
		online.ask("in")
		return
	_get_in_for(0)

func _get_in_for(player: int) -> void:
	if player >= workers.size():
		return
	var w := workers[player]
	var m := _near_machine(w)
	if m == null:
		return
	w.climb_on()
	if online.is_host():
		online.drivers[player] = machines.find(m)
	if player == 0:
		_take_machine(m)
	_sync_people()

## GET IN shows only when there's something to get into, and says what.
func _show_get_in() -> void:
	if get_in_button == null:
		return
	var m: Machine = _near_machine(active as Worker) if active is Worker else null
	get_in_button.visible = m != null and mode == "Drive" and menu == null
	if m != null:
		get_in_word.text = "GET IN
" + m.machine_name.to_upper()
	buttons["out"].visible = not active is Worker and mode == "Drive"

## Whether the two thumbs work apart: the excavator's left thumb swings the house and the right moves the arm.
func _two_sticks() -> bool:
	return active == digger and digger.dig_mode

func _toggle_left() -> void:
	if online.is_guest():
		online.ask("left")
		stick_finger = -1
		stick2_finger = -1
		return
	digger.dig_mode = not digger.dig_mode
	digger.throttle = 0.0
	digger.steer = 0.0
	digger.swing_cmd = 0.0
	stick_finger = -1
	stick2_finger = -1
	digger.reach_cmd = 0.0
	digger.raise_cmd = 0.0
	_show_left()
	stick_ui.queue_redraw()

func _show_left() -> void:
	if left_word:
		left_word.text = "NOW: SWING\ntap to DRIVE" if digger.dig_mode else "NOW: DRIVE\ntap to SWING"

func _set_mode(m: String, wanted_view := "") -> void:
	mode = m
	_label("mode", "Mode: " + m)
	buttons["tool"].visible = m == "Dirt"
	_show_buttons()
	stick_finger = -1
	stick2_finger = -1
	tool_finger = -1
	fingers.clear()
	stick_ui.queue_redraw()
	var views: Array = VIEWS[m]
	_set_view(wanted_view if views.has(wanted_view) else views[0])

func _set_view(v: String) -> void:
	view = v
	look_off = 0.0
	match v:
		"Wide":
			target = Vector3(1.5, 0.6, 2.0)
			yaw = deg_to_rad(208.0)
			pitch = deg_to_rad(27.0)
			dist = 37.0
		"Pit":
			target = Vector3(-8.5, -1.6, -3.0)
			yaw = deg_to_rad(150.0)
			pitch = deg_to_rad(17.0)
			dist = 17.0
		"Dozer":
			target = active.position + Vector3(0.0, 1.4, 0.0)
			var ahead := active.forward()
			yaw = atan2(ahead.x, ahead.y) + deg_to_rad(48.0)
			pitch = deg_to_rad(11.0)
			dist = 9.5
		"Cab":
			pitch = deg_to_rad(13.0)
		"Chase":
			# The excavator's work is out ahead and down in the ground, so it wants a higher look from further back.
			pitch = deg_to_rad(active.view_pitch)
			dist = active.view_dist
			chase_yaw = _behind_yaw()
		"High":
			pitch = deg_to_rad(52.0)
			dist = 24.0
			chase_yaw = _behind_yaw()
	camera.fov = 74.0 if v == "Cab" else 52.0
	_label("view", "View: " + v)
	_place_camera()

func _set_ink(i: String) -> void:
	ink = i
	outline.visible = INKS[i] > 0.0
	outline_mat.set_shader_parameter("line_px", INKS[i])
	_label("ink", "Ink: " + i)

func _set_grass(g: String) -> void:
	grass = g
	grass_density = GRASSES[g]
	_label("grass", "Grass: " + g)
	_update_grass_lod()

func _set_res(i: int) -> void:
	res_i = i
	get_viewport().scaling_3d_scale = RES_STEPS[i]
	_label("res", "Res: %d%%" % int(RES_STEPS[i] * 100.0))

func _label(key: String, text: String) -> void:
	if buttons.has(key):
		buttons[key].text = text

func _next(list: Array, current: String) -> String:
	return list[(list.find(current) + 1) % list.size()]

## Fewer blades further out: far chunks draw only the first of their random blades.
func _update_grass_lod() -> void:
	if camera == null:
		return
	var at := camera.global_position
	var count := 0
	for inst in grass_chunks:
		var d: float = at.distance_to(inst.get_meta("middle"))
		var share := 1.0 if d < 20.0 else (0.5 if d < 38.0 else 0.25)
		var n := int(grass_density * GRASS_CHUNK * GRASS_CHUNK * share)
		if inst.multimesh.visible_instance_count != n:
			inst.visible = n > 0
			inst.multimesh.visible_instance_count = n
		count += n
	set_meta("blades", count)

## ---------------------------------------------------------------- the camera

## The house, the trees and every machine's parts, each remembering which machine it belongs to.
func _gather_fadeables() -> void:
	fadeables.clear()
	if house != null:
		fadeables.append(house)
	for t in trees.list:
		fadeables.append(t.node)
	for m: Node in get_children():
		if m is Machine:
			for g: Node in m.find_children("*", "GeometryInstance3D", true, false):
				if (g as GeometryInstance3D).material_override == prop_mat:
					g.set_meta("machine", m)
					fadeables.append(g)

## Anything between the camera and the machine being driven fades to see-through, and comes back once it's out of the way.
func _update_fades(delta: float) -> void:
	if camera == null:
		return
	var from := camera.global_position
	var aim := active.camera_aim()
	var points := [aim, aim + Vector3.UP * 1.4]
	var cab := view == "Cab"
	for g in fadeables:
		if not is_instance_valid(g):
			continue
		var want := 1.0
		if not cab and g.is_visible_in_tree() and not (g.has_meta("machine") and g.get_meta("machine") == active):
			var box := (g.global_transform * g.get_aabb()).grow(0.15)
			# With the camera inside it, it would cover the whole view: it goes altogether.
			if box.grow(0.4).has_point(from):
				want = 0.0
			for p: Vector3 in points:
				if want == 0.0:
					break
				if box.intersects_segment(from, p):
					want = FADED
					break
		var now: float = g.get_meta("fade", 1.0)
		if now == want:
			continue
		now = move_toward(now, want, delta * 3.0)
		g.set_meta("fade", now)
		var see: ShaderMaterial = g.get_meta("fade_mat") if g.has_meta("fade_mat") else null
		if now < 1.0:
			if see == null:
				# Only things in the plain prop look: anything wearing something else right now is left alone.
				if g.material_override != prop_mat:
					g.set_meta("fade", 1.0)
					continue
				see = ShaderMaterial.new()
				see.shader = preload("res://shaders/prop_fade.gdshader")
				# After the grass and the lumps, so blades don't poke through its walls.
				see.render_priority = 2
				g.set_meta("fade_mat", see)
			see.set_shader_parameter("fade", now)
			g.material_override = see
		elif see != null:
			if g.material_override == see:
				g.material_override = prop_mat
			g.remove_meta("fade_mat")


func _behind_yaw() -> float:
	var f := active.view_forward()
	# Straight behind an excavator, its own arm hides the bucket. From the rear right, the arm is seen from the side.
	var offset := 0.6 if _two_sticks() else active.view_side
	return atan2(-f.x, -f.y) + offset

func _place_camera() -> void:
	if camera == null:
		return
	if _tour_t >= 0.0:
		_tour_camera()
		return
	if view == "Cab":
		var f := active.view_forward()
		camera.global_position = active.cab_eye()
		camera.global_rotation = Vector3(-pitch, atan2(f.x, f.y) + PI + look_off, 0.0)
	else:
		var use_yaw := yaw
		var aim := target
		if view == "Chase" or view == "High":
			use_yaw = chase_yaw + look_off
			aim = active.camera_aim()
		var off := Vector3(sin(use_yaw) * cos(pitch), sin(pitch), cos(use_yaw) * cos(pitch)) * dist
		var p := aim + off
		p.y = maxf(p.y, sim.height_at(Vector2(p.x, p.z)) + 0.6)
		camera.global_position = p
		camera.look_at(aim)
	if mode == "Drive":
		# Knocks, and a rumble from the work. Squared, so small ones stay small.
		var rumble := clampf(active.load_t / 25.0, 0.0, 1.0) * 0.025 * absf(active.throttle)
		if active != dozer:
			rumble = active.bog * 0.022
		var size := shake * shake * 0.32 + rumble
		camera.global_position += Vector3(randf_range(-size, size), randf_range(-size, size), randf_range(-size, size))
	_update_grass_lod()

## The ground under a point on the screen, or null.
func _ground_under(screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var t := 0.5
	while t < 160.0:
		var p := from + dir * t
		if absf(p.x) > 30.0 or absf(p.z) > 30.0:
			t += 0.5
			continue
		if p.y <= sim.height_at(Vector2(p.x, p.z)):
			return Vector2(p.x, p.z)
		t += 0.25
	return null

## ---------------------------------------------------------------- touch, mouse and keys

func _on_touch_button(pos: Vector2) -> bool:
	if pos.y < top_bar_h:
		return true
	for b in touch_buttons:
		if b.visible and Rect2(b.position, Vector2.ONE * b.get_meta("size")).has_point(pos):
			return true
	return false

func _unhandled_input(e: InputEvent) -> void:
	if menu != null:
		return
	if e is InputEventKey and e.pressed and not e.echo and mode == "Drive":
		if e.physical_keycode == KEY_L and active == dozer:
			_toggle_level()
			return
		if e.physical_keycode == KEY_M:
			_swap_machine()
			return
		if e.physical_keycode == KEY_F:
			if active is Worker:
				_get_in()
			else:
				_get_out()
			return
		if e.physical_keycode == KEY_T and active == digger:
			_toggle_left()
			return
		if e.physical_keycode == KEY_G and active.machine_name == Loader.DINGO:
			_on_attach()
			return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		_look(e.relative)
	elif e is InputEventScreenTouch:
		if e.pressed:
			if _on_touch_button(e.position):
				return
			# A finger that lifted without the game hearing (a notification, a screen edge) mustn't hold on to the stick.
			if e.index == stick_finger or not fingers.has(stick_finger):
				stick_finger = -1
			if e.index == stick2_finger or not fingers.has(stick2_finger):
				stick2_finger = -1
			fingers[e.index] = e.position
			# One finger anywhere drives. Only a second finger looks round, so driving can never turn into just moving the camera.
			# Digging, each half of the screen is its own thumb; a further finger looks.
			if mode == "Drive" and _two_sticks() and e.position.x > get_viewport().get_visible_rect().size.x * 0.5:
				if stick2_finger < 0:
					stick2_finger = e.index
					stick2_from = e.position
					stick2_at = e.position
			elif mode == "Drive" and stick_finger < 0:
				stick_finger = e.index
				stick_from = e.position
				stick_at = e.position
			elif mode == "Dirt" and fingers.size() == 1:
				tool_finger = e.index
			elif mode == "Dirt":
				tool_finger = -1
		else:
			fingers.erase(e.index)
			if e.index == stick_finger:
				stick_finger = -1
			if e.index == stick2_finger:
				stick2_finger = -1
			if e.index == tool_finger:
				tool_finger = -1
		pinch = _finger_gap()
		if stick_ui:
			stick_ui.queue_redraw()
	elif e is InputEventScreenDrag and fingers.has(e.index):
		# Each finger's own position, not `relative`, which goes wrong with two fingers on some phones (Kev's game).
		var moved: Vector2 = e.position - fingers[e.index]
		fingers[e.index] = e.position
		if e.index == stick_finger:
			stick_at = e.position
			stick_ui.queue_redraw()
		elif e.index == stick2_finger:
			stick2_at = e.position
			stick_ui.queue_redraw()
		elif e.index == tool_finger:
			pass
		elif mode == "Drive":
			_look(moved)
		elif fingers.size() >= 2:
			var gap := _finger_gap()
			if pinch > 0.0 and gap > 0.0:
				_zoom(pinch / gap)
			pinch = gap
			_look(moved * 0.5)
		else:
			_look(moved)

func _look(moved: Vector2) -> void:
	var k := 1.9 / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	if view == "Cab" or view == "Chase" or view == "High":
		look_off -= moved.x * k
		var lo := -30.0 if view == "Cab" else 3.0
		pitch = clampf(pitch + moved.y * k * 0.8, deg_to_rad(lo), deg_to_rad(80.0))
	else:
		yaw -= moved.x * k
		pitch = clampf(pitch + moved.y * k * 0.8, deg_to_rad(3.0), deg_to_rad(85.0))
	_place_camera()

func _finger_gap() -> float:
	if fingers.size() < 2:
		return 0.0
	var v: Array = fingers.values()
	return (v[0] as Vector2).distance_to(v[1])

func _zoom(k: float) -> void:
	if view == "Cab":
		return
	dist = clampf(dist * k, 3.0, 110.0)
	_place_camera()

## ---------------------------------------------------------------- each tick

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	if demo.begins_with("touch") or demo == "ui":
		_run_touch_demo()
	if demo.begins_with("net"):
		online.run_demo(dt)
	elif demo != "" and not demo.begins_with("touch") and demo != "ui":
		_run_demo(dt)
	elif mode == "Drive" and menu == null:
		var reach: float = get_viewport().get_visible_rect().size.y * 0.14
		var stick := Vector2.ZERO
		if stick_finger >= 0:
			stick = ((stick_at - stick_from) / reach).limit_length(1.0)
		var moved := Vector2(Input.get_axis("dz_left", "dz_right"), Input.get_axis("dz_forward", "dz_back")) + stick
		if active == digger:
			var arm := Vector2.ZERO
			if stick2_finger >= 0:
				arm = _dead_zone((stick2_at - stick2_from) / reach)
			arm += Vector2(Input.get_axis("dig_in", "dig_out"), Input.get_axis("dig_up", "dig_down"))
			if digger.dig_mode:
				digger.swing_cmd = clampf(_dead_zone(moved).x, -1.0, 1.0)
				digger.throttle = 0.0
				digger.steer = 0.0
			else:
				digger.swing_cmd = 0.0
				digger.throttle = clampf(-moved.y, -1.0, 1.0)
				digger.steer = _steer_of(moved.x)
			digger.reach_cmd = clampf(arm.x, -1.0, 1.0)
			digger.raise_cmd = clampf(-arm.y, -1.0, 1.0)
			digger.curl_cmd = Input.get_axis("dig_dump", "dig_curl")
		else:
			active.throttle = clampf(-moved.y, -1.0, 1.0)
			active.steer = _steer_of(moved.x)
			if active == dozer:
				dozer.lift_cmd = Input.get_axis("blade_down", "blade_up")
			elif active == truck:
				truck.tip_cmd = 1.0 if Input.is_action_pressed("blade_up") else 0.0
			elif active is Loader:
				var small := active as Loader
				small.lift_cmd = Input.get_axis("blade_down", "blade_up")
				small.curl_cmd = Input.get_axis("dig_dump", "dig_curl")
	else:
		for m: Machine in machines:
			if m != online.guest_machine():
				m.stop_commands()

	_sync_people()
	_show_get_in()
	# A guest's game only says what its thumbs are doing and draws what it's told.
	if online.is_guest():
		online.guest_tick(dt)
		_guest_buttons()
		trees.clear_view(camera.global_position)
		_update_fx(dt)
		_draw_air()
		if mode == "Drive":
			chase_yaw = lerp_angle(chase_yaw, _behind_yaw(), minf(dt * 2.2, 1.0))
			_place_camera()
		return

	if mode == "Dirt" and tool_finger >= 0 and fingers.has(tool_finger):
		var hit: Variant = _ground_under(fingers[tool_finger])
		if hit != null:
			_use_tool(hit, tool_name)

	if spread_button and spread_word.text != _spread_label():
		_show_spread()
	if cut_button and _cut_shown != dozer.cut_on:
		_show_cut()
	var was_spot := active.spot
	var was_angle := active.angle
	# The one being driven runs every tick. Parked ones only have the ground moving under them, so they check four times less often.
	tick_count += 1
	var friend := online.guest_machine()
	var friend_spot := friend.spot if friend else Vector2.ZERO
	var friend_angle := friend.angle if friend else 0.0
	for k in machines.size():
		var m: Machine = machines[k]
		if m == active or m == friend:
			m.step(dt)
		elif (tick_count + k) % 4 == 0:
			m.step(dt * 4.0)
	_bump_machines(was_spot, was_angle)
	if friend:
		_bump_machines(friend_spot, friend_angle, friend)
	trees.update(dt, active)
	if friend:
		trees.also(dt, friend)
	trees.clear_view(camera.global_position)
	_update_fx(dt)
	sim.step(dt)
	online.host_tick(dt)
	cost_physics = Time.get_ticks_usec() - t0
	_draw_air()
	if mode == "Drive":
		var aim := _behind_yaw()
		chase_yaw = lerp_angle(chase_yaw, aim, minf(dt * 2.2, 1.0))
		_place_camera()

## A thumb a hair off the middle shouldn't creep the arm along.
## Steering off the stick: a finger pushing ahead always drifts a little sideways, so near the middle does nothing, and turning
## builds gently from there, to full lock at the side.
func _steer_of(x: float) -> float:
	var off := absf(x)
	if off < STEER_DEAD:
		return 0.0
	return signf(x) * pow(minf((off - STEER_DEAD) / (1.0 - STEER_DEAD), 1.0), 1.7)

func _dead_zone(v: Vector2) -> Vector2:
	var size := v.length()
	if size < 0.14:
		return Vector2.ZERO
	return v / size * minf((size - 0.14) / 0.86, 1.0)

## How close the driven machine is to the nearest other one, less the room each takes up: under nothing and they're touching.
func _machine_gap(who: Machine = null) -> float:
	if who == null:
		who = active
	var a: Array = who.footprint()
	var least := 999.0
	for m: Machine in machines:
		if m == who:
			continue
		var b: Array = m.footprint()
		var near := Geometry2D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])
		least = minf(least, near[0].distance_to(near[1]) - a[2] - b[2])
	for b: Array in obstacles:
		var near := Geometry2D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])
		least = minf(least, near[0].distance_to(near[1]) - a[2] - b[2])
	return least

## The machines are solid to each other: the one being driven stops, with a knock. It can always back away.
func _bump_machines(was_spot: Vector2, was_angle: float, who: Machine = null) -> void:
	if who == null:
		who = active
	var gap := _machine_gap(who)
	if gap >= 0.0:
		return
	var now_spot := who.spot
	var now_angle := who.angle
	who.spot = was_spot
	who.angle = was_angle
	# Moving apart is always allowed, or they could get stuck together.
	if gap > _machine_gap(who):
		who.spot = now_spot
		who.angle = now_angle
		return
	if absf(who.speed) > 0.5 and who == active and not who is Worker:
		shake = maxf(shake, 0.5)
		sfx.clunked(1.0)
		Input.vibrate_handheld(90)
	who.speed = 0.0
	who.drive = 0.0

func _use_tool(at: Vector2, which: String) -> void:
	if which == "Drop":
		sim.pour(at, TOOL_R, POUR_CHUNKS, POUR_EACH, POUR_HIGH, rng)
	else:
		sim.scoop(at, TOOL_R, SCOOP_RATE)
	# The land's been remade here, so CUT goes from this.
	sim.mark_start_ground(at, TOOL_R + 0.5)

## Scripted input for the checks: the same calls a player's input makes.
func _run_demo(dt: float) -> void:
	demo_clock += dt
	match demo:
		"fillstars":
			# A pipe job past the digging: the trench cut and piped, the water gone, then filled back in a bit at a time. What the
			# player sees at each step: the banner, the FINISH button, and whether it ended by itself.
			var steps := [0.0, 0.5, 0.75, 0.85, 0.95, 1.0]
			var at := int(demo_clock / 1.5)
			if Mission.kind(mission) == "driveway" and _fill_cells.is_empty() and demo_clock > 0.5:
				# A driveway: its cells dusted, a share at a time.
				var r: Rect2 = mission["rect"]
				for j in range(DirtSim.cell_of(r.position).y, DirtSim.cell_of(r.end).y):
					for i in range(DirtSim.cell_of(r.position).x, DirtSim.cell_of(r.end).x):
						_fill_cells.append(Vector2i(i, j))
			if Mission.kind(mission) == "driveway" and not _fill_cells.is_empty() and at < steps.size() and at != _fill_step:
				_fill_step = at
				for k in int(steps[at] * _fill_cells.size()):
					var c: Vector2i = _fill_cells[k]
					var n := c.y * DirtSim.CELLS + c.x
					if sim.dust[n] < Mission.COVERED_MM:
						sim.put(c.x, c.y, Mission.COVERED_MM, Mission.COVERED_MM)
			if _fill_cells.is_empty() and demo_clock > 0.5:
				var from: Vector2 = Mission.source(mission)[0]
				var to: Vector2 = mission["drain"]
				for k in int(from.distance_to(to) / 0.2):
					var c := DirtSim.cell_of(from.lerp(to, k * 0.2 / from.distance_to(to)))
					if not _fill_cells.has(c):
						sim.trench(c, sim.bed[c.y * DirtSim.CELLS + c.x] - 400, 400, c + Vector2i(0, 12))
						_fill_cells.append(c)
				pipe_joined = true
				water_left = 0.0
				if water:
					water.visible = false
			if not _fill_cells.is_empty() and at < steps.size() and at != _fill_step:
				_fill_step = at
				var want := int(steps[at] * _fill_cells.size())
				for k in want:
					var c: Vector2i = _fill_cells[k]
					var n := c.y * DirtSim.CELLS + c.x
					sim.put(c.x, c.y, maxi(sim.start_ground[n] - sim.bed[n] - sim.soil[n], 0))
			if not _fill_cells.is_empty() and fmod(demo_clock, 1.5) > 1.3 and fmod(demo_clock - dt, 1.5) <= 1.3:
				print("FILL %.0f%%: banner \"%s\", FINISH shown %s \"%s\", card %s \"%s / %s\", done %s, stars %d" % [_score() * 100.0, banner.text, buttons["finish"].visible, buttons["finish"].text, star_card.visible, star_title.text, star_note.text, mission_done, stars_got])
				# KEEP GOING tapped at each star till the last, then FINISH, by touch on the card's own buttons.
				if star_card.visible:
					var pick: TouchScreenButton = null
					for c in star_card.get_children():
						if c is TouchScreenButton:
							pick = c
							if _fill_step < 4:
								continue
							break
					var mid: Vector2 = pick.position + pick.scale * 8.0
					_touch(3, mid, true)
					_touch(3, mid, false)
			if demo_clock > 10.0:
				get_tree().quit()
		"pour":
			if demo_clock < 8.0:
				_use_tool(Vector2(-19.0, 1.5), "Drop")
		"both":
			if demo_clock < 14.0:
				_use_tool(Vector2(-19.0, 1.5), "Drop")
			if demo_clock < 10.0:
				_use_tool(Vector2(-24.0, -9.0), "Remove")
		"dig":
			if demo_clock < 6.0:
				_use_tool(Vector2(-24.0, -9.0), "Remove")
		"edge":
			# The owner's glitch: blade down, flat out into the edge of the site, for a long time.
			if demo_clock < dt * 1.5:
				dozer.spot = Vector2(8.0, 16.0)
				dozer.angle = atan2(-1.0, 0.0)
				dozer.lift = -0.2
			dozer.throttle = 1.0
		"reset":
			if demo_clock < dt * 1.5 and not Engine.has_meta("was_reset"):
				Engine.set_meta("was_reset", true)
				print("RESET pressing")
				_pressed.call_deferred("reset")
			elif demo_clock > 0.5:
				dozer.throttle = 1.0
		"levelpile":
			if demo_clock < dt * 1.5:
				dozer.set_level(true)
				_show_level()
			dozer.throttle = 1.0
		"push":
			dozer.throttle = 1.0
		"excavate":
			_excavate_demo()
		"spread":
			# The test bot does the job with the player's controls. It lives with the tests, which never go on the phone.
			if bot == null:
				bot = load("res://test/spread_bot.gd").new(active, sim, mission)
			if not mission_done:
				bot.tick(dt)
			else:
				active.stop_commands()
		"swap":
			if demo_clock < dt * 1.5:
				_swap_machine()
		"scoop":
			(active as Loader).lift_cmd = -1.0 if demo_clock < 1.2 else 0.0
			(active as Loader).curl_cmd = -0.2 if demo_clock < 1.2 else 0.0
			active.throttle = 1.0
		"trench":
			if demo_clock < dt * 1.5:
				dingo.toggle_attachment()
				_show_attach()
			dingo.lift_cmd = -1.0 if demo_clock < 1.4 else 0.0
			dingo.throttle = 1.0
			dingo.steer = 0.25 * sin(demo_clock * 0.25)
		"trenchview":
			# For a picture of the trench gauge: from the start ring toward the drain, then the chain lifted a bit, so a stretch
			# goes uphill and the chain's short of the aim.
			var l := dingo as Loader
			if demo_clock < dt * 1.5:
				_take_machine(l)
				var a: Vector2 = Mission.source(mission)[0] if not mission.is_empty() else l.spot
				var b: Vector2 = mission["drain"] if not mission.is_empty() else l.spot + Vector2(0.0, -8.0)
				l.reposition(a - (b - a).normalized() * 0.75, (b - a).normalized())
				l.toggle_attachment()
				_show_attach()
				_tour_t = -1.0
			l.lift_cmd = -1.0 if demo_clock < 0.6 else (1.0 if demo_clock > 7.0 and demo_clock < 7.4 else 0.0)
			l.throttle = 1.0 if demo_clock < 11.0 else 0.0
		"piperun":
			# Cut a trench, back along it laying pipe, and bury a stretch.
			if demo_clock < dt * 1.5:
				dingo.toggle_attachment()
				_show_attach()
			if demo_clock < 0.7:
				dingo.lift_cmd = -1.0
			elif demo_clock < 26.0:
				dingo.lift_cmd = 0.0
				dingo.throttle = 1.0
			elif demo_clock < 27.0:
				if not dingo.pipe_on:
					dingo.toggle_attachment()
					_show_attach()
				dingo.throttle = 0.0
			elif demo_clock < 42.0:
				dingo.throttle = -1.0
			else:
				dingo.throttle = 0.0
		"tiptruck":
			if demo_clock < dt * 1.5:
				sim.store -= 64000
				sim.held += 64000
				truck.tray_mm = 64000
			if demo_clock > 1.0:
				truck.tip_cmd = 1.0
		"bump":
			if int(demo_clock * 60.0) % 120 == 0:
				print("BUMP at %.1f s: dozer %s, speed %.2f, gap %.2f" % [demo_clock, dozer.spot, dozer.speed, _machine_gap()])
			if demo_clock < dt * 1.5:
				dozer.spot = GroundData.digger_spot() + Vector2(-14.0, 0.0)
				dozer.angle = 0.0
			dozer.throttle = 1.0
		"stall":
			# Straight into the middle of the big pile, blade low.
			dozer.throttle = 1.0
			dozer.lift_cmd = -1.0
			var to_pile := (GroundData.PILE - dozer.spot).normalized()
			var off := wrapf(atan2(-to_pile.y, to_pile.x) - dozer.angle, -PI, PI)
			dozer.steer = clampf(-off * 2.0, -1.0, 1.0)

## One full bite of the pile, swung round and tipped out, over and over: the same calls a player's thumbs make.
func _excavate_demo() -> void:
	var t := fmod(demo_clock, 14.0)
	digger.reach_cmd = 0.0
	digger.raise_cmd = 0.0
	digger.curl_cmd = 0.0
	digger.swing_cmd = 0.0
	if t < 1.6:
		digger.reach_cmd = 1.0
		digger.raise_cmd = 0.6
		digger.curl_cmd = -1.0
	elif t < 3.4:
		digger.raise_cmd = -1.0
	elif t < 6.0:
		digger.reach_cmd = -1.0
		digger.raise_cmd = -0.1
	elif t < 7.2:
		digger.raise_cmd = 1.0
		digger.curl_cmd = 1.0
	elif t < 9.4:
		digger.swing_cmd = -1.0
	elif t < 11.2:
		digger.curl_cmd = -1.0
	elif t < 13.4:
		digger.swing_cmd = 1.0
		digger.curl_cmd = 1.0

## ---------------------------------------------------------------- the buttons and the readout

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	ui.visible = not OS.get_cmdline_user_args().has("--noui")
	var screen := get_viewport().get_visible_rect().size
	var h: float = screen.y
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var font := int(clampf(h / 38.0, 14.0, 36.0))
	var pad := int(h * 0.05)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", int(pad * 0.4))
	for key: String in ["menu", "out", "machine", "mode", "view", "tool", "ink", "grass", "res", "reset", "finish"]:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", font)
		b.custom_minimum_size = Vector2(h * 0.19, h * 0.095)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pressed.bind(key))
		row.add_child(b)
		buttons[key] = b
	buttons["reset"].text = "Reset"
	buttons["out"].text = "Get out"
	# A driveway with a star or more can be called done here; it's shown once there's a star to have.
	buttons["finish"].visible = false
	buttons["finish"].add_theme_color_override("font_color", Color("#ffd23f"))
	buttons["menu"].text = "Menu"
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", int(font * 0.8))
	stats.add_theme_color_override("font_color", Color.WHITE)
	stats.add_theme_color_override("font_outline_color", Color.BLACK)
	stats.add_theme_constant_override("outline_size", 6)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stats)
	top_bar_h = h * 0.13

	# The stick's ring, drawn only while a thumb's on it.
	stick_ui = Control.new()
	stick_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	stick_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_ui.draw.connect(_draw_stick)
	ui.add_child(stick_ui)

	# Big enough to read at a glance on a phone, which the readout isn't.
	alert = Label.new()
	alert.text = "TOO MUCH TO PUSH: back up, raise the blade, or try LEVEL"
	alert.position = Vector2(0.0, h * 0.6)
	alert.size = Vector2(screen.x, h * 0.1)
	alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert.add_theme_font_size_override("font_size", int(h / 22.0))
	alert.add_theme_color_override("font_color", Color("#ffd23f"))
	alert.add_theme_color_override("font_outline_color", Color.BLACK)
	alert.add_theme_constant_override("outline_size", 8)
	alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert.visible = false
	ui.add_child(alert)

	# Real multi-touch buttons: an ordinary Button can't be pressed while the other thumb is on the stick.
	var size: float = h * 0.2
	_touch_button("RAISE", "blade_up", Vector2(screen.x - size - pad, h - size * 2.0 - pad * 1.5), size)
	_touch_button("LOWER", "blade_down", Vector2(screen.x - size - pad, h - size - pad), size)
	_touch_button("GO", "dz_forward", Vector2(screen.x - size * 2.0 - pad * 1.5, h - size * 2.0 - pad * 1.5), size)
	_touch_button("BACK", "dz_back", Vector2(screen.x - size * 2.0 - pad * 1.5, h - size - pad), size)

	# How high the blade is, beside the buttons that move it.
	var top := h - size * 2.0 - pad * 1.5
	var text_h := h * 0.075
	var left := screen.x - size * 2.0 - pad * 2.0 - size * 0.5 - pad * 0.5
	gauge = Control.new()
	gauge.position = Vector2(left, top - text_h)
	gauge.size = Vector2(screen.x - left - pad, h - pad - top + text_h)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	ui.add_child(gauge)

	# The bucket from the side, as from the driver's view the machine often hides it.
	bucket_view = BucketView.new()
	bucket_view.size = Vector2(h * 0.42, h * 0.325)
	bucket_view.position = Vector2(screen.x - bucket_view.size.x - pad, h * 0.135)
	ui.add_child(bucket_view)
	var saved := ConfigFile.new()
	if saved.load(SETTINGS_PATH) == OK:
		side_shown = saved.get_value("view", "side_picture", true)

	var made := _touch_button("LEVEL", "", Vector2(left - size - pad * 0.5, h - size - pad), size)
	level_button = made[0]
	level_word = made[1]
	level_button.pressed.connect(_toggle_level)
	_show_level()
	var cut_at := Vector2(left - size - pad * 0.5, h - size * 2.0 - pad * 1.5)
	var cut_made := _touch_button("", "", cut_at, size)
	cut_button = cut_made[0]
	cut_word = cut_made[1]
	cut_word.position = cut_at + Vector2(size * 0.1, size * 0.25)
	cut_button.pressed.connect(_toggle_cut)
	var small := size * 0.5
	for pair: Array in [["+", 0.0, 1], ["-", small, -1]]:
		var at := Vector2(cut_at.x - small - pad * 0.25, cut_at.y + pair[1])
		var made_small := _touch_button(pair[0], "", at, small)
		made_small[1].position = at + Vector2(small * 0.34, small * 0.08)
		made_small[1].add_theme_font_size_override("font_size", int(small * 0.55))
		var steps: int = pair[2]
		made_small[0].pressed.connect(func(): _change_cut(steps))
	_show_cut()

	# The excavator's own. They sit on the far right, out of the way of the right thumb on the arm.
	_touch_button("CURL", "dig_curl", Vector2(screen.x - size - pad, h - size * 2.0 - pad * 1.5), size, "Excavator")
	_touch_button("DUMP", "dig_dump", Vector2(screen.x - size - pad, h - size - pad), size, "Excavator")
	var left_made := _touch_button("", "", Vector2(pad * 0.4, h * 0.3), size, "Excavator")
	left_button = left_made[0]
	left_word = left_made[1]
	left_word.position = left_button.position + Vector2(size * 0.06, size * 0.3)
	left_word.add_theme_font_size_override("font_size", int(size * 0.135))
	left_button.pressed.connect(_toggle_left)
	_show_left()

	# The buttons the machines share, and the ones the small machines and the truck need.
	touch_buttons[0].set_meta("for", "Dozer,Bobcat,Dingo")
	touch_buttons[1].set_meta("for", "Dozer,Bobcat,Dingo")
	touch_buttons[2].set_meta("for", "Dozer,Truck")
	touch_buttons[3].set_meta("for", "Dozer,Truck")
	var col2 := screen.x - size * 2.0 - pad * 1.5
	_touch_button("CURL", "dig_curl", Vector2(col2, h - size * 2.0 - pad * 1.5), size, "Bobcat,Dingo")
	_touch_button("DUMP", "dig_dump", Vector2(col2, h - size - pad), size, "Bobcat,Dingo")
	_touch_button("TIP", "blade_up", Vector2(screen.x - size - pad, h - size * 1.5 - pad), size, "Truck")
	var attach_made := _touch_button("ATTACH", "", Vector2(left - size - pad * 0.5, h - size - pad), size, "Dingo")
	attach_button = attach_made[0]
	attach_word = attach_made[1]
	attach_word.position = attach_button.position + Vector2(size * 0.06, size * 0.3)
	attach_word.add_theme_font_size_override("font_size", int(size * 0.12))
	attach_button.pressed.connect(_on_attach)
	_show_attach()
	var spread_made := _touch_button("SPREAD", "", Vector2(left - size - pad * 0.5, h - size * 2.0 - pad * 1.5), size, "Bobcat,Dingo")
	spread_button = spread_made[0]
	spread_word = spread_made[1]
	spread_button.pressed.connect(_on_spread)
	_show_spread()
	var side_made := _touch_button("HIDE", "", Vector2.ZERO, h * 0.1, "Dozer,Excavator,Bobcat,Dingo")
	side_button = side_made[0]
	side_word = side_made[1]
	side_word.add_theme_font_size_override("font_size", int(h * 0.028))
	side_button.pressed.connect(_toggle_side)
	_show_side()
	# On foot: the one button, where the right thumb rests, shown when he's by a machine.
	var in_made := _touch_button("", "", Vector2(screen.x - size * 2.0 - pad * 1.5, h - size - pad), size, "On foot")
	get_in_button = in_made[0]
	get_in_word = in_made[1]
	get_in_word.position = get_in_button.position + Vector2(size * 0.08, size * 0.28)
	get_in_word.add_theme_font_size_override("font_size", int(size * 0.14))
	get_in_button.pressed.connect(_get_in)

	# How the job's going, big enough to read while driving.
	banner = Label.new()
	banner.position = Vector2(0.0, top_bar_h)
	banner.size = Vector2(screen.x, h * 0.09)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", int(h / 20.0))
	banner.add_theme_color_override("font_color", Color.WHITE)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = not mission.is_empty()
	ui.add_child(banner)
	_show_banner()
	_build_star_card(screen, h)
	if menu_kind != "":
		_build_menu()
	else:
		# A pipe job opens with a look at where the pipe goes.
		_start_tour.call_deferred()

func _show_banner() -> void:
	# The room code, or who's just joined, isn't to be written over.
	if online and online.is_online() and (_banner_clock > 0.0 or (online.is_host() and not online.live)):
		return
	if banner == null or mission.is_empty():
		return
	if _tour_t >= 0.0:
		banner.text = _tour_words()
		return
	if Mission.kind(mission) != "driveway":
		var flood := Mission.kind(mission) == "flood"
		if not pipe_joined and flood and pipe_connected:
			banner.text = "START THE PIPE DEEPER, UNDER THE WATER" if stop_dry else "DIG DEEPER FROM THE FLAG TO THE DRAIN"
		elif not pipe_joined and not pipe_laid:
			banner.text = "PIPE THE FLOOD DOWNHILL TO THE DRAIN" if flood else "PIPE THE DOWNPIPE TO THE DRAIN"
		elif not pipe_joined:
			# Which end is still to reach, in the hoop's own words.
			banner.text = "PIPE: %s %s   DRAIN %s" % ["WATER" if flood else "DOWNPIPE", "JOINED" if end_reached[0] else "NOT YET", "JOINED" if end_reached[1] else "NOT YET"]
		elif water_left > 0.0:
			banner.text = "JOINED UP! THE LAWN'S DRAINING..."
		else:
			banner.text = _star_words("SPREAD ALONG THE TRENCH", filled)
		return
	banner.text = _star_words(String(mission["title"]).to_upper(), covered)

## How much is done and what that's worth: "DRIVEWAY: 74%   1 STAR, 80% FOR 2".
func _star_words(title: String, done: float) -> String:
	var got := Mission.stars_for(done)
	if got == 0:
		return "%s: %d%%   %d%% FOR 1 STAR" % [title, int(done * 100.0), int(Mission.STARS[0] * 100.0)]
	if got < Mission.STARS.size():
		return "%s: %d%%   %d STAR%s, %d%% FOR %d" % [title, int(done * 100.0), got, "" if got == 1 else "S", int(Mission.STARS[got] * 100.0), got + 1]
	return "%s: %d%%   3 STARS" % [title, int(done * 100.0)]

## How much of the job's done, 0 to 1, for its stars: the driveway covered, or the trench filled back in.
func _score() -> float:
	return covered if Mission.kind(mission) == "driveway" else filled

## Whether the stars can be earned yet: a pipe job needs the water through first.
func _can_score() -> bool:
	return Mission.kind(mission) == "driveway" or (pipe_joined and water_left <= 0.0)

## A whole-screen menu over the site: the jobs and free play at the start, or how a job went at the end of it.
func _build_menu() -> void:
	var h: float = get_viewport().get_visible_rect().size.y
	menu = ColorRect.new()
	(menu as ColorRect).color = Color(0.0, 0.0, 0.0, 0.62)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	# The end of a job has the most on it, so it's drawn a bit smaller to fit.
	var snug := menu_kind in ["done", "start", "host"]
	box.add_theme_constant_override("separation", int(h * (0.016 if snug else 0.025)))
	menu.add_child(box)
	var heading := func(text: String, size: float, colour: Color) -> void:
		var word := Label.new()
		word.text = text
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.add_theme_font_size_override("font_size", int(h * size))
		word.add_theme_color_override("font_color", colour)
		box.add_child(word)
	var choice := func(text: String, enabled: bool, what: Callable) -> void:
		var b := Button.new()
		b.text = text
		b.disabled = not enabled
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(h * 1.15, h * ((0.1 if menu_kind == "start" else 0.115) if snug else 0.14))
		b.add_theme_font_size_override("font_size", int(h * 0.05))
		b.pressed.connect(what)
		box.add_child(b)
	if menu_kind == "start":
		heading.call("DOZER DRIVE", 0.1, Color("#ffd23f"))
		for m: Dictionary in Mission.LIST:
			if Mission.open(m):
				var word := "%s: %s" % [m["title"], m["machine"]]
				if Mission.is_done(m["id"]):
					var best := Mission.stars(m["id"])
					if best == 0:
						word += "   SKIPPED"
					else:
						word += "   %d STAR%s" % [best, "" if best == 1 else "S"]
				if TEST_SKIP and not Mission.is_done(m["id"]):
					_skip_row(box, h, word, String(m["id"]), snug)
				else:
					choice.call(word, true, _start_mission.bind(m["id"]))
			else:
				choice.call("%s: finish %s first" % [m["title"], Mission.find(m["needs"])["title"]], false, _close_menu)
		choice.call("Free play: every machine", true, _start_free_play)
		if Online.available():
			choice.call("Play with a friend", true, _open_menu.bind("online"))
	elif menu_kind == "online":
		heading.call("PLAY WITH A FRIEND", 0.08, Color("#ffd23f"))
		heading.call("One of you hosts and gets a code. The other joins with it.", 0.04, Color.WHITE)
		choice.call("Host a game", true, _open_menu.bind("host"))
		choice.call("Join a game", true, _open_menu.bind("join"))
		choice.call("Back", true, _open_menu.bind("start"))
	elif menu_kind == "host":
		heading.call("WHAT WILL YOU PLAY?", 0.08, Color("#ffd23f"))
		for m: Dictionary in Mission.LIST:
			if Mission.open(m):
				choice.call("%s: two %ss" % [m["title"], m["machine"]], true, _host_job.bind(m["id"]))
		choice.call("Free play: every machine", true, _host_game)
		choice.call("Back", true, _open_menu.bind("online"))
	elif menu_kind == "join":
		_build_join_menu(box, h)
	elif menu_kind == "ended":
		heading.call("THE HOST HAS GONE", 0.08, Color("#ffd23f"))
		choice.call("Menu", true, _pressed.bind("menu"))
	else:
		heading.call("%s DONE" % String(mission["title"]).to_upper(), 0.085, Color("#ffd23f"))
		heading.call("%d STAR%s OF 3" % [stars_got, "" if stars_got == 1 else "S"], 0.06, Color.WHITE)
		if mission["done"] != "":
			heading.call(mission["done"], 0.055, Color("#a8f07a"))
		var next := Mission.after(mission)
		if not next.is_empty():
			if online.is_guest():
				heading.call("The host picks what's next", 0.05, Color.WHITE)
			else:
				choice.call("Next job: %s" % next["title"], true, _start_mission.bind(next["id"]))
		if stars_got < 3 and not online.is_guest():
			choice.call("Try again for 3 stars", true, _start_mission.bind(mission["id"]))
		choice.call("Keep working", true, _close_menu)
		choice.call("Menu", true, _pressed.bind("menu"))
	_show_buttons()
	stick_ui.queue_redraw()

## A job in the list with a SKIP beside it, which has to be held down.
func _skip_row(box: VBoxContainer, h: float, word: String, id: String, snug: bool) -> void:
	var tall := h * (0.1 if snug else 0.14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(h * 0.02))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var go := Button.new()
	go.text = word
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(h * 0.91, tall)
	go.add_theme_font_size_override("font_size", int(h * 0.05))
	go.pressed.connect(_start_mission.bind(id))
	row.add_child(go)
	var skip := Button.new()
	skip.text = "HOLD TO SKIP"
	skip.focus_mode = Control.FOCUS_NONE
	skip.custom_minimum_size = Vector2(h * 0.22, tall)
	skip.add_theme_font_size_override("font_size", int(h * 0.026))
	skip.add_theme_color_override("font_color", Color("#ff9a4a"))
	skip.button_down.connect(func() -> void:
		_skip_id = id
		_skip_button = skip
		_skip_held = 0.0)
	skip.button_up.connect(func() -> void:
		_skip_held = -1.0
		skip.text = "HOLD TO SKIP")
	row.add_child(skip)

func _open_menu(kind: String) -> void:
	if kind != "join":
		join_code = ""
	if online.role == "joining":
		online.leave()
	if menu != null:
		menu.queue_free()
	menu_kind = kind
	_build_menu()

## Typing a room code on a phone: the game's own keys, as the phone's keyboard doesn't come up for a web game.
func _build_join_menu(box: VBoxContainer, h: float) -> void:
	var add_line := func(text: String, size: float, colour: Color) -> Label:
		var line := Label.new()
		line.text = text
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", int(h * size))
		line.add_theme_color_override("font_color", colour)
		box.add_child(line)
		return line
	box.add_theme_constant_override("separation", int(h * 0.012))
	join_word = add_line.call("ROOM CODE", 0.08, Color("#ffd23f"))
	join_status = add_line.call("", 0.035, Color.WHITE)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", int(h * 0.012))
	grid.add_theme_constant_override("v_separation", int(h * 0.012))
	box.add_child(grid)
	var key := func(text: String, what: Callable) -> void:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(h * 0.145, h * 0.135)
		b.add_theme_font_size_override("font_size", int(h * 0.05))
		b.pressed.connect(what)
		grid.add_child(b)
	for k in Online.ABC.length():
		key.call(Online.ABC[k], _join_key.bind(Online.ABC[k]))
	key.call("<", _join_key.bind("<"))
	key.call("Back", _open_menu.bind("online"))
	_show_join()

func _join_key(k: String) -> void:
	if k == "<":
		join_code = join_code.left(-1)
		if online.role == "joining":
			online.leave()
			online.status_text = ""
	elif join_code.length() < 4:
		join_code += k
		if join_code.length() == 4:
			online.join(join_code)
	_show_join()

func _show_join() -> void:
	if join_word:
		join_word.text = "ROOM  " + (join_code + "____").left(4)
		join_status.text = online.status_text if online.status_text != "" else "Type the code your friend's game is showing"

## Opens the room, then starts the job: the room goes with it, and the friend's game follows when they join.
func _host_job(id: String) -> void:
	online.host(online_arg.substr(5) if online_arg.begins_with("host:") else "")
	_start_mission(id)

## The host's in another job now, so this game goes there too.
func online_go_to(id: String) -> void:
	# Sent straight on to the job this one unlocks: this one's done, even if the word never got here.
	if demo == "" and not mission.is_empty() and Mission.find(id).get("needs", "") == mission["id"]:
		Mission.mark_done(mission["id"])
	if id != "":
		_start_mission(id)
		return
	Engine.remove_meta("mission")
	Engine.set_meta("free_play", true)
	online.carry_over()
	get_tree().reload_current_scene()

## The world behind the first menu is free play already, so a host just gets on with it and the room's open while it does.
func _host_game() -> void:
	if mission.is_empty():
		_start_free_play()
	online.host(online_arg.substr(5) if online_arg.begins_with("host:") else "")
	_online_bar()
	online_changed()

func _online_from_arg() -> void:
	if online_arg.begins_with("host"):
		_host_game()
	elif online_arg.begins_with("join:"):
		online.join(online_arg.substr(5))

## Reset and the Dirt tools would pull the ground out from under the other player.
func _online_bar() -> void:
	for key: String in ["mode", "tool", "reset"]:
		buttons[key].visible = false

## Something changed about the connection: the words on screen.
func online_changed() -> void:
	if menu_kind == "join":
		_show_join()
	if banner == null or not online.is_online() or online.role == "joining":
		return
	_banner_clock = 0.0
	banner.visible = true
	if online.role == "host" and not online.live:
		if online.status_bad or online.code == "":
			banner.text = online.status_text
		else:
			banner.text = "ROOM %s   WAITING FOR PLAYER 2" % online.code
	elif online.role == "host":
		banner.text = "PLAYER 2 JOINED: IN THE %s" % String(machines[online.drivers[1]].machine_name).to_upper()
		_banner_clock = 6.0
	else:
		banner.text = "CONNECTED: YOU ARE PLAYER 2"
		_banner_clock = 6.0

## Connected as a guest: into the game, in whichever machine the host says.
func online_joined() -> void:
	Engine.set_meta("free_play", true)
	join_word = null
	join_status = null
	_close_menu()
	_online_bar()

func online_ended() -> void:
	mode = "Drive"
	_open_menu("ended")

func online_my_machine(k: int) -> void:
	if machines[k] != active:
		_take_machine(machines[k])

## A button pressed on another player's game, for the machine they're in.
func online_action(player: int, what: String, arg: int) -> void:
	if player >= online.drivers.size():
		return
	var m: Machine = machines[online.drivers[player]]
	match what:
		"swap":
			online.swap_for(player)
		"out":
			_get_out_for(player)
		"in":
			_get_in_for(player)
		"level":
			if m == dozer:
				dozer.set_level(not dozer.level_on)
		"cut":
			if m == dozer:
				dozer.set_cut(not dozer.cut_on)
		"depth":
			if m == dozer:
				dozer.change_cut(arg)
		"spread":
			if m is Loader:
				(m as Loader).toggle_spread()
		"attach":
			if m is Loader and m.machine_name == Loader.DINGO:
				(m as Loader).toggle_attachment()
		"left":
			if m == digger:
				digger.dig_mode = not digger.dig_mode
				digger.stop_commands()

## What the host's word has done to the machine's buttons.
func _guest_buttons() -> void:
	var small := _my_dingo()
	var now := "%s %s %s %s %s %s" % [dozer.level_on, dozer.cut_on, dozer.cut_cm, small.trencher_on, small.pipe_on, digger.dig_mode]
	if now != _guest_ui:
		_guest_ui = now
		_show_level()
		_show_cut()
		_show_attach()
		_show_left()
		stick_ui.queue_redraw()

func _close_menu() -> void:
	menu_kind = ""
	banner.visible = not mission.is_empty()
	if menu != null:
		menu.queue_free()
		menu = null
	_show_buttons()
	stick_ui.queue_redraw()

func _start_mission(id: String) -> void:
	if Engine.has_meta("free_play"):
		Engine.remove_meta("free_play")
	Engine.set_meta("mission", id)
	if online.is_online():
		online.carry_over()
	get_tree().reload_current_scene()

## The world behind the first menu is already free play, so it only has to get out of the way.
func _start_free_play() -> void:
	Engine.set_meta("free_play", true)
	if mission.is_empty():
		_close_menu()
	else:
		Engine.remove_meta("mission")
		get_tree().reload_current_scene()

## Every so often: how much of the driveway's done, and whether that's the job finished.
func _check_mission(delta: float) -> void:
	mission_clock -= delta
	if mission_clock > 0.0:
		return
	mission_clock = 0.25
	if Mission.kind(mission) != "driveway":
		pipes.settle(sim)
		if not pipe_joined:
			var run := Mission.pipe_run(pipes.points(), mission)
			pipe_connected = not run.is_empty()
			pipe_laid = pipes.segments() > 0
			end_reached = Mission.ends_reached(pipes.points(), mission)
			var stops := Mission.water_stops_at(run, mission)
			stop_at = stops
			# Stopped where it goes in, as that's above the water, rather than at a rise further on.
			stop_dry = stops >= 0 and run[stops].y > Mission.water_y(mission) and (stops == 0 or run[stops].y <= run[stops - 1].y + Mission.FALL_SLACK)
			if pipe_connected and stops < 0:
				pipe_joined = true
				sfx.clunked(0.8)
				Input.vibrate_handheld(120)
				_add_joins(run)
			_show_end_marks(end_reached)
			_show_stop_flag(run[stops] if pipe_connected and stops >= 0 else null)
		filled = Mission.filled_in(sim, mission)
	else:
		covered = Mission.coverage(sim, mission)
	_show_banner()
	var can_finish := not mission_done and not online.is_guest() and menu == null and _can_score() and Mission.stars_for(_score()) > 0
	buttons["finish"].visible = can_finish
	if can_finish:
		var n := Mission.stars_for(_score())
		buttons["finish"].text = "FINISH: %d STAR%s" % [n, "" if n == 1 else "S"]
	# Each new star, the choice: finish with it, or keep going. Nothing ends by itself, not even at three. With a friend it's the
	# host who says, so both finish together.
	var got := Mission.stars_for(_score()) if can_finish else 0
	if got > _stars_offered:
		_stars_offered = got
		_star_up = true
		star_title.text = "%d STAR%s!" % [got, "" if got == 1 else "S"]
		star_note.text = "Finish now, or keep going for %d%%" % int(Mission.STARS[got] * 100.0) if got < Mission.STARS.size() else "Finish now, or keep going to tidy up"
		sfx.clunked(0.5)
		Input.vibrate_handheld(60)
	_show_star_card()

## The card that comes up with each new star: big enough to hit while driving, and it doesn't stop anything.
func _build_star_card(screen: Vector2, h: float) -> void:
	star_card = Control.new()
	star_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(star_card)
	var w := h * 0.95
	var left := (screen.x - w) * 0.5
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.5)
	back.position = Vector2(left, h * 0.225)
	back.size = Vector2(w, h * 0.29)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_card.add_child(back)
	star_title = _card_label(Vector2(left, h * 0.23), Vector2(w, h * 0.08), int(h / 14.0), Color("#ffd23f"))
	star_note = _card_label(Vector2(left, h * 0.31), Vector2(w, h * 0.045), int(h / 30.0), Color.WHITE)
	var bw := w * 0.44
	# Clear of the buttons below it, so a tap on the card can't press one of them too.
	var bh := h * 0.13
	var top := h * 0.365
	_card_button("FINISH", Vector2(left + w * 0.04, top), Vector2(bw, bh), Color(0.86, 0.62, 0.08, 0.92), h, _on_star_finish)
	_card_button("KEEP GOING", Vector2(left + w * 0.52, top), Vector2(bw, bh), Color(0.12, 0.12, 0.12, 0.85), h, _on_star_keep)
	star_card.visible = false

func _card_label(at: Vector2, size: Vector2, font: int, colour: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_card.add_child(l)
	return l

## A real multi-touch button, so it works with the other thumb still on the stick.
func _card_button(text: String, at: Vector2, size: Vector2, colour: Color, h: float, on_press: Callable) -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	var b := TouchScreenButton.new()
	b.texture_normal = ImageTexture.create_from_image(img)
	b.scale = size / 16.0
	b.position = at
	b.pressed.connect(on_press)
	star_card.add_child(b)
	var l := _card_label(at, size, int(h / 22.0), Color.WHITE)
	l.text = text

func _show_star_card() -> void:
	if star_card:
		star_card.visible = _star_up and not mission_done and menu == null and not online.is_guest()

func _on_star_finish() -> void:
	if star_card.visible and not mission_done and _can_score() and Mission.stars_for(_score()) > 0:
		finish_mission()

func _on_star_keep() -> void:
	if star_card.visible:
		_star_up = false
		_show_star_card()

## A SKIP in the job list held long enough: that job's counted done but with no stars, and the list's drawn again with the next open.
func _hold_skip(delta: float) -> void:
	if _skip_held < 0.0:
		return
	if _skip_button == null or not is_instance_valid(_skip_button):
		_skip_held = -1.0
		return
	_skip_held += delta
	_skip_button.text = "%d%%" % int(minf(_skip_held / SKIP_HOLD_S, 1.0) * 100.0)
	if _skip_held < SKIP_HOLD_S:
		return
	_skip_held = -1.0
	Mission.mark_done(_skip_id, 0)
	print("SKIPPED %s" % _skip_id)
	_open_menu("start")

func finish_mission() -> void:
	mission_done = true
	buttons["finish"].visible = false
	_star_up = false
	_show_star_card()
	stars_got = Mission.stars_for(_score())
	# Checks and demos leave the real save alone.
	if demo == "":
		Mission.mark_done(mission["id"], stars_got)
	sfx.clunked(1.0)
	Input.vibrate_handheld(200)
	print("MISSION DONE: %s at %.1f%%" % [mission["id"], _score() * 100.0])
	active.stop_commands()
	if shot_path != "":
		shot_wait = mini(shot_wait, 20)
	menu_kind = "done"
	banner.visible = false
	_build_menu()

## Puts the side-on picture away, or brings it back. It stays how it's left, next time as well.
func _toggle_side() -> void:
	side_shown = not side_shown
	var saved := ConfigFile.new()
	saved.load(SETTINGS_PATH)
	saved.set_value("view", "side_picture", side_shown)
	saved.save(SETTINGS_PATH)
	_show_side()
	_show_buttons()

## Beside the picture while it's open, and in its corner when it's away.
func _show_side() -> void:
	var size: float = side_button.get_meta("size")
	var right := bucket_view.position.x + bucket_view.size.x
	side_button.position = Vector2(bucket_view.position.x - size - size * 0.08, bucket_view.position.y) if side_shown else Vector2(right - size, bucket_view.position.y)
	side_word.text = "HIDE" if side_shown else "SHOW"
	side_word.position = side_button.position + Vector2(size * 0.12, size * 0.32)

func _on_spread() -> void:
	if online.is_guest():
		online.ask("spread")
		return
	if active is Loader:
		(active as Loader).toggle_spread()
	_show_spread()

## SPREAD, or with the trencher on, GRADE: the word, and whether it's on.
func _spread_label() -> String:
	if not active is Loader:
		return "SPREAD"
	var l := active as Loader
	if l.trencher_on:
		return "GRADE ON" if l.grade_on else "GRADE"
	return "SPREAD ON" if l.spread_on else "SPREAD"

func _show_spread() -> void:
	var word := _spread_label()
	_spread_shown = word.ends_with(" ON")
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.55, 0.15, 0.85) if _spread_shown else Color(0.1, 0.1, 0.1, 0.55))
	spread_button.texture_normal = ImageTexture.create_from_image(img)
	spread_word.text = word

func _on_attach() -> void:
	if online.is_guest():
		online.ask("attach")
		return
	_my_dingo().toggle_attachment()
	_show_attach()

## The Dingo this player's in. On a job with a friend there are two.
func _my_dingo() -> Loader:
	return active as Loader if active is Loader and active.machine_name == Loader.DINGO else dingo

func _show_attach() -> void:
	if attach_word:
		var small := _my_dingo()
		attach_word.text = "NOW: TRENCH\ntap for PIPE" if small.trencher_on else ("NOW: PIPE\ntap for BUCKET" if small.pipe_on else "NOW: BUCKET\ntap for TRENCH")
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.75, 0.3, 0.1, 0.85) if small.trencher_on else (Color(0.15, 0.4, 0.7, 0.85) if small.pipe_on else Color(0.1, 0.1, 0.1, 0.55)))
		attach_button.texture_normal = ImageTexture.create_from_image(img)

func _touch_button(text: String, action: String, at: Vector2, size: float, for_who := "Dozer") -> Array:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.1, 0.55))
	var b := TouchScreenButton.new()
	b.texture_normal = ImageTexture.create_from_image(img)
	b.scale = Vector2.ONE * (size / 16.0)
	b.position = at
	b.action = action
	b.set_meta("size", size)
	b.set_meta("for", for_who)
	b.set_meta("label", text)
	ui.add_child(b)
	var word := Label.new()
	word.text = text
	word.position = at + Vector2(size * 0.14, size * 0.36)
	word.add_theme_font_size_override("font_size", int(size * 0.17))
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(word)
	b.visibility_changed.connect(func(): word.visible = b.visible)
	touch_buttons.append(b)
	return [b, word]

func _toggle_level() -> void:
	if online.is_guest():
		online.ask("level")
		return
	dozer.set_level(not dozer.level_on)
	_show_level()
	_show_cut()

func _toggle_cut() -> void:
	if online.is_guest():
		online.ask("cut")
		return
	dozer.set_cut(not dozer.cut_on)
	_show_cut()
	_show_level()

func _change_cut(steps: int) -> void:
	if online.is_guest():
		online.ask("depth", steps)
		return
	dozer.change_cut(steps)
	_show_cut()

func _show_cut() -> void:
	_cut_shown = dozer.cut_on
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.55, 0.15, 0.85) if dozer.cut_on else Color(0.1, 0.1, 0.1, 0.55))
	cut_button.texture_normal = ImageTexture.create_from_image(img)
	cut_word.text = "CUT %s\n%d cm" % ["ON" if dozer.cut_on else "OFF", dozer.cut_cm]

func _show_level() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.55, 0.15, 0.85) if dozer.level_on else Color(0.1, 0.1, 0.1, 0.55))
	level_button.texture_normal = ImageTexture.create_from_image(img)
	level_word.text = "LEVEL ON" if dozer.level_on else "LEVEL OFF"

## A side-on picture: the blade against the ground under its edge, so a pile rising over it shows too.
func _draw_gauge() -> void:
	if active != dozer:
		_draw_bucket_gauge()
		return
	var h: float = get_viewport().get_visible_rect().size.y
	var text_h := h * 0.075
	var font_size := int(h * 0.05)
	var gap := dozer.edge_gap
	var word := "BLADE ON GROUND"
	var colour := Color("#ffd23f")
	if gap > 0.06:
		word = "BLADE UP %.2f m" % gap
		colour = Color("#a8f07a")
	elif gap < -0.06:
		word = "BLADE IN DIRT %.2f m" % -gap
		colour = Color("#ff9a4a")
	if dozer.cut_on:
		word = "CUT %d cm: DRIVE" % dozer.cut_cm
	var font := ThemeDB.fallback_font
	gauge.draw_string_outline(font, Vector2(0.0, text_h * 0.72), word, HORIZONTAL_ALIGNMENT_RIGHT, gauge.size.x, font_size, 8, Color.BLACK)
	gauge.draw_string(font, Vector2(0.0, text_h * 0.72), word, HORIZONTAL_ALIGNMENT_RIGHT, gauge.size.x, font_size, colour)
	if side_shown:
		return
	# The picture spans a bit more than the blade's travel.
	var panel := Rect2(0.0, text_h, h * 0.1, gauge.size.y - text_h)
	var low := Dozer.LIFT_MIN - 0.3
	var high := Dozer.LIFT_MAX + 0.15
	var y_of := func(l: float) -> float:
		return panel.position.y + panel.size.y * (1.0 - clampf((l - low) / (high - low), 0.0, 1.0))
	gauge.draw_rect(panel, Color(0.1, 0.1, 0.1, 0.55))
	var ground_y: float = y_of.call(gauge_ground)
	gauge.draw_rect(Rect2(panel.position.x, ground_y, panel.size.x, panel.end.y - ground_y), Color("#7d4329"))
	gauge.draw_line(Vector2(panel.position.x, ground_y), Vector2(panel.end.x, ground_y), Color.BLACK, 2.0)
	var blade_y: float = y_of.call(dozer.lift)
	var blade_h := panel.size.y * 0.09
	var blade := Rect2(panel.position.x + panel.size.x * 0.15, blade_y - blade_h, panel.size.x * 0.7, blade_h)
	gauge.draw_rect(blade, colour)
	gauge.draw_rect(blade, Color.BLACK, false, 2.0)

## What's in the bucket and how deep its teeth are.
func _draw_bucket_gauge() -> void:
	var h: float = get_viewport().get_visible_rect().size.y
	var text_h := h * 0.075
	var font_size := int(h * 0.05)
	var said: Array = active.gauge_word()
	var word: String = said[0]
	var colour: Color = said[1]
	var font := ThemeDB.fallback_font
	var at := Vector2(gauge.size.x - font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x, text_h * 0.72)
	gauge.draw_string_outline(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 8, Color.BLACK)
	gauge.draw_string(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)

## A ring where a thumb goes, its name in the middle.
func _draw_rest(at: Vector2, reach: float, text: String) -> void:
	var h: float = get_viewport().get_visible_rect().size.y
	var font := ThemeDB.fallback_font
	var size := int(h * 0.04)
	var word_at := at + Vector2(-reach, size * 0.35)
	stick_ui.draw_arc(at, reach, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	stick_ui.draw_string_outline(font, word_at, text, HORIZONTAL_ALIGNMENT_CENTER, reach * 2.0, size, 6, Color(0, 0, 0, 0.6))
	stick_ui.draw_string(font, word_at, text, HORIZONTAL_ALIGNMENT_CENTER, reach * 2.0, size, Color.WHITE)

## The second ring, with which way does what round its edge, as nothing else on screen says.
func _draw_arm_ring(at: Vector2, reach: float) -> void:
	var h: float = get_viewport().get_visible_rect().size.y
	var font := ThemeDB.fallback_font
	var size := int(h * 0.032)
	for pair: Array in [["UP", Vector2(0.0, -1.0)], ["DOWN", Vector2(0.0, 1.0)], ["IN", Vector2(-1.0, 0.0)], ["OUT", Vector2(1.0, 0.0)]]:
		var p: Vector2 = at + (pair[1] as Vector2) * reach * 1.28 + Vector2(-reach * 0.5, size * 0.35)
		stick_ui.draw_string_outline(font, p, pair[0], HORIZONTAL_ALIGNMENT_CENTER, reach, size, 6, Color(0, 0, 0, 0.7))
		stick_ui.draw_string(font, p, pair[0], HORIZONTAL_ALIGNMENT_CENTER, reach, size, Color("#ffd23f"))

func _draw_stick() -> void:
	if mode != "Drive" or menu != null:
		return
	var h: float = get_viewport().get_visible_rect().size.y
	var reach: float = h * 0.14
	if _two_sticks():
		var w: float = get_viewport().get_visible_rect().size.x
		var arm_rest := Vector2(w - h * 0.66, h * 0.68)
		if stick2_finger < 0:
			_draw_rest(arm_rest, reach, "ARM")
			_draw_arm_ring(arm_rest, reach)
		else:
			stick_ui.draw_arc(stick2_from, reach, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 3.0)
			stick_ui.draw_circle(stick2_from + (stick2_at - stick2_from).limit_length(reach), reach * 0.38, Color(1, 1, 1, 0.45))
			_draw_arm_ring(stick2_from, reach)
		if stick_finger < 0:
			_draw_rest(Vector2(h * 0.32, h * 0.7), reach, "SWING")
			return
	if stick_finger < 0:
		# Where to put a thumb. The stick starts wherever the thumb lands on the left half, so this is only a sign.
		var rest := Vector2(h * 0.32, h * 0.7)
		var font := ThemeDB.fallback_font
		var size := int(h * 0.04)
		var at := rest + Vector2(-reach, size * 0.35)
		stick_ui.draw_arc(rest, reach, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
		stick_ui.draw_string_outline(font, at, "DRIVE", HORIZONTAL_ALIGNMENT_CENTER, reach * 2.0, size, 6, Color(0, 0, 0, 0.6))
		stick_ui.draw_string(font, at, "DRIVE", HORIZONTAL_ALIGNMENT_CENTER, reach * 2.0, size, Color.WHITE)
		return
	stick_ui.draw_arc(stick_from, reach, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 3.0)
	stick_ui.draw_circle(stick_from + (stick_at - stick_from).limit_length(reach), reach * 0.38, Color(1, 1, 1, 0.45))

func _pressed(key: String) -> void:
	match key:
		"out":
			_get_out()
		"machine":
			_swap_machine()
		"mode":
			_set_mode(_next(MODES, mode))
		"view":
			_set_view(_next(VIEWS[mode], view))
		"tool":
			tool_name = "Remove" if tool_name == "Drop" else "Drop"
			_label("tool", "Tool: " + tool_name)
		"ink":
			_set_ink(_next(INK_NAMES, ink))
		"grass":
			_set_grass(_next(GRASS_NAMES, grass))
		"res":
			_set_res((res_i + 1) % RES_STEPS.size())
		"reset":
			get_tree().reload_current_scene()
		"finish":
			if not mission.is_empty() and not mission_done and _can_score() and Mission.stars_for(_score()) > 0 and not online.is_guest():
				finish_mission()
		"menu":
			online.leave()
			for meta_name: String in ["mission", "free_play"]:
				if Engine.has_meta(meta_name):
					Engine.remove_meta(meta_name)
			get_tree().reload_current_scene()
	worst = 999.0

func _soil_line() -> String:
	var text := "Soil: %.1f m3 loose   %.1f in hand   %.1f in the air   %.1f in the bucket   " % [DirtSim.to_m3(sim.loose_total_cached), DirtSim.to_m3(sim.store), DirtSim.to_m3(sim.in_air), DirtSim.to_m3(sim.held)]
	text += "total unchanged" if total_ok else "TOTAL CHANGED BY %d" % (last_total - start_total)
	return text

func _process(delta: float) -> void:
	var t1 := Time.get_ticks_usec()
	view_data.sync(delta)
	_clod_wait -= delta
	if _clod_wait <= 0.0:
		_clod_wait = 0.2
		_update_clods()
	_update_fades(delta)
	cost_sync = Time.get_ticks_usec() - t1
	var fps := 1.0 / maxf(delta, 0.0001)
	worst_clock += delta
	if worst_clock > 5.0:
		worst_clock = 0.0
		worst = 999.0
	worst = minf(worst, fps)
	total_clock += delta
	if total_clock >= CHECK_TOTAL_EVERY:
		total_clock = 0.0
		last_total = sim.total()
		sim.loose_total_cached = sim.loose_total()
		total_ok = last_total == start_total or online.is_guest()
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var size := get_viewport().get_visible_rect().size * get_viewport().scaling_3d_scale
	var lines := "%d FPS   worst %d   %dk triangles   %d x %d   %s\n" % [Engine.get_frames_per_second(), int(worst), tris / 1000, int(size.x), int(size.y), RenderingServer.get_video_adapter_name()]
	lines += _soil_line() + "   %d chunks moving
Dirt code: %.1f ms a tick, %.1f ms redrawing" % [sim.awake_count(), cost_physics * 0.001, cost_sync * 0.001]
	if mode == "Drive":
		lines += "\n%.1f km/h   %s %.1f t   moved %.0f m3   trees down %d of %d" % [absf(active.speed) * 3.6, "blade load" if active == dozer else "load", active.load_t, active.moved_m3, trees.down, trees.list.size()]
		if active.slipping:
			lines += "   TRACKS SLIPPING"
		if active.on_rock:
			lines += "   ON ROCK"
		if not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")):
			if active == digger:
				lines += "\nA D swing (T: W A S D drive)   arrows move the arm   U curl   O dump   M swap machine"
			elif active == truck:
				lines += "\nW A S D drive   E hold to tip   M swap machine"
			elif active != dozer:
				lines += "\nW A S D drive   E raise   Q lower   U curl   O dump   G attachment   M swap machine"
			else:
				lines += "\nW A S D drive   Q lower blade   E raise blade   L level   M swap machine   right drag looks"
	# A moment's stall is part of the work. It only says so when it's really stuck, or at the fence.
	hint_time = maxf(hint_time - delta, 0.0)
	alert.text = "EDGE OF THE SITE: turn round" if active.at_edge else active.stuck_word
	alert.visible = mode == "Drive" and (slip_time > 1.2 or (active.at_edge and absf(active.throttle) > 0.3))
	if mode == "Drive" and hint_time > 0.0:
		alert.text = active.hint
		alert.visible = true
	if mode == "Drive":
		gauge_ground = lerpf(gauge_ground, dozer.lift - dozer.edge_gap, minf(delta * 8.0, 1.0))
		gauge.queue_redraw()
		bucket_view.machine = active
		bucket_view.truck = truck if machines.has(truck) else null
		bucket_view.water_y = water.position.y if water != null and water.visible and Mission.kind(mission) == "flood" else NAN
		bucket_view.queue_redraw()
	stats.text = lines
	if menu != null:
		alert.visible = false
	_hold_skip(delta)
	_tour_step(delta)
	if _tour_t >= 0.0:
		banner.text = _tour_words()
	if not end_marks.is_empty():
		_wave_end_marks(delta)
	if not mission.is_empty():
		_check_mission(delta)
		_drain_flood(delta)
		_update_floaters(delta)
	if _banner_clock > 0.0:
		_banner_clock -= delta
		if _banner_clock <= 0.0:
			banner.visible = not mission.is_empty()
			_show_banner()
	if shot_path != "":
		shot_wait -= 1
		if shot_wait <= 0:
			_take_shot()

func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	var exact := sim.total()
	print("SHOT %s" % shot_path)
	print(stats.text)
	print("total exact: %d, start %d, %s" % [exact, start_total, "SAME" if exact == start_total else "CHANGED"])
	print("physics %.2f ms, frame %.2f ms" % [Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	print("dozer at %s speed %.2f load %.1f t slipping %s rock %s moved %.1f m3" % [dozer.spot, dozer.speed, dozer.load_t, dozer.slipping, dozer.on_rock, dozer.moved_m3])
	print("digger at %s swing %.2f bucket %.2f m3 teeth %s moved %.1f m3 now in %s, gap %.2f" % [digger.spot, digger.swing, DirtSim.to_m3(digger.bucket_mm), digger.teeth, digger.moved_m3, active.name, _machine_gap()])
	get_tree().quit()

## ---------------------------------------------------------------- input checks

var _touch_tick := 0

func _touch(index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	Input.parse_input_event(e)

func _drag(index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	Input.parse_input_event(e)

func _click(at: Vector2) -> void:
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = down
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(e)

## Sends what a phone would send, then says what came of it: a thumb on the stick with another on RAISE, a finger on the dirt
## tool, or clicks on the menu buttons.
func _run_touch_demo() -> void:
	_touch_tick += 1
	var s := get_viewport().get_visible_rect().size
	match demo:
		"touchdig":
			# The excavator: a thumb on each half of the screen, then the button that swaps the left thumb over to the tracks.
			var left_thumb := s * Vector2(0.2, 0.7)
			var right_thumb2 := s * Vector2(0.62, 0.7)
			var reach2: float = s.y * 0.14
			var dump: Node2D = touch_buttons[6]
			var on_dump: Vector2 = dump.position + Vector2.ONE * dump.get_meta("size") * 0.5
			var on_left: Vector2 = left_button.position + Vector2.ONE * left_button.get_meta("size") * 0.5
			if _touch_tick == 20:
				_touch(0, left_thumb, true)
				_touch(1, right_thumb2, true)
			elif _touch_tick == 22:
				_drag(0, left_thumb + Vector2(reach2, 0.0))
				_drag(1, right_thumb2 + Vector2(reach2, -reach2 * 0.3))
			elif _touch_tick == 100:
				print("TOUCH dig: swing cmd %.2f (house at %.2f), reach cmd %.2f raise cmd %.2f, wrist %s, tracks throttle %.2f" % [digger.swing_cmd, digger.swing, digger.reach_cmd, digger.raise_cmd, digger.wrist, digger.throttle])
				_touch(0, left_thumb, false)
				_touch(1, right_thumb2, false)
			elif _touch_tick == 110:
				print("TOUCH let go: swing cmd %.2f reach cmd %.2f" % [digger.swing_cmd, digger.reach_cmd])
				_touch(0, on_dump, true)
			elif _touch_tick == 150:
				print("TOUCH dump held: curl cmd %.2f, curl %.2f" % [digger.curl_cmd, digger.curl])
				_touch(0, on_dump, false)
			elif _touch_tick == 155:
				_touch(0, on_left, true)
			elif _touch_tick == 160:
				_touch(0, on_left, false)
				print("TOUCH left button: dig mode %s, %s" % [digger.dig_mode, left_word.text.replace("
", " / ")])
			elif _touch_tick == 165:
				_touch(0, s * Vector2(0.7, 0.5), true)
			elif _touch_tick == 167:
				_drag(0, s * Vector2(0.7, 0.5) + Vector2(0.0, -reach2))
			elif _touch_tick == 300:
				print("TOUCH tracks, finger on the right: throttle %.2f, went %.1f m" % [digger.throttle, digger.spot.distance_to(GroundData.digger_spot())])
		"touchfleet":
			# Round all five machines with the button, checking each one shows its own controls; then the Dingo's trencher by touch.
			var shown := func() -> String:
				var names := []
				for b in touch_buttons:
					if b.visible:
						names.append(b.get_meta("label", "?"))
				return ", ".join(names)
			if _touch_tick in [20, 30, 40, 50, 60]:
				print("FLEET now %s: %s | %s" % [active.machine_name, shown.call(), active.gauge_word()[0]])
				if _touch_tick < 60:
					_click(buttons["machine"].get_global_rect().get_center())
			elif _touch_tick == 70:
				var on_attach: Vector2 = attach_button.position + Vector2.ONE * attach_button.get_meta("size") * 0.5
				_touch(0, on_attach, true)
			elif _touch_tick == 75:
				var off_attach: Vector2 = attach_button.position + Vector2.ONE * attach_button.get_meta("size") * 0.5
				_touch(0, off_attach, false)
				print("FLEET attach: trencher %s, %s" % [dingo.trencher_on, attach_word.text.replace("\n", " / ")])
			elif _touch_tick == 80:
				var low: Node2D = touch_buttons[1]
				_touch(1, low.position + Vector2.ONE * low.get_meta("size") * 0.5, true)
			elif _touch_tick == 150:
				var low2: Node2D = touch_buttons[1]
				_touch(1, low2.position + Vector2.ONE * low2.get_meta("size") * 0.5, false)
				print("FLEET lower: chain %.2f m, %s" % [dingo.chain_depth, dingo.gauge_word()[0]])
				_touch(2, s * Vector2(0.25, 0.7), true)
			elif _touch_tick == 152:
				_drag(2, s * Vector2(0.25, 0.7) + Vector2(0.0, -s.y * 0.14))
			elif _touch_tick == 500:
				print("FLEET cutting: throttle %.2f, went %.1f m, speed %.2f, trench %.1f m" % [dingo.throttle, dingo.spot.distance_to(GroundData.dingo_spot()), dingo.speed, dingo.trench_m])
		"touchmission":
			# A job from the player's side: the buttons there are, dust in the bucket by thumb, and the banner.
			var dump_b: Node2D = null
			var low_b: Node2D = null
			for b in touch_buttons:
				if b.visible and b.get_meta("label") == "DUMP":
					dump_b = b
				if b.visible and b.get_meta("label") == "LOWER":
					low_b = b
			if _touch_tick == 20:
				var shown := []
				for b in touch_buttons:
					if b.visible:
						shown.append(b.get_meta("label", "?"))
				var bar := []
				for key: String in buttons:
					if buttons[key].visible:
						bar.append(buttons[key].text)
				print("JOB %s on %s: buttons %s | bar %s | banner: %s" % [mission["id"], active.machine_name, ", ".join(shown), ", ".join(bar), banner.text])
				_touch(0, low_b.position + Vector2.ONE * low_b.get_meta("size") * 0.5, true)
			elif _touch_tick == 60:
				_touch(0, low_b.position + Vector2.ONE * low_b.get_meta("size") * 0.5, false)
				print("JOB lowered: %s" % active.gauge_word()[0])
				_touch(1, s * Vector2(0.25, 0.7), true)
			elif _touch_tick == 62:
				_drag(1, s * Vector2(0.25, 0.7) + Vector2(0.0, -s.y * 0.14))
			elif _touch_tick == 500:
				print("JOB drove into the pile: %s, dust in bucket %.3f m3" % [active.gauge_word()[0], DirtSim.to_m3((active as Loader).bucket_dust)])
				_touch(1, s * Vector2(0.25, 0.7), false)
				_touch(0, dump_b.position + Vector2.ONE * dump_b.get_meta("size") * 0.5, true)
			elif _touch_tick == 620:
				_touch(0, dump_b.position + Vector2.ONE * dump_b.get_meta("size") * 0.5, false)
				print("JOB dumped: %s; dust on the ground %.3f m3; total %s" % [active.gauge_word()[0], DirtSim.to_m3(sim.dust_total()), "same" if sim.total() == start_total else "CHANGED"])
			elif _touch_tick == 630:
				_touch(0, spread_button.position + Vector2.ONE * spread_button.get_meta("size") * 0.5, true)
			elif _touch_tick == 634:
				_touch(0, spread_button.position + Vector2.ONE * spread_button.get_meta("size") * 0.5, false)
				print("JOB tapped SPREAD: on %s, button says %s" % [(active as Loader).spread_on, spread_word.text])
			elif _touch_tick == 800:
				print("JOB bucket down: %s, arm at the bottom %s" % [active.gauge_word()[0], (active as Loader).arm <= (active as Loader).arm_low + 0.02])
				_touch(1, s * Vector2(0.25, 0.7), true)
			elif _touch_tick == 802:
				_drag(1, s * Vector2(0.25, 0.7) + Vector2(0.0, -s.y * 0.14))
			elif _touch_tick == 900:
				print("JOB driving forward: %s, speed %.2f, bucket %.3f m3" % [active.gauge_word()[0], active.speed, DirtSim.to_m3((active as Loader).bucket_mm)])
				_drag(1, s * Vector2(0.25, 0.7) + Vector2(0.0, s.y * 0.14))
			elif _touch_tick == 1020:
				print("JOB backing up: %s, speed %.2f" % [active.gauge_word()[0], active.speed])
				_touch(1, s * Vector2(0.25, 0.7), false)
				_touch(0, low_b.position - Vector2(0.0, low_b.get_meta("size")) + Vector2.ONE * low_b.get_meta("size") * 0.5, true)
			elif _touch_tick == 1040:
				print("JOB RAISE: spread on %s, button says %s" % [(active as Loader).spread_on, spread_word.text])
				_touch(0, low_b.position - Vector2(0.0, low_b.get_meta("size")) + Vector2.ONE * low_b.get_meta("size") * 0.5, false)
		"touchmenu":
			# Round the whole menu: Free play, back to the menu, into a job, Reset keeps the job, back to the menu again.
			var stage: int = Engine.get_meta("menu_stage", 0)
			if _touch_tick == 20:
				print("MENU stage %d: menu up %s, job %s, %d buttons showing, now %s" % [stage, menu != null, mission.get("id", "none"), touch_buttons.filter(func(b): return b.visible).size(), active.machine_name])
			if stage == 0:
				if _touch_tick == 20:
					_touch(0, s * Vector2(0.2, 0.7), true)
				elif _touch_tick == 22:
					_drag(0, s * Vector2(0.2, 0.6))
				elif _touch_tick == 30:
					print("MENU a thumb behind it: throttle %.2f" % active.throttle)
					_touch(0, s * Vector2(0.2, 0.7), false)
				elif _touch_tick == 40:
					var box: Node = menu.get_child(0)
					_click((box.get_child(box.get_child_count() - 1) as Button).get_global_rect().get_center())
				elif _touch_tick == 50:
					print("MENU after Free play: up %s, %d buttons showing" % [menu != null, touch_buttons.filter(func(b): return b.visible).size()])
					Engine.set_meta("menu_stage", 1)
					_click(buttons["menu"].get_global_rect().get_center())
			elif stage == 1 and _touch_tick == 40:
				Engine.set_meta("menu_stage", 2)
				_click((menu.get_child(0).get_child(1) as Button).get_global_rect().get_center())
			elif stage == 2 and _touch_tick == 40:
				Engine.set_meta("menu_stage", 3)
				_click(buttons["reset"].get_global_rect().get_center())
			elif stage == 3 and _touch_tick == 40:
				Engine.set_meta("menu_stage", 4)
				_click(buttons["menu"].get_global_rect().get_center())
			elif stage == 4 and _touch_tick == 40:
				get_tree().quit()
		"touchswap":
			if _touch_tick == 20:
				print("SWAP start: in dozer %s, raise visible %s, curl visible %s" % [active == dozer, touch_buttons[0].visible, touch_buttons[5].visible])
				_click(buttons["machine"].get_global_rect().get_center())
			elif _touch_tick == 30:
				print("SWAP clicked: in digger %s, raise visible %s, curl visible %s, label %s" % [active == digger, touch_buttons[0].visible, touch_buttons[5].visible, buttons["machine"].text])
				_click(buttons["machine"].get_global_rect().get_center())
			elif _touch_tick == 40:
				print("SWAP back: in dozer %s, raise visible %s, curl visible %s" % [active == dozer, touch_buttons[0].visible, touch_buttons[5].visible])
		"touchright":
			var right_thumb := s * Vector2(0.7, 0.5)
			if _touch_tick == 20:
				_touch(0, right_thumb, true)
			elif _touch_tick == 22:
				_drag(0, right_thumb + Vector2(0.0, -s.y * 0.14))
			elif _touch_tick == 110:
				print("TOUCH right side: throttle %.2f, went %.1f m" % [dozer.throttle, dozer.spot.distance_to(GroundData.dozer_spot())])
		"touchwalk":
			# GET OUT tapped, a walk away on the stick, round, back to the machine, and GET IN tapped.
			var thumb := s * Vector2(0.3, 0.6)
			var reach := s.y * 0.14
			var out_b: Button = buttons["out"]
			if _touch_tick == 30:
				_walk_from = active
				print("WALK start: in %s, Get out shown %s" % [active.machine_name, out_b.visible])
				_click(out_b.global_position + out_b.size * 0.5)
			elif _touch_tick == 40:
				print("WALK out: now %s at %s, %.2f m from the %s, its driver shown %s" % [active.machine_name, active.spot, active.spot.distance_to(_walk_from.spot), _walk_from.machine_name, (_walk_from as Loader)._driver.visible if _walk_from is Loader and (_walk_from as Loader)._driver else "-"])
				_walk_spot = active.spot
				_touch(0, thumb, true)
			elif _touch_tick == 42:
				_drag(0, thumb + Vector2(0.0, -reach))
			elif _touch_tick == 160:
				print("WALK walked %.2f m, GET IN shown %s" % [active.spot.distance_to(_walk_spot), get_in_button.visible])
			elif _touch_tick > 160 and _touch_tick < 600 and _near_machine(active as Worker) == null:
				# Thumb steering him back towards the machine, as a player would.
				var to := _walk_from.spot - active.spot
				var off := wrapf(atan2(-to.y, to.x) - active.angle, -PI, PI)
				_drag(0, thumb + Vector2(clampf(-off * 1.5, -1.0, 1.0) * reach, -reach * (0.9 if absf(off) < 0.6 else 0.0)))
			elif _touch_tick > 220 and _touch_tick < 600 and _near_machine(active as Worker) != null:
				_touch(0, thumb, false)
				print("WALK back by the %s after %d ticks, GET IN shown %s: %s" % [_near_machine(active as Worker).machine_name, _touch_tick, get_in_button.visible, get_in_word.text.replace("
", " ")])
				_touch(1, get_in_button.position + Vector2.ONE * get_in_button.get_meta("size") * 0.5, true)
				_touch(1, get_in_button.position + Vector2.ONE * get_in_button.get_meta("size") * 0.5, false)
				_touch_tick = 600
			elif _touch_tick == 610:
				print("WALK in: now %s, worker shown %s, Get out shown %s" % [active.machine_name, workers[0].visible, out_b.visible])
				get_tree().quit()
			elif _touch_tick == 599:
				print("WALK never got back to a machine: at %s" % active.spot)
				get_tree().quit()
		"touchsteer":
			# A thumb pushing ahead that wanders a little sideways keeps it straight; pushed right over, it turns hard.
			var thumb := s * Vector2(0.3, 0.6)
			var reach := s.y * 0.14
			if _touch_tick == 20:
				_touch(0, thumb, true)
			elif _touch_tick == 22:
				_drag(0, thumb + Vector2(reach * 0.12, -reach))
			elif _touch_tick == 60:
				print("STEER drift: throttle %.2f steer %.2f" % [active.throttle, active.steer])
				_drag(0, thumb + Vector2(reach * 0.6, -reach * 0.8))
			elif _touch_tick == 80:
				print("STEER half: steer %.2f" % active.steer)
				_drag(0, thumb + Vector2(reach * 1.2, 0.0))
			elif _touch_tick == 100:
				print("STEER full: steer %.2f" % active.steer)
				_touch(0, thumb, false)
				get_tree().quit()
		"touchlate":
			if _touch_tick == 20:
				DisplayServer.window_set_size(Vector2i(1280, 720))
			elif _touch_tick == 60:
				var go2: Node2D = touch_buttons[2]
				print("LATE size: screen %s, GO at %s size %s" % [s, go2.position, go2.get_meta("size")])
				_touch(0, go2.position + Vector2.ONE * go2.get_meta("size") * 0.5, true)
			elif _touch_tick == 150:
				print("LATE go: throttle %.2f, went %.1f m" % [dozer.throttle, dozer.spot.distance_to(GroundData.dozer_spot())])
		"touchcut":
			var cb: Vector2 = cut_button.position + Vector2.ONE * cut_button.get_meta("size") * 0.5
			var plus: Node2D = null
			for b in touch_buttons:
				if b.get_meta("label") == "+":
					plus = b
			var pb: Vector2 = plus.position + Vector2.ONE * plus.get_meta("size") * 0.5
			var go_b: Node2D = touch_buttons[2]
			var gb: Vector2 = go_b.position + Vector2.ONE * go_b.get_meta("size") * 0.5
			var rb: Vector2 = touch_buttons[0].position + Vector2.ONE * touch_buttons[0].get_meta("size") * 0.5
			if _touch_tick == 20:
				_touch(0, pb, true)
			elif _touch_tick == 24:
				_touch(0, pb, false)
				print("CUT plus: %d cm, %s" % [dozer.cut_cm, cut_word.text.replace("\n", " ")])
			elif _touch_tick == 30:
				_touch(0, cb, true)
			elif _touch_tick == 34:
				_touch(0, cb, false)
				print("CUT tapped: on %s, %s" % [dozer.cut_on, cut_word.text.replace("\n", " ")])
			elif _touch_tick == 150:
				print("CUT blade down: gap %.2f, lift %.2f" % [dozer.edge_gap, dozer.lift])
				_touch(1, gb, true)
			elif _touch_tick == 400:
				print("CUT driving: speed %.2f, gap %.2f, moved %.2f m3" % [dozer.speed, dozer.edge_gap, dozer.moved_m3])
				_touch(1, gb, false)
				_touch(0, rb, true)
			elif _touch_tick == 420:
				_touch(0, rb, false)
				print("CUT RAISE: on %s, %s" % [dozer.cut_on, cut_word.text.replace("\n", " ")])
		"touchlevel":
			var lb: Vector2 = level_button.position + Vector2.ONE * level_button.get_meta("size") * 0.5
			if _touch_tick == 20:
				_touch(0, lb, true)
			elif _touch_tick == 25:
				_touch(0, lb, false)
				print("TOUCH level: on %s, %s" % [dozer.level_on, level_word.text])
			elif _touch_tick == 30:
				var k := InputEventKey.new()
				k.physical_keycode = KEY_W
				k.keycode = KEY_W
				k.pressed = true
				Input.parse_input_event(k)
		"touchgo":
			var go: Node2D = touch_buttons[2]
			var on_go: Vector2 = go.position + Vector2.ONE * go.get_meta("size") * 0.5
			if _touch_tick == 20:
				_touch(0, on_go, true)
			elif _touch_tick == 110:
				print("TOUCH go: throttle %.2f, went %.1f m" % [dozer.throttle, dozer.spot.distance_to(GroundData.dozer_spot())])
		"touchkeys":
			if _touch_tick == 20 or _touch_tick == 200:
				var k := InputEventKey.new()
				k.keycode = KEY_W
				k.physical_keycode = KEY_W
				k.pressed = _touch_tick == 20
				Input.parse_input_event(k)
			if _touch_tick == 199:
				print("KEYS drive: throttle %.2f, went %.1f m, %.1f km/h" % [dozer.throttle, dozer.spot.distance_to(GroundData.dozer_spot()), dozer.speed * 3.6])
		"touchdrive":
			var thumb := s * Vector2(0.2, 0.7)
			var raise: Node2D = touch_buttons[0]
			var on_raise: Vector2 = raise.position + Vector2.ONE * raise.get_meta("size") * 0.5
			if _touch_tick == 20:
				_touch(0, thumb, true)
			elif _touch_tick == 22:
				_drag(0, thumb + Vector2(s.y * 0.04, -s.y * 0.14))
			elif _touch_tick == 30:
				_touch(1, on_raise, true)
			elif _touch_tick == 90:
				_touch(1, on_raise, false)
			elif _touch_tick == 200:
				print("TOUCH drive: throttle %.2f steer %.2f, went %.1f m, blade lift %.2f" % [dozer.throttle, dozer.steer, dozer.spot.distance_to(GroundData.dozer_spot()), dozer.lift])
		"touchdirt":
			var spot := s * Vector2(0.5, 0.75)
			if _touch_tick == 20:
				set_meta("before", sim.store)
				_touch(0, spot, true)
			elif _touch_tick == 140:
				_touch(0, spot, false)
				print("TOUCH dirt: drop took %.1f m3 from hand, target under finger %s" % [DirtSim.to_m3(int(get_meta("before")) - sim.store), _ground_under(spot)])
		"ui":
			if _touch_tick == 20:
				_click(buttons["mode"].get_global_rect().get_center())
			elif _touch_tick == 30:
				print("CLICK mode: now %s, tool button visible %s" % [mode, buttons["tool"].visible])
				_click(buttons["grass"].get_global_rect().get_center())
			elif _touch_tick == 40:
				print("CLICK grass: now %s" % grass)
				_click(buttons["mode"].get_global_rect().get_center())
			elif _touch_tick == 50:
				print("CLICK mode: now %s, raise button visible %s" % [mode, touch_buttons[0].visible])
