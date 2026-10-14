#[compute]
#version 450

// Final pass inside the 3D viewport. The glyphs themselves are drawn later,
// at native screen resolution, by ascii_composite.gdshader. Here the low-res
// scene colour is cleared so that what Godot draws next (transparent FX:
// fire, sparks, spells) plus its glow becomes a separate additive FX layer.
// Emissive pass-through cells keep their pixels so they glow too.
// Debug views draw their visualisation into the buffer instead.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D cell_aux_image;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D lummat_image;
layout(r16f, set = 0, binding = 3) uniform restrict readonly image2D dir_image;

layout(push_constant, std430) uniform Params {
	vec4 p0; // width, height, cell w, cell h (internal, fractional)
	vec4 p1; // cols, rows, debug view (0 none, 1 edges, 2 materials), unused
} pc;

const float MODE_PASS = 1.0;

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
	ivec2 cell = ivec2(floor((vec2(p) + 0.5) / pc.p0.zw));
	cell = min(cell, ivec2(pc.p1.xy) - 1);
	int debug_view = int(pc.p1.z + 0.5);

	vec4 aux = imageLoad(cell_aux_image, cell);
	vec3 c = imageLoad(color_image, p).rgb;
	vec3 out_c = vec3(0.0);

	if (debug_view == 1) {
		float d = imageLoad(dir_image, p).r;
		out_c = d > -0.5 ? dir_colour(int(d + 0.5)) : vec3(imageLoad(lummat_image, p).x * 0.1);
		if (aux.z < 6.5) {
			out_c = mix(out_c, dir_colour(int(aux.z + 0.5)), 0.35);
		}
	} else if (debug_view == 2) {
		vec4 lm = imageLoad(lummat_image, p);
		out_c = material_colour(int(lm.y + 0.5)) * (0.35 + 0.25 * min(lm.x * 4.0, 1.0));
	} else if (abs(aux.x - MODE_PASS) < 0.5) {
		out_c = c;
	}

	imageStore(color_image, p, vec4(out_c, 1.0));
}
