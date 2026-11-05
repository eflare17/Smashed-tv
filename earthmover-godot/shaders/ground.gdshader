shader_type spatial;
// The ground: a plain grid whose height comes from the height texture, and whose look comes from the data texture
// (R loose soil, G rock, B packed soil, A shading in hollows). Both are the dirt simulation's grid, so when the real
// simulation exists it only has to update those textures.

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D data_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D dust_tex : filter_linear, repeat_disable;
uniform sampler2D clods_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 dust_a : source_color = vec3(0.80, 0.78, 0.70);
uniform vec3 dust_b : source_color = vec3(0.74, 0.72, 0.64);
// The flat grass out past the grid. It must not read the grid, or what lies on the grid's edge smears out to the horizon.
uniform bool outside = false;
uniform vec3 grass_a : source_color = vec3(0.33, 0.56, 0.20);
uniform vec3 grass_b : source_color = vec3(0.39, 0.62, 0.22);
uniform vec3 soil_a : source_color = vec3(0.47, 0.25, 0.17);
uniform vec3 soil_b : source_color = vec3(0.36, 0.18, 0.12);
uniform vec3 under_a : source_color = vec3(0.29, 0.15, 0.10);
uniform vec3 cut_a : source_color = vec3(0.37, 0.21, 0.14);
uniform vec3 packed_a : source_color = vec3(0.35, 0.24, 0.17);
uniform vec3 rock_a : source_color = vec3(0.56, 0.56, 0.55);
uniform vec3 rock_b : source_color = vec3(0.50, 0.50, 0.50);

const float CELL = 0.25;
const float HALF = 32.0;
const int LAST = 256;
const float CLOD_M = 3.6;       // metres one copy of the lumps' picture covers

varying vec3 v_world;
varying vec3 v_normal;
varying float v_soft;

float hgt(ivec2 c) {
	return texelFetch(height_tex, clamp(c, ivec2(0), ivec2(LAST)), 0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 c = ivec2(round((w.xz + HALF) / CELL));
	// A touch of smoothing, so a soil edge running across the grid doesn't show as a saw-tooth.
	float here = hgt(c);
	float near_a = hgt(c - ivec2(1, 0));
	float near_b = hgt(c + ivec2(1, 0));
	float near_c = hgt(c - ivec2(0, 1));
	float near_d = hgt(c + ivec2(0, 1));
	float smoothed = (here * 4.0 + near_a + near_b + near_c + near_d) * 0.125;
	// But not across a real drop, such as a trench wall: that would draw the trench shallower than it is.
	float drop = max(max(abs(near_a - here), abs(near_b - here)), max(abs(near_c - here), abs(near_d - here)));
	float h = outside ? 0.0 : mix(smoothed, here, smoothstep(0.2, 0.35, drop));
	VERTEX.y += h;
	NORMAL = outside ? vec3(0.0, 1.0, 0.0) : normalize(vec3(hgt(c - ivec2(1, 0)) - hgt(c + ivec2(1, 0)), 2.0 * CELL, hgt(c - ivec2(0, 1)) - hgt(c + ivec2(0, 1))));
	v_normal = NORMAL;
	v_world = vec3(w.x, h, w.z);
}

void fragment() {
	vec2 uv = (v_world.xz + HALF + CELL * 0.5) / (HALF * 2.0 + CELL);
	vec4 m = outside ? vec4(0.0, 0.0, 0.0, 1.0) : texture(data_tex, uv);
	vec3 n = normalize(v_normal);

	// Top and side projections, so a steep pit wall doesn't stretch.
	float top = smoothstep(0.55, 0.8, n.y);
	float patches = texture(noise_tex, v_world.xz * 0.045).r;
	float fine_top = texture(noise_tex, v_world.xz * 0.17).r;
	float fine_side = texture(noise_tex, vec2(v_world.x + v_world.z, v_world.y * 2.6) * 0.3).r;
	float fine = mix(fine_side, fine_top, top);

	// Crisp, slightly ragged borders between materials: this is toon, so no long soft blends.
	// Loose and packed soil add up to how bare the ground is; the split between them says which it looks like.
	float bare = smoothstep(0.44, 0.56, m.r + m.b + (fine - 0.5) * 0.45);
	float split = smoothstep(0.42, 0.58, m.b / max(m.r + m.b, 0.001) + (fine - 0.5) * 0.3);
	float rock = smoothstep(0.44, 0.56, m.g + (fine - 0.5) * 0.45);

	vec3 col = mix(grass_a, grass_b, smoothstep(0.47, 0.53, patches));
	// Loose soil, with dark bands across steep faces so the wall's height reads at a glance.
	float strata = smoothstep(0.46, 0.5, fract(v_world.y * 0.9 + fine * 0.35));
	// Loose dirt is lumps with dark gaps between them, and the deeper it lies the bigger they stand. Cut ground is left smooth and darker.
	vec2 dust_look = outside ? vec2(0.0) : texture(dust_tex, uv).rg;
	// Even cut ground has some grit to it, or it looks like plastic.
	float lumpy = max(0.22, smoothstep(0.03, 0.2, dust_look.g));
	// From above on anything a heap can stand at, and from the side only on a real wall. Blended as pictures: blending where to read from would swirl them.
	vec4 clod = texture(clods_tex, v_world.xz / CLOD_M);
	float wall = 1.0 - smoothstep(0.4, 0.55, n.y);
	if (wall > 0.0) {
		vec2 side_at = vec2(abs(n.x) > abs(n.z) ? v_world.z : v_world.x, v_world.y) / CLOD_M;
		clod = mix(clod, texture(clods_tex, side_at), wall);
	}
	float gap = mix(1.0, smoothstep(0.08, 0.62, clod.b), lumpy);
	// Where the deep stuff lies the real lumps cover it, and this only shows in the cracks between them.
	float heap = smoothstep(0.3, 0.7, lumpy);
	vec3 soil = mix(cut_a * mix(0.9, 1.06, smoothstep(0.42, 0.58, fine)), mix(soil_b, soil_a, (clod.a - 0.5) * 2.0), smoothstep(0.22, 0.8, lumpy));
	soil = mix(soil, under_a, heap);
	soil *= mix(0.42, 1.0, gap);
	soil = mix(soil * mix(0.82, 1.0, strata), soil, max(top, lumpy));
	// The sun picks out each lump, the same stepped way as everything else.
	vec2 lean = (clod.rg - 0.5) * 2.0 * lumpy * bare * (1.0 - split) * (1.0 - rock) * (1.0 - heap);
	v_soft = heap * bare * (1.0 - split) * (1.0 - rock);
	if (top > 0.5) {
		n = normalize(n + vec3(lean.x, 0.0, lean.y) * 1.25);
	} else {
		n = normalize(n + vec3(lean.x, lean.y, lean.x) * 0.9);
	}
	vec3 worked = packed_a * mix(0.92, 1.05, step(0.5, fine));
	col = mix(col, mix(soil, worked, split), bare);
	col = mix(col, mix(rock_a, rock_b, smoothstep(0.45, 0.55, fine)), rock);

	// Cracker dust lies over whatever's under it.
	if (!outside) {
		float dusty = smoothstep(0.44, 0.56, dust_look.r + (fine - 0.5) * 0.45);
		col = mix(col, mix(dust_a, dust_b, smoothstep(0.42, 0.58, fine)), dusty);
	}

	// Hollows go darker and warmer: this is what lets you judge a hole's depth.
	col *= mix(vec3(0.42, 0.36, 0.40), vec3(1.0), m.a);

	ALBEDO = col;
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// Stepped like everything else, except on heaps, where stepped light breaks up into blotches.
void light() {
	float nl = dot(NORMAL, LIGHT);
	float stepped = smoothstep(0.12, 0.16, nl) * mix(0.68, 1.0, smoothstep(0.42, 0.46, nl));
	float soft = clamp(nl * 0.85 + 0.15, 0.0, 1.0);
	float shadow = mix(1.0, smoothstep(0.35, 0.65, ATTENUATION), smoothstep(0.16, 0.42, nl));
	DIFFUSE_LIGHT += LIGHT_COLOR * mix(stepped, soft, v_soft) * shadow;
}
