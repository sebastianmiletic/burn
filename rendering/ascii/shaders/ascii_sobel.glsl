#[compute]
#version 450

// Pass 3/5: Sobel on the edge mask -> quantised edge direction per pixel.
//   -1 none, 0 "|", 1 "-", 2 "/", 3 "\"
// Screen y grows downwards, so a gradient pointing down-right means the edge
// line runs up-right ("/").

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r16f, set = 0, binding = 0) uniform restrict readonly image2D edge_image;
layout(r16f, set = 0, binding = 1) uniform restrict writeonly image2D dir_image;

layout(push_constant, std430) uniform Params {
	vec4 screen; // width, height, unused, unused
} pc;

const float PI = 3.14159265;

float m(ivec2 q, ivec2 size) {
	return imageLoad(edge_image, clamp(q, ivec2(0), size - 1)).r;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(pc.screen.xy);
	if (p.x >= size.x || p.y >= size.y) {
		return;
	}

	float dir = -1.0;
	if (m(p, size) > 0.5) {
		float tl = m(p + ivec2(-1, -1), size), t = m(p + ivec2(0, -1), size), tr = m(p + ivec2(1, -1), size);
		float l = m(p + ivec2(-1, 0), size), r = m(p + ivec2(1, 0), size);
		float bl = m(p + ivec2(-1, 1), size), b = m(p + ivec2(0, 1), size), br = m(p + ivec2(1, 1), size);
		float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
		float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
		if (abs(gx) + abs(gy) > 0.5) {
			float a = mod(atan(gy, gx), PI); // [0, pi)
			if (a < PI * 0.125 || a >= PI * 0.875) {
				dir = 0.0; // gradient horizontal -> vertical line
			} else if (a < PI * 0.375) {
				dir = 2.0;
			} else if (a < PI * 0.625) {
				dir = 1.0; // gradient vertical -> horizontal line
			} else {
				dir = 3.0;
			}
		}
	}

	imageStore(dir_image, p, vec4(dir, 0.0, 0.0, 0.0));
}
