extends Node3D
## A test bed for the Trampoline and Gothica (not part of the game). Builds a floor, a stand-in World (in the
## "world_builder" group: ground_boxes() gives the lounge's solids plus a few extra test boxes, each one solid),
## the real Player, the trampoline and Gothica.
##
## Headless (--fixed-fps 60): runs a scripted check and prints "TEST ..." lines: the bounce heights with and
## without the roll held, the net, climbing on and off, the leaps, and Gothica walking for `goth_minutes`
## (checking she never gets inside a box).
## In a window or the web build (interactive = true, or no --headless): a camera on the trampoline; E, Shift,
## WASD as in the game; G jumps the camera between the trampoline and Gothica; V first person.

@export var interactive: bool = false
@export var goth_minutes: float = 10.0
## Use the real World (WorldBuilder, its trampoline left off) instead of the stand-in floor and boxes.
@export var use_world: bool = false

const EXTRA_BOXES := [
	{"x0": 300.0, "y0": 330.0, "x1": 360.0, "y1": 380.0, "h": 40.0, "m": "test"},
	{"x0": 440.0, "y0": 262.0, "x1": 456.0, "y1": 400.0, "h": 60.0, "m": "test"},
	{"x0": 250.0, "y0": 255.0, "x1": 270.0, "y1": 290.0, "h": 30.0, "m": "test"},
	{"x0": 500.0, "y0": 340.0, "x1": 560.0, "y1": 360.0, "h": 30.0, "m": "test"},
]

## A bare stand-in player: just the Player contract's on_tramp, dz and frozen (no vel, no halt()).
class StandIn extends CharacterBody3D:
	var on_tramp := false
	var dz := 0.0
	var frozen := false
	var facing := Vector2(1, 0)
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 14 * 0.025
		cap.height = 66 * 0.025
		cs.shape = cap
		cs.position.y = 34 * 0.025
		add_child(cs)

class StandInWorld extends Node3D:
	var boxes: Array = []
	var tramp_body: StaticBody3D = null
	func _enter_tree() -> void:
		add_to_group("world_builder")
	func ground_boxes() -> Array:
		return boxes.duplicate(true)

var player: Player
var tramp: Trampoline
var goth: Gothica
var world: Node3D
var cam: Camera3D
var rig: CameraRig
var f := 0
var boxes: Array = []

# bounce measuring
var peaks: Array = []
var _last_tv := 0.0
var _peak := 0.0
# gothica checks
var g_inside := 0
var g_min_clear := INF
var g_spots := 0
var g_stucks := 0
var g_dist := 0.0
var g_frames_moving := 0
var g_last: Vector2
var g_was_waiting := false
var g_xmin := INF
var g_xmax := -INF
var g_ymin := INF
var g_ymax := -INF

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		interactive = true
	if use_world:
		var wb := WorldBuilder.new()
		wb.name = "World"
		wb.include_trampoline = false
		add_child(wb)
		wb.build()
		world = wb
		boxes = wb.ground_boxes()
		_add_rest()
		return
	# the floor: the lounge picture and grass, big
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1800 * GameData.UNIT, 1900 * GameData.UNIT)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color8(82, 136, 52)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fl.material_override = fm
	fl.position = GameData.world_to_3d(900, 950, -0.2)
	add_child(fl)
	var lounge := MeshInstance3D.new()
	var lp := PlaneMesh.new()
	var a: Dictionary = GameData.data["ARENA"]
	lp.size = Vector2((a.w - a.wall * 2) * GameData.UNIT, (a.h - a.wall * 2) * GameData.UNIT)
	lounge.mesh = lp
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = GameData.tex(GameData.manifest["LOUNGE_IMG.src"])
	lm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lounge.material_override = lm
	lounge.position = GameData.world_to_3d(a.w / 2.0, a.h / 2.0, 0)
	add_child(lounge)

	var sw := StandInWorld.new()
	sw.name = "World"
	add_child(sw)
	world = sw
	var c: Dictionary = GameData.data.calls
	for b in c.lobbySolidBoxes:
		boxes.append({"x0": float(b.x0), "y0": float(b.y0), "x1": float(b.x1), "y1": float(b.y1), "h": 40.0, "m": "lounge"})
	for b in EXTRA_BOXES:
		boxes.append(b.duplicate())
	sw.boxes = boxes
	for b in boxes:
		_solid(b)

	_add_rest()

func _add_rest() -> void:
	tramp = Trampoline.new()
	tramp.name = "Trampoline"
	add_child(tramp)

	player = Player.new()
	player.name = "Player"
	player.char_id = "juicy"
	add_child(player)
	player.place(707, 1340 + 122 + 25)
	player.face_mouse = false

	goth = Gothica.new()
	goth.name = "Gothica"
	add_child(goth)
	g_last = goth.html_pos2()

	if interactive:
		rig = CameraRig.new()
		rig.name = "Rig"
		add_child(rig)
		rig.target = player
		rig.capture_mouse = true
		rig.bounds = Rect2()
		var lab := Label.new()
		lab.name = "Label"
		lab.position = Vector2(16, 16)
		lab.add_theme_font_size_override("font_size", 20)
		var cl := CanvasLayer.new()
		cl.add_child(lab)
		add_child(cl)
	else:
		cam = Camera3D.new()
		add_child(cam)
		cam.current = true

func _solid(b: Dictionary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var inset := 7.0                       # like the World: the player gets half his radius in
	bs.size = Vector3(maxf(1.0, b.x1 - b.x0 - inset * 2) * GameData.UNIT, b.h * GameData.UNIT, maxf(1.0, b.y1 - b.y0 - inset * 2) * GameData.UNIT)
	cs.shape = bs
	body.add_child(cs)
	body.position = GameData.world_to_3d((b.x0 + b.x1) / 2.0, (b.y0 + b.y1) / 2.0, b.h / 2.0)
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3((b.x1 - b.x0) * GameData.UNIT, b.h * GameData.UNIT, (b.y1 - b.y0) * GameData.UNIT)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.35, 0.3) if b.m == "test" else Color(0.55, 0.4, 0.25)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.75
	mi.material_override = m
	mi.position = body.position
	add_child(mi)

func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _unhandled_input(event: InputEvent) -> void:
	if interactive and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_G:
			# to Gothica in the lounge and back
			if player.html_pos().y > 900:
				if player.on_tramp:
					tramp.release(player)
				player.place(300, 440)
			else:
				player.place(707, 1340 + 122 + 25)
			rig.snap()
		elif event.physical_keycode == KEY_H:
			# straight onto the trampoline, high (for screenshots)
			if not player.on_tramp:
				player.place(707, 1340 + 122 + 25)
				tramp.climb_on(player)
			tramp.riders[player].tv = 520.0
			rig.snap()

func _process(_d: float) -> void:
	if interactive:
		var lab: Label = get_node("CanvasLayer/Label") if has_node("CanvasLayer/Label") else null
		if lab == null:
			for ch in get_children():
				if ch is CanvasLayer:
					lab = ch.get_child(0)
		if lab:
			var hp := player.html_pos()
			lab.text = "E: %s   dz %.0f   over mat %.0f   (Shift: higher, G: Gothica, H: high, V: view)" % [
				player.focus_label, player.dz, tramp.height_over_mat(player)]
		if f % 30 == 0:
			var gp := goth.html_pos2()
			print("STATE x=%.1f y=%.1f dz=%.1f tramp=%s label=%s goth=%.1f,%.1f moving=%s view=%s" % [
				player.html_pos().x, player.html_pos().y, player.dz, player.on_tramp, player.focus_label,
				gp.x, gp.y, goth.moving, goth.sprite.current_view])

func _physics_process(_d: float) -> void:
	f += 1
	_check_goth()
	if interactive:
		return
	cam.global_position = GameData.world_to_3d(707, 1340 + 600, 400)
	cam.look_at(GameData.world_to_3d(707, 1340, 40))
	_track_peak()
	var hp := player.html_pos()
	match f:
		5:
			print("TEST label next to it: '", player.focus_label, "' (want CLIMB ON) dist=", tramp.ground_distance(player))
			player.place(707, 1340 + 122 + 45)
		7:
			print("TEST label at r+45: '", player.focus_label, "' (want nothing, reach r+40)")
			player.place(707, 1340 + 122 + 25)
		9:
			key(KEY_E, true)
		10:
			key(KEY_E, false)
			print("TEST after E: on_tramp=", player.on_tramp, " dz=", player.dz, " pos=", player.html_pos(), " (want 707, 1426: r-36 from the middle) label='", player.focus_label, "'")
			peaks.clear()
			key(KEY_SHIFT, true)
		# 1) roll held from climbing on: higher every bounce
		600:
			print("TEST roll held from climbing on, peaks over the mat: ", _fmt(peaks))
			peaks.clear()
			key(KEY_SHIFT, false)
		# 2) let go: dies back down to the plain bounce
		1300:
			print("TEST let go (no pushes), peaks: ", _fmt(peaks))
			peaks.clear()
			key(KEY_SHIFT, true)
		# 3) roll held again from the plain bounce
		2000:
			print("TEST roll held from the plain bounce, peaks: ", _fmt(peaks))
			peaks.clear()
			key(KEY_SHIFT, false)
		2700:
			print("TEST let go again, peaks: ", _fmt(peaks))
			peaks.clear()
			print("TEST label low: '", player.focus_label, "'")
		2710:
			# the net: walk right into it
			key(KEY_D, true)
		2900:
			var d := Vector2(hp.x - 707, hp.y - 1340).length()
			print("TEST walking into the net: distance from the middle ", snappedf(d, 0.01), " (want <= 100: r-22) on=", player.on_tramp, " vel=", player.vel)
			key(KEY_D, false)
		2901:
			# climb off when low
			_wait_low_then("off")
		3200:
			print("TEST after CLIMB OFF: on=", player.on_tramp, " dz=", player.dz, " pos=", player.html_pos(), " dist=", snappedf(Vector2(hp.x - 707, hp.y - 1340).length(), 0.1), " (want r+24 = 146) frozen=", player.frozen)
			# on again, push up high, then E: JUMP OFF
			player.place(707 - 122 - 20, 1340)
		3202:
			key(KEY_E, true)
		3203:
			key(KEY_E, false)
			print("TEST on again from the west: pos=", player.html_pos(), " (want 621, 1340)")
			key(KEY_SHIFT, true)
		3600:
			_wait_high_then_jump()
		4200:
			print("TEST after the jump: on=", player.on_tramp, " frozen=", player.frozen, " dz=", player.dz, " pos=", player.html_pos(), " dist=", snappedf(Vector2(hp.x - 707, hp.y - 1340).length(), 0.1))
			# on again, high, run at the net: over it
			player.place(707, 1340 - 122 - 20)
		4202:
			key(KEY_E, true)
		4203:
			key(KEY_E, false)
			key(KEY_SHIFT, true)
			_leap_seen = false
			_land_seen = false
		4800:
			# by now up at ~300 every bounce; run south at the net
			key(KEY_S, true)
			_watch_leap = true
		5300:
			standin = StandIn.new()
			add_child(standin)
			standin.global_position = GameData.world_to_3d(707 + 140, 1340, 0)
			print("TEST stand-in: label '", tramp.label_for(standin), "'")
			tramp.act(standin)
			print("TEST stand-in after act: on_tramp=", standin.on_tramp, " dz=", standin.dz, " pos=", GameData.from_3d(standin.global_position))
		5200:
			key(KEY_S, false)
			key(KEY_SHIFT, false)
			print("TEST after running at the net: on=", player.on_tramp, " frozen=", player.frozen, " dz=", player.dz, " pos=", player.html_pos(), " dist=", snappedf(Vector2(hp.x - 707, hp.y - 1340).length(), 0.1))
	if standin and f > 5300:
		if tramp.riders.has(standin):
			tramp.riders[standin].tjump = true
			if tramp.is_high(standin) and tramp.riders[standin].tz > 250:
				print("TEST stand-in high: label '", tramp.label_for(standin), "' y=", snappedf(standin.global_position.y / 0.025, 0.1), " dz=", snappedf(standin.dz, 0.1))
				tramp.act(standin)
				print("TEST stand-in leapt: frozen=", standin.frozen, " flying=", tramp.fliers.has(standin))
		elif standin.frozen == false and standin.on_tramp == false and not _standin_done and standin.dz == 0.0 and f > 5310:
			_standin_done = true
			print("TEST stand-in landed at ", GameData.from_3d(standin.global_position), " dist ", snappedf(Vector2(GameData.from_3d(standin.global_position).x - 707, GameData.from_3d(standin.global_position).y - 1340).length(), 0.1))
	if _waiting != "":
		_poll_wait()
	if _watch_leap and tramp.fliers.has(player) and not _leap_seen:
		_leap_seen = true
		print("TEST auto leap over the net at f=", f, " pos=", hp, " dz=", player.dz, " dist=", snappedf(Vector2(hp.x - 707, hp.y - 1340).length(), 0.1))
	if _leap_seen and not _land_seen and not tramp.fliers.has(player):
		_land_seen = true
		print("TEST landed at f=", f, " pos=", hp, " dist=", snappedf(Vector2(hp.x - 707, hp.y - 1340).length(), 0.1), " dz=", player.dz, " frozen=", player.frozen)
	if f >= int(goth_minutes * 3600) and f > 6200:
		_report_goth()
		get_tree().quit()

var _waiting := ""
var standin: StandIn
var _standin_done := false
var _watch_leap := false
var _leap_seen := false
var _land_seen := false

func _wait_low_then(what: String) -> void:
	_waiting = what

func _wait_high_then_jump() -> void:
	_waiting = "jump"

func _poll_wait() -> void:
	if _waiting == "off":
		if player.on_tramp and tramp.height_over_mat(player) < 20 and not tramp.is_high(player):
			print("TEST label when low: '", player.focus_label, "' (want CLIMB OFF)")
			player.use()
			_waiting = ""
	elif _waiting == "jump":
		if player.on_tramp and tramp.height_over_mat(player) > 200:
			print("TEST label when high (", snappedf(tramp.height_over_mat(player), 0.1), " over the mat): '", player.focus_label, "' (want JUMP OFF)")
			key(KEY_SHIFT, false)
			player.facing = Vector2(-1, 0)
			player.use()
			print("TEST jumped: fliers=", tramp.fliers.has(player), " frozen=", player.frozen, " facing=", player.facing)
			_leap_seen = true
			_waiting = ""

func _track_peak() -> void:
	if not tramp.riders.has(player):
		_last_tv = 0.0
		return
	var r: Dictionary = tramp.riders[player]
	_peak = maxf(_peak, r.tz)
	if _last_tv > 0.0 and r.tv <= 0.0:
		peaks.append(_peak)
	if r.tv > 0.0 and _last_tv <= 0.0:
		_peak = 0.0
	_last_tv = r.tv

func _fmt(a: Array) -> String:
	var s: PackedStringArray = []
	for v in a:
		s.append(str(snappedf(v, 0.1)))
	return ", ".join(s)

func _check_goth() -> void:
	var p := goth.html_pos2()
	g_xmin = minf(g_xmin, p.x)
	g_xmax = maxf(g_xmax, p.x)
	g_ymin = minf(g_ymin, p.y)
	g_ymax = maxf(g_ymax, p.y)
	for b in boxes:
		var cx := clampf(p.x, b.x0, b.x1)
		var cy := clampf(p.y, b.y0, b.y1)
		var d := Vector2(p.x - cx, p.y - cy).length()
		if p.x > b.x0 and p.x < b.x1 and p.y > b.y0 and p.y < b.y1:
			d = 0.0
			g_inside += 1
			if g_inside < 5:
				print("TEST !!! Gothica inside a box at ", p, " box ", b)
		g_min_clear = minf(g_min_clear, d)
	var moved := p.distance_to(g_last)
	g_dist += moved
	if goth.moving:
		g_frames_moving += 1
	var waiting := goth.wait > 0.0
	if waiting and not g_was_waiting:
		g_spots += 1
	g_was_waiting = waiting
	g_last = p

func _report_goth() -> void:
	print("TEST Gothica over %.1f min: spots reached %d, walked %.0f units, %.1f s walking (%.1f units/s), inside a box %d frames, closest to a box %.2f units, roamed x %.0f..%.0f y %.0f..%.0f" % [
		f / 3600.0, g_spots, g_dist, g_frames_moving / 60.0, g_dist / maxf(0.01, g_frames_moving / 60.0), g_inside, g_min_clear, g_xmin, g_xmax, g_ymin, g_ymax])
	print("TEST Gothica obstacles used: ", goth.obstacles.size(), " sprite view=", goth.sprite.current_view, " key=", goth.sprite.current_key)
