shader_type spatial;
// Black ink lines from the depth buffer alone, so the PC and the phone draw the same thing. Raw depth changes in a straight
// line across any flat surface however it's tilted, so a bend in it means a silhouette or a crease, with no false lines
// on ground seen at a low angle. It paints only the ink, without reading the picture back.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float line_px = 1.5;
uniform float threshold = 0.03;
uniform vec3 ink : source_color = vec3(0.05, 0.04, 0.035);

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
	ALBEDO = ink;
	ALPHA = smoothstep(threshold, threshold * 2.0, bend / max(nearest, 0.00001));
}
