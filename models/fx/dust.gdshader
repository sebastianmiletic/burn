shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled;
// Soft, lit dust / snow / sand puff for movement FX. Lit (so it is dark at
// night and never glows), camera-facing, fades where it meets the ground.
// Transparent, so it is drawn on the FX layer after the ASCII pass; colours are
// kept dim so it reads as haze over the glyphs rather than a bright flare.
// Particle COLOR: rgb tint, a fades over the particle's life.

#include "res://rendering/materials/noise.gdshaderinc"

uniform float density = 0.55;
uniform float soft_distance = 0.35;
uniform bool streak = false;   // velocity-aligned streaks (particle Y = velocity)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float v_seed;

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.x * 7.0);
	if (streak) {
		vec3 y = normalize(MODEL_MATRIX[1].xyz);
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec3 x = normalize(cross(y, to_cam));
		vec3 z = cross(x, y);
		mat4 m = mat4(vec4(x * length(MODEL_MATRIX[0].xyz), 0.0), vec4(y * length(MODEL_MATRIX[1].xyz), 0.0),
				vec4(z, 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * m;
	} else {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		float sc = length(MODEL_MATRIX[0].xyz);
		// Spin each puff a little so they do not look stamped.
		float a = v_seed * 6.2831 + TIME * (v_seed - 0.5) * 0.6;
		mat4 rot = mat4(vec4(cos(a), sin(a), 0, 0), vec4(-sin(a), cos(a), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
		bb = bb * mat4(vec4(sc, 0, 0, 0), vec4(0, sc, 0, 0), vec4(0, 0, sc, 0), vec4(0, 0, 0, 1)) * rot;
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	}
}

void fragment() {
	vec2 q = UV - 0.5;
	float a;
	if (streak) {
		a = (1.0 - smoothstep(0.1, 0.5, abs(q.x))) * (1.0 - smoothstep(0.2, 0.5, abs(q.y)));
	} else {
		float d = length(q) * 2.0;
		float n = n_fbm2(UV * 3.5 + v_seed * 17.0);
		a = (1.0 - smoothstep(0.25, 1.0, d + (n - 0.5) * 0.6)) * (0.6 + 0.6 * n);
	}
	a *= COLOR.a * density;
	// Soft particle: fade near opaque geometry.
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float gap = VERTEX.z - view.z;
	a *= clamp(gap / soft_distance, 0.0, 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
