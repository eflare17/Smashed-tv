extends Node3D
## Smash arcade: a Smash TV-style arena shooter (stage 1). Self-contained: everything is built in code under this
## node, all state lives on it and its children (no autoloads, no statics, no physics bodies), and its input
## actions are its own (smash_input.gd). Made to run on its own or inside a SubViewport on an arcade cabinet.
##
## Each frame: player -> waves -> grunt grid + move -> bullets -> kills (score, gibs) -> pools draw to MultiMeshes.
## The cabinet can set `input_enabled` (false = ignore all input) and read `score` / `wave` / `lives`.

const Vox := preload("smash_vox.gd")
const SmashInput := preload("smash_input.gd")
const Horde := preload("smash_horde.gd")
const Shots := preload("smash_shots.gd")
const Gibs := preload("smash_gibs.gd")
const Hud := preload("smash_hud.gd")

const HALF := 10.0
const DOOR_HALF := 1.5
const CORRIDOR := 5.0
const PLAYER_SPEED := 6.5
const PLAYER_RADIUS := 0.3
const FIRE_GAP := 0.075
const START_LIVES := 3
const GUN_Y := 0.75
const EYE_Y := 1.05
const MOUSE_LOOK := 0.0025
const PAD_LOOK := 3.0
const SCORE_GRUNT := 100
const DEBUG_SPAWN := 50

## False: the game ignores all input (e.g. while the cabinet isn't being played).
@export var input_enabled := true
@export var debug_overlay := true
## False: no waves (the bench uses this).
var waves_enabled := true
var god := false
var first_person := false

var horde: Horde
var shots: Shots
var gibs: Gibs
var hud: Hud
var top_cam: Camera3D
var fp_cam: Camera3D
var player: MeshInstance3D
var _player_frames: Array[Mesh] = []

var player_pos := Vector2.ZERO
var player_face := Vector2(0, -1)
var _player_phase := 0.0
var _alive := true
var _respawn_t := 0.0
var _invuln_t := 0.0
var _fire_t := 0.0
var _use_mouse := true
var _yaw := PI
var _pitch := 0.0

var wave := 0
var score := 0
var lives := START_LIVES
var game_over := false
var _game_over_t := 0.0
var _to_spawn := 0
var _spawn_t := 0.0
var _burst_left := 0
var _burst_door := 0
var _next_wave_t := -1.0

## Microseconds this node's last _process took (the whole game simulation + buffer fills).
var sim_usec := 0
var _sim_avg := 0.0
var _debug_t := 0.0

func _enter_tree() -> void:
	# on a cabinet screen: keep this arena out of the main game's 3D world
	var vp := get_viewport()
	if vp is SubViewport and not vp.own_world_3d:
		vp.own_world_3d = true

func _ready() -> void:
	SmashInput.ensure_actions()
	_build()
	reset_game()

func _exit_tree() -> void:
	if first_person:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build() -> void:
	var arena := MeshInstance3D.new()
	arena.name = "Arena"
	arena.mesh = Vox.arena_mesh(HALF, DOOR_HALF, CORRIDOR)
	arena.mesh.surface_set_material(0, Vox.flat_material())
	arena.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arena)

	horde = Horde.new()
	horde.half = HALF
	horde.door_half = DOOR_HALF
	add_child(horde)
	shots = Shots.new()
	shots.half = HALF
	shots.door_half = DOOR_HALF
	shots.corridor = CORRIDOR
	add_child(shots)
	gibs = Gibs.new()
	gibs.half = HALF
	gibs.door_half = DOOR_HALF
	add_child(gibs)

	var mat := Vox.flat_material()
	for f in 2:
		var m := Vox.player_mesh(f)
		m.surface_set_material(0, mat)
		_player_frames.append(m)
	player = MeshInstance3D.new()
	player.name = "Player"
	player.mesh = _player_frames[0]
	player.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(player)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED

	# straight down, framing the arena plus a bit of each corridor
	top_cam = Camera3D.new()
	top_cam.name = "TopCamera"
	top_cam.fov = 45.0
	top_cam.near = 5.0
	top_cam.far = 60.0
	top_cam.position = Vector3(0, 31.5, 0)
	top_cam.rotation = Vector3(-PI / 2, 0, 0)
	top_cam.environment = env
	add_child(top_cam)
	fp_cam = Camera3D.new()
	fp_cam.name = "FirstPersonCamera"
	fp_cam.fov = 75.0
	fp_cam.near = 0.05
	fp_cam.far = 100.0
	fp_cam.environment = env
	add_child(fp_cam)
	top_cam.current = true

	hud = Hud.new()
	add_child(hud)

func reset_game() -> void:
	horde.clear()
	shots.clear()
	gibs.clear()
	score = 0
	lives = START_LIVES
	game_over = false
	hud.hide_banner()
	_spawn_player()
	if waves_enabled:
		_start_wave(1)
	else:
		wave = 0

## Debug: `n` more grunts, spread over the four corridors.
func spawn_debug(n: int) -> void:
	for k in n:
		horde.spawn(k % 4, randf_range(0.5, CORRIDOR - 0.5), _grunt_speed())

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		_use_mouse = true
		if first_person and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_yaw -= event.relative.x * MOUSE_LOOK
			_pitch = clampf(_pitch - event.relative.y * MOUSE_LOOK, -1.2, 1.2)
	elif event is InputEventMouseButton:
		_use_mouse = true
		if first_person and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		_use_mouse = false
	elif event is InputEventKey and (event.is_action(SmashInput.AIM_UP) or event.is_action(SmashInput.AIM_DOWN)
			or event.is_action(SmashInput.AIM_LEFT) or event.is_action(SmashInput.AIM_RIGHT)):
		_use_mouse = false

	if event.is_action_pressed(SmashInput.VIEW):
		set_first_person(not first_person)
	elif event.is_action_pressed(SmashInput.DEBUG_SPAWN):
		spawn_debug(DEBUG_SPAWN)
	elif event.is_action_pressed(SmashInput.DEBUG_OVERLAY):
		debug_overlay = not debug_overlay
	elif event.is_action_pressed(SmashInput.DEBUG_GOD):
		god = not god
	elif game_over and _game_over_t <= 0.0 and (event.is_action_pressed(SmashInput.START)
			or event.is_action_pressed(SmashInput.FIRE)):
		reset_game()

func set_first_person(on: bool) -> void:
	first_person = on
	if on:
		_yaw = atan2(player_face.x, player_face.y)
		_pitch = 0.0
		fp_cam.current = true
		if input_enabled:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		top_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.crosshair.visible = on

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var t0 := Time.get_ticks_usec()
	hud.tick(delta)
	_game_over_t -= delta
	_update_player(delta)
	if waves_enabled:
		_update_waves(delta)
	horde.build_grid()
	var can_touch := _alive and _invuln_t <= 0.0 and not god
	var touched := horde.step(delta, player_pos, PLAYER_RADIUS + Horde.RADIUS, can_touch)
	shots.step(delta, horde)
	_collect_kills()
	if touched:
		_player_hit()
	gibs.step(delta)
	horde.draw()
	shots.draw()
	gibs.draw()
	_place_player()
	sim_usec = Time.get_ticks_usec() - t0
	_sim_avg = lerpf(_sim_avg, sim_usec, 0.05)
	hud.set_stats(wave, score, lives)
	_update_debug(delta)

func _collect_kills() -> void:
	var kp := horde.kill_pos
	for k in kp.size():
		score += SCORE_GRUNT
		gibs.burst(kp[k], horde.kill_dir[k], Vox.GRUNT_GIBS, 5)
	horde.kill_pos.clear()
	horde.kill_dir.clear()
	horde.compact()

func _update_player(delta: float) -> void:
	if not _alive:
		_respawn_t -= delta
		if _respawn_t <= 0.0 and not game_over:
			_spawn_player()
		return
	_invuln_t -= delta
	var mv := Vector2.ZERO
	var aim := Vector2.ZERO
	var firing := false
	if input_enabled:
		mv = Input.get_vector(SmashInput.MOVE_LEFT, SmashInput.MOVE_RIGHT, SmashInput.MOVE_UP, SmashInput.MOVE_DOWN)
		aim = Input.get_vector(SmashInput.AIM_LEFT, SmashInput.AIM_RIGHT, SmashInput.AIM_UP, SmashInput.AIM_DOWN)
		firing = Input.is_action_pressed(SmashInput.FIRE)
	if first_person:
		# the aim stick / arrows turn the view; moving is relative to where you look
		_yaw -= aim.x * PAD_LOOK * delta
		_pitch = clampf(_pitch - aim.y * PAD_LOOK * 0.6 * delta, -1.2, 1.2)
		var f := Vector2(sin(_yaw), cos(_yaw))
		mv = Vector2(-f.y, f.x) * mv.x - f * mv.y
		player_face = f
	elif aim.length() > 0.3:
		player_face = aim.normalized()
		firing = true
	elif _use_mouse:
		var to := _mouse_ground() - player_pos
		if to.length() > 0.2:
			player_face = to.normalized()
	elif mv.length() > 0.1:
		player_face = mv.normalized()

	var lim := HALF - PLAYER_RADIUS
	player_pos += mv * (PLAYER_SPEED * delta)
	player_pos = Vector2(clampf(player_pos.x, -lim, lim), clampf(player_pos.y, -lim, lim))
	_player_phase = _player_phase + delta * 10.0 if mv.length() > 0.1 else 0.0

	_fire_t -= delta
	if firing and _fire_t <= 0.0:
		_fire_t = maxf(_fire_t + FIRE_GAP, 0.0)
		var f := player_face
		var right := Vector2(-f.y, f.x)
		# from the gun; in first person from a bit further out so the tracer isn't in your face
		var muzzle := player_pos + (f * 1.1 + right * 0.15 if first_person else f * 0.65 + right * 0.3)
		shots.fire(muzzle, f.rotated(randf_range(-0.04, 0.04)))
	elif not firing:
		_fire_t = maxf(_fire_t, 0.0)

func _mouse_ground() -> Vector2:
	var mp := get_viewport().get_mouse_position()
	var o := top_cam.project_ray_origin(mp)
	var n := top_cam.project_ray_normal(mp)
	if absf(n.y) < 0.001:
		return player_pos + player_face
	var hit := o + n * ((GUN_Y - o.y) / n.y)
	return Vector2(hit.x, hit.z)

func _place_player() -> void:
	var f := player_face
	player.position = Vector3(player_pos.x, 0, player_pos.y)
	player.basis = Basis(Vector3(f.y, 0, -f.x), Vector3.UP, Vector3(f.x, 0, f.y))
	player.mesh = _player_frames[int(_player_phase / PI) & 1]
	player.visible = _alive and not first_person and (_invuln_t <= 0.0 or int(_invuln_t * 10.0) % 2 == 0)
	if first_person:
		fp_cam.position = Vector3(player_pos.x, EYE_Y, player_pos.y)
		fp_cam.rotation = Vector3(_pitch, _yaw + PI, 0)

func _spawn_player() -> void:
	player_pos = Vector2.ZERO
	player_face = Vector2(0, -1)
	_alive = true
	_invuln_t = 2.0
	_fire_t = 0.0
	if first_person:
		_yaw = PI

func _player_hit() -> void:
	_alive = false
	lives -= 1
	gibs.burst(player_pos, Vector2.ZERO, Vox.PLAYER_GIBS, 14)
	# the grunts that got you go with you, so the respawn isn't an instant death
	horde.kill_radius(player_pos, 3.0)
	_collect_kills()
	if lives <= 0:
		game_over = true
		_game_over_t = 1.0
		hud.show_banner("GAME OVER\nSCORE %d\nfire or Enter to play again" % score, 0.0)
	else:
		_respawn_t = 1.5

func _start_wave(n: int) -> void:
	wave = n
	_to_spawn = 15 + n * 10
	_spawn_t = 1.5
	_burst_left = 0
	_next_wave_t = -1.0
	hud.show_banner("WAVE %d" % n, 2.0)

func _grunt_speed() -> float:
	return minf(2.4 + wave * 0.15, 4.5) * randf_range(0.85, 1.15)

func _update_waves(delta: float) -> void:
	if game_over:
		return
	if _to_spawn > 0:
		# grunts pour in bursts, each burst from one door
		_spawn_t -= delta
		while _spawn_t <= 0.0 and _to_spawn > 0:
			if _burst_left <= 0:
				_burst_door = randi() % 4
				_burst_left = randi_range(3, 5 + wave)
			horde.spawn(_burst_door, randf_range(0.5, 2.0), _grunt_speed())
			_to_spawn -= 1
			_burst_left -= 1
			_spawn_t += 0.12 if _burst_left > 0 else randf_range(0.5, 1.2) / (1.0 + wave * 0.1)
	elif horde.count == 0:
		if _next_wave_t < 0.0:
			_next_wave_t = 2.0
			hud.show_banner("WAVE CLEAR", 1.5)
		_next_wave_t -= delta
		if _next_wave_t <= 0.0:
			_start_wave(wave + 1)

func _update_debug(delta: float) -> void:
	hud.debug_label.visible = debug_overlay
	_debug_t -= delta
	if not debug_overlay or _debug_t > 0.0:
		return
	_debug_t = 0.25
	hud.debug_label.text = "FPS %d   process %.1f ms   arcade sim %.2f ms\n" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, _sim_avg / 1000.0,
	] + "grunts %d/%d   bullets %d   chunks %d   splats %d\n" % [
		horde.count, Horde.MAX, shots.count, gibs.chunks, gibs.splats,
	] + "F2 +%d grunts   F3 overlay   F4 god %s   C view: %s" % [
		DEBUG_SPAWN, "ON" if god else "off", "first person" if first_person else "top-down",
	]
