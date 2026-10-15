shader_type canvas_item;
// Wind-driven rain streaks in three depth layers over the loading cinematic,
// plus the white-blue wash of a lightning flash. Pure screen space: cheap.

uniform float time = 0.0;
uniform float intensity = 1.0;
uniform float flash = 0.0;
uniform float aspect = 1.777;
uniform float slant = 0.22;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float layer(vec2 uv, float density, float speed, float len, float width, float seed) {
	vec2 p = vec2(uv.x * aspect + uv.y * slant, uv.y);
	float col = floor(p.x * density);
	float r = hash(col + seed);
	float fx = fract(p.x * density) - 0.5 - (r - 0.5) * 0.6;
	float y = fract(p.y * 1.1 - time * speed * (0.75 + r * 0.5) + r * 17.0);
	float streak = smoothstep(0.0, len * 0.25, y) * (1.0 - smoothstep(len * 0.6, len, y));
	float thin = 1.0 - smoothstep(0.0, width, abs(fx));
	return streak * thin * step(0.35, hash(col * 3.1 + seed + floor(p.y * 1.1 - time * speed * (0.75 + r * 0.5) + r * 17.0)));
}

void fragment() {
	vec2 uv = UV;
	float a = 0.0;
	a += layer(uv, 120.0, 1.9, 0.09, 0.06, 1.0) * 0.18;
	a += layer(uv, 60.0, 2.6, 0.13, 0.05, 7.0) * 0.26;
	a += layer(uv, 26.0, 3.4, 0.2, 0.035, 13.0) * 0.32;
	a *= intensity;
	vec3 rain = vec3(0.62, 0.68, 0.76) * (1.0 + flash * 2.0);
	// Lightning: a cool wash, strongest at the top of the frame.
	float wash = flash * (0.18 + 0.12 * (1.0 - uv.y));
	vec3 col = mix(rain, vec3(0.75, 0.82, 1.0), wash / max(a + wash, 1e-4));
	COLOR = vec4(col, clamp(a + wash, 0.0, 1.0));
}
