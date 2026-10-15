shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Weapon swing trail ribbon (FX layer, additive, blooms over the glyphs).
// UV.x: 0 oldest sample .. 1 newest, UV.y: 0 at the grip .. 1 at the tip.
// COLOR.a carries the per-sample fade.

uniform vec3 color : source_color = vec3(1.0, 0.7, 0.4);
uniform float intensity = 2.2;

void fragment() {
	float along = UV.x;
	float edge = smoothstep(0.15, 1.0, UV.y);
	float a = pow(along, 1.6) * edge * edge * COLOR.a;
	// A hot leading edge along the blade tip.
	float hot = smoothstep(0.88, 1.0, UV.y) * along;
	ALBEDO = (color * a + vec3(1.0, 0.95, 0.85) * hot * a * 0.6) * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
