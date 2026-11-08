shader_type spatial;
// One colour, toon lit: the fence posts, the site office, the hand tools' parts.
#include "ds_toon.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8, 0.8, 0.8);

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
