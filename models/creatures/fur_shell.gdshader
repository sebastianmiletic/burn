shader_type spatial;
// Fur shells: drawn as next passes over a creature_skin body (CreatureSkin.with_fur),
// each pass pushed out along the normal by `layer` x `fur_length` and cut into
// strands and clumps by 3D noise in the rest pose (CUSTOM0), so the coat has
// a soft, broken silhouette and depth instead of a painted surface. Strands
// thin out towards the outer shells, droop a little and part along the body.
// Shells collapse beyond `fur_distance` (no cost far away). Shares the
// body's colouring (countershading, dorsal saddle) and per-instance state.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
uniform vec3 belly : source_color = vec3(0.75, 0.7, 0.6);
uniform float belly_mix = 0.7;
uniform vec3 accent : source_color = vec3(0.15);
uniform int accent_mode = 0;
uniform float accent_amount = 0.0;
uniform float accent_scale = 1.0;
uniform vec3 tip_color : source_color = vec3(1.0);
uniform float tip_mix = 0.25;
uniform float fur_length = 0.02;
uniform float layer = 0.5;
// Strand cells per metre and clump size.
uniform float density = 260.0;
uniform float clump_scale = 30.0;
uniform float droop = 0.35;
uniform float fur_distance = 22.0;
uniform float roughness = 0.9;
uniform float rim = 0.5;
uniform int ascii_id = 0;
uniform bool use_rest = true;

instance uniform float hit_flash = 0.0;
instance uniform vec3 flash_color = vec3(1.0, 1.0, 1.0);
instance uniform float burn = 0.0;
instance uniform float dissolve = 0.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_wnormal;

void vertex() {
	v_local = use_rest ? CUSTOM0.xyz : VERTEX;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(wpos - CAMERA_POSITION_WORLD);
	// Clumps vary the length a little; strands droop and lie back.
	float clump = n_value3(v_local * clump_scale);
	// CUSTOM0.w (MobRig.param) shortens the coat: 0 full fur .. 1 bare skin.
	float len = fur_length * layer * (0.7 + 0.6 * clump) * (use_rest ? 1.0 - CUSTOM0.w : 1.0);
	VERTEX += NORMAL * len;
	VERTEX.y -= droop * len * layer;
	if (d > fur_distance || (use_rest && CUSTOM0.w > 0.97)) {
		VERTEX = vec3(0.0);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Strands: fine fibrous noise in the rest pose (no lattice), gathered
	// into clumps so the coat parts into locks; fewer strands reach the
	// outer shells, so they taper.
	vec3 q = v_local * density * 2.0;
	float strand = n_value3(q) * 0.55 + n_value3(q * 2.37 + vec3(7.1, 3.3, 1.7)) * 0.45;
	float clump = n_value3(v_local * clump_scale);
	float h = strand * 0.9 + clump * 0.22;
	if (h < layer * 0.5 + 0.28) {
		discard;
	}
	if (dissolve > 0.0) {
		float dd = n_fbm3(v_world * 1.7);
		if (dd < dissolve + 0.05) {
			discard;
		}
	}
	float down = clamp(-v_wnormal.y * 1.4 + 0.15, 0.0, 1.0);
	vec3 col = mix(albedo, belly, down * belly_mix);
	if (accent_mode == 3 && accent_amount > 0.0) {
		float m = smoothstep(0.1, 0.6, v_wnormal.y) * smoothstep(0.35, 0.65, n_fbm3(v_local * accent_scale * 0.8) + 0.25);
		col = mix(col, accent, m * accent_amount);
	} else if (accent_mode == 1 && accent_amount > 0.0) {
		float w = n_fbm3(v_local * accent_scale * 1.5) * 0.6;
		float m = smoothstep(0.55, 0.75, abs(fract(v_local.z * accent_scale * 0.5 + w) - 0.5) * 2.0);
		col = mix(col, accent, m * accent_amount);
	}
	// Lighter tips, darker roots; per-strand variation.
	col *= 0.8 + 0.35 * strand;
	col = mix(col, col * tip_color * 1.25, tip_mix * layer);
	col *= mix(0.65, 1.0, layer);
	vec3 emit = vec3(0.0);
	if (burn > 0.0) {
		float b = n_fbm3(v_world * 3.0 + vec3(0.0, -TIME * 1.6, 0.0));
		emit += vec3(1.0, 0.36, 0.07) * burn * pow(b, 3.0) * 7.0;
	}
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	emit += albedo * pow(1.0 - ndv, 3.0) * rim * layer;
	emit += col * 0.1;
	ALBEDO = mix(col, flash_color, hit_flash);
	EMISSION = emit + flash_color * hit_flash * 1.6;
	ROUGHNESS = ascii_roughness(roughness, ascii_id);
	SPECULAR = 0.25;
	AO = mix(0.55, 1.0, layer);
}
