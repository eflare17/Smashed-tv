extends Interactable
## Smash on an arcade cabinet in the main game's lounge, on the top wall right of the Bricks / SNES cabinet.
## Made by the main game's Arcade (scripts/arcade/arcade.gd, one call), never by Smash itself, so the game in this
## folder still runs on its own.
##  - The cabinet is a picture drawn here in the same layout as the HTML game's cabinets (marquee, screen, control
##    panel, coin door), standing in the world with the World's prop shader and lit by the LookPass like its
##    neighbours (the screen and marquee glow at night), with a solid so you can't walk through it.
##  - Smash runs in its own SubViewport (its own 3D world). Its picture is the cabinet's live little screen: the
##    attract demo, playing to itself (only while the player is near, to save the frame).
##  - E (PLAY) blows that same viewport up to the whole window and hands it the input: the player stands still
##    and the main HUD goes, the way the other cabinets' overlay does (Arcade.hold_player). Esc, E or the pad's B /
##    View (arcade_close) walks away; the game goes back to its demo.

const SMASH := preload("smash.tscn")

## Middle of the cabinet (world units) and its picture's size (the other cabinets': 56 x 104, 2 pixels a unit).
const X := 305.0
const W := 56.0
const H := 104.0
const SCREEN_SIZE := Vector2i(216, 180)
## Smash's HUD is laid out for a 720-high screen and scaled to whatever the viewport really is.
const UI_HEIGHT := 720
## Run the demo on the cabinet's screen while the player is this close (world units).
const AWAKE := 420.0
const BODY := Color("#1b2a6b")
const TRIM := Color("#ff3b3b")
const MARQUEE := Color("#2a1030")
const TITLE := Color("#ffd23f")
const OUTLINE := Color("#0f0f14")

var arcade
var cab_y := 116.0
## The Smash scene's root (smash.gd).
var smash

var _vp: SubViewport
var _prop: MeshInstance3D
var _layer: CanvasLayer
var _view: TextureRect
var _open := false
var _opened_at := 0
var _awake := true

func _init() -> void:
	name = "SmashCabinet"
	reach = 70.0

func _ready() -> void:
	cab_y = float(GameData.data.get("calls", {}).get("cabY", 116.0))
	global_position = GameData.world_to_3d(X, cab_y + 20.0)
	_vp = SubViewport.new()
	_vp.size = SCREEN_SIZE
	_vp.size_2d_override = Vector2i(UI_HEIGHT * SCREEN_SIZE.x / SCREEN_SIZE.y, UI_HEIGHT)
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	smash = SMASH.instantiate()
	smash.input_enabled = false
	smash.debug_overlay = false
	_vp.add_child(smash)
	_build_prop()
	_build_solid()
	_build_overlay()

func is_open() -> bool:
	return _open

func label_for(p: Node) -> String:
	if p == null or p.get("frozen") or p.get("on_tramp") or float(p.get("dz") if p.get("dz") != null else 0.0) > 2.0:
		return ""
	if Arcade.is_open():
		return ""
	var hp: Vector3 = GameData.from_3d(p.global_position)
	if absf(hp.x - X) < 30.0 and hp.y > cab_y - 4.0 and hp.y < cab_y + 46.0:
		return "PLAY"
	return ""

func act(_p: Node) -> void:
	open()

func open() -> void:
	if _open:
		return
	_open = true
	_opened_at = Time.get_ticks_msec()
	if arcade:
		arcade.hold_player(true)
	_wake(true)
	_fit_window()
	_layer.visible = true
	smash.input_enabled = true
	smash.start_attract(false)

func close() -> void:
	if not _open:
		return
	_open = false
	smash.input_enabled = false
	smash.start_attract(false)
	_layer.visible = false
	_vp.size = SCREEN_SIZE
	_vp.size_2d_override = Vector2i(UI_HEIGHT * SCREEN_SIZE.x / SCREEN_SIZE.y, UI_HEIGHT)
	if arcade:
		arcade.hold_player(false)

func _process(_delta: float) -> void:
	if _open:
		_fit_window()
		return
	var p = arcade.player() if arcade else null
	_wake(p != null and ground_distance(p) < AWAKE)

## The demo only runs (and its viewport only renders) while someone's near enough to see it.
func _wake(on: bool) -> void:
	if on == _awake:
		return
	_awake = on
	smash.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

## Full screen at the window's real pixels, the HUD scaled from a 720-high layout.
func _fit_window() -> void:
	var px := DisplayServer.window_get_size()
	if px.x < 64 or px.y < 64:
		px = Vector2i(get_viewport().get_visible_rect().size)
	if _vp.size != px:
		_vp.size = px
		_vp.size_2d_override = Vector2i(UI_HEIGHT * px.x / px.y, UI_HEIGHT)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	# the E that opened it isn't the E that walks away; E is a letter while typing initials
	var typing: bool = smash.state == smash.State.NAME and event is InputEventKey and event.physical_keycode == KEY_E
	if event.is_action_pressed("arcade_close") and not typing and Time.get_ticks_msec() - _opened_at > 300:
		close()
		return
	var ev = event
	if event is InputEventMouse:
		ev = event.duplicate()
		var k := Vector2(_vp.size) / get_viewport().get_visible_rect().size
		ev.position = event.position * k
		ev.global_position = event.global_position * k
	_vp.push_input(ev, true)

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 60
	_layer.visible = false
	add_child(_layer)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(back)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_view)
	var hint := Label.new()
	hint.text = "ESC: WALK AWAY"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position -= Vector2(12, 8)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(hint)

## The cabinet's picture standing at its feet like the World's props, its live screen, and its night glow.
func _build_prop() -> void:
	var img := _picture()
	img.generate_mipmaps()
	var U := GameData.UNIT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-W / 2 * U, 0, 0), Vector3(W / 2 * U, 0, 0), Vector3(W / 2 * U, H * U, 0), Vector3(-W / 2 * U, H * U, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])
	_prop = MeshInstance3D.new()
	_prop.name = "Prop_cab_smash"
	_prop.mesh = st.commit()
	var sh := Shader.new()
	sh.code = WorldBuilder.PROP_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	_prop.material_override = sm
	_prop.extra_cull_margin = (W + H) * U
	_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.set_meta("rect", [X - W / 2, cab_y - H, X + W / 2, cab_y])
	add_child(_prop)
	_prop.global_position = GameData.world_to_3d(X, cab_y, 0.2)

	# the live screen: 36 x 30 units, 18 either side of the middle, 52 to 82 up (as ArcadeCabinet.add_screen)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sv := [Vector3(-18 * U, 52 * U, 0), Vector3(18 * U, 52 * U, 0), Vector3(18 * U, 82 * U, 0), Vector3(-18 * U, 82 * U, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st2.set_uv(uv[i])
		st2.add_vertex(sv[i])
	var screen := MeshInstance3D.new()
	screen.name = "ArcadeScreen"
	screen.mesh = st2.commit()
	# the prop shader too (same lean, same upright depth as the picture), a little nearer the camera than the
	# picture so it's always on its face, still behind anyone standing in front of the cabinet
	var ssm := ShaderMaterial.new()
	ssm.shader = sh
	ssm.set_shader_parameter("tex", _vp.get_texture())
	ssm.set_shader_parameter("depth_bias", 0.05)
	ssm.render_priority = 1
	screen.material_override = ssm
	screen.extra_cull_margin = 4.0
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.add_child(screen)

	# lit like the other cabinets, with the same glowing screen and marquee (same layout as theirs)
	var look := _find_look(arcade.main if arcade else null)
	if look:
		look._light_prop(_prop)
		var lit: ShaderMaterial = _prop.material_override
		var r: Array = LookPass.GLOW_RECTS["cab_bricks"]
		lit.set_shader_parameter("glow_a", r[0])
		lit.set_shader_parameter("glow_b", r[1])

func _find_look(n: Node) -> Node:
	if n == null:
		return null
	if n is LookPass:
		return n
	for c in n.get_children():
		var f := _find_look(c)
		if f:
			return f
	return null

## A solid like the World's for the other cabinets (their cabBoxes, inset for the player's size).
func _build_solid() -> void:
	var U := GameData.UNIT
	var body := StaticBody3D.new()
	body.name = "Solid_cab_smash"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3((W - 18.0) * U, H * U, 1.0 * U)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = GameData.world_to_3d(X, cab_y - 7.0, H / 2.0)

## The cabinet picture, 112 x 208 pixels (2 a unit), laid out like the HTML game's drawCabinet.
func _picture() -> Image:
	var img := Image.create(112, 208, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var box := func(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), c)
	# marquee
	box.call(0, 0, 112, 32, OUTLINE)
	box.call(4, 4, 108, 28, MARQUEE)
	_text(img, "SMASH", 27, 9, TITLE)
	# body with neon trim down both sides
	box.call(0, 32, 112, 208, OUTLINE)
	box.call(2, 32, 6, 206, TRIM)
	box.call(106, 32, 110, 206, TRIM)
	box.call(10, 32, 102, 206, BODY)
	# screen bezel (the live screen sits on the inside, 20..92 x 44..104)
	box.call(14, 38, 98, 110, OUTLINE)
	box.call(20, 44, 92, 104, Color("#0b0b18"))
	# control panel: stick ball and two buttons
	box.call(2, 116, 110, 140, Color("#26262e"))
	for y in range(120, 133):
		for x in range(24, 37):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(30, 126)) < 6.0:
				img.set_pixel(x, y, Color("#e04040"))
	box.call(62, 124, 70, 132, Color("#f2c94c"))
	box.call(78, 124, 86, 132, Color("#8ad4ff"))
	# coin door with two slots
	box.call(38, 152, 74, 188, Color("#141418"))
	box.call(46, 160, 48, 172, TRIM)
	box.call(64, 160, 66, 172, TRIM)
	return img

const _FONT := {
	"S": [".###.", "#...#", "#....", ".###.", "....#", "#...#", ".###."],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
}

## A 5 x 7 pixel font at 2x (the default font can't be drawn into an Image).
func _text(img: Image, s: String, x: int, y: int, c: Color) -> void:
	for ch in s:
		var g: Array = _FONT.get(ch, [])
		for row in g.size():
			for col in 5:
				if g[row][col] == "#":
					img.fill_rect(Rect2i(x + col * 2, y + row * 2, 2, 2), c)
		x += 12
