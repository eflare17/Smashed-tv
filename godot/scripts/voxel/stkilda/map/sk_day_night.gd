# (Copied from stkilda-godot scripts/town/day_night.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkDayNight
extends Node
## Day or night (N switches, easing over a couple of seconds). At night: a dark blue sky and a dim bluish moon instead
## of the sun; the windows round town lit, some of them (SkFacades.glass: most shopfronts, about half the offices and
## flats, fewer houses); Mr Moon's face floodlit (it's lit after dark: Luna Park at events); the park's lamp globes
## glowing, with a warm pool of light on the ground under each; a soft light over the rides; the car's headlights on.
## Luna Park opened in 1912 lit by thousands of bulbs, but where they all are now isn't known here, so there are no
## made-up strings of bulbs on the towers or the coaster.

const DAY := {"sun": 0.78, "sun_col": Color("#ffe9cc"), "top": Color("#2a73c9"), "low": Color("#a9cdea"),
	"ground": Color("#a9cbdb"), "amb": Color("#c4d2e6"), "amb_e": 0.36, "fog": Color("#a9cdea"), "exp": 0.92,
	"clouds": 0.85, "glow": 1.1, "glow_i": 0.35}
const NIGHT := {"sun": 0.14, "sun_col": Color("#9fb2ff"), "top": Color("#050a1c"), "low": Color("#1a2746"),
	"ground": Color("#101a30"), "amb": Color("#3c4c80"), "amb_e": 0.3, "fog": Color("#141f38"), "exp": 1.15,
	"clouds": 0.18, "glow": 0.75, "glow_i": 0.6}

## The park's lamp globes (SkLunaExtras puts them here as it builds them).
static var lamps: Array = []
## Other bulbs lit at night (the coaster's tunnel: SkScenicRailway puts them here), each [where, colour].
static var bulbs: Array = []

var town: SkTownBuilder
var face: Transform3D
var car: Node3D
var night := false
var t := 0.0                            # 0 day, 1 night
var _lit: Array = []                    # the things only on at night
var _lights: Array = []                 # [light, its night energy]

func setup(tb: SkTownBuilder, f: Transform3D, c: Node3D) -> void:
	town = tb
	face = f
	car = c

func _ready() -> void:
	# the lamps' globes, glowing, and a warm pool of light under each
	if not lamps.is_empty():
		var globe := SphereMesh.new()
		globe.radius = 0.25
		globe.height = 0.5
		globe.radial_segments = 8
		globe.rings = 4
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1.0, 0.9, 0.7)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.85, 0.6)
		gm.emission_energy_multiplier = 3.0
		globe.material = gm
		_lit.append(_many(globe, lamps, Vector3.ZERO, Vector3.ONE, "Globes"))
		var pool := QuadMesh.new()
		pool.orientation = PlaneMesh.FACE_Y
		pool.size = Vector2(1, 1)
		var pm := SkContactShade.blob_material().duplicate() as StandardMaterial3D
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.vertex_color_use_as_albedo = false
		pm.albedo_color = Color(1.0, 0.75, 0.45, 0.55)
		pool.material = pm
		var under := []
		for k in range(0, lamps.size(), 2):
			under.append(Vector3((lamps[k] as Vector3).x + 0.5, 0, (lamps[k] as Vector3).z))
		_lit.append(_many(pool, under, Vector3(0, SkContactShade.Y + 0.01, 0), Vector3(9, 1, 9), "LightPools"))
	# the coaster tunnel's bulbs (dim, warm)
	if not bulbs.is_empty():
		var at := []
		var cols := []
		for b in bulbs:
			at.append(b[0])
			cols.append((b[1] as Color) * 0.55)
		SkRideLights._bulbs(get_parent() as Node3D, at, 0.0, cols)
	# the rides' coloured bulbs (SkRideLights) are shown with the rest
	# Mr Moon floodlit, from out on the forecourt
	var flood := SpotLight3D.new()
	flood.name = "MoonFlood"
	flood.light_color = Color(1.0, 0.93, 0.8)
	flood.spot_range = 45.0
	flood.spot_angle = 32.0
	flood.shadow_enabled = false
	add_child(flood)
	flood.global_transform = Transform3D(Basis.looking_at((face * Vector3(0, 8, 0)) - (face * Vector3(0, 2.0, 22)), Vector3.UP), face * Vector3(0, 2.0, 22))
	_lights.append([flood, 6.0])
	# a soft light over the rides: warm, and pink and blue
	for spot in [[Vector3(0, 14, -45), Color(1.0, 0.8, 0.55)], [Vector3(-25, 12, -80), Color(1.0, 0.55, 0.8)], [Vector3(20, 12, -95), Color(0.55, 0.7, 1.0)]]:
		var o := OmniLight3D.new()
		o.light_color = spot[1]
		o.omni_range = 45.0
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		add_child(o)
		o.global_position = face * (spot[0] as Vector3)
		_lights.append([o, 1.4])                 # (softer: each ride has its own coloured light now, SkRideLights)
	# the car's headlights
	if car:
		for x in [-0.7, 0.7]:
			var hl := SpotLight3D.new()
			hl.name = "Headlight"
			hl.light_color = Color(1.0, 0.95, 0.85)
			hl.spot_range = 40.0
			hl.spot_angle = 24.0
			hl.shadow_enabled = false
			car.add_child(hl)
			hl.position = Vector3(x, 0.9, -2.6)
			hl.rotation = Vector3(-0.08, 0, 0)
			_lights.append([hl, 4.0])
	_apply()

func _many(mesh: Mesh, at: Array, lift: Vector3, size: Vector3, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for k in at.size():
		mm.set_instance_transform(k, Transform3D(Basis().scaled(size), (at[k] as Vector3) + lift))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func toggle() -> void:
	night = not night

func _process(dt: float) -> void:
	var want := 1.0 if night else 0.0
	if is_equal_approx(t, want):
		return
	t = move_toward(t, want, dt / 2.0)
	_apply()

func _apply() -> void:
	var k := smoothstep(0.0, 1.0, t)
	var e := town.environment
	town.sun.light_energy = lerpf(DAY.sun, NIGHT.sun, k)
	town.sun.light_color = (DAY.sun_col as Color).lerp(NIGHT.sun_col, k)
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = (DAY.top as Color).lerp(NIGHT.top, k)
	sm.sky_horizon_color = (DAY.low as Color).lerp(NIGHT.low, k)
	sm.ground_horizon_color = (DAY.ground as Color).lerp(NIGHT.ground, k)
	sm.sky_cover_modulate = Color(1, 1, 1, lerpf(DAY.clouds, NIGHT.clouds, k))
	sm.sun_angle_max = lerpf(20.0, 4.0, k)
	e.ambient_light_color = (DAY.amb as Color).lerp(NIGHT.amb, k)
	e.ambient_light_energy = lerpf(DAY.amb_e, NIGHT.amb_e, k)
	e.fog_light_color = (DAY.fog as Color).lerp(NIGHT.fog, k)
	e.tonemap_exposure = lerpf(DAY.exp, NIGHT.exp, k)
	e.glow_hdr_threshold = lerpf(DAY.glow, NIGHT.glow, k)
	e.glow_intensity = lerpf(DAY.glow_i, NIGHT.glow_i, k)            # (the bulbs bloom more at night)
	for g in SkFacades.glass:
		(g as ShaderMaterial).set_shader_parameter("night", k)
	SkRideLights.night = k
	for n in SkRideLights.night_only:
		if is_instance_valid(n):
			(n as Node3D).visible = k > 0.02
	for m in SkRideLights.mats:
		(m as ShaderMaterial).set_shader_parameter("night", k)
	for n in get_tree().get_nodes_in_group("night_lights"):
		(n as Node3D).visible = k > 0.3
	for n in _lit:
		(n as Node3D).visible = k > 0.05
	for l in _lights:
		(l[0] as Light3D).light_energy = float(l[1]) * k
		(l[0] as Light3D).visible = k > 0.02
