shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, shadows_disabled;
// Rain splash droplet (sub-emitter of RainCurtain): a short streak thrown up
// where a drop hits the ground, aligned to its velocity. Opaque and tagged
// STREAK, so the ASCII pass shows it as a ' or . flick at ground level.

#include "res://rendering/materials/ascii_material.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.62, 0.66, 0.72);
uniform float brightness = 1.0;
uniform float width = 0.012;
uniform float length_scale = 0.13;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - center);
	vec3 side = normalize(cross(axis, to_cam));
	vec3 world = center + side * VERTEX.x * width + axis * VERTEX.y * length_scale;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
}

void fragment() {
	ALBEDO = tint;
	EMISSION = tint * brightness * 0.12;
	ROUGHNESS = ascii_roughness(0.3, ASCII_STREAK);
}
