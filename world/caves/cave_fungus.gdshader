shader_type spatial;
render_mode cull_back;
// Cave fungi: pale stems, coloured caps with bioluminescent rims and spots, glowing gills.
//   COLOR: r part (0 stem, 0.5 gills / underside, 1 cap top), g glow mask, b random, a occlusion
//   UV: cap coordinates (spots)
//   INSTANCE_CUSTOM: r hue shift, g random (pulse phase), b brightness, a fade / 200

#include "res://world/caves/cave_common.gdshaderinc"

uniform vec3 stem_color : source_color = vec3(0.75, 0.72, 0.64);
uniform vec3 cap_color : source_color = vec3(0.2, 0.45, 0.55);
uniform vec3 cap_color2 : source_color = vec3(0.55, 0.85, 0.9);
uniform vec3 gill_color : source_color = vec3(0.5, 0.9, 0.95);
uniform vec3 glow_color : source_color = vec3(0.2, 0.9, 1.0);
uniform float glow_energy = 1.6;
uniform float spot_amount = 0.5;
uniform float ascii_class = 1.0;

varying vec4 v_color;
varying vec2 v_uv;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
	v_uv = UV;
}

void fragment() {
	if (cave_faded(FRAGCOORD.xy)) {
		discard;
	}
	float part = v_color.r;
	float stem = 1.0 - smoothstep(0.1, 0.4, part);
	float cap = smoothstep(0.7, 0.95, part);
	float gills = clamp(1.0 - stem - cap, 0.0, 1.0);
	vec3 capc = mix(cap_color, cap_color2, smoothstep(0.4, 1.0, v_color.g));
	capc = mix(capc, capc.gbr, v_custom.r * 0.25);
	float spots = smoothstep(0.78, 0.84, n_value2(v_uv * 26.0 + v_custom.g * 13.0)) * spot_amount * cap;
	float streak = n_fbm3(v_wp * 18.0);
	vec3 col = stem_color * (0.8 + 0.3 * streak) * stem + capc * (0.75 + 0.4 * streak) * cap + gill_color * gills * 0.6;
	col = mix(col, vec3(0.92, 0.95, 0.9), spots);
	float pulse = 0.8 + 0.2 * sin(TIME * (0.6 + v_custom.g * 0.5) + v_custom.g * 40.0);
	float glow = (v_color.g * (cap * 0.45 + gills * 0.8) + spots * 0.9) * pulse * (0.6 + v_custom.b * 0.8);
	ALBEDO = col;
	EMISSION = glow_color * glow_energy * glow;
	int cls = int(ascii_class);
	if (glow > 0.5) {
		cls = ASCII_EMISSIVE;
	}
	ROUGHNESS = ascii_roughness(mix(0.55, 0.35, cap) * (1.0 - wetness * 0.3), cls);
	SPECULAR = 0.45;
	BACKLIGHT = mix(stem_color, capc, cap) * 0.45;
	AO = v_color.a;
	AO_LIGHT_AFFECT = 0.3;
}
