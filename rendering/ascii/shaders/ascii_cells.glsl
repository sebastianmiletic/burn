#[compute]
#version 450

// Pass 4/5: one invocation per screen cell.
// Gathers the cell's pixels and decides what it shows:
//   - which material dominates (per-material glyph style)
//   - whether enough pixels agree on an edge direction (directional glyph)
//   - whether rain streaks cross it (slanted stroke following the streak)
//   - whether it is an emissive surface (passed through untouched)
// Writes the glyph index + flags and the tinted glyph colour.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D lummat_image;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D gbuf_image;
layout(r16f, set = 0, binding = 3) uniform restrict readonly image2D dir_image;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D cell_color_image; // fg (exposed, linear), glyph index
layout(rgba16f, set = 0, binding = 5) uniform restrict writeonly image2D cell_aux_image;   // mode, material, edge dir, brightness
layout(set = 0, binding = 6, std430) restrict readonly buffer GlyphTable {
	int data[];
} tbl;
layout(rg16f, set = 0, binding = 7) uniform restrict writeonly image2D cell_lum_image;
layout(set = 0, binding = 8, std430) restrict readonly buffer Exposure {
	float adapted_log;
	float initialised;
} ex;

layout(push_constant, std430) uniform Params {
	vec4 p0; // width, height, cell w, cell h (internal pixels, fractional)
	vec4 p1; // cols, rows, time, flags
	vec4 p2; // exposure, gamma, edge fraction, saturation
	vec4 p3; // contrast, glyph gain, flicker, liquid speed
	vec4 p4; // wind slant (-1..1), star threshold, adaptation strength, key
} pc;

const int M_SOLID = 0;
const int M_FOLIAGE = 1;
const int M_LIQUID = 2;
const int M_STREAK = 3;
const int M_GROUND = 4;
const int M_EMISSIVE = 5;
const int M_CLOTH = 6;
const int M_DEFAULT = 7;
const int M_SKY = 8;

const int R_SOLID = 0;
const int R_GROUND = 1;
const int R_FOLIAGE = 2;
const int R_LIQUID = 3;
const int R_SKY = 4;
const int R_CLASSIC = 5;
const int R_EDGES = 6;
const int R_RAIN = 7;
const int R_LEAF = 8;

// FOLIAGE ramp is fixed: " .,'|/\;:"
const int F_SPACE = 0, F_DOT = 1, F_COMMA = 2, F_TICK = 3, F_BAR = 4, F_SLASH = 5, F_BACK = 6, F_SEMI = 7, F_COLON = 8;

const uint FLAG_EDGES = 1u;
const uint FLAG_CLASSIC = 2u;
const uint FLAG_DITHER = 4u;
const uint FLAG_FLICKER = 8u;
const uint FLAG_RAIN = 16u;

const uint MODE_GLYPH = 0u;
const uint MODE_PASS = 1u;
const uint MODE_RAIN = 2u;
const uint MODE_EDGE = 3u;

int ramp_len(int r) {
	return tbl.data[r * 2 + 1];
}

int ramp_glyph(int r, int i) {
	return tbl.data[18 + tbl.data[r * 2] + clamp(i, 0, ramp_len(r) - 1)];
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bayer4(ivec2 c) {
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[(c.y & 3) * 4 + (c.x & 3)] + 0.5) / 16.0;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
	int cols = int(pc.p1.x);
	int rows = int(pc.p1.y);
	if (cell.x >= cols || cell.y >= rows) {
		return;
	}

	ivec2 size = ivec2(pc.p0.xy);
	vec2 cszf = pc.p0.zw;
	ivec2 origin = ivec2(floor(vec2(cell) * cszf));
	ivec2 cend = max(ivec2(floor(vec2(cell + 1) * cszf)), origin + 1);
	cend = min(cend, size);
	ivec2 csz = max(cend - origin, ivec2(1));
	ivec2 stp = max(ivec2(1), csz / ivec2(8, 12));
	uint flags = uint(pc.p1.w + 0.5);
	float time = pc.p1.z;

	float counts[9] = float[9](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	vec3 col_sum = vec3(0.0);
	float n = 0.0;
	float lum_max = 0.0;
	vec4 votes = vec4(0.0);
	float edge_y = 0.0;
	float edge_n = 0.0;

	// Rain streak moments, in pixels relative to the cell origin.
	float sn = 0.0;
	vec2 s1 = vec2(0.0);
	vec3 s2 = vec3(0.0);
	vec3 scol = vec3(0.0);

	for (int y = 0; y < csz.y; y += stp.y) {
		for (int x = 0; x < csz.x; x += stp.x) {
			ivec2 p = origin + ivec2(x, y);
			vec4 lm = imageLoad(lummat_image, p);
			int m = clamp(int(lm.y + 0.5), 0, 8);
			vec3 c = max(imageLoad(color_image, p).rgb, vec3(0.0));
			if (m == M_STREAK) {
				vec2 q = vec2(x, y);
				sn += 1.0;
				s1 += q;
				s2 += vec3(q.x * q.x, q.y * q.y, q.x * q.y);
				scol += c;
				continue;
			}
			counts[m] += 1.0;
			n += 1.0;
			col_sum += c;
			lum_max = max(lum_max, lm.x);
			float d = imageLoad(dir_image, p).r;
			if (d > -0.5) {
				votes[int(d + 0.5)] += 1.0;
				edge_y += float(y) / float(csz.y);
				edge_n += 1.0;
			}
		}
	}

	float total = n + sn;
	vec3 avg = n > 0.0 ? col_sum / n : (sn > 0.0 ? scol / sn : vec3(0.0));

	int dom = M_SKY;
	float dom_count = -1.0;
	for (int i = 0; i < 9; i++) {
		if (counts[i] > dom_count) {
			dom_count = counts[i];
			dom = i;
		}
	}

	// Normalise by the adapted scene luminance (see ascii_exposure.glsl).
	float scene_lum = luma(avg);
	float adapted = ex.initialised > 0.5 ? exp2(ex.adapted_log) : pc.p4.w;
	// Adaptation is partial and capped, like eyes rather than a camera: a dark
	// cave or night stays dark (dense glyphs only where the light is) instead
	// of being lifted to a uniform grey wash of fog and rock.
	float norm = clamp(pow(pc.p4.w / max(adapted, 1e-5), pc.p4.z), 0.25, 9.0);
	float exposure = pc.p2.x * norm;
	float colour_exposure = pc.p2.x * clamp(pow(0.3 / max(adapted, 1e-5), 0.7), 0.05, 9.0);
	float gamma = pc.p2.y;
	float lum = scene_lum * exposure;
	imageStore(cell_lum_image, cell, vec4(log2(scene_lum + 1e-4), dom == M_SKY ? 0.0 : 1.0, 0.0, 0.0));
	float x = pow(clamp(lum / (1.0 + lum), 0.0, 1.0), gamma);
	// Contrast around the middle of the ramp: deep darks, dense brights.
	x = clamp((x - 0.42) * 1.3 + 0.45, 0.0, 1.0);
	x = max(x, pow(clamp(lum / (1.0 + lum), 0.0, 1.0), gamma) * 0.6);  // keep shadow detail
	float dither = (flags & FLAG_DITHER) != 0u ? bayer4(cell) - 0.5 : 0.0;
	float h = hash12(vec2(cell) + 17.0);

	uint mode = MODE_GLYPH;
	int glyph = 0;
	int edge_dir = 7; // 7 = none
	vec3 fg = avg;

	int best_dir = 0;
	float best_votes = votes.x;
	for (int i = 1; i < 4; i++) {
		if (votes[i] > best_votes) {
			best_votes = votes[i];
			best_dir = i;
		}
	}
	float all_votes = votes.x + votes.y + votes.z + votes.w;
	bool edge_ok = (flags & FLAG_EDGES) != 0u && total > 0.0 && best_votes >= pc.p2.z * total && best_votes >= all_votes * 0.45;

	if (counts[M_EMISSIVE] > total * 0.35) {
		mode = MODE_PASS;
	} else if ((flags & FLAG_RAIN) != 0u && sn >= max(3.0, total * 0.08)) {
		mode = MODE_RAIN;
		vec2 mean = s1 / sn;
		float cxx = s2.x / sn - mean.x * mean.x;
		float cyy = s2.y / sn - mean.y * mean.y;
		float cxy = s2.z / sn - mean.x * mean.y;
		// Principal axis of the streak pixels (y down).
		float theta = 0.5 * atan(2.0 * cxy, cxx - cyy);
		vec2 axis = vec2(cos(theta), sin(theta));
		float spread = cxx + cyy;
		if (sn < total * 0.12 && spread < float(csz.y) * 0.6) {
			glyph = ramp_glyph(R_RAIN, h < 0.5 ? 3 : 4); // ' or .
		} else if (abs(axis.y) > 0.92) {
			glyph = ramp_glyph(R_RAIN, 0); // |
		} else if (axis.x * axis.y < 0.0) {
			glyph = ramp_glyph(R_RAIN, 1); // /
		} else {
			glyph = ramp_glyph(R_RAIN, 2); // backslash
		}
		vec3 rain = scol / sn;
		fg = max(rain, avg * 1.4) + vec3(0.004, 0.005, 0.006);
	} else if (dom == M_SKY) {
		float avg_l = luma(avg);
		if (lum_max > pc.p4.y && lum_max > avg_l * 3.0) {
			// A star or the moon's limb: a point brighter than its cell.
			int len = ramp_len(R_SKY);
			glyph = ramp_glyph(R_SKY, lum_max > pc.p4.y * 4.0 ? len - 1 : len - 2);
			fg = avg * 0.5 + vec3(lum_max) * 0.5;
		} else {
			int len = ramp_len(R_SKY);
			glyph = ramp_glyph(R_SKY, int((x * 0.7 + dither * 0.6 / float(len)) * float(len)));
		}
	} else if (dom == M_FOLIAGE) {
		if (x < 0.05) {
			glyph = ramp_glyph(R_FOLIAGE, F_SPACE);
		} else if (best_votes >= 0.16 * total) {
			// Blade silhouettes: follow the blade direction.
			int k = best_dir == 0 ? F_BAR : (best_dir == 2 ? F_SLASH : (best_dir == 3 ? F_BACK : F_TICK));
			glyph = ramp_glyph(R_FOLIAGE, k);
			edge_dir = best_dir;
		} else {
			// Canopy interiors: a soft dense ramp, with sparse . , highlights.
			int len = ramp_len(R_LEAF);
			if (x > 0.55 && h < 0.12) {
				glyph = ramp_glyph(R_FOLIAGE, h < 0.06 ? F_COMMA : F_DOT);
			} else {
				glyph = ramp_glyph(R_LEAF, max(int(float(len) * 0.35), int(x * float(len) + dither * 0.9)));
			}
		}
	} else if (dom == M_LIQUID) {
		int len = ramp_len(R_LIQUID);
		if (x < 0.12) {
			glyph = ramp_glyph(R_LIQUID, x < 0.04 ? 0 : 1);
		} else {
			// Ripples drift across the surface: cycle through the wave glyphs.
			float phase = time * pc.p3.w + h * 3.0 + float(cell.x) * 0.23 + sin(float(cell.y) * 0.9 + time) * 0.6;
			int k = int(floor(phase)) % 3;
			int base = x > 0.45 ? len - 3 : max(len - 4, 1);
			glyph = ramp_glyph(R_LIQUID, base + k);
		}
	} else {
		bool classic = (flags & FLAG_CLASSIC) != 0u;
		int r = classic ? R_CLASSIC : (dom == M_GROUND ? R_GROUND : R_SOLID);
		int len = ramp_len(r);
		if (edge_ok) {
			mode = MODE_EDGE;
			edge_dir = best_dir;
			int k = best_dir;
			if (best_dir == 1 && edge_y / max(edge_n, 1.0) > 0.62) {
				k = 4; // underscore: the edge sits low in the cell
			}
			glyph = ramp_glyph(R_EDGES, k);
		} else {
			float fi = x * float(len) + dither * 0.9;
			int idx = clamp(int(fi), 0, len - 1);
			if (scene_lum > 0.0003) {
				// Surfaces stay textured even in shadow; brightness is carried by
				// the glyph colour (as in classic ASCII art), not only by density.
				float floor_frac = classic ? 0.12 : (dom == M_GROUND ? 0.3 : 0.4);
				idx = max(idx, int(float(len) * floor_frac));
			}
			if ((flags & FLAG_FLICKER) != 0u && x < 0.3 && idx > 0) {
				float f = hash12(vec2(cell) + floor(time * 9.0) * 1.37);
				if (f < pc.p3.z * 0.2) {
					idx = clamp(idx + (f < pc.p3.z * 0.1 ? -1 : 1), 1, len - 1);
				}
			}
			glyph = ramp_glyph(r, idx);
		}
	}

	// Saturation / contrast in linear HDR, around mid grey.
	float l = luma(fg);
	fg = mix(vec3(l), fg, pc.p2.w);
	fg = 0.18 * pow(max(fg, vec3(0.0)) / 0.18, vec3(pc.p3.x));

	imageStore(cell_color_image, cell, vec4(fg * colour_exposure, float(glyph)));
	imageStore(cell_aux_image, cell, vec4(float(mode), float(dom), float(edge_dir), x));
}
