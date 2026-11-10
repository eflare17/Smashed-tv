shader_type spatial;
// The PC's water (Forward+ only): small moving waves, the ground seen through it and bent by them, clearer in the shallows and darker
// where it's deep, the sky and whatever's round it reflected off it (with screen-space reflections on), and foam where it meets the
// dirt. Phones and the web keep the plain water, which costs next to nothing.
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.30, 0.58, 0.68);
uniform vec3 deep : source_color = vec3(0.08, 0.24, 0.34);
uniform vec3 muddy : source_color = vec3(0.42, 0.33, 0.2);
uniform vec3 foam_col : source_color = vec3(0.94, 0.95, 0.92);
uniform float clear_m = 0.45;       // m of water before it's all its own colour
uniform float mud = 0.26;           // how brown it is: fresh flood water carries dirt

varying vec3 v_world;

float wave_h(vec2 p, float t) {
	return (sin(p.x * 2.1 + t * 1.6) * 0.5 + sin(p.y * 1.7 - t * 1.3) * 0.5 + sin((p.x + p.y) * 3.3 + t * 2.2) * 0.25) * 0.006;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave_h(v_world.xz, TIME);
}

void fragment() {
	// Ripples: two layers of noise drifting different ways, turned into a bent normal.
	vec2 a = v_world.xz * 0.32 + vec2(TIME * 0.031, TIME * 0.017);
	vec2 b = v_world.xz * 0.71 - vec2(TIME * 0.022, -TIME * 0.036);
	float e = 0.015;
	float ha = texture(noise_tex, a).r;
	float hb = texture(noise_tex, b).r;
	float dx = (texture(noise_tex, a + vec2(e, 0.0)).r - ha) + (texture(noise_tex, b + vec2(e, 0.0)).r - hb) * 0.6;
	float dz = (texture(noise_tex, a + vec2(0.0, e)).r - ha) + (texture(noise_tex, b + vec2(0.0, e)).r - hb) * 0.6;
	vec3 n_world = normalize(vec3(-dx * 2.4, 1.0, -dz * 2.4));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// How much water there is between the surface and the ground behind it, along this pixel.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	float thick = max(-behind.z - (-VERTEX.z), 0.0);
	float murk = clamp(thick / clear_m, 0.0, 1.0);

	// The ground seen through it, bent a little by the ripples where it's deep enough to bend.
	vec2 bent = SCREEN_UV + n_world.xz * 0.025 * murk;
	vec3 under = textureLod(screen_tex, bent, 0.0).rgb;
	vec3 body = mix(mix(shallow, deep, murk), muddy, mud);
	vec3 col = mix(under, body, 0.2 + 0.7 * murk);

	// Foam in a ragged line where it laps at the dirt.
	float edge = 1.0 - smoothstep(0.0, 0.06, thick);
	float froth = smoothstep(0.42, 0.58, texture(noise_tex, v_world.xz * 1.4 + vec2(TIME * 0.05, 0.0)).r + edge * 0.4);
	col = mix(col, foam_col, edge * froth * 0.85);

	ALBEDO = col * 0.35;
	EMISSION = col * 0.65;
	ROUGHNESS = mix(0.04, 0.6, edge * froth);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
