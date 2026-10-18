extends Node
## The game with digging set up for screenshots and speed checks (web export: set this as the main scene in a
## work copy, and let test/dig/ into the export). Options (the address's ?query on the web, or user args):
##   digdemo       holes (deeper each), a ramp down to a cave, a shaft, ploughed rows with crops, weedy rows
##   at=X,Y        put the player there (HTML units)   in       stand him in the cave
##   fp            first person   yaw=A   look that way (radians, HTML ground: 0 east, pi/2 south)   pitch=P
##   zoom=N        the top-down zoom level      tool=shovel|hoe   hand him a tool
##   nodig         draw the World's own flat yard floor instead of the dig's chunks (to compare frame times)
##   dmg           the block he aims at half broken (the health bar)
##   perf          from 6 s in, print frame times (median, 95th) and draw calls over 5 s: "DIGPERF ..."

const D := preload("res://scripts/dig/dig_data.gd")

var main: Node
var opts := {}
var _times: Array = []
var _t := 0.0
var _proc := 0.0
var _phys := 0.0

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	opts = _opts()
	_setup.call_deferred()

static func _opts() -> Dictionary:
	var out := {}
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			args += Array(q.substr(1).split("&"))
	for a in args:
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out

func _setup() -> void:
	await get_tree().process_frame
	var dig: Dig = main.get_node("Dig")
	var p: Player = main.player
	dig.persist = false
	if opts.has("digdemo"):
		var g := dig.grid
		g.clear()
		# holes along the lawn east of the trampoline, deeper each; a ramp down into a cave; a shaft
		# (broken blocks, as in play: 1 to 4 deep; then steps down, 2 blocks wide)
		for k in 4:
			for d in k + 1:
				dig.break_block(DigVolume.block_of(Vector3(1000 + k * 90, 1230, -16.0 - d * D.BLOCK)))
		for k in 7:
			for w in 2:
				for d in k + 1:
					dig.break_block(DigVolume.block_of(Vector3(1180.0 + k * D.BLOCK, 1320 + w * D.BLOCK, -16.0 - d * D.BLOCK)))
		dig.carve(Vector3(1380, 1330, -150), Vector3(1500, 1330, -150), 40.0)       # the cave
		dig.carve(Vector3(1440, 1300, -120), Vector3(1440, 1380, -170), 34.0)
		dig.carve(Vector3(1560, 1250, -180), Vector3(1560, 1250, 20), 18.0)          # a shaft
		# a little wall of placed blocks (dirt and stone, two high) on the lawn, and a backpack
		for bx in 3:
			for bz in 2:
				dig.grid.vol.fill_block(DigVolume.block_of(Vector3(1300 + bx * D.BLOCK, 1120, 16 + bz * D.BLOCK)), D.STONE_M if bz == 0 else D.DIRT_M)
		dig.inv.res = [24, 9, 13, 4, 3]
		dig.inv.pickaxe = true
		dig.inv.tiers.pickaxe = 1
		dig.ground.flush()
		# a field: rows ploughed across, a crop on some spots
		for r in 7:
			var y := 1420.0 + r * 8.0
			var x := 1020.0
			while x < 1300.0:
				g.plough(x, y, Vector2.RIGHT)
				x += 6.0
		# rows down the yard, old and weedy
		for c in 5:
			var x2 := 1500.0 + c * 8.0
			var y2 := 1060.0
			while y2 < 1300.0:
				g.plough(x2, y2, Vector2.DOWN)
				y2 += 6.0
		var fm := Farm.instance
		if fm:
			fm.persist = false
			var stages := [0.1, 0.4, 0.7, 1.0, 0.55]
			for k in stages.size():
				var spot = g.plant_spot(1060 + k * 48, 1444)
				if spot == null:
					continue
				var i: int = fm.state.field_plot(spot.x, spot.y)
				fm.state.add_seed(0, k % 2, 1)
				fm.state.plant(i, 0, k % 2)
				fm.state.plots[i].g = stages[k]
				fm.state.plots[i].wet = 2.0
			fm.state.changed.emit()
		g.grow_back(D.WEEDY_HOURS + 2.0, [Vector2(1150, 1444)])
		for r in 3:
			var x3 := 1020.0
			while x3 < 1300.0:
				g.plough(x3, 1420.0 + r * 8.0, Vector2.RIGHT)  # (the planted rows fresh again)
				x3 += 6.0
	if opts.has("nodig"):
		dig.ground.visible = false
		var wm: MeshInstance3D = main.world.get_node("WorldMesh")
		for i in wm.mesh.get_surface_count():
			var m := wm.get_surface_override_material(i)
			if m is ShaderMaterial and m.shader and m.shader.code.contains("discard"):
				wm.set_surface_override_material(i, null)
				var lp = main.find_child("LookPass", true, false)
				if lp and lp.has_method("light_mesh"):
					var base := wm.mesh.surface_get_material(i)
					if base is StandardMaterial3D:
						wm.set_surface_override_material(i, lp.lit_material(base))
	if opts.has("nosoil"):
		dig.ground.remove_child(dig.ground.get_node("DigSoil"))
	if opts.has("worldmat") or opts.has("unlit"):
		var wm2: MeshInstance3D = main.world.get_node("WorldMesh")
		for i in wm2.mesh.get_surface_count():
			var base := wm2.mesh.surface_get_material(i)
			if base is StandardMaterial3D and base.albedo_texture == main.world.get("_yard_tex"):
				var lp2 = main.find_child("LookPass", true, false)
				dig.ground.get_node("DigGrass").material_override = base if opts.has("unlit") else lp2.lit_material(base)
		print("DIGSHOT grass material: ", dig.ground.get_node("DigGrass").material_override)
	if opts.has("nograss"):
		dig.ground.get_node("DigGrass").visible = false
	if opts.has("tool"):
		dig.set_tool(p, String(opts.tool))
	if opts.has("at"):
		var xy := String(opts.at).split(",")
		p.place(float(xy[0]), float(xy[1]))
	elif opts.has("in"):
		p.place(1440, 1330)                      # in the cave
		dig.drop_to(p, -110.0)
	p.facing = Vector2(0, 1)
	if opts.has("fp"):
		main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	await get_tree().process_frame
	if opts.has("yaw"):
		p.look_ang = float(opts.yaw)
		p.facing = Vector2(cos(p.look_ang), sin(p.look_ang))
	if opts.has("pitch"):
		p.look_y = float(opts.pitch)
	if opts.has("zoom"):
		main.rig.set_zoom(int(opts.zoom))
	main.rig.snap()
	if opts.has("dmg"):
		await get_tree().create_timer(1.0).timeout
		var tb = dig.target.get("b")
		if tb != null:
			dig._damage[tb] = 1.6
func _process(delta: float) -> void:
	if not opts.has("perf"):
		return
	_t += delta
	if _t > 6.0 and _t < 11.0:
		_times.append(delta * 1000.0)
		_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	elif _t >= 11.0 and not _times.is_empty():
		_times.sort()
		var med: float = _times[_times.size() / 2]
		var p95: float = _times[int(_times.size() * 0.95)]
		print("DIGPERF process=%.1fms physics=%.1fms a frame" % [_proc / _times.size(), _phys / _times.size()])
		print("DIGPERF frames=%d median=%.1fms p95=%.1fms draws=%d objects=%d prims=%d look=%s" % [_times.size(), med, p95,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			opts.get("look", "?")])
		_times.clear()
