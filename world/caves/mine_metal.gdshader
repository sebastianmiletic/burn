shader_type spatial;
render_mode cull_back;
// Old iron: dark mill-scale metal under blooming rust; rails polished bright on the
// running surface (mode 1, COLOR.r = 1 on the rail head).
//   COLOR: r rust amount (mode 0) / head (mode 1), a occlusion
//   INSTANCE_CUSTOM: r extra rust, g random, a fade / 200

#include "res://world/caves/cave_common.gdshaderinc"

uniform int mode = 0;
uniform vec3 iron : source_color = vec3(0.16, 0.16, 0.17);
uniform vec3 rust : source_color = vec3(0.34, 0.15, 0.07);
uniform vec3 rust2 : source_color = vec3(0.52, 0.27, 0.1);

varying vec4 v_color;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
}

void fragment() {
	if (cave_faded(FRAGCOORD.xy)) {
		discard;
	}
	float nz = n_fbm3(v_wp * 7.0 + v_custom.g * 20.0);
	float pits = n_value3(v_wp * 60.0);
	float amount = mode == 0 ? v_color.r : 0.75;
	float r = smoothstep(0.35, 0.7, nz * 0.7 + amount * 0.5 + v_custom.r * 0.3);
	vec3 col = mix(iron * (0.8 + 0.4 * pits), mix(rust, rust2, pits), r);
	float met = mix(0.75, 0.1, r);
	float rough = mix(0.45, 0.92, r);
	if (mode == 1 && v_color.r > 0.5) {
		col = vec3(0.55, 0.55, 0.56) * (0.85 + 0.15 * pits);
		met = 1.0;
		rough = 0.28;
	}
	ALBEDO = col;
	METALLIC = met;
	ROUGHNESS = ascii_roughness(rough, ASCII_SOLID);
	SPECULAR = 0.5;
	AO = v_color.a;
	AO_LIGHT_AFFECT = 0.4;
}
