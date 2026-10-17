class_name LobbyPool
extends LobbyThing
## The pool, the dive tower with its ladder and springboard, diving, swimming and the rubber ducks, in both views.
## Follows the HTML game's stepDive / towerGeo / splash / inWater (Smashed.html L5637-L5771, spec: specs/pool.md);
## the water, rings, splashes, ducks and drips are in pool_fx.gd (LobbyPoolFx). Owned by the Lobby life session.
##
## Getting on: stand at the foot of the ladder (|x - ladderX| < 14, towerY < y < towerY + 30) and push up (W, the
## stick, the touch stick: my < -0.5 and not too sideways), like the HTML game, or press E ("CLIMB") for pad and
## touch. In first person you must face the ladder (read_steer turns the keys by where you look).
## The dive (p.dive): CLIMB (up and down the ladder), BOARD (left and right along the board, the roll button or
## walking off the tip dives; E dives too, and throws Gothica when you carry her), FALL (tumbling, no steering),
## SWIM (8-way, push into an edge to haul out; E climbs out at an edge). You cannot walk into the pool: it is a
## solid (Solid_pool); while you climb, fall or swim you pass through it and the tower's (Solid_tower).
## He is held (LobbyLife.hold) the whole time and this moves him.
##
## Heights. The HTML game's top-down view is flat (a height is that many pixels up the screen); the 3D top-down
## camera looks 65 degrees down, so a height shows as only cos(65) = 0.42 of that. While you are up the tower or
## in the air this draws him vis_k() (= 1 / cos(pitch)) times as high in the top-down view, so he stands on the
## tower's picture where the HTML game puts him; in first person it is his true height. Player.dz carries that
## height (the camera follows it); hz in the state is the true HTML height.
##
## API for the others (keep it): splash(x, y, big), in_water(x, y), water_rect(), pool_rect(), tower_geo(),
## shove_ducks(x, y, power), on_tower(p), diving(p), swimming(p), ripple(...), ellipse(...), vis_k(p),
## waterline(sprite, on, wob) (static: sink a CharSprite to its shoulders in the water).
## Input actions added: none (move_*, roll and interact are the game's own).

enum Dive { NONE, CLIMB, BOARD, FALL, SWIM }

## The water, in arena pixels (POOL, L769).
const POOL := Rect2(624, 90, 191, 149)
const FP_CLIMB := 0.16                # SHROOM_CLIMB: first person climbs this fast (of climbSpeed)
const FP_BOARD := 0.085               # SHROOM_BOARD_PACE
const SWIM_EYE := 18.0                # SHROOM_SWIM_EYE: how high the eyes are over the floor while swimming
const U := 0.025

var fx: LobbyPoolFx
var _s: Dictionary = {}               # player -> state
var _shake: float = 0.0
var _tip: Label
var _info_t: float = 0.0
var _ov: Node3D                       # the first-person ladder and board
var _ov_on: bool = false
var _flash: ColorRect
var _tower_vis: bool = true
var _exc: Dictionary = {}
## For screenshots: don't advance the dive (the test scene sets a state up and looks at it).
var test_hold: bool = false

signal dived(player: Node)
signal splashed(x: float, y: float, big: bool)

# ------------------------------------------------------------------ setup

func _ready() -> void:
	reach = 60.0
	fx = LobbyPoolFx.new()
	fx.name = "Fx"
	fx.pool = self
	add_child(fx)
	if ll and ll.ui:
		_tip = Label.new()
		_tip.add_theme_font_size_override("font_size", 16)
		_tip.add_theme_color_override("font_color", Color("#8fd3ff"))
		_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_tip.add_theme_constant_override("outline_size", 5)
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip.visible = false
		ll.ui.root.add_child(_tip)
		_flash = ColorRect.new()
		_flash.color = Color(1, 1, 1, 0)
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ll.ui.fx_root.add_child(_flash)

# ------------------------------------------------------------------ the numbers

## towerGeo(): everything in arena pixels.
func tower_geo() -> Dictionary:
	var k := LobbyLife.T("towerScale", 1.25)
	var tx := LobbyLife.T("towerX", 604.0)
	var ty := LobbyLife.T("towerY", 190.0)
	var r := LobbyLife.T("radius", 14.0)
	var climb_y := ty - 2.0
	var feet := climb_y + r * 0.9
	return {"ladderX": tx - 1.5 * k, "climbY": climb_y, "baseY": ty + r * 0.7 + 1.0,
		"deckH": feet - (ty - 66.0 * k), "boardH": feet - (ty - 72.0 * k),
		"boardX0": tx + 15.0 * k, "tipX": tx + 63.0 * k}

## inWater(x, y): did a fall land in the water (POOL, 6 in from its edge)?
static func in_water(x: float, y: float) -> bool:
	return x > POOL.position.x + 6.0 and x < POOL.end.x - 6.0 and y > POOL.position.y + 6.0 and y < POOL.end.y - 6.0

## The rectangle inWater tests (630..809 x 96..233).
static func water_rect() -> Rect2:
	return Rect2(POOL.position.x + 6.0, POOL.position.y + 6.0, POOL.size.x - 12.0, POOL.size.y - 12.0)

## POOL itself.
static func pool_rect() -> Rect2:
	return POOL

## The swimmer's clamp (x 638..801, y 100..231).
static func swim_rect() -> Rect2:
	return Rect2(POOL.position.x + 14.0, POOL.position.y + 10.0, POOL.size.x - 28.0, POOL.size.y - 18.0)

## How much higher a height is drawn from above (see the class note). 1 in first person.
func vis_k(p: Node = null) -> float:
	var pl = p if p else (ll.player if ll else null)
	if pl == null or ll == null or ll.rig == null or (pl.has_method("is_first_person") and pl.is_first_person()):
		return 1.0
	return 1.0 / maxf(0.2, cos(deg_to_rad(float(ll.rig.pitch_deg))))

# ------------------------------------------------------------------ the API

## splash(w, x, y) (big: FX.DIVE, a person landing) or fx(FX.SPLASH) (small: a potato): white water, rings, a
## shake and the word SPLASH! and the sound when big. Ducks nearby are shoved.
func splash(x: float, y: float, big: bool = true) -> void:
	var k := vis_k()
	if big:
		fx.burst(x, y, 16, Color.WHITE, 260.0, LobbyPoolFx.WATER_Z + 1.0)
		fx.shove_ducks(x, y, 1.6)
		fx.foam(x, y, 1.0)
		_shake = maxf(_shake, 8.0)
		if ll and ll.ui:
			ll.ui.float_text(x, y, 50.0 * k, "SPLASH!", Color("#8fd3ff"), 0.9, 16)
		if ll and ll.sfx:
			ll.sfx.noise(0.55, 0.45, 0.25)
			ll.sfx.tone(170.0, 0.2, "sine", 0.2, 60.0)
	else:
		fx.burst(x, y, 10, Color("#e6f7ff"), 200.0, LobbyPoolFx.WATER_Z + 1.0)
		fx.shove_ducks(x, y, 0.6)
		fx.foam(x, y, 0.45)
	splashed.emit(x, y, big)

## duckSplash: nudge the ducks near (x, y).
func shove_ducks(x: float, y: float, power: float = 1.0) -> void:
	fx.shove_ducks(x, y, power)

## A ring on the water.
func ripple(x: float, y: float, life: float = 1.3, grow: float = 70.0, w: float = 2.5, delay: float = 0.0) -> void:
	fx.ripple(x, y, life, grow, w, delay)

## An ellipse drawn on the water this frame (a swimmer's rings).
func ellipse(key: String, x: float, y: float, rx: float, ry: float, col: Color, lw: float, a: float) -> void:
	fx.ellipse(key, x, y, rx, ry, col, lw, a)

## p.dive for him: 0 none, 1 CLIMB, 2 BOARD, 3 FALL, 4 SWIM.
func dive_of(p: Node) -> int:
	return int(_s[p].dive) if _s.has(p) else 0

## Up the ladder or on the board.
func on_tower(p: Node) -> bool:
	var d := dive_of(p)
	return d == Dive.CLIMB or d == Dive.BOARD

## In any of the dive states (what turns the gym, the wardrobe, picking Gothica up... off).
func diving(p: Node) -> bool:
	return dive_of(p) != 0

func swimming(p: Node) -> bool:
	return dive_of(p) == Dive.SWIM

## His true height in HTML units (0 off the tower).
func height_of(p: Node) -> float:
	return float(_s[p].hz) if _s.has(p) else 0.0

## Cut a CharSprite off at the waterline and sink it to its shoulders (drawJared's swim), or put it back.
## wob is the bobbing, -1..1. Also used by Gothica when she is in the pool.
static func waterline(sp: CharSprite, on: bool, wob: float = 0.0) -> void:
	if sp == null:
		return
	var m = sp.get("_mat")
	if not (m is ShaderMaterial):
		return
	if not on:
		if (m as ShaderMaterial).shader == _clip_shader():
			(m as ShaderMaterial).shader = CharSprite._shader(sp.shaded)
			sp.set("_path", "")
			(m as ShaderMaterial).set_shader_parameter("sink", 0.0)
			sp.show_shadow = true
		return
	if (m as ShaderMaterial).shader != _clip_shader():
		(m as ShaderMaterial).shader = _clip_shader()
		sp.set("_path", "")                       # so it gives the new shader its picture again
	var key: String = sp.current_key if sp.current_key != "" else "front_a"
	var h := CharFrames.draw_height(sp.char_id, key)
	var foot := CharFrames.foot_frac(sp.char_id, key)
	var sink := 0.48 * h + wob * 1.5
	(m as ShaderMaterial).set_shader_parameter("cut", foot - sink / maxf(h, 1.0))
	(m as ShaderMaterial).set_shader_parameter("sink", sink * U)
	sp.show_shadow = false

static var _clip: Shader
static func _clip_shader() -> Shader:
	if _clip == null:
		_clip = Shader.new()
		_clip.code = CharSprite._SHADER_CODE.replace("%RENDER%", "cull_disabled, depth_draw_opaque, unshaded") \
			.replace("%LIT%", "") \
			.replace("uniform vec4 modulate = vec4(1.0);", "uniform vec4 modulate = vec4(1.0);\nuniform float cut = 2.0;\nuniform float sink = 0.0;") \
			.replace("up * VERTEX.y * sy;", "up * (VERTEX.y * sy - sink);") \
			.replace("if (c.a < 0.5) discard;", "if (c.a < 0.5 || UV.y > cut) discard;")
	return _clip

# ------------------------------------------------------------------ E and the Interactable contract

func _at_ladder(p: Node) -> bool:
	var g := tower_geo()
	var o := ppos(p)
	return absf(o.x - float(g.ladderX)) < 14.0 and o.y > LobbyLife.T("towerY", 190.0) and o.y < LobbyLife.T("towerY", 190.0) + 30.0

## He is "near" the pool's E where the ladder starts.
func ground_distance(player: Node3D) -> float:
	var g := tower_geo()
	return ppos(player).distance_to(Vector2(float(g.ladderX), LobbyLife.T("towerY", 190.0) + 15.0))

func label_for(p: Node) -> String:
	if p == null or _s.has(p) or not can_start(p) or not _at_ladder(p):
		return ""
	return "CLIMB"

func act(p: Node) -> void:
	if p is Player and label_for(p) != "":
		start_climb(p)

func busy_label(p: Player) -> String:
	if not _s.has(p):
		return ""
	var s: Dictionary = _s[p]
	match int(s.dive):
		Dive.BOARD:
			return "THROW!" if _carrying(p) else "DIVE"
		Dive.SWIM:
			return "CLIMB OUT" if _near_edge(s) else ""
	return ""

func busy_act(p: Player) -> void:
	if not _s.has(p):
		return
	var s: Dictionary = _s[p]
	match int(s.dive):
		Dive.BOARD:
			if _carrying(p):
				var gl = _goth()
				if gl:
					gl.throw_from_board(p)
			else:
				s.roll_req = true
		Dive.SWIM:
			if _near_edge(s):
				_haul_out(p, s, _edge_dir(s))

func busy_input(p: Player, event: InputEvent) -> bool:
	if _s.has(p) and event.is_action_pressed("roll") and not event.is_echo():
		_s[p].roll_req = true
	return false

func hides_sprite(_p: Player) -> bool:
	return false

func busy_end(p: Player) -> void:
	_cleanup(p)

func _carrying(p: Node) -> bool:
	return p != null and bool(p.get_meta("carrying_goth", false))

func _goth() -> Node:
	return ll.things.get("goth_life") if ll else null

# ------------------------------------------------------------------ starting, ending

## Up on the ladder (the HTML game: dive = CLIMB, dz 0, snapped to the ladder).
func start_climb(p: Player) -> void:
	var g := tower_geo()
	if _s.has(p):
		return
	var s := {"dive": Dive.CLIMB, "hz": 0.0, "vz": 0.0, "dvt": 0.0, "x": float(g.ladderX), "y": float(g.climbY), "vx": 0.0, "vy": 0.0,
		"odo": 0.0, "fx": 0.0, "fy": -1.0, "moving": false, "roll_req": false, "entered": false, "t": 0.0, "scale": 1.0}
	_s[p] = s
	ll.hold(p, self)
	_exceptions(p, true)
	p.facing = Vector2(0, -1)
	p.steer = Vector2.ZERO
	_apply(p, s)

func _cleanup(p: Player) -> void:
	if not _s.has(p):
		return
	_s.erase(p)
	_exceptions(p, false)
	if is_instance_valid(p) and p.sprite:
		waterline(p.sprite, false)
		p.sprite.scale = Vector3.ONE
		var pose := ll.pose_of(p)
		if pose:
			pose.scale = Vector3.ONE
		p.sprite.action = ""
		p.sprite.air = 0.0
	if is_instance_valid(p):
		p.dz = 0.0
		p.global_position.y = 0.0

## He's out of the dive (any way): put him back to normal.
func _finish(p: Player, x: float, y: float, face: Vector2) -> void:
	_cleanup(p)
	p.global_position = GameData.world_to_3d(x, y, 0.0)
	p.dz = 0.0
	p.facing = face
	p.vel = Vector2.ZERO
	ll.release(p)

func _exceptions(p: Node, on: bool) -> void:
	if not (p is PhysicsBody3D) or ll == null or ll.world == null:
		return
	var sol = ll.world.get("solids")
	if not (sol is Dictionary):
		return
	for n in ["pool", "tower"]:
		var b = sol.get(n)
		if b is PhysicsBody3D:
			if on and not _exc.has(p):
				(p as PhysicsBody3D).add_collision_exception_with(b)
			elif not on:
				(p as PhysicsBody3D).remove_collision_exception_with(b)
	if on:
		_exc[p] = true
	else:
		_exc.erase(p)

# ------------------------------------------------------------------ input

## The steering and the roll button as the dive reads them: [mx, my] up is negative my, and roll.
func _inp(p: Player, s: Dictionary) -> Vector3:
	var d := int(s.dive)
	var fp := p.is_first_person()
	var roll: bool = Input.is_action_pressed("roll") or bool(s.roll_req)
	s.roll_req = false
	p.set("_roll_tap", false)            # so a tap now does not roll him when he's let go
	if _carrying(p):
		roll = false                      # no rolling off the board with her in his arms (stepBase 7172)
	if fp and (d == Dive.CLIMB or d == Dive.BOARD):
		# shroomInput: W up the ladder and out along the board, slowly; S back
		var up := Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
		if d == Dive.CLIMB:
			return Vector3(0.0, 1.0 if (float(s.hz) <= 0.0 and up < 0.0) else -up * FP_CLIMB, 1.0 if roll else 0.0)
		var g := tower_geo()
		var back := up < 0.0 and float(s.x) <= float(g.ladderX) + 2.0
		return Vector3(0.0 if back else up * FP_BOARD, 1.0 if back else 0.0, 1.0 if roll else 0.0)
	if fp and d == Dive.FALL:
		return Vector3.ZERO
	var v := steer(p)
	return Vector3(v.x, v.y, 1.0 if roll else 0.0)

# ------------------------------------------------------------------ the dive, each frame

func busy_step(p: Player, dt: float) -> void:
	if not _s.has(p):
		return
	var s: Dictionary = _s[p]
	if not test_hold:
		var n := maxi(1, int(ceil(dt / (1.0 / 60.0))))
		var h := dt / n
		for i in n:
			if not _s.has(p):
				return
			_step_dive(p, s, h)
	if not _s.has(p):
		return
	_apply(p, s)
	_look_lock(p, s, dt)

## stepDive(w, p, inp, dt).
func _step_dive(p: Player, s: Dictionary, dt: float) -> void:
	var g := tower_geo()
	var inp := _inp(p, s)
	var mx := inp.x
	var my := inp.y
	s.dvt += dt
	s.t += dt
	match int(s.dive):
		Dive.CLIMB:
			var climb := -my * LobbyLife.T("climbSpeed", 120.0) * dt
			s.hz = maxf(0.0, float(s.hz) + climb)
			s.odo += absf(climb)
			s.vx = 0.0
			s.vy = 0.0
			s.fx = 0.0
			s.fy = -1.0
			s.moving = climb != 0.0
			if float(s.hz) <= 0.0 and my > 0.3:
				_finish(p, float(s.x), float(g.baseY), Vector2(0, 1))        # back off the bottom rung
			elif float(s.hz) >= float(g.deckH):
				s.hz = g.deckH
				s.dive = Dive.BOARD
				s.dvt = 0.0
		Dive.BOARD:
			var dir := signf(mx) if absf(mx) > 0.05 else 0.0
			var pace := minf(1.0, absf(mx) * 2.0)
			var walk := LobbyLife.T("boardWalk", 120.0)
			s.x = clampf(float(s.x) + dir * pace * walk * dt, float(g.ladderX), float(g.tipX))
			s.odo += absf(dir) * pace * walk * dt
			s.vx = 0.0
			s.vy = 0.0
			s.moving = dir != 0.0
			if dir != 0.0:
				s.fx = dir
				s.fy = 0.0
			var along := clampf((float(s.x) - float(g.ladderX)) / maxf(1.0, float(g.boardX0) - float(g.ladderX)), 0.0, 1.0)
			s.hz = float(g.deckH) + (float(g.boardH) - float(g.deckH)) * along
			if float(s.x) <= float(g.ladderX) + 2.0 and my > 0.5 and dir == 0.0:
				s.dive = Dive.CLIMB                                         # back down
				s.fx = 0.0
				s.fy = -1.0
				return
			if float(s.dvt) > 0.15 and (inp.z > 0.5 or (float(s.x) >= float(g.tipX) and dir > 0.0)):
				_leave_board(p, s)
		Dive.FALL:
			s.vz = float(s.vz) - 1200.0 * dt
			s.hz = float(s.hz) + float(s.vz) * dt
			s.x += float(s.vx) * dt
			s.y += float(s.vy) * dt
			s.odo += 240.0 * dt
			if float(s.hz) <= 0.0:
				s.hz = 0.0
				s.vz = 0.0
				if in_water(float(s.x), float(s.y)):
					s.dive = Dive.SWIM
					s.dvt = 0.0
					s.vx = float(s.vx) * 0.2
					s.vy = 0.0
					s.entered = true
					splash(float(s.x), float(s.y), true)
					if p.is_first_person():
						_flash_white()
				else:
					fx.burst(float(s.x), float(s.y), 3, Color("#5a6274"), 120.0)
					_finish(p, float(s.x), float(s.y), Vector2(1, 0))
		Dive.SWIM:
			_step_swim(p, s, Vector2(mx, my), dt)

## The board's roll button, or walking off the tip: out to the right and down the screen a little, hopping.
func _leave_board(p: Player, s: Dictionary) -> void:
	s.dive = Dive.FALL
	s.dvt = 0.0
	s.vx = LobbyLife.T("diveFwd", 130.0)
	s.vy = 40.0
	s.vz = LobbyLife.T("diveHop", 240.0)
	s.fx = 1.0
	s.fy = 0.0
	s.moving = false
	if ll and ll.sfx:
		ll.sfx.tone(260.0, 0.14, "triangle", 0.16, 720.0)                 # boing
	if _carrying(p):
		var gl = _goth()
		if gl:
			gl.drop_off_board(p, Vector3(float(s.vx) * 1.15, float(s.vy), float(s.vz) * 1.05))
	dived.emit(p)

func _step_swim(p: Player, s: Dictionary, st: Vector2, dt: float) -> void:
	var sw := LobbyLife.T("swimSpeed", 120.0)
	var ease_ := minf(1.0, 4.0 * dt)
	s.vx += (st.x * sw - float(s.vx)) * ease_
	s.vy += (st.y * sw - float(s.vy)) * ease_
	s.x += float(s.vx) * dt
	s.y += float(s.vy) * dt
	s.odo += Vector2(s.vx, s.vy).length() * dt
	var ml := st.length()
	s.moving = ml > 0.1
	if s.moving:
		s.fx = st.x / ml
		s.fy = st.y / ml
	var b := swim_rect()
	var ox := 0
	var oy := 0
	if s.x < b.position.x:
		s.x = b.position.x
		s.vx = 0.0
		if st.x < -0.5:
			ox = -1
	if s.x > b.end.x:
		s.x = b.end.x
		s.vx = 0.0
		if st.x > 0.5:
			ox = 1
	if s.y < b.position.y:
		s.y = b.position.y
		s.vy = 0.0
		if st.y < -0.5:
			oy = -1
	if s.y > b.end.y:
		s.y = b.end.y
		s.vy = 0.0
		if st.y > 0.5:
			oy = 1
	if (ox != 0 or oy != 0) and float(s.dvt) > 0.5:
		_haul_out(p, s, Vector2i(ox, oy))

## Haul yourself out onto the tiles on the side (ox, oy) (the HTML game: a push into the edge after half a second).
func _haul_out(p: Player, s: Dictionary, o: Vector2i) -> void:
	var out := LobbyLife.T("radius", 14.0) * 0.7
	var x: float = s.x
	var y: float = s.y
	if o.x < 0:
		x = POOL.position.x + 6.0 - out
	if o.x > 0:
		x = POOL.end.x - 6.0 + out
	if o.y < 0:
		y = POOL.position.y + 6.0 - out
	if o.y > 0:
		y = POOL.end.y - 6.0 + out
	fx.burst(x, y, 3, Color("#5a6274"), 120.0)
	_finish(p, x, y, Vector2(o.x, o.y).normalized() if o != Vector2i.ZERO else Vector2(0, 1))

func _near_edge(s: Dictionary) -> bool:
	return _edge_dir(s) != Vector2i.ZERO and float(s.dvt) > 0.5

## The edge he is nearest to (within 22 of the swim box), or (0, 0).
func _edge_dir(s: Dictionary) -> Vector2i:
	var b := swim_rect()
	var best := 22.0
	var o := Vector2i.ZERO
	var cand := [[float(s.x) - b.position.x, Vector2i(-1, 0)], [b.end.x - float(s.x), Vector2i(1, 0)],
		[float(s.y) - b.position.y, Vector2i(0, -1)], [b.end.y - float(s.y), Vector2i(0, 1)]]
	for c in cand:
		if float(c[0]) < best:
			best = float(c[0])
			o = c[1]
	return o

# ------------------------------------------------------------------ putting him where the state says

func _apply(p: Player, s: Dictionary) -> void:
	var d := int(s.dive)
	var fp := p.is_first_person()
	if d == Dive.SWIM:
		s.scale = 1.0
		p.global_position = GameData.world_to_3d(float(s.x), float(s.y), LobbyPoolFx.WATER_Z)
		p.dz = (SWIM_EYE - float(LobbyLife.D("SHROOM_EYE", 62.0))) if fp else 0.0
	else:
		var lift := _lift(p, float(s.x), float(s.y), float(s.hz))
		p.global_position = GameData.world_to_3d(float(s.x), float(s.y), lift.z)
		p.dz = lift.z
		s.scale = lift.s
	p.facing = Vector2(float(s.fx), float(s.fy))
	p.moving = bool(s.moving)
	p.odo = float(s.odo)
	p.vel = Vector2.ZERO
	p.velocity = Vector3.ZERO
	var sp := p.sprite
	if sp:
		sp.facing = p.facing
		sp.moving = p.moving
		sp.odo = p.odo
		sp.action = "tumble" if d == Dive.FALL else ""
		sp.air = p.dz if d != Dive.SWIM else 0.0
		sp.scale = Vector3.ONE * float(s.scale)
		var pose := ll.pose_of(p)
		if pose:
			pose.scale = sp.scale
		var cam := get_viewport().get_camera_3d()
		if not fp:
			sp.update_view(cam)
		if d == Dive.SWIM:
			waterline(sp, true, sin(LobbyLife.now() * 1000.0 / 260.0))
		else:
			waterline(sp, false)

## Where to put him and how big to draw him so that, in the top-down view, a height of hz (HTML units, which the
## flat HTML view draws as that many pixels up the screen) shows that far above his feet on the screen, as the
## tower's picture has it. The camera sits close, so a high point is also drawn bigger: the scale takes that off.
## In first person it is just his height, drawn as it is.
func _lift(p: Player, x: float, y: float, hz: float) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if p.is_first_person() or cam == null or hz <= 0.0:
		return {"z": hz, "s": 1.0}
	var g := GameData.world_to_3d(x, 0.0, y)
	var up := Vector3.UP
	var pa := cam.unproject_position(g)
	var pb := cam.unproject_position(g + cam.global_transform.basis.y * U)
	var upx := pa.distance_to(pb)
	var target := pa - Vector2(0.0, hz * upx)
	var o := cam.project_ray_origin(target)
	var d := cam.project_ray_normal(target)
	# the point on the vertical line through his feet that the ray through target passes nearest
	var w0 := g - o
	var b := up.dot(d)
	var dd := up.dot(w0)
	var e := d.dot(w0)
	var den := 1.0 - b * b
	if absf(den) < 0.0001:
		return {"z": hz * vis_k(p), "s": 1.0}
	var sc := (b * e - dd) / den
	var hi := g + up * sc
	var fwd := -cam.global_transform.basis.z
	var dg := (g - cam.global_position).dot(fwd)
	var dh := (hi - cam.global_position).dot(fwd)
	return {"z": maxf(0.0, sc / U), "s": clampf(dh / maxf(dg, 0.01), 0.3, 1.0)}

## In first person the view is held while he's on the tower (L4287): up the ladder looks at it, on the board out
## over the pool; it eases there.
func _look_lock(p: Player, s: Dictionary, dt: float) -> void:
	if not p.is_first_person():
		return
	var d := int(s.dive)
	var want := NAN
	if d == Dive.CLIMB:
		want = -PI / 2.0
	elif d == Dive.BOARD or d == Dive.FALL:
		want = 0.0
	if is_nan(want):
		return
	p.look_ang = lerp_angle(p.look_ang, want, minf(1.0, 6.0 * dt))

func _flash_white() -> void:
	if _flash == null:
		return
	_flash.color = Color(1, 1, 1, 0.75)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.7)

# ------------------------------------------------------------------ every frame (the rest)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	if ll == null or ll.player == null:
		return
	var p := ll.player
	# climbing on: push up at the foot of the ladder
	if not _s.has(p) and ll.can_start(p) and _at_ladder(p) and p.roll <= 0.0 and p.controls_enabled:
		var v := steer(p)
		if v.y < -0.5 and absf(v.x) < 0.7:
			start_climb(p)
	# who is swimming now (the ducks mind them), their rings and their dripping
	var swimmers: Array = []
	var key := "p0"
	if _s.has(p):
		var s: Dictionary = _s[p]
		var sw := int(s.dive) == Dive.SWIM
		if sw:
			swimmers.append({"x": s.x, "y": s.y, "vx": s.vx, "vy": s.vy})
			var wob := sin(LobbyLife.now() * 1000.0 / 260.0)
			var rw := 34.0 * 0.42 + (3.0 if s.moving else 0.0)
			fx.ellipse("swim_a", s.x, s.y, rw + wob, 5.0, Color(225 / 255.0, 246 / 255.0, 1.0), 2.0, 0.8)
			fx.ellipse("swim_b", s.x, s.y + 1.0, rw + 6.0 - wob, 8.0, Color("#e0473f"), 2.0, 0.6)
			fx.swimmer_rings(key, s.x, s.y, Vector2(s.vx, s.vy).length(), bool(s.entered), dt)
			s.entered = false
		fx.drip_tick(key, s.x, s.y, s.fx, s.fy, sw, not sw, dt)
	else:
		var o := ppos(p)
		fx.drip_tick(key, o.x, o.y, p.facing.x, p.facing.y, false, false, dt)
	var gl = _goth()
	if gl and gl.has_method("swimmer_info"):
		var gi: Dictionary = gl.swimmer_info()
		if not gi.is_empty():
			swimmers.append({"x": gi.x, "y": gi.y, "vx": gi.vx, "vy": gi.vy})
		if gl.has_method("drip_info"):
			var di: Dictionary = gl.drip_info()
			if not di.is_empty():
				fx.drip_tick("goth", di.x, di.y, di.fx, di.fy, bool(di.swim), bool(di.diving), dt)
	fx.swimmers = swimmers
	# the shake
	_shake = maxf(0.0, _shake - 90.0 * dt)
	var cam: Camera3D = ll.rig.camera() if ll.rig else null
	if cam:
		var a := minf(_shake, 40.0) / 2.0 * U
		cam.h_offset = randf_range(-a, a)
		cam.v_offset = randf_range(-a, a)
	_update_tower_view(p)
	_update_tips(p, dt)

# ------------------------------------------------------------------ prompts

func _update_tips(p: Player, dt: float) -> void:
	var text := ""
	var d := dive_of(p)
	var fp := p.is_first_person()
	if d == Dive.BOARD:
		text = (_act_key() + ": throw her in!") if _carrying(p) else "walk off or roll to dive!"
	elif d == 0 and not _s.has(p) and ll.can_start(p) and _at_ladder(p):
		text = "↑ climb"
	if _tip:
		_tip.visible = false
		if text != "" and not fp and not ll.ui.menu_open():
			var cam := get_viewport().get_camera_3d()
			if cam:
				# 85 units over his feet on the screen, like the HTML game's tip (a flat view: a unit is a pixel)
				var feet := p.global_position
				if d == 0 or d == Dive.SWIM:
					feet.y = 0.0
				var at := cam.unproject_position(feet)
				var upu: float = get_viewport().get_visible_rect().size.y / (float(LobbyLife.D("ARENA", {"h": 520.0}).h) / ll.rig.zoom_wanted())
				var hs := float(_s[p].scale) if _s.has(p) else 1.0
				if not cam.is_position_behind(feet):
					_tip.text = text
					_tip.visible = true
					_tip.size = _tip.get_minimum_size()
					_tip.position = at - Vector2(_tip.size.x / 2.0, _tip.size.y + 85.0 * upu * hs)
	# first person: the HTML game's tips across the screen
	_info_t -= dt
	if fp and _info_t <= 0.0 and ll.ui:
		var tip := ""
		if d == Dive.CLIMB:
			tip = "W: up   S: down"
		elif d == Dive.BOARD:
			tip = "walk off the end, or Shift to dive"
		elif d == 0 and not _s.has(p) and ll.can_start(p) and _at_ladder(p):
			tip = "face the ladder and hold W to climb"
		if tip != "":
			ll.ui.info(tip, 1.0)
			_info_t = 0.8

func _act_key() -> String:
	var h = ll.hud
	if h and h.get("pad_last"):
		return "A"
	return "E"

# ------------------------------------------------------------------ the first-person ladder and board

## While he is on the tower in first person the tower's flat picture is hidden and a ladder and a board are
## built in 3D in front of him (the HTML game draws the same as an overlay, L4675-L4754).
func _update_tower_view(p: Player) -> void:
	var want := _s.has(p) and p.is_first_person() and int(_s[p].dive) in [Dive.CLIMB, Dive.BOARD, Dive.FALL]
	if want != _ov_on:
		_ov_on = want
		if want and _ov == null:
			_build_overlay()
		if _ov:
			_ov.visible = want
		var pr = ll.world.get("props") if ll.world else null
		if pr is Dictionary and pr.get("tower") is Node3D:
			(pr.tower as Node3D).visible = not want

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size * U
	m.mesh = b
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = col
	m.material_override = mt
	m.position = pos * U
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

func _build_overlay() -> void:
	_ov = Node3D.new()
	_ov.name = "TowerView"
	add_child(_ov)
	var g := tower_geo()
	var lx: float = g.ladderX
	var top: float = float(g.deckH) + 22.0
	var gy: float = float(g.climbY) - 15.0        # the ladder stands a little in front of his face
	# the ladder: two rails and a rung every 14 units
	for sx in [-8.0, 8.0]:
		_box(_ov, Vector3(lx + sx, top / 2.0, gy), Vector3(2.4, top, 2.4), Color("#7b8794"))
	var z := 8.0
	while z < top:
		_box(_ov, Vector3(lx, z, gy), Vector3(17.0, 1.8, 2.0), Color("#c9d2da"))
		z += 14.0
	# the deck and board: planks along it, the board's rise from the deck to the springboard
	var x0 := float(g.ladderX) - 10.0
	var x1 := float(g.tipX) + 8.0
	var x := x0
	var i := 0
	while x < x1:
		var xm := x + 6.0
		var along := clampf((xm - float(g.ladderX)) / maxf(1.0, float(g.boardX0) - float(g.ladderX)), 0.0, 1.0)
		var hz := float(g.deckH) + (float(g.boardH) - float(g.deckH)) * along
		_box(_ov, Vector3(xm, hz - 2.0, float(g.climbY)), Vector3(11.4, 3.0, 26.0), Color("#4f8fd6") if i % 2 == 0 else Color("#3f78bd"))
		x += 12.0
		i += 1
	for sy in [-13.0, 13.0]:
		_box(_ov, Vector3((lx + float(g.boardX0)) / 2.0, float(g.deckH) + 8.0, float(g.climbY) + sy), Vector3(float(g.boardX0) - lx + 20.0, 2.0, 1.6), Color("#dfe6ee"))
	_ov.visible = false

# ------------------------------------------------------------------ screenshots

## Scenes for the browser screenshots (?lobby=pool[,tower|climb|board|dive|swim|splash][,fp]).
func test_scene(tl: Node, parts: PackedStringArray) -> void:
	var g := tower_geo()
	var p := ll.player
	tl.go(float(g.ladderX), 214.0, Vector2(0, -1))
	tl.later(3.0, func(): if _s.has(p): print("POOLDBG lift ", _lift(p, _s[p].x, _s[p].y, _s[p].hz), " pos ", p.global_position, " scale ", p.sprite.scale, " cam ", get_viewport().get_camera_3d().global_position))
	tl.later(3.0, func(): if false: print("POOLDBG tip ", _tip.visible, " ", _tip.text, " ", _tip.position, " ", _tip.size, " lbl=", ll.player.focus_label, " feet=", get_viewport().get_camera_3d().unproject_position(ll.player.global_position), " k=", vis_k(), " gp=", ll.player.global_position, " vp=", get_viewport().get_visible_rect().size))
	if parts.has("splash"):
		tl.go(690.0, 235.0, Vector2(0, -1))
		tl.later(1.0, func(): splash(730.0, 160.0, true))
		tl.later(3.0, func(): splash(700.0, 190.0, false))
		return
	if parts.has("climb"):
		tl.later(0.3, func():
			start_climb(p)
			_s[p].hz = 50.0
			test_hold = true)
	elif parts.has("board"):
		tl.later(0.3, func():
			start_climb(p)
			var s: Dictionary = _s[p]
			s.dive = Dive.BOARD
			s.hz = g.boardH
			s.x = 660.0
			s.fx = 1.0
			s.fy = 0.0
			test_hold = true)
	elif parts.has("dive"):
		tl.later(0.3, func():
			start_climb(p)
			var s: Dictionary = _s[p]
			s.dive = Dive.FALL
			s.hz = 60.0
			s.vz = 80.0
			s.x = 730.0
			s.y = 205.0
			s.odo = 40.0
			test_hold = true)
	elif parts.has("swim"):
		tl.later(0.3, func():
			start_climb(p)
			var s: Dictionary = _s[p]
			s.dive = Dive.SWIM
			s.hz = 0.0
			s.x = 735.0
			s.y = 175.0
			s.dvt = 0.0
			s.entered = true
			s.fx = 0.0
			s.fy = 1.0
			splash(735.0, 175.0, true))
