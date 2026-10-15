// Shared map renderer (minimap and world map). Everything is resolved per
// screen pixel from filtered layers, so nothing looks blocky at any zoom:
//   color_tex   land colour with baked hillshade (MapImage)
//   height_tex  terrain height, sampled bicubically: smooth coasts, contours
//   detail_tex  R roads, G buildings at a finer scale
//   fog_tex     0 unexplored .. 1 explored (MapFog), smooth edges
// Water, lava and the Ryft's void are drawn from the height layer.

uniform sampler2D color_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D detail_tex : filter_linear, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform bool has_map = false;
uniform bool has_height = false;
uniform bool has_detail = false;
uniform bool has_fog = false;
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

// The unexplored look: overcast grey vellum with soft cloud mottling.
vec3 fog_colour(vec2 uv) {
	float n = _fbm(uv * world_size / 90.0);
	return vec3(0.255, 0.255, 0.265) + (n - 0.5) * 0.05;
}

// Full map colour at `uv` (0..1 over the world).
vec3 map_colour(vec2 uv) {
	if (!has_map) {
		return vec3(0.05, 0.045, 0.045);
	}
	vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
	vec3 col = bicubic(color_tex, cuv, vec2(textureSize(color_tex, 0))).rgb;
	vec2 wpos = uv * world_size;
	if (has_height) {
		float h = map_height(cuv);
		float fw = max(fwidth(h), 0.02);
		float depth = sea_level - h;
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
			col = mix(col, vec3(0.7, 0.64, 0.48) * (0.85 + 0.25 * dot(col, vec3(0.33))), sand * 0.85);
		}
		float wet = clamp(depth / fw + 0.5, 0.0, 1.0);
		vec3 liq;
		if (liquid == 0) {
			vec3 shallow = vec3(0.2, 0.36, 0.38);
			vec3 deep = vec3(0.055, 0.12, 0.17);
			liq = mix(shallow, deep, smoothstep(0.0, 22.0, depth));
			float ripple = _noise(wpos / 26.0 + vec2(time * 0.05, time * 0.03)) * _noise(wpos / 11.0 - vec2(time * 0.04, 0.0));
			liq += ripple * 0.025;
			// A pale line of surf hugging the shore.
			float surf = 1.0 - smoothstep(0.0, 1.4 + fw * 1.5, depth);
			liq = mix(liq, vec3(0.62, 0.7, 0.68), surf * 0.55);
		} else if (liquid == 1) {
			float flow = _fbm(wpos / 30.0 + vec2(time * 0.07, -time * 0.05));
			liq = mix(vec3(0.55, 0.12, 0.03), vec3(1.0, 0.55, 0.15), smoothstep(0.35, 0.8, flow));
			liq = mix(liq, vec3(0.25, 0.06, 0.03), smoothstep(2.0, 18.0, depth) * 0.5);
		} else {
			float stars = step(0.996, _hash(floor(wpos / 6.0)));
			liq = vec3(0.04, 0.03, 0.07) + vec3(0.5, 0.45, 0.8) * stars * 0.5 + vec3(0.12, 0.07, 0.2) * _fbm(wpos / 120.0);
		}
		col = mix(col, liq, wet);
	}
	if (has_detail) {
		vec2 d = texture(detail_tex, cuv).rg;
		float casing = smoothstep(0.06, 0.28, d.r);
		float road = smoothstep(0.28, 0.6, d.r);
		col = mix(col, col * 0.62, casing * 0.7);
		col = mix(col, vec3(0.78, 0.69, 0.52), road * 0.9);
		float roof_edge = smoothstep(0.08, 0.35, d.g);
		float roof = smoothstep(0.38, 0.62, d.g);
		col = mix(col, vec3(0.16, 0.12, 0.1), roof_edge * 0.75);
		col = mix(col, vec3(0.66, 0.5, 0.38), roof);
	}
	if (has_fog) {
		float f = texture(fog_tex, cuv).r;
		float seen = smoothstep(0.1, 0.62, f);
		float edge = seen * (1.0 - seen) * 4.0;
		col *= 1.0 - edge * 0.18;
		col = mix(fog_colour(uv), col, seen);
	}
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		col = has_fog ? fog_colour(uv) * 0.7 : vec3(0.04, 0.035, 0.035);
	}
	return col;
}
