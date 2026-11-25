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
##   ... -- --spin                stand still and swing the view right round instead of walking the route
##   ... -- --chars               what a block character costs to build and to draw, at each cube size
##   ... -- --far=260             the camera drawn no further than this (a phone's cap; the PC's is 4000 m)
##   ... -- --scenery=110         St Kilda's scenery kept in full this far out (the "Scenery detail" setting)
##
## --spin (the owner, 25 Nov: "when I move the camera it lags"): stood on one spot, the view turned 15 degrees at a
## time all the way round, a handful of frames measured at each step and NOT settled first -- the frame right after
## the view moves is the one that hitches, so it has to be counted, not waited out. It prints the worst frame and the
## p99 as well as the p50, because a stutter is a spike and an average hides it, and it does two laps: the first lap
## sees everything for the first time (first-sight work shows up there), the second sees it all again (anything still
## spiking on lap two happens every time the view moves). It also says how many instances came newly into view at
## each step, so a spike can be read against what caused it.
##
## --walk (the owner, 25 Nov: "it only seems to stutter when I'm using both sticks"): the same ground covered three
## ways from the same spot -- walking straight ahead with the view still, standing still and turning the view, and both
## at once -- so the two can be told apart from the pair. Each step moves and/or turns and then measures straight away,
## as --spin does, and says how many instances came newly into view, because walking while turning sweeps new scenery
## in faster than either alone. If the game code spikes here it is the game code; if it does not and the browser still
## stutters with two thumbs down, it is the drawing or the browser's own input, not the logic.
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
	["the ride lights", ["RideSpill", "NightPools"]],
	["the rides turning", ["Carousel", "GhostTrain", "ArabianMerry", "MoonBalloons", "Spider", "SkyRider", "PowerSurge",
		"Supernova", "PharaohsCurse", "ConeyDrop", "SkScenicRailway"]],
	["the town", ["Town"]],
]
## --spin: where to stand and turn the view right round (the same spots the route starts from)
const SPIN := {
	"arena": [["the middle of the arena", Vector3(0, 0, 10), 0.0]],
	"luna": [["Luna Park's forecourt", "0,0,0"], ["among the rides", "4,-46,0"]],
}
const SPIN_STEP := 15.0          # degrees the view turns between measurements
const SPIN_FRAMES := 8           # frames measured at each step (not settled first: the hitch is in the first one)
## --walk: from each of the SPIN spots, 24 steps of this much (a step is about what 4.5 m/s walking covers in the 8
## frames measured, and the turn is the same per-step turn --spin uses)
const WALK_STEP := 0.6           # metres forward a step
const WALK_STEPS := 24
const WALK_WAYS := ["the left stick alone (walking, view still)", "the look drag alone (turning on the spot)",
	"both at once (walking and turning)"]

var arena: VoxelArena
var presets := ["low", "high"]
var where := ""
var frames := 90
var ablate := false
var spin := false
var chars := false
var walk := false
var far := 0.0                   # --far=: the camera's far plane after the preset is on (0: leave it)
var scen := -1.0                 # --scenery=: how far St Kilda's scenery stays in full (-1: leave it)
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
		elif x == "--spin":
			spin = true
		elif x == "--chars":
			chars = true
		elif x == "--walk":
			walk = true
		elif x.begins_with("--far="):
			far = float(x.trim_prefix("--far="))
		elif x.begins_with("--scenery="):
			scen = float(x.trim_prefix("--scenery="))
	seed(20261125)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

## --far= / --scenery=: the phone's two caps put on after a preset is applied, so the pair can be weighed without
## pretending to be a phone (apply() only caps a real one). The far plane shortens the frustum everything is counted
## against; the scenery distance is what St Kilda's dirt and rides go flat past.
func _caps() -> void:
	if far > 0.0:
		arena.cam.far = far
	if scen >= 0.0:
		VoxelParkDirt.detail_m = scen
		if arena.get("stkilda") and arena.stkilda:
			arena.stkilda.scenery(scen)

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
	if chars:
		await _chars_run()
		return
	if spin:
		await _spin_run()
		return
	if walk:
		await _walk_run()
		return
	# a lap of both places first, with nothing measured: Luna Park is built, every view's meshes are made and the
	# meshing jobs that a preset's cube size sets off are finished, so the first place measured isn't charged for it
	for p in ["low", "high"]:
		arena.settings_menu.s.set_preset(p)
		arena.settings_menu.s.apply(arena)
		_caps()
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
	_caps()
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

# ================================================================ --spin: turning the view on the spot

func _spin_run() -> void:
	# Luna Park built and both presets' meshes made before anything is measured, so lap one is charged for first
	# SIGHT of things, not for the park being built at all
	for p in ["low", "high"]:
		arena.settings_menu.s.set_preset(p)
		arena.settings_menu.s.apply(arena)
		_caps()
		arena.stkilda.go()
		_stand("luna", SPIN.luna[0])
		await _settle()
		arena.stkilda.home()
		_stand("arena", SPIN.arena[0])
		await _settle()
	print("SPIN (the park built, the presets' meshes made)")
	for p in presets:
		if where != "luna":
			await _spin_place("arena", p)
		if where != "arena":
			await _spin_place("luna", p)
	print("SPIN ==================================================== the lot")
	for l in lines:
		print("SPIN ", l)
	print("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	done = true

func _spin_place(place: String, preset: String) -> void:
	var s := arena.settings_menu.s
	s.set_preset(preset)
	s.apply(arena)
	_caps()
	if place == "luna":
		if not arena.stkilda.active:
			arena.stkilda.go()
	elif arena.stkilda.active:
		arena.stkilda.home()
	_check(not SPIN[place].is_empty(), "%s %s: spots to spin at" % [place, preset])
	for spot in SPIN[place]:
		_stand(place, spot)
		arena.look_pitch = -0.1
		await _settle()
		var start: float = arena.look_yaw
		for lap in 2:
			await _spin_lap("%s %s / %s" % [place, preset, spot[0]], lap, start)

## One lap: the view set SPIN_STEP degrees further round each step, SPIN_FRAMES frames measured straight away.
func _spin_lap(tag: String, lap: int, start: float) -> void:
	var steps := int(round(360.0 / SPIN_STEP))
	var all := []
	var firsts := []                 # the frame right after each turn
	var worst := [0.0, 0, 0]         # [ms, step, newly in view]
	var seen := _visible_set()
	for i in steps:
		arena.look_yaw = start + deg_to_rad(SPIN_STEP * (i + 1))
		var ms := []
		var last := Time.get_ticks_usec()
		for f in SPIN_FRAMES:
			await process_frame
			var now := Time.get_ticks_usec()
			ms.append(float(now - last) / 1000.0)
			last = now
		var now_seen := _visible_set()
		var fresh := 0
		for k in now_seen:
			if not seen.has(k):
				fresh += 1
		seen = now_seen
		all += ms
		firsts.append(ms[0])
		if ms[0] > worst[0]:
			worst = [ms[0], i, fresh]
	lines.append("%-46s lap %d  p50 %5.1f  p95 %5.1f  p99 %5.1f  worst %6.1f ms   (first frame after each turn: p50 %5.1f, worst %6.1f ms at step %d, %d newly in view)" % [
		tag, lap + 1, _pct(all, 50), _pct(all, 95), _pct(all, 99), _pct(all, 100),
		_pct(firsts, 50), worst[0], worst[1], worst[2]])
	print("SPIN ", lines[-1])

## What the camera can see now, as a set of node paths (for "newly in view").
func _visible_set() -> Dictionary:
	var planes := arena.cam.get_frustum()
	var out := {}
	for n in _every_visual(arena):
		var vi := n[0] as VisualInstance3D
		if not (vi is MeshInstance3D or vi is MultiMeshInstance3D):
			continue
		var box := vi.global_transform * vi.get_aabb()
		if not _seen(planes, box) or not _in_range(vi, box):
			continue
		out[vi.get_instance_id()] = true
	return out

# ================================================================ --walk: walking, turning, and both at once

func _walk_run() -> void:
	# the park built and both presets' meshes made first, so step one isn't charged for building the place
	for p in ["low", "high"]:
		arena.settings_menu.s.set_preset(p)
		arena.settings_menu.s.apply(arena)
		_caps()
		arena.stkilda.go()
		_stand("luna", SPIN.luna[0])
		await _settle()
		arena.stkilda.home()
		_stand("arena", SPIN.arena[0])
		await _settle()
	print("WALK (the park built, the presets' meshes made)")
	for p in presets:
		if where != "luna":
			await _walk_place("arena", p)
		if where != "arena":
			await _walk_place("luna", p)
	print("WALK ==================================================== the lot")
	for l in lines:
		print("WALK ", l)
	print("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	done = true

func _walk_place(place: String, preset: String) -> void:
	var s := arena.settings_menu.s
	s.set_preset(preset)
	s.apply(arena)
	_caps()
	if place == "luna":
		if not arena.stkilda.active:
			arena.stkilda.go()
	elif arena.stkilda.active:
		arena.stkilda.home()
	_check(not SPIN[place].is_empty(), "%s %s: spots to walk from" % [place, preset])
	for spot in SPIN[place]:
		for way in 3:
			# each way starts from the same place looking the same way, and every way is run twice: the second lap
			# has seen the ground before, so anything still spiking there happens every time
			for lap in 2:
				_stand(place, spot)
				arena.look_pitch = -0.1
				await _settle()
				await _walk_lap("%s %s / %s" % [place, preset, spot[0]], way, lap, place)

## One lap: WALK_STEPS steps of moving (way 0), turning (way 1) or both (way 2), SPIN_FRAMES frames measured straight
## after each one.
func _walk_lap(tag: String, way: int, lap: int, place: String) -> void:
	var start: float = arena.look_yaw
	var all := []
	var firsts := []                 # the frame right after each step
	var worst := [0.0, 0, 0]         # [ms, step, newly in view]
	var fresh_tot := 0
	var seen := _visible_set()
	for i in WALK_STEPS:
		var n := i + 1
		if way != 0:
			# the view turned, as --spin does; a walk-only lap keeps it where it started
			arena.look_yaw = start + deg_to_rad(SPIN_STEP * n)
		if way != 1:
			_walk_to(place, start, WALK_STEP * n)
		var ms := []
		var last := Time.get_ticks_usec()
		for f in SPIN_FRAMES:
			await process_frame
			var now := Time.get_ticks_usec()
			ms.append(float(now - last) / 1000.0)
			last = now
		var now_seen := _visible_set()
		var f2 := 0
		for k in now_seen:
			if not seen.has(k):
				f2 += 1
		seen = now_seen
		fresh_tot += f2
		all += ms
		firsts.append(ms[0])
		if ms[0] > worst[0]:
			worst = [ms[0], i, f2]
	lines.append("%-46s %-44s lap %d  p50 %5.1f  p95 %5.1f  p99 %5.1f  worst %6.1f ms   (first frame after each step: p50 %5.1f, worst %6.1f ms at step %d)   %d instances came newly into view" % [
		tag, WALK_WAYS[way], lap + 1, _pct(all, 50), _pct(all, 95), _pct(all, 99), _pct(all, 100),
		_pct(firsts, 50), worst[0], worst[1], fresh_tot])
	print("WALK ", lines[-1])

## The player `d` metres on from where the lap started, walking the way it was first looking (so the ground covered is
## the same whether the view turns or not).
func _walk_to(place: String, start_yaw: float, d: float) -> void:
	var f := Vector3(-sin(start_yaw), 0, -cos(start_yaw)) * d
	if place == "luna":
		arena.stkilda.stand("%f,%f,0" % [f.x, f.z])
		return
	arena.player.global_position = Vector3(clampf(f.x, -24.0, 24.0), 0.0, clampf(10.0 + f.z, -24.0, 24.0))
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()

# ================================================================ --chars: what a block character costs

## Each kind of body built at each cube size, once (nothing cached yet, as the start-up finds it) and then again
## (cached, as a wave of them finds it): how long it takes, and what it draws -- the draw calls (one a body part) and
## the triangles the camera is handed for every enemy on screen.
func _chars_run() -> void:
	print("CHARS  kind            cube size   first build   again   draw calls   triangles")
	for chunk in [1, 2]:
		var tot_first := 0.0
		var tot_tris := 0
		for key in (VoxelArena.HEIGHT as Dictionary).keys() + ["jared_new"]:
			VoxelBody._flesh_cache.clear()
			VoxelBody._shared.clear()
			var t0 := Time.get_ticks_usec()
			var b := _build_body(String(key), chunk)
			var first := float(Time.get_ticks_usec() - t0) / 1000.0
			var calls := 0
			var tris := 0
			for n in b.parts:
				var mi := b.parts[n].mesh as MeshInstance3D
				if mi and mi.mesh:
					calls += mi.mesh.get_surface_count()
					tris += _tris(mi.mesh)
			b.queue_free()
			var t1 := Time.get_ticks_usec()
			var b2 := _build_body(String(key), chunk)
			var again := float(Time.get_ticks_usec() - t1) / 1000.0
			b2.queue_free()
			await process_frame
			tot_first += first
			tot_tris += tris
			lines.append("  %-14s %s     %8.0f ms  %6.1f ms   %6d       %s" % [
				key, "fine (1)  " if chunk == 1 else "chunky (2)", first, again, calls, _k(tris)])
			print("CHARS ", lines[-1])
		_check(tot_tris > 0, "cube size %d: bodies built" % chunk)
		lines.append("  %-14s %s     %8.0f ms            all %d enemy kinds and Jared, %s tris the lot" % [
			"EVERYONE", "fine (1)  " if chunk == 1 else "chunky (2)", tot_first, (VoxelArena.HEIGHT as Dictionary).size(), _k(tot_tris)])
		print("CHARS ", lines[-1])
	print("CHARS ==================================================== the lot")
	for l in lines:
		print("CHARS ", l)
	print("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	done = true

func _build_body(key: String, chunk: int) -> VoxelBody:
	var md := VoxelModel.get_model(key)
	var rows := float(md.rig.get("ref_rows", 80)) if md else 80.0
	var cube_m := float((VoxelArena.HEIGHT as Dictionary).get(key, 1.85)) / rows * float(chunk)
	if key == "jared_new":                    # (the player's own body: its cube is a sprite pixel, not a height)
		cube_m = 0.0125 * float(chunk)
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(key, cube_m, chunk, arena._mat)
	return b

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
