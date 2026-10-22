extends Control
## Smash arcade: the TV host. A voxel game-show host (head and shoulders, waving a dollar bill) who drops down from
## the top right of the screen (beside the arena on a wide screen), says a line in a speech bubble while his mouth
## flaps to his babble, and goes back up.
## He's rendered by his own small SubViewport (own 3D world, transparent background) shown as a texture, and that
## viewport only renders while he's on screen. The scene root decides when he talks; important lines (`priority`)
## cut in, the rest wait out a cooldown so he doesn't nag.

const SmashVox := preload("smash_vox.gd")

const SIZE := 192
const SHOW := 224.0
const DROP := 0.25
const COOLDOWN := 7.0

var sfx

var _vp: SubViewport
var _model: MeshInstance3D
var _frames: Array[Mesh] = []
var _pic: TextureRect
var _bubble: PanelContainer
var _text: Label
var _phase := 0
var _t := 0.0
var _talk := 0.0
var _cool := 0.0

func _init() -> void:
	name = "SmashHost"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var mat := SmashVox.flat_material()
	for f in 2:
		var m := SmashVox.host_mesh(f)
		m.surface_set_material(0, mat)
		_frames.append(m)
	_model = MeshInstance3D.new()
	_model.mesh = _frames[0]
	_model.rotation.y = -0.25
	_vp.add_child(_model)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.75
	cam.position = Vector3(0, 0.78, 3)
	_vp.add_child(cam)

	_pic = TextureRect.new()
	_pic.texture = _vp.get_texture()
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.size = Vector2(SHOW, SHOW)
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.visible = false
	add_child(_pic)

	_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = Color.BLACK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	_text = Label.new()
	var ls := LabelSettings.new()
	ls.font_size = 30
	ls.font_color = Color.BLACK
	_text.label_settings = ls
	_bubble.add_child(_text)
	add_child(_bubble)

func busy() -> bool:
	return _phase != 0

## Has him say `text`. Without `priority` he stays quiet if he's talking or spoke within the cooldown.
## Returns false if he didn't.
func say(text: String, priority := false) -> bool:
	if not priority and (_phase != 0 or _cool > 0.0):
		return false
	var secs: float = sfx.say(text) if sfx else 1.5
	_text.text = text
	_talk = maxf(1.6, secs + 0.4)
	_cool = COOLDOWN
	if _phase == 0 or _phase == 3:
		_phase = 1
		_t = 0.0
	else:
		_phase = 2
		_t = 0.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pic.visible = true
	return true

func hide_now() -> void:
	_phase = 0
	_pic.visible = false
	_bubble.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if sfx:
		sfx.stop_voice()

func _process(delta: float) -> void:
	_cool -= delta
	if _phase == 0:
		return
	_t += delta
	var drop := 0.0
	match _phase:
		1:
			drop = minf(1.0, _t / DROP)
			if _t >= DROP:
				_phase = 2
				_t = 0.0
		2:
			drop = 1.0
			if _t >= _talk:
				_phase = 3
				_t = 0.0
		3:
			drop = 1.0 - minf(1.0, _t / DROP)
			if _t >= DROP:
				hide_now()
				return
	var x := size.x - SHOW - 16.0
	_pic.position = Vector2(x, lerpf(-SHOW, 64.0, drop))
	var talking := _phase == 2 and _t < _talk - 0.4
	_model.mesh = _frames[int(_t * 9.0) % 2 if talking else 0]
	_model.position.y = absf(sin(_t * 9.0)) * 0.03 if talking else 0.0
	_bubble.visible = _phase == 2
	_bubble.position = Vector2(x - _bubble.size.x + 24.0, 84.0)
