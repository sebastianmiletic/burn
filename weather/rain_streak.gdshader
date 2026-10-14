shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, shadows_disabled;
// Opaque rain streak for GPU particles. The quad is stretched along the
// particle's velocity (particle Y axis, see ParticleProcessMaterial
// align_y) and turned to face the camera. It is drawn opaque with the
// STREAK material id so the ASCII pass replaces it with a slanted stroke.

#include "res://rendering/materials/ascii_material.gdshaderinc"

uniform vec3 streak_color : source_color = vec3(0.55, 0.6, 0.68);
uniform float width = 0.008;
uniform float length_scale = 0.55;
uniform float self_light = 0.06;

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
	ALBEDO = streak_color;
	EMISSION = streak_color * self_light;
	ROUGHNESS = ascii_roughness(0.3, ASCII_STREAK);
}
