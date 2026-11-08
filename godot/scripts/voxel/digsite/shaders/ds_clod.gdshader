shader_type spatial;
// One lump of dirt per instance (the digger game's clod.gdshader): flat faces, its own shade of its soil's colour
// (the instance colour), near black where it goes down between its neighbours. Drawn after the ink.
render_mode depth_draw_always;

varying float v_low;
varying vec3 v_col;

void vertex() {
	v_low = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	v_col = COLOR.rgb;
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	ALBEDO = v_col * mix(0.22, 1.1, smoothstep(0.0, 0.62, v_low));
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// soft, not stepped: on rough dirt, stepped light breaks into blotches
void light() {
	float nl = dot(NORMAL, LIGHT);
	float shadow = mix(1.0, smoothstep(0.35, 0.65, ATTENUATION), smoothstep(0.0, 0.3, nl));
	DIFFUSE_LIGHT += LIGHT_COLOR * clamp(nl * 0.85 + 0.15, 0.0, 1.0) * shadow;
}
