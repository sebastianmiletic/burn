shader_type spatial;
render_mode cull_back;
// Smooth terrain (SmoothMesher output). Per-triangle material blending:
//   CUSTOM0.rgb  material codes of the triangle's three corners
//   COLOR.rgb    barycentric selector, COLOR.a ambient occlusion
//   UV2.x        skylight
// Each material code indexes the tables below (filled by TerrainTextures):
//   mat_a    = (albedo layer, cliff layer, tiles per metre, roughness multiplier)
//   mat_tint = (tint rgb, ASCII class)
//   mat_ore  = (ore/vein colour rgb, amount)
//   mat_emit = (emission rgb, metallic of the veins)
// Textures are CC0 PBR sets (Poly Haven) packed into two texture arrays:
// albedo (rgb) and normal (xy normal, z roughness, w height).

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform float wetness;
global uniform float snow_cover;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 mat_a[128];
uniform vec4 mat_tint[128];
uniform vec4 mat_ore[128];
uniform vec4 mat_emit[128];
uniform float cave_darkness : hint_range(0.0, 1.0) = 1.0;
uniform float snow_layer = 6.0;
uniform float macro_strength = 0.22;

varying vec3 v_world;
varying vec3 v_wn;
varying vec3 v_codes;
varying float v_sky;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_codes = CUSTOM0.rgb;
	v_sky = UV2.x;
}

// Triplanar sample of one layer with whiteout normal blending.
// Returns albedo.rgb + height in .a; world normal and roughness through out params.
vec4 tri(float layer, float scale, vec3 p, vec3 nw, vec3 bw, out vec3 n_out, out float rough) {
	// UDN blending: each plane's tangent normal perturbs the geometric normal
	// along the world axes its texture u / v (image up) run along.
	vec4 alb = vec4(0.0);
	vec3 nsum = vec3(0.0);
	rough = 0.0;
	if (bw.x > 0.0) {
		float s = sign(nw.x);
		vec2 uv = vec2(p.z * s, -p.y) * scale;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(normal_tex, vec3(uv, layer));
		vec2 tn = t.xy * 2.0 - 1.0;
		nsum += vec3(nw.x, nw.y + tn.y, nw.z + tn.x * s) * bw.x;
		alb += vec4(a.rgb, t.a) * bw.x;
		rough += t.z * bw.x;
	}
	if (bw.y > 0.0) {
		vec2 uv = p.xz * scale;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(normal_tex, vec3(uv, layer));
		vec2 tn = t.xy * 2.0 - 1.0;
		nsum += vec3(nw.x + tn.x, nw.y, nw.z - tn.y) * bw.y;
		alb += vec4(a.rgb, t.a) * bw.y;
		rough += t.z * bw.y;
	}
	if (bw.z > 0.0) {
		float s = sign(nw.z);
		vec2 uv = vec2(-p.x * s, -p.y) * scale;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(normal_tex, vec3(uv, layer));
		vec2 tn = t.xy * 2.0 - 1.0;
		nsum += vec3(nw.x - tn.x * s, nw.y + tn.y, nw.z) * bw.z;
		alb += vec4(a.rgb, t.a) * bw.z;
		rough += t.z * bw.z;
	}
	n_out = normalize(nsum);
	return alb;
}

struct Mat {
	vec3 albedo;
	float height;
	vec3 n;
	float rough;
	vec3 emit;
	float metal;
	float cls;
};

Mat sample_mat(int code, vec3 p, vec3 nw, vec3 bw, float macro) {
	vec4 a = mat_a[code];
	vec4 tint = mat_tint[code];
	Mat m;
	vec3 n;
	float r;
	vec4 alb = tri(a.x, a.z, p, nw, bw, n, r);
	// Steep slopes show the cliff layer (rock under grass, dirt banks...).
	float cliff = (a.y != a.x) ? smoothstep(0.78, 0.5, nw.y + (alb.a - 0.5) * 0.25) : 0.0;
	if (cliff > 0.01) {
		vec3 n2;
		float r2;
		vec4 alb2 = tri(a.y, a.z * 0.8, p, nw, bw, n2, r2);
		alb = mix(alb, alb2, cliff);
		n = normalize(mix(n, n2, cliff));
		r = mix(r, r2, cliff);
	}
	m.albedo = alb.rgb * tint.rgb * (1.0 + (macro - 0.5) * macro_strength * 2.0);
	m.height = alb.a;
	m.n = n;
	m.rough = clamp(r * a.w, 0.04, 1.0);
	m.cls = tint.a;
	// Ore veins and gem pockets: clustered speckles of the ore colour.
	vec4 ore = mat_ore[code];
	vec4 em = mat_emit[code];
	m.emit = vec3(0.0);
	m.metal = 0.0;
	if (ore.a > 0.0) {
		float v1 = n_value3(p * 3.1);
		float v2 = n_value3(p * 9.0 + 7.3);
		float vein = smoothstep(0.62 - ore.a * 0.25, 0.7 - ore.a * 0.25, v1 * 0.7 + v2 * 0.3);
		m.albedo = mix(m.albedo, ore.rgb * (0.75 + v2 * 0.5), vein);
		m.rough = mix(m.rough, 0.28, vein * em.a);
		m.metal = vein * em.a;
		m.emit = em.rgb * vein;
		m.height = mix(m.height, 0.8, vein);
	} else {
		m.emit = em.rgb * smoothstep(0.35, 0.85, n_value3(p * 2.3 + vec3(TIME * 0.05)));
	}
	return m;
}

void fragment() {
	vec3 p = v_world;
	vec3 nw = normalize(v_wn);
	// Sharp triplanar weights, small planes skipped.
	float dist = length(VERTEX);
	vec3 bw = pow(abs(nw), vec3(6.0));
	bw /= (bw.x + bw.y + bw.z);
	if (dist > 55.0) {
		// Far away a single projection is indistinguishable and a third of the cost.
		bw = (bw.y >= bw.x && bw.y >= bw.z) ? vec3(0, 1, 0) : (bw.x >= bw.z ? vec3(1, 0, 0) : vec3(0, 0, 1));
	} else {
		bw = max(bw - 0.03, 0.0);
		bw /= (bw.x + bw.y + bw.z);
	}
	float macro = n_fbm2(p.xz * 0.018) * 0.7 + n_value2(p.xz * 0.11) * 0.3;

	int c0 = int(v_codes.x + 0.5);
	int c1 = int(v_codes.y + 0.5);
	int c2 = int(v_codes.z + 0.5);
	vec3 bary = COLOR.rgb;
	// Merge corners that share a material.
	float w0 = bary.x + (c1 == c0 ? bary.y : 0.0) + (c2 == c0 ? bary.z : 0.0);
	float w1 = c1 == c0 ? 0.0 : bary.y + (c2 == c1 ? bary.z : 0.0);
	float w2 = (c2 == c0 || c2 == c1) ? 0.0 : bary.z;

	Mat m = sample_mat(c0, p, nw, bw, macro);
	if ((w1 > 0.01 || w2 > 0.01) && dist < 90.0) {
		// Height-based blend: material with the taller texture wins at the transition.
		Mat m1 = m;
		Mat m2 = m;
		if (w1 > 0.01) m1 = sample_mat(c1, p, nw, bw, macro);
		if (w2 > 0.01) m2 = sample_mat(c2, p, nw, bw, macro);
		float h0 = m.height + w0 * 1.5;
		float h1 = w1 > 0.01 ? m1.height + w1 * 1.5 : -10.0;
		float h2 = w2 > 0.01 ? m2.height + w2 * 1.5 : -10.0;
		float top = max(h0, max(h1, h2)) - 0.3;
		float b0 = max(h0 - top, 0.0);
		float b1 = max(h1 - top, 0.0);
		float b2 = max(h2 - top, 0.0);
		float bs = b0 + b1 + b2;
		b0 /= bs; b1 /= bs; b2 /= bs;
		m.albedo = m.albedo * b0 + m1.albedo * b1 + m2.albedo * b2;
		m.n = normalize(m.n * b0 + m1.n * b1 + m2.n * b2);
		m.rough = m.rough * b0 + m1.rough * b1 + m2.rough * b2;
		m.emit = m.emit * b0 + m1.emit * b1 + m2.emit * b2;
		m.metal = m.metal * b0 + m1.metal * b1 + m2.metal * b2;
		m.height = m.height * b0 + m1.height * b1 + m2.height * b2;
		m.cls = b1 > b0 && b1 > b2 ? m1.cls : (b2 > b0 ? m2.cls : m.cls);
	}

	// Weather: fresh snow settles on up-facing ground; rain darkens and glosses,
	// and pools in the low parts of the surface texture.
	float open_sky = smoothstep(0.6, 0.95, v_sky);
	float up = smoothstep(0.55, 0.9, m.n.y);
	float snow = clamp(snow_cover * 1.4 - (1.0 - up) - (m.height - 0.5) * 0.4, 0.0, 1.0) * open_sky;
	if (snow > 0.01) {
		vec3 sn;
		float sr;
		vec4 s = tri(snow_layer, 0.3, p, nw, bw, sn, sr);
		m.albedo = mix(m.albedo, s.rgb, snow);
		m.n = normalize(mix(m.n, sn, snow));
		m.rough = mix(m.rough, sr, snow);
	}
	float wet = wetness * open_sky * (0.45 + 0.55 * up);
	float puddle = smoothstep(0.42, 0.3, m.height) * up * smoothstep(0.35, 0.8, wetness) * open_sky;
	m.albedo *= 1.0 - wet * 0.38 - puddle * 0.2;
	m.rough = mix(m.rough, 0.12, wet * 0.7);
	m.rough = mix(m.rough, 0.02, puddle);
	m.n = normalize(mix(m.n, nw, puddle * 0.9));

	ALBEDO = m.albedo;
	NORMAL = normalize((VIEW_MATRIX * vec4(m.n, 0.0)).xyz);
	METALLIC = m.metal;
	SPECULAR = 0.4;
	EMISSION = m.emit;
	int cls = int(m.cls + 0.5);
	if (dot(m.emit, vec3(0.333)) > 0.6) cls = ASCII_EMISSIVE;
	ROUGHNESS = ascii_roughness(m.rough, cls);
	// Skylight only dims ambient light, so torches still light caves fully.
	AO = COLOR.a * mix(1.0, v_sky, cave_darkness);
	AO_LIGHT_AFFECT = 0.0;
}
