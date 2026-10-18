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
var _pending := false

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
	get_tree().node_added.connect(_on_node_added)
	_scan()

# a CharSprite made later (player 2, the mirror's reflection...) gets its blocks a frame later
func _on_node_added(n: Node) -> void:
	if n is CharSprite and mode == "blocks":
		_pending = true

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
	# a full look round now and then (a sheet changing to one that has a model), and whenever a CharSprite appears
	_scan_t += delta
	if _pending or _scan_t >= 3.0:
		_pending = false
		_scan_t = 0.0
		_scan()
	if mode == "blocks":
		_lobby_poses()

## Lobby life's poses the blocks do themselves: lying in bed, sitting at the table, swimming. For those the lobby's
## own picture is hidden and the sprite (whose picture the blocks hide) shown, posed. (The gym's lifts and carrying
## Gothica stay the lobby's pictures: they draw the machine, or her, in the same picture.)
func _lobby_poses() -> void:
	var ll := LobbyLife.current
	for pl in get_tree().get_nodes_in_group("player"):
		if not (pl is Player) or pl.sprite == null:
			continue
		var vc := pl.sprite.get_node_or_null("Blocks") as VoxelChar
		if vc == null:
			continue
		var pose := pose_for(ll, pl)
		vc.lobby_pose = pose
		vc.facing_override = Vector2.ZERO
		if pose == "":
			continue
		var pic = ll.pose_of(pl) if ll else null
		if pic and is_instance_valid(pic):
			pic.visible = false
		pl.sprite.visible = not pl.is_first_person()
		if pose == "lie":
			vc.facing_override = Vector2(0, 1)

## Which of the blocks' lobby poses a player is in ("" for none).
static func pose_for(ll: LobbyLife, pl: Player) -> String:
	if ll == null or not ll.busy.has(pl):
		return ""
	var th = ll.busy[pl]
	if th is LobbyBed:
		return "lie"
	if th is LobbyTable and (th as LobbyTable).sitters.has(pl):
		return "sit"
	if th is LobbyPool and (th as LobbyPool).swimming(pl):
		return "swim"
	return ""

## Adds a VoxelChar to every CharSprite that can have one (blocks), or takes them all away (pixel).
func _scan() -> void:
	if not is_inside_tree():
		return
	var on := mode == "blocks"
	for n in get_tree().root.find_children("*", "CharSprite", true, false):
		var cs := n as CharSprite
		if cs.has_meta("no_blocks"):
			continue
		var vc := cs.get_node_or_null("Blocks") as VoxelChar
		if on:
			if vc == null:          # (every sprite: a VoxelChar with no model for its sheet just leaves the picture)
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
