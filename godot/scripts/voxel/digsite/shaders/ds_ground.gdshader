shader_type spatial;
// The Dig Site's ground (the digger game's ground.gdshader, on a true 3D surface): the mesher gives each vertex its
// material's colour (COLOR) and, in CUSTOM0, how much of the ground here is loose dirt, how deep in a hollow it
// sits, whether grass stands on it, and whether it's rock. Grass in two patchy greens with a crisp ragged border;
// soil as lumps with dark gaps between them where it's loose (the lumps' picture, clods_tex, from above, and from
// the side on a wall), smooth and darker where it's been cut; dark strata bands across steep faces so a wall's
// height reads; rock in flat greys; hollows darker and warmer, which is what lets you judge a hole's depth. Noise is
// read from the world position (top and side projections), so a pit wall doesn't stretch. Toon lit, soft on heaps.
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D clods_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.29, 0.50, 0.18);
uniform vec3 grass_b : source_color = vec3(0.34, 0.56, 0.20);
uniform vec3 under_a : source_color = vec3(0.29, 0.15, 0.10);
uniform vec3 rock_a : source_color = vec3(0.56, 0.56, 0.55);
uniform vec3 rock_b : source_color = vec3(0.50, 0.50, 0.50);
const float CLOD_M = 3.6;       // metres one copy of the lumps' picture covers
// the ground gliding (DsTerrain._glide): each column's surface drawn off its block top by an amount that eases away,
// so dirt arriving or going shows as a smooth rise or fall, not a block's jump. Only vertices at a column's top move.
uniform sampler2D show_off_tex : filter_linear, repeat_disable;   // R: cells the surface is still drawn off its top
uniform sampler2D topo_tex : filter_nearest, repeat_disable;      // R: the column's top cell /255
uniform vec2 grid_size = vec2(512.0, 512.0);
uniform float cell = 0.125;

varying vec3 v_world;
varying vec3 v_normal;
varying vec4 v_info;            // loose, cavity, grass, rock
varying vec3 v_col;
varying float v_soft;

void vertex() {
	// (VERTEX: metres from the grid's corner; a column's middle at (i + 0.5) cells)
	vec2 uv = VERTEX.xz / cell / grid_size;
	float off = textureLod(show_off_tex, uv, 0.0).r;
	float top = textureLod(topo_tex, uv, 0.0).r * 255.0 + 1.0;
	float near_top = 1.0 - smoothstep(1.2, 2.6, abs(VERTEX.y / cell - top));
	VERTEX.y += off * cell * near_top;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_info = CUSTOM0;
	v_col = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(v_normal);
	float top = smoothstep(0.55, 0.8, n.y);
	float patches = texture(noise_tex, v_world.xz * 0.045).r;
	float fine_top = texture(noise_tex, v_world.xz * 0.17).r;
	float fine_side = texture(noise_tex, vec2(v_world.x + v_world.z, v_world.y * 2.6) * 0.3).r;
	float fine = mix(fine_side, fine_top, top);

	// crisp, slightly ragged borders between what's here: this is toon, so no long soft blends
	float grass = smoothstep(0.44, 0.56, v_info.b + (fine - 0.5) * 0.45);
	float rock = smoothstep(0.44, 0.56, v_info.a + (fine - 0.5) * 0.45);
	float lumpy = smoothstep(0.1, 0.6, v_info.r);

	// soil: the material's own colour, in lumps with dark gaps where it's loose, smooth and a shade darker where cut
	vec4 clod = texture(clods_tex, v_world.xz / CLOD_M);
	float wall = 1.0 - smoothstep(0.4, 0.55, n.y);
	if (wall > 0.0) {
		vec2 side_at = vec2(abs(n.x) > abs(n.z) ? v_world.z : v_world.x, v_world.y) / CLOD_M;
		clod = mix(clod, texture(clods_tex, side_at), wall);
	}
	float gap = mix(1.0, smoothstep(0.08, 0.62, clod.b), lumpy);
	vec3 base = v_col;
	vec3 cut = base * 0.82 * mix(0.92, 1.06, smoothstep(0.42, 0.58, fine));
	vec3 lumps = base * mix(0.8, 1.15, (clod.a - 0.5) * 2.0 * 0.5 + 0.5);
	vec3 soil = mix(cut, lumps, lumpy);
	// deep in a heap the real lumps cover it, and the ground only shows in the cracks between them
	float heap = smoothstep(0.5, 0.9, v_info.r);
	soil = mix(soil, under_a, heap * 0.6);
	soil *= mix(0.42, 1.0, gap);
	// dark bands across steep faces, so a wall's height reads at a glance (not on loose slopes: they're lumps)
	float strata = smoothstep(0.46, 0.5, fract(v_world.y * 0.9 + fine * 0.35));
	soil = mix(soil * mix(0.82, 1.0, strata), soil, max(top, lumpy));
	// the sun picks out each lump
	vec2 lean = (clod.rg - 0.5) * 2.0 * lumpy * (1.0 - grass) * (1.0 - rock);
	v_soft = heap * (1.0 - grass) * (1.0 - rock);
	if (top > 0.5) {
		n = normalize(n + vec3(lean.x, 0.0, lean.y) * 1.25);
	} else {
		n = normalize(n + vec3(lean.x, lean.y, lean.x) * 0.9);
	}

	vec3 col = mix(soil, mix(grass_a, grass_b, smoothstep(0.47, 0.53, patches)), grass);
	col = mix(col, mix(rock_a, rock_b, smoothstep(0.45, 0.55, fine)) * (0.7 + 0.6 * v_col.r), rock);

	// hollows go darker and warmer
	col *= mix(vec3(1.0), vec3(0.42, 0.36, 0.40), v_info.g * 0.62);

	ALBEDO = col;
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// stepped like everything else, except on heaps, where stepped light breaks up into blotches
void light() {
	float nl = dot(NORMAL, LIGHT);
	float stepped = smoothstep(0.12, 0.16, nl) * mix(0.68, 1.0, smoothstep(0.42, 0.46, nl));
	float soft = clamp(nl * 0.85 + 0.15, 0.0, 1.0);
	float shadow = mix(1.0, smoothstep(0.35, 0.65, ATTENUATION), smoothstep(0.16, 0.42, nl));
	DIFFUSE_LIGHT += LIGHT_COLOR * mix(stepped, soft, v_soft) * shadow;
}
