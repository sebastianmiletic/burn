shader_type sky;
// Night sky: deep gradient, drifting cloud banks, twinkling stars and a moon
// disc aligned with the first directional light.

#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 zenith_color : source_color = vec3(0.004, 0.006, 0.014);
uniform vec3 horizon_color : source_color = vec3(0.025, 0.026, 0.035);
uniform vec3 cloud_color : source_color = vec3(0.03, 0.032, 0.04);
uniform vec3 moon_color : source_color = vec3(0.9, 0.92, 1.0);
uniform float moon_size = 0.02;
uniform float moon_energy = 4.0;
uniform float star_density : hint_range(0.0, 0.02) = 0.006;
uniform float star_energy = 1.6;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(h, 0.45));

	vec3 moon_dir = normalize(-LIGHT0_DIRECTION);
	if (LIGHT0_ENABLED) {
		moon_dir = normalize(LIGHT0_DIRECTION);
	}
	float md = dot(d, moon_dir);

	float cloud = 0.0;
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.15);
		cloud = n_fbm2(uv * 1.4 + vec2(TIME * 0.008, 0.0));
		cloud = smoothstep(1.0 - cloud_cover, 1.0, cloud);
	}

	if (!AT_CUBEMAP_PASS && d.y > 0.0) {
		vec3 sp = d * 300.0;
		vec3 cell = floor(sp);
		float r = n_hash13(cell);
		if (r < star_density * 10.0) {
			vec3 star_pos = cell + vec3(n_hash13(cell + 1.3), n_hash13(cell + 2.7), n_hash13(cell + 5.1));
			float dist = length(sp - star_pos);
			float twinkle = 0.6 + 0.4 * sin(TIME * (2.0 + r * 40.0) + r * 100.0);
			col += vec3(0.85, 0.9, 1.0) * smoothstep(0.35, 0.0, dist) * star_energy * twinkle * (1.0 - cloud);
		}
	}

	col = mix(col, cloud_color, cloud * 0.85);

	float disc = smoothstep(1.0 - moon_size * 0.06, 1.0 - moon_size * 0.05, md);
	float halo = pow(max(md, 0.0), 300.0) * 0.6 + pow(max(md, 0.0), 30.0) * 0.08;
	col += moon_color * (disc * moon_energy * (1.0 - cloud * 0.7) + halo * (1.0 - cloud * 0.4));

	COLOR = col;
}
