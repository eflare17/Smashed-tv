shader_type spatial;
// One real lump of dirt per instance. Like a grass blade, each one finds its height and whether it should exist from the grid's
// textures, so nothing needs rebuilding: dirt arriving brings lumps up out of it, scraping it away takes them with it, and
// while the ground under a lump is moving, the lump rolls. Only for looks: the soil itself is all in the simulation.
// Drawn in the transparent pass, after the ink pass, so the ink doesn't draw a line round every lump.
render_mode skip_vertex_transform, depth_draw_always;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D data_tex : filter_linear, repeat_disable;
uniform sampler2D dust_tex : filter_linear, repeat_disable;
uniform vec3 soil_a : source_color = vec3(0.52, 0.28, 0.19);
uniform vec3 soil_b : source_color = vec3(0.38, 0.19, 0.13);
uniform vec3 dust_a : source_color = vec3(0.80, 0.78, 0.70);

const float CELL = 0.25;
uniform float HALF = 32.0;

varying float v_shade;
varying float v_low;
varying float v_dusty;
varying float v_hollow;

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
	vec2 look = textureLod(dust_tex, uv, 0.0).rg;
	// How deep the loose stuff lies here, in metres. A lump only stands where there's enough dirt to hold one its size.
	float deep = look.g * 255.0 * 0.004;
	float size = length(MODEL_MATRIX[1].xyz);
	float keep = smoothstep(size * 0.12, size * 0.8, deep);
	float dusty = smoothstep(0.44, 0.56, look.r);
	// Cracker dust is fine stuff: its lumps stay small.
	keep *= mix(1.0, 0.4, dusty);
	float seed = fract(root.x * 12.9898 + root.z * 78.233);
	float h = hgt(root.xz);
	// The ground rising or falling under it turns it over and shuffles it about, so pushed dirt churns. Settled dirt stays still.
	float angle = h * (7.0 + seed * 9.0);
	vec3 axis = normalize(vec3(sin(seed * 40.0), 0.35, cos(seed * 40.0)));
	vec3 p = mat3(MODEL_MATRIX) * VERTEX * keep;
	p = p * cos(angle) + cross(axis, p) * sin(angle) + axis * dot(axis, p) * (1.0 - cos(angle));
	vec3 shuffle = vec3(sin(h * 5.0 + seed * 20.0), 0.0, cos(h * 4.0 + seed * 31.0)) * 0.1;
	vec3 w = root + p + shuffle;
	// Part buried, so it looks like it's lying in the heap rather than balanced on it.
	float sunk = h - size * keep * 0.35;
	w.y += sunk;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	if (keep <= 0.0) {
		VERTEX = vec3(0.0);
	}
	v_shade = fract(seed * 7.3);
	v_low = clamp((w.y - sunk) / max(size * keep * 0.9, 0.001), 0.0, 1.0);
	v_dusty = dusty;
	v_hollow = textureLod(data_tex, uv, 0.0).a;
}

void fragment() {
	// Flat faces, worked out from the corner positions so each lump only needs its 12 corners.
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	vec3 col = mix(mix(soil_b, soil_a, v_shade * v_shade), dust_a, v_dusty);
	// Near black where it goes down between its neighbours: the cracks are what make it read as a heap of chunks.
	col *= mix(0.22, 1.1, smoothstep(0.0, 0.62, v_low));
	col *= mix(vec3(0.42, 0.36, 0.40), vec3(1.0), v_hollow);
	ALBEDO = col;
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// Soft, not stepped: on rough dirt, stepped light breaks into blotches.
void light() {
	float nl = dot(NORMAL, LIGHT);
	float shadow = mix(1.0, smoothstep(0.35, 0.65, ATTENUATION), smoothstep(0.0, 0.3, nl));
	DIFFUSE_LIGHT += LIGHT_COLOR * clamp(nl * 0.85 + 0.15, 0.0, 1.0) * shadow;
}
