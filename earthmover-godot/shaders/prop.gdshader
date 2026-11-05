shader_type spatial;
// Flat-shaded colour-swatch props: the face normals and solid colours are in the mesh.
#include "res://shaders/toon.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
