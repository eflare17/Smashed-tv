class_name LightingInstall
extends Node
## The Lighting session's one entry point (1.4 day and night, 1.5 the look): LightingInstall.install(main) adds
## it all to the running game. What it adds:
## - the GameClock at /root/GameClock (unless the autoload is there already), its day and time loaded from the
##   save (user://gameclock.json) and saved every few seconds and after every skip;
## - DayNight: the sun and moon, the sky, the ambient light, the haze's colour and the lamps, by the clock;
## - LookPass: the lit materials, the characters' light and shadows, the glows, the far blur, the quality;
## - ClockHud: the clock at the top right and the sleep fade;
## - a BedSleep on the bed (until the Lobby session's bed with its sleep_requested signal turns up).
## This node ("Lighting", a child of main) holds them all and does the saving and the keys.
##
## Keys (input actions it adds): F8 look_quality (high / low), F6 clock_skip (an hour on).
## The web build's address: ?look=low or ?look=high picks the quality; ?hour=19.5 (and &day=3) sets the clock.

const ClockScript := preload("res://scripts/clock/game_clock.gd")
const SAVE_PATH := "user://gameclock.json"
const SAVE_EVERY := 10.0
const LAMP := Color(1.0, 0.78, 0.52)

var main: Node
var clock: Node
var day_night: DayNight
var look: LookPass
var clock_hud: ClockHud
var bed: BedSleep

var _save_t := 0.0

## Adds everything to main (the running game: main.world, main.sun, main.player, main.rig, main.hud...).
static func install(main_: Node) -> LightingInstall:
	var li := LightingInstall.new()
	li.name = "Lighting"
	li.main = main_
	li._setup()
	return li

func _setup() -> void:
	_add_actions()
	clock = _ensure_clock(main.get_tree())
	var args := _page_args()
	var loaded := false
	if args.has("hour"):
		clock.hour = clampf(float(args.hour), 0.0, 23.99)
		clock.day = maxi(1, int(args.get("day", clock.day)))
		loaded = true
	elif FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var v = JSON.parse_string(f.get_as_text()) if f else null
		if v is Dictionary:
			# straight in, no signals: nothing has been counting yet, so nothing should count a skip
			clock.day = maxi(1, int(v.get("day", 1)))
			clock.hour = clampf(float(v.get("hour", 7.0)), 0.0, 23.9999)
			loaded = true
	if args.has("speed"):
		clock.speed = float(args.speed)
	main.add_child(self)

	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	var world: Node = main.get("world")
	day_night.setup(main.get("sun"), world.get("environment") if world else null)
	_add_lamps()

	look = LookPass.new()
	look.name = "LookPass"
	var q := "low" if _is_phone() else "high"
	if args.has("look"):
		q = "low" if String(args.look) == "low" else "high"
		look.auto_quality = false
	look.quality = q
	add_child(look)
	look.setup(main, day_night)

	clock_hud = ClockHud.new()
	clock_hud.name = "ClockHud"
	add_child(clock_hud)

	bed = BedSleep.new()
	bed.name = "BedSleep"
	var B: Dictionary = GameData.data.get("BED", {"x0": 314, "x1": 446, "y0": 520, "y1": 676})
	bed.position = GameData.world_to_3d((B.x0 + B.x1) / 2.0, (B.y0 + B.y1) / 2.0, 0)
	bed.reach = maxf(B.x1 - B.x0, B.y1 - B.y0) / 2.0 + 28.0
	bed.hud = clock_hud
	bed.slept.connect(func(_d): save())
	add_child(bed)

	clock.time_skipped.connect(func(_h): save())
	clock.day_started.connect(func(_d): save())
	main.get_tree().node_added.connect(_on_node_added)
	for n in main.get_tree().get_nodes_in_group("interactable"):
		_on_node_added(n)
	print("Lighting: installed (look %s, day %d %s%s)" % [q, clock.day, clock.time_text(), ", from the save" if loaded else ""])

## The GameClock at /root/GameClock: the autoload if there is one, else a new one added there.
static func _ensure_clock(tree: SceneTree) -> Node:
	var c := tree.root.get_node_or_null("GameClock")
	if c:
		return c
	c = ClockScript.new()
	c.name = "GameClock"
	tree.root.add_child.call_deferred(c)
	return c

## The lamps (HTML units): the lounge's ceiling lights, the pool's light, the bedroom's ceiling light and the
## nightstand's lamp, and the porch light over the back door. low: kept on phones (the low look has fewer
## lights, each reaching further).
func _add_lamps() -> void:
	var L := [
		# x, y, z, colour, energy, reach, bulb, which ("both", "high", "low")
		[200, 150, 138, LAMP, 3.2, 330, true, "high"],
		[200, 390, 138, LAMP, 3.2, 330, true, "high"],
		[470, 300, 138, LAMP, 3.2, 340, true, "high"],
		[740, 380, 138, LAMP, 2.8, 300, true, "high"],
		[720, 165, 30, Color(0.35, 0.85, 1.0), 1.6, 220, false, "high"],
		[430, 260, 140, LAMP, 4.0, 470, true, "low"],
		[240, 700, 138, LAMP, 2.2, 330, true, "both"],
		[295, 532, 42, Color(1.0, 0.7, 0.42), 1.0, 150, false, "high"],
		[645, 585, 112, Color(1.0, 0.82, 0.6), 2.6, 280, true, "both"],
	]
	for l in L:
		day_night.add_lamp(l[0], l[1], l[2], l[3], l[4], l[5], l[6])
		var e: Dictionary = day_night.lamps.back()
		e["which"] = l[7]

func _on_node_added(n: Node) -> void:
	# the Lobby session's bed: use its sleep_requested, retire the stand-in
	if n == bed or not n.has_signal("sleep_requested"):
		return
	var argc := 0
	for s in n.get_signal_list():
		if s.name == "sleep_requested":
			argc = s.args.size()
	n.connect("sleep_requested", (func(): bed.sleep(main.get("player"))).unbind(argc))
	bed.reach = 0.0
	bed.remove_from_group("interactable")
	print("Lighting: the bed's sleep_requested hooked up")

func _process(dt: float) -> void:
	_save_t += dt
	if _save_t >= SAVE_EVERY:
		_save_t = 0.0
		save()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("clock_skip") and not event.is_echo():
		clock.advance_hours(1.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save()

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(clock.save_state()))

static func _add_actions() -> void:
	var add := func(action: String, key: Key):
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
	add.call("look_quality", KEY_F8)
	add.call("clock_skip", KEY_F6)

## Phones and tablets get the low look.
static func _is_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

## The page's ?a=b&c=d (web), or the command line's user args --a=b.
static func _page_args() -> Dictionary:
	var out := {}
	var parts: PackedStringArray = []
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			parts = q.trim_prefix("?").split("&", false)
	for a in OS.get_cmdline_user_args():
		parts.append(a.trim_prefix("--"))
	for p in parts:
		var kv := p.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out
