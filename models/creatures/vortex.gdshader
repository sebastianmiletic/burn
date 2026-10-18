shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Charybdis's whirlpool: the funnel wall of water spirals inward and down. UV.x runs
// around the funnel, UV.y from the rim (0) to the throat (1). Foam streaks follow the
// spiral; the water darkens with depth and glows faintly from the maw below.

instance uniform float spin = 1.0;
instance uniform float fury = 0.0;
uniform vec3 shallow : source_color = vec3(0.12, 0.32, 0.36);
uniform vec3 deep : source_color = vec3(0.01, 0.04, 0.06);
uniform vec3 foam : source_color = vec3(0.82, 0.9, 0.92);
uniform vec3 maw_glow : source_color = vec3(0.25, 0.9, 0.7);

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

varying float v_depth;

void vertex() {
	v_depth = UV.y;
	// Ripples travelling down the spiral.
	float a = UV.x * 6.2831853;
	VERTEX += NORMAL * sin(a * 9.0 + UV.y * 22.0 - TIME * spin * 4.0) * 0.12 * (1.0 - UV.y);
}

void fragment() {
	float t = TIME * spin;
	// Spiral coordinates: around the funnel, sheared with depth, flowing downward.
	vec2 sp = vec2(UV.x * 24.0 + UV.y * 9.0 - t * 1.6, UV.y * 6.0 - t * 0.9);
	float streak = vn(sp * vec2(1.0, 4.0)) * 0.6 + vn(sp * vec2(2.3, 9.0) + 7.0) * 0.4;
	float foam_mask = smoothstep(0.62, 0.86, streak) * (1.0 - smoothstep(0.2, 0.9, UV.y)) + smoothstep(0.0, 0.07, 0.07 - UV.y) * 0.8;
	vec3 water = mix(shallow, deep, smoothstep(0.0, 0.85, UV.y));
	water *= 0.85 + 0.3 * streak;
	ALBEDO = mix(water, foam, clamp(foam_mask, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.5, foam_mask);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = maw_glow * smoothstep(0.65, 1.0, UV.y) * (0.4 + 1.2 * fury) * (0.7 + 0.3 * sin(TIME * 2.0));
}
