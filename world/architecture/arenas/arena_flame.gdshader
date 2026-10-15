shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Arena flames (braziers, candles, torches, soul fire): one MultiMesh of unit
// quads (x -0.5..0.5, y 0..1) turned towards the camera around their own up
// axis. Transparent additive FX: drawn after the ASCII pass, never glyphs.
// INSTANCE_CUSTOM: rgb tint multiplier, a = phase seed.

uniform vec3 hot_color : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 cool_color : source_color = vec3(1.0, 0.32, 0.05);
uniform float intensity = 4.0;
uniform float speed = 1.0;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up = MODEL_MATRIX[1].xyz;
	float h = length(up);
	up /= max(h, 1e-4);
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	vec3 right = normalize(cross(up, to_cam));
	if (length(cross(up, to_cam)) < 1e-4) {
		right = INV_VIEW_MATRIX[0].xyz;
	}
	vec3 world = origin + right * VERTEX.x * w + up * VERTEX.y * h;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = TIME * speed + v_custom.a * 37.0;
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);   // x -1..1, y 0 (base) .. 1 (tip)
	float n1 = vnoise(vec2(uv.x * 3.0, uv.y * 4.0 - t * 3.2));
	float n2 = vnoise(vec2(uv.x * 7.0 + 3.0, uv.y * 9.0 - t * 5.1));
	float turb = n1 * 0.65 + n2 * 0.35;
	// Teardrop body that licks upwards and sways.
	float sway = (vnoise(vec2(t * 1.3, 0.5)) - 0.5) * 0.35 * uv.y;
	float x = uv.x - sway;
	float width = (1.0 - uv.y) * 0.75 * (0.6 + 0.4 * sqrt(clamp(uv.y * 4.0, 0.0, 1.0)));
	float body = 1.0 - smoothstep(width * 0.55, width * 1.05 + 0.02, abs(x) + (turb - 0.5) * 0.35 * uv.y);
	body *= 1.0 - smoothstep(0.55, 1.0, uv.y + (turb - 0.5) * 0.5);
	float core = 1.0 - smoothstep(0.0, width * 0.55, abs(x));
	core *= 1.0 - smoothstep(0.1, 0.55, uv.y + (n2 - 0.5) * 0.25);
	vec3 tint = v_custom.rgb;
	vec3 c = mix(cool_color, hot_color, clamp(core * 1.3, 0.0, 1.0)) * tint;
	float a = clamp(body, 0.0, 1.0);
	ALBEDO = c * intensity * a * (0.8 + 0.4 * turb);
	ALPHA = a;
}
