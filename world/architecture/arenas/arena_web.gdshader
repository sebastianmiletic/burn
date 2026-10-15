shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Spider silk sheets (Broodmother lair, web curtains). Each quad carries
// UV 0..1 and UV2 = (seed, style): style 0 orb web centred on the quad,
// 1 sheet web (dense tangled strands), 2 orb web anchored in a corner.
// Alpha-scissored strands with a pearly sheen.

#include "res://rendering/materials/ascii_material.gdshaderinc"

uniform vec3 silk_color : source_color = vec3(0.86, 0.86, 0.82);
uniform float thickness = 1.0;
uniform float sway = 0.04;

varying vec2 v_info;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	v_info = UV2;
	float s = sin(TIME * 0.9 + VERTEX.x * 0.6 + VERTEX.z * 0.4 + UV2.x) * sway;
	VERTEX += NORMAL * s * UV.y * (1.0 - UV.y) * 4.0;
}

float line_mask(float d, float w) {
	return 1.0 - smoothstep(w * 0.4, w, d);
}

void fragment() {
	float seed = v_info.x;
	int style = int(v_info.y + 0.5);
	vec2 uv = UV;
	float px = fwidth(uv.x) + fwidth(uv.y);
	float w = px * 1.1 * thickness + 0.0015;
	float m = 0.0;
	if (style == 1) {
		// Sheet: many crossing strands.
		for (int i = 0; i < 14; i++) {
			float fi = float(i);
			float a = hash(seed + fi * 3.1) * 3.14159;
			vec2 dir = vec2(cos(a), sin(a));
			vec2 o = vec2(hash(seed + fi * 7.7), hash(seed + fi * 1.9));
			float d = abs(dot(uv - o, vec2(-dir.y, dir.x)));
			m = max(m, line_mask(d, w));
		}
		m *= 0.85;
	} else {
		vec2 c = style == 2 ? vec2(0.08, 0.08) : vec2(0.5, 0.5);
		vec2 q = uv - c;
		float r = length(q);
		float ang = atan(q.y, q.x);
		float spokes = 16.0;
		float sa = ang * spokes / 6.28318 + hash(seed) * 3.0;
		float spoke_d = abs(fract(sa) - 0.5) / spokes * 6.28318 * r;
		m = line_mask(spoke_d, w);
		// Spiral capture threads, sagging between spokes.
		float sag = abs(fract(sa) - 0.5) * 0.012;
		float rr = r + sag + (ang / 6.28318) * 0.028;
		float ring = abs(fract(rr / 0.028) - 0.5) * 0.028;
		m = max(m, line_mask(ring, w) * step(0.03, r));
		float extent = style == 2 ? 0.95 : 0.48;
		m *= 1.0 - smoothstep(extent - 0.06, extent, r + hash(floor(sa) + seed) * 0.05);
		// Torn patches.
		m *= step(0.18, hash(floor(sa) * 1.3 + floor(r * 9.0) * 7.0 + seed));
	}
	if (m < 0.5) {
		discard;
	}
	ALBEDO = silk_color;
	ROUGHNESS = ascii_roughness(0.35, ASCII_CLOTH);
	SPECULAR = 0.8;
	BACKLIGHT = vec3(0.4);
	RIM = 0.6;
	RIM_TINT = 0.4;
}
