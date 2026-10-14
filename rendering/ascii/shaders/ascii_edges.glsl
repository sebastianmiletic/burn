#[compute]
#version 450

// Pass 2/5: edge mask.
// A pixel is an edge when its 3x3 neighbourhood shows a depth or normal
// discontinuity, or (optionally) a difference-of-Gaussians luminance edge.
// The approach follows AcerolaFX_ASCII (MIT, Garrett Gunnell), adapted to
// Godot's G-buffer.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D gbuf_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D lummat_image;
layout(r16f, set = 0, binding = 2) uniform restrict writeonly image2D edge_image;

layout(push_constant, std430) uniform Params {
	vec4 screen; // width, height, unused, unused
	vec4 edge;   // depth threshold (relative), normal threshold, max distance, luminance edges on
	vec4 dog;    // sigma, sigma scale, threshold, unused
} pc;

const float MAT_STREAK = 3.0;

float log_lum(ivec2 q) {
	return log2(1e-3 + imageLoad(lummat_image, q).x);
}

float gauss(float sigma, float x) {
	return exp(-(x * x) / (2.0 * sigma * sigma));
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(pc.screen.xy);
	if (p.x >= size.x || p.y >= size.y) {
		return;
	}

	vec4 c = imageLoad(gbuf_image, p);
	vec4 cm = imageLoad(lummat_image, p);
	bool c_sky = cm.z > 0.5;
	// Rain streaks get their own strokes; they must not outline themselves or
	// leave edges on whatever is behind them.
	if (abs(cm.y - MAT_STREAK) < 0.5) {
		imageStore(edge_image, p, vec4(0.0));
		return;
	}

	float depth_sum = 0.0;
	float normal_sum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x == 0 && y == 0) {
				continue;
			}
			ivec2 q = clamp(p + ivec2(x, y), ivec2(0), size - 1);
			if (abs(imageLoad(lummat_image, q).y - MAT_STREAK) < 0.5) {
				continue;
			}
			vec4 g = imageLoad(gbuf_image, q);
			depth_sum += abs(g.w - c.w);
			normal_sum += 1.0 - clamp(dot(g.xyz, c.xyz), -1.0, 1.0);
		}
	}
	depth_sum /= max(c.w, 1e-3);

	float e = 0.0;
	if (!c_sky && c.w < pc.edge.z) {
		if (depth_sum > pc.edge.x) {
			e = 1.0;
		}
		if (normal_sum > pc.edge.y) {
			e = 1.0;
		}
		if (pc.edge.w > 0.5 && e < 0.5) {
			float s1 = pc.dog.x;
			float s2 = pc.dog.x * pc.dog.y;
			float a = 0.0, b = 0.0, wa = 0.0, wb = 0.0;
			for (int y = -2; y <= 2; y++) {
				for (int x = -2; x <= 2; x++) {
					ivec2 q = clamp(p + ivec2(x, y), ivec2(0), size - 1);
					float r = length(vec2(x, y));
					float l = log_lum(q);
					float g1 = gauss(s1, r);
					float g2 = gauss(s2, r);
					a += l * g1;
					wa += g1;
					b += l * g2;
					wb += g2;
				}
			}
			if (abs(a / wa - b / wb) > pc.dog.z) {
				e = 1.0;
			}
		}
	}

	imageStore(edge_image, p, vec4(e, 0.0, 0.0, 0.0));
}
