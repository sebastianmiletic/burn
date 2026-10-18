shader_type spatial;
render_mode cull_back;
// The horizon height-field (world/distant_land.gd). Same texture arrays and
// material table as terrain.gdshader, reduced to what reads at a distance:
//   COLOR, CUSTOM0  blend weights of the 8 surface material classes
//   CUSTOM1         tree canopy colour (rgb) and cover (a)
//   CUSTOM3         blend weights of classes 9..12 (revision 3 rock and red sand)
//   UV              (snow cover the terrain has there, sea / lake: 1, lava: 2)
//   UV2             horizon tangents towards the rising / setting sun
//   CUSTOM2         softened height and normal the far fine LOD morphs to
// Lighting is custom so ridges can shadow valleys at low sun; the fog is
// custom so far ranges thin into the sky instead of a uniform wall.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform float snow_cover;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 mat_a[128];
uniform vec4 mat_tint[128];
uniform int class_codes[12];
uniform int snow_code = 5;

uniform sampler2D coverage : filter_nearest, repeat_disable;   // VoxelWorld.horizon_coverage
uniform float world_size = 3072.0;
uniform vec3 focus;
uniform float near_radius = 120.0;
uniform float near_end = 184.0;
uniform float cam_height = 20.0;
// Haze (SkyController.haze_params).
uniform vec3 fog_col = vec3(0.5, 0.55, 0.6);
uniform vec3 sky_hz = vec3(0.5, 0.55, 0.6);
uniform vec3 sky_hz_sun = vec3(0.6, 0.55, 0.5);
uniform float fog_aerial = 0.6;
uniform float fog_sky_affect = 0.12;
uniform float fog_dens = 0.0016;
uniform float far_dens = 0.0004;
uniform float sun_scatter = 0.1;
uniform vec3 sun_dir_w = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_col = vec3(1.0);
uniform float fog_h = 17.0;
uniform float fog_h_dens = 0.0;

const float SEA = 12.85;

varying vec3 v_world;
varying vec3 v_wn;
varying vec4 v_w0;
varying vec4 v_w1;
varying vec4 v_w2;
varying vec4 v_canopy;
varying vec2 v_flags;
varying vec2 v_hz;
varying float v_far;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(world.xz, focus.xz);
	// Geomorph: exact terrain near the streamed rim, the softened massif shape
	// (CUSTOM2: height, normal) further out, continuously.
	float morph = smoothstep(near_end + 10.0, near_end + 320.0, d) * 0.97;
	v_far = morph;
	VERTEX.y = mix(VERTEX.y, CUSTOM2.x, morph);
	NORMAL = normalize(mix(NORMAL, CUSTOM2.yzw, morph));
	// Around the rim of the streamed field: sink under the detailed terrain.
	float sink = 1.0 - smoothstep(near_end - 16.0, near_end, d);
	// Beyond it, forests gain the bulk of their crowns.
	float far_f = smoothstep(near_end, near_end + 140.0, d);
	VERTEX.y += -sink * 4.0 + CUSTOM1.a * 7.0 * far_f * (1.0 - UV.y);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_w0 = COLOR;
	v_w1 = CUSTOM0;
	v_w2 = CUSTOM3;
	v_canopy = CUSTOM1;
	v_flags = UV;
	v_hz = UV2;
}

vec3 layer_top(int code, vec2 xz) {
	vec4 a = mat_a[code];
	return texture(albedo_tex, vec3(xz * a.z, a.x)).rgb * mat_tint[code].rgb;
}

void fragment() {
	vec3 p = v_world;
	// Give way only where every requested chunk mesh of the column is ready:
	// streaming gaps (fast travel, climbs) keep the horizon instead of a hole.
	if (texture(coverage, p.xz / world_size).r > 0.5) {
		discard;
	}
	vec3 nw = normalize(v_wn);
	float lava = smoothstep(1.4, 1.6, v_flags.y);
	float sea = smoothstep(0.45, 0.55, v_flags.y) * (1.0 - lava);

	// Ground: blend of the surface materials, as the streamed terrain has them.
	float w[12] = float[12](v_w0.x, v_w0.y, v_w0.z, v_w0.w, v_w1.x, v_w1.y, v_w1.z, v_w1.w, v_w2.x, v_w2.y, v_w2.z, v_w2.w);
	vec3 ground = vec3(0.0);
	float wsum = 0.0;
	for (int k = 0; k < 12; k++) {
		if (w[k] > 0.04) {
			ground += layer_top(class_codes[k], p.xz) * w[k];
			wsum += w[k];
		}
	}
	ground = wsum > 0.0 ? ground / wsum : layer_top(class_codes[0], p.xz);
	float macro = n_fbm2(p.xz * 0.018) * 0.7 + n_value2(p.xz * 0.11) * 0.3;
	ground *= 1.0 + (macro - 0.5) * 0.44;

	// Tree canopy: clumps of crowns where the world plants trees.
	float clump = n_value2(p.xz * 0.11) * 0.65 + n_value2(p.xz * 0.37 + 3.1) * 0.35;
	float cover = clamp((clump - (1.0 - v_canopy.a)) * 3.5, 0.0, 1.0);
	vec3 crowns = v_canopy.rgb * (0.65 + 0.7 * n_value2(p.xz * 0.6));

	// Cliffs: the rock under every material on steep faces (the 8 m mesh is
	// smoother than the real terrain, so the threshold is a little lower).
	// The rock that dominates here (grey stone, red canyon rock, basalt, alpine rock).
	int rock_k = 7;
	float rock_w = w[7] + 0.001;
	for (int k = 8; k < 11; k++) {
		if (w[k] > rock_w) {
			rock_w = w[k];
			rock_k = k;
		}
	}
	if (w[11] > rock_w) {
		rock_k = 8;   // red sand country: red cliffs
	}
	vec4 ra = mat_a[class_codes[rock_k]];
	vec2 side_uv = (abs(nw.x) > abs(nw.z) ? p.zy : p.xy) * ra.z * 0.8;
	vec3 rock = texture(albedo_tex, vec3(side_uv, ra.y)).rgb * mat_tint[class_codes[rock_k]].rgb * (0.62 + macro * 0.3);
	float cliff = smoothstep(0.84, 0.6, nw.y + (macro - 0.5) * 0.12);

	vec3 alb = mix(ground, crowns, cover * (1.0 - cliff));
	alb = mix(alb, rock, cliff);

	// Snow: the mountains snow above the same height the streamed terrain does,
	// weather snow settles on gentle slopes everywhere.
	float up = smoothstep(0.55, 0.9, nw.y);
	float snow = clamp(v_flags.x * 1.4 - 0.2, 0.0, 1.0) * (1.0 - cliff * 0.8);
	// Seen from afar the high summits carry snowcaps on all but sheer faces
	// (the real slopes there are broken by ledges the 8 m mesh cannot show).
	float cap = v_flags.x * smoothstep(95.0, 150.0, p.y + (macro - 0.5) * 20.0) * smoothstep(0.32, 0.6, nw.y) * v_far;
	snow = max(snow, cap);
	snow = max(snow, clamp(snow_cover * 1.4 - (1.0 - up), 0.0, 1.0));
	snow *= (1.0 - sea) * (1.0 - lava);
	vec3 snow_alb = layer_top(snow_code, p.xz * 0.5) * 0.92;
	alb = mix(alb, snow_alb, snow);

	// Sea.
	vec3 water = vec3(0.018, 0.045, 0.055);
	alb = mix(alb, water, sea);
	alb = mix(alb, vec3(0.05, 0.02, 0.015), lava);
	vec3 n = mix(nw, vec3(0.0, 1.0, 0.0), sea);
	if (sea > 0.5) {
		// Long swell so the sun glitters instead of mirroring flat.
		float t = TIME * 0.35;
		n = normalize(n + vec3(n_value2(p.xz * 0.02 + t) - 0.5, 0.0, n_value2(p.xz * 0.02 - t + 7.0) - 0.5) * 0.12);
	}

	ALBEDO = alb;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	SPECULAR = mix(0.35, 0.5, sea);
	EMISSION = vec3(1.0, 0.32, 0.05) * lava * (1.2 + 0.8 * n_value2(p.xz * 0.05 + TIME * 0.05));
	ROUGHNESS = ascii_roughness(mix(mix(0.92, 0.75, snow), 0.06, sea), sea > 0.5 ? ASCII_LIQUID : ASCII_GROUND);

	// Aerial perspective: matches the environment fog up to the rim of the
	// streamed terrain, then thins (and thins further with altitude) so the
	// far ranges fade into the horizon sky instead of a flat wall.
	vec3 v = p - CAMERA_POSITION_WORLD;
	float d = length(v);
	vec3 vd = v / max(d, 1e-3);
	float facing = max(dot(vd, sun_dir_w), 0.0);
	vec3 sky = mix(sky_hz, sky_hz_sun, facing * facing);
	float d0 = near_end + 40.0;
	// Far away the haze is simply the sky behind (in a storm a dark grey), so
	// fully hazed ranges dissolve into the horizon rather than standing out.
	float aer = mix(fog_aerial, 1.0, smoothstep(d0, d0 + 700.0, d));
	vec3 col = mix(fog_col, sky, aer) + sun_col * pow(facing, 8.0) * sun_scatter;
	float hm = max(0.5 * (cam_height + p.y) - SEA, 0.0);
	float od = fog_dens * min(d, d0) + far_dens * exp(-hm / 420.0) * max(d - d0, 0.0);
	float amount = 1.0 - exp(-od);
	if (fog_h_dens > 0.0001) {
		amount = max(amount, 1.0 - exp(min(0.0, (p.y - fog_h) * fog_h_dens)));
	}
	// Ranges never vanish completely into haze: a trace of their own shading
	// always reads, darker than the sky in foul weather, never a pale cut-out.
	// In thick weather (fog banks, blizzards) they do vanish, as the near fog
	// hides everything past ~150 m.
	FOG = vec4(col, min(amount, mix(0.93, 1.0, clamp((fog_dens - 0.004) * 80.0, 0.0, 1.0))));
}

void light() {
	float diff = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float vis = 1.0;
	if (LIGHT_IS_DIRECTIONAL && v_hz.x > -0.99) {
		// The sun is hidden behind the terrain's horizon in its direction.
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float hl = max(length(lw.xz), 1e-3);
		float tan_e = lw.y / hl;
		float east = clamp(lw.x / hl * 0.6 + 0.5, 0.0, 1.0);
		float horizon = mix(v_hz.y, v_hz.x, east);
		vis = smoothstep(horizon - 0.02, horizon + 0.06, tan_e);
	}
	DIFFUSE_LIGHT += diff * vis * ATTENUATION * LIGHT_COLOR / PI;
	if (v_flags.y > 0.5 && v_flags.y < 1.5) {
		vec3 h = normalize(VIEW + LIGHT);
		float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), 180.0) * 5.0;
		SPECULAR_LIGHT += s * vis * ATTENUATION * LIGHT_COLOR / PI;
	}
}
