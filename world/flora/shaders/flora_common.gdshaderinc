// Shared helpers for every flora shader: weather globals, gust field, body pushers,
// per-instance distance fades and wet/snow surface response.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wetness;
global uniform float snow_cover;
global uniform sampler2D foliage_pushers;
global uniform int foliage_pusher_count;

// Normalised wind direction with a safe fallback.
vec2 fl_wind_dir() {
	float l = length(wind_dir);
	return l > 0.001 ? wind_dir / l : vec2(1.0, 0.0);
}

// Gust field: broad bands of stronger wind rolling across the land along the wind.
// Returns 0..1 (mostly 0.2..0.8, peaks in the gust fronts).
float fl_gust(vec2 p, float t) {
	vec2 wd = fl_wind_dir();
	float speed = 2.0 + wind_strength * 7.0;
	// Elongate the bands across the wind so they read as rolling fronts.
	vec2 q = vec2(dot(p, wd), dot(p, vec2(-wd.y, wd.x)) * 0.35);
	float g = n_value2(q * 0.06 - vec2(t * speed * 0.06, 0.0));
	return smoothstep(0.2, 0.85, g);
}

// Accumulated push vector (xz) from nearby bodies on foliage rooted at `root`.
// Length 0 (untouched) .. ~1.5 (flattened). Bodies more than ~1.6 m above or below are ignored.
vec2 fl_push(vec3 root) {
	vec2 push = vec2(0.0);
	int n = min(foliage_pusher_count, 16);
	for (int i = 0; i < n; i++) {
		vec4 p = texelFetch(foliage_pushers, ivec2(i, 0), 0);
		if (p.w <= 0.0) {
			continue;
		}
		vec2 d = root.xz - p.xz;
		float dist = length(d);
		float dy = root.y - p.y;
		if (dist >= p.w || dy > 0.6 || dy < -1.6) {
			continue;
		}
		float f = 1.0 - smoothstep(p.w * 0.3, p.w, dist);
		vec2 away = dist > 0.001 ? d / dist : vec2(0.7, 0.7);
		push += away * f * 1.4;
	}
	float l = length(push);
	return l > 1.5 ? push * (1.5 / l) : push;
}

// Bends a vertex (world space) of a plant rooted at `root` by the xz vector `bend`
// (radians-ish), rotating around the root so the stem keeps roughly its length.
// t: 0 at the root .. 1 at the tip (bend increases toward the tip).
vec3 fl_bend(vec3 v, vec3 root, vec2 bend, float t) {
	float a = length(bend);
	if (a < 0.0001) {
		return v;
	}
	vec2 dir = bend / a;
	float ang = a * (0.35 + 0.65 * t);
	float h = v.y - root.y;
	v.xz += dir * sin(ang) * h;
	v.y = root.y + h * cos(ang);
	return v;
}

// 0..1 screen-space dither for alpha fades (interleaved gradient noise).
float fl_dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

// Darkens and glosses a surface with the global wetness (porous surfaces darken more).
vec3 fl_wet_albedo(vec3 c, float porosity) {
	return c * (1.0 - wetness * porosity * 0.45);
}

float fl_wet_rough(float r) {
	return mix(r, r * 0.35, wetness);
}

// Snow / frost on surfaces facing up (world normal y).
vec3 fl_snow(vec3 c, float up, float amount) {
	float s = clamp(snow_cover * amount * smoothstep(0.1, 0.7, up), 0.0, 1.0);
	return mix(c, vec3(0.86, 0.89, 0.93), s);
}

// Tree wind. w: world vertex, origin: tree root (world), hm: tree height (m),
// col: vertex colour (r branch weight 0 trunk..1 twig tip, g branch phase, b leaf flutter), hsh: per-tree random.
vec3 fl_tree_sway(vec3 w, vec3 origin, float hm, vec4 col, float hsh) {
	vec2 wd = fl_wind_dir();
	vec2 side = vec2(-wd.y, wd.x);
	float tt = TIME;
	float gust = fl_gust(origin.xz, tt);
	float s = wind_strength * (0.35 + 0.65 * gust);
	float yn = clamp((w.y - origin.y) / max(hm, 0.1), 0.0, 1.3);
	float yy = yn * yn;
	// Whole tree: leans downwind with the gusts, slow pendulum around it.
	float sway = s * (0.55 + 0.45 * sin(tt * (0.55 + 0.25 * hsh) + hsh * 6.2831))
			+ 0.12 * wind_strength * sin(tt * 1.7 + hsh * 9.0);
	vec2 off = wd * sway * hm * 0.024 * yy;
	off += side * sin(tt * (0.8 + 0.2 * hsh) + hsh * 4.0) * (0.15 + s) * hm * 0.005 * yy;
	// Branches: independent sway + bob, stronger out at the tips.
	float bw = col.r;
	float bph = col.g * 6.2831 + hsh * 6.2831;
	off += (wd * sin(tt * (1.4 + col.g * 0.8) + bph) + side * 0.5 * sin(tt * (1.1 + col.g) + bph * 1.7))
			* bw * (0.025 + 0.16 * s);
	float bob = sin(tt * (1.9 + col.g * 0.7) + bph) * bw * (0.015 + 0.08 * s);
	// Leaves flutter fast and small.
	float fl = col.b * (0.008 + 0.045 * s);
	vec3 flv = vec3(sin(tt * 8.3 + bph * 3.0 + w.y * 3.1), sin(tt * 10.1 + bph * 2.0 + w.x * 2.7),
			sin(tt * 9.2 + bph + w.z * 2.9)) * fl;
	return w + vec3(off.x, bob - dot(off, off) * 0.15 * yn, off.y) + flv;
}

// Per-instance LOD band with dithered cross-fade.
// Returns visibility 0..1 for distance d in band [b, e] faded over `f` metres at both ends.
float fl_band(float d, float b, float e, float f) {
	float in_v = b <= 0.0 ? 1.0 : smoothstep(b - f * 0.5, b + f * 0.5, d);
	float out_v = 1.0 - smoothstep(e - f * 0.5, e + f * 0.5, d);
	return in_v * out_v;
}
