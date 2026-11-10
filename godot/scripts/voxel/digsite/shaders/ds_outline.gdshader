shader_type spatial;
// Black ink lines from the depth buffer alone (the digger game's outline.gdshader). Raw depth changes in a straight
// line across any flat surface however it's tilted, so a bend in it means a silhouette or a crease, with no false
// lines on ground seen at a low angle. It paints only the ink, without reading the picture back.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float line_px = 1.5;
uniform float threshold = 0.05;
uniform vec3 ink : source_color = vec3(0.05, 0.04, 0.035);
uniform float fade_from = 70.0;     // m: past this the ink thins out, gone by fade_to (far off, the ground's gentle rises
uniform float fade_to = 140.0;      // drew lines across the paddock like scratches; nearer than that the trees want their ink)

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 p = line_px * (VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	float c = texture(depth_tex, SCREEN_UV).r;
	float l = texture(depth_tex, SCREEN_UV - vec2(p.x, 0.0)).r;
	float r = texture(depth_tex, SCREEN_UV + vec2(p.x, 0.0)).r;
	float d = texture(depth_tex, SCREEN_UV - vec2(0.0, p.y)).r;
	float u = texture(depth_tex, SCREEN_UV + vec2(0.0, p.y)).r;
	float a = texture(depth_tex, SCREEN_UV + p).r;
	float b = texture(depth_tex, SCREEN_UV - p).r;
	float e = texture(depth_tex, SCREEN_UV + vec2(p.x, -p.y)).r;
	float f = texture(depth_tex, SCREEN_UV + vec2(-p.x, p.y)).r;
	float bend = max(max(abs(l + r - 2.0 * c), abs(u + d - 2.0 * c)), max(abs(a + b - 2.0 * c), abs(e + f - 2.0 * c)));
	float nearest = max(c, max(max(l, r), max(u, d)));
	// how far away this is (the depth buffer's raw value back to metres)
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, c * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, c);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float dist = -view.z / view.w;
	ALBEDO = ink;
	ALPHA = smoothstep(threshold, threshold * 2.0, bend / max(nearest, 0.00001)) * (1.0 - smoothstep(fade_from, fade_to, dist));
}
