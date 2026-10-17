class_name Player
extends CharacterBody3D
## CONTRACT. The player. Owned by the Player and cameras task. Others may read these:
##
## Moves the way the HTML game's player step does (Smashed.html, the "players" loop of the game step):
## accelerate at T.accel toward where you steer, brake at T.friction when you let go, capped at T.maxSpeed;
## Shift is the dive roll (T.rollSpeed through ROLL_FRAMES' speeds over T.rollTime, then T.rollCooldown before
## the next). All tuning stays in HTML units (game_data.json's T table) and is converted to metres at the edge.
## Top-down: W is up the screen (north, HTML -y). First person: relative to where you look (shroomInput).
## E uses the nearest Interactable that has something to do (label_for != "") within its reach.
##
## Collision: a capsule T.radius wide on collision layer 2 ("players", GameData.LAYER_PLAYERS), hitting layer 1
## (the World's walls and solids). The feet are on this node's origin; the body stands at dz (HTML units) above
## the floor (y = 0), which the trampoline sets.
##
## The clock: he steps in _physics_process, 120 times a second (the HTML game's FIXED_DT), and physics
## interpolation draws him smoothly between steps. Whoever moves him by hand (a teleport) calls place() or
## reset_physics_interpolation() after. visual_pos() is where he's drawn this frame (for cameras).

signal interacted(target: Node)

## HTML-game state the other parts look at.
var char_id: String = "juicy":                ## a key of the manifest's CHARS ("juicy", "tyson2", "goth")
	set(v):
		char_id = v
		if sprite:
			sprite.char_id = v
var facing: Vector2 = Vector2(0, 1)      ## where he faces, HTML ground axes
var odo: float = 0.0                     ## distance walked, HTML units
var moving: bool = false
var dz: float = 0.0                      ## height off the ground, HTML units (the trampoline sets it)
var on_tramp: bool = false               ## up on the trampoline: the trampoline moves him up and down
var frozen: bool = false                 ## something else is in charge of him (the trampoline's climb on)

## --- Not contract (others may read them; set them only if you know why) ---
## Velocity on the ground, HTML units a second (the HTML game's p.vx, p.vy).
var vel: Vector2 = Vector2.ZERO
## Time left in the dive roll (p.roll), the cooldown before the next (p.rollCd), and its direction (p.rdx/rdy).
var roll: float = 0.0
var roll_cd: float = 0.0
var roll_dir: Vector2 = Vector2(0, 1)
## The steering as last read, HTML ground axes, length 0..1 (p.ix/iy while moving).
var steer: Vector2 = Vector2.ZERO
## First person: where he looks, as the HTML game's SHROOM.ang (atan2 of the HTML ground direction) and
## lookY (radians, + is down, held to +-0.6). The CameraRig turns these with the mouse; WASD goes by look_ang.
var look_ang: float = -PI / 2.0
var look_y: float = 0.0
## The CameraRig showing him (set by the rig when its target is set): first person changes the steering.
var rig: Node = null
## Read the keyboard (false: stands still, for cut scenes or a second player driven by something else).
var controls_enabled: bool = true
## Top-down with a mouse over the window: face the cursor, like the HTML game (it aims at the mouse).
var face_mouse: bool = true
## Where something other than the mouse or a pad aims him top-down (the touch layer's right stick), HTML ground
## axes, length 0..1; under 0.3 it's ignored.
var aim_override: Vector2 = Vector2.ZERO
## The Interactable E would use now, and what it says ("" for nothing). Updated every frame.
var focus: Node = null
var focus_label: String = ""
## The character picture (a CharSprite child, made in _ready if the scene doesn't have one).
var sprite: CharSprite

var _mouse_seen: bool = false
var _roll_tap: bool = false               # a Shift (or pad button) press since the last step (consumeRollTap)
var _mouse_in: bool = true
var _shape: CollisionShape3D

const BODY_H := 66.0          # how tall the capsule is, HTML units (his eyes are at 62)
const LIFT := 0.8             # the capsule's bottom just off the floor, HTML units

func _enter_tree() -> void:
	add_to_group("player")

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = GameData.LAYER_PLAYERS
	collision_mask = GameData.LAYER_WORLD
	wall_min_slide_angle = 0.0
	safe_margin = 0.004
	_shape = null
	for c in get_children():
		if c is CollisionShape3D:
			_shape = c
		elif c is CharSprite and sprite == null:
			sprite = c
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Body"
		add_child(_shape)
	var cap := CapsuleShape3D.new()
	cap.radius = _t("radius") * GameData.UNIT
	cap.height = BODY_H * GameData.UNIT
	_shape.shape = cap
	_shape.position = Vector3(0, (LIFT + BODY_H / 2.0) * GameData.UNIT, 0)
	if sprite == null:
		sprite = CharSprite.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.auto_update = false
	sprite.char_id = char_id
	add_pad_bindings()

## Give the input actions their controller buttons too, the HTML game's pad layout (b314): left stick moves,
## A is E, B / RB / LT roll, View (Back) is first person. Only adds what an action doesn't already have.
static func add_pad_bindings() -> void:
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for a in axes:
		if not InputMap.has_action(a) or _has_pad_event(a):
			continue
		var m := InputEventJoypadMotion.new()
		m.axis = axes[a][0]
		m.axis_value = axes[a][1]
		InputMap.action_add_event(a, m)
	var buttons := {"interact": [JOY_BUTTON_A], "roll": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
		"toggle_view": [JOY_BUTTON_BACK]}
	for a in buttons:
		if not InputMap.has_action(a) or _has_pad_event(a):
			continue
		for b in buttons[a]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(a, e)
		if a == "roll":
			var lt := InputEventJoypadMotion.new()
			lt.axis = JOY_AXIS_TRIGGER_LEFT
			lt.axis_value = 1.0
			InputMap.action_add_event(a, lt)

static func _has_pad_event(action: String) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return true
	return false

## Where he is in HTML units (x, y on the ground, z up).
func html_pos() -> Vector3:
	return GameData.from_3d(global_position)

## Put him somewhere, in HTML units.
func place(x: float, y: float) -> void:
	global_position = GameData.world_to_3d(x, y, 0.0)
	reset_physics_interpolation()

## Where he's drawn this frame (between two physics steps), HTML units: for cameras and anything drawn by him.
func visual_pos() -> Vector3:
	if is_inside_tree():
		return GameData.from_3d(get_global_transform_interpolated().origin)
	return html_pos()

## --- Not contract ---

## Stop dead (velocity and roll), e.g. when something else takes him somewhere.
func halt() -> void:
	vel = Vector2.ZERO
	velocity = Vector3.ZERO
	roll = 0.0
	moving = false

## In first person (his rig shows him through his eyes)?
func is_first_person() -> bool:
	return rig != null and rig.get("mode") == 1 and rig.get("target") == self

## E: use what's in front of him (the HUD's round button calls this too).
func use() -> void:
	if frozen or focus == null or not is_instance_valid(focus):
		return
	if focus.has_method("act"):
		focus.act(self)
	interacted.emit(focus)
	_update_focus()

## The steering from the keyboard, HTML ground axes (x across, y down the screen), length up to 1.
func read_steer() -> Vector2:
	if not controls_enabled:
		return Vector2.ZERO
	var mx := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var my := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	if not is_first_person() and pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() < 0.01:
		# the look actions (the arrows) move him too, like the HTML game's player 1 when he's alone (in first
		# person they look round); not when they come from a pad's right stick, which aims
		mx += Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
		my += Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
		mx = clampf(mx, -1.0, 1.0)
		my = clampf(my, -1.0, 1.0)
	var m := Vector2(mx, my)
	if is_first_person():
		# shroomInput: forward is where you look, right is a quarter turn clockwise of it (screen axes)
		var f := Vector2(cos(look_ang), sin(look_ang))
		var r := Vector2(-f.y, f.x)
		var fwd := -m.y
		var side := m.x
		m = f * fwd + r * side
	return m

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_seen = true
		_mouse_in = true
	if not controls_enabled:
		return
	if event.is_action_pressed("roll") and not event.is_echo():
		_roll_tap = true                       # a tap shorter than a frame still rolls
	if event.is_action_pressed("interact") and not event.is_echo():
		use()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse_in = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		_mouse_in = true

func _physics_process(delta: float) -> void:
	# one physics tick (1/120 s, the HTML game's FIXED_DT): the same dt moves him, steers him and runs his timers
	if not frozen:
		_step(minf(delta, 0.1))

func _process(_delta: float) -> void:
	_update_focus()
	_update_sprite()

# The HTML game's player step, for one physics tick.
func _step(dt: float) -> void:
	roll = maxf(0.0, roll - dt)
	roll_cd = maxf(0.0, roll_cd - dt)
	var inp := read_steer()
	var mlen := inp.length()
	if mlen > 0.001:
		steer = inp / maxf(mlen, 1.0)
		moving = true
	else:
		steer = Vector2.ZERO
		moving = false
	var tap := _roll_tap
	_roll_tap = false
	var want_roll := controls_enabled and (Input.is_action_pressed("roll") or tap) and not on_tramp   # on the trampoline Shift bounces higher (the trampoline reads it)
	# ---- dive roll: committed, directional, brief
	if want_roll and roll <= 0.0 and roll_cd <= 0.0:
		var d := inp
		if d.length() > 0.001:
			d = d.normalized()                                  # roll where you're steering
		else:
			d = facing.normalized() if facing.length() > 0.001 else Vector2(0, 1)
		roll = _t("rollTime")
		roll_cd = _t("rollTime") + _t("rollCooldown")
		roll_dir = d
		vel = d * _t("rollSpeed")
	if roll > 0.0:
		# mid-roll you're committed: speed from the frame table, so what you see is what moves him
		var frac := clampf(1.0 - roll / maxf(0.05, _t("rollTime")), 0.0, 0.9999)
		var fr := CharFrames.ROLL_FRAMES
		var acc := 0.0
		var i := fr.size() - 1
		var tt := 1.0
		for n in fr.size():
			var dd: float = fr[n]["dur"]
			if frac < acc + dd:
				i = n
				tt = (frac - acc) / dd
				break
			acc += dd
		var s0: float = fr[i]["speed"]
		var s1: float = fr[mini(fr.size() - 1, i + 1)]["speed"]
		vel = roll_dir * ((s0 + (s1 - s0) * tt) * _t("rollSpeed"))
		facing = roll_dir
	else:
		if mlen > 0.001:
			var n := inp / mlen if mlen > 1.0 else inp
			vel += n * _t("accel") * dt
			facing = n.normalized()
		else:
			var sp := vel.length()
			if sp > 0.0:
				var drop := minf(sp, _t("friction") * dt)
				vel -= vel / sp * drop
		# aim: first person faces where you look; top-down with a mouse, the cursor
		var stick := pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y) if controls_enabled else Vector2.ZERO
		if is_first_person():
			facing = Vector2(cos(look_ang), sin(look_ang))
		elif aim_override.length() > 0.3 and controls_enabled:
			facing = aim_override.normalized()                     # the touch layer's right stick
			_mouse_seen = false
		elif stick.length() > 0.3:
			facing = stick.normalized()                            # the right stick aims (b314)
			_mouse_seen = false
		elif face_mouse and _mouse_seen and _mouse_in and controls_enabled:
			var at = _mouse_ground()
			if at != null:
				var hp := html_pos()
				var a: Vector2 = Vector2(at.x - hp.x, at.y - hp.y)
				if a.length() > 0.001:
					facing = a.normalized()
		var cap := _t("maxSpeed")
		var sp2 := vel.length()
		if sp2 > cap:
			vel = vel / sp2 * cap
	odo += vel.length() * dt                       # drives the run cycle
	# move, sliding along walls and solids (the HTML game zeroes the blocked part, like a slide); move_and_slide
	# moves by the physics step, so scale to dt in case it was clamped
	velocity = Vector3(vel.x, 0.0, vel.y) * GameData.UNIT * (dt / maxf(get_physics_process_delta_time(), 0.0001))
	global_position.y = dz * GameData.UNIT
	move_and_slide()
	# what hit something loses the part of its speed going into it (lobbyClamp: hit.x -> vx = 0)
	for i in get_slide_collision_count():
		var n3 := get_slide_collision(i).get_normal()
		var n := Vector2(n3.x, n3.z)
		if n.length() < 0.2:
			continue
		n = n.normalized()
		var into := vel.dot(n)
		if into < 0.0:
			vel -= n * into
	global_position.y = dz * GameData.UNIT

## A stick of the first connected controller, round dead zone 0.2 (padStick), or zero.
static func pad_stick(ax: int, ay: int, dead: float = 0.2) -> Vector2:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(pads[0], ax), Input.get_joy_axis(pads[0], ay))
	var m := v.length()
	if m < dead:
		return Vector2.ZERO
	return v / m * minf(1.0, (m - dead) / (1.0 - dead))

# Where the mouse points on the ground plane (HTML units), or null.
func _mouse_ground():
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 0.0001:
		return null
	var k := (global_position.y - o.y) / d.y
	if k < 0.0:
		return null
	return GameData.from_3d(o + d * k)

func _update_focus() -> void:
	var best: Node = null
	var best_label := ""
	var best_d := INF
	if not frozen:
		for n in get_tree().get_nodes_in_group("interactable"):
			if not (n is Node3D) or not n.has_method("label_for") or not n.is_inside_tree():
				continue
			var d: float
			if n.has_method("ground_distance"):
				d = n.ground_distance(self)
			else:
				var a := GameData.from_3d(n.global_position)
				var b := html_pos()
				d = Vector2(a.x - b.x, a.y - b.y).length()
			var reach = n.get("reach")
			if reach == null:
				reach = 40.0
			if d > float(reach):
				continue
			# things in front of him win over things beside or behind him (the vending machine stands just in
			# front of the Bricks cabinet: facing the cabinet picks the cabinet)
			var to := GameData.from_3d(n.global_position)
			var me := html_pos()
			var dir := Vector2(to.x - me.x, to.y - me.y)
			var looks := Vector2(cos(look_ang), sin(look_ang)) if is_first_person() else facing
			# (only for things a step or more away: right under him, which way he faces doesn't matter)
			if dir.length() > 10.0 and looks.length() > 0.001:
				d -= 20.0 * dir.normalized().dot(looks.normalized())
			if d >= best_d:
				continue
			var l = n.label_for(self)
			if l is String and l != "":
				best = n
				best_label = l
				best_d = d
	focus = best
	focus_label = best_label

func _update_sprite() -> void:
	if sprite == null:
		return
	sprite.char_id = char_id
	sprite.facing = facing
	sprite.moving = moving
	sprite.odo = odo
	if roll > 0.0:
		sprite.action = "roll"
		sprite.roll_t = clampf(1.0 - roll / maxf(0.05, _t("rollTime")), 0.0, 0.9999)
	else:
		sprite.action = ""
		sprite.roll_t = 0.0
	# his contact shadow on what he's over: the mat when he's on the trampoline (drawJared draws it there)
	var floor_z := 0.0
	if on_tramp:
		var tr = GameData.data.get("TRAMP", {})
		floor_z = float(tr.get("mat", 32.0)) if tr is Dictionary else 32.0
	# (his height as drawn this frame: physics interpolation moves him between steps)
	var vz := visual_pos().z if is_inside_tree() else dz
	sprite.air = maxf(0.0, vz - floor_z)
	sprite.visible = not is_first_person()
	var cam := get_viewport().get_camera_3d()
	if sprite.visible:
		sprite.update_view(cam)

static func _t(key: String) -> float:
	if _has_t(key):
		return CharFrames.t(key)
	return float(_FALLBACK.get(key, CharFrames.t(key)))

static func _has_t(key: String) -> bool:
	var gd = Engine.get_main_loop().root.get_node_or_null("GameData") if Engine.get_main_loop() is SceneTree else null
	return gd != null and gd.data.has("T") and gd.data["T"].has(key)

## The HTML game's own numbers, if game_data.json ever lacks one.
const _FALLBACK := {
	"maxSpeed": 260.0, "accel": 2200.0, "friction": 1900.0, "radius": 14.0,
	"rollSpeed": 620.0, "rollTime": 0.42, "rollCooldown": 0.55,
}
