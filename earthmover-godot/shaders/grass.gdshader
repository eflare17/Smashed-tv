shader_type spatial;
// One grass blade per instance. Each blade finds its own height and whether it should exist from the same grid textures
// as the ground: scrape or bury a cell and its blades vanish with no rebuilding. Drawn in the transparent pass, after the
// ink pass, so the ink doesn't draw a line round every blade.
render_mode cull_disabled, depth_draw_always, skip_vertex_transform;
#include "res://shaders/toon.gdshaderinc"

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D data_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 root_a : source_color = vec3(0.24, 0.45, 0.16);
uniform vec3 tip_a : source_color = vec3(0.42, 0.66, 0.24);
uniform vec3 tip_b : source_color = vec3(0.50, 0.72, 0.26);

const float CELL = 0.25;
uniform float HALF = 32.0;

varying float v_t;
varying float v_patch;
varying vec3 v_up;

float hgt(vec2 p) {
	vec2 g = (p + HALF) / CELL;
	ivec2 c = ivec2(floor(g));
	vec2 f = fract(g);
	float a = mix(texelFetch(height_tex, c, 0).r, texelFetch(height_tex, c + ivec2(1, 0), 0).r, f.x);
	float b = mix(texelFetch(height_tex, c + ivec2(0, 1), 0).r, texelFetch(height_tex, c + ivec2(1, 1), 0).r, f.x);
	return mix(a, b, f.y);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec2 uv = (root.xz + HALF + CELL * 0.5) / (HALF * 2.0 + CELL);
	vec4 m = textureLod(data_tex, uv, 0.0);
	float grass = 1.0 - min(m.r + m.g + m.b, 1.0);
	float edge = max(abs(root.x), abs(root.z));
	float keep = smoothstep(0.55, 0.8, grass) * (1.0 - smoothstep(25.0, 31.5, edge) * 0.8);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX * vec3(1.0, keep, 1.0), 1.0)).xyz;
	w.y += hgt(root.xz);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	if (keep <= 0.0) {
		VERTEX = vec3(0.0);
	}
	v_up = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	NORMAL = v_up;
	v_t = UV.y;
	v_patch = textureLod(noise_tex, root.xz * 0.045, 0.0).r;
}

void fragment() {
	vec3 tip = mix(tip_a, tip_b, smoothstep(0.47, 0.53, v_patch));
	ALBEDO = mix(root_a, tip, smoothstep(0.1, 0.85, v_t));
	ALPHA = 1.0;
	// Lit like the ground on both faces. Left alone, Godot flips the normal on a blade's back face and it goes dark.
	NORMAL = v_up;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
