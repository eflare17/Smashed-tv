shader_type spatial;
// Flat-shaded colour-swatch props (the machines, the ground's blocks): the colours are in the mesh's vertices.
#include "ds_toon.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
