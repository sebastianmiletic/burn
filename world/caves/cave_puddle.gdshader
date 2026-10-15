shader_type spatial;
render_mode cull_back;
// Still cave pools: a mirror-dark surface with a muddy shore, an irregular outline
// (alpha scissor) and drip rings now and then. warm > 0: a turquoise hot spring.
//   COLOR: r 0 centre .. 1 shore

#include "res://world/caves/cave_common.gdshaderinc"

uniform vec3 water_color : source_color = vec3(0.012, 0.016, 0.018);
uniform vec3 shore_color : source_color = vec3(0.16, 0.13, 0.1);
uniform float warm = 0.0;

varying vec4 v_color;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
}

void fragment() {
	if (cave_faded(FRAGCOORD.xy)) {
		discard;
	}
	float r = v_color.r + (n_fbm3(v_wp * 2.5) - 0.5) * 0.35;
	float shore = smoothstep(0.55, 0.92, r);
	// Drip rings: one drop per cell every few seconds.
	vec2 cell = floor(v_wp.xz * 0.7);
	float phase = fract(TIME * 0.23 + n_hash12(cell));
	vec2 c = (cell + vec2(n_hash12(cell + 3.1), n_hash12(cell + 7.7))) / 0.7;
	float dist = length(v_wp.xz - c);
	float ring = sin(dist * 38.0 - phase * 30.0) * exp(-dist * 4.0) * (1.0 - phase) * step(dist, phase * 1.6);
	vec2 dir = dist > 0.001 ? (v_wp.xz - c) / dist : vec2(0.0);
	vec3 nw = normalize(vec3(dir.x * ring * 0.12, 1.0, dir.y * ring * 0.12));
	vec3 water = mix(water_color, vec3(0.03, 0.16, 0.15), warm);
	ALBEDO = mix(water, shore_color, shore);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = ascii_roughness(mix(0.06, 0.45, shore), ASCII_LIQUID);
	SPECULAR = 0.6;
	EMISSION = vec3(0.02, 0.12, 0.1) * warm * (1.0 - shore);
	ALPHA = 1.0 - smoothstep(0.9, 1.0, r);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
