class_name LobbyMirror
extends LobbyThing
## The full-length mirror (Smashed.html: MIRROR @2161, mirrorNear, mirrorTryLook, mirrorStep, drawMirror @2247, the
## hair arrows and hint) and Jared's hair styles (BEARDS, setLocalBeard). Owned by the Lobby life session.
##
## The mirror stands at MIRROR (246, 616), 60 x 92, in the bedroom. Pass it and the glass shows your reflection
## (the character, his y-facing flipped, smaller with distance). E next to it ("LOOK"): the camera swings to a
## close view of the glass and the reflection grows to fill it; A/D (or the left stick, or the big arrows) turn
## you round to see yourself from every side, F / Shift+F ([ ] , . and the shoulder buttons too, or the small
## arrows) change the hair, S / down or E ("BACK") step away. The hair is baked onto Jared's frames by LobbyLook; this
## node also swaps the baked frames into every juicy CharSprite it knows of (the player's, the reflections', and
## any another thing hands it with register_sprite).
##
## Port decisions: the close view is its own camera (the HTML game zooms its 2D camera to 4.4x); the real you
## isn't faded, you simply vanish from the room while the glass shows you; first person goes to this camera too.

const MIR := Vector2(246.0, 616.0)
const SIZE := Vector2(60.0, 92.0)
const GLASS := Rect2(220, 529, 48, 80)
const TURN_SPEED := 3.2
const GOAL_SPEED := 6.0

var looking: bool = false
var k: float = 0.0                       # mirrorK: 0..1 fade/zoom in
var turn: float = -PI / 2.0              # mirrorTurn: the way the reflection faces
var goal: float = INF                    # mirrorGoal
var at: Vector2 = Vector2.ZERO           # mirrorAt: where he stood

var _cam: Camera3D
var _quad: MeshInstance3D
var _refl: Dictionary = {}               # person -> CharSprite
var _sprites: Array = []                 # CharSprites that wear the look
var _ui: Control
var _hint: Label
var _title: Label
var _tip: Label
var _prev_cam: Camera3D

func _ready() -> void:
	reach = 60.0
	LobbyLife.ensure_action("lobby_hair", [KEY_F])
	LobbyLook.load_saved()
	global_position = GameData.world_to_3d(MIR.x, MIR.y + 14.0, 0.0)
	_build_mirror()
	_cam = Camera3D.new()
	_cam.name = "MirrorCam"
	_cam.fov = 38.0
	add_child(_cam)
	_cam.top_level = true
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.12, -1), Vector3.UP), GameData.world_to_3d(MIR.x, MIR.y + 175.0, 52.0))
	await get_tree().process_frame
	_hide_world_prop()
	_build_ui()
	if ll and ll.player and ll.player.sprite:
		register_sprite(ll.player.sprite)

func _hide_world_prop() -> void:
	var w = ll.world if ll else null
	if w and w.get("props") is Dictionary:
		var m = w.props.get("mirror")
		if m is Node3D:
			m.visible = false

## A CharSprite that should wear the hair and the shirt print (the juicy ones do).
func register_sprite(s: CharSprite) -> void:
	if s and not _sprites.has(s):
		_sprites.append(s)

# ------------------------------------------------------------------ the mirror itself

func _build_mirror() -> void:
	var w := int(SIZE.x)
	var h := int(SIZE.y)
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	var wood := Color("#6b4526")
	var ox := int(MIR.x - 30.0)
	var oy := 524
	im.fill_rect(Rect2i(0, 0, 60, 89), wood)
	im.fill_rect(Rect2i(1, 1, 58, 2), Color("#8a5a34"))
	im.fill_rect(Rect2i(3, 88, 4, 4), Color("#4a2e1c"))
	im.fill_rect(Rect2i(49, 88, 4, 4), Color("#4a2e1c"))
	var gx := int(GLASS.position.x) - ox
	var gy := int(GLASS.position.y) - oy
	for y in int(GLASS.size.y):
		var t := float(y) / (GLASS.size.y - 1.0)
		var c := Color("#9fb4c4").lerp(Color("#6d8193"), t)
		for x in int(GLASS.size.x):
			var col := c
			var sheen_l := (30.0 - y) * 14.0 / 30.0 if y < 30 else 0.0
			var sheen_r := (44.0 - y) * 0.5
			if y <= 44 and x >= sheen_l and x <= sheen_r:
				col = col.lerp(Color.WHITE, 0.18)
			im.set_pixel(gx + x, gy + y, col)
	_quad = MeshInstance3D.new()
	_quad.name = "Glass"
	var q := QuadMesh.new()
	q.size = SIZE * GameData.UNIT
	_quad.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = ImageTexture.create_from_image(im)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad.material_override = mat
	_quad.top_level = true
	add_child(_quad)
	_quad.global_position = GameData.world_to_3d(MIR.x, MIR.y - 2.4, SIZE.y / 2.0)
	# a soft shadow on the floor under it
	var sh := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(68, 8) * GameData.UNIT
	sq.orientation = PlaneMesh.FACE_Y
	sh.mesh = sq
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0, 0, 0, 0.25)
	sh.material_override = smat
	sh.top_level = true
	add_child(sh)
	sh.global_position = GameData.world_to_3d(MIR.x, MIR.y - 1.0, 0.2)

# ------------------------------------------------------------------ E

## mirrorNear.
func near(p: Node) -> bool:
	var o := ppos(p)
	return absf(o.x - MIR.x) < 24.0 and o.y > MIR.y and o.y < MIR.y + 40.0

func label_for(p: Node) -> String:
	if looking and holding(p):
		return "BACK"
	if can_start(p) and near(p):
		return "LOOK"
	return ""

func act(p: Node) -> void:
	if can_start(p) and near(p):
		look(p as Player)

func look(p: Player) -> void:
	ll.hold(p, self)
	looking = true
	at = ppos(p)
	turn = -PI / 2.0
	goal = INF
	_prev_cam = get_viewport().get_camera_3d()
	_cam.make_current()
	_ui.visible = true
	_sync_ui()

func leave(p: Player) -> void:
	looking = false
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	elif ll.rig:
		ll.rig.camera().make_current()
	_ui.visible = false
	ll.release(p)

func busy_label(_p: Player) -> String:
	return "BACK"

func busy_act(p: Player) -> void:
	leave(p)

func hides_sprite(_p: Player) -> bool:
	return true

func busy_end(_p: Player) -> void:
	looking = false
	if _ui:
		_ui.visible = false
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()

func busy_input(p: Player, event: InputEvent) -> bool:
	if event.is_action_pressed("lobby_hair"):
		hair(-1 if Input.is_physical_key_pressed(KEY_SHIFT) else 1)
		return true
	if event.is_action_pressed("lobby_next"):
		hair(1)
		return true
	if event.is_action_pressed("lobby_prev"):
		hair(-1)
		return true
	if event.is_action_pressed("lobby_back"):
		leave(p)
		return true
	return false

## setLocalBeard(LOCAL_BEARD + d), with the snip.
func hair(d: int) -> void:
	LobbyLook.set_style(LobbyLook.style + d)
	if ll and ll.sfx:
		ll.sfx.noise(0.08, 0.12, 0.7)
		ll.sfx.tone(900, 0.05, "square", 0.06, 1300)
	_sync_ui()

## mirrorSpin: an eighth of a turn, taps adding up.
func spin(d: int) -> void:
	goal = (turn if goal == INF else goal) + d * PI / 4.0

func busy_step(p: Player, dt: float) -> void:
	p.halt()
	var tn := Input.get_axis("move_left", "move_right")
	var js := Player.pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if absf(js.x) > 0.3:
		tn = js.x
	if Input.is_physical_key_pressed(KEY_LEFT):
		tn -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		tn += 1.0
	tn = clampf(tn, -1.0, 1.0)
	var down := maxf(Input.get_action_strength("move_down"), maxf(js.y, 0.0))
	if Input.is_physical_key_pressed(KEY_DOWN):
		down = 1.0
	if down > 0.6:
		leave(p)
		return
	if absf(tn) > 0.01:
		turn += tn * TURN_SPEED * dt
		goal = INF
	elif goal != INF:
		var step := GOAL_SPEED * dt
		if absf(goal - turn) <= step:
			turn = goal
			goal = INF
		else:
			turn += signf(goal - turn) * step
	# stay where he stood
	p.global_position = GameData.world_to_3d(at.x, at.y, 0.0)

# ------------------------------------------------------------------ every frame

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	k = clampf(k + (dt if looking else -dt) * 3.0, 0.0, 1.0)
	if ll == null or ll.player == null:
		return
	_update_reflections(ll.player)
	if ll.gothica:
		_update_reflections(ll.gothica)
	for s in _sprites.duplicate():
		if not is_instance_valid(s):
			_sprites.erase(s)
			continue
		wear(s)
	for p in _refl.keys():
		if is_instance_valid(_refl[p]):
			wear(_refl[p])
	if looking:
		_title.visible = k >= 0.8

## Swap the baked frame (hair, shirt print) into a juicy CharSprite.
func wear(s: CharSprite) -> void:
	if s.char_id != "juicy" or s.current_path == "":
		return
	var base: Texture2D = GameData.tex(s.current_path)
	var tex := LobbyLook.baked(s.current_path, base, s.current_flip)
	var cur = s._mat.get_shader_parameter("tex") if s._mat else null
	if tex != cur:
		s._mat.set_shader_parameter("tex", tex)

func _update_reflections(who: Node3D) -> void:
	var o := LobbyLife.hpos(who)
	var is_me := who == ll.player
	var in_zone := o.y > MIR.y and o.y < MIR.y + 170.0 and absf(o.x - MIR.x) < 70.0
	var busy_elsewhere: bool = is_me and ll.busy.has(who) and ll.busy[who] != self
	if who is Player and (who.dz > 0.5 or who.frozen) and not (is_me and looking):
		in_zone = false
	var show: bool = (in_zone or (is_me and k > 0.0)) and not busy_elsewhere
	var sp: CharSprite = _refl.get(who)
	if sp == null:
		if not show:
			return
		sp = CharSprite.new()
		sp.show_shadow = false
		sp.top_level = true
		add_child(sp)
		_refl[who] = sp
	sp.visible = show
	if not show:
		return
	var id: String = who.char_id if "char_id" in who else "goth"
	sp.char_id = id
	var d := o.y - MIR.y
	var s := 0.72 - 0.3 * minf(1.0, d / 170.0)
	var rx := MIR.x + (o.x - MIR.x) * 0.35
	var zf := 6.0                                     # the reflection's feet over the floor
	var fac: Vector2 = who.facing if "facing" in who else Vector2(0, 1)
	var f := Vector2(fac.x, -fac.y)
	var mv: bool = bool(who.get("moving"))
	if is_me and k > 0.0:
		var e := k * k * (3.0 - 2.0 * k)
		s += (1.0 - s) * e
		rx += (MIR.x - rx) * e
		zf += 2.0 * e
		if looking:
			f = Vector2(cos(turn), -sin(turn))
			mv = false
	sp.facing = f
	sp.moving = mv
	sp.odo = float(who.get("odo") if who.get("odo") != null else 0.0)
	sp.scale = Vector3(s, s, s)
	sp.global_position = GameData.world_to_3d(rx, MIR.y - 1.4, zf)

# ------------------------------------------------------------------ the on-screen controls

func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "MirrorUI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.visible = false
	ll.ui.root.add_child(_ui)
	var mk := func(text: String, size: Vector2, anchor: Vector2, off: Vector2, cb: Callable) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = size
		b.size = size
		b.focus_mode = Control.FOCUS_NONE
		b.anchor_left = anchor.x
		b.anchor_right = anchor.x
		b.anchor_top = anchor.y
		b.anchor_bottom = anchor.y
		b.offset_left = off.x - size.x / 2.0
		b.offset_top = off.y - size.y / 2.0
		b.offset_right = off.x + size.x / 2.0
		b.offset_bottom = off.y + size.y / 2.0
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(cb)
		_ui.add_child(b)
		return b
	mk.call("<", Vector2(78, 78), Vector2(0.5, 0.42), Vector2(-250, 0), func(): spin(-1))
	mk.call(">", Vector2(78, 78), Vector2(0.5, 0.42), Vector2(250, 0), func(): spin(1))
	mk.call("<", Vector2(54, 54), Vector2(0.5, 1.0), Vector2(-150, -150), func(): hair(-1))
	mk.call(">", Vector2(54, 54), Vector2(0.5, 1.0), Vector2(150, -150), func(): hair(1))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -92
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(box)
	_hint = _lbl(10, Color(0.965, 0.82, 0.48, 0.85))
	_title = _lbl(22, Color("#f6d17a"))
	_tip = _lbl(14, Color.WHITE)
	box.add_child(_hint)
	box.add_child(_title)
	box.add_child(_tip)

func _lbl(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _sync_ui() -> void:
	_hint.text = "HAIR  %d of %d" % [LobbyLook.style + 1, LobbyLook.beards().size()]
	_title.text = LobbyLook.style_label()
	var touch := DisplayServer.is_touchscreen_available()
	_tip.text = ("big arrows to turn round  ·  small arrows: hair  ·  BACK to step away" if touch
		else "A / D or the big arrows: turn round  ·  F or the small arrows: hair  ·  S or E: step away")

# ------------------------------------------------------------------ test

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	var st := 0
	for s in parts:
		if s.begins_with("hair="):
			st = int(s.substr(5))
	LobbyLook.set_style(st)
	tl.go(246.0, 650.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	tl.later(0.8, func(): tl.use())
	if parts.has("turn"):
		tl.later(2.0, func(): spin(1))
