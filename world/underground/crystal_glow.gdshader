shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Luminous crystal (Hearthold's Heartcrystal, lamp crystals, the Everbloom's fruit and sap):
// a dark glassy body that glows from within. COLOR.rgb is the glow colour, COLOR.a its
// strength; `energy` scales all of it (faded by gameplay, e.g. the dying tree).

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform float energy = 2.4;
uniform float pulse = 0.12;
uniform vec3 body_color : source_color = vec3(0.08, 0.05, 0.04);

varying vec3 v_world;
varying vec4 v_col;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.2);
	// Veils and inclusions drifting slowly inside the stone.
	float veil = n_fbm3(v_world * 0.35 + vec3(0.0, TIME * 0.04, 0.0));
	float spark = smoothstep(0.82, 0.95, n_value3(v_world * 3.1 + TIME * 0.2));
	float beat = 1.0 + pulse * sin(TIME * 1.3 + v_world.y * 0.15);
	float core = 0.55 + 0.6 * veil + 0.8 * fres;
	ALBEDO = body_color * (0.6 + veil * 0.5);
	ROUGHNESS = ascii_roughness(0.08, ASCII_EMISSIVE);
	SPECULAR = 0.9;
	METALLIC = 0.0;
	EMISSION = v_col.rgb * v_col.a * energy * beat * (core + spark * 1.5);
}
