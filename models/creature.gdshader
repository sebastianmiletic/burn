shader_type spatial;
// Shared material for creature and character models.
// Per-instance state (set with set_instance_shader_parameter) lets every
// mesh share one material per colour while flashing, burning and dissolving
// independently.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform int ascii_id = 0;
uniform float detail : hint_range(0.0, 1.0) = 0.22;
uniform float detail_scale = 5.0;
uniform float rim = 0.0;

instance uniform float hit_flash = 0.0;
instance uniform vec3 flash_color = vec3(1.0, 1.0, 1.0);
instance uniform float burn = 0.0;
instance uniform float dissolve = 0.0;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = n_fbm3(v_local * detail_scale);
	vec3 col = albedo * (1.0 - detail + n * detail * 2.0);
	vec3 emit = vec3(0.0);

	if (dissolve > 0.0) {
		float d = n_fbm3(v_world * 1.7);
		if (d < dissolve) {
			discard;
		}
		float edge = 1.0 - smoothstep(dissolve, dissolve + 0.07, d);
		emit += vec3(1.0, 0.42, 0.1) * edge * 6.0;
		col *= 1.0 - edge * 0.8;
	}
	if (burn > 0.0) {
		float f = n_fbm3(v_world * 3.0 + vec3(0.0, -TIME * 1.6, 0.0));
		emit += vec3(1.0, 0.36, 0.07) * burn * pow(f, 3.0) * 7.0;
	}
	if (rim > 0.0) {
		float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		emit += albedo * r * rim;
	}

	// A little self-illumination keeps characters readable as glyphs even when
	// back-lit against bright ground (they would otherwise become blank holes).
	emit += col * 0.16;
	ALBEDO = mix(col, flash_color, hit_flash);
	EMISSION = emit + flash_color * hit_flash * 1.6;
	ROUGHNESS = ascii_roughness(roughness, ascii_id);
	SPECULAR = 0.35;
}
