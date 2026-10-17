extends Node
## The Lighting session's test scene (scenes/look/look_test.tscn): the real game (scenes/main.tscn) with
## LightingInstall.install(main) called, as main.gd will once it's merged. For screenshots the address (or the
## command line's user args) can also say: view=fp, at=x,y (where the player stands, HTML units), face=deg (where
## he looks in first person, 0 east, 90 south), ly=0.2 (look down), zoom=0|1|2, perf (print frame times).

var main: Node
var _ft: Array = []
var _perf := false
var _t := 0.0
var _last := 0

func _ready() -> void:
	LightingInstall._ensure_clock(get_tree())    # (the autoload, once merged: the farm finds it at its install)
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var a := LightingInstall._page_args()
	if not a.has("nolight"):
		LightingInstall.install(main)
	_perf = a.has("perf")
	if a.has("at"):
		var p: PackedStringArray = String(a.at).split(",")
		main.player.place(float(p[0]), float(p[1]))
	if a.has("zoom"):
		main.rig.set_zoom(int(a.zoom))
	if a.get("view", "") == "fp":
		main.rig.capture_mouse = false
		main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	if a.has("face"):
		main.player.look_ang = deg_to_rad(float(a.face))
		var f := Vector2(cos(main.player.look_ang), sin(main.player.look_ang))
		main.player.facing = f
	if a.has("ly"):
		main.player.look_y = float(a.ly)
	main.rig.snap()
	if a.has("inspect"):
		_inspect()
		get_tree().quit()

## Prints the World's meshes: each surface's material, its height range and its ground extent (HTML units).
func _inspect() -> void:
	for mi in main.world.find_children("*", "MeshInstance3D", true, false) + main.find_children("HouseShadow", "", true, false):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		print("MESH ", mi.name, " surfaces=", m.get_surface_count(), " cast=", mi.cast_shadow)
		for i in m.get_surface_count():
			var arr := m.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			for p in v:
				lo = lo.min(p)
				hi = hi.max(p)
			var mat = mi.get_surface_override_material(i)
			if mat == null:
				mat = m.surface_get_material(i)
			var desc := ""
			if mat is ShaderMaterial:
				var t = mat.get_shader_parameter("tex")
				desc = "tex=%s col=%s" % [(t.get_size() if t else "none"), mat.get_shader_parameter("albedo")]
			elif mat is StandardMaterial3D:
				desc = "STD tex=%s col=%s" % [(mat.albedo_texture.get_size() if mat.albedo_texture else "none"), mat.albedo_color]
			var a3 := GameData.from_3d(lo)
			var b3 := GameData.from_3d(hi)
			print("  %d tris=%d y=%.2f..%.2f x=%d..%d y=%d..%d %s" % [i, v.size() / 3, lo.y, hi.y, a3.x, b3.x, a3.y, b3.y, desc])

func _process(dt: float) -> void:
	if not _perf:
		return
	_t += dt
	var now := Time.get_ticks_usec()
	if _t > 3.0 and _last > 0:
		_ft.append((now - _last) / 1000.0)    # real time: the engine's delta is held to 8 physics steps
	_last = now
	if _ft.size() == 30:
		var s := _ft.duplicate()
		s.sort()
		var sum := 0.0
		for v in s:
			sum += v
		print("PERF avg=%.1fms p50=%.1fms p95=%.1fms fps=%d draws=%d" % [sum / s.size(), s[s.size() / 2], s[int(s.size() * 0.95)],
			Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		_ft.clear()
		_t = 0.0
