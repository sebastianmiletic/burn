shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// The swirling veil inside a portal frame (FX layer: glows over the glyphs).

#include "res://rendering/materials/noise.gdshaderinc"

uniform vec4 color_a : source_color = vec4(1.0, 0.3, 0.06, 1.0);
uniform vec4 color_b : source_color = vec4(0.4, 0.02, 0.0, 1.0);
uniform float open = 1.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv * vec2(1.0, 0.8));
	float a = atan(uv.y, uv.x);
	float swirl = n_fbm2(vec2(a * 2.0 + TIME * 0.6 - r * 6.0, r * 5.0 - TIME * 0.8));
	float edge = smoothstep(0.5, 0.35, r);
	float core = smoothstep(0.45, 0.0, r);
	vec3 col = mix(color_b.rgb, color_a.rgb, swirl) * (0.6 + core * 1.4);
	float alpha = edge * (0.35 + swirl * 0.65) * open;
	ALBEDO = col * 3.0 * alpha;
	ALPHA = alpha;
}
