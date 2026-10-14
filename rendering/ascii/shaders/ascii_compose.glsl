#[compute]
#version 450

// Pass 5/5: draw every cell's glyph from the font atlas back into the scene
// colour buffer. Runs before Godot's transparent pass, so fire, sparks and
// magic (transparent / additive materials) are drawn on top un-converted, and
// Godot's glow + tonemapping run afterwards, spilling light across glyphs.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D cell_color_image;
layout(r32ui, set = 0, binding = 2) uniform restrict readonly uimage2D cell_info_image;
layout(set = 0, binding = 3) uniform sampler2D atlas_tex;
layout(rgba16f, set = 0, binding = 4) uniform restrict readonly image2D lummat_image;
layout(r16f, set = 0, binding = 5) uniform restrict readonly image2D dir_image;

layout(push_constant, std430) uniform Params {
	vec4 p0; // width, height, cell w, cell h
	vec4 p1; // cols, rows, time, debug view (0 none, 1 edges, 2 materials)
	vec4 p2; // background tint, vignette, grain, shimmer
	vec4 p3; // grid overlay, background level, glyph gain, unused
} pc;

const uint MODE_PASS = 1u;
const uint MODE_EDGE = 3u;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float glyph_ink(uint g, ivec2 local, ivec2 csz) {
	local = clamp(local, ivec2(0), csz - 1);
	return texelFetch(atlas_tex, ivec2(int(g) * csz.x + local.x, local.y), 0).r;
}

vec3 material_colour(int m) {
	const vec3 pal[9] = vec3[9](
			vec3(0.55, 0.55, 0.58), // solid
			vec3(0.15, 0.75, 0.2), // foliage
			vec3(0.1, 0.4, 0.95), // liquid
			vec3(0.7, 0.9, 1.0), // streak
			vec3(0.55, 0.38, 0.2), // ground
			vec3(1.0, 0.55, 0.05), // emissive
			vec3(0.75, 0.15, 0.6), // cloth
			vec3(0.95, 0.1, 0.1), // default (unmarked)
			vec3(0.02, 0.02, 0.08)); // sky
	return pal[clamp(m, 0, 8)];
}

vec3 dir_colour(int d) {
	if (d == 0) return vec3(1.0, 0.2, 0.2);
	if (d == 1) return vec3(0.2, 1.0, 0.2);
	if (d == 2) return vec3(0.2, 0.9, 1.0);
	if (d == 3) return vec3(1.0, 0.95, 0.2);
	return vec3(0.0);
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(pc.p0.xy);
	if (p.x >= size.x || p.y >= size.y) {
		return;
	}
	ivec2 csz = ivec2(pc.p0.zw);
	ivec2 cell = p / csz;
	ivec2 local = p - cell * csz;
	float time = pc.p1.z;
	int debug_view = int(pc.p1.w + 0.5);

	uint info = imageLoad(cell_info_image, cell).r;
	vec4 cc = imageLoad(cell_color_image, cell);
	uint glyph = info & 0xFFu;
	uint mode = (info >> 8u) & 0xFu;
	int dom = int((info >> 12u) & 0xFu);
	int edge_dir = int((info >> 16u) & 0x7u);

	vec3 orig = imageLoad(color_image, p).rgb;
	vec3 fg = cc.rgb;
	vec3 out_c;

	if (mode == MODE_PASS) {
		out_c = orig;
	} else {
		float gain = max(pc.p3.z, 1e-3);
		vec3 bg = vec3(pc.p3.y) + fg / gain * pc.p2.x * 0.12;
		float ink = glyph_ink(glyph, local, csz);
		if (pc.p2.w > 0.0 && cc.a > 0.8) {
			// Chromatic shimmer on very bright cells: red and blue ink drift apart.
			float s = sin(time * 3.0 + float(cell.x) * 0.7 + float(cell.y) * 1.3);
			int off = s > 0.33 ? 1 : (s < -0.33 ? -1 : 0);
			float ink_r = glyph_ink(glyph, local + ivec2(off, 0), csz);
			float ink_b = glyph_ink(glyph, local - ivec2(off, 0), csz);
			vec3 inks = mix(vec3(ink), vec3(ink_r, ink, ink_b), pc.p2.w);
			out_c = bg * (1.0 - inks) + fg * inks;
		} else {
			out_c = mix(bg, fg, ink);
		}
	}

	if (debug_view == 1) {
		vec4 lm = imageLoad(lummat_image, p);
		int d = int(imageLoad(dir_image, p).r + 0.5);
		vec3 px = imageLoad(dir_image, p).r > -0.5 ? dir_colour(d) * 0.35 : vec3(lm.x * 0.08);
		float ink = glyph_ink(glyph, local, csz);
		vec3 gc = mode == MODE_EDGE ? dir_colour(edge_dir) : vec3(0.25);
		out_c = px + gc * ink;
	} else if (debug_view == 2) {
		vec4 lm = imageLoad(lummat_image, p);
		int m = int(lm.y + 0.5);
		float ink = glyph_ink(glyph, local, csz);
		out_c = material_colour(m) * (0.25 + 0.15 * lm.x) + material_colour(dom) * ink * 0.9;
	}

	if (pc.p2.y > 0.0) {
		vec2 uv = (vec2(p) + 0.5) / vec2(size) - 0.5;
		out_c *= clamp(1.0 - pc.p2.y * dot(uv, uv) * 2.2, 0.0, 1.0);
	}
	if (pc.p2.z > 0.0) {
		float g = hash12(vec2(p) + fract(time * 13.7) * 1000.0) - 0.5;
		out_c *= 1.0 + g * pc.p2.z;
	}
	if (pc.p3.x > 0.5 && (local.x == 0 || local.y == 0)) {
		out_c = mix(out_c, vec3(0.05, 0.12, 0.18), 0.65);
	}

	imageStore(color_image, p, vec4(max(out_c, vec3(0.0)), 1.0));
}
