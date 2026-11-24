extends SceneTree
## Pictures of "Luna Park: Invasion" (under a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot --resolution 1280x720 --fixed-fps 60 -s res://test/voxel/luna_invasion_shots.gd
## into integration/voxel_shots/luna_invasion_*.png: enemies on the Carousel (as you see it, and close up), on the
## Scenic Railway, the Sky Rider and the Spider (close up, from a camera of the test's own), a group on the ground,
## the phone. (-- --only=name: just that one.) Owned by the St Kilda session.

const I := preload("res://scripts/voxel/stkilda/voxel_park_invasion.gd")
const OUT := "res://integration/voxel_shots/luna_invasion_%s.png"

var arena: VoxelArena
var sk: VoxelStKilda
var inv: VoxelParkInvasion
var f := 0
var step := 0
var busy := false
var only := ""
var list := ["carousel", "carousel_close", "coaster", "wheel", "spider", "phone", "ground"]
var cam: Camera3D                # the close-ups' own camera (the riders seen from in front, wherever the ride's taken them)

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--only="):
			only = x.trim_prefix("--only=")
	seed(20261124)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _save(name: String) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT % name))
	print("SHOT ", name)
	busy = false

# stood `back` m from `at` on the side nearer `toward`, looking at `at`
func _look(at: Vector3, back: float, toward: Vector3, eye := 1.7) -> void:
	var d := Vector3(toward.x - at.x, 0, toward.z - at.z)
	d = d.normalized() if d.length() > 0.5 else Vector3(0, 0, -1)
	var p := Vector3(at.x, 0.05, at.z) + d * back
	var to := at - (p + Vector3(0, eye, 0))
	sk._put(p, atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))

func _riders(name: String) -> Array:
	var r: Dictionary = inv.rides.filter(func(x): return x.name == name)[0]
	return (r.riders as Array).filter(func(x): return x.state == I.SEATED)

func _mid(recs: Array) -> Vector3:
	var m := Vector3.ZERO
	for r in recs:
		m += inv._seat_xf(r).origin
	return m / maxf(1.0, recs.size())

# the test's camera in front of a rider (or a few), `back` m off and a little above, looking at them
func _close(recs: Array, back: float) -> void:
	if recs.is_empty():
		return
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 55.0
		cam.near = 0.1
		cam.far = 1500.0
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # (put by the frame)
		root.add_child(cam)
	var at := Vector3.ZERO
	var front := Vector3.ZERO
	for r in recs:
		var x := inv._seat_xf(r)
		at += x * Vector3(0, 1.0, 0)
		front += -x.basis.z.normalized()
	at /= recs.size()
	front.y = 0.0
	front = front.normalized() if front.length() > 0.1 else Vector3(0, 0, 1)
	cam.global_position = at + front * back + Vector3(0, 0.9, 0) + front.cross(Vector3.UP) * back * 0.45
	cam.look_at(at, Vector3.UP)
	cam.current = true

func _process(_dt: float) -> bool:
	f += 1
	if arena.waves and arena.waves._banner:
		arena.waves._banner.text = ""             # (the arena's "WAVE 1", just started: not in these)
	if busy:
		return false
	if step == 0:
		if f < 30:
			return false
		arena.waves.queue.clear()
		arena.godmode = true
		sk = arena.stkilda
		sk.go()
		inv = sk.invasion
		inv.seed_ = 7
		inv.start()
		step = 1
		f = 0
		return false
	if arena.phone.is_open() and step % 2 == 1:
		arena.phone.close()                       # (the picture before's taken)
	var k := (step - 1) / 2
	if k >= list.size():
		quit(0)
		return false
	var name: String = list[k]
	if only != "" and name != only:
		step += 2
		return false
	var home: Vector3 = sk.arrive_spot()[0]
	var ride_of := {"carousel_close": "Carousel", "coaster": "SkScenicRailway", "wheel": "SkyRider", "spider": "Spider"}
	if step % 2 == 1:                         # (stood there; a few frames for the riders to be made and sat)
		if cam:
			cam.current = false
			arena.cam.current = true
		match name:
			"carousel":
				var n := sk.get_node("Carousel") as Node3D
				_look(n.global_position + Vector3(0, 1.6, 0), 14.5, home)
			"ground":
				_look(inv.areas.filter(func(a): return a.name == "Ghost Train")[0].at, 20.0, home)
			"phone":
				_look(home + Vector3(0, 3, 0), 12.0, home + Vector3(0, 0, -10))
				arena.phone.open()
			_:
				_look(_mid(_riders(ride_of[name])), 16.0, home)       # (near enough for them to be made, not so near they get off)
		step += 1
		f = 0
		return false
	match name:
		"carousel":
			if f < 12:
				return false
		"ground":
			if f < 300:
				return false
			if f > 300 and f < 304:
				return false
			# (they've come in round you and walked up: turned to face the nearest)
			var gs := inv._ground.filter(func(b): return is_instance_valid(b) and b.alive)
			var me := arena.player.global_position
			gs.sort_custom(func(x, y): return x.global_position.distance_to(me) < y.global_position.distance_to(me))
			print("ground: ", gs.size(), " about, the nearest ", ("%.1f m" % gs[0].global_position.distance_to(me)) if not gs.is_empty() else "-")
			if not gs.is_empty():
				var to: Vector3 = gs[0].global_position + Vector3(0, 1.0, 0) - (me + Vector3(0, 1.7, 0))
				sk._put(me, atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
			if f == 300:
				return false                      # (a few frames for the view to turn)
		"phone":
			if f < 4:
				return false
		_:
			if f < 8:
				return false
			var rs := _riders(ride_of[name]).filter(func(r): return r.body != null and is_instance_valid(r.body))
			if name == "wheel":
				rs.sort_custom(func(a, b): return inv._seat_xf(a).origin.y < inv._seat_xf(b).origin.y)
			if rs.size() > 1 and inv._seat_xf(rs[0]).origin.distance_to(inv._seat_xf(rs[1]).origin) < 2.5:
				_close(rs.slice(0, 2), 3.6)
			else:
				_close(rs.slice(0, 1), 3.2)
			print(name, ": ", rs.size(), " riders made; the first a ", rs[0].kind if not rs.is_empty() else "-")
	_save(name)
	step += 1
	f = 0
	return false
