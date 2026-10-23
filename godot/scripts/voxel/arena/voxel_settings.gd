class_name VoxelSettings
extends RefCounted
## The game's settings (the owner, Stage 9: "PC first, as physics/graphics heavy as possible, but scalable settings, plus
## a recommended-settings test based on the player's hardware"). Presets Low, Medium, High (as it's been), Ultra, and
## Extreme (Stage 10, for the PCs that run Ultra at hundreds of frames a second: supersampled, 8192 shadows, every effect at
## its best, reflections, twice the gore kept); any
## one changed by hand makes it Custom. The picture: render scale (FSR upscaling below 100% on Forward+), MSAA, TAA,
## shadows (off / hard 2048 / soft 4096), SSAO, SSIL, glow, SDFGI global illumination, volumetric fog, the bedroom's
## mirror. The gore's weight: the cube size (1 sprite pixel a cube, or 2: an eighth of the cubes), how many knocked-out
## cubes lie about and fly at once, cut-off pieces, corpses kept. Yours alone (not in the presets): field of view, mouse
## speed, volume, full screen, frame cap, vsync. Saved in user://voxel_settings.cfg. The first time the game runs it
## guesses a preset from the graphics card (guess()); the benchmark (VoxelSettingsMenu) measures one. Owned by the voxel
## session.

const FILE := "user://voxel_settings.cfg"
const ORDER := ["low", "medium", "high", "ultra", "extreme"]
const PRESETS := {
	"low": {"scale": 0.67, "msaa": 0, "taa": false, "shadows": 0, "ssao": false, "ssil": false, "glow": false, "sdfgi": false,
		"fog": false, "mirror": false, "chunk": 2, "lying": 40000, "flying": 3000, "pieces": 12, "corpses": 12, "gore": 0, "jiggle": 3},
	"medium": {"scale": 0.85, "msaa": 0, "taa": false, "shadows": 1, "ssao": true, "ssil": false, "glow": true, "sdfgi": false,
		"fog": false, "mirror": true, "chunk": 1, "lying": 80000, "flying": 5000, "pieces": 20, "corpses": 25, "gore": 1, "jiggle": 3},
	"high": {"scale": 1.0, "msaa": 2, "taa": false, "shadows": 2, "ssao": true, "ssil": false, "glow": true, "sdfgi": false,
		"fog": false, "mirror": true, "chunk": 1, "lying": 150000, "flying": 8000, "pieces": 30, "corpses": 40, "gore": 1, "jiggle": 3},
	"ultra": {"scale": 1.0, "msaa": 4, "taa": true, "shadows": 2, "ssao": true, "ssil": true, "glow": true, "sdfgi": true,
		"fog": true, "mirror": true, "chunk": 1, "lying": 300000, "flying": 12000, "pieces": 45, "corpses": 60, "gore": 1, "jiggle": 3},
	"extreme": {"scale": 1.5, "msaa": 8, "taa": true, "shadows": 3, "ssao": true, "ssil": true, "glow": true, "sdfgi": true,
		"fog": true, "mirror": true, "chunk": 1, "lying": 600000, "flying": 25000, "pieces": 90, "corpses": 120, "gore": 2, "jiggle": 3},
}
## (the effects' own quality, and screen-space reflections: Extreme's, or anything set to them by hand)
const FX_PRESETS := {"low": 0, "medium": 0, "high": 0, "ultra": 0, "extreme": 1}
const PERSONAL := {"fov": 80.0, "sens": 1.0, "volume": 1.0, "fullscreen": false, "fps": 0, "vsync": true,
	"mine_sewers": true, "mine_cops": true, "mine_rivals": true, "announcer": 2}
## (what each setting can be, for the menu: [label, values, value labels])
const CHOICES := {
	"scale": ["Render scale", [0.5, 0.67, 0.77, 0.85, 1.0, 1.25, 1.5], ["50%", "67%", "77%", "85%", "100%", "125% (supersampled)", "150% (supersampled)"]],
	"msaa": ["Anti-aliasing (MSAA)", [0, 2, 4, 8], ["Off", "2x", "4x", "8x"]],
	"taa": ["Temporal AA", [false, true], ["Off", "On"]],
	"shadows": ["Shadows", [0, 1, 2, 3], ["Off", "Hard (2048)", "Soft (4096)", "Sharpest (8192)"]],
	"fx": ["Effects quality", [0, 1], ["Normal", "Best (+ reflections)"]],
	"gore": ["Gore", [0, 1, 2], ["Normal", "Ultra (bleeding, pools)", "Extreme"]],
	"jiggle": ["Jiggle (Gothica)", [0, 1, 2, 3], ["Off", "Natural", "Bouncy", "Out of this world"]],
	"ssao": ["Ambient occlusion", [false, true], ["Off", "On"]],
	"ssil": ["Indirect light (SSIL)", [false, true], ["Off", "On"]],
	"glow": ["Glow", [false, true], ["Off", "On"]],
	"sdfgi": ["Global illumination (SDFGI)", [false, true], ["Off", "On"]],
	"fog": ["Volumetric fog", [false, true], ["Off", "On"]],
	"mirror": ["Bedroom mirror", [false, true], ["Off", "On"]],
	"chunk": ["Cube size (gore detail)", [1, 2], ["Fine (1 pixel)", "Chunky (2 pixels)"]],
	"lying": ["Cubes lying about", [40000, 80000, 150000, 300000, 600000], ["40k", "80k", "150k", "300k", "600k"]],
	"flying": ["Cubes flying at once", [3000, 5000, 8000, 12000, 25000], ["3k", "5k", "8k", "12k", "25k"]],
	"pieces": ["Cut-off pieces", [12, 20, 30, 45, 90], ["12", "20", "30", "45", "90"]],
	"corpses": ["Corpses kept", [12, 25, 40, 60, 120], ["12", "25", "40", "60", "120"]],
	"fps": ["Frame cap", [0, 60, 120, 144, 240], ["None", "60", "120", "144", "240"]],
	"vsync": ["VSync", [false, true], ["Off", "On"]],
	"fullscreen": ["Full screen", [false, true], ["Off", "On"]],
	"announcer": ["Kill announcer", [0, 1, 2], ["Off", "Callouts only", "Callouts and sound"]],
	"mine_sewers": ["Mine: sewers and rats", [false, true], ["Off", "On"]],
	"mine_cops": ["Mine: the cop bunker", [false, true], ["Off", "On"]],
	"mine_rivals": ["Mine: rival dealers' tunnels", [false, true], ["Off", "On"]],
}

var file := FILE                # ("": never saved, the tests' games)
var v := {}                     # every setting now
var preset := "high"            # or "custom"
var first_run := false
var bench := {}                 # the last benchmark: {preset: [average fps, 1% low fps]}, "pick", "hw"

func _init() -> void:
	v = PRESETS.high.duplicate()
	v.fx = 0
	v.merge(PERSONAL)

func set_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	for k in PRESETS[name]:
		v[k] = PRESETS[name][k]
	v.fx = FX_PRESETS[name]
	preset = name

## A setting changed by hand: Custom, unless it happens to match a preset.
func set_value(key: String, value) -> void:
	v[key] = value
	preset = which_preset()

func which_preset() -> String:
	for name in ORDER:
		var same := true
		for k in PRESETS[name]:
			if v.get(k) != PRESETS[name][k]:
				same = false
				break
		if same and int(v.get("fx", 0)) == FX_PRESETS[name]:
			return name
	return "custom"

func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(file) != OK:
		first_run = true
		set_preset(guess())
		return
	for k in v:
		v[k] = cf.get_value("settings", k, v[k])
	preset = which_preset()
	bench = cf.get_value("bench", "last", {})

func save_file() -> void:
	if file == "":
		return
	var cf := ConfigFile.new()
	for k in v:
		cf.set_value("settings", k, v[k])
	if not bench.is_empty():
		cf.set_value("bench", "last", bench)
	cf.save(file)

## A preset guessed from the graphics card's name (the first run, before any benchmark).
static func guess(card := RenderingServer.get_video_adapter_name()) -> String:
	var gpu := card.to_lower().replace("(tm)", "").replace("(r)", "")     # ("Intel(R) Arc(TM) A770": "intel arc a770")
	if gpu == "" or gpu.contains("llvmpipe") or gpu.contains("software") or gpu.contains("swiftshader"):
		return "low"
	for hi in ["rtx 40", "rtx 50", "rx 79", "rx 9070", "rtx 3090", "rtx 3080"]:
		if gpu.contains(hi):
			return "ultra"
	for mid in ["rtx", "rx 6", "rx 7", "arc a7", "arc b5"]:
		if gpu.contains(mid):
			return "high"
	for lo in ["intel", "uhd", "iris", "vega", "radeon graphics", "780m", "680m"]:
		if gpu.contains(lo):
			return "low"
	return "medium"

## The PC, in a line: the processor, its threads, the memory, the graphics card.
static func hardware() -> String:
	var mem: Dictionary = OS.get_memory_info()
	var gb := float(mem.get("physical", 0)) / 1073741824.0
	return "%s (%d threads), %.0f GB, %s" % [OS.get_processor_name(), OS.get_processor_count(), gb, RenderingServer.get_video_adapter_name()]

## Everything put into effect. The cube size and the cubes' caps start the arena over (its enemies and loose cubes)
## when they change (not mid co-op, where the host's world decides the cube size).
func apply(arena: Node3D) -> void:
	var vp := arena.get_viewport()
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_scale = float(v.scale)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (forward and float(v.scale) < 0.99) else Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(int(v.msaa), Viewport.MSAA_DISABLED)
	vp.use_taa = bool(v.taa) and forward
	var sh := int(v.shadows)
	arena.sun.shadow_enabled = sh > 0
	if arena.house:                 # (the bedroom's ceiling light, its own child, too: Off is off in there as well)
		for l in arena.house.find_children("*", "OmniLight3D", false, false):
			l.shadow_enabled = sh > 0
	if sh > 0:
		RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 8192][sh], true)
		RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][sh])
	var hi := int(v.get("fx", 0)) == 1
	var env: Environment = arena.world_env
	if env:
		env.ssao_enabled = bool(v.ssao)
		env.ssil_enabled = bool(v.ssil)
		env.glow_enabled = bool(v.glow)
		env.sdfgi_enabled = bool(v.sdfgi) and forward
		env.volumetric_fog_enabled = bool(v.fog) and forward
		env.volumetric_fog_density = 0.012 if hi else 0.008
		env.volumetric_fog_albedo = Color(0.75, 0.7, 0.8)
		env.ssr_enabled = hi and forward          # (reflections: the floor's sheen shows the fight)
		env.ssr_max_steps = 96
		env.ssr_fade_in = 0.2
		env.ssr_depth_tolerance = 0.3
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA if hi else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_ULTRA if hi else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_128 if hi
		else int(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/probe_ray_count", 1)))
	RenderingServer.environment_set_volumetric_fog_volume_size(128 if hi else 64, 128 if hi else 64)
	VoxelMirror.enabled = bool(v.mirror)
	VoxelBlood.level = int(v.get("gore", 1))
	VoxelJiggle.level = int(v.get("jiggle", 3))
	VoxelAnnouncer.level = int(v.get("announcer", 2))
	VoxelMine.hazards = {"sewers": bool(v.get("mine_sewers", true)), "cops": bool(v.get("mine_cops", true)), "rivals": bool(v.get("mine_rivals", true))}
	var aa := int(v.msaa)                    # (the mirror as sharp as the rest: more pixels and its own MSAA at the higher levels)
	VoxelMirror.max_res = {0: 720, 2: 1080, 4: 1440, 8: 2160}.get(aa, 1080)
	VoxelMirror.msaa = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(aa, Viewport.MSAA_2X)
	VoxelPieces.MAX_PIECES = int(v.pieces)
	VoxelArena.MAX_DEAD = int(v.corpses)
	var restart := false
	var linked: bool = arena.net != null and arena.net.linked
	# (the cubes' caps start the fight over: not mid co-op, where the host's world is shared; they wait for a solo apply)
	if not linked and (VoxelDebris.max_lie != int(v.lying) or VoxelDebris.max_fly != int(v.flying)):
		VoxelDebris.max_lie = int(v.lying)
		VoxelDebris.max_fly = int(v.flying)
		restart = true
	if arena.chunk != int(v.chunk) and not arena._opts.has("chunk") and not (arena.net and arena.net.linked):
		arena.chunk = int(v.chunk)
		if arena.debris:            # (at the start: nothing made yet, it's all made at this size)
			arena._warm_up()
			restart = true
	if restart and arena.debris:
		arena._respawn_all()
	arena.base_fov = float(v.fov)
	arena.mouse_sens = float(v.sens)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(v.volume))))
	Engine.max_fps = int(v.fps)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(v.vsync) else DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() != "headless":
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if bool(v.fullscreen) != fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(v.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)
