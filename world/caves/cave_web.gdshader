shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Spider silk: faint translucent threads that catch the light with a sheen.
//   COLOR: r 0 frame thread .. 1 sticky spiral, a thread opacity

#include "res://world/caves/cave_common.gdshaderinc"

uniform vec3 silk_color : source_color = vec3(0.86, 0.86, 0.82);
uniform float opacity = 0.75;
uniform float near_fade = 34.0;

varying vec4 v_color;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
}

void fragment() {
	float d = distance(v_wp, CAMERA_POSITION_WORLD);
	vec3 view = normalize(CAMERA_POSITION_WORLD - v_wp);
	float sheen = pow(1.0 - abs(dot(normalize(v_wn), view)), 2.0);
	// Dew and dust beads on the sticky spiral.
	float beads = step(0.8, n_value3(v_wp * 120.0)) * v_color.r;
	ALBEDO = silk_color;
	EMISSION = silk_color * (0.025 + sheen * 0.05 + beads * 0.08);
	ROUGHNESS = ascii_roughness(0.35, ASCII_CLOTH);
	SPECULAR = 0.8;
	ALPHA = clamp(v_color.a * opacity * (0.55 + sheen * 0.6 + beads) * (1.0 - smoothstep(near_fade * 0.6, near_fade, d)) * v_fade, 0.0, 1.0);
}
