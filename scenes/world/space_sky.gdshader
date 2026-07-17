shader_type sky;

// Procedural deep-space sky: two star layers, a faint galactic band, subtle
// nebula color, and the K-dwarf sun disc drawn at LIGHT0's direction so the
// visible star always agrees with the DirectionalLight. Procedural instead of
// an HDRI: nothing to license, no 8K texture in VRAM, and the radiance map
// still gives the hulls something to reflect.

uniform vec3 nebula_tint_a : source_color = vec3(0.16, 0.09, 0.22);
uniform vec3 nebula_tint_b : source_color = vec3(0.05, 0.12, 0.20);
uniform vec3 sun_color : source_color = vec3(1.0, 0.62, 0.32);
uniform float sun_angular_size : hint_range(0.001, 0.1) = 0.012;
uniform float star_intensity : hint_range(0.0, 4.0) = 1.6;
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.35;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Point stars on a 3D cell grid over the view direction.
float stars(vec3 dir, float scale, float density, float sharpness) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	vec3 offset = (hash33(id) - 0.5) * 0.7;
	float seed = hash13(id + 17.31);
	float d = length(f - offset);
	float point = smoothstep(sharpness, 0.0, d);
	return point * step(1.0 - density, seed) * (0.3 + 0.7 * hash13(id + 3.7));
}

float vnoise(vec3 p) {
	vec3 id = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float v = 0.0;
	for (int i = 0; i < 2; i++)
		for (int j = 0; j < 2; j++)
			for (int k = 0; k < 2; k++) {
				vec3 c = vec3(float(i), float(j), float(k));
				float h = hash13(id + c);
				vec3 w = mix(1.0 - f, f, c);
				v += h * w.x * w.y * w.z;
			}
	return v;
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;

	// Galactic band: brighter dust + denser faint stars near an arbitrary
	// tilted plane.
	vec3 band_normal = normalize(vec3(0.2, 0.85, 0.45));
	float band = pow(1.0 - abs(dot(dir, band_normal)), 3.0);

	float n = fbm(dir * 3.0 + vec3(7.3, 1.1, 4.8));
	float n2 = fbm(dir * 9.0 + vec3(2.0, 5.0, 9.0));
	vec3 nebula = mix(nebula_tint_b, nebula_tint_a, n) * (n * n)
			* nebula_intensity * (0.25 + 0.75 * band);

	float s = stars(dir, 90.0, 0.10, 0.10) * 0.9
			+ stars(dir, 220.0, 0.06, 0.14) * 0.45 * (0.4 + 0.6 * band)
			+ stars(dir, 40.0, 0.03, 0.05) * 1.6;
	// Slight warm/cool tint variation per star region.
	vec3 star_tint = mix(vec3(0.85, 0.9, 1.0), vec3(1.0, 0.92, 0.8),
			n2);
	vec3 color = nebula + star_tint * s * star_intensity;

	// K-dwarf primary: hard disc plus a tight glare halo for Glow to bite on.
	if (LIGHT0_ENABLED) {
		float c = dot(dir, LIGHT0_DIRECTION);
		float disc = smoothstep(cos(sun_angular_size), cos(sun_angular_size * 0.6), c);
		float halo = pow(max(c, 0.0), 900.0) * 0.6 + pow(max(c, 0.0), 80.0) * 0.06;
		color += sun_color * (disc * 12.0 + halo) * LIGHT0_ENERGY;
	}

	COLOR = color;
}
