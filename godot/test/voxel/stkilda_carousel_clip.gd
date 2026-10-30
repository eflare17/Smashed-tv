extends SceneTree
## A clip (with --write-movie): walking slowly round the made-over Carousel (VoxelCarousel) as it turns, by day, then
## the same at night. Owned by the St Kilda session.

const ROUND := 9.0          # seconds each way round
const FAR := 10.5           # how far out from its middle
var arena: VoxelArena
var sk: VoxelStKilda
var car: Node3D
var t := 0.0
var step := 0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _look(a: float) -> void:
	var mid := car.global_position
	var at := mid + Vector3(cos(a), 0, sin(a)) * FAR
	var to := mid + Vector3(0, 2.3, 0) - (at + Vector3(0, 1.7, 0))
	sk._put(Vector3(at.x, 0.05, at.z), atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 and step == 0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			car = sk.get_node("Carousel") as Node3D
			arena.loadout.select(arena.loadout.index_of("hammer"))
			step = 1
			t = 0.0
		1, 2:
			_look(0.3 + t / ROUND * PI * 0.9)
			if t > ROUND:
				if step == 1:
					sk.day_night.toggle()
					step = 2
					t = 0.0
				else:
					quit(0)
	return false
