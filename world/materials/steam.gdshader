shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float soft = 1.0 - smoothstep(0.1, 1.0, radius);
	ALBEDO = vec3(0.65, 0.73, 0.72);
	ALPHA = COLOR.a * soft * soft * 0.4;
}
