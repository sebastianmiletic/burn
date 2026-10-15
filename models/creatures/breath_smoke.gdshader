shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Soot / ash billows trailing a breath stream (BreathStream): soft, torn,
// dark puffs that grow and thin out with age.

#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 smoke_color : source_color = vec3(0.09, 0.07, 0.06);
uniform vec3 lit_color : source_color = vec3(0.5, 0.2, 0.06);
uniform float density = 0.55;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying float v_age;
varying float v_seed;

void vertex() {
	// Age from the colour ramp (alpha 1 -> 0 over the particle's life).
	v_age = 1.0 - COLOR.a;
	v_seed = float(INSTANCE_ID % 89) * 0.211;
	float a = v_seed * 6.2831 + v_age * 0.8;
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
	float n = n_fbm3(vec3(uv * 2.2 + v_seed * 5.0, TIME * 0.5 + v_seed));
	float d = length(uv) * 2.0 + (n - 0.5) * 0.8;
	float shape = 1.0 - smoothstep(0.2, 1.0, d);
	float age = clamp(v_age, 0.0, 1.0);
	float fade = smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.45, 1.0, age));
	// Young smoke still carries the glow of the fire beneath it.
	ALBEDO = mix(lit_color, smoke_color, smoothstep(0.0, 0.35, age)) * (0.7 + 0.5 * n);
	float scene_z = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_z, 1.0);
	float soft = clamp((-sv.z / sv.w + VERTEX.z) / 2.0, 0.0, 1.0);
	ALPHA = clamp(shape * fade * density * soft, 0.0, 1.0);
}
