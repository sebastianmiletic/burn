shader_type spatial;
render_mode cull_back;
// Flowing emissive liquids along a ribbon: lava channels, the river of souls.
// UV.x across the channel (0..1), UV.y along it in metres.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.05, 0.02, 0.01);
uniform vec3 glow_color : source_color = vec3(1.0, 0.35, 0.05);
uniform vec3 hot_color : source_color = vec3(1.0, 0.8, 0.35);
uniform float energy = 3.0;
uniform float speed = 0.5;
uniform float crust = 0.5;      // 0 all molten / spectral .. 1 mostly dark crust
uniform float wisps = 0.0;      // > 0: drifting ghostly streaks (souls)

void fragment() {
	vec2 uv = vec2(UV.x * 2.0, UV.y * 0.35);
	float t = TIME * speed;
	float f1 = n_fbm2(uv * vec2(1.6, 1.0) + vec2(0.0, -t));
	float f2 = n_fbm2(uv * vec2(3.1, 2.2) + vec2(1.7, -t * 1.6));
	float flow = f1 * 0.6 + f2 * 0.4;
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	float molten = smoothstep(crust * 0.8, crust * 0.8 + 0.25, flow + edge * 0.25 - 0.1);
	vec3 e = mix(glow_color, hot_color, smoothstep(0.65, 0.95, flow) * molten) * molten;
	if (wisps > 0.0) {
		float s = n_fbm2(vec2(UV.x * 5.0, UV.y * 0.6 - t * 2.4));
		float streak = smoothstep(0.62, 0.8, s) * edge;
		e += hot_color * streak * wisps;
	}
	ALBEDO = mix(deep_color, deep_color * 0.5, molten);
	EMISSION = e * energy;
	ROUGHNESS = ascii_roughness(mix(0.85, 0.2, molten), ASCII_EMISSIVE);
	SPECULAR = 0.3;
}
