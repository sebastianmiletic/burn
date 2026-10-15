shader_type spatial;
render_mode cull_back;
// Dripstone, rubble, basalt, sinter, waste rock: photographic rock (triplanar, world space)
// tinted to the cave's mineral, calcite growth bands, wet glistening tips and drops.
//   COLOR: r 0 base .. 1 tip, g 1 = water drop / hot pool, b random, a occlusion
//   INSTANCE_CUSTOM: r tint variation, g random, b darkness, a fade distance / 200

#include "res://world/caves/cave_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.78, 0.72, 0.62);
uniform vec3 tint2 : source_color = vec3(0.93, 0.86, 0.72);
uniform float band_amount = 0.5;
uniform float band_freq = 22.0;
uniform float tex_mix = 0.55;
uniform float tex_scale = 0.9;
uniform float wet_tip = 0.75;
uniform float base_rough = 0.82;
uniform float translucency = 0.0;
uniform vec3 pool_color : source_color = vec3(0.03, 0.035, 0.04);
uniform vec3 pool_glow : source_color = vec3(0.0);
uniform vec3 emit_color : source_color = vec3(0.0);
uniform float emit_energy = 0.0;
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
	vec3 p = v_wp * tex_scale;
	vec3 photo = cave_triplanar(albedo_tex, p, n);
	float lum = dot(photo, vec3(0.333));
	// Calcite growth rings and streaks running down the formation.
	float streak = n_fbm3(vec3(v_wp.x * 6.0, v_local.y * 1.5, v_wp.z * 6.0));
	float band = smoothstep(0.35, 0.65, 0.5 + 0.5 * sin(v_local.y * band_freq + streak * 5.0)) * band_amount;
	vec3 mineral = mix(tint, tint2, band) * (0.8 + 0.4 * v_custom.r);
	vec3 col = mix(mineral, mineral * lum * 2.2, tex_mix);
	col *= 1.0 - v_custom.b * 0.35;
	float tip = v_color.r;
	float wet = clamp(smoothstep(0.55, 1.0, tip) * wet_tip + wetness * 0.3, 0.0, 1.0);
	col *= 1.0 - wet * 0.35;
	float rough = mix(base_rough, 0.18, wet);
	vec3 wn = cave_triplanar_normal(normal_tex, p, n, 0.85 * (1.0 - wet * 0.6));
	vec3 emit = emit_color * emit_energy * (0.6 + 0.4 * n_value3(v_wp * 3.0 + vec3(TIME * 0.2)));
	if (v_color.g > 0.5) {
		// Standing water: a clinging drop, or the hot pool of a sinter basin.
		col = pool_color;
		rough = 0.02;
		wn = n;
		emit += pool_glow * (0.8 + 0.2 * sin(TIME * 1.7 + v_wp.x));
	}
	ALBEDO = col;
	AO = v_color.a;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	SPECULAR = mix(0.4, 0.75, wet);
	if (translucency > 0.0) {
		BACKLIGHT = mineral * translucency * (0.5 + tip);
	}
	EMISSION = emit;
	ROUGHNESS = ascii_roughness(rough, int(ascii_class));
}
