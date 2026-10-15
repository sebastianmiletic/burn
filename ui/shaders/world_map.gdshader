shader_type canvas_item;
// Full world map: the shared map renderer over the whole view. The view is
// mapped to world uv through `view_origin_uv` + pixel * `uv_per_px`, so zoom
// and pan are exact at every scale (no stretched textures).

#include "res://ui/shaders/map_common.gdshaderinc"

uniform vec2 view_origin_uv = vec2(0.0);  // map uv at the view's top-left
uniform vec2 view_size = vec2(1000.0);    // pixels
uniform float uv_per_px = 0.001;

void fragment() {
	vec2 uv = view_origin_uv + UV * view_size * uv_per_px;
	vec3 col = map_colour(uv);
	// Gentle vignette so markers stay the brightest thing on screen.
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.55;
	COLOR = vec4(col, 1.0);
}
