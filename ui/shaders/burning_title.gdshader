shader_type canvas_item;
// "BURN" burning into existence, drawn as glyphs: embers smoulder where the
// letters will be, a dissolve front sweeps up with a white-hot edge, flames
// lick off the tops of the letters and sparks rise.

#include "res://ui/shaders/glyph_common.gdshaderinc"

uniform sampler2D mask : filter_linear;   // white letters on black, fills the rect
uniform float progress = 1.0;             // 0 = nothing, 1 = fully burnt in
uniform float flames = 1.0;               // flame intensity once revealed
uniform float fade = 1.0;                 // overall opacity

float mask_at(vec2 uv) {
	return texture(mask, clamp(uv, vec2(0.0), vec2(1.0))).r;
}

void fragment() {
	vec2 px = UV * rect_px;
	vec2 cell = floor(px / cell_px);
	vec2 local = px - cell * cell_px;
	vec2 cuv = (cell + 0.5) * cell_px / rect_px;
	vec2 cstep = cell_px / rect_px;

	float m = mask_at(cuv);
	// Soft halo around the letters.
	float halo = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785;
		halo += mask_at(cuv + vec2(cos(a), sin(a)) * cstep * 2.5);
	}
	halo /= 8.0;

	// Burn front: noise-shaped, travelling from the bottom up.
	float n = g_fbm(cell * vec2(0.09, 0.14) + 7.0) * 0.75 + (1.0 - cuv.y) * 0.45;
	float thr = progress * 1.45 - 0.15;
	float revealed = step(n, thr);
	float edge = 1.0 - smoothstep(0.0, 0.14, abs(n - thr));
	edge *= step(0.001, progress) * step(progress, 0.999);

	float flicker = g_noise(vec2(cell.x * 0.37, time * 6.0)) * 0.35 + 0.65;
	float b = 0.0;
	vec3 col = vec3(0.0);

	// The letters: cooling embers inside, hot at the burn front.
	if (m > 0.35) {
		float inner = mix(0.08 + 0.1 * g_hash12(cell + floor(time * 3.0)), 0.62 + 0.18 * flicker, revealed);
		float heat = max(inner, edge * 1.05);
		b = max(b, heat);
		col = g_ember(heat * 0.9 + edge * 0.25);
		col = mix(col, vec3(1.0, 0.95, 0.85), edge * 0.7);
	}

	// Flames lick upward from the revealed letter tops.
	float flame = 0.0;
	float wobble = (g_noise(vec2(cell.y * 0.4 - time * 3.0, cell.x * 0.2)) - 0.5) * 2.0;
	for (int k = 1; k <= 7; k++) {
		vec2 below = cuv + vec2(wobble * cstep.x * 0.8, float(k) * cstep.y);
		float src = step(0.35, mask_at(below)) * (1.0 - step(0.35, m));
		float reach = 1.0 - float(k) / 8.0;
		float tongue = g_noise(vec2(cell.x * 0.45, cell.y * 0.25 + time * 4.0));
		flame = max(flame, src * reach * smoothstep(0.25, 0.75, tongue + reach * 0.4));
	}
	flame *= flames * clamp(progress * 1.6 - 0.4, 0.0, 1.0) * flicker;
	if (flame > b) {
		b = flame * 0.85;
		col = g_ember(0.35 + flame * 0.6);
	}

	// Halo glow and rising sparks.
	float glow = halo * (1.0 - step(0.35, m)) * 0.35 * clamp(progress * 2.0, 0.0, 1.0);
	float spark_col = floor(cell.x);
	float speed = 4.0 + g_hash12(vec2(spark_col, 3.0)) * 6.0;
	float lane = fract((cell.y + time * speed) / 23.0 + g_hash12(vec2(spark_col, 9.0)));
	float spark = step(0.965, g_hash12(vec2(spark_col, floor((cell.y + time * speed) / 23.0)))) * step(lane, 0.06);
	spark *= smoothstep(0.0, 0.3, halo + flame) + step(0.97, g_hash12(cell)) * 0.0;
	spark *= clamp(progress * 3.0, 0.0, 1.0);
	if (spark > 0.0 && b < 0.5) {
		b = 0.75;
		col = vec3(1.0, 0.78, 0.4);
	}
	if (glow > b) {
		b = glow;
		col = g_ember(0.3);
	}

	float jitter = g_hash12(cell + floor(time * 8.0)) - 0.5;
	float ink = g_ink(b, local, jitter * step(b, 0.5));
	vec3 bg = col * b * 0.18;
	COLOR = vec4(col * (0.35 + b) * ink + bg, clamp(ink * smoothstep(0.02, 0.12, b) + b * 0.25, 0.0, 1.0) * fade);
}
