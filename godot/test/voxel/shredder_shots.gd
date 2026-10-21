extends SceneTree
## Screenshots of Stage 6.5 (not headless: under a display, e.g. xvfb-run): the hand-crank mincer, the electric
## shredder and the industrial woodchipper grinding (blood spraying, bags on the pile), and a body burnt down to its
## bones by the flamethrower. -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
var burnt: VoxelBody
var _fire_t := 0.0
var _sweep := 0

# [name, player position, yaw, pitch, tier]
const SHOTS := [
	["shredder_mincer", Vector3(13.2, 0, 36.2), PI + 0.35, -0.3, 0],
	["shredder_shredder", Vector3(13.0, 0, 35.9), PI + 0.4, -0.25, 1],
	["shredder_chipper", Vector3(12.6, 0, 35.0), PI + 0.45, -0.2, 2],
	["shredder_burnt", Vector3(0, 0, 2.6), 0.0, -0.32, -1],
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
	var sh: VoxelShredder = arena.yard.shredder
	# the flamethrower held on it, sweeping across the chest and an arm (a tick of fire every 0.1 s)
	_fire_t += dt
	if burnt and is_instance_valid(burnt) and _fire_t >= 0.1 and step > 0:
		_fire_t = 0.0
		_sweep += 1
		var x := -0.28 + 0.56 * absf(fmod(_sweep * 0.037, 2.0) - 1.0)
		var y := 0.95 + 0.5 * absf(fmod(_sweep * 0.011, 2.0) - 1.0)
		var h := burnt.trace(Vector3(x, y, 1.0), Vector3(0, 0, -1), 2.0)
		if not h.is_empty():
			burnt.ignite(h.point, 0.085)
	if step == 0:
		arena.frozen = true
		for b in arena.bodies:
			b.queue_free()
		arena.bodies.clear()
		# a grunt set alight all over, left to burn (by the last shot: flesh gone to ash, the bones left)
		burnt = VoxelBody.new()
		arena.add_child(burnt)
		burnt.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
		burnt.position = Vector3(0, 0, 0)
		arena.bodies.append(burnt)
		burnt.hp = 1e9
		_setup_shot(0)
		mark = t
		step = 1
		return false
	var k2 := (step - 1) / 2
	if k2 >= SHOTS.size():
		return t - mark > 0.5
	if (step - 1) % 2 == 0:
		if t - mark > (1.0 if k2 < 3 else 30.0):
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
	var sh: VoxelShredder = arena.yard.shredder
	if int(s[4]) >= 0:
		sh.tier = int(s[4])
		sh._show_tier()
		sh.queue = {"meat": 900000}
		sh.bags = 3 + k * 2
		sh.ground = 40000.0 * (k + 1)
	else:
		sh.queue = {}
	arena.player.global_position = s[1]
	arena.player.reset_physics_interpolation()
	arena.look_yaw = s[2]
	arena.look_pitch = s[3]
