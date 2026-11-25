extends SceneTree
## Pictures of Demolition (under a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" /root/godot/godot --path godot --resolution 1280x720 --fixed-fps 60 \
##     -s res://test/voxel/demolition_shots.gd
## into integration/demolition_shots/demolition_*.png: the street before anything's touched, the block half down, the
## crane with its ball alongside a building, the tower block coming down, the enemies stationed on the office's roof and
## in its windows, the office coming down under them, and the petrol station's chain going off. (-- --only=name: just
## that one.)
## Owned by the Demolition session.

const D := preload("res://scripts/voxel/demolition/voxel_demolition.gd")
const OUT := "res://integration/demolition_shots/demolition_%s.png"

var arena: VoxelArena
var dem: VoxelDemolition
var t := 0.0
var step := 0
var busy := false
var only := ""

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--only="):
			only = x.trim_prefix("--only=")
	seed(20261125)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://integration/demolition_shots"))
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _save(nm: String) -> void:
	if only != "" and only != nm:
		return
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT % nm))
	print("SHOT ", nm)
	busy = false

# stood at `at`, looking at `look`
func _stand(at: Vector3, look: Vector3) -> void:
	var to := look - (at + Vector3(0, 1.7, 0))
	arena.player.global_position = at
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _of(nm: String) -> VoxelBreakables.Building:
	for b in dem.breaks.list:
		if String(b.data.id) == nm:
			return b
	return null

# enemies on every post of one kind on a building (the pictures: who's on the roof, who's in the windows)
func _man(nm: String, kind: int) -> int:
	var n := 0
	for p in dem.mob.posts:
		if int(p.kind) == kind and String(dem.breaks.list[int(p.bi)].data.id) == nm and not bool(p.taken):
			dem.mob.fill(p)
			n += 1
	return n

func _wall(b: VoxelBreakables.Building, c: int, y: float) -> Vector3:
	var n: Vector2 = b.cols[c].n
	var at: Vector3 = b.block_at(c, 0)
	return Vector3(at.x + n.x * 0.3, y, at.z + n.y * 0.3)

func _process(dt: float) -> bool:
	t += dt
	if busy or t < 2.0:
		return false
	match step:
		0:
			arena.waves.queue.clear()
			arena.godmode = true
			arena.demolition.go()
			dem = arena.demolition
			dem._hud.visible = true
			step = 1
			t = 0.0
		1:
			if t < 0.3:
				return false
			# the street, nothing touched: straight down the road from its west end, the crane parked on it
			dem.crane.place(D.AT + D.CRANE_AT, -PI / 2.0, 0.8)   # (the boom swung out, so you can see what it is)
			_stand(D.AT + Vector3(-34.0, 0.05, 0.0), D.AT + Vector3(12.0, 4.5, -1.0))
			step = 2
			t = 0.0
		2:
			_save("street")
			step = 3
			t = 0.0
		3:
			# the crane: out in the street, the boom round over the north footpath, the ball hanging off it
			dem.crane.place(D.AT + Vector3(-6.0, 0.0, 1.0), -PI / 2.0, 0.6)
			_stand(D.AT + Vector3(-20.0, 0.05, 2.0), D.AT + Vector3(0.0, 6.0, -4.0))
			step = 4
			t = 0.0
		4:
			if t < 0.4:
				return false
			_save("crane")
			step = 5
			t = 0.0
		5:
			# the block half down: the crane out of the way, then holes in four of them and the water tower's legs out
			dem.crane.place(D.AT + Vector3(46.0, 0.0, 0.0), -PI / 2.0)
			# (the walls that face the road, so the holes show from it: the third side of a north-row building, the
			# first of a south-row one -- a ring runs x0,z0 -> x1,z0 -> x1,z1 -> x0,z1)
			for c in [25, 28, 31]:
				dem.breaks.blast(_wall(_of("BrickShop"), c, 1.4), 2.6)
			for c in [21, 24, 27]:
				dem.breaks.blast(_wall(_of("CornerShop"), c, 1.4), 2.6)
			for c in [30, 34, 38]:
				dem.breaks.blast(_wall(_of("Office"), c, 2.2), 2.8)
			for c in [2, 6]:
				dem.breaks.blast(_wall(_of("LockUps"), c, 1.4), 2.4)
			var tank := _of("WaterTower")
			for k in 2:
				var a: Vector2 = tank.ring[k]
				dem.breaks.blast(Vector3(a.x, 1.4, a.y), 2.8)
			step = 6
			t = 0.0
		6:
			if t < 1.4:
				return false
			_stand(D.AT + Vector3(-34.0, 0.05, 0.0), D.AT + Vector3(12.0, 4.5, -1.0))     # (the street shot again)
			step = 7
			t = 0.0
		7:
			_save("smash")
			step = 8
			t = 0.0
		8:
			# the tower block: its ground floor taken out all round, five storeys coming down on top of it
			var tower := _of("TowerBlock")
			for c in [2, 5, 8, 11, 14, 17, 20, 23]:
				dem.breaks.blast(_wall(tower, c, 1.2), 2.8)
			_stand(D.AT + Vector3(6.0, 0.05, -1.0), D.AT + Vector3(-16.0, 9.0, 12.0))
			step = 9
			t = 0.0
		9:
			if t < 0.5:
				return false
			_save("tower")
			step = 10
			t = 0.0
		10:
			# phase B. The block as new again, and enemies stationed on the office: three on its roof, three in the
			# windows of its upper storeys (VoxelDemolitionMob's posts are its roof tiles and its glazed blocks)
			dem.start()
			dem.crane.place(D.AT + Vector3(46.0, 0.0, 0.0), -PI / 2.0)
			_man("Office", VoxelDemolitionMob.ROOF)
			_man("Office", VoxelDemolitionMob.WINDOW)
			_man("BrickShop", VoxelDemolitionMob.ROOF)
			dem.mob.made = dem.mob.most()      # (no more coming while the picture's taken: just these)
			_stand(D.AT + Vector3(-8.0, 0.05, 6.0), D.AT + Vector3(11.0, 8.0, -6.0))
			step = 11
			t = 0.0
		11:
			if t < 1.0:
				return false
			_save("enemies")
			step = 12
			t = 0.0
		12:
			# the office brought down under them: the sills of the windows they stand in blown out, the roof caved in
			var off := _of("Office")
			for c in [30, 34, 38]:
				dem.breaks.blast(_wall(off, c, 7.0), 3.0)
			for c in [30, 34, 38]:
				dem.breaks.blast(_wall(off, c, 4.0), 3.0)
			var mid := Vector2.ZERO
			for v in off.ring:
				mid += v
			mid /= off.ring.size()
			dem.breaks.blast(Vector3(mid.x, off.h - 0.2, mid.y), 5.0)
			_stand(D.AT + Vector3(-8.0, 0.05, 6.0), D.AT + Vector3(11.0, 7.0, -6.0))    # (the same spot, after)
			step = 13
			t = 0.0
		13:
			if t < 0.8:
				return false
			_save("collapse")
			step = 14
			t = 0.0
		14:
			# the petrol station's chain: the tanker in the road lit, and the pumps and the gas bottles with it. It
			# runs in under a second and this script's steps are 2 s apart, so the chain is stepped here, by hand, to
			# the moment the picture wants: the tanker and the pumps gone up, the fire still in the air.
			dem.props.reset()
			for i in dem.props.list.size():
				if String(dem.props.list[i].kind) == "tanker":
					dem.props.light(i, 0.0)
			_stand(D.AT + Vector3(2.0, 0.05, -1.5), D.AT + Vector3(12.0, 2.0, 9.0))
			for i in 40:
				dem.props.step(1.0 / 60.0)
			for i in 7:
				arena.flames._process(0.045)        # (the fire risen and spread a little: a ball, not a spark)
			_save("chain")
			step = 16
			t = 0.0
		16:
			print("SHOTS done (%d%% down, %d blocks, %d enemies, %d props gone off)" % [roundi(dem.share() * 100.0),
				dem.down(), dem.mob.mobs.size(), dem.props.booms])
			quit(0)
	return false
