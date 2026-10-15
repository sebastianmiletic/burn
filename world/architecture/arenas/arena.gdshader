shader_type spatial;
render_mode cull_back;
// Boss-arena architecture (ArenaKit meshes). One material per arena; every
// vertex picks its surface:
//   UV     texture coordinates (metres * layer scale), V grows downwards on walls
//   UV2.x  material code: 0..23 texture layer (mesh UVs), 50..73 the layer
//          triplanar in world space, 100 iron, 101 cloth, 102 glow, 103 gold,
//          104 still black liquid, 105 bone
//   UV2.y  emission strength (COLOR.rgb is then the emission colour)
//   COLOR  rgb tint, a baked ambient occlusion
// Textures are the shared terrain PBR arrays (TerrainTextures): albedo rgb,
// normal xy + roughness z + height w. Normal maps use a derivative cotangent
// frame, so meshes need no tangents.

#include "res://rendering/materials/ascii_material.gdshaderinc"
#include "res://rendering/materials/noise.gdshaderinc"

global uniform float wetness;
global uniform float snow_cover;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float frost : hint_range(0.0, 1.0) = 0.0;     // hoarfrost on up-facing surfaces
uniform float soot : hint_range(0.0, 1.0) = 0.0;      // scorch patches
uniform float moss : hint_range(0.0, 1.0) = 0.0;      // moss on up-facing surfaces
uniform float ambient : hint_range(0.0, 1.0) = 1.0;   // sky ambient (underground < 1)
uniform float outdoor = 0.0;                          // 1: follows rain wetness and snow
uniform float grime = 0.35;                           // large-scale dirt variation
uniform vec3 grime_color : source_color = vec3(0.32, 0.29, 0.25);
uniform vec3 frost_color : source_color = vec3(0.82, 0.9, 1.0);
uniform float glow_pulse = 0.0;                       // animated glow surfaces (lava, souls)

varying vec3 v_world;
varying vec3 v_wn;
varying flat float v_code;
varying flat float v_emit;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_code = UV2.x;
	v_emit = UV2.y;
}

// Cotangent frame from screen-space derivatives (Schueler).
mat3 cotangent_frame(vec3 n, vec3 p, vec2 uv) {
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
	return mat3(t * invmax, b * invmax, n);
}

vec4 tri_sample(float layer, float scale, vec3 p, vec3 nw, out vec3 n_out, out float rough) {
	vec3 bw = pow(abs(nw), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 alb = vec4(0.0);
	vec3 nsum = vec3(0.0);
	rough = 0.0;
	if (bw.x > 0.02) {
		float s = sign(nw.x);
		vec2 uv = vec2(p.z * s, -p.y) * scale;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(normal_tex, vec3(uv, layer));
		vec2 tn = t.xy * 2.0 - 1.0;
		nsum += vec3(nw.x, nw.y + tn.y, nw.z + tn.x * s) * bw.x;
		alb += vec4(a.rgb, t.a) * bw.x;
		rough += t.z * bw.x;
	}
	if (bw.y > 0.02) {
		vec2 uv = p.xz * scale;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(normal_tex, vec3(uv, layer));
		vec2 tn = t.xy * 2.0 - 1.0;
		nsum += vec3(nw.x + tn.x, nw.y, nw.z - tn.y) * bw.y;
		alb += vec4(a.rgb, t.a) * bw.y;
		rough += t.z * bw.y;
	}
	if (bw.z > 0.02) {
		float s = sign(nw.z);
		vec2 uv = vec2(-p.x * s, -p.y) * scale;
		vec4 a = texture(albedo_tex, vec3(uv, layer));
		vec4 t = texture(normal_tex, vec3(uv, layer));
		vec2 tn = t.xy * 2.0 - 1.0;
		nsum += vec3(nw.x - tn.x * s, nw.y + tn.y, nw.z) * bw.z;
		alb += vec4(a.rgb, t.a) * bw.z;
		rough += t.z * bw.z;
	}
	float wsum = (bw.x > 0.02 ? bw.x : 0.0) + (bw.y > 0.02 ? bw.y : 0.0) + (bw.z > 0.02 ? bw.z : 0.0);
	n_out = normalize(nsum);
	rough /= max(wsum, 1e-4);
	return alb / max(wsum, 1e-4);
}

void fragment() {
	vec3 p = v_world;
	vec3 n = normalize(v_wn);
	float code = v_code;
	vec3 col;
	vec3 wn = n;
	float rough = 0.8;
	float metal = 0.0;
	float height = 0.5;
	float spec = 0.45;
	int ascii = ASCII_SOLID;
	vec3 emission = vec3(0.0);
	float big = n_fbm3(p * 0.07);
	if (code < 49.5) {
		vec4 a = texture(albedo_tex, vec3(UV, code));
		vec4 t = texture(normal_tex, vec3(UV, code));
		vec2 tn = t.xy * 2.0 - 1.0;
		mat3 tbn = cotangent_frame(n, p, UV);
		wn = normalize(n + tbn[0] * tn.x - tbn[1] * tn.y);
		col = a.rgb;
		rough = t.z;
		height = t.a;
		if (code > 16.5 && code < 18.5) {
			ascii = ASCII_SOLID;  // wood keeps the solid glyphs
		}
		if (code > 21.5 && code < 22.5) {
			ascii = ASCII_CLOTH;
		}
	} else if (code < 99.5) {
		vec4 a = tri_sample(code - 50.0, UV.x, p, n, wn, rough);
		col = a.rgb;
		height = a.a;
	} else if (code < 100.5) {
		// Wrought iron: dark, slightly blotchy, rust in the cavities.
		float rust = smoothstep(0.45, 0.8, n_fbm3(p * 3.1) + (1.0 - COLOR.a) * 0.4);
		col = mix(vec3(0.16, 0.16, 0.17), vec3(0.3, 0.16, 0.08), rust * 0.75);
		metal = mix(0.85, 0.2, rust);
		rough = mix(0.42, 0.85, rust) + n_value3(p * 25.0) * 0.08;
		wn = normalize(n + (vec3(n_value3(p * 40.0), n_value3(p * 40.0 + 7.1), n_value3(p * 40.0 + 3.7)) - 0.5) * 0.12);
		spec = 0.5;
	} else if (code < 101.5) {
		// Woven cloth (banners, rags).
		float weave = sin(UV.x * 380.0) * sin(UV.y * 380.0);
		col = COLOR.rgb * (0.85 + weave * 0.06 + (n_fbm2(UV * 9.0) - 0.5) * 0.3);
		rough = 0.95;
		ascii = ASCII_CLOTH;
		spec = 0.25;
	} else if (code < 102.5) {
		// Glow surfaces: lava, soul fire, runes. Dark crust, bright cracks.
		float flow = n_fbm3(p * 0.9 + vec3(0.0, -TIME * 0.35, TIME * 0.2) * glow_pulse);
		float cracks = smoothstep(0.35, 0.7, flow);
		col = vec3(0.05, 0.04, 0.04);
		emission = COLOR.rgb * v_emit * mix(0.35, 1.25, cracks);
		rough = 0.6;
		ascii = ASCII_EMISSIVE;
	} else if (code < 103.5) {
		// Old gold / bronze.
		float tarnish = n_fbm3(p * 2.3);
		col = mix(vec3(0.85, 0.62, 0.25), vec3(0.35, 0.3, 0.18), smoothstep(0.4, 0.8, tarnish + (1.0 - COLOR.a) * 0.5));
		metal = 0.95;
		rough = 0.3 + tarnish * 0.3;
		spec = 0.5;
	} else if (code < 104.5) {
		// Still black water / tar.
		col = vec3(0.015, 0.018, 0.016);
		rough = 0.04;
		spec = 0.6;
		wn = normalize(n + vec3(sin(p.x * 3.0 + TIME * 0.7), 0.0, cos(p.z * 2.7 - TIME * 0.6)) * 0.01);
		ascii = ASCII_LIQUID;
	} else {
		// Bone: limestone texture, warm and smooth.
		vec4 a = tri_sample(15.0, UV.x, p, n, wn, rough);
		col = mix(a.rgb, vec3(0.86, 0.8, 0.66), 0.55);
		rough = 0.55 + a.a * 0.2;
		height = a.a;
	}
	if (code < 99.5 || code > 104.5) {
		col *= COLOR.rgb;
		// Large-scale grime so long walls don't look printed.
		col = mix(col, col * grime_color * 2.2, grime * smoothstep(0.35, 0.75, big) * 0.6);
		// Moss and frost settle on up-facing surfaces, deeper in the cavities.
		float up = clamp(wn.y, 0.0, 1.0);
		if (moss > 0.0) {
			float m = smoothstep(0.55, 0.95, up + (n_fbm3(p * 0.6) - 0.5) * 0.9 + (0.5 - height) * 0.6) * moss;
			vec4 ma = texture(albedo_tex, vec3(p.xz * 0.45, 16.0));
			col = mix(col, ma.rgb * vec3(0.8, 0.95, 0.7), m);
			rough = mix(rough, 0.95, m);
		}
		if (soot > 0.0) {
			float s = smoothstep(0.4, 0.75, n_fbm3(p * 0.35 + 11.0)) * soot;
			col *= 1.0 - s * 0.75;
		}
		float f = frost + outdoor * snow_cover * 0.8;
		if (f > 0.0) {
			float fm = smoothstep(0.25, 0.85, up * 0.8 + (n_fbm3(p * 1.7) - 0.4) * 0.8 + (0.5 - height) * 0.5) * f;
			col = mix(col, frost_color, fm);
			rough = mix(rough, 0.35, fm);
			spec = mix(spec, 0.7, fm);
		}
	}
	float wet = outdoor * wetness * (0.35 + 0.65 * clamp(wn.y, 0.0, 1.0));
	col *= 1.0 - wet * 0.35;
	rough = mix(rough, 0.12, wet * 0.6);
	if (v_emit > 0.0 && (code < 101.5 || code > 102.5)) {
		// Emissive inlays on textured surfaces glow in their grooves.
		emission = COLOR.rgb * v_emit * (0.6 + 0.4 * smoothstep(0.6, 0.2, height));
		col = col * 0.25;
	}
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	METALLIC = metal;
	SPECULAR = spec;
	ROUGHNESS = ascii_roughness(clamp(rough, 0.04, 1.0), emission != vec3(0.0) ? ASCII_EMISSIVE : ascii);
	EMISSION = emission;
	AO = (code > 101.5 && code < 102.5 ? 1.0 : COLOR.a) * ambient;
	AO_LIGHT_AFFECT = 0.0;
}
