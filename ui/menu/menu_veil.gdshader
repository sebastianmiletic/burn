shader_type canvas_item;
// Drawn over the live menu world, under the menu text: a soft dark band down
// the middle so the title and options read over any shot, a vignette and a
// letterbox gradient, and a few embers drifting up as glyphs.

#include "res://ui/shaders/glyph_common.gdshaderinc"

uniform float strength = 1.0;      // 0 = no veil (nothing behind to calm down)
uniform float band_width = 0.36;   // half-width of the central band, in screen heights
uniform float band_dark = 0.58;
uniform float edge_dark = 0.72;
uniform float embers = 1.0;
uniform float band_extra = 0.0;    // extra darkening while a panel is open
uniform vec4 title_rect = vec4(0.5, 0.25, 0.3, 0.1);  // centre xy, half size xy (UV) of a soft pool behind the title
uniform float title_dark = 0.45;

void fragment() {
	vec2 px = UV * rect_px;
	vec2 cell = floor(px / cell_px);
	vec2 local = px - cell * cell_px;
	vec2 uv = UV;
	float aspect = rect_px.x / max(rect_px.y, 1.0);

	vec2 v = (uv - 0.5) * vec2(aspect, 1.0);
	float vig = smoothstep(0.32, 1.1, length(v * vec2(0.8, 1.0)));
	float bx = (uv.x - 0.5) * aspect / band_width;
	float band = exp(-bx * bx * 1.6) * smoothstep(1.05, 0.15, uv.y);
	float bottom = smoothstep(0.62, 1.0, uv.y);
	float top = smoothstep(0.18, 0.0, uv.y);
	vec2 tq = (uv - title_rect.xy) / max(title_rect.zw, vec2(0.001));
	float pool = exp(-dot(tq, tq) * 1.4);
	float a = vig * edge_dark + band * (band_dark + band_extra) + bottom * 0.55 + top * 0.35 + pool * title_dark;
	a = clamp(a, 0.0, 0.94) * strength;
	vec3 dark = vec3(0.012, 0.007, 0.005);

	// Embers rising from below, sparse, in their own glyph columns.
	vec2 cuv = (cell + 0.5) * cell_px / rect_px;
	float speed = 2.5 + g_hash12(vec2(cell.x, 1.0)) * 5.0;
	float y = cell.y + time * speed + g_hash12(vec2(cell.x, 5.0)) * 47.0;
	float slot = floor(y / 47.0);
	float lane = fract(y / 47.0);
	float alive = step(0.93, g_hash12(vec2(cell.x, slot)));
	float rise = pow(cuv.y, 1.6);
	float e = alive * step(lane, 0.03) * rise * embers;
	e *= 0.6 + 0.4 * sin(time * 8.0 + cell.x * 2.7);
	float ink = g_ink(e, local, 0.0);
	vec3 ember_col = g_ember(0.55 + e * 0.4);
	float ea = ink * e * strength;
	COLOR = vec4(mix(dark, ember_col, ea / max(a + ea, 0.001)), clamp(a + ea, 0.0, 1.0));
}
