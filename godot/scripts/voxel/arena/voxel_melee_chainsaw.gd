class_name VoxelMeleeChainsaw
extends VoxelMelee
## The chainsaw (the owner, 20 Oct: five melee weapons, each doing something different). It doesn't swing, it grinds.
## Hold left and the bar goes out in front of you and saws whatever it touches: about ten times a second a thin kerf
## along the bar (VoxelBody.carve: a short capsule from just in front of you to past arm's length, a little below the
## eye line) is ground out of every body it's in, so sweeping the mouse while you hold drags the cut through them and
## saws off an arm, a leg, the head or the top half (carve takes off whatever the kerf leaves hanging). In flesh the bar
## drags: from one bite to the next it can only move so far (the view shows it lagging behind the mouse), so each kerf
## overlaps the last and the cut stays unbroken. Held still it chews the kerf wider. Through the middle of the neck the
## head comes off (a thin plane cut at its base: a kerf alone can't sever it there). Chips and blood spray up off the
## chain, the screen shakes, and whoever is being sawn is held there, twitching. Right click lunges (every 1.5 s):
## you're thrown forward with the saw out front, grinding all the way; it bites into the first one it reaches, drags you
## on up to them, then rips up out of them (one thick plane cut from where it went in up through the head) and shoves
## them off. Out, it idles (a little shake, the chain still); cutting, it revs (the chain runs, more shake) and the bar
## gets bloodier. Top-down it's in Jared's right hand and grinds level at chest height toward the mouse. A bite into a
## body is a carve with a flood fill of the part (a few ms for the chest), so bites are spaced to keep the grinding to
## about a tenth of the time, and one body is ground a frame. The core (does the bar touch a body, what one bite grinds
## out, how far the bar may move between bites, the neck, the rip) is static so the logic test can run it. Owned by
## the voxel session.

const NEAR := 0.45              # metres in front of the eye the kerf starts
const FAR := 1.6                # ... and ends (enemies stop about 1.2 m off; this reaches through them)
const DROP := 0.07              # metres below the eye line the bar runs
const KERF_R := 0.04            # the kerf's radius, metres
const JUDDER := 0.005           # metres the bar jumps about each bite (a ragged kerf)
const CHEW := 0.012             # held still: metres the kerf chews wider each other bite,
const CHEW_MAX := 0.06          # ... up to this each side
const HP_PER_CUBE := 0.12       # health each body cube ground out costs
const TICK := 0.08              # seconds between bites at most (12.5 a second) ...
const BUDGET := 0.1             # ... and fewer if they cost more than this share of the time
const LUNGE_TICK := 0.045       # in a lunge (it's short)
const LUNGE_BUDGET := 0.3
const MAX_BODIES := 3           # bodies one bite grinds at most (one a frame)
const BITE_ANG := 0.045         # radians the bar may move between bites in flesh (the kerfs overlap out to FAR)
const MAX_LAG := 0.6            # radians it lags the mouse at most (beyond that it tears loose)
const NECK_D := 0.05            # the kerf this near the neck joint is through the middle of the neck: the head comes off
const LUNGE_V := 9.0            # m/s the lunge throws you
const LUNGE_BITE_V := 3.0       # ... once the saw is in someone (it drags you on into them)
const LUNGE_STOP := 0.85        # metres (level) from someone standing that the lunge stops (the saw buried)
const WIND_T := 0.07            # the lunge, seconds: cocked back,
const LUNGE_T := 0.28           # thrown forward grinding,
const RIP_T := 0.16             # ripping up out of them,
const BACK_T := 0.32            # back to rest
const RIP := 0.75               # radians the bar rips up at least (one plane cut through whoever it's in) ...
const RIP_TOP := 0.35           # ... and to this far above level at least (up through the head)
const COOLDOWN := 1.5           # seconds between lunges
const OUT_T := 0.1              # seconds the bar takes to go out when you hold left
const IN_T := 0.22              # ... and to come back when you let go
const CHAIN_V := 1.1            # m/s the teeth run on screen (slow enough not to strobe)
const PITCH := 0.05             # metres between the chain's teeth
const BAR_Z0 := 0.3             # the guide bar, weapon space: from z (metres from the grip) ...
const BAR_Z1 := 0.9             # ... to z
const BAR_Y := -0.015
const BAR_X := -0.02            # a little to the right of the engine's middle, as on a real one
# poses in camera space (x right, y up, -z forward): where the grip is and a point the bar aims at
const REST_GRIP := Vector3(0.32, -0.38, -0.36)  # the engine and front handle in view right of the weapon bar
const REST_AT := Vector3(0.1, -0.42, -1.4)
const CUT_GRIP := Vector3(0.26, -0.42, -0.42)
const WIND_GRIP := Vector3(0.31, -0.37, -0.2)
const WIND_AT := Vector3(0.14, 0.0, -1.2)
const LUNGE_GRIP := Vector3(0.24, -0.42, -0.52)
const RIP_GRIP := Vector3(0.2, -0.3, -0.5)
const ROLL := 0.28              # radians the saw's turned over to the right about the bar (its side toward you)

const ORANGE := Color(1.0, 0.43, 0.04)
const BAR_COL := Color(0.7, 0.72, 0.76)
const BAR_HAND_COL := Color(0.86, 0.88, 0.92)
const TOOTH_COL := Color(0.13, 0.13, 0.15)
const BLOOD := Color(0.42, 0.03, 0.04)

var _saw: Node3D                # first person: the saw (the grip at its origin, the bar along +z), posed under view
var _teeth: Array = []          # [MeshInstance3D, index, top edge?] the view model's chain teeth (run along the bar)
var _hand: Node3D               # top-down: the saw in Jared's hands (the arena frees it on a switch)
var _hand_teeth: Array = []
var _m_bar: StandardMaterial3D
var _m_bar_hand: StandardMaterial3D
var _m_teeth: StandardMaterial3D
var _cutting := false           # left held
var _cut_k := 0.0               # 0 at rest .. 1 out in front cutting
var _rev := 0.0                 # 0 idling .. 1 flat out
var _bite_k := 0.0              # 1 just after a bite that cut, fading
var _in_t := 0.0                # seconds the bar still counts as in flesh (it drags)
var _kickback := 0.0            # the saw bucking back in the hands on a bite
var _chain := 0.0               # how far the chain has run, metres
var _chain_shown := -1.0        # ... as the teeth show it
var _gore_shown := -1.0
var _tick := 0.0                # seconds to the next bite
var _dir := Vector3.FORWARD     # the bar's direction (world); lags look() in flesh
var _bite_dir := Vector3.FORWARD  # ... at the last bite
var _vdir := Vector3.FORWARD    # ... as the view shows it (smoothed)
var _prev_eye := Vector3.ZERO   # the eye at the last bite (a lunge grinds the ground covered since)
var _td := false                # top-down when the bar was last set where you look (V mid-move sets it again)
var _chew := 0                  # bites in a row held still
var _queue := []                # [body, a, z]: the rest of a bite's bodies, ground one a frame
var _lunge_t := -1.0            # seconds into the lunge (-1: none)
var _lunge_dir := Vector3.FORWARD
var _lunge_bit := false         # the lunge's saw is in someone
var _lunge_held := false        # stopped against someone
var _lunge_ripped := false
var _lunge_rip := false         # the rip's cut done
var _rip_ang := RIP             # how far this one rips up
var _cd := 0.0
var _gore := 0.0                # how bloody the bar is, 0..1
var _t := 0.0
var _sawn := {}                 # body -> seconds since the saw last bit it (held there twitching a moment)
var _stop_ms := 0               # the last hit-stop (real ms; a constant grind mustn't stutter the game)
var _move_t := 0.0              # seconds into this move (game time)

func _build() -> void:
	_m_bar = mat(BAR_COL, 0.5, 0.35)
	_m_bar_hand = mat(BAR_HAND_COL, 0.2, 0.45)
	_m_teeth = mat(TOOTH_COL, 0.8, 0.35)
	_saw = Node3D.new()
	view.add_child(_saw)
	_teeth = _model(_saw, false)
	_saw.transform = _aim_xf(REST_GRIP, REST_AT, ROLL)

# the saw, weapon space (the rear grip at the origin, the bar along +z, its top +y; +x is its left), metres; returns
# its chain teeth. light: brighter, the bar thicker, for top-down (seen small from up high on a dark floor).
func _model(root: Node3D, light: bool) -> Array:
	var orange := mat(ORANGE.lightened(0.15) if light else ORANGE, 0.0, 0.55)
	var black := mat(Color(0.2, 0.2, 0.22) if light else Color(0.07, 0.07, 0.08), 0.0, 0.7)
	var dark := mat(Color(0.26, 0.26, 0.29), 0.3, 0.6)
	var chrome := mat(Color(0.78, 0.78, 0.8), 0.9, 0.25)
	var cover := mat(ORANGE.darkened(0.25) if light else Color(0.17, 0.17, 0.19), 0.2, 0.6)
	# the rear handle: the grip, its top and the back post
	box(root, Vector3(0.032, 0.04, 0.13), Vector3(0, 0, -0.025), black)
	box(root, Vector3(0.032, 0.028, 0.1), Vector3(0, 0.085, -0.03), black)
	box(root, Vector3(0.032, 0.11, 0.028), Vector3(0, 0.04, -0.09), black)
	box(root, Vector3(0.016, 0.022, 0.03), Vector3(0, -0.03, 0.005), orange)     # the throttle
	# the engine, its cover and the bits on it
	box(root, Vector3(0.13, 0.15, 0.24), Vector3(0, 0.03, 0.15), orange)
	box(root, Vector3(0.11, 0.035, 0.15), Vector3(0, 0.12, 0.12), cover)
	for i in 3:
		box(root, Vector3(0.09, 0.006, 0.008), Vector3(0, 0.14, 0.08 + 0.035 * i), black)  # the cooling fins
	box(root, Vector3(0.03, 0.014, 0.03), Vector3(-0.042, 0.112, 0.235), black)      # the fuel cap
	box(root, Vector3(0.02, 0.022, 0.055), Vector3(0.074, 0.08, 0.09), black)        # the pull cord's handle
	box(root, Vector3(0.022, 0.05, 0.075), Vector3(0.076, -0.005, 0.21), chrome)     # the muffler
	box(root, Vector3(0.016, 0.105, 0.13), Vector3(-0.073, 0.0, 0.235), dark)        # the clutch cover
	# the wrap-round front handle and the chain brake in front of it
	box(root, Vector3(0.17, 0.024, 0.03), Vector3(0, 0.19, 0.215), black)
	box(root, Vector3(0.024, 0.13, 0.024), Vector3(0.085, 0.125, 0.215), black)
	box(root, Vector3(0.024, 0.13, 0.024), Vector3(-0.085, 0.125, 0.215), black)
	box(root, Vector3(0.12, 0.065, 0.01), Vector3(0, 0.165, 0.275), black)
	# the guide bar: a groove down it, a nose, the chain along both edges
	var zl := BAR_Z1 - BAR_Z0
	var zm := (BAR_Z0 + BAR_Z1) * 0.5
	var bt := 0.045 if light else 0.018
	var ct := 0.014 if light else 0.022       # the chain (top-down: narrower than the bar, so the bar shows from above)
	var bar_m := _m_bar_hand if light else _m_bar
	box(root, Vector3(bt, 0.075, zl), Vector3(BAR_X, BAR_Y, zm), bar_m)
	box(root, Vector3(bt + 0.0006, 0.01, zl * 0.8), Vector3(BAR_X, BAR_Y, zm + 0.02), dark)
	box(root, Vector3(bt, 0.05, 0.03), Vector3(BAR_X, BAR_Y, BAR_Z1 + 0.015), bar_m)
	box(root, Vector3(ct, 0.007, zl), Vector3(BAR_X, BAR_Y + 0.041, zm), _m_teeth)
	box(root, Vector3(ct, 0.007, zl), Vector3(BAR_X, BAR_Y - 0.041, zm), _m_teeth)
	box(root, Vector3(ct, 0.06, 0.012), Vector3(BAR_X, BAR_Y, BAR_Z1 + 0.034), _m_teeth)
	var out := []
	var n := roundi(zl / PITCH)
	for top in [true, false]:
		for i in n:
			var tooth := box(root, Vector3(ct + 0.004, 0.017, 0.022), Vector3.ZERO, _m_teeth)
			out.append([tooth, i, top])
	_place_teeth(out, 0.0)
	return out

# the teeth round the chain, run on by chain metres: along the top toward the nose, back along the bottom
static func _place_teeth(teeth: Array, chain: float) -> void:
	var n := maxi(1, teeth.size() / 2)
	var loop := float(n) * PITCH
	for tt in teeth:
		var mi: MeshInstance3D = tt[0]
		if not is_instance_valid(mi):
			continue
		var i: int = tt[1]
		var top: bool = tt[2]
		var s := fposmod(float(i) * PITCH + (chain if top else -chain), loop)
		var side := 0.004 if (i % 2) == 0 else -0.004       # the cutters lean left, right, left ...
		mi.position = Vector3(BAR_X + side, BAR_Y + (0.046 if top else -0.046), BAR_Z0 + 0.01 + s)

# a pose: the grip at grip, the bar aimed at at (both camera space), turned roll radians about the bar
static func _aim_xf(grip: Vector3, at: Vector3, roll: float = 0.0) -> Transform3D:
	var z := (at - grip).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var bs := Basis(x, z.cross(x), z)
	if roll != 0.0:
		bs = Basis(z, roll) * bs
	return Transform3D(bs, grip)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	_hand = Node3D.new()            # shaken (the arena sets root's own transform)
	root.add_child(_hand)
	var inner := Node3D.new()
	inner.position = Vector3(0, 0, -0.06)
	_hand.add_child(inner)
	_hand_teeth = _model(inner, true)
	return root

func hand_pose() -> String:
	return "shotgun"                # at the hip, both hands on it

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.3, col.g * 0.3, col.b * 0.32, col.a)
	var org := Color(ORANGE.r, ORANGE.g, ORANGE.b, col.a)
	var rects := [[Rect2(0.2, 2.2, 1.4, 0.8), dim], [Rect2(0.2, 1.4, 0.4, 1.6), dim], [Rect2(1.4, 1.3, 2.7, 2.3), org],
		[Rect2(2.2, 0.5, 1.7, 0.45), dim], [Rect2(3.55, 0.5, 0.35, 1.0), dim], [Rect2(4.1, 2.0, 5.3, 1.0), col],
		[Rect2(9.4, 2.15, 0.35, 0.7), col]]
	for i in 7:
		rects.append([Rect2(4.3 + i * 0.75, 1.72, 0.38, 0.28), dim])
		rects.append([Rect2(4.6 + i * 0.75, 3.0, 0.38, 0.28), dim])
	for b in rects:
		var rr: Rect2 = b[0]
		ci.draw_rect(Rect2(r.position + rr.position * u, rr.size * u), b[1])

# ---------------------------------------------------------------- the buttons

func busy() -> bool:
	return _cutting or _lunge_t >= 0.0 or _cut_k > 0.01

func cooling() -> float:
	return clampf(_cd / COOLDOWN, 0.0, 1.0)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if not _cutting:
			_cutting = true
			if _lunge_t < 0.0:
				_begin("hold")
				_tick = OUT_T * 0.6     # the first bite as the bar gets out there
	elif button == MOUSE_BUTTON_RIGHT:
		lunge()

func hold(button: int, _dt: float) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_cutting = true

func release(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_cutting = false

func on_select() -> void:
	_cut_k = 0.0
	_rev = 0.0

func on_deselect() -> void:
	_cutting = false
	if _lunge_t >= 0.0 and _lunge_t < WIND_T + LUNGE_T:
		arena.dash(Vector3.ZERO, 0.0)
	_lunge_t = -1.0
	_cut_k = 0.0
	_rev = 0.0
	_bite_k = 0.0
	_in_t = 0.0
	_queue.clear()
	_sawn.clear()

## Right click: thrown forward with the saw out front, grinding all the way (cooldown COOLDOWN).
func lunge() -> void:
	if _cd > 0.0 or _lunge_t >= 0.0:
		return
	_cd = COOLDOWN
	_lunge_t = 0.0
	var f := look()
	_lunge_dir = Vector3(f.x, 0.0, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else Vector3.FORWARD
	_lunge_bit = false
	_lunge_held = false
	_lunge_ripped = false
	_lunge_rip = false
	_begin("lunge")

# a new move: the bar where you look, fresh numbers in last
func _begin(move: String) -> void:
	_aim_bar()
	_move_t = 0.0
	last = {"move": move, "bites": 0, "carves": 0, "hits": 0, "cut": 0, "parts": [], "pieces": 0, "killed": false,
		"head_off": false, "ms": 0.0, "max_ms": 0.0, "per_s": 0.0, "rip_ms": 0.0}

# the bar where you look now, no drag, no kerf back to an old eye
func _aim_bar() -> void:
	_dir = look()
	_bite_dir = _dir
	_vdir = _dir
	_prev_eye = eye()
	_chew = 0
	_td = top_down()

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	_t += dt
	_cd = maxf(0.0, _cd - dt)
	if _lunge_t >= 0.0:
		_lunge_step(dt)
	var lunging := _lunge_t >= 0.0
	var active := _cutting or lunging
	_cut_k = move_toward(_cut_k, 1.0 if _cutting and not lunging else 0.0, dt / (OUT_T if _cutting else IN_T))
	_rev = move_toward(_rev, 1.0 if active else 0.0, dt * (5.0 if active else 2.0))
	_bite_k = maxf(0.0, _bite_k - dt * 5.0)
	_in_t = maxf(0.0, _in_t - dt)
	_kickback = maxf(0.0, _kickback - dt * 9.0)
	_gore = maxf(0.0, _gore - dt * 0.015)
	_chain += dt * CHAIN_V * _rev * _rev
	_tick -= dt
	if active:
		_move_t += dt
		if top_down() != _td:
			_aim_bar()                          # V mid-move: the eye and the look jump
		var want := look()
		if not _ripping():
			if _in_t > 0.0:
				# in flesh the bar gets only so far from its last bite (and tears loose past MAX_LAG)
				_dir = turn(_bite_dir, want, BITE_ANG)
				if _dir.angle_to(want) > MAX_LAG:
					_dir = turn(want, _dir, MAX_LAG)
			else:
				_dir = want
		if top_down() and arena.avatar:
			arena.avatar.attack = 0.5           # both arms out in front
		if not top_down():
			arena._kick = maxf(float(arena._kick), randf_range(0.04, 0.16) + 0.35 * _bite_k)
	if not _queue.is_empty():
		# the rest of the last bite's bodies, one a frame
		var q: Array = _queue.pop_front()
		_carve(q[0], q[1], q[2], frame())
	elif active and _tick <= 0.0:
		if _grinding():
			_bite()
		else:
			_tick = 0.0
	_hold_sawn(dt)
	_look(dt)

# the bar's out where it cuts: held out, or the lunge thrown forward / ripping up
func _grinding() -> bool:
	if _lunge_t >= 0.0:
		return _lunge_t >= WIND_T and _lunge_t < WIND_T + LUNGE_T
	return _cutting and _cut_k > 0.5

func _ripping() -> bool:
	return _lunge_t >= WIND_T + LUNGE_T and _lunge_t < WIND_T + LUNGE_T + RIP_T

func _lunge_step(dt: float) -> void:
	var was := _lunge_t
	_lunge_t += dt
	var t0 := WIND_T
	var t1 := WIND_T + LUNGE_T
	var t2 := t1 + RIP_T
	if was < t0 and _lunge_t >= t0:
		# off: thrown forward
		arena.dash(_lunge_dir * LUNGE_V, LUNGE_T)
		arena._kick = maxf(float(arena._kick), 0.8)
		_tick = 0.0
	if _lunge_t >= t0 and _lunge_t < t1:
		# up against someone still standing in front: the saw's buried, you stop there
		if not _lunge_held:
			var pp: Vector3 = arena.player.global_position
			for b in bodies_near(pp, LUNGE_STOP, true):
				if not b.floored() and (b.global_position - pp).dot(_lunge_dir) > 0.0:
					_lunge_held = true
					arena.dash(Vector3.ZERO, t1 - _lunge_t)
					break
	if was < t1 and _lunge_t >= t1:
		_rip_ang = rip_angle(look())
	if _lunge_t >= t1 and _lunge_t < t2:
		# ripping up out of them: the bar swings up about your shoulders
		_dir = look().rotated(frame().x.normalized(), _rip_ang * _smooth((_lunge_t - t1) / RIP_T))
	if _lunge_t >= t1 + RIP_T * 0.35 and not _lunge_rip:
		_lunge_rip = true
		_rip_out()
	if _lunge_t >= t2 and not _lunge_ripped:
		_lunge_ripped = true
		# out of them: whoever it was in is shoved off
		for b in _sawn:
			if is_instance_valid(b) and b.alive:
				b.hit_react(_lunge_dir, 40, "torso")
		_sawn.clear()
	if _lunge_t >= t2 + BACK_T:
		_lunge_t = -1.0
		if _cutting:
			_begin("hold")              # left still down: sawing on from here

# one bite: the kerf along the bar, ground out of the bodies it touches (the nearest now, the rest the next frames)
func _bite() -> void:
	var e := eye()
	var fr := frame()
	var off := (fr.x * randf_range(-1.0, 1.0) + fr.y * randf_range(-1.0, 1.0)) * JUDDER
	if _dir.angle_to(_bite_dir) < 0.01 and e.distance_to(_prev_eye) < 0.02:
		# held still: it chews the kerf wider, up and down by turns
		_chew += 1
		off = fr.y * minf(CHEW_MAX, CHEW * ceili(_chew / 2.0)) * (1.0 if (_chew % 2) == 1 else -1.0)
	else:
		_chew = 0
	var down := -fr.y.normalized() * DROP
	var a := _prev_eye + _dir * NEAR + down + off
	var z := e + _dir * FAR + down + off
	_prev_eye = e
	_bite_dir = _dir
	last.bites = int(last.bites) + 1
	last.per_s = snappedf(int(last.bites) / maxf(0.05, _move_t), 0.1)
	var touched := []
	for b in bodies_near(e, FAR + 1.0):
		if touches(b, a, z, KERF_R):
			touched.append(b)
			if touched.size() >= MAX_BODIES:
				break
	_tick = LUNGE_TICK if _lunge_t >= 0.0 else TICK
	if touched.is_empty():
		return
	_carve(touched[0], a, z, fr)
	for i in range(1, touched.size()):
		_queue.append([touched[i], a, z])

# the rip up out of whoever the lunge is in: one plane cut up through them, from the bar where it went in to RIP above
func _rip_out() -> void:
	var fr := frame()
	var from := eye() - fr.y.normalized() * DROP
	var t0 := Time.get_ticks_usec()
	for b in _sawn.keys():
		if not is_instance_valid(b):
			continue
		var res := rip(b, from, look(), fr.x.normalized(), _rip_ang)
		if int(res.cut) > 0 or not (res.pieces as Array).is_empty():
			_hit(b, res, fr, true)
	last.rip_ms = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)

# grinds the kerf a-z out of b (if it's still there); the next bite waits longer if that was dear
func _carve(b: Variant, a: Vector3, z: Vector3, fr: Basis) -> void:
	if not is_instance_valid(b):
		return
	var t0 := Time.get_ticks_usec()
	var res := grind(b, a, z)
	var res2 := neck_cut(b) if through_neck(b, a, z) else {}
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	last.carves = int(last.carves) + 1
	last.ms = snappedf((float(last.ms) * (int(last.carves) - 1) + ms) / int(last.carves), 0.01)
	last.max_ms = snappedf(maxf(float(last.max_ms), ms), 0.01)
	_tick = maxf(_tick, ms / 1000.0 / (LUNGE_BUDGET if _lunge_t >= 0.0 else BUDGET))
	for rr in [res, res2]:
		if not rr.is_empty() and (int(rr.cut) > 0 or not (rr.pieces as Array).is_empty()):
			_hit(b, rr, fr)

# what a bite that cut does: spray, pieces off, the saw bucks, the body's held there
func _hit(b: VoxelBody, res: Dictionary, fr: Basis, ripped: bool = false) -> void:
	var first := not _sawn.has(b)
	_sawn[b] = 0.0
	_bite_k = 1.0
	_in_t = 0.35
	_kickback = 1.0
	var cut := int(res.cut)
	_gore = minf(1.0, _gore + cut * 0.0025)
	last.hits = int(last.hits) + 1
	last.cut = int(last.cut) + cut
	for p in res.parts:
		if not (last.parts as Array).has(p):
			(last.parts as Array).append(p)
	last.pieces = int(last.pieces) + (res.pieces as Array).size()
	last.killed = bool(last.killed) or bool(res.killed)
	last.head_off = bool(last.head_off) or bool(res.head_off)
	# chips and blood off the chain: half back up over the saw, half up and out along the bar
	var bits: Array = res.bits
	bloody(bits, 0.5)
	var side := fr.x.normalized() * (1.0 if randf() < 0.5 else -1.0)
	var back := []
	var fwd := []
	for i in bits.size():
		(back if (i % 2) == 0 else fwd).append(bits[i])
	spray({"bits": back}, (Vector3.UP - _dir * (0.12 if ripped else 0.4) + side * 0.3).normalized(), 3.2 if ripped else 2.0)
	spray({"bits": fwd}, (Vector3.UP * 0.7 + _dir * 0.55 - side * 0.4).normalized(), 3.6 if ripped else 2.7)
	var off := not (res.pieces as Array).is_empty()
	if off and ripped:
		# ripped out: up and away over the saw
		fling(b, res, Vector3.UP * randf_range(2.0, 3.0) + _lunge_dir * randf_range(1.0, 2.0) + side * randf_range(0.5, 1.5),
			fr.x * randf_range(5.0, 9.0) + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
	elif off:
		# sawn off: it drops away, kicked aside by the chain
		fling(b, res, Vector3.UP * randf_range(0.4, 1.4) + side * randf_range(0.8, 2.0) + _dir * 0.6,
			Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6)))
	if b.alive:
		b.stagger = maxf(b.stagger, 0.3)
		b.flinch_head = (res.parts as Array).has("head")
	# a beat of hit-stop as it bites in, a longer one when something comes off or it dies (never back to back)
	var now := Time.get_ticks_msec()
	var big := bool(res.killed) or off or ripped
	if (first or big) and now - _stop_ms > 250:
		_stop_ms = now
		if ripped:
			hit_stop(0.11, 0.05)
		elif bool(res.killed):
			hit_stop(0.09, 0.06)
		elif big:
			hit_stop(0.07, 0.1)
		else:
			hit_stop(0.04, 0.25)
	if not top_down():
		arena._kick = maxf(float(arena._kick), 2.0 if ripped else (1.4 if big else 0.6))
	# the lunge: in someone, it drags you on into them
	if _lunge_t >= WIND_T and _lunge_t < WIND_T + LUNGE_T and not _lunge_bit and b.alive and not _lunge_held:
		_lunge_bit = true
		arena.dash(_lunge_dir * LUNGE_BITE_V, WIND_T + LUNGE_T - _lunge_t)

# whoever the saw's in is held there twitching (no walking on, no swinging) till a moment after it stops
func _hold_sawn(dt: float) -> void:
	for b in _sawn.keys():
		if not is_instance_valid(b):
			_sawn.erase(b)
			continue
		_sawn[b] = float(_sawn[b]) + dt
		if float(_sawn[b]) > 0.3 and not (_lunge_t >= 0.0 and not _lunge_ripped):
			_sawn.erase(b)
			continue
		if b.alive and not b.floored():
			b.stagger = maxf(b.stagger, 0.2)
			b.flinch = maxf(b.flinch, randf_range(0.1, 0.55))
			b.knock = Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
			b.yaw += randf_range(-0.04, 0.04)

# ---------------------------------------------------------------- the look

func _look(dt: float) -> void:
	var held := is_instance_valid(_hand) and _hand.is_visible_in_tree()
	if not view.visible and not held:
		return
	var run := absf(_chain - _chain_shown) > 0.0001
	_chain_shown = _chain
	if run and view.visible:
		_place_teeth(_teeth, _chain)
	if held:
		if run:
			_place_teeth(_hand_teeth, _chain)
		var a := 0.002 + 0.004 * _rev + 0.004 * _bite_k
		_hand.position = Vector3(sin(_t * 91.0), sin(_t * 117.0 + 1.3), sin(_t * 71.0)) * a
	var g := _gore * 0.75
	if absf(g - _gore_shown) > 0.004:
		# the bar bloodier the more it's cut
		_gore_shown = g
		_m_bar.albedo_color = BAR_COL.lerp(BLOOD, g)
		_m_bar_hand.albedo_color = BAR_HAND_COL.lerp(BLOOD, g)
		_m_teeth.albedo_color = TOOTH_COL.lerp(BLOOD, g * 0.8)
	if top_down() or not view.visible:
		return
	# the bar's direction in the camera's own space, smoothed (it lags the crosshair in flesh, bite by bite)
	if _vdir.is_normalized() and _dir.is_normalized() and _vdir.angle_to(_dir) > 0.0001:
		_vdir = _vdir.slerp(_dir, 1.0 - exp(-dt * 22.0)).normalized()
	else:
		_vdir = _dir
	var local: Vector3 = (arena.cam.global_transform.basis.inverse() * _vdir).normalized()
	var drop := Vector3(0, -DROP, 0)
	var xf := _aim_xf(REST_GRIP, REST_AT, ROLL)
	if _cut_k > 0.0:
		# out in front, the bar aimed down the kerf, bucking back a little on each bite
		var grip := CUT_GRIP + Vector3(0, 0.01 * _kickback, 0.025 * _kickback)
		var cut := _aim_xf(grip, local * 1.2 + drop, ROLL + 0.06 * sin(_t * 23.0) * _rev)
		var k2 := _cut_k
		k2 = 1.0 - (1.0 - k2) * (1.0 - k2) * (1.0 - k2) if _cutting else _smooth(k2)
		xf = xf.interpolate_with(cut, k2)
	if _lunge_t >= 0.0:
		# from wherever it was (held out, if left was down: that eases back in as the lunge goes)
		var t := _lunge_t
		var t1 := WIND_T + LUNGE_T
		var wind := _aim_xf(WIND_GRIP, WIND_AT, -0.25)
		var thrust := _aim_xf(LUNGE_GRIP + Vector3(0, 0, 0.03 * _kickback), local * 1.3 + drop, ROLL)
		var up_xf := _aim_xf(RIP_GRIP, local * 1.2 + drop, 0.15)
		if t < WIND_T:
			xf = xf.interpolate_with(wind, _smooth(t / WIND_T))
		elif t < t1:
			var k := clampf((t - WIND_T) / 0.07, 0.0, 1.0)
			xf = wind.interpolate_with(thrust, 1.0 - (1.0 - k) * (1.0 - k))
		elif t < t1 + RIP_T:
			xf = thrust.interpolate_with(up_xf, _smooth((t - t1) / RIP_T))
		else:
			xf = up_xf.interpolate_with(xf, _smooth((t - t1 - RIP_T) / BACK_T))
	# the engine shaking: a little idling, more revving, most biting
	var amp := 0.0012 + 0.0032 * _rev + 0.0045 * _bite_k
	xf.origin += Vector3(sin(_t * 93.0), sin(_t * 121.0 + 1.7), 0.6 * sin(_t * 67.0 + 0.5)) * amp
	xf.basis = xf.basis * Basis.from_euler(Vector3(sin(_t * 83.0), 0.7 * sin(_t * 101.0 + 0.3), 1.5 * sin(_t * 59.0 + 2.0)) * amp * 2.5)
	_saw.transform = xf

static func _smooth(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

# ---------------------------------------------------------------- the core (static: the logic test runs it)

## Whether the kerf a-z (radius r, world) can touch b at all: near its upright middle (standing), or within its height
## of its feet (lying, dead, crawling). Cheap; grind only what passes.
static func touches(b: VoxelBody, a: Vector3, z: Vector3, r: float) -> bool:
	if not is_instance_valid(b):
		return false
	var p := b.global_position
	if b.alive and not b.floored() and b.legs_lost() < 2:
		var pts := Geometry3D.get_closest_points_between_segments(a, z, p, p + Vector3.UP * b.height)
		return pts[0].distance_to(pts[1]) <= b.radius + 0.2 + r
	var q := Geometry3D.get_closest_point_to_segment(p, a, z)
	return q.distance_to(p) <= b.height + r

## One bite: every cube within r of a-z (world) ground out of b, each body cube costing hp_per_cube health; whatever
## that leaves hanging comes off (VoxelBody.carve; every cube taken comes back as a flying bit).
static func grind(b: VoxelBody, a: Vector3, z: Vector3, r: float = KERF_R, hp_per_cube: float = HP_PER_CUBE) -> Dictionary:
	return b.carve(a, z, r, hp_per_cube, 1)

## The lunge's rip: a thick plane cut up through b from from (the bar's line), the plane along fwd and up (its normal
## right), from fwd up to ang radians above it, out to FAR (VoxelBody.slice; KERF_R either side of the plane).
static func rip(b: VoxelBody, from: Vector3, fwd: Vector3, right: Vector3, ang: float) -> Dictionary:
	var mid := fwd.rotated(right, ang * 0.5).normalized()
	return b.slice(from, right, mid, FAR, cos(ang * 0.5 + 0.08), KERF_R)

## How far the rip goes up from where the bar points (f, unit): RIP at least, and up to RIP_TOP above level.
static func rip_angle(f: Vector3) -> float:
	return clampf(maxf(RIP, RIP_TOP - asin(clampf(f.y, -1.0, 1.0))), 0.0, 1.3)

## Whether the kerf a-z goes through the middle of b's neck (within NECK_D of the head's joint).
static func through_neck(b: VoxelBody, a: Vector3, z: Vector3) -> bool:
	if not b.parts.has("head") or bool(b.parts.head.gone):
		return false
	var jw := neck_point(b)
	return Geometry3D.get_closest_point_to_segment(jw, a, z).distance_to(jw) <= NECK_D

## Sawn through the neck: the head off at its base (a carve's kerf can't sever it: the head's joint is at its bottom
## edge, so whatever is left of the neck either side of a kerf still counts as joined). A thin plane cut across the
## neck's own axis through the joint (VoxelBody.slice), so the whole head comes away as one piece.
static func neck_cut(b: VoxelBody) -> Dictionary:
	var hb := b.model.bone("head")
	var pose := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(hb)
	var up := pose.basis.y.normalized()
	var fwd := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return b.slice(pose.origin, up, fwd, 0.3, -1.0, b.vm * 0.9)

## The neck joint in the world (the head's bone).
static func neck_point(b: VoxelBody) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(b.model.bone("head")).origin

## The bar turned from cur toward want (unit vectors), by at most max_a radians.
static func turn(cur: Vector3, want: Vector3, max_a: float) -> Vector3:
	var ang := cur.angle_to(want)
	if ang <= max_a:
		return want
	var ax := cur.cross(want)
	if ax.length() < 0.000001:
		return want
	return cur.rotated(ax.normalized(), max_a).normalized()

## Mince: about frac of the bits that aren't already meat, bone or brain turned blood red. Returns how many.
static func bloody(bits: Array, frac: float) -> int:
	var n := 0
	for bt in bits:
		var c: Color = bt.col
		if VoxelBody.FLESH.has(c) or VoxelBody.BRAIN.has(c) or c == VoxelBody.BONE:
			continue
		if randf() < frac:
			bt.col = VoxelBody.FLESH[randi() % VoxelBody.FLESH.size()]
			n += 1
	return n

# a grunt for the checks (stands at the origin facing +z)
static func _grunt(host: Node, m: Material) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, m)
	b.animate(0.0, false)
	return b

# a sweep for the checks: the bar level along -z from 1.3 m in front, at height y, stepped across from x0 to x1 as
# far as it may move between bites at its tip (the worst case: the kerfs must still overlap)
static func _sweep(b: VoxelBody, y: float, x0: float, x1: float) -> Dictionary:
	var out := {"bites": 0, "cut": 0, "pieces": [], "killed": false, "head_off": false, "ms": 0.0, "max_ms": 0.0}
	var stp := BITE_ANG * FAR
	var n := maxi(1, ceili(absf(x1 - x0) / stp))
	for i in n + 1:
		var x := lerpf(x0, x1, float(i) / n)
		var e := Vector3(x, y + DROP, 1.3)
		var a := e + Vector3.FORWARD * NEAR + Vector3.DOWN * DROP
		var z := e + Vector3.FORWARD * FAR + Vector3.DOWN * DROP
		if not touches(b, a, z, KERF_R):
			continue
		var t0 := Time.get_ticks_usec()
		var r := grind(b, a, z)
		var r2 := neck_cut(b) if through_neck(b, a, z) else {}
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		out.bites += 1
		out.ms += ms
		out.max_ms = maxf(float(out.max_ms), ms)
		for rr in [r, r2]:
			if rr.is_empty():
				continue
			out.cut += int(rr.cut)
			for pc in rr.pieces:
				(out.pieces as Array).append(String(pc.part))
			out.killed = bool(out.killed) or bool(rr.killed)
			out.head_off = bool(out.head_off) or bool(rr.head_off)
	if int(out.bites) > 0:
		out.ms = float(out.ms) / int(out.bites)
	return out

static func checks(host: Node) -> Array:
	var out := []
	var was := VoxelBody.immortal
	VoxelBody.immortal = false
	var m := StandardMaterial3D.new()
	# one bite level into the chest from in front: a thin kerf through him, no pieces, health off by the cubes taken
	var b := _grunt(host, m)
	var e := Vector3(0, 1.0 + DROP, 1.3)
	var a := e + Vector3.FORWARD * NEAR + Vector3.DOWN * DROP
	var z := e + Vector3.FORWARD * FAR + Vector3.DOWN * DROP
	var t0 := Time.get_ticks_usec()
	var r := grind(b, a, z)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var cut := int(r.cut)
	out.append([touches(b, a, z, KERF_R) and cut > 40 and cut < 400 and (r.pieces as Array).is_empty() and (r.parts as Array) == ["torso"],
		"a bite into the chest: a thin kerf right through (%d cubes, %.1f ms), nothing off" % [cut, ms]])
	out.append([absf(b.hp - (100.0 - cut * HP_PER_CUBE)) < 0.01 and b.alive, "health off by the cubes ground out (%.1f left)" % b.hp])
	out.append([(r.bits as Array).size() >= cut, "every cube ground out flies (%d bits)" % (r.bits as Array).size()])
	var r2 := grind(b, a, z)
	out.append([int(r2.cut) == 0, "the same bite again grinds nothing new (%d)" % r2.cut])
	# bites that miss: over his head, off to the side; touches() rules them out before any carve
	var up := Vector3(0, 1.6, 0)
	var aside := Vector3(1.4, 0, 0)
	out.append([not touches(b, a + up, z + up, KERF_R) and not touches(b, a + aside, z + aside, KERF_R),
		"a bar over his head or off to the side doesn't touch him"])
	b.queue_free()
	# swept across a shin: the foot comes off
	var b2 := _grunt(host, m)
	var s := _sweep(b2, 0.27, -0.5, -0.06)
	out.append([(s.pieces as Array).has("foot_r") and b2.parts.foot_r.gone and b2.legs_lost() >= 1,
		"swept across the right shin: the foot comes off (%d bites, %d cubes, %.1f ms a bite)" % [s.bites, s.cut, s.ms]])
	# swept across the neck: the head comes off and that kills him
	var s2 := _sweep(b2, 1.42, -0.3, 0.3)
	out.append([bool(s2.head_off) and b2.parts.head.gone and not b2.alive, "swept across the neck: off with his head, dead (%d bites)" % s2.bites])
	# ground into the face (well above the neck): no head off, the brain's what kills
	var b4 := _grunt(host, m)
	var s4 := _sweep(b4, 1.6, -0.06, 0.06)
	out.append([not bool(s4.head_off) and not b4.parts.head.gone, "ground into the face: the head stays on (%d cubes)" % s4.cut])
	b4.queue_free()
	b2.queue_free()
	# swept across the middle: the top half (chest, arms, head) comes off
	var b3 := _grunt(host, m)
	var s3 := _sweep(b3, 0.85, -0.5, 0.5)
	out.append([(s3.pieces as Array).has("torso") and b3.parts.head.gone and b3.parts.arm_l.gone and b3.parts.arm_r.gone and not b3.parts.thigh_l.gone,
		"swept across the middle: sawn in half, the top half off (%d bites, %d cubes)" % [s3.bites, s3.cut]])
	out.append([float(s3.ms) < 40.0, "a bite into the body costs %.1f ms (worst %.1f)" % [s3.ms, s3.max_ms]])
	b3.queue_free()
	# the lunge's rip: up through him from the chest, a gash to the head; that and the brain cut kill him
	var b5 := _grunt(host, m)
	var from := Vector3(0.03, 1.58, 0.85)
	var fwd := (Vector3(0.03, 1.1, 0) - from).normalized()
	var t1 := Time.get_ticks_usec()
	var r5 := rip(b5, from, fwd, Vector3.RIGHT, rip_angle(fwd))
	var ms5 := (Time.get_ticks_usec() - t1) / 1000.0
	out.append([(r5.parts as Array).has("torso") and (r5.parts as Array).has("head") and int(r5.cut) > 200 and (not b5.alive or b5.hp <= 66.0),
		"the lunge's rip: one cut up through chest and head (%d cubes, %.1f ms), %s" % [r5.cut, ms5, "dead" if not b5.alive else "hp %.0f" % b5.hp]])
	b5.queue_free()
	# between bites the bar in flesh moves only so far
	var d := turn(Vector3.FORWARD, Vector3.RIGHT, BITE_ANG)
	var near_v := Vector3(0.02, 0, -1).normalized()
	out.append([absf(Vector3.FORWARD.angle_to(d) - BITE_ANG) < 0.001 and turn(Vector3.FORWARD, near_v, BITE_ANG) == near_v,
		"the bar drags behind the mouse in flesh, keeps up out of it"])
	# mince: skin cubes turned blood, meat left as it is
	var bits := [{"pos": Vector3.ZERO, "col": Color(0.2, 0.5, 0.9)}, {"pos": Vector3.ZERO, "col": VoxelBody.FLESH[0]}]
	bloody(bits, 1.0)
	out.append([VoxelBody.FLESH.has(bits[0].col) and bits[1].col == VoxelBody.FLESH[0], "the spray comes out bloody"])
	VoxelBody.immortal = was
	return out
