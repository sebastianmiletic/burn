shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Tree / bush leaf cards: alpha-tested atlas (so the ASCII pass sees them as FOLIAGE),
// crown-shaped normals (baked in the mesh) for soft volumetric light, translucency,
// wind sway shared with the bark, per-tree LOD band with dithered cross-fade,
// autumn tint per tree, wet darkening and snow on top.
//   COLOR: r branch weight, g branch phase, b leaf flutter, a crown occlusion
//   INSTANCE_CUSTOM: rgb tint (multiplies the atlas colour), a random 0..1

#include "res://world/flora/shaders/flora_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float lod_begin = 0.0;
uniform float lod_end = 10000.0;
uniform float lod_fade = 6.0;
uniform bool shadow_proxy = false;   // in directional shadow passes ignore lod_begin
uniform float snow_hold = 0.6;       // how much snow these leaves hold (pine needles ~1)
uniform float translucency = 0.7;
uniform float alpha_cut = 0.45;
uniform bool static_mesh = false;    // not instanced (felling FX / props): origin from the node

varying float v_in;
varying float v_out;
varying float v_up;
varying vec3 v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float hm = length(MODEL_MATRIX[1].xyz);
	float hsh = static_mesh ? 0.37 : INSTANCE_CUSTOM.a;
	float d = distance(origin, CAMERA_POSITION_WORLD);
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	float b = (shadow_proxy && ortho) ? 0.0 : lod_begin;
	v_in = b <= 0.0 ? 1.0 : smoothstep(b - lod_fade * 0.5, b + lod_fade * 0.5, d);
	v_out = 1.0 - smoothstep(lod_end - lod_fade * 0.5, lod_end + lod_fade * 0.5, d);
	if (v_in <= 0.0 || v_out <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX = fl_tree_sway(VERTEX, origin, hm, COLOR, hsh);
	}
	v_up = NORMAL.y;
	v_tint = static_mesh ? vec3(1.0) : INSTANCE_CUSTOM.rgb;
}

void fragment() {
	float dth = fl_dither(FRAGCOORD.xy);
	if (dth < 1.0 - v_in || dth >= v_out) {
		discard;
	}
	vec4 tex = texture(albedo_tex, UV);
	// Keep coverage stable in the mips (averaged alpha shrinks leaves at a distance).
	float mip = max(textureQueryLod(albedo_tex, UV).x, 0.0);
	if (tex.a * (1.0 + mip * 0.22) < alpha_cut) {
		discard;
	}
	vec3 col = tex.rgb * v_tint;
	col *= mix(0.8, 1.0, COLOR.a);
	col = fl_wet_albedo(col, 0.35);
	col = fl_snow(col, v_up, snow_hold);
	ALBEDO = col;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.1;
	BACKLIGHT = col * translucency * (1.0 - snow_cover * snow_hold * 0.6);
	SPECULAR = mix(0.3, 0.55, wetness);
	ROUGHNESS = ascii_roughness(fl_wet_rough(0.6), ASCII_FOLIAGE);
}
