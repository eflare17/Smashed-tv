class_name LobbyWardrobe
extends LobbyThing
## The wardrobe (Smashed.html: WARD @1947, wardNear, toggleWard, drawWardrobe @1954) and the shirt picture (the ART
## button, pickShirtArt, the shirt editor). Owned by the Lobby life session.
##
## It stands at WARD (180, 620) in the bedroom. E next to it ("OPEN" / "CLOSE", x 140..220, y 618..658): the doors
## swing (a creak and a clunk, 0.2 s) and a menu offers ART (pick a picture for the front of the singlet and place it
## on the shirt with the editor; a picture already there opens the editor, with a button to take it off), CHANGE
## CLOTHES (the other characters, which the HTML wardrobe can't do: the owner asked for it) and CLOSE. Q opens
## the menu again while it's open. The doors' art is the HTML game's three wardrobe pictures.

const WARD := Vector2(180.0, 620.0)

var open: bool = false
var k: float = 0.0
var editor: LobbyShirtEditor
var _pic: LobbyPic
var _frame: int = -1

func _ready() -> void:
	reach = 90.0
	global_position = GameData.world_to_3d(WARD.x, WARD.y + 20.0, 0.0)
	await get_tree().process_frame
	_pic = LobbyPic.make(LobbyPic.art("bedroom/wardrobe_0_shut.png"), 0.5)
	_pic.top_level = true
	add_child(_pic)
	_pic.global_position = GameData.world_to_3d(WARD.x, WARD.y, 0.0)
	var w = ll.world if ll else null
	if w and w.get("props") is Dictionary:
		var m = w.props.get("wardrobe")
		if m is Node3D:
			m.visible = false
	editor = LobbyShirtEditor.new()
	editor.name = "ShirtEditor"
	ll.ui.root.add_child(editor)

## wardNear.
func near(p: Node) -> bool:
	var o := ppos(p)
	return absf(o.x - WARD.x) < 40.0 and o.y > WARD.y - 2.0 and o.y < WARD.y + 38.0

func label_for(p: Node) -> String:
	if can_start(p) and near(p) and not editor_open():
		return "CLOSE" if open else "OPEN"
	return ""

func act(p: Node) -> void:
	if can_start(p) and near(p) and not editor_open():
		toggle()

func editor_open() -> bool:
	return editor != null and editor.is_open()

## toggleWard: the doors, the sounds, and (opening) the menu.
func toggle() -> void:
	open = not open
	if ll and ll.sfx:
		if open:
			ll.sfx.tone(180, 0.35, "saw", 0.08, 320)
		else:
			ll.sfx.tone(240, 0.35, "saw", 0.08, 150)
		ll.sfx.noise(0.12, 0.12, 0.3)
	if open:
		show_menu()
	else:
		ll.ui.close_menu()

func show_menu() -> void:
	var opts: Array = []
	if LobbyLook.art_front == null:
		opts.append(["ART: PICK A PICTURE", func(): pick()])
	else:
		opts.append(["ART: PLACE ON SHIRT", func(): ll.ui.close_menu(); editor.open()])
		opts.append(["ART: PICK ANOTHER", func(): pick()])
		opts.append(["ART: TAKE IT OFF", func(): LobbyLook.clear_art(); ll.ui.close_menu(); ll.ui.info("picture off")])
	opts.append(["CHANGE CLOTHES", func(): clothes()])
	opts.append(["CLOSE", func(): if open: toggle()])
	ll.ui.menu("WARDROBE", opts, func(): ll.ui.close_menu())

func pick() -> void:
	ll.ui.close_menu()
	LobbyLook.pick_picture(ll.ui.root, func(im: Image) -> void:
		editor.take_picture(im))

## Change clothes: another character (the Hud's 1 2 3 do the same).
func clothes() -> void:
	var p := ll.player
	var names := {"juicy": "JUICY JARED", "tyson2": "TORNADO TYSON", "goth": "GOTHICA"}
	var opts: Array = []
	for id in CharFrames.PLAYABLE:
		var c: String = id
		opts.append([String(names.get(c, c.to_upper())) + ("  ✓" if p.char_id == c else ""), func():
			p.char_id = c
			ll.ui.close_menu()
			ll.ui.info(String(names.get(c, c)))
			if ll.sfx:
				ll.sfx.play("pop")])
	opts.append(["BACK", func(): show_menu()])
	ll.ui.menu("CHANGE CLOTHES", opts, func(): show_menu())

func _unhandled_input(event: InputEvent) -> void:
	if open and ll and ll.player and near(ll.player) and not ll.ui.menu_open() and not editor_open() and event.is_action_pressed("lobby_alt"):
		show_menu()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	k = clampf(k + (dt if open else -dt) * 5.0, 0.0, 1.0)
	var f := 0 if k <= 0.0 else (1 if k < 1.0 else 2)
	if f != _frame and _pic:
		_frame = f
		_pic.texture = LobbyPic.art(["bedroom/wardrobe_0_shut.png", "bedroom/wardrobe_1_one_door.png", "bedroom/wardrobe_2_both_open.png"][f])
	# walked away with it open and the menu showing: the menu goes (the doors stay as they are)
	if open and ll.ui.menu_open() and ll.player and ppos(ll.player).distance_to(WARD) > 140.0:
		ll.ui.close_menu()

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(180.0, 645.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	tl.later(0.8, func(): tl.use())
	if parts.has("art"):
		tl.later(1.6, func():
			ll.ui.close_menu()
			var im := Image.create(120, 80, false, Image.FORMAT_RGBA8)
			for y in 80:
				for x in 120:
					im.set_pixel(x, y, Color.from_hsv(float(x) / 120.0, 0.8, 0.4 + 0.6 * float(y) / 80.0))
			editor.take_picture(im))
