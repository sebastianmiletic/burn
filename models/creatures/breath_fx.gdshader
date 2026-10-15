shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Flame licks for breath streams (BreathStream): a billboard whose outline is
// torn by animated noise and whose colour cools with the particle's age
// (white-yellow core at the mouth, orange body, deep red tongues). Additive,
// drawn after the ASCII pass so it blooms over the glyph grid.

#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 hot_color : source_color = vec3(1.0, 0.92, 0.65);
uniform vec3 mid_color : source_color = vec3(1.0, 0.48, 0.1);
uniform vec3 cool_color : source_color = vec3(0.55, 0.08, 0.02);
uniform float intensity = 4.0;
uniform float tear = 0.9;
// Soft particles: fade where a flame lick meets the ground or a wall.
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform float softness = 1.6;

varying float v_age;
varying float v_seed;

void vertex() {
	// Age from the colour ramp (alpha 1 -> 0 over the particle's life).
	v_age = 1.0 - COLOR.a;
	v_seed = float(INSTANCE_ID % 97) * 0.173;
	float a = v_seed * 6.2831 + v_age * 1.5;
	mat4 rot = mat4(vec4(cos(a), sin(a), 0.0, 0.0), vec4(-sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)) * rot;
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float n = n_fbm3(vec3(uv * 2.6 + v_seed * 7.0, TIME * 1.7 + v_seed * 3.0));
	float d = length(uv) * 2.0 + (n - 0.5) * tear * (0.4 + v_age);
	float shape = 1.0 - smoothstep(0.25, 1.0, d);
	shape *= shape;
	float age = clamp(v_age, 0.0, 1.0);
	vec3 col = mix(hot_color, mid_color, smoothstep(0.05, 0.35, age));
	col = mix(col, cool_color, smoothstep(0.35, 0.85, age));
	float fade = smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.55, 1.0, age));
	float core = 1.0 - smoothstep(0.0, 0.55, d);
	float scene_z = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_z, 1.0);
	float scene_d = -sv.z / sv.w;
	float soft = clamp((scene_d + VERTEX.z) / softness, 0.0, 1.0);
	ALBEDO = (col + hot_color * core * (1.0 - age) * 0.5) * intensity * shape * fade * soft;
	ALPHA = clamp(shape * fade * soft, 0.0, 1.0);
}
