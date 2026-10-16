shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;
// The shade's robe and hood: heavy, slowly flowing grave-cloth that goes
// thin and ghostly towards the hem, tears into ragged tongues and fades into
// mist. Rest-pose position (CUSTOM0, MobRig) drives every pattern so the
// cloth does not swim while the skirt bones sway. Cold light gathers on the
// silhouette (rim) and the inside of the folds stays dark.
//
// Same per-instance state as the creature shaders (hit flash, burn,
// dissolve), so CreatureModel drives it.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.1, 0.11, 0.14);
uniform vec3 albedo2 : source_color = vec3(0.32, 0.36, 0.42);
uniform vec3 glow_color : source_color = vec3(0.45, 0.8, 1.0);
uniform float rim_energy = 1.6;
// Rest-pose heights (m): fully solid above hem_top, gone below hem_bottom.
uniform float hem_top = 0.85;
uniform float hem_bottom = 0.1;
// Ragged tongues cut into the hem (0 = straight edge).
uniform float tatter = 0.35;
uniform float opacity = 0.9;
uniform float flow_speed = 0.12;

instance uniform float hit_flash = 0.0;
instance uniform vec3 flash_color = vec3(1.0, 1.0, 1.0);
instance uniform float burn = 0.0;
instance uniform float dissolve = 0.0;
instance uniform float intensity : instance_index(15) = 1.0;

varying vec3 v_rest;
varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_rest;
	float ang = atan(p.x, p.z);
	// Long vertical folds that slowly drift, plus fine threads.
	float folds = n_fbm3(vec3(ang * 2.2, p.y * 0.7 - TIME * flow_speed, 0.3));
	float threads = n_fbm3(vec3(ang * 14.0, p.y * 2.0, 1.7));
	float stains = n_fbm3(p * 3.1 + vec3(0.0, -TIME * flow_speed * 0.5, 0.0));

	// Ragged hem: tongues of cloth of different lengths.
	float tongue = n_fbm3(vec3(ang * 3.5, 0.0, 4.1)) * 0.8 + n_fbm3(vec3(ang * 11.0, TIME * 0.05, 7.3)) * 0.35;
	float edge = mix(hem_bottom, hem_top, 0.35) + (tongue - 0.5) * tatter * 2.0 * (hem_top - hem_bottom);
	float below = edge - p.y;
	if (below > 0.0 && n_fbm3(vec3(ang * 20.0, p.y * 9.0, 2.0)) < 0.35 + below * 3.0) {
		discard;
	}
	// Fade into mist towards the bottom.
	float fade = smoothstep(hem_bottom, hem_top, p.y + (stains - 0.5) * 0.25);

	vec3 col = mix(albedo, albedo2, folds * 0.55 + threads * 0.15);
	col *= 0.75 + 0.5 * stains;
	// Ghostly, paler cloth near the hem; the inside of the folds is dark.
	col = mix(col, albedo2 * 0.9, (1.0 - fade) * 0.6);
	if (!FRONT_FACING) {
		col *= 0.35;
	}
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	vec3 emit = glow_color * fres * rim_energy * (0.6 + 0.4 * fade) * intensity;
	// A cold glow seeping through the thinning hem.
	emit += glow_color * (1.0 - fade) * 0.1 * (0.5 + 0.5 * folds) * intensity;

	float alpha = mix(opacity * fade * (0.7 + 0.3 * threads), 1.0, smoothstep(0.85, 1.0, fade));

	if (dissolve > 0.0) {
		float d = n_fbm3(v_world * 1.7);
		if (d < dissolve) {
			discard;
		}
		float e = 1.0 - smoothstep(dissolve, dissolve + 0.08, d);
		emit += glow_color * e * 5.0;
		alpha *= 1.0 - dissolve * 0.5;
	}
	if (burn > 0.0) {
		float f = n_fbm3(v_world * 3.0 + vec3(0.0, -TIME * 1.6, 0.0));
		emit += vec3(1.0, 0.36, 0.07) * burn * pow(f, 3.0) * 7.0;
	}
	ALBEDO = mix(col, flash_color, hit_flash);
	EMISSION = emit + flash_color * hit_flash * 1.6;
	ALPHA = clamp(alpha + hit_flash * 0.3, 0.0, 1.0);
	ROUGHNESS = ascii_roughness(0.92, ASCII_CLOTH);
	SPECULAR = 0.2;
}
