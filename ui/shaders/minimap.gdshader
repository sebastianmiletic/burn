shader_type canvas_item;
// Circular minimap. The map image is in world-aligned texels (north up);
// the view is rotated so the player's facing points up, and the terrain is
// redrawn as an ember-toned dot field so it matches the glyph world.

uniform sampler2D map_tex : filter_linear, repeat_disable;
uniform bool has_map = false;
uniform bool cave_mode = false;
uniform sampler2D cave_tex : filter_nearest, repeat_disable;
uniform vec2 cave_offset = vec2(0.0);
uniform vec2 center_uv = vec2(0.5);   // player position in map uv
uniform float span = 0.08;            // map uv covered by the circle's diameter
uniform float angle = 0.0;            // radians, view rotation
uniform float cells = 52.0;           // dot grid across the diameter
uniform int style = 0;                // 0 ember, 1 natural colour
uniform float underground = 0.0;      // dims the surface map below ground
uniform float time = 0.0;

vec3 ember(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c0 = vec3(0.04, 0.015, 0.01);
	vec3 c1 = vec3(0.3, 0.09, 0.03);
	vec3 c2 = vec3(0.75, 0.38, 0.15);
	vec3 c3 = vec3(1.0, 0.82, 0.6);
	if (t < 0.33) return mix(c0, c1, t / 0.33);
	if (t < 0.66) return mix(c1, c2, (t - 0.33) / 0.33);
	return mix(c2, c3, (t - 0.66) / 0.34);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	if (r > 1.0) {
		discard;
	}
	// Dot grid in screen space.
	vec2 g = UV * cells;
	vec2 gc = floor(g) + 0.5;
	vec2 q = style == 0 ? gc / cells - 0.5 : p;
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 rot = vec2(q.x * ca + q.y * sa, -q.x * sa + q.y * ca);
	vec2 muv = center_uv + rot * span;
	vec3 c = vec3(0.0);
	float outside = 0.0;
	if (has_map) {
		if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
			outside = 1.0;
		}
		c = texture(map_tex, clamp(muv, vec2(0.0), vec2(1.0))).rgb;
	}
	if (cave_mode) {
		c = texture(cave_tex, vec2(0.5) + cave_offset + rot).rgb;
	}
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 tone = style == 0 ? ember(pow(lum, 0.8) * 1.15) : c;
	tone = mix(tone, vec3(0.02, 0.012, 0.01), outside);
	tone *= cave_mode ? 1.0 : 1.0 - underground * 0.7;
	float d = length(g - gc);
	float dot_r = 0.32 + lum * 0.22;
	float ink = 1.0 - smoothstep(dot_r - 0.08, dot_r + 0.04, d);
	vec3 bg = tone * 0.22;
	vec3 col = style == 0 && !cave_mode ? mix(bg, tone * 1.2, ink) : tone;
	// Scan sweep and edge falloff.
	float sweep = fract(atan(p.y, p.x) / 6.2831 - time * 0.12);
	if (style == 0) col += vec3(1.0, 0.55, 0.2) * pow(sweep, 18.0) * 0.12 * (1.0 - r);
	col *= 1.0 - smoothstep(0.82, 1.0, r) * 0.65;
	COLOR = vec4(col, 1.0 - smoothstep(0.985, 1.0, r));
}
