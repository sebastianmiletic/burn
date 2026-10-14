shader_type canvas_item;
// Full map: terrain colours redrawn as an ember dot field with a parchment-
// dark ground, matching the minimap.

uniform float cells = 200.0;
uniform int style = 0;

vec3 ember(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c0 = vec3(0.04, 0.015, 0.01);
	vec3 c1 = vec3(0.3, 0.09, 0.03);
	vec3 c2 = vec3(0.75, 0.38, 0.15);
	vec3 c3 = vec3(1.0, 0.82, 0.6);
	if (t < 0.33) return mix(c0, c1, t / 0.33);
	if (t < 0.66) return mix(c1, c2, (t - 0.33) / 0.33);
	return mix(c2, c3, (t - 0.66) / 0.34);
}

void fragment() {
	vec2 g = UV * cells;
	vec2 gc = floor(g) + 0.5;
	vec3 c = texture(TEXTURE, gc / cells).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 tone = ember(pow(lum, 0.8) * 1.15);
	float d = length(g - gc);
	float ink = 1.0 - smoothstep(0.3 + lum * 0.22, 0.42 + lum * 0.22, d);
	COLOR = vec4(mix(tone * 0.2, tone * 1.15, ink), 1.0);
}
