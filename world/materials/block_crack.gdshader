shader_type spatial;
render_mode cull_back;
// Cracks spreading over a block being mined. Pixels that are not crack are
// discarded, so the overlay draws only dark fissures; it is opaque and tagged
// SOLID so the ASCII pass turns the fissures into glyph strokes.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

uniform float progress : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 n = abs(NORMAL);
	vec2 p = UV * 4.0;
	vec3 v = n_voronoi2(p * (1.5 + progress));
	float edge = v.y - v.x;
	float reach = length(UV - 0.5) * 1.6;
	float width = 0.04 + progress * 0.12;
	if (edge > width || reach > progress * 1.6 + 0.1) {
		discard;
	}
	ALBEDO = vec3(0.02);
	ROUGHNESS = ascii_roughness(1.0, ASCII_SOLID);
}
