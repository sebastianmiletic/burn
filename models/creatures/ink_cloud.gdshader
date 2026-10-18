shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded, shadows_disabled;
// The Kraken's ink: a billowing black-violet cloud. Drawn from inside as well, so a player
// caught in it sees nothing but swirling ink until it thins out.

instance uniform float density = 1.0;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	float n = vnoise(VERTEX * 2.2 + vec3(0.0, TIME * 0.35, 0.0));
	VERTEX *= 0.85 + 0.3 * n;
}

void fragment() {
	float n = vnoise(v_local * 3.0 + vec3(TIME * 0.2, -TIME * 0.3, 0.0)) * 0.6 + vnoise(v_local * 7.0 - vec3(0.0, TIME * 0.5, TIME * 0.2)) * 0.4;
	float rim = FRONT_FACING ? pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 0.6) : 1.0;
	ALBEDO = mix(vec3(0.01, 0.005, 0.02), vec3(0.08, 0.03, 0.12), n);
	ALPHA = clamp(density * rim * (0.75 + 0.35 * n), 0.0, FRONT_FACING ? 0.93 : 0.97);
}
