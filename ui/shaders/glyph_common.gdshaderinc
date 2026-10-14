// Shared helpers for UI shaders that draw with the game's glyph atlas.
// The atlas is one row of glyphs, each cell_px in size (GlyphAtlas).

uniform sampler2D atlas : filter_nearest;
uniform bool has_atlas = false;
uniform vec2 cell_px = vec2(8.0, 14.0);
uniform vec2 rect_px = vec2(1920.0, 1080.0);
uniform int ramp[12];
uniform int ramp_len = 12;
uniform float time = 0.0;

float g_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash12(i), g_hash12(i + vec2(1.0, 0.0)), u.x),
			mix(g_hash12(i + vec2(0.0, 1.0)), g_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float g_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * g_noise(p);
		p = p * 2.02 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s / 0.9375;
}

vec3 g_ember(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c0 = vec3(0.05, 0.015, 0.01);
	vec3 c1 = vec3(0.35, 0.06, 0.02);
	vec3 c2 = vec3(0.85, 0.3, 0.06);
	vec3 c3 = vec3(1.0, 0.62, 0.22);
	vec3 c4 = vec3(1.0, 0.9, 0.7);
	if (t < 0.25) return mix(c0, c1, t / 0.25);
	if (t < 0.5) return mix(c1, c2, (t - 0.25) / 0.25);
	if (t < 0.75) return mix(c2, c3, (t - 0.5) / 0.25);
	return mix(c3, c4, (t - 0.75) / 0.25);
}

// Ink coverage of the glyph for brightness b (0..1) at a pixel inside a cell.
float g_ink(float b, vec2 local_px, float jitter) {
	if (b <= 0.02) return 0.0;
	int idx = clamp(int(b * float(ramp_len) + jitter * 0.6), 1, ramp_len - 1);
	if (!has_atlas) {
		vec2 c = abs(local_px / cell_px - 0.5);
		return step(max(c.x, c.y), 0.5 * b);
	}
	ivec2 lp = clamp(ivec2(local_px), ivec2(0), ivec2(cell_px) - 1);
	return texelFetch(atlas, ivec2(ramp[idx] * int(cell_px.x) + lp.x, lp.y), 0).r;
}
