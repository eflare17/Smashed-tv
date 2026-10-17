class_name LobbyLife
extends Node3D
## Milestone 3, lobby life: everything you can do in the lobby, the bedroom and the yard besides walking about.
## Owned by the Lobby life session (scripts/lobby_life/, scenes/lobby_life/, test/lobby_life/).
##
## One entry point: LobbyLife.install(main) adds this node to the running game (main.gd calls it once, at the end
## of its _ready). It makes every thing (each a LobbyThing, an Interactable, so E and the on-screen button work in
## both views) and the overlay (LobbyUI: speech bubbles, floating words, the money line, the menus).
##
## Being busy. Many things take the player over (swimming, lifting, sitting, lying in bed...), the way the HTML
## game's p.dive / p.lift / p.leg / p.sit / p.bed do. hold(p, thing) freezes the Player (player.frozen: his own
## step stops) and hands him to the thing: every frame it gets busy_step(p, dt) and moves him itself, E (key, pad,
## the round button) goes to its busy_act(p), and the prompt shows its busy_label(p). release(p) gives him back.
## This node sits between the Player and the Hud in main's children, so it writes the prompt after the Player has
## worked his out and before the Hud draws it.

## Fired when someone lies down in the bed (the day and night clock skips to morning: GameClock hooks on here).
signal sleep_requested(player: Node)
## Fired when someone gets out of the bed.
signal woke(player: Node)

var main: Node
var player: Player
var rig: CameraRig
var hud: Node
var gothica: Node
var world: Node
var ui: LobbyUI
var sfx: LobbySfx

## Every thing, by name ("pool", "bench", ...).
var things: Dictionary = {}
## Who's busy with what: player -> LobbyThing.
var busy: Dictionary = {}

## Money, when the Player has no wallet of its own (coins): player -> amount.
var _cash: Dictionary = {}

static var current: LobbyLife

## The one call main.gd makes.
static func install(main_node: Node) -> LobbyLife:
	var ll := LobbyLife.new()
	ll.name = "LobbyLife"
	ll.main = main_node
	main_node.add_child(ll)
	var h = main_node.get("hud")
	if h is Node and h.get_parent() == main_node:
		main_node.move_child(ll, h.get_index())
	return ll

func _enter_tree() -> void:
	current = self

func _ready() -> void:
	add_input_actions()
	player = _main_get("player")
	rig = _main_get("rig")
	hud = _main_get("hud")
	gothica = _main_get("gothica")
	world = _main_get("world")
	if player == null:
		var ps := get_tree().get_nodes_in_group("player")
		player = ps[0] if ps.size() > 0 else null
	sfx = LobbySfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	ui = LobbyUI.new()
	ui.name = "UI"
	ui.ll = self
	add_child(ui)
	_hook_hud_button()
	_make_things()

func _main_get(k: String):
	if main == null:
		return null
	var v = main.get(k)
	return v if v is Node else null

func _make_things() -> void:
	for pair in [
		["pool", LobbyPool], ["gym", LobbyGym], ["rope", LobbyRope], ["table", LobbyTable],
		["mirror", LobbyMirror], ["wardrobe", LobbyWardrobe], ["bed", LobbyBed], ["shroom", LobbyShroom],
		["slot", LobbySlot], ["vend", LobbyVend], ["bbq", LobbyBbq], ["goth_life", GothLife],
	]:
		var n: Node = pair[1].new()
		n.name = String(pair[0]).capitalize().replace(" ", "")
		if "ll" in n:
			n.ll = self
		add_child(n)
		things[pair[0]] = n

# ------------------------------------------------------------------ input

## The input actions lobby life adds (if the project doesn't have them): keyboard, pad.
## lobby_up / lobby_down: change a choice (hair style, bet), lobby_left / lobby_right: turn (the mirror),
## lobby_back: leave a menu (Esc / Backspace / pad B), lobby_alt: the second thing a place does
## (Q / pad X: "hit" at the cards, cook at the barbecue...).
static func add_input_actions() -> void:
	var keys := {
		"lobby_alt": [KEY_Q], "lobby_back": [KEY_BACKSPACE],
		"lobby_prev": [KEY_BRACKETLEFT, KEY_COMMA], "lobby_next": [KEY_BRACKETRIGHT, KEY_PERIOD],
	}
	var pads := {
		"lobby_alt": [JOY_BUTTON_X], "lobby_back": [JOY_BUTTON_B],
		"lobby_prev": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_LEFT], "lobby_next": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_RIGHT],
	}
	for a in keys:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.3)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for b in pads.get(a, []):
			var j := InputEventJoypadButton.new()
			j.button_index = b
			InputMap.action_add_event(a, j)
	# the movement and E actions are the game's own; make sure they exist for a bare test scene too
	for a in ["move_up", "move_down", "move_left", "move_right", "interact", "roll", "toggle_view"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)

func _hook_hud_button() -> void:
	if hud == null:
		return
	var b = hud.get("_ebtn")
	if b is Object and b.has_signal("pressed"):
		b.pressed.connect(_on_hud_e)

func _on_hud_e() -> void:
	if player and busy.has(player):
		busy_act(player)

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not busy.has(player):
		return
	var th: LobbyThing = busy[player]
	if event.is_action_pressed("interact") and not event.is_echo():
		busy_act(player)
		get_viewport().set_input_as_handled()
		return
	if th.busy_input(player, event):
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ busy

## Is p doing something (anything that holds him, the trampoline included)?
func is_busy(p: Node) -> bool:
	if p == null:
		return true
	if busy.has(p):
		return true
	return bool(p.get("frozen")) or bool(p.get("on_tramp")) or float(p.get("dz") if p.get("dz") != null else 0.0) > 0.5

## Can p start something here (alive, on the floor, not holding anything that stops it)?
func can_start(p: Node) -> bool:
	return p != null and not is_busy(p)

func busy_with(p: Node) -> LobbyThing:
	return busy.get(p, null)

func hold(p: Player, th: LobbyThing) -> void:
	if busy.has(p) and busy[p] != th:
		var old: LobbyThing = busy[p]
		busy.erase(p)
		old.busy_end(p)
	busy[p] = th
	p.halt()
	p.frozen = true
	p.moving = false

func release(p: Player) -> void:
	if not busy.has(p):
		return
	busy.erase(p)
	p.frozen = false
	p.halt()
	if p.sprite:
		p.sprite.visible = not p.is_first_person()
	set_pose(p, null)

func busy_act(p: Player) -> void:
	var th: LobbyThing = busy.get(p, null)
	if th:
		th.busy_act(p)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for p in busy.keys():
		if not is_instance_valid(p):
			busy.erase(p)
			continue
		var th: LobbyThing = busy[p]
		th.busy_step(p, dt)
		if busy.get(p) == th:
			p.focus = th
			p.focus_label = th.busy_label(p)
		_apply_pose(p)
	if player and not busy.has(player):
		_apply_pose(player)

# ------------------------------------------------------------------ poses

## Show a picture of his own instead of his character sprite (lifting, sitting, lying...): a LobbyPic child of the
## player (null: his normal sprite).
var _poses: Dictionary = {}

func set_pose(p: Node3D, pic: LobbyPic) -> void:
	var old: LobbyPic = _poses.get(p, null)
	if old == pic:
		return
	if old and is_instance_valid(old) and old.get_parent() == p:
		old.queue_free()
	if pic == null:
		_poses.erase(p)
		return
	_poses[p] = pic
	if pic.get_parent() == null:
		p.add_child(pic)

func pose_of(p: Node3D) -> LobbyPic:
	return _poses.get(p, null)

func _apply_pose(p: Player) -> void:
	var pic: LobbyPic = _poses.get(p, null)
	if pic and not is_instance_valid(pic):
		_poses.erase(p)
		pic = null
	var fp := p.is_first_person()
	if pic:
		if p.sprite:
			p.sprite.visible = false
		pic.visible = not fp
	elif busy.has(p) and p.sprite:
		p.sprite.facing = p.facing
		p.sprite.moving = p.moving
		p.sprite.odo = p.odo
		p.sprite.visible = not fp and not bool(busy[p].hides_sprite(p))

# ------------------------------------------------------------------ money

## His money (the Player's own coins if it has them, else kept here: the HTML game's lobby cash, testCash 2500).
func cash(p: Node) -> int:
	if p and p.get("coins") != null:
		return int(p.get("coins"))
	if not _cash.has(p):
		_cash[p] = int(maxf(LobbyLife.T("lobbyCash", 40), LobbyLife.T("testCash", 2500)))
	return _cash[p]

func add_cash(p: Node, n: int) -> void:
	if p and p.get("coins") != null:
		p.set("coins", int(p.get("coins")) + n)
	else:
		_cash[p] = cash(p) + n

## Pay n if he has it.
func pay(p: Node, n: int) -> bool:
	if cash(p) < n:
		return false
	add_cash(p, -n)
	return true

# ------------------------------------------------------------------ helpers

## A tuning number from the HTML game's T table.
static func T(k: String, def: float = 0.0) -> float:
	var t = GameData.data.get("T", {})
	return float(t.get(k, def)) if t is Dictionary else def

static func D(k: String, def = null):
	return GameData.data.get(k, def)

static func calls(k: String, def = null):
	var c = GameData.data.get("calls", {})
	return c.get(k, def) if c is Dictionary else def

## Where a node stands, HTML units on the ground.
static func hpos(n: Node3D) -> Vector2:
	var p := GameData.from_3d(n.global_position)
	return Vector2(p.x, p.y)

static func at(x: float, y: float, z: float = 0.0) -> Vector3:
	return GameData.world_to_3d(x, y, z)

## The character's picture name for the lobby things that have their own art (Jared's): juicy and tyson2 share it.
static func is_jared(p: Node) -> bool:
	var c = p.get("char_id")
	return c == "juicy" or c == "tyson2" or c == "jared" or c == "tyson"

## The frame time (s) since the game started, for wobbles.
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0
