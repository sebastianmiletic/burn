shader_type spatial;
render_mode cull_disabled;
// Instanced grass blade. UV.y runs 0 at the root to 1 at the tip.
// Wind bends blades along the global wind direction, with gusts rolling
// across the field.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 root_color : source_color = vec3(0.05, 0.08, 0.03);
uniform vec3 tip_color : source_color = vec3(0.32, 0.4, 0.14);
uniform vec3 dry_color : source_color = vec3(0.42, 0.35, 0.16);
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength = 0.6;
uniform float gust_scale = 0.08;
uniform float gust_speed = 1.6;

varying float v_tip;
varying vec3 v_tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	vec2 wd = normalize(wind_direction);
	float tip = UV.y;

	float gust = n_value2(root.xz * gust_scale - wd * TIME * gust_speed);
	float flutter = sin(TIME * 4.3 + root.x * 3.1 + root.z * 2.3) * 0.12;
	float bend = (wind_strength * (0.25 + gust * 1.1) + flutter) * tip * tip;

	world.xz += wd * bend * 0.6;
	world.y -= bend * bend * 0.12;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;

	v_tip = tip;
	float patch = n_fbm2(root.xz * 0.12);
	v_tint = mix(tip_color, dry_color, smoothstep(0.55, 0.8, patch));
}

void fragment() {
	vec3 col = mix(root_color, v_tint, smoothstep(0.0, 1.0, v_tip));
	ALBEDO = col;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = col * 0.6;
	ROUGHNESS = ascii_roughness(0.65, ASCII_FOLIAGE);
	SPECULAR = 0.25;
}
