// Shared map renderer (minimap and world map). Everything is resolved per
// screen pixel from filtered layers, so nothing looks blocky at any zoom:
//   color_tex   land colour with baked hillshade (MapImage)
//   height_tex  terrain height, sampled bicubically: smooth coasts, contours
//   detail_tex  R roads, G buildings at a finer scale
//   fog_tex     0 unexplored .. 1 explored (MapFog), smooth edges
//   edge_tex    land biome borders (MapImage "biome_edge")
// Water, lava and the Ryft's void are drawn from the height layer.
// Explored ground is a toned cartographic map: biome tints with baked
// relief, inked coastlines, engraved waterlines off the shore, dotted biome
// borders and paper grain. Unexplored ground keeps only the shape of the
// land: a grey relief silhouette with a grey coastline over grey water.
// Beyond the charted square the sheet never ends: a faint survey grid on
// dark sea-slate runs on forever (chart_void), so panning or zooming out
// never shows a black border.

uniform sampler2D color_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D detail_tex : filter_linear, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool has_map = false;
uniform bool has_height = false;
uniform bool has_detail = false;
uniform bool has_fog = false;
uniform sampler2D edge_tex : filter_linear, repeat_disable;
uniform bool has_edges = false;
uniform vec2 height_size = vec2(768.0);
uniform float world_size = 3072.0;
uniform float sea_level = 12.0;
uniform int liquid = 0;            // 0 water, 1 lava, 2 void
uniform float contour_strength = 0.0;
uniform float time = 0.0;

vec4 _cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

// Cubic B-spline sample of a texture from four bilinear taps: smooth curves
// instead of texel stair-steps when magnified.
vec4 bicubic(sampler2D tex, vec2 uv, vec2 tsize) {
	vec2 st = uv * tsize - 0.5;
	vec2 f = fract(st);
	st -= f;
	vec4 xc = _cubic(f.x);
	vec4 yc = _cubic(f.y);
	vec4 c = st.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) / tsize.xxyy;
	vec4 s0 = texture(tex, o.xz);
	vec4 s1 = texture(tex, o.yz);
	vec4 s2 = texture(tex, o.xw);
	vec4 s3 = texture(tex, o.yw);
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

// Cubic B-spline height from four bilinear taps.
float map_height(vec2 uv) {
	vec2 st = uv * height_size - 0.5;
	vec2 f = fract(st);
	st -= f;
	vec4 xc = _cubic(f.x);
	vec4 yc = _cubic(f.y);
	vec4 c = st.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) / height_size.xxyy;
	float s0 = texture(height_tex, o.xz).r;
	float s1 = texture(height_tex, o.yz).r;
	float s2 = texture(height_tex, o.xw).r;
	float s3 = texture(height_tex, o.yw).r;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_hash(i), _hash(i + vec2(1, 0)), f.x), mix(_hash(i + vec2(0, 1)), _hash(i + vec2(1, 1)), f.x), f.y);
}

float _fbm(vec2 p) {
	return _noise(p) * 0.55 + _noise(p * 2.1 + 3.7) * 0.3 + _noise(p * 4.3 + 9.1) * 0.15;
}

const vec3 INK = vec3(0.13, 0.1, 0.075);

// Relief from the height layer alone (the unexplored silhouette): light from
// the north-west, as on the baked colour layer.
float relief(vec2 uv, float h) {
	vec2 t = 1.0 / height_size;
	float hx = map_height(uv + vec2(t.x, 0.0)) - h;
	float hz = map_height(uv + vec2(0.0, t.y)) - h;
	float mpt = world_size / height_size.x;
	return clamp(1.0 + (hx + hz) / mpt * 0.55, 0.72, 1.22);
}

// Engraved lines following the shore out to sea, fading with depth.
float waterlines(float depth, float fw) {
	float l = 0.0;
	l += (1.0 - smoothstep(0.35, 1.25, abs(depth - 1.4) / fw)) * 0.55;
	l += (1.0 - smoothstep(0.35, 1.25, abs(depth - 3.6) / fw)) * 0.36;
	l += (1.0 - smoothstep(0.35, 1.25, abs(depth - 7.0) / fw)) * 0.2;
	return l * step(0.0, depth);
}

// What an unexplored place looks like: only the shape of the land.
vec3 unexplored_colour(vec2 uv, float h, float depth, float fw, float grain) {
	vec2 wpos = uv * world_size;
	float wet = clamp(depth / fw + 0.5, 0.0, 1.0);
	float shade = has_height ? relief(clamp(uv, vec2(0.0), vec2(1.0)), h) : 1.0;
	vec3 land = vec3(0.35, 0.34, 0.325) * shade;
	vec3 sea = mix(vec3(0.2, 0.205, 0.215), vec3(0.15, 0.155, 0.165), smoothstep(0.0, 26.0, depth));
	sea += vec3(0.07) * waterlines(depth, fw);
	vec3 col = mix(land, sea, wet);
	float coast = 1.0 - smoothstep(0.5, 1.5, abs(depth) / fw);
	col = mix(col, vec3(0.11, 0.11, 0.115), coast * 0.8);
	col *= 0.93 + grain * 0.1 + (_fbm(wpos / 140.0) - 0.5) * 0.06;
	return col;
}

vec3 explored_colour(vec2 uv, float h, float depth, float fw, float grain) {
	vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 wpos = uv * world_size;
	vec3 col = bicubic(color_tex, cuv, vec2(textureSize(color_tex, 0))).rgb;
	// A touch of parchment in every tint, so the palette reads as one map.
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(0.62, 0.55, 0.4) * lum * 1.6, 0.14);
	if (has_height) {
		// Contours every 10 m, anti-aliased against the screen.
		if (contour_strength > 0.0) {
			float d = abs(fract(h / 10.0 + 0.5) - 0.5) * 10.0;
			float line = 1.0 - smoothstep(0.35, 1.2, d / fw);
			float major = mod(floor(h / 10.0 + 0.5), 5.0) < 0.5 ? 1.7 : 1.0;
			col *= 1.0 - line * contour_strength * major * smoothstep(-1.0, 1.0, -depth);
		}
		// Beaches: a smooth sand band just above the waterline.
		if (liquid == 0) {
			float sand = 1.0 - smoothstep(0.3, 1.7, -depth);
			col = mix(col, vec3(0.72, 0.65, 0.48) * (0.85 + 0.25 * dot(col, vec3(0.33))), sand * 0.85);
		}
	}
	// Land biome borders: a fine dotted brown line.
	if (has_edges) {
		float e = bicubic(edge_tex, cuv, vec2(textureSize(edge_tex, 0))).r;
		float line = smoothstep(0.32, 0.6, e) * (1.0 - smoothstep(-0.5, 0.5, depth));
		float dots = 0.55 + 0.45 * step(0.5, fract((wpos.x + wpos.y * 0.7) / 9.0));
		col = mix(col, INK * 1.4, line * 0.42 * dots);
	}
	if (has_detail) {
		vec2 d = texture(detail_tex, cuv).rg;
		float casing = smoothstep(0.06, 0.28, d.r);
		float road = smoothstep(0.28, 0.6, d.r);
		col = mix(col, col * 0.62, casing * 0.7);
		col = mix(col, vec3(0.8, 0.71, 0.54), road * 0.9);
		float roof_edge = smoothstep(0.08, 0.35, d.g);
		float roof = smoothstep(0.38, 0.62, d.g);
		col = mix(col, vec3(0.16, 0.12, 0.1), roof_edge * 0.75);
		col = mix(col, vec3(0.66, 0.5, 0.38), roof);
	}
	col *= 0.94 + grain * 0.1;
	if (has_height) {
		float wet = clamp(depth / fw + 0.5, 0.0, 1.0);
		vec3 liq;
		if (liquid == 0) {
			vec3 shallow = vec3(0.24, 0.4, 0.41);
			vec3 deep = vec3(0.07, 0.15, 0.2);
			liq = mix(shallow, deep, smoothstep(0.0, 24.0, depth));
			// Each sea's bed shows through faintly (reefs, kelp, the trench).
			liq = mix(liq, col * 0.8, 0.12 * (1.0 - smoothstep(4.0, 30.0, depth)));
			float ripple = _noise(wpos / 26.0 + vec2(time * 0.05, time * 0.03)) * _noise(wpos / 11.0 - vec2(time * 0.04, 0.0));
			liq += ripple * 0.025;
			liq = mix(liq, vec3(0.7, 0.78, 0.74), waterlines(depth, fw) * 0.42);
			liq *= 0.96 + grain * 0.06;
		} else if (liquid == 1) {
			float flow = _fbm(wpos / 30.0 + vec2(time * 0.07, -time * 0.05));
			liq = mix(vec3(0.55, 0.12, 0.03), vec3(1.0, 0.55, 0.15), smoothstep(0.35, 0.8, flow));
			liq = mix(liq, vec3(0.25, 0.06, 0.03), smoothstep(2.0, 18.0, depth) * 0.5);
		} else {
			float stars = step(0.996, _hash(floor(wpos / 6.0)));
			liq = vec3(0.04, 0.03, 0.07) + vec3(0.5, 0.45, 0.8) * stars * 0.5 + vec3(0.12, 0.07, 0.2) * _fbm(wpos / 120.0);
		}
		col = mix(col, liq, wet);
		// The inked coastline.
		float coast = 1.0 - smoothstep(0.45, 1.45, abs(depth) / fw);
		col = mix(col, liquid == 1 ? vec3(0.2, 0.05, 0.02) : INK, coast * 0.82);
	}
	return col;
}

const vec3 VOID_SEA = vec3(0.1, 0.113, 0.124);

// Off the chart: dark sea-slate with an endless survey grid. The major lines
// fall on the atlas squares (world_size / 12) and split by four as you zoom
// in; each level fades in and out smoothly, so lines stay 14..220 px apart
// at any zoom. `mpp` is metres per screen pixel.
vec3 chart_void(vec2 wpos, float mpp, float grain) {
	vec3 col = VOID_SEA * (0.95 + grain * 0.08) + (_fbm(wpos / 300.0) - 0.5) * 0.018;
	float cell = world_size / 12.0;
	float lvl = log(mpp * 56.0 / cell) / log(4.0);
	float l0 = floor(lvl);
	float f = lvl - l0;
	float ink = 0.0;
	for (int i = 0; i < 3; i++) {
		float s = cell * pow(4.0, l0 + float(i));
		vec2 g = abs(fract(wpos / s + 0.5) - 0.5) * s / mpp;
		float line = 1.0 - smoothstep(0.2, 1.05, min(g.x, g.y));
		ink = max(ink, line * clamp(0.5 + 0.5 * (float(i) - f), 0.0, 1.0));
	}
	return mix(col, vec3(0.66, 0.6, 0.47), ink * 0.2);
}

// Full map colour at `uv` (0..1 over the world).
vec3 map_colour(vec2 uv) {
	vec2 wpos = uv * world_size;
	vec2 dw = fwidth(wpos);
	float mpp = max(max(dw.x, dw.y), 1e-4);
	if (!has_map) {
		return chart_void(wpos, mpp, _noise(wpos / 2.2));
	}
	vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
	float h = has_height ? map_height(cuv) : sea_level + 20.0;
	float fw = max(fwidth(h), 0.02);
	float depth = sea_level - h;
	float grain = _noise(wpos / 2.2) * 0.5 + _noise(wpos / 7.5 + 3.1) * 0.5;
	float seen = 1.0;
	if (has_fog) {
		// A ragged, hand-drawn edge to the known world.
		float f = texture(fog_tex, cuv).r;
		seen = smoothstep(0.3, 0.55, f + (_fbm(wpos / 34.0) - 0.5) * 0.3);
	}
	vec3 col = vec3(0.0);
	if (seen > 0.0) {
		col = explored_colour(uv, h, depth, fw, grain);
	}
	if (seen < 1.0) {
		col = mix(unexplored_colour(uv, h, depth, fw, grain), col, seen);
		// Burnt-paper rim where the known world ends.
		float rim = seen * (1.0 - seen) * 4.0;
		col = mix(col, vec3(0.09, 0.07, 0.05), rim * 0.35);
	}
	// The charted square fades into the endless grid over a short band
	// (signed distance to the square's edge, metres; negative inside).
	vec2 outside = max(max(-uv, uv - 1.0), vec2(0.0)) * world_size;
	float inside = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)) * world_size;
	float sd = inside > 0.0 ? -inside : length(outside);
	float band = max(60.0, mpp * 26.0);
	float off_chart = smoothstep(-band * 0.35, band, sd);
	if (off_chart > 0.0) {
		col = mix(col, chart_void(wpos, mpp, grain), off_chart);
	}
	return col;
}
