# (Copied from stkilda-godot scripts/town/worn_look.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkWornLook
extends RefCounted
## Age on Luna Park's old buildings (the owner's idea, 2026-10-29, to go with the scruffy wooden coaster): the
## Moon face entrance (1912), the Carousel's building, the Ghost Train (1934) and Luna Palace (1927). Their own colours
## (the baked vertex colours, as SkModels.baked_material shows them), with grime gathered at the foot of the walls, dirty
## streaks running down them from the rain, broad patches where the paint has faded, and little flecks where it's
## peeled back to the pale undercoat. All in the shader, from where each bit is in the world: no textures to load,
## nothing extra to draw.

static var _mat: ShaderMaterial

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = CODE
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.03
		n.fractal_octaves = 3
		n.seed = 1912
		var img := n.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(img))
	return _mat

const CODE := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnrm;

float nz(vec2 p) { return texture(noise_tex, p).r; }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float up = abs(wnrm.y);
	// across a wall: x or z, whichever way the wall runs
	float across = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
	vec2 wall = vec2(across, wpos.y);
	// faded patches: broad, paler and a little greyer
	float fade = smoothstep(0.5, 0.75, nz(wall * 0.025 + 0.3));
	c = mix(c, mix(c, vec3(dot(c, vec3(0.33))), 0.35) * 1.04, fade * 0.45);
	// streaks down the walls from the rain (the noise stretched tall)
	float streak = smoothstep(0.52, 0.7, nz(vec2(across * 0.3, wpos.y * 0.03)));
	c *= 1.0 - streak * 0.07 * (1.0 - up);
	// grime gathered at the foot
	float foot = 1.0 - smoothstep(0.0, 1.4, wpos.y);
	c *= 1.0 - foot * (0.16 + 0.08 * nz(wall * 0.3)) * (1.0 - up * 0.5);
	// paint peeled back to the pale undercoat, in small flecks, where it's most faded
	float fleck = step(0.74, nz(wall * 0.55 + 7.1)) * smoothstep(0.35, 0.7, nz(wall * 0.04 + 2.2));
	c = mix(c, vec3(0.78, 0.76, 0.7), fleck * 0.55 * (1.0 - up) * smoothstep(0.12, 0.3, dot(c, vec3(0.33))));      // (not on the dark bits)
	// fine grain, so no wall's one flat colour
	c *= 0.96 + 0.08 * nz(wall * 1.7);
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""
