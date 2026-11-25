class_name VoxelSettings
extends RefCounted
## The game's settings (the owner, Stage 9: "PC first, as physics/graphics heavy as possible, but scalable settings, plus
## a recommended-settings test based on the player's hardware"). Presets Low, Medium, High (as it's been), Ultra, and
## Extreme (Stage 10, for the PCs that run Ultra at hundreds of frames a second: supersampled, 8192 shadows, every effect at
## its best, reflections, twice the gore kept); any
## one changed by hand makes it Custom. The picture: render scale (FSR upscaling below 100% on Forward+), MSAA, TAA,
## shadows (off / hard 2048 / soft 4096), SSAO, SSIL, glow, SDFGI global illumination, volumetric fog, the bedroom's
## mirror. The block characters' detail: the cube size the enemies are built at, and your own Jared's (1 sprite pixel
## a cube, or 2: an eighth of the cubes, which is what makes an enemy look blocky -- the owner, 25 Nov: "the enemies
## look worse". Measured with test/voxel/voxel_perf_sweep.gd --chars: Fine and Chunky draw the same 14 calls a body,
## Fine is about 13,000 triangles an enemy against 6,000, and the whole difference is in the one-off building during
## the loading screen, so every preset now builds the enemies Fine. Jared alone is 650,000 cells and 11 s of that
## building, so Low still builds him Chunky; it's a row in the menu either way.) The gore's weight: how many knocked-out
## cubes lie about and fly at once, cut-off pieces, corpses kept. Yours alone (not in the presets): field of view, mouse
## speed, volume, full screen, frame cap, vsync. Saved in user://voxel_settings.cfg. The first time the game runs it
## guesses a preset from the graphics card (guess()); the benchmark (VoxelSettingsMenu) measures one. Owned by the voxel
## session.

const FILE := "user://voxel_settings.cfg"
const ORDER := ["low", "medium", "high", "ultra", "extreme"]
const PRESETS := {
	"low": {"scale": 0.67, "msaa": 0, "taa": false, "shadows": 0, "ssao": false, "ssil": false, "glow": false, "sdfgi": false,
		"fog": false, "mirror": false, "chunk": 1, "jared": 2, "lying": 40000, "flying": 3000, "pieces": 12, "corpses": 12, "gore": 0, "jiggle": 3,
		"scenery": 60.0},
	"medium": {"scale": 0.85, "msaa": 0, "taa": false, "shadows": 1, "ssao": true, "ssil": false, "glow": true, "sdfgi": false,
		"fog": false, "mirror": true, "chunk": 1, "jared": 1, "lying": 80000, "flying": 5000, "pieces": 20, "corpses": 25, "gore": 1, "jiggle": 3,
		"scenery": 110.0},
	"high": {"scale": 1.0, "msaa": 2, "taa": false, "shadows": 2, "ssao": true, "ssil": false, "glow": true, "sdfgi": false,
		"fog": false, "mirror": true, "chunk": 1, "jared": 1, "lying": 150000, "flying": 8000, "pieces": 30, "corpses": 40, "gore": 1, "jiggle": 3,
		"scenery": 180.0},
	"ultra": {"scale": 1.0, "msaa": 4, "taa": true, "shadows": 2, "ssao": true, "ssil": true, "glow": true, "sdfgi": true,
		"fog": true, "mirror": true, "chunk": 1, "jared": 1, "lying": 300000, "flying": 12000, "pieces": 45, "corpses": 60, "gore": 1, "jiggle": 3,
		"scenery": 0.0},
	"extreme": {"scale": 1.5, "msaa": 8, "taa": true, "shadows": 3, "ssao": true, "ssil": true, "glow": true, "sdfgi": true,
		"fog": true, "mirror": true, "chunk": 1, "jared": 1, "lying": 600000, "flying": 25000, "pieces": 90, "corpses": 120, "gore": 2, "jiggle": 3,
		"scenery": 0.0},
}
## (the effects' own quality, and screen-space reflections: Extreme's, or anything set to them by hand)
const FX_PRESETS := {"low": 0, "medium": 0, "high": 0, "ultra": 0, "extreme": 1}
## (what only the Forward+ renderer does: the browser's game, on Compatibility, doesn't show these rows)
const FORWARD_ONLY := ["taa", "ssao", "ssil", "sdfgi", "fog", "fx"]
## The settings the renderer itself has to chew on when they change: a new shadow map or a new effect means the
## driver compiles the shaders that draw with it, on the first frame drawn after the change, and in a browser that
## is one long frame nobody can do anything during. Measured through Chromium at phone size: shadows Off -> Soft
## was 4,078 ms and Off -> Sharpest 4,931 ms, with the whole tab unreachable (this machine software-renders, so a
## real phone's driver will be a good deal quicker -- but it is the same frame and the same silence). Nothing can
## make that frame short, so the settings screen says what it is doing first and draws the line before it changes
## anything (VoxelSettingsMenu._changed): the picture stops for a moment with a message over it, not for nothing.
const PICTURE := ["scale", "msaa", "taa", "shadows", "ssao", "ssil", "glow", "sdfgi", "fog", "mirror", "fx"]
const PHONE_ACROSS := 1280.0     # a phone's browser: the 3D picture's longer side, in pixels, before the preset's scale
const PHONE_FAR := 260.0         # ... and how far it draws (metres)
## The native Android build is not the browser: threads, a real driver, no WASM. The owner's Galaxy S25 ran it on
## these browser caps at 109-120 fps (25 Nov: "that APK seemed buttery smooth ... it was 120 and then dropped down to
## like 109"), and on a 2340x1080 screen the 1280 cap meant Low drew the 3D at 858x396 and stretched it over the
## panel -- the owner's "I don't know if it's quite getting the res". So on native the cap comes off: "Render scale"
## means what it says, as it does on a PC, and NATIVE_ACROSS is only a stop so a 4K Android panel doesn't try 3840.
## The view goes half as far again as well: measured with voxel_perf_sweep --far=, 260 m -> 420 m costs 11 draw calls
## and 11k triangles at the worst spot in the arena and nothing at all in Luna Park, because the scenery's own
## visibility ranges do the culling, not the far plane.
const NATIVE_ACROSS := 2560.0
const NATIVE_FAR := 420.0
## What a native phone starts on, over Low: the screen's own pixels, and Luna Park's scenery kept in full out to 110 m
## instead of 60 m (+35% triangles at the worst spot there, +3 draw calls -- voxel_perf_sweep --scenery=). Shadows
## stay off and your own Jared stays chunky, because those two are the ones that can't be afforded blind: the sun's
## shadow is four splits over 60 m, which is the one change that could double Luna Park's geometry, and nothing here
## can measure a phone's GPU; and Jared at Fine is 12.1 s of building on the loading screen (--chars) for a body you
## only ever see in the bedroom mirror. MEDIUM in SET turns on both, and the rest of Medium with them.
const NATIVE_START := {"scale": 1.0, "scenery": 110.0}
const PERSONAL := {"fov": 80.0, "sens": 1.0, "volume": 1.0, "fullscreen": false, "fps": 0, "vsync": true,
	"mine_sewers": true, "mine_cops": true, "mine_rivals": true, "announcer": 2, "steady": true, "fold": true, "own": true, "smooth": false}
## (what each setting can be, for the menu: [label, values, value labels])
const CHOICES := {
	# The three view fixes, first in the list so they are easy to find on a phone, and switchable so the owner can
	# feel the difference back to back in one session instead of trusting a memory of an hour ago (the owner, 25 Nov:
	# "I don't know if you fixed it or if I'm learning the old one"). Both default On. "Steady view" keeps the camera
	# out of Godot's physics interpolation, which was smearing it between frames and making an even thumb look uneven
	# (VoxelArena.steady_view has the measurements); "Combine thumb moves" applies a frame's worth of touch samples
	# once instead of one at a time (VoxelTouch.fold). ?steady=0 / ?fold=0 on the page start with either one off.
	# once instead of one at a time (VoxelTouch.fold); "Own thumb tracking" works each thumb's movement out from its
	# own last position instead of believing the engine, which on the web measures one thumb's move from the other
	# thumb's place every time the browser changes which fingers it reports together -- the snap (VoxelTouch.own_delta
	# has the measurements). ?steady=0 / ?fold=0 / ?own=0 on the page start with any of them off.
	"steady": ["Steady view (shudder fix)", [false, true], ["Off - as it was", "On"]],
	"fold": ["Combine thumb moves (shudder fix)", [false, true], ["Off - as it was", "On"]],
	"own": ["Own thumb tracking (snap fix)", [false, true], ["Off - as it was", "On"]],
	# and one that is OFF by default and only worth trying if a shudder is still there with the three above on:
	# it holds back the part of a bursty frame above the recent average and lets it out on the next frame, which is
	# at most 17 ms of lag on that part and none at all on a steady thumb (VoxelTouch.smooth, _spread)
	"smooth": ["Even out the view (try if it still shudders)", [false, true], ["Off", "On - up to 17 ms later"]],
	"scale": ["Render scale", [0.5, 0.67, 0.77, 0.85, 1.0, 1.25, 1.5], ["50%", "67%", "77%", "85%", "100%", "125% (supersampled)", "150% (supersampled)"]],
	"msaa": ["Anti-aliasing (MSAA)", [0, 2, 4, 8], ["Off", "2x", "4x", "8x"]],
	"taa": ["Temporal AA", [false, true], ["Off", "On"]],
	"shadows": ["Shadows", [0, 1, 2, 3], ["Off", "Hard (2048)", "Soft (4096)", "Sharpest (8192)"]],
	"scenery": ["Scenery detail", [60.0, 110.0, 180.0, 0.0], ["Near (60 m)", "Medium (110 m)", "Far (180 m)", "Everything"]],
	"fx": ["Effects quality", [0, 1], ["Normal", "Best (+ reflections)"]],
	"gore": ["Gore", [0, 1, 2], ["Normal", "Ultra (bleeding, pools)", "Extreme"]],
	"jiggle": ["Jiggle (Gothica)", [0, 1, 2, 3], ["Off", "Natural", "Bouncy", "Out of this world"]],
	"ssao": ["Ambient occlusion", [false, true], ["Off", "On"]],
	"ssil": ["Indirect light (SSIL)", [false, true], ["Off", "On"]],
	"glow": ["Glow", [false, true], ["Off", "On"]],
	"sdfgi": ["Global illumination (SDFGI)", [false, true], ["Off", "On"]],
	"fog": ["Volumetric fog", [false, true], ["Off", "On"]],
	"mirror": ["Bedroom mirror", [false, true], ["Off", "On"]],
	"chunk": ["Enemy detail (cube size)", [1, 2], ["Fine (every block)", "Chunky (an eighth of the blocks)"]],
	"jared": ["Your own blocks (mirror, top-down, co-op)", [1, 2], ["Fine (every block)", "Chunky (an eighth of the blocks)"]],
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
		set_preset("low" if VoxelTouch.active else guess())     # (a phone's browser: Low, no guessing; SET raises it)
		if native():
			for k in NATIVE_START:                              # (the native build: Low, with the headroom spent)
				v[k] = NATIVE_START[k]
			preset = which_preset()
		return
	var missing := []
	for k in v:
		if cf.has_section_key("settings", k):
			v[k] = cf.get_value("settings", k, v[k])
		else:
			missing.append(k)
	if not missing.is_empty():
		# (a file from before a setting was added, gore or jiggle: it takes the value of the preset the rest match, not
		# High's; a Low player shouldn't wake up to Ultra gore)
		for name in ORDER:
			var same: bool = int(v.get("fx", 0)) == FX_PRESETS[name] or missing.has("fx")
			for k in PRESETS[name]:
				if not missing.has(k) and v.get(k) != PRESETS[name][k]:
					same = false
					break
			if same:
				for k in missing:
					if PRESETS[name].has(k):
						v[k] = PRESETS[name][k]
				break
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

## The native Android build, told from a phone's browser by the "Android Voxel Arena" preset's own feature tag.
static func native() -> bool:
	return OS.has_feature("voxel_mobile")

## A phone's two caps: the 3D picture's longest side in pixels (before the preset's own scale), and how far it draws.
static func across() -> float:
	return NATIVE_ACROSS if native() else PHONE_ACROSS

static func far_m() -> float:
	return NATIVE_FAR if native() else PHONE_FAR

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
	var sc := float(v.scale)
	if VoxelTouch.phone():
		# A phone never supersamples. In a browser across() was already holding it to 1280 across, so 125% and 150%
		# meant nothing there; on the native build, where the cap is the screen's own pixels, 150% on the owner's
		# 2340-wide Galaxy S25 would ask WebGL (and the phone's driver) for a 3510x1620 buffer with MSAA on top --
		# a buffer several times the screen, which is how a phone runs out of memory and loses the picture. The
		# menu hides those two entries on a phone as well (VoxelSettingsMenu), so this is the backstop for a saved
		# file, a preset (Extreme is 150%) or a ?preset= link that asks for one anyway.
		sc = minf(sc, 1.0)
		# a phone: the 3D is drawn no wider than across() (1280 in a browser, where WebGL is single-threaded and the
		# fill is what hurts; the screen's own pixels on native) with the preset's scale on top, and no further than
		# far_m(). The HUD is 2D and stays sharp either way.
		var win := arena.get_window().size
		sc *= clampf(across() / maxf(1.0, float(maxi(win.x, win.y))), 0.4, 1.0)
		if arena.get("cam") and arena.cam:
			arena.cam.far = far_m()
	vp.scaling_3d_scale = sc
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (forward and sc < 0.99) else Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(int(v.msaa), Viewport.MSAA_DISABLED)
	vp.use_taa = bool(v.taa) and forward
	var sh := int(v.shadows)
	if VoxelTouch.phone():
		# A phone stops at the 4096 map. "Sharpest (8192)" is a 64 MB depth texture on top of everything else the
		# page is holding, which is how a phone's browser runs out and loses the picture altogether -- and on a
		# screen this size nobody could see the difference anyway. The menu hides the entry there as well; this is
		# the backstop for a saved file or a ?preset= link that asks for it.
		sh = mini(sh, 2)
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
	# how far off St Kilda's scenery keeps every block: past it the diggable dirt along Luna Park's wall is a flat band
	# instead of 650,000 blocks' faces, and the Carousel's twelve 30,000-triangle horses aren't drawn
	var scen := float(v.get("scenery", 0.0))
	VoxelParkDirt.detail_m = scen
	if arena.get("stkilda") and arena.stkilda:
		arena.stkilda.scenery(scen)
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
	# (chunk_wanted(), not chunk: through a staged rebuild the old enemies are still the ones in the arena, and a row
	# tapped twice must not leave the rebuild heading for the size that was asked for first)
	if arena.chunk_wanted() != int(v.chunk) and not arena._opts.has("chunk") and not (arena.net and arena.net.linked):
		if arena.debris:            # (built already: the new size built a slice a frame, the fight started over at the end)
			arena.rebuild_enemies(int(v.chunk))
		else:                       # (at the start: nothing made yet, it's all made at this size)
			arena.chunk = int(v.chunk)
	# your own Jared, his own setting: he's 650,000 cells at Fine where an enemy is 80,000, so he's the one thing a
	# phone still keeps chunky by default (Low). Before this he was forced chunky on every phone with no way back.
	# Building him is the slowest thing any setting asks for, so it goes through the arena's staged rebuild: the row
	# answers at once and he is built a slice a frame behind a line that says how far along it is.
	if VoxelArena.jared_chunk != int(v.get("jared", 1)) and not arena._opts.has("lightjared"):
		VoxelArena.jared_chunk = int(v.get("jared", 1))
		if arena.avatar:            # (at the start: made after this, at the new size)
			arena.rebuild_avatar()  # (655,000 cubes at Fine: a slice a frame, never inside the tap on the row)
	if restart and arena.debris:
		arena._respawn_all()
	# the three view fixes (CHOICES says what they are): all on unless the owner has turned one off to compare
	if arena.has_method("set_steady_view"):
		arena.set_steady_view(bool(v.get("steady", true)))
	VoxelTouch.fold = bool(v.get("fold", true))
	VoxelTouch.own_delta = bool(v.get("own", true))
	VoxelTouch.smooth = bool(v.get("smooth", false))
	arena.base_fov = float(v.fov)
	arena.mouse_sens = float(v.sens)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(v.volume))))
	Engine.max_fps = int(v.fps)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(v.vsync) else DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() != "headless":
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if bool(v.fullscreen) != fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(v.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)
