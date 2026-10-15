shader_type spatial;
render_mode cull_disabled;
#include "res://rendering/materials/ascii_material.gdshaderinc"
varying float height;
void vertex() {
	height = UV.y;
	VERTEX.x += sin(TIME * 0.8 + MODEL_MATRIX[3].x * 0.3 + VERTEX.y * 3.0) * VERTEX.y * 0.24;
}
void fragment() {
	float width = 0.12 + sin(UV.y * 34.0) * 0.07 + (1.0 - UV.y) * 0.06;
	if (abs(UV.x - 0.5) > width) discard;
	ALBEDO = mix(vec3(0.08, 0.19, 0.12), vec3(0.26, 0.38, 0.13), UV.y);
	ROUGHNESS = ascii_roughness(0.8, ASCII_FOLIAGE);
}
