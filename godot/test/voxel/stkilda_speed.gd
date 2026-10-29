extends SceneTree
## St Kilda's speed (not a pass or fail: numbers to read): how long the graphics card takes a frame (its own
## measure, so the frame cap doesn't hide it) and the game's own code, in Luna Park on the Low and High settings:
## stood in the park by day, by night, while a building comes down, and with 40 enemies about. Prints a table
## (milliseconds a frame: the average and the slowest 1 in 20; draw calls). The second figure is the whole frame on
## the main thread, waiting for the frame cap included: not the game's own code (the arena's HUD shows that). Under
## a display, Forward+. Owned by the St Kilda session.

const SCENES := ["day", "night", "collapse", "forty"]
const PRESETS := ["low", "high"]
const WARM := 1.5
const MEASURE := 3.0

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var pi_ := 0
var si := 0
var phase := 0                    # 0 set up, 1 warm, 2 measure
var times := PackedFloat32Array()
var draws := 0
var rows := []
var cpu := PackedFloat32Array()

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.5 and sk == null:
		return false
	if sk == null:
		arena.godmode = true
		arena.waves.queue.clear()
		sk = arena.stkilda
		sk.go()
		sk.nav.bake()
		t = 0.0
		return false
	match phase:
		0:
			if not sk.nav.ready_:
				return false
			var s := arena.settings_menu.s
			s.set_preset(PRESETS[pi_])
			s.apply(arena)
			Engine.max_fps = 0
			_set_scene(SCENES[si])
			phase = 1
			t = 0.0
		1:
			if t > WARM:
				phase = 2
				t = 0.0
				times.clear()
				cpu.clear()
				RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
				draws = 0
		2:
			times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			if t > MEASURE:
				var sorted := times.duplicate()
				sorted.sort()
				var avg := 0.0
				for x in times:
					avg += x
				avg /= maxf(1.0, times.size())
				var slow := sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0.0
				var c_avg := 0.0
				for x in cpu:
					c_avg += x
				c_avg /= maxf(1.0, cpu.size())
				rows.append("%-5s %-9s graphics card %5.2f ms (slowest 1 in 20: %5.2f)   game + drawing set-up %5.2f ms   %4d draw calls" % [PRESETS[pi_], SCENES[si], avg, slow, c_avg, draws])
				print(rows[-1])
				si += 1
				if si >= SCENES.size():
					si = 0
					pi_ += 1
				if pi_ >= PRESETS.size():
					print("\nSPEED (", RenderingServer.get_video_adapter_name(), "):")
					for r in rows:
						print(r)
					quit()
					return false
				phase = 0
				t = 0.0
	return false

func _set_scene(name: String) -> void:
	sk.clear_park()
	if sk.day_night.night:
		sk.day_night.toggle()
	sk.stand("0,-40,0")
	match name:
		"night":
			sk.day_night.toggle()
			sk.day_night.t = 1.0
			sk.day_night._apply()
		"collapse":
			sk.breaks.reset()
			var b: VoxelBreakables.Building = null
			for bb in sk.breaks.list:
				if b == null or bb.alive.size() > b.alive.size():
					b = bb
			# you, 20 m out from its wall; a row of blasts along its foot
			var c := b.cols.size() / 2
			var n: Vector2 = b.cols[c].n
			var at := b.block_at(c, 0)
			sk._put(at + Vector3(n.x, 0, n.y) * 20.0, atan2(n.x, n.y), 0.15)
			for k in range(-8, 9):
				sk.breaks.blast(b.block_at((c + k * 2 + b.cols.size()) % b.cols.size(), 0) + Vector3(n.x, 0, n.y) * 0.3, 1.6)
		"forty":
			var me := arena.player.global_position
			for k in 40:
				var a := TAU * k / 40.0
				sk.spawn(VoxelParkGame.KINDS[k % VoxelParkGame.KINDS.size()], me + Vector3(cos(a), 0, sin(a)) * randf_range(8.0, 20.0))
