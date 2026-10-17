extends RefCounted
## The mushroom.

func run(t) -> void:
	var ll: LobbyLife = t.ll
	var s: LobbyShroom = ll.things["shroom"]
	await t.wait(0.3)
	t.place(55, 440)
	await t.wait(0.2)
	t.check(t.label() == "EAT", "label EAT (%s)" % t.label())
	t.press_e()
	await t.wait(0.3)
	t.check(s.on and ll.rig.mode == CameraRig.Mode.FIRST_PERSON, "E starts the trip in first person")
	t.check(s.fade > 0.0 and s.fade < 1.0, "the fade is spiralling in (%f)" % s.fade)
	await t.wait(2.3)
	t.check(s.amp > 0.95, "full strength (%f)" % s.amp)
	t.check(t.label() == "", "nothing to eat meanwhile (%s)" % t.label())
	s.t = 29.0
	await t.wait(1.2)
	t.check(not s.on and ll.rig.mode == CameraRig.Mode.TOP_DOWN, "after 30 s it ends and the view returns")
	t.check(not s.here() and s._now >= 0.0, "the mushroom has gone")
	s.gone_until = 0.0
	await t.wait(0.1)
	t.place(55, 440)
	await t.wait(0.2)
	t.check(t.label() == "EAT", "and it grows back")
