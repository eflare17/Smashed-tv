class_name VoxelParkGame
extends Node
## "Kill 1, 2 come" in Luna Park (the owner's idea, 29 Oct: "for every 1 you kill 2 spawn"): picked on the phone.
## Three enemies to start; every one you kill brings two more, over Luna Park's wall somewhere or out of the Ghost
## Train, so there's always one more than before. At most MAX_ALIVE about at once (the rest wait their turn). It goes
## till you go down: then your kills and time, and your best (kept in user://). The phone takes you home (and stops it).

const START := 3
const MAX_ALIVE := 40
const SPAWN_GAP := 0.35          # s between new ones coming in
const FAR := 14.0                # m from you at least, where they come in
const KINDS := ["grunt", "grunt", "swarmer", "swarmer", "batter", "batter", "brute", "charger", "shielder"]
const BEST_FILE := "user://stkilda_kill12.cfg"

var sk: VoxelStKilda
var running := false
var over := false
var kills := 0
var time := 0.0
var best_kills := 0
var best_time := 0.0
var _due := 0                    # still to come in
var _gap := 0.0
var _spots: Array = []           # where they come in: inside the wall's foot, and the Ghost Train's door
var _hud: Label
var _end: Label

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "Kill12"
	var cf := ConfigFile.new()
	if cf.load(BEST_FILE) == OK:
		best_kills = int(cf.get_value("best", "kills", 0))
		best_time = float(cf.get_value("best", "time", 0.0))
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.offset_left = -360
	_hud.offset_right = 360
	_hud.offset_top = 64
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color("#ffd54a"))
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.visible = false
	sk.arena._hud_layer.add_child(_hud)
	_end = Label.new()
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.offset_left = -360
	_end.offset_right = 360
	_end.offset_top = -250
	_end.offset_bottom = -60
	_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.add_theme_font_size_override("font_size", 30)
	_end.add_theme_color_override("font_color", Color.WHITE)
	_end.add_theme_color_override("font_outline_color", Color.BLACK)
	_end.add_theme_constant_override("outline_size", 10)
	_end.visible = false
	sk.arena._hud_layer.add_child(_end)

## Off we go (you're in St Kilda).
func start() -> void:
	stop()
	_find_spots()
	running = true
	over = false
	kills = 0
	time = 0.0
	_due = START
	_gap = 0.0
	_hud.visible = true
	_end.visible = false
	sk.arena.player_hp = sk.arena.HP_MAX

## Stopped (going home, or starting again): its enemies gone.
func stop() -> void:
	running = false
	over = false
	_hud.visible = false
	_end.visible = false
	sk.clear_park()

func _process(dt: float) -> void:
	if not running:
		return
	var a := sk.arena
	if a.down_t > 0.0:
		_game_over()
		return
	time += dt
	_gap -= dt
	var alive := 0
	for b in a.bodies:
		if b.alive and b.has_meta("park"):
			alive += 1
	if _due > 0 and alive < MAX_ALIVE and _gap <= 0.0:
		_come_in()
		_due -= 1
		_gap = SPAWN_GAP
	_hud.text = "KILL 1, 2 COME     kills %d     about %d%s     %s" % [kills, alive, ("  (+%d coming)" % _due) if _due > 0 else "", _clock(time)]

func _come_in() -> void:
	var me := sk.arena.player.global_position
	var at: Vector3 = _spots[randi() % _spots.size()]
	for k in 8:                               # (not right next to you)
		if Vector2(at.x - me.x, at.z - me.z).length() >= FAR:
			break
		at = _spots[randi() % _spots.size()]
	var b := sk.spawn(KINDS[randi() % KINDS.size()], at)
	b.died.connect(_killed, CONNECT_ONE_SHOT)
	if sk.arena.debris:                       # (a puff of grey where it drops in)
		sk.arena.debris.throw(b.position + Vector3(0, 0.3, 0), Vector3.UP, Color(0.55, 0.55, 0.58), 12)

func _killed(_b: VoxelBody) -> void:
	if not running:
		return
	kills += 1
	_due += 2

func _game_over() -> void:
	running = false
	over = true
	var new_best := kills > best_kills or (kills == best_kills and time > best_time)
	if new_best:
		best_kills = kills
		best_time = time
		var cf := ConfigFile.new()
		cf.set_value("best", "kills", best_kills)
		cf.set_value("best", "time", best_time)
		cf.save(BEST_FILE)
	_hud.visible = false
	_end.text = "%s in %s%s\nbest: %s in %s\nP: the phone (home, or play again)" % [_n(kills), _clock(time),
		"   NEW BEST!" if new_best else "", _n(best_kills), _clock(best_time)]
	_end.visible = true
	sk.clear_park()

static func _n(k: int) -> String:
	return "%d kill%s" % [k, "" if k == 1 else "s"]

static func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]

# where they come in: just inside Luna Park's wall, every few metres round it, and the Ghost Train's door
func _find_spots() -> void:
	if not _spots.is_empty():
		return
	var park = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/luna.json"))
	var wall := PackedVector2Array()
	for e in park.elements:
		if e.type == "way" and int(e.id) == SkLunaPark.WALL_WAY:
			for g in e.geometry:
				wall.append(sk.town.project(g.lat, g.lon))
	var mid := Vector2.ZERO
	for p in wall:
		mid += p
	mid /= maxf(1.0, wall.size())
	for i in wall.size() - 1:
		var a := wall[i]
		var c := wall[i + 1]
		var n := maxi(1, int(a.distance_to(c) / 6.0))
		for k in n:
			var p := a.lerp(c, (k + 0.5) / n)
			p += (mid - p).normalized() * 2.5          # (in from the wall)
			_spots.append(Vector3(p.x, 0, p.y))
	var gt = sk.get_meta("luna_spots", {}).get("Luna Park - Ghost Train")     # ([where you stand before it, which way])
	if gt is Array and not gt.is_empty():
		for k in 3:
			_spots.append(Vector3(gt[0].x, 0, gt[0].z))
	if _spots.is_empty():
		_spots.append(sk.arrive_spot()[0])
