shader_type sky;
// The yard's sky through the day (DayNight sets it): a gradient from the horizon up, the sun's disc and its
// glow (warm low down), the moon, and stars at night. Cheap enough for phones: no clouds, no textures.

uniform vec3 top_color : source_color = vec3(0.24, 0.48, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.67, 0.80, 0.93);
uniform vec3 ground_color : source_color = vec3(0.32, 0.53, 0.20);
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);    // toward the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.9997;                 // cos of the disc's radius
uniform float sun_glow = 0.5;                    // how much it lights the sky round it
uniform vec3 moon_dir = vec3(-0.5, 0.6, -0.6);
uniform float moon = 0.0;                        // 0..1 how much moon shows
uniform float stars = 0.0;                       // 0..1

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(h, 0.55));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}
	// the sun: a disc and its glow (a wide warm haze when it's low)
	vec3 sd = normalize(sun_dir);
	float cs = dot(d, sd);
	float low = 1.0 - clamp(sd.y * 2.5, 0.0, 1.0);
	col += sun_color * sun_glow * (pow(max(cs, 0.0), 8.0) * 0.35 + pow(max(cs, 0.0), 64.0) * 0.5) * (0.6 + low);
	col += sun_color * sun_glow * low * 0.25 * pow(max(cs, 0.0), 2.0) * (1.0 - clamp(abs(h) * 4.0, 0.0, 1.0));
	if (sd.y > -0.05) {
		col = mix(col, sun_color * 2.2, smoothstep(sun_size - 0.00012, sun_size, cs) * step(0.0, h));
	}
	// stars: small points on a grid of directions, twinkling a little
	if (stars > 0.0 && h > 0.0) {
		vec3 g = d * 180.0;
		vec3 cell = floor(g);
		float r = hash(cell);
		if (r > 0.985) {
			vec3 f = fract(g) - 0.5;
			float s = smoothstep(0.32, 0.0, length(f));
			float tw = 0.7 + 0.3 * sin(TIME * (1.5 + r * 4.0) + r * 40.0);
			col += vec3(0.85, 0.9, 1.0) * s * tw * stars * smoothstep(0.0, 0.25, h) * (r - 0.985) * 66.0;
		}
	}
	// the moon: a pale disc with a soft halo
	if (moon > 0.0) {
		float cm = dot(d, normalize(moon_dir));
		col += vec3(0.6, 0.7, 0.9) * pow(max(cm, 0.0), 300.0) * 0.25 * moon;
		col = mix(col, vec3(0.92, 0.94, 1.0), smoothstep(0.99955, 0.9997, cm) * moon);
	}
	COLOR = col;
}
