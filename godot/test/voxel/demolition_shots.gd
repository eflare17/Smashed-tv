extends SceneTree
## Pictures of Demolition (under a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" /root/godot/godot --path godot --resolution 1280x720 --fixed-fps 60 \
##     -s res://test/voxel/demolition_shots.gd
## into integration/demolition_shots/demolition_*.png: the street before anything's touched, the block half down, the
## crane with its ball alongside a building, and the tower block coming down. (-- --only=name: just that one.)
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
			# the street, nothing touched: down it from the west end, the crane parked on the road
			_stand(D.AT + Vector3(-38.0, 0.05, 7.0), D.AT + Vector3(2.0, 5.0, -4.0))
			step = 2
			t = 0.0
		2:
			_save("street")
			step = 3
			t = 0.0
		3:
			# the crane: swung round with the ball out over the road, the office behind it
			dem.crane.place(D.AT + Vector3(-2.0, 0.0, -1.0), -PI / 2.0 - 0.5)
			dem.crane.cable = 6.0
			_stand(D.AT + Vector3(-13.0, 0.05, 12.0), D.AT + Vector3(2.0, 7.0, -3.0))
			step = 4
			t = 0.0
		4:
			if t < 0.4:
				return false
			_save("crane")
			step = 5
			t = 0.0
		5:
			# the block half down: holes in the shop and the office, the water tower's legs out
			var shop := _of("BrickShop")
			for c in [2, 5, 8]:
				dem.breaks.blast(_wall(shop, c, 1.4), 2.4)
			var office := _of("Office")
			for c in [30, 34, 38]:
				dem.breaks.blast(_wall(office, c, 2.0), 2.6)
			var tank := _of("WaterTower")
			for k in 2:
				var a: Vector2 = tank.ring[k]
				dem.breaks.blast(Vector3(a.x, 1.4, a.y), 2.8)
			step = 6
			t = 0.0
		6:
			if t < 1.2:
				return false
			_stand(D.AT + Vector3(-10.0, 0.05, 2.0), D.AT + Vector3(-2.0, 4.0, -10.0))
			step = 7
			t = 0.0
		7:
			_save("smash")
			step = 8
			t = 0.0
		8:
			# the tower block: its ground floor taken out, five storeys coming down on top of it
			var tower := _of("TowerBlock")
			for c in [2, 5, 8, 11]:
				dem.breaks.blast(_wall(tower, c, 1.2), 2.8)
			for c in [14, 17, 20]:
				dem.breaks.blast(_wall(tower, c, 1.2), 2.8)
			_stand(D.AT + Vector3(-18.0, 0.05, -6.0), D.AT + Vector3(-16.0, 7.0, 10.0))
			step = 9
			t = 0.0
		9:
			if t < 0.45:
				return false
			_save("tower")
			step = 10
			t = 0.0
		10:
			print("SHOTS done (%d%% down, %d blocks)" % [roundi(dem.share() * 100.0), dem.down()])
			quit(0)
	return false
