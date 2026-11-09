shader_type spatial;
// One lump of dirt per instance (the digger game's clod.gdshader, on the Dig Site's grid): laid once at a fixed spot
// (DsClods), each finds its height, whether it should be there and how big from the ground's textures (DsTerrain:
// each column's top cell, how deep the loose dirt lies, its material, and how far its surface is still gliding), so
// nothing needs laying again: dirt arriving brings lumps up out of it, scraping it away takes them with it, and while
// the ground under a lump moves, the lump turns over. Kept smaller than its distance from any blade or bucket nearby
// (keep_*: DsClods), so none pokes through the steel. Flat faces, near black where it goes down between its
// neighbours. Drawn after the ink, so the ink doesn't ring every lump.
render_mode skip_vertex_transform, depth_draw_always;

uniform sampler2D show_off_tex : filter_nearest, repeat_disable;
uniform sampler2D topo_tex : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(512.0, 512.0);
uniform float cell = 0.125;
uniform vec3 grid_origin = vec3(0.0);
uniform vec3 soil_cols[16];
uniform int keep_n = 0;
uniform vec4 keep_rx[8];
uniform vec4 keep_ry[8];
uniform vec4 keep_rz[8];
uniform vec3 keep_half[8];

varying float v_shade;
varying float v_low;
varying vec3 v_soil;

// the drawn surface's height (metres, from the grid's corner) at p, blended between the four columns round it
float hgt(vec2 p) {
	vec2 g = p / cell - 0.5;
	ivec2 c = ivec2(floor(g));
	vec2 f = fract(g);
	ivec2 hi = ivec2(grid_size) - 1;
	float h[4];
	for (int k = 0; k < 4; k++) {
		ivec2 q = clamp(c + ivec2(k & 1, k >> 1), ivec2(0), hi);
		h[k] = (texelFetch(topo_tex, q, 0).r * 255.0 + 1.0 + texelFetch(show_off_tex, q, 0).r) * cell;
	}
	return mix(mix(h[0], h[1], f.x), mix(h[2], h[3], f.x), f.y);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec2 at = root.xz - grid_origin.xz;
	ivec2 col = clamp(ivec2(floor(at / cell)), ivec2(0), ivec2(grid_size) - 1);
	vec4 t = texelFetch(topo_tex, col, 0);
	// how deep the loose dirt lies here (m; the texture has eighths of a cell): a lump only stands where there's enough
	// to hold one its size
	float deep = t.g * 255.0 / 8.0 * cell;
	float size = length(MODEL_MATRIX[1].xyz);
	float keep = smoothstep(size * 0.12, size * 0.8, deep);
	float seed = fract(root.x * 12.9898 + root.z * 78.233);
	float h = hgt(at);
	vec3 centre = vec3(root.x, grid_origin.y + h, root.z);
	// kept smaller than its distance from a blade's or a bucket's steel
	for (int k = 0; k < keep_n; k++) {
		vec4 c4 = vec4(centre, 1.0);
		vec3 q = vec3(dot(keep_rx[k], c4), dot(keep_ry[k], c4), dot(keep_rz[k], c4));
		vec3 out_by = abs(q) - keep_half[k];
		float d = max(max(out_by.x, out_by.y), out_by.z);
		keep *= clamp(d / max(size, 0.001), 0.0, 1.0);
	}
	// the ground rising or falling under it turns it over and shuffles it about, so pushed dirt churns; settled stays still
	float angle = h * (7.0 + seed * 9.0);
	vec3 axis = normalize(vec3(sin(seed * 40.0), 0.35, cos(seed * 40.0)));
	vec3 p = mat3(MODEL_MATRIX) * VERTEX * keep;
	p = p * cos(angle) + cross(axis, p) * sin(angle) + axis * dot(axis, p) * (1.0 - cos(angle));
	vec3 shuffle = vec3(sin(h * 5.0 + seed * 20.0), 0.0, cos(h * 4.0 + seed * 31.0)) * 0.1;
	vec3 w = vec3(root.x, 0.0, root.z) + p + shuffle;
	// part buried, so it lies in the heap rather than balanced on it
	float sunk = grid_origin.y + h - size * keep * 0.35;
	w.y += sunk;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	if (keep <= 0.001) {
		VERTEX = vec3(0.0);
	}
	v_shade = fract(seed * 7.3);
	v_low = clamp((w.y - sunk) / max(size * keep * 0.9, 0.001), 0.0, 1.0);
	int m = int(t.b * 255.0 + 0.5);
	v_soil = soil_cols[clamp(m, 0, 15)];
}

void fragment() {
	// flat faces, from the corner positions, so each lump needs only its 12 corners
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	vec3 col = v_soil * mix(0.8, 1.15, v_shade * v_shade);
	// near black where it goes down between its neighbours: the cracks are what make it read as a heap of chunks
	col *= mix(0.22, 1.1, smoothstep(0.0, 0.62, v_low));
	ALBEDO = col;
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
