class_name GothLife
extends LobbyThing
## Gothica's extra life in the lobby, an add-on to scripts/npc/gothica.gd (which wanders her about) that doesn't
## edit it: it steers her from outside. Owned by the Lobby life session.
## Follows Smashed.html: canCarry / lobbyAction (the carry), lobbyGoth, putGothDown, throwGoth, stepThrownGoth,
## drawThrownGoth (specs/gothica.md).
##
## The API the other things use (keep it):
## - claim(owner, spot, speed_mul, face): she walks to spot (HTML units) at npcSpeed * speed_mul, round the
##   furniture, and stands there facing face until unclaim(owner). The strongest claim wins (the cards' dealer
##   spot over the gym's watching spot over the rest), the newest among equals. at_spot(owner): she's there.
## - say(text, dur): a speech bubble over her.
## - is_busy(): she's being carried or thrown (or is swimming out): can't deal, can't watch.
## - held: true while something else moves her (carry, throw): her own wander is off.
## - carrying(p): he has her in his arms (also the player's meta "carrying_goth", which the gym, the table, the
##   rope and the bed read to turn themselves off).
##
## Carrying (E "PICK UP" next to her, only Juicy Jared; E "PUT DOWN"): he is drawn as one picture with her in his
## arms (the HTML game's carry frames, art/gothica/carry_*.png, the walk built the way it builds it at load), he
## can't roll, can't leave the lounge with her, and a pick or a set-down takes 0.34 s in which he stands still.
## Up the tower with him: on the board E throws her in (throw_from_board), walking off the tip drops her as he
## dives (drop_off_board(p, vel), which the pool calls). She cartwheels through the air, then is paddling (3.5 s,
## drifting, ringing the water, shoving the ducks), then climbs out over the near edge and drips; or lies flat on
## the floor for 1.8 s if she missed.
## Watching the gym: when the gym says he has done 2 reps she hurries to its watch spot and watches; at 5 reps she
## says "Wow, you're really strong!". Needs the gym's signal rep and lifting(p) (connected when it is there).

var goth: Node3D
## Something else is moving her (carry/throw/swim): her wander is switched off and she's placed by that.
var held: bool = false

## Who has her in his arms (null: nobody) and which way the art faces (true: he faces left).
var carrier: Player = null
var face: bool = false
## The pick-up / set-down: {kind: "pick"|"drop", t, dur}, empty when none.
var anim: Dictionary = {}
## Thrown: "" | "air" | "floor" | "swim".
var thrown: String = ""

signal picked_up(player: Node)
signal put_down(player: Node)
signal thrown_in(x: float, y: float)

const CARRY_DUR := 0.34
const NPC_AREA := Rect2(70, 250, 520, 160)
const PRIO := {"cards": 2, "watch": 1}

var _claims: Array = []        # [{owner, spot, mul, face}], newest last
var _base_speed: float = 38.0
var _was_claimed: bool = false
var _pose: LobbyPic
var _pose_shadow: MeshInstance3D
var _walk: Array = []
var _stand: Texture2D
var _squat: Texture2D
var _spin_tex: Array = []
var _spin_pic: LobbyPic
var _spin_shadow: MeshInstance3D
var _t_pos: Vector2 = Vector2.ZERO     # thrown: where she is (HTML units)
var _t_z: float = 0.0
var _t_vel: Vector3 = Vector3.ZERO
var _t_spin: float = 0.0
var _t_wait: float = 0.0
var _t_rip: float = 0.0
var _t_odo: float = 0.0
var _locked_controls: bool = false
var _watch: Dictionary = {}            # {p, machine, said, last}
var _gym_hooked: bool = false
## For screenshots: the thrown state stands still.
var test_hold: bool = false

func _ready() -> void:
	process_physics_priority = -10       # before her own _physics_process (0)
	reach = LobbyLife.T("carryRange", 46.0)
	goth = ll.gothica if ll else null
	if goth == null:
		var g := get_tree().get_nodes_in_group("gothica")
		goth = g[0] if g.size() > 0 else null
	_base_speed = LobbyLife.T("npcSpeed", 38.0)
	for k in 7:
		_walk.append(LobbyPic.art("gothica/carry_walk_%d.png" % k))
	_stand = LobbyPic.art("gothica/carry_stand_c.png")
	_squat = LobbyPic.art("gothica/carry_squat_m.png")
	for k in 16:
		_spin_tex.append(LobbyPic.art("gothica/goth_spin_%02d.png" % k))
	_hook_gym.call_deferred()

# ------------------------------------------------------------------ steering (claims)

func claim(owner: String, spot: Vector2, speed_mul: float = 1.0, face_: Vector2 = Vector2(0, 1)) -> void:
	unclaim(owner)
	_claims.append({"owner": owner, "spot": spot, "mul": speed_mul, "face": face_})

func unclaim(owner: String) -> void:
	for c in _claims.duplicate():
		if c.owner == owner:
			_claims.erase(c)

## The claim that counts: the highest priority (cards, then watching, then the rest), the newest among equals.
func _top() -> Dictionary:
	var best: Dictionary = {}
	var bp := -1
	for c in _claims:
		var pr: int = int(PRIO.get(c.owner, 0))
		if pr >= bp:
			bp = pr
			best = c
	return best

func claimed_by() -> String:
	var c := _top()
	return "" if c.is_empty() else String(c.owner)

func at_spot(owner: String) -> bool:
	var c := _top()
	if goth == null or c.is_empty() or c.owner != owner:
		return false
	return LobbyLife.hpos(goth).distance_to(c.spot) < 5.0

func is_busy() -> bool:
	return held

func say(text: String, dur: float = 2.6) -> void:
	if ll and ll.ui and goth:
		ll.ui.say(goth, text, dur, 92.0)

## Where she is, HTML units.
func pos() -> Vector2:
	return LobbyLife.hpos(goth) if goth else Vector2.ZERO

func _physics_process(_delta: float) -> void:
	if goth == null or not is_instance_valid(goth):
		return
	if held:
		goth.set("_enabled", false)
		return
	goth.set("_enabled", goth.visible)
	var c := _top()
	if c.is_empty():
		if _was_claimed:
			_was_claimed = false
			goth.set("_speed", _base_speed)
			goth.set("wait", 1.5)
		return
	_was_claimed = true
	goth.set("_speed", _base_speed * float(c.mul))
	var at := LobbyLife.hpos(goth)
	if at.distance_to(c.spot) < 4.0:
		goth.set("wait", 0.5)
		goth.set("facing", c.face)
		goth.set("moving", false)
		goth.set("target", at)
	else:
		goth.set("wait", 0.0)
		goth.set("target", c.spot)

# ------------------------------------------------------------------ the pool's view of her

## While she paddles: where, and how fast, for the ducks to mind ({} when she isn't).
func swimmer_info() -> Dictionary:
	if thrown != "swim":
		return {}
	return {"x": _t_pos.x, "y": _t_pos.y, "vx": _t_vel.x, "vy": _t_vel.y}

## For the drips: where she stands, how she faces, and whether she is swimming or up in the air (carried, thrown).
func drip_info() -> Dictionary:
	if goth == null:
		return {}
	var o := pos()
	var f: Vector2 = goth.get("facing") if goth.get("facing") is Vector2 else Vector2(0, 1)
	return {"x": o.x, "y": o.y, "fx": f.x, "fy": f.y, "swim": thrown == "swim", "diving": thrown == "air" or carrier != null}

# ------------------------------------------------------------------ E: pick her up, put her down

func _pool() -> LobbyPool:
	return ll.things.get("pool") if ll else null

func carrying(p: Node) -> bool:
	return carrier != null and carrier == p

## Jared (the new art, juicy) and Jared (old art) can carry; Tyson, Inky and Gothica herself cannot.
static func is_carrier(p: Node) -> bool:
	var c = p.get("char_id")
	return c == "juicy" or c == "jared"

## canCarry(w, p): on his feet, free, not on the tower or the bench..., and near her.
func can_carry(p: Node) -> bool:
	if p == null or goth == null or not is_instance_valid(goth) or carrier != null or thrown != "" or held:
		return false
	if LobbyLife.T("npcGoth", 1.0) == 0.0 or not goth.visible or not is_carrier(p):
		return false
	if not (ll.can_start(p)):
		return false
	var gym = ll.things.get("gym")
	if gym and gym.has_method("lifting") and gym.lifting(p):
		return false
	if gym and gym.has_method("holding_plate") and String(gym.holding_plate(p)) != "":
		return false
	var pl := _pool()
	if pl and pl.diving(p):
		return false
	return ppos(p).distance_to(pos()) < LobbyLife.T("carryRange", 46.0)

## Nearest by the player's reckoning: when he carries her she is with him.
func ground_distance(player: Node3D) -> float:
	if carrying(player):
		return 0.0
	return ppos(player).distance_to(pos())

func label_for(p: Node) -> String:
	if carrying(p):
		return "PUT DOWN"
	return "PICK UP" if can_carry(p) else ""

func act(p: Node) -> void:
	if not anim.is_empty():
		return                                    # the scoop or the set-down: E is ignored
	if carrying(p):
		_begin(p, "drop")
	elif can_carry(p):
		pick_up(p)

## E next to her: scoop her up (carrier = p, face the way he looks, the pick animation, she bounces).
func pick_up(p: Player) -> void:
	carrier = p
	face = p.facing.x < 0.0
	held = true
	p.set_meta("carrying_goth", true)
	goth.visible = false
	_begin(p, "pick")
	_ensure_pose(p)
	picked_up.emit(p)

func _begin(p: Player, kind: String) -> void:
	anim = {"kind": kind, "t": 0.0, "dur": CARRY_DUR}
	if p.controls_enabled:
		p.controls_enabled = false                 # he stands still for the 0.34 s
		_locked_controls = true
	p.halt()

## putGothDown: set down behind him (20 back, 4 lower), snapped into her strolling area, standing 2-4 s.
func _put_down(p: Node) -> void:
	var pl := _pool()
	var at := Vector2.ZERO
	if p != null and is_instance_valid(p):
		at = ppos(p)
		if pl and pl.diving(p):
			var sp := pl.state_pos(p)
			at = Vector2(sp.x, sp.y)
		at += Vector2(20.0 if face else -20.0, 4.0)
	else:
		at = pos()
	at.x = clampf(at.x, NPC_AREA.position.x, NPC_AREA.end.x)
	at.y = clampf(at.y, NPC_AREA.position.y, NPC_AREA.end.y)
	_release_carrier(p)
	goth.visible = true
	goth.call("place", at.x, at.y)
	goth.set("moving", false)
	goth.set("wait", 2.0 + randf() * 2.0)
	goth.set("facing", Vector2(0, 1))
	held = false
	put_down.emit(p)

func _release_carrier(p: Node) -> void:
	anim = {}
	if p != null and is_instance_valid(p):
		p.set_meta("carrying_goth", false)
		if _locked_controls:
			p.controls_enabled = true
		if ll.pose_of(p) == _pose:
			ll.set_pose(p, null)
	_locked_controls = false
	_pose = null
	_pose_shadow = null
	carrier = null

# ------------------------------------------------------------------ throwing

## E on the board with her: throwGoth(w, (p.fx < 0 ? -1 : 1) * T.diveFwd * 1.25, 40, T.diveHop * 0.9).
func throw_from_board(p: Player) -> void:
	if not carrying(p):
		return
	var dir := -1.0 if p.facing.x < 0.0 else 1.0
	if ll.sfx:
		ll.sfx.tone(260.0, 0.14, "triangle", 0.16, 720.0)
	_throw(p, Vector3(dir * LobbyLife.T("diveFwd", 130.0) * 1.25, 40.0, LobbyLife.T("diveHop", 240.0) * 0.9))

## He walked off the tip with her: she's thrown with his velocity (p.vx * 1.15, p.vy, p.vz * 1.05).
func drop_off_board(p: Player, vel: Vector3) -> void:
	if not carrying(p):
		return
	_throw(p, vel)

func _throw(p: Player, v: Vector3) -> void:
	var pl := _pool()
	var at := ppos(p)
	var z := 0.0
	if pl and pl.diving(p):
		var sp := pl.state_pos(p)
		at = Vector2(sp.x, sp.y)
		z = sp.z
	_release_carrier(p)
	thrown = "air"
	held = true
	_t_pos = at
	_t_z = z
	_t_vel = v
	_t_spin = 0.0
	goth.visible = true
	goth.set("moving", false)
	goth.set("facing", Vector2(0, 1))
	_show_goth_sprite(false)
	if ll.ui:
		ll.ui.float_text(at.x, at.y, z + 40.0, "WHEEE!", Color("#f7a8ff"), 0.9, 16)
	_place_thrown()

func _show_goth_sprite(on: bool) -> void:
	var sp = goth.get("sprite")
	if sp is CharSprite:
		sp.visible = on

func _step_thrown(dt: float) -> void:
	var pl := _pool()
	match thrown:
		"air":
			_t_vel.z -= 1200.0 * dt
			_t_z += _t_vel.z * dt
			_t_pos += Vector2(_t_vel.x, _t_vel.y) * dt
			_t_spin += 9.0 * dt
			if _t_z > 0.0:
				_place_thrown()
				return
			_t_z = 0.0
			_t_vel.z = 0.0
			if LobbyPool.in_water(_t_pos.x, _t_pos.y):
				thrown = "swim"
				_t_wait = 3.5
				_t_vel.x *= 0.2
				_t_vel.y = 0.0
				_t_odo = 0.0
				_t_rip = 0.4
				if pl:
					pl.splash(_t_pos.x, _t_pos.y, true)
					for i in 3:
						pl.ripple(_t_pos.x, _t_pos.y, 1.3, 70.0, 2.5, i * 0.18)
				_show_goth_sprite(true)
				thrown_in.emit(_t_pos.x, _t_pos.y)
			else:
				thrown = "floor"
				_t_wait = 1.8
				_t_vel = Vector3.ZERO
				if pl:
					pl.fx.burst(_t_pos.x, _t_pos.y, 3, Color("#5a6274"), 120.0)
				if ll.ui:
					ll.ui.float_text(_t_pos.x, _t_pos.y, 40.0, "OOF", Color("#ffd0d0"), 0.9, 16)
		"swim":
			_t_pos.x += _t_vel.x * dt
			_t_vel.x *= 1.0 - minf(1.0, 3.0 * dt)
			_t_wait -= dt
			_t_odo += 20.0 * dt
			_t_rip -= dt
			if _t_rip <= 0.0:
				if pl:
					pl.ripple(_t_pos.x, _t_pos.y, 1.6, 26.0, 1.5)
				_t_rip = 0.9
			var b := LobbyPool.swim_rect()
			_t_pos.x = clampf(_t_pos.x, b.position.x, b.end.x)
			_t_pos.y = clampf(_t_pos.y, b.position.y, b.end.y)
			if _t_wait <= 0.0:
				# she climbs out over the near edge and stands there a moment
				thrown = ""
				LobbyPool.waterline(goth.get("sprite"), false)
				_show_goth_sprite(true)
				goth.visible = true
				goth.call("place", _t_pos.x, LobbyPool.pool_rect().end.y + 18.0)
				goth.set("facing", Vector2(0, 1))
				goth.set("moving", false)
				goth.set("wait", 1.2)
				held = false
				return
		"floor":
			_t_wait -= dt
			if _t_wait <= 0.0:
				thrown = ""
				var x := clampf(_t_pos.x, NPC_AREA.position.x, NPC_AREA.end.x)
				var y := clampf(_t_pos.y, NPC_AREA.position.y, NPC_AREA.end.y)
				_show_goth_sprite(true)
				goth.call("place", x, y)
				goth.set("wait", 1.0)
				held = false
				if _spin_pic:
					_spin_pic.visible = false
				if _spin_shadow:
					_spin_shadow.visible = false
				return
	_place_thrown()

## Put her node and her picture where the thrown state says.
func _place_thrown() -> void:
	var pl := _pool()
	var fp := ll.player != null and ll.player.is_first_person()
	var r := LobbyLife.T("radius", 14.0)
	if thrown == "swim":
		goth.global_position = GameData.world_to_3d(_t_pos.x, _t_pos.y, LobbyPoolFx.WATER_Z)
		goth.set("facing", Vector2(0, 1))
		goth.set("moving", false)
		goth.set("odo", _t_odo)
		var wob := sin(LobbyLife.now() * 1000.0 / 260.0 + 6.0)
		var sp = goth.get("sprite")
		if sp is CharSprite:
			sp.facing = Vector2(0, 1)
			sp.moving = false
			sp.update_view(get_viewport().get_camera_3d())
			LobbyPool.waterline(sp, true, wob)
		if pl:
			var rw := 30.0 * 0.42
			pl.ellipse("goth_a", _t_pos.x, _t_pos.y, rw + wob, 5.0, Color(225 / 255.0, 246 / 255.0, 1.0), 2.0, 0.8)
			pl.ellipse("goth_b", _t_pos.x, _t_pos.y + 1.0, rw + 6.0 - wob, 8.0, Color(225 / 255.0, 246 / 255.0, 1.0), 2.0, 0.6)
		if _spin_pic:
			_spin_pic.visible = false
		if _spin_shadow:
			_spin_shadow.visible = false
		return
	# in the air or flat on the floor: her picture, turning
	goth.global_position = GameData.world_to_3d(_t_pos.x, _t_pos.y, 0.0)
	if _spin_pic == null:
		_spin_pic = LobbyPic.new()
		_spin_pic.name = "GothThrown"
		_spin_pic.units_per_px = 0.5
		add_child(_spin_pic)
		_spin_shadow = _make_shadow(_spin_pic)
	_spin_pic.visible = true
	if _spin_shadow:
		_spin_shadow.visible = true
	var idx := 4 if thrown == "floor" else int(round(_t_spin / (TAU / 16.0))) % 16
	if fp and thrown == "air":
		idx = 0                                   # no cartwheel in first person
	_spin_pic.texture = _spin_tex[idx]
	var fy := _t_pos.y + r * 0.9                  # his p.y is the middle: the feet are 0.9 radius lower on the screen
	var lift := pl._lift(ll.player, _t_pos.x, fy, _t_z) if pl else {"z": _t_z, "s": 1.0}
	var half := 15.0 if thrown == "floor" else 40.0          # her middle's height over her feet (dw / 2 when lying)
	_spin_pic.foot_px = float(_spin_pic.texture.get_height()) / 2.0 - half / 0.5
	_spin_pic.global_position = GameData.world_to_3d(_t_pos.x, fy, float(lift.z))
	_spin_pic.scale = Vector3.ONE * float(lift.s)
	if _spin_shadow:
		var sf := 1.0 - minf(0.45, _t_z / 22.0)
		_spin_shadow.global_position = GameData.world_to_3d(_t_pos.x, fy - 1.0, 0.012 / GameData.UNIT)
		_spin_shadow.scale = Vector3(sf, 1, sf)

## A soft shadow on the floor under a picture (CharSprite's), as a free-standing mesh.
func _make_shadow(under: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	var r := LobbyLife.T("radius", 14.0) * GameData.UNIT
	q.size = Vector2(r * 0.95 * 2.0, r * 0.6 * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = CharSprite._shadow_shader_get()
	sm.set_shader_parameter("alpha", 0.35)
	m.material_override = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.top_level = true
	return m

# ------------------------------------------------------------------ carrying: the picture, the walls

## His picture with her in his arms (a pose, so his own sprite is hidden): the walk frame for how far he has
## walked, the standing one, or the squat of the scoop and the set-down.
func _ensure_pose(p: Player) -> void:
	if _pose != null and is_instance_valid(_pose) and ll.pose_of(p) == _pose:
		return
	var h := CharFrames.draw_height(p.char_id, "front_a") * (185.0 / 160.0) * LobbyLife.T("carryScale", 1.0)
	_pose = LobbyPic.new()
	_pose.name = "CarryPose"
	_pose.units_per_px = h / 185.0
	_pose.foot_px = 185.0 - 168.0                       # his feet land around row 168 of 185
	_pose.texture = _stand
	ll.set_pose(p, _pose)
	_pose_shadow = null

func _pose_frame(p: Player) -> Texture2D:
	if not anim.is_empty():
		var squat: bool = anim.t < 0.2 if anim.kind == "pick" else anim.t >= 0.12
		if squat and _squat:
			return _squat
	if p.moving:
		var n := _walk.size()
		var k := int(floor(maxf(p.odo, 0.0) / LobbyLife.T("runStride", 13.0))) % maxi(1, n)
		return _walk[k] if _walk[k] else _stand
	return _stand

func _process(delta: float) -> void:
	if goth == null or not is_instance_valid(goth):
		return
	var dt := minf(delta, 0.1)
	if thrown != "":
		if not test_hold:
			_step_thrown(dt)
	elif carrier != null:
		_step_carried(dt)
	_step_watch(dt)

## lobbyGoth while carried.
func _step_carried(dt: float) -> void:
	var p := carrier
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		_put_down(null)
		return
	var pl := _pool()
	_ensure_pose(p)
	goth.global_position = p.global_position
	var dived := pl != null and pl.diving(p)
	if not anim.is_empty():
		anim.t += dt
		if anim.t >= anim.dur:
			var k: String = anim.kind
			anim = {}
			if _locked_controls:
				p.controls_enabled = true
				_locked_controls = false
			if k == "drop":
				_put_down(p)
				return
	# face the way he last walked
	if p.moving and absf(p.steer.x) > 0.2:
		face = p.steer.x < 0.0
	elif dived and p.moving and absf(p.facing.x) > 0.2:
		face = p.facing.x < 0.0
	if _pose and is_instance_valid(_pose):
		_pose.texture = _pose_frame(p)
		_pose.flip = face
		_pose.shift_x = (-4.0 if face else 4.0) * _pose.units_per_px / 0.5     # his head over p.x (row 72 of 160)
	# no rolling with her in his arms, and she lives in the lounge
	p.roll_cd = maxf(p.roll_cd, 0.2)
	if not dived:
		_shut(p)

## lobbyClamp(p, T.radius, shut = true): only the lounge and the bedroom, not the doorways or the yard.
func _shut(p: Player) -> void:
	var r := LobbyLife.T("radius", 14.0)
	var wl := 18.0
	var o := ppos(p)
	var rects: Array = [Rect2(wl + r, wl + r, 860.0 - wl * 2.0 - r * 2.0, 520.0 - wl * 2.0 - r * 2.0)]
	var bd = LobbyLife.D("BEDROOM")
	if bd is Dictionary:
		rects.append(Rect2(float(bd.x0) + r, float(bd.y0) + r, float(bd.x1) - float(bd.x0) - r * 2.0, float(bd.y1) - float(bd.y0) - r * 2.0))
	var best := o
	var bdist := INF
	for rc in rects:
		var q := Vector2(clampf(o.x, rc.position.x, rc.end.x), clampf(o.y, rc.position.y, rc.end.y))
		var d := q.distance_squared_to(o)
		if d < bdist:
			bdist = d
			best = q
	if bdist > 0.0001:
		p.global_position = GameData.world_to_3d(best.x, best.y, p.html_pos().z)
		var n := (best - o).normalized()
		var into := p.vel.dot(-n)
		if into > 0.0:
			p.vel += n * into

# ------------------------------------------------------------------ watching the gym

func _hook_gym() -> void:
	if _gym_hooked or ll == null:
		return
	var gym = ll.things.get("gym")
	if gym == null or not gym.has_signal("rep"):
		return
	_gym_hooked = true
	var n := 3
	for s in gym.get_signal_list():
		if s.name == "rep":
			n = (s.args as Array).size()
	match n:
		1: gym.rep.connect(func(a): _on_rep(a, "", 0))
		2: gym.rep.connect(func(a, b): _on_rep(a, "", int(b)))
		3: gym.rep.connect(func(a, b, c): _on_rep(a, str(b), int(c)))
		_: gym.rep.connect(func(a, b, c, _d): _on_rep(a, str(b), int(c)))

## A rep done: from the second one she comes to watch.
func _on_rep(p: Node, machine: String, reps: int) -> void:
	if reps < 2 or p == null:
		return
	if machine == "":
		var gym = ll.things.get("gym")
		if gym and gym.has_method("machine_of"):
			machine = String(gym.machine_of(p))
	if _watch.is_empty():
		_watch = {"p": p, "machine": machine, "said": false, "reps": reps, "idle": 0.0}
	else:
		_watch.reps = reps
		_watch.machine = machine
	_watch.idle = 0.0

func _step_watch(dt: float) -> void:
	if _watch.is_empty():
		return
	var p = _watch.p
	var gym = ll.things.get("gym")
	var lifting := false
	if gym and gym.has_method("lifting") and is_instance_valid(p):
		lifting = gym.lifting(p)
		if lifting and gym.has_method("reps"):
			_watch.reps = int(gym.reps(p))
		if lifting and gym.has_method("machine_of"):
			_watch.machine = String(gym.machine_of(p))
	else:
		_watch.idle += dt
		lifting = _watch.idle < 4.0
	if not lifting or held:
		unclaim("watch")
		if not lifting:
			if goth and not held:
				goth.set("wait", 1.2)
			_watch = {}
		return
	var m: String = _watch.machine
	var spot := Vector2(390, 262) if m == "leg" else Vector2(478, 154)
	var at := Vector2(454, 206) if m == "leg" else Vector2(420, 120)
	if gym:
		if gym.has_method("watch_spot"):
			spot = gym.watch_spot(m)
		if gym.has_method("watch_at"):
			at = gym.watch_at(m)
	var d := (at - spot)
	claim("watch", spot, 2.4, d.normalized() if d.length() > 0.001 else Vector2(0, 1))
	if at_spot("watch"):
		# looking at him from where she stands now
		var f := (at - pos())
		if f.length() > 0.001:
			goth.set("facing", f.normalized())
		if not _watch.said and int(_watch.reps) >= 5:
			_watch.said = true
			say("Wow, you're really strong!", 3.5)

# ------------------------------------------------------------------ screenshots

## ?lobby=goth[,carry|throw|swim|floor|watch][,fp]
func test_scene(tl: Node, parts: PackedStringArray) -> void:
	var p := ll.player
	var pl := _pool()
	if parts.has("carry"):
		goth.call("place", 300.0, 300.0)
		tl.go(320.0, 300.0, Vector2(1, 0))
		tl.later(0.5, func(): pick_up(p))
		return
	if parts.has("throw") or parts.has("swim") or parts.has("floor"):
		var g := pl.tower_geo()
		tl.go(float(g.ladderX), 214.0, Vector2(0, -1))
		goth.call("place", float(g.ladderX) + 10.0, 214.0)
		tl.later(0.4, func():
			pick_up(p)
			anim = {})
		tl.later(0.8, func():
			pl.start_climb(p)
			var s: Dictionary = pl._s[p]
			s.dive = LobbyPool.Dive.BOARD
			s.hz = g.boardH
			s.x = 660.0 if parts.has("throw") else g.tipX
			s.fx = 1.0
			s.fy = 0.0)
		if parts.has("swim"):
			tl.later(1.4, func():
				throw_from_board(p)
				for i in 12:
					_step_thrown(0.06)
				_t_wait = 99.0
				test_hold = true)
		if parts.has("throw"):
			tl.later(1.4, func():
				throw_from_board(p)
				for i in 5:
					_step_thrown(0.06)
				test_hold = true)
		if parts.has("floor"):
			tl.later(1.4, func():
				pl._s[p].x = g.boardX0 - 15.0
				pl._s[p].fx = -1.0
				p.facing = Vector2(-1, 0)
				throw_from_board(p)
				for i in 14:
					_step_thrown(0.05)
				test_hold = true)
		return
	tl.go(380.0, 300.0, Vector2(0, 1))
