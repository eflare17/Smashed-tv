extends SceneTree
## The Carousel's horses face the way it turns (VoxelCarousel): each one's nose (its +x) along the way its pole moves
## as the ride turns. Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var t := 0.0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0:
		return false
	arena.stkilda.go()
	var spin := arena.stkilda.get_node("Carousel/Ride") as SkLunaRides.Spinner
	var worst := 1.0
	for h in spin.horses:
		var xf: Transform3D = h[2]
		var moving := (Basis(Vector3.UP, 0.01) * xf.origin - xf.origin).normalized()
		worst = minf(worst, (xf.basis * Vector3.RIGHT).normalized().dot(moving))
	var ok := worst > 0.99
	print(("ok   " if ok else "FAIL ") + "every horse faces the way it turns (worst %.3f)" % worst)
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true
