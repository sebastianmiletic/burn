shader_type spatial;
render_mode cull_disabled;
// Water and lava surfaces. Drawn opaque so the ASCII pass sees them: water is
// tagged LIQUID (animated ~ - = glyphs), lava EMISSIVE (passed through and
// glowing).
//
// Vertex input (world/voxel/chunk_mesher.gd, liquid surface) - keep in sync:
//   COLOR.rgb  block colour, COLOR.a ASCII class / 7
//   UV         position on the face
//   UV2        (block id, skylight 0..1)
//   NORMAL     face normal (top faces are lowered by 0.12 by the mesher)
//
// Water: wind-driven layered waves (normals from analytic wave derivatives
// plus fine noise), physically based Fresnel against the sky / SSR (F0 0.02),
// body colour that deepens with view angle and darkens out of the sky light,
// whitecaps in strong wind, rain ripples (global rain_amount), and falling
// foam-streaked sheets on the vertical faces (waterfalls, spills).
// Lava: slowly drifting basalt crust plates over a molten flow, glowing seams,
// hot pulses, crust breaking up where the lava pours down vertical faces.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float rain_amount;

varying vec3 v_world;
varying vec3 v_wnormal;
varying flat float v_block;
varying float v_sky;

const int LAVA = 20;

// Directional wave train: returns height and adds its slope to `grad`.
// lod: size of a pixel on the surface (m); trains too fine for the screen
// fade out instead of aliasing into noise.
float wave(vec2 p, vec2 dir, float freq, float speed, float amp, float t, float lod, inout vec2 grad) {
	amp *= 1.0 - smoothstep(0.35, 1.2, freq * lod);
	float ph = dot(p, dir) * freq + t * speed;
	grad += dir * freq * amp * cos(ph);
	return amp * sin(ph);
}

vec2 water_waves(vec2 p, float t, float calm, float lod) {
	// A spectrum of directional wave trains around the wind direction (no
	// noise lookups: sines are far cheaper than fbm on large water surfaces).
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	vec2 wp = vec2(-wd.y, wd.x);
	float ws = clamp(wind_strength, 0.0, 1.0);
	float a = mix(0.012, 0.05, ws) * calm;
	vec2 g = vec2(0.0);
	wave(p, wd, 0.9, 1.6, a, t, lod, g);
	wave(p, normalize(wd + wp * 0.6), 1.7, 2.3, a * 0.6, t, lod, g);
	wave(p, normalize(wd - wp * 0.7), 2.6, 2.9, a * 0.45, t, lod, g);
	wave(p, normalize(wd * 0.3 + wp), 4.1, 3.7, a * 0.25, t, lod, g);
	wave(p, normalize(-wp + wd * 0.2), 6.3, 4.6, a * 0.18, t, lod, g);
	// Short capillary ripples: high-frequency trains in scattered directions,
	// their phases warped by the long waves so they never form a grid.
	float warp = dot(g, vec2(7.0, 5.0));
	float c = (0.006 + 0.01 * ws) * calm;
	wave(p + warp, normalize(wd + wp * 1.7), 9.7, 6.1, c, t, lod, g);
	wave(p - warp, normalize(wd - wp * 1.3), 12.9, 7.3, c * 0.8, t, lod, g);
	wave(p + warp * 0.5, normalize(-wd + wp * 0.4), 15.3, 8.2, c * 0.6, t, lod, g);
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

void vertex() {
	v_block = UV2.x;
	v_sky = UV2.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	int b = int(UV2.x + 0.5);
	if (NORMAL.y > 0.5) {
		float t = TIME;
		if (b == LAVA) {
			world.y += (sin(t * 0.5 + world.x * 0.35) + sin(t * 0.37 + world.z * 0.29)) * 0.035;
		} else {
			vec2 wd = normalize(wind_dir + vec2(1e-4));
			float a = mix(0.025, 0.08, clamp(wind_strength, 0.0, 1.0));
			world.y += sin(dot(world.xz, wd) * 0.9 + t * 1.6) * a + sin(dot(world.xz, vec2(-wd.y, wd.x)) * 0.6 + t * 1.1) * a * 0.5;
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
	vec3 molten = mix(vec3(1.0, 0.28, 0.03), vec3(1.0, 0.72, 0.28), smoothstep(0.3, 0.9, heat));
	vec3 hot = molten * (3.2 + 2.5 * smoothstep(0.12, 0.0, seam)) * pulse;
	vec3 cool = vec3(0.32, 0.06, 0.02) * (0.4 + 0.6 * smoothstep(0.35, 0.05, seam));
	emission = mix(hot, cool, crust);
	albedo = mix(vec3(0.08, 0.03, 0.02), vec3(0.05, 0.045, 0.045), crust);
	rough = mix(0.5, 0.9, crust);
}

void water(float t, vec3 view_dir_world, float lod, out vec3 n_out, out vec3 albedo, out float foam_out) {
	bool top = v_wnormal.y > 0.5;
	bool side = abs(v_wnormal.y) < 0.5;
	vec3 n = v_wnormal;
	float foam = 0.0;
	if (side) {
		// A falling sheet: streaks race downwards, broken by foam.
		vec2 p = vec2(dot(v_world.xz, vec2(-v_wnormal.z, v_wnormal.x)), v_world.y);
		vec2 q = vec2(p.x * 2.5, p.y * 0.6 + t * 2.4);
		float s = n_value2(q);
		float e = 0.08;
		float sx = n_value2(q + vec2(e, 0.0)) - s;
		float sy = n_value2(q + vec2(0.0, e)) - s;
		vec3 tangent = normalize(cross(v_wnormal, vec3(0.0, 1.0, 0.0)));
		n = normalize(v_wnormal + tangent * sx / e * 0.25 + vec3(0.0, sy / e * 0.1, 0.0));
		foam = smoothstep(0.55, 0.85, n_value2(vec2(p.x * 3.0, p.y * 1.2 + t * 3.0)) * 0.6 + s * 0.4) * 0.8;
	} else {
		vec2 p = v_world.xz;
		vec2 g = water_waves(p, t, 1.0, lod);
		g += rain_ripples(p, t, rain_amount) * (1.0 - smoothstep(0.03, 0.12, lod));
		n = normalize(vec3(-g.x, 1.0, -g.y));
		if (!top) {
			n = -n;
		}
		// Whitecaps in strong wind, drifting with it.
		if (wind_strength > 0.55) {
			float caps = n_fbm2(p * 0.6 - normalize(wind_dir + 1e-4) * t * 0.8);
			foam = smoothstep(0.78 - wind_strength * 0.15, 0.95, caps) * smoothstep(0.55, 1.0, wind_strength) * 0.7;
		}
	}
	n_out = n;
	foam_out = foam;
	// Body colour: light scattered back out of the water. Looking straight
	// down you see deeper (darker, greener); out of the sky light it is dark.
	float facing = clamp(dot(n, view_dir_world), 0.0, 1.0);
	vec3 shallow = vec3(0.045, 0.085, 0.08);
	vec3 deep = vec3(0.012, 0.03, 0.04);
	vec3 body = mix(shallow, deep, facing) * (0.35 + 0.65 * v_sky);
	albedo = mix(body, vec3(0.75, 0.78, 0.8), foam);
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
		vec3 n;
		vec3 albedo;
		float foam;
		water(t, view_dir_world, lod, n, albedo, foam);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		ALBEDO = albedo;
		SPECULAR = mix(0.25, 0.05, foam);        // F0 = 0.02, as real water
		ROUGHNESS = ascii_roughness(mix(0.03, 0.6, foam), ASCII_LIQUID);
		AO = mix(1.0, v_sky, 0.8);
		AO_LIGHT_AFFECT = 0.0;
	}
}
