extends SceneTree
## Screenshots of Stage 4 (not headless: under a display, e.g. xvfb-run): the yard, a hole dug down through the
## layers (dirt, clay, stone, rock, gold), the shovels (rusty, golden) and the pick in hand, a worm, from above.
## -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

func _tool(id: String, tier := 0) -> void:
	var i: int = arena.loadout.index_of(id)
	arena._switch(func(): arena.loadout.select(i))
	arena.loadout.switch_t = 0.0
	arena.set_shovel_tier(tier)

# [name, player position, yaw, pitch, tool, tier, top-down]
const SHOTS := [
	["dig_backdoor", Vector3(12.7, 0, 19.0), PI, -0.05, "shovel", 0, false],
	["dig_yard", Vector3(13.5, 0, 24.2), PI * 0.92, -0.38, "shovel", 0, false],
	["dig_pit", Vector3(12.2, 0, 33.0), 0.0, -0.95, "shovel", 1, false],
	["dig_golden_shovel", Vector3(15.6, 0, 30.2), 0.0, -0.55, "shovel", 2, false],
	["dig_pick", Vector3(13.0, 0, 33.0), PI * 0.6, -0.6, "pick", 0, false],
	["dig_worm", Vector3(15.3, 0, 26.4), 0.0, -1.0, "shovel", 0, false],
	["dig_topdown", Vector3(13.5, 0, 30.0), 0.0, 0.0, "shovel", 0, true],
]

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var g: VoxelTerrain = arena.yard.ground
	if step == 0:
		arena.frozen = true
		for b in arena.bodies:
			b.queue_free()
		arena.bodies.clear()
		# a stepped pit down through the layers, a trench, a few scoops
		for k in 7:
			g.dig(Vector3(11.0 + k * 0.35, -0.2 - k * 0.38, 31.0), 0.9 - k * 0.04, 4)
		for k in 10:
			g.dig(Vector3(15.0, -0.15, 27.0 + k * 0.25), 0.3, 2)
		g.dig(Vector3(17.5, -0.1, 34.0), 0.32, 2)
		g.dig(Vector3(18.2, -0.1, 33.6), 0.2, 2)
		g.finish()
		_setup_shot(0)
		mark = t
		step = 1
		return false
	var k := (step - 1) / 2
	if k >= SHOTS.size():
		return t - mark > 0.5
	if (step - 1) % 2 == 0:
		if t - mark > 1.0:
			_shot(SHOTS[k][0])
			mark = t
			step += 1
	elif t - mark > 0.3:
		if k + 1 < SHOTS.size():
			_setup_shot(k + 1)
		mark = t
		step += 1
	return false

func _setup_shot(k: int) -> void:
	var s: Array = SHOTS[k]
	arena.top_down = s[6]
	_tool(s[4], s[5])
	_place(s[1], s[2], s[3])
	if s[0] == "dig_worm":
		var w := VoxelWorm.new()
		arena.add_child(w)
		w.start(Vector3(15.3, 0.02, 25.6), arena.player)
		w._t = -2.0          # (wriggling a while longer, for the picture)
