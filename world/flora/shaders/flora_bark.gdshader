shader_type spatial;
render_mode world_vertex_coords;
// Tree trunks and branches (also fallen logs): photographic bark (albedo + normal map),
// roughness from the bark cavities, moss on the shaded/upward side, wet darkening,
// snow on top, wind sway identical to the leaves so crowns stay attached.
//   COLOR: r branch weight, g phase, b 0, a occlusion (root flare / forks)

#include "res://world/flora/shaders/flora_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bark_tint : source_color = vec3(1.0);
uniform vec3 moss_color : source_color = vec3(0.22, 0.27, 0.09);
uniform float moss = 0.35;
uniform float lod_begin = 0.0;
uniform float lod_end = 10000.0;
uniform float lod_fade = 6.0;
uniform bool shadow_proxy = false;
uniform bool static_mesh = false;   // not instanced: no wind, origin from the node
uniform bool wind_sway = true;

varying float v_in;
varying float v_out;
varying vec3 v_wn;
varying vec3 v_wp;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float hm = length(MODEL_MATRIX[1].xyz);
	float hsh = static_mesh ? 0.37 : INSTANCE_CUSTOM.a;
	float d = distance(origin, CAMERA_POSITION_WORLD);
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	float b = (shadow_proxy && ortho) ? 0.0 : lod_begin;
	v_in = b <= 0.0 ? 1.0 : smoothstep(b - lod_fade * 0.5, b + lod_fade * 0.5, d);
	v_out = 1.0 - smoothstep(lod_end - lod_fade * 0.5, lod_end + lod_fade * 0.5, d);
	v_wn = NORMAL;
	v_wp = VERTEX - origin;
	if (v_in <= 0.0 || v_out <= 0.0) {
		VERTEX = vec3(0.0);
	} else if (wind_sway) {
		VERTEX = fl_tree_sway(VERTEX, origin, hm, COLOR, hsh);
	}
}

void fragment() {
	float dth = fl_dither(FRAGCOORD.xy);
	if (dth < 1.0 - v_in || dth >= v_out) {
		discard;
	}
	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.333));
	vec3 col = tex * bark_tint;
	// Moss: on the up-facing side and low on the trunk, patchy.
	float m = n_fbm3(v_wp * 1.7);
	float moss_mask = moss * smoothstep(0.35, 0.75, m + v_wn.y * 0.35 + (1.0 - COLOR.a) * 0.3);
	moss_mask *= smoothstep(0.08, 0.35, lum);
	col = mix(col, moss_color * (0.6 + 0.8 * m), clamp(moss_mask, 0.0, 1.0));
	col *= mix(0.45, 1.0, COLOR.a);
	col = fl_wet_albedo(col, 0.7);
	col = fl_snow(col, v_wn.y, 0.9 * smoothstep(0.2, 0.5, lum + 0.2));
	ALBEDO = col;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.3;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.4;
	float r = mix(0.95, 0.75, lum);
	SPECULAR = 0.3;
	ROUGHNESS = ascii_roughness(fl_wet_rough(r), ASCII_SOLID);
}
