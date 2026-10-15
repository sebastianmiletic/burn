shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Lightning channel ribbon (LightningBolt). Additive, so it is drawn after the
// ASCII pass and its HDR core blooms through Godot's glow. COLOR.r = heat of
// the branch (main channel 1, side branches dimmer).

uniform float intensity = 20.0;

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float core = exp(-x * x * 18.0);
	float halo = exp(-x * x * 3.0) * 0.25;
	vec3 hot = vec3(0.92, 0.95, 1.0);
	vec3 glow = vec3(0.55, 0.62, 1.0);
	ALBEDO = (hot * core + glow * halo) * intensity * COLOR.r;
	ALPHA = 1.0;
}
