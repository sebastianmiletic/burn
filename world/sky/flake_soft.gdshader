shader_type spatial;
render_mode cull_disabled, shadows_disabled, unshaded, blend_mix, depth_draw_never;
// Soft precipitation flake (snow, dust, ash) for the un-converted image.

uniform vec3 tint : source_color = vec3(0.9, 0.92, 0.96);
uniform float brightness = 1.0;
uniform float size = 0.05;
uniform float opacity = 1.0;

varying float v_fade;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float tumble = 0.65 + 0.35 * sin(TIME * 7.0 + MODEL_MATRIX[3].x * 3.1 + MODEL_MATRIX[3].z * 2.3);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(size * tumble, 0, 0, 0), vec4(0, size, 0, 0), vec4(0, 0, size, 0), vec4(0, 0, 0, 1));
	float dist = length(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
	v_fade = smoothstep(0.25, 0.8, dist);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.45, r);
	ALBEDO = tint * brightness;
	ALPHA = a * opacity * v_fade * COLOR.a;
}
