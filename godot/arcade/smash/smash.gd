extends Node3D
## Smash arcade: a Smash TV-style arena shooter. Self-contained: everything is built in code under this node, all
## state lives on it and its children (no autoloads, no statics, no physics bodies), and its input actions are its
## own (smash_input.gd). Made to run on its own or inside a SubViewport on an arcade cabinet.
##
## States: ATTRACT (the bot plays a demo under the title / high scores / controls screens) -> PLAY -> NAME (initials
## for a high score) -> ATTRACT. A run is rooms of waves (SmashWaves decides what each sends; every 5th room is
## Big Tony's); clearing a room pays a time / no-death bonus and opens one door, and walking out of it fades into
## the next room. Kills drop power-ups and prizes; the smart bomb clears the screen.
## Each frame: player -> spawning -> grunt grid + move -> brutes, snipers, mines, boss, enemy shots -> shield ->
## player shots -> blasts (chained) -> kills (score, gibs, drops, host) -> pickups, prizes -> effects; then every
## pool draws to its MultiMeshes.
## The cabinet can set `input_enabled` (false = ignore all input; it just keeps playing the demo) and read
## `state`, `score`, `room`, `wave`, `lives`.

const SmashVox := preload("smash_vox.gd")
const SmashInput := preload("smash_input.gd")
const SmashHorde := preload("smash_horde.gd")
const SmashBrutes := preload("smash_brutes.gd")
const SmashSnipers := preload("smash_snipers.gd")
const SmashMines := preload("smash_mines.gd")
const SmashBoss := preload("smash_boss.gd")
const SmashShots := preload("smash_shots.gd")
const SmashEShots := preload("smash_eshots.gd")
const SmashGibs := preload("smash_gibs.gd")
const SmashPickups := preload("smash_pickups.gd")
const SmashPrizes := preload("smash_prizes.gd")
const SmashHud := preload("smash_hud.gd")
const SmashSfx := preload("smash_sfx.gd")
const SmashScores := preload("smash_scores.gd")
const SmashWaves := preload("smash_waves.gd")
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
const START_BOMBS := 1
const MAX_BOMBS := 3
const GUN_Y := 0.75
const EYE_Y := 1.05
const CAM_Y := 31.5
const MOUSE_LOOK := 0.0025
const PAD_LOOK := 3.0
const SCORE_GRUNT := 100
const SCORE_BRUTE := 500
const SCORE_SNIPER := 300
const SCORE_MINE := 200
const SCORE_BOSS := 10000
const SCORE_PICKUP := 250
const NO_DEATH_BONUS := 2500
const DEBUG_SPAWN := 50
const POWER_TIME := 10.0
const SHIELD_TIME := 8.0
const BLAST := 2.6
const MINE_BLAST := 2.4
const BARREL_BLAST := 2.4
## Gib bursts per frame; past this (a smart bomb on a stress test) kills still count, they just don't burst.
const MAX_BURSTS := 250
const DEMO_LENGTH := 75.0
const ATTRACT_SCREEN := 6.0
const BOSS_NAME := "BIG TONY"
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
const LINE_BOSS_IN := "HERE COMES BIG TONY!"
const LINE_BOSS_DOWN := "WHAT A KNOCKOUT!"
const LINE_TOASTER := "A BRAND NEW TOASTER!"
const LINE_VCR := "A VCR! WHAT A PRIZE!"
const LINE_CAR := "YOU WIN A NEW CAR!"
const LINE_BOMB := "KA-BOOM!"

enum State { ATTRACT, PLAY, NAME }

## False: the game ignores all input (e.g. while the cabinet isn't being played) and keeps running its demo.
@export var input_enabled := true
@export var debug_overlay := true
## Also play the demo's sounds (off: an idle cabinet stays quiet).
@export var attract_sound := false
## False: the high-score table isn't loaded or saved (the bench).
@export var save_scores := true
## False: nothing spawns by itself (the bench uses this).
var waves_enabled := true
## The bot plays the real game, lives and all (the balance bench).
var autopilot := false
## Makes the bot more like a person (the balance bench): it only re-decides every `bot_reaction` seconds and its
## aim is off by up to `bot_aim_error` radians. The attract demo leaves both at 0.
var bot_reaction := 0.0
var bot_aim_error := 0.0
var _bot_t := 0.0
var _bot_last: Array = [Vector2.ZERO, Vector2.ZERO, false, false]
var god := false
var first_person := false
var state := State.ATTRACT

var horde: SmashHorde
var brutes: SmashBrutes
var snipers: SmashSnipers
var mines: SmashMines
var boss: SmashBoss
var shots: SmashShots
var eshots: SmashEShots
var gibs: SmashGibs
var pickups: SmashPickups
var prizes: SmashPrizes
var hud: SmashHud
var sfx: SmashSfx
var scores: SmashScores
var waves: SmashWaves
var top_cam: Camera3D
var fp_cam: Camera3D
var player: MeshInstance3D
var _targets: Array = []
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
var _beep_t := 0.0
## 0 gun, 1 spread, 2 rockets.
var weapon := 0
var weapon_t := 0.0
var shield_t := 0.0
var speed_t := 0.0
var bombs := START_BOMBS

var room := 1
var wave := 0
var wave_in_room := 0
var score := 0
var lives := START_LIVES
var kills := 0
var game_over := false
var prize_counts := PackedInt32Array([0, 0, 0, 0, 0])
var prize_total := 0
var _game_over_t := 0.0
var _ratings_at := 150
var _next_wave_t := -1.0
var _room_t := 0.0
var _room_deaths := 0
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
	waves = SmashWaves.new()
	waves.game = self
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
	brutes = SmashBrutes.new()
	snipers = SmashSnipers.new()
	mines = SmashMines.new()
	boss = SmashBoss.new()
	shots = SmashShots.new()
	eshots = SmashEShots.new()
	gibs = SmashGibs.new()
	prizes = SmashPrizes.new()
	for pool in [horde, brutes, snipers, mines, boss, shots, eshots, gibs, prizes]:
		pool.half = HALF
		if "door_half" in pool:
			pool.door_half = DOOR_HALF
		add_child(pool)
	shots.corridor = CORRIDOR
	pickups = SmashPickups.new()
	add_child(pickups)
	# what a player bullet can hit before the grunts, in order
	_targets = [boss, brutes, snipers, mines, eshots]

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

func _clear_arena() -> void:
	horde.clear()
	brutes.clear()
	snipers.clear()
	mines.clear()
	boss.clear()
	shots.clear()
	eshots.clear()
	gibs.clear()
	pickups.clear()
	prizes.clear()
	hud.hide_boss()

func _reset_run() -> void:
	_clear_arena()
	score = 0
	lives = START_LIVES
	bombs = START_BOMBS
	wave = 0
	kills = 0
	prize_counts = PackedInt32Array([0, 0, 0, 0, 0])
	prize_total = 0
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
	hud.hide_summary()
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
					hud.hide_summary()
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
	return "NEW HIGH SCORE!   %d\n\nENTER YOUR INITIALS\n\n%s\n\nup / down: letter    fire: next" % [
		score, s.strip_edges(),
	]

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
		horde.spawn(k % 4, randf_range(0.5, CORRIDOR - 0.5), waves.grunt_speed())

## Debug: straight into the next room (to try the later rooms and the boss).
func debug_next_room() -> void:
	_clear_arena()
	_start_room(room + 1, randi() % 4)

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
	elif event.is_action_pressed(SmashInput.DEBUG_ROOM):
		debug_next_room()
	elif state == State.PLAY and event.is_action_pressed(SmashInput.VIEW):
		set_first_person(not first_person)
	elif state == State.PLAY and event.is_action_pressed(SmashInput.BOMB):
		smart_bomb()
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
	# world-sized labels would fill the screen up close
	pickups.set_label_size(0.004 if on else 0.012)
	prizes.set_label_size(0.004 if on else 0.012)

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
	snipers.draw()
	mines.draw()
	shots.draw()
	eshots.draw()
	gibs.draw()
	prizes.draw()
	_place_player(delta)
	_update_doors()
	sim_usec = Time.get_ticks_usec() - t0
	_sim_avg = lerpf(_sim_avg, sim_usec, 0.05)
	hud.set_stats(room, wave, score, lives, state == State.ATTRACT)
	hud.power_label.text = _power_text()
	if boss.active:
		hud.show_boss(BOSS_NAME, float(boss.hp) / boss.max_hp)
	_update_debug(delta)

func _can_be_hurt() -> bool:
	return _alive and _invuln_t <= 0.0 and shield_t <= 0.0 and not god and state == State.PLAY

func _simulate(delta: float) -> void:
	_update_player(delta)
	if waves_enabled:
		waves.update(delta)
	horde.build_grid()
	var can_touch := _can_be_hurt()
	var touched := horde.step(delta, player_pos, PLAYER_RADIUS + SmashHorde.RADIUS, can_touch)
	if brutes.count > 0:
		touched = brutes.step(delta, player_pos, PLAYER_RADIUS + SmashBrutes.RADIUS, can_touch, horde) or touched
	if snipers.count > 0:
		touched = snipers.step(delta, player_pos, PLAYER_RADIUS + SmashSnipers.RADIUS, can_touch, eshots) or touched
		if snipers.fired > 0:
			sfx.play("sniper", 0.05)
			snipers.fired = 0
	if mines.count > 0:
		mines.step(delta, player_pos, _alive and state != State.NAME)
		_mine_beeps(delta)
	if boss.active:
		touched = boss.step(delta, self, player_pos, PLAYER_RADIUS, can_touch) or touched
	if eshots.count > 0:
		touched = eshots.step(delta, player_pos, PLAYER_RADIUS, can_touch) or touched
	if _alive and shield_t > 0.0:
		# the shield pops grunts that touch it and keeps clubbing brutes
		horde.kill_near(player_pos, 0.9)
		brutes.damage_radius(player_pos, 0.9, 1, true)
	shots.step(delta, _targets, horde)
	_blasts()
	_collect_kills()
	if touched:
		_player_hit()
	pickups.step(delta)
	if _alive:
		var t := pickups.collect(player_pos)
		if t >= 0:
			_power_up(t)
	for k in prizes.step(delta, player_pos, _alive):
		_prize(k)
	gibs.step(delta)
	if waves_enabled:
		_update_room(delta)
	_room_t += delta
	_shake *= exp(-7.0 * delta)

func _mine_beeps(delta: float) -> void:
	_beep_t -= delta
	if _beep_t > 0.0:
		return
	for i in mines.count:
		if mines.fuse[i] >= 0.0:
			sfx.play("mine")
			_beep_t = 0.12
			return

## Every blast this frame: rockets (don't hurt you), mines and barrels (do). A blast sets off the mines and
## barrels near it, which queue their own: chains run to the end (capped) in this frame.
func _blasts() -> void:
	var before := horde.kill_pos.size()
	var hurt := false
	for guard in 64:
		var p: Vector2
		var r := BLAST
		var harmful := true
		if not shots.booms.is_empty():
			p = shots.booms[shots.booms.size() - 1]
			shots.booms.remove_at(shots.booms.size() - 1)
			harmful = false
		elif not mines.booms.is_empty():
			p = mines.booms[mines.booms.size() - 1]
			mines.booms.remove_at(mines.booms.size() - 1)
			r = MINE_BLAST
		elif not eshots.booms.is_empty():
			p = eshots.booms[eshots.booms.size() - 1]
			eshots.booms.remove_at(eshots.booms.size() - 1)
			r = BARREL_BLAST
		else:
			break
		gibs.boom(p, r)
		horde.kill_radius(p, r)
		brutes.damage_radius(p, r, 4, false)
		snipers.damage_radius(p, r, SmashSnipers.HP)
		boss.damage_radius(p, r, 6)
		mines.detonate_radius(p, r * 0.8)
		eshots.detonate_radius(p, r * 0.8)
		sfx.play("boom", 0.05)
		_shake = minf(_shake + 0.5, 1.0)
		if harmful and _can_be_hurt() and p.distance_to(player_pos) < r:
			hurt = true
	shots.booms.clear()
	mines.booms.clear()
	eshots.booms.clear()
	if horde.kill_pos.size() - before >= 8:
		hud.host.say(LINE_MESS if randf() < 0.4 else LINE_DOLLAR)
	if hurt:
		_player_hit()

func _collect_kills() -> void:
	var kp := horde.kill_pos
	var n := kp.size()
	var bursts := 0
	for k in n:
		score += SCORE_GRUNT
		if bursts < MAX_BURSTS:
			bursts += 1
			gibs.burst(kp[k], horde.kill_dir[k], SmashVox.GRUNT_GIBS, 5)
		_drops(kp[k], 0.012, [[SmashPrizes.CASH, 0.025], [SmashPrizes.GOLD, 0.006]])
	if n > 0:
		sfx.play("splat", 0.04, -2.0)
		_shake = minf(_shake + 0.04 * mini(n, 10), 0.6)
	horde.kill_pos.clear()
	horde.kill_dir.clear()
	horde.compact()

	var bp := brutes.kill_pos
	for k in bp.size():
		score += SCORE_BRUTE
		gibs.burst(bp[k], brutes.kill_dir[k], SmashVox.BRUTE_GIBS, 12, SmashVox.BLOOD, 1.6)
		_drops(bp[k], 0.35, [[SmashPrizes.CASH, 0.4], [SmashPrizes.GOLD, 0.2], [SmashPrizes.TOASTER, 0.08],
				[SmashPrizes.VCR, 0.05]])
		sfx.play("brute_die")
		_shake = minf(_shake + 0.3, 1.0)
	n += bp.size()
	brutes.kill_pos.clear()
	brutes.kill_dir.clear()
	brutes.compact()
	if brutes.hits > 0:
		sfx.play("thud", 0.05)
		brutes.hits = 0

	var sp := snipers.kill_pos
	for k in sp.size():
		score += SCORE_SNIPER
		gibs.burst(sp[k], snipers.kill_dir[k], SmashVox.SNIPER_GIBS, 8)
		_drops(sp[k], 0.2, [[SmashPrizes.CASH, 0.4], [SmashPrizes.GOLD, 0.1], [SmashPrizes.TOASTER, 0.03]])
		sfx.play("brute_die", 0.05, -4.0)
	n += sp.size()
	snipers.kill_pos.clear()
	snipers.kill_dir.clear()
	snipers.compact()

	if mines.shot_down > 0:
		score += SCORE_MINE * mines.shot_down
		n += mines.shot_down
		mines.shot_down = 0

	kills += n
	if kills >= _ratings_at:
		_ratings_at += 150
		hud.host.say(LINE_RATINGS)

## Maybe drops a power-up (`power` chance) and maybe prizes ([kind, chance] each) at `p`.
func _drops(p: Vector2, power: float, prize_odds: Array) -> void:
	if randf() < power:
		_drop_power_up(p)
	for po in prize_odds:
		if randf() < po[1]:
			prizes.spawn(p, po[0])

func _drop_power_up(p: Vector2) -> void:
	var lim := HALF - 0.8
	var total := 0
	for w in SmashPickups.WEIGHTS:
		total += w
	var roll := randi() % total
	var t := 0
	while roll >= SmashPickups.WEIGHTS[t]:
		roll -= SmashPickups.WEIGHTS[t]
		t += 1
	pickups.spawn(Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim)), t)

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
		SmashPickups.BOMB:
			bombs = mini(bombs + 1, MAX_BOMBS)
	sfx.play("pickup")
	hud.host.say(LINE_DOLLAR if randf() < 0.75 else LINE_PRIZE)

func _prize(k: int) -> void:
	var v: int = SmashPrizes.VALUES[k]
	score += v
	prize_counts[k] += 1
	prize_total += v
	match k:
		SmashPrizes.CASH:
			sfx.play("cash", 0.05)
		SmashPrizes.GOLD:
			sfx.play("cash", 0.05)
			hud.host.say(LINE_DOLLAR)
		SmashPrizes.TOASTER:
			sfx.play("prize")
			hud.host.say(LINE_TOASTER, true)
		SmashPrizes.VCR:
			sfx.play("prize")
			hud.host.say(LINE_VCR, true)
		SmashPrizes.CAR:
			sfx.play("car")
			hud.host.say(LINE_CAR, true)

func _power_text() -> String:
	var s := ""
	if weapon > 0:
		s += "%s %d   " % [SmashPickups.NAMES[weapon - 1], ceili(weapon_t)]
	if shield_t > 0.0:
		s += "SHIELD %d   " % ceili(shield_t)
	if speed_t > 0.0:
		s += "SPEED %d   " % ceili(speed_t)
	if bombs > 0:
		s += "BOMBS %d" % bombs
	return s

## The smart bomb: everything on screen dies (the boss loses 15%), enemy shots vanish.
func smart_bomb() -> void:
	if bombs <= 0 or not _alive or _trans_t > 0.0:
		return
	bombs -= 1
	horde.kill_all(player_pos)
	for i in brutes.count:
		brutes.damage(i, SmashBrutes.HP, (brutes.pos[i] - player_pos).normalized())
	for i in snipers.count:
		snipers.damage(i, SmashSnipers.HP, (snipers.pos[i] - player_pos).normalized())
	score += SCORE_MINE * mines.remove_all()
	eshots.clear()
	if boss.count > 0:
		boss.damage(ceili(boss.max_hp * 0.15))
	hud.flash(Color.WHITE, 0.9)
	_shake = 1.0
	sfx.play("bomb")
	hud.host.say(LINE_BOMB)

## Big Tony's moments: sounds, shakes, gibs, score (he calls this).
func boss_event(what: String, p: Vector2) -> void:
	match what:
		"roar":
			sfx.play("roar")
			_shake = maxf(_shake, 0.4)
		"charge":
			sfx.play("charge")
		"slam":
			sfx.play("boom")
			_shake = 1.0
			for i in 10:
				gibs.puff(p + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))
		"throw":
			sfx.play("throw", 0.1)
		"boom":
			gibs.boom(p, 1.8)
			sfx.play("boom", 0.08)
			_shake = minf(_shake + 0.3, 1.0)
		"dead":
			for i in 3:
				var at := p + Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))
				gibs.burst(at, Vector2.ZERO, SmashVox.BOSS_GIBS, 16, SmashVox.BLOOD, 2.5)
			prizes.spawn(p, SmashPrizes.CAR)
			for i in 3:
				prizes.spawn(p, SmashPrizes.GOLD)
			for i in 6:
				prizes.spawn(p, SmashPrizes.CASH)
			score += SCORE_BOSS * maxi(1, room / SmashWaves.BOSS_EVERY)
			kills += 1
			sfx.play("brute_die")
			_shake = 1.0
			hud.hide_boss()
			hud.host.say(LINE_BOSS_DOWN, true)

func spawn_boss(door: int, health: int) -> void:
	boss.start(door, health)
	sfx.play("roar")
	_banner("HERE COMES " + BOSS_NAME + "!", 2.5)
	hud.host.say(LINE_BOSS_IN, true)

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
	if state == State.ATTRACT or (state == State.PLAY and autopilot):
		_bot_t -= delta
		if _bot_t <= 0.0:
			_bot_t = bot_reaction
			_bot_last = SmashBot.think(self)
			_bot_last[1] = Vector2(_bot_last[1]).rotated(randf_range(-bot_aim_error, bot_aim_error))
		var b := _bot_last
		mv = b[0]
		aim = b[1] if b[2] else Vector2.ZERO
		if b[3]:
			smart_bomb()
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
	elif _use_mouse and state == State.PLAY and not autopilot:
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
	if not _alive:
		return
	_alive = false
	lives -= 1
	_room_deaths += 1
	gibs.burst(player_pos, Vector2.ZERO, SmashVox.PLAYER_GIBS, 14)
	# whatever got you goes with you, so the respawn isn't an instant death
	horde.kill_radius(player_pos, 3.0)
	brutes.damage_radius(player_pos, 3.0, SmashBrutes.HP, false)
	snipers.damage_radius(player_pos, 3.0, SmashSnipers.HP)
	mines.detonate_radius(player_pos, 3.0)
	mines.booms.clear()
	eshots.clear()
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
		_game_over_t = 4.0
		hud.hide_banner()
		hud.show_summary(_summary_text())
		sfx.play("gameover")
		hud.host.say(LINE_BYE, true)
	else:
		_respawn_t = 1.5
		hud.host.say(LINE_DEAD, true)

func _summary_text() -> String:
	var s := "GAME OVER\n\nPRIZES WON\n"
	if prize_total == 0:
		return s + "nothing... better luck next time!"
	for k in prize_counts.size():
		if prize_counts[k] > 0:
			s += "%s x%d\n" % [SmashPrizes.NAMES[k], prize_counts[k]]
	return s + "TOTAL $%d" % prize_total

# --- rooms and waves --------------------------------------------------------------------------------------

func _banner(text: String, secs: float) -> void:
	if state != State.ATTRACT:
		hud.show_banner(text, secs)

func _start_room(r: int, from_door: int) -> void:
	room = r
	wave_in_room = 0
	entry_door = from_door
	exit_door = -1
	_room_t = 0.0
	_room_deaths = 0
	var pal: Array = ROOMS[(r - 1) % ROOMS.size()]
	_floor_mat.albedo_color = pal[0]
	_wall_mat.albedo_color = pal[1]
	_spawn_player(from_door)
	_start_wave()

func _start_wave() -> void:
	wave += 1
	wave_in_room += 1
	_next_wave_t = -1.0
	waves.start(room, wave_in_room)
	if SmashWaves.is_boss_room(room):
		_banner("ROOM %d   BOSS!" % room, 2.0)
	else:
		_banner("ROOM %d   WAVE %d" % [room, wave], 2.0)
	sfx.play("wave")

## A random door, but not the one you just came in by during the room's first wave.
func spawn_door() -> int:
	var d := randi() % 4
	if d == entry_door and wave_in_room == 1:
		d = d ^ 1
	return d

func enemies_left() -> int:
	return horde.count + brutes.count + snipers.count + mines.count + (1 if boss.active else 0)

func _update_room(delta: float) -> void:
	if game_over or exit_door >= 0 or not waves.done_spawning() or enemies_left() > 0:
		return
	if wave_in_room < SmashWaves.waves_in_room(room):
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
	# the bonus: faster is better, and more for not dying
	var time_bonus := maxi(0, 6000 - int(_room_t) * 50) / 100 * 100
	var clean := NO_DEATH_BONUS if _room_deaths == 0 else 0
	score += time_bonus + clean
	var text := "ROOM CLEAR!\nTIME BONUS %d" % time_bonus
	if clean > 0:
		text += "\nNO-DEATH BONUS %d" % clean
	_banner(text + "\nTAKE THE GREEN DOOR", 3.0)
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
		_clear_arena()
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
	] + "grunts %d/%d  brutes %d  snipers %d  mines %d  shots %d/%d  chunks %d  prizes %d\n" % [
		horde.count, SmashHorde.MAX, brutes.count, snipers.count, mines.count, shots.count, eshots.count, gibs.chunks,
		prizes.count,
	] + "F2 +%d grunts   F3 overlay   F4 god %s   PgDn next room   C view: %s" % [
		DEBUG_SPAWN, "ON" if god else "off", "first person" if first_person else "top-down",
	]
