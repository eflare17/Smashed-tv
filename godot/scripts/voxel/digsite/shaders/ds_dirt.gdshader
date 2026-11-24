shader_type spatial;
// A clod in the air or on the roll (DsDirt): one lump per instance, the instance's transform only where it is. Its
// custom data says the rest: x its material, radius (m, in 800ths) and a number for its shape, packed (DsDirt._pack);
// y how far it's turned (rad); z, w the level line it turns about. Lit and coloured as the lumps lying on the loose
// dirt are (ds_clod.gdshader), so one landing and melting into them doesn't change its look; drawn after the ink, as
// they are, so no lump's ringed.
render_mode skip_vertex_transform, depth_draw_always;

uniform vec3 soil_cols[16];

varying float v_shade;
varying float v_low;
varying vec3 v_soil;

vec3 turn(vec3 p, vec3 axis, float angle) {
	return p * cos(angle) + cross(axis, p) * sin(angle) + axis * dot(axis, p) * (1.0 - cos(angle));
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float m = floor(c.x);
	float f = (c.x - m) * 800.0;
	float size = floor(f) / 400.0;
	float seed = fract(f);
	// its own shape: stretched a little, turned about its own way, before it rolls
	vec3 p = VERTEX * vec3(mix(0.85, 1.3, seed), 1.0, mix(0.8, 1.2, fract(seed * 7.0)));
	p = turn(p, normalize(vec3(sin(seed * 40.0), 0.35, cos(seed * 40.0))), seed * 6.2832);
	vec3 axis = vec3(c.z, 0.0, c.w);
	float al = length(axis);
	axis = al > 0.01 ? axis / al : vec3(1.0, 0.0, 0.0);
	p = turn(p, axis, c.y) * size;
	vec3 w = MODEL_MATRIX[3].xyz + p;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	if (size <= 0.001) {
		VERTEX = vec3(0.0);
	}
	v_shade = fract(seed * 7.3);
	v_low = clamp(p.y / max(size, 0.001) * 0.5 + 0.5, 0.0, 1.0);
	v_soil = soil_cols[clamp(int(m + 0.5), 0, 15)];
}

void fragment() {
	// flat faces, from the corner positions
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	vec3 col = v_soil * mix(0.8, 1.15, v_shade * v_shade);
	// darker underneath, as a lump lying among others is
	col *= mix(0.55, 1.08, smoothstep(0.0, 0.6, v_low));
	ALBEDO = col;
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float shadow = mix(1.0, smoothstep(0.35, 0.65, ATTENUATION), smoothstep(0.0, 0.3, nl));
	DIFFUSE_LIGHT += LIGHT_COLOR * clamp(nl * 0.85 + 0.15, 0.0, 1.0) * shadow;
}
