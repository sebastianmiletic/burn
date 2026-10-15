shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Instanced grass / reed / stubble clumps (geometry blades, no alpha test, so it stays cheap).
//   UV.x across the blade (0..1), UV.y root (0) .. tip (1)
//   COLOR.r per-blade random, COLOR.g dry tip amount, COLOR.b seed head / cattail part
//   INSTANCE_CUSTOM.rgb clump tint, .a random 0..1 (distance thinning + phase)
// Sways with the global wind (gust fronts roll across the field), bends away from
// foliage_pushers, thins and sinks into the ground with distance.

#include "res://world/flora/shaders/flora_common.gdshaderinc"

uniform float fade_end = 50.0;        // fully gone at this distance (m)
uniform float fade_len = 8.0;         // sinks into the ground over this distance before fade_end
uniform float thin_start = 14.0;      // density starts thinning here
uniform float thin_min = 0.35;        // fraction of clumps kept at fade_end
uniform float flex = 1.0;             // 0 rigid stubble .. 1 soft grass .. 1.4 tall grass
uniform float frost = 1.0;            // how strongly snow_cover frosts the tips
uniform vec3 seed_color : source_color = vec3(0.45, 0.33, 0.18);
uniform float translucency = 0.55;
uniform float sheen = 0.3;            // gust brightening (makes rolling wind visible)
uniform float lod_split = 0.0;        // near/far mesh switch distance (0 = single mesh)
uniform bool lod_far = false;         // this material draws the far (sparse) clump mesh

varying float v_t;
varying vec3 v_nw;
varying float v_gust;
varying float v_bend;
varying vec3 v_tint;
varying float v_hash;

void vertex() {
	v_tint = INSTANCE_CUSTOM.rgb;
	v_hash = fract(INSTANCE_CUSTOM.a * 13.71);
	vec3 root = MODEL_MATRIX[3].xyz;
	float hsh = INSTANCE_CUSTOM.a;
	float d = distance(root, CAMERA_POSITION_WORLD);
	float far_t = smoothstep(thin_start, fade_end, d);
	float keep = mix(1.0, thin_min, far_t);
	float grow = 1.0 - smoothstep(fade_end - fade_len, fade_end, d);
	bool wrong_lod = false;
	if (lod_split > 0.0) {
		wrong_lod = (d >= lod_split + fract(hsh * 7.7) * 4.0) != lod_far;
	}
	if (hsh > keep || grow <= 0.001 || wrong_lod) {
		VERTEX = vec3(0.0);
		v_t = 0.0;
		v_nw = vec3(0.0, 1.0, 0.0);
		v_gust = 0.0;
		v_bend = 0.0;
	} else {
		vec3 rel = VERTEX - root;
		// Thinned clumps get a little wider so the field keeps its coverage.
		rel.xz *= 1.0 + far_t * 0.7;
		rel.y *= grow;
		vec3 v = root + rel;
		float t = UV.y;
		vec2 wd = fl_wind_dir();
		float gust = fl_gust(root.xz, TIME);
		float s = wind_strength;
		float ph = hsh * 37.0 + COLOR.r * 11.0;
		float flutter = sin(TIME * (3.1 + COLOR.r * 2.3) + ph) * (0.04 + 0.12 * s) * flex;
		vec2 wind = wd * (s * (0.12 + 0.95 * gust) * flex + flutter * 0.5)
				+ vec2(-wd.y, wd.x) * flutter * 0.6;
		vec2 push = d < 30.0 ? fl_push(root) : vec2(0.0);
		vec2 bend = wind + push * (0.75 + 0.25 * flex);
		v = fl_bend(v, root, bend, t);
		VERTEX = v;
		v_t = t;
		// Soft, mostly-up normals: grass fields read as a lit surface, not as noisy cards.
		v_nw = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.45));
		v_gust = gust * s;
		v_bend = clamp(length(push), 0.0, 1.0);
	}
}

void fragment() {
	vec3 tint = v_tint;
	float t = v_t;
	vec3 col = mix(tint * 0.28, tint, smoothstep(0.0, 0.55, t));
	// Dry, lighter tips and per-blade variation.
	col = mix(col, tint * vec3(1.3, 1.1, 0.75) + vec3(0.05, 0.035, 0.0), COLOR.g * smoothstep(0.55, 1.0, t));
	// Per-blade and per-clump variation: some blades greener, some browner.
	col *= 0.72 + 0.5 * COLOR.r;
	col = mix(col, col * vec3(1.15, 0.92, 0.7), step(0.8, fract(COLOR.r * 7.13 + v_hash * 3.1)) * 0.6);
	col *= 0.85 + 0.3 * v_hash;
	// Faint midrib.
	col *= 1.0 + 0.1 * (1.0 - abs(UV.x * 2.0 - 1.0));
	// Seed heads / cattails.
	col = mix(col, seed_color * (0.75 + 0.5 * COLOR.r), COLOR.b);
	// Gust fronts and trampled grass catch the light differently.
	col *= 1.0 + v_gust * sheen - v_bend * 0.12;
	col = fl_wet_albedo(col, 0.6);
	col = fl_snow(col, 1.0, frost * smoothstep(0.25, 0.9, t) * (1.0 - COLOR.b * 0.5));
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_nw, 0.0)).xyz);
	AO = mix(0.35, 1.0, smoothstep(0.0, 0.7, t));
	AO_LIGHT_AFFECT = 0.25;
	BACKLIGHT = col * translucency;
	SPECULAR = mix(0.28, 0.5, wetness);
	ROUGHNESS = ascii_roughness(fl_wet_rough(0.62), ASCII_FOLIAGE);
}
