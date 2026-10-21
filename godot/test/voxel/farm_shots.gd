extends SceneTree
## Screenshots of Stage 5 (not headless: under a display, e.g. xvfb-run): hoed rows with every strain at every stage,
## dry and wilted ones, the seed crate, the buyer, the water tank and the worm farm, the can pouring, the hoe.
## -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"

# [name, player position, yaw, pitch, tool, pouring]
const SHOTS := [
	["farm_rows", Vector3(11.4, 0, 33.2), 0.25, -0.42, "hoe", false],
	["farm_ready", Vector3(13.6, 0, 27.4), 0.6, -0.3, "can", false],
	["farm_props", Vector3(14.0, 0, 27.0), PI * 0.82, -0.12, "can", false],
	["farm_wormery", Vector3(8.4, 0, 36.8), PI * 1.25, -0.35, "can", false],
	["farm_pour", Vector3(11.3, 0, 31.2), 0.0, -0.55, "can", true],
	["farm_topdown", Vector3(12.0, 0, 30.0), 0.0, 0.0, "hoe", false],
]

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

func _tool(id: String) -> void:
	var i: int = arena.loadout.index_of(id)
	arena._switch(func(): arena.loadout.select(i))
	arena.loadout.switch_t = 0.0

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var farm: VoxelFarm = arena.yard.farm
	if step == 0:
		arena.frozen = true
		for b in arena.bodies:
			b.queue_free()
		arena.bodies.clear()
		arena.spawn(1)
		for b in arena.bodies:
			b.position = Vector3(0, 0, -15)
		# six rows (one a strain), four spots each (the stages), and a dry and a wilted one at the end
		var base := farm.spot_of(Vector3(10.0, 0, 28.0))
		for s in 6:
			var keys := []
			for k in 6:
				keys.append(base + s * 2000 + k)
			arena.yard.till(keys)
			for k in 4:
				farm.plants[base + s * 2000 + k] = {"s": s, "g": [0.1, 0.35, 0.7, 1.0][k], "wet": 100.0, "dry": 0.0, "wilt": 0, "fed": 0}
			farm.plants[base + s * 2000 + 4] = {"s": s, "g": 0.7, "wet": 0.0, "dry": 10.0, "wilt": 0, "fed": 0}
			farm.plants[base + s * 2000 + 5] = {"s": s, "g": 0.7, "wet": 0.0, "dry": 200.0, "wilt": 1, "fed": 0}
		arena.yard.ground.finish()
		_setup_shot(0)
		mark = t
		step = 1
		return false
	var k2 := (step - 1) / 2
	if k2 >= SHOTS.size():
		return t - mark > 0.5
	if (step - 1) % 2 == 0:
		if t - mark > 1.0:
			_shot(SHOTS[k2][0])
			mark = t
			step += 1
	elif t - mark > 0.3:
		var can = arena.melee.get("can")
		if can:
			can.release(MOUSE_BUTTON_LEFT)
		if k2 + 1 < SHOTS.size():
			_setup_shot(k2 + 1)
		mark = t
		step += 1
	return false

func _setup_shot(k: int) -> void:
	var s: Array = SHOTS[k]
	arena.top_down = s[0] == "farm_topdown"
	_tool(s[4])
	arena.player.global_position = s[1]
	arena.player.reset_physics_interpolation()
	arena.look_yaw = s[2]
	arena.look_pitch = s[3]
	if s[5]:
		arena.melee.can.water = VoxelFarm.CAN
		arena.melee.can.press(MOUSE_BUTTON_LEFT)
