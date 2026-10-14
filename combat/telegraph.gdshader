shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Ground warning for a heavy attack. Drawn on the FX layer (additive, never
// turned into glyphs) as a dotted outline of glyph-sized marks plus a fill
// that sweeps outwards; when the fill completes the attack lands.

uniform int shape = 0;          // 0 circle, 1 cone, 2 line, 3 ring
uniform vec2 size = vec2(4.0, 30.0);
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.28, 0.05);

varying vec2 v_p;

void vertex() {
	v_p = VERTEX.xz;
}

void fragment() {
	vec2 p = v_p;
	float r = length(p);
	bool inside = false;
	float norm = 0.0;
	float edge = 0.0;
	if (shape == 0) {
		inside = r <= size.x;
		norm = r / size.x;
		edge = size.x - r;
	} else if (shape == 3) {
		inside = r >= size.x && r <= size.y;
		norm = (r - size.x) / max(size.y - size.x, 0.01);
		edge = min(r - size.x, size.y - r);
	} else if (shape == 1) {
		float ang = degrees(abs(atan(p.x, -p.y)));
		inside = r <= size.x && ang <= size.y;
		norm = r / size.x;
		edge = min(size.x - r, radians(size.y - ang) * r);
	} else {
		float along = -p.y;
		inside = along >= 0.0 && along <= size.x && abs(p.x) <= size.y * 0.5;
		norm = along / size.x;
		edge = min(min(along, size.x - along), size.y * 0.5 - abs(p.x));
	}
	if (!inside) {
		discard;
	}
	// Glyph-sized dots on a half-metre grid.
	vec2 cell = fract(p * 2.0) - 0.5;
	float dot_mark = 1.0 - smoothstep(0.12, 0.2, length(cell));
	float outline = (1.0 - smoothstep(0.25, 0.6, edge)) * dot_mark;
	float filled = step(norm, fill);
	float front = (1.0 - smoothstep(0.0, 0.06, abs(norm - fill))) * step(0.001, fill);
	float body = filled * (0.12 + dot_mark * 0.35);
	float intensity = outline * 0.9 + body + front * 0.9 + flash * (0.6 + dot_mark);
	vec3 c = mix(color, vec3(1.0, 0.85, 0.5), flash * 0.6 + front * 0.4);
	ALBEDO = c * intensity * alpha * 2.2;
	ALPHA = clamp(intensity * alpha, 0.0, 1.0);
}
