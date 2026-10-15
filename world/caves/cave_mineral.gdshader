shader_type spatial;
render_mode cull_back;
// Ore nodules, crystals, gems, obsidian, ice and glowing cracks.
//   COLOR: r 0 base .. 1 tip, g 1 mineral / 0 rock matrix, b random, a occlusion
//   INSTANCE_CUSTOM: r size/brightness variation, g random, b glow multiplier, a fade / 200
// pattern: 0 plain, 1 copper patina, 2 rust, 3 tarnish, 4 hammered gold, 5 molten cracks

#include "res://world/caves/cave_common.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.6, 0.6, 0.6);
uniform vec3 color_b : source_color = vec3(0.3, 0.29, 0.28);
uniform vec3 color_c : source_color = vec3(0.2, 0.5, 0.4);
uniform float metallic = 0.0;
uniform float roughness = 0.4;
uniform float clarity = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform int pattern = 0;
uniform float sparkle = 0.4;
uniform float ascii_class = 0.0;

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
	vec3 view = normalize(CAMERA_POSITION_WORLD - v_wp);
	float ndv = clamp(dot(n, view), 0.0, 1.0);
	float mask = v_color.g;
	float tip = v_color.r;
	float nz = n_fbm3(v_wp * 9.0);
	vec3 col = color_a;
	float met = metallic;
	float rough = roughness;
	vec3 emit = vec3(0.0);
	if (pattern == 1) {
		// Native copper with green malachite crust in the hollows.
		float pat = smoothstep(0.45, 0.62, nz + (1.0 - v_color.a) * 0.4);
		col = mix(color_a, color_c * (0.8 + 0.4 * n_value3(v_wp * 40.0)), pat);
		met = mix(metallic, 0.0, pat);
		rough = mix(roughness, 0.85, pat);
	} else if (pattern == 2) {
		// Hematite kidneys under ochre rust bloom.
		float pat = smoothstep(0.4, 0.7, nz * 0.8 + (1.0 - v_color.a) * 0.5);
		col = mix(color_a, color_c, pat);
		met = mix(metallic, 0.05, pat);
		rough = mix(roughness, 0.9, pat);
	} else if (pattern == 3) {
		// Silver tarnished black in the creases.
		float pat = smoothstep(0.5, 0.75, nz + (1.0 - v_color.a) * 0.6);
		col = mix(color_a, color_c, pat);
		rough = mix(roughness, 0.6, pat);
	} else if (pattern == 4) {
		col = color_a * (0.85 + 0.3 * n_value3(v_wp * 30.0));
	}
	if (clarity > 0.0) {
		// Gem / ice: a deep body, clearer tips, bright rims and inner flaws.
		// Each facet catches the light differently; the body darkens with thickness.
		float facet = n_hash13(floor(n * 7.0 + 11.0));
		float body = mix(0.25, 0.9, tip) * (0.45 + 0.9 * facet);
		float flaw = smoothstep(0.62, 0.8, n_value3(v_wp * 14.0 + view * 0.6));
		float rim = pow(1.0 - ndv, 3.0);
		col = color_a * body * (1.0 + flaw * 0.6);
		rough *= 0.6 + facet * 0.4;
		emit += color_a * (rim * 0.3 + flaw * 0.12 + tip * 0.08) * clarity * (0.4 + v_custom.b);
		rough = mix(roughness, roughness * 0.5, tip);
	}
	// Glints from tiny facets catching the light.
	vec3 gc = v_wp * 90.0;
	float glint = step(0.985, n_hash13(floor(gc))) * smoothstep(0.3, 0.05, length(fract(gc) - 0.5)) * pow(ndv, 4.0) * sparkle;
	emit += vec3(glint) * mask * 0.6;
	if (pattern == 5) {
		// Molten cracks: white-hot core fading to deep red, flickering.
		float flick = 0.75 + 0.25 * sin(TIME * 2.3 + v_custom.g * 30.0 + v_wp.x * 3.0);
		float heat = smoothstep(0.0, 1.0, tip);
		emit += mix(vec3(0.9, 0.12, 0.02), vec3(1.0, 0.55, 0.15), heat * n_value3(v_wp * 12.0 + vec3(TIME * 0.4))) * (0.35 + 1.9 * heat) * flick * mask;
		col = mix(color_b, vec3(0.08, 0.03, 0.02), mask);
	}
	emit += emission * emission_energy * mask * (0.55 + 0.45 * tip) * (0.6 + v_custom.b);
	// Matrix / vein crust (g = 0): host rock, malachite bands, rust bloom, quartz.
	vec3 matrix = color_b * (0.7 + 0.5 * n_fbm3(v_wp * 6.0));
	float mrough = 0.9;
	if (pattern == 1) {
		float band = 0.5 + 0.5 * sin(length(v_local.xz) * 70.0 + nz * 8.0);
		matrix = mix(color_b * 0.45, color_b * 1.3, band) * (0.85 + 0.3 * n_value3(v_wp * 30.0));
		mrough = 0.55;
	} else if (pattern == 2) {
		matrix = mix(color_b, color_b * 0.45, smoothstep(0.45, 0.8, n_fbm3(v_wp * 14.0)));
		mrough = 0.85;
	} else if (pattern == 3) {
		matrix = color_b * (0.6 + 0.6 * n_fbm3(v_wp * 20.0));
		mrough = 0.7;
	} else if (pattern == 4) {
		matrix = color_b * (0.9 + 0.15 * n_value3(v_wp * 20.0));
		mrough = 0.3;
	}
	ALBEDO = mix(matrix, col * (0.85 + 0.3 * v_custom.r), mask);
	METALLIC = met * mask;
	int cls = int(ascii_class);
	if (dot(emit, vec3(0.333)) > 0.5) {
		cls = ASCII_EMISSIVE;
	}
	ROUGHNESS = ascii_roughness(mix(mrough, rough, mask), cls);
	SPECULAR = mix(0.4, clarity > 0.0 ? 0.95 : 0.75, mask);
	EMISSION = emit;
	AO = v_color.a;
	AO_LIGHT_AFFECT = 0.3;
	if (clarity > 0.0) {
		BACKLIGHT = color_a * 0.6 * mask * clarity;
	}
}
