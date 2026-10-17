class_name LobbyVend
extends LobbyThing
## The vending machine that sells the nuke launcher (Smashed.html: vendPos, the buy in stepPlayers @7251, the
## cabinet and its texts @12013). Owned by the Lobby life session.
##
## 176 x 300 art at 0.5 (150 units tall), blinking its two idle pictures at 2.5 Hz, a sold-out picture after a
## sale. $2500 (T.vendPrice) buys the launcher with 3 rockets (T.launcherRounds): E ("BUY $2500") roots him for
## T.vendHold 0.8 s with a progress bar (moving or pressing E again cancels, as walking off does in the HTML
## game); then "-$2500" floats up, the cash goes, a chirp and a thump play, and signal prize(player, "launcher")
## fires with the player's meta "rockets" set to 3 (the fighting session turns that into the weapon).
##
## Port decisions: the HTML game only has the machine during a run (705, 154); here it also stands in the
## lounge at calls.vendPos (235, 154), as the owner's brief asks, and restocks 8 s after a sale (a run restocks it
## each wave).

signal prize(player: Node, kind: String)

const RESTOCK := 8.0

var pos := Vector2(235.0, 154.0)
var sold: bool = false
var restock_t: float = 0.0
var buy: float = 0.0
var buyer: Player

var _pic: LobbyPic
var _t: float = 0.0
var _bar: ColorRect
var _fill: ColorRect

func _ready() -> void:
	reach = 70.0
	var v = LobbyLife.calls("vendPos", {"x": 235, "y": 154})
	pos = Vector2(float(v.x), float(v.y))
	global_position = GameData.world_to_3d(pos.x, pos.y, 0.0)
	await get_tree().process_frame
	_pic = LobbyPic.make(LobbyPic.art("machines/vend_idle_a.png"), 0.5, 0.0)
	_pic.top_level = true
	add_child(_pic)
	_pic.global_position = GameData.world_to_3d(pos.x, pos.y + 6.0, 0.0)
	_bar = ColorRect.new()
	_bar.color = Color(20 / 255.0, 22 / 255.0, 28 / 255.0, 0.8)
	_bar.size = Vector2(140, 12)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -70
	_bar.offset_right = 70
	_bar.offset_top = -200
	_bar.offset_bottom = -188
	_bar.visible = false
	_fill = ColorRect.new()
	_fill.color = Color("#9be29b")
	_fill.size = Vector2(0, 12)
	_bar.add_child(_fill)
	ll.ui.root.add_child(_bar)

func near(p: Node) -> bool:
	return ppos(p).distance_to(pos) < LobbyLife.T("vendRadius", 56.0) + 8.0

func price() -> int:
	return int(LobbyLife.T("vendPrice", 2500))

func label_for(p: Node) -> String:
	if not can_start(p) or not near(p):
		return ""
	if sold:
		return "SOLD OUT"
	if ll.cash(p) < price():
		return "NEED $%d" % price()
	return "BUY $%d" % price()

func act(p: Node) -> void:
	if not can_start(p) or not near(p) or sold or ll.cash(p) < price():
		return
	buyer = p as Player
	buy = 0.0
	ll.hold(buyer, self)
	_bar.visible = true

func busy_label(_p: Player) -> String:
	return "STOP"

func busy_act(p: Player) -> void:
	cancel(p)

func busy_end(_p: Player) -> void:
	_bar.visible = false
	buyer = null
	buy = 0.0

func cancel(p: Player) -> void:
	_bar.visible = false
	buyer = null
	buy = 0.0
	ll.release(p)

func busy_step(p: Player, dt: float) -> void:
	p.halt()
	if p.read_steer().length() > 0.3:
		cancel(p)
		return
	buy += dt
	_fill.size.x = 140.0 * clampf(buy / LobbyLife.T("vendHold", 0.8), 0.0, 1.0)
	if buy >= LobbyLife.T("vendHold", 0.8):
		_sell(p)

func _sell(p: Player) -> void:
	_bar.visible = false
	buyer = null
	buy = 0.0
	ll.release(p)
	if not ll.pay(p, price()):
		return
	sold = true
	restock_t = RESTOCK
	p.set_meta("rockets", int(LobbyLife.T("launcherRounds", 3)))
	p.set_meta("weapon", "launcher")
	ll.ui.float_text(pos.x, pos.y, 110.0, "-$%d" % price(), Color("#e0473f"), 1.2, 18)
	ll.ui.info("NUKE LAUNCHER!", 1.4)
	ll.sfx.tone(500, 0.08, "square", 0.2, 900)
	ll.sfx.tone(90, 0.25, "square", 0.3, 60)
	prize.emit(p, "launcher")

func _process(dt: float) -> void:
	_t += dt
	if sold:
		restock_t -= dt
		if restock_t <= 0.0:
			sold = false
	if _pic:
		var key := "machines/vend_sold.png" if sold else ("machines/vend_idle_b.png" if int(_t * 2.5) % 2 == 1 else "machines/vend_idle_a.png")
		var t := LobbyPic.art(key)
		if _pic.texture != t:
			_pic.texture = t

func test_scene(tl: Node, parts: PackedStringArray) -> void:
	tl.go(235.0, 205.0, Vector2(0, -1))
	if parts.has("walk"):
		return
	tl.later(0.8, func(): tl.use())
