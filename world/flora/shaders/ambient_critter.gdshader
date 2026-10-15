shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;
// Tiny opaque ambient life (alpha-tested so the ASCII pass sees FOLIAGE):
//   mode 0  butterflies: two flapping wings, fluttering flight around a home on the ground
//           (instance origin = home, INSTANCE_CUSTOM.rgb wing colour, .a phase)
//   mode 1  falling leaves: drop from a tree crown, drift with the wind, tumble, loop
//           (instance origin = crown centre, CUSTOM.r crown radius, .g fall height, .b hue, .a phase)
//   mode 2  swirling leaves: skitter and loop along the ground with gusts
//           (instance origin = start point on the ground, CUSTOM.b hue, .a phase)
// The mesh is a quad (or two wing quads) in the XZ plane, UV 0..1; UV2.x = -1 left wing, +1 right.

#include "res://world/flora/shaders/flora_common.gdshaderinc"

uniform int mode = 0;
uniform float size = 0.07;
uniform float visible_amount = 1.0;   // 0 hides (night, rain, calm air)

varying vec3 v_col;
varying float v_kill;

vec3 hash3(float n) {
	return fract(sin(vec3(n, n + 17.13, n + 41.7)) * vec3(43758.5453, 22578.1459, 19642.3490));
}

mat3 rot_y(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

mat3 rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

vec3 leaf_color(float h) {
	vec3 a = vec3(0.86, 0.42, 0.1);
	vec3 b = vec3(0.65, 0.18, 0.07);
	vec3 c = vec3(0.92, 0.66, 0.2);
	vec3 d = vec3(0.6, 0.08, 0.05);
	return h < 0.3 ? mix(a, c, h / 0.3) : (h < 0.6 ? mix(c, b, (h - 0.3) / 0.3) : mix(b, d, (h - 0.6) / 0.4));
}

vec3 butterfly_path(vec3 home, float ph, float t) {
	return home + vec3(sin(t * 0.43 + ph * 6.28) * 2.2 + sin(t * 1.3 + ph) * 0.4,
			0.55 + 0.35 * sin(t * 1.1 + ph * 3.0) + 0.12 * sin(t * 6.0 + ph * 9.0),
			sin(t * 0.31 + ph * 12.0) * 2.2 + cos(t * 1.7 + ph * 2.0) * 0.4);
}

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = cu.a;
	vec3 local = VERTEX;
	vec3 world;
	v_kill = 0.0;
	vec2 wd = fl_wind_dir();
	if (mode == 0) {
		float t = TIME + ph * 100.0;
		vec3 p = butterfly_path(origin, ph, t);
		vec3 q = butterfly_path(origin, ph, t + 0.05);
		vec3 fwd = q - p;
		float yaw = atan(fwd.x, fwd.z);
		// Wings hinge on the body (x = 0): flap fast, glide now and then.
		float glide = smoothstep(0.6, 0.9, sin(t * 0.7 + ph * 5.0));
		float flap = mix(sin(t * 17.0 + ph * 20.0) * 1.0 + 0.35, 0.25, glide);
		float side = UV2.x;
		float r = abs(local.x);
		local = vec3(side * r * cos(flap), r * sin(flap), local.z);
		world = p + rot_y(yaw) * (local * size);
		v_col = cu.rgb;
	} else if (mode == 1) {
		float period = 6.0 + ph * 4.0;
		float cyc = TIME / period + ph * 13.0;
		float u = fract(cyc);
		vec3 h = hash3(floor(cyc) + ph * 91.0);
		float radius = cu.r;
		float fall = cu.g;
		vec2 off = (h.xy - 0.5) * 2.0 * radius * 0.8;
		vec3 start = origin + vec3(off.x, (h.z - 0.3) * radius * 0.5, off.y);
		vec2 side = vec2(-wd.y, wd.x);
		float drift = u * fall * (0.25 + wind_strength * 1.2);
		vec3 p = start + vec3(wd.x * drift, -u * fall, wd.y * drift)
				+ vec3(side.x, 0.0, side.y) * sin(u * 11.0 + ph * 7.0) * 0.45 * (0.5 + h.x);
		float tum = TIME * (1.6 + h.y * 2.0) + ph * 20.0;
		mat3 r = rot_y(tum) * rot_x(sin(tum * 0.7) * 1.3 + 0.4);
		float s = smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.93, 1.0, u));
		world = p + r * (local * size * s);
		v_col = leaf_color(fract(cu.b + h.z * 0.3));
		if (s <= 0.0) {
			v_kill = 1.0;
		}
	} else {
		float period = 4.0 + ph * 3.0;
		float cyc = TIME / period + ph * 7.0;
		float u = fract(cyc);
		vec3 h = hash3(floor(cyc) + ph * 57.0);
		float gust = fl_gust(origin.xz, TIME);
		float w = smoothstep(0.2, 0.6, wind_strength) * (0.4 + gust);
		vec2 side = vec2(-wd.y, wd.x);
		float run = u * (3.0 + h.x * 4.0) * w;
		float loop_r = 0.5 + h.y * 0.6;
		vec3 p = origin + vec3(wd.x * run, 0.05, wd.y * run)
				+ vec3(side.x, 0.0, side.y) * sin(u * 12.0 + h.z * 6.0) * loop_r * w
				+ vec3(0.0, abs(sin(u * 6.28 * (1.0 + h.z))) * (0.4 + h.y * 1.2) * w, 0.0);
		float tum = TIME * (3.0 + h.y * 3.0) + ph * 20.0;
		mat3 r = rot_y(tum) * rot_x(sin(tum * 0.9) * 1.4);
		float s = smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.9, 1.0, u)) * step(0.05, w);
		world = p + r * (local * size * s);
		v_col = leaf_color(fract(cu.b + h.z * 0.4));
		if (s <= 0.0) {
			v_kill = 1.0;
		}
	}
	if (visible_amount < fract(ph * 7.31) + 0.001) {
		v_kill = 1.0;
	}
	if (v_kill > 0.5) {
		world = CAMERA_POSITION_WORLD - vec3(0.0, 1000.0, 0.0);
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = v_col;
	if (mode == 0) {
		// Wing: forewing + hindwing lobes, dark veins and margin with pale spots.
		float x = uv.x;              // 0 at the body .. 1 at the wing tip
		float y = uv.y * 2.0 - 1.0;  // -1 rear .. 1 front
		float fore = length(vec2((x - 0.45) / 0.55, (y - 0.3) / 0.62));
		float hind = length(vec2((x - 0.3) / 0.38, (y + 0.45) / 0.5));
		float d = min(fore, hind);
		if (d > 1.0) {
			discard;
		}
		float margin = smoothstep(0.72, 0.85, d);
		col = mix(col, vec3(0.05, 0.04, 0.04), margin);
		float spot = step(fract(x * 6.0 + y * 3.0), 0.12) * margin;
		col = mix(col, vec3(0.95), spot * 0.8);
		col *= 0.85 + 0.15 * sin(x * 30.0);
		if (x < 0.05) {
			col = vec3(0.06, 0.05, 0.04);
		}
	} else {
		// Single leaf outline (oak-ish lobes) with a midrib.
		float y = uv.y;
		float x = abs(uv.x - 0.5) * 2.0;
		float w = pow(sin(3.14159 * clamp(y, 0.0, 1.0)), 0.7) * (0.75 + 0.25 * abs(sin(y * 14.0)));
		if (x > w || y < 0.02) {
			discard;
		}
		col *= 0.85 + 0.2 * (1.0 - x) - 0.15 * y;
		col = mix(col, col * 1.3, 1.0 - smoothstep(0.0, 0.08, x));
	}
	ALBEDO = col;
	BACKLIGHT = col * 0.5;
	ROUGHNESS = ascii_roughness(0.6, ASCII_FOLIAGE);
}
