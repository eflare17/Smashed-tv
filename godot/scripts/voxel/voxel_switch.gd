class_name VoxelSwitch
extends Node
## The setting "Characters: pixel / blocks": in blocks, every CharSprite whose character has a voxel model (player 1,
## player 2 on the same keyboard or online, Gothica, the mirror's reflection...) gets a VoxelChar that stands in for
## its picture. F10 (or the HUD's "Chars" button) switches; kept in user://smashed.cfg ([chars] look). Default pixel.
## The web build's address can say ?voxel=blocks or ?voxel=pixel (also --voxel=blocks after -- on the command line).
## Owned by the voxel session. Entry point: VoxelSwitch.install(main).

const CFG := "user://smashed.cfg"
const MODES := ["pixel", "blocks"]

static var me: VoxelSwitch
## "pixel" or "blocks".
static var mode: String = "pixel"
static var _loaded := false

var main: Node
var _btn: Button
var _scan_t := 0.0

static func install(main_: Node) -> VoxelSwitch:
	var s := VoxelSwitch.new()
	s.name = "VoxelSwitch"
	s.main = main_
	main_.add_child(s)
	return s

static func load_mode() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		var m := String(cf.get_value("chars", "look", "pixel"))
		if m in MODES:
			mode = m
	var want := _asked()
	if want != "":
		mode = want

# ?voxel=blocks on the web, --voxel=blocks on the command line
static func _asked() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--voxel="):
			var v := a.substr(8)
			return v if v in MODES else ""
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			for m in MODES:
				if q.find("voxel=" + m) >= 0:
					return m
	return ""

static func save_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("chars", "look", mode)
	cf.save(CFG)

func _ready() -> void:
	me = self
	load_mode()
	process_priority = 800
	if not InputMap.has_action("voxel_toggle"):
		InputMap.add_action("voxel_toggle")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F10
		InputMap.action_add_event("voxel_toggle", k)
	_add_button()
	_scan()

func _add_button() -> void:
	var hud = main.get("hud") if main else null
	var row = hud.get("_picker") if hud else null
	if not (row is Container):
		return
	_btn = Button.new()
	_btn.name = "VoxelButton"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 13)
	_btn.tooltip_text = "Characters: pixel art or blocks (F10)"
	_btn.pressed.connect(toggle)
	row.add_child(_btn)
	_label()

func _label() -> void:
	if _btn:
		_btn.text = "Chars: " + mode

func set_mode(m: String, save := true) -> void:
	if not (m in MODES):
		return
	mode = m
	if save:
		save_mode()
	_label()
	_scan()
	print("VoxelSwitch: characters ", mode)

func toggle() -> void:
	set_mode("pixel" if mode == "blocks" else "blocks")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("voxel_toggle") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= 0.25:
		_scan_t = 0.0
		_scan()

## Adds a VoxelChar to every CharSprite that can have one (blocks), or takes them all away (pixel).
func _scan() -> void:
	if not is_inside_tree():
		return
	var on := mode == "blocks"
	for n in get_tree().root.find_children("*", "CharSprite", true, false):
		var cs := n as CharSprite
		var vc := cs.get_node_or_null("Blocks") as VoxelChar
		if on:
			if vc == null and VoxelModel.model_for_sheet(cs.char_id) != "":
				vc = VoxelChar.new()
				vc.name = "Blocks"
				vc.source = cs
				# the mirror's reflection: pressed flat against the glass
				vc.flatten = cs.top_level and cs.get_parent() is LobbyMirror
				cs.add_child(vc)
		elif vc != null:
			vc.queue_free()
			cs.remove_child(vc)
			var pic = cs.get("_spr")
			if pic is Node3D:
				pic.visible = true
