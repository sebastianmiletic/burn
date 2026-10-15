shader_type sky;
render_mode use_half_res_pass;
// Physically based sky (see world/sky/atmosphere.gd for the CPU twin):
//  * single-scattering Rayleigh + Mie + ozone atmosphere over a spherical
//    planet, Chapman-function sun optical depths (sunrise/sunset colours,
//    blue hour, aerial haze, sun aureole all fall out of the model);
//  * a lit 2D cumulus layer (coverage from the weather, sun-ward light march,
//    powder + dual-lobe phase for silver linings) and a high cirrus layer;
//  * moon with phase and maria, stars, a faint milky way, rainbow after rain,
//    lightning flashes inside the clouds;
//  * the underworld: an ember-lit vault of slowly churning ash clouds.
// Cost: the atmosphere and clouds run in the half-resolution pass (and in the
// incremental radiance cubemap); the full-resolution pass only adds the sun,
// moon and stars on top.

#include "res://rendering/materials/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_phase = 1.0;           // 0 new .. 1 full (lit fraction)
uniform float night = 0.0;                // 0 day .. 1 night (stars, night glow)
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_dark : hint_range(0.0, 1.0) = 0.0;   // storm: thick, dark bases
uniform float cirrus : hint_range(0.0, 1.0) = 0.4;
uniform float haze : hint_range(0.0, 1.0) = 0.0;          // fog / rain murk at the horizon
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
uniform float flash = 0.0;                 // lightning, 0..1
uniform vec3 flash_dir = vec3(0.0, 0.3, 1.0);
uniform vec3 sun_light = vec3(1.0);        // sun colour * transmittance at cloud height
uniform vec3 sky_ambient = vec3(0.2, 0.3, 0.45);  // zenith radiance (cloud ambient)
uniform vec2 wind = vec2(0.9, 0.44);       // cloud drift direction * speed (km/s)
uniform float sky_energy = 1.0;            // overall dimming
uniform float underworld = 0.0;
// Underground the radiance cubemap (ambient light, reflections, SDFGI sky
// light) is occluded by the rock overhead: it fades to the cave's own dim,
// tinted bounce colour. The visible sky (cave mouths) is left alone.
uniform float occlusion : hint_range(0.0, 1.0) = 0.0;
// Weather events (Weather): aurora curtains and meteors at night, a hot pale
// haze in a heatwave, a smoky ember-lit sky in an ember storm.
uniform float aurora : hint_range(0.0, 1.0) = 0.0;
uniform float meteors : hint_range(0.0, 1.0) = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float embers : hint_range(0.0, 1.0) = 0.0;
uniform vec3 occluded_color = vec3(0.02);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

const float EARTH_R = 6360.0;
const float ATMOS_R = 6420.0;
const float H_R = 8.0;
const float H_M = 1.2;
const vec3 BETA_R = vec3(5.8e-3, 13.5e-3, 33.1e-3);
const float BETA_M = 14e-3;
const float MIE_EXT = 1.11;
const vec3 BETA_O = vec3(0.65e-3, 1.881e-3, 0.085e-3) * 1.9;
const float CAM_H = 0.25;
const float SUN_E = 20.0;
const float CLOUD_H = 1.8;     // km
const float CIRRUS_H = 8.0;    // km

float horizon_mu(float r) {
	float k = EARTH_R / r;
	return sqrt(max(1.0 - k * k, 0.0));
}

float chapman(float r, float mu, float H) {
	float x = r / H;
	float h = (r - EARTH_R) / H;
	float c = sqrt(x);
	if (mu >= 0.0) {
		return c / (c * mu + 1.0) * exp(-h);
	}
	float x0 = sqrt(1.0 - mu * mu) * x;
	float c0 = sqrt(x0);
	return 2.0 * c0 * exp(EARTH_R / H - x0) - c / (1.0 - c * mu) * exp(-h);
}

vec3 optical_depth(float r, float mu) {
	return (BETA_R + BETA_O) * chapman(r, mu, H_R) * H_R + vec3(BETA_M * MIE_EXT * chapman(r, mu, H_M) * H_M);
}

float ray_sphere(float r, float mu, float radius) {
	float b = r * mu;
	float c = r * r - radius * radius;
	return -b + sqrt(max(b * b - c, 0.0));
}

float phase_mie(float mu, float g) {
	float g2 = g * g;
	return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu)) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

float phase_hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

// In-scattered sunlight along the view ray up to distance `tlimit` (km), and
// the view transmittance to that point (rgb). Returns radiance for a sun of 1.
vec3 atmosphere(vec3 d, vec3 sdir, float tlimit, int samples, out vec3 trans) {
	float r0 = EARTH_R + CAM_H;
	float tmax = min(ray_sphere(r0, d.y, ATMOS_R), tlimit);
	float mu_s = dot(d, sdir);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu_s * mu_s);
	float pm = phase_mie(mu_s, 0.76);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float od_r = 0.0;
	float od_m = 0.0;
	float fs = float(samples);
	for (int i = 0; i < samples; i++) {
		float f0 = float(i) / fs;
		float f1 = float(i + 1) / fs;
		float t = tmax * (f0 * f0 + f1 * f1) * 0.5;
		float ds = tmax * (f1 * f1 - f0 * f0);
		vec3 p = vec3(0.0, r0, 0.0) + d * t;
		float r = length(p);
		float h = r - EARTH_R;
		float dr = exp(-h / H_R) * ds;
		float dm = exp(-h / H_M) * ds;
		od_r += dr * 0.5;
		od_m += dm * 0.5;
		float smu = dot(p / r, sdir);
		// Soft planet shadow (the sun setting behind the curve of the earth).
		float lit = smoothstep(-horizon_mu(r) - 0.004, -horizon_mu(r) + 0.004, smu);
		if (lit > 0.0) {
			vec3 tau = optical_depth(r, max(smu, -horizon_mu(r) + 0.0005)) + (BETA_R + BETA_O) * od_r + vec3(BETA_M * MIE_EXT * od_m);
			vec3 tr = exp(-tau) * lit;
			sum_r += tr * dr;
			sum_m += tr * dm;
		}
		od_r += dr * 0.5;
		od_m += dm * 0.5;
	}
	trans = exp(-((BETA_R + BETA_O) * od_r + vec3(BETA_M * MIE_EXT * od_m)));
	return sum_r * BETA_R * pr + sum_m * BETA_M * pm;
}

float cloud_density(vec2 p, float cover) {
	// p in km. Two octaves of tiling noise, eroded by a finer third.
	vec2 drift = wind * TIME;
	float base = texture(cloud_noise, (p + drift) / 22.0).r;
	float mid = texture(cloud_noise, (p + drift * 1.3) / 7.3 + vec2(0.37, 0.71)).r;
	float fine = texture(cloud_noise, (p + drift * 1.6) / 2.1 + vec2(0.13, 0.29)).r;
	float n = base * 0.62 + mid * 0.28 + fine * 0.1;
	float thresh = mix(0.68, 0.18, cover);
	return clamp((n - thresh) / mix(0.12, 0.3, cover), 0.0, 1.0);
}

// Cumulus layer: returns premultiplied colour (rgb) and coverage (a).
vec4 clouds(vec3 d, vec3 light_dir, vec3 light_col, float t_hit, int light_steps) {
	vec3 p = vec3(0.0, EARTH_R + CAM_H, 0.0) + d * t_hit;
	vec2 uv = p.xz;
	float cover = cloud_cover;
	float dens = cloud_density(uv, cover);
	if (dens <= 0.001) {
		return vec4(0.0);
	}
	// Light march towards the sun across the layer.
	vec2 ldir = light_dir.xz / max(light_dir.y + 0.15, 0.12);
	float lsum = 0.0;
	for (int i = 1; i <= light_steps; i++) {
		lsum += cloud_density(uv + ldir * float(i) * 0.35, cover);
	}
	lsum *= 3.0 / float(max(light_steps, 1));
	float thick = mix(1.0, 3.5, cloud_dark);
	float light_t = exp(-lsum * 0.9 * thick);
	float powder = 1.0 - exp(-dens * 4.0);
	float mu = dot(d, light_dir);
	float ph = mix(phase_hg(mu, 0.65), phase_hg(mu, -0.15), 0.5) * 4.0 * PI;
	ph = max(ph, 0.6);
	vec3 direct = light_col * light_t * powder * ph * 0.9;
	// Ambient from the sky above and (dimmer) the ground below: cloud bases are darker.
	vec3 amb = sky_ambient * mix(1.05, 0.55, dens) * (1.0 - cloud_dark * 0.65) + light_col * 0.04;
	vec3 col = direct * (1.0 - cloud_dark * 0.75) + amb;
	// Lightning lights the clouds from inside.
	col += vec3(0.75, 0.8, 1.0) * flash * (0.4 + 2.5 * pow(max(dot(d, flash_dir), 0.0), 6.0)) * dens;
	// Oblique views look through more cloud.
	float od = dens * mix(6.0, 14.0, cover) / sqrt(max(d.y, 0.04) * 6.0 + 0.2);
	float a = 1.0 - exp(-od);
	return vec4(col * a, a);
}

vec4 cirrus_layer(vec3 d, vec3 light_dir, vec3 light_col) {
	float t = ray_sphere(EARTH_R + CAM_H, d.y, EARTH_R + CIRRUS_H);
	vec3 p = vec3(0.0, EARTH_R + CAM_H, 0.0) + d * t;
	vec2 uv = p.xz;
	// Stretched along the jet stream.
	vec2 q = vec2(uv.x * 0.35 + uv.y * 0.12, uv.y * 0.9 - uv.x * 0.2) + wind * TIME * 2.0;
	float n = texture(cloud_noise, q / 40.0 + vec2(0.5, 0.2)).r;
	float w = texture(cloud_noise, vec2(q.x / 9.0, q.y / 28.0)).r;
	float dens = clamp((n * 0.6 + w * 0.5 - 0.62) * 3.0, 0.0, 1.0) * cirrus;
	float mu = dot(d, light_dir);
	vec3 col = light_col * (0.35 + phase_hg(mu, 0.75) * 3.0) + sky_ambient * 0.7;
	float a = dens * 0.55 * smoothstep(0.0, 0.08, d.y);
	return vec4(col * a, a);
}

vec3 rainbow_col(vec3 d) {
	// Primary bow at 42 degrees and faint secondary at 51 around the antisolar point.
	float ang = degrees(acos(clamp(dot(d, -sun_dir), -1.0, 1.0)));
	vec3 col = vec3(0.0);
	float x = (ang - 40.6) / 1.9;  // 0 violet (inner) .. 1 red (outer)
	if (x > 0.0 && x < 1.0) {
		col += clamp(vec3(abs(x * 6.0 - 4.5) - 1.5, 2.0 - abs(x * 6.0 - 3.0), 2.0 - abs(x * 6.0 - 1.4)), 0.0, 1.0) * sin(x * PI);
	}
	float x2 = (53.5 - ang) / 2.6;
	if (x2 > 0.0 && x2 < 1.0) {
		col += clamp(vec3(abs(x2 * 6.0 - 4.5) - 1.5, 2.0 - abs(x2 * 6.0 - 3.0), 2.0 - abs(x2 * 6.0 - 1.4)), 0.0, 1.0) * sin(x2 * PI) * 0.35;
	}
	return col * smoothstep(0.0, 0.1, d.y);
}

vec3 stars(vec3 d) {
	vec3 sp = d * 280.0;
	vec3 cell = floor(sp);
	float r = n_hash13(cell);
	vec3 col = vec3(0.0);
	if (r < 0.07) {
		vec3 star_pos = cell + vec3(n_hash13(cell + 1.3), n_hash13(cell + 2.7), n_hash13(cell + 5.1));
		float tw = 0.65 + 0.35 * sin(TIME * (2.0 + r * 40.0) + r * 100.0);
		float mag = pow(n_hash13(cell + 9.1), 6.0) * 3.0 + 0.25;
		vec3 tint = mix(vec3(1.0, 0.82, 0.65), vec3(0.75, 0.85, 1.0), n_hash13(cell + 4.4));
		col = tint * smoothstep(0.38, 0.0, length(sp - star_pos)) * mag * tw;
	}
	// Milky way: a faint, mottled band across the sky.
	vec3 band_n = normalize(vec3(0.35, 0.25, 0.9));
	float band = exp(-pow(dot(d, band_n) / 0.18, 2.0));
	float mott = texture(cloud_noise, d.xz / (abs(d.y) + 0.6) * 1.7).r;
	col += vec3(0.55, 0.6, 0.75) * band * smoothstep(0.35, 0.8, mott) * 0.05;
	return col * smoothstep(-0.02, 0.15, d.y);
}

// Aurora: folded curtains of green light with violet hems, high in the sky.
vec3 aurora_col(vec3 d) {
	if (d.y < 0.02) {
		return vec3(0.0);
	}
	vec3 col = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		float h = 0.7 + float(i) * 0.25;           // curtain layer height (relative)
		vec2 p = d.xz / (d.y + 0.08) * h;
		float fold = texture(cloud_noise, vec2(p.x * 0.06 + TIME * 0.004 * (1.0 + float(i)), float(i) * 0.31)).r;
		float band = p.y * 0.35 + fold * 2.6 + sin(p.x * 0.25 + TIME * 0.05) * 0.6;
		float curtain = exp(-pow(fract(band) - 0.5, 2.0) * 60.0);
		float rays = 0.6 + 0.4 * texture(cloud_noise, vec2(p.x * 0.9, TIME * 0.02 + float(i))).r;
		float alt = smoothstep(0.02, 0.18, d.y) * (1.0 - smoothstep(0.55, 0.95, d.y));
		vec3 tint = mix(vec3(0.15, 1.0, 0.45), vec3(0.6, 0.25, 1.0), smoothstep(0.25, 0.7, d.y + fold * 0.2));
		col += tint * curtain * rays * alt * (0.55 - float(i) * 0.12);
	}
	return col * 0.09;
}

// Full sky radiance (no sun disc / stars): atmosphere, night glow, clouds.
vec4 sky_color(vec3 d, int samples, bool cheap) {
	vec3 dd = d;
	dd.y = max(d.y, 0.0) + 0.003;
	dd = normalize(dd);
	vec3 trans;
	vec3 col = atmosphere(dd, sun_dir, 1e9, samples, trans) * SUN_E;
	// Night: airglow + moonlit blue sky + moon aureole.
	float moon_up = smoothstep(-0.05, 0.2, moon_dir.y);
	vec3 night_sky = mix(vec3(0.010, 0.013, 0.022), vec3(0.0035, 0.005, 0.012), sqrt(dd.y));
	night_sky *= (0.4 + 0.6 * moon_up * moon_phase);
	float md = max(dot(dd, moon_dir), 0.0);
	night_sky += vec3(0.08, 0.1, 0.14) * (pow(md, 40.0) * 0.25 + pow(md, 400.0) * 0.6) * moon_phase * moon_up;
	col += night_sky * night;
	// Horizon murk from fog / rain.
	vec3 murk = mix(sky_ambient * 1.1, vec3(dot(col, vec3(0.3, 0.5, 0.2))), 0.4);
	col = mix(col, murk, haze * (1.0 - smoothstep(0.0, 0.5, dd.y)) * 0.8 + haze * 0.35);

	// Light source for the clouds: the sun by day, the moon at night.
	vec3 ldir = sun_dir.y > -0.08 ? sun_dir : moon_dir;
	vec3 lcol = sun_dir.y > -0.08 ? sun_light : vec3(0.05, 0.06, 0.09) * moon_phase * moon_up;
	float cov = 0.0;
	if (d.y > 0.0) {
		vec4 ci = cheap ? vec4(0.0) : cirrus_layer(dd, ldir, lcol);
		col = col * (1.0 - ci.a) + ci.rgb;
		float t_hit = ray_sphere(EARTH_R + CAM_H, dd.y, EARTH_R + CLOUD_H);
		vec4 cl = clouds(dd, ldir, lcol, t_hit, cheap ? 1 : 3);
		// Aerial perspective: distant clouds sink into the haze.
		float fade = exp(-t_hit / mix(55.0, 25.0, haze));
		cl *= fade;
		col = col * (1.0 - cl.a) + cl.rgb;
		cov = cl.a + (1.0 - cl.a) * ci.a * 0.5;
		col += rainbow_col(d) * rainbow * (1.0 - cl.a) * max(col, vec3(0.05)) * 0.6;
	}
	// Below the horizon: the haze darkens towards the unseen ground.
	if (d.y < 0.0) {
		col *= mix(1.0, 0.45, smoothstep(0.0, -0.25, d.y));
	}
	if (aurora > 0.001) {
		col += aurora_col(d) * aurora * night * (1.0 - cov * 0.8);
	}
	if (heat > 0.001) {
		// Bleached, shimmering heat haze towards the horizon.
		float lum = dot(col, vec3(0.3, 0.5, 0.2));
		col = mix(col, vec3(lum * 1.15, lum * 1.02, lum * 0.82), heat * 0.45 * (1.0 - smoothstep(0.0, 0.6, dd.y)));
	}
	if (embers > 0.001) {
		// Smoke from the crater, lit from below by fire.
		float smoke = texture(cloud_noise, d.xz / (abs(d.y) + 0.25) * 0.4 + vec2(TIME * 0.004, 0.0)).r;
		vec3 ember_sky = mix(vec3(0.05, 0.02, 0.015), vec3(0.45, 0.13, 0.04), smoothstep(0.5, 0.0, dd.y)) * (0.6 + smoke * 0.8);
		col = mix(col, ember_sky * (0.35 + 0.65 * (1.0 - night)), embers * 0.75);
	}
	return vec4(col * sky_energy, cov);
}

vec3 hell_sky(vec3 d) {
	float up = clamp(d.y, -0.3, 1.0);
	vec3 col = mix(vec3(0.16, 0.025, 0.008), vec3(0.025, 0.004, 0.003), smoothstep(-0.1, 0.6, up));
	float t = 0.6 / (abs(d.y) + 0.12);
	vec2 uv = d.xz * t;
	float n1 = texture(cloud_noise, uv * 0.35 + vec2(TIME * 0.006, TIME * 0.003)).r;
	float n2 = texture(cloud_noise, uv * 1.1 - vec2(TIME * 0.011, -TIME * 0.004)).r;
	float ash = smoothstep(0.35, 0.85, n1 * 0.7 + n2 * 0.4);
	// Clouds lit from below by the lava seas: bright undersides, dark tops.
	vec3 lit = vec3(0.55, 0.12, 0.03) * (0.4 + 0.6 * smoothstep(0.9, 0.2, up));
	col = mix(col, lit * (0.3 + n2 * 0.7), ash * 0.85);
	// Distant fiery glow at the horizon.
	col += vec3(0.35, 0.07, 0.015) * exp(-abs(d.y) * 9.0);
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	if (underworld > 0.5) {
		if (AT_CUBEMAP_PASS) {
			COLOR = mix(hell_sky(d), occluded_color, occlusion);
		} else if (AT_HALF_RES_PASS) {
			COLOR = hell_sky(d);
		} else {
			COLOR = HALF_RES_COLOR.rgb;
		}
	} else if (AT_CUBEMAP_PASS) {
		COLOR = mix(sky_color(d, 5, true).rgb, occluded_color, occlusion);   // lighting only: coarse is fine
	} else if (AT_HALF_RES_PASS) {
		vec4 s = sky_color(d, 8, false);
		COLOR = s.rgb;
		ALPHA = 1.0 - s.a;   // stored: how much of the sky behind the clouds shows through
	} else {
		vec3 col = HALF_RES_COLOR.rgb;
		float clear = HALF_RES_COLOR.a;
		// Sun disc with limb darkening, dimmed by the atmosphere and the clouds.
		float sd = dot(d, sun_dir);
		float sun_r = 0.0105;       // ~0.6 degrees, a touch larger than life
		float x = clamp((1.0 - sd) / (1.0 - cos(sun_r)), 0.0, 1.0);
		if (sd > cos(sun_r * 1.4)) {
			float disc = 1.0 - smoothstep(0.75, 1.0, x);
			float limb = 0.55 + 0.45 * sqrt(max(1.0 - x, 0.0));
			col += sun_light * disc * limb * 60.0 * clear * smoothstep(-0.02, 0.01, d.y) * sky_energy;
		}
		// Moon: phase-lit sphere with darker maria.
		float md = dot(d, moon_dir);
		float moon_r = 0.0125;
		if (md > cos(moon_r) && night > 0.01) {
			vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)) + 1e-5);
			vec3 up = cross(right, moon_dir);
			vec2 q = vec2(dot(d, right), dot(d, up)) / sin(moon_r);
			float zz = sqrt(max(1.0 - dot(q, q), 0.0));
			vec3 nrm = q.x * right + q.y * up - zz * moon_dir;   // faces the viewer
			// Phase angle a: lit fraction k = (1 + cos a) / 2; the light comes from the sun's side.
			vec3 s_perp = sun_dir - moon_dir * dot(sun_dir, moon_dir);
			s_perp = length(s_perp) > 1e-4 ? normalize(s_perp) : up;
			float ca = moon_phase * 2.0 - 1.0;
			vec3 sl = -moon_dir * ca + s_perp * sqrt(max(1.0 - ca * ca, 0.0));
			float lit = smoothstep(-0.04, 0.1, dot(nrm, sl));
			float maria = texture(cloud_noise, q * 0.35 + vec2(0.3, 0.6)).r;
			vec3 albedo = vec3(0.92, 0.9, 0.86) * mix(0.55, 1.0, smoothstep(0.35, 0.7, maria));
			float edge = smoothstep(1.0, 0.94, length(q));
			col += albedo * (lit * 2.2 + 0.015) * edge * clear * night;
		}
		if (meteors > 0.001 && night > 0.05 && d.y > 0.0) {
			// Shooting stars: a few slots, each flaring for a moment on a
			// random path, mostly radiating from one point of the sky.
			vec3 radiant = normalize(vec3(0.4, 0.75, -0.5));
			for (int i = 0; i < 6; i++) {
				float slot = floor(TIME * 0.35 + float(i) * 0.37);
				float t = fract(TIME * 0.35 + float(i) * 0.37);
				vec3 r = vec3(n_hash13(vec3(slot, float(i), 1.0)), n_hash13(vec3(slot, float(i), 2.0)), n_hash13(vec3(slot, float(i), 3.0)));
				if (r.x > meteors * 0.9) {
					continue;
				}
				vec3 start = normalize(radiant + (r - 0.5) * vec3(1.6, 0.6, 1.6));
				vec3 dir = normalize(start - radiant + vec3(0.0, -0.15, 0.0));
				float len = 0.12 + r.y * 0.18;
				vec3 head = normalize(start + dir * len * t);
				// Distance from d to the segment start..head on the sphere (small angles).
				vec3 a = start;
				vec3 b = head;
				vec3 ab = b - a;
				float k = clamp(dot(d - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
				float dist = length(d - (a + ab * k));
				float trail = smoothstep(0.0025, 0.0, dist) * k * k;
				float life = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.6, 1.0, t));
				col += vec3(0.85, 0.92, 1.0) * trail * life * 3.0 * clear;
			}
		}
		if (night > 0.01) {
			col += stars(d) * night * clear * (1.0 - haze);
		}
		COLOR = col;
	}
}
