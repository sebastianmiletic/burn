shader_type spatial;
// Lantern glass: emissive with a soft flicker per instance.
//   COLOR: r brightness across the glass
//   INSTANCE_CUSTOM: g random (flicker phase), b lit (1) / dark (0), a fade / 200

#include "res://world/caves/cave_common.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.28);
uniform float energy = 3.5;
uniform vec3 off_color : source_color = vec3(0.05, 0.045, 0.04);

varying vec4 v_color;

void vertex() {
	CAVE_VERTEX
	v_color = COLOR;
}

void fragment() {
	float on = v_custom.b;
	float flick = 0.85 + 0.1 * sin(TIME * 7.3 + v_custom.g * 50.0) + 0.05 * sin(TIME * 17.0 + v_custom.g * 9.0);
	ALBEDO = mix(off_color, vec3(0.0), on);
	EMISSION = glow_color * energy * flick * on * (0.7 + 0.3 * v_color.r);
	ROUGHNESS = ascii_roughness(0.1, on > 0.5 ? ASCII_EMISSIVE : ASCII_SOLID);
	SPECULAR = 0.8;
}
