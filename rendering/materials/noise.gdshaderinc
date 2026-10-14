// Small procedural noise helpers shared by world materials.

float n_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float n_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float n_value3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = n_hash13(i);
	float b = n_hash13(i + vec3(1.0, 0.0, 0.0));
	float c = n_hash13(i + vec3(0.0, 1.0, 0.0));
	float d = n_hash13(i + vec3(1.0, 1.0, 0.0));
	float e = n_hash13(i + vec3(0.0, 0.0, 1.0));
	float f1 = n_hash13(i + vec3(1.0, 0.0, 1.0));
	float g = n_hash13(i + vec3(0.0, 1.0, 1.0));
	float h = n_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, f1, u.x), mix(g, h, u.x), u.y), u.z);
}

float n_value2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(n_hash12(i), n_hash12(i + vec2(1.0, 0.0)), u.x),
			mix(n_hash12(i + vec2(0.0, 1.0)), n_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float n_fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * n_value3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

float n_fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * n_value2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s / 0.9375;
}

// Cellular pattern: x = distance to nearest feature, y = distance to the
// second nearest, z = id of the nearest cell. Used for flagstones.
vec3 n_voronoi2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(n_hash12(i + g), n_hash12(i + g + 19.19));
			vec2 r = g + o * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = n_hash12(i + g + 7.7);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2), id);
}
