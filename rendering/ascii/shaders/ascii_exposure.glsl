#[compute]
#version 450

// Glyph exposure: average log-luminance of all non-sky cells, adapted over
// time. Godot's auto-exposure only runs in the tonemapper, after the ASCII
// pass, so glyph *choice* needs its own adaptation or a night scene would be
// nothing but spaces. The result is read by the cells pass next frame.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(rg16f, set = 0, binding = 0) uniform restrict readonly image2D cell_lum_image; // log2 lum, valid
layout(set = 0, binding = 1, std430) restrict buffer Exposure {
	float adapted_log;
	float initialised;
} ex;

layout(push_constant, std430) uniform Params {
	vec4 p0; // cols, rows, blend factor (0..1), unused
} pc;

shared float s_sum[256];
shared float s_count[256];

void main() {
	uint id = gl_LocalInvocationID.x;
	int cols = int(pc.p0.x);
	int total = cols * int(pc.p0.y);
	float sum = 0.0;
	float count = 0.0;
	for (int i = int(id); i < total; i += 256) {
		vec2 v = imageLoad(cell_lum_image, ivec2(i % cols, i / cols)).rg;
		sum += v.x * v.y;
		count += v.y;
	}
	s_sum[id] = sum;
	s_count[id] = count;
	barrier();
	for (uint stride = 128u; stride > 0u; stride >>= 1u) {
		if (id < stride) {
			s_sum[id] += s_sum[id + stride];
			s_count[id] += s_count[id + stride];
		}
		barrier();
	}
	if (id == 0u && s_count[0] > 0.0) {
		float target = s_sum[0] / s_count[0];
		if (ex.initialised < 0.5) {
			ex.adapted_log = target;
			ex.initialised = 1.0;
		} else {
			ex.adapted_log = mix(ex.adapted_log, target, pc.p0.z);
		}
	}
}
