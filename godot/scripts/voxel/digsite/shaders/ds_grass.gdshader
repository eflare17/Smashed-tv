shader_type spatial;
// One grass blade per instance (the digger game's grass.gdshader, without the textures: here the blades are laid
// out again whenever their ground's redrawn, so a dug cell simply has none). Drawn after the ink, so the ink
// doesn't draw a line round every blade.
render_mode cull_disabled, depth_draw_always;
#include "ds_toon.gdshaderinc"

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 root_a : source_color = vec3(0.22, 0.42, 0.15);
uniform vec3 tip_a : source_color = vec3(0.38, 0.61, 0.22);
uniform vec3 tip_b : source_color = vec3(0.45, 0.66, 0.24);

varying float v_t;
varying float v_patch;
varying vec3 v_up;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	v_up = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	v_t = UV.y;
	v_patch = textureLod(noise_tex, root.xz * 0.045, 0.0).r;
}

void fragment() {
	vec3 tip = mix(tip_a, tip_b, smoothstep(0.47, 0.53, v_patch));
	ALBEDO = mix(root_a, tip, smoothstep(0.1, 0.85, v_t));
	ALPHA = 1.0;
	// lit like the ground on both faces (left alone, Godot flips the normal on a blade's back face and it goes dark)
	NORMAL = v_up;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
