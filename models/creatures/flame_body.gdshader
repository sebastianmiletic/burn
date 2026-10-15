shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Living fire on a skinned mesh (the fire elemental's body, vortex, crest and
// burning fists): rising tongues of flame torn by scrolling noise, a white-
// yellow core where the surface faces the eye, cooling to orange and red at
// the silhouette and the licking tips. Vertices flicker outwards along their
// normals so the outline dances. Additive, unshaded, after the ASCII pass.
// `flare` (per instance) stokes it: roar, wind-up; 0 puts it out (death).

#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 hot_color : source_color = vec3(1.0, 0.9, 0.6);
uniform vec3 mid_color : source_color = vec3(1.0, 0.45, 0.08);
uniform vec3 cool_color : source_color = vec3(0.6, 0.08, 0.02);
uniform float intensity = 1.0;
uniform float scale = 3.2;
uniform float rise = 1.6;
uniform float lick = 0.09;
// Rest-pose positions in CUSTOM0 (MobRig) keep the flames attached to limbs.
uniform bool use_rest = true;

instance uniform float flare = 1.0;

varying vec3 v_rest;
varying float v_lick;

void vertex() {
	v_rest = use_rest ? CUSTOM0.xyz : VERTEX;
	float n = n_fbm3(v_rest * scale * 0.7 + vec3(0.0, -TIME * rise, 0.0));
	v_lick = n;
	VERTEX += NORMAL * (n - 0.35) * lick * (0.6 + 0.4 * flare);
}

void fragment() {
	vec3 p = v_rest * scale + vec3(0.0, -TIME * rise * 1.4, 0.0);
	float n1 = n_fbm3(p);
	float n2 = n_fbm3(p * 2.3 + vec3(3.1, -TIME * rise, 1.7));
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	// Tongues: streaks stretched upward, torn more at the silhouette.
	float tongue = smoothstep(0.5, 0.85, n1 * 0.7 + n2 * 0.45 + ndv * 0.15 - (1.0 - ndv) * 0.2);
	float heat = clamp(tongue * (0.25 + ndv * 0.6) + v_lick * 0.15, 0.0, 1.0);
	vec3 col = mix(cool_color, mid_color, smoothstep(0.1, 0.5, heat));
	col = mix(col, hot_color, smoothstep(0.55, 0.95, heat));
	float a = tongue * (0.25 + 0.5 * ndv) * (1.0 - pow(1.0 - ndv, 4.0) * 0.6);
	ALBEDO = col * intensity * clamp(flare, 0.0, 3.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
