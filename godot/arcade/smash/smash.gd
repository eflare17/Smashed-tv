extends Node3D
## Smash arcade: a Smash TV-style arena shooter. Self-contained: everything is built in code under this node, all
## state lives on it and its children (no autoloads, no statics, no physics bodies), and its input actions are its
## own (smash_input.gd). Made to run on its own or inside a SubViewport on an arcade cabinet.
##
## States: ATTRACT (the bot plays a demo under the title / high scores / controls screens) -> PLAY -> NAME (initials
## for a high score) -> ATTRACT. A run is rooms of WAVES_PER_ROOM waves; clearing a room opens one door, and
## walking out of it fades into the next room (re-tinted, harder: brutes from room 2).
## Each frame: player -> waves -> grunt grid + move -> brutes -> shield -> shots -> blasts -> kills (score, gibs,
## drops, host) -> pickups -> effects; then every pool draws to its MultiMeshes.
## The cabinet can set `input_enabled` (false = ignore all input; it just keeps playing the demo) and read
## `state`, `score`, `room`, `wave`, `lives`.

const SmashVox := preload("smash_vox.gd")
const SmashInput := preload("smash_input.gd")
const SmashHorde := preload("smash_horde.gd")
const SmashBrutes := preload("smash_brutes.gd")
const SmashShots := preload("smash_shots.gd")
const SmashGibs := preload("smash_gibs.gd")
const SmashPickups := preload("smash_pickups.gd")
const SmashHud := preload("smash_hud.gd")
const SmashSfx := preload("smash_sfx.gd")
const SmashScores := preload("smash_scores.gd")
const SmashBot := preload("smash_bot.gd")

const HALF := 10.0
const DOOR_HALF := 1.5
const CORRIDOR := 5.0
## Door inward normals: N, S, W, E (the opposite door is d ^ 1).
const DOOR_N := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
## Door -> quarter-turns from north for its frame mesh.
const DOOR_TURNS := [0, 2, 3, 1]
const PLAYER_SPEED := 6.5
const PLAYER_RADIUS := 0.3
## Seconds between shots per weapon: gun, spread, rockets.
const FIRE_GAP := [0.075, 0.1, 0.28]
const SPREAD_ANGLES := [-0.3, -0.15, 0.0, 0.15, 0.3]
const START_LIVES := 3
const GUN_Y := 0.75
const EYE_Y := 1.05
const CAM_Y := 31.5
const MOUSE_LOOK := 0.0025
const PAD_LOOK := 3.0
const SCORE_GRUNT := 100
const SCORE_BRUTE := 500
const SCORE_PICKUP := 250
const DEBUG_SPAWN := 50
const WAVES_PER_ROOM := 2
const POWER_TIME := 10.0
const SHIELD_TIME := 8.0
const BLAST := 2.6
const DROP_GRUNT := 0.03
const DROP_BRUTE := 0.5
const DEMO_LENGTH := 75.0
const ATTRACT_SCREEN := 6.0
## Floor tint, wall tint for each room (cycled).
const ROOMS := [
	[Color(0.31, 0.29, 0.27), Color(0.55, 0.22, 0.6)],
	[Color(0.2, 0.26, 0.32), Color(0.15, 0.55, 0.55)],
	[Color(0.33, 0.25, 0.17), Color(0.75, 0.38, 0.1)],
	[Color(0.21, 0.29, 0.19), Color(0.3, 0.5, 0.2)],
	[Color(0.3, 0.19, 0.24), Color(0.62, 0.15, 0.28)],
]
const DOOR_COLOR := Color(1.0, 0.6, 0.1)
const DOOR_SHUT := Color(0.45, 0.1, 0.1)
const DOOR_EXIT := Color(0.2, 1.0, 0.35)
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

const LINE_DOLLAR := "I'D BUY THAT FOR A DOLLAR!"
const LINE_PRIZE := "NOW THAT'S A PRIZE!"
const LINE_WELCOME := "WELCOME TO SMASH!"
const LINE_CLEAR := "NEXT ROOM, BIG SPENDER!"
const LINE_DEAD := "OUCH! THAT'S GOTTA HURT!"
const LINE_MESS := "WHAT A MESS!"
const LINE_RATINGS := "RATINGS ARE THROUGH THE ROOF!"
const LINE_HIGH := "A NEW HIGH SCORE!"
const LINE_BYE := "DON'T TOUCH THAT DIAL!"

enum State { ATTRACT, PLAY, NAME }

## False: the game ignores all input (e.g. while the cabinet isn't being played) and keeps running its demo.
@export var input_enabled := true
@export var debug_overlay := true
## Also play the demo's sounds (off: an idle cabinet stays quiet).
@export var attract_sound := false
## False: the high-score table isn't loaded or saved (the bench).
@export var save_scores := true
## False: no waves (the bench uses this).
var waves_enabled := true
var god := false
var first_person := false
var state := State.ATTRACT

var horde: SmashHorde
var brutes: SmashBrutes
var shots: SmashShots
var gibs: SmashGibs
var pickups: SmashPickups
var hud: SmashHud
var sfx: SmashSfx
var scores: SmashScores
var top_cam: Camera3D
var fp_cam: Camera3D
var player: MeshInstance3D
var _player_frames: Array[Mesh] = []
var _shield: MeshInstance3D
var _muzzle: MeshInstance3D
var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _door_mats: Array[StandardMaterial3D] = []

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
var _muzzle_t := 0.0
var _muzzle_pos := Vector2.ZERO
var _dust_t := 0.0
## 0 gun, 1 spread, 2 rockets.
var weapon := 0
var weapon_t := 0.0
var shield_t := 0.0
var speed_t := 0.0

var room := 1
var wave := 0
var wave_in_room := 0
var score := 0
var lives := START_LIVES
var kills := 0
var game_over := false
var _game_over_t := 0.0
var _ratings_at := 150
var _to_spawn := 0
var _brutes_to_spawn := 0
var _spawn_t := 0.0
var _burst_left := 0
var _burst_door := 0
var _next_wave_t := -1.0
## The door this room was entered by (-1: the first room), and the open exit (-1: none yet).
var entry_door := -1
var exit_door := -1
var _trans_t := 0.0
var _trans_swapped := false
var _shake := 0.0

var _state_t := 0.0
var _attract_t := 0.0
var _demo_t := 0.0
var _name := PackedInt32Array([0, 0, 0])
var _name_pos := 0
var _rank := -1

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
	# the camera shake moves cameras every frame; no physics interpolation in here
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	SmashInput.ensure_actions()
	scores = SmashScores.new()
	scores.persist = save_scores
	scores.load_table()
	_build()
	start_attract(false)

func _exit_tree() -> void:
	if first_person:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build() -> void:
	_floor_mat = SmashVox.flat_material()
	_wall_mat = SmashVox.flat_material()
	_add_mesh("Floor", SmashVox.floor_mesh(HALF, DOOR_HALF, CORRIDOR), _floor_mat)
	_add_mesh("Walls", SmashVox.walls_mesh(HALF, DOOR_HALF, CORRIDOR), _wall_mat)
	for d in 4:
		var mat := SmashVox.flat_material()
		mat.albedo_color = DOOR_COLOR
		_door_mats.append(mat)
		_add_mesh("Door%d" % d, SmashVox.door_mesh(HALF, DOOR_HALF, DOOR_TURNS[d]), mat)

	horde = SmashHorde.new()
	horde.half = HALF
	horde.door_half = DOOR_HALF
	add_child(horde)
	brutes = SmashBrutes.new()
	brutes.half = HALF
	brutes.door_half = DOOR_HALF
	add_child(brutes)
	shots = SmashShots.new()
	shots.half = HALF
	shots.door_half = DOOR_HALF
	shots.corridor = CORRIDOR
	add_child(shots)
	gibs = SmashGibs.new()
	gibs.half = HALF
	gibs.door_half = DOOR_HALF
	add_child(gibs)
	pickups = SmashPickups.new()
	add_child(pickups)

	var mat := SmashVox.flat_material()
	for f in 2:
		var m := SmashVox.player_mesh(f)
		m.surface_set_material(0, mat)
		_player_frames.append(m)
	player = _add_mesh("Player", _player_frames[0], null)
	var ball := SphereMesh.new()
	ball.radius = 0.85
	ball.height = 1.4
	ball.radial_segments = 8
	ball.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.albedo_color = Color(0.35, 0.9, 1.0, 0.25)
	_shield = _add_mesh("Shield", ball, smat)
	_shield.visible = false
	_muzzle = _add_mesh("Muzzle", SmashVox.box_mesh(Vector3.ONE * 0.3, Color(1.0, 0.95, 0.6)), SmashVox.flat_material())
	_muzzle.visible = false

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
	top_cam.position = Vector3(0, CAM_Y, 0)
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

	sfx = SmashSfx.new()
	add_child(sfx)
	hud = SmashHud.new()
	add_child(hud)
	hud.host.sfx = sfx

func _add_mesh(n: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

# --- states -----------------------------------------------------------------------------------------------

func start_game() -> void:
	state = State.PLAY
	_state_t = 0.0
	_reset_run()
	sfx.enabled = true
	sfx.play("coin")
	hud.hide_attract()
	hud.hide_name()
	hud.host.say(LINE_WELCOME, true)

## The demo, under the title screens; `show_scores` starts on the high-score table.
func start_attract(show_scores: bool) -> void:
	state = State.ATTRACT
	_state_t = 0.0
	if first_person:
		set_first_person(false)
	_reset_run()
	sfx.enabled = attract_sound
	_attract_t = ATTRACT_SCREEN if show_scores else 0.0
	_demo_t = 0.0
	hud.hide_name()
	hud.host.hide_now()
	hud.set_table(scores.entries, _rank)

func _reset_run() -> void:
	horde.clear()
	brutes.clear()
	shots.clear()
	gibs.clear()
	pickups.clear()
	score = 0
	lives = START_LIVES
	wave = 0
	kills = 0
	_ratings_at = 150
	weapon = 0
	weapon_t = 0.0
	shield_t = 0.0
	speed_t = 0.0
	game_over = false
	_trans_t = 0.0
	_shake = 0.0
	hud.set_fade(0.0)
	hud.hide_banner()
	_start_room(1, -1)

func _update_state(delta: float) -> void:
	_state_t += delta
	match state:
		State.ATTRACT:
			_attract_t += delta
			_demo_t += delta
			hud.show_attract(int(_attract_t / ATTRACT_SCREEN) % 3, int(_attract_t * 2.0) % 2 == 0)
			if _demo_t > DEMO_LENGTH:
				_reset_run()
				_demo_t = 0.0
		State.PLAY:
			hud.hide_attract()
			if game_over:
				_game_over_t -= delta
				if _game_over_t <= 0.0:
					hud.hide_banner()
					if scores.qualifies(score):
						_begin_name()
					else:
						_rank = -1
						start_attract(true)
		State.NAME:
			hud.hide_attract()
			hud.show_name(_name_text())

func _begin_name() -> void:
	state = State.NAME
	_state_t = 0.0
	if first_person:
		set_first_person(false)
	_name = PackedInt32Array([0, 0, 0])
	_name_pos = 0
	hud.hide_banner()
	sfx.play("coin")
	hud.host.say(LINE_HIGH, true)

func _name_text() -> String:
	var s := ""
	for i in 3:
		var ch := LETTERS[_name[i]]
		if i == _name_pos and int(_state_t * 4.0) % 2 == 0:
			ch = "_"
		s += ch + " "
	return "NEW HIGH SCORE!   %d\n\nENTER YOUR INITIALS\n\n%s\n\nup / down: letter    fire: next" % [score, s.strip_edges()]

func _name_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var u: int = event.unicode
		if (u >= 65 and u <= 90) or (u >= 97 and u <= 122):
			_name[_name_pos] = String.chr(u).to_upper().unicode_at(0) - 65
			_name_next()
			return
		if event.keycode == KEY_BACKSPACE:
			_name_pos = maxi(0, _name_pos - 1)
			sfx.play("blip")
			return
	if event.is_action_pressed(SmashInput.AIM_UP) or event.is_action_pressed(SmashInput.MOVE_UP):
		_name[_name_pos] = (_name[_name_pos] + 1) % 26
		sfx.play("blip")
	elif event.is_action_pressed(SmashInput.AIM_DOWN) or event.is_action_pressed(SmashInput.MOVE_DOWN):
		_name[_name_pos] = (_name[_name_pos] + 25) % 26
		sfx.play("blip")
	elif event.is_action_pressed(SmashInput.AIM_RIGHT) or event.is_action_pressed(SmashInput.MOVE_RIGHT):
		_name_pos = mini(2, _name_pos + 1)
		sfx.play("blip")
	elif event.is_action_pressed(SmashInput.AIM_LEFT) or event.is_action_pressed(SmashInput.MOVE_LEFT):
		_name_pos = maxi(0, _name_pos - 1)
		sfx.play("blip")
	elif event.is_action_pressed(SmashInput.START):
		_name_done()
	elif event.is_action_pressed(SmashInput.FIRE):
		_name_next()

func _name_next() -> void:
	sfx.play("blip")
	if _name_pos < 2:
		_name_pos += 1
	else:
		_name_done()

func _name_done() -> void:
	var nm := ""
	for i in 3:
		nm += LETTERS[_name[i]]
	_rank = scores.insert(nm, score, room)
	start_attract(true)

# --- input ------------------------------------------------------------------------------------------------

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

	if state == State.NAME:
		_name_input(event)
		return
	if event.is_action_pressed(SmashInput.DEBUG_SPAWN):
		spawn_debug(DEBUG_SPAWN)
	elif event.is_action_pressed(SmashInput.DEBUG_OVERLAY):
		debug_overlay = not debug_overlay
	elif event.is_action_pressed(SmashInput.DEBUG_GOD):
		god = not god
	elif state == State.PLAY and event.is_action_pressed(SmashInput.VIEW):
		set_first_person(not first_person)
	elif state == State.ATTRACT and _state_t > 0.6 and (event.is_action_pressed(SmashInput.START)
			or event.is_action_pressed(SmashInput.FIRE)):
		start_game()

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
	# world-sized pickup labels would fill the screen up close
	pickups.set_label_size(0.004 if on else 0.012)

# --- frame ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var t0 := Time.get_ticks_usec()
	hud.tick(delta)
	_update_state(delta)
	if _trans_t > 0.0:
		_update_transition(delta)
	else:
		_simulate(delta)
	horde.draw()
	brutes.draw()
	shots.draw()
	gibs.draw()
	_place_player(delta)
	_update_doors()
	sim_usec = Time.get_ticks_usec() - t0
	_sim_avg = lerpf(_sim_avg, sim_usec, 0.05)
	hud.set_stats(room, wave, score, lives, state == State.ATTRACT)
	hud.power_label.text = _power_text()
	_update_debug(delta)

func _simulate(delta: float) -> void:
	_update_player(delta)
	if waves_enabled:
		_update_waves(delta)
	horde.build_grid()
	var can_touch := _alive and _invuln_t <= 0.0 and shield_t <= 0.0 and not god and state == State.PLAY
	var touched := horde.step(delta, player_pos, PLAYER_RADIUS + SmashHorde.RADIUS, can_touch)
	if brutes.count > 0:
		touched = brutes.step(delta, player_pos, PLAYER_RADIUS + SmashBrutes.RADIUS, can_touch, horde) or touched
	if _alive and shield_t > 0.0:
		# the shield pops grunts that touch it and keeps clubbing brutes
		horde.kill_near(player_pos, 0.9)
		brutes.damage_radius(player_pos, 0.9, 1, true)
	shots.step(delta, horde, brutes)
	_explode()
	_collect_kills()
	if touched:
		_player_hit()
	pickups.step(delta)
	if _alive:
		var t := pickups.collect(player_pos)
		if t >= 0:
			_power_up(t)
	gibs.step(delta)
	_shake *= exp(-7.0 * delta)

func _explode() -> void:
	if shots.booms.is_empty():
		return
	var before := horde.kill_pos.size()
	for p in shots.booms:
		gibs.boom(p, BLAST)
		horde.kill_radius(p, BLAST)
		brutes.damage_radius(p, BLAST, 4, false)
		sfx.play("boom", 0.05)
		_shake = minf(_shake + 0.5, 1.0)
	shots.booms.clear()
	if horde.kill_pos.size() - before >= 8:
		hud.host.say(LINE_MESS if randf() < 0.4 else LINE_DOLLAR)

func _collect_kills() -> void:
	var kp := horde.kill_pos
	var n := kp.size()
	for k in n:
		score += SCORE_GRUNT
		gibs.burst(kp[k], horde.kill_dir[k], SmashVox.GRUNT_GIBS, 5)
		if randf() < DROP_GRUNT:
			_drop(kp[k])
	if n > 0:
		sfx.play("splat", 0.04, -2.0)
		_shake = minf(_shake + 0.04 * n, 0.6)
	horde.kill_pos.clear()
	horde.kill_dir.clear()
	horde.compact()
	var bp := brutes.kill_pos
	for k in bp.size():
		score += SCORE_BRUTE
		gibs.burst(bp[k], brutes.kill_dir[k], SmashVox.BRUTE_GIBS, 12, SmashVox.BLOOD, 1.6)
		if randf() < DROP_BRUTE:
			_drop(bp[k])
		sfx.play("brute_die")
		_shake = minf(_shake + 0.3, 1.0)
	kills += n + bp.size()
	brutes.kill_pos.clear()
	brutes.kill_dir.clear()
	brutes.compact()
	if brutes.hits > 0:
		sfx.play("thud", 0.05)
		brutes.hits = 0
	if kills >= _ratings_at:
		_ratings_at += 150
		hud.host.say(LINE_RATINGS)

func _drop(p: Vector2) -> void:
	var lim := HALF - 0.8
	pickups.spawn(Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim)), randi() % 4)

func _power_up(t: int) -> void:
	score += SCORE_PICKUP
	match t:
		SmashPickups.SPREAD:
			weapon = 1
			weapon_t = POWER_TIME
		SmashPickups.ROCKETS:
			weapon = 2
			weapon_t = POWER_TIME
		SmashPickups.SHIELD:
			shield_t = SHIELD_TIME
		SmashPickups.SPEED:
			speed_t = POWER_TIME
	sfx.play("pickup")
	hud.host.say(LINE_DOLLAR if randf() < 0.75 else LINE_PRIZE)

func _power_text() -> String:
	var s := ""
	if weapon > 0:
		s += "%s %d   " % [SmashPickups.NAMES[weapon - 1], ceili(weapon_t)]
	if shield_t > 0.0:
		s += "SHIELD %d   " % ceili(shield_t)
	if speed_t > 0.0:
		s += "SPEED %d" % ceili(speed_t)
	return s

# --- player -----------------------------------------------------------------------------------------------

func _update_player(delta: float) -> void:
	if not _alive:
		_respawn_t -= delta
		if _respawn_t <= 0.0 and not game_over:
			_spawn_player(-1)
		return
	_invuln_t -= delta
	weapon_t -= delta
	shield_t -= delta
	speed_t -= delta
	if weapon_t <= 0.0:
		weapon = 0
	var mv := Vector2.ZERO
	var aim := Vector2.ZERO
	var firing := false
	if state == State.ATTRACT:
		var b := SmashBot.think(self)
		mv = b[0]
		aim = b[1] if b[2] else Vector2.ZERO
	elif state == State.PLAY and input_enabled:
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
	elif _use_mouse and state == State.PLAY:
		var to := _mouse_ground() - player_pos
		if to.length() > 0.2:
			player_face = to.normalized()
	elif mv.length() > 0.1:
		player_face = mv.normalized()

	var prev := player_pos
	player_pos += mv * (PLAYER_SPEED * (1.6 if speed_t > 0.0 else 1.0) * delta)
	player_pos = _clamp_player(player_pos, prev)
	var moving := mv.length() > 0.1
	_player_phase = _player_phase + delta * (16.0 if speed_t > 0.0 else 10.0) if moving else 0.0
	if speed_t > 0.0 and moving:
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.05
			gibs.puff(player_pos)

	_fire_t -= delta
	if firing and _fire_t <= 0.0:
		_fire_t = maxf(_fire_t + FIRE_GAP[weapon], 0.0)
		var f := player_face
		var right := Vector2(-f.y, f.x)
		# from the gun; in first person from a bit further out so the tracer isn't in your face
		var muzzle := player_pos + (f * 1.1 + right * 0.15 if first_person else f * 0.65 + right * 0.3)
		match weapon:
			0:
				shots.fire(muzzle, f.rotated(randf_range(-0.04, 0.04)))
				sfx.gun("shot")
			1:
				for a: float in SPREAD_ANGLES:
					shots.fire(muzzle, f.rotated(a + randf_range(-0.02, 0.02)))
				sfx.gun("spread")
			2:
				shots.fire(muzzle, f, SmashShots.ROCKET)
				sfx.gun("rocket")
		_muzzle_t = 0.05
		_muzzle_pos = muzzle
	elif not firing:
		_fire_t = maxf(_fire_t, 0.0)

## Keeps the player in the room, except through the open exit's door gap and down its corridor (going far enough
## down it starts the move to the next room).
func _clamp_player(p: Vector2, prev: Vector2) -> Vector2:
	var lim := HALF - PLAYER_RADIUS
	if exit_door >= 0:
		var out: Vector2 = -DOOR_N[exit_door]
		var t := Vector2(out.y, -out.x)
		var gap := DOOR_HALF - PLAYER_RADIUS
		var o := p.dot(out)
		var lat := p.dot(t)
		if o > lim and (prev.dot(out) > lim or absf(lat) < gap):
			o = minf(o, HALF + 3.0)
			if o > HALF + 0.8 and _trans_t <= 0.0:
				_begin_transition()
			return out * o + t * clampf(lat, -gap, gap)
	return Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim))

func _mouse_ground() -> Vector2:
	var mp := get_viewport().get_mouse_position()
	var o := top_cam.project_ray_origin(mp)
	var n := top_cam.project_ray_normal(mp)
	if absf(n.y) < 0.001:
		return player_pos + player_face
	var hit := o + n * ((GUN_Y - o.y) / n.y)
	return Vector2(hit.x, hit.z)

func _place_player(delta: float) -> void:
	var f := player_face
	player.position = Vector3(player_pos.x, 0, player_pos.y)
	player.basis = Basis(Vector3(f.y, 0, -f.x), Vector3.UP, Vector3(f.x, 0, f.y))
	player.mesh = _player_frames[int(_player_phase / PI) & 1]
	player.visible = _alive and not first_person and (_invuln_t <= 0.0 or int(_invuln_t * 10.0) % 2 == 0)
	_shield.visible = _alive and shield_t > 0.0 and (shield_t > 2.0 or int(shield_t * 8.0) % 2 == 0)
	_shield.position = Vector3(player_pos.x, 0.6, player_pos.y)
	_muzzle_t -= delta
	_muzzle.visible = _alive and _muzzle_t > 0.0
	if _muzzle.visible:
		_muzzle.position = Vector3(_muzzle_pos.x, GUN_Y, _muzzle_pos.y)
		_muzzle.rotation.y = randf() * TAU
		_muzzle.scale = Vector3.ONE * randf_range(0.7, 1.3) * (2.0 if weapon == 2 else 1.0)
	var sh := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	top_cam.position = Vector3(sh.x * 0.45, CAM_Y, sh.y * 0.45)
	if first_person:
		fp_cam.position = Vector3(player_pos.x, EYE_Y, player_pos.y)
		fp_cam.rotation = Vector3(_pitch + sh.y * 0.04, _yaw + PI + sh.x * 0.04, 0)

func _spawn_player(door: int) -> void:
	if door < 0:
		player_pos = Vector2.ZERO
		player_face = Vector2(0, -1)
	else:
		player_face = DOOR_N[door]
		player_pos = -player_face * (HALF - 1.2)
	_alive = true
	_invuln_t = 2.0
	_fire_t = 0.0
	_yaw = atan2(player_face.x, player_face.y)

func _player_hit() -> void:
	_alive = false
	lives -= 1
	gibs.burst(player_pos, Vector2.ZERO, SmashVox.PLAYER_GIBS, 14)
	# whatever got you goes with you, so the respawn isn't an instant death
	horde.kill_radius(player_pos, 3.0)
	brutes.damage_radius(player_pos, 3.0, SmashBrutes.HP, false)
	_collect_kills()
	weapon = 0
	weapon_t = 0.0
	shield_t = 0.0
	speed_t = 0.0
	sfx.play("die")
	hud.hurt()
	_shake = 1.0
	if lives <= 0:
		game_over = true
		_game_over_t = 3.0
		_banner("GAME OVER", 0.0)
		sfx.play("gameover")
		hud.host.say(LINE_BYE, true)
	else:
		_respawn_t = 1.5
		hud.host.say(LINE_DEAD, true)

# --- rooms and waves --------------------------------------------------------------------------------------

func _banner(text: String, secs: float) -> void:
	if state != State.ATTRACT:
		hud.show_banner(text, secs)

func _start_room(r: int, from_door: int) -> void:
	room = r
	wave_in_room = 0
	entry_door = from_door
	exit_door = -1
	var pal: Array = ROOMS[(r - 1) % ROOMS.size()]
	_floor_mat.albedo_color = pal[0]
	_wall_mat.albedo_color = pal[1]
	_spawn_player(from_door)
	_start_wave()

func _start_wave() -> void:
	wave += 1
	wave_in_room += 1
	_to_spawn = 15 + wave * 10
	_brutes_to_spawn = (room - 1) * 2 + (wave_in_room - 1)
	_spawn_t = 1.5
	_burst_left = 0
	_next_wave_t = -1.0
	_banner("ROOM %d   WAVE %d" % [room, wave], 2.0)
	sfx.play("wave")

func _grunt_speed() -> float:
	return minf(2.4 + wave * 0.15, 4.5) * randf_range(0.85, 1.15)

func _brute_speed() -> float:
	return minf(1.6 + room * 0.1, 2.6) * randf_range(0.9, 1.1)

## A random door, but not the one you just came in by during the room's first wave.
func _spawn_door() -> int:
	var d := randi() % 4
	if d == entry_door and wave_in_room == 1:
		d = d ^ 1
	return d

func _update_waves(delta: float) -> void:
	if game_over or exit_door >= 0:
		return
	if _to_spawn > 0 or _brutes_to_spawn > 0:
		# grunts pour in bursts, each burst from one door; a brute sometimes leads one
		_spawn_t -= delta
		while _spawn_t <= 0.0 and (_to_spawn > 0 or _brutes_to_spawn > 0):
			if _burst_left <= 0:
				_burst_door = _spawn_door()
				_burst_left = randi_range(3, 5 + wave)
				if _brutes_to_spawn > 0 and (randf() < 0.35 or _to_spawn == 0):
					brutes.spawn(_burst_door, randf_range(0.8, 2.0), _brute_speed())
					_brutes_to_spawn -= 1
			if _to_spawn > 0:
				horde.spawn(_burst_door, randf_range(0.5, 2.0), _grunt_speed())
				_to_spawn -= 1
			_burst_left -= 1
			_spawn_t += 0.12 if _burst_left > 0 else randf_range(0.5, 1.2) / (1.0 + wave * 0.1)
	elif horde.count == 0 and brutes.count == 0:
		if wave_in_room < WAVES_PER_ROOM:
			if _next_wave_t < 0.0:
				_next_wave_t = 2.0
				_banner("WAVE CLEAR", 1.5)
			_next_wave_t -= delta
			if _next_wave_t <= 0.0:
				_start_wave()
		else:
			_open_exit()

func _open_exit() -> void:
	var options := [0, 1, 2, 3]
	options.erase(entry_door)
	exit_door = options[randi() % options.size()]
	_banner("ROOM CLEAR!\nTAKE THE GREEN DOOR", 2.5)
	sfx.play("door")
	hud.host.say(LINE_CLEAR, true)

func _begin_transition() -> void:
	_trans_t = 1.0
	_trans_swapped = false

## One second: fade to black, swap in the next room at the darkest point, fade back.
func _update_transition(delta: float) -> void:
	_trans_t -= delta
	var k := 1.0 - maxf(_trans_t, 0.0)
	if k >= 0.5 and not _trans_swapped:
		_trans_swapped = true
		horde.clear()
		brutes.clear()
		shots.clear()
		gibs.clear()
		pickups.clear()
		_start_room(room + 1, exit_door ^ 1)
	hud.set_fade(k * 2.0 if k < 0.5 else (1.0 - k) * 2.0)

func _update_doors() -> void:
	var blink := (Time.get_ticks_msec() / 250) % 2 == 0
	for d in 4:
		var c := DOOR_COLOR
		if exit_door >= 0:
			c = (DOOR_EXIT if blink else Color.WHITE) if d == exit_door else DOOR_SHUT
		if _door_mats[d].albedo_color != c:
			_door_mats[d].albedo_color = c

func _update_debug(delta: float) -> void:
	hud.debug_label.visible = debug_overlay
	_debug_t -= delta
	if not debug_overlay or _debug_t > 0.0:
		return
	_debug_t = 0.25
	hud.debug_label.text = "FPS %d   process %.1f ms   arcade sim %.2f ms\n" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, _sim_avg / 1000.0,
	] + "grunts %d/%d   brutes %d   bullets %d   chunks %d   splats %d\n" % [
		horde.count, SmashHorde.MAX, brutes.count, shots.count, gibs.chunks, gibs.splats,
	] + "F2 +%d grunts   F3 overlay   F4 god %s   C view: %s" % [
		DEBUG_SPAWN, "ON" if god else "off", "first person" if first_person else "top-down",
	]
