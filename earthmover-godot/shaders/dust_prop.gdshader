shader_type spatial;
// Cracker dust where it isn't on the ground: in a bucket, a tray, or falling. The same flat toon look as the props.
#include "res://shaders/toon.gdshaderinc"

uniform vec3 colour : source_color = vec3(0.80, 0.78, 0.70);

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
