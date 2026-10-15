shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Modelled buildings and props (ArchMesh). One material for a whole village:
// the texture layer, snow, wear, tint and grime travel with the vertices.
//   UV     metres along the surface (scaled by layer_info.xy); the tangent frame
//          comes from screen-space derivatives, so meshes carry no tangents
//   UV2.x  layer + snow * 0.9        UV2.y  wear (moss, damp, colour drift); glass: lit at night
//   COLOR  rgb tint, a grime (1 clean .. 0 sooty)
// Layers 0..11 sample the CC0 Poly Haven arrays (see CREDITS.md); 12 glass,
// 13 embers, 14 flat colour, 15 water are procedural.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform float wetness;
global uniform float snow_cover;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
// xy: 1 / tile size (m), z: roughness multiplier, w: ASCII class.
uniform vec4 layer_info[16];
uniform float night_glow : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength = 1.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.62, 0.3);

varying vec3 v_world;
varying vec3 v_wnormal;
varying flat int v_layer;
varying float v_snow;
varying float v_wear;

void vertex() {
	float l = floor(UV2.x + 0.001);
	v_layer = int(l);
	v_snow = clamp((UV2.x - l) / 0.9, 0.0, 1.0);
	v_wear = UV2.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int L = v_layer;
	vec3 n = normalize(v_wnormal);
	// Tangent frame from screen-space derivatives (no stored tangents):
	// t along +u, b towards the top of the texture (-v).
	vec3 dp1 = dFdx(v_world);
	vec3 dp2 = dFdy(v_world);
	vec2 duv1 = dFdx(UV);
	vec2 duv2 = dFdy(UV);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 tt = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 bb = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(tt, tt), dot(bb, bb)), 1e-20));
	vec3 t = tt * invmax;
	vec3 b = -bb * invmax;
	vec3 albedo = vec3(0.5);
	vec3 wn = n;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	float ao = 1.0;
	float spec = 0.5;
	int cls = ASCII_SOLID;
	float up = n.y;
	if (L == 12) {
		// Leaded glass: diamond quarries in lead cames, a little uneven.
		vec2 g = UV * 5.2;
		vec2 d = abs(fract(vec2(g.x + g.y, g.x - g.y) * 0.5) - 0.5);
		float came = 1.0 - smoothstep(0.035, 0.07, min(d.x, d.y));
		float pane = n_hash12(floor(vec2(g.x + g.y, g.x - g.y) * 0.5));
		albedo = mix(vec3(0.05, 0.075, 0.07) * (0.8 + pane * 0.4), vec3(0.07, 0.065, 0.06), came);
		rough = mix(0.06 + pane * 0.08, 0.5, came);
		spec = mix(0.6, 0.3, came);
		metal = came * 0.3;
		// Wobbly crown glass.
		vec2 wob = vec2(n_value2(UV * 9.0 + pane * 7.0), n_value2(UV * 9.0 - 3.0)) - 0.5;
		wn = normalize(n + (t * wob.x + b * wob.y) * 0.12 * (1.0 - came));
		float lit = step(0.5, v_wear) * night_glow;
		// Warm firelit room behind: brighter low down, shapes of the room.
		float room = 0.55 + 0.45 * n_value2(UV * 1.7 + vec2(pane * 0.2, TIME * 0.05));
		float flick = 0.85 + 0.15 * sin(TIME * 7.0 + v_world.x * 3.1) * sin(TIME * 4.3 + v_world.z);
		emit = window_color * lit * (1.0 - came * 0.92) * room * flick * 1.35;
		cls = lit > 0.3 ? ASCII_EMISSIVE : ASCII_SOLID;
	} else if (L == 13) {
		// Glowing embers / coals.
		float h = n_fbm3(v_world * 3.0 + vec3(0.0, TIME * 0.35, 0.0));
		float cracks = smoothstep(0.35, 0.75, h);
		albedo = vec3(0.04, 0.03, 0.025);
		emit = mix(vec3(0.6, 0.05, 0.0), vec3(1.6, 0.6, 0.12), cracks) * (1.4 + 0.6 * sin(TIME * 3.0 + h * 6.0)) * COLOR.rgb;
		rough = 0.9;
		cls = ASCII_EMISSIVE;
	} else if (L == 14) {
		albedo = COLOR.rgb * (0.9 + 0.2 * n_value3(v_world * 2.0));
		rough = 0.75;
	} else if (L == 15) {
		// Still water in wells and troughs.
		vec2 r1 = vec2(n_value2(v_world.xz * 3.0 + TIME * 0.3), n_value2(v_world.xz * 3.0 - TIME * 0.27 + 5.0)) - 0.5;
		wn = normalize(n + vec3(r1.x, 0.0, r1.y) * 0.08);
		albedo = vec3(0.02, 0.035, 0.035);
		rough = 0.04;
		spec = 0.6;
		cls = ASCII_LIQUID;
	} else {
		vec4 info = layer_info[L];
		vec2 uv = UV * info.xy;
		vec3 alb = texture(albedo_tex, vec3(uv, float(L))).rgb;
		vec4 nr = texture(normal_tex, vec3(uv, float(L)));
		vec2 tn = (nr.xy * 2.0 - 1.0) * normal_strength;
		wn = normalize(n * sqrt(max(0.0, 1.0 - dot(tn, tn))) + t * tn.x + b * tn.y);
		ao = mix(1.0, nr.b, 0.85);
		rough = clamp(nr.a * info.z, 0.05, 1.0);
		cls = int(info.w + 0.5);
		// Break up tiling and give each piece a slightly different colour.
		float drift = n_fbm3(v_world * 0.23) - 0.5;
		float piece = n_hash13(floor(v_world * 0.5 + n * 0.3)) - 0.5;
		albedo = alb * COLOR.rgb * (1.0 + drift * 0.22 + piece * 0.05 * v_wear);
		// Grime: soot / splashback / damp, broken up by noise.
		float gn = n_fbm3(v_world * vec3(1.3, 0.6, 1.3));
		float grime = clamp(1.0 - (1.0 - COLOR.a) * (0.7 + gn * 0.6), 0.0, 1.0);
		albedo *= mix(vec3(0.36, 0.33, 0.3), vec3(1.0), grime);
		rough = mix(rough, min(1.0, rough + 0.1), 1.0 - grime);
		// Wear: green moss on upward faces, dark damp streaks running down walls.
		float moss_n = n_fbm3(v_world * 1.7 + 11.0);
		float moss = v_wear * smoothstep(0.15, 0.7, up + moss_n * 0.6 - 0.25) * smoothstep(0.4, 0.75, moss_n);
		albedo = mix(albedo, vec3(0.11, 0.14, 0.06) * (0.7 + moss_n * 0.6), clamp(moss, 0.0, 0.85));
		float streak = n_value2(vec2(v_world.x * 5.0 + v_world.z * 5.0, v_world.y * 0.35));
		float side = 1.0 - abs(up);
		albedo *= 1.0 - v_wear * side * smoothstep(0.55, 0.9, streak) * 0.3;
	}
	// Snow settles on upward faces (roofs, sills, beams); weather adds more.
	// Paths and squares are trodden clear.
	float sn = max(v_snow, snow_cover * (L == 10 ? 0.3 : 0.85));
	if (sn > 0.0 && L != 12 && L != 13 && L != 15) {
		float noise_s = n_fbm3(v_world * 1.1);
		float lie = smoothstep(0.25, 0.75, n.y + noise_s * 0.35);
		float s = clamp(sn * 1.6 * lie - (1.0 - lie) * 0.3, 0.0, 1.0);
		s = smoothstep(0.25, 0.6, s + (noise_s - 0.5) * 0.4);
		albedo = mix(albedo, vec3(0.86, 0.89, 0.93), s);
		wn = normalize(mix(wn, n, s * 0.8));
		rough = mix(rough, 0.55, s);
		ao = mix(ao, 1.0, s * 0.6);
	}
	float wet = wetness * smoothstep(-0.2, 0.6, up);
	if (L <= 11) {
		albedo *= 1.0 - wet * 0.3;
		rough = mix(rough, 0.2, wet * 0.6);
	}
	ALBEDO = albedo;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = ascii_roughness(rough, cls);
	METALLIC = metal;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	EMISSION = emit;
}
