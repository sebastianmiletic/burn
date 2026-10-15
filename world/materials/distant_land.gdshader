shader_type spatial;
#include "res://rendering/materials/ascii_material.gdshaderinc"
uniform sampler2D coverage : filter_nearest, repeat_disable;
uniform float world_size = 3072.0;
uniform vec3 focus;
uniform float near_radius = 112.0;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Sink the overlap zone below the detailed field to prevent z-fighting.
	float near = 1.0 - smoothstep(near_radius, near_radius + 64.0, distance(world_pos.xz, focus.xz));
	VERTEX.y -= near * 5.0;
}
void fragment() {
	// Keep the horizon until every requested mesh in this column is ready.
	// Distance-only removal exposed holes during fast travel and mountain climbs.
	if (texture(coverage, world_pos.xz / world_size).r > 0.5) discard;
	ALBEDO = COLOR.rgb;
	ROUGHNESS = ascii_roughness(0.9, ASCII_GROUND);
}
