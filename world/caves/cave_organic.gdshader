shader_type spatial;
render_mode cull_back;
// Roots (mode 0) and moss (mode 1).
//   COLOR: r 0 base .. 1 tip/edge, b random, a occlusion
//   INSTANCE_CUSTOM: r tint, g random, b glow multiplier, a fade / 200

#include "res://world/caves/cave_common.gdshaderinc"

uniform int mode = 0;
uniform vec3 color_a : source_color = vec3(0.24, 0.17, 0.11);
uniform vec3 color_b : source_color = vec3(0.62, 0.52, 0.4);
uniform vec3 glow_color : source_color = vec3(0.2, 1.0, 0.6);
uniform float glow_energy = 0.0;

varying vec4 v_color;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
}

void fragment() {
	if (cave_faded(FRAGCOORD.xy)) {
		discard;
	}
	vec3 n = normalize(v_wn);
	vec3 col;
	float rough;
	vec3 emit = vec3(0.0);
	int cls = ASCII_FOLIAGE;
	if (mode == 0) {
		float fiber = n_fbm3(vec3(v_wp.x * 40.0, v_wp.y * 3.0, v_wp.z * 40.0));
		col = mix(color_a, color_b, smoothstep(0.55, 1.0, v_color.r)) * (0.7 + 0.5 * fiber);
		col *= 0.85 + 0.3 * v_custom.r;
		rough = 0.8;
		cls = ASCII_SOLID;
	} else {
		// Moss: tufted, darker in hollows, sparse tiny bioluminescent sporangia.
		float tuft = n_fbm3(v_wp * 28.0);
		float clump = n_value3(v_wp * 5.0);
		col = mix(color_a, color_b, clump * 0.7 + tuft * 0.3) * (0.6 + 0.6 * tuft);
		col *= 0.85 + 0.3 * v_custom.r;
		vec3 bump = vec3(n_value3(v_wp * 60.0), n_value3(v_wp * 60.0 + 3.1), n_value3(v_wp * 60.0 + 7.4)) - 0.5;
		n = normalize(n + bump * 0.9);
		rough = 0.95 - wetness * 0.3;
		float spore = step(0.975, n_hash13(floor(v_wp * 70.0))) * smoothstep(0.35, 0.1, length(fract(v_wp * 70.0) - 0.5)) * glow_energy * v_custom.b;
		emit = glow_color * spore * (0.7 + 0.3 * sin(TIME * 1.3 + v_wp.x * 5.0));
	}
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	EMISSION = emit;
	ROUGHNESS = ascii_roughness(rough, cls);
	SPECULAR = 0.3;
	AO = v_color.a;
	AO_LIGHT_AFFECT = 0.4;
	BACKLIGHT = col * (mode == 1 ? 0.25 : 0.1);
}
