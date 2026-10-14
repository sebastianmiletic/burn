shader_type sky;
// Day/night sky: gradient that follows the sun, sun and moon discs, cloud
// banks, stars at night. In the underworld: a dark ember-lit vault with
// drifting ash clouds.

#include "res://rendering/materials/noise.gdshaderinc"

uniform float day = 1.0;          // 0 night .. 1 day
uniform float dusk = 0.0;         // 0..1 golden hour strength
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.4;
uniform float storm = 0.0;
uniform float underworld = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, -0.2, 1.0);

	vec3 day_zenith = vec3(0.16, 0.24, 0.38);
	vec3 day_horizon = vec3(0.55, 0.52, 0.48);
	vec3 night_zenith = vec3(0.004, 0.006, 0.014);
	vec3 night_horizon = vec3(0.02, 0.022, 0.03);
	vec3 dusk_horizon = vec3(0.75, 0.32, 0.12);

	vec3 zenith = mix(night_zenith, day_zenith, day);
	vec3 horizon = mix(night_horizon, day_horizon, day);
	float sun_side = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-4)), 0.0);
	horizon = mix(horizon, dusk_horizon, dusk * (0.35 + 0.65 * sun_side));
	vec3 col = mix(horizon, zenith, pow(max(h, 0.0), 0.5));
	col = mix(col, horizon * 0.6, smoothstep(0.0, -0.2, d.y));

	// Clouds.
	float cloud = 0.0;
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12);
		float c = n_fbm2(uv * 1.1 + vec2(TIME * 0.01, TIME * 0.004));
		cloud = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover * 0.4, c) * smoothstep(0.0, 0.15, d.y);
	}
	vec3 cloud_col = mix(vec3(0.03, 0.03, 0.04), mix(vec3(0.7, 0.68, 0.65), vec3(0.95, 0.55, 0.3), dusk), day) * (1.0 - storm * 0.6);

	// Stars.
	if (!AT_CUBEMAP_PASS && d.y > 0.0 && day < 0.6) {
		vec3 sp = d * 300.0;
		vec3 cell = floor(sp);
		float r = n_hash13(cell);
		if (r < 0.06) {
			vec3 star_pos = cell + vec3(n_hash13(cell + 1.3), n_hash13(cell + 2.7), n_hash13(cell + 5.1));
			float tw = 0.6 + 0.4 * sin(TIME * (2.0 + r * 40.0) + r * 100.0);
			col += vec3(0.85, 0.9, 1.0) * smoothstep(0.35, 0.0, length(sp - star_pos)) * 1.4 * tw * (1.0 - day / 0.6) * (1.0 - cloud);
		}
	}

	float sd = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.85, 0.6) * smoothstep(0.9993, 0.9996, sd) * 18.0 * (1.0 - cloud * 0.9);
	col += vec3(1.0, 0.6, 0.3) * pow(max(sd, 0.0), 24.0) * (0.25 + dusk * 0.6) * (1.0 - cloud * 0.5);
	float md = dot(d, normalize(moon_dir));
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9988, 0.9991, md) * 3.0 * (1.0 - cloud * 0.8);
	col += vec3(0.5, 0.6, 0.8) * pow(max(md, 0.0), 60.0) * 0.06;

	col = mix(col, cloud_col, cloud * 0.85);

	// Underworld vault.
	vec3 hell = mix(vec3(0.05, 0.008, 0.004), vec3(0.18, 0.03, 0.01), smoothstep(0.4, -0.1, d.y));
	float ash = n_fbm2(d.xz / (abs(d.y) + 0.2) * 1.5 + vec2(TIME * 0.02));
	hell += vec3(0.25, 0.05, 0.01) * smoothstep(0.5, 0.9, ash) * 0.6;
	col = mix(col, hell, underworld);

	COLOR = col;
}
