shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Emissive FX layer (fire, sparks, fireballs, magic). Transparent, so it is
// drawn after the ASCII pass and is never turned into glyphs; HDR values
// above the glow threshold bloom across the character grid.
// Billboarded for particles; particle COLOR drives tint and fade.

uniform vec3 hot_color : source_color = vec3(1.0, 0.85, 0.5);
uniform vec3 cool_color : source_color = vec3(1.0, 0.3, 0.05);
uniform float intensity = 6.0;
uniform float softness : hint_range(0.05, 1.0) = 0.6;
uniform bool billboard = true;

void vertex() {
	if (billboard) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		bb = bb * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	}
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, d);
	float shape = pow(core, 1.0 / softness);
	// COLOR.a fades the particle over its life; COLOR.rgb tints it.
	float heat = COLOR.a;
	vec3 col = mix(cool_color, hot_color, clamp(heat * core * 1.4, 0.0, 1.0)) * COLOR.rgb;
	ALBEDO = col * intensity * shape * heat;
	ALPHA = clamp(shape * heat, 0.0, 1.0);
}
