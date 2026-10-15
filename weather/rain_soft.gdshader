shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, shadows_disabled, unshaded, blend_mix, depth_draw_never;
// Rain streak for the un-converted image (render style "ASCII off"): a soft,
// motion-blurred, semi-transparent streak that catches the sky light. The
// ASCII styles use the opaque rain_streak.gdshader instead (the ASCII pass
// turns those into slanted strokes).

uniform vec3 tint : source_color = vec3(0.6, 0.65, 0.72);
uniform float brightness = 1.0;
uniform float width = 0.012;
uniform float length_scale = 0.75;
uniform float opacity = 0.32;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - center;
	float dist = length(to_cam);
	to_cam /= max(dist, 1e-4);
	vec3 side = normalize(cross(axis, to_cam));
	// Distant drops get a little wider (and fainter) so they do not alias away.
	float w = width * (1.0 + dist * 0.06);
	vec3 world = center + side * VERTEX.x * w * 2.0 + axis * VERTEX.y * length_scale;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	v_fade = clamp(1.6 / (1.0 + dist * 0.08), 0.15, 1.0) * smoothstep(1.0, 4.0, dist);
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float y = UV.y;
	float a = (1.0 - x * x) * smoothstep(0.0, 0.35, y) * smoothstep(1.0, 0.6, y);
	ALBEDO = tint * brightness;
	ALPHA = a * opacity * v_fade * COLOR.a;
}
