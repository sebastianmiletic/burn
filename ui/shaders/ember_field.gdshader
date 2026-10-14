shader_type canvas_item;
// Menu background: ash drifting through the dark, embers rising from a fire
// glowing below the screen, all drawn as dim glyphs.

#include "res://ui/shaders/glyph_common.gdshaderinc"

uniform float intensity = 1.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	vec2 px = UV * rect_px;
	vec2 cell = floor(px / cell_px);
	vec2 local = px - cell * cell_px;
	vec2 uv = (cell + 0.5) * cell_px / rect_px;
	float aspect = rect_px.x / rect_px.y;

	// Smoke / ash fog drifting up and sideways.
	vec2 q = vec2(uv.x * aspect, uv.y);
	float fog = g_fbm(q * 3.0 + vec2(time * 0.02, time * 0.06));
	fog = g_fbm(q * 2.0 + fog * 1.5 + vec2(-time * 0.015, time * 0.04));
	float heat = pow(uv.y, 2.2);  // the fire is below the bottom edge
	float b = fog * 0.16 + heat * fog * 0.32;

	// Rising embers: sparse columns of moving points.
	float col_id = cell.x;
	float speed = 3.0 + g_hash12(vec2(col_id, 1.0)) * 7.0;
	float y = cell.y + time * speed + g_hash12(vec2(col_id, 5.0)) * 31.0;
	float slot = floor(y / 31.0);
	float lane = fract(y / 31.0);
	float alive = step(0.9, g_hash12(vec2(col_id, slot)));
	float ember = alive * step(lane, 0.035) * (0.4 + 0.6 * heat + 0.3);
	float ember_flicker = 0.6 + 0.4 * sin(time * 9.0 + col_id * 3.1);
	b = max(b, ember * ember_flicker * 0.9);

	// Vignette
	vec2 v = UV - 0.5;
	float vig = clamp(1.0 - dot(v, v) * 1.6, 0.0, 1.0);
	b *= vig * intensity;

	vec3 col = g_ember(0.15 + b * 1.1) * tint;
	float jitter = g_hash12(cell + floor(time * 2.0)) - 0.5;
	float ink = g_ink(b, local, jitter);
	vec3 base = vec3(0.012, 0.008, 0.007) + g_ember(0.2) * heat * 0.08 * intensity;
	COLOR = vec4(base + col * ink * (0.5 + b), 1.0);
}
