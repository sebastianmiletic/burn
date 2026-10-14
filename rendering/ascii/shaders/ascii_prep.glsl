#[compute]
#version 450

// Pass 1/5: unpack the G-buffer into compact per-pixel data.
//   gbuf   = view-space normal, linear depth
//   lummat = luminance, material id (8 = sky), sky flag, roughness

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_tex;
layout(set = 0, binding = 1) uniform sampler2D normal_roughness_tex;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D color_image;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D gbuf_image;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D lummat_image;

layout(push_constant, std430) uniform Params {
	vec4 screen; // width, height, z_near, z_far
} pc;

const float MAT_SKY = 8.0;

// Godot 4.3+ uses reversed Z in [0, 1]: 1 at the near plane, 0 at the far plane.
float linear_depth(float d) {
	float n = pc.screen.z;
	float f = pc.screen.w;
	return n * f / (n + d * (f - n));
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= int(pc.screen.x) || p.y >= int(pc.screen.y)) {
		return;
	}

	float d = texelFetch(depth_tex, p, 0).r;
	vec4 nr = texelFetch(normal_roughness_tex, p, 0);
	vec3 c = imageLoad(color_image, p).rgb;
	bool sky = d < 1e-7;

	vec3 n = normalize(nr.xyz * 2.0 - 1.0);

	// See AsciiMaterialId.gd: alpha = round(roughness * 127), mirrored for dynamic instances.
	float stored = floor(nr.w * 255.0 + 0.5);
	if (stored > 127.5) {
		stored = 255.0 - stored;
	}
	int bits = int(stored);
	float mat = sky ? MAT_SKY : float(bits & 7);
	float rough = float(bits >> 3) / 15.0;

	float lin = sky ? pc.screen.w : linear_depth(d);
	float lum = dot(max(c, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));

	imageStore(gbuf_image, p, vec4(sky ? vec3(0.0, 0.0, 1.0) : n, lin));
	imageStore(lummat_image, p, vec4(lum, mat, sky ? 1.0 : 0.0, rough));
}
