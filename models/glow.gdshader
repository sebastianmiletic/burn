shader_type spatial;
// Opaque glowing parts of creatures (eyes, crowns, throat fire, runes).
// Tagged EMISSIVE so the ASCII pass passes them through and the glow pass
// blooms them over the glyph grid.

#include "res://rendering/materials/ascii_material.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(1.0, 0.3, 0.1);
uniform float energy = 5.0;
uniform float pulse = 0.0;
instance uniform float intensity : instance_index(15) = 1.0;

void fragment() {
	float p = 1.0 - pulse * 0.5 + pulse * 0.5 * sin(TIME * 5.0);
	ALBEDO = vec3(0.0);
	EMISSION = glow_color * energy * intensity * p;
	ROUGHNESS = ascii_roughness(0.5, ASCII_EMISSIVE);
}
