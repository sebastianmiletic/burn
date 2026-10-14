shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Weapon swing trail: an additive arc that fades towards its tail (UV.x = 0)
// and is brightest along its outer edge (UV.y = 1). FX layer, so it glows over
// the glyphs instead of being turned into them.

uniform vec3 color : source_color = vec3(1.0, 0.7, 0.4);
uniform float alpha = 0.0;
uniform float head = 1.0;  // 0..1: how far along the arc the swing has reached

void fragment() {
	float along = UV.x;
	if (along > head) {
		discard;
	}
	float tail = smoothstep(head - 0.55, head, along);
	float edge = pow(UV.y, 2.5);
	float a = tail * edge * alpha;
	ALBEDO = color * a * 4.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
