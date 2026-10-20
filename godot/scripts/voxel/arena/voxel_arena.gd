class_name VoxelArena
extends Node3D
## The PC voxel arena test (PLAN.md, 20 Oct: "PC only, voxel destruction"). One arena, block enemies (grunt,
## swarmer, brute, batter) coming at you one at a time (F3 / F5 send in more), and every shot makes a hole exactly
## where it hits: the cubes there are knocked out (flying, bouncing, settling), the meat and bone inside show, a limb shot mostly away comes off, a head
## or chest shot through drops them. Only the hit body parts are meshed again, on worker threads, a few a frame.
## The top left shows what it costs (frame rate, frame time, draw calls, triangles, cubes flying, meshing jobs).
## Owned by the voxel session. Desktop renderer (Forward+); the Windows build boots straight into this scene.
##
## Keys: WASD move, mouse look, left click blaster (holds), right click shotgun, Shift run, Space jump, V top-down /
## first person, F1 shadows, F2 cube size (1 or 2 sprite pixels a cube), F3 ten more enemies, F4 freeze them,
## F5 a big wave (40), Esc frees the mouse (click to grab it again).
##
## Testing (after -- on the command line): --auto (it aims at the nearest enemy and fires by itself, alternating
## blaster and shotgun), --enemies=N, --shot=path.png and --secs=S (save a screenshot after S seconds and quit),
## --topdown, --chunk=2, --stats (print the frame numbers every second).

const KEYS := ["grunt", "grunt", "swarmer", "swarmer", "brute", "batter", "batter", "batter"]
const HEIGHT := {"grunt": 1.85, "swarmer": 1.7, "brute": 2.2, "batter": 1.9}
const MAX_JOBS := 12            # meshing jobs running at once
const ARENA := 22.0             # half the arena's width, metres

var chunk := 1                  # sprite pixels a cube
var bodies: Array[VoxelBody] = []
var debris: VoxelDebris
var player: CharacterBody3D
var cam: Camera3D
var avatar: VoxelBody
var sun: DirectionalLight3D
var hud: Label
var help: Label
var cross: Label
var top_down := false
var frozen := false
var wave := 0
var knocked := 0
var kills := 0
var look_yaw := 0.0
var look_pitch := 0.0
var _jobs := []                 # [{id, body: WeakRef, part, out: Dictionary}]
var _jobs_done := 0
var _fire_cd := 0.0
var _sg_cd := 0.0
var _hud_t := 0.0
var _flash: OmniLight3D
var _flash_t := 0.0
var _tracers: MeshInstance3D
var _tracer_list := []          # [{a, b, t}]
var _mat: StandardMaterial3D
var _kick := 0.0
var _opts := {}
var _t := 0.0
var _stat_t := 0.0
var _frames := PackedFloat32Array()
var _next_t := 0.0
var _code_ms := 0.0            # the arena's own code a frame (smoothed)
var _prof := {}                 # section -> microseconds this second (--stats)
var sword: VoxelSword
var vacuum_out := false         # E: the vacuum gun instead of the guns (hold click: sucks up the cubes lying about)
var vacuum: VoxelVacuum
var _sucking := false
var _mouse_v := Vector2.ZERO    # the mouse's recent movement (the way a slash goes)
var _flip := 1.0                # still mouse: slashes go back and forth

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	chunk = int(_opts.get("chunk", "1"))
	top_down = _opts.has("topdown")
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
	_world()
	_player()
	_hud()
	debris = VoxelDebris.new()
	add_child(debris)
	debris.setup(_cube_m("grunt"))
	_tracers = MeshInstance3D.new()
	_tracers.mesh = ImmediateMesh.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.9, 0.5)
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.8, 0.3)
	_tracers.material_override = tm
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracers)
	sword = VoxelSword.new()
	add_child(sword)
	sword.setup(self, cam)
	vacuum = VoxelVacuum.new()
	add_child(vacuum)
	vacuum.setup(self, cam)
	_warm_up()
	if _opts.has("walkcheck"):
		_walkcheck_setup()
	elif _opts.has("swordtest"):
		_swordtest_setup()
	elif _opts.has("enemies"):
		wave = 1
		spawn(int(_opts.enemies))
	else:
		_next_wave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (top_down or _opts.has("auto")) else Input.MOUSE_MODE_CAPTURED
	print("VoxelArena: ready (renderer ", RenderingServer.get_current_rendering_method(), ")")

func _cube_m(key: String) -> float:
	var md := VoxelModel.get_model(key)
	var rows := float(md.rig.get("ref_rows", 80)) if md else 80.0
	return float(HEIGHT.get(key, 1.85)) / rows * float(chunk)

# ---------------------------------------------------------------- the place

func _world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.45, 0.68)
	sm.sky_horizon_color = Color(0.7, 0.72, 0.75)
	sm.ground_horizon_color = Color(0.45, 0.42, 0.4)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# the floor: the Smash TV arena's dark grid, big tiles
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ARENA * 2.0, ARENA * 2.0)
	floor_mi.mesh = pm
	var fs := ShaderMaterial.new()
	fs.shader = Shader.new()
	fs.shader.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz / 2.0 + 0.5) - 0.5) * 2.0;
	float line = 1.0 - smoothstep(0.0, 0.025, min(1.0 - g.x, 1.0 - g.y));
	float n = fract(sin(dot(floor(w.xz / 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = mix(vec3(0.018, 0.02, 0.028) * (0.8 + 0.4 * n), vec3(0.08, 0.1, 0.2), line);
	ROUGHNESS = 0.8;
}
"""
	floor_mi.material_override = fs
	add_child(floor_mi)
	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(ARENA * 2.0, 1.0, ARENA * 2.0)
	fc.shape = fsh
	fc.position = Vector3(0, -0.5, 0)
	fb.add_child(fc)
	add_child(fb)
	# walls and a few pillars
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.16, 0.17, 0.22)
	wall_mat.roughness = 0.9
	for i in 4:
		var a := i * PI / 2.0
		_box(Vector3(sin(a) * ARENA, 2.0, cos(a) * ARENA), Vector3(ARENA * 2.0 if i % 2 == 0 else 1.0, 4.0, 1.0 if i % 2 == 0 else ARENA * 2.0), wall_mat)
	var pil := StandardMaterial3D.new()
	pil.albedo_color = Color(0.3, 0.12, 0.35)
	pil.emission_enabled = true
	pil.emission = Color(0.5, 0.1, 0.6)
	pil.emission_energy_multiplier = 0.15
	for p in [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(-8, 0, 8), Vector3(8, 0, 8)]:
		_box(p + Vector3(0, 1.75, 0), Vector3(1.2, 3.5, 1.2), pil)

func _box(at: Vector3, size: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = at
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

func _player() -> void:
	player = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	player.add_child(cs)
	player.position = Vector3(0, 0, 6)
	add_child(player)
	cam = Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	add_child(_flash)
	# Juicy Jared in blocks, seen in the top-down view
	avatar = VoxelBody.new()
	add_child(avatar)
	avatar.setup("jared", 0.0125 * 2.0, 2, _mat)
	avatar.visible = false

func _hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(12, 10)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	cl.add_child(hud)
	help = Label.new()
	help.text = "WASD move   mouse look   left click blaster   right click shotgun   F sword slash (the way you move the mouse; or a mouse side button)   C chop down / low sweep   E vacuum (hold click, wheel: brush size)   Shift run   Space jump   V view   F1 shadows   F2 cube size   F3 +10 enemies   F4 freeze   F5 big wave   F6 can't die   Esc mouse"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.offset_top = -30
	cl.add_child(help)
	cross = Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.add_theme_color_override("font_outline_color", Color.BLACK)
	cross.add_theme_constant_override("outline_size", 4)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.offset_left = -8
	cross.offset_top = -20
	cl.add_child(cross)

# ---------------------------------------------------------------- enemies

## One enemy at a time (the owner, 20 Oct): the next walks in a moment after the last one drops.
func _next_wave() -> void:
	wave += 1
	spawn(1)

## n more enemies round the arena's edge.
func spawn(n: int) -> void:
	for i in n:
		var key: String = KEYS[randi() % KEYS.size()]
		var b := VoxelBody.new()
		add_child(b)
		b.setup(key, _cube_m(key), chunk, _mat)
		var a := randf() * TAU
		b.position = Vector3(cos(a), 0.0, sin(a)) * (ARENA - 2.0) * randf_range(0.7, 1.0)
		b.speed = randf_range(1.1, 1.9) * (1.4 if key == "swarmer" else (0.75 if key == "brute" else 1.0))
		b.died.connect(_on_died)
		bodies.append(b)

# every kind made once while loading (their flesh and meshes cached), so the first of each doesn't stall the game
func _warm_up() -> void:
	for key in HEIGHT:
		var b := VoxelBody.new()
		add_child(b)
		b.setup(key, _cube_m(key), chunk, _mat)
		b.queue_free()

func _on_died(_b: VoxelBody) -> void:
	kills += 1

func _respawn_all() -> void:
	var n := 0
	for b in bodies:
		if b.alive:
			n += 1
		b.queue_free()
	bodies.clear()
	_jobs.clear()
	var got := debris.got
	debris.queue_free()
	debris = VoxelDebris.new()
	add_child(debris)
	debris.setup(_cube_m("grunt"))
	debris.got = got
	spawn(maxi(n, 1))

# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= e.relative.x * 0.0025
		look_pitch = clampf(look_pitch - e.relative.y * 0.0025, -1.4, 1.4)
		_mouse_v += e.relative
	elif e is InputEventMouseMotion:
		_mouse_v += e.relative
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if vacuum_out:
			vacuum.wheel(e.button_index == MOUSE_BUTTON_WHEEL_UP)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2] and (top_down or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_sword_key(false)
	elif e is InputEventMouseButton and e.pressed and not top_down and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# first person grabs the mouse on a click; top-down keeps it free (aiming follows the pointer)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_F:
				_sword_key(false)
			KEY_C:
				_sword_key(true)
			KEY_E:
				vacuum_out = not vacuum_out
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_V:
				top_down = not top_down
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if top_down else Input.MOUSE_MODE_CAPTURED
			KEY_F1:
				sun.shadow_enabled = not sun.shadow_enabled
			KEY_F2:
				chunk = 2 if chunk == 1 else 1
				_warm_up()
				_respawn_all()
			KEY_F3:
				spawn(10)
			KEY_F4:
				frozen = not frozen
			KEY_F5:
				spawn(40)
			KEY_F6:
				VoxelBody.immortal = not VoxelBody.immortal

# ---------------------------------------------------------------- each frame

# --swordtest=dir: a grunt standing in front, frozen, slashed through an arm, at the neck, then at the knees,
# a frame saved round each cut (sword_<cut>_<k>.png), what each cut did printed, then quit
const SWORD_CUTS := [[1.15, Vector2(0.3, 1.0), -0.5], [1.45, Vector2(-1, 0), 0.0], [0.25, Vector2(1, 0), 0.0]]   # [height, slash, across]
var _st_i := 0
var _st_t := 0.0
func _swordtest_setup() -> void:
	var b := VoxelBody.new()
	add_child(b)
	b.setup("grunt", _cube_m("grunt"), chunk, _mat)
	b.position = Vector3(0, 0, 4.5)
	b.yaw = 0.0
	b.died.connect(_on_died)
	bodies.append(b)
	frozen = true
	VoxelBody.immortal = _opts.has("immortal")
	player.position = Vector3(0.25, 0, 6.0)
	look_yaw = 0.0

func _swordtest(dt: float) -> void:
	_st_t += dt
	if _st_i >= SWORD_CUTS.size():
		# then the vacuum, looking down at the mess, for two seconds
		vacuum_out = true
		look_pitch = -0.75
		_sucking = _st_t > 1.0
		for k in 3:
			var tag := "vf%d" % k
			if _st_t >= [0.95, 1.35, 2.2][k] and not _opts.has(tag):
				_opts[tag] = "1"
				_shot_png("%s/vacuum_%d.png" % [String(_opts.swordtest), k])
		if _st_t > 3.1:
			print("SWORD vacuum: got %s, lying %d, pieces %d" % [str(debris.got), debris.lying(), sword.pieces()])
			_finish()
		return
	var c: Array = SWORD_CUTS[_st_i]
	var b: VoxelBody = bodies[0]
	var target := b.global_position + Vector3(float(c[2]), float(c[0]), 0)
	var to := target - cam.global_position
	look_yaw = atan2(-to.x, -to.z)
	look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	if _st_t > 1.0 and sword.ready_to_swing() and not _opts.has("sc%d" % _st_i):
		_opts["sc%d" % _st_i] = "1"
		slash(c[1])
	for k in 6:
		var at: float = 1.0 + [0.02, 0.06, 0.15, 0.3, 0.6, 1.2][k]
		var tag := "sf%d_%d" % [_st_i, k]
		if _st_t >= at and not _opts.has(tag):
			_opts[tag] = "1"
			_shot_png("%s/sword_%d_%d.png" % [String(_opts.swordtest), _st_i, k])
	if _st_t > 2.4:
		print("SWORD cut %d at %.2f m: %s; legs lost %d, alive %s" % [_st_i, c[0], str(sword.last), b.legs_lost(), str(b.alive)])
		_st_i += 1
		_st_t = 0.8

func _shot_png(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

# --walkcheck=dir: the four kinds side by side, walking on the spot side-on to the camera, a frame saved every
# tenth of a second (walk_0.png ...), then quit
func _walkcheck_setup() -> void:
	var i := 0
	for key in ["grunt", "swarmer", "brute", "batter"]:
		var b := VoxelBody.new()
		add_child(b)
		b.setup(key, _cube_m(key), chunk, _mat)
		b.position = Vector3(-2.4 + i * 1.6, 0, 0)
		b.yaw = PI / 2.0
		b.speed = 2.6 if key != "brute" else 1.9
		if _opts.has("legless"):     # --legless: both legs off, to see the worm crawl
			b._blow("thigh_l")
			b._blow("thigh_r")
			b.speed *= b.move_factor()
		bodies.append(b)
		i += 1
	frozen = true
	player.position = Vector3(0, 0, 5.0)
	look_yaw = 0.0
	look_pitch = -0.12

func _walkcheck(dt: float) -> void:
	for b in bodies:
		b.odo += b.speed * dt
		b.animate(dt, true)
	var k := int(floor((_t - 1.0) / 0.1))
	if k >= 0 and k < 10 and not _opts.has("wk%d" % k):
		_opts["wk%d" % k] = "1"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/walk_%d.png" % [String(_opts.walkcheck), k])
	if k >= 10:
		get_tree().quit()

func _physics_process(dt: float) -> void:
	if _opts.has("walkcheck"):
		return
	# the player: WASD by where you look (top-down: by the screen)
	var iv := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var sp := 7.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 4.5
	var dir := Vector3.ZERO
	if top_down:
		dir = Vector3(iv.x, 0, iv.y)
	else:
		var f := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
		var r := Vector3(cos(look_yaw), 0, -sin(look_yaw))
		dir = r * iv.x - f * iv.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	player.velocity.x = dir.x * sp
	player.velocity.z = dir.z * sp
	if player.is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			player.velocity.y = 5.0
	else:
		player.velocity.y -= 14.0 * dt
	player.move_and_slide()
	# the enemies come at you
	var pp := player.global_position
	for i in bodies.size():
		var b := bodies[i]
		if not b.alive:
			continue
		var to := Vector3(pp.x - b.position.x, 0, pp.z - b.position.z)
		var d := to.length()
		var mv := Vector3.ZERO
		var stop := 4.5 if _opts.has("auto") else 1.2
		b.react_step(dt)
		if not frozen and d > stop and b.stagger <= 0.0:
			mv = to / d * b.speed * b.move_factor()
		# keep apart
		for j in range(maxi(0, i - 6), mini(bodies.size(), i + 7)):
			if j == i or not bodies[j].alive:
				continue
			var away := b.position - bodies[j].position
			away.y = 0
			var dl := away.length()
			if dl < 0.8 and dl > 0.001:
				mv += away / dl * (0.8 - dl) * 6.0
		b.position += mv * dt
		b.position.x = clampf(b.position.x, -ARENA + 1.0, ARENA - 1.0)
		b.position.z = clampf(b.position.z, -ARENA + 1.0, ARENA - 1.0)
		if d > 0.01:
			b.yaw = lerp_angle(b.yaw, atan2(to.x, to.z), 1.0 - exp(-dt * 8.0))
		b.odo += mv.length() * dt
		b.attack = fmod(b.attack + dt * 1.6, 1.0) if (d <= stop + 0.2 and not frozen and b.stagger <= 0.0) else 0.0

func _process(dt: float) -> void:
	_t += dt
	_frames.append(dt)
	if _opts.has("stats"):
		_stat_t += dt
		if _stat_t >= 1.0:
			_stat_t = 0.0
			_hud_text()
			print("ARENA ", hud.text.replace("\n", " | "))
			var ps := ""
			for k in _prof:
				ps += "%s %.1f  " % [k, _prof[k] / 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
			print("ARENA ms a frame: ", ps, " debris ", "%.1f" % (debris.prof_us / 1000.0 / maxf(1.0, Engine.get_frames_per_second())))
			debris.prof_us = 0
			_prof.clear()
	if _opts.has("burst"):
		var k := int(floor((_t - float(_opts.get("burst_at", "3")) ) / 0.1))
		if k >= 0 and k < 12 and not _opts.has("bk%d" % k):
			_opts["bk%d" % k] = "1"
			_burst_save(k)
	if _opts.has("secs") and _t >= float(_opts.secs):
		_finish()
		return
	if _opts.has("walkcheck"):
		_camera(dt)
		_walkcheck(dt)
		return
	if _opts.has("swordtest"):
		_swordtest(dt)
	var t0 := Time.get_ticks_usec()
	_camera(dt)
	var t1 := Time.get_ticks_usec()
	_shoot(dt)
	var t2 := Time.get_ticks_usec()
	for b in bodies:
		var moving := b.alive and not frozen
		if not b.alive:
			b.dead_t += dt
			if b.dead_t > 0.7:
				continue          # lying still
		b.animate(dt, moving and b.attack <= 0.0)
	# the dead lie a while, then go
	for i in range(bodies.size() - 1, -1, -1):
		var b := bodies[i]
		if not b.alive and b.dead_t > 12.0:
			b.queue_free()
			bodies.remove_at(i)
	var t3 := Time.get_ticks_usec()
	if not bodies.any(func(x): return x.alive):
		_next_t += dt
		if _next_t >= 1.5:
			_next_t = 0.0
			_next_wave()
	var t4 := Time.get_ticks_usec()
	_mesh_jobs()
	var t5 := Time.get_ticks_usec()
	_prof["camera"] = _prof.get("camera", 0) + t1 - t0
	_prof["shoot"] = _prof.get("shoot", 0) + t2 - t1
	_prof["animate"] = _prof.get("animate", 0) + t3 - t2
	_prof["spawn"] = _prof.get("spawn", 0) + t4 - t3
	_prof["jobs"] = _prof.get("jobs", 0) + t5 - t4
	_code_ms = lerpf(_code_ms, (t5 - t0) / 1000.0, 0.1)
	_draw_tracers(dt)
	_mouse_v *= exp(-dt * 14.0)
	sword.view.visible = sword.busy() and not top_down
	sword.step(dt)
	vacuum.step(dt, vacuum_out, _sucking)
	_flash_t = maxf(0.0, _flash_t - dt)
	_flash.light_energy = 4.0 * _flash_t / 0.05 if _flash_t > 0.0 else 0.0
	_hud_t += dt
	if _hud_t >= 0.25:
		_hud_t = 0.0
		_hud_text()

func _camera(dt: float) -> void:
	var pp := player.get_global_transform_interpolated().origin
	_kick = maxf(0.0, _kick - dt * 6.0)
	avatar.visible = top_down
	if top_down:
		avatar.global_position = pp
		var aim := _mouse_floor()
		if aim != Vector3.INF:
			var to := aim - pp
			avatar.yaw = atan2(to.x, to.z)
		avatar.speed = Vector2(player.velocity.x, player.velocity.z).length()
		avatar.odo += avatar.speed * dt
		avatar.attack = maxf(0.0, avatar.attack - dt * 2.5)    # a sword swing's arms, back down
		avatar.animate(dt, avatar.speed > 0.2)
		cam.global_position = pp + Vector3(0, 13.0, 6.0)
		cam.look_at(pp + Vector3(0, 0.8, 0), Vector3.UP)
		cross.visible = false
	else:
		cam.global_position = pp + Vector3(0, 1.65, 0)
		cam.rotation = Vector3(look_pitch + _kick * 0.04, look_yaw, 0)
		cross.visible = true

func _mouse_floor() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (1.2 - o.y) / d.y
	return o + d * t if t > 0 else Vector3.INF

# where the gun points from: the eye (first person) or Jared's chest toward the mouse (top-down)
func _aim() -> Array:
	if top_down:
		var pp := player.global_position + Vector3(0, 1.2, 0)
		var at := _mouse_floor()
		if at == Vector3.INF:
			return []
		return [pp, (at - pp).normalized()]
	return [cam.global_position, -cam.global_transform.basis.z]

func _shoot(dt: float) -> void:
	if not _opts.has("swordtest"):
		_sucking = false
	_fire_cd = maxf(0.0, _fire_cd - dt)
	_sg_cd = maxf(0.0, _sg_cd - dt)
	if _opts.has("auto"):
		_auto()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not top_down:
		return
	var a := _aim()
	if a.is_empty():
		return
	if vacuum_out:
		if not _opts.has("swordtest"):
			_sucking = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cd <= 0.0:
		_fire_cd = 1.0 / 10.0
		fire(a[0], a[1], 1, 0.6, 1.9)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _sg_cd <= 0.0:
		_sg_cd = 0.9
		fire(a[0], a[1], 9, 4.5, 1.4)

# the sword, with the guns still in hand: F (or a mouse side button) slashes the way the mouse was moving (still:
# back and forth); C chops down (first person) or sweeps low at the legs (top-down)
func _sword_key(low: bool) -> void:
	if not sword.ready_to_swing() or (not top_down and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _opts.has("swordtest")):
		return
	var sv := Vector2(_flip, 0.0)
	if low:
		sv = Vector2(0.0, 1.0)
	elif _mouse_v.length() > 30.0:
		sv = _mouse_v.normalized()
	else:
		_flip = -_flip
	slash(sv, low)

## One slash, sv the way it goes on screen (x right, y down); low: top-down's leg sweep.
func slash(sv: Vector2, low: bool = false) -> void:
	if top_down:
		var pp := player.global_position
		var at := _mouse_floor()
		var f := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
		if at != Vector3.INF:
			f = Vector3(at.x - pp.x, 0, at.z - pp.z).normalized()
		var eye := pp + Vector3(0, 0.45 if low else 1.15, 0)
		var right := f.cross(Vector3.UP).normalized()
		var tilt := 0.0 if low else 0.3 * signf(sv.x if absf(sv.x) > 0.01 else 1.0)
		var side := (right * signf(sv.x if absf(sv.x) > 0.01 else 1.0) * cos(tilt) + Vector3.DOWN * sin(absf(tilt))).normalized()
		avatar.attack = 0.5
		sword.swing(eye, f, side, eye, Vector3(1, 0, 0))
		return
	var bs := cam.global_transform.basis
	var side_cam := Vector3(sv.x, -sv.y, 0.0).normalized()
	var side := (bs * side_cam).normalized()
	var apex := cam.global_position + bs * Vector3(0.05, -0.28, -0.1)
	sword.swing(cam.global_position, -bs.z, side, apex, side_cam)

## One trigger pull: pellets rays spread degrees apart, each knocking a hole r cubes round where it lands.
func fire(from: Vector3, dir: Vector3, pellets: int, spread: float, r: float) -> void:
	_flash.global_position = from + dir * 0.6
	_flash_t = 0.05
	_kick = 1.0
	for i in pellets:
		var d := dir
		if spread > 0.0:
			var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
			var ax := deg_to_rad(randf_range(-spread, spread))
			var ay := deg_to_rad(randf_range(-spread, spread))
			d = (b * Vector3(ax, ay, -1.0)).normalized()
		var best := {}
		var best_b: VoxelBody = null
		var reach := 60.0
		for b2 in bodies:
			var h := b2.trace(from, d, reach)
			if not h.is_empty() and float(h.dist) < reach:
				reach = h.dist
				best = h
				best_b = b2
		# the world (walls, pillars, floor) stops it first?
		var q := PhysicsRayQueryParameters3D.create(from, from + d * reach)
		q.exclude = [player.get_rid()]
		var wh := get_world_3d().direct_space_state.intersect_ray(q)
		var end := from + d * reach
		if not wh.is_empty():
			end = wh.position
			best_b = null
		_tracer_list.append({"a": from + d * 0.5 + Vector3(0, -0.12, 0), "b": end, "t": 0.06})
		if best_b:
			var res := best_b.damage(best, r)
			best_b.hit_react(d, (res.bits as Array).size(), String(best.part))
			knocked += (res.bits as Array).size()
			var bits: Array = res.bits
			if bits.size() > 40:
				bits = bits.slice(0, 40) + (bits.slice(40) as Array).filter(func(_x): return randf() < 0.35)
			debris.burst(bits, d, 4.0 if res.limb == "" else 2.5)

# ---------------------------------------------------------------- meshing on worker threads

func _mesh_jobs() -> void:
	# finished ones swapped in
	for i in range(_jobs.size() - 1, -1, -1):
		var j: Dictionary = _jobs[i]
		if WorkerThreadPool.is_task_completed(j.id):
			WorkerThreadPool.wait_for_task_completion(j.id)
			var b = (j.body as WeakRef).get_ref()
			if b and is_instance_valid(b):
				b.set_part_arrays(j.part, j.out.arrays)
			_jobs.remove_at(i)
			_jobs_done += 1
	# new ones, while there's room
	for b in bodies:
		if _jobs.size() >= MAX_JOBS:
			break
		for n in b.dirty_parts():
			if _jobs.size() >= MAX_JOBS:
				break
			var p: Dictionary = b.parts[n]
			p.dirty = false
			var g := {"size": p.grid.size, "cells": (p.grid.cells as PackedInt32Array).duplicate()}
			var out := {}
			var origin: Vector3 = b.mesh_origin(n)
			var vm: float = b.vm
			var id := WorkerThreadPool.add_task(func(): out["arrays"] = VoxMesher.mesh(g, origin, vm))
			p.job = id
			_jobs.append({"id": id, "body": weakref(b), "part": n, "out": out})

func _draw_tracers(dt: float) -> void:
	var im: ImmediateMesh = _tracers.mesh
	im.clear_surfaces()
	for i in range(_tracer_list.size() - 1, -1, -1):
		_tracer_list[i].t -= dt
		if _tracer_list[i].t <= 0.0:
			_tracer_list.remove_at(i)
	if _tracer_list.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for tr in _tracer_list:
		im.surface_add_vertex(tr.a)
		im.surface_add_vertex(tr.b)
	im.surface_end()

func _hud_text() -> void:
	var alive := 0
	var tris := 0
	for b in bodies:
		if b.alive:
			alive += 1
		tris += b.triangles()
	var fps := Engine.get_frames_per_second()
	hud.text = "%d fps   %.1f ms a frame   (game code %.1f ms)\ndraw calls %d   triangles on screen %s   (enemies %s)\nenemy %d   enemies %d alive, %d lying   kills %d\ncubes knocked out %d   flying now %d   meshing jobs %d running, %d done\ncube %.1f cm (%d sprite pixel%s a cube)   shadows %s   %s\n%s   cubes lying %s   pieces %d   sucked up: %d blocks  %d meat  %d bone  %d brain" % [
		fps, 1000.0 / maxf(1.0, fps), _code_ms + debris.last_ms,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		_k(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)), _k(tris),
		wave, alive, bodies.size() - alive, kills, knocked, debris.count(), _jobs.size(), _jobs_done,
		_cube_m("grunt") * 100.0, chunk, "" if chunk == 1 else "s", ("on" if sun.shadow_enabled else "off") + ("   CAN'T DIE" if VoxelBody.immortal else ""),
		RenderingServer.get_current_rendering_method(),
		"VACUUM (brush %.1f m)" % vacuum.brush_r if vacuum_out else "GUNS + SWORD (F)", _k(debris.lying()), sword.pieces(),
		debris.got.blocks, debris.got.meat, debris.got.bone, debris.got.brain]

static func _k(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)

# the self-test: look at the nearest standing enemy's chest and fire (blaster, a shotgun blast now and then)
func _auto() -> void:
	var pp := cam.global_position
	var best: VoxelBody = null
	var bd := INF
	for b in bodies:
		if b.alive:
			var d := b.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = b
	if best == null:
		return
	var target := best.global_position + Vector3(0, best.height * (0.62 if randf() < 0.7 else 0.9), 0)
	var to := target - pp
	look_yaw = atan2(-to.x, -to.z)
	look_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	var dir := to.normalized()
	if _fire_cd <= 0.0:
		_fire_cd = 0.1
		fire(pp, dir, 1, 0.6, 1.9)
	if _sg_cd <= 0.0:
		_sg_cd = 1.5
		fire(pp, dir, 9, 4.5, 1.4)

func _burst_save(k: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/burst_%d.png" % [String(_opts.burst), k])

# closing the window: no meshing job left running on a worker thread
func _exit_tree() -> void:
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j.id)
	_jobs.clear()

func _finish() -> void:
	sword.finish_jobs()
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j.id)
	_jobs.clear()
	var fr := _frames.slice(mini(_frames.size() - 1, 30))
	var sorted := Array(fr)
	sorted.sort()
	var med: float = sorted[sorted.size() / 2] if sorted.size() > 0 else 0.0
	print("ARENA done: %d frames, median %.1f ms, worst %.1f ms; kills %d, cubes %d, meshing jobs %d" % [
		_frames.size(), med * 1000.0, (sorted[-1] if sorted.size() > 0 else 0.0) * 1000.0, kills, knocked, _jobs_done])
	if _opts.has("shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(_opts.shot))
		print("ARENA shot saved: ", _opts.shot)
	get_tree().quit()
