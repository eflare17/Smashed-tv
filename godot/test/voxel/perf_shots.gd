extends SceneTree
## The same views on the Low preset and on High, to check that what the phone gets still looks like the game (under a
## display; software rendering is about a frame a second, so this scripts every shot):
##   xvfb-run -a -s "-screen 0 1280x720x24" /root/godot/godot --path godot --rendering-method gl_compatibility \
##     --resolution 1280x720 --fixed-fps 60 -s res://test/voxel/perf_shots.gd
## into integration/perf_shots/<view>_<preset>.png: the arena from the middle looking at the house, a chest with its
## padlock close up (the boxes joined into one mesh a material), Luna Park's forecourt, the Carousel (Low rides the
## horse cut down to 3,800 triangles), and the dirt strip along the park wall (Low draws it as a flat band past 60 m).
## The renderer is the browser's, Compatibility, on purpose. Owned by the voxel phone-performance session.

const OUT := "res://integration/perf_shots/%s_%s.png"

var arena: VoxelArena
var sk: VoxelStKilda
var busy := false
var done := false
var t := 0.0

func _initialize() -> void:
	seed(20261125)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://integration/perf_shots"))
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if busy:
		return done
	if t < 2.0 or arena.debris == null:
		return false
	busy = true
	_run()
	return false

func _run() -> void:
	arena.godmode = true
	VoxelBody.immortal = true
	arena.frozen = true                      # (the fight still: the same picture both times)
	sk = arena.stkilda
	sk.go()
	for preset in ["low", "high"]:
		arena.settings_menu.s.set_preset(preset)
		arena.settings_menu.s.apply(arena)
		sk.go()
		sk.stand("0,0,0")
		await _shot("luna_forecourt", preset)
		sk.stand_by_carousel()
		await _shot("luna_carousel", preset)
		_along_the_dirt()
		await _shot("luna_dirt", preset)
		sk.home()
		_face(Vector3(0, 0, 10), PI)             # (the arena's heaviest view: the middle, looking at the house)
		await _shot("arena_house", preset)
		_at_a_chest()
		await _shot("arena_chest", preset)
	print("PASS")
	done = true

## Stood on the strip of diggable dirt, looking along the park wall (the flat band runs off into the distance).
func _along_the_dirt() -> void:
	var best: Array = sk.dirt.cuts[0]
	for c in sk.dirt.cuts:                   # (the run of wall with the most dirt along it)
		if float(c[2]) > float(best[2]):
			best = c
	var o: Vector2 = best[0]
	var d: Vector2 = best[1]
	var across := Vector2(-d.y, d.x) * 2.0   # (stood off the wall's line, on the dirt)
	var p := o + d * 1.5 + across
	var at := sk.global_transform * Vector3(p.x, 0.05, p.y)
	var look := sk.global_transform * Vector3(p.x + d.x * 40.0, 0.0, p.y + d.y * 40.0)
	_stand(at, look)

## Two metres in front of a chest with its padlock on, looking at it.
func _at_a_chest() -> void:
	for st: VoxelStorage in arena.stash.list:
		if st.kind != "chest":
			continue
		st.set_lock(true, true)
		var mid := st.global_position + Vector3(0, 0.3, 0)
		var front := st.front()
		var at := mid + (front - mid).normalized() * 1.4
		_stand(Vector3(at.x, 0.05, at.z), mid)
		return

func _face(at: Vector3, yaw: float) -> void:
	arena.player.global_position = at
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = -0.1

func _stand(at: Vector3, look: Vector3) -> void:
	var to := look - (at + Vector3(0, 1.7, 0))
	arena.player.global_position = at
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _shot(name: String, preset: String) -> void:
	for i in 12:                             # (the view's meshes made, the levels of detail settled)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT % [name, preset]))
	print("SHOT ", name, " ", preset)
