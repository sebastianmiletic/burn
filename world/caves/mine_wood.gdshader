shader_type spatial;
render_mode cull_back;
// Weathered hewn timber: grain along the member (local +Y), dark checks and splits,
// adze facets, end grain rings, damp patches.
//   COLOR: g 1 = end grain, b random, a occlusion
//   INSTANCE_CUSTOM: r darkness, g random, b damp, a fade / 200

#include "res://world/caves/cave_common.gdshaderinc"

uniform vec3 wood_light : source_color = vec3(0.42, 0.31, 0.2);
uniform vec3 wood_dark : source_color = vec3(0.17, 0.11, 0.07);
uniform vec3 damp_color : source_color = vec3(0.12, 0.13, 0.08);

varying vec4 v_color;
varying vec3 v_scale;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
	v_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	if (cave_faded(FRAGCOORD.xy)) {
		discard;
	}
	vec3 lp = v_local * v_scale;
	float seed = v_custom.g * 37.0;
	float grain = n_fbm3(vec3(lp.x * 30.0 + seed, lp.y * 1.2, lp.z * 30.0));
	float fine = n_value3(vec3(lp.x * 140.0, lp.y * 4.0, lp.z * 140.0));
	float check = smoothstep(0.82, 0.9, n_value3(vec3(lp.x * 9.0 + seed, lp.y * 0.6, lp.z * 9.0)));
	vec3 col = mix(wood_dark, wood_light, grain * 0.75 + fine * 0.25);
	col *= 1.0 - check * 0.6;
	if (v_color.g > 0.5) {
		vec2 q = lp.xz - vec2(0.03, -0.02);
		float rings = 0.5 + 0.5 * sin(length(q) * 260.0 + grain * 9.0);
		float split = smoothstep(0.93, 1.0, n_value2(vec2(atan(q.y, q.x) * 3.0, seed)));
		col = mix(wood_dark * 1.5, wood_light * 1.05, 0.55 + rings * 0.2 + fine * 0.15) * (1.0 - split * 0.6);
	}
	col *= 0.85 + 0.25 * v_color.b - v_custom.r * 0.35;
	float damp = clamp(v_custom.b * (0.6 + 0.4 * n_value3(v_wp * 3.0)), 0.0, 1.0);
	col = mix(col, damp_color, damp * 0.5);
	ALBEDO = col;
	ROUGHNESS = ascii_roughness(0.86 - damp * 0.3, ASCII_SOLID);
	SPECULAR = 0.3;
	AO = v_color.a;
	AO_LIGHT_AFFECT = 0.4;
}
