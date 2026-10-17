class_name Arcade
extends Node
## The arcade (milestone 5, the arcade cabinets). One entry point: Arcade.install(main) adds it to the running
## game: the two cabinets on the lounge's top wall (CABINETS in game_data.json: Sand Miner, and Bricks, which is
## the Mega Drive / SNES cabinet too) as Interactables (E or the round button: PLAY, in both views), the
## full-screen overlay their games run in (ArcadeOverlay), and the live little screens on the cabinets.
## The broken cabinet (the slot machine with its OUT OF ORDER sign) is not ours and stays as it is.
##
## Smashed.html: "the arcade row" (CABINETS, arcadeNear, drawArcade, ARCADE_GAMES) and "MEGA DRIVE" (MD).
##
## Others can ask:
##   Arcade.is_open()      something of ours has the screen (a game, the Mega Drive menu or the emulator)
##   Arcade.close_all()    shut it (a run starting closes it, like the HTML game's drawArcade / mdClose)
##   Arcade.instance()     the Arcade node (its overlay, md bridge and the friend hooks below)

const GAMES := {"snake": preload("res://scripts/arcade/snake.gd"), "bricks": preload("res://scripts/arcade/bricks.gd"),
	"miner": preload("res://scripts/arcade/sand_miner.gd")}

static var _inst: Arcade = null

var main: Node
var overlay: ArcadeOverlay
var md: ArcadeMd
var sfx: ArcadeSfx
var cabinets: Array[ArcadeCabinet] = []
## High scores by game id (the HTML game's ARC.hi; kept in localStorage "smashedArcadeHi" on the web, so the
## HTML game's and this one's are the same list on the same site; user://arcade_hi.json elsewhere).
var hi: Dictionary = {}

## Add the arcade to the running game (main.gd calls this once, after its _ready).
static func install(m: Node) -> Arcade:
	if _inst and is_instance_valid(_inst):
		return _inst
	var a := Arcade.new()
	a.name = "Arcade"
	a.main = m
	m.add_child(a)
	return a

static func instance() -> Arcade:
	return _inst if _inst and is_instance_valid(_inst) else null

static func is_open() -> bool:
	var a := instance()
	return a != null and (a.overlay.is_open() or a.md.is_open())

static func close_all() -> void:
	var a := instance()
	if a:
		a.md.close()
		a.overlay.close()

## A fresh game by id ("snake", "bricks", "miner").
static func make_game(id: String) -> ArcadeGame:
	var s = GAMES.get(id)
	return s.new() if s else null

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## The arcade's input actions, added if missing (keyboard, pad; touch is the overlay's own buttons and swipes).
## Each game reads them through the overlay's stick: move, fire (start / launch the ball / jump), Sand Miner's
## dig, launch, ammo and upgrade, and close (walk away).
const ACTIONS := {
	"arcade_left": {"keys": [KEY_A, KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT], "axes": [[JOY_AXIS_LEFT_X, -1.0]]},
	"arcade_right": {"keys": [KEY_D, KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT], "axes": [[JOY_AXIS_LEFT_X, 1.0]]},
	"arcade_up": {"keys": [KEY_W, KEY_UP], "buttons": [JOY_BUTTON_DPAD_UP], "axes": [[JOY_AXIS_LEFT_Y, -1.0]]},
	"arcade_down": {"keys": [KEY_S, KEY_DOWN], "buttons": [JOY_BUTTON_DPAD_DOWN], "axes": [[JOY_AXIS_LEFT_Y, 1.0]]},
	"arcade_fire": {"keys": [KEY_SPACE, KEY_ENTER], "buttons": [JOY_BUTTON_A]},
	"arcade_launch": {"keys": [KEY_F], "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]},
	"arcade_dig": {"axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
	"arcade_ammo": {"keys": [KEY_Q], "buttons": [JOY_BUTTON_X]},
	"arcade_upgrade": {"keys": [KEY_U], "buttons": [JOY_BUTTON_Y]},
	"arcade_close": {"keys": [KEY_ESCAPE, KEY_E], "buttons": [JOY_BUTTON_B, JOY_BUTTON_BACK]},
}

static func add_actions() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.3)                    # the HTML game's stick dead zone (arcadeStick: 0.3)
		var d: Dictionary = ACTIONS[a]
		for k in d.get("keys", []):
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for bt in d.get("buttons", []):
			var e := InputEventJoypadButton.new()
			e.button_index = bt
			InputMap.action_add_event(a, e)
		for ax in d.get("axes", []):
			var e := InputEventJoypadMotion.new()
			e.axis = ax[0]
			e.axis_value = ax[1]
			InputMap.action_add_event(a, e)

func _ready() -> void:
	add_actions()
	load_hi()
	sfx = ArcadeSfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	overlay = ArcadeOverlay.new()
	overlay.name = "Overlay"
	overlay.arcade = self
	add_child(overlay)
	md = ArcadeMd.new()
	md.name = "MegaDrive"
	md.arcade = self
	add_child(md)
	var d: Dictionary = GameData.data
	var cy := float(d.get("calls", {}).get("cabY", 116.0))
	var world = main.get("world") if main else null
	for c in d.get("CABINETS", []):
		var cab := ArcadeCabinet.new()
		cab.cab = c
		cab.cab_y = cy
		cab.arcade = self
		cab.name = "Cabinet_" + String(c.game)
		add_child(cab)
		cab.global_position = GameData.world_to_3d(float(c.x), cy + 20.0)
		cabinets.append(cab)
		if world and world.get("props") is Dictionary:
			var prop = world.props.get("cab_" + String(c.game))
			if prop:
				cab.add_screen(prop)

## The player who's playing (the main game's), or the first in group "player".
func player() -> Node:
	var p = main.get("player") if main else null
	if p:
		return p
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if ps.size() > 0 else null

## E at a cabinet.
func use_cabinet(cab: ArcadeCabinet) -> void:
	if is_open():
		return
	if cab.cab.game == "bricks":
		md.open(cab.cab)                           # b303: the Mega Drive menu (Bricks is in it)
	else:
		overlay.open(cab.cab, String(cab.cab.game))

# ---------------------------------------------------------------- holding the player still while we're open

var _held := false
var _was_captured := false

## While something of ours has the screen: he stands still, the view keys and the HUD's keys are off, the
## pointer is let go. Called by the overlay and the Mega Drive menu.
func hold_player(on: bool) -> void:
	if on == _held:
		return
	_held = on
	var p = player()
	var rig = main.get("rig") if main else null
	var hud = main.get("hud") if main else null
	if on:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if _was_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if p:
			p.controls_enabled = false
			if p.has_method("halt"):
				p.halt()
			p.set_process_unhandled_input(false)
		if rig:
			rig.set_process_unhandled_input(false)
			rig.set("capture_mouse", false)
		if hud:
			hud.set_process_unhandled_input(false)
			hud.visible = false
	else:
		if p:
			p.controls_enabled = true
			p.set_process_unhandled_input(true)
		if rig:
			rig.set_process_unhandled_input(true)
			rig.set("capture_mouse", true)
			if _was_captured and rig.get("mode") == 1:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if hud:
			hud.set_process_unhandled_input(true)
			hud.visible = true
	if main:
		main.set_meta("arcade_open", on)

# ---------------------------------------------------------------- high scores

func load_hi() -> void:
	hi = {}
	var txt := ""
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('smashedArcadeHi')||'{}'}catch(e){return '{}'}})()", true)
		txt = v if v is String else "{}"
	elif FileAccess.file_exists("user://arcade_hi.json"):
		var f := FileAccess.open("user://arcade_hi.json", FileAccess.READ)
		txt = f.get_as_text() if f else "{}"
	var d = JSON.parse_string(txt) if txt.strip_edges().begins_with("{") else {}
	if d is Dictionary:
		for k in d:
			hi[k] = int(d[k])

## Keep this score if it beats the best (arcadeSaveHi).
func save_hi(game_id: String, score: int) -> void:
	if score <= int(hi.get(game_id, 0)):
		return
	hi[game_id] = score
	var txt := JSON.stringify(hi)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('smashedArcadeHi'," + JSON.stringify(txt) + ")}catch(e){}", true)
	else:
		var f := FileAccess.open("user://arcade_hi.json", FileAccess.WRITE)
		if f:
			f.store_string(txt)
