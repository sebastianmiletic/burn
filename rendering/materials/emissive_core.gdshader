shader_type spatial;
// Opaque glowing surface (runes, crystal cores, eyes). Tagged EMISSIVE so the
// ASCII pass passes its pixels through untouched; the glow pass blooms them.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float energy = 6.0;
uniform float pulse_speed = 1.3;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float n = n_fbm3(v_local * 3.0 + vec3(0.0, TIME * 0.6, 0.0));
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed * 6.2831);
	ALBEDO = vec3(0.0);
	EMISSION = glow_color * energy * pulse * (0.55 + n * 0.9);
	ROUGHNESS = ascii_roughness(0.4, ASCII_EMISSIVE);
}
