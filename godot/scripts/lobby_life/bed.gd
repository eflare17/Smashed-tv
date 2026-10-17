class_name LobbyBed
extends LobbyThing
## The bed (Smashed.html: BED @1971, bedSpot, bedNear, lieDown, getUp, drawSleepers @2459). Owned by the Lobby life
## session.
##
## E near the bed (x 290..470, y 520..710; "LIE DOWN") puts him in it on the half he's nearer: he lies with his head
## on the pillow, the sheet and the blanket over his chest and three z's drifting up. E ("GET UP") or any move
## input (or the roll button) gets him out at the foot of the bed. Lying down emits LobbyLife.sleep_requested (the day
## and night clock skips to morning on it, the one thing the HTML game doesn't do); getting up emits woke.
##
## Port decisions: the bed is top-down only, as in the HTML game (first person steps aside to top-down for the
## time and comes back); his picture is a LobbyPic of his frame (hair and shirt print included) cut off at the
## sheet, like drawSleepers' clip.

const BED := Rect2(314.0, 520.0, 132.0, 156.0)    # x0 314, x1 446, y0 520, y1 676
const NEAR := Rect2(290.0, 520.0, 180.0, 190.0)   # x 290..470, y 520..710

var sides: Dictionary = {}        # player -> 1 | 2 (which half)
var _was_fp: Dictionary = {}
var _z_t: float = 0.0

func _ready() -> void:
	reach = 130.0
	global_position = GameData.world_to_3d(380.0, 615.0, 0.0)

## bedSpot(side): side 1 left, 2 right.
static func spot(side: int) -> Vector2:
	return Vector2((BED.position.x + BED.end.x) / 2.0 + (-30.0 if side == 1 else 30.0), BED.position.y + 70.0)

## bedNear: which side he could take (0 for none).
func side_for(p: Node) -> int:
	if not can_start(p):
		return 0
	var o := ppos(p)
	if not NEAR.has_point(o):
		return 0
	var want := 1 if o.x < (BED.position.x + BED.end.x) / 2.0 else 2
	if not _taken(want, p):
		return want
	if not _taken(3 - want, p):
		return 3 - want
	return 0

func _taken(s: int, but: Node) -> bool:
	for q in sides:
		if q != but and sides[q] == s:
			return true
	return false

func label_for(p: Node) -> String:
	return "LIE DOWN" if side_for(p) > 0 and not (p.get("carrying_goth") if p.get("carrying_goth") != null else false) else ""

func act(p: Node) -> void:
	if side_for(p) > 0:
		lie_down(p as Player, side_for(p))

func lie_down(p: Player, side: int) -> void:
	ll.hold(p, self)
	sides[p] = side
	var s := spot(side)
	p.facing = Vector2(0, 1)
	put(p, s.x, s.y, 0.0)
	_was_fp[p] = p.is_first_person()
	if _was_fp[p]:
		ll.rig.set_mode(CameraRig.Mode.TOP_DOWN)
	ll.set_pose(p, _sleeper(p))
	_z_t = 0.0
	ll.sleep_requested.emit(p)

func get_up(p: Player) -> void:
	var s := spot(sides.get(p, 1))
	sides.erase(p)
	var fp: bool = _was_fp.get(p, false)
	_was_fp.erase(p)
	ll.release(p)
	p.facing = Vector2(0, 1)
	put(p, s.x, BED.end.y + LobbyLife.T("radius", 14.0) + 2.0, 0.0)
	p.halt()
	if fp:
		ll.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	ll.woke.emit(p)

func busy_label(_p: Player) -> String:
	return "GET UP"

func busy_act(p: Player) -> void:
	get_up(p)

func busy_end(p: Player) -> void:
	sides.erase(p)

func hides_sprite(_p: Player) -> bool:
	return true

func busy_step(p: Player, dt: float) -> void:
	var s := spot(sides.get(p, 1))
	put(p, s.x, s.y, 0.0)
	p.halt()
	var m := p.read_steer()
	var js := Player.pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if m.length() > 0.3 or js.length() > 0.3 or Input.is_action_pressed("roll"):
		get_up(p)
		return
	_z_t += dt
	# three z's drifting up and right, fading (drawSleepers)
	if fmod(_z_t, 0.66) < dt:
		ll.ui.float_text(s.x + 16.0, s.y - 20.0, 30.0, "z", Color(0.86, 0.92, 1.0), 2.0, 16)

## drawSleepers: his front frame from the pillow down to the fold, the sheet and the blanket edge.
func _sleeper(p: Player) -> LobbyPic:
	var path := CharFrames.path(p.char_id, "front_run", 0)
	var tex := GameData.tex(path)
	var src := tex.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	if p.char_id == "juicy":
		var bt := LobbyLook.baked(path, tex, false)
		if bt != tex:
			src = bt.get_image()
			src.convert(Image.FORMAT_RGBA8)
	var cut := 68                                   # 34 units of him show above the fold
	var w := src.get_width()
	var im := Image.create(w, cut + 32, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	im.blit_rect(src, Rect2i(0, 0, w, cut), Vector2i.ZERO)
	im.fill_rect(Rect2i(4, cut, w - 8, 16), Color("#dfe6f0"))
	im.fill_rect(Rect2i(4, cut + 16, w - 8, 16), Color("#2f4f7a"))
	var pic := LobbyPic.make(ImageTexture.create_from_image(im), 0.5)
	pic.lift = 20.0
	return pic

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(360.0, 700.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	tl.later(0.8, func(): tl.use())
