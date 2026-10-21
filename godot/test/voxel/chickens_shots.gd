extends SceneTree
## Screenshots of Stage 6 (not headless: under a display, e.g. xvfb-run): the run and the coop from the yard through
## the open gate, the coop's door and sign, inside (the nest boxes with eggs, the feeder, the perches), the hens close
## up, chicks, poo, from above. -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"

# [name, player position, yaw, pitch]
const SHOTS := [
	["chickens_gate", Vector3(20.0, 0, 30.5), -PI * 0.5, -0.12],
	["chickens_run", Vector3(23.6, 0, 24.2), PI * 0.82, -0.18],
	["chickens_door", Vector3(29.3, 0, 31.2), PI, -0.05],
	["chickens_nests", Vector3(28.6, 0, 36.6), -PI * 0.5 - 0.2, -0.3],
	["chickens_feeder", Vector3(30.0, 0, 37.8), PI * 0.25, -0.35],
	["chickens_close", Vector3(25.0, 0, 27.6), PI * 0.75, -0.45],
	["chickens_topdown", Vector3(26.0, 0, 31.0), 0.0, 0.0],
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

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var ch: VoxelChickens = arena.yard.chickens
	if step == 0:
		arena.frozen = true
		for b in arena.bodies:
			b.queue_free()
		arena.bodies.clear()
		ch.level = 2
		ch.gate = true
		ch.food = 40.0
		ch.hens.clear()
		var spots := [Vector2(24.5, 26.5), Vector2(25.3, 27.0), Vector2(24.2, 27.8), Vector2(26.0, 26.0), Vector2(25.6, 28.2),
			Vector2(29.5, 37.0), Vector2(28.8, 38.5), Vector2(30.2, 36.0), Vector2(19.5, 31.0), Vector2(18.0, 29.0), Vector2(24.8, 25.6)]
		for i in spots.size():
			var h: Dictionary = ch._hatch(spots[i], 1.0 if i < 8 else 0.2, i % 3)
			h.full = 0.9
			h.t = 999.0               # (standing still for the pictures)
			h.st = "peck" if i % 2 == 0 else "idle"
		for k in 6:
			for e in [0.2, 0.5, 0.9].slice(0, k % 3 + 1):
				(ch.nests[k] as Array).append(e)
		for i in 5:
			arena.debris.plop(Vector3(24.0 + i * 0.5, 0.1, 26.0 + (i % 2) * 1.2), VoxelChickens.POO, 8, i + 1)
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
		if k2 + 1 < SHOTS.size():
			_setup_shot(k2 + 1)
		mark = t
		step += 1
	return false

func _setup_shot(k: int) -> void:
	var s: Array = SHOTS[k]
	arena.top_down = s[0] == "chickens_topdown"
	arena.player.global_position = s[1]
	arena.player.reset_physics_interpolation()
	arena.look_yaw = s[2]
	arena.look_pitch = s[3]
