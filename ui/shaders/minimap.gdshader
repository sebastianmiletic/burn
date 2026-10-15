shader_type canvas_item;
// Circular minimap: the shared map renderer (map_common), rotated so the
// view direction points up, with a soft inner vignette. Underground it shows
// a local cave slice instead.

#include "res://ui/shaders/map_common.gdshaderinc"

uniform bool cave_mode = false;
uniform sampler2D cave_tex : filter_linear, repeat_disable;
uniform vec2 cave_offset = vec2(0.0);
uniform vec2 center_uv = vec2(0.5);   // player position in map uv
uniform float span = 0.08;            // map uv covered by the circle's diameter
uniform float angle = 0.0;            // radians, view rotation
uniform float underground = 0.0;      // dims the surface map below ground

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 rot = vec2(p.x * ca + p.y * sa, -p.x * sa + p.y * ca);
	vec3 col;
	if (cave_mode) {
		vec3 c = texture(cave_tex, vec2(0.5) + cave_offset + rot).rgb;
		col = c;
	} else {
		col = map_colour(center_uv + rot * span);
		col *= 1.0 - underground * 0.6;
	}
	// Inner shadow towards the rim, like glass over vellum.
	col *= 1.0 - smoothstep(0.7, 1.0, r) * 0.45;
	float aa = fwidth(r) * 1.5;
	COLOR = vec4(col, 1.0 - smoothstep(1.0 - aa, 1.0, r));
}
