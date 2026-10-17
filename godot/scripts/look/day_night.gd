class_name DayNight
extends Node3D
## The day and night cycle's look (1.4): the sun (and at night the moon) across the sky, the sky's colours, the
## ambient light, the distance haze's colour, and the lamps (on at dusk, off in the morning), all from the
## GameClock's hour. Owned by the Lighting session; LightingInstall adds it.
##
## The sun rises in the east (+x), crosses the north (it's Australia: the HTML game lights its north faces most)
## and sets in the west. One DirectionalLight3D does the sun by day and the moon by night (it swaps over in the
## dark between them), so there's only ever one shadowed light.
##
## The look of each time of day is a key in KEYS; between keys everything blends.

const SKY_SHADER := preload("res://scripts/look/sky.gdshader")

## The hour each look is for, and the look. sky: top, horizon; light: colour, energy (the sun or the moon);
## amb: the ambient light; fog: the haze; lamps: 0..1 how on the lamps are; stars: 0..1.
const KEYS := [
	[0.0, {"top": "#040916", "hor": "#0c1730", "light": "#8ca6ff", "le": 0.22, "amb": "#262c4a", "fog": "#0a1222", "lamps": 1.0, "stars": 1.0}],
	[4.8, {"top": "#060c20", "hor": "#141e3c", "light": "#8ca6ff", "le": 0.2, "amb": "#282e4c", "fog": "#0e1628", "lamps": 1.0, "stars": 1.0}],
	[5.85, {"top": "#1c2650", "hor": "#6a5272", "light": "#8ca6ff", "le": 0.0, "amb": "#4a4a66", "fog": "#3a3850", "lamps": 1.0, "stars": 0.4}],
	[6.4, {"top": "#4466a6", "hor": "#f2a272", "light": "#ff9a66", "le": 0.22, "amb": "#7a6e78", "fog": "#c8a090", "lamps": 0.8, "stars": 0.0}],
	[7.3, {"top": "#5a8ad8", "hor": "#f2d2b0", "light": "#ffd8b0", "le": 0.36, "amb": "#9c9ca2", "fog": "#d4d0c8", "lamps": 0.0, "stars": 0.0}],
	[9.5, {"top": "#3e7ad6", "hor": "#aacdec", "light": "#fff6e6", "le": 0.4, "amb": "#acaeb6", "fog": "#ccdae8", "lamps": 0.0, "stars": 0.0}],
	[15.5, {"top": "#3e7ad6", "hor": "#aacdec", "light": "#fff2e0", "le": 0.4, "amb": "#acaeb6", "fog": "#ccdae8", "lamps": 0.0, "stars": 0.0}],
	[17.8, {"top": "#4a78c4", "hor": "#f6c48a", "light": "#ffc27a", "le": 0.46, "amb": "#a49488", "fog": "#e6c8a0", "lamps": 0.0, "stars": 0.0}],
	[19.0, {"top": "#3e4c90", "hor": "#ff9056", "light": "#ff8a4a", "le": 0.36, "amb": "#7e6670", "fog": "#d88a6a", "lamps": 0.6, "stars": 0.0}],
	[19.9, {"top": "#1e2654", "hor": "#a04c5c", "light": "#ff6a4a", "le": 0.0, "amb": "#5a4e66", "fog": "#5a3a50", "lamps": 1.0, "stars": 0.2}],
	[20.8, {"top": "#0a1028", "hor": "#2a2448", "light": "#8ca6ff", "le": 0.18, "amb": "#2c3250", "fog": "#161a32", "lamps": 1.0, "stars": 0.8}],
	[24.0, {"top": "#040916", "hor": "#0c1730", "light": "#8ca6ff", "le": 0.22, "amb": "#262c4a", "fog": "#0a1222", "lamps": 1.0, "stars": 1.0}],
]
## When the sun is up (the light is the sun between these, the moon outside them).
const SUNRISE := 5.85
const SUNSET := 19.9
## The sun's highest, degrees above the horizon (at 1 pm), and the lowest it's allowed to shine from (a very
## low sun throws shadows across the whole yard).
const SUN_MAX_DEG := 62.0
const SUN_MIN_DEG := 12.0
const NOON := 12.9
## The moon: where it hangs (high in the north-west) and how high.
const MOON_AZ_DEG := 125.0
const MOON_DEG := 52.0

## The ambient light's strength (it is most of the light: the pictures already have their shading drawn in).
var ambient_energy: float = 1.0
## The sun's strength multiplier.
var light_scale: float = 1.0
## The hour shown (follows the GameClock unless hour_override >= 0).
var hour: float = 12.0
var hour_override: float = -1.0

var sun: DirectionalLight3D
var env: Environment
var lamps: Array = []          # [{light: OmniLight3D, energy: float, glow: Node3D}]
var lamp_level: float = 0.0    # 0..1, the lamps' brightness now
## Which lamps may be on (LookPass's quality setting): func(lamp: Dictionary) -> bool; unset: all.
var lamp_filter: Callable
var sky_mat: ShaderMaterial
## The look now (blended from KEYS), for others (the water, the glows): read only.
var look: Dictionary = {}

var _keys: Array = []

func _init() -> void:
	for k in KEYS:
		var d: Dictionary = {}
		for key in k[1]:
			var v = k[1][key]
			d[key] = Color(v) if v is String else float(v)
		_keys.append([float(k[0]), d])

func setup(sun_: DirectionalLight3D, env_: Environment) -> void:
	sun = sun_
	env = env_
	if sun:
		sun.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # turned in _process by the clock
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	if env:
		if env.sky == null:
			env.sky = Sky.new()
		env.sky.sky_material = sky_mat
		env.sky.radiance_size = Sky.RADIANCE_SIZE_32
		env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
		env.background_mode = Environment.BG_SKY
		# the sky is only a background: nothing lights or reflects from it, so it's never baked into a radiance
		# map (its colours change every frame)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	update_now()

## The clock (or the override) to the scene.
func update_now() -> void:
	var c := get_node_or_null("/root/GameClock")
	if hour_override >= 0.0:
		hour = hour_override
	elif c:
		hour = c.hour
	apply(hour)

func _process(_dt: float) -> void:
	update_now()

## The look at hour h: blended between the keys either side.
func look_for(h: float) -> Dictionary:
	h = fposmod(h, 24.0)
	for i in _keys.size() - 1:
		var a: Array = _keys[i]
		var b: Array = _keys[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / maxf(0.0001, b[0] - a[0])
			t = t * t * (3.0 - 2.0 * t)
			var out: Dictionary = {}
			for key in a[1]:
				var va = a[1][key]
				var vb = b[1][key]
				out[key] = va.lerp(vb, t) if va is Color else lerpf(va, vb, t)
			return out
	return _keys[0][1].duplicate()

## Toward the sun at hour h (a unit vector, y up); below the horizon outside sunrise..sunset.
static func sun_dir_at(h: float) -> Vector3:
	var day_t := (h - SUNRISE) / (SUNSET - SUNRISE)            # 0 at sunrise, 1 at sunset
	var az := lerpf(0.0, PI, clampf(day_t, 0.0, 1.0))          # 0 east, PI/2 north, PI west
	# the height: up from the horizon to its highest at NOON, and back down
	var e: float
	if h <= NOON:
		e = sin(clampf((h - SUNRISE) / (NOON - SUNRISE), 0.0, 1.0) * PI / 2.0)
	else:
		e = sin(clampf((SUNSET - h) / (SUNSET - NOON), 0.0, 1.0) * PI / 2.0)
	var el := deg_to_rad(SUN_MAX_DEG) * e
	return Vector3(cos(el) * cos(az), sin(el), -cos(el) * sin(az)).normalized()

static func moon_dir() -> Vector3:
	var az := deg_to_rad(MOON_AZ_DEG)
	var el := deg_to_rad(MOON_DEG)
	return Vector3(cos(el) * cos(az), sin(el), -cos(el) * sin(az)).normalized()

func is_sun_up(h: float) -> bool:
	return h >= SUNRISE and h <= SUNSET

func apply(h: float) -> void:
	look = look_for(h)
	var sd := sun_dir_at(h)
	var md := moon_dir()
	var up := is_sun_up(h)
	if sun:
		var ld := sd if up else md
		if up and ld.y < sin(deg_to_rad(SUN_MIN_DEG)):
			# keep the light itself from lying flat (the sky still shows the sun low)
			var flat := Vector3(ld.x, 0, ld.z).normalized()
			var e := deg_to_rad(SUN_MIN_DEG)
			ld = flat * cos(e) + Vector3.UP * sin(e)
		sun.global_transform = Transform3D(Basis.looking_at(-ld, Vector3.UP if absf(ld.y) < 0.99 else Vector3.FORWARD), sun.global_position)
		sun.light_color = look.light
		sun.light_energy = look.le * light_scale
		sun.visible = sun.light_energy > 0.005
	if env:
		env.ambient_light_color = look.amb
		env.ambient_light_energy = ambient_energy
		env.fog_light_color = look.fog
	if sky_mat:
		sky_mat.set_shader_parameter("top_color", look.top)
		sky_mat.set_shader_parameter("horizon_color", look.hor)
		sky_mat.set_shader_parameter("ground_color", (look.hor as Color).lerp(Color8(82, 136, 52), 0.5) * clampf(look.amb.v * 1.3, 0.2, 1.0))
		sky_mat.set_shader_parameter("sun_dir", sd)
		var sc: Color = look.light if up else Color(1.0, 0.6, 0.4)
		sky_mat.set_shader_parameter("sun_color", sc)
		sky_mat.set_shader_parameter("sun_glow", clampf(sd.y * 4.0 + 0.6, 0.0, 1.0))
		sky_mat.set_shader_parameter("moon_dir", md)
		sky_mat.set_shader_parameter("moon", look.stars)
		sky_mat.set_shader_parameter("stars", look.stars)
		sky_mat.set_shader_parameter("twinkle", float(Time.get_ticks_msec() % 100000) / 1000.0)
	lamp_level = look.lamps
	for l in lamps:
		var o: Light3D = l.light
		o.light_energy = l.energy * lamp_level
		o.visible = lamp_level > 0.01 and (not lamp_filter.is_valid() or lamp_filter.call(l))
		if l.has("glow") and l.glow:
			l.glow.visible = lamp_level > 0.01
			var gm = l.glow.get("material_override")
			if gm is ShaderMaterial:
				gm.set_shader_parameter("level", lamp_level)

## A lamp: an OmniLight3D at (x, y, z) in HTML units, its colour, strength and reach (units). A small glowing
## bulb is drawn there too when bulb is true (a ceiling light, seen in first person).
func add_lamp(x: float, y: float, z: float, col: Color, energy: float, reach: float, bulb: bool = true) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.name = "Lamp%d" % lamps.size()
	o.position = GameData.world_to_3d(x, y, z)
	o.light_color = col
	o.light_energy = energy
	o.omni_range = reach * GameData.UNIT
	o.omni_attenuation = 1.1
	o.shadow_enabled = false
	o.light_specular = 0.0
	add_child(o)
	var e := {"light": o, "energy": energy}
	if bulb:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.12
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = _bulb_shader()
		m.set_shader_parameter("col", col)
		mi.material_override = m
		mi.position = o.position + Vector3(0, 0.02, 0)
		mi.layers = 1 << (WorldBuilder.ROOF_LAYER - 1)    # with the ceiling: not in the view from above
		add_child(mi)
		e["glow"] = mi
	lamps.append(e)
	return o

static var _bulb: Shader
static func _bulb_shader() -> Shader:
	if _bulb == null:
		_bulb = Shader.new()
		_bulb.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.8, 0.5);
uniform float level = 1.0;
void fragment() {
	ALBEDO = mix(vec3(0.35, 0.33, 0.3), col * 2.5, level);
}
"""
	return _bulb
