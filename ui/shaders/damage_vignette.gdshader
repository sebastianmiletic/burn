shader_type canvas_item;
// Red edges when health is low or a hit lands; a cold blue tint while frozen
// or in water could reuse this with another colour.

uniform float low = 0.0;      // 0..1 persistent low-health strength
uniform float hit = 0.0;      // 0..1 flash on damage
uniform float time = 0.0;
uniform vec3 color = vec3(0.75, 0.05, 0.02);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p * vec2(1.2, 1.0));
	float pulse = 0.75 + 0.25 * sin(time * 5.0);
	float edge = smoothstep(0.28, 0.75, r);
	float a = edge * (low * 0.55 * pulse + hit * 0.45);
	COLOR = vec4(color, clamp(a, 0.0, 0.85));
}
