extends Node
## A visual online test (screenshots, test/net/two_pages.mjs with DRIVE=res://test/net/look.gd): seeing what the
## other player is doing. The host takes a hair style and lies in bed; the guest stands by the bed watching
## (top-down for 70 s), then turns to first person looking at the host (70 s more), then the host gets up and
## walks over to the guest. Prints "LOOK <phase>" as each starts.
## Owned by the Online task.

var net: Net
var t := -1.0
var phase := 0

func _ready() -> void:
	net = get_parent()

func _process(dt: float) -> void:
	if not net.live or net.fight == null or not is_instance_valid(net.fight) or net.p2 == null or not is_instance_valid(net.p2):
		return
	if t < 0.0:
		t = 0.0
	t += dt
	var host := net.role == "host"
	var me: Player = net.player
	var bed = LobbyLife.current.things["bed"]
	if phase == 0 and t > 2.0:
		phase = 1
		print("LOOK bed")
		if host:
			LobbyLook.set_style(3)
			me.char_id = "juicy"
			bed.lie_down(me, 1)
		else:
			me.char_id = "tyson2"
			me.place(330, 640)
			me.facing = Vector2(0, -1)
	elif phase == 1 and t > 70.0:
		phase = 2
		print("LOOK first person")
		if not host:
			net.main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
			var them := net.p2.html_pos()
			var at := me.html_pos()
			me.look_ang = atan2(them.y - at.y, them.x - at.x)
			me.look_y = 0.25
	elif phase == 2 and t > 140.0:
		phase = 3
		print("LOOK up")
		if host:
			bed.get_up(me)
