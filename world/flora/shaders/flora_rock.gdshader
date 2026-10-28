shader_type spatial;
render_mode world_vertex_coords;
// Boulders and pebbles: triplanar photographic rock, moss and lichen on top, wet sheen,
// snow, per-instance distance fade (dithered).
//   INSTANCE_CUSTOM: r moss amount, g tint (0 grey .. 1 warm), b darkness, a random

#include "res://world/flora/shaders/flora_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 moss_color : source_color = vec3(0.2, 0.26, 0.07);
uniform vec3 lichen_color : source_color = vec3(0.62, 0.58, 0.42);
uniform float tex_scale = 0.45;
uniform float fade_end = 120.0;
uniform float fade_len = 10.0;
uniform float ascii_class = 0.0;   // 0 solid (boulders), 4 ground (pebbles)

varying vec4 v_custom;
varying vec3 v_wp;
varying vec3 v_wn;
varying float v_fade;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = distance(origin, CAMERA_POSITION_WORLD);
	v_fade = 1.0 - smoothstep(fade_end - fade_len, fade_end, d);
	if (v_fade <= 0.0) {
		VERTEX = vec3(0.0);
	}
	v_wp = VERTEX;
	v_wn = NORMAL;
}

void fragment() {
	if (fl_dither(FRAGCOORD.xy) >= v_fade) {
		discard;
	}
	vec3 n = normalize(v_wn);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_wp * tex_scale;
	vec3 cx = texture(albedo_tex, p.zy).rgb;
	vec3 cy = texture(albedo_tex, p.xz).rgb;
	vec3 cz = texture(albedo_tex, p.xy).rgb;
	vec3 col = cx * w.x + cy * w.y + cz * w.z;
	vec3 nx = texture(normal_tex, p.zy).rgb * 2.0 - 1.0;
	vec3 ny = texture(normal_tex, p.xz).rgb * 2.0 - 1.0;
	vec3 nz = texture(normal_tex, p.xy).rgb * 2.0 - 1.0;
	// Whiteout-style triplanar normal blend in world space.
	vec3 tn = normalize(vec3(nx.z, nx.y, nx.x) * w.x * vec3(sign(n.x), 1.0, 1.0)
			+ vec3(ny.x, ny.z, ny.y) * w.y * vec3(1.0, sign(n.y), 1.0)
			+ vec3(nz.x, nz.y, nz.z) * w.z * vec3(1.0, 1.0, sign(n.z)));
	vec3 wn = normalize(n + (tn - n * dot(tn, n)) * 0.9);

	float lum = dot(col, vec3(0.333));
	col = mix(col, col * vec3(1.12, 1.0, 0.85), v_custom.g);
	col *= 1.0 - v_custom.b * 0.4;
	float m = n_fbm3(v_wp * 1.3);
	float moss_mask = v_custom.r * smoothstep(0.15, 0.65, n.y * 0.8 + m * 0.6 - 0.15);
	col = mix(col, moss_color * (0.55 + 0.9 * m), clamp(moss_mask, 0.0, 1.0));
	float lich = smoothstep(0.72, 0.8, n_value3(v_wp * 6.0)) * (1.0 - moss_mask) * 0.6;
	col = mix(col, lichen_color, lich);
	col = fl_wet_albedo(col, 0.6);
	col = fl_snow(col, wn.y, 1.0);
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	SPECULAR = mix(0.35, 0.6, wetness);
	float r = mix(0.85, 0.95, moss_mask);
	ROUGHNESS = ascii_roughness(fl_wet_rough(r), int(ascii_class));
}
