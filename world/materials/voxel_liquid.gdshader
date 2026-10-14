shader_type spatial;
render_mode cull_disabled;
// Water and lava surfaces. Drawn opaque so the ASCII pass sees them: water is
// tagged LIQUID (animated ~ - = glyphs), lava EMISSIVE (passed through and
// glowing).

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

varying vec3 v_world;
varying flat float v_block;
varying float v_sky;

void vertex() {
	v_block = UV2.x;
	v_sky = UV2.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (NORMAL.y > 0.5) {
		world.y += (sin(TIME * 1.1 + world.x * 0.6) + sin(TIME * 0.8 + world.z * 0.45)) * 0.03;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	}
	v_world = world;
}

void fragment() {
	int b = int(v_block + 0.5);
	vec2 p = v_world.xz;
	float t = TIME;
	if (b == 20) {
		float flow = n_fbm2(p * 0.35 + vec2(t * 0.05, t * 0.03));
		float crust = smoothstep(0.55, 0.75, n_fbm2(p * 0.8 - vec2(t * 0.02)));
		vec3 hot = mix(vec3(1.0, 0.3, 0.03), vec3(1.0, 0.75, 0.25), flow);
		ALBEDO = vec3(0.05);
		EMISSION = mix(hot * 4.0, vec3(0.25, 0.05, 0.02), crust);
		ROUGHNESS = ascii_roughness(0.6, ASCII_EMISSIVE);
	} else {
		float e = 0.05;
		float h = n_fbm2(p * 0.5 + vec2(t * 0.15, t * 0.1));
		float hx = n_fbm2((p + vec2(e, 0.0)) * 0.5 + vec2(t * 0.15, t * 0.1)) - h;
		float hz = n_fbm2((p + vec2(0.0, e)) * 0.5 + vec2(t * 0.15, t * 0.1)) - h;
		vec3 wn = normalize(vec3(-hx / e * 0.15, 1.0, -hz / e * 0.15));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		ALBEDO = vec3(0.03, 0.05, 0.06) * (0.6 + v_sky * 0.4);
		SPECULAR = 0.7;
		ROUGHNESS = ascii_roughness(0.05, ASCII_LIQUID);
		AO = v_sky;
		AO_LIGHT_AFFECT = 0.0;
	}
}
