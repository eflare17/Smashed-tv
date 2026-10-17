extends Node
## A visual online test (screenshots, test/net/two_pages.mjs with DRIVE=res://test/net/look.gd): seeing what the
## other player is doing. The host takes a hair style and lies in bed; the guest stands by the bed watching
## (top-down), then turns to first person looking at the host, then (as Jared) picks up lobby Gothica, which the
## host's game runs. Prints "LOOK <phase>" as each starts (game seconds: a slow page runs slower than real time).
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
	elif phase == 1 and t > 12.0:
		phase = 2
		print("LOOK first person")
		if not host:
			net.main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
			var them := net.p2.html_pos()
			var at := me.html_pos()
			me.look_ang = atan2(them.y - at.y, them.x - at.x)
			me.look_y = 0.25
	elif phase == 2 and t > 24.0:
		phase = 3
		print("LOOK carry")
		if host:
			bed.get_up(me)
		else:
			net.main.rig.set_mode(CameraRig.Mode.TOP_DOWN)
			me.char_id = "juicy"
	elif phase == 3 and not host:
		var gl = LobbyLife.current.things["goth_life"]
		if gl.carrier != me:
			if me.focus_label == "PICK UP":
				me.use()
			else:
				var g := GameData.from_3d(net.main.gothica.global_position)
				me.place(g.x + 20.0, g.y)
		else:
			phase = 4
			print("LOOK carrying")
