shader_type spatial;
// Standing water: near-black, mirror-smooth, with rain ripples in the normal.
// Screen-space reflections pick up torches and the moon.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 water_color : source_color = vec3(0.012, 0.014, 0.016);
uniform float ripple_strength = 0.35;
uniform float rain_intensity : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_world_pos;

float ripples(vec2 p, float t) {
	// Expanding rings from pseudo-random drop points.
	vec2 i = floor(p);
	vec2 f = fract(p);
	float h = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(n_hash12(i + g), n_hash12(i + g + 3.7));
			float phase = fract(t * 0.9 + n_hash12(i + g + 11.1));
			float d = length(g + o - f);
			float ring = sin((d - phase) * 30.0) * smoothstep(0.0, 0.1, phase - d + 0.1) * (1.0 - phase);
			h += ring * smoothstep(0.5, 0.0, d);
		}
	}
	return h;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz * 2.2;
	float t = TIME;
	float e = 0.02;
	float h = ripples(p, t);
	float hx = ripples(p + vec2(e, 0.0), t) - h;
	float hz = ripples(p + vec2(0.0, e), t) - h;
	float s = ripple_strength * rain_intensity * 0.02;
	vec3 wn = normalize(vec3(-hx / e * s, 1.0, -hz / e * s));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	ALBEDO = water_color;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ROUGHNESS = ascii_roughness(0.02, ASCII_LIQUID);
}
