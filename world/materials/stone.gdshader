shader_type spatial;
// Weathered stone for ruins and props. Triplanar procedural albedo, moss on
// upward faces, and a gentle bump so grazing torchlight picks out the surface.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 color_light : source_color = vec3(0.46, 0.43, 0.39);
uniform vec3 color_dark : source_color = vec3(0.22, 0.21, 0.2);
uniform vec3 moss_color : source_color = vec3(0.16, 0.2, 0.09);
uniform float noise_scale = 1.4;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float bump_strength : hint_range(0.0, 1.0) = 0.25;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform int ascii_id = 0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float stone_field(vec3 p) {
	float n = n_fbm3(p * noise_scale);
	float chips = n_value3(p * noise_scale * 6.0);
	return n * 0.8 + chips * 0.2;
}

void fragment() {
	vec3 p = v_world_pos;
	float n = stone_field(p);
	vec3 col = mix(color_dark, color_light, smoothstep(0.25, 0.75, n));

	// Dark grime collects in crevices (low noise) and near the ground.
	float grime = smoothstep(0.45, 0.15, n) * 0.5 + smoothstep(0.6, 0.0, p.y) * 0.25;
	col *= 1.0 - grime * 0.6;

	float up = smoothstep(0.55, 0.95, v_world_normal.y);
	float moss_mask = up * smoothstep(0.35, 0.7, n_fbm3(p * 0.9 + 4.0)) * moss_amount;
	col = mix(col, moss_color, moss_mask);

	// Bump: gradient of the stone field, applied in world space.
	float e = 0.03;
	vec3 grad = vec3(
		stone_field(p + vec3(e, 0.0, 0.0)) - n,
		stone_field(p + vec3(0.0, e, 0.0)) - n,
		stone_field(p + vec3(0.0, 0.0, e)) - n) / e;
	vec3 wn = normalize(v_world_normal - (grad - dot(grad, v_world_normal) * v_world_normal) * bump_strength * 0.05);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	ALBEDO = col * (1.0 - wetness * 0.45);
	ROUGHNESS = ascii_roughness(mix(base_roughness, 0.18, wetness), ascii_id);
	SPECULAR = 0.4;
}
