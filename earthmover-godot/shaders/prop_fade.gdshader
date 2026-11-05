shader_type spatial;
// The props' look, see-through: worn by a house, tree or machine while it stands between the camera and the machine
// being driven. Drawn in the transparent pass, so the ink lines leave it while it's faded.
render_mode depth_draw_never;
#include "res://shaders/toon.gdshaderinc"

uniform float fade = 1.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = fade;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
