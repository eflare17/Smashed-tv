# (Copied from stkilda-godot scripts/town/ground_look.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkGroundLook
extends RefCounted
## What the town's ground looks like close up (the ground is one big flat mesh, its colours painted on): each part's
## kind rides along in its colour's alpha (kind()), and one shader dresses each kind: grass in patches of greener and
## drier, roads with a fine grain, darker patches and the odd crack, footpaths laid in pavers, sand grainy and rippled,
## the sea moving (small waves catching the sun), foam washing on the wet sand at its edge, car parks a lighter worn
## asphalt, the piers' decks in planks. A kind of 0 (alpha 1) is left plain.

enum { PLAIN, GRASS, ROAD, PATH, SAND, SEA, SHORE, PARKING, DECK, ROCK }

static var _mat: ShaderMaterial

## A colour carrying its kind of ground (in its alpha).
static func kind(c: Color, k: int) -> Color:
	return Color(c.r, c.g, c.b, float(k) / 16.0)

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = CODE
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.02
		n.fractal_octaves = 4
		n.seed = 13
		var img := n.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(img))
	return _mat

const CODE := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying float kind;

float nz(vec2 p) { return texture(noise_tex, p).r; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 to_linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	kind = COLOR.a * 16.0;
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec2 p = wpos.xz;
	float k = floor(kind + 0.5);
	float rough = 0.92;
	float spec = 0.4;
	if (COLOR.a > 0.97) {
		// plain
	} else if (k == 1.0) {
		// grass: big patches greener and drier, and a fine mottle
		float big = nz(p * 0.004);
		float mid = nz(p * 0.03);
		float fine = nz(p * 0.6);
		c *= 0.88 + 0.2 * mid + 0.1 * (fine - 0.5);
		c = mix(c, c * vec3(1.12, 1.02, 0.78), smoothstep(0.55, 0.75, big));     // (drier)
		c = mix(c, c * vec3(0.92, 0.97, 0.9), smoothstep(0.45, 0.25, big));     // (darker, lusher)
	} else if (k == 2.0 || k == 7.0) {
		// asphalt: fine grain, darker patches where it's been mended, a crack here and there
		float grain = nz(p * 0.9) - 0.5;
		float patch = smoothstep(0.66, 0.69, nz(p * 0.03 + 3.7));
		float crack = (1.0 - smoothstep(0.0, 0.007, abs(nz(p * 0.05 + 1.3) - 0.5))) * step(0.58, nz(p * 0.01));
		c *= 1.0 + grain * 0.18;
		c *= 1.0 - patch * 0.09;
		c *= 1.0 - crack * 0.13;
		if (k == 7.0) { c *= 1.0 + 0.12 * (nz(p * 0.05) - 0.5); }
	} else if (k == 3.0) {
		// footpath pavers: 0.6 m squares (every other row offset), each a touch different, darker joints
		vec2 q = p / 0.6;
		q.x += 0.5 * mod(floor(q.y), 2.0);
		vec2 f = fract(q);
		float joint = 1.0 - smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		c *= 0.94 + 0.1 * hash(floor(q));
		c *= 1.0 - joint * 0.25;
		c *= 1.0 + (nz(p * 0.08) - 0.5) * 0.12;
	} else if (k == 4.0) {
		// sand: grainy, with wind ripples
		float rip = sin(p.x * 2.2 + p.y * 0.8 + nz(p * 0.05) * 12.0);
		c *= 1.0 + (nz(p * 2.5) - 0.5) * 0.14 + rip * 0.03;
		c *= 0.95 + 0.1 * nz(p * 0.02);
	} else if (k == 5.0) {
		// the sea: small waves running in, catching the sun
		vec2 a = p * 0.05 + vec2(TIME * 0.02, TIME * 0.013);
		vec2 b = p * 0.11 - vec2(TIME * 0.017, -TIME * 0.025);
		float h1 = nz(a);
		float h2 = nz(b);
		float e = 0.01;
		float dx = (nz(a + vec2(e, 0.0)) - h1) + (nz(b + vec2(e, 0.0)) - h2);
		float dz = (nz(a + vec2(0.0, e)) - h1) + (nz(b + vec2(0.0, e)) - h2);
		vec3 n = normalize(vec3(-dx * 3.0, 1.0, -dz * 3.0));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		c *= 0.62 + 0.22 * (h1 * 0.6 + h2 * 0.4);
		c = mix(c, c * vec3(0.85, 1.0, 1.05), nz(p * 0.003));
		rough = 0.12;
		spec = 0.7;
	} else if (k == 6.0) {
		// the wet sand at the water's edge, and foam washing over it
		c *= 0.82 + 0.12 * nz(p * 1.5);
		float wash = nz(p * 0.08 + vec2(TIME * 0.03, 0.0));
		float foam = smoothstep(0.55, 0.7, wash + 0.25 * sin(TIME * 0.8 + nz(p * 0.02) * 20.0));
		foam *= 0.6 + 0.4 * nz(p * 0.9);
		c = mix(c, vec3(0.92, 0.94, 0.95), foam * 0.85);
		rough = mix(0.35, 0.9, foam);
	} else if (k == 8.0) {
		// a pier's deck: planks across it (the pier runs out roughly west, so they run north-south), worn
		float board = fract(p.x / 0.18);
		c *= 0.9 + 0.12 * hash(vec2(floor(p.x / 0.18), 0.0));
		c *= 1.0 - (1.0 - smoothstep(0.0, 0.1, board)) * 0.35;
		c *= 1.0 + (nz(p * vec2(2.0, 0.08)) - 0.5) * 0.15;
	} else if (k == 9.0) {
		c *= 0.75 + 0.5 * nz(p * 0.7);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
"""
