extends SceneTree
## Pictures of the Carousel's horses (VoxelCarousel): from outside the ride, from on the platform, by day and by night
## (--out=dir). Checks there are 12 of them riding up and down on it. Prints PASS or FAIL. Owned by the St Kilda session.

# [where you stand: metres out from its middle, height, how far round (radians)], look at this high, night?
const SHOTS := [[11.0, 1.7, 0.4, 2.0, false, "day"], [6.3, 1.6, 1.3, 1.6, false, "close"], [8.0, 1.65, 2.2, 1.3, false, "edge"], [6.6, 1.5, 3.4, 4.6, false, "ceiling"],
	[11.0, 1.7, 0.4, 2.0, true, "night"]]

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var shot := 0
var out := ""
var fails := []
var y0 := 0.0

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 and step == 0:
		return false
	var car := sk.get_node("Carousel") as Node3D if sk else null
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			car = sk.get_node("Carousel") as Node3D
			var spin := car.get_node("Ride") as SkLunaRides.Spinner
			_check(spin.horses.size() == 12, "12 horses on it (%d)" % spin.horses.size())
			_check(car.find_children("Horses?", "", true, false).is_empty(), "the old box horses gone")
			step = 1
			t = 0.0
		1:
			var s: Array = SHOTS[shot]
			if t < dt * 1.5:
				if bool(s[4]) != sk.day_night.night:
					sk.day_night.toggle()
				var mid := car.global_position
				var a: float = s[2]
				var at := mid + Vector3(cos(a), 0, sin(a)) * float(s[0])
				var to := mid + Vector3(0, float(s[3]), 0) - (at + Vector3(0, float(s[1]), 0))
				sk._put(Vector3(at.x, 0.05, at.z), atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
				var h: Array = (car.get_node("Ride") as SkLunaRides.Spinner).horses[0]
				y0 = (h[0] as MultiMeshInstance3D).multimesh.get_instance_transform(h[1]).origin.y
			if t > 2.5:
				if shot == 0:
					var h: Array = (car.get_node("Ride") as SkLunaRides.Spinner).horses[0]
					var y1 := (h[0] as MultiMeshInstance3D).multimesh.get_instance_transform(h[1]).origin.y
					_check(absf(y1 - y0) > 0.01, "they ride up and down (%.2f m)" % absf(y1 - y0))
				if out != "":
					root.get_texture().get_image().save_png("%s/carousel_%s.png" % [out, s[5]])
				shot += 1
				t = 0.0
				if shot >= SHOTS.size():
					step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
