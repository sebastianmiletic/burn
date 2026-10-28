shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Water and lava surfaces.
//
// Vertex input (world/voxel/chunk_mesher.gd, liquid surface) - keep in sync:
//   COLOR.rgb  block colour, COLOR.a legacy material class / 7
//   UV         side faces: position on the face; top faces: (water depth under
//              the corner in m, 0), 0 along the shore and on the shore skirt
//   UV2        (block id, skylight 0..1)
//   NORMAL     face normal (top faces sit at ChunkMesher.WATER_TOP above the block base)
//
// Water:
//  * Geometry: a sum of Gerstner waves. Every train has its own randomised
//    wavelength, direction (spread around the wind), phase, and a deep-water
//    dispersion speed with a little jitter, so the frequencies never line up
//    into a repeating pattern; each train's amplitude also rises and falls in
//    slow travelling groups ("sets"). Wind strength (weather) scales the
//    wavelengths and steepness; the open sea (at sea level) gets a long swell,
//    lakes a short chop, sheltered/underground water stays nearly still.
//  * Normals: the same trains analytically, plus short randomised chop and
//    drifting noise ripples (faded out where a pixel covers them: no aliasing).
//  * Depth (per vertex, from the mesher): the swell is full over deep water,
//    shoals (grows, its crests sharpen and lean) over 1-6 m, and dies out
//    along the shore so the surface never lifts off the beach.
//  * Shoreline: the mesher continues the surface one cell into the ground (a
//    skirt); the edge is where the smooth terrain rises through it, faded by
//    the depth behind the water with a noisy, breathing swash line.
//  * Foam: whitecaps where the Gerstner surface folds (Jacobian < 0) in wind,
//    crests breaking over the shallows, lines that roll in towards the shore,
//    and swash foam that runs up and back along the water's edge.
//  * Optics: own screen-space reflections (with the visible sky behind them)
//    falling back to an analytic sky from the sky controller (so dusk water
//    reflects the glowing horizon instead of going black), Fresnel (F0 0.02),
//    sun glitter, subsurface light through thin crests, refraction with
//    depth absorption and in-scattering, caustics on the bed seen through the
//    water, Snell's window and total internal reflection from below.
//  Biomes can tint water through the colour / absorption uniforms below.
// Lava: slowly drifting basalt crust plates over a molten flow, glowing seams,
// hot pulses, crust breaking up where the lava pours down vertical faces.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

// Water optics (parameters so biomes / oceans can tune them per material):
// colour of light scattered back out of the water, extinction per metre
// (red is absorbed first, so depth turns blue-green), shoreline foam.
uniform vec3 shallow_color : source_color = vec3(0.045, 0.085, 0.08);
uniform vec3 deep_color : source_color = vec3(0.012, 0.03, 0.04);
uniform vec3 absorption = vec3(0.42, 0.11, 0.08);
uniform float turbidity : hint_range(0.0, 2.0) = 0.35;   // in-scattering per metre
uniform float refraction = 0.035;
uniform float shore_foam : hint_range(0.0, 1.0) = 0.55;
// Light glowing through thin wave crests (subsurface scattering).
uniform vec3 scatter_color : source_color = vec3(0.06, 0.32, 0.26);
// Wave height multiplier (0 = a mirror-still pool, e.g. an oasis).
uniform float wave_scale : hint_range(0.0, 3.0) = 1.0;
// Water at or below this height is open sea (long swell); above it, lakes.
uniform float sea_level = 12.0;
uniform float caustics : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D refr_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float rain_amount;
// Set by SkyController: the sky as its shader draws it, and the sun.
global uniform vec3 sky_zenith_color;
global uniform vec3 sky_horizon_color;
global uniform vec3 sky_horizon_sun_color;
global uniform vec3 sun_direction;
global uniform vec3 sun_radiance;
// Dark-ocean regions (0..1): deeper, near-black blue-green, less transparent water.
global uniform float dark_ocean_amount;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec2 v_rest;       // undisplaced position on the water plane
varying float v_height;    // wave height at this vertex (m)
varying float v_calm;      // 0 still .. 1 full sea state
varying float v_sea;       // 1 open sea, 0 lake
varying float v_env;       // wave envelope from the water depth (0 at the shore)
varying float v_shoal;     // 0 deep water .. 1 shallows where the swell steepens
varying float v_amp;       // rough crest height of the local swell (m)
varying flat float v_block;
varying float v_sky;

const int LAVA = 20;
const int WAVES = 8;

// Sea state from the weather, the kind of water and its shelter.
void sea_state(float sea, out float lmax, out float steep) {
	float ws = clamp(wind_strength, 0.0, 1.0);
	// The open sea always carries some swell from far storms; lakes only chop.
	lmax = mix(mix(3.0, 8.0, ws), mix(16.0, 44.0, ws), sea);
	steep = mix(mix(0.026, 0.07, ws * ws), mix(0.034, 0.09, ws * ws), sea);
}

// The i-th Gerstner train: direction, wavenumber, amplitude, angular speed,
// phase. Hashes are fixed per index: the pattern is random but stable.
void train(int i, float lmax, float steep, out vec2 dir, out float k, out float amp, out float omega, out float phase) {
	float fi = float(i);
	float h1 = n_hash12(vec2(fi * 7.31, 1.7));
	float h2 = n_hash12(vec2(fi * 3.17, 9.2));
	float h3 = n_hash12(vec2(fi * 5.73, 4.4));
	float h4 = n_hash12(vec2(fi * 2.11, 6.6));
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	float spread = mix(2.2, 1.2, clamp(wind_strength, 0.0, 1.0));
	// Every fourth train is a cross swell from a quite different direction.
	float a = atan(wd.y, wd.x) + (h1 - 0.5) * spread + (i % 4 == 3 ? (h4 - 0.5) * 2.6 : 0.0);
	dir = vec2(cos(a), sin(a));
	float l = lmax * pow(0.67, fi) * (0.72 + 0.56 * h2);
	k = TAU / l;
	omega = sqrt(9.81 * k) * (0.93 + 0.14 * h3);
	amp = steep * (0.75 + 0.5 * h4) / k;
	phase = h3 * TAU + h1 * 17.0;
}

// Slow travelling wave groups: each train's amplitude swells and fades.
float group(vec2 p, vec2 dir, float k, float omega, float t, float fi) {
	vec2 gd = vec2(-dir.y, dir.x) * 0.35 + dir;
	float g = sin(dot(p, gd) * k * 0.11 - omega * 0.5 * 0.11 * t + fi * 2.39)
			+ 0.6 * sin(dot(p, vec2(dir.y, -dir.x)) * k * 0.067 + t * 0.031 * (1.0 + fi * 0.13) + fi * 4.1);
	return 0.62 + 0.38 * clamp(g * 0.62, -1.0, 1.0);
}

// Slow, large-scale phase warp: bends every train's crests into long curves
// that wander over ~100 m (no straight, endlessly parallel ridges). Two fields,
// shared out between the trains so they do not bend together.
vec2 crest_warp(vec2 p, float t) {
	vec2 q = p * 0.011 + vec2(t * 0.004, -t * 0.003);
	return vec2(n_value2(q), n_value2(q * 1.37 + vec2(5.3, 1.9))) * 5.0 - 2.5;
}

// Gerstner displacement of a rest position (x, y, z offsets). The mesh is a
// 1 m grid: trains shorter than ~3 m stay in the normals only. shoal sharpens
// the crests (more horizontal pinch) over shallow water.
vec3 gerstner(vec2 p, float t, float lmax, float steep, float scale, float shoal) {
	vec3 d = vec3(0.0);
	vec2 w = crest_warp(p, t);
	for (int i = 0; i < WAVES; i++) {
		vec2 dir;
		float k;
		float amp;
		float omega;
		float ph;
		train(i, lmax, steep, dir, k, amp, omega, ph);
		amp *= group(p, dir, k, omega, t, float(i)) * scale;
		amp *= 1.0 - smoothstep(TAU / 4.0, TAU / 2.2, k);
		float th = k * dot(dir, p) - omega * t + ph + (i % 2 == 0 ? w.x : w.y) * (0.6 + 0.12 * float(i));
		float q = 0.55 * (1.0 + shoal * 0.7) / (k * amp * float(WAVES) + 1e-4);   // choppiness, never loops
		q = min(q, 1.0);
		d.xz += dir * (q * amp * cos(th));
		d.y += amp * sin(th);
	}
	return d;
}

// Normal of the Gerstner sum (GPU Gems 1, ch. 1) plus its Jacobian (folding
// crests). lod: metres per pixel; trains finer than that fade out.
vec3 gerstner_normal(vec2 p, float t, float lmax, float steep, float scale, float shoal, float lod, out float jac) {
	vec3 n = vec3(0.0, 1.0, 0.0);
	jac = 1.0;
	vec2 w = crest_warp(p, t);
	for (int i = 0; i < WAVES; i++) {
		vec2 dir;
		float k;
		float amp;
		float omega;
		float ph;
		train(i, lmax, steep, dir, k, amp, omega, ph);
		amp *= group(p, dir, k, omega, t, float(i)) * scale;
		amp *= 1.0 - smoothstep(0.25, 0.9, k * lod * 0.16);
		float th = k * dot(dir, p) - omega * t + ph + (i % 2 == 0 ? w.x : w.y) * (0.6 + 0.12 * float(i));
		float q = min(0.55 * (1.0 + shoal * 0.7) / (k * amp * float(WAVES) + 1e-4), 1.0);
		float wa = k * amp;
		n.x -= dir.x * wa * cos(th);
		n.z -= dir.y * wa * cos(th);
		n.y -= q * wa * sin(th);
		jac -= q * wa * sin(th) * 1.6;
	}
	return n;
}

// Short wind chop: randomised small trains plus drifting noise ripples.
vec2 chop(vec2 p, float t, float lod, float strength) {
	vec2 g = vec2(0.0);
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	float ws = clamp(wind_strength, 0.0, 1.0);
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float h1 = n_hash12(vec2(fi * 4.7, 21.3));
		float h2 = n_hash12(vec2(fi * 8.9, 2.9));
		float a = atan(wd.y, wd.x) + (h1 - 0.5) * 3.4;
		vec2 dir = vec2(cos(a), sin(a));
		float l = mix(2.4, 0.28, fi / 6.0) * (0.8 + 0.4 * h2);
		float k = TAU / l;
		float amp = (0.05 + 0.06 * ws) / k * strength;
		amp *= 1.0 - smoothstep(0.3, 1.1, k * lod * 0.16);
		float th = k * dot(dir, p) - sqrt(9.81 * k) * t + h2 * TAU;
		g += dir * k * amp * cos(th);
	}
	// Aperiodic ripples (value-noise gradients drifting with the wind).
	float fade = 1.0 - smoothstep(0.04, 0.2, lod);
	if (fade > 0.0) {
		vec2 q = p * 1.9 - wd * t * 0.6;
		float e = 0.12;
		float n0 = n_value2(q);
		float nx = n_value2(q + vec2(e, 0.0));
		float nz = n_value2(q + vec2(0.0, e));
		vec2 q2 = p * 4.3 + vec2(wd.y, -wd.x) * t * 0.9;
		float m0 = n_value2(q2);
		float mx = n_value2(q2 + vec2(e, 0.0));
		float mz = n_value2(q2 + vec2(0.0, e));
		g += (vec2(nx - n0, nz - n0) * 0.07 + vec2(mx - m0, mz - m0) * 0.035) / e * (0.4 + ws) * fade * strength;
	}
	return g;
}

// Expanding rings where raindrops land. Returns a slope.
vec2 rain_ripples(vec2 p, float t, float amount) {
	vec2 g = vec2(0.0);
	if (amount <= 0.01) {
		return g;
	}
	for (int layer = 0; layer < 3; layer++) {
		vec2 q = p * 1.7 + vec2(float(layer) * 0.37, float(layer) * 0.71);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float h = n_hash12(cell + float(layer) * 13.1);
		if (n_hash12(cell * 1.7 + 4.2 + float(layer)) > amount) {
			continue;
		}
		vec2 c = vec2(0.5) + (vec2(h, fract(h * 7.31)) - 0.5) * 0.2;
		float phase = fract(t * 1.1 + h * 5.0);
		float r = phase * 0.42;
		vec2 to = f - c;
		float d = length(to);
		float x = (d - r) * 34.0;
		float ring = cos(clamp(x, -3.14159, 3.14159)) * 0.5 + 0.5;
		ring *= smoothstep(3.14159, 0.0, abs(x)) * (1.0 - phase) * (1.0 - phase);
		g += to / max(d, 1e-3) * ring * -sin(clamp(x, -3.14159, 3.14159)) * 0.9;
	}
	return g;
}

// Caustic web (light focused by the waves above), 0..~1.
float caustic(vec2 p, float t) {
	vec2 q = mod(p * 0.55, TAU) - 250.0;
	vec2 i = q;
	float c = 1.0;
	const float inten = 0.005;
	for (int n = 0; n < 4; n++) {
		float tt = t * 0.45 * (1.0 - (3.5 / float(n + 1)));
		i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / inten), q.y / (cos(i.y + tt) / inten)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 2.0);
}

// The sky as the sky controller sees it (horizon glow, zenith, the sun).
vec3 sky(vec3 dir) {
	float up = clamp(dir.y, 0.0, 1.0);
	vec2 sh = normalize(sun_direction.xz + vec2(1e-4));
	vec2 dh = normalize(dir.xz + vec2(1e-4));
	float toward = dot(sh, dh) * 0.5 + 0.5;
	vec3 hz = mix(sky_horizon_color, sky_horizon_sun_color, toward * toward);
	vec3 s = mix(hz, sky_zenith_color, pow(up, 0.55));
	float sd = max(dot(dir, sun_direction), 0.0);
	s += sun_radiance * (pow(sd, 12.0) * 0.08 + pow(sd, 400.0) * 0.6);
	if (dir.y < 0.0) {
		s = mix(s, hz * 0.35, smoothstep(0.0, -0.25, dir.y));
	}
	return s;
}

void vertex() {
	v_block = UV2.x;
	v_sky = UV2.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	int b = int(UV2.x + 0.5);
	v_rest = world.xz;
	v_height = 0.0;
	v_env = 0.0;
	v_shoal = 0.0;
	v_amp = 0.0;
	v_sea = 1.0 - smoothstep(sea_level + 0.5, sea_level + 2.5, world.y);
	v_calm = wave_scale * smoothstep(0.15, 0.85, v_sky) * mix(0.55, 1.0, v_sea);
	if (NORMAL.y > 0.5) {
		float t = TIME;
		if (b == LAVA) {
			world.y += (sin(t * 0.5 + world.x * 0.35) + sin(t * 0.37 + world.z * 0.29)) * 0.035;
		} else {
			float lmax;
			float steep;
			sea_state(v_sea, lmax, steep);
			// Depth under this vertex (mesher): nothing on the shore, the swell
			// building over the first metres, growing a little as it shoals
			// (Green's law) before it breaks, full over deep water.
			float h = UV.x;
			v_shoal = smoothstep(0.6, 2.0, h) * (1.0 - smoothstep(2.5, 7.0, h));
			v_env = smoothstep(0.0, 2.6, h) * (1.0 + 0.35 * v_shoal);
			vec3 d = gerstner(world.xz, t, lmax, steep, v_calm * v_env, v_shoal);
			world += d;
			v_height = d.y;
			v_amp = 1.6 * steep * lmax / TAU * v_calm * v_env;
		}
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	}
	v_world = world;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void lava(float t, out vec3 albedo, out vec3 emission, out float rough) {
	bool side = abs(v_wnormal.y) < 0.5;
	vec2 p = side ? vec2(dot(v_world.xz, vec2(-v_wnormal.z, v_wnormal.x)), v_world.y) : v_world.xz;
	// Flow: slow drift on pools, a steady pour down vertical faces.
	vec2 flow = side ? vec2(0.0, t * 0.6) : vec2(t * 0.05, t * 0.03);
	vec2 warp = vec2(n_value2(p * 0.4 + t * 0.03), n_value2(p * 0.4 + 5.2 - t * 0.02)) - 0.5;
	vec2 q = p * (side ? vec2(1.2, 0.5) : vec2(0.75)) + flow + warp * 1.2;
	vec3 v = n_voronoi2(q);
	float seam = v.y - v.x;                       // 0 on a crack between plates
	float heat = n_fbm2(p * 0.25 + vec2(t * 0.04, -t * 0.03));
	float pulse = 0.75 + 0.25 * sin(t * 1.3 + heat * 9.0);
	// Plates cool to dark basalt in their centres; the seams stay molten.
	float crust = smoothstep(0.06, 0.35, seam) * smoothstep(0.25, 0.7, heat + n_hash12(vec2(v.z)) * 0.35);
	if (side) {
		crust *= 0.35;   // pouring lava breaks the crust apart
	}
	// Kept below the tonemapper's white point: molten rock reads orange with
	// yellow seams instead of desaturating to a white sheet (and SDFGI does not
	// flood whole caverns with its light).
	vec3 molten = mix(vec3(1.0, 0.22, 0.02), vec3(1.0, 0.55, 0.14), smoothstep(0.3, 0.9, heat));
	vec3 hot = molten * (1.25 + 1.5 * smoothstep(0.12, 0.0, seam)) * pulse;
	vec3 cool = vec3(0.32, 0.06, 0.02) * (0.4 + 0.6 * smoothstep(0.35, 0.05, seam));
	emission = mix(hot, cool, crust);
	albedo = mix(vec3(0.08, 0.03, 0.02), vec3(0.05, 0.045, 0.045), crust);
	rough = mix(0.5, 0.9, crust);
}

// Nothing but sky behind this screen point (reverse-Z clears to 0).
bool is_sky(vec2 uv) {
	return textureLod(depth_tex, uv, 0.0).r <= 1e-7;
}

// View-space position of the opaque scene behind a screen point.
vec3 scene_view_pos(vec2 uv, mat4 inv_proj) {
	float d = max(textureLod(depth_tex, uv, 0.0).r, 1e-7);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
#endif
	vec4 view = inv_proj * ndc;
	return view.xyz / view.w;
}

// Screen-space reflection: march the reflected ray against the depth buffer.
// Returns the colour and how much of it is a confident hit (0..1).
vec4 ssr(vec3 origin, vec3 dir, mat4 proj, mat4 inv_proj) {
	float dist = 0.25;
	vec3 prev = origin;
	for (int i = 0; i < 22; i++) {
		vec3 p = origin + dir * dist;
		vec4 c = proj * vec4(p, 1.0);
		if (c.w <= 0.0) {
			break;
		}
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		vec3 s = scene_view_pos(uv, inv_proj);
		float behind = s.z - p.z;    // > 0: the ray went behind the scene
		if (behind > 0.0 && behind < 0.6 + dist * 0.12 && !is_sky(uv)) {
			// Refine between the last two samples.
			vec3 a = prev;
			vec3 b = p;
			for (int r = 0; r < 4; r++) {
				vec3 m = (a + b) * 0.5;
				vec4 mc = proj * vec4(m, 1.0);
				vec2 muv = mc.xy / mc.w * 0.5 + 0.5;
				if (scene_view_pos(muv, inv_proj).z - m.z > 0.0) {
					b = m;
				} else {
					a = m;
				}
			}
			vec4 bc = proj * vec4(b, 1.0);
			vec2 huv = bc.xy / bc.w * 0.5 + 0.5;
			vec2 e = smoothstep(vec2(0.0), vec2(0.08), huv) * smoothstep(vec2(1.0), vec2(0.92), huv);
			float conf = e.x * e.y * (1.0 - smoothstep(0.5, 1.0, float(i) / 22.0));
			return vec4(textureLod(refr_tex, huv, 0.0).rgb, conf);
		}
		prev = p;
		dist *= 1.32;
	}
	return vec4(0.0);
}

// Metres of water between the surface fragment and the scene behind it (0 when
// the scene sample is in front of the water).
float water_thickness(vec2 uv, vec3 vertex, mat4 inv_proj) {
	return max(length(scene_view_pos(uv, inv_proj)) - length(vertex), 0.0);
}

void fragment() {
	int b = int(v_block + 0.5);
	float t = TIME;
	if (b == LAVA) {
		vec3 albedo;
		vec3 emission;
		float rough;
		lava(t, albedo, emission, rough);
		ALBEDO = albedo;
		EMISSION = emission;
		ROUGHNESS = ascii_roughness(rough, ASCII_EMISSIVE);
	} else {
		vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - v_world);
		float lod = length(fwidth(v_world.xz));
		bool side = abs(v_wnormal.y) < 0.5;
		bool top = v_wnormal.y > 0.5;
		vec3 n = v_wnormal;
		float foam = 0.0;
		float jac = 1.0;
		vec2 p = v_rest;
		float day = clamp(sun_direction.y * 6.0 + 0.3, 0.0, 1.0);
		if (side) {
			// A falling sheet: streaks race downwards, broken by foam.
			vec2 sp = vec2(dot(v_world.xz, vec2(-v_wnormal.z, v_wnormal.x)), v_world.y);
			vec2 q = vec2(sp.x * 2.5, sp.y * 0.6 + t * 2.4);
			float s = n_value2(q);
			float e = 0.08;
			float sx = n_value2(q + vec2(e, 0.0)) - s;
			float sy = n_value2(q + vec2(0.0, e)) - s;
			vec3 tangent = normalize(cross(v_wnormal, vec3(0.0, 1.0, 0.0)));
			n = normalize(v_wnormal + tangent * sx / e * 0.25 + vec3(0.0, sy / e * 0.1, 0.0));
			foam = smoothstep(0.55, 0.85, n_value2(vec2(sp.x * 3.0, sp.y * 1.2 + t * 3.0)) * 0.6 + s * 0.4) * 0.8;
		} else {
			float lmax;
			float steep;
			sea_state(v_sea, lmax, steep);
			// Even the calm water at the very edge keeps a little relief.
			vec3 gn = gerstner_normal(p, t, lmax, steep, v_calm * max(v_env, 0.25), v_shoal, lod, jac);
			vec2 g = chop(p, t, lod, mix(0.25, 1.0, v_calm / max(wave_scale, 1e-3)) * min(wave_scale, 1.5));
			g += rain_ripples(p, t, rain_amount) * (1.0 - smoothstep(0.03, 0.12, lod));
			n = normalize(vec3(gn.x - g.x, gn.y, gn.z - g.y));
			// Whitecaps where crests fold over in a strong wind, streaked downwind.
			float ws = clamp(wind_strength, 0.0, 1.0);
			if (ws > 0.4) {
				vec2 wd = normalize(wind_dir + 1e-4);
				vec2 sp = vec2(dot(p, wd) * 0.35, dot(p, vec2(-wd.y, wd.x))) * 0.9;
				float tex = n_fbm2(sp * 1.3 - vec2(t * 0.25, 0.0));
				float fold = smoothstep(0.75, 0.15, jac + (tex - 0.5) * 0.6);
				foam = fold * smoothstep(0.4, 0.95, ws) * smoothstep(0.35, 0.65, tex) * v_calm;
				// Wind tears the tops off the highest crests of each wave set.
				if (v_amp > 0.03) {
					float cap = smoothstep(0.4, 0.85, v_height / v_amp) * smoothstep(0.5, 1.0, ws);
					foam = max(foam, cap * smoothstep(0.3, 0.6, tex + cap * 0.2) * v_calm);
				}
			}
			// Shoaling crests spill over: foam on the leading face of the
			// highest crests where the swell runs into shallow water.
			if (v_amp > 0.03 && v_shoal * v_sea > 0.01) {
				float c = v_height / v_amp;
				float spill = smoothstep(0.35, 0.8, c) * v_shoal * v_sea;
				float tex2 = n_fbm2(p * 1.6 + vec2(t * 0.35, -t * 0.2));
				foam = max(foam, spill * smoothstep(0.3, 0.6, tex2 + spill * 0.25) * (0.5 + 0.5 * clamp(wind_strength, 0.0, 1.0)));
			}
		}
		// Body colour: light scattered back out of the water. Looking straight
		// down you see deeper (darker, greener); out of the sky light it is dark.
		float facing = clamp(dot(n, view_dir_world), 0.0, 1.0);
		float dark = clamp(dark_ocean_amount, 0.0, 1.0);
		vec3 sh_col = mix(shallow_color, vec3(0.008, 0.026, 0.024), dark);
		vec3 dp_col = mix(deep_color, vec3(0.002, 0.008, 0.009), dark);
		vec3 absorb = absorption * mix(1.0, 3.2, dark);
		float turb = mix(turbidity, 1.4, dark);
		vec3 body = mix(sh_col, dp_col, facing) * (0.35 + 0.65 * v_sky);
		vec3 albedo = body;
		vec3 emission = vec3(0.0);
		bool from_above = top && CAMERA_POSITION_WORLD.y > v_world.y - 0.05;
		vec3 nv = normalize((VIEW_MATRIX * vec4(top && !from_above ? -n : n, 0.0)).xyz);
		if (from_above) {
			// What lies under the water, bent by the waves, absorbed and
			// scattered over the distance light travels through it.
			float thick = water_thickness(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX);
			vec2 off = nv.xy * refraction * clamp(thick, 0.0, 1.5) * 1.4;
			// No offset off the screen's edges (clamped samples smear).
			vec2 border = smoothstep(vec2(0.0), vec2(0.08), SCREEN_UV) * smoothstep(vec2(1.0), vec2(0.92), SCREEN_UV);
			off *= border.x * border.y;
			vec3 bed_v = scene_view_pos(SCREEN_UV + off, INV_PROJECTION_MATRIX);
			float thick_r = max(length(bed_v) - length(VERTEX), 0.0);
			vec2 uv = SCREEN_UV + off;
			if (thick_r <= 0.0) {
				uv = SCREEN_UV;   // the offset hit something in front of the water
				thick_r = thick;
				bed_v = scene_view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
			}
			vec3 bed = (INV_VIEW_MATRIX * vec4(bed_v, 1.0)).xyz;
			float depth = max(v_world.y - bed.y, 0.0);
			if (is_sky(uv)) {
				depth = 60.0;   // open sea beyond the streamed bed
				thick_r = 60.0;
			}
			float path = thick_r + depth;   // down to the bed and back up for its light
			vec3 trans = exp(-absorb * path * 0.5);
			vec3 under = textureLod(refr_tex, uv, clamp(path * 0.15, 0.0, 3.0)).rgb;
			// Caustics on the bed, fading with depth and out of the sun.
			float cst = caustic(bed.xz + n.xz * 0.6, t) * caustics * exp(-depth * 0.22) * smoothstep(0.02, 0.6, depth);
			under *= 1.0 + cst * 1.6 * day * v_sky * v_calm / max(wave_scale, 0.3);
			float scatter = 1.0 - exp(-turb * path);
			// Shallows: waves steepen and break in lines rolling up the beach,
			// with a fringe of foam where the water meets the shore.
			float shore = 1.0 - smoothstep(0.0, 2.4, depth);
			float wobble = n_value2(v_world.xz * 0.45 + vec2(t * 0.05, 0.0)) * 3.0;
			float band = sin(depth * 4.2 - t * 1.25 + wobble);
			// Breakers belong to the sea (and grow with the wind), not to ponds.
			float lines = smoothstep(0.72, 0.97, band) * shore * smoothstep(0.05, 0.5, depth) * v_calm * v_sea * (0.45 + 0.55 * clamp(wind_strength, 0.0, 1.0));
			float edge = 1.0 - smoothstep(0.0, 0.16, min(depth, thick));
			float speck = n_fbm2(v_world.xz * 2.4 + vec2(t * 0.2, -t * 0.15));
			// Swash: a foam line that runs up the beach and slides back, out of
			// step along the shore, as each wave set arrives.
			float sw_phase = t * 0.55 + n_value2(v_world.xz * 0.08) * 6.0;
			float sw_d = (0.5 + 0.5 * sin(sw_phase)) * 0.3 * (0.4 + 0.6 * v_sea);
			float swash = exp(-abs(min(depth, thick) - sw_d) * 14.0) * smoothstep(0.25, 0.6, speck + 0.2) * (0.5 + 0.5 * v_sea);
			float sf = shore_foam * (lines * smoothstep(0.35, 0.6, speck) + edge * 0.7 * smoothstep(0.4, 0.62, speck + edge * 0.15) + swash * 0.8);
			foam = max(foam, clamp(sf, 0.0, 1.0));
			// Steeper normals over the shallows (shoaling), calmer right at the edge.
			n = normalize(mix(n, vec3(0.0, 1.0, 0.0), edge * 0.6));
			// Fresnel on a smoothed normal: small ripples tilt the highlights,
			// not the whole balance of reflection and transparency.
			float ndv = clamp(dot(normalize(mix(n, vec3(0.0, 1.0, 0.0), 0.55)), view_dir_world), 0.0, 1.0);
			float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
			// Reflection: screen-space hits over the sky behind them.
			vec3 rd = reflect(-view_dir_world, n);
			rd.y = abs(rd.y) * 0.95 + 0.05 * length(rd.xz);
			rd = normalize(rd);
			vec3 refl = sky(rd);
			vec3 rd_v = normalize((VIEW_MATRIX * vec4(rd, 0.0)).xyz);
			// The real sky where it is on screen (clouds, sun disc).
			vec4 far_c = PROJECTION_MATRIX * vec4(VERTEX + rd_v * 2000.0, 1.0);
			if (far_c.w > 0.0) {
				vec2 fuv = far_c.xy / far_c.w * 0.5 + 0.5;
				if (fuv.x > 0.0 && fuv.x < 1.0 && fuv.y > 0.0 && fuv.y < 1.0 && is_sky(fuv)) {
					vec2 e = smoothstep(vec2(0.0), vec2(0.1), fuv) * smoothstep(vec2(1.0), vec2(0.9), fuv);
					refl = mix(refl, textureLod(refr_tex, fuv, 1.0).rgb, e.x * e.y * 0.85);
				}
			}
			vec4 hit = ssr(VERTEX, rd_v, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
			refl = mix(refl, hit.rgb, hit.a);
			// Sky light reaches sheltered water less (overhangs, caves).
			refl *= mix(0.25, 1.0, v_sky);
			// Sun glitter: a tight highlight on the detailed normal plus
			// sparkles where a facet catches the sun.
			vec3 h = normalize(view_dir_world + sun_direction);
			float nh = max(dot(n, h), 0.0);
			float spec = pow(nh, 900.0) * 60.0 + pow(nh, 120.0) * 1.2;
			vec2 cell = floor(v_world.xz * 9.0);
			float sparkle = step(0.985, n_hash12(cell + floor(t * 7.0) * 0.37)) * pow(nh, 40.0) * 14.0 * (1.0 - smoothstep(0.03, 0.15, lod));
			vec3 sun_spec = sun_radiance * (spec + sparkle) * fres * 5.0 * smoothstep(0.4, 0.9, v_sky);
			// Subsurface: sunlight through thin crests seen against the sun.
			float crest = clamp(v_height / 0.25 + 0.35, 0.0, 1.0);
			float back = pow(clamp(dot(-view_dir_world, -sun_direction) * 0.5 + 0.5 + 0.0, 0.0, 1.0), 4.0);
			float back2 = pow(clamp(dot(view_dir_world.xz, -sun_direction.xz) * 0.5 + 0.5, 0.0, 1.0), 3.0);
			vec3 sss = scatter_color * (1.0 - dark * 0.8) * sun_radiance * crest * (back * 0.6 + back2 * 0.4) * (1.0 - ndv * 0.5) * 0.35 * v_calm * v_sky;
			emission = under * trans * (1.0 - fres) + refl * fres + sun_spec + sss;
			emission *= 1.0 - foam;
			albedo = body * scatter;
			// The shoreline fades out along the terrain contour (the skirt
			// carries the surface over the ground), with a ragged wet edge.
			float rag = n_value2(v_world.xz * 1.3 + vec2(t * 0.04, 0.0)) * 0.12;
			ALPHA = smoothstep(0.0, 0.1 + rag, min(depth, thick));
		} else if (top) {
			// From below: Snell's window shows the world above, outside it the
			// surface mirrors the dark water (total internal reflection).
			vec3 nd = -n;   // facing down, into the water
			vec3 incident = -view_dir_world;
			vec3 tr = refract(incident, -nd, 1.0 / 1.33);
			float cosi = clamp(dot(view_dir_world, nd), 0.0, 1.0);
			vec3 water_light = scatter_color * (sky_zenith_color * 0.6 + sun_radiance * 0.15) * v_sky;
			if (dot(tr, tr) < 0.01) {
				emission = water_light * 0.5;
			} else {
				float f = 0.02 + 0.98 * pow(1.0 - cosi, 5.0);
				vec2 uv = SCREEN_UV + nv.xy * 0.04;
				vec3 above = textureLod(refr_tex, uv, 0.0).rgb;
				if (is_sky(uv)) {
					above = sky(tr);
				}
				float window = smoothstep(0.0, 0.12, cosi - 0.66);
				emission = mix(water_light * 0.5, above * (1.0 - f), window);
			}
			albedo = vec3(0.0);
		} else if (side) {
			emission = sky(reflect(-view_dir_world, n)) * 0.25 * v_sky;
		}
		ALBEDO = mix(albedo, vec3(0.8, 0.83, 0.85), foam);
		// Foam scatters the sky light too (it never goes black under a storm sky).
		EMISSION = emission + foam * (sky_zenith_color * 0.35 + sky_horizon_color * 0.25) * mix(0.3, 1.0, v_sky);
		NORMAL = normalize((VIEW_MATRIX * vec4(top && !from_above ? -n : n, 0.0)).xyz);
		// Reflections are the shader's own (SSR + sky, above): no engine IBL.
		SPECULAR = mix(0.0, 0.1, foam);
		ROUGHNESS = ascii_roughness(mix(0.08, 0.7, foam), ASCII_LIQUID);
		AO = mix(1.0, v_sky, 0.8);
		AO_LIGHT_AFFECT = 0.0;
	}
}
