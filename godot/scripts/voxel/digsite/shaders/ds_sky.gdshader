shader_type sky;
// The Dig Site's sky (the digger game's): a saturated blue with flat, painted-looking clouds in two tones.
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 top : source_color = vec3(0.13, 0.42, 0.86);
uniform vec3 horizon : source_color = vec3(0.60, 0.83, 0.97);

void sky() {
	float y = max(EYEDIR.y, 0.0);
	vec3 col = mix(horizon, top, smoothstep(0.0, 0.55, y));
	vec2 p = EYEDIR.xz / (y + 0.18) * 0.085;
	float n = texture(noise_tex, p).r * 0.65 + texture(noise_tex, p * 2.7).r * 0.35;
	float fade = smoothstep(0.02, 0.2, y);
	float cloud = smoothstep(0.56, 0.58, n) * fade;
	float lit = smoothstep(0.62, 0.64, n);
	col = mix(col, mix(vec3(0.82, 0.88, 0.95), vec3(1.0), lit), cloud);
	COLOR = col;
}
