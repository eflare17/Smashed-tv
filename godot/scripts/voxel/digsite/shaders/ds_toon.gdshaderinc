// The Dig Site's stepped light (the digger game's toon.gdshaderinc): a hard terminator, one extra band, a crisp
// shadow edge. Shared by the ground, the machines, the props, the grass and the clods.
void light() {
	float nl = dot(NORMAL, LIGHT);
	float sun = smoothstep(0.12, 0.16, nl);
	float band = mix(0.68, 1.0, smoothstep(0.42, 0.46, nl));
	// Faces near edge-on to the sun can't take a clean shadow, and speckle. Those are nearly dark already, so they go without.
	float shadow = mix(1.0, smoothstep(0.35, 0.65, ATTENUATION), smoothstep(0.16, 0.42, nl));
	DIFFUSE_LIGHT += LIGHT_COLOR * sun * band * shadow;
}
