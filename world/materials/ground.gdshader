shader_type spatial;
// Courtyard ground: worn flagstones fading into packed dirt and mud.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 stone_color : source_color = vec3(0.36, 0.34, 0.31);
uniform vec3 grout_color : source_color = vec3(0.08, 0.07, 0.06);
uniform vec3 dirt_color : source_color = vec3(0.2, 0.15, 0.1);
uniform vec3 mud_color : source_color = vec3(0.09, 0.07, 0.05);
uniform float tile_scale = 0.9;
uniform vec2 paved_center = vec2(0.0, 0.0);
uniform float paved_radius = 9.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	vec3 vor = n_voronoi2(p * tile_scale);
	float grout = smoothstep(0.03, 0.12, vor.y - vor.x);
	float slab_tint = 0.75 + vor.z * 0.4;
	float wear = n_fbm2(p * 1.7);
	vec3 slab = stone_color * slab_tint * (0.8 + wear * 0.35);
	vec3 paved = mix(grout_color, slab, grout);

	float dirt_noise = n_fbm2(p * 0.35 + 3.0);
	float edge = length(p - paved_center) / paved_radius;
	float dirt_mask = smoothstep(0.75, 1.15, edge + (dirt_noise - 0.5) * 0.6);
	vec3 dirt = mix(dirt_color, mud_color, smoothstep(0.4, 0.8, n_fbm2(p * 0.8)));
	vec3 col = mix(paved, dirt, dirt_mask);

	// Grout lines and dirt hold water first.
	float wet = clamp(wetness * (1.0 + (1.0 - grout) * 0.8 + dirt_mask * 0.4), 0.0, 1.0);
	ALBEDO = col * (1.0 - wet * 0.5);

	float e = 0.02;
	float hx = n_fbm2((p + vec2(e, 0.0)) * 1.7) - wear;
	float hz = n_fbm2((p + vec2(0.0, e)) * 1.7) - wear;
	vec3 wn = normalize(vec3(-hx / e * 0.015, 1.0, -hz / e * 0.015) + vec3(0.0, (1.0 - grout) * -0.2, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	ROUGHNESS = ascii_roughness(mix(0.9, 0.15, wet), ASCII_GROUND);
	SPECULAR = 0.35;
}
