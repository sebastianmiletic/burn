shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Opaque precipitation flake (snow, dust, ash) for the ASCII styles: tagged
// STREAK so the ASCII pass draws sparse ' . specks where flakes cross a cell.
// Billboarded; tumbles a little so flakes flicker like the real thing.

#include "res://rendering/materials/ascii_material.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.9, 0.92, 0.96);
uniform float brightness = 1.0;   // self-light so flakes read against dark ground
uniform float size = 0.05;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float tumble = 0.65 + 0.35 * sin(TIME * 7.0 + MODEL_MATRIX[3].x * 3.1 + MODEL_MATRIX[3].z * 2.3);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(size * tumble, 0, 0, 0), vec4(0, size, 0, 0), vec4(0, 0, size, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	if (length(UV - 0.5) > 0.5) {
		discard;
	}
	ALBEDO = tint;
	EMISSION = tint * brightness * 0.08;
	ROUGHNESS = ascii_roughness(0.6, ASCII_STREAK);
}
