extends SceneTree
## How heavy the game is to run, measured the same way every time (the owner, 25 Nov: the browser game on a Galaxy S25
## "was a bit laggy"). A scripted route through the arena and through Luna Park, standing at fixed spots looking fixed
## ways, with a preset's settings on; at each spot it prints the frame time (p50 / p95 of the frames measured), what's
## in front of the camera (instances and draw calls in the view frustum, triangles) and, under a display, the
## renderer's own draw-call count. Nothing here is random: the same numbers come back, so a change can be shown to
## have helped.
##
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/voxel_perf_sweep.gd
##   ... -- --preset=low          just one preset (default: low and high)
##   ... -- --where=luna          just one place (arena / luna)
##   ... -- --ablate              Luna Park again with one group of things switched off at a time: what each costs
##   ... -- --frames=120          frames measured at each spot (default 90)
##
## Prints PASS or FAIL: FAIL if the route couldn't be walked (no Luna Park, no spots). The numbers themselves are for
## reading, not for passing: a phone's budget is 16.7 ms a frame and the arena/Luna lines say how much of that the game
## code alone takes. Owned by the voxel phone-performance session.

const SPOTS := {
	# the arena: stood in the middle and at the yard end, looking each way (the house, the farm, the open floor)
	"arena": [
		["middle, at the house", Vector3(0, 0, 10), 0.0],
		["middle, looking away", Vector3(0, 0, 10), PI],
		["middle, looking right", Vector3(0, 0, 10), PI * 0.5],
		["the yard end", Vector3(0, 0, 24), 0.0],
	],
	# Luna Park: dx,dz,yaw from where you arrive (facing Mr Moon's face), as --stkilda= takes
	"luna": [
		["the forecourt, at Mr Moon", "0,0,0"],
		["through the mouth", "0,-14,0"],
		["among the rides", "4,-46,0"],
		["the back of the park", "0,-70,160"],
		["out on the Esplanade", "0,26,135"],
	],
}
## --ablate: what's switched off, one at a time (node name under Luna Park, or a group of them)
const ABLATE := [
	["the crowd", ["SkCrowd"]],
	["the flags", ["SkParkFlags"]],
	["the ride lights", ["SkRideLights"]],
	["the rides turning", ["Carousel", "GhostTrain", "ArabianMerry", "MoonBalloons", "Spider", "SkyRider", "PowerSurge",
		"Supernova", "PharaohsCurse", "ConeyDrop", "SkScenicRailway"]],
	["the town", ["Town"]],
]

var arena: VoxelArena
var presets := ["low", "high"]
var where := ""
var frames := 90
var ablate := false
var fails := []
var lines := []                  # every row printed, for the summary at the end

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--preset="):
			presets = [x.trim_prefix("--preset=")]
		elif x.begins_with("--where="):
			where = x.trim_prefix("--where=")
		elif x.begins_with("--frames="):
			frames = int(x.trim_prefix("--frames="))
		elif x == "--ablate":
			ablate = true
	seed(20261125)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

# ================================================================ what's in front of the camera

## Everything the camera can see, counted by hand (the dummy renderer in --headless counts nothing): [instances,
## draw calls (a surface each, one for a whole MultiMesh), triangles, {group: draw calls}, {group: triangles}]
func _in_view() -> Array:
	var planes := arena.cam.get_frustum()
	var inst := 0
	var calls := 0
	var tris := 0
	var by := {}
	var by_tris := {}
	var heavy := {}                 # the single instances worth naming (over 20k triangles each)
	for n in _every_visual(arena):
		var vi := n[0] as VisualInstance3D
		var mesh: Mesh = null
		var many := 1
		if vi is MeshInstance3D:
			mesh = (vi as MeshInstance3D).mesh
		elif vi is MultiMeshInstance3D:
			var mm := (vi as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			many = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			if many <= 0:
				continue
		else:
			continue
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var box := vi.global_transform * vi.get_aabb()
		if not _seen(planes, box):
			continue
		if not _in_range(vi, box):
			continue
		var sc := mesh.get_surface_count()
		var t := _tris(mesh) * many
		if t > 20000:
			heavy[String(arena.get_path_to(vi))] = t
		inst += many
		calls += sc
		tris += t
		by[n[1]] = int(by.get(n[1], 0)) + sc
		by_tris[n[1]] = int(by_tris.get(n[1], 0)) + t
	return [inst, calls, tris, by, by_tris, heavy]

## A mesh's triangles (counted once and remembered: the same mesh is used over and over).
static var _tri_cache := {}
static func _tris(mesh: Mesh) -> int:
	var id := mesh.get_instance_id()
	if _tri_cache.has(id):
		return _tri_cache[id]
	var t := 0
	for i in mesh.get_surface_count():
		if mesh is ArrayMesh:
			var am := mesh as ArrayMesh
			var n := am.surface_get_array_index_len(i)
			t += (n if n > 0 else am.surface_get_array_len(i)) / 3
		else:
			var a := mesh.surface_get_arrays(i)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			t += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_tri_cache[id] = t
	return t

## Every visible VisualInstance3D under `n`, with the group it belongs to: the first two names down from the arena
## (so "StKilda/Town", "StKilda/Carousel", "Farm/Chickens"), which is what says where the drawing is going.
func _every_visual(n: Node, group := "") -> Array:
	var out := []
	for c in n.get_children():
		var g := group
		if g.count("/") < 2:
			g = (g + "/" if g != "" else "") + _label(c)
		if c is VisualInstance3D and (c as VisualInstance3D).is_visible_in_tree():
			out.append([c, g])
		out += _every_visual(c, g)
	return out

## A node's name, or where it has none of its own ("@Node3D@2013"), its script's or its class's.
static func _label(n: Node) -> String:
	var nm := String(n.name)
	if not nm.begins_with("@"):
		return nm
	var s := n.get_script() as Script
	return s.resource_path.get_file().get_basename() if s else n.get_class()

## Is it near enough, and far enough, to be drawn (its visibility range: the far scenery and the levels of detail)?
func _in_range(vi: VisualInstance3D, box: AABB) -> bool:
	var g := vi as GeometryInstance3D
	if g == null:
		return true
	var d := arena.cam.global_position.distance_to(box.get_center())
	if g.visibility_range_end > 0.0 and d > g.visibility_range_end + g.visibility_range_end_margin:
		return false
	return not (g.visibility_range_begin > 0.0 and d < g.visibility_range_begin - g.visibility_range_begin_margin)

## Is any of this box on the camera's side of every one of the frustum's planes?
static func _seen(planes: Array[Plane], box: AABB) -> bool:
	for p in planes:
		var out := true
		for i in 8:
			if p.distance_to(box.get_endpoint(i)) <= 0.0:
				out = false
				break
		if out:
			return false
	return true

# ================================================================ the route

var _t := 0.0
var busy := false
var done := false

# (the route is one long coroutine of its own: _process must give back a bool every frame, so it starts it and waits)
func _process(dt: float) -> bool:
	_t += dt
	if busy:
		return done
	if _t < 2.0 or arena.debris == null:
		return false
	arena.godmode = true
	VoxelBody.immortal = true
	busy = true
	_run()
	return false

func _run() -> void:
	# a lap of both places first, with nothing measured: Luna Park is built, every view's meshes are made and the
	# meshing jobs that a preset's cube size sets off are finished, so the first place measured isn't charged for it
	for p in ["low", "high"]:
		arena.settings_menu.s.set_preset(p)
		arena.settings_menu.s.apply(arena)
		arena.stkilda.go()
		for spot in SPOTS.luna:
			_stand("luna", spot)
			await _settle()
		arena.stkilda.home()
		for spot in SPOTS.arena:
			_stand("arena", spot)
			await _settle()
	print("SWEEP (warmed up)")
	for p in presets:
		if where != "luna":
			await _place("arena", p, "")
		if where != "arena":
			await _place("luna", p, "")
	if ablate:
		for a in ABLATE:
			await _place("luna", presets[0], a[0], a[1])
	print("SWEEP ==================================================== the lot")
	for l in lines:
		print("SWEEP ", l)
	print("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	done = true

## One place with one preset on: each spot measured in turn. `off_name` / `off`: the ablation run, with those nodes
## switched off (hidden and not processed) the whole way round.
func _place(place: String, preset: String, off_name: String, off: Array = []) -> void:
	var s := arena.settings_menu.s
	s.set_preset(preset)
	s.apply(arena)
	if place == "luna":
		if not arena.stkilda.active:
			arena.stkilda.go()
	elif arena.stkilda.active:
		arena.stkilda.home()
	var hidden := []
	for nm in off:
		var n := arena.stkilda.get_node_or_null(NodePath(nm)) as Node3D
		if n:
			hidden.append([n, n.visible, n.process_mode])
			n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var tag := "%s %s" % [place, preset]
	if off_name != "":
		tag += " / without %s" % off_name
		_check(not hidden.is_empty(), "%s: found it to switch off" % tag)
	var all := []                                   # every frame measured in this place
	var rows := []
	_check(not SPOTS[place].is_empty(), "%s: spots to stand at" % tag)
	for spot in SPOTS[place]:
		_stand(place, spot)
		await _settle()
		var ms := await _measure()
		all += ms
		var v := _in_view()
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var row := "  %-24s p50 %5.1f ms  p95 %5.1f ms   in view: %5d instances, %4d draw calls, %s tris%s" % [
			spot[0], _pct(ms, 50), _pct(ms, 95), v[0], v[1], _k(v[2]),
			"   renderer draw calls %d" % draws if draws > 0 else ""]
		rows.append(row)
		if off_name == "":
			rows.append("      draw calls by group: " + _by(v[3], false))
			rows.append("      triangles by group:  " + _by(v[4], true))
			if not v[5].is_empty():
				rows.append("      the heaviest meshes: " + _by(v[5], true))
	lines.append("%-34s p50 %5.1f ms  p95 %5.1f ms   (the whole route)" % [tag, _pct(all, 50), _pct(all, 95)])
	print("SWEEP ", lines[-1])
	for r in rows:
		print("SWEEP ", r)
		if off_name == "":
			lines.append(r)
	for h in hidden:
		(h[0] as Node3D).visible = h[1]
		(h[0] as Node).process_mode = h[2]

func _stand(place: String, spot: Array) -> void:
	if place == "luna":
		arena.stkilda.stand(spot[1])
		return
	arena.player.global_position = spot[1]
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = spot[2]
	arena.look_pitch = -0.1

## A moment stood there before the clock starts: the view's meshes made, the rides caught up, the first frames' spikes
## (shaders, buffers) left out of the numbers.
func _settle() -> void:
	for i in 24:
		await process_frame

## The frame times (ms) of the next `frames` frames.
func _measure() -> Array:
	var out := []
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		out.append(float(now - last) / 1000.0)
		last = now
	return out

static func _pct(a: Array, p: int) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(round(float(p) / 100.0 * (s.size() - 1))), 0, s.size() - 1)]

static func _k(n: int) -> String:
	return "%.0fk" % (n / 1000.0) if n >= 1000 else str(n)

## The groups costing the most, biggest first.
static func _by(by: Dictionary, thousands: bool) -> String:
	var ks := by.keys()
	ks.sort_custom(func(a, b): return int(by[a]) > int(by[b]))
	var out := []
	for k in ks.slice(0, 8):
		out.append("%s %s" % [k, _k(by[k]) if thousands else str(by[k])])
	return ", ".join(out)
